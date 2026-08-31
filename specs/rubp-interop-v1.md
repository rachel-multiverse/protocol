# RUBP Live Interop Check v1

Where [rubp-conformance-v1.md](rubp-conformance-v1.md) checks codecs against
*static* golden bytes, this is the *live* check: a real client and a real server
exchanging RUBP over a TCP socket, each using its own independent implementation.

## How to run it

Two processes, two repos, one socket.

**1. Start the Go server** (`rachel-server`):

```bash
go run . serve --addr 127.0.0.1:6502 --min-players 1 --ai-players 1 --auto-start 1s -v
```

One human slot plus one AI, so a single client triggers a full game.

**2. Run the Swift reference client** (`rachel-ios`):

```bash
swift run RachelInteropClient --addr 127.0.0.1:6502 --name SwiftBot
```

`RachelInteropClient` speaks RUBP using the `RachelEngine` reference codec over a
raw POSIX socket. It sends a `HELLO`, decodes every reply, takes its turn once
(a `DRAW_CARD`), and prints a summary. Exit 0 means the handshake completed.

## Result — 2026-06-09

Verified against `rachel-server` at `31e48f9`:

- **Handshake + framing: PASS.** `HELLO` → `WELCOME` → `ANNOUNCE` / `PLAYER_LIST`
  → `GAME_START` (hand decoded) → `GAME_STATE`, all decoded by the Swift
  reference straight off the wire.
- **Action round-trip: PASS.** The client detected its turn, sent `DRAW_CARD`,
  and the server replied with `CARD_DRAWN` / `GAME_STATE` / `TURN_START`.

So the two implementations are byte-compatible at the header/framing level and
for the messages exercised here — real cross-language interop, not a mock.

## Open finding — TURN_END payload is not spec-conformant

The reference **rejected the server's `TURN_END` (0x09)** with `invalidPayload`,
intermittently: it decoded when the current player index was 1 or 2 and failed
when it was 0.

Cause: the server writes `Payload[1] = CurrentPlayer`, but the reconciled spec
([PROTOCOL.md](../PROTOCOL.md) § TURN_END) defines byte 1 as **ActionKind**
(`0x01`=PLAY, `0x02`=DRAW). The reference validates `ActionKind`, so the message
only survives when the current-player value happens to be a legal action kind.

The server's payloads predate the reconciled structured layouts. Bringing
`TURN_END` (and the other `H→C` payloads) fully into conformance also requires
the server to emit the rules-only `StateHash`, which means implementing the
`RachelSpec` state hash on the Go side — a tracked follow-up, not a one-liner.

Until then, the server interoperates for connection and gameplay flow, but its
structured public-event payloads should not be treated as spec-conformant.
