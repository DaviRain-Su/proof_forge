# Gap Analysis: Testing, CI & Toolchain

**Dimension:** `testing-ci-toolchain`
**Project:** ProofForge (`/Users/davirian/orca/projects/proof_forge`)
**Date:** 2026-07-10
**Maturity score:** 5.5 / 10

## Maturity summary

ProofForge has a **broad** test surface: ~33 kLOC of Lean test drivers across ~214 files, ~192 shell smoke scripts, a product-first GitHub Actions workflow, a Codeberg Woodpecker pipeline, and a nascent unified Rust testkit (`testkit/`). The product gate (`just product`) and the formal-semantics anchors are well-structured and run in CI.

The dimension is **not production-grade** because:

- There is no standard Lean unit-testing framework; tests use ad-hoc `require`/`IO.userError` patterns.
- CI is essentially a long sequential shell recipe with ~60 steps in `just check`, no test-result artifacts, no code-coverage reporting, and minimal retry/flaky handling.
- The unified testkit (RFC 0007) is still Draft and only covers EVM, NEAR and Solana; Psy/Aleo/Cloudflare/Sui/Aptos are not harnessed.
- Toolchain installation in CI downloads binaries without checksums and is Ubuntu-only.

## Top 5 gaps

| # | Gap | Severity | Evidence |
|---|-----|----------|----------|
| 1 | **Ad-hoc Lean test framework** — no discovery, no structured reporting, no fixtures. Every `Tests/*.lean` repeats a custom `require`/`IO.userError` helper. | **Blocker** | `Tests/TargetRegistry.lean:9-13`, `Tests/CliCheck.lean:5-6`, `Tests/Product/Matrix.lean:54-58`. Grep for `plausible|lspec|LeanTest` in `Tests/` returns nothing. |
| 2 | **CI is monolithic and slow** — `just check` runs ~60 recipes serially; no matrix fan-out, no per-step timeouts, no test artifacts, no JUnit/XML. | **High** | `justfile:1332` (`check:` recipe); `.github/workflows/ci.yml:66` (`needs: [product]` but build-test itself is one job); no `upload-artifact`, `junit`, or `strategy.matrix` anywhere in CI. |
| 3 | **Unified testkit is incomplete** — RFC 0007 is Draft; only 13 scenarios; harnesses exist only for EVM/revm, NEAR/wasmtime and Solana/Mollusk. Psy, Aleo, Cloudflare, Sui, Aptos are not in testkit. | **High** | `docs/rfcs/0007-unified-rust-test-framework.md:1` (Draft); `testkit/scenarios/*.toml` lists 13 files; `testkit/harness-evm/src/lib.rs`, `testkit/harness-near/src/lib.rs`, `testkit/harness-solana/src/lib.rs` exist; no `harness-psy|aleo|sui|aptos|cloudflare`. |
| 4 | **No code-coverage tooling** — only manual IR-constructor coverage manifests (TSV) are checked; no line/branch coverage for Lean or Rust, no coverage gate, no report artifact. | **High** | `Tests/Backend/Evm/EvmCoverage.tsv`, `Tests/Backend/Wasm/WasmNearCoverage.tsv`, `Tests/Backend/Wasm/EmitWatCoverage.tsv`, `Tests/PsyCoverage.tsv`; `scripts/evm/check-ir-coverage-manifest.py`, `scripts/near/check-ir-coverage-manifest.py`, `scripts/psy/check-ir-coverage-manifest.py`. |
| 5 | **CI toolchain installation is fragile and non-portable** — downloads `solc`, Foundry, Leo, Aptos CLI from network without checksum verification; only `ubuntu-latest`; no Windows/macOS jobs. | **High** | `.github/workflows/ci.yml:37-41` (`solc-static-linux` download), `89-94`, `345-355` (Leo), `468-476` (Aptos); `scripts/ci/woodpecker-setup.sh:33-35` (`foundryup`), `38-40` (`solc`); all `runs-on: ubuntu-latest`. |

## Detailed gap register

### 1. Ad-hoc Lean test framework
- **Area:** Lean unit / integration tests
- **Evidence:** `Tests/TargetRegistry.lean:9-13`, `Tests/CliCheck.lean:5-6`, `Tests/Product/Matrix.lean:54-58`, and ~214 other files define their own `require` and `main : IO UInt32`. No shared test library, no `Plausible`/`LSpec`/`LeanTest`, no test discovery, no fixtures, no parameterized tests.
- **Severity:** blocker
- **Remediation:** Adopt a Lean test framework (e.g., `l_spec` or `Plausible`) or ship a minimal shared `ProofForge.Test` library with assertions, diffing, golden-file helpers and a runner. Convert the most frequently edited tests first.

