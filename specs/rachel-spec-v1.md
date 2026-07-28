# RachelSpec v1 Draft

Status: Draft

Last updated: 2026-04-14

## Purpose

`RachelSpec` defines the portable, language-agnostic behavior of the Rachel card game.

It exists to support:

- native iOS
- native Android
- vintage ports
- deterministic replay
- multiplayer parity
- desync debugging

`RachelSpec` is the behavioral contract.
It is not the transport protocol and it is not the UI contract.

## Relationship To Other Layers

- `RachelSpec` defines game meaning
- `RachelVM` executes `RachelSpec`
- `RUBP` transports `RachelSpec` actions and state between peers
- host apps render state and collect input

The layers should stay separate.

## Versioning

`RachelSpec` must be versioned independently.

v1 goals:

- fixed rules for the current Rachel game
- fixed deterministic shuffle behavior
- fixed action format
- fixed transition event order
- fixed snapshot and replay formats

The external format definitions live in
[rachel-formats-v1.md](./rachel-formats-v1.md).

Future incompatible rule changes must increment the spec version.

## Core Concepts

### State

Canonical state must include:

- deck order
- discard pile
- players
- hands
- current player index
- direction
- pending draws
- pending skips
- nominated suit
- finish order
- attack history
- turn number
- RNG state

This is derived from the current engine state in `GameState.swift` (in the `rachel-ios` repo, `Sources/RachelEngine/`).

### Actions

`RachelSpec v1` supports exactly two actions:

- `play(cards, nominated_suit)`
- `draw`

This matches `GameAction.swift` (in the `rachel-ios` repo, `Sources/RachelEngine/`).

Hosts may also supply an optional acting player index when they need the VM to
enforce turn ownership as part of action application, rather than treating the
caller as a fully trusted single-player shell.

### Legal Actions

`RachelSpec v1` must also define `legal_actions(state)`.

That list must be:

- deterministic
- stable across implementations
- ordered, not just set-like

For the current reference implementation, the canonical order is:

- playable actions sorted by action-catalogue order
- draw last when legal

More concretely:

- play actions sort by rank
- then by card suit bitmask
- then by nominated suit
- draw is the final action

This is the ordering exposed by `RachelVM.swift` (in the `rachel-ios` repo, `Sources/RachelEngine/`) and used by the AI action catalogue.

### Transition Result

Applying an action must produce:

- `new_state`
- `events[]`
- `state_hash` if hashing is enabled

This is the first important API addition the current Swift engine should gain.

### Transition Events

Events should be emitted in stable order so every implementation can:

- animate consistently
- replay consistently
- verify parity consistently

Candidate events for v1:

- `cards_removed_from_hand`
- `cards_added_to_discard`
- `attack_applied`
- `attack_reduced`
- `skip_applied`
- `direction_reversed`
- `suit_nominated`
- `cards_drawn`
- `player_finished`
- `turn_advanced`
- `game_finished`
- `invalid_action_rejected`

### Error Behavior

Applying an invalid action must fail in a deterministic way.

`RachelSpec v1` does not need a transport-specific error packet format, but it does need stable rule-failure categories such as:

- invalid play
- must play if able
- must nominate suit
- cannot nominate suit
- not your turn
- game already over

The current Swift reference exposes these through `GameError.swift` (in the `rachel-ios` repo, `Sources/RachelEngine/`).

The VM surface should preserve those categories directly. The checked-in
fixture suite in `Tests/RachelEngineTests/Fixtures/vm-error-cases-v1.json`
exists so future ports can match both successful transitions and rejected
actions against the same spec data.

## Determinism

Determinism is mandatory.

The spec must define:

- exact PRNG algorithm
- seed width
- shuffle algorithm
- action ordering
- integer widths
- overflow behavior
- card ordering within serialized hands, deck, and discard

Same input must produce the same output on:

- Swift
- Kotlin
- 8-bit/16-bit interpreters

`RachelSpec v1` now fixes the random path exactly:

- PRNG: `xorshift64`
- seed width: unsigned 64-bit
- zero-seed normalization: `0x00000000DEADBEEF`
- PRNG step:
  - `x ^= x << 13`
  - `x ^= x >> 7`
  - `x ^= x << 17`
- shuffle: Fisher-Yates from the end of the array down to index `1`
- swap index selection: `next() % (i + 1)`

Deck order before shuffling is fixed:

- suits in this order: hearts, diamonds, clubs, spades
- ranks in this order: 2 through ace

`GameState.randomSeed` and `StateSnapshot.randomSeed` represent the current
PRNG state after the most recent random operation, not the original caller
seed. `ReplayTrace.seed` remains the original initial seed used to start a new
game.

