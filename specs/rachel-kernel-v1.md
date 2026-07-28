# RachelKernel v1

`RachelKernel v1` defines a tiny host/runtime boundary for constrained ports.

It is intended for systems that:

- have very limited RAM
- are likely to be programmed in assembly
- need deterministic rule execution without carrying modern host layers

This is not a wire protocol.
This is not a UI contract.
This is the local host-to-rules ABI shape.

## Design Goals

`RachelKernel v1` is designed around these constraints:

- no required dynamic allocation
- no required VM-owned heap objects exposed to the host
- no host dependency on Swift object layout
- fixed-size or tightly bounded command results
- deterministic action ordering and transition summaries

## What The Host Owns

The host owns:

- display names
- rendering
- input
- audio
- menus and save UX
- networking
- any local AI personality/commentary layer

The kernel owns:

- legal action enumeration
- action application
- deterministic rule state
- compact save/load over a stripped kernel state image

For many vintage ports, especially BASIC- and FORTH-friendly ones, a local
kernel implementation is not the expected starting point. A render-only network
client is often the more realistic first version. `RachelKernel v1` exists so
that tighter or more ambitious ports have a frozen local ABI when they need it.

## Workspace Model

The host provides an opaque workspace for the target interpreter.

Important:

- the workspace layout is not part of `RachelKernel v1`
- the workspace byte size is target-binding-specific, not cross-platform spec data
- the frozen part of the contract is the command set and the input/output blobs

For vintage ports that do want a concrete memory model, the repo now also
freezes a reference packed workspace profile in
[rachel-workspace-v1.md](./rachel-workspace-v1.md). That profile is guidance for
assembly-oriented implementations, not a requirement for all `RachelKernel v1`
hosts.

This keeps the ABI portable while still allowing a 6502, Z80, 68000, or ARM
interpreter to use whatever internal packing is most practical.

Target commitment is a separate question. A machine being identifiable by the
protocol or plausible under the kernel ABI is not the same thing as a promised
client. That policy is frozen in
[rachel-target-tiers-v1.md](./rachel-target-tiers-v1.md).

## Command Set

The minimal command set is:

- `GET_INFO`
- `NEW_GAME`
- `LOAD_STATE`
- `SAVE_STATE`
- `GET_ACTION_COUNT`
- `GET_ACTION_AT`
- `LIST_ACTIONS`
- `APPLY_ACTION`

`NEW_GAME`, `LOAD_STATE`, and `SAVE_STATE` should use the compact kernel state
image with magic `RKSI`.

The richer `StateSnapshot` format from
[rachel-formats-v1.md](./rachel-formats-v1.md) still exists as the full-fidelity
checkpoint/interchange format, but it is no longer the preferred hot-path save
image for constrained hosts.

`LIST_ACTIONS`, `GET_ACTION_COUNT`, `GET_ACTION_AT`, and `APPLY_ACTION` use
smaller kernel-specific binary result formats so assembly hosts do not need to
parse the larger JSON or replay formats during normal gameplay.

## GET_INFO

`GET_INFO` returns a fixed binary info block with magic `RHKI`.

The checked-in fixture is:

- `Tests/RachelEngineTests/Fixtures/kernel-info-v1.hex`

Fields:

- `abiVersion: UInt16`
- `specVersion: UInt16`
- `minPlayers: UInt8`
- `maxPlayers: UInt8`
- `maxActionCount: UInt8`
- `maxActionBytes: UInt8`
- `maxActionTableBytes: UInt16`
- `maxApplySummaryBytes: UInt16`
- `maxHandBytes: UInt8`
- `flags: UInt16`

Current v1 flags mean:

- deterministic action order is guaranteed
- actor validation is supported
- an opaque workspace model is supported
- a no-dynamic-allocation interpreter is a supported target shape
- binary action tables are supported
- binary apply summaries are supported

## NEW_GAME

Inputs:

- player count
- AI mask
- deterministic seed

Output:

- `RKSI` binary blob

Names are host metadata and are not required by the kernel ABI itself.
Reference hosts may still layer placeholder names onto the Swift implementation
when producing the canonical snapshot.

## LOAD_STATE

Input:

- `RKSI` binary blob

Effect:

- restore authoritative rules state into workspace

If the snapshot is invalid or unsupported, the call fails deterministically.

## SAVE_STATE

Output:

- `RKSI` binary blob

This is the canonical persistence/export format for constrained `RachelKernel v1`
hosts.

## Kernel State Image

The compact kernel state image uses magic `RKSI`.

The checked-in fixture is:

- `Tests/RachelEngineTests/Fixtures/kernel-state-v1.hex`

Purpose:

- hot-path save/load for constrained ports
- compact seed state for assembly hosts
- deterministic kernel hashing and action enumeration

Important properties:

- strips `attackHistory`
- strips per-player `isAI`
- preserves deck, discard, hands, turn state, finish order, and PRNG state

That means `RKSI` is suitable for deterministic rules execution, but it is not
the full-fidelity state needed for grudge-aware AI parity.

### Binary Layout

Header:

- magic `RKSI`
- `abiVersion: UInt16`
- `specVersion: UInt16`
- `playerCount: UInt8`
- `currentPlayerIndex: UInt8`
- `direction: UInt8`
- `nominatedSuit: UInt8` or `0xFF`
- `pendingDraws: UInt8`
- `pendingSkips: UInt8`
- `turnNumber: UInt32`
- `randomSeed: UInt64`

Variable sections:

1. deck
2. discard pile
3. per-player records
4. finish order

Deck section:

- `UInt8 deckCount`
- `deckCount` encoded card bytes

Discard section:

- `UInt8 discardCount`
- `discardCount` encoded card bytes

Per-player record:

- `UInt8 flags`
- `UInt8 handCount`
- `handCount` encoded card bytes

Player flags:

- bit `0x01`: `isOut`

Finish order section:

- `UInt8 finishOrderCount`
- `finishOrderCount` player indexes as `UInt8`

Safe upper bound:

- `209` bytes

The actual canonical v1 fixture is much smaller than that upper bound.

## LIST_ACTIONS

`LIST_ACTIONS` returns a compact binary action table with magic `RKAT`.

The checked-in fixture is:

- `Tests/RachelEngineTests/Fixtures/kernel-actions-v1.hex`

Fields:

- `abiVersion: UInt16`
- `specVersion: UInt16`
- `actingPlayerIndex: UInt8`
- `turnNumber: UInt32`
- `stateHash: UInt64`
- `actionCount: UInt8`
- `actions: [KernelAction]`

Each `KernelAction` uses the same compact action encoding as the frozen binary
spec:

- `actionKind: UInt8`
- `cardCount: UInt8`
- `nominatedSuit: UInt8`
- `cards: [UInt8]`

The host should treat the returned action order as canonical.

## GET_ACTION_COUNT

`GET_ACTION_COUNT` returns a compact catalog header with magic `RKCT`.

The checked-in fixture is:

- `Tests/RachelEngineTests/Fixtures/kernel-action-count-v1.hex`

Fields:

- `abiVersion: UInt16`
- `specVersion: UInt16`
- `actingPlayerIndex: UInt8`
- `turnNumber: UInt32`
- `stateHash: UInt64`
- `actionCount: UInt8`

This is the preferred entry point for very small hosts that cannot spare the
full `RKAT` action-table buffer.

## GET_ACTION_AT

`GET_ACTION_AT` returns one legal action by index with magic `RKIX`.

The checked-in fixture is:

- `Tests/RachelEngineTests/Fixtures/kernel-action-at-0-v1.hex`

Fields:

- `abiVersion: UInt16`
- `specVersion: UInt16`
- `actionIndex: UInt8`
- `KernelAction`

`KernelAction` uses the same compact encoding as `RKAT`.

The host should:

1. call `GET_ACTION_COUNT`
2. iterate from `0` to `actionCount - 1`
3. call `GET_ACTION_AT(index)` for the specific action it wants to inspect or execute

This avoids the large contiguous `RKAT` output buffer on memory-constrained
machines.

## APPLY_ACTION

`APPLY_ACTION` takes one encoded action plus an optional actor index and mutates
the workspace state.

It returns a fixed-size binary summary with magic `RKAP`.

The checked-in fixture is:

- `Tests/RachelEngineTests/Fixtures/kernel-apply-v1.hex`

Fields:

- `abiVersion: UInt16`
- `specVersion: UInt16`
- `stateHash: UInt64`
- `actingPlayerIndex: UInt8`
- `nextPlayerIndex: UInt8`
- `turnNumber: UInt32`
- `pendingDraws: UInt8`
- `pendingSkips: UInt8`
- `actionKind: UInt8`
- `drawCount: UInt8`
- `finishPosition: UInt8` or `0xFF`
- `winnerIndex: UInt8` or `0xFF`
- `nominatedSuit: UInt8` or `0xFF`
- `flags: UInt16`

Apply-summary flags currently cover:

- cards drawn by the actor
- direction changed
- suit nominated
- acting player finished
- game won
- draw attack applied
- draw attack reduced
- skip attack applied

The fixed summary is intentionally smaller than a full event log. If a host
needs more detail, it can:

- inspect the new saved snapshot, or
- use the larger JSON/binary trace tooling offline during development

## Why This Shape Fits Vintage Targets

This split keeps the hot gameplay path small:

- `GET_ACTION_COUNT` gives a tiny legal-action header
- `GET_ACTION_AT` gives one bounded action at a time
- `LIST_ACTIONS` gives a bounded action catalog
- `APPLY_ACTION` gives a bounded post-action summary
- `SAVE_STATE` / `LOAD_STATE` use `RKSI`, not the fuller `StateSnapshot`

That is a much better fit for assembly hosts than:

- parsing large JSON documents
- carrying a full replay trace every turn
- depending on a large event object model in runtime memory
- carrying variable-length attack/grudge history in the core save image
- requiring an `806`-byte contiguous legal-action buffer on every turn

## Non-Goals

`RachelKernel v1` does not freeze:

- a shared internal workspace layout
- a common calling convention for 6502 vs Z80 vs 68000 vs ARM
- neural AI
- commentary/grudge metadata
- richer host-side inspection helpers

Those can be added later as target bindings or future kernel revisions.

## Porting Rule

Before claiming compatibility with `RachelKernel v1`, a constrained port should
be able to:

1. consume `kernel-info-v1.hex`
2. load a frozen `kernel-state-v1.hex`
3. reproduce either `kernel-actions-v1.hex` or the indexed pair `kernel-action-count-v1.hex` and `kernel-action-at-0-v1.hex`
4. apply a frozen action and reproduce `kernel-apply-v1.hex`
5. save the resulting `RKSI` image deterministically

Ports that also need full-fidelity replay/debug interchange should separately
support `StateSnapshot`.

That is the minimal viable host/runtime boundary for the first vintage ports.
