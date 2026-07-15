# Artifact Contract v1 (draft)

Status: **Draft contract for Seam B (evidence layer)**

Parent design: [Lean / Rust boundary](2026-07-15-lean-rust-boundary-design.md)
([中文](2026-07-15-lean-rust-boundary-design.zh.md))

Chinese: [2026-07-15-artifact-contract-v1.zh.md](2026-07-15-artifact-contract-v1.zh.md)

Authority until code freezes fields: **checked-in Lean emitters + this document**;
when they disagree, code wins and this draft must be updated in the same change.

This is the Phase 0 deliverable shape: document what Rust harnesses and
differential scripts may rely on. It does **not** introduce a Rust compile path.

## Purpose

Consumers (testkit harnesses, compare benches, CI scripts) must treat
`proof-forge-artifact.json` and related sidecars as a versioned API:

- required top-level fields
- typed output inventory (`artifactBundle`)
- path/hash entries for files that runners load
- honesty rules (no green validation when tools are missing)

## Schema identity

| Item | Value |
|---|---|
| Document schema | `proof-forge-artifact` consumer contract |
| Current `schemaVersion` | `1` (integer or string `"1"` as emitted by CLI paths; consumers should accept both) |
| Nested bundle kind | `proof-forge-artifact-bundle` with its own `schemaVersion: "1"` |
| Breaking change rule | Bump top-level `schemaVersion`; keep dual-read for one release when possible |

Related but **separate** contracts (do not conflate):

| Contract | Identity | Notes |
|---|---|---|
| SDK schema | `proof-forge.sdk-schema.v0` / `SdkSchema.schemaVersion = 0` | Client generation |
| Deploy manifest | e.g. `proof-forge-evm-deploy-manifest` | Chain deploy helpers |
| Benchmark result | `proof-forge.benchmark-result.v1` | Cost/behavior benches |
| Core export | `core.v0` (experimental) | Seam A; [draft](2026-07-15-core-export-v0-draft.md) |
| Observation / scenario | testkit scenario + harness trace | Version independently |

## File layout (typical product build)

Exact filenames vary by CLI flags; harnesses should prefer metadata pointers
over hard-coded paths when present.

```text
build/<target>/<Module>/
  proof-forge-artifact.json          # required metadata entrypoint
  proof-forge-deploy.json            # optional deploy sidecar (EVM often)
  *.yul | *.s | *.wat                # intermediate (target-dependent)
  *.bin | *.so | *.wasm              # final deployable (target-dependent)
  proof-forge-sdk.json               # optional SDK schema
  proof-forge-client.ts              # optional client wrapper
```

Default metadata basename helpers live in `ProofForge.Cli.Artifact`
(`defaultArtifactOutput`, `defaultDeployManifestOutput`).

## Top-level fields (consumer minimum)

Observed on primary-triad CLI artifacts (e.g. EVM ValueVault) and enforced in
spirit by `ProofForge.Target.ArtifactBundle` honesty checks.

| Field | Required for runners | Meaning |
|---|---|---|
| `schemaVersion` | **yes** | Contract major version (`1`) |
| `target` | **yes** | Public target id (`evm`, `solana-sbpf-asm`, `wasm-near`, …) |
| `targetFamily` | recommended | Family grouping (`evm`, …) |
| `artifactKind` | **yes** | Primary claim (`evm-bytecode`, `solana-elf`, …) |
| `sourceModule` | **yes** | Module / product identity string |
| `sourceKind` | recommended | e.g. `contract-sdk`, `portable-ir`, fixture kinds |
| `fixture` | optional | Fixture id when not a free product path |
| `irVersion` | optional | Set for portable-IR fixtures; may be null for SDK sources |
| `capabilities` | recommended | Capability id list used/declared |
| `abi` | target-dependent | Entrypoints/constructor/events (EVM heavy; others may differ) |
| `artifacts` | **yes** for file loading | Map or list of named file refs with path + sha256 + bytes |
| `artifactBundle` | **yes** for honesty | Typed multi-output bundle (PF-P1-03) |
| `toolchain` | recommended | Tool path/version observations |
| `validation` | recommended | Named validation outcomes |
| `storageBinding` / `materialization` / `preflight` / `crosscallMaterialization` | optional for most runners | Planning metadata; do not invent runtime behavior from these alone |
| `sdkSchema` | optional | Relative/path pointer to SDK schema file |
| `storageLayout` | optional | Target storage description |

### File reference shape

Wherever a file is named for consumption, prefer:

```json
{
  "path": "relative/or/absolute",
  "sha256": "<64 hex>",
  "bytes": 1234
}
```

