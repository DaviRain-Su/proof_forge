# Gap Analysis: Production Operations Readiness

**Dimension:** `production-operations-readiness`
**Project:** ProofForge (`/Users/davirian/orca/projects/proof_forge`)
**Date:** 2026-07-10
**Branch:** `main`

## Executive Summary

ProofForge has strong *development-time* rigor (product-first CI, versioning policy, resource-limit wrappers, and an explicit upgrade/signing boundary), but it is not yet a production-grade *deployed product*. The missing pieces cluster around release engineering, observability, production deployment orchestration, secrets hygiene, and a real cloud/hosted isolation boundary. Most operational capabilities today are local/CI conveniences rather than externally facing, supportable services.

**Overall maturity score: 4 / 10**

## What appears complete / healthy

| Area | Evidence | Notes |
|------|----------|-------|
| CI/CD gating | `.github/workflows/ci.yml`, `.woodpecker.yml`, `justfile` | Product-first `just product` gate, optional continue-on-error research jobs, clear separation of required vs optional gates. |
| Versioning & toolchain pinning | `lakefile.lean:5` (`v!"0.1.0"`), `lean-toolchain` (`v4.31.0`), `lake-manifest.json` | Dependencies pinned; RFC 0012 documents IR/artifact/SDK compatibility rules. |
| Resource-limit wrappers | `scripts/cli/worker-resource-limit.py`, `scripts/cli/worker-limits-smoke.sh`, `scripts/cli/worker-cgroup-smoke.sh` | Wall-clock, CPU (`RLIMIT_CPU`), and cgroup-v2/rlimit memory controls exist and are gated. |
| Hosted-isolation honesty | `ProofForge/Cli/ContractLoader.lean:18-35`, `scripts/cli/hosted-isolation-smoke.sh` | `PROOF_FORGE_HOSTED_ISOLATION` env var makes the compiler refuse trusted-local elaboration rather than falsely claim sandbox safety. |
| Upgrade/signing boundary | `docs/rfcs/0013-deployment-lifecycle-upgrades-and-signing.md`, `docs/upgrade-signing-ops.md` | `upgradePolicy` intent implemented; compiler emits unsigned manifests only; key custody stays outside. |
| Structured diagnostics | `ProofForge/Cli/Check.lean:36-128` | `proof-forge check --report-format json` emits schema-versioned diagnostics with severity/code/location. |
| Artifact/deploy schema versioning | `ProofForge/Cli/EvmArtifacts.lean:345`, `ProofForge/Cli/EmitWatArtifacts.lean:90`, RFC 0012 | `schemaVersion` and `irVersion` fields are present and policy-backed. |
| Validation gates catalog | `docs/validation-gates.md`, `justfile` | Runnable gates are documented and mapped to CI commands. |

## Gaps

### 1. Release engineering / distribution / packaging
- **Area:** Release & distribution
- **Evidence:**
  - No `CHANGELOG*`, no `Dockerfile*`, no release workflow in `.github/workflows/` (only `ci.yml`).
  - No install script, no binary release artifact, no Homebrew/nix/cargo package.
  - `lakefile.lean:5` hardcodes `v!"0.1.0"`; no release automation or tag-driven versioning.
- **Severity:** blocker
- **Remediation:** Add a release workflow that builds the `proof-forge` binary for target platforms, produces versioned GitHub releases, publishes a CHANGELOG, and ideally packages the CLI (e.g., nix flake, brew formula, or static binary tarballs).

### 2. No observability, telemetry, or structured logging
- **Area:** Observability
- **Evidence:**
  - No `--verbose`, `--quiet`, `--log-level`, or `--debug` flags in `ProofForge/Cli/TargetFirst.lean` or `ProofForge/Cli/LegacyArgs.lean`.
  - No metrics, tracing, or health endpoints. Output is ad-hoc `IO.println`/`IO.eprintln`.
  - Errors are `IO.userError` strings; no correlation IDs, no stack traces, no structured log records.
  - Grep for `PROOF_FORGE_LOG`, `--verbose`, `logLevel` returns no CLI observability matches (only FV “trace” semantics).
- **Severity:** blocker
- **Remediation:** Introduce a minimal structured logger (severity + code + context), add `-v`/`-q` flags, and emit machine-readable event records for build/check/deploy stages.

### 3. Deployment command is EVM-only and operationally basic
- **Area:** Deployment orchestration
- **Evidence:**
  - `ProofForge/Cli/Deploy.lean:443-446` explicitly rejects non-EVM targets.
  - `ProofForge/Cli/Deploy.lean:188-198` starts Anvil with `nohup ... &` and polls RPC; no PID file, no cleanup on interrupt, no retry/backoff.
  - No Solana/NEAR/Aleo deploy subcommand; upgrade orchestration beyond `upgradePolicy` metadata is absent.
  - No idempotency, no rollback, no multi-step deploy plan execution, no dry-run beyond `--plan-only`.
- **Severity:** high
- **Remediation:** Extend `deploy` to Solana/NEAR, add a robust local-node lifecycle manager, and implement plan-driven multi-step deploy/upgrade with rollback hooks.

