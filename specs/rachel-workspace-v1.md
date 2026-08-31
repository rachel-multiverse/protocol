# RachelWorkspace v1

`RachelWorkspace v1` defines the frozen reference in-memory layout for
assembly-oriented Rachel ports.

This is **not** a compatibility requirement for `RachelKernel v1`.

It exists so that:

- vintage ports have one concrete packed layout to copy
- memory budgets are explicit instead of guessed
- future ports can compare alternative layouts against a stable baseline

It does **not** mean every machine that can theoretically fit one of these
profiles is a promised product target. That commitment layer is defined in
[rachel-target-tiers-v1.md](./rachel-target-tiers-v1.md).

## Scope

`RachelWorkspace v1` is the recommended resident layout for constrained hosts
that want a straightforward assembly implementation.

It is designed around these rules:

- resident state should stay below `256` bytes
- no dynamic allocation is required
- save/load should use the compact `RKSI` kernel state image
- `attackHistory`, AI flags, and host metadata are excluded

## Budget

Reference packed profile:

- resident workspace: `192` bytes
- transient scratch: `16` bytes
- recommended total working set: `208` bytes

Constrained 2-player profile:

- resident workspace: `144` bytes
- transient scratch: `16` bytes
- recommended total working set: `160` bytes

Compact constrained 2-player profile:

- resident workspace: `80` bytes
- transient scratch: `16` bytes
- recommended total working set: `96` bytes

External host-managed buffers:

- `RKSI` state image: up to `209` bytes
- `RKAT` action table: up to `806` bytes
- `RKCT` action-count header: `22` bytes
- `RKIX` indexed action: up to `16` bytes
- `RKAP` apply summary: `31` bytes

Important:

- the `806`-byte `RKAT` buffer is not resident state
- hosts can reuse one shared output buffer across turns
- if a target cannot spare that contiguous action buffer, the next step should
  be the indexed action ABI (`RKCT` + `RKIX`), not inflating the workspace

## Resident Layout

The reference packed layout is exactly `192` bytes.

Offsets:

| Offset | Size | Field |
|---|---:|---|
| `0` | `1` | `layoutVersion` |
| `1` | `1` | `playerCount` |
| `2` | `1` | `currentPlayerIndex` |
| `3` | `1` | `packedFlags` |
| `4` | `1` | `pendingDraws` |
| `5` | `1` | `pendingSkips` |
| `6` | `4` | `turnNumber` |
| `10` | `8` | `randomSeed` |
| `18` | `1` | `finishOrderCount` |
| `19` | `8` | `finishOrder[8]` |
| `27` | `1` | `deckCount` |
| `28` | `52` | `deck[52]` |
| `80` | `1` | `discardCount` |
| `81` | `52` | `discard[52]` |
| `133` | `56` | `handMasks[8][7]` |
| `189` | `3` | reserved |

Segment sizes:

- metadata bytes before deck: `28`
- deck segment: `53`
- discard segment: `53`
- finish order segment: `9`
- hand mask bytes per player: `7`
- hand mask table: `56`
- reserved bytes: `3`

## Constrained 2-Player Layout

The constrained 2-player layout is exactly `144` bytes.

It uses the same field meanings and hand-mask mapping as the reference profile,
but only allocates space for:

- `2` finish-order slots
- `2` player hand masks

Offsets:

| Offset | Size | Field |
|---|---:|---|
| `0` | `1` | `layoutVersion` |
| `1` | `1` | `playerCount` |
| `2` | `1` | `currentPlayerIndex` |
| `3` | `1` | `packedFlags` |
| `4` | `1` | `pendingDraws` |
| `5` | `1` | `pendingSkips` |
| `6` | `4` | `turnNumber` |
| `10` | `8` | `randomSeed` |
| `18` | `1` | `finishOrderCount` |
| `19` | `2` | `finishOrder[2]` |
| `21` | `1` | `deckCount` |
| `22` | `52` | `deck[52]` |
| `74` | `1` | `discardCount` |
| `75` | `52` | `discard[52]` |
| `127` | `14` | `handMasks[2][7]` |
| `141` | `3` | reserved |

This is the first layout worth considering for “prove we can” targets around
the `1 KB` class.

## Compact Constrained 2-Player Layout

The compact constrained 2-player layout is exactly `80` bytes.

It is the smallest serious workspace profile currently frozen in the repo.

It makes three aggressive but defensible choices:

- deck order is kept in a packed `39`-byte card-ordinal stream
- only the top discard card has a dedicated resident field; buried discards
  share the packed storage after the live-deck boundary
- finish order keeps only the single finisher slot needed for a `2`-player game

Offsets:

