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

/-! # EVM IR entrypoint body lowering

Compatibility lowering for local aggregate bindings, assignments, returns, and
planned `StmtPlan` bodies. The public `IR.lean` facade imports this module and
keeps module assembly, dispatch, validation, and metadata construction.
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

def abiReturnNames (module : Module) (entrypointName : String) : ValueType → Except LowerError (Array String)
  | returnType => do
      let plan ←
        match ProofForge.Backend.Evm.Lower.returnPlan module s!"entrypoint `{entrypointName}`" returnType with
        | .ok plan => .ok plan
        | .error err => .error { message := err.message }
      .ok plan.localNames

def abiReturnTypedNames (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array Lean.Compiler.Yul.TypedName) := do
  let plan ←
    match ProofForge.Backend.Evm.Lower.returnPlan module s!"entrypoint `{entrypoint.name}`" entrypoint.returns with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  .ok (ProofForge.Backend.Evm.ToYul.returnTypedNames plan)

def returnTypeSupportsScalarStmtPlan : ValueType → Bool
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
  | .unit | .bytes | .string | .array _ | .fixedArray _ _ | .structType _ => false

def returnTypeSupportsDynamicStmtPlan : ValueType → Bool
  | .bytes | .string | .array _ => true
  | .unit | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .fixedArray _ _ | .structType _ => false

def returnTypeSupportsAggregateStmtPlan : ValueType → Bool
  | .fixedArray _ _ | .structType _ => true
  | .unit | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .bytes | .string | .array _ => false

def lowerAggregateCrosscallReturnAssignment?
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Option (Array Lean.Compiler.Yul.Statement)) := do
  let plan? ←
    match ProofForge.Backend.Evm.Lower.aggregateCrosscallReturnAssignmentPlan?
        module (toValidateTypeEnv env) entrypointName returnType value with
    | .ok plan? => .ok plan?
    | .error err => .error { message := err.message }
  match plan? with
  | some plan => .ok (some #[← lowerCrosscallReturnAssignmentPlan module env plan])
  | none => .ok none

def lowerReturnAssignments
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let aggregateAssignment? ← lowerAggregateCrosscallReturnAssignment? module env entrypointName returnType value
  match aggregateAssignment? with
  | some statements => .ok statements
  | none => do
      let returnValuePlan? ←
        match ProofForge.Backend.Evm.Lower.returnValueWordPlan?
            module (toValidateTypeEnv env) entrypointName returnType value with
        | .ok plan? => .ok plan?
        | .error err => .error { message := err.message }
      match returnValuePlan? with
      | some plan =>
          lowerReturnValueWordPlan module env entrypointName plan
      | none =>
          .error {
            message := s!"entrypoint `{entrypointName}` aggregate return must be consumed by ReturnValueWordPlan or aggregate crosscall return planning in IR EVM v0"
          }

partial def lowerReturnStmtPlan
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ProofForge.IR.Expr)
    (leaveAfterReturn : Bool) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  if returnTypeSupportsDynamicStmtPlan returnType then
    match value with
    | .local _ =>
        let valuePlan ←
          match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) value with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        let returns ←
          match ProofForge.Backend.Evm.Lower.returnPlan module s!"entrypoint `{entrypointName}`" returnType with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        ProofForge.Backend.Evm.ToYul.dynamicReturnStmtPlanStatements
          toYulError
          returns
          leaveAfterReturn
          (.return valuePlan)
    | _ =>
        .error {
          message := s!"entrypoint `{entrypointName}` dynamic returns in IR EVM v0 support local references only"
        }
  else if returnTypeSupportsAggregateStmtPlan returnType then
    let statements ← lowerReturnAssignments module env entrypointName returnType value
    if leaveAfterReturn then
      .ok (statements.push .leave)
    else
      .ok statements
  else if returnTypeSupportsScalarStmtPlan returnType then
    let valuePlan ←
      match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) value with
      | .ok plan => .ok plan
      | .error err => .error { message := err.message }
    let returns ←
      match ProofForge.Backend.Evm.Lower.returnPlan module s!"entrypoint `{entrypointName}`" returnType with
      | .ok plan => .ok plan
      | .error err => .error { message := err.message }
    ProofForge.Backend.Evm.ToYul.scalarReturnExprPlanStatements
      toYulError
      (lowerExprPlanExpr module env)
      returns.localNames
      leaveAfterReturn
      (.return valuePlan)
  else
    .error { message := s!"entrypoint `{entrypointName}` has unsupported return type `{returnType.name}` in IR EVM v0" }

def lowerReturnStmt
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ProofForge.IR.Expr)
    (leaveAfterReturn : Bool) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  lowerReturnStmtPlan module env entrypointName returnType value leaveAfterReturn

def plannedBodyScalarTypeSupported : ValueType → Bool
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
  | .unit | .bytes | .string | .array _ | .fixedArray _ _ | .structType _ => false

partial def storagePathSegmentSupportsPlannedBody :
    StoragePathSegment → Bool
  | .field _ => true
  | .index index => exprSupportsPlanScalarYul index
  | .mapKey key => exprSupportsPlanScalarYul key

def storagePathSupportsPlannedBody
    (path : Array StoragePathSegment) : Bool :=
  path.all storagePathSegmentSupportsPlannedBody

def valuePlanSupportsPlannedBody :
    ProofForge.Backend.Evm.Plan.ValuePlan → Bool
  | .irExpr expr => exprSupportsPlanScalarYul expr

