# Release / Distribution / First-Run Readiness Deep-Dive

**Dimension:** `release-distribution-first-run`
**Project:** ProofForge (`/Users/davirian/orca/projects/proof_forge`)
**Branch:** `main` (dirty: `docs/zh/INDEX.zh.md`, `scripts/i18n/manifest.json`, `scripts/near/target-first-smoke.sh`, untracked `docs/review/`)
**Date:** 2026-07-10

---

## Executive Summary

ProofForge has a working compiler core and a strong product gate (`just product`), but it is **not yet packaged for an external public beta**. There is no release workflow, no Git tags, no `CHANGELOG`, and the first-run path has several sharp edges: README/AGENTS onboarding commands use the wrong `--module` value, `proof-forge init` only works inside a monorepo checkout, the scaffolded project pulls the entire repository from GitHub on first `lake update`, and the Chinese documentation layer contains hundreds of broken internal links. The existing `portable-init-smoke`, `portable-check-smoke`, and `portable-evm-client` recipes already exercise the first-run path, but **none of them run in CI** today.

**Maturity score: 3 / 10** for release/distribution readiness.

---

## 1. Minimum Release Artifacts for a Public Beta

A beta release must ship enough that a user on a clean machine can install, scaffold, build, and inspect artifacts without cloning the monorepo. Today the following pieces exist, but they are not assembled into a distributable release.

| Artifact | Current state | Evidence |
|---|---|---|
| `proof-forge` executable | Built by `lake build`; **184 MB** with interpreter support (`supportInterpreter := true` in `lakefile.lean:71`). Binary lives at `.lake/build/bin/proof-forge` (192,749,552 bytes on this checkout). | `lakefile.lean:70-72`, `.lake/build/bin/proof-forge` |
| Project template | Only `templates/portable-counter/` exists; copied by `ProofForge.Cli.Scaffold`. Includes `Counter.lean`, `lakefile.lean`, `justfile`, `.vscode/`, Foundry workspace. | `templates/portable-counter/`, `ProofForge/Cli/Scaffold.lean:13-14` |
| SDK package layout | Per-target `proof-forge-sdk.json` + client TS + artifact/deploy manifests are generated under `build/sdk/<target>/`. Validated by `scripts/sdk/validate-sdk-layout.py`. | `scripts/sdk/validate-sdk-layout.py:8-41`, `scripts/portable/counter-four-target-sdk.sh` |
| Documentation | Rich doc tree (README, `docs/INDEX.md`, `docs/onboarding.md`, `docs/product-sdk.md`, `docs/validation-gates.md`, generated `docs/generated/backend-status.md`). | `docs/INDEX.md`, `docs/generated/backend-status.md` |
| Version metadata | `lakefile.lean:5` pins `v!"0.1.0"`, but the CLI **does not expose `--version`**. | `ProofForge/Cli.lean:303-415`, `ProofForge/Cli/Options.lean` |
| CHANGELOG / release notes | **Absent**. `git tag -l` returns no tags. | shell check |

**What is missing for a beta bundle:**

1. **A distributable archive** (tarball/zip) containing the `proof-forge` binary, `templates/`, a copy of `docs/`, `lean-toolchain`, and an `install.sh`.
2. **Cross-platform builds.** CI currently builds only on `ubuntu-latest` (`.github/workflows/ci.yml:15,65`); macOS builds are not produced in CI even though development happens on macOS.
3. **Template embedding or side-by-side installation.** `init` discovers templates by searching `LEAN_SRC_PATH` or parent directories (`ProofForge/Cli/Scaffold.lean:156-168`), so a standalone binary cannot scaffold unless the template directory is co-located.
4. **Published SDK packages.** The TypeScript client is generated into `build/evm/proof-forge-evm-abi.ts` per project; there is no npm package (`package.json` only exists under `Examples/Backend/CloudflareWorkers/Counter/`).
5. **Release automation.** No `.github/workflows/release.yml`, no `Dockerfile`, no Homebrew formula, no signed checksums/SBOM.

### Honest public target support matrix for the beta

The only targets that should be advertised as beta-ready for `contract_source` authors are the **primary triad**. The registry and generated backend status already distinguish them.

