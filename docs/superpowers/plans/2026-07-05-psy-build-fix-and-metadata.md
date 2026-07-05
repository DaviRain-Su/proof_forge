# Psy DPN Build Fix + Metadata Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `lake build` and review debt on the `update-psy-implment` branch, then wire `ProofForge.Backend.Psy.Metadata` into Psy smoke artifact output.

**Architecture:** Add explicit `whileLoop` rejection branches to every backend that pattern-matches on `Statement`; fix three Psy lowering correctness issues; remove dead direct-to-string helpers from `Backend.Psy.IR`; expose `buildPlanArtifactMetadata` through a small Lean export runner and merge its fields into the Python artifact writer; add targeted tests.

**Tech Stack:** Lean 4 (v4.31.0), Lake, ProofForge portable IR, `ProofForge.Compiler.Psy.AST`/`Printer`, Dargo CLI, Python 3, bash.

## Global Constraints

- `lake build` must pass after every task group.
- `just psy-diagnostics` must keep all 59 cases passing.
- `just psy-golden-sources` must keep generated `.psy` sources byte-identical.
- `just psy-coverage` must keep the IR coverage manifest unchanged.
- All artifact JSON changes are additive; do not remove existing `proof-forge-artifact.json` fields.
- Follow existing naming conventions (`camelCase` for Lean functions, `Psy` prefix for target-specific types).
- Do not introduce new `Statement` handling semantics beyond explicit rejection; full `whileLoop` support for Psy is out of scope.

---

## File map

| File | Responsibility | Change type |
|---|---|---|
| `ProofForge/Backend/Psy/IR.lean` | Lower portable IR → Psy AST; validation | Add `whileLoop` rejections; fix nested storage targets; fix `feltBacked`; remove dead helpers |
| `ProofForge/Backend/Psy/Plan.lean` | Build semantic plan from IR | Fix `stmtContextOps` / `stmtCrosscallTargets`; remove or use `ContextPlan` |
| `ProofForge/Backend/WasmNear/IR.lean` | WasmNear Rust sourcegen | Fix `whileLoop` syntax error; add rejection case |
| `ProofForge/Backend/WasmNear/EmitWat.lean` | Wasm WAT emission | Add `whileLoop` cases to lit-collection functions |
| `ProofForge/Backend/Evm/Lower.lean` | EVM statement planning | Add `whileLoop` rejection to six statement-matching functions |
| `ProofForge/Compiler/TS/Printer.lean` | TypeScript source printer | Add `whileLoop` emission |
| `Tests/PsyMetadata.lean` | Unit tests for Psy metadata | New file |
| `Tests/PsyMetadataExport.lean` | Export plan metadata as JSON for smoke scripts | New file |
| `scripts/psy/write-artifact-metadata.py` | Generate `proof-forge-artifact.json` | Accept `--plan-metadata` and merge fields |
| `scripts/psy/counter-smoke.sh` (and siblings) | End-to-end Psy smoke | Call export runner, pass JSON to writer |

---

## Task 1: Fix `Statement.whileLoop` in `ProofForge.Backend.Psy.IR`

**Files:**
- Modify: `ProofForge/Backend/Psy/IR.lean`

**Interfaces:**
- Consumes: `IR.Statement.whileLoop`
- Produces: explicit error cases in `validateStatement`, `buildStmt`, `validateStatementIdentifiers`

- [ ] **Step 1: Add `whileLoop` rejection to `validateStatement`**

Find the `validateStatement` function (around line 1104). Insert a new case between `.boundedFor` and `.return`:

```lean
| .whileLoop _ _ =>
    .error { message := "while loops are not supported by Psy IR v0" }
```

- [ ] **Step 2: Add `whileLoop` rejection to `buildStmt`**

Find the `buildStmt` function (around line 1478). Insert a new case between `.boundedFor` and `.return`:

```lean
| .whileLoop _ _ =>
    .error { message := "while loops are not supported by Psy IR v0" }
```

- [ ] **Step 3: Add `whileLoop` case to `validateStatementIdentifiers`**

Find the catch-all pattern in `validateStatementIdentifiers` (around line 1548). Add `| .whileLoop _ _` to the multi-pattern that returns `pure ()`, or add an explicit case:

```lean
| .whileLoop _ body => validateBodyIdentifiers entrypointName body
```

Either form is acceptable; the explicit form is preferred because it documents the recursive validation.

- [ ] **Step 4: Verify**

Run:
```bash
lake build ProofForge.Backend.Psy.IR
```

Expected: build succeeds with no errors.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Backend/Psy/IR.lean
git commit -m "fix(psy): reject Statement.whileLoop in lowering/validation"
```

---

## Task 2: Fix `Statement.whileLoop` in `ProofForge.Backend.WasmNear.IR`

**Files:**
- Modify: `ProofForge/Backend/WasmNear/IR.lean`

**Interfaces:**
- Consumes: `IR.Statement.whileLoop`
- Produces: repaired `boundedFor` branch + explicit `whileLoop` rejection

- [ ] **Step 1: Repair the corrupted `lowerStatement` block**

Find the broken block around line 988-993:

```lean
| .boundedFor _ _ _ _ =>
| .whileLoop _ _ =>
    .error { message := "while loops are not supported by wasm-near IR v0" }
    .error { message := "bounded for loops are not supported by wasm-near IR v0" }