def storageSlotPlanSupportsPlannedBody :
    ProofForge.Backend.Evm.Plan.StorageSlotPlan → Bool
  | .scalarSlot _ | .fixedSlot _ => true
  | .mapValueSlot _ keys
  | .mapPresenceSlot _ keys =>
      keys.all valuePlanSupportsPlannedBody
  | .arraySlot _ _ index
  | .structArrayFieldSlot _ _ _ _ index
  | .dynamicArraySlot _ index =>
      valuePlanSupportsPlannedBody index

def storagePathWriteTargetPlanSupportsPlannedBody :
    ProofForge.Backend.Evm.Plan.StoragePathWriteTargetPlan → Bool
  | .mapWrite _ key => valuePlanSupportsPlannedBody key
  | .singleSlot slot => storageSlotPlanSupportsPlannedBody slot
  | .mapValuePresence valueSlot presenceSlot =>
      storageSlotPlanSupportsPlannedBody valueSlot &&
        storageSlotPlanSupportsPlannedBody presenceSlot

def scalarStorageTargetPlanSupportsPlannedBody
    (target : ProofForge.Backend.Evm.Plan.ScalarStorageTargetPlan) : Bool :=
  storageSlotPlanSupportsPlannedBody target.slot

mutual
  partial def storageSlotExprPlanSupportsPlannedBody :
      ProofForge.Backend.Evm.Plan.StorageSlotExprPlan → Bool
    | .scalarSlot _ | .fixedSlot _ => true
    | .mapValueSlot _ keys
    | .mapPresenceSlot _ keys =>
        keys.all exprPlanSupportsPlannedBody
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        exprPlanSupportsPlannedBody index

  partial def storagePathWriteExprTargetPlanSupportsPlannedBody :
      ProofForge.Backend.Evm.Plan.StoragePathWriteExprTargetPlan → Bool
    | .mapWrite _ key => exprPlanSupportsPlannedBody key
    | .singleSlot slot => storageSlotExprPlanSupportsPlannedBody slot
    | .mapValuePresence valueSlot presenceSlot =>
        storageSlotExprPlanSupportsPlannedBody valueSlot &&
          storageSlotExprPlanSupportsPlannedBody presenceSlot

  partial def effectPlanSupportsPlannedBodyExpr :
      ProofForge.Backend.Evm.Plan.EffectPlan → Bool
    | .storageScalarRead _ => true
    | .storageScalarReadTarget target =>
        scalarStorageTargetPlanSupportsPlannedBody target
    | .contextRead _ => true
    | .storageMapContains _ key
    | .storageMapGet _ key => exprPlanSupportsPlannedBody key
    | .storageMapContainsTarget _ key
    | .storageMapGetTarget _ key => exprPlanSupportsPlannedBody key
    | .storageArrayRead _ index => exprPlanSupportsPlannedBody index
    | .storageArrayReadTarget _ index => exprPlanSupportsPlannedBody index
    | .storageStructFieldRead _ _ => true
    | .storageStructFieldReadTarget _ => true
    | .storageArrayStructFieldRead _ index _ => exprPlanSupportsPlannedBody index
    | .storageArrayStructFieldReadTarget _ index => exprPlanSupportsPlannedBody index
    | .storagePathRead _ path => storagePathSupportsPlannedBody path
    | .storagePathReadTarget slot => storageSlotPlanSupportsPlannedBody slot
    | .storagePathReadExprTarget slot => storageSlotExprPlanSupportsPlannedBody slot
    | _ => false

  partial def crosscallArgWordPlanSupportsPlannedBody :
      ProofForge.Backend.Evm.Plan.CrosscallArgWordPlan → Bool
    | .expr value => exprPlanSupportsPlannedBody value
    | .local .. | .storage .. => true

  partial def exprPlanSupportsPlannedBody :
      ProofForge.Backend.Evm.Plan.ExprPlan → Bool
    | .literalWord _ => true
    | .local _ => true
    | .calldataWord _ => true
    | .storageLoad _ => true
    | .builtin _ args => args.all exprPlanSupportsPlannedBody
    | .helperCall _ args => args.all exprPlanSupportsPlannedBody
    | .checkedArith _ lhs rhs => exprPlanSupportsPlannedBody lhs && exprPlanSupportsPlannedBody rhs
    | .hashPack a b c d =>
        exprPlanSupportsPlannedBody a &&
        exprPlanSupportsPlannedBody b &&
        exprPlanSupportsPlannedBody c &&
        exprPlanSupportsPlannedBody d
    | .context _ => true
    | .cast source _ => exprPlanSupportsPlannedBody source
    | .hashValue a b c d =>
        exprPlanSupportsPlannedBody a &&
        exprPlanSupportsPlannedBody b &&
        exprPlanSupportsPlannedBody c &&
        exprPlanSupportsPlannedBody d
    | .hash preimage => exprPlanSupportsPlannedBody preimage
    | .hashTwoToOne lhs rhs => exprPlanSupportsPlannedBody lhs && exprPlanSupportsPlannedBody rhs
    | .nativeValue => true
    | .effect effect => effectPlanSupportsPlannedBodyExpr effect
    | .crosscall _ target methodId callValue? args returnType =>
        plannedBodyScalarTypeSupported returnType &&
        exprPlanSupportsPlannedBody target &&
        exprPlanSupportsPlannedBody methodId &&
        (match callValue? with
         | none => true
         | some callValue => exprPlanSupportsPlannedBody callValue) &&
        args.all crosscallArgWordPlanSupportsPlannedBody
    | .create _ callValue salt? _ =>
        exprPlanSupportsPlannedBody callValue &&
        match salt? with
        | none => true
        | some salt => exprPlanSupportsPlannedBody salt
    | .localArrayGet _ path _ =>
        path.all exprPlanSupportsPlannedBody
    | .arrayGet (.arrayLit _ values) index =>
        !values.isEmpty &&
          values.all exprPlanSupportsPlannedBody &&
          exprPlanSupportsPlannedBody index
    | .structField (.local _) _ => true
    | .structField (.structLit _ fields) _ =>
        fields.all fun field => exprPlanSupportsPlannedBody field.snd
    | .structField (.localArrayGet _ path _) _ =>
        path.all exprPlanSupportsPlannedBody
    | .memoryArrayNew _ length =>
        exprPlanSupportsPlannedBody length
    | .memoryArrayLength array =>
        exprPlanSupportsPlannedBody array
    | .memoryArrayGet array index =>
        exprPlanSupportsPlannedBody array && exprPlanSupportsPlannedBody index
    | .structField .. | .arrayGet .. | .arrayLit .. | .structLit .. => false
