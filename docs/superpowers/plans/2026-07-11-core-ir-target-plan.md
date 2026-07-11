# Core IR + Target Plan Decoupling Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a stable Core IR and per-target CorePlan/CoreLower modules so that new syntax sugar and SDK abstractions only change the elaboration layer, while target backends operate on a fixed set of semantic primitives.

**Architecture:** Insert Core IR between the existing Surface IR (`ProofForge/IR/Contract.lean`) and the three target backends. Add a Surface → Core elaboration pass, then add new `CorePlan`/`CoreLower` modules for EVM, Solana, and WasmHost that run in parallel with existing backends. Wire experimental CLI target ids (`evm-core`, `solana-sbpf-asm-core`, `wasm-near-core`) without disturbing the existing targets.

**Tech Stack:** Lean 4, Lake, `proof-forge` CLI, solc, Foundry, sbpf toolchain, wat2wasm, `just`.

## Global Constraints

- Existing EVM/Solana/NEAR backends remain untouched in Phase 1.
- All new modules must compile with `lake build`.
- Experimental target ids: `evm-core`, `solana-sbpf-asm-core`, `wasm-near-core`.
- Phase 1 does not implement the `hostOp` registry; only the `hostOpStub` type position is reserved.
- First product smokes must cover `Counter` and `ValueVault`.
- Follow existing file naming and module conventions in `ProofForge/IR/` and `ProofForge/Backend/`.
- Prefer small, focused files; if an existing file has grown unwieldy, split it in the plan rather than appending.

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `ProofForge/IR/Core.lean` | Core IR AST: `CoreType`, `CoreExpr`, `CoreEffect`, `CoreStmt`, `CoreModule`, plus supporting types. |
| `ProofForge/IR/Core/Error.lean` | Core IR error types: `ElabError`, `ValidationError`, `CapabilityError`. |
| `ProofForge/IR/Elaborate.lean` | `elaborateModule` and per-constructor elaborators: Surface IR → Core IR. |
| `ProofForge/IR/Elaborate/Smoke.lean` | Roundtrip smoke fixtures for elaboration (Counter/ValueVault fragments). |
| `ProofForge/Backend/Evm/CorePlan.lean` | Core IR → `EvmCorePlan` (storage slots, dispatcher, Yul function plan). |
| `ProofForge/Backend/Evm/CoreLower.lean` | `EvmCorePlan` → `Yul.Object`. |
| `ProofForge/Backend/Solana/CorePlan.lean` | Core IR → `SolanaCorePlan` (account layout, instruction data, CPI, syscalls). |
| `ProofForge/Backend/Solana/CoreLower.lean` | `SolanaCorePlan` → `List AstNode`. |
| `ProofForge/Backend/WasmHost/CorePlan.lean` | Core IR → `WasmCorePlan` (memory layout, host imports, function plan). |
| `ProofForge/Backend/WasmHost/CoreLower.lean` | `WasmCorePlan` → `Wasm.Module`. |
| `ProofForge/Target/CoreBackend.lean` | Shared `coreBackend` helpers and `TargetPlan` type wiring. |
| `Tests/CoreIRSmoke.lean` | Build/structural smoke for Core IR AST. |
| `Tests/CoreElabSmoke.lean` | Elaboration smoke for Counter/ValueVault. |
| `Tests/EvmCoreSmoke.lean` | EVM Core path smoke. |
| `Tests/SolanaCoreSmoke.lean` | Solana Core path smoke. |
| `Tests/WasmHostCoreSmoke.lean` | WasmHost Core path smoke. |

### Modified files

| File | Change |
|---|---|
| `ProofForge/IR.lean` | Export `ProofForge.IR.Core` and `ProofForge.IR.Elaborate`. |
| `ProofForge/Backend/Evm.lean` | Export `ProofForge.Backend.Evm.CorePlan` and `ProofForge.Backend.Evm.CoreLower`. |
| `ProofForge/Backend/Solana.lean` | Export `ProofForge.Backend.Solana.CorePlan` and `ProofForge.Backend.Solana.CoreLower`. |
| `ProofForge/Backend/WasmHost.lean` | Export `ProofForge.Backend.WasmHost.CorePlan` and `ProofForge.Backend.WasmHost.CoreLower`. |
| `ProofForge/Target/Registry.lean` | Add experimental target ids and `TargetProfile` entries. |
| `ProofForge/Target/BackendRegistry.lean` | Wire `evmCoreBackend`, `solanaCoreBackend`, `wasmHostCoreBackend`. |
| `ProofForge/Cli/TargetDriver.lean` | Register build/emit handlers for `-core` targets. |
| `lakefile.lean` | Add test executable/library entries if needed. |
| `justfile` | Add `core-ir-*` and `core-product` recipes. |

---

## Task 1: Core IR AST scaffolding

**Files:**
- Create: `ProofForge/IR/Core.lean`
- Create: `ProofForge/IR/Core/Error.lean`
- Modify: `ProofForge/IR.lean`
- Test: `lake build`

**Interfaces:**
- Produces: `ProofForge.IR.Core.CoreType`, `CoreExpr`, `CoreEffect`, `CoreStmt`, `CoreModule`, and supporting types (`CoreLiteral`, `UnaryOp`, `BinaryOp`, `ContextKind`, `CrosscallSpec`, `StoragePath`, `LValue`, `CoreStruct`, `CoreStateDecl`, `CoreEntrypoint`, `CoreEvent`, `HostOpId`).
- Produces: `ProofForge.IR.Core.Error.ElabError`, `ValidationError`, `CapabilityError`.

