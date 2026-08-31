# RUBP Protocol Specification

**Rachel Unified Binary Protocol** — Cross-platform multiplayer protocol for Rachel card game.

Designed for compatibility with vintage computers (ZX Spectrum, C64, Amiga) as well as modern platforms.

This document is the cross-platform source of truth, reconciled against the
`RachelEngine` reference implementation in `rachel-ios`. When the wire format
and the reference code disagree, the reference code wins and this document is a
bug. See [Changelog](#changelog) for what changed against the original v1.0
draft.

## Design Constraints

- Fixed 64-byte messages (no variable-length parsing)
- Parseable in Z80/6502/68000 assembly with minimal code
- Big-endian byte order (network standard)
- Implementable with <2KB of protocol handling code on 8-bit systems
- Two to eight players, identified by stable seat indexes `0` through `7`

Eight is a protocol limit, not merely a host default. The public state reserves
eight card counts and finish positions, and represents eliminated seats in one
eight-bit mask. A host must reject a ninth admission rather than truncate a
player list or start a game whose state cannot be represented on every client.

### Clients render, the host decides

The host owns the deck, the rules and the shuffle. A client renders what it is
told and sends back what its player pressed. **A client is not expected to
implement the rules**, and doing so is not what conformance means — the
conformance harness in each client repository tests messages, not rules.

This is what makes *same rules everywhere* true rather than merely claimed.
Sixteen independent reimplementations of stacking, compulsory counters and
red-jack defence would each have to agree exactly with `RachelEngine` or a
cross-machine game desyncs — a divergence no test suite can catch, because it
only appears in a live game between two particular machines. One authoritative
engine and many renderers makes divergence impossible by construction.

Message design follows from this. `PLAYER_WON` carries per-seat attack totals
precisely so a client can show end-of-game awards without replicating rules
logic; new messages should be built the same way. The host computes, the
payload carries, the client displays.

A platform **may** additionally implement the game locally in order to offer
solo play. iOS does, which is why the app needs no network to play alone. That
is a platform capability, not a protocol requirement: the vintage clients do
not have it, and a vintage machine with no host on the network has no game to
play.

### No hot-seat

Networked multiplayer is the only multiplayer mode: there is deliberately **no
hot-seat / pass-and-play**. A single shared screen would expose every player's
hand, so hidden-hand integrity requires one device per player, separated by the
network. This holds regardless of the above — it is a property of hidden hands,
not of where the rules run.

## RachelSpec Alignment

`RUBP` is the fixed-size binary transport for `RachelSpec`. It does not send the
JSON shapes used by `RachelVMTool`, but it carries the same meanings:

- `HELLO` and `WELCOME` negotiate the selected `specVersion`
- `PLAY_CARD` is the wire form of the RachelSpec action `{ "type": "play", ... }`
- `DRAW_CARD` is the wire form of the RachelSpec action `{ "type": "draw" }`
- `GAME_STATE` is the wire form of `PublicStateSummary`
- `HAND_SYNC` is the wire form of `PrivateHandSnapshot`
- `SYNC_REQUEST` carries the client's last authoritative `turnNumber`, `specVersion`, and optional `stateHash`
- `TURN_START`, `TURN_END`, and `PLAYER_WON` are public transition checkpoints derived from authoritative engine transitions
- `StateHash` fields always mean the rules-only RachelSpec state hash, excluding host-only metadata such as names and UUIDs

Where this document names stable identifiers such as `not_your_turn` or
`invalid_play`, those identifiers match the external contract used by
`RachelVMTool` and the checked-in VM fixtures.

Recovery semantics are frozen separately in:

- [specs/rachel-handshake-v1.md](specs/rachel-handshake-v1.md)
- [specs/rachel-sync-v1.md](specs/rachel-sync-v1.md)
- [specs/rachel-transitions-v1.md](specs/rachel-transitions-v1.md)

To prove an implementation against the reference, validate it with the golden
wire vectors in [specs/rubp-conformance-v1.md](specs/rubp-conformance-v1.md).

## Message Format

Every RUBP message is exactly 64 bytes:

```
┌─────────────────────────────────────────────────────────────────┐
│  HEADER (16 bytes)                                              │
├─────────────────────────────────────────────────────────────────┤
│  PAYLOAD (48 bytes)                                             │
└─────────────────────────────────────────────────────────────────┘
```

### Header Structure (16 bytes)

```
Offset  Size  Field         Description
0       4     Magic         "RACH" (0x52, 0x41, 0x43, 0x48)
4       1     Version       Transport version (0x01 legacy, 0x02 CRC)
5       1     Type          Message type (see below)
6       2     Sequence      Message sequence number (big-endian)
8       2     PlayerID      Sender player ID (0xFFFF for host)
10      2     GameID        Game identifier
12      4     v1 Timestamp  Unix timestamp or 0 (big-endian)
```

### RUBP v2 integrity header

RUBP v2 preserves the 16-byte header, 48-byte payload, and every payload
layout. Only header bytes 12-15 change:

```
Offset  Size  Field         Description
12      2     Timestamp16   Low 16 timestamp bits, or 0 (big-endian)
14      2     CRC16         CRC-16/CCITT-FALSE (big-endian)
```

The CRC parameters are `poly=0x1021`, `init=0xFFFF`, `refin=false`,
`refout=false`, `xorout=0x0000`; `"123456789"` produces `0x29B1`. Compute it
over all 64 bytes with bytes 14-15 set to zero. A receiver must reject a v2
frame whose CRC does not match before interpreting its type, identifiers,
payload, state hash, or game-over flag.

The transport version is negotiated by the client's HELLO header. A host that
successfully decodes a v1 HELLO replies to that connection in v1; a v2 HELLO
selects v2 for every reply on that connection. Selection is per connection, so
v1 and v2 clients may share a lobby. RachelSpec `specVersion` in message
payloads is independent of this transport version.

CRC detects corruption but does not itself recover a lost frame. A client
already holding an assigned identity uses `SYNC_REQUEST` to obtain a fresh
`GAME_STATE` and `HAND_SYNC`. Slow software-UART platforms should additionally
advertise or document their required inter-frame idle interval; the reference
server currently spaces VIC-20 frames by at least 70 ms.

### Message Types

| Type | Name | Direction | Description |
|------|------|-----------|-------------|
| 0x00 | HEARTBEAT | C↔H | Keep-alive |
| 0x01 | HELLO | C→H | Client connection request |
| 0x02 | WELCOME | H→C | Connection accepted |
| 0x03 | GAME_START | H→C | Game starting, initial hand |
| 0x04 | PLAY_CARD | C→H | Player plays card(s) |
| 0x05 | DRAW_CARD | C→H | Player draws |
| 0x06 | CARD_DRAWN | H→C | Cards drawn (private) |
| 0x07 | GAME_STATE | H→C | Current game state |
| 0x08 | TURN_START | H→C | Turn notification |
| 0x09 | TURN_END | H→C | Turn completed |
| 0x0A | PLAYER_WON | H→C | Game over |
| 0x0B | ERROR | H→C | Action rejected |
| 0x0C | PLAYER_LIST | H→C | Lobby player info |
| 0x0D | ANNOUNCE | H→C | Flavour text/broadcast |
| 0x0E | PLAYER_NAME | H→C | Individual player name |
| 0x0F | HAND_SYNC | H→C | Private authoritative hand sync |
| 0x10 | SYNC_REQUEST | C→H | Request authoritative resync |

---

## Card Encoding

A card is encoded in a single byte:

```
Bits 7-6: Suit (00=Hearts, 01=Diamonds, 10=Clubs, 11=Spades)
Bits 5-0: Rank (2-10, 11=Jack, 12=Queen, 13=King, 14=Ace)

Special values:
0x00: No card / empty slot
0xFF: Unknown card (e.g. an opponent's concealed hand)
0xFE: Joker (reserved for the Ultimate variant)
```

For suit nominations and matching (e.g. the `NominatedSuit` fields), suits use
the same two-bit ordering as the card encoding, widened to a byte:

```
0x00: Hearts   0x01: Diamonds   0x02: Clubs   0x03: Spades   0xFF: No nomination
```

### Examples

| Card | Binary | Hex |
|------|--------|-----|
| 2♥ | 00_000010 | 0x02 |
| A♥ | 00_001110 | 0x0E |
| K♦ | 01_001101 | 0x4D |
| J♣ | 10_001011 | 0x8B |
| Q♠ | 11_001100 | 0xCC |

### Decoding (Z80 Assembly)

```z80
; Input: A = encoded card
; Output: B = suit (0-3), C = rank (2-14)
decode_card:
    ld c, a
    and 0x3F        ; Mask rank bits
    ld c, a         ; C = rank
    ld a, b
    srl a
    srl a
    srl a
    srl a
    srl a
    srl a           ; A = suit (top 2 bits shifted down)
    ld b, a         ; B = suit
    ret
```

### Decoding (6502 Assembly)

```asm
; Input: A = encoded card
; Output: card_suit = suit (0-3), card_rank = rank (2-14)
decode_card:
    pha
    and #$3F        ; Mask rank bits
    sta card_rank
    pla
    lsr             ; Shift suit bits down
    lsr
    lsr
    lsr
    lsr
    lsr
    sta card_suit
    rts
```

---

## Payload Definitions

### HELLO (0x01) — Client → Host

```
Offset  Size  Field           Description
0       16    PlayerName      ASCII name, null-padded
16      2     PlatformID      Client platform (see below)
18      2     SpecVersion     RachelSpec version supported by client
20      8     ReconnectToken  Stable token for reclaiming a slot (0 = none)
28      20    Reserved        Zero-filled
```

The HELLO header `GameID` is `0` for a fresh join and the active game ID when reclaiming a disconnected slot.

Current canonical platform IDs implemented in this repo include. The shared
source of truth in code is `RUBPPlatformID` inside `RachelEngine`.

Important: inclusion in this registry means the protocol can identify the
machine class. It does **not** mean a supported client exists. The current
commitment policy lives in `docs/specs/rachel-target-tiers-v1.md`.

The intended policy is open protocol, narrow official support: machines that
can honestly implement the handshake, sync, and action contract should be able
to connect, even when the project is not promising a maintained native client.

- 0x0001: Apple II
- 0x0002: Commodore 64
- 0x0003: ZX Spectrum
- 0x0005: Amiga
- 0x000B: Atari 800
- 0x0030: Web Browser
- 0x0031: iOS
- 0x0032: Android
- 0x0033: Windows
- 0x0034: macOS
- 0x0035: Linux

The modern IDs above are the canonical ones to use for current and future
native clients. The earlier `0x0010`-style modern IDs are not used by the
current implementation.

#### Full platform registry

The table below is the cross-platform registry of identifiable machine
classes. The implemented subset is whatever `RUBPPlatformID` in `RachelEngine`
currently defines (40 cases at the time of writing); the remaining IDs are
reserved so any client can announce itself honestly without colliding.

```
0x0001: Apple II              0x0002: Commodore 64         0x0003: ZX Spectrum
0x0004: DOS                   0x0005: Amiga                0x0006: Atari ST
0x0007: BBC Micro             0x0008: MSX                  0x0009: Amstrad CPC
0x000A: TRS-80                0x000B: Atari 800            0x000C: VIC-20
0x000D: Mac Classic           0x000E: Windows 3.x          0x000F: Acorn Archimedes

0x0010: NES                   0x0011: Game Boy             0x0012: SNES
0x0013: Master System         0x0014: Genesis/Mega Drive   0x0015: Sega CD
0x0016: 32X                   0x0017: Game Gear            0x0018: Saturn
0x0019: Dreamcast             0x001A: PlayStation          0x001B: PlayStation 2
0x001C: PSP                   0x001D: PS Vita

0x0020: PalmOS                0x0021: Windows Mobile       0x0022: BlackBerry
0x0023: Newton

0x0030: Web Browser           0x0031: iOS                  0x0032: Android
0x0033: Windows (modern)      0x0034: macOS                0x0035: Linux

0x0040: TI Calculator         0x0041: HP Calculator        0x0042: Casio Calculator

0x0050: Arduino               0x0051: Raspberry Pi         0x0052: ESP32
0x0053: MiSTer FPGA

0x0060: Terminal/Telnet       0x0061: SSH                  0x0062: BBS

0x0070: SG-1000               0x0071: SC-3000              0x0072: Sega Pico
0x0073: Sega Nomad            0x0074: Sega Neptune (prototype!)

0x0080: PC Engine/TurboGrafx  0x0081: PC-FX                0x0082: Neo Geo AES
0x0083: Neo Geo Pocket        0x0084: 3DO                  0x0085: Jaguar
0x0086: Lynx                  0x0087: Wonderswan           0x0088: Virtual Boy
0x0089: Vectrex               0x008A: Intellivision        0x008B: ColecoVision
0x008C: Odyssey²              0x008D: Fairchild Channel F   0x008E: Bally Astrocade

0x0090: VAX/VMS Terminal      0x0091: PDP-11               0x0092: PLATO System
0x0093: Wang 2200             0x0094: Sinclair QL          0x0095: Enterprise 64/128
0x0096: Tandy Color Computer  0x0097: Commodore Plus/4     0x0098: Commodore 128
0x0099: Commodore PET         0x009A: Sharp MZ-80          0x009B: Sharp X68000
0x009C: NEC PC-88             0x009D: NEC PC-98            0x009E: FM Towns
0x009F: Oric-1/Atmos          0x00A0: Dragon 32/64         0x00A1: Jupiter ACE
0x00A2: SAM Coupé             0x00A3: Tatung Einstein      0x00A4: Memotech MTX
0x00A5: Camputers Lynx (the other one!)                    0x00A6: Acorn Electron

0x00D7: Atari 7800

0x00F0: Smart TV              0x00F1: Smart Fridge         0x00F2: Tesla
0x00F3: Smart Watch           0x00F4: Steam Deck           0x00F5: Analogue Pocket
0x00F6: Playdate              0x00F7: Kindle               0x00F8: ATM Machine
0x00F9: In-flight Entertainment System

0xFFFF: Unknown/Custom
```

### WELCOME (0x02) — Host → Client

```
Offset  Size  Field           Description
0       2     AssignedPlayerID  Player's ID for this game
2       2     GameID            Game identifier
4       1     PlayerCount       Total players in game
5       1     GameState         0=WAITING, 1=PLAYING, 2=FINISHED
6       2     SpecVersion       RachelSpec version selected by host
8       40    Reserved          Zero-filled
```

### GAME_START (0x03) — Host → Client (Private)

Sent individually to each player with their initial hand.

```
Offset  Size  Field       Description
0       1     CardCount   Number of cards dealt
1       32    Cards       Encoded cards (unused slots = 0x00)
33      15    Reserved    Zero-filled
```

### PLAY_CARD (0x04) — Client → Host

Wire form of the RachelSpec action `{ "type": "play", "cards": [...], "nominatedSuit": ... }`.

```
Offset  Size  Field         Description
0       1     CardCount     Number of cards played (1-4)
1       32    Cards         Encoded cards (unused slots = 0x00)
33      1     NominatedSuit Suit if playing Ace (0xFF = none)
34      2     SpecVersion   RachelSpec version assumed by client
36      1     Flags         Bit 0 = ObservedStateHash present
37      8     ObservedStateHash  Last authoritative host state hash seen by client
45      3     Reserved      Zero-filled
```

### DRAW_CARD (0x05) — Client → Host

Wire form of the RachelSpec action `{ "type": "draw" }`.

```
Offset  Size  Field     Description
0       1     Reason    0=CANNOT_PLAY, 1=ATTACK_PENALTY
1       1     Count     Number of cards to draw
2       2     SpecVersion RachelSpec version assumed by client
4       1     Flags     Bit 0 = ObservedStateHash present
5       8     ObservedStateHash  Last authoritative host state hash seen by client
13      35    Reserved  Zero-filled
```

### CARD_DRAWN (0x06) — Host → Client (Private)

Sent to the drawing player only.

```
Offset  Size  Field       Description
0       1     CardCount   Number of cards drawn
1       32    Cards       Encoded cards drawn
33      15    Reserved    Zero-filled
```

### GAME_STATE (0x07) — Host → Clients

Broadcast to sync public game state. This is the binary form of `PublicStateSummary`.

```
Offset  Size  Field             Description
0       1     CurrentPlayer     Current player index (0-7)
1       1     Direction         0=clockwise, 1=counter-clockwise
2       1     TopCard           Top discard pile card (encoded)
3       1     NominatedSuit     Active suit nomination (0xFF = none)
4       1     PendingDraws      Cards owed from attacks
5       1     PendingSkips      Skips pending
6       1     DeckCount         Cards remaining in deck
7       8     PlayerCardCounts  Card count per player (index = player)
15      1     IsGameOver        0=playing, 1=game over
16      1     WinnerIndex       Sole surviving player, i.e. the LOSER (0xFF while playing) - see "WinnerIndex is a misnomer"
17      4     TurnNumber        Current turn number (big-endian)
21      2     SpecVersion       RachelSpec version for this state
23      1     Flags             Bit 0 = StateHash present, Bit 1 = extended summary present
24      8     StateHash         64-bit RachelSpec rules-only state hash
32      1     DiscardCount      Cards currently in discard pile
33      1     PlayerOutMask     Bitmask of players marked out
34      8     FinishOrder       Finishing player indexes (0xFF = unused)
42      6     Reserved          Zero-filled
```

`StateHash` is the deterministic RachelSpec hash of the rules state only.
It excludes host metadata like display names and UUIDs, so it can be compared across native implementations.

The extended summary fields are public-only state. They intentionally do not expose hands or deck order.

For authoritative recovery, `GAME_STATE` must pair with `HAND_SYNC` from the
same host rules state. `specVersion`, `turnNumber`, and `stateHash` must match
between the two messages.

### TURN_START (0x08) — Host → Clients

Structured notification for the next active turn.

```
Offset  Size  Field             Description
0       1     PlayerIndex       Player whose turn is starting
1       4     TurnNumber        Current turn number (big-endian)
5       1     PendingDraws      Cards owed at start of turn
6       1     PendingSkips      Skips owed at start of turn
7       1     Flags             Bit 0 = StateHash present
8       2     SpecVersion       RachelSpec version for this state
10      8     StateHash         64-bit RachelSpec rules-only state hash
18      30    Reserved          Zero-filled
```

### TURN_END (0x09) — Host → Clients

Structured public summary of the action that just completed.

```
Offset  Size  Field             Description
0       1     PlayerIndex       Player who acted
1       1     ActionKind        0x01=PLAY, 0x02=DRAW
2       1     CardCount         Public cards included below
3       4     Cards             Up to 4 public cards (unused = 0x00)
7       1     NominatedSuit     Suit chosen by Ace play (0xFF = none)
8       1     DrawCount         Number of cards drawn if ActionKind=DRAW
9       1     NextPlayerIndex   Player whose turn follows
10      4     TurnNumber        Resulting turn number (big-endian)
14      1     FinishPosition    Finishing position if actor went out (0xFF = none)
15      1     WinnerIndex       Sole surviving player if the game ended this turn (0xFF = none) - see "WinnerIndex is a misnomer"
16      2     SpecVersion       RachelSpec version for this state
18      1     Flags             Bit 0 = StateHash present
19      8     StateHash         64-bit RachelSpec rules-only state hash
27      21    Reserved          Zero-filled
```

### PLAYER_WON (0x0A) — Host → Clients

Explicit game-over notification.

```
Offset  Size  Field             Description
0       1     WinnerIndex       Sole surviving player, i.e. the LOSER - see "WinnerIndex is a misnomer"
1       4     TurnNumber        Final turn number (big-endian)
5       2     SpecVersion       RachelSpec version for this state
7       1     Flags             Bit 0 = StateHash present, Bit 1 = AttackTotals present
8       8     StateHash         64-bit RachelSpec rules-only state hash
16      8     AttackDealt       Per-seat attack severity dealt, seats 0-7 (Flags bit 1)
24      8     AttackTaken       Per-seat attack severity received, seats 0-7 (Flags bit 1)
32      16    Reserved          Zero-filled
```

#### AttackTotals (Flags bit 1, additive)

Summed attack severity per seat across the whole game, using RachelSpec
attack severities: a 2 counts 2, a Black Jack 5, a 7 (skip) 1. `AttackDealt`
credits the attacker's seat; `AttackTaken` debits the seat the attack
resolved against. Each byte saturates at 255. Seats beyond the game's player
count are zero.

The wire carries raw totals only - award naming ("nastiest player" and the
like), tie-breaking, and presentation are client-side concerns. Hosts MAY
omit the totals (Flags bit 1 unset, bytes 16-31 zero); decoders MUST ignore
bytes 16-31 when the flag is unset. This is a flag-gated addition in
previously reserved bytes, same mechanism as StateHash: existing encoders,
golden vectors, and vintage decoders that ignore reserved bytes are
unaffected.

#### WinnerIndex is a misnomer: it names the survivor, who LOSES

Every `WinnerIndex` field in this protocol (GAME_STATE offset 16, TURN_END
offset 15, PLAYER_WON offset 0) carries the index of the **sole player still
holding cards** when the game ends. Under GAME_RULES.md that player finishes
**last**: Rachel is a shedding race, first out takes 1st place, and "the game
continues until only one player remains - that player finishes last."

The field name is historical and the byte layout is **frozen** - the golden
conformance vectors, rachel-server, and the vintage clients all encode these
bytes as-is, so the semantics are documented rather than changed. Both
reference derivations in the Swift engine make the survivor semantics
explicit: `GameEngine.winnerIndex(in:)` returns the first player with
`!isOut` (feeding TURN_END and PLAYER_WON via the `gameFinished` transition
event), and `SyncSnapshot.resolvedWinnerIndex` returns the single active
player (feeding GAME_STATE).

**Clients MUST NOT congratulate or credit `WinnerIndex`.** The rules winner -
the player to celebrate, and the one stats should credit - is the first
finisher: `FinishOrder[0]` in GAME_STATE (offset 34), or equivalently the
actor of the TURN_END whose `FinishPosition` is 0. The iOS client originally
celebrated `WinnerIndex` and congratulated the loser on every joined game
(fixed in rachel-ios 4cef442 by deriving the winner from FinishOrder);
treat `WinnerIndex` purely as "the game is over and this seat came last."

### PLAYER_LIST (0x0C) — Host → Clients

Sent to provide lobby player info with platform IDs.

```
Offset  Size  Field         Description
0       1     PlayerCount   Number of players in list
1-48    6*n   PlayerInfo[]  Array of player info (max 8)

PlayerInfo structure (6 bytes):
  Offset  Size  Field       Description
  0       1     PlayerID    Player index (0-7)
  1       2     PlatformID  Platform ID (big-endian)
  3       3     Reserved    Zero-filled
```

### ANNOUNCE (0x0D) — Host → Clients

Flavour text broadcast from server.

```
Offset  Size  Field       Description
0       47    Text        UTF-8 text, null-padded
47      1     Reserved    Zero
```

### PLAYER_NAME (0x0E) — Host → Clients

Sent once per player to communicate names (supports longer names than HELLO).

```
Offset  Size  Field       Description
0       1     PlayerIndex Player index (0-7)
1       47    PlayerName  UTF-8 name, null-padded
```

### HAND_SYNC (0x0F) — Host → Client (Private)

Sent privately to a player with their authoritative current hand.
Useful after optimistic local play, rejected actions, or future reconnect/resync flows.
This is the binary form of `PrivateHandSnapshot`.

```
Offset  Size  Field             Description
0       1     CardCount         Number of cards in authoritative hand
1       32    Cards             Encoded cards in authoritative hand
33      4     TurnNumber        Current turn number (big-endian)
37      2     SpecVersion       RachelSpec version for this hand view
39      1     Flags             Bit 0 = StateHash present
40      8     StateHash         64-bit RachelSpec rules-only state hash
```

`HAND_SYNC` is the private half of the authoritative recovery pair
`GAME_STATE + HAND_SYNC`. It should not be treated as an unrelated sync format.

### SYNC_REQUEST (0x10) — Client → Host

Sent by a client when it wants the host to resend the authoritative public/private sync pair.
Useful if the client detects that its local hand no longer matches the host's public summary.

```
Offset  Size  Field             Description
0       4     TurnNumber        Last turn number seen by the client (big-endian)
4       2     SpecVersion       RachelSpec version assumed by client
6       1     Flags             Bit 0 = ObservedStateHash present
7       8     ObservedStateHash Last authoritative host state hash seen by client
15      33    Reserved          Zero-filled
```

For `RachelSync v1`, a client should populate `SYNC_REQUEST` from the last
authoritative host metadata it has observed:

- `TurnNumber = PublicStateSummary.turnNumber`
- `SpecVersion = PublicStateSummary.specVersion`
- `ObservedStateHash = PublicStateSummary.stateHash` when available

### ERROR (0x0B) — Host → Client

```
Offset  Size  Field         Description
0       1     ErrorCode     See error codes below
1       1     CardCount     Cards involved (if applicable)
2       32    Cards         Rejected cards (if applicable)
34      14    Reserved      Zero-filled
```

**Error Codes:**

| Code | RUBP RejectReason | Stable Wire Identifier | Primary RachelSpec Identifier |
|------|-------------------|------------------------|-------------------------------|
| 0x01 | NOT_YOUR_TURN | `not_your_turn` | `not_your_turn` |
| 0x02 | INVALID_PLAY | `invalid_play` | `invalid_play` |
| 0x03 | CARDS_NOT_IN_HAND | `card_not_in_hand` | `card_not_in_hand` |
| 0x04 | CANNOT_DRAW | `cannot_draw` | usually `must_play_if_able` in the current host |
| 0x05 | GAME_NOT_STARTED | `game_not_started` | none; host/session state only |
| 0x06 | LOBBY_FULL | `lobby_full` | none; join-time rejection |
| 0x07 | GAME_IN_PROGRESS | `game_in_progress` | none; join-time rejection |
| 0x08 | NAME_TAKEN | `name_taken` | none; join-time rejection |
| 0xFF | UNKNOWN | `unknown` | none |

`ERROR` remains a wire-level reject summary. It is intentionally smaller and
coarser than the full RachelSpec error surface.

Codes 0x06-0x08 answer a HELLO that cannot be seated (no free slot, game
already running with no matching reservation, or the display name is taken by
a different device). CardCount is 0 for these. A joiner receiving one MUST
treat the join attempt as terminal rather than retrying: the condition will
not clear on its own. Hosts that predate these codes simply stayed silent, so
clients MUST still handle a rejection-less timeout.

---

## Byte Order

All multi-byte integers are **big-endian** (network byte order).

### Converting on Little-Endian Platforms

**Z80 (load big-endian 16-bit):**
```z80
; Load big-endian word from (HL) into DE
load_be16:
    ld d, (hl)      ; High byte first
    inc hl
    ld e, (hl)      ; Low byte second
    ret
```

**6502 (load big-endian 16-bit):**
```asm
; Load big-endian word from 'addr' into A (low) and X (high)
load_be16:
    ldx addr        ; High byte
    lda addr+1      ; Low byte
    rts
```

**68000 (native big-endian):**
No conversion needed.

---

## Transport Layer

### TCP (Recommended for Vintage)

- Port: 19840 (1984 + 0)
- Bonjour/mDNS service type: `_rachel._tcp`
- **TCP framing required** — TCP is a byte stream, use 64-byte message boundaries
- Unencrypted (TLS not viable for vintage hardware)
- IPv4 preferred (vintage WiFi bridges often IPv4-only)

#### TCP Connection Handshake

After TCP connect, both parties exchange transport-level HELLO messages before game traffic:

```
Client → Host:  HELLO (type 0x01) with display name in payload bytes 0-15
Host → Client:  HELLO (type 0x01) with display name in payload bytes 0-15
                (connection established, game-layer messages can flow)
```

If HELLO is not received within 5 seconds, the connection is closed.

Once the TCP transport is established, the normal game-layer initial sync still begins with the client sending a HELLO to claim or reclaim a player slot.

#### Display Name Requirements

Display names in HELLO messages are sanitized for vintage computer compatibility:
- ASCII printable characters only (32-126)
- Maximum 15 characters (null-padded in the HELLO payload)
- Emoji and extended Unicode stripped at the protocol boundary
- UI may show fuller names locally; `PLAYER_NAME` messages carry richer display names after join

### Local Network Discovery

Hosts advertise via mDNS:
```
Service Type: _rachel._tcp
Service Name: <user-chosen game name>
Port: 19840
```

ESP8266/ESP32 WiFi bridges support mDNS, enabling vintage machine discovery.

### MultipeerConnectivity (iOS/macOS)

Same 64-byte messages sent via MC framework.

### GameKit (Apple Platforms)

Same 64-byte messages sent via GKMatch.

---

## State Synchronisation

### Initial Sync

1. Transport becomes ready
2. Client sends HELLO with player name, spec version, and reconnect token
3. Host assigns or reclaims a slot based on HELLO
4. Host sends WELCOME (includes GameID and current game state)
5. Host sends PLAYER_NAME for each player
6. If this is a fresh lobby join, normal game start later sends GAME_START and HAND_SYNC
7. If this is a reconnect into an active or finished game, host immediately sends GAME_STATE and HAND_SYNC

Fresh join before game start:
- WELCOME
- PLAYER_NAME x N
- later, at game start: GAME_START + HAND_SYNC + GAME_STATE

Reconnect during or after a game:
- WELCOME
- PLAYER_NAME x N
- GAME_STATE
- HAND_SYNC

### Gameplay Sync

For each action:
1. Player sends PLAY_CARD or DRAW_CARD
2. Host validates action
3. If valid: Host may send CARD_DRAWN to that player (private, draw only)
4. If valid: Host sends HAND_SYNC to that player (private)
5. If valid: Host broadcasts TURN_END / GAME_STATE / TURN_START
6. If invalid: Host sends ERROR and HAND_SYNC to that player

### Explicit Resync

1. Client detects drift, or otherwise wants a fresh authoritative view
2. Client sends SYNC_REQUEST with its last seen turn/hash metadata
3. Host responds to that peer with GAME_STATE and HAND_SYNC

The response pair must come from the same authoritative rules state:

- same `specVersion`
- same `turnNumber`
- same `stateHash`
- `playerCardCounts[playerIndex] == HAND_SYNC.CardCount`

### Deterministic Local Computation

Vintage clients may compute state locally from seed + actions to reduce bandwidth:

1. Host sends random seed in initial sync
2. Clients track all PLAY_CARD/DRAW_CARD broadcasts
3. Clients apply actions locally using identical engine logic
4. GAME_STATE broadcasts serve as checkpoints/verification

**Requires deterministic engine:** Same seed + same actions = same state.

---

## Timing Considerations

At 9600 baud (vintage serial):
- 64 bytes ≈ 67ms transmission time
- Acceptable for turn-based gameplay
- Host should not flood messages; wait for acknowledgment if needed

**Recommended intervals:**
- HEARTBEAT: every 10 seconds
- Turn timeout: 60+ seconds
- Reconnection grace period: 30 seconds

---

## Security Notes

This protocol has minimal security (vintage machines cannot handle crypto).

**Mitigations:**
1. Host validates all actions
2. Private data (hands) sent only to owning player
3. Sequence numbers detect replay/reorder
4. For trusted networks only (local/family play)

**Do not use for money games.**

---

## Implementation Checklist

### Host Implementation
- [ ] Listen on port 19840
- [ ] Advertise via mDNS
- [ ] Handle HELLO → assign/reclaim slot → send WELCOME
- [ ] Broadcast PLAYER_LIST on join
- [ ] Send GAME_START (private) on game begin
- [ ] Send HAND_SYNC (private) after authoritative hand changes
- [ ] Validate PLAY_CARD/DRAW_CARD
- [ ] Broadcast GAME_STATE after valid action
- [ ] Send CARD_DRAWN (private) on draw
- [ ] Send ERROR on invalid action
- [ ] Reserve reconnectable slots on disconnect
- [ ] Handle disconnection gracefully

### Client Implementation
- [ ] Discover hosts via mDNS (or manual IP)
- [ ] Send HELLO on connect with reconnect token
- [ ] Parse WELCOME, store PlayerID/GameID
- [ ] Parse PLAYER_LIST for player names
- [ ] Parse GAME_START for initial hand
- [ ] Parse HAND_SYNC for authoritative hand recovery
- [ ] Send SYNC_REQUEST if public/private state drifts
- [ ] Render based on GAME_STATE
- [ ] Send PLAY_CARD with selected cards
- [ ] Send DRAW_CARD when drawing
- [ ] Handle CARD_DRAWN to update hand
- [ ] Handle ERROR gracefully

---

## Quick Reference

```
┌─────────────────────────────────────────────────────────────────┐
│  RUBP v1 - QUICK REFERENCE                                      │
├─────────────────────────────────────────────────────────────────┤
│  Message: 64 bytes (16 header + 48 payload)                     │
│  Byte order: Big-endian                                         │
│  Magic: "RACH" (0x52 0x41 0x43 0x48)                            │
│  Port: 19840                                                    │
│  mDNS: _rachel._tcp                                             │
├─────────────────────────────────────────────────────────────────┤
│  Card encoding (1 byte):                                        │
│    Bits 7-6: Suit (00=♥ 01=♦ 10=♣ 11=♠)                         │
│    Bits 5-0: Rank (2-10, 11=J, 12=Q, 13=K, 14=A)                │
├─────────────────────────────────────────────────────────────────┤
│  Key message types:                                             │
│    0x01 HELLO        0x04 PLAY_CARD    0x07 GAME_STATE         │
│    0x02 WELCOME      0x05 DRAW_CARD    0x0B ERROR              │
│    0x03 GAME_START   0x06 CARD_DRAWN   0x0C PLAYER_LIST        │
│    0x0F HAND_SYNC    0x10 SYNC_REQUEST                         │
│                                        0x0D ANNOUNCE           │
│                                        0x0E PLAYER_NAME        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Changelog

### RUBP v2 — CRC-protected transport

- Added CRC-16/CCITT-FALSE in header bytes 14-15.
- Reduced the optional transport timestamp to its low 16 bits in v2.
- Kept the 64-byte frame, 48-byte payload, message types, and payload layouts.
- Defined per-connection v1/v2 selection from the HELLO header.
- Required CRC validation before any v2 frame content is trusted.

### Reconciled against the `rachel-ios` reference

This revision brings the cross-platform spec back in line with the
`RachelEngine` reference implementation, which had moved ahead of the original
v1.0 draft. Client authors targeting the old draft should note:

**Breaking — message types 0x0C and 0x0D were reassigned.** The early draft
listed `0x0C = CHAT` and `0x0D = RAGE_QUIT`. Neither was implemented. The
reference now uses that range for lobby and presence messages:

| Type | Old draft | Now (reference) |
|------|-----------|-----------------|
| 0x0C | CHAT | **PLAYER_LIST** — lobby player info |
| 0x0D | RAGE_QUIT | **ANNOUNCE** — flavour text / broadcast |
| 0x0E | (unused) | **PLAYER_NAME** — per-player name |

A client built against the old draft that sent `CHAT`/`RAGE_QUIT` on 0x0C/0x0D
would now be misread as `PLAYER_LIST`/`ANNOUNCE`. There is no compatibility
shim; the reference assignments are authoritative.

**Added since the draft (all additive):**

- `0x0F HAND_SYNC` and `0x10 SYNC_REQUEST` — the authoritative private-hand
  resync pair (`PrivateHandSnapshot` / explicit resync request).
- `HELLO` now carries `SpecVersion` and a `ReconnectToken` for slot reclaim.
- `WELCOME`, `PLAY_CARD`, `DRAW_CARD`, `GAME_STATE`, `TURN_START`, `TURN_END`,
  `PLAYER_WON`, and `HAND_SYNC` carry a `SpecVersion` and an optional rules-only
  `StateHash` (flag-gated) for drift detection.
- `PLAYER_WON` carries optional per-seat `AttackDealt`/`AttackTaken` totals
  (Flags bit 1) in formerly reserved bytes 16-31, so clients can show
  end-of-game attack awards without replicating rules logic.
- `HEARTBEAT` (0x00) gained drop-detection semantics: peers that go silent past
  the timeout are treated as disconnected. The reference iOS client beats every
  ~2s and times out at ~8s on fast transports; vintage clients on slow links
  should use the gentler intervals under [Timing Considerations](#timing-considerations).
- The frozen handshake, sync, and transition contracts under [`specs/`](specs/)
  are the authoritative recovery semantics.

**Clarified — clients render, the host decides.** The Design Constraints
section previously opened by saying every platform implements the full game
locally, with its own rules engine, AI and deck management, and needs no
network for solo play. That was never true of anything but iOS: every vintage
client is render-only, and this document already assumed as much elsewhere —
`PLAYER_WON`'s attack totals exist so clients can show awards *without
replicating rules logic*.

**No message, field or byte changed**, so this is not a version bump and no
client needs altering. It is the document catching up with what the wire format
always described. If you are writing a client: you are not expected to
implement the rules, and a platform that wants solo play implements the game
locally as a matter of its own choosing rather than of conformance. The reasoning is recorded as decision 0003, "Clients render, the host
decides".

The **single source of truth is the `RachelEngine` code** (`RUBPMessage`,
`RUBPPlatformID`, `RachelSpec`). This document tracks it; the frozen `specs/`
files pin the behaviours that must not change within v1.
