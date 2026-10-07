# Engine transition fixtures v1

`fixtures/engine-transitions-v1.tsv` checks the local rules engines against
Swift `RachelEngine` revision `4c022eba2dc96c3d1bf15d09ed4cca70e7c2dace`.
It is not a new wire format and does not require render-only clients to run
an engine. The separate `rachel-transitions-v1.md` describes public RUBP
checkpoints.

There are 88 cases: 47 focused actions and 41 consecutive actions from two
complete two-player games (seeds 7 and 42). Fourteen actions are rejected.
Coverage includes normal play/draw, stacks, Ace nomination, attacks and
counters, red-Jack residue, skip wraparound and counter interruption,
reversals, exhaustion and deterministic reshuffling, finishing, duplicate
cards, and actions after game end. This does not prove every engine state,
multiplayer player count, native client or network transport.

## Encoding

UTF-8 with LF endings. Lines beginning `#` are comments. Nine tab-separated
columns: case ID, action (`play` or `draw`), played cards, nominated suit,
outcome (`ok` or a Swift `GameError.specIdentifier`), before state, after
state, before hash, after hash. Rejected actions preserve the before state
and hash. Other engines may use their existing error types but must reject
and leave state untouched.

Card values are decimal RUBP bytes. Lists are comma-separated; `-` is an
empty list. Suits are 0–3 in RUBP order, or -1 for no nomination. Hashes and
PRNG states are unsigned decimal 64-bit integers, never floating point.

Each state is thirteen semicolon-separated fields:

1. Deck, next card first.
2. Discard pile, top card last.
3. Hands in seat order; `/` separates hands (including empty `-` hands).
4. Current seat index.
5. Direction, 1 clockwise or -1 counterclockwise.
6. Pending draws.
7. Pending skips.
8. Nominated suit, or -1.
9. Out flags in seat order, 0 or 1.
10. Finish order as seat indices.
11. Turn number.
12. PRNG state.
13. Attack history: comma-separated `attacker:target:severity:turn` entries.

Swift and Go compare every field and both canonical hashes. Kotlin compares
fields 1–12: its current solo model stores neither attack history nor a local
rules hash. That omission is a remaining parity limit, not an optional part
of the full rules-state hash. Network clients still use the host's hash.

## Reproduce and consume

Build the reference Apple package first. With the current Xcode SwiftPM layout,
run from this repository:

```sh
swiftc \
  -I ../rachel-ios/.build/out/Intermediates.noindex/RachelEngine.build/Debug/RachelEngine-t.build/Objects-normal/arm64 \
  tools/ExportEngineTransitions.swift \
  ../rachel-ios/.build/out/Products/Debug/libRachelEngine.a \
  -o /tmp/rachel-export-engine-transitions
/tmp/rachel-export-engine-transitions > /tmp/engine-transitions-v1.tsv
diff -u specs/fixtures/engine-transitions-v1.tsv /tmp/engine-transitions-v1.tsv
```

Run each command successfully before trusting the following comparison. The
exporter fails if either seeded game does not finish. Keep the provenance
revision synchronized with the engine actually used to generate expectations;
review changes against the rules rather than regenerating to silence a test.

Consumers read this file directly. `RACHEL_TRANSITION_FIXTURES` supplies its
absolute path; local tests otherwise use the sibling `protocol` checkout.
CI checks out a pinned protocol revision and sets that variable. A missing,
empty, truncated, duplicate-ID or wrong-count pack must fail, not skip.
