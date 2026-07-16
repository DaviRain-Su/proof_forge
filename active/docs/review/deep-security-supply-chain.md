# Deep-Dive: Security & Supply-Chain Readiness

**Dimension:** `security-supply-chain`
**Project:** ProofForge (`/Users/davirian/orca/projects/proof_forge`)
**Date:** 2026-07-10
**Branch:** `main` (dirty: `docs/zh/INDEX.zh.md`, `scripts/i18n/manifest.json`, `scripts/near/target-first-smoke.sh`; untracked `docs/review/`)

## Executive Summary

ProofForge has a **honest but immature** security and supply-chain posture. The project documents a clear signing boundary (compiler emits unsigned manifests only; keys live outside), refuses to misrepresent local elaboration as a cloud sandbox, and pins most Lean/Rust dependencies via lockfiles. However, it ships a hardcoded Anvil private key in the production `deploy` path, downloads CI toolchains via unverified curl-to-bash, emits no SBOM or build-provenance attestation, has no secret-scanning or fuzzing harness, and relies on an opt-in env var rather than a real sandbox for hosted compilation.

**Overall maturity score: 3 / 10**

---

## 1. Secrets Hygiene

### 1.1 `.gitignore` does not protect key material
`.gitignore` (lines 1–23) ignores build outputs (`build/`, `.lake/`, `target/`, `*.bin`, `*.yul`, `.DS_Store`, `scripts/__pycache__/`) but **never mentions** `.env`, `*.pem`, `*.key`, mnemonics, `id.json`, or keypair files. The `docs/upgrade-signing-ops.md` forbids committing these, but the ignore file itself does not enforce it.

### 1.2 Hardcoded Anvil private key in the CLI deploy path
`ProofForge/Cli/Deploy.lean:13–19` bakes in the well-known Anvil test key, deployer address, and chain ID:

```lean
def defaultAnvilPrivateKey : String :=
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
```

The same key is repeated in `scripts/evm/dynamic-constructor-anvil-smoke.sh:79` and in `scripts/benchmarks/counter-native-runner.sh:101`, `value-vault-native-runner.sh:74`, and `ownable-native-runner.sh:71`. `ProofForge/Cli/Deploy.lean:354` uses this key as the default when `--private-key` is omitted:

```lean
let privateKey := opts.privateKey?.getD defaultAnvilPrivateKey
```

It is then passed to `cast send --private-key` at lines 379–386. The help text at line 35 documents the default as "Anvil test key", but a default test key in a deploy command is a secret-management bug if a user ever targets a public RPC without overriding it.

### 1.3 No secret-scanning in CI
There is no `.github/dependabot.yml`, no GitHub secret-scanning workflow, no `trufflehog`, `gitleaks`, or `gitguardian` action in `.github/workflows/`. `docs/upgrade-signing-ops.md:78–79` explicitly says secret scanning is an "optional future CI check (RFC 0013 M4 remainder) — not implemented."

### 1.4 Honest boundaries that exist today
- `docs/upgrade-signing-ops.md:8–21` declares a non-negotiable compiler boundary: ProofForge compiles and emits unsigned plans; wallets/KMS/CI secrets hold keys and sign.
- `ProofForge/Cli/ContractLoader.lean:12–35` defines `PROOF_FORGE_HOSTED_ISOLATION` and refuses local elaboration when set, with a clear message that local elaboration is **not** an isolation boundary.
- Solana live smokes generate throwaway keypairs under `build/` (e.g. `scripts/solana/pinocchio-system-transfer-live-equivalence.sh:84`) and pass them via env vars; `build/` is gitignored.

---

## 2. Supply-Chain Tooling

