# Building a minimal Rachel online client

This is the shortest honest route to putting a vintage or constrained machine
into an online Rachel game.

The client described here is **server-authoritative and render-only**:

- the Go server owns rules, deck, shuffle and legal-action validation
- the client renders public state and its private hand
- the client sends the action its player selected
- the client does not provide offline solo play

For local rules, AI, save/resume, robust reconnect behavior, product packaging,
regional timing, physical support claims and the full edge-case catalogue, use
[Porting a complete Rachel client](COMPLETE_CLIENT_PORT.md).

## Do not copy the wire format from this guide

The byte contract lives only in [PROTOCOL.md](PROTOCOL.md), with versioned
behavior in [`specs/`](specs/) and golden messages in
[`specs/fixtures/`](specs/fixtures/).

Start by making the target's actual codec reproduce those fixture bytes. This
guide explains how to organize the machine around that codec; it does not
restate offsets, payloads, card bits or message IDs.

The canonical raw endpoint is TCP port **6502**. Modern TLS-capable clients may
use the separately published secure endpoint. Do not inherit ports from old
scaffolds.

## Minimum product

A minimal client must:

- load and reach a title/connect screen
- accept or provide a server address
- connect through a real transport available to that machine
- complete `HELLO` / `WELCOME` and retain its assigned identifiers
- receive the private initial hand
- render current turn, top discard, local hand and public card counts
- let the player choose play or draw
- encode actions exactly as RUBP specifies
- accept authoritative hand/state updates and errors
- show the terminal result

It need not know whether a move is legal. It may use fresh authoritative state
to avoid obviously stale input, but the server makes the decision.

## Suggested modules

```text
main          startup, connection and game state machine
protocol      RUBP encode, decode, CRC and dispatch
transport     adapter, serial framing and TCP connection
display       title, public table, discard and hand
input         cursor, selection, draw/play controls
state         identifiers, public summary and private hand
```

Those can be assembly files, C modules, BASIC sections or FORTH words. The
boundaries matter more than the language: protocol code should not know screen
layout, and display code should not parse modem status text.

## State machine

```text
INIT
  -> CONNECT
  -> send HELLO
  -> receive WELCOME
  -> wait for GAME_START
  -> PLAYING
       receive and validate frames
       update public/private state
       render
       if it is our turn, accept one action
       on rejection, discard pending UI state and resync
  -> GAME_OVER
```

Do not fall through from “socket connected” into gameplay. `WELCOME` assigns or
reclaims the seat; `GAME_START` carries private initial state. Preserve the
opaque reconnect token and assigned game ID even if reconnect is deferred from
the first release.

## Receiving authoritative state

RUBP uses fixed 64-byte frames, but TCP and serial adapters are streams:

- one read can contain less than one frame
- one read can contain several frames
- modem status or command framing may surround the data

Accumulate exactly one frame, synchronize on `RACH`, then validate version and
CRC before dispatch. Never render or mutate live state from a partially
validated frame.

**Synchronize on every frame, not just the first.** Reading a fixed 64 bytes
and trusting the stream to stay aligned works right up until it doesn't, and
then it never works again: a single byte lost or gained shifts every frame that
follows for the rest of the session. The host carries on talking correctly and
the client parses nothing, which reads like a dead link rather than a framing
fault. The C64 client shipped this way and its symptom was a receive buffer
holding `43 48 01 0f` — `RACH` short by two bytes, and no way back.
Rescanning for the magic costs nothing on a clean stream and recovers by
itself on a dirty one.

**Do not require the next frame to be the one you are waiting for.** During the
handshake a host may send an announcement or a player list before `WELCOME`;
nothing in the protocol promises otherwise. Skip frames you are not waiting for
and keep reading, bounded by a frame count so a silent host still fails. A
client that treats the first frame it sees as fatal if it is the wrong type has
made itself depend on message ordering the protocol never guaranteed.

**On a bit-banged link, hold the interrupt mask across a whole frame.** Masking
per byte leaves every inter-byte gap open. A 64-byte frame at 2400 baud takes
about a quarter of a second, which is fifteen or more jiffy interrupts, and one
arriving mid-start-bit corrupts the byte and — without magic resynchronization
— every frame after it.

Public and private state are separate:

- `GAME_STATE` describes the table and public hand counts
- `HAND_SYNC` describes only this client's authoritative hand
- `CARD_DRAWN` is private action feedback

Do not reconstruct a hand from public counts. If the client may have missed a
broadcast, send `SYNC_REQUEST` and wait for fresh public/private state before
acting. On `ERROR`, clear selection, show a concise reason where possible and
request authoritative state rather than retrying a stale action blindly.

### Acknowledge what you received, not what you were told

A client that advertises `CAP_SYNC_ACK` is not sent `TURN_START` until it
returns a `SYNC_REQUEST` whose `ObservedStateHash` matches. That is what stops
a slow serial client acting before the state it should act on has arrived, and
it only works if the acknowledgement means what the host assumes.

