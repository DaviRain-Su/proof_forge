import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Evm.IR.Validate
import ProofForge.Backend.Evm.IR.Expr
import ProofForge.Backend.Evm.Lower
import ProofForge.Backend.SharedValidate
import ProofForge.IR.Contract
import ProofForge.IR.Semantics
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Compiler.Yul.AST

/-! # EVM IR local aggregate body lowering

Compatibility lowering for local aggregate bindings and assignment statements in
the legacy EVM IR-to-Yul path. `Body.lean` imports this layer for statement and
entrypoint body lowering.
-/

namespace ProofForge.Backend.Evm.IR

open ProofForge.Backend.Evm.Plan
open ProofForge.IR.Semantics
open ProofForge.Backend.Evm.Validate (needsCheckedArithmetic exprUsesCheckedArithmetic)

open ProofForge.IR
open ProofForge.Target
open ProofForge.Backend.Evm.Validate
open ProofForge.Backend.Evm.ToYul
open ProofForge.Backend.Evm.Lower
open ProofForge.Backend.Evm.Plan

def ensureLocalScalarType (context name : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .unit => .error { message := s!"{context} `{name}` has unsupported EVM IR v0 type `Unit`" }
  | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ => .error { message := s!"{context} `{name}` has unsupported EVM IR v0 type `{type.name}`" }

def ensureLocalFixedArrayElementType (context name : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} `{name}` has unsupported EVM IR v0 fixed-array element type `{type.name}`; local fixed arrays support U32, U64, Bool, or Hash elements"
      }

