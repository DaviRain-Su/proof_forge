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
| bf-pack-1 | pending | Extract **program-agnostic** preservation packaging lemmas from `EvenCounterPreservationV1` into a new shared module under `ProofForgeV2/Semantic/` (suggested name `PreservationPackagingV1.lean`). Candidates: gate-ready packaging from returned outcomes, post=pre returned arm, uint64 size-from-validate, failure-arm / Outcome unchanged helpers that do not mention EvenCounter constants. Import from ProofInstances; keep EvenCounter product GREEN. |
| bf-pack-2 | pending | Refactor `EvenCounterPreservationV1` to **consume** shared packaging lemmas; delete duplicate instance-local copies when defeq-safe; `lake build` instance + `Tests.Compiler.InlineProofCertifierV1` still GREEN. |
| bf-unpin-1 | pending | Harden **non-pin** author path: document + (if needed) test that unpinned programs prove `PreservationTheoremV1 subjectProgramV1 ordinal` via generic/eq-bytes lemmas without requiring `ClosedSubjectPinV1` table growth. Pin remains golden accelerator only. |
| bf-docs-1 | pending | Sync INV-2 / Agents Active·Next / ADR-0034 status / research-023 after packaging + unpin slices; `just docs-check`; no formal overclaim. |

## Done criteria (program complete)

All four rows `done`, worktree clean, EvenCounter preserving product still certified, ADR-0027 still not superseded.

## Runner notes

1. One slice per fire when possible; never expand into MiniAmm or second AMM instance.
2. Second non-AMM instance remains **deferred** (not in this queue).
3. After each green slice: local commit only (no push); update this table status.
4. If blocked, write reason under the row and stop that slice; next fire re-reads this file.