### 2.1 Dependency lockfiles are present and mostly pinned
- `lake-manifest.json` pins all Lean dependencies by git revision (e.g. `evm_semantics` at `ae13dbc506158f9d0c7e05634636b17e2bccf850`, `solanalib` at `6c115ef1ef6a0cde8dbd6fd875b7dc87d60939ec`).
- `lakefile.lean:7–14` pins `evm-semantics` and `solanalib` by explicit git SHA.
- Multiple `Cargo.lock` files exist (`testkit/Cargo.lock`, `runtime/offline-host/Cargo.lock`, `tools/cosmwasm-vm-runner/Cargo.lock`, and many under `testkit/compare/near/` and `references/solana/pinocchio/`).
- Rust `cargo install --git … --rev … --locked` is used for `sbpf` and `surfpool` (`scripts/solana/install-testkit-ci-tools.sh:78`, `scripts/solana/install-pinocchio-live-ci-tools.sh:114, 125`).

### 2.2 CI toolchain installation relies on curl-to-bash without checksums
Multiple scripts and workflows download installers or binaries and execute them without hash verification:

| File | Lines | Practice |
|------|-------|----------|
| `scripts/ci/woodpecker-setup.sh` | 23 | `curl … https://just.systems/install.sh \| bash` |
| `scripts/ci/woodpecker-setup.sh` | 27–28 | `curl … elan-init.sh` then `sh elan-init.sh` |
| `scripts/ci/woodpecker-setup.sh` | 33–35 | `curl … https://foundry.paradigm.xyz \| bash` then `foundryup` |
| `scripts/ci/woodpecker-setup.sh` | 38–40 | `curl … solc-static-linux` (no checksum) |
| `scripts/ci/woodpecker-setup.sh` | 43 | `curl … https://sh.rustup.rs \| sh` |
| `.github/workflows/ci.yml` | 28–29, 80–81, 267–268, etc. | Same `elan-init.sh` curl-to-sh pattern repeated in every job |
| `.github/workflows/ci.yml` | 37–41, 89–94 | `solc-static-linux` download without checksum |
| `.github/workflows/ci.yml` | 396–398 | `curl -fsSL https://deb.nodesource.com/setup_22.x \| sudo -E bash -` |
| `.github/workflows/ci.yml` | 468–473 | Aptos CLI install script via `curl -sSfL https://aptos.dev/scripts/install_cli.sh` |
| `.github/workflows/ci.yml` | 345–355 | Leo binary download; only checks HTTP success, skips if unavailable |
| `scripts/solana/install-testkit-ci-tools.sh` | 70 | `curl -sSfL https://release.anza.xyz/…/install \| sh` |
| `scripts/solana/install-pinocchio-live-ci-tools.sh` | 76 | Same Agave `curl \| sh` install |
| `scripts/psy/*-smoke.sh` | ~44–47 | Document `curl -fsSL …/psyup/main/install.sh \| bash` for local installs |
| `docs/targets/psy-dpn.md` | 394 | Same psyup curl-to-bash instruction in user docs |

### 2.3 No artifact checksum verification
No SHA-256/GPG verification is performed for downloaded toolchains. Even the reproducible rebuild smoke (`scripts/cli/rebuild-hash-smoke.sh`) only compares artifacts produced by the same toolchain on the same host; it does not verify the integrity of the toolchain that produced them.

---

## 3. Build Provenance / SBOM

### 3.1 Artifact metadata exists but is not a provenance attestation
`ProofForge/Cli/EvmArtifacts.lean:399–442` defines an `ArtifactBundle` that records:
- `source` identity (module name, path, kind)
- typed outputs with `sha256?` and `bytes?`
- `toolchain` array (e.g. `lean` version, `solc` version, availability)
- `validations` array (`solcStrictAssembly`, `bytecodeGeneration`, `contractSizeCheck`)

`ProofForge/Cli/EvmArtifacts.lean:345` also emits `schemaVersion`, `irVersion`, `target`, `targetFamily`, `capabilities`, etc. This is a strong foundation.

