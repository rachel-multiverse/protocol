# Rachel protocol

The wire format every Rachel client speaks, and the frozen contracts that go
with it.

- **[PROTOCOL.md](PROTOCOL.md)** — RUBP, the Rachel Unified Binary Protocol.
  Fixed 64-byte messages, big-endian, parseable in Z80, 6502 and 68000
  assembly. Start here.
- **[specs/](specs/)** — the frozen handshake, sync and transition contracts
  the protocol refers to, plus the shared conformance fixtures.

## If you are writing a client

**You are not expected to implement the rules.** The host owns the deck, the
rules and the shuffle; a client renders what it is told and sends back what
its player pressed. That is what keeps the rules identical across machines —
only one machine has them.

A platform *may* additionally implement the game locally to offer solo play,
as the iOS app does. That is a platform's own choice and has nothing to do
with conformance.

Conformance means your messages are right. The fixtures in
[`specs/fixtures/`](specs/fixtures/) are the shared vectors to check against:

```
specs/fixtures/rubp-messages-v1.json
```

**Use this copy, do not vendor your own.** Five client repositories carry a
copy of that file today and every one of them has already drifted from it —
identical in length, differing in a single card byte, which is the kind of
drift nothing notices until two machines disagree mid-game. That is why this
repository exists.

## Why this is a repository of its own

The specification used to live in a private repository beside internal
decision records. Two things followed from that, and both were real:

- Independent port authors could not read it, although the spec's own
  changelog said breaking changes were written down "because independent port
  authors read it".
- The conformance fixtures were copied into client repositories rather than
  referenced, and drifted.

The contract is public because people outside this project are meant to
implement it. The working notes that produced it are not, and stay where they
were.

## What is authoritative

The **`RachelEngine` reference implementation** in `rachel-ios` is the source
of truth. Where this specification and that code disagree, the code is right
and this document is the bug. See `PROTOCOL.md` § Changelog.

This repository is where the specification lives, not where the truth is
decided.

## Published

The specification is rendered at
**<https://rachel.stevehill.xyz/protocol>**, generated from this repository.