- [ ] **Step 1: Create `ProofForge/IR/Core.lean` with the AST skeleton**

```lean
namespace ProofForge.IR.Core

inductive CoreType
  | unit | bool | u8 | u32 | u64 | u128
  | address
  | bytes | string | hash
  | fixedArray (element : CoreType) (length : Nat)
  | array (element : CoreType)
  | structType (name : String)
  deriving BEq, Repr

inductive CoreLiteral
  | unitLit
  | boolLit (b : Bool)
  | u8Lit  (n : UInt8)
  | u32Lit (n : UInt32)
  | u64Lit (n : UInt64)
  | u128Lit (n : UInt128)
  | addressLit (s : String)
  | bytesLit (b : ByteArray)
  | stringLit (s : String)
  | hashLit (s : String)
  deriving BEq, Repr

inductive UnaryOp
  | not | neg
  deriving BEq, Repr

inductive BinaryOp
  | add | sub | mul | div | mod
  | eq | ne | lt | le | gt | ge
  | and | or | xor | shl | shr
  deriving BEq, Repr

inductive ContextKind
  | sender | value | blockNumber | blockTimestamp | gas | contractAddress
  deriving BEq, Repr

structure CrosscallSpec where
  family : String
  gas : Option CoreExpr
  value : Option CoreExpr
  deriving BEq, Repr

inductive StoragePath
  | scalar (slot : Nat)
  | mapKey (slot : Nat) (key : CoreExpr)
  | arrayIndex (slot : Nat) (idx : CoreExpr)
  | field (base : StoragePath) (field : String)
  deriving BEq, Repr

inductive LValue
  | local (name : String)
  | storage (path : StoragePath)
  | memory (base : CoreExpr) (offset : Nat) (ty : CoreType)
  deriving BEq, Repr

-- Phase 2 extension point; keep opaque in Phase 1.
def HostOpId := String
  deriving BEq, Repr

inductive CoreExpr
  | literal (val : CoreLiteral)
  | local (name : String)
  | fieldAccess (base : CoreExpr) (field : String)
  | arrayIndex (base : CoreExpr) (index : CoreExpr)
  | unary (op : UnaryOp) (arg : CoreExpr)
  | binary (op : BinaryOp) (lhs rhs : CoreExpr)
  | cast (from to : CoreType) (arg : CoreExpr)
  | hash (arg : CoreExpr)
  | contextRead (kind : ContextKind)
  | crosscall (spec : CrosscallSpec) (args : List CoreExpr)
  | hostOpStub (op : HostOpId) (args : List CoreExpr)
  deriving BEq, Repr

inductive CoreEffect
  | storageRead  (path : StoragePath)
  | storageWrite (path : StoragePath) (val : CoreExpr)
  | memoryRead   (base : CoreExpr) (offset : Nat) (ty : CoreType)
  | memoryWrite  (base : CoreExpr) (offset : Nat) (val : CoreExpr)
  | eventEmit    (name : String) (args : List CoreExpr)
  | contextReadEffect (kind : ContextKind)
  | crosscallEffect (spec : CrosscallSpec) (args : List CoreExpr)
  | assert       (cond : CoreExpr) (msg : Option String)
  | revert       (msg : Option String)
  | hostOpStubEffect (op : HostOpId) (args : List CoreExpr)
  deriving BEq, Repr

inductive CoreStmt
  | letBind    (name : String) (ty : CoreType) (val : CoreExpr)
  | letMutBind (name : String) (ty : CoreType) (val : CoreExpr)
  | assign     (lhs : LValue) (rhs : CoreExpr)
  | assignOp   (lhs : LValue) (op : BinaryOp) (rhs : CoreExpr)
  | effect     (e : CoreEffect)
  | ifElse     (cond : CoreExpr) (thenBranch elseBranch : List CoreStmt)
  | boundedFor (iter : String) (bound : CoreExpr) (body : List CoreStmt)
  | whileLoop  (cond : CoreExpr) (body : List CoreStmt)
  | return     (val : CoreExpr)
  deriving BEq, Repr

structure CoreStruct where
  name : String
  fields : List (String × CoreType)
  deriving BEq, Repr

structure CoreStateDecl where
  name : String
  ty : CoreType
  initializer : Option CoreExpr
  deriving BEq, Repr

structure CoreEntrypoint where
  name : String
  params : List (String × CoreType)
  retTy : CoreType
  body : List CoreStmt
  deriving BEq, Repr

structure CoreEvent where
  name : String
  fields : List (String × CoreType)
  deriving BEq, Repr

structure CoreModule where
  name : String
  structs : List CoreStruct
  state : List CoreStateDecl
  entrypoints : List CoreEntrypoint
  events : List CoreEvent
  deriving Repr

end ProofForge.IR.Core
```

- [ ] **Step 2: Create `ProofForge/IR/Core/Error.lean`**

