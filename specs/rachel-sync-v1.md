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

## Negotiated Slow-Client Acknowledgement

Clients that cannot reliably buffer consecutive 64-byte frames may negotiate
flow control without changing the RachelSpec version:

- `HELLO` payload byte 36 capability bit `0x01` advertises sync-ACK support.
- `WELCOME` payload byte 8 and `PLAYER_LIST` payload byte 47 repeat the host's
  support bit. Repetition lets a client recover if WELCOME is lost.
- After parsing a matching `GAME_STATE + HAND_SYNC` pair, the client sends a
  `SYNC_REQUEST` with flags `0x03`: bit `0x01` says the hash is present and bit
  `0x02` identifies the message as an acknowledgement.
- The acknowledgement echoes the pair's `turnNumber`, `specVersion`, and
  `observedStateHash` in the ordinary SYNC_REQUEST fields.
- A host that negotiated the capability must not send `TURN_START` until a
  matching acknowledgement arrives. It retransmits the pair after a bounded
  timeout and discards actions received before the matching acknowledgement.

Peers that do not advertise the capability retain the original v1 behavior.
An ACK flag sent without negotiation is treated as an ordinary resync request.

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