The checked-in fixture file `Tests/RachelEngineTests/Fixtures/prng-vectors-v1.json`
is the normative vector pack for this behavior.

## Serialization

`RachelSpec v1` now freezes four portable external formats:

- `StateSnapshot`
- `PublicStateSummary`
- `PrivateHandSnapshot`
- `ReplayTrace`
- `RachelActionLog`
- `RachelBinary`
- `RachelKernel`

Their concrete binary / JSON shapes are defined in
[rachel-formats-v1.md](./rachel-formats-v1.md).

The recovery contract built on top of those formats is defined in
[rachel-sync-v1.md](./rachel-sync-v1.md).

The session-establishment contract used before gameplay sync begins is defined
in [rachel-handshake-v1.md](./rachel-handshake-v1.md).

The public checkpoint contract emitted around authoritative actions is defined
in [rachel-transitions-v1.md](./rachel-transitions-v1.md).

Summary:

- `StateSnapshot` is the deterministic binary checkpoint format
- `PublicStateSummary` is the public sync and rendering summary
- `PrivateHandSnapshot` is the authoritative per-player private sync view
- `ReplayTrace` is the JSON-first replay and parity format
- `RachelActionLog` is the compact JSON action/event parity log
- `RachelBinary` is the compact binary parity format for constrained ports
- `RachelKernel` is the tiny host/runtime ABI shape for constrained ports

## Protocol Alignment

`RachelSpec` should align tightly with `RUBP`, but not collapse into it.

### What RUBP Should Carry

RUBP should carry:

- action requests
- lobby metadata
- player identity
- state sync snapshots or summaries
- optional state hashes
- protocol/spec compatibility information

### What RUBP Should Not Carry

RUBP should not carry:

- VM opcodes
- VM bytecode internals
- host UI state
- implementation-specific engine objects

### Mapping To Current RUBP

Current good alignments:

- `PLAY_CARD` maps to `play(cards, nominated_suit)`
- `DRAW_CARD` maps to `draw`
- `GAME_STATE` maps to a partial state sync
- `ERROR` maps to action rejection

Relevant protocol reference:
- [PROTOCOL.md](../PROTOCOL.md)
- [rachel-handshake-v1.md](./rachel-handshake-v1.md)
- [rachel-sync-v1.md](./rachel-sync-v1.md)
- [rachel-transitions-v1.md](./rachel-transitions-v1.md)
- [rachel-action-log-v1.md](./rachel-action-log-v1.md)
- [rachel-binary-v1.md](./rachel-binary-v1.md)
- [rachel-kernel-v1.md](./rachel-kernel-v1.md)
- [rachel-workspace-v1.md](./rachel-workspace-v1.md)

## Current Reference Behavior

The current Swift engine is the reference implementation until `RachelVM` exists.

Primary reference files:

- `GameEngine.swift`
- `PlayValidator.swift`
- `EffectProcessor.swift`
- `TurnManager.swift`

(all in the `rachel-ios` repo under `Sources/RachelEngine/`)

The repo also ships a small executable oracle, `RachelVMTool`, for ports and
fixture validation. It exposes the current VM boundary over JSON so non-Swift
hosts can inspect snapshots, legal actions, transitions, replays, and the
checked-in fixture packs without embedding app code.

`RachelVMTool` should be treated as part of the external contract, not a debug
dump. Its JSON must stay explicit and version-stable:

- suits as strings
- ranks as strings
- directions as strings
- tagged action objects with `type`
- tagged event objects with `kind`

It should not expose Swift enum encoding details such as single-key objects.
The checked-in JSON fixture packs and golden CLI outputs are part of that
contract, and should stay roundtrippable without any Swift-specific fallback
decoding.

Primary executable spec:

- `Tests/RachelEngineTests/`
- [rachel-formats-v1.md](./rachel-formats-v1.md)
- [rachel-workspace-v1.md](./rachel-workspace-v1.md)

## Immediate Engineering Steps

1. Add `TransitionEvent` and `TransitionResult` to the Swift engine.
2. Add deterministic state hashing.
3. Add replay fixture tests for engine edge cases.
4. Keep the external formats stable and versioned as more ports appear.
5. Keep the recovery pair contract stable as more hosts and transports appear.

## Open Questions

These need explicit answers before `RachelSpec v1` is final:

1. Should the canonical state store full UUIDs, player indexes, or both?
2. Should hashes be part of the baseline replay format or optional debug metadata?
3. Should future format revisions stay hand-authored, or move to schema-generated specs?

## Non-Goals For v1

`RachelSpec v1` should not try to solve:

- neural AI portability
- dynamic user-authored rules
- multiple game variants
- scriptable content packs
- generalized VM tooling for other games

The first job is to make one game portable and testable.
