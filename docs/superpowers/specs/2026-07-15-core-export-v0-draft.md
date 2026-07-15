# Core Export v0 (draft)

Status: **Experimental draft (not a stable product API); LR-1a serializer + pf-core-inspect landed on PR #105 branch**  
Parent design: [Lean / Rust boundary](2026-07-15-lean-rust-boundary-design.md)  
Companion: [Artifact Contract v1](2026-07-15-artifact-contract-v1.md)

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

## Suggested directory layout

```text
build/export/<module>/<targetId>/
  export-meta.json           # versions, hashes, toolchain, git identity
  source-manifest.json       # product path, target request, input digests
  core.v0.json               # checked module (experimental schema)
  capability-plan.v0.json    # resolved capabilities for this target
```

Optional later:

```text
  plan.v0.json               # A0: Lean-built TargetPlan dump for dual-run
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

Include in `contentHash` (canonical bytes, deterministic key order):

- `core.v0` semantic body
- `capability-plan.v0` body
- `targetId`, `moduleName`, schema ids

**Exclude** from `contentHash`:

- absolute paths, wall-clock timestamps
- CanonicalEvidence (source maps, diagnostic spans, migration traces)
- free-form notes, pretty-print whitespace variants (hash canonical encoding only)
- git dirty flags if they do not affect semantic body

This matches architecture: evidence must not affect capability selection, target
plans, rendered artifacts, or semantic artifact hashes.

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

## Rust consumers (Phase 1)

| Consumer | Role |
|---|---|
| `pf-core-inspect` | Schema validate, print summary, recompute contentHash (no chain SDK) |
| Future `pf-backend-*` | Phase 2+ lowering only after dual-run policy exists |

Rust must not treat missing Validate as soft-success. If Lean would refuse to
export, Rust backends must refuse to lower.

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


## Implementation status (LR-1a)

| Piece | Location | Notes |
|---|---|---|
| Lean serializer | `ProofForge/IR/Core/Export.lean` | Validate then JSON; refuse on Validate error |
| Lean gate | `just core-export-v0` / `Tests/Canonical/CoreExport.lean` | Determinism + fail-closed |
| Rust inspect | `tools/pf-core-inspect` | Zero chain SDKs; checks `core.v0` / optional plan |
| CLI product path | not yet | Full `export-core` waits for quieter cutover + LR-1 |