### 2. Monolithic, sequential CI
- **Area:** GitHub Actions / Woodpecker
- **Evidence:** `justfile:1332` defines `check:` as a single recipe with ~60 serial dependencies. `.github/workflows/ci.yml` has two jobs (`product`, `build-test`) and optional spike jobs; `build-test` runs 25+ steps in one runner. `.woodpecker.yml:16-31` runs two sequential steps. No `strategy.matrix`, `upload-artifact`, JUnit, or per-step timeouts except `solana-pinocchio-live` (`timeout-minutes: 75`).
- **Severity:** high
- **Remediation:** Split `build-test` into a matrix by target/host (EVM, Solana, NEAR, Wasm, Psy/Aleo) with artifact passing; add per-step timeouts; upload test logs and structured reports.

### 3. Incomplete unified testkit
- **Area:** Cross-target behavior testing (`testkit/`)
- **Evidence:** RFC 0007 is Draft (`docs/rfcs/0007-unified-rust-test-framework.md:1`). Only 13 scenario manifests (`testkit/scenarios/*.toml`). Harnesses exist only for `evm` (`testkit/harness-evm/src/lib.rs`), `wasm-near` (`testkit/harness-near/src/lib.rs`) and `solana-sbpf-asm` (`testkit/harness-solana/src/lib.rs`). README states Psy/Aleo/Cloudflare are out of scope for M1 (`docs/rfcs/0007-unified-rust-test-framework.md:150-155`).
- **Severity:** high
- **Remediation:** Promote RFC 0007 to Accepted; add harnesses for Psy, Aleo, Cloudflare, Sui, Aptos; migrate duplicated shell smokes into scenarios; implement `--bless` for golden updates.

### 4. No code-coverage reporting
- **Area:** Coverage measurement
- **Evidence:** Only manual TSV manifests exist (`Tests/Backend/Evm/EvmCoverage.tsv`, `Tests/Backend/Wasm/WasmNearCoverage.tsv`, `Tests/Backend/Wasm/EmitWatCoverage.tsv`, `Tests/PsyCoverage.tsv`). Validation is three near-identical Python scripts (`scripts/evm/check-ir-coverage-manifest.py`, `scripts/near/check-ir-coverage-manifest.py`, `scripts/psy/check-ir-coverage-manifest.py`). No `tarpaulin`, `llvm-cov`, `lcov`, or Lean coverage tooling in CI.
- **Severity:** high
- **Remediation:** Add Rust coverage with `cargo llvm-cov` for `testkit`; investigate `lean --profile` or source-level coverage for Lean; publish coverage diffs in PRs.

### 5. Fragile, non-portable toolchain setup
- **Area:** CI environment provisioning
- **Evidence:** `.github/workflows/ci.yml:37-41` downloads `solc-static-linux` without checksum; `89-94` repeats it; `345-355` downloads Leo and skips if unavailable; `468-476` runs Aptos install script. `scripts/ci/woodpecker-setup.sh:33-35` runs `foundryup`. All CI jobs use `runs-on: ubuntu-latest`.
- **Severity:** high
- **Remediation:** Pin toolchain versions with lockfiles/checksums; cache downloads; add `macos-latest` and `windows-latest` jobs for the CLI/product gate; verify checksums for all downloaded binaries.

### 6. Duplicated IR-coverage validation scripts
- **Area:** Test maintenance / code duplication
- **Evidence:** `scripts/evm/check-ir-coverage-manifest.py`, `scripts/near/check-ir-coverage-manifest.py`, and `scripts/psy/check-ir-coverage-manifest.py` are ~95 % identical except defaults/label.
- **Severity:** medium
- **Remediation:** Merge into one `scripts/check-ir-coverage-manifest.py` invoked with `--backend evm|near|psy|emitwat`.

### 7. No flaky-test / retry / quarantine policy
- **Area:** Test reliability
- **Evidence:** Live gates (`solana-counter-live`, `evm-anvil-deploy`, `near-compare-live`) depend on external tools/network but have no retry, no quarantine, and no `RERUNS` environment variable. Only `solana-pinocchio-live` has a timeout.
- **Severity:** medium
- **Remediation:** Add `--retries` to long-running live gates; mark optional spike jobs as non-blocking (already `continue-on-error`) but report flaky rates; isolate live jobs with their own timeout and artifact upload.