### 3.2 Reproducibility smoke is present
- `scripts/cli/rebuild-hash-smoke.sh:14–54` builds Counter for EVM twice and asserts `Counter.bin` and `Counter.yul` SHA-256 hashes reproduce.
- `scripts/cli/rebuild-hash-smoke.sh:55–73` verifies the `lean-toolchain` pin is recorded in artifact metadata.
- `scripts/cli/hosted-isolation-smoke.sh:57–88` also verifies the lean pin is present in the emitted artifact bundle.

### 3.3 What is missing
- **No SBOM**: no Software Bill of Materials for Lean dependencies, Rust dependencies, or external tools.
- **No build-environment digest**: artifact metadata does not capture the CI runner image, OS, or installed-tool hashes.
- **No signed attestation**: no SLSA, no `cosign`, no Sigstore/Rekor entry, no GPG-signed release metadata.
- **No release workflow**: `.github/workflows/` contains only `ci.yml`; no `release.yml`, no `CHANGELOG*`, no published binary checksums.
- `lakefile.lean:5` hardcodes version `v!"0.1.0"`; no tag-driven versioning or release artifact automation.

---

## 4. Fuzzing / Audit Surface

### 4.1 No automated fuzzing or security scanning
Grep for `fuzz|afl|cargo-fuzz|libfuzzer|trivy|snyk|semgrep|codeql|bandit|trufflehog|gitleaks` returns no CI workflows or harnesses. There is no `dependabot.yml`, no `.github/codeql.yml`, no container scanning.

### 4.2 Manual coverage manifests substitute for audit
IR coverage is enforced through TSV manifests (`Tests/Backend/Evm/EvmCoverage.tsv`, `Tests/Backend/Wasm/WasmNearCoverage.tsv`, `Tests/Backend/Wasm/EmitWatCoverage.tsv`, `Tests/PsyCoverage.tsv`) checked by near-identical Python scripts. These are completeness checks, not security audits.

