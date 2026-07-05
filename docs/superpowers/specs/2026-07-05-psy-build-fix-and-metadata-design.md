# Psy DPN: Build Fix + Metadata Integration Design

**Date:** 2026-07-05  
**Status:** Design spec (awaiting review)  
**Scope:** Fix `lake build` regressions and review debt on the `update-psy-implment` branch, then wire `ProofForge.Backend.Psy.Metadata` into Psy smoke artifact output. This is the next increment toward full `psy-dpn` support.  
**Related docs:**
- [Psy DPN target note](../../targets/psy-dpn.md)
- [Design decisions](../../decisions.md) (D-047, D-048, D-049)
- [Implementation backlog](../../implementation-backlog.md)
- [Capability registry](../../capability-registry.md)

---

## 1. Goal

Make the current `psy-dpn` branch build cleanly (`lake build`), fix the correctness gaps found in code review, and complete Phase B3 by integrating plan-driven metadata into every Psy smoke artifact.

---

## 2. Background

The branch added `Statement.whileLoop` to the portable IR but did not update every backend that pattern-matches on `Statement`. As a result, `lake build` fails on:

- `ProofForge.Backend.Psy.IR`
- `ProofForge.Backend.WasmNear.IR` (also has a syntax error in the `whileLoop` insertion)
- `ProofForge.Backend.WasmNear.EmitWat`
- `ProofForge.Backend.Evm.Lower`
- `ProofForge.Compiler.TS.Printer`

A code review also surfaced:

- `ProofForge.Backend.Psy.IR.resolveStorageTargetRoot` rejects nested struct-field assignment targets that validation already accepts.
- `ProofForge.Backend.Psy.Plan.stmtContextOps` / `stmtCrosscallTargets` do not recurse into all contained expressions.
- `ProofForge.Backend.Psy.IR` computes `feltBacked` differently for storage-path reads vs writes.
- `ProofForge.Backend.Psy.IR` still contains dead direct-to-string helpers from the pre-AST printer.
- `ProofForge.Backend.Psy.Plan.ContextPlan` is defined but unused.
- `ProofForge.Backend.Psy.Metadata` exists but is not called from any artifact path.

---

## 3. Design

### 3.1 Fix `whileLoop` pattern matches

Because no backend currently supports unbounded `while` loops, the safest fix is to add explicit rejection branches everywhere the case is missing. The message should name the backend, e.g. `"while loops are not supported by <backend> IR v0"`.

| File | Action |
|---|---|
| `ProofForge.Backend.Psy.IR` | Add `whileLoop` rejection to `validateStatement`, `buildStmt`, and `validateStatementIdentifiers`. |
| `ProofForge.Backend.WasmNear.IR` | Repair the corrupted `boundedFor` / `whileLoop` block, then add rejection to both `lowerStatement` and `validateStatementIdentifiers`. |
| `ProofForge.Backend.WasmNear.EmitWat` | Add `whileLoop` rejection to the statement-lowering match. |
| `ProofForge.Backend.Evm.Lower` | Add `whileLoop` rejection to all statement-planning functions that match on `Statement`. |
| `ProofForge.Compiler.TS.Printer` | Add `whileLoop` emission or rejection to the `Stmt` printer match. |

If `ProofForge.Compiler.TS.AST` already supports `whileLoop`, the TS printer should emit a normal `while` statement rather than reject it. If not, it should reject with a clear message.

### 3.2 Fix Psy lowering correctness

**Nested storage targets.**
In `resolveStorageTargetRoot`, when the resolved base is `.structField` or `.arrayStructField`, a subsequent `.field` access should extend a `.path` target rather than error. Likewise, `.arrayGet` on those bases should extend the path with an `.index` segment.

**Context/crosscall collection.**
`stmtContextOps` and `stmtCrosscallTargets` should apply `exprContextOps` / `exprCrosscallTargets` to every `Expr` reachable from a statement, including:
- both operands of `.assertEq`
- map keys, array indices, storage path indices
- event field values
- condition expressions