end

def plannedBodyAssignmentTargetSupported :
    ProofForge.Backend.Evm.Plan.ExprPlan → Bool
  | .local _ => true
  | target => exprPlanIsStaticAggregateScalarTarget target

def eventFieldPlanSupportsPlannedBody :
    ProofForge.Backend.Evm.Plan.EventFieldPlan → Bool
  | .mk _ type _ =>
      match type with
      | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
      | .unit | .bytes | .string | .array _ | .fixedArray _ _ | .structType _ => false

def abiValuePlanSupportsPlannedBody :
    ProofForge.Backend.Evm.Plan.AbiValuePlan → Bool
  | .expr value => exprPlanSupportsPlannedBody value
  | .local .. | .storage .. | .arrayLit .. | .structLit .. => false

def eventFieldWordPlansSupportPlannedBody
    (fields : Array ProofForge.Backend.Evm.Plan.EventFieldPlan)
    (fieldWords : Array (Array ProofForge.Backend.Evm.Plan.ExprPlan)) : Bool :=
  fields.size == fieldWords.size &&
    fieldWords.all (fun words => words.all exprPlanSupportsPlannedBody)

def eventFieldPlansSupportPlannedBody
    (fields : Array ProofForge.Backend.Evm.Plan.EventFieldPlan)
    (values : Array ProofForge.Backend.Evm.Plan.AbiValuePlan) : Bool :=
  fields.size == values.size &&
    fields.all eventFieldPlanSupportsPlannedBody &&
    values.all abiValuePlanSupportsPlannedBody

def effectPlanSupportsPlannedBodyStmt :
    ProofForge.Backend.Evm.Plan.EffectPlan → Bool
  | .storageScalarWrite _ value => exprPlanSupportsPlannedBody value
  | .storageScalarWriteTarget target value =>
      scalarStorageTargetPlanSupportsPlannedBody target &&
        exprPlanSupportsPlannedBody value
  | .storageScalarAssignOp _ _ value => exprPlanSupportsPlannedBody value
  | .storageScalarAssignOpTarget target _ value =>
      scalarStorageTargetPlanSupportsPlannedBody target &&
        exprPlanSupportsPlannedBody value
  | .storageMapInsert _ key value
  | .storageMapSet _ key value =>
      exprPlanSupportsPlannedBody key && exprPlanSupportsPlannedBody value
  | .storageMapInsertTarget _ key value
  | .storageMapSetTarget _ key value =>
      exprPlanSupportsPlannedBody key && exprPlanSupportsPlannedBody value
  | .storageArrayWrite _ index value =>
      exprPlanSupportsPlannedBody index && exprPlanSupportsPlannedBody value
  | .storageArrayWriteTarget _ index value =>
      exprPlanSupportsPlannedBody index && exprPlanSupportsPlannedBody value
  | .storageArrayStructFieldWrite _ index _ value =>
      exprPlanSupportsPlannedBody index && exprPlanSupportsPlannedBody value
  | .storageArrayStructFieldWriteTarget _ index value =>
      exprPlanSupportsPlannedBody index && exprPlanSupportsPlannedBody value
  | .storageDynamicArrayPush _ value =>
      exprPlanSupportsPlannedBody value
  | .storageDynamicArrayPushTarget _ value =>
      exprPlanSupportsPlannedBody value
  | .storageDynamicArrayPop _ =>
      true
  | .storageDynamicArrayPopTarget _ =>
      true
  | .memoryArraySet array index value =>
      exprPlanSupportsPlannedBody array &&
        exprPlanSupportsPlannedBody index &&
        exprPlanSupportsPlannedBody value
  | .storageStructFieldWrite _ _ value =>
      exprPlanSupportsPlannedBody value
  | .storageStructFieldWriteTarget _ value =>
      exprPlanSupportsPlannedBody value
  | .storagePathWrite _ path value =>
      storagePathSupportsPlannedBody path && exprPlanSupportsPlannedBody value
  | .storagePathWriteTarget target value =>
      storagePathWriteTargetPlanSupportsPlannedBody target &&
        exprPlanSupportsPlannedBody value
  | .storagePathWriteExprTarget target value =>
      storagePathWriteExprTargetPlanSupportsPlannedBody target &&
        exprPlanSupportsPlannedBody value
  | .storagePathAssignOp _ path _ value =>
      storagePathSupportsPlannedBody path && exprPlanSupportsPlannedBody value
  | .storagePathAssignOpTarget target _ value =>
      storagePathWriteTargetPlanSupportsPlannedBody target &&
        exprPlanSupportsPlannedBody value
  | .storagePathAssignOpExprTarget target _ value =>
      storagePathWriteExprTargetPlanSupportsPlannedBody target &&
        exprPlanSupportsPlannedBody value
  | .eventEmit event dataFields =>
      event.indexedFields.isEmpty &&
        eventFieldPlansSupportPlannedBody event.dataFields dataFields
  | .eventEmitIndexed event indexedFields dataFields =>
      eventFieldPlansSupportPlannedBody event.indexedFields indexedFields &&
        eventFieldPlansSupportPlannedBody event.dataFields dataFields
  | .eventEmitWords event dataFieldWords =>
      event.indexedFields.isEmpty &&
        eventFieldWordPlansSupportPlannedBody event.dataFields dataFieldWords
  | .eventEmitIndexedWords event indexedFieldWords dataFieldWords =>
      eventFieldWordPlansSupportPlannedBody event.indexedFields indexedFieldWords &&
        eventFieldWordPlansSupportPlannedBody event.dataFields dataFieldWords
  | _ => false

