# RachelHandshake v1

`RachelHandshake v1` freezes the session-establishment contract used before
normal gameplay sync begins.

This covers:

- `HELLO`
- `WELCOME`
- host slot assignment rules
- reconnect reclaim rules

The checked-in fixture file is:

- `Tests/RachelEngineTests/Fixtures/handshake-v1.json`

Ports should treat that fixture pack as normative for v1 handshake semantics.

## Core Model

Session establishment has three outcomes:

1. fresh join accepted
2. reconnect reclaim accepted
3. handshake rejected

`HELLO` is the client request. `WELCOME` is only sent when the host accepts the
handshake.

## Fresh Join

Fresh join means:

- `HELLO` header `GameID == 0`
- no reconnect reservation is required
- host assigns the first open non-host slot
- host only accepts the join if the game has not started

Accepted fresh join returns:

- `WELCOME`
- `PLAYER_NAME` messages for current players

If the game is still waiting in the lobby, there is no immediate authoritative
state pair yet.

## Reconnect Reclaim

Reconnect reclaim means:

- `HELLO` header `GameID == host.gameID`
- `ReconnectToken` matches a reserved disconnected slot
- host restores that original slot and player identity

Accepted reconnect reclaim returns:

1. `WELCOME`
2. `PLAYER_NAME` messages
3. if the game has already started, the authoritative recovery pair
   `GAME_STATE + HAND_SYNC`

The slot identity is the important thing. The reconnecting peer name in `HELLO`
does not override the reserved player identity during reclaim.

## Rejection Rules

At minimum, a host must reject:

- a fresh join after the game has already started
- a reclaim attempt with no matching reservation
- a handshake when there is no available lobby slot

Rejected handshakes do not receive `WELCOME`.

## WELCOME GameState

`WELCOME.GameState` must reflect the host session phase:

- `waiting` = 0
- `playing` = 1
- `finished` = 2

This is determined by the authoritative host session, not by the client's
request.

## Fixture Coverage

The v1 fixture pack currently freezes:

- `fresh_join_waiting_lobby`
- `reconnect_reclaim_playing_game`
- `reconnect_reclaim_finished_game`
- `late_join_rejected_after_game_start`

Each case pins:

- the request-side `HELLO` fields
- the expected assignment outcome
- the expected `WELCOME` fields when accepted

## Porting Rule

Before implementing host/client session establishment on another platform, a
port should be able to:

1. encode and decode the fixture `HELLO` messages
2. encode and decode the fixture `WELCOME` messages
3. reproduce the same accept/reject outcome rules
4. reproduce the same `WELCOME.GameState` values for waiting, playing, and finished hosts

Only after that should reconnect and gameplay sync be considered trustworthy.