| Offset | Size | Field |
|---|---:|---|
| `0` | `1` | `layoutVersion` |
| `1` | `1` | `playerCount` |
| `2` | `1` | `currentPlayerIndex` |
| `3` | `1` | `packedFlags` |
| `4` | `1` | `pendingDraws` |
| `5` | `1` | `pendingSkips` |
| `6` | `4` | `turnNumber` |
| `10` | `8` | `randomSeed` |
| `18` | `1` | `finishOrderCount` |
| `19` | `1` | `finishOrder[1]` |
| `20` | `1` | `deckCount` |
| `21` | `39` | `packedDeck[39]` |
| `60` | `1` | `discardCount` |
| `61` | `1` | `topDiscard` |
| `62` | `14` | `handMasks[2][7]` |
| `76` | `4` | reserved |

This is the first profile where the full resident kernel plus scratch fits
inside a `96`-byte working set.

## Packed Flags

`packedFlags` at offset `3` is defined as:

- bit `0`: direction
- bits `1..3`: nominated suit encoding
- bits `4..7`: reserved

Direction encoding:

- `0`: clockwise
- `1`: counter-clockwise

Nominated suit encoding:

- `0`: none
- `1`: hearts
- `2`: diamonds
- `3`: clubs
- `4`: spades

## Card Storage Strategy

The reference workspace uses two different card representations:

- deck and discard use normal encoded card bytes
- player hands use compact bitmasks

### Deck / Discard

`deck` and `discard` store normal `Card.encoded` bytes.

That keeps draw order and discard order explicit.

For `constrained_2p_v2`, the card strategy is different:

- `packedDeck[39]` stores draw order as `52` possible card ordinals packed into
  `6`-bit slots
- the ordinal mapping is the same as the hand-mask mapping:
  `suit * 13 + (rank - 2)`
- `topDiscard` stores only the current top card as a normal encoded byte
- buried discards follow the live deck in chronological order

The boundary is `deckCount`; `discardCount - 1` ordinals immediately after the
live deck are the buried discard pile. Preserving their chronology matters:
when the live deck is exhausted, the canonical deterministic shuffle consumes
that exact ordered sequence. Treating it as an unordered membership set can
produce a different deck, PRNG progression and replay on another platform.

### Hand Masks

Each player gets `7` bytes, or `56` bits.

Only the first `52` bits are used.

Bit ordering:

- bit order is ascending suit, then ascending rank
- bit `0` is `2 of hearts`
- bit `12` is `ace of hearts`
- bit `13` is `2 of diamonds`
- bit `25` is `ace of diamonds`
- bit `26` is `2 of clubs`
- bit `38` is `ace of clubs`
- bit `39` is `2 of spades`
- bit `51` is `ace of spades`

Formula:

```text
bitIndex = suit * 13 + (rank - 2)
byteIndex = bitIndex >> 3
bitMask = 1 << (bitIndex & 7)
```

Bits are numbered little-endian within each 7-byte player mask.

This gives compact hand storage without wasting space on sparse encoded values.

## Why This Layout

This profile keeps the resident kernel small while preserving rule-essential
information:

- deck order is preserved
- discard order is preserved
- every player hand is preserved
- finish order is preserved
- deterministic PRNG state is preserved

It deliberately excludes:

- `attackHistory`
- `isAI`
- display names
- UUIDs
- commentary state
- transport metadata

The compact constrained 2-player layout excludes a separate discard array, but
not discard order. The packed area is interpreted as the live deck prefix
followed by `discardCount - 1` buried discards. The top discard remains at
offset `61`. Sharing that storage is what keeps the resident layout sane for
small machines without sacrificing deterministic recycling.

## Scratch Budget

The reference scratch budget is `16` bytes.

This is intended to cover:

- action staging for up to `4` stacked cards
- temporary counters
- one-card swap / shuffle temporaries
- small loop state

The scratch budget is separate from the resident `192`-byte layout.

## Relationship To RKSI

`RKSI` is the compact portable save image.

`RachelWorkspace v1` is the recommended resident memory layout.

They are related, but not identical:

- `RKSI` uses count-prefixed card arrays for all zones
- `RachelWorkspace v1` uses bitmasks for hands to save RAM

A vintage host can:

1. load `RKSI`
2. unpack into the resident workspace
3. run gameplay from the workspace
4. repack to `RKSI` when saving or syncing

## Porting Rule

A port claiming support for this reference profile should be able to:

1. allocate the `192`-byte resident workspace
2. allocate the `16`-byte scratch area
3. map `RKSI` into that layout and back out again
4. reproduce the `RKAT` and `RKAP` fixtures using that resident state

For the constrained 2-player profile, the preferred action path is:

1. load `kernel-workspace-2p-v1.json`
2. use `RKCT` to get `actionCount`
3. use `RKIX` to fetch only the specific actions needed
4. avoid `RKAT` unless the target can spare the larger output buffer

For the compact constrained 2-player profile, the preferred path is:

1. load `kernel-workspace-2p-v2.json`
2. keep only the `80`-byte resident workspace plus `16` bytes scratch
3. use `RKCT` and `RKIX` exclusively
4. treat full `RKAT` support as optional

## References

- [rachel-kernel-v1.md](./rachel-kernel-v1.md)
- [rachel-formats-v1.md](./rachel-formats-v1.md)