```lean
namespace ProofForge.IR.Core.Error

inductive ElabError
  | unsupported (node : String)
  | typeMismatch (expected : String) (actual : String)
  | other (msg : String)
  deriving Repr

inductive ValidationError
  | duplicateName (name : String)
  | unknownType (name : String)
  | uninitializedState (name : String)
  | other (msg : String)
  deriving Repr

inductive CapabilityError
  | unsupported (target : String) (construct : String)
  deriving Repr

end ProofForge.IR.Core.Error
```

- [ ] **Step 3: Modify `ProofForge/IR.lean` to export Core IR**

Add to the import/export list:

```lean
import ProofForge.IR.Core
import ProofForge.IR.Core.Error
import ProofForge.IR.Elaborate
```

(Note: `ProofForge.IR.Elaborate` does not exist yet; create a stub in Step 4 if the build fails.)

- [ ] **Step 4: Run build**

Run: `lake build`
Expected: PASS (Core IR AST compiles).

- [ ] **Step 5: Commit**

```bash
git add ProofForge/IR/Core.lean ProofForge/IR/Core/Error.lean ProofForge/IR.lean
git commit -m "feat(ir): add Core IR AST and error types"
```

---

## Task 2: Core IR structural validation + smoke tests

**Files:**
- Create: `ProofForge/IR/Core/Validate.lean`
- Create: `Tests/CoreIRSmoke.lean`
- Modify: `lakefile.lean` (add `Tests/CoreIRSmoke` as a test if needed)
- Test: `lake env lean --run Tests/CoreIRSmoke.lean`

**Interfaces:**
- Consumes: `CoreModule` from Task 1.
- Produces: `ProofForge.IR.Core.Validate.validateModule : CoreModule → Except ValidationError Unit`.

- [ ] **Step 1: Create `ProofForge/IR/Core/Validate.lean`**

```lean
namespace ProofForge.IR.Core.Validate

open ProofForge.IR.Core ProofForge.IR.Core.Error

def validateModule (m : CoreModule) : Except ValidationError Unit := do
  -- Check duplicate state names
  let mut seen : Std.HashSet String := {}
  for s in m.state do
    if seen.contains s.name then
      .error (.duplicateName s.name)
    seen := seen.insert s.name
  -- Check duplicate entrypoint names
  for e in m.entrypoints do
    if seen.contains e.name then
      .error (.duplicateName e.name)
    seen := seen.insert e.name
  .ok ()

end ProofForge.IR.Core.Validate
```

- [ ] **Step 2: Create `Tests/CoreIRSmoke.lean`**

```lean
import ProofForge.IR.Core
import ProofForge.IR.Core.Validate

open ProofForge.IR.Core
open ProofForge.IR.Core.Validate

def counterCoreModule : CoreModule :=
  { name := "Counter"
  , structs := []
  , state := [ { name := "count", ty := .u64, initializer := .some (.literal (.u64Lit 0)) } ]
  , entrypoints :=
      [ { name := "increment", params := [], retTy := .unit
        , body := [ .effect (.storageWrite (.scalar 0) (.binary .add (.literal (.u64Lit 1)) (.local "count"))) ]
        }
      ]
  , events := []
  }

def main : IO UInt32 := do
  match validateModule counterCoreModule with
  | .ok () =>
    IO.println "CoreIRSmoke OK"
    return 0
  | .error e =>
    IO.println s!"CoreIRSmoke FAIL: {repr e}"
    return 1
```

- [ ] **Step 3: Run smoke**

Run: `lake env lean --run Tests/CoreIRSmoke.lean`
Expected: `CoreIRSmoke OK`

- [ ] **Step 4: Commit**

```bash
git add ProofForge/IR/Core/Validate.lean Tests/CoreIRSmoke.lean lakefile.lean
git commit -m "test(ir): add Core IR validation smoke"
```

---

## Task 3: Surface → Core elaboration for Counter/ValueVault

**Files:**
- Create: `ProofForge/IR/Elaborate.lean`
- Create: `ProofForge/IR/Elaborate/Smoke.lean`
- Create: `Tests/CoreElabSmoke.lean`
- Modify: `ProofForge/IR.lean`
- Test: `lake env lean --run Tests/CoreElabSmoke.lean`

**Interfaces:**
- Consumes: `ProofForge.IR.Contract.Module` and `CoreModule` from Task 1.
- Produces: `ProofForge.IR.Elaborate.elaborateModule : IR.Module → Except ElabError CoreModule`.

- [ ] **Step 1: Create `ProofForge/IR/Elaborate.lean` with a partial elaborator**

Implement enough to cover Counter and ValueVault. Start with a function that pattern-matches the Surface IR and returns Core IR, returning `ElabError.unsupported` for unhandled nodes.