Harnesses that verify integrity must re-hash the file and compare `sha256` /
`bytes` when those fields are present (testkit already supports nested
`[[artifact.file]]` checks against metadata).

## `artifactBundle` (typed inventory)

Serialized by `ProofForge.Target.ArtifactBundle.ArtifactBundle.toJson`:

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | `"1"` |
| `kind` | string | `proof-forge-artifact-bundle` |
| `targetId` | string | Same public target id |
| `source` | object | `moduleName`, optional `path`, `kind`, `leanElaborated` |
| `outputs` | array | Typed outputs (see below) |
| `primaryOutput` | string or null | Output `kind` treated as primary |
| `finalOutput` | string or null | Final deployable kind when present |
| `toolchain` | array | Tool provenance entries |
| `validations` | array | Named validation entries |

### Typed output

| Field | Notes |
|---|---|
| `kind` | Stable id: `yul`, `evm-bytecode`, `evm-initcode`, `sbpf-asm`, `solana-elf`, `wat`, `wasm`, … |
| `role` | `intermediate` \| `primary` \| `final-deployable` \| `sidecar` |
| `path` | optional path string |
| `sha256` | optional |
| `bytes` | optional |

### Tool provenance

| Field | Notes |
|---|---|
| `tool` | e.g. `lean`, `solc` |
| `stage` | e.g. `source-elaboration`, compile/link stages |
| `available` | bool |
| `version` / `declaredVersion` / `observedVersion` | optional strings |

### Validation entry

| Field | Notes |
|---|---|
| `name` | Stable check name |
| `state` | `notRun` \| `passed` \| `failed` \| `unavailable` |
| `detail` | optional |

### Honesty rules (must remain fail-closed)

From `ArtifactBundle.validateHonesty` (normative for emitters):

1. If `finalOutput` is set, a matching output kind exists with role
   `final-deployable` or `primary`.
2. If `primaryOutput` is set, that kind exists in `outputs`.
3. `leanElaborated=true` requires Lean source-elaboration toolchain provenance
   matching `lean-toolchain` / running Lean; mismatch is an error.
4. `leanElaborated=false` must not carry source-elaboration toolchain entries.
5. Unavailable tools must not be reported as validation `passed`
   (`unavailable` or `failed` only).
6. `notRun` must never be serialized as a successful pass for a required gate.

## Primary-triad final kinds (runner orientation)

| Target id | Typical intermediate | Typical final | Common runner input |
|---|---|---|---|
| `evm` | `yul` | `evm-bytecode` (+ `evm-initcode` sidecar) | runtime bytecode / initcode per scenario |
| `solana-sbpf-asm` | `sbpf-asm` | `solana-elf` when `sbpfBuild=passed` | ELF for Mollusk/product scenarios |
| `wasm-near` | `wat` | `wasm` | wasm (+ metadata) for offline-host / sandbox |

Runners must fail closed if the advertised final kind is missing or marked
failed/unavailable.

## What Rust may depend on (Phase 0 allowlist)

Safe for harnesses without treating optional planning fields as ABI:

1. `schemaVersion`, `target`, `sourceModule`, `artifactKind`
2. `artifactBundle.finalOutput` / `primaryOutput` + matching `outputs[]`
3. File refs under `artifacts` / output `path`+`sha256`
4. Target-specific ABI/entrypoint tables **only** where the harness already
   documents encoding (EVM selectors, Solana tags, NEAR method names)
5. Scenario-declared `[[artifact.*]]` checks in testkit TOML

Avoid hard-coding:

- absolute machine-specific path prefixes without re-resolving from metadata
- assuming bytecode equality across `solc` versions
- reading CanonicalEvidence or diagnostics as semantic inputs

## Dual-run / evidence comparison

When comparing Lean-produced vs future Rust-produced artifacts, gate on:

1. Runtime observation parity (testkit traces)
2. Entrypoint/ABI surface parity on declared fields
3. Matching `target` + final output kind + content hashes of listed final files
4. Optional normalized intermediate text if a normalizer is defined

Do **not** require full JSON deep equality of entire artifact documents
(toolchain path strings and free-form notes drift).

## Phase 0 implementation checklist (future branch)

- [ ] Inventory all CLI emitters of `proof-forge-artifact.json` against this table
- [ ] Add a Lean or golden test that fails when required consumer fields disappear
- [ ] Teach testkit core to reject missing `schemaVersion` / `target` /
      final output when a scenario declares execution
- [ ] Document observation JSON fields next to this contract (separate version)
- [ ] Keep per-harness packages free of multi-chain SDK package deps

## Non-goals for this draft

- Freezing Core export (see [core export v0](2026-07-15-core-export-v0-draft.md))
- Changing on-disk artifact layout
- Declaring Rust backends production-ready
