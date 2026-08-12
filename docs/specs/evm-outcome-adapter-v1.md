---
id: SPEC-EVM-OUTCOME-ADAPTER-001
title: EVM → OutcomeV1 engineering adapter (slice-4)
status: draft
owner: semantic
updated: 2026-08-12
normative: false
---

# EVM → OutcomeV1 engineering adapter v1

> **Engineering lighthouse slice-4.** Does **not** close formal TASK-D2-07 /
> TST-SEM-002/003 / C-3, Anvil target refinement, or EV retained-artifact binding.

## Purpose

Bridge Reference↔Anvil corpus legs toward structural Outcome equality without
pretending `proof-forge.evm-observation.v1` is Outcome wire.

| Carrier | Role |
|---|---|
| `OutcomeV1` / `pf.reference-outcome.v1` | Structural Reference outcome + retained digest (`OutcomeWireV1`) |
| `proof-forge.evm-observation.v1` | Evidence-style shared + optional EVM raw (NOT Outcome) |
| `proof-forge.evm-outcome-projection.v1` | Honest subset projected from `shared` for cross-leg compare |

## Lossless vs fail-closed

### Lossless (Reference-only OutcomeWire)

Lean `stepReferenceSliceV1` yields in-process `OutcomeV1`. For digest-listed
primitive cases the Reference corpus runner mints:

- `reference-outcome-{step}.bin.hex` — exact `pf.reference-outcome.v1` envelope
- `reference-outcome-{step}.digest` — `SHA-256(envelope)` (64 lowercase hex)

**Digest-listed cases (slice-4):**

| Case id | Steps | Notes |
|---|---|---|
| `pf.primitive.statecell.overflow-hold.v1` | 6 | slice-2b |
| `pf.primitive.accumulator.overflow-hold.v1` | 6 | slice-2b |
| `pf.primitive.arithops.bitnot-scale.v1` | 6 | slice-3 |
| `pf.primitive.eventflow.emit-cap.v1` | 5 | slice-4 (emit + declared Cap rollback) |

Carrier re-encode identity is checked in Lean before write. Python
`validate-outcome-digests` / `validate_outcome_digest_tree` joins digest↔bytes
+ magic presence for every listed case/step. Missing digest or envelope for a
listed case → `PF-CORPUS-OUTCOME`.

OwnableLike Reference steps remain shared-observation-only (no OutcomeWire
sidecars) until an admit/step surface can mint without invention.

### Honest projection subset (both legs)

From observation `shared` only:

| Field | Mapping |
|---|---|
| `status=success/revert/trap` | `kind=returned/reverted/trapped` |
| `logicalState` | as-is JSON object |
| `returnValue` | retained only for `returned`; must be `null` on revert/trap |
| `effects` | collapsed to `effectsEmpty` bool |
| `rollbackEqual` | as-is |

Do **not** invent `standardRevertCode`, declared error args, fault constructors,
typed valueBytes, or effect occurrence pairs from Anvil/observation.

### Mandatory projection equality (pass closure, slice-3)

For **every** required pass-leg pair on the same step, `close_case` compares
`outcome_projection_compare_key` across legs. Mismatch → `PF-CORPUS-OUTCOME`.

On digest-listed cases, pass closure additionally requires:

1. Reference OutcomeWire sidecars present and digest-validated for all listed steps
2. Every required pass-leg step successfully projects (malformed shared →
   `PF-CORPUS-OUTCOME`)
3. Projection equality reference↔`pf-anvil` is **mandatory** (not soft / not
   skippable when both legs pass)

Shared exact equality for `primitive` class remains a separate
`PF-CORPUS-INVARIANT` gate; Outcome projection is the honest subset compare and
may fail closed even when shared JSON would otherwise match (e.g. revert with
non-null `returnValue`).

### Fail closed (still cannot invent OutcomeWire from observation)

Observation / Anvil lack:

1. `canonical-logical-state-bytes`
2. `typed-return-value` (`typeId` + `valueBytes`)
3. `semantic-revert-reason` (declared args / standard code / externalCallReverted)
4. `semantic-fault`
5. `effect-occurrence-pairs`
6. `declared-error-args`

`try_mint_outcome_wire_from_observation` always returns `PF-CORPUS-OUTCOME`.
Do **not** silently drop declared error args, fault constructors, or effect
occurrence pairs to force equality. Anvil **↛** OutcomeWire lossless encoding.

`status=blocked` is corpus-only and cannot project to an Outcome constructor.

## Expected engineering negatives

| Failure | Stable code | Owner surface |
|---|---|---|
| Missing `reference-outcome-{i}.digest` / `.bin.hex` for digest-listed case | `PF-CORPUS-OUTCOME` | `validate-outcome-digests` / sidecar helpers |
| Digest ≠ `SHA-256(envelope)` or missing magic | `PF-CORPUS-OUTCOME` | same |
| Projection kind / compare-key mismatch across pass legs | `PF-CORPUS-OUTCOME` | `close_case` |
| Revert/trap with non-null `returnValue` | `PF-CORPUS-OUTCOME` | `project_outcome_from_shared` |
| Observation→OutcomeWire mint attempt | `PF-CORPUS-OUTCOME` | `try_mint_outcome_wire_from_observation` |
| `status=blocked` projection | `PF-CORPUS-OUTCOME` | projection |

Disk JSON under `schema-tests/negative/` remains case/observation schema shape
coverage; Outcome sidecar / projection gates are harness self-tests +
`validate-outcome-digests` (not a second JSON schema authority).

## Wiring

- Lean: `Tests/Materialization/EvmCorpusPrimitiveV1.lean`
  (StateCell/Accumulator/ArithOps/EventFlow sidecars) +
  `Tests/Materialization/EvmOutcomeAdapterV1.lean` (focused mint)
- Python: `scripts/evm_corpus_v1.py` — `OUTCOME_DIGEST_CASE_STEPS`, projection /
  FC mint / sidecar gate / `close-case` projection equality
- Reference recipe: `scripts/evm_corpus_reference.sh` → `validate-outcome-digests`

## Non-claims

- Not formal TST-SEM-002/003 or TASK-D2-07.
- Not Anvil→OutcomeWire lossless encoding.
- Not a second Outcome schema (reuses `OutcomeWireV1` only).
- Not formal C-3 Reference↔Anvil identity-bound differential.
- OwnableLike remains without OutcomeWire sidecars in this slice.