**Felt-backed U32 consistency.**
After resolving a storage path's type, use a single helper to decide `feltBacked` for both reads and writes. The helper returns `true` when the resolved path type is `.u32` and the state is flagged as felt-backed.

### 3.3 Clean dead code

Remove the legacy direct-to-string helpers and old path validators from `ProofForge.Backend.Psy.IR`:

- `indent`, `lines`, `literal`, `stringLiteral`
- `structDecl`, `stateDecl`, `testBody`
- `storagePathStartType`, `resolveStoragePathType`, `isFeltBackedU32StorageArrayPath`
- old `requireScalarState` / `requireMapState` / `requireArrayState` / `requireStructScalarState` / `requireStructArrayState`

Either delete the unused `ContextPlan` structure in `ProofForge.Backend.Psy.Plan` or replace `PsyModulePlan.contextOps : Array ContextOp` with `ContextPlan`. Deletion is preferred unless a consumer is added in the same change.

### 3.4 Integrate Metadata into artifact output

`ProofForge.Backend.Psy.Metadata.buildPlanArtifactMetadata` produces:

```lean
structure ArtifactMetadata where
  targetId : String
  moduleName : String
  entrypoints : Array AbiEntrypointDescriptor
  events : Array AbiEventDescriptor
  contextOps : Array ContextOpDescriptor
  crosscalls : Array CrosscallDescriptor
  capabilities : Array String
```

The Psy smoke scripts already generate `proof-forge-artifact.json`. Update the generation path to call `buildPlanArtifactMetadata` and merge its fields into the artifact JSON:

- `targetId` → overwrite or validate the existing target id.
- `moduleName` → record the module name.
- `entrypoints` → add an `abi.entrypoints` array.
- `events` → add an `events` array.
- `contextOps` → add a `contextOps` array.
- `crosscalls` → add a `crosscalls` array.
- `capabilities` → validate against the existing capability list from the smoke script.

Keep the existing EVM-compatible artifact schema fields (`bytecode`, `initcode`, etc.) unchanged. The new fields are additive.

### 3.5 Add tests

- `Tests/PsyMetadata.lean`: build `ArtifactMetadata` for Counter, MapProbe, EventProbe, and ContextProbe; assert expected entrypoints, events, context ops, and capabilities.
- Extend at least one smoke script to assert that `proof-forge-artifact.json` contains the new metadata fields after the run.

---

## 4. Testing Plan

1. `lake build` — must pass with no errors.
2. `just check` — must pass.
3. `just psy-diagnostics` — all 59 cases must pass.
4. `just psy-coverage` — IR coverage manifest must remain unchanged.
5. `just psy-golden-sources` — generated `.psy` sources must remain byte-identical.
6. New `Tests/PsyMetadata.lean` — run via `lake env lean --run Tests/PsyMetadata.lean`.
7. At least one smoke script verifies the enriched `proof-forge-artifact.json`.

---

## 5. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Removing dead code breaks a test or script not covered by `just check` | Search all `Tests/` and `scripts/` for references before deletion; run full `lake build` after removal. |
| Metadata integration changes artifact JSON shape and breaks existing validators | Keep fields additive; do not remove existing fields. Update validators in the same change if they check exact field lists. |
| `whileLoop` rejection in EVM Lower interacts with plan-building invariants | Add the case at the same level as `boundedFor` handling; EVM already rejects `whileLoop` in validation, so lowering should never see it in practice. |
| Nested storage target fix changes behavior for existing fixtures | Verify with `just psy-golden-sources` and the storage-nested-aggregate smoke. |

---

## 6. Out of Scope

- Full `whileLoop` support for Psy (requires adding `while` to `ProofForge.Compiler.Psy.AST` and `Printer`).
- Phase C Counter scenario parity.
- Live Psy node/prover deployment research.
- Else-if syntax sugar.
- Memory arrays.

These remain future work after this increment lands.
