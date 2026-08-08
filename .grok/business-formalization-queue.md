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

## Wave 1 (packaging / pin / docs) — drained

| id | status | objective |
|---|---|---|
| bf-pack-1 | done | PreservationPackagingV1 extract |
| bf-pack-2 | done | EvenCounter consumes packaging |
| bf-unpin-1 | done | non-pin author path + suite |
| bf-docs-1 | done | docs/Goal/workflow sync |

## Wave 2 — second non-AMM instance (ZeroCounter, P: count==0)

| id | status | objective |
|---|---|---|
| bf2-data | done | Closed `ZeroCounterV1` data + 1499-byte spine + `structure_ok` + `encode_ok` + admission decide; different P from EvenCounter; suite `Tests.Semantic.ZeroCounterV1` |
| bf2-preserve | pending | `ZeroCounterPreservationV1`: base + full `PreservationStepV1` + `preservation_theorem` reusing packaging; no second step machine |
| bf2-product | pending | Product source alignment + optional pin + InlineProofCertifier product-positive for ZeroCounter |
| bf2-docs | pending | INV-2 / Agents / ADR-0034 / research-023 second-instance status; docs-check |

## Done criteria (wave 2)

All bf2-* `done`, EvenCounter still GREEN, ZeroCounter preserving product certified (or explicit partial bar documented), ADR-0027 not superseded.

## Runner notes

1. One slice per fire when possible; never MiniAmm in this wave.
2. After each green slice: local commit only (no push); update this table.
3. Prefer Goal `/goal @.grok/goals/prompt-business-formalization.md` or `/workflow business-formalization-drain` (update prompts to read wave 2 rows).
