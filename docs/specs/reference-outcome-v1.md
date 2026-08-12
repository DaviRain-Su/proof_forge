---
id: SPEC-REF-OUTCOME-001
title: Reference Outcome retained wire (engineering)
status: draft
owner: semantic
updated: 2026-08-12
normative: false
---

# Reference Outcome retained wire v1 (engineering)

> **Engineering packaging prerequisite for TST-SEM-002/003 / TASK-D2-07.**
> Does **not** close formal TASK/TST, EV retained-artifact binding, target
> adapters, or `proof-forge.evidence.v1` observations.

## Purpose

`SPEC-SEM-001` OutcomeV1 carriers are an in-memory executable model. Formal
persisted differential evidence requires a versioned exact tagged envelope.
This document freezes the engineering schema implemented by
`ProofForgeV2.Semantic.OutcomeWireV1`.

## Identifiers

| Field | Value |
|---|---|
| Schema id | `proof-forge.reference-outcome.v1` |
| Magic | `pf.reference-outcome.v1` |
| Module | `ProofForgeV2/Semantic/OutcomeWireV1.lean` |

## Envelope

```text
encodeMagicPrefix(magic) || encodeOutcomeDataV1(outcome)
```

- Full-consume decode; trailing bytes → `.trailingBytes`.
- Carrier decode = transport decode → re-encode → exact byte identity
  (mismatch → `.nonCanonical`).
- Digest = `SHA-256(canonicalBytes)` (`referenceOutcomeDigestV1`).

## Outcome body tags

| Tag | Fields (source order) |
|---|---|
| `returned` | `logicalState`, `option(value)`, `array(effect)` |
| `reverted` | `reason`, `logicalState` |
| `trapped` | `fault`, `logicalState` |

### Leaves

- `logicalState` → `bool initialized` + `bytearray canonicalValues`
- `value` → `u32 typeId` + `bytearray valueBytes`
- `occurrence` → `u32 effectId` + `u32 occurrence`
- `effect` → `occurrence` + payload (`event` / `externalCall` / `schedule`)
- `reason` → `declared` / `standard` / `externalCallReverted`
- `fault` / `standard` → closed `u8` tables (declaration order)

Framing reuses WireV1 tagged/magic/array helpers. Program-relative
valueBytes validation remains the caller's responsibility
(`StateConformsV1` / Reference step).

## Non-claims

- Not formal TASK-D2-07 / TST-SEM-002/003 completion.
- Not EV catalog retained-artifact digest binding.
- Not an EVM/Solana/NEAR/… → OutcomeV1 adapter.
- Not a replacement for evidence v1 observation projections.
