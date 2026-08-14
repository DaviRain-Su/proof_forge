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
| `increment(delta)` | yes | **missing** | **missing** |
| increment overflow | yes (nonzero status + pre-account hold) | **missing** | **missing** |

`SbpfHandlerJoinV1` already has the HandlerIR ↔ Loader invocation/observation
relation, including overflow → nonzero status. The gap is **get-shaped
production subject + sparse certificate** for the other three recipes.

Code facts:

- Only one resolver exists: `ProofForgeV2/Targets/Solana/SbpfStateCellProductionV1.lean`
  `resolveStateCellGetProductionSubjectV1`.
- Sparse certificate lives in `SbpfStateCellGetV1.lean`.
- Authoring doc: still no unconditional kernel equality for the large
  production theorem; release SBOM/source-dependency stays fail closed.

## Recommended next implementable slices (serial)

Do **not** start all three in one commit. Copy the `get` pattern; do not write
a second codegen.

1. **SOL-0048-INIT** — **done 2026-08-15**: production subject + generic
   executed HandlerIR/provider join + assembly identity vs `get`. Sparse
   55-step initialize certificate remains later.
2. **SOL-0048-INC** — same generic executed join for `increment` success.
3. **SOL-0048-OVF** — same for increment overflow (nonzero program error +
   pre-account snapshot). Join relation already names overflow; this slice
   only adds the production-subject/certificate.

Each slice: allowlist under `ProofForgeV2/Targets/Solana/Sbpf*` + focused
Solana asm/provider tests + SBOM if `ProofForgeV2/**` changes.

## Non-claims

Not formal TASK-D5. Not ELF/Mollusk/SVM. Not CPI/multi-account. Not product
`build` consuming the provider. Not EVM lighthouse progress.
