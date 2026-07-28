# RUBP Conformance Fixtures v1

Golden wire vectors that let any Rachel client or the server prove it speaks RUBP
correctly, independent of language or machine. If your encoder reproduces these
bytes and your decoder round-trips them, you are on-protocol.

## What the fixtures are

[`fixtures/rubp-messages-v1.json`](fixtures/rubp-messages-v1.json) holds one entry
per RUBP message type. Each entry pairs a set of human-readable field values with
the exact 64-byte encoding the reference implementation produces for them:

```json
{
  "name": "hello",
  "type": "HELLO",
  "type_code": "0x01",
  "summary": "Client connection / slot claim",
  "fields": { "playerName": "Alice", "sequence": "0x0021", "gameID": "0x0042", "...": "..." },
  "hex": "5241434801010021ffff0042...0000"
}
```

- `hex` is lowercase, 128 characters (64 bytes). All multi-byte values are
  big-endian. Byte layouts for every field live in [PROTOCOL.md](../PROTOCOL.md).
- `fields` are the inputs used to build the message. Where a value is the default
  for that field (e.g. HELLO's `platformID`), it is still listed so the vector is
  reproducible without reading the reference source.

## How to use them

Two checks, both required for conformance:

1. **Encode.** Build the message from `fields`, encode it, lowercase-hex the 64
   bytes, and assert it equals `hex`. This proves your field packing, byte order,
   and padding match.
2. **Decode.** Parse `hex` back into your in-memory message and re-encode it; the
   result must equal `hex` again. This proves your parser is loss-free.

A render-only vintage client that never *sends* a given message can skip its
encode check, but should still decode every `H→C` vector it will receive.

### Pseudocode

```
for msg in fixtures.messages:
    built   = build_message(msg.type, msg.fields)
    assert  hex(encode(built)) == msg.hex          # encode conformance
    parsed  = decode(unhex(msg.hex))
    assert  hex(encode(parsed)) == msg.hex          # decode round-trip
```

## Source of truth and drift

These vectors are generated from the `RachelEngine` reference encoders and guarded
by `RUBPProtocolFixtureTests` in the `rachel-ios` repo: the test rebuilds each
message and asserts the reference still produces the published `hex`, and a
coverage check fails if the file and the tests fall out of step. This file is the
mirror that other repos consume.

When the protocol changes, the reference test changes first; regenerate this file
from it and bump to `-v2` rather than editing `-v1` in place — a frozen vector is
only useful if it stays frozen.

## Coverage

`hello`, `welcome`, `play_card`, `draw_card`, `game_state`, `turn_start`,
`turn_end`, `player_won`, `hand_sync`, `sync_request`.

`heartbeat` (0x00) carries an all-zero payload and is exercised by the reference
round-trip tests rather than a golden vector; its encoding is simply the 16-byte
header followed by 48 zero bytes.
