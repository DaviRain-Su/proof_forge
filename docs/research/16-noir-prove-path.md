---
id: RPT-016
title: C-4 Noir prove/verify path availability research
status: draft
owner: engineering
updated: 2026-08-03
normative: false
---

# C-4: Noir Nargo / prove path — promote acceptance gate?

## Question

Can ProofForge promote a **real** Noir prove/verify acceptance gate
(compile → witness → prove → verify), or must maturity stay **source-only**
(relation packages + Lean relation model)?

## Method

The original code-first audit ran on 2026-08-02: Noir target leaf, dossier
`07-noir.md`, artifact validator `scripts/validate_artifacts.py`, Tool Lock /
`supply-chain/*` inventory, and ambient-host `nargo` presence. No network install
was performed in that slice.

## 2026-08-03 follow-up（current status）

Wave 1 / G123 subsequently pinned nargo `1.0.0-beta.26` in both Tool Lock v4
files and registered `Tests.Materialization.NoirCompileAcceptance` plus
`scripts/noir_compile_acceptance.sh`. The engineering gate materializes product
Counter relation packages and runs `nargo compile`; it clean-skips when the
locked tool has not been materialized. This supersedes the original “no nargo
pin / no compile gate” observation.

It does **not** add Barretenberg (`bb`) or another proving backend, a CRS/security
profile, witness execution, prove/verify, or proof-stage product artifacts.
Accordingly, the original decision **not to promote prove/verify maturity** is
unchanged.

## Current in-tree engineering facts

| Surface | Status |
|---|---|
| Capability Plan / IR / emitter | Present (`Targets/Noir/*`) |
| Product materialize | `Nargo.toml` + `src/main.nr` per relation + `*.noir-relations.json` |
| Lean relation model | `Tests/Materialization/NoirRelationModel` — **not** Nargo/ACIR execution |
| Compile-only gate | Locked nargo `1.0.0-beta.26`; registered `NoirCompileAcceptance`; engineering-only, tool-absent clean skip |
| Artifact validator | Source-only bundle; **forbids** `.acir`/`.proof`/`.vk`/`.witness`; non-deployable |
| Profile | `noir-source-u64-relations-v1` / dialect `noir-native-u64-relations-v1`; `proofStatus=not-produced` |
| Tool Lock / supply-chain | nargo pinned for compile-only; `barretenberg=null`; no proving backend or CRS profile |

## Upstream toolchain boundary

- Nargo owns Noir compile/execute/prove/verify workflow; a proving backend such
  as Barretenberg is selected separately.
- A proof-capable product gate still needs an exact backend version/digest,
  CRS/security profile, witness and negative-case contract, proof/public-input
  binding, and fail-closed verification.
- Dossier `07-noir.md` requires future `noir-acir-proof-v1` to carry arithmetic,
  CRS, soundness, proof-binding, and privacy contracts. A locked compiler alone
  is insufficient.

## Recommendation

**Do not promote** a Noir prove/verify acceptance gate.

| Decision | Detail |
|---|---|
| Maturity stays | **source-only** Plan/IR + relation source packages |
| Compile-only | Engineering gate present with locked nargo; not ACIR/witness/proof evidence |
| Why prove remains blocked | No locked proving backend, CRS/security profile, witness/prove/verify path, or proof artifact binding; validator intentionally rejects proof-stage leaves |
| Follow-on (only after product decision) | Design `NoirProveAcceptance`: lock backend + CRS/security contract, run compile/witness/prove/verify with positive and negative cases, bind outputs to semantic/profile/plan identity, then review a successor profile |

## Explicit non-claims

- Not formal `TST-NOIR-*` completion.
- Not hermetic Stage-0 or release-qualification evidence.
- Not a claim that compile-only acceptance validates circuit soundness.
- Does **not** change product emitters to emit ACIR, witness, proof, or VK files.

## Decision table（current）

| Gate | Status | Notes |
|---|---|---|
| `nargo compile` | **Engineering gate present** | nargo `1.0.0-beta.26`; Counter relation packages; clean skip when tool is not materialized |
| witness execute | **No** | no witness contract/backend integration |
| prove / verify | **No** | no backend pin, CRS/security profile, or proof binding |
| Lean relation model | **Keep** | engineering structure model only |
| Maturity label | **source-only** (unchanged) | compile-only does not promote proof maturity |
