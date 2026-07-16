# Z2 fallback policy — Aleo Instructions (2026-07-10)

## Decision (Z2.5 / Z2.6)

**Partial go for Counter public-mapping Instructions; Leo Road 1 remains required general front-end.**

| Path | Status | Role |
|------|--------|------|
| Leo sourcegen (`--format leo`) | **Required** general front-end | All fixtures; `leo build` oracle |
| Direct Aleo Instructions (`--format aleo`) | **Bootstrap Counter only** | Matches `leo build` golden `.aleo` |
| Private records / transitions / proofs | **Deferred (Z2.6)** | Road 2; not Z2 scope |
| Hand-rolled AVM bytecode files | **No-go** | Official boundary is `.aleo` → snarkVM |

## Counter Instructions surface (Z2.0)

Needed for public mapping Counter (from `leo build` of Road 1 Leo):

```text
program counter.aleo;
mapping count: key as u64.public; value as u64.public;
function F: async F into r0; output r0 as counter.aleo/F.future;
finalize F: set | get.or_use | add ...
constructor: assert.eq edition 0u16;
```

Official guidance: compilers may target Aleo Instructions; Leo is one frontend.
See https://docs.aleo.org/build/aleo-instructions/overview

## Go criteria (met for Counter)

1. Golden `.aleo` pinned from `leo build` of `Counter.golden.leo`.
2. Lean AST + printer byte-match golden.
3. `emit --format aleo` matches golden.
4. When `leo` present, rebuild from Leo source still equals golden / direct emit.

## Blockers for general IR→Instructions

- Async/finalize split and future register assignment for non-trivial ABIs.
- Private records / transitions (Road 2).
- Constructor / edition policies beyond `@noupgrade` empty constructor.
- External imports / cross-program calls (Leo 4.0.2 bytecode-gen bugs already noted).

## Honesty

- Do not claim general `.aleo` lower while only Counter bootstrap exists.
- Product `contract_source` remains fail-closed for `aleo-leo` until general path.
- Benchmarks may measure `.aleo` size; proof metrics need snarkVM and are optional.

## Commands

```sh
just aleo-aleo-goldens
just aleo-instructions-printer
just aleo-instructions-direct
just aleo-instructions-validate   # skips if no leo
```