| Target | `contract_source` build | `emit --fixture` | Maturity | Notes |
|---|---|---|---|---|
| `evm` | ✅ | ✅ | Experimental | Full validate/plan/package hooks (`ProofForge/Target/BackendRegistry.lean:77-82`). |
| `solana-sbpf-asm` | ✅ | ✅ | Experimental | Full hooks (`ProofForge/Target/BackendRegistry.lean:84-89`). |
| `wasm-near` | ✅ | ✅ | Experimental | Full hooks (`ProofForge/Target/BackendRegistry.lean:91-96`). |
| `wasm-stellar-soroban` | ✅ (Counter only) | ❌ | Counter MVP | Auth/TTL/Stellar CLI follow-on; `emit` unmapped (`ProofForge/Cli/TargetDriver.lean:235-236`). |
| `wasm-cosmwasm` | ✅ (Counter only) | ✅ (counter `.wat`) | Counter MVP | `execute_msg` stub; research spike per README honest claim. |
| `move-aptos` | ❌ | ✅ (counter) | Counter MVP | `sourceInputUnsupported` diagnostic (`ProofForge/Cli/TargetDriver.lean:300-304`). |
| `move-sui` | ❌ | ✅ (counter) | Counter MVP | Fixture-only; scalar storage only. |
| `psy-dpn` | ❌ | ✅ | Spike | Fixture-only; `dargo` optional. |
| `aleo-leo` | ❌ | ✅ | Counter MVP | Fixture-only; requires `leo`. |
| `wasm-cloudflare-workers` | ❌ | ✅ (counter `.ts`) | Counter MVP | Fixture-only TypeScript Worker. |
| `quint` | ❌ | ✅ | CLI-only verification | Not in `--list-targets`. |

Source of truth: `docs/generated/backend-status.md:7-19` (generated from `proof-forge --list-targets --json`) and `ProofForge/Target/Registry.lean:150-453` (`support.inputModes`).

---

## 2. Concrete First-Run Defects

### 2.1 README/AGENTS onboarding command uses the wrong `--module` value

`README.md:103` and `AGENTS.md:73` tell users to run:

```sh
lake env proof-forge build --target evm --root . --module contract \
  -o build/evm/Counter.bin Examples/Product/Counter.lean
```

The actual module namespace in `Examples/Product/Counter.lean:10` is `Counter`, not `contract`. Running the documented command fails with:

```
no spec : ProofForge.Contract.ContractSpec found while loading module contract
```

The same `--module contract` pattern is copy-pasted into `docs/validation-gates.md:60`, `docs/zh/validation-gates.zh.md:57`, `docs/development-log.md:10554`, and others. This is the single biggest first-run blocker.

### 2.2 `proof-forge init` is monorepo-only

`ProofForge.Cli.Scaffold.initCommand` (`ProofForge/Cli/Scaffold.lean:214-252`) locates templates by:

1. Looking for `templates/portable-counter/Counter.lean` in `LEAN_SRC_PATH` entries (`ProofForge/Cli/Scaffold.lean:147-168`).
2. Walking up to 32 parent directories from the current directory (`ProofForge/Cli/Scaffold.lean:160-168`).

If neither finds the monorepo, it errors:

```
proof-forge init could not locate templates/portable-counter; run from a ProofForge checkout or set LEAN_SRC_PATH
```

A released binary cannot scaffold a standalone project. Only one template exists (`defaultTemplateId := "portable-counter"`, `ProofForge/Cli/Scaffold.lean:13-14`).

### 2.3 `lake update` in a scaffolded project fetches the whole repository from GitHub

The template `lakefile.lean` requires ProofForge as a Git dependency:

```lean
require proofForge from git
  "{{PROOF_FORGE_GIT_URL}}" @ "main"
```

`ProofForge/Cli/Scaffold.lean:10-11`, `templates/portable-counter/lakefile.lean:10-11`.

`resolveGitUrl` defaults to `https://github.com/DaviRain-Su/proof_forge.git` (`ProofForge/Cli/Scaffold.lean:10-11,196-200`). Running `lake update` in a scaffolded project therefore clones the entire repo from GitHub, which timed out at 180 s in prior onboarding tests. The template README also instructs `lake build proofForge:proof-forge` (`ProofForge/Cli/Scaffold.lean:63`), forcing a full source build of the compiler inside the user’s project instead of using a released binary.

### 2.4 Chinese documentation has hundreds of broken links and formatting defects

A mechanical scan of `docs/zh/` found **305 likely broken internal links**. Representative examples:

