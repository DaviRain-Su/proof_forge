# ProofForge Integrated Product-Readiness Scorecard

> **Historical baseline:** This scorecard is the pre-remediation 2026-07-10
> snapshot. Several concrete findings below have since been fixed, so its line
> references and blocker states are not current. See the
> [post-review hardening addendum](../superpowers/plans/2026-07-10-post-review-execution.md#post-review-hardening-addendum-2026-07-10)
> for the live remediation ledger and verification evidence.

**Date:** 2026-07-10
**Source:** Synthesis of the 13 review reports in `docs/review/` (gap analyses, deep-dives, and `verdict-round2.md`).
**Verdict:** **Not ready for a real public beta.** The compiler core and primary target triad are solid, but release, security, CLI/UX, SDK, and honest-target-roster blockers must be resolved before external users can install and trust the product.

---

## 1. Dimension Scorecard

| # | Dimension | Maturity | Top Blocker | Status |
|---|-----------|:--------:|-------------|--------|
| 1 | **Backend Target Maturity** | 6 / 10 | Only 3 of 10 listed targets (`evm`, `solana-sbpf-asm`, `wasm-near`) have real `validateModule?`/`ensurePlan?`/`ensurePackage?` backend hooks; the other 7 are Counter-MVP/fixture-only/research spikes. | ⚠️ Credibility gap |
| 2 | **Formal-Verification Boundaries** | 5 / 10 | The only closed `∀ (m : Module)` refinement theorem is for `Counter`; auth, arrays/structs, crosscalls, unbounded loops, Token/RoleGatedToken/StakingVault are outside the proved fragment. | ⚠️ Claims mismatch |
| 3 | **CLI / Authoring UX** | 4 / 10 | `build`/`emit` still rewrite to the legacy 158-constructor flag zoo; `check` has a stale "not yet implemented" stub; no `--version`, no per-command `--help`; `deploy` is EVM/Anvil-only. | 🔴 Beta blocker |
| 4 | **Testing, CI & Toolchain** | 5.5 / 10 | No standard Lean test framework (ad-hoc `require` everywhere); `just check` is a ~60-step serial monolith; testkit covers only EVM/NEAR/Solana; CI downloads binaries without checksums. | ⚠️ Quality risk |
| 5 | **SDK / Library Ecosystem** | 4 / 10 | No published packages, no release tags, generated TS clients use global mutable state and weak typing, only one project template, no stable programmatic API. | 🔴 Beta blocker |
| 6 | **Documentation / Onboarding** | 6 / 10 | README/AGENTS first-build command uses wrong `--module contract`; `docs/zh/` has hundreds of broken internal links; 4 docs out of translation sync; no CHANGELOG. | 🔴 Beta blocker |
| 7 | **Release / Distribution** | 3 / 10 | No release workflow, no Git tags, no `CHANGELOG`, no install script, no cross-platform binaries; `proof-forge init` only works inside the monorepo. | 🔴 Beta blocker |
| 8 | **Production Operations Readiness** | 4 / 10 | No observability/structured logging, deploy is EVM-only, no real hosted sandbox, no artifact provenance/SBOM. | 🔴 Beta blocker |
| 9 | **Security / Supply Chain** | 3 / 10 | Hardcoded Anvil private key in `deploy` CLI; unverified curl-to-bash/binary downloads in CI; no secret scanning, fuzzing, or CVE scanning; `.gitignore` does not protect key material. | 🔴 Beta blocker |
| 10 | **Performance / Resource Usage** | 4 / 10 | No output-size regression gate, no compile-time tracking, no peak-memory measurement, no CI performance job; `.lake/` is 7.9 GiB with no cold-build measurement. | ⚠️ Operational risk |

**Reconciled overall product-readiness score: 4.0 / 10**

**Rationale:** The backend compiler surface and CI discipline for the primary triad justify a ~6 on the *compiler-engineering* axis, but public-beta readiness is dominated by user-facing, trust, and shipability dimensions that sit at 3–4. The scoring inconsistency noted in `verdict-round2.md` is resolved by weighting toward the external-developer experience: a product cannot honestly enter public beta while its onboarding command is broken, its deploy command ships a hardcoded private key, it has no release artifacts, and it advertises 10 targets while only 3 are real product compilers.

---

## 2. Unified Blocker List (Public-Beta Gating)

Ordered by dependency and impact. All items must be closed before a real public beta.

| Rank | Blocker | Evidence | Why it gates beta |
|------|---------|----------|-------------------|
| 1 | **README/AGENTS onboarding command is broken** — uses `--module contract` instead of `--module Counter` (`README.md:103`, `AGENTS.md:73`). | `gap-documentation-onboarding.md`, `deep-release-distribution-first-run.md` | The first command every new user copies fails immediately. |
| 2 | **No release engineering or installable artifact** — no tags, `CHANGELOG`, release workflow, cross-platform binaries, or `install.sh`. | `gap-sdk-library-ecosystem.md`, `deep-release-distribution-first-run.md`, `gap-production-operations-readiness.md` | A public beta must be installable without cloning the monorepo. |
| 3 | **Hardcoded Anvil private key in `deploy`** — `ProofForge/Cli/Deploy.lean:13-19` bakes in the well-known test key as the default. | `deep-security-supply-chain.md`, `gap-production-operations-readiness.md` | Shipping a default private key is a critical secret-management bug. |
| 4 | **Honest target roster is not reflected in marketing/registry UX** — 7 of 10 `--list-targets` entries are Counter-MVP/fixture-only/spikes. | `gap-backend-target-maturity.md`, `deep-cli-target-first-and-target-roster.md` | Advertising 10 targets misrepresents the product surface and erodes trust. |
| 5 | **CLI target-first surface is still legacy-routed** — `build`/`emit` rewrite to old flags; `check` has a stale stub; no `--version` or per-command `--help`. | `gap-cli-authoring-ux.md`, `deep-cli-target-first-and-target-roster.md`, `deep-release-distribution-first-run.md` | The documented product path is not yet native. |
| 6 | **No observability or structured logging** — no `--verbose`/`--quiet`/`--log-level`, no metrics, only `IO.println`/`IO.userError` strings. | `gap-production-operations-readiness.md` | Operations and user support are impossible to run at scale. |
| 7 | **FV boundary is not visible to users** — no proof manifest in artifacts; proved fragment is Counter-only while product docs show richer examples. | `gap-formal-verification-boundaries.md`, `deep-fv-boundary-vs-product-surface.md` | Users cannot tell what assurance they receive per build. |
| 8 | **No published SDK packages or stable programmatic API** — clients are generated per-project, global-mutable, weakly typed, TS-only. | `gap-sdk-library-ecosystem.md` | External adoption requires installable, versioned packages. |
| 9 | **Ad-hoc test framework and monolithic CI** — every Lean test reinvents `require`; `just check` is serial; no test-result artifacts. | `gap-testing-ci-toolchain.md` | Blocks reliable quality engineering and fast iteration. |
| 10 | **Unverified curl-to-bash/binary downloads in CI** — `solc`, `elan`, Foundry, Aptos CLI, etc. are downloaded without checksums. | `deep-security-supply-chain.md`, `gap-testing-ci-toolchain.md` | Supply-chain integrity risk for the build itself. |

---

## 3. Prioritized Remediation Roadmap

### Short-term (0–6 weeks) — Close beta blockers

1. **Fix onboarding command** — replace `--module contract` with `--module Counter` (or omit where auto-resolution works) in README, AGENTS, `docs/validation-gates.md`, and translations; add a CI step that literally runs the corrected first-build command.
2. **Ship basic CLI affordances** — implement `--version` (prints CLI version, Lean toolchain, git SHA), honor `--help` on `build`/`emit`/`check`/`init`, and remove the stale `check` stub from `ProofForge.Cli.TargetFirst`.
3. **Security hardening** — remove the default Anvil key from `deploy`; require `--private-key` or `--private-key-env`; harden `.gitignore` for key material; add secret-scanning to CI.
4. **Release mechanics** — create `.github/workflows/release.yml`; tag `v0.1.0-beta.1`; add `CHANGELOG.md`; publish Linux x86_64 + macOS x86_64/ARM64 binaries with SHA-256 checksums and an `install.sh`.
5. **First-run validation in CI** — add `just portable-init-smoke`, `just portable-check-smoke`, and `just portable-evm-client` to the required `product`/`build-test` jobs.
6. **Repair i18n** — fix broken links in `docs/zh/`, resync the 4 stale translations (`decisions.md`, `capability-registry.md`, `implementation-backlog.md`, `validation-gates.md`), and add a link-check gate to `just docs-check`.
7. **Honest marketing matrix** — demote `wasm-cloudflare-workers`, `move-aptos`, `move-sui`, `psy-dpn`, `aleo-leo` to `research`/`spike` in public copy; only advertise `evm`, `solana-sbpf-asm`, `wasm-near` as beta-ready `contract_source` targets.
8. **Basic observability** — add `-v`/`--verbose`, `-q`/`--quiet`, and machine-readable build/check stage events.

### Medium-term (6–12 weeks) — Stabilize the product surface

1. **Complete RFC 0009 M4** — delete/shrink `EmitMode`, remove legacy flag translation in `build`/`emit`, make `TargetDriver` return compiler actions instead of flag strings, and update `Usage.lean` to show only the product path.
2. **Scope `deploy` honestly** — either generalize `deploy` around `proof-forge-deploy.json` for Solana/NEAR or clearly document it as an EVM/Anvil smoke harness until multi-chain broadcasters land.
3. **Publish SDK packages** — ship `@proof-forge/evm-client`, `@proof-forge/solana-client`, `@proof-forge/near-client` on npm with `peerDependencies`, typed interfaces, and transaction helpers.
4. **Project config file** — introduce `proof-forge.toml` so users do not repeat `--root`, `--module`, and output paths.
5. **FV transparency** — emit a `proofManifest` in artifact metadata recording fragment predicate, discharged theorems, `native_decide` trust assumptions, and external-toolchain boundaries.
6. **CI/toolchain hardening** — pin versions with checksums for all downloaded tools; add a macOS product gate; merge the duplicated IR-coverage validators.
7. **Test framework** — adopt `l_spec`/`Plausible` or ship a shared `ProofForge.Test` helper library; begin converting high-traffic test files.
8. **Performance gates** — enforce output-size baselines and add compile-time/peak-memory measurements to the B1 benchmark matrix.

### Long-term (12+ weeks) — Expand depth and trust

1. **Real backend hooks for secondary targets** — implement `validateModule?`/`ensurePlan?`/`ensurePackage?` for CosmWasm and Aptos, or keep them demoted indefinitely.
2. **Expand the proved fragment** — bring `Ownable`/`StakingVault`/simple-token into C-proof; add `storagePathRead`/`storagePathWrite` or change the DSL for role membership.
3. **Hosted sandbox** — provide a containerized worker image with cgroup/seccomp/network policy instead of the env-var-only isolation gate.
4. **Supply-chain assurance** — emit SBOMs, SLSA/Sigstore attestations, and deterministic-build documentation.
5. **Cross-platform CI** — add Windows builds and a fully matrixed `build-test` job with test-result artifacts.
6. **Modern CLI parser** — replace hand-rolled parsers with a generated/standard combinator library supporting POSIX flags, shell completion, and `--` end-of-options.

---

## 4. Public-Beta Scope Recommendation

### Advertise (in beta)

- **Targets:** `evm`, `solana-sbpf-asm`, `wasm-near` only.
- **Authoring path:** `ProofForge.Contract.Source` contracts (`Counter`, `ValueVault`, `Ownable`, `Token` via `TokenSpec`, `RemoteCall`) compiled with `proof-forge build --target <id>`.
- **Verbs:** `build`, `emit`, `check --target <id>` (after the stale stub is removed and the native path is clearly documented).
- **Generated artifacts per project:** `proof-forge-sdk.json`, `proof-forge-client.ts`, `proof-forge-artifact.json`, `proof-forge-deploy.json` (where applicable).
- **Documentation:** corrected English onboarding + repaired Chinese link layer.

### Demote (do not advertise as beta-ready)

- **Counter-MVP host adapters:** `wasm-cosmwasm`, `wasm-stellar-soroban`.
- **Fixture/research spikes:** `wasm-cloudflare-workers`, `move-aptos`, `move-sui`, `aleo-leo`, `psy-dpn`.
- **Verification target:** `quint` — keep CLI-only for model-checking, not in `--list-targets` marketing.

### Minimum release artifacts to ship

1. `proof-forge-linux-x86_64`, `proof-forge-macos-x86_64`, `proof-forge-macos-arm64` binaries with SHA-256 checksums.
2. `templates/portable-counter/` archive with a `lakefile.lean` that uses a bundled or path-based dependency, not a full GitHub clone.
3. Docs archive (README, INDEX, onboarding, product-sdk, validation-gates, generated backend-status, repaired Chinese translations).
4. `install.sh` that detects OS/arch, downloads binary + templates, and symlinks into `~/.local/bin`.
5. `CHANGELOG.md` at repo root with Breaking/Migration sections.
6. Source tarball (GitHub auto-generated) for users building from source.

---

## 5. Executive Summary

**Overall score: 4.0 / 10.**

**Top 3 blockers for public beta:**

1. **The first-run onboarding command is broken** (`--module contract` in README/AGENTS must be `--module Counter`).
2. **There is no release artifact or install path** — no tags, binaries, `CHANGELOG`, or `install.sh`.
3. **`deploy` ships a hardcoded Anvil private key** as its default, which is a critical security defect.

The product has a strong compiler core and a credible primary target triad, but it is currently a monorepo-first compiler toolchain rather than an installable, supportable, externally trustworthy public beta. Close the onboarding, release, and security blockers first; then finish the CLI target-first migration and honest target roster before expanding the advertised surface.