```

Replace it with:

```lean
| .boundedFor _ _ _ _ =>
    .error { message := "bounded for loops are not supported by wasm-near IR v0" }
| .whileLoop _ _ =>
    .error { message := "while loops are not supported by wasm-near IR v0" }
```

- [ ] **Step 2: Add `whileLoop` rejection to `validateStatementIdentifiers`**

Find `validateStatementIdentifiers` (around line 284). It already has a `whileLoop` case at line 295 that recurses into the body. Because WasmNear rejects `whileLoop`, this case can either stay (it validates identifiers in unreachable code) or be merged into a rejection. Leave it as-is; it does no harm and keeps the identifier validator complete.

- [ ] **Step 3: Verify**

Run:
```bash
lake build ProofForge.Backend.WasmNear.IR
```

Expected: build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add ProofForge/Backend/WasmNear/IR.lean
git commit -m "fix(wasm-near): repair whileLoop insertion and reject unbounded loops"
```

---

## Task 3: Fix `Statement.whileLoop` in `ProofForge.Backend.WasmNear.EmitWat`

**Files:**
- Modify: `ProofForge/Backend/WasmNear/EmitWat.lean`

**Interfaces:**
- Consumes: `IR.Statement.whileLoop`
- Produces: explicit handling in `collectArrayLitsStmt` and `collectStructLitsStmt`

- [ ] **Step 1: Add `whileLoop` to `collectArrayLitsStmt`**

Find `collectArrayLitsStmt` (around line 1570). After the `.boundedFor` case, add:

```lean
| .whileLoop c body => collectArrayLitsExpr c ++ body.foldl (fun acc st => acc ++ collectArrayLitsStmt st) #[]
```

- [ ] **Step 2: Add `whileLoop` to `collectStructLitsStmt`**

Find `collectStructLitsStmt` (around line 1638). After the `.boundedFor` case, add:

```lean
| .whileLoop c body => collectStructLitsExpr c ++ body.foldl (fun acc st => acc ++ collectStructLitsStmt st) #[]
```

- [ ] **Step 3: Verify**

Run:
```bash
lake build ProofForge.Backend.WasmNear.EmitWat
```

Expected: build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add ProofForge/Backend/WasmNear/EmitWat.lean
git commit -m "fix(wasm-near): handle Statement.whileLoop in literal collection"
```

---

## Task 4: Fix `Statement.whileLoop` in `ProofForge.Backend.Evm.Lower`

**Files:**
- Modify: `ProofForge/Backend/Evm/Lower.lean`

**Interfaces:**
- Consumes: `IR.Statement.whileLoop`
- Produces: explicit rejection in six statement-matching functions

- [ ] **Step 1: Add rejection to `buildStatementPlan`**

Find `buildStatementPlan` (around line 830). Insert after the `.boundedFor` case:

```lean
| .whileLoop _ _ =>
    .error { message := "while loops are not supported by EVM IR v0; use boundedFor" }
