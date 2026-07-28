# RachelActionLog v1

`RachelActionLog v1` freezes a compact external action/event trace for ports,
parity checks, and desync debugging.

It is intentionally smaller than the full `RachelVMTool replay` output:

- one initial `StateSnapshot`
- ordered action steps
- resulting state hashes
- emitted transition events
- emitted public checkpoints

It does not repeat full snapshots, public sync summaries, or private hands after
every step.

The checked-in fixture file is:

- `Tests/RachelEngineTests/Fixtures/action-log-v1.json`

Ports should treat that fixture as normative for the v1 compact trace contract.

## Top-Level Shape

```json
{
  "specVersion": 1,
  "initialSnapshotHex": "52534e50...",
  "initialStateHash": 9892255162964722708,
  "steps": [
    {
      "actingPlayerIndex": 0,
      "action": {
        "type": "play",
        "cards": [{ "rank": "4", "suit": "spades" }]
      },
      "stateHash": 18355280802430975518,
      "events": [
        { "kind": "cards_removed_from_hand", "playerIndex": 0, "cards": [{ "rank": "4", "suit": "spades" }] }
      ],
      "turnEnd": { "...": "..." },
      "turnStart": { "...": "..." },
      "playerWon": null
    }
  ]
}
```

Fields:

- `specVersion: UInt16`
- `initialSnapshotHex: String`
- `initialStateHash: UInt64`
- `steps: [ActionLogStep]`

## Step Shape

Each step represents one authoritative action application.

Fields:

- `actingPlayerIndex: Int`
- `action: RachelSpecAction`
- `stateHash: UInt64`
- `events: [RachelSpecEvent]`
- `turnEnd: TURN_END checkpoint`
- `turnStart: TURN_START checkpoint | null`
- `playerWon: PLAYER_WON checkpoint | null`

Rules:

- `actingPlayerIndex` is the authoritative actor before the action is applied
- `stateHash` is the authoritative post-action rules hash
- `events` must preserve the exact event ordering emitted by the reference VM
- `turnEnd` is always present for valid actions
- exactly one of `turnStart` or `playerWon` is present for a valid action

## Relationship To Other Formats

`RachelActionLog` is derived from:

- `StateSnapshot`
- `RachelSpecAction`
- `RachelSpecEvent`
- public checkpoints from [rachel-transitions-v1.md](./rachel-transitions-v1.md)

It is typically produced from a `ReplayTrace`, but it is a separate external
contract. Ports should consume the log directly and should not need to know how
the reference Swift implementation stores replay traces internally.

## Why Use It

Use `RachelActionLog` when a port needs:

- a smaller deterministic parity artifact than full replay output
- exact event ordering
- exact checkpoint ordering
- post-action state hashes
- one initial snapshot instead of a full snapshot per step

For many constrained or vintage targets, this is the recommended debugging and
parity format.

## Porting Rule

Before claiming parity with the v1 compact trace contract, a port should be able
to:

1. restore the initial snapshot from `initialSnapshotHex`
2. apply each step action using `actingPlayerIndex`
3. reproduce the same post-action `stateHash`
4. reproduce the same ordered `events`
5. reproduce the same `turnEnd`
6. reproduce the same `turnStart` or `playerWon`

Only after that should a port rely on the log for multiplayer/debug parity.