### 4.3 Large interpreters increase audit surface
`ProofForge/IR/SemanticsFuel.lean` implements a fuel-indexed interpreter for the portable IR. While fuel-bounded, any bug in expression/effect evaluation is part of the FV trusted computing base (`docs/formal-verification.md:84–145`). `docs/formal-verification.md:94` acknowledges that pointwise trace-matching theorems rely on `native_decide` (trusting Lean's native evaluator) and that EVM bytecode reduction trusts the pinned powdr `stepF`.

### 4.4 Formal verification boundary is narrow
The proved fragment covers Counter-shaped code (scalar/map storage, caller context, events, checked arithmetic, assertions). Auth, arrays/structs, crosscalls, unbounded loops, Token/RoleGatedToken/StakingVault constructs are outside the proved fragment per `ProofForge/Backend/Refinement/ConstructorCoverage.lean` and the FV gap analysis.

---

## 5. `unsafe` Usage in CLI / Main Paths

### 5.1 Lean `unsafe` is pervasive in CLI due to elaboration
Every CLI command that loads a `.lean` source uses `enableInitializersExecution` + `Lean.Elab.runFrontend` + `env.evalConstCheck`, which are `unsafe` in Lean:

- `ProofForge/Cli.lean:303` — `main` is `unsafe`
- `ProofForge/Cli/ContractLoader.lean:82–118` — `loadSpecFromEnv` / `loadSpec`
- `ProofForge/Cli/TokenLoader.lean:30–74` — `loadTokenFromEnv` / `loadToken`
- `ProofForge/Cli/Check.lean:215`, `393`, `457`
- `ProofForge/Cli/ContractSourceArtifacts.lean`, `SolanaCommands.lean`, `LearnArtifacts.lean`, etc.

This is inherent: compiling Lean source requires running the Lean frontend and evaluating constants. `ContractLoader.lean:108` sets `trustLevel := 0` (do not trust untrusted `.olean` plugins), and lines 94–95 fail closed under `PROOF_FORGE_HOSTED_ISOLATION`. The security issue is not the use of `unsafe` per se, but that the only isolation mechanism is an env var.

### 5.2 Rust `unsafe` is minimal
Only one occurrence in the Rust codebases surveyed:
- `references/solana/pinocchio/memo/src/lib.rs:42`: `unsafe { core::str::from_utf8_unchecked(bytes) }` in a reference fixture.

### 5.3 Process invocation
`ProofForge/Cli/Process.lean:8–14` wraps `IO.Process.output` with an explicit args array, which is generally safe from shell injection. The exception is `ProofForge/Cli/Deploy.lean:188–192`, which builds a shell command string for Anvil and runs it via `bash -c`:

```lean
let cmd := s!"nohup {anvilPath} --host 127.0.0.1 --port {port} ... &"
let _ ← runProcess "bash" #["-c", cmd]
```

`anvilPath` comes from user input (`--anvil PATH`), so this is a shell-injection vector if a path containing metacharacters is supplied. The same file also shells out to Python for JSON extraction at line 216–218 with a dynamically built script.

---

## 6. Top 5 Security / Supply-Chain Blockers for Production

| Rank | Blocker | Severity | Evidence |
|------|---------|----------|----------|
| 1 | **Hardcoded Anvil private key in deploy CLI** | **Critical** | `ProofForge/Cli/Deploy.lean:13–19`, `354`, `379–386`; `scripts/evm/dynamic-constructor-anvil-smoke.sh:79`; `scripts/benchmarks/*-native-runner.sh` |
| 2 | **Unverified curl-to-bash / binary downloads in CI** | **High** | `scripts/ci/woodpecker-setup.sh:23, 27–28, 33, 35, 43`; `.github/workflows/ci.yml:28–29, 37–41, 80–81, 396–398, 468–473`; `scripts/solana/install-testkit-ci-tools.sh:70` |
| 3 | **No SBOM, provenance attestation, or signed releases** | **High** | `ProofForge/Cli/EvmArtifacts.lean:399–442` records hashes/versions but no SBOM; no release workflow; no `cosign`/SLSA/Rekor |
| 4 | **Hosted compilation has no real sandbox** | **High** | `ProofForge/Cli/ContractLoader.lean:90–118` only refuses via env var; `scripts/cli/worker-resource-limit.py` is an external wrapper, not an enforced sandbox; no container/network/filesystem isolation |
| 5 | **No fuzzing, secret scanning, or CVE scanning** | **High** | No GitHub security workflows; no `cargo-fuzz`/`libfuzzer`; no Dependabot/Trivy/CodeQL; `.gitignore` does not protect secrets |

---

## 7. Hardening: Existing CI/Tooling vs New Infrastructure

### 7.1 Can be added with existing CI/tooling (low/no new infra)
- **`.gitignore` hardening**: add `.env`, `*.pem`, `*.key`, `*.json` keypair patterns, mnemonics, `id.json`, `*.p12`.
- **Secret scanning**: enable GitHub secret-scanning if on GitHub; otherwise add a `trufflehog` or `gitleaks` CI step.
- **Remove/reclassify the hardcoded Anvil key**: make `deploy` require `--private-key` or `--private-key-env` with no default; keep the Anvil key only in test-only shell scripts with explicit comments.
- **Checksum verification in CI**: pin SHA-256 sums for `solc-static-linux`, `elan-init.sh`, `just` installer, and any other downloaded binary. Use `GITHUB_TOKEN` only for rate-limited API calls (already scoped to `${{ github.token }}` at `.github/workflows/ci.yml:470`).
- **Extend artifact metadata**: add dependency hashes (git revs from `lake-manifest.json`, Cargo lock hashes), build-host digest, and a deterministic rebuild explanation for any nondeterministic input.
- **Shell-injection fix**: replace the `bash -c` Anvil launch in `ProofForge/Cli/Deploy.lean:191–192` with `IO.Process.spawn` using an args array.

### 7.2 Requires new infrastructure or significant design
- **Real hosted sandbox**: a containerized worker (Docker/OCI or gVisor) with cgroup v2, seccomp/network policy, read-only rootfs, and no access to host Lean toolchains. The current `scripts/cli/worker-resource-limit.py` is a useful local wrapper but not a multi-tenant boundary.
- **SLSA / Sigstore provenance**: add a release workflow that builds the `proof-forge` binary, generates an SBOM (e.g. `syft`), and signs attestations with `cosign` + Sigstore/Rekor.
- **Fuzzing harness**: `cargo-fuzz` for Rust testkit/harnesses; for Lean, property-based fuzzing of `ProofForge/IR/SemanticsFuel.lean` and backend printers using `Plausible` or a custom generator.
- **CVE scanning**: integrate `cargo-audit` (already uses Rust), `trivy`, or `snyk` for Rust and container images; Lean has no mature CVE scanner, so dependency review must be manual or based on git-rev diff gates.
- **Reproducible build environment**: a Nix flake or pinned Docker image containing all toolchains, so CI and users build with identical byte-for-byte dependencies.

---

## 8. Recommendations (Priority Order)

1. **Remove the default Anvil private key from `ProofForge/Cli/Deploy.lean`** and require explicit key input; mark all benchmark/smoke scripts that contain it as test-local-only.
2. **Add checksum verification** for every downloaded installer/binary in CI and document expected hashes.
3. **Harden `.gitignore`** and add a secret-scanning CI gate (e.g. `trufflehog filesystem --only-verified`).
4. **Emit an SBOM + build provenance record** per artifact, starting with dependency git SHAs and toolchain version hashes; extend `scripts/cli/rebuild-hash-smoke.sh` to verify them.
5. **Design a real hosted worker sandbox** before offering cloud compilation; keep `PROOF_FORGE_HOSTED_ISOLATION` as the fail-closed gate until then.
6. **Add `cargo-audit` and a Lean dependency-change gate** to CI; investigate `cargo-fuzz` for the Rust testkit.

---

## Evidence Index

- `.gitignore:1–23` — build-output ignores, missing secret patterns
- `ProofForge/Cli/Deploy.lean:13–19, 354, 379–386, 188–192` — hardcoded key, default usage, shell Anvil launch
- `scripts/evm/dynamic-constructor-anvil-smoke.sh:79` — repeated hardcoded key
- `scripts/benchmarks/*-native-runner.sh:71,74,101` — keys in benchmarks
- `docs/upgrade-signing-ops.md:8–21, 78–79` — signing boundary, secret scanning not implemented
- `ProofForge/Cli/ContractLoader.lean:12–35, 90–118` — hosted-isolation env gate, local elaboration
- `scripts/ci/woodpecker-setup.sh:23, 27–28, 33, 35, 38–40, 43` — curl-to-bash toolchain installs
- `.github/workflows/ci.yml:28–29, 37–41, 80–81, 267–268, 345–355, 396–398, 468–473` — unverified downloads
- `scripts/solana/install-testkit-ci-tools.sh:70, 78` — Agave curl-to-sh, pinned cargo install
- `scripts/solana/install-pinocchio-live-ci-tools.sh:76, 114, 125` — same patterns
- `lake-manifest.json:1–116`, `lakefile.lean:7–14` — Lean dependency pins
- `testkit/Cargo.lock`, `runtime/offline-host/Cargo.lock`, `tools/cosmwasm-vm-runner/Cargo.lock` — Rust lockfiles
- `ProofForge/Cli/EvmArtifacts.lean:399–442` — ArtifactBundle metadata
- `scripts/cli/rebuild-hash-smoke.sh:14–73` — reproducibility smoke
- `scripts/cli/hosted-isolation-smoke.sh:57–88` — lean-pin provenance check
- `ProofForge/Cli/Process.lean:8–14` — process wrapper
- `ProofForge/IR/SemanticsFuel.lean` — portable-IR interpreter (audit surface)
- `docs/formal-verification.md:84–145` — TCB and `native_decide` discussion