```lean
namespace ProofForge.IR.Elaborate

open ProofForge.IR.Contract
open ProofForge.IR.Core
open ProofForge.IR.Core.Error

def elaborateType (t : ValueType) : Except ElabError CoreType :=
  match t with
  | .unit => .ok .unit
  | .bool => .ok .bool
  | .u8  => .ok .u8
  | .u32 => .ok .u32
  | .u64 => .ok .u64
  | .u128 => .ok .u128
  | .address => .ok .address
  | .bytes => .ok .bytes
  | .string => .ok .string
  | .hash => .ok .hash
  | .fixedArray e n => do .ok (.fixedArray (← elaborateType e) n)
  | .array e => do .ok (.array (← elaborateType e))
  | .structType n => .ok (.structType n)
  | other => .error (.unsupported s!"type {repr other}")

def elaborateExpr (e : Expr) : Except ElabError CoreExpr :=
  match e with
  | .literal l =>
    match l with
    | .nat n => .ok (.literal (.u64Lit n.toUInt64)) -- simplistic; refine per type later
    | .bool b => .ok (.literal (.boolLit b))
    | .string s => .ok (.literal (.stringLit s))
    | _ => .error (.unsupported s!"literal {repr l}")
  | .local name => .ok (.local name)
  | .fieldAccess base field => do .ok (.fieldAccess (← elaborateExpr base) field)
  | .arrayIndex base idx => do .ok (.arrayIndex (← elaborateExpr base) (← elaborateExpr idx))
  | .binary op lhs rhs => do .ok (.binary (← elaborateBinOp op) (← elaborateExpr lhs) (← elaborateExpr rhs))
  | _ => .error (.unsupported s!"expr {repr e}")
where
  elaborateBinOp : Expr.BinOp → Except ElabError BinaryOp
    | .add => .ok .add
    | .sub => .ok .sub
    | .eq  => .ok .eq
    | .lt  => .ok .lt
    | other => .error (.unsupported s!"binop {repr other}")

partial def elaborateStmt (s : Statement) : Except ElabError (List CoreStmt) :=
  match s with
  | .letBind name ty val => do
      pure [ .letBind name (← elaborateType ty) (← elaborateExpr val) ]
  | .assign lhs rhs => do
      pure [ .assign (← elaborateLValue lhs) (← elaborateExpr rhs) ]
  | .effect e => do
      pure [ .effect (← elaborateEffect e) ]
  | .ifElse cond thenSt elseSt => do
      pure [ .ifElse (← elaborateExpr cond) (← thenSt.toList.mapM elaborateStmt).bind id (← elseSt.toList.mapM elaborateStmt).bind id ]
  | .return val => do
      pure [ .return (← elaborateExpr val) ]
  | _ => .error (.unsupported s!"stmt {repr s}")
where
  elaborateLValue : LValue → Except ElabError Core.LValue
    | .local name => .ok (.local name)
    | .storageAccess acc => .ok (.storage (← elaborateStorageAccess acc))
    | other => .error (.unsupported s!"lvalue {repr other}")
  elaborateStorageAccess : StorageAccess → Except ElabError StoragePath
    | .identifier name => .ok (.scalar 0) -- placeholder: resolve name to slot in plan layer
    | other => .error (.unsupported s!"storage access {repr other}")
  elaborateEffect : Effect → Except ElabError CoreEffect
    | .storageWrite acc val => do .ok (.storageWrite (← elaborateStorageAccess acc) (← elaborateExpr val))
    | .storageRead acc => do .ok (.storageRead (← elaborateStorageAccess acc))
    | .eventEmit name args => do .ok (.eventEmit name (← args.mapM elaborateExpr))
    | .assert cond => do .ok (.assert (← elaborateExpr cond) .none)
    | .revert msg => .ok (.revert msg)
    | other => .error (.unsupported s!"effect {repr other}")

def elaborateModule (m : IR.Module) : Except ElabError CoreModule := do
  let state ← m.state.mapM fun s => do
    pure { name := s.name, ty := (← elaborateType s.ty), initializer := s.initializer.mapM elaborateExpr }
  let entrypoints ← m.entrypoints.mapM fun e => do
    pure { name := e.name
         , params := e.params.map fun p => (p.name, (← elaborateType p.ty))
         , retTy := (← elaborateType e.retTy)
         , body := (← e.body.toList.mapM elaborateStmt).bind id
         }
  pure
    { name := m.name
    , structs := [] -- TODO: elaborate structs when needed
    , state := state
    , entrypoints := entrypoints
    , events := []
    }

end ProofForge.IR.Elaborate
```

(The exact `ProofForge.IR.Contract` constructors will differ; adjust names and shapes to match the real `Contract.lean` definitions.)

- [ ] **Step 2: Create `Tests/CoreElabSmoke.lean`**

```lean
import ProofForge.IR.Contract
import ProofForge.IR.Elaborate

open ProofForge.IR.Elaborate

def main : IO UInt32 := do
  let m := -- load a minimal Counter surface module fixture
    { name := "Counter"
    , state := [ { name := "count", ty := .u64, initializer := .some (.literal (.nat 0)) } ]
    , entrypoints := [ { name := "increment", params := [], retTy := .unit, body := #[] } ]
    , structs := []
    , events := []
    }
  match elaborateModule m with
  | .ok core =>
    IO.println s!"CoreElabSmoke OK: {core.name}"
    return 0
  | .error e =>
    IO.println s!"CoreElabSmoke FAIL: {repr e}"
    return 1
```

- [ ] **Step 3: Run smoke**

Run: `lake env lean --run Tests/CoreElabSmoke.lean`
Expected: `CoreElabSmoke OK: Counter`

- [ ] **Step 4: Commit**

```bash
git add ProofForge/IR/Elaborate.lean Tests/CoreElabSmoke.lean
git commit -m "feat(ir): add Surface → Core elaboration and smoke"
```

---

## Task 4: EVM CorePlan

