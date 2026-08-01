---
id: RPT-015
title: C-2 Aleo/Psy compiler and VM availability research
status: draft
owner: engineering
updated: 2026-08-02
normative: false
---

# C-2: Aleo Leo compiler / Psy VM — promote acceptance gates?

## Question

Should ProofForge promote **real** compiler/VM acceptance gates for `aleo` and
`psy` (analogous to EvmSolc / Solana Mollusk / NearWasmAcceptance), or keep
**source-only** maturity?

## Method

Code-first audit of in-tree target leaves and product materialize path
(2026-08-02 HEAD), plus dossier claims in `docs/targets/09-aleo.md` /
`10-psy.md` and coverage matrix `12-target-coverage-matrix.md`.  
**No** live network deploys; **no** claim of hermetic tool lock.

## Aleo (`TargetId.aleo`)

### In-tree engineering facts

| Surface | Status |
|---|---|
| Capability Plan / IR / emitter | Present (`Targets/Aleo/*`) |
| Product materialize | Emits Leo-oriented **source package** files |
| Tests | `Tests/Materialization/Aleo.lean` — plan/IR validate + files |
| Coverage | B-1c AleoCoverage: scalar UInt64 envelope LOWERED; Field FAIL-CLOSED (BLS12-377 Fr ≠ catalog bn254); aggregates/ContextRead/emit/call FC |
| Real `leo` compile gate | **Absent** — no pinned `leo` version in Tool Lock product path, no CI step `leo build` |

### Compiler/VM availability (research)

- Public Leo 4.x / snarkVM tooling exists upstream, but this repo does **not**
  pin a cargo-git/binary asset for `leo` under Tool Lock v4 product supply.
- Engineering acceptance would require at minimum: pinned Leo patch +
  deterministic `leo build` (or equivalent) on materialize staging, skip-clean
  when absent, fail-closed on non-zero (pattern of EvmSolc / NearWasm).
- Field mismatch (native Aleo field ≠ ProofForge bn254 Fr catalog) remains a
  product semantic lock; a compile gate must not paper over it.

### Recommendation

**Do not promote** an Aleo compiler acceptance gate in the current wave.

- Maturity stays **source-only** (plan/IR/source package).
- Next step if product prioritizes Aleo: design `AleoLeoAcceptance` gate under
  Tool Lock pin + Field fail-closed regression, separate backlog ID.

## Psy (`TargetId.psy`)

### In-tree engineering facts

| Surface | Status |
|---|---|
| Capability Plan / IR / emitter | Present (`Targets/Psy/*`) |
| Product materialize | Source-oriented packages |
| Field | Psy Felt = Goldilocks — **FAIL-CLOSED** vs bn254 catalog (documented) |
| Real psy-vm / prover gate | **Absent** |

### Compiler/VM availability (research)

- Psy public materials remain pre-testnet / provisional; dossier
  `10-psy.md` states research snapshot only, no supported toolchain.
- No in-repo pin of a Psy compiler or local proving VM suitable for CI
  skip/fail-closed pattern.

### Recommendation

**Do not promote** a Psy VM acceptance gate.

- Keep design-only / source-only posture.
- Revisit only after: stable versioned schema, licensed tool pin, and a
  minimal local MWE that can be skip-clean or fail-closed in ordinary CI.

## Decision table (C-2 outcome)

| Target | Promote acceptance gate now? | Maturity stays |
|---|---|---|
| aleo | **No** | source-only Plan/IR/source package |
| psy | **No** | source-only / research |

## Explicit non-claims

- Not formal Stage-0 / hermetic evidence.
- Not a claim that Leo/Psy cannot be productized later.
- Not an upgrade of AGENTS maturity beyond “source-only” for Aleo/Psy.

## Follow-on (not this slice)

1. If Aleo is prioritized: Tool Lock asset + `AleoLeoAcceptance` suite ID.
2. If Psy is prioritized: re-open dossier with live tool MWE before any gate.
3. Coverage matrix C-2 row → closed as **researched, no promote**.
