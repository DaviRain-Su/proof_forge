---
id: RPT-016
title: C-4 Noir prove/verify path availability research
status: draft
owner: engineering
updated: 2026-08-02
normative: false
---

# C-4: Noir Nargo / prove path — promote acceptance gate?

## Question

Can ProofForge promote a **real** Noir prove/verify acceptance gate
(compile → witness → prove → verify), or must maturity stay **source-only**
(relation packages + Lean relation model)?

## Method

Code-first audit (2026-08-02 HEAD): Noir target leaf, dossier `07-noir.md`,
artifact validator `scripts/validate_artifacts.py` Noir path, Tool Lock /
`supply-chain/*` inventory, host `nargo` presence. No network install of
toolchains in this slice.

## In-tree engineering facts

| Surface | Status |
|---|---|
| Capability Plan / IR / emitter | Present (`Targets/Noir/*`) |
| Product materialize | `Nargo.toml` + `src/main.nr` per relation + `*.noir-relations.json` |
| Lean relation model | `Tests/Materialization/NoirRelationModel` — **not** Nargo/ACIR |
| Artifact validator | Source-only bundle; **forbids** proof-stage artifacts; evidence notes no pinned compiler/proving backend |
| Profile | `noir-source-u64-relations-v1` / dialect `noir-native-u64-relations-v1` |
| Tool Lock / supply-chain | **No** nargo / noirc / Barretenberg (or other backend) asset pin |
| Host `nargo` | **Not found** on implementer PATH (`nargo not found`) |

## Upstream toolchain (research, not product pin)

- Public Nargo exists and owns compile/execute/prove/verify workflow; backend
  (e.g. Barretenberg) is selected separately.
- Product gate would need at minimum: exact nargo/noirc + backend versions,
  binary digests, CRS/profile contract, skip-clean when tools absent,
  fail-closed on non-zero — same pattern as EvmSolc / NearWasm / Mollusk.
- Dossier already states future `noir-acir-proof-v1` must carry arithmetic /
  CRS / soundness / proof-binding / privacy contract; bare binary alone is
  insufficient.

## Recommendation

**Do not promote** a Noir prove/verify acceptance gate in the current wave.

| Decision | Detail |
|---|---|
| Maturity stays | **source-only** Plan/IR + relation source packages |
| Why | No Tool Lock pin; no CI prove path; host nargo absent; validator intentionally rejects proof-stage leaves |
| Follow-on (new ID when product prioritizes) | Design `NoirProveAcceptance`: pin nargo+backend under Tool Lock v4+, Counter relation compile+witness+prove+verify skip/fail-closed, then open profile beyond source-only |

## Explicit non-claims

- Not formal `TST-NOIR-*` completion.
- Not hermetic Stage-0 evidence.
- Not a claim that Noir cannot gain prove gates later.
- Does **not** change product emitters to emit fake proof artifacts.

## Decision table (C-4 outcome)

| Gate | Promote now? | Notes |
|---|---|---|
| nargo compile | **No** | no pin |
| witness execute | **No** | no pin |
| prove / verify | **No** | no pin + no CRS contract |
| Lean relation model only | **Keep** | engineering structure check only |
