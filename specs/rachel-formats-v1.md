# RachelSpec External Formats v1

Status: Draft

Last updated: 2026-04-14

## Purpose

This document freezes the external data formats that non-Swift ports should
target for `RachelSpec v1`.

It covers:

- `StateSnapshot`
- `PublicStateSummary`
- `PrivateHandSnapshot`
- `ReplayTrace`
- the normative fixture/oracle artifacts used to validate them

This document is about portable formats, not app UI and not the `RUBP` wire
packing. `RUBP` is documented separately in [PROTOCOL.md](../PROTOCOL.md).

## Normative Sources

For `RachelSpec v1`, the normative sources are:

1. this document
2. [rachel-spec-v1.md](./rachel-spec-v1.md)
3. checked-in fixtures under `Tests/RachelEngineTests/Fixtures/`
4. exact JSON emitted by `RachelVMTool`

The Swift implementation in `Sources/RachelEngine/` is the current reference,
but future non-Swift ports should target the external contract above rather
than depending on Swift struct layout or `Codable` quirks.

## Shared Value Rules

### Spec Version

- `specVersion` is an unsigned 16-bit integer
- `RachelSpec v1` uses value `1`
- unknown versions must be rejected rather than guessed

### Player Indexes

- player indexes are zero-based
- `0` is the first player in turn order / roster order
- `finishOrder` stores player indexes, not names and not UUIDs

### Cards

Cards use the stable Rachel single-byte encoding already shared with `RUBP`:

- bits `7-6`: suit
- bits `5-0`: rank

Suit values:

- `0`: hearts
- `1`: diamonds
- `2`: clubs
- `3`: spades

JSON card objects use:

```json
{ "rank": "queen", "suit": "clubs" }
```

### Direction

Binary snapshot encoding:

- `0`: clockwise
- `1`: counter-clockwise

JSON encoding:

- `"clockwise"`
- `"counter_clockwise"`

### State Hash

- `stateHash` is a rules-only 64-bit unsigned hash
- it excludes host metadata such as player names and UUIDs
- it is used for parity checks, replay validation, and desync debugging

## StateSnapshot

Purpose:

- save/load
- deterministic checkpoints
- replay/debugging seed state
- cross-platform parity fixtures

Properties:

- binary
- deterministic
- versioned
- independent of Swift memory layout

Magic:

- ASCII `RSNP`
- hex `52 53 4E 50`

### Binary Layout

Header:

| Offset | Size | Field |
|---|---:|---|
| 0 | 4 | magic `RSNP` |
| 4 | 2 | `specVersion` |
| 6 | 1 | `playerCount` |
| 7 | 1 | `currentPlayerIndex` |
| 8 | 1 | `direction` |
| 9 | 1 | `nominatedSuit`, or `0xFF` for none |
| 10 | 2 | `pendingDraws` |
| 12 | 2 | `pendingSkips` |
| 14 | 4 | `turnNumber` |
| 18 | 8 | `randomSeed` |

`randomSeed` stores the current `xorshift64` state after the most recent
random operation, not necessarily the original caller-provided seed.

Variable sections, in order:

1. deck
2. discard pile
3. per-player records
4. finish order
5. attack history

Deck section:

- `UInt16 deckCount`
- `deckCount` encoded card bytes

Discard section:

- `UInt16 discardCount`
- `discardCount` encoded card bytes

Per-player record:

- `UInt8 flags`
- `UInt16 handCount`
- `handCount` encoded card bytes

Player flags:

- bit `0x01`: `isAI`
- bit `0x02`: `isOut`

Finish order section:

- `UInt8 finishOrderCount`
- `finishOrderCount` player indexes as `UInt8`

Attack history section:

- `UInt16 attackCount`
- repeated attack entries:
  - `UInt8 attackerIndex`
  - `UInt8 targetIndex`
  - `UInt16 severity`
  - `UInt32 turn`

### Validation Rules

Decoders must reject:

- bad magic
- unsupported `specVersion`
- invalid player count
- out-of-range player indexes
- invalid card encodings
- invalid suit encodings
- invalid direction encodings
- trailing bytes
- truncated data

### Excluded Data

`StateSnapshot` intentionally does not serialize:

- player display names
- player UUIDs
- platform IDs
- network session metadata
- UI state

Hosts may layer names and other presentation metadata back in after restore.

Constrained vintage hosts do not need to use `StateSnapshot` in their hot
save/load path. For that, use the compact `RKSI` image documented in
[rachel-kernel-v1.md](./rachel-kernel-v1.md).

### Checked-In Fixture

Canonical v1 fixture:

- `Tests/RachelEngineTests/Fixtures/state-snapshot-v1.hex`
- `Tests/RachelEngineTests/Fixtures/prng-vectors-v1.json`

## PublicStateSummary

Purpose:

- public sync state
- UI rendering
- replay summaries
- parity assertions that do not expose hidden information

This format intentionally excludes deck order and private hands.

Stable JSON/object shape:

```json
{
  "specVersion": 1,
  "currentPlayerIndex": 0,
  "direction": "clockwise",
  "topCard": { "rank": "5", "suit": "spades" },
  "pendingDraws": 0,
  "pendingSkips": 0,
  "deckCount": 37,
  "discardCount": 1,
  "playerCardCounts": [7, 7],
  "playerOutMask": 0,
  "finishOrder": [],
  "isGameOver": false,
  "winnerIndex": null,
  "turnNumber": 0,
  "stateHash": 9110715470989085846
}
```

Fields:

- `specVersion: UInt16`
- `currentPlayerIndex: Int`
- `direction: "clockwise" | "counter_clockwise"`
- `topCard: Card | null`
- `nominatedSuit: "hearts" | "diamonds" | "clubs" | "spades" | null`
- `pendingDraws: Int`
- `pendingSkips: Int`
- `deckCount: Int`
- `discardCount: Int`
- `playerCardCounts: [Int]`
- `playerOutMask: UInt8`
- `finishOrder: [Int]`
- `isGameOver: Bool`
- `winnerIndex: Int | null`
- `turnNumber: Int`
- `stateHash: UInt64`

`winnerIndex` is the first entry of `finishOrder` when the game is over.
In `playerOutMask`, bit `n` corresponds to player index `n`.

## PrivateHandSnapshot

Purpose:

- authoritative per-player hand sync
- player-specific replay/debugging
- host-to-client recovery data

Stable JSON/object shape:

```json
{
  "specVersion": 1,
  "playerIndex": 0,
  "cards": [
    { "rank": "2", "suit": "hearts" }
  ],
  "turnNumber": 0,
  "stateHash": 9110715470989085846
}
```

Fields:

- `specVersion: UInt16`
- `playerIndex: Int`
- `cards: [Card]`
- `turnNumber: Int`
- `stateHash: UInt64`

This format is private to the owning player and must not be broadcast to all
peers.

## ReplayTrace

Purpose:

- deterministic replay
- regression fixtures
- parity testing across implementations
- desync reproduction

Stable JSON shape:

```json
{
  "specVersion": 1,
  "playerNames": ["Alice", "Bob"],
  "aiPlayerIndices": [],
  "seed": 42,
  "initialStateHash": 9110715470989085846,
  "steps": [
    {
      "action": {
        "type": "play",
        "cards": [{ "rank": "5", "suit": "clubs" }]
      },
      "expectedStateHash": 13453199444655529146
    }
  ]
}
```

Fields:

- `specVersion: UInt16`
- `playerNames: [String]`
- `aiPlayerIndices: [Int]`
- `seed: UInt64`
- `initialStateHash: UInt64 | null`
- `steps: [ReplayStep]`

Replay step:

- `action: RachelSpecAction`
- `expectedStateHash: UInt64 | null`

`ReplayTrace` is JSON-first in v1. The checked-in fixture file is:

- `Tests/RachelEngineTests/Fixtures/replay-trace-v1.json`

## Action And Event JSON Shapes

These are shared by `ReplayTrace`, `RachelVMTool`, and the checked-in fixture
packs.

Action shapes:

```json
{ "type": "draw" }
```

```json
{
  "type": "play",
  "cards": [
    { "rank": "ace", "suit": "hearts" }
  ],
  "nominatedSuit": "clubs"
}
```

Event shapes are tagged objects with `kind`, for example:

```json
{
  "kind": "turn_advanced",
  "fromPlayerIndex": 0,
  "toPlayerIndex": 1,
  "turnNumber": 1
}
```

Stable rule error identifiers include:

- `invalid_play`
- `card_not_in_hand`
- `must_play_if_able`
- `must_nominate_suit`
- `cannot_nominate_suit`
- `not_your_turn`
- `game_already_over`

## Conformance Workflow

Ports should validate against the external contract in this order:

1. parse and emit `StateSnapshot`
2. reproduce `PublicStateSummary` and `PrivateHandSnapshot`
3. reproduce the sync recovery fixture pack in `sync-recovery-v1.json`
4. replay the checked-in `ReplayTrace` and scenario fixtures
5. match `stateHash` values
6. match VM error identifiers
7. only then implement `RUBP` wire packing

Recommended oracle commands:

```bash
swift run RachelVMTool validate-fixtures
swift run RachelVMTool show-state --snapshot Tests/RachelEngineTests/Fixtures/state-snapshot-v1.hex
swift run RachelVMTool replay --trace Tests/RachelEngineTests/Fixtures/replay-trace-v1.json
swift run RachelVMTool action-log --trace Tests/RachelEngineTests/Fixtures/replay-trace-v1.json
```

For recovery semantics, also read:

- [rachel-binary-v1.md](./rachel-binary-v1.md)
- [rachel-kernel-v1.md](./rachel-kernel-v1.md)
- [rachel-workspace-v1.md](./rachel-workspace-v1.md)
- [rachel-action-log-v1.md](./rachel-action-log-v1.md)
- [rachel-sync-v1.md](./rachel-sync-v1.md)

## Relationship To RUBP

These formats are spec-level objects.

`RUBP` carries compact wire representations of some of them:

- `GAME_STATE` carries `PublicStateSummary`
- `HAND_SYNC` carries `PrivateHandSnapshot`
- `PLAY_CARD` carries a `play` action
- `DRAW_CARD` carries a `draw` action

The `RUBP` byte layout is intentionally separate from the external JSON and
snapshot formats documented here.
