# RachelTransitions v1

`RachelTransitions v1` freezes the public checkpoint stream emitted around
authoritative action application.

This covers:

- `TURN_END`
- `TURN_START`
- `PLAYER_WON`

The checked-in fixture file is:

- `Tests/RachelEngineTests/Fixtures/transition-checkpoints-v1.json`

Ports should treat that fixture pack as normative for v1 public checkpoint
behavior.

## Core Model

These messages are public checkpoints derived from the authoritative engine
transition, not independent game logic.

Given:

- an authoritative pre-action state
- an action
- the acting player index
- the resulting authoritative transition

the public checkpoint stream is:

1. `TURN_END`
2. if the game is not over, `TURN_START`
3. if the game is over, `PLAYER_WON` instead of `TURN_START`

## TURN_END

`TURN_END` is the public summary of the action that just completed.

Its fields are derived as follows:

- `playerIndex`: the acting player
- `actionKind`: `play` or `draw`
- `cards`: the public cards in the action
- `nominatedSuit`: the nominated suit for Ace plays, otherwise `null`
- `drawCount`: number of cards drawn by the acting player in the transition
- `nextPlayerIndex`: `transition.snapshot.currentPlayerIndex`
- `turnNumber`: `transition.snapshot.turnNumber`
- `finishPosition`: emitted only if the acting player finished on this action
- `winnerIndex`: emitted only if this action ended the game
- `specVersion`: `transition.snapshot.specVersion`
- `stateHash`: authoritative post-action rules hash

## TURN_START

`TURN_START` is only emitted when the game continues after the action.

Its fields are derived from the authoritative post-action state:

- `playerIndex`: `transition.snapshot.currentPlayerIndex`
- `turnNumber`: `transition.snapshot.turnNumber`
- `pendingDraws`: `transition.snapshot.pendingDraws`
- `pendingSkips`: `transition.snapshot.pendingSkips`
- `specVersion`: `transition.snapshot.specVersion`
- `stateHash`: authoritative post-action rules hash

## PLAYER_WON

`PLAYER_WON` is only emitted when the transition includes `game_finished`.

Its fields are derived from the same authoritative post-action state:

- `winnerIndex`: the winner reported by the transition
- `turnNumber`: `transition.snapshot.turnNumber`
- `specVersion`: `transition.snapshot.specVersion`
- `stateHash`: authoritative post-action rules hash

## Ordering Rule

For a valid action:

- emit `TURN_END` first
- then emit exactly one of:
  - `TURN_START`
  - `PLAYER_WON`

For an invalid action:

- do not emit any of these checkpoint messages

## Fixture Coverage

The v1 fixture pack currently freezes:

- draw with authoritative turn restart
- Ace play with suit nomination
- attack play that carries pending draws into the next turn
- play that finishes a player but not the game
- play that finishes the game

Each case pins:

- the source snapshot
- the action and acting player
- the expected portable event kinds
- the expected `TURN_END`
- the expected `TURN_START` or `PLAYER_WON`

## Porting Rule

Before implementing multiplayer checkpoint handling on another platform, a port
should be able to:

1. replay the fixture action from the fixture snapshot
2. reproduce the same event ordering and post-action hash
3. reproduce the same `TURN_END`
4. reproduce the same `TURN_START` or `PLAYER_WON`

Only after that should a host/client claim compatibility with the v1 public
checkpoint stream.
