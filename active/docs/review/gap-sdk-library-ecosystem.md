# SDK / Library Ecosystem Gap Analysis

**Dimension:** `sdk-library-ecosystem`
**Scope:** What ProofForge ships *around* the compiler so that external developers can build, distribute, and integrate contracts the way they expect from a production-grade platform: published SDK packages, generated client libraries, templates, language bindings, package-manager metadata, and a stable programmatic surface.

**Date:** 2026-07-10

---

## Executive summary

ProofForge has a working *internal* SDK pipeline: a unified `proof-forge-sdk.json` schema, per-target TypeScript client stubs, a project scaffold, and CI validation for the generated artifacts. However, almost none of it is packaged or published for external consumption. The generated clients are minimal, rely on global mutable state, lack peer-dependency manifests, and cover only a subset of targets and languages. There is no stable library API outside the CLI, only one project template, and no release tags or registry distribution. For a real product, the ecosystem dimension is still largely compiler-for-internal-use rather than a developer-facing SDK.

**Maturity score:** **4 / 10**

- Strong points: schema, client generation, CI gates, docs, versioning policy.
- Weak points: distribution, packaging, client depth, language coverage, templates, programmatic API.

---

## What is healthy / complete

| Area | Evidence | Notes |
|---|---|---|
| Unified SDK schema | `ProofForge/Contract/SdkSchema.lean:11–15`, `build/sdk/evm/proof-forge-sdk.json`, `build/sdk/solana-sbpf-asm/proof-forge-sdk.json` | `proof-forge.sdk-schema.v0` / `portable-ir-v0` are emitted and validated. |
| SDK layout validation | `scripts/sdk/validate-sdk-layout.py:8–41`, `justfile:85–97` (`sdk-schema`) | Required files per target are checked in CI. |
| TypeScript client generation | `ProofForge/Contract/Client.lean:191–215` (EVM), `ProofForge/Backend/Solana/Client.lean:7–143` (Solana), `ProofForge/Contract/Client.lean:253–282` (NEAR), `build/sdk/move-sui/proof-forge-client.ts` (Sui) | EVM, Solana, NEAR, and Sui all emit a TS client sketch. |
| Generated-client smoke tests | `scripts/portable/evm-client-smoke.sh`, `scripts/sui/client-ts-smoke.sh` | At least EVM and Sui generated clients are type-checked/exercised. |
| Project scaffold | `ProofForge/Cli/Scaffold.lean:214–252`, `templates/portable-counter/` | `proof-forge init` produces a runnable multi-target Counter project. |
| Versioning policy | `docs/rfcs/0012-versioning-and-compatibility-policy.md:24–35`, `ProofForge/Contract/SdkSchema.lean:11–15` | Semver-ish SDK/CLI rules and IR schema rules are documented. |
| Product SDK docs | `docs/product-sdk.md`, `docs/product-sdk-gap-plan-2026-07.md` | Clear author-path narrative exists. |

---

## Gaps

### 1. No published, versioned SDK packages or release artifacts

| | |
|---|---|
| **Area** | Package distribution / release management |
| **Evidence** | - `git tag -l` returns **no release tags**.<br>- No root `package.json`, `Cargo.toml` for a published SDK, or `setup.py`/`pyproject.toml` (`Glob` found none at repo root; only internal `testkit`/benchmark/example manifests).<br>- Generated clients are plain files inside `build/sdk/<target>/` (e.g. `build/sdk/evm/proof-forge-client.ts:1`), not installable packages.<br>- Template `templates/portable-counter/lakefile.lean:10–11` pins the Lean dependency to the Git repo `@ "main"`, not a released version. |
| **Severity** | **Blocker** for external adoption |
| **Remediation** | - Publish semver-tagged releases (`v0.x.y`).<br>- Ship `@proof-forge/evm-client`, `@proof-forge/solana-client`, `@proof-forge/near-client`, `@proof-forge/sui-client` on npm with `package.json`, `peerDependencies`, and `types`.<br>- Publish the Lean library as a tagged Lake dependency (or eventually to a registry).<br>- Add a `CHANGELOG.md` and release-notes process. |