### 8. No structured test-result artifacts
- **Area:** CI observability
- **Evidence:** No `upload-artifact` in `.github/workflows/ci.yml`; no JUnit/XML; test output is console-only. Failure diagnosis requires re-running locally.
- **Severity:** medium
- **Remediation:** Emit JUnit or TAP from the testkit runner and Lean harnesses; upload logs and reports as CI artifacts.

### 9. Limited testkit scenario coverage
- **Area:** Functional behavior coverage
- **Evidence:** Only 13 scenarios (`testkit/scenarios/*.toml`) vs. ~50 product/backend fixtures. TokenSpec, ERC-20/721/1155 lifecycle, CREATE2, UUPS proxy, and many Solana CPI cases are only in shell scripts or Foundry tests.
- **Severity:** medium
- **Remediation:** Port high-value shell smokes (`evm-foundry`, `portable-counter-multi-target`, `near-target-first`) into testkit scenarios.

### 10. `just ci` is not a strict mirror of GitHub `build-test`
- **Area:** Local/CI fidelity
- **Evidence:** `AGENTS.md` and `justfile:1578-1622` document that `just ci` omits several `build-test` steps and adds others (`evm-broadcast-smoke`, `evm-mixin-compose`). The comment in `justfile:1578` admits this explicitly.
- **Severity:** low
- **Remediation:** Keep `github-build-test` exactly aligned with `.github/workflows/ci.yml` via a CI self-check job.

## What appears healthy / complete

- **Product-first CI split:** `.github/workflows/ci.yml:14-63` runs `just product` as a required gate before `build-test`, matching the documented policy (`docs/examples-and-tests-taxonomy.md:53-58`).
- **Rich formal-semantics test anchors:** `just check` includes `ir-step-semantics-smoke`, `ir-counter-semantics-smoke`, `constructor-coverage-smoke`, `lean-invariants-smoke`, etc. (`justfile:1332`).
- **Declarative scenario runner:** `testkit/runner/src/main.rs` discovers TOML scenarios, runs them per target, checks artifacts and traces, and supports `--deny-skip` (`testkit/runner/src/main.rs:34-35`, `298-305`).
- **Mechanical doc↔code sync checks:** `scripts/docs/audit-doc-code-sync.sh` and `scripts/i18n/check-sync.sh` run in `just docs-check` (`justfile:1199-1208`).
- **Coverage manifests are enforced:** EVM, NEAR, EmitWat and Psy IR manifests are checked in CI (`.github/workflows/ci.yml:161-165`, `198-199`, `219-220`).

## Remediation roadmap (priority order)

1. **Stabilize the test framework:** introduce a shared Lean test helper library or adopt `l_spec`; stop copy-pasting `require` in every file.
2. **Parallelize CI:** split `build-test` into a target matrix; add per-step timeouts and artifact upload.
3. **Complete the testkit:** accept RFC 0007, add missing harnesses, migrate shell smokes, add `--bless`.
4. **Add coverage tooling:** Rust `llvm-cov` for testkit; investigate Lean coverage; block PRs on coverage regression for new backends.
5. **Harden toolchain provisioning:** pin versions with checksums, add macOS/Windows jobs, cache aggressively.
6. **Deduplicate scripts:** merge the three IR-coverage validators and similar shell patterns.

## Evidence index

- `justfile:1332` — `check` recipe
- `.github/workflows/ci.yml:14-487` — CI jobs
- `.woodpecker.yml:16-31` — Woodpecker pipeline
- `docs/rfcs/0007-unified-rust-test-framework.md` — Draft testkit RFC
- `testkit/runner/src/main.rs` — Scenario runner
- `testkit/core/src/lib.rs` — Scenario model / validation
- `testkit/harness-evm/src/lib.rs`, `testkit/harness-near/src/lib.rs`, `testkit/harness-solana/src/lib.rs` — Harnesses
- `testkit/scenarios/*.toml` — 13 scenario manifests
- `Tests/TargetRegistry.lean`, `Tests/CliCheck.lean`, `Tests/Product/Matrix.lean` — Ad-hoc test patterns
- `Tests/Backend/Evm/EvmCoverage.tsv`, `Tests/Backend/Wasm/WasmNearCoverage.tsv`, `Tests/PsyCoverage.tsv` — IR coverage manifests
- `scripts/evm/check-ir-coverage-manifest.py`, `scripts/near/check-ir-coverage-manifest.py`, `scripts/psy/check-ir-coverage-manifest.py` — Duplicated validators
- `scripts/ci/woodpecker-setup.sh` — Toolchain setup
- `docs/examples-and-tests-taxonomy.md` — Product/backend test taxonomy