def lowerStructValueFieldExprs
    (module : Module)
    (env : TypeEnv)
    (context typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError (Array (String × Lean.Compiler.Yul.Expr)) := do
  let decl ← ensureLocalFlatStructType module context typeName
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType context (.structType typeName) binding.type
      let mut values : Array (String × Lean.Compiler.Yul.Expr) := #[]
      for fieldDecl in decl.fields do
        values := values.push (fieldDecl.id, Lean.Compiler.Yul.Expr.id (structLocalFieldName sourceName fieldDecl.id))
      .ok values
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"{context} expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut values : Array (String × Lean.Compiler.Yul.Expr) := #[]
      for fieldDecl in decl.fields do
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        values := values.push (fieldDecl.id, ← lowerExpr module env field.snd)
      .ok values
  | .effect (.storageScalarRead stateId) =>
      lowerStructStorageReadFields module context typeName stateId
  | _ =>
      .error {
        message := s!"{context} supports local struct values, struct literals, or storage scalar struct reads in IR EVM v0"
      }

partial def lowerNestedFixedArrayLetBindings
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (path : Array Nat)
    (type : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      .ok #[Lean.Compiler.Yul.Statement.varDecl
        #[{ name := arrayLocalPathName name path }]
        (some (← lowerExpr module env value))]
  | .fixedArray elementType length => do
      ensureLocalNestedFixedArrayValueType module "let binding" name elementType
      match value with
      | .arrayLit literalElementType values => do
          ensureType s!"let binding `{name}` fixed-array element type" elementType literalElementType
          if values.size != length then
            .error {
              message := s!"let binding `{name}` expected fixed array length {length}, got {values.size}"
            }
          let mut statements : Array Lean.Compiler.Yul.Statement := #[]
          for h : index in [0:values.size] do
            statements := statements ++
              (← lowerNestedFixedArrayLetBindings module env name (path.push index) elementType values[index])
          .ok statements
      | _ =>
          .error {
            message := s!"let binding `{name}` fixed array must be initialized from an array literal in IR EVM v0"
          }
  | .structType typeName => do
      let fields ← lowerStructValueFieldExprs module env s!"let binding `{name}` nested fixed-array leaf" typeName value
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for field in fields do
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.varDecl
            #[{ name := arrayStructLocalPathFieldName name path field.fst }]
            (some field.snd)
      .ok statements
  | .unit | .bytes | .string | .array _ =>
      .error {
        message := s!"let binding `{name}` has unsupported EVM IR v0 nested fixed-array leaf type `Unit`; nested local fixed arrays support U32, U64, Bool, Hash, or flat struct leaves"
      }

def lowerStructArrayLetBinding
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let decl ← ensureLocalFlatStructType module s!"let binding `{name}` fixed-array element" typeName
  match value with
  | .arrayLit literalElementType values => do
      ensureType s!"let binding `{name}` fixed-array element type" (.structType typeName) literalElementType
      if values.size != length then
        .error {
          message := s!"let binding `{name}` expected fixed array length {length}, got {values.size}"
        }
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for h : index in [0:values.size] do
        match values[index] with
        | .structLit literalTypeName fields => do
            if literalTypeName != typeName then
              .error { message := s!"let binding `{name}` expected struct `{typeName}`, got `{literalTypeName}`" }
            for fieldDecl in decl.fields do
              let some field := fields.find? fun field => field.fst == fieldDecl.id
                | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
              statements := statements.push <|
                Lean.Compiler.Yul.Statement.varDecl
                  #[{ name := arrayStructLocalFieldName name index fieldDecl.id }]
                  (some (← lowerExpr module env field.snd))
        | other =>
            let actualType ← inferExprType module env other
            .error {
              message := s!"let binding `{name}` fixed-array element {index} expected struct literal `{typeName}`, got `{actualType.name}`"
            }
      .ok statements
  | _ =>
      .error {
        message := s!"let binding `{name}` fixed array of structs must be initialized from an array literal in IR EVM v0"
      }

def lowerFixedArrayLetBinding
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (elementType : ValueType)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  if length == 0 then
    .error { message := s!"let binding `{name}` fixed array must have non-zero length in IR EVM v0" }
  match elementType with
  | .structType typeName =>
      lowerStructArrayLetBinding module env name typeName length value
  | .fixedArray _ _ => do
      ensureLocalNestedFixedArrayValueType module "let binding" name elementType
      lowerNestedFixedArrayLetBindings module env name #[] (.fixedArray elementType length) value
  | _ => do
      ensureLocalFixedArrayElementType "let binding" name elementType
      match value with
      | .arrayLit literalElementType values => do
          ensureType s!"let binding `{name}` fixed-array element type" elementType literalElementType
          if values.size != length then
            .error {
              message := s!"let binding `{name}` expected fixed array length {length}, got {values.size}"
            }
          let mut statements : Array Lean.Compiler.Yul.Statement := #[]
          for h : index in [0:values.size] do
            statements := statements.push <|
              Lean.Compiler.Yul.Statement.varDecl
                #[{ name := arrayLocalElementName name index }]
                (some (← lowerExpr module env values[index]))
          .ok statements
      | _ =>
          .error {
            message := s!"let binding `{name}` fixed array must be initialized from an array literal in IR EVM v0"
          }

def lowerStructLetBinding
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct `{typeName}`" }
  match value with
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"let binding `{name}` expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for fieldDecl in decl.fields do
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.varDecl
            #[{ name := structLocalFieldName name fieldDecl.id }]
            (some (← lowerExpr module env field.snd))
      .ok statements
  | .effect (.storageScalarRead stateId) => do
      let fields ← lowerStructStorageReadFields module s!"let binding `{name}` struct type" typeName stateId
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for field in fields do
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.varDecl
            #[{ name := structLocalFieldName name field.fst }]
            (some field.snd)
      .ok statements
  | _ =>
      .error {
        message := s!"let binding `{name}` struct must be initialized from a struct literal or storage scalar struct read in IR EVM v0"
      }

def lowerAssignTargetName (context : String) : ProofForge.IR.Expr → Except LowerError String
  | .local name =>
      .ok name
  | .arrayGet (.local name) index => do
      let indexValue ← requireStaticArrayIndex s!"{context} fixed-array index" index
      .ok (arrayLocalElementName name indexValue)
  | .field (.arrayGet (.local name) index) fieldName => do
      let indexValue ← requireStaticArrayIndex s!"{context} fixed-array index" index
      .ok (arrayStructLocalFieldName name indexValue fieldName)
  | .field (.local name) fieldName =>
      .ok (structLocalFieldName name fieldName)
  | .field base fieldName =>
      match collectStaticLocalArrayGetPath base with
      | some (name, path) =>
          .ok (arrayStructLocalPathFieldName name path fieldName)
      | none =>
          .error { message := s!"{context} must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }
  | target =>
      match collectStaticLocalArrayGetPath target with
      | some (name, path) =>
          .ok (arrayLocalPathName name path)
      | none =>
          .error { message := s!"{context} must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }

def aggregateAssignArrayTempName (name : String) (index : Nat) : String :=
  ProofForge.Backend.Evm.ToYul.aggregateAssignArrayTempName name index

def aggregateAssignArrayPathTempName (name : String) (path : Array Nat) : String :=
  ProofForge.Backend.Evm.ToYul.aggregateAssignArrayPathTempName name path

def aggregateAssignStructTempName (name fieldName : String) : String :=
  ProofForge.Backend.Evm.ToYul.aggregateAssignStructTempName name fieldName

def aggregateAssignStructArrayTempName (name : String) (index : Nat) (fieldName : String) : String :=
  ProofForge.Backend.Evm.ToYul.aggregateAssignStructArrayTempName name index fieldName

def lowerFixedArrayAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (elementType : ValueType)
    (length : Nat)
    (value : ProofForge.IR.Expr) :
    Except LowerError (Array ProofForge.Backend.Evm.Plan.FixedArrayAssignmentSourcePlan) :=
  lowerValidate <|
    ProofForge.Backend.Evm.Lower.fixedArrayAssignmentSourcePlans
      module
      (toValidateTypeEnv env)
      name
      elementType
      length
      value

def lowerStructAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (value : ProofForge.IR.Expr) :
    Except LowerError (Array ProofForge.Backend.Evm.Plan.StructAssignmentSourcePlan) :=
  lowerValidate <|
    ProofForge.Backend.Evm.Lower.structAssignmentSourcePlans
      module
      (toValidateTypeEnv env)
      name
      typeName
      value

def lowerNestedFixedArrayAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (expectedType : ValueType)
    (value : ProofForge.IR.Expr) :
    Except LowerError (Array ProofForge.Backend.Evm.Plan.NestedFixedArrayAssignmentSourcePlan) :=
  lowerValidate <|
    ProofForge.Backend.Evm.Lower.nestedFixedArrayAssignmentSourcePlans
      module
      (toValidateTypeEnv env)
      name
      expectedType
      value

def lowerStructArrayAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (length : Nat)
    (value : ProofForge.IR.Expr) :
    Except LowerError (Array ProofForge.Backend.Evm.Plan.StructArrayAssignmentSourcePlan) :=
  lowerValidate <|
    ProofForge.Backend.Evm.Lower.structArrayAssignmentSourcePlans
      module
      (toValidateTypeEnv env)
      name
      typeName
      length
      value

def lowerWholeStructArrayAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let sourcePlans ← lowerStructArrayAssignmentSourcePlans module env name typeName length value
  ProofForge.Backend.Evm.ToYul.wholeStructArrayAssignStmtFromPlan
    (lowerExprPlanExpr module env)
    name
    sourcePlans

def lowerWholeFixedArrayAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (elementType : ValueType)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  match elementType with
  | .structType typeName =>
      lowerWholeStructArrayAssignStmt module env name typeName length value
  | .fixedArray _ _ => do
      let expectedType := ValueType.fixedArray elementType length
      let sourcePlans ← lowerNestedFixedArrayAssignmentSourcePlans module env name expectedType value
      ProofForge.Backend.Evm.ToYul.wholeNestedFixedArrayAssignStmtFromPlan
        (lowerExprPlanExpr module env)
        name
        sourcePlans
  | _ => do
      let sourcePlans ← lowerFixedArrayAssignmentSourcePlans module env name elementType length value
      if sourcePlans.size != length then
        .error { message := s!"assignment target `{name}` lowering produced {sourcePlans.size} element(s), expected {length}" }
      ProofForge.Backend.Evm.ToYul.wholeFixedArrayAssignStmtFromPlan
        (lowerExprPlanExpr module env)
        name
        sourcePlans

def lowerWholeStructAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let sourcePlans ← lowerStructAssignmentSourcePlans module env name typeName value
  ProofForge.Backend.Evm.ToYul.wholeStructAssignStmtFromPlan
    (lowerExprPlanExpr module env)
    name
    sourcePlans

def lowerWholeLocalAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (binding : LocalBinding)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement :=
  match binding.type with
  | .fixedArray elementType length =>
      lowerWholeFixedArrayAssignStmt module env name elementType length value
  | .structType typeName =>
      lowerWholeStructAssignStmt module env name typeName value
  | _ =>
      .error { message := s!"assignment target local `{name}` is not an aggregate value" }

def exprPlanIsStaticAggregateScalarTarget : ProofForge.Backend.Evm.Plan.ExprPlan → Bool
  | .localArrayGet _ path _ =>
      match ProofForge.Backend.Evm.ToYul.localArrayStaticPath? path with
      | some _ => true
      | none => false
  | .structField (.local _) _ =>
      true
  | .structField (.localArrayGet _ path _) _ =>
      match ProofForge.Backend.Evm.ToYul.localArrayStaticPath? path with
      | some _ => true
      | none => false
  | _ => false

def buildStaticAggregateScalarTargetPlan?
    (module : Module)
    (env : TypeEnv)
    (target : ProofForge.IR.Expr) :
    Except LowerError (Option ProofForge.Backend.Evm.Plan.ExprPlan) := do
  match target with
  | .field (.local name) fieldName =>
      .ok (some (.structField (.local name) fieldName))
  | _ =>
      match collectLocalArrayFieldGetPath target with
      | some (name, path, fieldName) => do
          let some binding := findLocal? env name
            | .error { message := s!"unknown local `{name}`" }
          let (lengths, _) ← fixedArrayPathShape "assignment target fixed-array path" binding.type path
          .ok <| some <| .structField
            (.localArrayGet name
              (← path.mapM fun index =>
                match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) index with
                | .ok plan => .ok plan
                | .error err => .error { message := err.message })
              lengths)
            fieldName
      | none =>
          match collectLocalArrayGetPath target with
          | some (name, path) => do
              let some binding := findLocal? env name
                | .error { message := s!"unknown local `{name}`" }
              let (lengths, _) ← fixedArrayPathShape "assignment target fixed-array path" binding.type path
              .ok <| some <| .localArrayGet name
                (← path.mapM fun index =>
                  match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) index with
                  | .ok plan => .ok plan
                  | .error err => .error { message := err.message })
                lengths
          | none =>
              .ok none

def lowerAggregateScalarAssignmentStmt
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (target value : ProofForge.IR.Expr)
    (op? : Option AssignOp) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let targetPlan? ← buildStaticAggregateScalarTargetPlan? module env target
  match targetPlan? with
  | none =>
      .error {
        message := s!"{context} must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0"
      }
  | some targetPlan =>
      let valuePlan ←
        match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) value with
        | .ok plan => .ok plan
        | .error err => .error { message := err.message }
      let stmtPlan :=
        match op? with
        | none => ProofForge.Backend.Evm.Plan.StmtPlan.assign targetPlan valuePlan
        | some op => ProofForge.Backend.Evm.Plan.StmtPlan.assignOp targetPlan op valuePlan
      if exprPlanIsStaticAggregateScalarTarget targetPlan then
        ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
          module.overflowChecked
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          stmtPlan
      else
        ProofForge.Backend.Evm.ToYul.dynamicAggregateScalarAssignmentStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          stmtPlan