### 4. Secrets & key-management posture is immature
- **Area:** Security / secrets
- **Evidence:**
  - `ProofForge/Cli/Deploy.lean:13` hardcodes the default Anvil private key (`0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`).
  - `.gitignore` does not list `.env`, `*.json` keypairs, mnemonics, or PEM files.
  - `docs/upgrade-signing-ops.md:78-79` says secret scanning is an “optional future CI check (RFC 0013 M4 remainder) — not implemented.”
- **Severity:** high
- **Remediation:** Remove or clearly mark the hardcoded key as testnet-only, add secret-scanning to CI, and harden `.gitignore`/documentation for key material.

### 5. Hosted/cloud compilation is not a real sandbox
- **Area:** Cloud / multi-tenant operations
- **Evidence:**
  - `ProofForge/Cli/ContractLoader.lean:90-95` refuses when `PROOF_FORGE_HOSTED_ISOLATION` is set; there is no actual sandboxed elaboration path.
  - Resource limits live in external Python/bash wrappers (`scripts/cli/worker-resource-limit.py`) rather than being enforced by the CLI itself.
  - No network egress policy, no filesystem sandbox, no container image.
- **Severity:** high
- **Remediation:** Provide a containerized worker image and integrate cgroup/timeout controls into the CLI or a supported worker wrapper; document the cloud boundary explicitly.

### 6. CLI lacks production-grade UX affordances
- **Area:** CLI surface
- **Evidence:**
  - No `proof-forge --version` command (only `lean-toolchain` and `lakefile.lean` versions).
  - No per-subcommand `--help`; `ProofForge/Cli/Usage.lean` dumps a single massive usage block.
  - No config file / persistent settings; every invocation repeats `--root`, `--module`, etc.
  - Core CLI functions are `unsafe` (`ProofForge/Cli.lean:303`, `ProofForge/Cli/Check.lean:393`).
- **Severity:** medium
- **Remediation:** Add `--version`, per-command help, a project config file (e.g., `proof-forge.toml`), and reduce reliance on `unsafe` in the main CLI path.

### 7. CI runtime is slow and not optimized for operations
- **Area:** CI / build engineering
- **Evidence:**
  - `.woodpecker.yml:18-31` installs the entire toolchain (`elan`, `foundryup`, Rust, Solana testkit, etc.) from the internet on every run via `scripts/ci/woodpecker-setup.sh`.
  - No published base image or pre-baked runner; no documented artifact retention policy.
  - No nightly/staging job separate from PR CI.
- **Severity:** medium
- **Remediation:** Build and publish a CI runner image with toolchains preinstalled; add nightly/staging jobs; document artifact retention.

### 8. No artifact provenance, SBOM, or reproducibility guarantees
- **Area:** Supply chain / build integrity
- **Evidence:**
  - `scripts/cli/rebuild-hash-smoke.sh` exists for reproducibility smoke, but there is no SBOM/provenance emission in artifact metadata.
  - `ProofForge/Cli/EvmArtifacts.lean:399-440` records `solcVersion?` and `leanVersion?`, but not dependency hashes or build environment digest.
- **Severity:** medium
- **Remediation:** Emit an artifact provenance record (tool versions, dependency hashes, build host digest) and optionally SLSA-style attestation.

### 9. Dependency installation relies on curl-to-bash
- **Area:** Supply chain security
- **Evidence:**
  - `scripts/ci/woodpecker-setup.sh:27-35` installs `elan` and Foundry via `curl | sh`/`curl | bash`.
  - No checksum verification or pinned install-script hashes in CI.
- **Severity:** medium
- **Remediation:** Pin installer script hashes, verify checksums for downloaded binaries, or use distribution packages/container layers.

### 10. No operator / on-call runbooks
- **Area:** Operations documentation
- **Evidence:**
  - No incident-response, on-call, or SLO/SLA documentation in `docs/`.
  - No healthcheck endpoint or status-page guidance.
- **Severity:** low
- **Remediation:** Add an `ops/` or `docs/ops/` section with runbooks, escalation paths, and expected build/check/deploy latencies.

## Top 5 gaps

1. **Release engineering / distribution / packaging** — blocker
   No CHANGELOG, release workflow, binaries, or installable package; product cannot be shipped.

2. **Observability, telemetry, and structured logging** — blocker
   No verbose/quiet/debug flags, no metrics, no structured logs, only `IO.userError` strings.

3. **Deployment orchestration limited to EVM and lacks robustness** — high
   EVM-only deploy; Anvil lifecycle is ad-hoc; no rollback/retry/idempotency for chain operations.

4. **Secrets and key-management hygiene** — high
   Hardcoded Anvil test key in source; no secret scanning; `.gitignore` does not protect key files.

5. **Cloud/hosted compilation boundary is not a real sandbox** — high
   Hosted isolation only refuses; resource limits are external wrappers; no container/network sandbox.

## Overall maturity score

**4 / 10**

Reasoning: The project has solid CI, versioning, resource-limit smoke tests, and honest policy documentation for upgrades/signing — all necessary foundations. However, it lacks the basic operational packaging (release artifacts, install story), runtime observability, production deployment breadth, and security hardening (secrets, sandboxing) that would let an operations team run ProofForge as a real product or service.
