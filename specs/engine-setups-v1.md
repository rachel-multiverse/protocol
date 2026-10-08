# Engine setup fixtures v1

`fixtures/engine-setups-v1.tsv` checks new-game dealing against Swift
`RachelEngine` revision `dce77031bf6a4c49bc3b6780abd89254b88a8f97`.
The [transition fixtures](engine-transitions-v1.md) start from supplied states;
these cases exercise the setup entry point itself.

There are 35 cases: two through eight seats at each of seeds 0, 7, 11, 42 and
18446744073709551615. The inherited deal is seven cards each for two to five
players, six each for six players, and **five each for seven or eight players**.
Every case contains all 52 distinct cards, one initial discard and at least ten
cards in reserve. Opening discards cover every rank, including both colours
of Jack. Their effects are not applied: play starts clockwise at seat zero,
with no pending draws, skips, nomination, finish order or attack history.

The exporter asserts these rules independently of the engine's hand-size
helper before producing any output. Ordered hands, discard, draw deck and
advanced PRNG state are retained so consumers can detect a different shuffle
or deal, even when the card counts agree.

## Format and consumers

UTF-8, LF endings, `#` comment lines. Five tab-separated columns: unique case
ID, seat count, input seed, complete state, canonical state hash. The state
uses the existing thirteen-field [transition encoding](engine-transitions-v1.md#encoding).
Seeds and hashes are unsigned 64-bit decimal integers, never floating point.

Read the canonical file directly; do not vendor it. `RACHEL_SETUP_FIXTURES`
can point to its absolute path. Missing files, wrong counts, duplicate IDs or
incomplete seat/seed coverage must fail instead of skipping validation. CI
consumers should pin a protocol revision.

Swift and Go support all table sizes. Kotlin's shipped `SoloGame.new` supports
two players; it checks those five cases only. This does not add larger solo
games or require render-only clients to implement an engine.

Go's `StartGame` treats a zero state seed as a request for system randomness.
Its fixture consumer checks that `ShuffleSeeded` maps zero to `0xDEADBEEF`,
then supplies that replacement to `StartGame` for the zero-input cases. The
other four seeds pass directly through the production setup entry point.
This preserves the existing Go API convention while checking the same deal.

## Reproduce

Build a fresh reference engine first. With the current Xcode SwiftPM layout,
run from this repository:

```sh
swiftc \
  -I ../rachel-ios/.build/out/Intermediates.noindex/RachelEngine.build/Debug/RachelEngine-t.build/Objects-normal/arm64 \
  tools/ExportEngineSetups.swift \
  ../rachel-ios/.build/out/Products/Debug/libRachelEngine.a \
  -o /tmp/rachel-export-engine-setups
/tmp/rachel-export-engine-setups > /tmp/engine-setups-v1.tsv
diff -u specs/fixtures/engine-setups-v1.tsv /tmp/engine-setups-v1.tsv
```

Each command must succeed before running the next. A failed exporter can
leave an empty output file; never publish it or trust a later comparison
without checking the exit status and 35-case count. Update the provenance
revision when intentionally regenerating from a different engine, and review
changes against the inherited rule rather than accepting new expectations
just because an implementation produced them.