### 2. Generated client libraries are minimal and not production-grade

| | |
|---|---|
| **Area** | Generated client code quality / usability |
| **Evidence** | - EVM wrapper uses a **global mutable** `contract` / `iface` (`ProofForge/Contract/Client.lean:126–137`, `206–214`); no typed struct args; `typeToTs` collapses `fixedArray`/`structType`/`array` to `any[]` / `Record<string, any>` (`ProofForge/Contract/Client.lean:33–34`).<br>- Solana client only supports `le-u64`, `le-u32`, `u8-bool`, and `raw-bytes` encodings and throws on anything else (`ProofForge/Backend/Solana/Client.lean:57–83`). Account pubkeys must be supplied manually; no PDA derivation helper in the client (`ProofForge/Backend/Solana/Client.lean:85–98`).<br>- NEAR wrapper is also global-mutable (`ProofForge/Contract/Client.lean:274–280`) and only handles scalar args via a flat args object.<br>- Sui generated client is explicitly labeled a *sketch* and returns `unknown` for every call (`build/sdk/move-sui/proof-forge-client.ts:1`, `12`, `34–51`).<br>- No generated package manifests: `scripts/sdk/validate-sdk-layout.py:8–41` does not require `package.json` / `tsconfig.json`, and the emitted files `import { ethers }` / `near-api-js` / `@solana/web3.js` without declaring peer deps. |
| **Severity** | **High** |
| **Remediation** | - Emit per-target `package.json` with correct `peerDependencies` and `devDependencies`.<br>- Generate typed input/return interfaces from IR structs/arrays.<br>- Add Solana transaction builder + PDA derivation, NEAR `near-api-js` transaction helpers, and EVM event filters / contract factory.<br>- Add a generated-client test suite that actually calls the offline hosts / local networks. |

### 3. Language and target coverage are incomplete

| | |
|---|---|
| **Area** | Multi-language / multi-target SDK support |
| **Evidence** | - Client generation is TypeScript-only. No Rust, Python, Go, or mobile SDKs are generated.<br>- Soroban and CosmWasm clients are explicit **stubs**: `renderSorobanWrapper` / `renderCosmWasmWrapper` only emit `connect`, `entrypoints`, and `getContractId`/`getContractAddress` (`ProofForge/Contract/Client.lean:284–340`).<br>- Aleo/Leo, Aptos, and Psy/DPN targets emit source/circuit artifacts (`ProofForge/Cli/SourcegenCommands.lean:24–138`) but no client library at all.<br>- `ProofForge/Contract/Client.lean:8–18` only defines paths for EVM/NEAR/Solana/Soroban/CosmWasm wrappers; Aleo/Aptos/Psy/Sui paths are absent (Sui client is rendered elsewhere in `ProofForge/Backend/Move/Sui.lean`). |
| **Severity** | **High** |
| **Remediation** | - Finish Soroban/CosmWasm TS clients with real RPC/auth/funds helpers.<br>- Add Rust client crate (especially valuable for NEAR/Solana ecosystems).<br>- Add Python/Go SDKs at least for EVM and NEAR, where those languages are common.<br>- Generate clients for every registered `--list-targets` backend. |

### 4. No stable programmatic library API; the CLI is the only public surface

| | |
|---|---|
| **Area** | Embedding / library API |
| **Evidence** | - `ProofForge.Cli.Command` enum only exposes `build`, `emit`, `check`, `init`, `metadata`, `listTargets`, `listFixtures` (`ProofForge/Cli/Options.lean:19–27`).<br>- `ProofForge/Cli/Usage.lean:3–187` documents CLI commands only; there is no documented function-level API for loading a Lean module, resolving a spec, lowering to IR, or emitting artifacts from another tool.<br>- All SDK-schema/client writing functions live in `ProofForge.Cli` (`ProofForge/Cli/Artifact.lean:102–124`, `126–135`) rather than a reusable `ProofForge.Sdk` library namespace. |
| **Severity** | **Medium–High** (blocks IDE integrations, CI plugins, cloud platform) |
| **Remediation** | - Define a public `ProofForge.Sdk` API with stable types for `ContractSpec`, `CapabilityPlan`, artifact emission, and SDK-schema rendering.<br>- Version the API under the RFC 0012 policy.<br>- Provide small embedding examples (e.g. from a Rust or Python host). |