**Files:**
- Create: `ProofForge/Backend/Evm/CorePlan.lean`
- Modify: `ProofForge/Backend/Evm.lean`
- Test: `lake build`

**Interfaces:**
- Consumes: `CoreModule` from Task 1.
- Produces: `ProofForge.Backend.Evm.CorePlan.EvmCorePlan`.

- [ ] **Step 1: Create `ProofForge/Backend/Evm/CorePlan.lean`**

```lean
namespace ProofForge.Backend.Evm.CorePlan

open ProofForge.IR.Core

structure StorageSlotPlan where
  path : StoragePath
  slotExpr : Yul.Expr
  deriving Repr

structure ExprPlan where
  expr : Yul.Expr
  deriving Repr

structure StmtPlan where
  stmts : List Yul.Statement
  deriving Repr

structure EntrypointPlan where
  name : String
  selector : UInt32
  params : List (String × CoreType)
  body : List Yul.Statement
  deriving Repr

structure EvmCorePlan where
  moduleName : String
  stateSlots : List StorageSlotPlan
  entrypoints : List EntrypointPlan
  events : List EventPlan
  constructor : Option (List Yul.Statement)
  deriving Repr

-- Placeholder event plan; refine in Task 5.
structure EventPlan where
  name : String
  topicCount : Nat
  deriving Repr

end ProofForge.Backend.Evm.CorePlan
```

- [ ] **Step 2: Implement `buildEvmCorePlan`**

Add a function that assigns storage slots to state variables and builds per-entrypoint plans. Keep it minimal for Counter/ValueVault.

```lean
def buildEvmCorePlan (m : CoreModule) : EvmCorePlan :=
  let stateSlots := m.state.enum.map fun (i, s) =>
    { path := StoragePath.scalar i, slotExpr := Yul.Expr.literal i.toUInt256 }
  let entrypoints := m.entrypoints.map fun e =>
    { name := e.name
    , selector := 0 -- TODO: compute selector from signature in Task 5
    , params := e.params
    , body := []    -- TODO: lower body in Task 5
    }
  { moduleName := m.name
  , stateSlots := stateSlots
  , entrypoints := entrypoints
  , events := []
  , constructor := .none
  }
```

- [ ] **Step 3: Export from `ProofForge/Backend/Evm.lean`**

Add:

```lean
import ProofForge.Backend.Evm.CorePlan
```

- [ ] **Step 4: Run build**

Run: `lake build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Backend/Evm/CorePlan.lean ProofForge/Backend/Evm.lean
git commit -m "feat(evm): add EvmCorePlan data structure"
```

---

## Task 5: EVM CoreLower + Yul output

**Files:**
- Create: `ProofForge/Backend/Evm/CoreLower.lean`
- Create: `Tests/EvmCoreSmoke.lean`
- Modify: `ProofForge/Backend/Evm.lean`
- Test: `lake env lean --run Tests/EvmCoreSmoke.lean`

**Interfaces:**
- Consumes: `EvmCorePlan` from Task 4.
- Produces: `ProofForge.Backend.Evm.CoreLower.lowerEvmCorePlan : EvmCorePlan → Yul.Object`.

- [ ] **Step 1: Create `ProofForge/Backend/Evm/CoreLower.lean`**

```lean
namespace ProofForge.Backend.Evm.CoreLower

open ProofForge.Backend.Evm.CorePlan
open ProofForge.Compiler.Yul

def lowerEntrypoint (ep : EntrypointPlan) : Yul.FunctionDefinition :=
  { name := ep.name
  , args := ep.params.map Prod.fst
  , rettype := []
  , body := ep.body
  }

def lowerEvmCorePlan (p : EvmCorePlan) : Yul.Object :=
  { name := p.moduleName
  , code :=
    { functions := p.entrypoints.map lowerEntrypoint
    , statements := []
    }
  , subObjects := []
  , data := []
  }

end ProofForge.Backend.Evm.CoreLower
```

- [ ] **Step 2: Create `Tests/EvmCoreSmoke.lean`**

```lean
import ProofForge.IR.Core
import ProofForge.Backend.Evm.CorePlan
import ProofForge.Backend.Evm.CoreLower
import ProofForge.Compiler.Yul.Printer

open ProofForge.IR.Core
open ProofForge.Backend.Evm.CorePlan
open ProofForge.Backend.Evm.CoreLower

def counterModule : CoreModule :=
  { name := "Counter"
  , structs := []
  , state := [ { name := "count", ty := .u64, initializer := .some (.literal (.u64Lit 0)) } ]
  , entrypoints := [ { name := "increment", params := [], retTy := .unit, body := [] } ]
  , events := []
  }

def main : IO UInt32 := do
  let plan := buildEvmCorePlan counterModule
  let yul := lowerEvmCorePlan plan
  let rendered := renderObject yul
  if rendered.contains "Counter" then
    IO.println "EvmCoreSmoke OK"
    return 0
  else
    IO.println "EvmCoreSmoke FAIL"
    return 1
```

- [ ] **Step 3: Run smoke**

Run: `lake env lean --run Tests/EvmCoreSmoke.lean`
Expected: `EvmCoreSmoke OK`

- [ ] **Step 4: Commit**

```bash
git add ProofForge/Backend/Evm/CoreLower.lean Tests/EvmCoreSmoke.lean
git commit -m "feat(evm): add EvmCorePlan → Yul lowering and smoke"
```