partial def aggregateReturnExprPlanSupportsPlannedBody
    (returnType : ValueType)
    (value : ProofForge.Backend.Evm.Plan.ExprPlan) : Bool :=
  match returnType with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      exprPlanSupportsPlannedBody value
  | .fixedArray elementType length =>
      match value with
      | .local _ => true
      | .crosscall _ target methodId callValue? args callReturnType =>
          callReturnType == returnType &&
            exprPlanSupportsPlannedBody target &&
            exprPlanSupportsPlannedBody methodId &&
            (match callValue? with
             | none => true
             | some callValue => exprPlanSupportsPlannedBody callValue) &&
            args.all crosscallArgWordPlanSupportsPlannedBody
      | .arrayLit literalElementType values =>
          literalElementType == elementType &&
            values.size == length &&
            values.all (aggregateReturnExprPlanSupportsPlannedBody elementType)
      | _ => false
  | .structType _ =>
      match value with
      | .local _ => true
      | .effect (.storageScalarRead _) => true
      | .crosscall _ target methodId callValue? args callReturnType =>
          callReturnType == returnType &&
            exprPlanSupportsPlannedBody target &&
            exprPlanSupportsPlannedBody methodId &&
            (match callValue? with
             | none => true
             | some callValue => exprPlanSupportsPlannedBody callValue) &&
            args.all crosscallArgWordPlanSupportsPlannedBody
      | .structLit _ fields =>
          fields.all fun field => exprPlanSupportsPlannedBody field.snd
      | _ => false
  | .unit | .bytes | .string | .array _ => false

def returnStmtPlanSupportsPlannedBody
    (returnType : ValueType)
    (value : ProofForge.Backend.Evm.Plan.ExprPlan) : Bool :=
  if returnTypeSupportsScalarStmtPlan returnType then
    exprPlanSupportsPlannedBody value
  else if returnTypeSupportsDynamicStmtPlan returnType then
    match value with
    | .local _ => true
    | _ => false
  else if returnTypeSupportsAggregateStmtPlan returnType then
    aggregateReturnExprPlanSupportsPlannedBody returnType value
  else
    false

mutual
  partial def stmtPlanSupportsPlannedBody
      (returnType : ValueType) :
      ProofForge.Backend.Evm.Plan.StmtPlan → Bool
    | .letBind _ type value
    | .letMutBind _ type value =>
        plannedBodyScalarTypeSupported type && exprPlanSupportsPlannedBody value
    | .assign target value
    | .assignOp target _ value =>
        plannedBodyAssignmentTargetSupported target && exprPlanSupportsPlannedBody value
    | .effect effect =>
        effectPlanSupportsPlannedBodyStmt effect
    | .assert condition _ _ =>
        exprPlanSupportsPlannedBody condition
    | .assertEq lhs rhs _ _ =>
        exprPlanSupportsPlannedBody lhs && exprPlanSupportsPlannedBody rhs
    | .release _ => false
    | .revert _ => true
    | .revertWithError _ => true
    | .ifElse condition thenBody elseBody =>
        exprPlanSupportsPlannedBody condition &&
        stmtPlansSupportPlannedBody returnType thenBody &&
        stmtPlansSupportPlannedBody returnType elseBody
    | .boundedFor _ _ _ body =>
        stmtPlansSupportPlannedBody returnType body
    | .return value =>
        returnStmtPlanSupportsPlannedBody returnType value

  partial def stmtPlansSupportPlannedBody
      (returnType : ValueType)
      (plans : Array ProofForge.Backend.Evm.Plan.StmtPlan) : Bool :=
    plans.all (stmtPlanSupportsPlannedBody returnType)
end

def plannedBodyEntrypoint
    (entrypointName : String)
    (returnType : ValueType) : Entrypoint := {
  name := entrypointName
  returns := returnType
  body := #[]
}

def plannedBodyStatement?
    (module : Module)
    (entrypointName : String)
    (returnType : ValueType)
    (env : TypeEnv)
    (statement : ProofForge.IR.Statement) :
    Except LowerError (Option ProofForge.Backend.Evm.Plan.StmtPlan) := do
  let entrypoint := plannedBodyEntrypoint entrypointName returnType
  match validateStatementTypes module entrypoint env statement with
  | .ok _ => pure ()
  | .error _ => return none
  match ProofForge.Backend.Evm.Lower.buildStatementPlan module entrypoint (toValidateTypeEnv env) statement with
  | .ok (plan, _) =>
      if stmtPlanSupportsPlannedBody returnType plan then
        .ok (some plan)
      else
        .ok none
  | .error _ =>
      .ok none

