# Rachel Vintage Target Tiers v1

`Rachel Vintage Target Tiers v1` exists to stop the protocol registry and
memory work from being misread as a shipping commitment.

Important:

- a `RUBPPlatformID` means the protocol can name that machine class
- it does **not** mean a maintained client exists
- it does **not** mean the machine is currently on the delivery roadmap

This document is about vintage and constrained targets only.

Modern platforms are assumed to be comfortable Rachel machines. The main
question here is not “can a modern machine run Rachel?” but “which vintage
machines are we actually promising to support?”

This document defines the current commitment levels.

## Tier A: Supported Vintage Targets

Tier A means:

- a native client is an explicit project goal
- the machine is large enough that `RachelKernel v1` is not a stunt
- we are willing to support the port as a real Rachel client, not a curiosity

Current Tier A floor:

- `Commodore 64`

Why the C64 is the floor:

- enough RAM to make the kernel, screen, serial bridge, and program code sane
- a concrete client design already exists in
  [2025-12-22-rachel-c64-design.md](../plans/2025-12-22-rachel-c64-design.md)
- it is a good baseline for 6502-era “real” support rather than proof-only work

Implication:

- `Commodore 64` is the smallest vintage machine we should currently describe as
  a supported target

## Tier B: Plausible But Not Promised

Tier B means:

- the current kernel and memory profile suggest the machine could run Rachel
- a port would be welcomed if proven
- the main project is not yet promising delivery or ongoing support

Current Tier B examples:

- `VIC-20`
- `ZX81` with RAM expansion
- other machines in the same “very small but not absurd” class

Why these stay in Tier B:

- the `constrained_2p_v2` workspace is now only `80` resident bytes plus `16`
  bytes scratch, but that solves only the rules core
- code size, display memory, stack, serial buffers, and toolchain pain still
  matter as much as the kernel footprint
- these are now plausible Rachel machines, but still not sensible promises

## Tier C: Out Of Scope For RachelSpec v1

Tier C means:

- the machine is not a credible target for full Rachel under the current rules
  and ABI
- making it work would require a different game, a materially reduced ruleset,
  or a non-Rachel host model

Current Tier C examples:

- stock `ZX80`
- stock `ZX81`
- `Atari 2600`

Why:

- the current `RachelKernel v1` and workspace trims are strong, but they do not
  erase the total-system costs around them
- these machines are below the line where “can run Rachel” is still honest

## Policy

The project ethos is still:

- if a machine can honestly run Rachel, we should be open to it

The network policy should be read as:

- open protocol, narrow official support
- any machine that can honestly implement the Rachel handshake, sync, and
  action contract should be allowed to connect
- that openness does **not** imply an official maintained client
- official support still follows the target tiers

But roadmap language must follow the tiers:

- Tier A: may be described as a supported target
- Tier B: may be described as plausible or experimental only
- Tier C: must not be described as a target for full Rachel

In other words:

- Tier A machines can be promised
- Tier B machines can be welcomed
- Tier C machines should not be implied at all

## Language Policy

Support is defined at the `machine + protocol` level, not the language level.

That means:

- a machine may have multiple Rachel clients in different languages
- Assembly, BASIC, FORTH, C, Pascal, and similar implementations are all valid
- one machine does **not** automatically imply one blessed language
- language diversity is welcomed, but it is not the same thing as a support
  promise for every implementation

The preferred model is:

- one maintained reference client per supported machine
- any number of alternative or experimental clients

For constrained vintage systems, the expected default is:

- render-only clients first

Why:

- they are much easier to fit into small machines
- they avoid forcing every language/runtime to host the full rules engine
- they make BASIC and FORTH implementations much more realistic
- they still benefit from the open protocol and frozen sync/action contract

So the practical reading is:

- support the machine
- welcome multiple language implementations
- expect many vintage clients to be render-only unless a local kernel port is
  clearly justified

## Relationship To Platform IDs

The protocol registry intentionally contains more IDs than the current support
matrix.

That is by design:

- the protocol needs stable numeric identities ahead of individual ports
- platform IDs are naming infrastructure
- the target tiers are the commitment layer

So the correct reading is:

- `RUBPPlatformID` answers “can the protocol identify this machine class?”
- `Rachel Vintage Target Tiers v1` answers “are we promising a client?”
