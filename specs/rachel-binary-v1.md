# RachelBinary v1

`RachelBinary v1` freezes a compact binary-facing contract for constrained
ports.

It is designed for targets where:

- JSON parsing is awkward or expensive
- storage is tight
- deterministic parity artifacts still matter

The v1 binary contract is intentionally layered on top of the already-frozen
RachelSpec meanings:

- `Card`
- `RachelSpecAction`
- `RachelSpecEvent`
- `TURN_END`
- `TURN_START`
- `PLAYER_WON`
- `StateSnapshot`

The checked-in binary fixture is:

- `Tests/RachelEngineTests/Fixtures/action-log-binary-v1.hex`

Ports should treat that fixture as normative for the v1 compact binary trace
contract.

## Card Encoding

Cards use the existing one-byte Rachel encoding:

- bits `7..6`: suit
- bits `5..0`: rank

Suit values:

- `0`: hearts
- `1`: diamonds
- `2`: clubs
- `3`: spades

Rank values:

- `2` through `14`
- `14` is Ace

This is the same card byte used by:

- `StateSnapshot`
- `RUBP`
- the reference Swift engine

## Action Encoding

Each action is encoded as:

- `actionKind: UInt8`
- `cardCount: UInt8`
- `nominatedSuit: UInt8`
- `cards: [UInt8]`

Action kinds:

- `0x00`: draw
- `0x01`: play

Rules:

- draw must use `cardCount = 0` and `nominatedSuit = 0xFF`
- play must use `cardCount > 0`
- `nominatedSuit = 0xFF` means no nominated suit

## Event Encoding

Each event begins with `eventKind: UInt8`, followed by a fixed or
count-prefixed payload.

Event kinds:

- `0x01`: `cards_removed_from_hand`
- `0x02`: `cards_added_to_discard`
- `0x03`: `attack_applied`
- `0x04`: `attack_reduced`
- `0x05`: `skip_applied`
- `0x06`: `direction_reversed`
- `0x07`: `suit_nominated`
- `0x08`: `cards_drawn`
- `0x09`: `player_finished`
- `0x0A`: `turn_advanced`
- `0x0B`: `game_finished`

Direction values:

- `0`: clockwise
- `1`: counter-clockwise

Card-array events use:

- `cardCount: UInt8`
- `cards: [UInt8]`

## Binary Action Log File

The v1 binary file is a compact equivalent of `RachelActionLog`, with duplicate
checkpoint fields removed where they can be derived from enclosing step data.

Header:

- magic `"RALG"` (`0x52 0x41 0x4C 0x47`)
- binary format version `UInt16`, currently `1`
- `specVersion: UInt16`
- `initialSnapshotLength: UInt16`
- `initialSnapshotBytes`
- `initialStateHash: UInt64`
- `stepCount: UInt16`

Each step encodes:

- `actingPlayerIndex: UInt8`
- action bytes
- `stateHash: UInt64`
- `eventCount: UInt8`
- event records
- turn-end summary:
  - `drawCount: UInt8`
  - `nextPlayerIndex: UInt8`
  - `turnNumber: UInt32`
  - `finishPosition: UInt8` or `0xFF`
  - `winnerIndex: UInt8` or `0xFF`
- continuation kind:
  - `0x00`: turn start
  - `0x01`: player won
- if continuation is turn start:
  - `pendingDraws: UInt8`
  - `pendingSkips: UInt8`

Derived fields:

- `TURN_END.playerIndex` is the step `actingPlayerIndex`
- `TURN_END.actionKind/cards/nominatedSuit` come from the encoded action
- `TURN_END.specVersion` comes from the file header
- `TURN_END.stateHash` comes from the step `stateHash`
- `TURN_START.playerIndex` is `nextPlayerIndex`
- `TURN_START.turnNumber` is the step `turnNumber`
- `TURN_START.specVersion` comes from the file header
- `TURN_START.stateHash` comes from the step `stateHash`
- `PLAYER_WON.winnerIndex` is the turn-end `winnerIndex`
- `PLAYER_WON.turnNumber` is the step `turnNumber`
- `PLAYER_WON.specVersion` comes from the file header
- `PLAYER_WON.stateHash` comes from the step `stateHash`

## Porting Rule

Before claiming compatibility with the v1 binary contract, a port should be able
to:

1. decode `action-log-binary-v1.hex`
2. reconstruct the equivalent `RachelActionLog`
3. replay the initial snapshot and steps
4. reproduce the same events, checkpoints, and post-action hashes
5. re-encode the exact same binary bytes

Only after that should a constrained port rely on the binary contract for
parity or debugging work.
