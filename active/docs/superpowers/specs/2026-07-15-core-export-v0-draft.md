# Core Export v0 (draft)

Status: **Experimental draft (not a stable product API); Seam A LR-0…2g landed on PR #105 branch**

Parent design: [Lean / Rust boundary](2026-07-15-lean-rust-boundary-design.md)
([中文](2026-07-15-lean-rust-boundary-design.zh.md))

Companion: [Artifact Contract v1](2026-07-15-artifact-contract-v1.md)
([中文](2026-07-15-artifact-contract-v1.zh.md))

Chinese: [2026-07-15-core-export-v0-draft.zh.md](2026-07-15-core-export-v0-draft.zh.md)

Do **not** implement as a default CLI product path until primary-triad authoring
cutover and HostOp identity work have settled enough that export churn is
acceptable. Prefer label **`core.v0` / experimental** until then; promote to
`core.v1` only with an explicit decision and dual-run window.

## Purpose

Serialize **checked** Canonical Core plus resolved CapabilityPlan so external
tools (Rust inspect, later optional backends) can consume meaning without
parsing Lean sources or linking Lean objects.

Lean remains the authority for Validate and Semantics. Export is a **lossless
enough projection** of the checked semantic program for lowering and hashing.

## When export is allowed

Export only after all of the following succeed:

1. Frontend materialize / normalize into Canonical Core
2. `IR.Core` type/validate (fail-closed)
3. CapabilityPlan resolution for the requested target profile
4. HostOp exact-id/version resolution for the selected target

On any failure: **no export directory** (or only a diagnostics JSON outside the
semantic hash tree). Fail-closed alignment with Validate is a Phase 1 gate.

## Package directory layout (normative for experimental Seam A)

```text
build/export/<id>/<targetId>/
  core.v0.json                 # checked Canonical Core (in contentHash)
  capability-plan.v0.json      # requirements + hostOpHandlers + targetHostOpCatalog (in contentHash)
  interface.v0.json            # entrypoint surface (outside contentHash)
  export-meta.json             # contentHash = sha256(core file bytes ‖ plan file bytes)
  source-manifest.json         # provenance; outside contentHash
  lean-evm-observe.v0.json     # optional; Lean dual-run surface dump
  evm-storage-sketch.v0.json   # optional; from pf-core-inspect lower-sketch
```

Optional later (not required for dual-run observe):

```text
  plan.v0.json               # full Lean ModulePlan dump for richer dual-run
  core.v0.bincode            # optional compact encoding; JSON remains reference
```

## `export-meta.json` (sketch)

| Field | Meaning |
|---|---|
| `schemaVersion` | Export envelope version (`0` while experimental) |
| `coreSchema` | `core.v0` |
| `capabilityPlanSchema` | `capability-plan.v0` |
| `leanToolchain` | Pin from `lean-toolchain` |
| `leanVersionObserved` | Running Lean version string |
| `gitSha` | Optional; omit or `dirty` when worktree unclean — document policy |
| `targetId` | Public target id requested |
| `moduleName` | Logical module name |
| `contentHash` | Hash of the **semantic package** (see below) |
| `createdBy` | `proof-forge export-core` (or equivalent) |

### Content hash scope

**Implemented rule (LR-1b+):** `contentHash` is the hex SHA-256 of the
**concatenation of the on-disk file bytes** of `core.v0.json` and
`capability-plan.v0.json` in that order (same bytes Lean wrote; do not
re-canonicalize before hashing).

Include in the hashed semantic package:

- `core.v0.json` file bytes
- `capability-plan.v0.json` file bytes (includes `requirements`,
  `hostOpHandlers`, `targetHostOpCatalog`)

**Exclude** from `contentHash`:

- `interface.v0.json`, `source-manifest.json`, observe/sketch sidecars
- absolute paths, wall-clock timestamps
- CanonicalEvidence (source maps, diagnostic spans, migration traces)
- free-form notes

Gates: re-export of the same Counter fixture must yield identical core, plan,
and `export-meta` (including `contentHash`); `pf-core` reloads must recompute
the same hash.

## `source-manifest.json` (sketch)

| Field | Meaning |
|---|---|
| `productPath` | Repo-relative Lean product path when applicable |
| `sourceKind` | `contract-source` / intent / fixture class |
| `requestedTarget` | Target id |
| `inputDigests` | Optional digests of source files for provenance |
| `notPartOfContentHash` | Explicit list of fields excluded from semantic hash |

## `core.v0.json` field families (sketch)

Exact constructors follow Lean `IR.Core` types at implementation time. Export
must be updated when Core shapes change; that cost is why this stays v0 until
cutover quiets.

