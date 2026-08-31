# Porting a complete Rachel client

This guide describes the work required to ship Rachel on another machine. It
is deliberately broader than [CLIENT_GUIDE.md](CLIENT_GUIDE.md), which covers a
small online renderer. A complete port may include offline play, a local rules
kernel, AI, save/resume, reconnect recovery, packaging and real-hardware proof.

The VIC-20 client is the constrained reference case: one 8K-expanded PRG now
contains solo play and RUBP online play, while retaining deterministic fixtures
and complete PAL/NTSC emulator matches. Its implementation is a model, not a
second specification. When code and prose disagree, the RachelEngine fixtures
and the versioned documents in `specs/` are authoritative.

## 1. Define the product before choosing an architecture

Write down which of these the first release promises:

| Capability | Minimum implementation |
|---|---|
| Online renderer | RUBP codec, transport, public state, private hand, input |
| Robust online play | Sync request, state hash, reconnect token, seat reclaim |
| Offline solo | RachelKernel-compatible rules, deterministic deal, local AI |
| Offline multiplayer | More seats, local turn handoff and hidden-hand UX |
| Save/resume | Stable state image **and** a tested storage device/path |
| Full product | Menus, controls, sound, packaging, evidence and support claims |

Do not implement a local rules engine merely to validate online moves. The Go
server is authoritative online. On a very small system, a render-only client is
often the honest first release. Conversely, do not call a title “solo” if it
quietly requires a server.

Classify the machine using
[rachel-target-tiers-v1.md](specs/rachel-target-tiers-v1.md). A registered
platform ID identifies a machine; it is not evidence that a client, transport
adapter or maintainership commitment exists.

## 2. Survey the whole machine

Rules-state RAM is only one budget. Record all of these before coding:

- CPU type, clock variants and interrupt behavior
- installed and realistically common RAM configurations
- executable/code ceiling and loader format
- screen, colour/attribute, character-set and sprite memory
- hardware stack and worst-case call/interrupt depth
- input devices, key rollover and joystick electrical sharing
- sound hardware and whether delays block network polling
- real storage devices users possess
- real network adapters users possess, their voltage levels and firmware
- emulator support for those exact peripherals
- assembler, linker, image builder and CI availability
- PAL/NTSC or other regional clocks and display geometries

Budget production, test-only fixtures and packaging separately. A test image
can cross a bank or expansion boundary even when production still fits. Verify
the resulting load address and final byte, not just the file size.

For mutually exclusive online and offline modes, overlaying buffers can be a
major saving. Freeze the lifetime rule explicitly: after transport memory
becomes a kernel workspace, no network routine may run until a full mode reset.

## 3. Choose the rules boundary

There are three sensible shapes:

1. **Server-authoritative renderer.** No resident rules kernel.
2. **Host-language engine.** Suitable when the platform has comfortable RAM.
3. **RachelKernel-style interpreter.** Suitable for assembly and constrained
   targets; the host owns UI, transport and storage while the kernel owns legal
   actions and deterministic transitions.

Available workspace profiles are defined in
[rachel-workspace-v1.md](specs/rachel-workspace-v1.md):

- reference packed: 192 bytes resident + 16 scratch
- constrained two-player: 144 + 16
- compact constrained two-player: 80 + 16

The 80-byte profile is not “free Rachel.” It assumes two players, packed 6-bit
deck ordinals, 14 bytes of hand masks, a single finish slot and careful reuse of
the packed deck/discard area. The UI, hand cache, protocol frames and program
still need memory.

Prefer `GET_ACTION_COUNT` + `GET_ACTION_AT` on small machines. A full `RKAT`
action table can require 806 contiguous bytes. The kernel must remain the sole
legality authority; UI and AI should select an enumerated action rather than
reimplementing rules independently.

If a target exposes a reduced kernel command subset, its `RHKI` capability
flags and buffer sizes must describe what it actually implements. Do not copy
the reference flags while omitting action tables or apply summaries.

## 4. Port in an evidence-first order

The most reliable sequence is:

