---
id: PLAN-SOL-ADR-0048-NEXT
title: Solana ADR-0048 D4 remaining certificates
status: draft
owner: engineering
updated: 2026-08-15
normative: false
---

# ADR-0048 D4：还缺什么

> Engineering inventory only. Does **not** close formal `TASK-D5-*`,
> Mollusk/`.so`/validator semantics, or accepted-PRD expansion.
> Does **not** invent a new `TASK-*`. Provider stays off the product `build` path
> (ADR-0048 D3).

Authority: [`0048-optional-solana-sbpf-semantics-provider.md`](../adr/0048-optional-solana-sbpf-semantics-provider.md)
D4 · [`verified-contract-authoring.md`](verified-contract-authoring.md) §5.

## Already pinned

| D4 recipe | Observation execute | Production subject resolver | Sparse kernel certificate |
|---|---|---|---|
| `get()` | yes | `resolveStateCellGetProductionSubjectV1` | 55-step + `runFuel` status-zero |
| `initialize(initial)` | yes (Loader V3 single-account) | `resolveStateCellInitializeProductionSubjectV1` | generic executed join (no 55-step sparse cert yet) |
| `increment(delta)` | yes | `resolveStateCellIncrementProductionSubjectV1` | generic executed join (no sparse cert yet) |
| increment overflow | yes (nonzero status + pre-account hold) | `resolveStateCellIncrementOverflowProductionSubjectV1` | generic executed join (no sparse cert yet) |

`SbpfHandlerJoinV1` already has the HandlerIR ↔ Loader invocation/observation
relation, including overflow → nonzero status. All four production subjects are
now bound; sparse certificates remain open for all three mutating recipes.

Code facts:

- `ProofForgeV2/Targets/Solana/SbpfStateCellProductionV1.lean` contains the
  `get`, `initialize`, increment-success, and increment-overflow resolvers. All
  consume the same elaborated Source AST, production validator/canonical encoder
  binding, compiler and production `.s`; overflow reuses the private increment
  subject directly. Only `get` currently retains a sparse provider certificate.
- Sparse certificate lives in `SbpfStateCellGetV1.lean`.
- Authoring doc: still no unconditional kernel equality for the large
  production theorem; release SBOM/source-dependency stays fail closed.

## Recommended next implementable slices (serial)

Do **not** start all three in one commit. Copy the `get` pattern; do not write
a second codegen.

1. **SOL-0048-INIT** — **done 2026-08-15**: production subject + generic
   executed HandlerIR/provider join + assembly identity vs `get`. Sparse
   55-step initialize certificate remains later.
2. **SOL-0048-INC** — **done 2026-08-15**: same generic executed join for
   pinned `41 + 1` increment success; sparse certificate remains later.
3. **SOL-0048-OVF** — **done 2026-08-15**: `UInt64.max + 1` generic executed
   join fixes provider status `0x1001` and exact pre-account snapshot agreement;
   sparse certificate remains later.

Next certificate order: initialize sparse trace first, then factor the shared
increment dispatch/load prefix before closing success and overflow suffixes.
Hashed-QN CallGate/ScheduleGate last-20 pin is done; binding stays
`B-CALL-SEM` ([`evm-call-addr-gap.md`](evm-call-addr-gap.md)).

Each slice: allowlist under `ProofForgeV2/Targets/Solana/Sbpf*` + focused
Solana asm/provider tests + SBOM if `ProofForgeV2/**` changes.

## Non-claims

Not formal TASK-D5. Not ELF/Mollusk/SVM. Not CPI/multi-account. Not product
`build` consuming the provider. Not EVM lighthouse progress.