```

- [ ] **Step 2: Add rejection to `collectEventPlansFromStatements` loop match**

Find the `for stmt in statements do` block (around line 1161). Add a case before the final catch-all:

```lean
| .whileLoop _ _ => pure ()
```

Because EVM rejects `whileLoop` earlier, this branch will not execute; it only makes the match exhaustive.

- [ ] **Step 3: Add rejection to `crosscallHelperSpecsFromStatement`**

Find `crosscallHelperSpecsFromStatement` (around line 1405). Insert after `.boundedFor`:

```lean
| .whileLoop _ _ => .ok (#[], env)
```

- [ ] **Step 4: Add rejection to `createHelperSpecsFromStatement`**

Find `createHelperSpecsFromStatement` (around line 1565). Insert after `.boundedFor`:

```lean
| .whileLoop _ _ => #[]
```

- [ ] **Step 5: Add rejection to `localArrayGetLengthsStatement`**

Find `localArrayGetLengthsStatement` (around line 1751). Insert after `.boundedFor`:

```lean
| .whileLoop _ _ => .ok (#[], env)
```

- [ ] **Step 6: Add rejection to `nestedLocalArrayGetShapesStatement`**

Find `nestedLocalArrayGetShapesStatement` (around line 1908). Insert after `.boundedFor`:

```lean
| .whileLoop _ _ => .ok (#[], env)
```

- [ ] **Step 7: Verify**

Run:
```bash
lake build ProofForge.Backend.Evm.Lower
```

Expected: build succeeds with no errors.

- [ ] **Step 8: Commit**

```bash
git add ProofForge/Backend/Evm/Lower.lean
git commit -m "fix(evm): reject Statement.whileLoop in lower planning"
```

---

## Task 5: Fix `Statement.whileLoop` in `ProofForge.Compiler.TS.Printer`

**Files:**
- Modify: `ProofForge/Compiler/TS/Printer.lean`

**Interfaces:**
- Consumes: `TS.AST.Stmt.whileLoop`
- Produces: printed `while (cond) { body }` TypeScript source

- [ ] **Step 1: Add `whileLoop` emission to `printStmt`**

Find `printStmt` (around line 120). Insert a new case after `.forLoop` and before `.return`:

```lean
| .whileLoop cond body =>
    let head := indent depth ++ s!"while ({printExpr cond}) "
    head ++ printBlock depth body ++ "\n"
```

- [ ] **Step 2: Verify**

Run:
```bash
lake build ProofForge.Compiler.TS.Printer
```

Expected: build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Compiler/TS/Printer.lean
git commit -m "feat(ts-printer): emit whileLoop statements"
```

---

## Task 6: Full `lake build` verification

- [ ] **Step 1: Run full build**

```bash
lake build
```

Expected: all 318 targets build successfully. If any new `whileLoop` missing-case errors appear, add rejection branches to the reported file/function and repeat this step.

- [ ] **Step 2: Run baseline checks**

```bash
just psy-diagnostics
just psy-coverage
just psy-golden-sources
```

Expected: all pass.

- [ ] **Step 3: Commit any follow-up fixes**

Commit each additional `whileLoop` fix atomically with the same message pattern:
```bash
git commit -m "fix(<backend>): reject Statement.whileLoop in <function>"
```

---

## Task 7: Fix nested storage assignment targets in `ProofForge.Backend.Psy.IR`

**Files:**
- Modify: `ProofForge/Backend/Psy/IR.lean`

**Interfaces:**
- Consumes: `IR.Expr.field` / `IR.Expr.arrayGet` over storage struct/array targets
- Produces: extended `StorageTarget.path` for nested forms

- [ ] **Step 1: Extend `.field` branch in `resolveStorageTargetRoot`**

Find `resolveStorageTargetRoot` (around line 1354). Replace the `.structField`/`.arrayStructField` error branches with path extension:

```lean
| .field base fieldName => do
    match ← resolveStorageTargetRoot ctx base with
    | .scalar stateId => .ok <| .structField stateId fieldName
    | .arrayIndex stateId index feltBacked => .ok <| .arrayStructField stateId index fieldName
    | .path stateId segs feltBacked => .ok <| .path stateId (segs.push (.field fieldName)) feltBacked
    | .structField stateId baseField =>
        .ok <| .path stateId #[.field baseField, .field fieldName] false
    | .arrayStructField stateId index baseField =>
        .ok <| .path stateId #[.index index, .field baseField, .field fieldName] false
```

- [ ] **Step 2: Extend `.arrayGet` branch in `resolveStorageTargetRoot`**

The existing `.arrayGet` branch already handles `.scalar`, `.arrayIndex`, and `.path` correctly. Verify that `.structField` and `.arrayStructField` are still rejected, which is correct because a struct field is not an array target.

- [ ] **Step 3: Verify**

Run:
```bash
lake build ProofForge.Backend.Psy.IR
lake env lean --run Tests/PsyDiagnostics.lean
just psy-golden-sources
```

Expected: build succeeds, diagnostics pass, golden sources unchanged.

- [ ] **Step 4: Commit**

```bash
git add ProofForge/Backend/Psy/IR.lean
git commit -m "fix(psy): allow nested struct-field storage assignment targets"
```

---

## Task 8: Fix context-op and crosscall-target collection in `ProofForge.Backend.Psy.Plan`

**Files:**
- Modify: `ProofForge/Backend/Psy/Plan.lean`

**Interfaces:**
- Consumes: `IR.Statement`, `IR.Expr`, `IR.Effect`
- Produces: complete `stmtContextOps` and `stmtCrosscallTargets`

- [ ] **Step 1: Fix `stmtContextOps` for `.assertEq`**

Find `stmtContextOps` (around line 216). Change:

```lean
| .assert c _ _ | .assertEq _ c _ _ => exprContextOps c
```

to:

```lean
| .assert c _ _ => exprContextOps c
| .assertEq lhs rhs _ _ => exprContextOps lhs ++ exprContextOps rhs
```

- [ ] **Step 2: Add `effectCrosscallTargets`**

Find `exprCrosscallTargets` (around line 206). After the `exprContextOps`/`effectContextOps` mutual block, add a new mutual function `effectCrosscallTargets`:

```lean
partial def effectCrosscallTargets (eff : IR.Effect) : Array String :=
  match eff with
  | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v
  | .storageArrayWrite _ _ v | .storageStructFieldWrite _ _ v
  | .storageArrayStructFieldWrite _ _ _ v
  | .storagePathWrite _ _ v | .storagePathAssignOp _ _ _ v
  | .storageMapInsert _ _ v | .storageMapSet _ _ v =>
      exprCrosscallTargets v
  | .storageMapContains _ k | .storageMapGet _ k | .storageArrayRead _ k =>
      exprCrosscallTargets k
  | .storagePathRead _ path =>
      path.foldl (fun acc seg => match seg with | .index e => acc ++ exprCrosscallTargets e | _ => acc) #[]
  | .storageArrayStructFieldRead _ k _ => exprCrosscallTargets k
  | .storageStructFieldRead _ _ => #[]
  | .eventEmit _ fields | .eventEmitIndexed _ _ fields =>
      fields.foldl (fun acc (_, v) => acc ++ exprCrosscallTargets v) #[]
  | _ => #[]
```

Because `effectCrosscallTargets` and `exprCrosscallTargets` are mutually recursive, place this definition inside the same `mutual ... end` block as `exprContextOps`/`effectContextOps`, or create a new `mutual` block for `exprCrosscallTargets` + `effectCrosscallTargets`.

- [ ] **Step 3: Make `exprCrosscallTargets` recurse through all expressions**

Replace `exprCrosscallTargets` with a fully recursive definition:

```lean
partial def exprCrosscallTargets (e : IR.Expr) : Array String :=
  match e with
  | .crosscallInvoke target _ args =>
      let targetIds := match target with | .local n => #[n] | _ => #[]
      args.foldl (fun acc v => acc ++ exprCrosscallTargets v) targetIds
  | .effect eff => effectCrosscallTargets eff
  | .arrayLit _ values => values.foldl (fun acc v => acc ++ exprCrosscallTargets v) #[]
  | .arrayGet array index => exprCrosscallTargets array ++ exprCrosscallTargets index
  | .structLit _ fields => fields.foldl (fun acc (_, v) => acc ++ exprCrosscallTargets v) #[]
  | .field base _ => exprCrosscallTargets base
  | .add l r | .sub l r | .mul l r | .div l r | .mod l r | .pow l r
  | .bitAnd l r | .bitOr l r | .bitXor l r | .shiftLeft l r | .shiftRight l r
  | .eq l r | .ne l r | .lt l r | .le l r | .gt l r | .ge l r
  | .boolAnd l r | .boolOr l r => exprCrosscallTargets l ++ exprCrosscallTargets r
  | .boolNot v | .hash v => exprCrosscallTargets v
  | .hashTwoToOne l r => exprCrosscallTargets l ++ exprCrosscallTargets r
  | .cast v _ => exprCrosscallTargets v
  | .hashValue a b c d =>
      exprCrosscallTargets a ++ exprCrosscallTargets b ++ exprCrosscallTargets c ++ exprCrosscallTargets d
  | _ => #[]
```

- [ ] **Step 4: Fix `stmtCrosscallTargets` to use `effectCrosscallTargets` and collect both sides of `.assertEq`**

Replace `stmtCrosscallTargets` with:

```lean
partial def stmtCrosscallTargets (s : IR.Statement) : Array String :=
  match s with
  | .letBind _ _ v | .letMutBind _ _ v | .assign _ v | .assignOp _ _ v => exprCrosscallTargets v
  | .effect eff => effectCrosscallTargets eff
  | .assert c _ _ => exprCrosscallTargets c
  | .assertEq lhs rhs _ _ => exprCrosscallTargets lhs ++ exprCrosscallTargets rhs
  | .ifElse c thenBody elseBody =>
      exprCrosscallTargets c ++ thenBody.flatMap stmtCrosscallTargets ++ elseBody.flatMap stmtCrosscallTargets
  | .boundedFor _ _ _ body => body.flatMap stmtCrosscallTargets
  | .return v => exprCrosscallTargets v
  | _ => #[]
```

- [ ] **Step 5: Verify**

Run:
```bash
lake build ProofForge.Backend.Psy.Plan
lake env lean --run Tests/PsyDiagnostics.lean
just psy-golden-sources
```

Expected: build and tests pass; golden sources unchanged.

- [ ] **Step 6: Commit**

```bash
git add ProofForge/Backend/Psy/Plan.lean
git commit -m "fix(psy): complete context-op and crosscall-target collection"
```

---

## Task 9: Unify `feltBacked` computation for storage paths

**Files:**
- Modify: `ProofForge/Backend/Psy/IR.lean`

**Interfaces:**
- Consumes: `BuildContext`, state id, storage path
- Produces: consistent `feltBacked` Bool for reads and writes

- [ ] **Step 1: Add a single helper**

Near `isFeltBackedU32ArrayCtx` (around line 115), add:

```lean
/-- Decide whether a resolved storage path should use the Felt-backed U32 rewrite.
    True only when the root state is a felt-backed U32 array and the path is a
    valid index/field path into that array. -/
def storagePathFeltBacked (ctx : BuildContext) (stateId : String) (pathType : ValueType) (path : Array IR.StoragePathSegment) : Bool :=
  isFeltBackedU32ArrayCtx ctx stateId && pathType == .u32
```

- [ ] **Step 2: Use the helper in `buildEffectExpr` for `storagePathRead`**

Find the `storagePathRead` branch (around line 1315). Replace:

```lean
let feltBacked := pathType == .u32
```

with:

```lean
let feltBacked := storagePathFeltBacked ctx stateId pathType path
```

- [ ] **Step 3: Use the helper in `buildEffectStmt` for `storagePathWrite`**

Find the `storagePathWrite` branch (around line 1428). Replace:

```lean
let feltBacked := isFeltBackedU32ArrayCtx ctx stateId
```

with:

```lean
let feltBacked := storagePathFeltBacked ctx stateId pathType path
```

Also remove the now-unused `pathType` binding warning by using it only inside `storagePathFeltBacked` or by naming it `_pathType` if truly unused.

- [ ] **Step 4: Use the helper in `storagePathAssignOp`**

Find the `.storagePathAssignOp` branch (around line 1435). Replace the inline `pathType == .u32` check with:

```lean
if storagePathFeltBacked ctx stateId pathType path then
```

- [ ] **Step 5: Verify**

Run:
```bash
lake build ProofForge.Backend.Psy.IR
lake env lean --run Tests/PsyDiagnostics.lean
just psy-golden-sources
```

Expected: build and tests pass; golden sources unchanged.

- [ ] **Step 6: Commit**

```bash
git add ProofForge/Backend/Psy/IR.lean
git commit -m "fix(psy): use single helper for storage-path feltBacked flag"
```

---

## Task 10: Remove dead code from `ProofForge.Backend.Psy.IR`

**Files:**
- Modify: `ProofForge/Backend/Psy/IR.lean`

**Interfaces:**
- Removes unused direct-to-string rendering helpers and old path validators.

- [ ] **Step 1: Identify references**

Before deleting, search for each symbol across `Tests/`, `ProofForge/Backend/Psy/`, and `ProofForge/Compiler/Psy/`:

```bash
for name in indent lines literal stringLiteral structDecl stateDecl testBody storagePathStartType resolveStoragePathType isFeltBackedU32StorageArrayPath requireScalarState requireMapState requireArrayState requireStructScalarState requireStructArrayState; do
  echo "=== $name ==="
  rg -n "\\b$name\\b" Tests/ ProofForge/Backend/Psy/ ProofForge/Compiler/Psy/ 2>/dev/null || true
done
```

Only delete symbols whose only references are their own definitions.

- [ ] **Step 2: Delete old rendering helpers**

Delete from `indent` (around line 167) through `testBody` (around line 499), stopping before the validation functions that begin around line 501. Keep:
- `asciiLetters`, `isPsyIdentifierStart`, `isPsyIdentifierContinue`, `psyReservedIdentifiers` (still used for identifier validation).
- `capitalizedRefName` (still used by EVM? verify first).
- `testFunctionName` if it has any external caller.

If `capitalizedRefName` or `testFunctionName` are unused after the Plan refactor, delete them too.

- [ ] **Step 3: Delete old path/state validators**

Delete:
- `requireScalarState`
- `requireMapState`
- `requireArrayState`
- `requireStructScalarState`
- `requireStructArrayState`
- `storagePathStartType`
- `resolveStoragePathType`
- `isFeltBackedU32StorageArrayPath`

Keep the `Ctx`-suffixed equivalents (`requireScalarStateCtx`, etc.) that the new builder uses.

- [ ] **Step 4: Verify**

Run:
```bash
lake build ProofForge.Backend.Psy.IR
lake build
lake env lean --run Tests/PsyDiagnostics.lean
just psy-golden-sources
```

Expected: full build passes, diagnostics pass, golden sources unchanged.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Backend/Psy/IR.lean
git commit -m "refactor(psy): remove dead direct-to-string helpers and old validators"
```

---

## Task 11: Remove or use unused `ContextPlan` in `ProofForge.Backend.Psy.Plan`

**Files:**
- Modify: `ProofForge/Backend/Psy/Plan.lean`

**Interfaces:**
- Removes unused `ContextPlan` structure.

- [ ] **Step 1: Delete `ContextPlan`**

Find the `ContextPlan` structure (around line 113). Delete it. `PsyModulePlan.contextOps` remains `Array ContextOp`.

- [ ] **Step 2: Verify**

Run:
```bash
lake build ProofForge.Backend.Psy.Plan
lake build
```

Expected: build passes.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Backend/Psy/Plan.lean
git commit -m "refactor(psy): remove unused ContextPlan structure"
```

---

## Task 12: Create `Tests/PsyMetadata.lean` unit tests

**Files:**
- Create: `Tests/PsyMetadata.lean`

**Interfaces:**
- Consumes: `ProofForge.Backend.Psy.Metadata.buildPlanArtifactMetadata`
- Produces: passing assertions over `ArtifactMetadata` for selected fixtures

- [ ] **Step 1: Create the test file**

```lean
import ProofForge.Backend.Psy.Metadata
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.ContextProbe

namespace ProofForge.Tests.PsyMetadata

open ProofForge.Backend.Psy.Metadata
open ProofForge.IR

def requireOk (x : Except String α) (msg : String) : α :=
  match x with
  | .ok v => v
  | .error e => panic s!"{msg}: {e}"

def assertEq [Repr α] [BEq α] (name : String) (expected actual : α) : IO Unit :=
  if expected == actual then
    IO.println s!"ok: {name}"
  else
    throw <| IO.userError s!"fail: {name}\n  expected: {repr expected}\n  actual: {repr actual}"

def main : IO Unit := do
  let counterMeta := requireOk (buildPlanArtifactMetadata Counter.module) "counter metadata"
  assertEq "counter targetId" "psy-dpn" counterMeta.targetId
  assertEq "counter moduleName" "Counter" counterMeta.moduleName
  assertEq "counter entrypoint names" #["initialize", "increment", "get"] (counterMeta.entrypoints.map (·.name))
  assertEq "counter return types" #["()", "()", "Felt"] (counterMeta.entrypoints.map (·.returnType))

  let mapMeta := requireOk (buildPlanArtifactMetadata MapProbe.module) "map metadata"
  assertEq "map has events" false mapMeta.events.isEmpty
  assertEq "map has capabilities" false mapMeta.capabilities.isEmpty

  let eventMeta := requireOk (buildPlanArtifactMetadata EventProbe.module) "event metadata"
  assertEq "event has events" false eventMeta.events.isEmpty
  assertEq "event field type" "Felt" (eventMeta.events[0]!.fields[0]!.type)

  let ctxMeta := requireOk (buildPlanArtifactMetadata ContextProbe.module) "context metadata"
  assertEq "context has contextOps" false ctxMeta.contextOps.isEmpty

  IO.println "PsyMetadata: all assertions passed"

end ProofForge.Tests.PsyMetadata
```

- [ ] **Step 2: Verify the test file compiles and runs**

```bash
lake env lean --run Tests/PsyMetadata.lean
```

Expected: prints all `ok:` lines and "PsyMetadata: all assertions passed".

- [ ] **Step 3: Commit**

```bash
git add Tests/PsyMetadata.lean
git commit -m "test(psy): add unit tests for plan-driven artifact metadata"
```

---

## Task 13: Create `Tests/PsyMetadataExport.lean` JSON export runner

**Files:**
- Create: `Tests/PsyMetadataExport.lean`

**Interfaces:**
- Consumes: fixture name (from `argv`), `ProofForge.Backend.Psy.Metadata`
- Produces: JSON object on stdout matching `ArtifactMetadata`

- [ ] **Step 1: Create the export runner**

```lean
import ProofForge.Backend.Psy.Metadata
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.ContextProbe

namespace ProofForge.Tests.PsyMetadataExport

open ProofForge.Backend.Psy.Metadata
open ProofForge.IR

def moduleByName (name : String) : Option Module :=
  match name with
  | "Counter" => some Counter.module
  | "MapProbe" => some MapProbe.module
  | "EventProbe" => some EventProbe.module
  | "ContextProbe" => some ContextProbe.module
  | _ => none

def quoteString (s : String) : String :=
  "\"" ++ (s.toList.map (fun c => match c with
    | '\\' => "\\\\"
    | '"' => "\\\""
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | c => c.toString)).foldl (· ++ ·) "" ++ "\""

def jsonArray (items : List String) : String :=
  "[" ++ ", ".intercalate items ++ "]"

def jsonObject (fields : List (String × String)) : String :=
  "{" ++ ", ".intercalate (fields.map (fun (k, v) => quoteString k ++ ": " ++ v)) ++ "}"

def renderAbiParam (p : AbiParamDescriptor) : String :=
  jsonObject [("name", quoteString p.name), ("type", quoteString p.type)]

def renderAbiEntrypoint (e : AbiEntrypointDescriptor) : String :=
  jsonObject [
    ("name", quoteString e.name),
    ("params", jsonArray (e.params.toList.map renderAbiParam)),
    ("returnType", quoteString e.returnType)
  ]

def renderAbiEventField (f : AbiEventFieldDescriptor) : String :=
  jsonObject [("name", quoteString f.name), ("type", quoteString f.type)]

def renderAbiEvent (e : AbiEventDescriptor) : String :=
  jsonObject [
    ("name", quoteString e.name),
    ("fields", jsonArray (e.fields.toList.map renderAbiEventField))
  ]

def renderContextOp (o : ContextOpDescriptor) : String :=
  jsonObject [("name", quoteString o.name)]

def renderCrosscall (c : CrosscallDescriptor) : String :=
  jsonObject [("targetContractId", quoteString c.targetContractId)]

def renderArtifactMetadata (m : ArtifactMetadata) : String :=
  jsonObject [
    ("targetId", quoteString m.targetId),
    ("moduleName", quoteString m.moduleName),
    ("entrypoints", jsonArray (m.entrypoints.toList.map renderAbiEntrypoint)),
    ("events", jsonArray (m.events.toList.map renderAbiEvent)),
    ("contextOps", jsonArray (m.contextOps.toList.map renderContextOp)),
    ("crosscalls", jsonArray (m.crosscalls.toList.map renderCrosscall)),
    ("capabilities", jsonArray (m.capabilities.toList.map quoteString))
  ]

def main (args : List String) : IO Unit :=
  match args with
  | [name] =>
      match moduleByName name with
      | some module =>
          match buildPlanArtifactMetadata module with
          | .ok m => IO.println (renderArtifactMetadata m)
          | .error e => throw <| IO.userError s!"failed to build metadata for {name}: {e}"
      | none => throw <| IO.userError s!"unknown fixture: {name}"
  | _ => throw <| IO.userError "usage: PsyMetadataExport <fixture-name>"

end ProofForge.Tests.PsyMetadataExport
```

- [ ] **Step 2: Verify it runs for Counter**

```bash
lake env lean --run Tests/PsyMetadataExport.lean Counter
```

Expected: prints a JSON object with `targetId`, `moduleName`, `entrypoints`, etc.

- [ ] **Step 3: Commit**

```bash
git add Tests/PsyMetadataExport.lean
git commit -m "feat(psy): add JSON export runner for plan-driven metadata"
```

---

## Task 14: Wire Metadata export into `scripts/psy/write-artifact-metadata.py`

**Files:**
- Modify: `scripts/psy/write-artifact-metadata.py`
- Modify: `scripts/psy/counter-smoke.sh`

**Interfaces:**
- Consumes: `--plan-metadata` JSON file
- Produces: merged `proof-forge-artifact.json`

- [ ] **Step 1: Add `--plan-metadata` argument and merge logic**

In `scripts/psy/write-artifact-metadata.py`, add to the argument parser:

```python
parser.add_argument("--plan-metadata")
```

After the `metadata` dict is built (before writing), add:

```python
if args.plan_metadata:
    plan_meta_path = Path(args.plan_metadata)
    plan_meta = json.loads(plan_meta_path.read_text())
    metadata["target"] = plan_meta.get("targetId", metadata["target"])
    metadata["moduleName"] = plan_meta.get("moduleName")
    metadata["abi"] = {"entrypoints": plan_meta.get("entrypoints", [])}
    metadata["events"] = plan_meta.get("events", [])
    metadata["contextOps"] = plan_meta.get("contextOps", [])
    metadata["crosscalls"] = plan_meta.get("crosscalls", [])
    metadata["planCapabilities"] = plan_meta.get("capabilities", [])
```

- [ ] **Step 2: Update `scripts/psy/counter-smoke.sh` to call the export and pass the file**

After the `proof-forge emit` step and before `write-artifact-metadata.py`, add:

```bash
PLAN_METADATA_FILE="$PROJECT_DIR/target/plan-metadata.json"
lake env lean --run "$ROOT/Tests/PsyMetadataExport.lean" Counter > "$PLAN_METADATA_FILE"
```

Then append `--plan-metadata "$PLAN_METADATA_FILE"` to the `write-artifact-metadata.py` invocation.

- [ ] **Step 3: Verify**

Run:
```bash
just psy-smoke counter
```

If `dargo` is not installed, the script exits early with a helpful message. In that case, run only the Lean parts manually:

```bash
lake build proof-forge
.lake/build/bin/proof-forge emit --target psy-dpn --fixture counter -o build/psy/Counter.psy
lake env lean --run Tests/PsyMetadataExport.lean Counter > /tmp/plan-metadata.json
python3 scripts/psy/write-artifact-metadata.py --root . --fixture Counter --source build/psy/Counter.psy --package-source build/psy/dargo-counter/src/main.psy --circuit-json build/psy/dargo-counter/target/proof_forge_counter.json --abi-json build/psy/dargo-counter/target/Counter.json --execute-log build/psy/dargo-counter/target/counter-execute.log --dargo-manifest build/psy/dargo-counter/Dargo.toml --deploy-json build/psy/dargo-counter/target/proof-forge-deploy.json --out /tmp/proof-forge-artifact.json --dargo dargo --execute-result "result_vm: [2]" --capability storage.scalar --capability zk.circuit --plan-metadata /tmp/plan-metadata.json
python3 -m json.tool /tmp/proof-forge-artifact.json | head -60
```

Expected: the artifact JSON contains `moduleName`, `abi.entrypoints`, `events`, `contextOps`, `crosscalls`, and `planCapabilities`.

- [ ] **Step 4: Commit**

```bash
git add scripts/psy/write-artifact-metadata.py scripts/psy/counter-smoke.sh
git commit -m "feat(psy): merge plan-driven metadata into proof-forge-artifact.json"
```

---

## Task 15: Propagate Metadata integration to other Psy smoke scripts

**Files:**
- Modify: each `scripts/psy/*-smoke.sh` that calls `write-artifact-metadata.py`

**Interfaces:**
- Reuses `Tests/PsyMetadataExport.lean` and the updated Python writer.

- [ ] **Step 1: List affected smoke scripts**

```bash
ls scripts/psy/*-smoke.sh
```

Expected scripts include: `map-smoke.sh`, `event-smoke.sh`, `context-smoke.sh`, `assert-smoke.sh`, `hash-smoke.sh`, `array-smoke.sh`, `struct-smoke.sh`, etc.

- [ ] **Step 2: For each script, add the export call and `--plan-metadata` argument**

Pattern to insert after the `proof-forge emit` step:

```bash
PLAN_METADATA_FILE="$PROJECT_DIR/target/plan-metadata.json"
lake env lean --run "$ROOT/Tests/PsyMetadataExport.lean" <FixtureName> > "$PLAN_METADATA_FILE"
```

Pattern to append to `write-artifact-metadata.py`:

```bash
  --plan-metadata "$PLAN_METADATA_FILE" \
```

Replace `<FixtureName>` with the actual fixture name used in the script (e.g., `MapProbe`, `EventProbe`, `ContextProbe`).

- [ ] **Step 3: Extend `Tests/PsyMetadataExport.lean` fixture mapping**

Add entries to `moduleByName` for every fixture used by a smoke script:

```lean
| "MapProbe" => some MapProbe.module
| "EventProbe" => some EventProbe.module
| "ContextProbe" => some ContextProbe.module
| "AssertProbe" => some AssertProbe.module
| "HashProbe" => some HashProbe.module
| "ArrayProbe" => some ArrayProbe.module
| "StructProbe" => some StructProbe.module
| ...
```

Import the corresponding `ProofForge.IR.Examples.*` modules at the top.

- [ ] **Step 4: Verify at least one additional script**

Run:
```bash
just psy-smoke map
```

Or, if `dargo` is unavailable, manually verify the export runner:

```bash
lake env lean --run Tests/PsyMetadataExport.lean MapProbe | python3 -m json.tool | head -40
```

Expected: valid JSON with MapProbe metadata.

- [ ] **Step 5: Commit**

```bash
git add Tests/PsyMetadataExport.lean scripts/psy/*-smoke.sh
git commit -m "feat(psy): wire plan-driven metadata into all psy smoke scripts"
```

---

## Task 16: Final verification and CI alignment

- [ ] **Step 1: Full build and check**

```bash
lake build
just check
```

Expected: both pass.

- [ ] **Step 2: Psy-specific gates**

```bash
just psy-diagnostics
just psy-coverage
just psy-golden-sources
```

Expected: all pass.

- [ ] **Step 3: Run new tests**

```bash
lake env lean --run Tests/PsyMetadata.lean
```

Expected: "PsyMetadata: all assertions passed".

- [ ] **Step 4: Update `docs/targets/psy-dpn.md` Phase B3 remaining item**

Find the Phase B3 "Remaining" bullet:

```markdown
- Remaining: integrate `Metadata.buildPlanArtifactMetadata` into Psy smoke
  scripts so `proof-forge-artifact.json` records the plan-driven metadata, and
  consider upstream `psy-ast` emission if the compiler internals stabilize.
```

Change it to:

```markdown
- Done: integrate `Metadata.buildPlanArtifactMetadata` into Psy smoke
  scripts so `proof-forge-artifact.json` records the plan-driven metadata.
- Remaining: consider upstream `psy-ast` emission if the compiler internals stabilize.
```

- [ ] **Step 5: Commit**

```bash
git add docs/targets/psy-dpn.md
git commit -m "docs(psy): mark Metadata integration complete in Phase B3"
```

---

## Task 17: Update validation gates if needed

- [ ] **Step 1: Check `docs/validation-gates.md` for Psy gates**

Search for `psy` in `docs/validation-gates.md`. If the new `Tests/PsyMetadata.lean` test should be listed as a gate, add an entry.

- [ ] **Step 2: Check CI workflow**

Open `.github/workflows/ci.yml` and verify that the Psy gate already runs `scripts/psy/diagnostic-smoke.sh` and `scripts/psy/check-ir-coverage-manifest.py`. The new Metadata test does not need a separate CI step if `just check` covers it, but add it to `just check` if it is not already invoked there.

To add to `just check`, find the `check:` recipe and add `psy-metadata` to its dependency list, then define:

```makefile
psy-metadata:
    lake env lean --run Tests/PsyMetadata.lean
```

- [ ] **Step 3: Verify**

```bash
just psy-metadata
```

Expected: test passes.

- [ ] **Step 4: Commit**

```bash
git add justfile docs/validation-gates.md
git commit -m "chore(psy): add psy-metadata gate to just check"
```

---

## Self-review checklist

- [ ] **Spec coverage:** Every requirement from `docs/superpowers/specs/2026-07-05-psy-build-fix-and-metadata-design.md` maps to a task above.
- [ ] **Placeholder scan:** No `TBD`, `TODO`, or vague steps remain.
- [ ] **Type consistency:** `ArtifactMetadata` field names in `Tests/PsyMetadataExport.lean` match `ProofForge.Backend.Psy.Metadata.ArtifactMetadata`.
- [ ] **Command correctness:** All `lake build`, `lake env lean --run`, and `just` commands use the current project's paths and conventions.
- [ ] **Additive changes:** `write-artifact-metadata.py` only adds fields; existing fields are untouched.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-05-psy-build-fix-and-metadata.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