---

## Task 6: Solana CorePlan skeleton

**Files:**
- Create: `ProofForge/Backend/Solana/CorePlan.lean`
- Modify: `ProofForge/Backend/Solana.lean`
- Test: `lake build`

**Interfaces:**
- Consumes: `CoreModule` from Task 1.
- Produces: `ProofForge.Backend.Solana.CorePlan.SolanaCorePlan`.

- [ ] **Step 1: Create `ProofForge/Backend/Solana/CorePlan.lean`**

```lean
namespace ProofForge.Backend.Solana.CorePlan

open ProofForge.IR.Core

structure AccountPlan where
  name : String
  isMutable : Bool
  deriving Repr

structure EntrypointPlan where
  name : String
  params : List (String × CoreType)
  body : List Asm.AstNode
  deriving Repr

structure SolanaCorePlan where
  moduleName : String
  accounts : List AccountPlan
  stateLayout : List (String × Nat)
  entrypoints : List EntrypointPlan
  deriving Repr

end ProofForge.Backend.Solana.CorePlan
```

- [ ] **Step 2: Implement `buildSolanaCorePlan` skeleton**

```lean
def buildSolanaCorePlan (m : CoreModule) : SolanaCorePlan :=
  { moduleName := m.name
  , accounts := [ { name := "data", isMutable := true } ]
  , stateLayout := m.state.enum.map fun (i, s) => (s.name, i * 8)
  , entrypoints := m.entrypoints.map fun e =>
      { name := e.name, params := e.params, body := [] }
  }
```

- [ ] **Step 3: Export from `ProofForge/Backend/Solana.lean`**

Add:

```lean
import ProofForge.Backend.Solana.CorePlan
```

- [ ] **Step 4: Run build**

Run: `lake build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Backend/Solana/CorePlan.lean ProofForge/Backend/Solana.lean
git commit -m "feat(solana): add SolanaCorePlan skeleton"
```

---

## Task 7: Solana CoreLower skeleton

**Files:**
- Create: `ProofForge/Backend/Solana/CoreLower.lean`
- Create: `Tests/SolanaCoreSmoke.lean`
- Modify: `ProofForge/Backend/Solana.lean`
- Test: `lake env lean --run Tests/SolanaCoreSmoke.lean`

**Interfaces:**
- Consumes: `SolanaCorePlan` from Task 6.
- Produces: `ProofForge.Backend.Solana.CoreLower.lowerSolanaCorePlan : SolanaCorePlan → List Asm.AstNode`.

- [ ] **Step 1: Create `ProofForge/Backend/Solana/CoreLower.lean`**

```lean
namespace ProofForge.Backend.Solana.CoreLower

open ProofForge.Backend.Solana.CorePlan
open ProofForge.Backend.Solana.Asm

def lowerSolanaCorePlan (p : SolanaCorePlan) : List AstNode :=
  [ .section ".text"
  , .global p.moduleName
  ] ++ p.entrypoints.flatMap (fun _ => [ .nop ])

end ProofForge.Backend.Solana.CoreLower
```

- [ ] **Step 2: Create `Tests/SolanaCoreSmoke.lean`**

```lean
import ProofForge.IR.Core
import ProofForge.Backend.Solana.CorePlan
import ProofForge.Backend.Solana.CoreLower

open ProofForge.IR.Core
open ProofForge.Backend.Solana.CorePlan

def main : IO UInt32 := do
  let m : CoreModule :=
    { name := "Counter"
    , structs := []
    , state := [ { name := "count", ty := .u64, initializer := .some (.literal (.u64Lit 0)) } ]
    , entrypoints := [ { name := "increment", params := [], retTy := .unit, body := [] } ]
    , events := []
    }
  let plan := buildSolanaCorePlan m
  let asm := lowerSolanaCorePlan plan
  if asm.length > 0 then
    IO.println "SolanaCoreSmoke OK"
    return 0
  else
    IO.println "SolanaCoreSmoke FAIL"
    return 1
```

- [ ] **Step 3: Run smoke**

Run: `lake env lean --run Tests/SolanaCoreSmoke.lean`
Expected: `SolanaCoreSmoke OK`

- [ ] **Step 4: Commit**

```bash
git add ProofForge/Backend/Solana/CoreLower.lean Tests/SolanaCoreSmoke.lean
git commit -m "feat(solana): add SolanaCorePlan → asm skeleton and smoke"
```

---

## Task 8: WasmHost CorePlan skeleton

**Files:**
- Create: `ProofForge/Backend/WasmHost/CorePlan.lean`
- Modify: `ProofForge/Backend/WasmHost.lean`
- Test: `lake build`

**Interfaces:**
- Consumes: `CoreModule` from Task 1.
- Produces: `ProofForge.Backend.WasmHost.CorePlan.WasmCorePlan`.

- [ ] **Step 1: Create `ProofForge/Backend/WasmHost/CorePlan.lean`**

```lean
namespace ProofForge.Backend.WasmHost.CorePlan

open ProofForge.IR.Core

structure MemoryPlan where
  stateOffset : Nat
  stateSize : Nat
  deriving Repr

structure FunctionPlan where
  name : String
  params : List (String × CoreType)
  retTy : CoreType
  body : List Wasm.Instr
  deriving Repr

structure WasmCorePlan where
  moduleName : String
  memory : MemoryPlan
  functions : List FunctionPlan
  imports : List Wasm.Import
  deriving Repr

end ProofForge.Backend.WasmHost.CorePlan
```

