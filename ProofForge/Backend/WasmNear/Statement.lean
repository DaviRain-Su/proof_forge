/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmNear.Diagnostics
import ProofForge.Backend.WasmNear.ExprAnalysis
import ProofForge.Backend.WasmNear.LoweringEnv
import ProofForge.Backend.WasmNear.Struct
import ProofForge.Backend.WasmNear.Types

namespace ProofForge.Backend.WasmNear.Statement

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Diagnostics
open ProofForge.Backend.WasmNear.ExprAnalysis
open ProofForge.Backend.WasmNear.LoweringEnv
open ProofForge.Backend.WasmNear.Struct
open ProofForge.Backend.WasmNear.Types

/-! Small, non-recursive statement instruction helpers used by EmitWat. -/

def localLetBindInsns (name : String) (expectedType : ValueType)
    (valueInsns : Array Insn) (valueType : ValueType) : Except EmitError (Array Insn) :=
  if valueType != expectedType then
    err s!"EmitWat: let `{name}` expected `{expectedType.name}`, got `{valueType.name}`"
  else .ok (valueInsns ++ #[.localSet name])

def localAssignInsns (env : LocalTypes) (name : String) (valueInsns : Array Insn) :
    Except EmitError (Array Insn) :=
  if (lookupLocal? env name).isNone then err s!"EmitWat: assignment to unknown local `{name}`"
  else .ok (valueInsns ++ #[.localSet name])

def localAssignOpTargetType (env : LocalTypes) (name : String) : Except EmitError ValueType := do
  let some localType ← pure (lookupLocal? env name) |
    err s!"EmitWat: compound assignment to unknown local `{name}`"
  if !(isNumeric localType) then err "EmitWat: compound assignment requires U32/U64 local"
  else .ok localType

def localAssignOpInsns (name : String) (op : AssignOp) (localType : ValueType)
    (valueInsns : Array Insn) (valueType : ValueType) : Except EmitError (Array Insn) :=
  if valueType != localType then
    err s!"EmitWat: compound `{assignOpName op}` expected `{localType.name}`, got `{valueType.name}`"
  else
    .ok (#[.localGet name] ++ valueInsns ++
      #[.plain (widthOf localType ++ "." ++ assignOpName op), .localSet name])

def storagePathAssignOpTargetType (valueKind : String) (currentType : ValueType) :
    Except EmitError ValueType :=
  if !isNumeric currentType then
    err s!"EmitWat: storagePathAssignOp requires U32/U64 {valueKind}, got `{currentType.name}`"
  else .ok currentType

def storagePathAssignOpValueInsns (op : AssignOp) (currentInsns : Array Insn)
    (currentType : ValueType) (valueInsns : Array Insn) (valueType : ValueType) :
    Except EmitError (Array Insn) :=
  if valueType != currentType then
    err s!"EmitWat: storagePathAssignOp expected `{currentType.name}`, got `{valueType.name}`"
  else
    .ok (currentInsns ++ valueInsns ++ #[.plain (widthOf currentType ++ "." ++ assignOpName op)])

def dropResultInsns (valueInsns : Array Insn) : Array Insn :=
  valueInsns ++ #[.drop]

def appendInsnChunks (chunks : Array (Array Insn)) : Array Insn :=
  chunks.foldl (fun acc is => acc ++ is) #[]

def appendInsnChunksM {m : Type -> Type} [Monad m] {α : Type}
    (items : Array α) (lower : α -> m (Array Insn)) : m (Array Insn) :=
  items.foldlM (init := #[]) fun acc item => do
    let is ← lower item
    pure (acc ++ is)

def requireDuplicableExpr (expr : Expr) (message : String) : Except EmitError Unit :=
  if canDuplicateExpr expr then .ok () else err message

def ifElseInsns (conditionInsns thenInsns elseInsns : Array Insn) : Array Insn :=
  conditionInsns ++ #[.if_ { insns := thenInsns } { insns := elseInsns }]

def boundedForInsns (indexName : String) (start stop : Nat) (bodyInsns : Array Insn) :
    Array Insn :=
  #[.i64Const start, .localSet indexName,
    .block_ { insns := #[ .loop_ { insns := #[
      .localGet indexName, .i64Const stop, .plain "i64.ge_u", .brIf 1 ] ++ bodyInsns ++ #[
      .localGet indexName, .i64Const 1, .plain "i64.add", .localSet indexName, .br 0 ] } ] } ]

def releaseInsns (ctx : Ctx) (env : LocalTypes) (name : String) :
    Except EmitError (Array Insn) := do
  let some valueType ← pure (lookupLocal? env name) |
    err s!"EmitWat: release of unknown local `{name}`"
  match valueType with
  | .fixedArray elemType len =>
    .ok #[.localGet name, .i64Const (len * scalarWidth elemType), .call "__pf_arr_dealloc"]
  | .structType typeName =>
    match findStruct? ctx.structs typeName with
    | none => err s!"EmitWat: release refers to unknown struct `{typeName}`"
    | some sd => .ok #[.localGet name, .i64Const (structTotalSize sd), .call "__pf_arr_dealloc"]
  | _ => err s!"EmitWat: release expects a heap-backed FixedArray/Struct local, got `{valueType.name}`"

end ProofForge.Backend.WasmNear.Statement