def lowerPlannedBodyEventEffectPlan
    (module : Module)
    (env : TypeEnv)
    (effect : ProofForge.Backend.Evm.Plan.EffectPlan) :
    Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let effect ← lowerEventEffectWordPlan module env effect
  ProofForge.Backend.Evm.ToYul.eventEffectStmtPlanStatements
    toYulError
    (lowerExprPlanExpr module env)
    (.effect effect)

def lowerPlannedBodyEffectPlan
    (module : Module)
    (env : TypeEnv)
    (effect : ProofForge.Backend.Evm.Plan.EffectPlan) :
    Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  match effect with
  | .storageScalarWriteTarget .. | .storageScalarAssignOpTarget .. =>
      ProofForge.Backend.Evm.ToYul.scalarStorageTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (.effect effect)
  | .storageScalarWrite stateId value => do
      match ← scalarStateType module stateId with
      | .structType _ =>
          let fields ←
            lowerValidate <|
              ProofForge.Backend.Evm.Lower.storageStructWriteFieldPlans
                module
                (toValidateTypeEnv env)
                stateId
                value
          ProofForge.Backend.Evm.ToYul.storageStructWriteFieldPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            stateId
            fields
      | _ =>
          match ProofForge.Backend.Evm.Lower.scalarStorageTargetPlan? module stateId with
          | some target =>
              ProofForge.Backend.Evm.ToYul.scalarStorageTargetEffectStmtPlanStatements
                toYulError
                (fun expr => lowerExpr module env expr)
                (lowerPlanEffectExpr module env)
                (.effect (.storageScalarWriteTarget target value))
          | none =>
              ProofForge.Backend.Evm.ToYul.scalarStorageEffectStmtPlanStatements
                toYulError
                (fun expr => lowerExpr module env expr)
                (lowerPlanEffectExpr module env)
                (lowerScalarStorageSlotExpr module env)
                (scalarStatePacking module)
                (.effect effect)
  | .storageScalarAssignOp stateId op value => do
      match ← scalarStateType module stateId with
      | .structType _ =>
          .error { message := s!"storage.scalar.assign_op does not support struct state `{stateId}` in planned body lowering yet" }
      | _ =>
          match ProofForge.Backend.Evm.Lower.scalarStorageTargetPlan? module stateId with
          | some target =>
              ProofForge.Backend.Evm.ToYul.scalarStorageTargetEffectStmtPlanStatements
                toYulError
                (fun expr => lowerExpr module env expr)
                (lowerPlanEffectExpr module env)
                (.effect (.storageScalarAssignOpTarget target op value))
          | none =>
              ProofForge.Backend.Evm.ToYul.scalarStorageEffectStmtPlanStatements
                toYulError
                (fun expr => lowerExpr module env expr)
                (lowerPlanEffectExpr module env)
                (lowerScalarStorageSlotExpr module env)
                (scalarStatePacking module)
                (.effect effect)
  | .storageMapInsertTarget .. | .storageMapSetTarget .. =>
      ProofForge.Backend.Evm.ToYul.mapWriteTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (.effect effect)
  | .storageMapInsert stateId key value =>
      match ProofForge.Backend.Evm.Lower.mapWriteTargetPlan? module stateId with
      | some target =>
          ProofForge.Backend.Evm.ToYul.mapWriteTargetEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (.effect (.storageMapInsertTarget target key value))
      | none =>
          ProofForge.Backend.Evm.ToYul.mapWriteEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (fun stateId => do
              let (slot, _, _) ← requireStorageMapState module stateId
              .ok (slotExpr slot))
            (.effect effect)
  | .storageMapSet stateId key value =>
      match ProofForge.Backend.Evm.Lower.mapWriteTargetPlan? module stateId with
      | some target =>
          ProofForge.Backend.Evm.ToYul.mapWriteTargetEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (.effect (.storageMapSetTarget target key value))
      | none =>
          ProofForge.Backend.Evm.ToYul.mapWriteEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (fun stateId => do
              let (slot, _, _) ← requireStorageMapState module stateId
              .ok (slotExpr slot))
            (.effect effect)
  | .storageArrayWrite stateId index value =>
      match ProofForge.Backend.Evm.Lower.arrayWriteTargetPlan? module stateId with
      | some target =>
          ProofForge.Backend.Evm.ToYul.arrayWriteTargetEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (.effect (.storageArrayWriteTarget target index value))
      | none =>
          ProofForge.Backend.Evm.ToYul.arrayWriteEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (fun stateId indexPlan => do
              let (slot, length, _) ← requireStorageArrayState module stateId
              .ok (ProofForge.Backend.Evm.ToYul.helperCall ProofForge.Backend.Evm.Plan.Helper.arraySlot #[
                slotExpr slot,
                Lean.Compiler.Yul.Expr.num length,
                ← lowerExprPlanExpr module env indexPlan
              ]))
            (.effect effect)
  | .storageArrayWriteTarget .. =>
      ProofForge.Backend.Evm.ToYul.arrayWriteTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (.effect effect)
  | .storageDynamicArrayPushTarget .. =>
      ProofForge.Backend.Evm.ToYul.dynamicArrayPushTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (.effect effect)
  | .storageDynamicArrayPopTarget .. =>
      ProofForge.Backend.Evm.ToYul.dynamicArrayPopTargetEffectStmtPlanStatements
        toYulError
        (.effect effect)
  | .memoryArraySet .. =>
      ProofForge.Backend.Evm.ToYul.memoryArraySetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (.effect effect)
  | .storageStructFieldWriteTarget .. =>
      ProofForge.Backend.Evm.ToYul.structFieldWriteTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (.effect effect)
  | .storageArrayStructFieldWriteTarget .. =>
      ProofForge.Backend.Evm.ToYul.structArrayFieldWriteTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (.effect effect)
  | .storageStructFieldWrite stateId fieldName value =>
      match ProofForge.Backend.Evm.Lower.structFieldWriteTargetPlan? module stateId fieldName with
      | some target =>
          ProofForge.Backend.Evm.ToYul.structFieldWriteTargetEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (.effect (.storageStructFieldWriteTarget target value))
      | none =>
          ProofForge.Backend.Evm.ToYul.structFieldWriteEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (fun stateId fieldName => lowerStructFieldSlotExpr module stateId fieldName)
            (fun stateId indexPlan fieldName => do
              let (slot, length, fieldCount, fieldOffset, _) ← requireStructArrayStateField module stateId fieldName
              .ok (ProofForge.Backend.Evm.ToYul.helperCall ProofForge.Backend.Evm.Plan.Helper.structArraySlot #[
                slotExpr slot,
                Lean.Compiler.Yul.Expr.num length,
                Lean.Compiler.Yul.Expr.num fieldCount,
                Lean.Compiler.Yul.Expr.num fieldOffset,
                ← lowerExprPlanExpr module env indexPlan
              ]))
            (.effect effect)
  | .storageArrayStructFieldWrite stateId index fieldName value =>
      match ProofForge.Backend.Evm.Lower.structArrayFieldWriteTargetPlan? module stateId fieldName with
      | some target =>
          ProofForge.Backend.Evm.ToYul.structArrayFieldWriteTargetEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (.effect (.storageArrayStructFieldWriteTarget target index value))
      | none =>
          ProofForge.Backend.Evm.ToYul.structFieldWriteEffectStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (fun stateId fieldName => lowerStructFieldSlotExpr module stateId fieldName)
            (fun stateId indexPlan fieldName => do
              let (slot, length, fieldCount, fieldOffset, _) ← requireStructArrayStateField module stateId fieldName
              .ok (ProofForge.Backend.Evm.ToYul.helperCall ProofForge.Backend.Evm.Plan.Helper.structArraySlot #[
                slotExpr slot,
                Lean.Compiler.Yul.Expr.num length,
                Lean.Compiler.Yul.Expr.num fieldCount,
                Lean.Compiler.Yul.Expr.num fieldOffset,
                ← lowerExprPlanExpr module env indexPlan
              ]))
            (.effect effect)
  | .storagePathWriteTarget .. =>
      ProofForge.Backend.Evm.ToYul.storagePathWriteTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (.effect effect)
  | .storagePathWriteExprTarget .. =>
      ProofForge.Backend.Evm.ToYul.storagePathWriteExprTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (lowerExprPlanExpr module env)
        (.effect effect)
  | .storagePathAssignOpTarget .. =>
      ProofForge.Backend.Evm.ToYul.storagePathAssignOpTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (.effect effect)
  | .storagePathAssignOpExprTarget .. =>
      ProofForge.Backend.Evm.ToYul.storagePathAssignOpExprTargetEffectStmtPlanStatements
        toYulError
        (fun expr => lowerExpr module env expr)
        (lowerPlanEffectExpr module env)
        (lowerExprPlanExpr module env)
        (.effect effect)
  | .eventEmit .. | .eventEmitIndexed .. | .eventEmitWords .. | .eventEmitIndexedWords .. =>
      lowerPlannedBodyEventEffectPlan module env effect
  | _ =>
      .error { message := "planned scalar control-flow body expected a supported effect" }