1. Prove the loader actually enters machine code.
2. Encode and decode static RUBP conformance vectors.
3. Validate card encoding, endianness, CRC and exact 64-byte framing.
4. Load canonical state and expose public/private summaries.
5. Enumerate every indexed legal action in canonical order.
6. Prove invalid actions cannot mutate a single state byte.
7. Apply canonical transition fixtures.
8. Match deterministic PRNG, shuffle, deal and recycling vectors.
9. Round-trip the compact state image byte-for-byte.
10. Build a minimal UI over fixture state.
11. Complete a server-free match if solo is in scope.
12. Complete a real client-to-Go-server match.
13. Test reconnect, long games, regional variants and packaging.
14. Only then make a physical-hardware support claim.

A screenshot proves rendering, not game execution. A host-side codec test does
not prove the assembled target codec. Prefer exported result bytes, memory
queries, terminal server events and deterministic screenshots from the actual
target binary.

## 5. Rules edge cases a port must preserve

### Cards and action ordering

- Card suit occupies bits 7–6 and rank the defined low bits; use the fixture,
  not a remembered enum layout.
- Hands can grow to all 52 cards. A 32-byte cache is not a safe maximum.
- Multi-card plays contain cards of one rank, but suit combinations and Ace
  nominations expand into distinct indexed actions.
- Portable action order is by canonical card identity, not insertion order in
  a host array or order cards happened to be dealt.
- An Ace play must carry a valid nominated suit. “No nomination” is not a fifth
  suit.
- If the product UI offers one-card-at-a-time play, that is an input policy;
  the kernel and online codec must still understand legal stacked actions.

### Effects and turn movement

- Twos accumulate draws; sevens accumulate skips.
- Black Jacks start/extend their attack and red Jacks counter according to the
  canonical transition order. Colour is derived from suit, not display colour.
- Queens reverse direction. Two-player direction/skip behavior is especially
  easy to implement as a four-player mental model and get wrong.
- Effect order for a stack must follow the canonical action ordering, including
  which card becomes the visible top and which effect is the leader.
- A nomination remains active only for the specified state transition window.
- Finishing, current-player advancement and pending attacks interact. Never
  remove a player from arrays in a way that renumbers protocol seats.
- “First out,” finish order, sole remaining card-holder and a protocol payload
  named `winnerIndex` are not interchangeable concepts. Render the semantics
  defined by the current payload/fixture rather than guessing from the name.

### Deck, discard and determinism

- Seed zero is normalized to the canonical nonzero seed.
- The PRNG width, shifts, overflow and modulo operation must match exactly.
- Fisher–Yates consumes one PRNG output for each defined swap, including cases
  whose selected index equals the current index.
- The top discard is never shuffled back into the deck.
- Buried discards retain chronological order before deterministic recycling.
  Membership alone is insufficient because shuffle input order affects the
  next deck and replay.
- A play containing several cards archives the previous top and intermediate
  played cards in the canonical order, leaving only the final top visible.
- A legal game can run for a very long time—or indefinitely—because recycling
  reintroduces cards. Soak tests need a finite turn bound and must report
  “bounded without winner” separately from an engine hang or invalid state.

### State and persistence

- Validate the complete image, version, lengths, player indexes, counts and
  checksum before the first live-workspace write.
- `RKSI` is the portable kernel image. A target-specific packed image may be
  useful internally, but give it a distinct magic/version and document the
  conversion boundary.
- A correct state serializer does not by itself provide save/resume. Disk,
  tape, flash, SD and server-hosted saves have different failure and memory
  behavior and must be tested on the storage path users will actually use.
- Host-only metadata such as names, AI personality and commentary does not
  belong in the stripped rules image unless a higher-level save container owns
  it.

## 6. RUBP and transport edge cases

- RUBP frames are exactly 64 bytes; TCP reads and serial packets are not.
  Accumulate partial reads and split coalesced reads.
- Resynchronize on the `RACH` magic after modem status text or corruption, then
  validate version and CRC before dispatch.
- All multi-byte wire values use network byte order. Most 6502/Z80 hosts must
  swap; 6809/68000 hosts still need to prove fixture bytes.
- Sequence numbers wrap. Use wrapping arithmetic and do not treat zero as an
  implicit reset unless the protocol says so.
- Public `GAME_STATE` and private `HAND_SYNC` have different visibility. Never
  infer the local hand from public counts.
- A turn notification does not guarantee the local cached state is current.
  Pull authoritative public/private state before acting when required.
