---
id: ADR-0041
title: Psy Commit / public-input binding — fail-closed gate
status: accepted
date: 2026-08-11
owner: engineering
normative: true
---

# ADR-0041: Psy Commit remains fail-closed

## Status

**accepted** (2026-08-11). This ADR freezes the product decision: **do not open
`Op.Commit` / B-COMMIT-ZK on the Psy DPN target** until the checklist below is
met with official authority. No implementation work is authorized by this document.

Related:

- Boundary note: [`docs/targets/psy-p3-context-commit-gate.md`](../targets/psy-p3-context-commit-gate.md)
- Hash gadgets: [ADR-0039](0039-psy-hash-gadgets-gate.md)
- Emitter FC: `ProofForgeV2/Targets/Psy/LowerSemanticV1.lean` (`.commit` → B-COMMIT-ZK)

## Context

ProofForge Psy product materialization is:

1. capability-gated **Plan → DPN package** emission (`.dpn.json`);
2. host-optional official `psy_user_cli simulate` / `psy_vm` for engineering smoke.

It is **not** a full UPS / proof / coordinator product. Semantic Wire already
admits `Op.Commit` as a structure-gated shape on other surfaces. Opening Commit
on Psy as:

- Felt identity passthrough, or
- a silent drop, or
- a session-only “commit” without public inputs,

would **over-claim** a cryptographic commitment that DPN package emission does
not prove.

Official `psy_vm` software evaluate / DPN op surface surveyed for this ADR
(PsyProtocol/psy-node pin used by PF Schema):

- no standalone DPN opcode equivalent to Semantic `Op.Commit`;
- commitment / disclosure semantics live in UPS / circuit / public-input layers
  outside the PF DPN materializer contract.

Therefore Commit is **honestly fail-closed** on Psy today.

## Decision

### D1 — Keep Plan fail-closed

| Surface | Behavior |
|---------|----------|
| Language / Semantic `commit` | Psy Plan rejects with B-COMMIT-ZK diagnostic |
| DPN emitter | No Commit-shaped state cmd or fake public-input slot |
| Session harness | N/A (never reaches session) |
| Coverage | Remain `ContextRead-Commit` / Commit FC until checklist complete |

### D2 — Opening checklist (all required)

Commit may open on Psy **only** after **all** of:

1. **Algorithm ADR** — exact commitment scheme (e.g. Poseidon/Keccak over which
   wires), domain separation, and limb layout.
2. **Public-input layout** — frozen mapping from Commit operands → UPS /
   circuit public inputs (or documented “simulate-only witness” with no
   mainnet claim).
3. **Wire rows** — Semantic requirement ids for Commit on Psy bound to real
   DPN / PI slots (no silent skip).
4. **Official fixture** — `psy_user_cli` / circuit path that executes or
   verifies the binding; session-only is insufficient.
5. **Probe + differential** — PF example + official simulate (or prover)
   matrix green; coverage flip only after 1–4.

Until then, product guidance:

| Need | Guidance |
|------|----------|
| Application state, maps, IMT, events, void call, context ids, hash | Supported Psy subset (probes) |
| Cryptographic Commit / private disclosure binding | Use **Noir** / other circuit target, or wait for checklist |
| EVM-style `msg.sender` / block height | Not Psy addresses; use EVM/Solana or DPN `pf.context.*` ids |

### D3 — Explicit non-goals

- Reimplementing UPS commitment gadgets in Lean or Python session.
- Emitting placeholder Commit ops “for shape only” that claim product semantics.
- Equating Semantic `Op.Commit` with DPN `SetIMT` / hash gadgets.

## Consequences

- P3 gate doc stays **Partial open** for `pf.context.*` only; Commit section
  points here.
- Engineering priority after this ADR: product docs for open surfaces (HashOut
  Array4, IMT, context); **not** Commit emitter work.
- Upstream Psy / official evaluator gaps (Merkle `todo!`, keccak full HashOut
  arrays, context HashOut arrays) are tracked separately; they do **not**
  unblock Commit.

## References

- `LowerSemanticV1` commit FC message (B-COMMIT-ZK)
- `docs/targets/10-psy.md` § fail-closed
- `docs/targets/psy-op-coverage.md` feature backlog `ContextRead-Commit`