def lowerAssignStmt
    (module : Module)
    (env : TypeEnv)
    (target value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  match target with
  | .local name => do
      let some binding := findLocal? env name
        | .error { message := s!"unknown local `{name}`" }
      match binding.type with
      | .fixedArray _ _ | .structType _ =>
          .ok #[← lowerWholeLocalAssignStmt module env name binding value]
      | _ =>
          lowerScalarLocalAssignmentStmt module env name none value
  | _ =>
      lowerAggregateScalarAssignmentStmt module env "assignment target" target value none

def lowerAssignOpStmt
    (module : Module)
    (env : TypeEnv)
    (target : ProofForge.IR.Expr)
    (op : AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  match target with
  | .local name => do
      let some binding := findLocal? env name
        | .error { message := s!"unknown local `{name}`" }
      match binding.type with
      | .fixedArray _ _ | .structType _ =>
          let targetName ← lowerAssignTargetName "compound assignment target" target
          .ok #[.assignment #[targetName] (lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id targetName) (← lowerAssignmentValueExpr module env value))]
      | _ =>
          lowerScalarLocalAssignmentStmt module env name (some op) value
  | _ =>
      lowerAggregateScalarAssignmentStmt module env "compound assignment target" target value (some op)

mutual
  partial def statementAlwaysReturns : Statement → Bool :=
    ProofForge.Backend.SharedValidate.statementAlwaysReturns

  partial def statementsAlwaysReturn (statements : Array Statement) : Bool :=
    ProofForge.Backend.SharedValidate.statementsAlwaysReturn statements
end


end ProofForge.Backend.Evm.IR