- State hashes detect stale actions; they do not repair state. On rejection,
  request a fresh sync and clear pending UI state.
- Reconnect requires the opaque token, game ID and assigned seat. Re-sending a
  fresh HELLO without reclaim data can create a new participant.
- Do not assume one server write equals one serial receive call. Pace continuous
  frames for slow software UARTs, but keep that transport accommodation out of
  the rules protocol.
- ESP-AT `+IPD` headers may be fragmented around payload bytes. Hayes/Zimodem
  transparent mode must drain the complete `CONNECT\r\n` response first.
- A modem can acknowledge a baud-change command at the old rate while the
  client has already switched. Treat the first CRC-valid RUBP exchange as more
  authoritative than optional trailing status text.
- Use the canonical raw endpoint, currently TCP port 6502. Early scaffolds and
  old documents used other ports; do not cargo-cult them.

## 7. Hardware and timing edge cases

- Target a real adapter and document its connector, signals, firmware dialect,
  voltage regulation and level shifting. A fictional “generic ESP” is not a
  shippable hardware story.
- Never connect a bare 3.3 V module directly to 5 V logic without suitable
  regulation and translation.
- Keyboard matrices and joystick lines may share VIA/PIA/CIA pins. Restore data
  direction registers after atomic joystick sampling.
- Bit-banged serial must account for fixed instructions around delay loops, not
  just scale the loop counter by CPU-frequency percentage.
- PAL/NTSC and hardware revisions may alter both CPU cycles per bit and raster
  geometry. Detect or select the variant, maintain separate timing sets, and
  regression-test the previously supported one.
- Disable interrupts only for the timing-critical byte, not the whole game
  loop. Conversely, a supposedly harmless sound or screen delay can make the
  receiver miss a start bit.
- Screen RAM and colour/attribute RAM are independent on many machines. Clear
  both or old card colours can leak into later text.
- Emulator peripheral models must use the same physical-time assumptions as
  the emulated regional clock. A passing test against a PAL-timed virtual modem
  attached to an NTSC CPU is false confidence.

## 8. UI edge cases on small displays

- Provide paging or scrolling for a 52-card hand and clamp the cursor after
  every sync/draw/play.
- Make only enumerated actions submit-able. Disable or reject unavailable draw,
  play and nomination actions locally without corrupting selection state.
- Clear selections after authoritative state changes and rejected actions.
- Distinguish “your turn,” “waiting,” “finished but spectating” and terminal
  game-over states.
- Display all supported seats and two-digit counts. Test zero, 9, 10 and 52.
- Centre text using measured string length; hard-coded columns fail after copy
  changes and localization.
- Controls may differ by mode. If Space selects online but plays directly in
  solo, the help text must change too.
- Title/menu changes are protocol-test changes: automated scripts that formerly
  pressed any key must choose the new mode explicitly.

## 9. Release validation matrix

For every claimed machine/region/adapter combination, retain evidence for:

- production build and memory map
- loader entry and title screen
- protocol fixture conformance from the target codec
- complete offline game, if claimed
- multi-seed bounded soak with failure reason
- complete online game through the real Go server
- draw, play, stack, Ace nomination, finish and replay
- disconnect/reclaim and corrupt/stale-frame recovery
- maximum players and large-hand pagination
- keyboard and every supported controller
- sound while networking remains active
- regional clocks and display modes
- release archive contents and checksum
- physical hardware, wiring and firmware versions

Hosted CI may be unable to redistribute firmware ROMs. In that case CI should
still assemble the executable fixture and publish it, while a documented local
release command runs the ROM-backed emulator. Label the evidence honestly:
“build verified,” “emulator verified,” and “physical hardware verified” are
three different claims.

## 10. Definition of done

A complete port is ready for an experimental release when:

- its advertised feature set works without hidden dependencies
- canonical fixtures pass through target code
- every user input maps to a legal enumerated action
- deterministic matches and bounded soaks report no kernel failure
- a complete online match ends at the server's terminal event
- memory ceilings and overlay lifetimes are enforced in CI
- packaging contains controls, compatibility, wiring and evidence status
- unsupported regions, storage devices and adapters are explicitly named

It becomes hardware-supported only after the same artifact passes on the real
machine and peripherals named in the support claim.
