---
id: SPEC-EVM-OUTCOME-ADAPTER-001
title: EVM → OutcomeV1 engineering adapter (slice-2b)
status: draft
owner: semantic
updated: 2026-08-12
normative: false
---

# EVM → OutcomeV1 engineering adapter v1

> **Engineering lighthouse slice-2b.** Does **not** close formal TASK-D2-07 /
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

### Lossless (Reference-only)

Lean `stepReferenceSliceV1` yields in-process `OutcomeV1`. For StateCell and
Accumulator overflow-hold steps the Reference corpus runner mints:

- `reference-outcome-{step}.bin.hex` — exact `pf.reference-outcome.v1` envelope
- `reference-outcome-{step}.digest` — `SHA-256(envelope)` (64 lowercase hex)

Carrier re-encode identity is checked in Lean before write. Python validates
digest↔bytes join + magic presence (`validate-outcome-digests`).

### Honest projection subset (both legs)

From observation `shared` only:

| Field | Mapping |
|---|---|
| `status=success/revert/trap` | `kind=returned/reverted/trapped` |
| `logicalState` | as-is JSON object |
| `returnValue` | retained only for `returned`; must be `null` on revert/trap |
| `effects` | collapsed to `effectsEmpty` bool |
| `rollbackEqual` | as-is |

Compared across required pass legs inside `close_case`.

### Fail closed (cannot invent OutcomeWire from observation)

Observation lacks:

1. `canonical-logical-state-bytes`
2. `typed-return-value` (`typeId` + `valueBytes`)
3. `semantic-revert-reason` (declared args / standard code / externalCallReverted)
4. `semantic-fault`
5. `effect-occurrence-pairs`
6. `declared-error-args`

`try_mint_outcome_wire_from_observation` always returns `PF-CORPUS-OUTCOME`.
Do **not** silently drop declared error args or fault constructors to force
equality.

`status=blocked` is corpus-only and cannot project to an Outcome constructor.

## Wiring

- Lean: `Tests/Materialization/EvmCorpusPrimitiveV1.lean` (StateCell/Accumulator
  sidecars) + `Tests/Materialization/EvmOutcomeAdapterV1.lean` (focused mint)
- Python: `scripts/evm_corpus_v1.py` projection / FC mint / sidecar gate /
  `close-case` projection equality
- Reference recipe: `scripts/evm_corpus_reference.sh` → `validate-outcome-digests`

## Non-claims

- Not formal TST-SEM-002/003 or TASK-D2-07.
- Not Anvil→OutcomeWire lossless encoding.
- Not a second Outcome schema (reuses `OutcomeWireV1` only).
- EventFlow / OwnableLike / ArithOps Reference steps still emit shared
  observations without OutcomeWire sidecars in this slice (residual).
