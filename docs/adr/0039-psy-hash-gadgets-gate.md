---
id: ADR-0039
title: Psy hash gadgets — design gate (not yet emitted)
status: proposed
owner: engineering
updated: 2026-08-11
normative: true
---

# ADR-0039: Psy hash gadgets design gate

## Context

Official DPN / `psy_vm` exposes hash-related opcodes (schema pin
`PsyProtocol/psy-node@79e0b824…`):

| op id | name |
|------:|------|
| 21 | `hashNoPad` |
| 22 | `hashPad` |
| 78 | `hashTwoToOne` |
| 81 | `keccak256` |
| 45 | `calculateMerkleRoot` |

ProofForge `SchemaV1.lean` mirrors these wire ids for codec alignment.
**Partial open (2026-08-10):** expression-position
`call pf.crypto.hashNoPad(a0, …, aN)` (N∈1..8) lowers to DPN `hashNoPad` (op 21).
Product ABI returns the **first HashOut limb** as `UInt64` (official simulate).
Other hash ops (`hashPad`, `hashTwoToOne`, `keccak256`, merkle) remain closed.
Session harness **fail-closes** on op 21 — Poseidon authority is official only.

Product work through 2026-08-10 focused on:

- scalar / multi-leaf state (StateCell, Option, Wide, Map)
- control flow (if/match/bounded-for)
- PARTIAL `emit` + void `call`

Claiming hash coverage without a language entry would be dishonest.

## Decision

1. **Keep fail-closed:** unknown / unemitted hash ops stay unsupported in session;
   emitter must not invent `hashNoPad` from unrelated Plan shapes.
2. **Gate opening** behind a concrete language or builtin design, minimum:
   - syntax or stdlib entry (e.g. `pf.crypto.poseidon(xs…)` or fixed-arity `hashNoPad`);
   - exact operand types (Felt / U32 arrays) and return shape (first limb vs HashOut);
   - golden DPN package + official `psy_user_cli simulate` differential;
   - supply-chain note if Poseidon/Keccak parameters are pinned beyond schema.
3. **Do not** expand the Python session into a second crypto VM. Authority remains
   official `psy_vm` / simulate; session only mirrors emitted subsets.

## Consequences

- Coverage report marks hash gadgets as
  `not-emitted-by-PF; no ProgramV1/language surface yet (P2 design gate)`.
- Next implementation PR for hash must include language/Plan admission **and**
  official differential fixtures before flipping the coverage status to covered.
- IMT state commands remain a separate gate (official-only schema; not in
  PF `StateCmdV1`).

## Non-goals (this ADR)

- Implementing Poseidon/Keccak in Lean or Python.
- UPS / proof-system binding for hash public inputs.
- Replacing official `hashTwoToOne` merkle gadgets with custom trees.

## Implemented slice

| Item | Status |
|------|--------|
| Language entry | `call pf.crypto.hashNoPad|hashPad|hashTwoToOne|keccak256(...)` |
| Plan | `Expr.hashNoPad` / `hashPad` / `hashTwoToOne` / `keccak256` |
| DPN | ops 21 / 22 / 78 / 81 |
| Probe | `Examples/HashProbe.lean` |
| Official differential | hashNoPad, hashTwoToOne, keccak256 (nonzero + hash_ops) |
| hashPad official software eval | **gap**: `psy_user_cli simulate` currently returns 0 / hash_ops=0 (emit still correct) |
| Session | fail-closed with ADR-0039 message |

## Full HashOut multi-limb ABI (2026-08-11)

When the call result type is `Array UInt64 4`, **`hashNoPad` / `hashTwoToOne`**
lower to one HashOut-typed DPN op + four `TargetAt` limbs (`Expr.hashOutLimb`),
CSE’d so store+return share a single hash def. Official `psy_vm` software eval
fills `hash_out_arrays` only for those two ops.

- `keccak256` / context pk / sessionRoot: **UInt64 limb0 only** (official does
  not populate full HashOut arrays for TargetAt).
- Scalar `UInt64` path remains first-limb (backward compatible).
- Probe: `Examples/HashOutProbe.lean`.

## Still closed

`calculateMerkleRoot`.

