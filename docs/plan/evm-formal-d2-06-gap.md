---
id: PLAN-EVM-FORMAL-D2-06-GAP
title: EVM formal lighthouse — TASK-D2-06 / TST-SEM-001 gap
status: draft
owner: engineering
updated: 2026-08-14
normative: false
---

# EVM formal lighthouse：D2-06 gap

> Engineering inventory only. Does **not** close `TASK-D2-06`, `TST-SEM-001`,
> `TST-PROOF-001`, or any EV/qualification object. Does **not** invent a new
> `TASK-*`. `TASK-D2-07` remains blocked on this task.

Authority: [`04-task-breakdown.md`](../04-task-breakdown.md) `TASK-D2-06` →
[`05-test-spec.md`](../05-test-spec.md) `TST-SEM-001` / `TST-PROOF-001` ·
[`semantic-program-wire.md`](../specs/semantic-program-wire.md) · ADR-0036.

## Why this cannot be marked formal-done

| Blocker | Fact |
|---|---|
| Evidence | Formal closeout needs EV retained-artifact digest binding of canonical `.pfsem` / `.pfprov`. Production encoders exist; no formal EV object. |
| Qualification | `TASK-D1-01` still blocked; recovery forbids inventing freeze/EV ceremony. |
| Proof join | `TST-PROOF-001` requires `TST-SEM-001` first, then immutable proof-bundle theorem ↔ closed `SemanticProgramV1` definitional equality. Inline ADR-0027 is engineering-only. |
| Dependency | `TASK-D2-07` / `TST-SEM-002/003` stay pending until this task is formal-done. |

## Engineering already pins

`NormalizeV1` is the sole `.pfsem` / `.pfprov` mint path
(`normalizeProgramV1` / `normalizeProgramWithProvenanceV1`).
`semanticHashV1` = SHA-256(canonical bytes) after structure gate.
`semanticProvenanceDigestV1` validates then hashes the provenance envelope.
CheckV1 / ProofSubject suites cover join, origin substitution, carrier
substitution, and re-normalize stability. **Not** a dedicated TST-SEM-001
shape suite until this slice.

## First fail-closed slice (this wave)

Allowlist: `Tests/Semantic/Sem001ShapeV1.lean` (+ Fast / Tests.lean / lakefile
registration).

1. Same `Source.Program`, two project-relative paths → identical `.pfsem` /
   `semanticHash` / `sourceHash`; `.pfprov` bytes and provenance digest differ.
2. Path-swapped provenance fails `validateSemanticProvenanceV1`.
3. Business change (`+ 2` vs `+ 3`) changes `.pfsem` and `semanticHash`.

**Not** formal TST-SEM-001. Sem001/002/003 are registered in Fast, `Tests.lean`,
and `Tests/Shards/Typed.lean` (ordinary `just ci`). The layout/span-only
companion is now pinned in the same suite.

## Later slices

1. Isolated layout/span-only companion — pinned 2026-08-14 in
   `Sem001ShapeV1` (leading-comment span shift; inventory rebuild accepts;
   `.pfsem`/`semanticHash`/`sourceHash` hold; `.pfprov` moves; span-swapped
   provenance fail closed).
2. EV binding of canonical `.pfsem` / `.pfprov` (product decision).
3. `TST-PROOF-001` after SEM-001 formal path exists.

## Non-claims

No formal TASK/TST status change. No Anvil lossless. No second serializer.
No accepted-PRD expansion.