| File | Broken link | Tries to resolve |
|---|---|---|
| `docs/zh/onboarding.zh.md` | `validation-gates.md` | `docs/zh/validation-gates.md` (should be `validation-gates.zh.md`) |
| `docs/zh/decisions.zh.md` | `zh/review-checklist.md` | `docs/zh/zh/review-checklist.md` (double `zh/`) |
| `docs/zh/decisions.zh.md` | `rfcs/0005-solana-sbpf-assembly-backend.md` | `docs/zh/rfcs/...` (no `.zh.md` sibling) |
| `docs/zh/targets-README.zh.md` | `move-family.md` | `docs/zh/move-family.md` (should be `move-family.zh.md` or `../targets/move-family.md`) |

Additionally, `docs/zh/INDEX.zh.md:76` and `docs/zh/INDEX.zh.md:108` have Markdown formatting glitches where bullet lines are merged with preceding text.

Translation sync is also **4 docs behind**:

```
4 doc(s) need translation:
  docs/decisions.md
  docs/capability-registry.md
  docs/implementation-backlog.md
  docs/validation-gates.md
```

This causes `just docs-check` (`justfile:1199-1200`) to exit non-zero on `main`.

### 2.5 CLI lacks basic product affordances

- `--version` is unimplemented. `lake env proof-forge --version` prints `unknown option: --version` and dumps the global legacy usage.
- Subcommand `--help` is not honored: `proof-forge build --help` and `proof-forge emit --help` return `unknown option: --help` (`ProofForge/Cli/Usage.lean:23` starts help with **"Usage (legacy + full surface):"** and 150+ legacy flags).
- No `CHANGELOG.md` or release tags exist, so users have no migration narrative despite RFC 0012 versioning policy being accepted.

### 2.6 `check` product verb has a stale stub message

`ProofForge/Cli/TargetFirst.lean:218` still says `proof-forge check is not yet implemented`, even though `ProofForge.Cli.main` dispatches `check` natively (`ProofForge/Cli.lean:362-376,402-403`). This contradicts the documented support matrix and confuses users who hit the rewrite path.

---

## 3. How to Automate i18n Link-Check and First-Run Smoke Tests in CI

### 3.1 i18n link-check gate

Current state: `scripts/i18n/check-sync.sh` only checks translation freshness; it does not validate links. `just docs-check` (`justfile:1199-1200`) runs `scripts/i18n/check-sync.sh` but not a link checker.

Recommended addition:

1. Create `scripts/i18n/check-links.py` that:
   - Walks `docs/zh/**/*.md`.
   - Extracts internal Markdown links `](path)`.
   - Resolves each path relative to the source file.
   - Accepts either a sibling `.zh.md` target or a fallback `../<name>.md` English target.
   - Exits non-zero on broken links and prints file/line/link.
2. Call it from `scripts/i18n/check-sync.sh` (or directly from `just docs-check`) before/after the translation-sync check.
3. Fix the link convention first: all links from `docs/zh/` should point to sibling `.zh.md` files when the translation exists, or to `../<en>.md` for intentional English fallbacks.
4. For external links, optionally add `lychee` or `markdown-link-check` in a separate non-blocking job.

This gate should run on every PR because `docs/zh/*.zh.md` must only be modified on `main` per `docs/development-standards.md:76-81`, so catching link rot on `main` is sufficient.

### 3.2 First-run smoke test in CI

Current state: the following recipes already implement first-run validation but **are not invoked in `.github/workflows/ci.yml`**:

- `just portable-init-smoke` (`justfile:833-834`) → `scripts/portable/init-smoke.sh`
- `just portable-check-smoke` (`justfile:841-842`) → `scripts/portable/check-smoke.sh`
- `just portable-evm-client` (`justfile:845-846`) → `scripts/portable/evm-client-smoke.sh`
- `just portable-foundry-workspace` (`justfile:837-838`) → `scripts/portable/foundry-workspace-smoke.sh`

Recommended CI changes:

1. Add to the required `product` job (after `just product`):
   ```yaml
   - name: First-run scaffold + build smoke
     run: just portable-init-smoke
   - name: First-run check smoke
     run: just portable-check-smoke
   ```
2. Add to the `build-test` job:
   ```yaml
   - name: First-run EVM client + Foundry workspace
     run: |
       just portable-evm-client
       just portable-foundry-workspace
   ```
