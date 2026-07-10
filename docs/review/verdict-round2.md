# Round-2 Product-Readiness Gap Review — Verdict

**Date:** 2026-07-10
**Branch:** `main` (dirty: `docs/zh/INDEX.zh.md`, `scripts/i18n/manifest.json`, `scripts/near/target-first-smoke.sh`, `docs/review/` untracked)
**Reviewer:** verifier / quality-review subagent
**Verdict:** **NEEDS_DEEPER**

---

## 1. Are the reports fair, evidence-based, and complete enough?

**Fairness / evidence:** The seven reports are **mostly fair and well-evidenced**. They cite concrete files and line ranges, and several claims were spot-checked successfully:

- `ProofForge/Target/BackendRegistry.lean:79-95` confirms only `evm`, `solana-sbpf-asm`, and `wasm-near` have `validateModule?` / `ensurePlan?` / `ensurePackage?` hooks.
- `ProofForge/Cli/TargetFirst.lean:167-221` confirms the target-first surface still rewrites `build`/`emit` to legacy flags and explicitly stubs `check` as unimplemented.
- `ProofForge/Cli/Deploy.lean:444-445` confirms deploy is EVM-only.
- `ProofForge/Cli/Check.lean:204-231` confirms honest fail-closed behavior for fixture-only/research targets.
- `README.md:103` and `AGENTS.md:73` do use the incorrect `--module contract` example.
- `git tag -l` returns no release tags; no `CHANGELOG*`, `Dockerfile*`, or release workflow exists.
- `.gitignore` does not protect `.env`, keypairs, mnemonics, or PEM files.
- `scripts/i18n/check-sync.sh` reports 4 docs needing translation.
- `ProofForge/Backend/Refinement/ConstructorCoverage.lean` shows `arrayLit`, `structLit`, all `crosscallInvoke*` constructors, and unbounded loops marked as outside the proved fragment.

**Completeness / missing dimensions:** The seven reports cover backend maturity, FV boundaries, CLI/UX, testing/CI, SDK ecosystem, documentation/onboarding, and production operations — a reasonable spread. However, several important cross-cutting concerns are **under-covered or absent**:

- **Security / supply-chain hardening:** No dedicated dimension for audit surface, fuzzing, dependency CVE scanning, SLSA/SBOM, or secret-scanning (only ops briefly notes secrets).
- **Performance / compiler latency & output size:** Not covered at all.
- **Data privacy / compliance:** None.
- **Accessibility / i18n beyond Chinese:** Only the docs report mentions i18n; there is no i18n quality framework or coverage of other languages.
- **Community / support / escalation model:** None.

**Recommendation:** Add at least a lightweight security/supply-chain dimension and a performance/resource dimension in the next round.

---

## 2. Factual inconsistencies and contradictions

| # | Inconsistency | Evidence / notes |
|---|---------------|------------------|
| 1 | **`check` semantics are contradictory across reports.** The CLI/UX report lists `check` as healthy and producing structured JSON/text reports (`ProofForge/Cli/Check.lean:36-128`), while the backend report notes the target-first `check` is stubbed (`ProofForge/Cli/TargetFirst.lean:219`). The reports never reconcile that `check` works via the *legacy* parser path but is *unimplemented* in the documented target-first surface. | Backend and CLI reports should align on whether `check` is a supported product verb. |
| 2 | **Scoring optimism mismatch.** Backend-target maturity scores **6/10** and docs **6/10**, while CLI, SDK, and production ops all score **4/10**. A product with only 3 real backends, legacy-routed CLI, no published packages, and no release artifacts arguably cannot rate two dimensions at 6/10 while the user-facing surface is at 4/10. | Rescore with a single rubric, or explain why backend/docs are independently more mature than the product experience they support. |
| 3 | **Target roster claims are not reconciled.** The backend report says Move/Sui is Counter-only and source-fail-closed; the SDK report notes a generated Sui TypeScript client. The two claims are individually true but read as conflicting product signals unless explicitly tied to the *emit/fixture* path vs. the *contract-source* path. | Add a per-target capability table that separates `build`, `check`, `emit --fixture`, `deploy`, and `client` support. |
| 4 | **CLI/UX "healthy" table may overstate target-first completeness.** It lists target-first verbs as "exist and tested" but the same report later admits `check` is unimplemented and the path translates to legacy flags. | Reclassify target-first verbs as partial/MVP rather than healthy. |
| 5 | **FV vs product surface gap is stated but not quantified.** The FV report says the proved fragment is Counter-shaped, but does not map which of the documented product examples (Ownable, Token, Vault, RemoteCall, StakingVault, RoleGatedToken) fall inside vs. outside. | Produce a concrete capability→example→proof-coverage mapping. |

No material contradictions in *evidence* were found; the conflicts are in **interpretation, scoring, and scope boundaries**.

---

## 3. Top 3 areas needing deeper investigation

1. **CLI target-first completion and honest target roster**
   - The documented product path is `build|emit|check --target <id>`, but target-first still rewrites to legacy flags and `check` is unimplemented (`ProofForge/Cli/TargetFirst.lean:219`).
   - 10 targets are listed by `--list-targets`; only 3 have real backend hooks.
   - **Investigation needed:** Exact migration plan to native registry-driven dispatch; which targets must be demoted to `research`/`spike`; what the supported matrix should advertise to users.

2. **Formal-verification boundary vs. advertised product surface**
   - FV proves only a narrow fragment (`storageScalar/Map`, `callerSender`, events, conditional, checked arithmetic, assertions). Auth, crosscall, arrays/structs, unbounded loops, Token/RoleGated/StakingVault constructs are outside.
   - **Investigation needed:** Map each documented product example to its FV coverage status; decide whether to shrink the advertised surface or expand the proved fragment; clarify what assurance users actually receive per build.

3. **Release / distribution and external-developer first run**
   - No release tags, no published SDK packages, README/AGENTS first command is broken (`--module contract`), Chinese docs have broken links, and `lake update` in a scaffolded project can time out.
   - **Investigation needed:** Define the minimum viable release artifact set, a correct onboarding script/test, an i18n link-checker gate, and a concrete release schedule or pilot scope.

---

## 4. Overall verdict and rationale

**Verdict: NEEDS_DEEPER**

The seven reports are a solid first pass: evidence is generally accurate, line references are specific, and the dimensions cover the major product-readiness concerns. However, the round is **not yet sufficient for a production-readiness sign-off** because:

- The reports contain **internal contradictions** around whether `check` is a supported product verb and whether target-first verbs are "healthy."
- **Scoring is inconsistent** across dimensions, making it hard to judge the true overall maturity.
- The **user-facing product boundary** is not crisply separated from research spikes, legacy fixtures, and formal-verification fragments.
- Two important cross-cutting dimensions — **security/supply-chain** and **performance/resource usage** — are missing or only touched in passing.

**Recommended follow-up:** Produce a single integrated readiness scorecard that reconciles the CLI/backend/FV claims, rescores with a common rubric, adds security and performance dimensions, and turns the top-3 investigations above into tracked remediation tickets with owners and acceptance criteria.
