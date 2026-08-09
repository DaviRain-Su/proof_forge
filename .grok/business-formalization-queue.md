# Business formalization queue (track 1)

**Authority:** ADR-0034 D10 · INV-2 · Agents Next task · RESEARCH-023  
**Mode:** autonomous runner — do **not** wait for the user to say continue  
**Sole step:** `SemanticProgramV1 → admitReferenceProgramSliceV1 → stepReferenceSliceV1`  
**Forbidden:** second State/Effect/step · MiniAmm platform special-case · supersede ADR-0027 · formal TASK/TST claims · push unless user later asks

## Status legend

- `pending` / `in_progress` / `done` / `blocked`

## Wave 1–2 — drained (EvenCounter + ZeroCounter)

| id | status |
|---|---|
| bf-pack-1/2, bf-unpin-1, bf-docs-1 | done |
| bf2-data/preserve/product/docs (ZeroCounter) | done |

## Wave 3 — MiniAmm L1 P1 (empty pool)

P1 (RESEARCH-023): `totalSupply == 0 → reserve0 == 0 ∧ reserve1 == 0`  
Surface: `Examples/MiniAmmL1.lean` (full vault-internal MiniAmm + executable `emptyPool`; deployable no-inv `Examples/MiniAmm.lean` unchanged).

| id | status | objective |
|---|---|---|
| bf3-surface | done | Ship `Examples/MiniAmmL1.lean` with executable `emptyPool`; product `check` ok |
| bf3-admit-docs | done | Reference admit suite + focused `Tests.Semantic.MiniAmmL1Admit` (18470B carrier); INV-2/Agents/queue wave-3 open |
| bf3-preserve | in_progress | **GREEN** data 2342B + `structure_ok` + `encode_ok` + admission + production decode bridge + triple UInt64 foundation packing（`705e43908`/`310d3196b`）。**Residual（runner 注意：勿重复翻这块）**：multi-state clear/get `stepReferenceSliceV1` ready micro-path（类 ZeroCounter 的 `stepReferenceSliceV1_ready_clear_returned`，但 3-state overlay）+ emptyPool eval returnedTrue + full `PreservationTheoremV1` in `MiniAmmEmptyPoolPreservationV1`（新文件） |
| bf3-product | pending | same-file `proof emptyPool preserving` + InlineProofCertifier positive（ZeroCounter 已有模板）；ClosedSubjectPin 可选 |
| bf3-docs | pending | ADR/research/Agents closeout |

## Done criteria (wave 3)

All bf3-* done; EvenCounter + ZeroCounter still GREEN; MiniAmmL1 P1 product preserving certified (or honest partial bar); no MiniAmm-only step; ADR-0027 not superseded.

## Runner notes

1. Prefer product path + Reference; reuse PreservationPackagingV1.
2. Do not put nonempty inv on deployable `Examples/MiniAmm.lean` unless product decision says so — L1 proof surface is MiniAmmL1.
3. One slice per fire; **never** restart a `done`/`in_progress` slice from scratch. Read the residual note and continue it.
4. If a slice keeps cycling (>2 commits on same id), mark it `blocked` with the exact failing theorem and move on; do not loop 4× on one id.
5. Local commit only; update this table.
6. Goal: `/goal @.grok/goals/prompt-business-formalization.md`  
   Workflow: `/workflow business-formalization-drain`
7. Inline same-file (ADR-0027/0034): business theorem must live in same source as `program`; ProofInstances is lemma library only.
