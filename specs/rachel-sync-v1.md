# RachelSync v1

`RachelSync v1` freezes the authoritative recovery contract built on top of
`RachelSpec v1` and `RUBP`.

This is not a separate rules system. It is the stable meaning of:

- `PublicStateSummary`
- `PrivateHandSnapshot`
- `SYNC_REQUEST`
- the host response pair `GAME_STATE + HAND_SYNC`

The checked-in fixture file is:

- `Tests/RachelEngineTests/Fixtures/sync-recovery-v1.json`

Ports should treat that fixture file as normative for v1 recovery behavior.

## Authoritative Sync Pair

Every authoritative recovery response consists of exactly two spec-level views:

1. `PublicStateSummary`
2. `PrivateHandSnapshot` for the recovering player

The pair must be derived from the same authoritative rules state.

That means these fields must match across both objects:

- `specVersion`
- `turnNumber`
- `stateHash`

The public/private pair must also satisfy:

- `playerCardCounts[playerIndex] == cards.count`
- `PrivateHandSnapshot.playerIndex` is the recovering player slot
- `PublicStateSummary` contains only public information
- `PrivateHandSnapshot` contains only the recovering player's hidden hand

## Recovery Modes

There are two v1 recovery modes.

### Explicit Resync

Used when a client detects drift and asks the host to resend the authoritative
view.

Client sends:

- `SYNC_REQUEST`

Host responds to that peer only with:

1. `GAME_STATE`
2. `HAND_SYNC`

The `SYNC_REQUEST` metadata should reflect the last authoritative host metadata
the client has seen:

- `turnNumber == PublicStateSummary.turnNumber`
- `specVersion == PublicStateSummary.specVersion`
- `observedStateHash == PublicStateSummary.stateHash`

### Reconnect

Used when a previously assigned player reconnects and reclaims their slot.

Host sends to the reclaimed peer:

1. `WELCOME`
2. `PLAYER_NAME` entries
3. `GAME_STATE`
4. `HAND_SYNC`

The recovery pair is the same one used for explicit resync. Reconnect does not
introduce a second recovery format.

## Wire Mapping

`RachelSync v1` is a spec-level contract. `RUBP` carries compact wire forms of
that contract:

- `GAME_STATE` is the wire form of `PublicStateSummary`
- `HAND_SYNC` is the wire form of `PrivateHandSnapshot`
- `SYNC_REQUEST` carries the client's last authoritative `turnNumber`,
  `specVersion`, and optional `stateHash`

`RUBP` must not invent a second meaning for these messages.

## Fixture Coverage

The v1 fixture pack currently freezes two recovery situations:

- `explicit_resync_midgame_player_1`
- `reconnect_finished_game_player_2`

Each case pins:

- the source `StateSnapshot`
- the expected `PublicStateSummary`
- the expected `PrivateHandSnapshot`
- the expected `SYNC_REQUEST` metadata when applicable

## Porting Rule

Before implementing network recovery on another platform, a port should be able
to:

1. load the fixture snapshot
2. reproduce the expected public/private sync pair
3. reproduce the expected `SYNC_REQUEST` metadata for explicit resync cases
4. verify the same pair maps to `GAME_STATE` and `HAND_SYNC`

Only after that should the host/client reconnect logic be considered correct.
