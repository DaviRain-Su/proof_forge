---
id: PLAN-EVM-FORMAL-D2-07-GAP
title: EVM formal lighthouse — TASK-D2-07 / TST-SEM-002/003 gap
status: draft
owner: engineering
updated: 2026-08-14
normative: false
---

# EVM formal lighthouse：D2-07 gap

> Engineering inventory only. Does **not** close `TASK-D2-07`, `TST-SEM-002`,
> `TST-SEM-003`, C-3, Anvil lossless, or any EV/qualification object.
> Does **not** invent a new `TASK-*`.

Authority: [`04-task-breakdown.md`](../04-task-breakdown.md) `TASK-D2-07` →
[`05-test-spec.md`](../05-test-spec.md) `TST-SEM-002/003` paragraph ·
[`semantic-core.md`](../specs/semantic-core.md) Reference Semantics ·
ADR-0036 EVM-first.

## Why this cannot be marked formal-done

| Blocker | Fact |
|---|---|
| Dependency | `TASK-D2-07` depends on `TASK-D2-06` (`TST-SEM-001` / `TST-PROOF-001`). Both pending. |
| Evidence | Formal closeout needs EV retained-artifact digest binding. `OutcomeWireV1` is engineering-only (`pf.reference-outcome.v1`). |
| Qualification | `TASK-D1-01` still blocked; recovery forbids inventing freeze/EV ceremony. |
| Adapter | TST allows in-process structural `OutcomeV1` equality **now**; persisted target differential stays blocked until tagged retained artifact + verifier exist. Anvil ↛ OutcomeWire lossless remains spec-FC (C-3). |
| Spec drift | `SPEC-SEM-001` still says v1 external call has no return value. Product `N-CALL-RET` already has typed `returnValue?`. Formal corpus stays on the void-call subset until an ADR amends the accepted spec. |

## Engineering already pins (LH-1…28)

Public `ReferenceV1.step` → `admitReferenceProgramSliceV1` → `stepReferenceSliceV1`.
`Tests.Semantic.Sem002ShapeV1` / `Sem003ShapeV1` mint OutcomeWire and require
structural decode identity.

**TST-SEM-002 shape present:** no-init default `initialized=true`; init default
`initialized=false` then init; entry + view; unixTime context
missing/extra/duplicate/wrong-bytes/**wrong TypeId**; sync call returned/reverted;
wrong kind/arity/type; noncanonical arg bytes; response
missing/extra/duplicate/reordered; same-key different Core result TypeId
(structure `.badCfg`, step unseen); emit occurrence 0 + normalized UInt64 result.

**TST-SEM-003 shape present:** overflow / declared / assert rollback; every
`SemanticFaultV1`; all ten `StandardRevertCodeV1`; matched revert + trailing
extra; program revert/trap + unconsumed response → unique
`invalidExternalResponse`; pre-state held; zero committed effects.

## Remaining corpus holes

| Hole | Status |
|---|---|
| Response **missing** / **extra** | pinned 2026-08-14 in `Sem002ShapeV1` (`responses/missing`, `responses/extra`; same trapped digest) |
| Context **wrong TypeId** (Bool vs UInt64) | pinned 2026-08-14 (`ctx/wrong-type`) |
| Same-key different **Core** result TypeId | pinned 2026-08-14 in `Sem002ShapeV1` (`ctx/core-type`; structure+encode `.badCfg`; step unseen). Do not weaken the wire gate. |

## First fail-closed slice (engineering done)

Allowlist: `Tests/Semantic/Sem002ShapeV1.lean` (+ `NormalizeV1` fn body-local
purity so the Sem002Ctx `fn flag` intern is legal). Focused `#eval run` ok.
**Not** formal TST-SEM-002.

Track F corpus holes listed above are now pinned. Later slices below remain
product/formal decisions.

## Later slices (do not start here)

1. SPEC honesty ADR: document typed external-call return values or keep formal
   corpus void-only forever.
2. `TASK-D2-06` / `TST-SEM-001` canonical `.pfsem` / `.pfprov` formal path.
3. EV binding of `pf.reference-outcome.v1` (product decision; not a silent
   `registryDigest`).
4. C-3 / Anvil lossless — remains fail closed.

## Non-claims

No formal TASK/TST status change. No Anvil lossless. No second reference
machine. No accepted-PRD expansion.