def lowerAggregateReturnStmtPlan
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ProofForge.Backend.Evm.Plan.ExprPlan)
    (leaveAfterReturn : Bool) :
    Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let crosscallPlan? ←
    match ProofForge.Backend.Evm.Lower.aggregateCrosscallReturnAssignmentPlanFromExprPlan?
        module
        entrypointName
        returnType
        value with
    | .ok plan? => .ok plan?
    | .error err => .error { message := err.message }
  let statements ←
    match crosscallPlan? with
    | some plan => .ok #[← lowerCrosscallReturnAssignmentPlan module env plan]
    | none => do
        let plan ←
          match ProofForge.Backend.Evm.Lower.returnValueWordPlanFromExprPlan
              module
              (toValidateTypeEnv env)
              entrypointName
              returnType
              value with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        lowerReturnValueWordPlan module env entrypointName plan
  .ok <| if leaveAfterReturn then statements.push .leave else statements

mutual
  partial def lowerPlannedBodyStatements
      (module : Module)
      (entrypointName : String)
      (returnType : ValueType)
      (env : TypeEnv)
      (leaveAfterReturn : Bool)
      (plans : Array ProofForge.Backend.Evm.Plan.StmtPlan) :
      Except LowerError (Array Lean.Compiler.Yul.Statement × TypeEnv) := do
    ProofForge.Backend.Evm.ToYul.stmtPlanBodyStatements
      plans
      env
      leaveAfterReturn
      (fun currentEnv stmtLeaveAfterReturn plan =>
        lowerPlannedBodyStatement
          module
          entrypointName
          returnType
          currentEnv
          stmtLeaveAfterReturn
          plan)

  partial def lowerPlannedBodyStatement
      (module : Module)
      (entrypointName : String)
      (returnType : ValueType)
      (env : TypeEnv)
      (leaveAfterReturn : Bool) :
      ProofForge.Backend.Evm.Plan.StmtPlan →
      Except LowerError (Array Lean.Compiler.Yul.Statement × TypeEnv)
    | .letBind name type value => do
        ensureLocalScalarType "planned scalar let binding" name type
        let statements ←
          ProofForge.Backend.Evm.ToYul.scalarBindingStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (.letBind name type value)
        let nextEnv ← addLocal env name type false
        .ok (statements, nextEnv)
    | .letMutBind name type value => do
        ensureLocalScalarType "planned scalar mutable let binding" name type
        let statements ←
          ProofForge.Backend.Evm.ToYul.scalarBindingStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (.letMutBind name type value)
        let nextEnv ← addLocal env name type true
        .ok (statements, nextEnv)
    | .assign target value => do
        let statements ←
          ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (.assign target value)
        .ok (statements, env)
    | .assignOp target op value => do
        let statements ←
          ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (.assignOp target op value)
        .ok (statements, env)
    | .effect effect => do
        .ok (← lowerPlannedBodyEffectPlan module env effect, env)
    | .assert condition message errorRef? => do
        let statements ←
          ProofForge.Backend.Evm.ToYul.scalarAssertStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (fun
              | none => #[revertStmt]
              | some ref => errorRefRevertStmts ref)
            (.assert condition message errorRef?)
        .ok (statements, env)
    | .assertEq lhs rhs message errorRef? => do
        let statements ←
          ProofForge.Backend.Evm.ToYul.scalarAssertStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            (fun
              | none => #[revertStmt]
              | some ref => errorRefRevertStmts ref)
            (.assertEq lhs rhs message errorRef?)
        .ok (statements, env)
    | .release _ =>
        .error { message := "planned body lowering does not support release statements" }
    | .revert message => do
        let statements ←
          ProofForge.Backend.Evm.ToYul.revertStmtPlanStatements
            toYulError
            errorRefRevertStmts
            (.revert message)
        .ok (statements, env)
    | .revertWithError errorRef => do
        let statements ←
          ProofForge.Backend.Evm.ToYul.revertStmtPlanStatements
            toYulError
            errorRefRevertStmts
            (.revertWithError errorRef)
        .ok (statements, env)
    | .ifElse condition thenBody elseBody => do
        let (thenStatements, _) ←
          lowerPlannedBodyStatements module entrypointName returnType env true thenBody
        let (elseStatements, _) ←
          lowerPlannedBodyStatements module entrypointName returnType env true elseBody
        let statements ←
          ProofForge.Backend.Evm.ToYul.ifElseStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module env expr)
            (lowerPlanEffectExpr module env)
            thenStatements
            elseStatements
            (.ifElse condition thenBody elseBody)
        .ok (statements, env)
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let loopEnv ← addLocal env indexName .u32 false
        let (bodyStatements, _) ←
          lowerPlannedBodyStatements module entrypointName returnType loopEnv true body
        let statements ←
          ProofForge.Backend.Evm.ToYul.boundedForStmtPlanStatements
            toYulError
            (fun expr => lowerExpr module loopEnv expr)
            (lowerPlanEffectExpr module loopEnv)
            bodyStatements
            (.boundedFor indexName start stopExclusive body)
        .ok (statements, env)
    | .return value => do
        let statements ←
          if returnTypeSupportsDynamicStmtPlan returnType then
            let returns ←
              match ProofForge.Backend.Evm.Lower.returnPlan module s!"entrypoint `{entrypointName}`" returnType with
              | .ok plan => .ok plan
              | .error err => .error { message := err.message }
            ProofForge.Backend.Evm.ToYul.dynamicReturnStmtPlanStatements
              toYulError
              returns
              leaveAfterReturn
              (.return value)
          else if returnTypeSupportsAggregateStmtPlan returnType then
            lowerAggregateReturnStmtPlan
              module
              env
              entrypointName
              returnType
              value
              leaveAfterReturn
          else
            ProofForge.Backend.Evm.ToYul.scalarReturnExprPlanStatements
              toYulError
              (lowerExprPlanExpr module env)
              (← abiReturnNames module entrypointName returnType)
              leaveAfterReturn
              (.return value)
        .ok (statements, env)