### 5. Project template ecosystem is thin

| | |
|---|---|
| **Area** | Scaffolding / examples as reusable starting points |
| **Evidence** | - `ProofForge/Cli/Scaffold.lean:13–15` hard-codes `defaultTemplateId := "portable-counter"`.<br>- `parseInitOptions` rejects any `--template` value other than `portable-counter` (`ProofForge/Cli/Scaffold.lean:109–124`).<br>- `templates/portable-counter/` only contains a Counter; no Token, Vault, Staking, or AccessControl templates.<br>- README (`README.md:89`) still advertises the same single starter. |
| **Severity** | **Medium** |
| **Remediation** | - Add `portable-token`, `portable-vault`, `portable-ownable`, and `portable-staking` templates.<br>- Allow `proof-forge init --template <id>` to discover templates from a directory.<br>- Add a template validation gate that builds each template to at least two targets. |

### 6. Versioning policy is documented but not enforced by tooling

| | |
|---|---|
| **Area** | Schema / SDK compatibility enforcement |
| **Evidence** | - RFC 0012 M3 ("CI check that warns when a PR changes IR constructors without updating `irVersion`") and M4 are still **open** (`docs/rfcs/0012-versioning-and-compatibility-policy.md:120–121`).<br>- `ProofForge/Contract/SdkSchema.lean:11–15` uses `schemaVersion := 0` and `irVersion := "portable-ir-v0"` with no automated bump logic.<br>- No release tags exist, so the Semver policy has no practical anchor. |
| **Severity** | **Medium** |
| **Remediation** | - Implement the M3 CI check (diff IR constructors / capability registry and require version bump).<br>- Automate `schemaVersion`/`irVersion` bumping or fail CI on manual mismatch.<br>- Start tagging releases so the compatibility policy is observable. |

### 7. No dedicated SDK/API documentation site or typedoc

| | |
|---|---|
| **Area** | Developer documentation / API reference |
| **Evidence** | - Docs are Markdown files in `docs/`; there is no generated TypeDoc/Rustdoc/API reference for the generated clients or the Lean authoring API.<br>- `docs/product-sdk.md` is high-level; generated client functions are not documented. |
| **Severity** | **Low–Medium** |
| **Remediation** | - Generate TypeDoc for emitted TS clients and Rustdoc for the testkit/harness crates.<br>- Publish a docs site (even a simple GitHub Pages / Codeberg Pages render) with search. |

---

## Top 5 gaps (prioritized)

1. **No published/versioned SDK packages** — everything is local files; no npm/crate/PyPI releases, no tags, no `CHANGELOG`. This is the biggest blocker to real-world adoption.
2. **Generated clients are too minimal** — global mutable state, weak typing, no peer-dependency manifests, no transaction/signing/PDA helpers; not safe to ship.
3. **Incomplete language & target coverage** — only TypeScript for four targets; Soroban/CosmWasm are stubs; Aleo/Aptos/Psy have no client.
4. **No stable programmatic API** — the CLI is the only public surface; embedding in other tools/IDEs/cloud requires a versioned `ProofForge.Sdk` library.
5. **Single project template** — only `portable-counter` exists; no Token/Vault/AccessControl starters, and the CLI rejects other template ids.

---

## Overall maturity score: 4 / 10

ProofForge has laid the groundwork (schema, codegen, CI, docs, policy), but the *ecosystem* dimension remains a compiler-for-the-monorepo rather than a distributed, multi-language SDK product. Closing the packaging and client-quality gaps would move this score to 6–7; closing language coverage and programmatic API gaps would push it toward production-grade.