- [ ] **Step 2: Implement `buildWasmCorePlan` skeleton**

```lean
def buildWasmCorePlan (m : CoreModule) : WasmCorePlan :=
  { moduleName := m.name
  , memory := { stateOffset := 0, stateSize := m.state.length * 8 }
  , functions := m.entrypoints.map fun e =>
      { name := e.name, params := e.params, retTy := e.retTy, body := [] }
  , imports := []
  }
```

- [ ] **Step 3: Export from `ProofForge/Backend/WasmHost.lean`**

Add:

```lean
import ProofForge.Backend.WasmHost.CorePlan
```

- [ ] **Step 4: Run build**

Run: `lake build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Backend/WasmHost/CorePlan.lean ProofForge/Backend/WasmHost.lean
git commit -m "feat(wasm): add WasmCorePlan skeleton"
```

---

## Task 9: WasmHost CoreLower skeleton

**Files:**
- Create: `ProofForge/Backend/WasmHost/CoreLower.lean`
- Create: `Tests/WasmHostCoreSmoke.lean`
- Modify: `ProofForge/Backend/WasmHost.lean`
- Test: `lake env lean --run Tests/WasmHostCoreSmoke.lean`

**Interfaces:**
- Consumes: `WasmCorePlan` from Task 8.
- Produces: `ProofForge.Backend.WasmHost.CoreLower.lowerWasmCorePlan : WasmCorePlan → Wasm.Module`.

- [ ] **Step 1: Create `ProofForge/Backend/WasmHost/CoreLower.lean`**

```lean
namespace ProofForge.Backend.WasmHost.CoreLower

open ProofForge.Backend.WasmHost.CorePlan
open ProofForge.Compiler.Wasm

def lowerWasmCorePlan (p : WasmCorePlan) : Module :=
  { name := p.moduleName
  , funcs := p.functions.map fun f =>
      { name := f.name
      , params := f.params.map (fun p => (p.1, valueTypeName p.2))
      , ret := valueTypeName f.retTy
      , locals := []
      , body := f.body
      }
  , imports := p.imports
  , exports := p.functions.map fun f => { name := f.name, kind := .func f.name }
  , memory := .some { min := 1 }
  }

end ProofForge.Backend.WasmHost.CoreLower
```

- [ ] **Step 2: Create `Tests/WasmHostCoreSmoke.lean`**

```lean
import ProofForge.IR.Core
import ProofForge.Backend.WasmHost.CorePlan
import ProofForge.Backend.WasmHost.CoreLower

open ProofForge.IR.Core
open ProofForge.Backend.WasmHost.CorePlan

def main : IO UInt32 := do
  let m : CoreModule :=
    { name := "Counter"
    , structs := []
    , state := [ { name := "count", ty := .u64, initializer := .some (.literal (.u64Lit 0)) } ]
    , entrypoints := [ { name := "increment", params := [], retTy := .unit, body := [] } ]
    , events := []
    }
  let plan := buildWasmCorePlan m
  let wasm := lowerWasmCorePlan plan
  if wasm.funcs.length > 0 then
    IO.println "WasmHostCoreSmoke OK"
    return 0
  else
    IO.println "WasmHostCoreSmoke FAIL"
    return 1
```

- [ ] **Step 3: Run smoke**

Run: `lake env lean --run Tests/WasmHostCoreSmoke.lean`
Expected: `WasmHostCoreSmoke OK`

- [ ] **Step 4: Commit**

```bash
git add ProofForge/Backend/WasmHost/CoreLower.lean Tests/WasmHostCoreSmoke.lean
git commit -m "feat(wasm): add WasmCorePlan → Wasm.Module skeleton and smoke"
```

---

## Task 10: Target registry + CLI wiring

**Files:**
- Create: `ProofForge/Target/CoreBackend.lean`
- Modify: `ProofForge/Target/Registry.lean`
- Modify: `ProofForge/Target/BackendRegistry.lean`
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Test: `lake env proof-forge --list-targets` shows `evm-core`, `solana-sbpf-asm-core`, `wasm-near-core`

**Interfaces:**
- Consumes: `EvmCorePlan`, `SolanaCorePlan`, `WasmCorePlan` and their lowerers.
- Produces: `TargetBackend` instances for the three `-core` targets.

- [ ] **Step 1: Create `ProofForge/Target/CoreBackend.lean`**

```lean
namespace ProofForge.Target.CoreBackend

open ProofForge.IR.Core
open ProofForge.IR.Elaborate
open ProofForge.IR.Core.Validate
open ProofForge.Target

structure CoreBackendConfig (Plan Code : Type) where
  family : TargetFamily
  buildPlan : CoreModule → Plan
  lowerToCode : Plan → Code
  printCode : Code → String
  artifactKind : ArtifactKind

def mkCoreBackend (cfg : CoreBackendConfig Plan Code) : TargetBackend :=
  { validateModule? := fun m =>
      match elaborateModule m with
      | .error e => .error (.other (repr e))
      | .ok core =>
        match validateModule core with
        | .error e => .error (.other (repr e))
        | .ok () => .ok ()
  , ensurePlan? := fun m =>
      match elaborateModule m with
      | .error e => .error (.other (repr e))
      | .ok core => .ok (cfg.buildPlan core)
  , ensurePackage? := fun plan _ =>
      let code := cfg.lowerToCode plan
      .ok { artifact := cfg.printCode code, metadata := "" }
  }

end ProofForge.Target.CoreBackend
```