| Family | Intent |
|---|---|
| `schemaVersion` / `coreSchema` | `0` / `core.v0` |
| `module` | Module identity |
| `types` | Checked type environment needed by ops |
| `state` | Logical state declarations (no physical slots) |
| `entrypoints` | Names, signatures, mutability class, bodies |
| `blocks` / `ops` | ANF/CFG semantic program |
| `hostCalls` | Exact HostOp id + version + use sites |
| `interfaces` / materialization **requirements** | Target-neutral requirements only; no Yul/sBPF/Wasm AST |
| `contentHashContribution` | Optional self-description for hash tools |

**Must not appear in Core export:**

- Target physical layouts (EVM slots, Solana account offsets, Wasm linear addresses)
- Raw target AST nodes
- Frontend Surface / Authored trees
- Proof objects / Lean environment pointers

## `capability-plan.v0.json` (sketch)

| Field | Intent |
|---|---|
| `schemaVersion` | `0` |
| `targetId` | Resolved target |
| `capabilities` | Selected capability ids |
| `hostOpHandlers` | Exact HostOp id/version → handler identity available on target |
| `profileNotes` | Optional non-hashed diagnostics |

## Rust consumers (Seam A pilot)

| Consumer | Role |
|---|---|
| `tools/pf-core` | Load package, verify contentHash, walk ops, dual-run readiness, storage sketch |
| `tools/pf-core-inspect` | CLI: `check`, `summary`, `compare`, `lower-sketch`, `dual-run-observe` (no chain SDKs) |
| Future `pf-backend-*` | Phase 2+ full lower only after dual-run policy + release cycle |

Rust must not treat missing Validate as soft-success. If Lean would refuse to
export, Rust backends must refuse to lower.

## Observe dual-run dimensions (declared; not bytecode)

`pf-core-inspect dual-run-observe <export-dir>` compares:

1. **Entrypoint names** (and mutability when present) — Lean observe vs sketch
   from `interface.v0.json`.
2. **Scalar storage slot order** — Lean provisional slots (from EVM
   `buildFromCore` when available, else sequential Core state indices) vs
   Rust `evm-storage-sketch.v0` provisional slots.

**Not compared:** selectors, event ABI, context semantics, bytecode, gas.

**Sketch eligibility:** pure + storage ops, plus optional `contextRead`,
`emit`, `assert`. HostCall / memory / crosscall modules refuse fail-closed.

Verified products/fixtures: Counter, ValueVault, Ownable (Ownable may use
interface+Core surface dump when ModulePlan selectors are missing).

## Determinism gates (Phase 1)

1. Same inputs + same Lean pin → byte-identical `core.v0.json` and
   `capability-plan.v0.json` (canonical JSON encoding).
2. Validate failure cases produce no semantic export (or only non-hashed
   diagnostics).
3. Round-trip or structural checks: exported hostCalls ⊆ catalog; every call
   has exact version.
4. Subset products only at first: Counter + one stateful product on one target.

## Relationship to TargetPlan (A0)

Optional `plan.v0.json` may dump the **Lean-built** target plan after
`buildFromCore` for dual-run of render-only Rust paths. That plan is
**target-owned** and is not a substitute for Core authority. Plan schema is
per-target and versioned separately from `core.v0`.

## Promotion criteria: v0 → v1

Promote only when:

1. Primary-triad direct authoring path is the product default and residual
   dual routes for Core shape are gone or frozen.
2. HostOp extension boundary (IR-B*) no longer reshapes shared Core weekly.
3. At least one dual-run consumer exists (inspect or backend pilot).
4. A written compatibility policy for breaking Core field changes is accepted
   (decision entry).

## Non-goals

- Stable public SDK promise for `core.v0`
- Exporting Legacy `IR.Module` / `ContractSpec` as the long-term seam
- Replacing Lean Validate with Rust schema checks alone
- Claiming formal verification of a future Rust lowerer by virtue of consuming
  this export


## Implementation status (PR #105 / LR-0…2g)

| Piece | Location | Notes |
|---|---|---|
| Lean serializer | `ProofForge/IR/Core/Export.lean` | Validate then JSON; refuse on Validate error |
| CLI experimental | `proof-forge export-core --experimental` | Fixtures + product paths; not product default |
| Lean gates | `just core-export-v0`, `Tests/Canonical/CoreExport*.lean`, `DualRunObserve.lean` | Determinism, package, hostCall, dual-run dumps |
| Rust loader | `tools/pf-core` | contentHash, walk, sketch, dual-run-observe |
| Rust CLI | `tools/pf-core-inspect` | Zero chain SDKs |
| Goal charter | `docs/agent-goal-prompt-lean-rust-seam-a.md` | Continuous Seam A execution |
