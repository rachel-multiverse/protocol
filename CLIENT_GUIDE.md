# Rachel Retro Client Development Guide

This document describes how to build a Rachel client for any retro platform.

## Overview

A Rachel client connects to the rachel-server over TCP, uses the RUBP (Rachel Unified Binary Protocol) for all communication, and presents a card game UI appropriate to the platform's capabilities.

## The wire format

**This guide does not describe the wire format.** It is specified once, in
[PROTOCOL.md](https://github.com/rachel-multiverse/protocol/blob/main/PROTOCOL.md) — message layout, the header, card
encoding, every payload, the platform IDs, and the conformance vectors to
check your implementation against.

That is not tidiness. This guide used to carry its own copy of those tables,
and by July 2026 the copy was wrong in four places: it put the message type at
byte 6 instead of byte 5, invented `Flags`, `Reserved` and `Checksum` fields
that do not exist while omitting `Timestamp`, encoded cards with the suit and
rank bits transposed, and filed the CoCo under an ID that belongs to the
Jupiter ACE. A client built from it could not have exchanged a single message.
The tables looked maintained, because the message-type list beside them had
been kept current.

So: read the spec for the bytes, and read this for everything the spec does
not tell you — how to get those bytes in and out of a machine with a 3.5MHz
CPU and a serial port.

Start with the [conformance fixtures](https://github.com/rachel-multiverse/protocol/tree/main/specs/fixtures). They
are the shared vectors every client checks itself against, and they will tell
you your codec is right long before a real game will.

## Client Architecture

### Required Modules

```
src/
├── main.asm        # Entry point, main loop, state machine
├── equates.asm     # Constants, memory map, message types
├── rubp.asm        # Protocol: build_header, send_hello, send_play, etc.
├── display.asm     # Screen output: title, game state, hand, cards
├── input.asm       # Keyboard handling, cursor, selection
├── game.asm        # Game logic: card rendering, selection state
├── connect.asm     # Connection UI flow
└── net/
    └── wifi.asm    # Platform-specific networking (serial/WiFi adapter)
```

### State Machine

```
┌─────────────┐
│   INIT      │ Display title screen
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  CONNECT    │ Get server address, establish TCP connection
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   HELLO     │ Send HELLO with name + platform ID
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  WAITING    │ Wait for WELCOME, then GAME_START
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  PLAYING    │◄──┐ Main game loop
└──────┬──────┘   │
       │          │
       ▼          │
   [Is my turn?]──┴── Handle input, send PLAY_CARD or DRAW_CARD
       │
       ▼
┌─────────────┐
│  GAME_OVER  │ Display winner (FinishOrder[0], NOT WinnerIndex), return to menu
└─────────────┘
```

### Main Loop Pattern

```
main_loop:
    ; 1. Check for incoming messages
    call    net_recv
    jr      c, no_message       ; Carry set = no data

    ; 2. Validate RUBP header
    call    rubp_validate
    jr      c, no_message

    ; 3. Dispatch by message type
    ld      a, (rx_buffer+5)    ; Message type (byte 5; bytes 0-3 magic, 4 version)
    cp      MSG_GAME_STATE
    jr      z, handle_game_state
    cp      MSG_CARD_DRAWN
    jr      z, handle_card_drawn
    ; ... etc

no_message:
    ; 4. Check if it's our turn
    ld      a, (CURRENT_TURN)
    ld      b, a
    ld      a, (MY_INDEX)
    cp      b
    jr      nz, main_loop       ; Not our turn

    ; 5. Handle input
    call    get_input
    ; ... process keys

    jr      main_loop
```

### Staying in Sync: Ask, Then Act

Game state arrives as a stream of `GAME_STATE` / `HAND_SYNC` broadcasts. A simple
client can fall behind that stream and choose a move against a stale top card or
an out-of-date hand — which the server then rejects. The robust, low-memory
pattern is **ask, then act**:

1. When it becomes your turn, send a **`SYNC_REQUEST`** (0x10).
2. **Block** until the server replies with the authoritative pair — `GAME_STATE`
   (0x07) then `HAND_SYNC` (0x0F). The server answers these in line before it
   reads your move, so the wait is short and bounded.
3. Decide and send your `PLAY_CARD` / `DRAW_CARD` against that fresh view.

Because the server holds the game state still while it waits for your action, the
pair you pull is exactly what your move is validated against — so a correctly
chosen play is never rejected for staleness. This is cheaper and simpler than
trying to perfectly track every broadcast, which is why it suits constrained
machines. The same pattern is used by the reference iOS client and `rachel-mcp`.

`HAND_SYNC` is also pushed to you unprompted after each of your actions and at the
start of your turn, so a render-only client that never sends `SYNC_REQUEST` still
gets an authoritative hand — but if you act on hidden state, pull first.

## Networking

### WiFi Adapter Patterns

Most retro platforms use a serial-to-WiFi adapter:

| Platform | Adapter | Interface |
|----------|---------|-----------|
| C64 | User port WiFi | CIA shift register |
| ZX Spectrum | ESP8266 | 128-byte buffer at 0x3000 |
| Amstrad CPC | ESP8266 | Port-based I/O |
| Dragon/CoCo | DragonWiFi | ACIA at $FF04 |
| BBC Micro | User port | ACIA |

### Modem Dialects: ESP-AT vs Hayes/Zimodem

Those adapters fall into two AT-command dialects. Pick the one your hardware
speaks — they differ in how you open the connection and, crucially, how inbound
data is framed:

| Dialect | Typical hardware | Open with | Inbound data | Outbound data |
|---------|------------------|-----------|--------------|---------------|
| **ESP-AT** | ESP8266 "AT" firmware (ZX, CPC, many builds) | `AT+CIPSTART="TCP","host",port` | `+IPD,<n>:<bytes>` frames, in command mode | `AT+CIPSEND=<n>`, then `n` raw bytes |
| **Hayes / Zimodem** | Commodore WiFi modems — WiFi232, Zimodem (C64) | `ATDT host:port` | **transparent**: raw bytes, no framing | **transparent**: write raw bytes straight to the line |

The canonical Rachel server endpoint is raw TCP port **6502**. Modern clients
may use TLS on port **443**. Port 8765 appeared in early client scaffolding and
is not a Rachel service endpoint.

With ESP-AT you stay in command mode the whole session and unwrap each `+IPD`
frame (always `+IPD,64:` for RUBP). With Hayes/Zimodem the link goes
**transparent** after `CONNECT`: read and write 64-byte RUBP messages directly,
with nothing wrapping them.

> **Hayes drain gotcha.** The dial reply is the standard `\r\nCONNECT\r\n`.
> Consume the **entire** CONNECT line — through the trailing `\n` — before you
> treat bytes as data. A drain that stops at the *first* CR **or** LF leaves the
> `\n` behind and shifts your first message by one byte (it looks like a valid
> 64 bytes, but every field is off). The first byte after that LF is RUBP byte 0.

Both dialects are answered by the `wifi-modem` test bridge (below), which
auto-selects based on whether the client sends `AT+CIPSTART` or `ATDT`.

### Required Network Functions

```asm
net_init        ; Initialize hardware
net_connect     ; Connect to server (IP from user)
net_send        ; Send tx_buffer (64 bytes)
net_recv        ; Receive to rx_buffer (64 bytes), set carry if none
net_close       ; Disconnect
```

### TCP Connection

The adapter typically handles TCP. The client provides:
- Server IP address (user input or hardcoded)
- Port: 19840 (Rachel default)

## Display

### Minimum Requirements

- Show current turn indicator
- Show top card on discard pile
- Show player's hand (scrollable if needed)
- Show card counts for other players
- Highlight selected cards
- Show pending draws/skips

### Card Representation

A card arrives as a single byte; the encoding is in
[PROTOCOL.md § Card Encoding](https://github.com/rachel-multiverse/protocol/blob/main/PROTOCOL.md#card-encoding),
along with the reserved values for "no card", a concealed opponent hand, and
the Joker.

What is worth deciding here is how you *draw* it:
- Text mode: "7H", "KS", "AD"
- Graphics mode: Unicode suits or custom characters

## Input

### Required Controls

| Action | Typical Keys |
|--------|--------------|
| Move cursor left | ← or Z |
| Move cursor right | → or X |
| Select/deselect card | Space |
| Play selected cards | Enter/Return |
| Draw card | D |
| Quit | Q or Break |

### Selection Model

Players can select multiple cards of the same rank for stacking:
- First selection: any playable card
- Subsequent selections: same rank only
- Playing clears selection

## Testing

### Local Server

```bash
cd rachel-server
go run . serve --min-players=2 --ai-players=1
```

### Emulator Testing

| Platform | Recommended Emulator |
|----------|---------------------|
| C64 | VICE (x64sc) |
| ZX Spectrum | Fuse |
| Amstrad CPC | Caprice32 |
| Dragon | XRoar |
| BBC Micro | BeebEm |

To test networking in an emulator (no real WiFi adapter needed), run the
**virtual ESP modem** and point the emulator's serial line at it:

```bash
# host side: emulate the WiFi adapter, bridging serial <-> TCP
go run ./cmd/wifi-modem --listen 127.0.0.1:2323
# then in VICE: RS232 / userport device -> 127.0.0.1:2323
```

`wifi-modem` answers **both** dialects (ESP-AT `AT+CIPSTART`/`AT+CIPSEND`/`+IPD`
*and* Hayes/Zimodem `ATDT` + transparent passthrough) and auto-selects from what
your client sends, then bridges to the game server — so the *same client code*
you'd run against a real ESP or WiFi232 board works in the emulator. See
`cmd/wifi-modem/README.md` in `rachel-server` for the wiring.

### Test Checklist

- [ ] Builds without errors
- [ ] Title screen displays
- [ ] Can enter server IP
- [ ] HELLO sent with correct platform ID
- [ ] WELCOME received and parsed
- [ ] Game state displays correctly
- [ ] Cards selectable and playable
- [ ] Draw works
- [ ] Game over detected

## Byte Order

**Important**: RUBP uses big-endian (network byte order) for all multi-byte values.

- **6809 (Dragon, CoCo)**: Native big-endian - no conversion needed!
- **6502 (C64, Apple II, etc.)**: Little-endian - swap bytes
- **Z80 (Spectrum, CPC, etc.)**: Little-endian - swap bytes

Example for little-endian CPUs:
```asm
; Store 16-bit value 0x00A0 at payload+16 (big-endian)
lda     #$00            ; High byte first
sta     buffer+16
lda     #$A0            ; Low byte second
sta     buffer+17
```

## Common Pitfalls

1. **Forgetting platform ID** - Server shows "Unknown" universe
2. **Wrong byte order** - 16-bit values garbled
3. **Not padding messages** - Messages must be exactly 64 bytes
4. **Blocking on receive** - Main loop should poll, not block
5. **Ignoring sequence numbers** - May cause message ordering issues
6. **Working from a copy of the spec** - Including an old copy of this guide.
   Byte offsets are worth exactly as much as their source; check them against
   [PROTOCOL.md](https://github.com/rachel-multiverse/protocol/blob/main/PROTOCOL.md)
   and prove your codec against the conformance fixtures. This document
   carried a wrong header layout for months and read as confidently as the
   right one.

## Example Implementations

Sixteen clients are public, all in assembly, none released yet. Read them —
they are the same protocol solved sixteen ways on sixteen budgets.

| Platform | CPU | Networking | Repository |
|----------|-----|------------|------------|
| Commodore 64 | 6502 | Zimodem WiFi | [rachel-commodore-64](https://github.com/rachel-multiverse/rachel-commodore-64) |
| ZX Spectrum | Z80 | Next WiFi, Spectranet | [rachel-sinclair-zx-spectrum](https://github.com/rachel-multiverse/rachel-sinclair-zx-spectrum) |
| Dragon 32 / CoCo | 6809 | DragonWiFi | [rachel-dragon-32](https://github.com/rachel-multiverse/rachel-dragon-32) |
| Commodore Amiga | 68000 | — | [rachel-commodore-amiga](https://github.com/rachel-multiverse/rachel-commodore-amiga) |
| BBC Micro | 6502 | WiFi | [rachel-acorn-bbc](https://github.com/rachel-multiverse/rachel-acorn-bbc) |
| Atari 8-bit | 6502 | FujiNet | [rachel-atari-800](https://github.com/rachel-multiverse/rachel-atari-800) |
| MSX | Z80 | GR8NET UNAPI | [rachel-msx](https://github.com/rachel-multiverse/rachel-msx) |
| Nintendo NES | 6502 | — | [rachel-nintendo-nes](https://github.com/rachel-multiverse/rachel-nintendo-nes) |

Eight more — VIC-20, Acorn Electron, Oric Atmos, ColecoVision, Master System,
Game Gear, Game Boy, Atari 7800 — are listed at
<https://rachel.stevehill.xyz/ports>.

Five of them carry a conformance harness that runs the real codec against the
shared fixtures. The C64's is the most developed: it assembles the client's
own `rubp.asm` routines and runs them on an emulated C64, diffing the bytes
they produce against the golden vectors. Copy that arrangement rather than
inventing one.

## Where to ask

The specification lives at [rachel-multiverse/protocol](https://github.com/rachel-multiverse/protocol) and is
rendered at <https://rachel.stevehill.xyz/protocol>. If something here is
wrong, or the spec and a client disagree, that repository is the place to say
so — and note which is right: the `RachelEngine` reference implementation is
the source of truth, so a disagreement is usually the document's bug.