end

mutual
  partial def lowerStatements
      (module : Module)
      (entrypointName : String)
      (returnType : ValueType)
      (env : TypeEnv)
      (leaveAfterReturn : Bool)
      (statements : Array Statement) : Except LowerError (Array Lean.Compiler.Yul.Statement) :=
    do
      let mut statementsAcc : Array Lean.Compiler.Yul.Statement := #[]
      let mut currentEnv := env
      for h : idx in [0:statements.size] do
        let stmtLeaveAfterReturn := leaveAfterReturn || decide (idx + 1 < statements.size)
        let (lowered, nextEnv) ← lowerStatement module entrypointName returnType currentEnv stmtLeaveAfterReturn statements[idx]
        statementsAcc := statementsAcc ++ lowered
        currentEnv := nextEnv
      .ok statementsAcc

  partial def lowerStatement
      (module : Module)
      (entrypointName : String)
      (returnType : ValueType)
      (env : TypeEnv)
      (leaveAfterReturn : Bool) : ProofForge.IR.Statement → Except LowerError (Array Lean.Compiler.Yul.Statement × TypeEnv)
    | .letBind name (.fixedArray elementType length) value => do
        let lowered ← lowerFixedArrayLetBinding module env name elementType length value
        let nextEnv ← addLocal env name (.fixedArray elementType length) false
        .ok (lowered, nextEnv)
    | .letBind name (.structType typeName) value => do
        let lowered ← lowerStructLetBinding module env name typeName value
        let nextEnv ← addLocal env name (.structType typeName) false
        .ok (lowered, nextEnv)
    | .letBind name (.array elementType) value => do
        let lowered ← lowerExpr module env value
        let nextEnv ← addLocal env name (.array elementType) false
        .ok (#[Lean.Compiler.Yul.Statement.varDecl #[{ name := name }] (some lowered)], nextEnv)
    | .letBind name type value => do
        ensureLocalScalarType "let binding" name type
        let nextEnv ← addLocal env name type false
        .ok (← lowerScalarBindingStmtPlan module env name type false value, nextEnv)
    | .letMutBind name (.fixedArray elementType length) value => do
        let lowered ← lowerFixedArrayLetBinding module env name elementType length value
        let nextEnv ← addLocal env name (.fixedArray elementType length) true
        .ok (lowered, nextEnv)
    | .letMutBind name (.structType typeName) value => do
        let lowered ← lowerStructLetBinding module env name typeName value
        let nextEnv ← addLocal env name (.structType typeName) true
        .ok (lowered, nextEnv)
    | .letMutBind name (.array elementType) value => do
        let lowered ← lowerExpr module env value
        let nextEnv ← addLocal env name (.array elementType) true
        .ok (#[Lean.Compiler.Yul.Statement.varDecl #[{ name := name }] (some lowered)], nextEnv)
    | .letMutBind name type value => do
        ensureLocalScalarType "mutable let binding" name type
        let nextEnv ← addLocal env name type true
        .ok (← lowerScalarBindingStmtPlan module env name type true value, nextEnv)
    | .assign target value => do
        .ok (← lowerAssignStmt module env target value, env)
    | .assignOp target op value => do
        .ok (← lowerAssignOpStmt module env target op value, env)
    | .effect effect => do
        .ok (#[← lowerEffectStmt module env effect], env)
    | .assert condition message errorRef? => do
        .ok (← lowerScalarAssertStmtPlan module env (.assert condition message errorRef?), env)
    | .assertEq lhs rhs message errorRef? => do
        .ok (← lowerScalarAssertStmtPlan module env (.assertEq lhs rhs message errorRef?), env)
    | .release _ =>
        .error { message := "release statements are not supported by IR EVM v0" }
    | .revert message => do
        let statements ←
          ProofForge.Backend.Evm.ToYul.revertStmtPlanStatements
            toYulError
            errorRefRevertStmts
            (.revert message)
        .ok (statements, env)
    | .revertWithError errorRef => do
        let statements ←
          ProofForge.Backend.Evm.ToYul.revertStmtPlanStatements
            toYulError
            errorRefRevertStmts
            (.revertWithError errorRef)
        .ok (statements, env)
    | .ifElse condition thenBody elseBody => do
        let fallback : Except LowerError (Array Lean.Compiler.Yul.Statement × TypeEnv) := do
          let thenStatements ← lowerStatements module entrypointName returnType env true thenBody
          let elseStatements ← lowerStatements module entrypointName returnType env true elseBody
          let conditionPlan ←
            match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) condition with
            | .ok plan => .ok plan
            | .error err => .error { message := err.message }
          let statements ←
            ProofForge.Backend.Evm.ToYul.ifElseStmtPlanStatements
              toYulError
              (fun expr => lowerExpr module env expr)
              (lowerPlanEffectExpr module env)
              thenStatements
              elseStatements
              (.ifElse conditionPlan #[] #[])
          .ok (statements, env)
        match ← plannedBodyStatement? module entrypointName returnType env (.ifElse condition thenBody elseBody) with
        | some plan =>
            match lowerPlannedBodyStatement module entrypointName returnType env leaveAfterReturn plan with
            | .ok lowered => .ok lowered
            | .error _ => fallback
        | none =>
            fallback
    | .boundedFor indexName start stopExclusive body => do
        let fallback : Except LowerError (Array Lean.Compiler.Yul.Statement × TypeEnv) := do
          if stopExclusive <= start then
            .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
          let loopEnv ← addLocal env indexName .u32 false
          let bodyStatements ← lowerStatements module entrypointName returnType loopEnv true body
          let statements ←
            ProofForge.Backend.Evm.ToYul.boundedForStmtPlanStatements
              toYulError
              (fun expr => lowerExpr module loopEnv expr)
              (lowerPlanEffectExpr module loopEnv)
              bodyStatements
              (.boundedFor indexName start stopExclusive #[])
          .ok (statements, env)
        match ← plannedBodyStatement? module entrypointName returnType env (.boundedFor indexName start stopExclusive body) with
        | some plan =>
            match lowerPlannedBodyStatement module entrypointName returnType env leaveAfterReturn plan with
            | .ok lowered => .ok lowered
            | .error _ => fallback
        | none =>
            fallback
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by EVM IR v0; use boundedFor" }
    | .return value => do
        .ok (← lowerReturnStmt module env entrypointName returnType value leaveAfterReturn, env)
end

def lowerEntrypointBodyWithPlan?
    (module : Module)
    (entrypoint : Entrypoint)
    (entrypointPlan : ProofForge.Backend.Evm.Plan.EntrypointPlan) :
    Except LowerError (Option (Array Lean.Compiler.Yul.Statement)) := do
  if entrypointPlan.body.isEmpty && !entrypoint.body.isEmpty then
    .ok none
  else if stmtPlansSupportPlannedBody entrypoint.returns entrypointPlan.body then
    match lowerPlannedBodyStatements
        module
        entrypoint.name
        entrypoint.returns
        (entrypointTypeEnv entrypoint)
        false
        entrypointPlan.body with
    | .ok (body, _) => .ok (some body)
    | .error _ => .ok none
  else
    .ok none

end ProofForge.Backend.Evm.IR