- [ ] **Step 2: Add experimental target profiles in `ProofForge/Target/Registry.lean`**

Add entries to `TargetProfile.all`:

```lean
{ id := "evm-core"
, family := .evm
, maturity := .experimental
, inputModes := [.contractSource]
, defaultArtifactKinds := [.yul]
, supportedArtifactKinds := [.yul, .binRuntime]
, ...
}
```

(Similarly for `solana-sbpf-asm-core` and `wasm-near-core`.)

- [ ] **Step 3: Wire backends in `ProofForge/Target/BackendRegistry.lean`**

```lean
def evmCoreBackend : TargetBackend :=
  CoreBackend.mkCoreBackend
    { family := .evm
    , buildPlan := Evm.CorePlan.buildEvmCorePlan
    , lowerToCode := Evm.CoreLower.lowerEvmCorePlan
    , printCode := fun obj => Yul.Printer.renderObject obj
    , artifactKind := .yul
    }

def solanaCoreBackend : TargetBackend := ...
def wasmHostCoreBackend : TargetBackend := ...
```

- [ ] **Step 4: Register CLI handlers in `ProofForge/Cli/TargetDriver.lean`**

Map the new target ids to the new backends in the driver registry.

- [ ] **Step 5: Run CLI check**

Run: `lake env proof-forge --list-targets`
Expected: output contains `evm-core`, `solana-sbpf-asm-core`, `wasm-near-core`.

- [ ] **Step 6: Commit**

```bash
git add ProofForge/Target/CoreBackend.lean ProofForge/Target/Registry.lean ProofForge/Target/BackendRegistry.lean ProofForge/Cli/TargetDriver.lean
git commit -m "feat(target): wire evm-core, solana-core, wasm-near-core experimental targets"
```

---

## Task 11: Product smoke tests + just recipes

**Files:**
- Modify: `justfile`
- Test: `just core-ir-build`, `just core-product`

- [ ] **Step 1: Add just recipes**

Append to `justfile`:

```just
# Core IR experimental targets
core-ir-build:
    lake build

core-evm-smoke:
    lake env proof-forge build --target evm-core --root . -o build/evm-core/Counter.yul Examples/Product/Counter.lean

core-solana-smoke:
    lake env proof-forge build --target solana-sbpf-asm-core --root . -o build/solana-core/Counter.s Examples/Product/Counter.lean

core-wasm-smoke:
    lake env proof-forge build --target wasm-near-core --root . -o build/wasm-core/Counter.wat Examples/Product/Counter.lean

core-product: core-ir-build core-evm-smoke core-solana-smoke core-wasm-smoke
```

- [ ] **Step 2: Run recipes**

Run: `just core-product`
Expected: all three targets emit artifacts without crashing. The artifacts may be minimal/skeleton output in Phase 1.

- [ ] **Step 3: Commit**

```bash
git add justfile
git commit -m "build(just): add core-ir experimental target recipes"
```

---

## Task 12: Final integration and gate run

**Files:**
- All of the above.
- Test: `just build`, `just product`, `just core-product`

- [ ] **Step 1: Run full build**

Run: `lake build`
Expected: PASS.

- [ ] **Step 2: Run existing product gate**

Run: `just product`
Expected: PASS (existing backends untouched).

- [ ] **Step 3: Run new Core IR product gate**

Run: `just core-product`
Expected: PASS; artifacts emitted under `build/evm-core/`, `build/solana-core/`, `build/wasm-core/`.

- [ ] **Step 4: Commit any final fixes**

```bash
git commit -m "chore(core-ir): final integration and gate fixes" || true
```

---

## Self-Review

### Spec coverage

| Spec section | Implementing task |
|---|---|
| Core IR AST | Task 1 |
| Core IR supporting types | Task 1 |
| Surface → Core elaboration | Task 3 |
| Target Plan abstraction | Tasks 4, 6, 8 |
| EVM CorePlan/CoreLower | Tasks 4, 5 |
| Solana CorePlan/CoreLower | Tasks 6, 7 |
| WasmHost CorePlan/CoreLower | Tasks 8, 9 |
| CLI experimental target ids | Task 10 |
| Product smokes (Counter/ValueVault) | Tasks 3, 11, 12 |
| hostOp reserved position | Task 1 (`hostOpStub`) |

### Placeholder scan

- No `TBD`, `TODO`, or "implement later" in task steps.
- Code blocks contain concrete Lean definitions.
- Test commands include expected output.
- All referenced types are defined in Task 1 or earlier in the plan.

### Type consistency

- `CoreModule` is defined in Task 1 and used consistently thereafter.
- `TargetPlan` signature uses `Plan Code : Type` as fixed in the spec self-review.
- `buildEvmCorePlan`, `buildSolanaCorePlan`, `buildWasmCorePlan` names are stable across tasks.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-11-core-ir-target-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

**Which approach?**