The trap is that the state hash appears in more than one message. `GAME_STATE`,
`HAND_SYNC` and `TURN_START` all carry it. If you keep one `state_hash`
variable, let each handler overwrite it, and send the acknowledgement when
`HAND_SYNC` arrives, then a discarded `GAME_STATE` is still acknowledged: you
return a perfectly current hash for a view you never received. The host takes
you at your word and releases `TURN_START`, and you act a turn behind.

It surfaces on whichever fields only one message carries. The top discard comes
from `GAME_STATE` alone, so it goes stale while the pending draw and skip
counts — which `TURN_START` also carries — stay correct. The result is a client
that knows an attack is live and counters against the wrong card.

**Record that you processed the message carrying the state you will act on, and
gate the acknowledgement on that flag.** When it is not set, send a plain
`SYNC_REQUEST` instead: the host answers by resending the public/private pair,
which costs a round trip rather than waiting out its timeout.

Do not treat this as an edge case. Frame loss is the ordinary condition of a
bit-banged UART on a machine that also has to draw a screen — the VIC-20 client
discards 37 to 74 frames in a game it completes cleanly, and hit this path
seven to nine times per ten-play game. The acknowledgement is the one place
where losing a frame is silent rather than self-correcting, because you have
told the host the opposite.

The general form is worth carrying into any handshake you add: an
acknowledgement must attest to the thing you are about to act on, not merely
that something arrived.

## Transport choices

Choose hardware that exists for the target and document the exact adapter,
connector, firmware and electrical requirements. “Generic ESP” is not a usable
support claim.

Common adapter dialects are:

| Dialect | Connection | Data mode |
|---|---|---|
| ESP-AT | `AT+CIPSTART="TCP","host",6502` | `+IPD` inbound, `CIPSEND` outbound |
| Hayes/Zimodem | `ATDThost:6502` | transparent bytes after `CONNECT` |
| Native TCP API | platform-specific open call | direct stream |

ESP-AT headers and payloads may arrive fragmented. In transparent Hayes mode,
drain the complete `CONNECT\r\n` response—including the final line feed—before
treating bytes as RUBP.

The target transport interface only needs:

```text
init
connect(host, 6502)
send(64-byte frame)
poll/receive bytes
close
```

For bit-banged serial, account for regional CPU clocks, fixed instructions
around delay loops and interrupt latency. Keep sound and display delays from
blocking receive polling. The complete-port guide contains the larger hardware
and timing checklist.

Never connect a bare 3.3 V WiFi module directly to 5 V logic or power. Use the
real adapter's regulation and level translation.

## Minimum display and input

Display:

- current player/turn
- top discard
- local hand, with paging or scrolling
- public card count for every supported seat
- cursor/selection
- waiting, rejected, finished and terminal states

Input:

- move through the entire hand
- select the intended card or stack
- choose a suit when playing an Ace
- submit play
- submit draw
- leave or return to menu

A hand can contain all 52 cards. Test page boundaries and clamp the cursor after
every authoritative hand update. If the minimal UI supports only one-card
plays, say so; the online codec must still safely decode legal stacked state and
server responses.

## Implementation order

1. Prove the loader enters the program.
2. Match static encode/decode/CRC fixtures through target code.
3. Render a fixture state without networking.
4. Exercise all input and hand-page boundaries locally.
5. Connect to the Go server and complete `HELLO` / `WELCOME`.
6. Receive and render a private deal plus public state.
7. Complete one draw.
8. Complete one play and one Ace nomination.
9. Handle a rejected/stale action by resynchronizing.
10. Reach the server's terminal game event.

Do not begin with a full match and debug bytes, transport, state and UI at the
same time.

## Minimum verification

- production binary builds with an enforced memory ceiling
- target codec matches shared golden frames
- bad magic/version/CRC cannot mutate state
- partial and coalesced transport reads assemble correctly
- hand paging reaches indexes 0 through 51
- draw, play and Ace nomination reach the server
- server rejection clears pending input and triggers recovery
- a complete deterministic client/server match terminates
- packaging names the required machine configuration and real adapter

An emulator screenshot is rendering evidence, not protocol evidence. Prefer a
terminal server event, target memory observations and retained transport logs.
Physical support still requires the released artifact on the named machine and
adapter.

## Useful references

- [RUBP specification](PROTOCOL.md)
- [Complete client port guide](COMPLETE_CLIENT_PORT.md)
- [Hardware evidence levels and report template](HARDWARE_TESTING.md)
- [Handshake contract](specs/rachel-handshake-v1.md)
- [Sync/recovery contract](specs/rachel-sync-v1.md)
- [Transport endpoint fixture](specs/rubp-transport-v1.json)
- [Vintage target tiers](specs/rachel-target-tiers-v1.md)
- [Public client/port catalogue](https://rachel.stevehill.xyz/ports)

If a fixture, specification and implementation disagree, report it in this
repository with the exact bytes and versions. Do not solve the disagreement by
adding another local copy of the contract.
