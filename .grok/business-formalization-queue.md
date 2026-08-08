# Business formalization queue (track 1)

**Authority:** ADR-0034 D10 · INV-2 · Agents Next task  
**Mode:** autonomous runner — do **not** wait for the user to say continue  
**Sole step:** `SemanticProgramV1 → admitReferenceProgramSliceV1 → stepReferenceSliceV1`  
**Forbidden:** second State/Effect/step · MiniAmm special-case · supersede ADR-0027 · formal TASK/TST claims · push unless user later asks

## Status legend

- `pending` — next work
- `in_progress` — runner claimed
- `done` — committed green
- `blocked` — needs human (record reason; skip to later only if independent)

## Queue (strict order)

| id | status | objective |
|---|---|---|
| bf-pack-1 | done | Extract **program-agnostic** preservation packaging lemmas from `EvenCounterPreservationV1` into a new shared module under `ProofForgeV2/Semantic/` (suggested name `PreservationPackagingV1.lean`). Candidates: gate-ready packaging from returned outcomes, post=pre returned arm, uint64 size-from-validate, failure-arm / Outcome unchanged helpers that do not mention EvenCounter constants. Import from ProofInstances; keep EvenCounter product GREEN. **GREEN 2026-08-09** committed: `PreservationPackagingV1` + EvenCounter thin wrappers + SBOM pin + focused lake builds exit 0. |
| bf-pack-2 | done | Refactor `EvenCounterPreservationV1` to **consume** shared packaging lemmas; delete duplicate instance-local copies when defeq-safe; `lake build` instance + `Tests.Compiler.InlineProofCertifierV1` still GREEN. **GREEN 2026-08-09** uncommitted per runner: deleted thin aliases (`preservation_step_failure_arms` / `step_returned_implies_gate_ready` / `preservation_step_returned_post_eq_pre`); step/get-returned call packaging directly; focused lake builds exit 0. |
| bf-unpin-1 | done | Harden **non-pin** author path: document + test that unpinned programs prove via packaging / eq-bytes without pin table growth. Pin remains golden accelerator only. **GREEN 2026-08-09**: ClosedSubjectPin/PreservationPackaging author recipe docs; `Tests.Semantic.ClosedSubjectPinV1` pin miss + eq-bytes transport. |
| bf-docs-1 | done | Sync INV-2 / Agents Active·Next / ADR-0034 status after packaging + unpin; `just docs-check`; no formal overclaim. **GREEN 2026-08-09** docs + Goal/workflow autonomous drain entry. |

## Done criteria (program complete)

All four rows `done`, worktree clean, EvenCounter preserving product still certified, ADR-0027 still not superseded.

## Runner notes

1. One slice per fire when possible; never expand into MiniAmm or second AMM instance.
2. Second non-AMM instance remains **deferred** (not in this queue).
3. After each green slice: local commit only (no push); update this table status.
4. If blocked, write reason under the row and stop that slice; next fire re-reads this file.
