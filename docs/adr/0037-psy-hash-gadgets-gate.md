---
id: ADR-0037
title: Psy hash gadgets — design gate (not yet emitted)
status: proposed
date: 2026-08-10
---

# ADR-0037: Psy hash gadgets design gate

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
**PF emitter does not push them today.** There is no ProgramV1 / language surface
(`hash`, `poseidon`, …) and no capability row that admits them.

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