3. Add a step that literally runs the corrected README first-build command, so copy-paste drift is caught mechanically:
   ```sh
   lake env proof-forge build --target evm --root . \
     -o build/evm/Counter.bin \
     Examples/Product/Counter.lean
   ```
4. For CI speed, the existing scripts set `INIT_USE_LOCAL_PROOF_FORGE=1` and rewrite the scaffolded `lakefile.lean` to use a relative path (`../..`). For a released binary, add a `--local` init mode or a bundled dependency path so external users are not forced to clone from GitHub.
5. Cache `.lake/packages` in GitHub Actions to mitigate the `lake update` network fetch.

---

## 4. Realistic Public Beta Scope and First Release Version Content

### 4.1 Version

Follow RFC 0012 (`docs/rfcs/0012-versioning-and-compatibility-policy.md:91-104`): pre-1.0 semver-ish. First public beta should be tagged **`v0.1.0-beta.1`**.

### 4.2 Beta scope

**In scope:**

- Primary triad targets only: `evm`, `solana-sbpf-asm`, `wasm-near`.
- Product authoring path: `ProofForge.Contract.Source` contracts (`Counter`, `ValueVault`, `Ownable`, `Token` via `TokenSpec`, `RemoteCall`) compiled with `proof-forge build --target <id>`.
- `proof-forge check --target <id>` diagnostics (JSON/text) for the primary triad.
- `proof-forge init` scaffolding a standalone project from the released binary.
- Generated per-project SDK packages: `proof-forge-sdk.json`, `proof-forge-client.ts`, `proof-forge-artifact.json`, and `proof-forge-deploy.json` (where applicable).
- English documentation corrected and Chinese documentation link layer repaired.
- `CHANGELOG.md` with “Breaking / Migration” sections.

**Explicitly out of beta scope:**

- Secondary/research targets: `wasm-cosmwasm`, `wasm-stellar-soroban`, `wasm-cloudflare-workers`, `move-aptos`, `move-sui`, `psy-dpn`, `aleo-leo`. These stay Counter-MVP/fixture-only/spike and must not be advertised as product authoring targets.
- Generic multi-chain `proof-forge deploy` beyond the existing EVM/Anvil smoke harness.
- Published npm/cargo SDK packages (clients are generated per project).
- Native Windows builds (start with Linux x86_64 + macOS x86_64/ARM).

### 4.3 First release bundle content

A GitHub Release `v0.1.0-beta.1` should ship:

1. **Binaries**
   - `proof-forge-linux-x86_64`
   - `proof-forge-macos-x86_64`
   - `proof-forge-macos-arm64`
   - SHA-256 checksums for each.
2. **Template archive**
   - `templates/portable-counter/` with `lakefile.lean` rewritten to use a bundled or path-based ProofForge dependency (not a Git clone).
3. **Docs archive**
   - README, INDEX, onboarding, product-sdk, validation-gates, generated backend-status, and repaired Chinese translations.
4. **Install script**
   - `install.sh` that detects OS/arch, downloads the binary + templates, and places them under `~/.proof-forge/<version>/` with a symlink in `~/.local/bin`.
5. **`CHANGELOG.md`** at repo root.
6. **Source tarball** (GitHub auto-generated) for users who want to build from source.

### 4.4 Acceptance criteria for the beta

An external user on a clean machine should be able to:

```sh
./install.sh
proof-forge --version            # prints v0.1.0-beta.1 + lean-toolchain + git sha
proof-forge init my-counter
cd my-counter
lake update                      # fast, no full-repo Git clone
just build-evm
just build-solana
just build-near
```

and obtain deterministic artifacts plus a valid `proof-forge-sdk.json` for each target.

---

## Top 3 Findings

1. **The first command in README/AGENTS is broken.** The documented `--module contract` will fail for every new user; it must be `--module Counter` or omitted. This is a beta-blocking onboarding defect.
2. **`proof-forge init` and the scaffolded `lakefile.lean` assume a monorepo/GitHub source fetch.** A released binary cannot scaffold standalone projects, and first `lake update` clones the entire repository. Templates and dependency resolution must be bundled or side-carred.
3. **First-run smokes exist but are not in CI.** `portable-init-smoke`, `portable-check-smoke`, and `portable-evm-client` already validate the external-developer path, yet `.github/workflows/ci.yml` runs only `just product`. Adding them to the required `product`/`build-test` jobs is the fastest way to prevent regressions in the release path.
