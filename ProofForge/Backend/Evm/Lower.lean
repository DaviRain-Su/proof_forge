import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Lower.Body
import ProofForge.Backend.Evm.Lower.Requirements
import ProofForge.Backend.Evm.Validate
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

/-! # EVM semantic plan lowering (IR -> ModulePlan)

This module is the `Lower` pass from RFC 0004. It consumes a portable IR
`Module` together with the pure validation/type-inference from `Validate.lean`
and produces a fully populated `Plan.ModulePlan` with:

- `EntrypointPlan` nodes (selector, ABI params, return plan, body)
- `EventPlan` nodes (signature, indexed/data field layout)
- `CrosscallHelperSpec` and `CreateHelperSpec` discovered from the IR
- Local-array-get and nested-local-array-get helper requirements
- The checked-arithmetic flag
- A `MetadataPlan` summarizing the module for artifact/deploy metadata

The plan is then consumed by `ToYul.lean` (helper emission) and `IR.lean`
(Yul AST construction). Keeping plan construction separate from Yul AST
construction is the core architectural goal of RFC 0004. -/

namespace ProofForge.Backend.Evm.Lower

open ProofForge.IR
open ProofForge.Target
open ProofForge.Backend.Evm.Plan
open ProofForge.Backend.Evm.Validate

/-! ## Assignment source and full module plan assembly -/

def fixedArrayAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (elementType : ValueType)
    (length : Nat)
    (value : Expr) : Except LowerError (Array FixedArrayAssignmentSourcePlan) := do
  match value with
  | .local sourceName => do
      let (sourceElementType, sourceLength) ← requireLocalFixedArray "assignment value" env sourceName
      ensureType s!"assignment target `{name}` fixed-array element type" elementType sourceElementType
      if sourceLength != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {sourceLength}" }
      let mut sources : Array FixedArrayAssignmentSourcePlan := #[]
      for _h : idx in [0:length] do
        sources := sources.push {
          index := idx
          expr := .local (arrayLocalElementName sourceName idx)
        }
      .ok sources
  | .arrayLit literalElementType literalValues => do
      ensureType s!"assignment target `{name}` fixed-array element type" elementType literalElementType
      if literalValues.size != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {literalValues.size}" }
      let mut sources : Array FixedArrayAssignmentSourcePlan := #[]
      for h : idx in [0:literalValues.size] do
        sources := sources.push {
          index := idx
          expr := ← buildExprPlan module env literalValues[idx]
        }
      .ok sources
  | _ =>
      .error { message := s!"assignment target `{name}` fixed-array whole assignment supports local fixed-array values or array literals in IR EVM v0" }

partial def nestedFixedArrayValueFieldPlans
    (module : Module)
    (env : TypeEnv)
    (context typeName : String)
    (value : Expr) : Except LowerError (Array (String × ExprPlan)) := do
  let decl ← ensureLocalFlatStructType module context typeName
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType context (.structType typeName) binding.type
      let mut fields : Array (String × ExprPlan) := #[]
      for fieldDecl in decl.fields do
        fields := fields.push (fieldDecl.id, .local (structLocalFieldName sourceName fieldDecl.id))
      .ok fields
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"{context} expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut fieldPlans : Array (String × ExprPlan) := #[]
      for fieldDecl in decl.fields do
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        fieldPlans := fieldPlans.push (fieldDecl.id, ← buildExprPlan module env field.snd)
      .ok fieldPlans
  | .effect (.storageScalarRead stateId) => do
      let (slot, stateTypeName, _) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireStructState module stateId
      ensureType context (.structType typeName) (.structType stateTypeName)
      let mut fieldPlans : Array (String × ExprPlan) := #[]
      for h : idx in [0:decl.fields.size] do
        let fieldDecl := decl.fields[idx]
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        fieldPlans := fieldPlans.push (fieldDecl.id, .storageLoad (.scalarSlot (slot + idx)))
      .ok fieldPlans
  | _ =>
      .error {
        message := s!"{context} supports local struct values, struct literals, or storage scalar struct reads in IR EVM v0"
      }

partial def nestedFixedArrayLocalSourcePlansAt
    (module : Module)
    (sourceName : String)
    (path : Array Nat) : ValueType → Except LowerError (Array NestedFixedArrayAssignmentSourcePlan)
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      let localName :=
        if path.isEmpty then
          sourceName
        else
          arrayLocalPathName sourceName path
      .ok #[{ path := path, fieldName? := none, expr := .local localName }]
  | .structType typeName => do
      let decl ← ensureLocalFlatStructType module s!"assignment value `{sourceName}` nested fixed-array leaf" typeName
      let mut sources : Array NestedFixedArrayAssignmentSourcePlan := #[]
      for fieldDecl in decl.fields do
        let fieldName :=
          if path.isEmpty then
            structLocalFieldName sourceName fieldDecl.id
          else
            arrayStructLocalPathFieldName sourceName path fieldDecl.id
        sources := sources.push {
          path := path,
          fieldName? := some fieldDecl.id,
          expr := .local fieldName
        }
      .ok sources
  | .fixedArray elementType length => do
      ensureLocalNestedFixedArrayValueType module "assignment value" sourceName elementType
      let mut sources : Array NestedFixedArrayAssignmentSourcePlan := #[]
      for _h : idx in [0:length] do
        sources := sources ++ (← nestedFixedArrayLocalSourcePlansAt module sourceName (path.push idx) elementType)
      .ok sources
  | .unit | .bytes | .string | .array _ =>
      .error {
        message := s!"assignment value `{sourceName}` has unsupported EVM IR v0 nested fixed-array leaf type `Unit`; nested local fixed arrays support U32, U64, Bool, Hash, Address, or flat struct leaves"
      }

partial def nestedFixedArrayLiteralSourcePlansAt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (path : Array Nat)
    (expectedType : ValueType)
    (value : Expr) : Except LowerError (Array NestedFixedArrayAssignmentSourcePlan) := do
  match expectedType with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      .ok #[{ path := path, fieldName? := none, expr := ← buildExprPlan module env value }]
  | .structType typeName => do
      let fields ←
        nestedFixedArrayValueFieldPlans
          module
          env
          s!"assignment target `{name}` nested fixed-array leaf"
          typeName
          value
      let mut sources : Array NestedFixedArrayAssignmentSourcePlan := #[]
      for field in fields do
        sources := sources.push {
          path := path,
          fieldName? := some field.fst,
          expr := field.snd
        }
      .ok sources
  | .fixedArray elementType length => do
      ensureLocalNestedFixedArrayValueType module "assignment target" name elementType
      match value with
      | .arrayLit literalElementType values => do
          ensureType s!"assignment target `{name}` fixed-array element type" elementType literalElementType
          if values.size != length then
            .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {values.size}" }
          let mut sources : Array NestedFixedArrayAssignmentSourcePlan := #[]
          for h : idx in [0:values.size] do
            sources := sources ++
              (← nestedFixedArrayLiteralSourcePlansAt module env name (path.push idx) elementType values[idx])
          .ok sources
      | _ =>
          .error {
            message := s!"assignment target `{name}` fixed-array whole assignment supports local fixed-array values or array literals in IR EVM v0"
          }
  | .unit | .bytes | .string | .array _ =>
      .error {
        message := s!"assignment target `{name}` has unsupported EVM IR v0 nested fixed-array leaf type `{expectedType.name}`; nested local fixed arrays support U32, U64, Bool, Hash, Address, or flat struct leaves"
      }

def nestedFixedArrayAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (expectedType : ValueType)
    (value : Expr) : Except LowerError (Array NestedFixedArrayAssignmentSourcePlan) := do
  ensureLocalNestedFixedArrayValueType module "assignment target" name expectedType
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType s!"assignment target `{name}` fixed-array type" expectedType binding.type
      nestedFixedArrayLocalSourcePlansAt module sourceName #[] expectedType
  | .arrayLit _ _ =>
      nestedFixedArrayLiteralSourcePlansAt module env name #[] expectedType value
  | _ =>
      .error {
        message := s!"assignment target `{name}` fixed-array whole assignment supports local fixed-array values or array literals in IR EVM v0"
      }

def structArrayAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (length : Nat)
    (value : Expr) : Except LowerError (Array StructArrayAssignmentSourcePlan) := do
  let decl ← ensureLocalFlatStructType module s!"assignment target `{name}` fixed-array element" typeName
  match value with
  | .local sourceName => do
      let (sourceElementType, sourceLength) ← requireLocalFixedArray "assignment value" env sourceName
      ensureType s!"assignment target `{name}` fixed-array element type" (.structType typeName) sourceElementType
      if sourceLength != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {sourceLength}" }
      let mut sources : Array StructArrayAssignmentSourcePlan := #[]
      for _h : idx in [0:length] do
        for fieldDecl in decl.fields do
          sources := sources.push {
            index := idx,
            fieldName := fieldDecl.id,
            expr := .local (arrayStructLocalFieldName sourceName idx fieldDecl.id)
          }
      .ok sources
  | .arrayLit literalElementType literalValues => do
      ensureType s!"assignment target `{name}` fixed-array element type" (.structType typeName) literalElementType
      if literalValues.size != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {literalValues.size}" }
      let mut sources : Array StructArrayAssignmentSourcePlan := #[]
      for h : idx in [0:literalValues.size] do
        match literalValues[idx] with
        | .structLit literalTypeName fields => do
            if literalTypeName != typeName then
              .error { message := s!"assignment target `{name}` expected struct `{typeName}`, got `{literalTypeName}`" }
            for fieldDecl in decl.fields do
              let some field := fields.find? fun field => field.fst == fieldDecl.id
                | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
              sources := sources.push {
                index := idx,
                fieldName := fieldDecl.id,
                expr := ← buildExprPlan module env field.snd
              }
        | other =>
            let actualType ← inferExprType module env other
            .error {
              message := s!"assignment target `{name}` fixed-array element {idx} expected struct literal `{typeName}`, got `{actualType.name}`"
            }
      .ok sources
  | _ =>
      .error {
        message := s!"assignment target `{name}` struct-array whole assignment supports local fixed-array values or array literals in IR EVM v0"
      }

def structAssignmentSourcePlans
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (value : Expr) : Except LowerError (Array StructAssignmentSourcePlan) := do
  let decl ← ensureLocalFlatStructType module s!"assignment target `{name}` struct type" typeName
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType s!"assignment target `{name}` struct type" (.structType typeName) binding.type
      let mut sources : Array StructAssignmentSourcePlan := #[]
      for fieldDecl in decl.fields do
        sources := sources.push {
          fieldName := fieldDecl.id
          expr := .local (structLocalFieldName sourceName fieldDecl.id)
        }
      .ok sources
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"assignment target `{name}` expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut sources : Array StructAssignmentSourcePlan := #[]
      for fieldDecl in decl.fields do
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        sources := sources.push {
          fieldName := fieldDecl.id
          expr := ← buildExprPlan module env field.snd
        }
      .ok sources
  | .effect (.storageScalarRead stateId) => do
      let (slot, stateTypeName, _) ← lowerPlan <| ProofForge.Backend.Evm.Plan.requireStructState module stateId
      ensureType s!"assignment target `{name}` struct type" (.structType typeName) (.structType stateTypeName)
      let mut sources : Array StructAssignmentSourcePlan := #[]
      for h : idx in [0:decl.fields.size] do
        let fieldDecl := decl.fields[idx]
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        sources := sources.push {
          fieldName := fieldDecl.id
          expr := .storageLoad (.scalarSlot (slot + idx))
        }
      .ok sources
  | _ =>
      .error { message := s!"assignment target `{name}` struct whole assignment supports local struct values, struct literals, or storage scalar struct reads in IR EVM v0" }

def storageStructWriteFieldPlans
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (value : ExprPlan) : Except LowerError (Array StorageStructWriteFieldPlan) := do
  let (slot, typeName, decl) ← requireStructState module stateId
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType s!"storage scalar struct write `{stateId}` source type" (.structType typeName) binding.type
      let mut fields : Array StorageStructWriteFieldPlan := #[]
      for h : idx in [0:decl.fields.size] do
        let fieldDecl := decl.fields[idx]
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        fields := fields.push {
          slot := slot + idx
          fieldName := fieldDecl.id
          value := .local (structLocalFieldName sourceName fieldDecl.id)
        }
      .ok fields
  | .structLit literalTypeName sourceFields => do
      if literalTypeName != typeName then
        .error { message := s!"storage scalar struct write `{stateId}` expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut fields : Array StorageStructWriteFieldPlan := #[]
      for h : idx in [0:decl.fields.size] do
        let fieldDecl := decl.fields[idx]
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        let some field := sourceFields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        fields := fields.push {
          slot := slot + idx
          fieldName := fieldDecl.id
          value := field.snd
        }
      .ok fields
  | .effect (.storageScalarRead sourceStateId) => do
      let (sourceSlot, sourceTypeName, sourceDecl) ← requireStructState module sourceStateId
      ensureType
        s!"storage scalar struct write `{stateId}` source type"
        (.structType typeName)
        (.structType sourceTypeName)
      let mut fields : Array StorageStructWriteFieldPlan := #[]
      for h : idx in [0:sourceDecl.fields.size] do
        let fieldDecl := sourceDecl.fields[idx]
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        fields := fields.push {
          slot := slot + idx
          fieldName := fieldDecl.id
          value := .storageLoad (.scalarSlot (sourceSlot + idx))
        }
      .ok fields
  | _ =>
      .error {
        message := s!"storage scalar struct write `{stateId}` supports local struct values, struct literals, or storage scalar struct reads in IR EVM v0"
      }

def crosscallModeArgContext : CrosscallMode → String
  | .call => "typed crosscall argument"
  | .callValue => "value crosscall argument"
  | .staticcall => "static crosscall argument"
  | .delegatecall => "delegate crosscall argument"

def buildCrosscallReturnAssignmentPlan
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (mode : CrosscallMode)
    (target methodId : Expr)
    (callValue? : Option Expr)
    (args : Array Expr)
    (callReturnType : ValueType) :
    Except LowerError CrosscallReturnAssignmentPlan := do
  ensureType s!"entrypoint `{entrypointName}` aggregate crosscall return type" returnType callReturnType
  let returns ← crosscallReturnPlan module s!"entrypoint `{entrypointName}` return value" returnType
  .ok {
    returns
    mode
    target := ← buildExprPlan module env target
    methodId := ← buildExprPlan module env methodId
    callValue? := ← callValue?.mapM (buildExprPlan module env)
    args := ← buildCrosscallArgWordPlansMany module env (crosscallModeArgContext mode) args
  }

def aggregateCrosscallReturnAssignmentPlan?
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : Expr) :
    Except LowerError (Option CrosscallReturnAssignmentPlan) := do
  if isCrosscallWordType returnType then
    .ok none
  else
    match value with
    | .crosscallInvokeTyped target methodId args callReturnType => do
        let plan ← buildCrosscallReturnAssignmentPlan
          module env entrypointName returnType .call target methodId none args callReturnType
        .ok (some plan)
    | .crosscallInvokeValueTyped target methodId callValue args callReturnType => do
        let plan ← buildCrosscallReturnAssignmentPlan
          module env entrypointName returnType .callValue target methodId (some callValue) args callReturnType
        .ok (some plan)
    | .crosscallInvokeStaticTyped target methodId args callReturnType => do
        let plan ← buildCrosscallReturnAssignmentPlan
          module env entrypointName returnType .staticcall target methodId none args callReturnType
        .ok (some plan)
    | .crosscallInvokeDelegateTyped target methodId args callReturnType => do
        let plan ← buildCrosscallReturnAssignmentPlan
          module env entrypointName returnType .delegatecall target methodId none args callReturnType
        .ok (some plan)
    | _ => .ok none

def aggregateCrosscallReturnAssignmentPlanFromExprPlan?
    (module : Module)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ExprPlan) :
    Except LowerError (Option CrosscallReturnAssignmentPlan) := do
  match returnType with
  | .fixedArray _ _ | .structType _ =>
      match value with
      | .crosscall mode target methodId callValue? args callReturnType => do
          ensureType s!"entrypoint `{entrypointName}` aggregate crosscall return type"
            returnType
            callReturnType
          let returns ← crosscallReturnPlan module s!"entrypoint `{entrypointName}` return value" returnType
          .ok (some {
            returns
            mode
            target
            methodId
            callValue?
            args
          })
      | _ => .ok none
  | .unit | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .bytes | .string | .array _ =>
      .ok none

def returnValueWordPlan?
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : Expr) :
    Except LowerError (Option ReturnValueWordPlan) := do
  let context := s!"entrypoint `{entrypointName}` return value"
  let returns ← returnPlan module s!"entrypoint `{entrypointName}`" returnType
  match returnType, value with
  | .fixedArray _ _, _
  | .structType _, _ => do
      .ok (some {
        returns
        source := ← buildAbiValuePlan module env context returnType value
      })
  | _, _ =>
      .ok none

def buildEntrypointBodyPlan (module : Module) (entrypoint : Entrypoint) :
    Except LowerError (Array StmtPlan) := do
  validateEntrypointTypes module entrypoint
  let (body, _) ← buildStatementPlans module entrypoint (entrypointTypeEnv entrypoint) entrypoint.body
  .ok body

def buildEntrypointPlan (module : Module) (entrypoint : Entrypoint) :
    Except LowerError EntrypointPlan := do
  let selector ← entrypointSelector entrypoint
  let params ← entrypointParamPlans module entrypoint
  let returns ← returnPlan module s!"entrypoint `{entrypoint.name}`" entrypoint.returns
  let body ← buildEntrypointBodyPlan module entrypoint
  .ok { name := entrypoint.name, selector, params, returns, body }

def buildEntrypointSurfacePlan (module : Module) (entrypoint : Entrypoint) :
    Except LowerError EntrypointPlan := do
  let selector ← entrypointSelector entrypoint
  let params ← entrypointParamPlans module entrypoint
  let returns ← returnPlan module s!"entrypoint `{entrypoint.name}`" entrypoint.returns
  .ok { name := entrypoint.name, selector, params, returns, body := #[] }

def buildEntrypointPlans (module : Module) : Except LowerError (Array EntrypointPlan) :=
  module.entrypoints.foldlM (init := #[]) fun acc entrypoint => do
    .ok (acc.push (← buildEntrypointPlan module entrypoint))

/-! ## Event plan construction

Event plans are built by walking each entrypoint's body with a growing type
environment (params + let-bound locals), matching the same pattern used by
`Cli.lean` for event ABI extraction. This ensures event field expressions can
reference locals bound earlier in the same entrypoint. -/

structure EventCollector where
  plans : Array EventPlan := #[]
  deriving Repr

def EventCollector.find (collector : EventCollector) (name : String) : Option EventPlan :=
  collector.plans.find? (fun plan => plan.name == name)

def EventCollector.add (collector : EventCollector) (plan : EventPlan) : EventCollector :=
  match collector.find plan.name with
  | some _ => collector
  | none => { plans := collector.plans.push plan }

mutual
  partial def collectEventPlansFromExpr
      (module : Module)
      (env : TypeEnv)
      (collector : EventCollector) :
      Expr → Except LowerError EventCollector
    | .literal _ | .local _ | .nativeValue => pure collector
    | .arrayLit _ values =>
        values.foldlM (init := collector) (collectEventPlansFromExpr module env)
    | .arrayGet array index => do
        let collector ← collectEventPlansFromExpr module env collector array
        collectEventPlansFromExpr module env collector index
    | .memoryArrayNew _ length =>
        collectEventPlansFromExpr module env collector length
    | .memoryArrayLength array =>
        collectEventPlansFromExpr module env collector array
    | .memoryArrayGet array index => do
        let collector ← collectEventPlansFromExpr module env collector array
        collectEventPlansFromExpr module env collector index
    | .structLit _ fields =>
        fields.foldlM (init := collector) fun acc field =>
          collectEventPlansFromExpr module env acc field.snd
    | .field base _ => collectEventPlansFromExpr module env collector base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs => do
        let collector ← collectEventPlansFromExpr module env collector lhs
        collectEventPlansFromExpr module env collector rhs
    | .cast value _ | .boolNot value | .hash value =>
        collectEventPlansFromExpr module env collector value
    | .hashValue a b c d => do
        let collector ← collectEventPlansFromExpr module env collector a
        let collector ← collectEventPlansFromExpr module env collector b
        let collector ← collectEventPlansFromExpr module env collector c
        collectEventPlansFromExpr module env collector d
    | .crosscallInvoke _ _ _ | .crosscallInvokeTyped _ _ _ _ | .crosscallInvokeValueTyped _ _ _ _ _
    | .crosscallInvokeStaticTyped _ _ _ _ | .crosscallInvokeDelegateTyped _ _ _ _ => pure collector
    | .crosscallCreate _ _ | .crosscallCreate2 _ _ _ => pure collector
    | .nearPromiseThen _ _ _ _ | .nearCrosscallInvokePool _ _ _ _ | .nearPromiseResultsCount | .nearPromiseResultStatus _ | .nearPromiseResultU64 _ => pure collector
    | .effect effect => collectEventPlansFromEffect module env collector effect

  partial def collectEventPlansFromEffect
      (module : Module)
      (env : TypeEnv)
      (collector : EventCollector) :
      Effect → Except LowerError EventCollector
    | .storageScalarRead _ => pure collector
    | .storageScalarWrite _ value | .storageScalarAssignOp _ _ value =>
        collectEventPlansFromExpr module env collector value
    | .storageMapContains _ key | .storageMapGet _ key =>
        collectEventPlansFromExpr module env collector key
    | .storageMapInsert _ key value | .storageMapSet _ key value => do
        let collector ← collectEventPlansFromExpr module env collector key
        collectEventPlansFromExpr module env collector value
    | .storageArrayRead _ index => collectEventPlansFromExpr module env collector index
    | .storageArrayWrite _ index value | .storageArrayStructFieldWrite _ index _ value => do
        let collector ← collectEventPlansFromExpr module env collector index
        collectEventPlansFromExpr module env collector value
    | .storageArrayStructFieldRead _ index _ => collectEventPlansFromExpr module env collector index
    | .storageDynamicArrayPush _ value => collectEventPlansFromExpr module env collector value
    | .storageDynamicArrayPop _ => pure collector
    | .memoryArraySet array index value => do
        let collector ← collectEventPlansFromExpr module env collector array
        let collector ← collectEventPlansFromExpr module env collector index
        collectEventPlansFromExpr module env collector value
    | .storageStructFieldRead _ _ => pure collector
    | .storageStructFieldWrite _ _ value => collectEventPlansFromExpr module env collector value
    | .storagePathRead _ path =>
        path.foldlM (init := collector) fun acc segment =>
          match segment with
          | .mapKey key => collectEventPlansFromExpr module env acc key
          | .index index => collectEventPlansFromExpr module env acc index
          | .field _ => pure acc
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value => do
        let collector ← path.foldlM (init := collector) fun acc segment =>
          match segment with
          | .mapKey key => collectEventPlansFromExpr module env acc key
          | .index index => collectEventPlansFromExpr module env acc index
          | .field _ => pure acc
        collectEventPlansFromExpr module env collector value
    | .contextRead _ => pure collector
    | .eventEmit name fields => do
        let signature ← eventSignature module env name fields
        let mut fieldPlans : Array EventFieldPlan := #[]
        for field in fields do
          let fieldType ← inferEventFieldExprType module env field.snd
          fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType false)
        pure (collector.add (EventPlan.mk name signature fieldPlans))
    | .eventEmitIndexed name indexedFields dataFields => do
        validateIndexedEventFieldCount name indexedFields.size
        let mut fieldPlans : Array EventFieldPlan := #[]
        for field in indexedFields do
          let fieldType ← inferEventFieldExprType module env field.snd
          fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType true)
        for field in dataFields do
          let fieldType ← inferEventFieldExprType module env field.snd
          fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType false)
        let signature ← eventSignature module env name (indexedFields ++ dataFields)
        pure (collector.add (EventPlan.mk name signature fieldPlans))

  partial def collectEventPlansFromStatements
      (module : Module)
      (env : TypeEnv)
      (collector : EventCollector) :
      Array Statement → Except LowerError EventCollector
    | #[] => pure collector
    | statements => do
      let mut current := env
      let mut acc := collector
      for stmt in statements do
        match stmt with
        | .letBind name type value => do
            ensureType s!"let binding `{name}`" type (← inferExprType module current value)
            current ← addLocal current name type false
            acc ← collectEventPlansFromExpr module current acc value
        | .letMutBind name type value => do
            ensureType s!"mutable let binding `{name}`" type (← inferExprType module current value)
            current ← addLocal current name type true
            acc ← collectEventPlansFromExpr module current acc value
        | .assign target value | .assignOp target _ value => do
            acc ← collectEventPlansFromExpr module current acc target
            acc ← collectEventPlansFromExpr module current acc value
        | .effect effect => do
            acc ← collectEventPlansFromEffect module current acc effect
        | .assert condition _ _ => do
            acc ← collectEventPlansFromExpr module current acc condition
        | .assertEq lhs rhs _ _ => do
            acc ← collectEventPlansFromExpr module current acc lhs
            acc ← collectEventPlansFromExpr module current acc rhs
        | .release _ | .revert _ | .revertWithError _ => pure ()
        | .ifElse condition thenBody elseBody => do
            acc ← collectEventPlansFromExpr module current acc condition
            acc ← collectEventPlansFromStatements module current acc thenBody
            acc ← collectEventPlansFromStatements module current acc elseBody
        | .boundedFor indexName _ _ body => do
            let loopEnv ← addLocal current indexName .u32 false
            acc ← collectEventPlansFromStatements module loopEnv acc body
        | .whileLoop _ _ => pure ()
        | .return value => do
            acc ← collectEventPlansFromExpr module current acc value
      pure acc
end

def buildEventPlans (module : Module) : Except LowerError (Array EventPlan) := do
  let mut collector : EventCollector := {}
  for entrypoint in module.entrypoints do
    collector ← collectEventPlansFromStatements module (entrypointTypeEnv entrypoint) collector entrypoint.body
  .ok collector.plans

/-! ## Helper plan discovery -/

def plainValueTransferMethodId? : Expr → Bool
  | .literal (.u64 0) => true
  | _ => false

def plainValueTransferCall? (methodId : Expr) (args : Array Expr) : Bool :=
  plainValueTransferMethodId? methodId && args.isEmpty

def pushCrosscallHelperSpecIfMissing
    (acc : Array CrosscallHelperSpec)
    (value : CrosscallHelperSpec) : Array CrosscallHelperSpec :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeCrosscallHelperSpecs
    (lhs rhs : Array CrosscallHelperSpec) : Array CrosscallHelperSpec :=
  rhs.foldl pushCrosscallHelperSpecIfMissing lhs

def crosscallArgWordCountForExpr
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (arg : Expr) : Except LowerError Nat := do
  let type ← inferExprType module env arg
  let words ← crosscallArgWordTypes module context type
  .ok words.size

def crosscallArgWordCountForArgs
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (args : Array Expr) : Except LowerError Nat := do
  let mut count := 0
  for arg in args do
    count := count + (← crosscallArgWordCountForExpr module env context arg)
  .ok count

def crosscallHelperSpec
    (module : Module)
    (context : String)
    (arity : Nat)
    (returnType : ValueType)
    (mode : CrosscallMode)
    (plainTransfer : Bool := false) : Except LowerError CrosscallHelperSpec := do
  let wordTypes ← crosscallReturnWordTypes module context returnType
  .ok { arity, returnType, wordTypes, mode, plainTransfer }

mutual
  partial def crosscallHelperSpecsFromExpr
      (module : Module)
      (env : TypeEnv) : Expr → Except LowerError (Array CrosscallHelperSpec)
    | .literal _ | .local _ | .nativeValue => .ok #[]
    | .arrayLit _ values =>
        values.foldlM (init := #[]) fun acc value => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env value))
    | .arrayGet array index => do
        let arraySpecs ← crosscallHelperSpecsFromExpr module env array
        let indexSpecs ← crosscallHelperSpecsFromExpr module env index
        .ok (mergeCrosscallHelperSpecs arraySpecs indexSpecs)
    | .memoryArrayNew _ length =>
        crosscallHelperSpecsFromExpr module env length
    | .memoryArrayLength array =>
        crosscallHelperSpecsFromExpr module env array
    | .memoryArrayGet array index => do
        let arraySpecs ← crosscallHelperSpecsFromExpr module env array
        let indexSpecs ← crosscallHelperSpecsFromExpr module env index
        .ok (mergeCrosscallHelperSpecs arraySpecs indexSpecs)
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
    | .field base _ =>
        crosscallHelperSpecsFromExpr module env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs => do
        let lhsSpecs ← crosscallHelperSpecsFromExpr module env lhs
        let rhsSpecs ← crosscallHelperSpecsFromExpr module env rhs
        .ok (mergeCrosscallHelperSpecs lhsSpecs rhsSpecs)
    | .cast value _ | .boolNot value | .hash value =>
        crosscallHelperSpecsFromExpr module env value
    | .hashValue a b c d => do
        let ab := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env a)
          (← crosscallHelperSpecsFromExpr module env b)
        let cd := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env c)
          (← crosscallHelperSpecsFromExpr module env d)
        .ok (mergeCrosscallHelperSpecs ab cd)
    | .crosscallInvoke target methodId args => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let spec ← crosscallHelperSpec module "crosscall return" args.size .u64 .call
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "typed crosscall argument" args
        let spec ← crosscallHelperSpec module "typed crosscall return" argWordCount returnType .call
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env callValue)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "value crosscall argument" args
        let plainTransfer := plainValueTransferCall? methodId args && isCrosscallWordType returnType
        let spec ← crosscallHelperSpec
          module
          "value crosscall return"
          argWordCount
          returnType
          .callValue
          plainTransfer
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "static crosscall argument" args
        let spec ← crosscallHelperSpec module "static crosscall return" argWordCount returnType .staticcall
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env target)
          (← crosscallHelperSpecsFromExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "delegate crosscall argument" args
        let spec ← crosscallHelperSpec module "delegate crosscall return" argWordCount returnType .delegatecall
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .crosscallCreate callValue _ =>
        crosscallHelperSpecsFromExpr module env callValue
    | .crosscallCreate2 callValue salt _ => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExpr module env callValue)
          (← crosscallHelperSpecsFromExpr module env salt))
    | .nearPromiseThen _ _ _ _ | .nearCrosscallInvokePool _ _ _ _ | .nearPromiseResultsCount | .nearPromiseResultStatus _ | .nearPromiseResultU64 _ => .ok #[]
    | .effect effect =>
        crosscallHelperSpecsFromEffect module env effect

  partial def crosscallHelperSpecsFromEffect
      (module : Module)
      (env : TypeEnv) : Effect → Except LowerError (Array CrosscallHelperSpec)
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => .ok #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        crosscallHelperSpecsFromExpr module env value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        crosscallHelperSpecsFromExpr module env key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value => do
        let keySpecs ← crosscallHelperSpecsFromExpr module env key
        let valueSpecs ← crosscallHelperSpecsFromExpr module env value
        .ok (mergeCrosscallHelperSpecs keySpecs valueSpecs)
    | .storageDynamicArrayPush _ value =>
        crosscallHelperSpecsFromExpr module env value
    | .storageDynamicArrayPop _ =>
        .ok #[]
    | .memoryArraySet array index value => do
        let arraySpecs ← crosscallHelperSpecsFromExpr module env array
        let indexSpecs ← crosscallHelperSpecsFromExpr module env index
        let valueSpecs ← crosscallHelperSpecsFromExpr module env value
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs arraySpecs indexSpecs) valueSpecs)
    | .storagePathRead _ path =>
        path.foldlM (init := #[]) fun acc segment => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStoragePathSegment module env segment))
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value => do
        let pathSpecs ← path.foldlM (init := #[]) fun acc segment => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStoragePathSegment module env segment))
        .ok (mergeCrosscallHelperSpecs pathSpecs (← crosscallHelperSpecsFromExpr module env value))
    | .eventEmit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexedSpecs ← indexedFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))
        dataFields.foldlM (init := indexedSpecs) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExpr module env field.snd))

  partial def crosscallHelperSpecsFromStoragePathSegment
      (module : Module)
      (env : TypeEnv) : StoragePathSegment → Except LowerError (Array CrosscallHelperSpec)
    | .field _ => .ok #[]
    | .index index => crosscallHelperSpecsFromExpr module env index
    | .mapKey key => crosscallHelperSpecsFromExpr module env key

  partial def crosscallHelperSpecsFromStatement
      (module : Module)
      (env : TypeEnv) : Statement → Except LowerError (Array CrosscallHelperSpec × TypeEnv)
    | .letBind name type value => do
        let specs ← crosscallHelperSpecsFromExpr module env value
        let nextEnv ← addLocal env name type false
        .ok (specs, nextEnv)
    | .letMutBind name type value => do
        let specs ← crosscallHelperSpecsFromExpr module env value
        let nextEnv ← addLocal env name type true
        .ok (specs, nextEnv)
    | .assign target value | .assignOp target _ value => do
        let targetSpecs ← crosscallHelperSpecsFromExpr module env target
        let valueSpecs ← crosscallHelperSpecsFromExpr module env value
        .ok (mergeCrosscallHelperSpecs targetSpecs valueSpecs, env)
    | .effect effect => do
        .ok (← crosscallHelperSpecsFromEffect module env effect, env)
    | .assert condition _ _ => do
        .ok (← crosscallHelperSpecsFromExpr module env condition, env)
    | .assertEq lhs rhs _ _ => do
        let lhsSpecs ← crosscallHelperSpecsFromExpr module env lhs
        let rhsSpecs ← crosscallHelperSpecsFromExpr module env rhs
        .ok (mergeCrosscallHelperSpecs lhsSpecs rhsSpecs, env)
    | .release _ =>
        .ok (#[], env)
    | .revert _ => .ok (#[], env)
    | .revertWithError _ => .ok (#[], env)
    | .ifElse condition thenBody elseBody => do
        let conditionSpecs ← crosscallHelperSpecsFromExpr module env condition
        let (thenSpecs, _) ← crosscallHelperSpecsFromStatements module env thenBody
        let (elseSpecs, _) ← crosscallHelperSpecsFromStatements module env elseBody
        .ok (mergeCrosscallHelperSpecs conditionSpecs (mergeCrosscallHelperSpecs thenSpecs elseSpecs), env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodySpecs, _) ← crosscallHelperSpecsFromStatements module loopEnv body
        .ok (bodySpecs, env)
    | .whileLoop _ _ => .ok (#[], env)
    | .return value => do
        .ok (← crosscallHelperSpecsFromExpr module env value, env)

  partial def crosscallHelperSpecsFromStatements
      (module : Module)
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array CrosscallHelperSpec × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (specs, currentEnv) := acc
      let (stmtSpecs, nextEnv) ← crosscallHelperSpecsFromStatement module currentEnv stmt
      .ok (mergeCrosscallHelperSpecs specs stmtSpecs, nextEnv)
end

def buildCrosscallHelperPlans (module : Module) : Except LowerError (Array CrosscallHelperSpec) := do
  let mut specs : Array CrosscallHelperSpec := #[]
  for entrypoint in module.entrypoints do
    let (entrypointSpecs, _) ←
      crosscallHelperSpecsFromStatements module (entrypointTypeEnv entrypoint) entrypoint.body
    specs := mergeCrosscallHelperSpecs specs entrypointSpecs
  .ok specs

def plainValueTransferMethodIdPlan? : ExprPlan → Bool
  | .literalWord 0 => true
  | _ => false

def plainValueTransferCallPlan? (methodId : ExprPlan) (args : Array CrosscallArgWordPlan) : Bool :=
  plainValueTransferMethodIdPlan? methodId && args.isEmpty

mutual
  partial def crosscallHelperSpecsFromContextExprPlan
      (module : Module) : ContextExprPlan → Except LowerError (Array CrosscallHelperSpec)
    | .blockHash blockNumber =>
        crosscallHelperSpecsFromExprPlan module blockNumber
    | .userId | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        .ok #[]

  partial def crosscallHelperSpecsFromStorageSlotExprPlan
      (module : Module) : StorageSlotExprPlan → Except LowerError (Array CrosscallHelperSpec)
    | .scalarSlot _ | .fixedSlot _ => .ok #[]
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldlM (init := #[]) fun acc key => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module key))
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        crosscallHelperSpecsFromExprPlan module index

  partial def crosscallHelperSpecsFromStoragePathWriteExprTargetPlan
      (module : Module) : StoragePathWriteExprTargetPlan → Except LowerError (Array CrosscallHelperSpec)
    | .mapWrite _ key =>
        crosscallHelperSpecsFromExprPlan module key
    | .singleSlot slot =>
        crosscallHelperSpecsFromStorageSlotExprPlan module slot
    | .mapValuePresence valueSlot presenceSlot => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromStorageSlotExprPlan module valueSlot)
          (← crosscallHelperSpecsFromStorageSlotExprPlan module presenceSlot))

  partial def crosscallHelperSpecsFromAbiValuePlan
      (module : Module) : AbiValuePlan → Except LowerError (Array CrosscallHelperSpec)
    | .expr value =>
        crosscallHelperSpecsFromExprPlan module value
    | .local .. | .storage .. =>
        .ok #[]
    | .arrayLit _ values =>
        values.foldlM (init := #[]) fun acc value => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module value))
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field.snd))

  partial def crosscallHelperSpecsFromCrosscallArgWordPlan
      (module : Module) : CrosscallArgWordPlan → Except LowerError (Array CrosscallHelperSpec)
    | .expr value =>
        crosscallHelperSpecsFromExprPlan module value
    | .local .. | .storage .. =>
        .ok #[]

  partial def crosscallHelperSpecsFromExprPlan
      (module : Module) : ExprPlan → Except LowerError (Array CrosscallHelperSpec)
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        .ok #[]
    | .storageLoad slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldlM (init := #[]) fun acc valuePlan => do
              match valuePlan with
              | .irExpr _ => .ok acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            .ok #[]
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldlM (init := #[]) fun acc arg => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module arg))
    | .checkedArith _ lhs rhs
    | .arrayGet lhs rhs
    | .hashTwoToOne lhs rhs => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module lhs)
          (← crosscallHelperSpecsFromExprPlan module rhs))
    | .hashPack a b c d | .hashValue a b c d => do
        let ab := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module a)
          (← crosscallHelperSpecsFromExprPlan module b)
        let cd := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module c)
          (← crosscallHelperSpecsFromExprPlan module d)
        .ok (mergeCrosscallHelperSpecs ab cd)
    | .context field =>
        crosscallHelperSpecsFromContextExprPlan module field
    | .crosscall mode target methodId callValue? args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module target)
          (← crosscallHelperSpecsFromExprPlan module methodId)
        match callValue? with
        | some callValue =>
            nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromExprPlan module callValue)
        | none => pure ()
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsFromCrosscallArgWordPlan module arg)
        let plainTransfer :=
          match mode with
          | .callValue => plainValueTransferCallPlan? methodId args && isCrosscallWordType returnType
          | .call | .staticcall | .delegatecall => false
        let spec ← crosscallHelperSpec
          module
          "planned crosscall return"
          args.size
          returnType
          mode
          plainTransfer
        .ok (pushCrosscallHelperSpecIfMissing nested spec)
    | .create _ callValue salt? _ => do
        let callValueSpecs ← crosscallHelperSpecsFromExprPlan module callValue
        match salt? with
        | some salt =>
            .ok (mergeCrosscallHelperSpecs callValueSpecs (← crosscallHelperSpecsFromExprPlan module salt))
        | none =>
            .ok callValueSpecs
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        crosscallHelperSpecsFromExprPlan module source
    | .localArrayGet _ path _ =>
        path.foldlM (init := #[]) fun acc index => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module index))
    | .memoryArrayNew _ length =>
        crosscallHelperSpecsFromExprPlan module length
    | .memoryArrayGet array index => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module array)
          (← crosscallHelperSpecsFromExprPlan module index))
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromExprPlan module field.snd))
    | .effect effect =>
        crosscallHelperSpecsFromEffectPlan module effect

  partial def crosscallHelperSpecsFromEffectPlan
      (module : Module) : EffectPlan → Except LowerError (Array CrosscallHelperSpec)
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        .ok #[]
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        crosscallHelperSpecsFromExprPlan module value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        crosscallHelperSpecsFromExprPlan module key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value => do
        let keySpecs ← crosscallHelperSpecsFromExprPlan module key
        let valueSpecs ← crosscallHelperSpecsFromExprPlan module value
        .ok (mergeCrosscallHelperSpecs keySpecs valueSpecs)
    | .memoryArraySet array index value => do
        let arraySpecs ← crosscallHelperSpecsFromExprPlan module array
        let indexSpecs ← crosscallHelperSpecsFromExprPlan module index
        let valueSpecs ← crosscallHelperSpecsFromExprPlan module value
        .ok (mergeCrosscallHelperSpecs (mergeCrosscallHelperSpecs arraySpecs indexSpecs) valueSpecs)
    | .storagePathRead _ _ =>
        .ok #[]
    | .storagePathReadTarget slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldlM (init := #[]) fun acc valuePlan => do
              match valuePlan with
              | .irExpr _ => .ok acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            .ok #[]
    | .storagePathReadExprTarget slot =>
        crosscallHelperSpecsFromStorageSlotExprPlan module slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        crosscallHelperSpecsFromExprPlan module value
    | .storagePathWriteTarget target value
    | .storagePathAssignOpTarget target _ value => do
        let targetSpecs ←
          match target with
          | .mapWrite _ (.irExpr _) => .ok #[]
          | .singleSlot _ => .ok #[]
          | .mapValuePresence _ _ => .ok #[]
        .ok (mergeCrosscallHelperSpecs targetSpecs (← crosscallHelperSpecsFromExprPlan module value))
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromStoragePathWriteExprTargetPlan module target)
          (← crosscallHelperSpecsFromExprPlan module value))
    | .contextRead field =>
        crosscallHelperSpecsFromContextExprPlan module field
    | .eventEmit _ dataFields =>
        dataFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field))
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexedSpecs ← indexedFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field))
        dataFields.foldlM (init := indexedSpecs) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromAbiValuePlan module field))
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldlM (init := #[]) fun acc words => do
          words.foldlM (init := acc) fun wordAcc word => do
            .ok (mergeCrosscallHelperSpecs wordAcc (← crosscallHelperSpecsFromExprPlan module word))
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords => do
        let indexedSpecs ← indexedFieldWords.foldlM (init := #[]) fun acc words => do
          words.foldlM (init := acc) fun wordAcc word => do
            .ok (mergeCrosscallHelperSpecs wordAcc (← crosscallHelperSpecsFromExprPlan module word))
        dataFieldWords.foldlM (init := indexedSpecs) fun acc words => do
          words.foldlM (init := acc) fun wordAcc word => do
            .ok (mergeCrosscallHelperSpecs wordAcc (← crosscallHelperSpecsFromExprPlan module word))

  partial def crosscallHelperSpecsFromStmtPlan
      (module : Module) : StmtPlan → Except LowerError (Array CrosscallHelperSpec)
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        crosscallHelperSpecsFromExprPlan module value
    | .assign target value
    | .assignOp target _ value => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module target)
          (← crosscallHelperSpecsFromExprPlan module value))
    | .effect effect =>
        crosscallHelperSpecsFromEffectPlan module effect
    | .assertEq lhs rhs _ _ => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsFromExprPlan module lhs)
          (← crosscallHelperSpecsFromExprPlan module rhs))
    | .release _ | .revert _ | .revertWithError _ =>
        .ok #[]
    | .ifElse condition thenBody elseBody => do
        let conditionSpecs ← crosscallHelperSpecsFromExprPlan module condition
        let thenSpecs ← crosscallHelperSpecsFromStmtPlans module thenBody
        let elseSpecs ← crosscallHelperSpecsFromStmtPlans module elseBody
        .ok (mergeCrosscallHelperSpecs conditionSpecs (mergeCrosscallHelperSpecs thenSpecs elseSpecs))
    | .boundedFor _ _ _ body =>
        crosscallHelperSpecsFromStmtPlans module body

  partial def crosscallHelperSpecsFromStmtPlans
      (module : Module)
      (statements : Array StmtPlan) : Except LowerError (Array CrosscallHelperSpec) :=
    statements.foldlM (init := #[]) fun acc stmt => do
      .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStmtPlan module stmt))
end

def buildCrosscallHelperPlansFromEntrypoints
    (module : Module)
    (entrypoints : Array EntrypointPlan) : Except LowerError (Array CrosscallHelperSpec) :=
  entrypoints.foldlM (init := #[]) fun acc entrypoint => do
    .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsFromStmtPlans module entrypoint.body))

def pushCreateHelperSpecIfMissing
    (acc : Array CreateHelperSpec)
    (value : CreateHelperSpec) : Array CreateHelperSpec :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeCreateHelperSpecs
    (lhs rhs : Array CreateHelperSpec) : Array CreateHelperSpec :=
  rhs.foldl pushCreateHelperSpecIfMissing lhs

mutual
  partial def createHelperSpecsFromExpr : Expr → Array CreateHelperSpec
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr value)
    | .arrayGet array index =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr array) (createHelperSpecsFromExpr index)
    | .memoryArrayNew _ length =>
        createHelperSpecsFromExpr length
    | .memoryArrayLength array =>
        createHelperSpecsFromExpr array
    | .memoryArrayGet array index =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr array) (createHelperSpecsFromExpr index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
    | .field base _ =>
        createHelperSpecsFromExpr base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr lhs) (createHelperSpecsFromExpr rhs)
    | .cast value _ | .boolNot value | .hash value =>
        createHelperSpecsFromExpr value
    | .hashValue a b c d =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr a) (createHelperSpecsFromExpr b))
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr c) (createHelperSpecsFromExpr d))
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsFromExpr target) (createHelperSpecsFromExpr methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsFromExpr target) (createHelperSpecsFromExpr methodId)
        let nested := mergeCreateHelperSpecs nested (createHelperSpecsFromExpr callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr arg)
    | .crosscallCreate callValue initCodeHex =>
        pushCreateHelperSpecIfMissing (createHelperSpecsFromExpr callValue) { mode := .create, initCodeHex }
    | .crosscallCreate2 callValue salt initCodeHex =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsFromExpr callValue) (createHelperSpecsFromExpr salt)
        pushCreateHelperSpecIfMissing nested { mode := .create2, initCodeHex }
    | .nearPromiseThen _ _ _ _ | .nearCrosscallInvokePool _ _ _ _ | .nearPromiseResultsCount | .nearPromiseResultStatus _ | .nearPromiseResultU64 _ => #[]
    | .effect effect =>
        createHelperSpecsFromEffect effect

  partial def createHelperSpecsFromEffect : Effect → Array CreateHelperSpec
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        createHelperSpecsFromExpr value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        createHelperSpecsFromExpr key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr key) (createHelperSpecsFromExpr value)
    | .storageDynamicArrayPush _ value =>
        createHelperSpecsFromExpr value
    | .storageDynamicArrayPop _ =>
        #[]
    | .memoryArraySet array index value =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsFromExpr array) (createHelperSpecsFromExpr index))
          (createHelperSpecsFromExpr value)
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromStoragePathSegment segment)
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        let pathSpecs := path.foldl (init := #[]) fun acc segment =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromStoragePathSegment segment)
        mergeCreateHelperSpecs pathSpecs (createHelperSpecsFromExpr value)
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedSpecs := indexedFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)
        dataFields.foldl (init := indexedSpecs) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExpr field.snd)

  partial def createHelperSpecsFromStoragePathSegment : StoragePathSegment → Array CreateHelperSpec
    | .field _ => #[]
    | .index index => createHelperSpecsFromExpr index
    | .mapKey key => createHelperSpecsFromExpr key

  partial def createHelperSpecsFromStatement : Statement → Array CreateHelperSpec
    | .letBind _ _ value | .letMutBind _ _ value =>
        createHelperSpecsFromExpr value
    | .assign target value | .assignOp target _ value =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr target) (createHelperSpecsFromExpr value)
    | .effect effect =>
        createHelperSpecsFromEffect effect
    | .assert condition _ _ =>
        createHelperSpecsFromExpr condition
    | .assertEq lhs rhs _ _ =>
        mergeCreateHelperSpecs (createHelperSpecsFromExpr lhs) (createHelperSpecsFromExpr rhs)
    | .release _ =>
        #[]
    | .revert _ => #[]
    | .revertWithError _ => #[]
    | .ifElse condition thenBody elseBody =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExpr condition)
          (mergeCreateHelperSpecs (createHelperSpecsFromStatements thenBody) (createHelperSpecsFromStatements elseBody))
    | .boundedFor _ _ _ body =>
        createHelperSpecsFromStatements body
    | .whileLoop _ _ => #[]
    | .return value =>
        createHelperSpecsFromExpr value

  partial def createHelperSpecsFromStatements (statements : Array Statement) : Array CreateHelperSpec :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeCreateHelperSpecs acc (createHelperSpecsFromStatement stmt)
end

def buildCreateHelperPlans (module : Module) : Array CreateHelperSpec :=
  module.entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeCreateHelperSpecs acc (createHelperSpecsFromStatements entrypoint.body)

mutual
  partial def createHelperSpecsFromContextExprPlan : ContextExprPlan → Array CreateHelperSpec
    | .blockHash blockNumber =>
        createHelperSpecsFromExprPlan blockNumber
    | .userId | .contractId | .checkpointId | .timestamp | .chainId
    | .gasPrice | .gasLeft | .baseFee | .prevRandao | .origin | .coinbase =>
        #[]

  partial def createHelperSpecsFromStorageSlotExprPlan : StorageSlotExprPlan → Array CreateHelperSpec
    | .scalarSlot _ | .fixedSlot _ => #[]
    | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
        keys.foldl (init := #[]) fun acc key =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan key)
    | .arraySlot _ _ index
    | .structArrayFieldSlot _ _ _ _ index
    | .dynamicArraySlot _ index =>
        createHelperSpecsFromExprPlan index

  partial def createHelperSpecsFromStoragePathWriteExprTargetPlan :
      StoragePathWriteExprTargetPlan → Array CreateHelperSpec
    | .mapWrite _ key =>
        createHelperSpecsFromExprPlan key
    | .singleSlot slot =>
        createHelperSpecsFromStorageSlotExprPlan slot
    | .mapValuePresence valueSlot presenceSlot =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromStorageSlotExprPlan valueSlot)
          (createHelperSpecsFromStorageSlotExprPlan presenceSlot)

  partial def createHelperSpecsFromAbiValuePlan : AbiValuePlan → Array CreateHelperSpec
    | .expr value =>
        createHelperSpecsFromExprPlan value
    | .local .. | .storage .. =>
        #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan value)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field.snd)

  partial def createHelperSpecsFromCrosscallArgWordPlan :
      CrosscallArgWordPlan → Array CreateHelperSpec
    | .expr value =>
        createHelperSpecsFromExprPlan value
    | .local .. | .storage .. =>
        #[]

  partial def createHelperSpecsFromExprPlan : ExprPlan → Array CreateHelperSpec
    | .literalWord _ | .local _ | .calldataWord _ | .nativeValue =>
        #[]
    | .storageLoad slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldl (init := #[]) fun acc valuePlan =>
              match valuePlan with
              | .irExpr _ => acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            #[]
    | .builtin _ args | .helperCall _ args | .arrayLit _ args =>
        args.foldl (init := #[]) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan arg)
    | .checkedArith _ lhs rhs
    | .arrayGet lhs rhs
    | .hashTwoToOne lhs rhs =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan lhs)
          (createHelperSpecsFromExprPlan rhs)
    | .hashPack a b c d | .hashValue a b c d =>
        let ab := mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan a)
          (createHelperSpecsFromExprPlan b)
        let cd := mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan c)
          (createHelperSpecsFromExprPlan d)
        mergeCreateHelperSpecs ab cd
    | .context field =>
        createHelperSpecsFromContextExprPlan field
    | .crosscall _ target methodId callValue? args _ =>
        let nested := mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan target)
          (createHelperSpecsFromExprPlan methodId)
        let nested :=
          match callValue? with
          | some callValue => mergeCreateHelperSpecs nested (createHelperSpecsFromExprPlan callValue)
          | none => nested
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromCrosscallArgWordPlan arg)
    | .create mode callValue salt? initCodeHex =>
        let nested :=
          match salt? with
          | some salt =>
              mergeCreateHelperSpecs
                (createHelperSpecsFromExprPlan callValue)
                (createHelperSpecsFromExprPlan salt)
          | none =>
              createHelperSpecsFromExprPlan callValue
        pushCreateHelperSpecIfMissing nested { mode, initCodeHex }
    | .cast source _
    | .structField source _
    | .memoryArrayLength source
    | .hash source =>
        createHelperSpecsFromExprPlan source
    | .localArrayGet _ path _ =>
        path.foldl (init := #[]) fun acc index =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan index)
    | .memoryArrayNew _ length =>
        createHelperSpecsFromExprPlan length
    | .memoryArrayGet array index =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan array)
          (createHelperSpecsFromExprPlan index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromExprPlan field.snd)
    | .effect effect =>
        createHelperSpecsFromEffectPlan effect

  partial def createHelperSpecsFromEffectPlan : EffectPlan → Array CreateHelperSpec
    | .storageScalarRead _ | .storageScalarReadTarget _
    | .storageStructFieldRead _ _ | .storageStructFieldReadTarget _
    | .storageDynamicArrayPop _ | .storageDynamicArrayPopTarget _ =>
        #[]
    | .storageScalarWrite _ value
    | .storageScalarWriteTarget _ value
    | .storageScalarAssignOp _ _ value
    | .storageScalarAssignOpTarget _ _ value
    | .storageStructFieldWrite _ _ value
    | .storageStructFieldWriteTarget _ value
    | .storageDynamicArrayPush _ value
    | .storageDynamicArrayPushTarget _ value =>
        createHelperSpecsFromExprPlan value
    | .storageMapContains _ key
    | .storageMapContainsTarget _ key
    | .storageMapGet _ key
    | .storageMapGetTarget _ key
    | .storageArrayRead _ key
    | .storageArrayReadTarget _ key
    | .storageArrayStructFieldRead _ key _
    | .storageArrayStructFieldReadTarget _ key =>
        createHelperSpecsFromExprPlan key
    | .storageMapInsert _ key value
    | .storageMapInsertTarget _ key value
    | .storageMapSet _ key value
    | .storageMapSetTarget _ key value
    | .storageArrayWrite _ key value
    | .storageArrayWriteTarget _ key value
    | .storageArrayStructFieldWrite _ key _ value
    | .storageArrayStructFieldWriteTarget _ key value =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan key)
          (createHelperSpecsFromExprPlan value)
    | .memoryArraySet array index value =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs
            (createHelperSpecsFromExprPlan array)
            (createHelperSpecsFromExprPlan index))
          (createHelperSpecsFromExprPlan value)
    | .storagePathRead _ _ =>
        #[]
    | .storagePathReadTarget slot =>
        match slot with
        | .mapValueSlot _ keys | .mapPresenceSlot _ keys =>
            keys.foldl (init := #[]) fun acc valuePlan =>
              match valuePlan with
              | .irExpr _ => acc
        | .arraySlot .. | .structArrayFieldSlot .. | .dynamicArraySlot ..
        | .scalarSlot _ | .fixedSlot _ =>
            #[]
    | .storagePathReadExprTarget slot =>
        createHelperSpecsFromStorageSlotExprPlan slot
    | .storagePathWrite _ _ value | .storagePathAssignOp _ _ _ value =>
        createHelperSpecsFromExprPlan value
    | .storagePathWriteTarget target value
    | .storagePathAssignOpTarget target _ value =>
        let targetSpecs :=
          match target with
          | .mapWrite _ (.irExpr _) => #[]
          | .singleSlot _ => #[]
          | .mapValuePresence _ _ => #[]
        mergeCreateHelperSpecs targetSpecs (createHelperSpecsFromExprPlan value)
    | .storagePathWriteExprTarget target value
    | .storagePathAssignOpExprTarget target _ value =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromStoragePathWriteExprTargetPlan target)
          (createHelperSpecsFromExprPlan value)
    | .contextRead field =>
        createHelperSpecsFromContextExprPlan field
    | .eventEmit _ dataFields =>
        dataFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedSpecs := indexedFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field)
        dataFields.foldl (init := indexedSpecs) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsFromAbiValuePlan field)
    | .eventEmitWords _ dataFieldWords =>
        dataFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeCreateHelperSpecs wordAcc (createHelperSpecsFromExprPlan word)
    | .eventEmitIndexedWords _ indexedFieldWords dataFieldWords =>
        let indexedSpecs := indexedFieldWords.foldl (init := #[]) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeCreateHelperSpecs wordAcc (createHelperSpecsFromExprPlan word)
        dataFieldWords.foldl (init := indexedSpecs) fun acc words =>
          words.foldl (init := acc) fun wordAcc word =>
            mergeCreateHelperSpecs wordAcc (createHelperSpecsFromExprPlan word)

  partial def createHelperSpecsFromStmtPlan : StmtPlan → Array CreateHelperSpec
    | .letBind _ _ value
    | .letMutBind _ _ value
    | .assert value _ _
    | .return value =>
        createHelperSpecsFromExprPlan value
    | .assign target value
    | .assignOp target _ value =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan target)
          (createHelperSpecsFromExprPlan value)
    | .effect effect =>
        createHelperSpecsFromEffectPlan effect
    | .assertEq lhs rhs _ _ =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan lhs)
          (createHelperSpecsFromExprPlan rhs)
    | .release _ | .revert _ | .revertWithError _ =>
        #[]
    | .ifElse condition thenBody elseBody =>
        mergeCreateHelperSpecs
          (createHelperSpecsFromExprPlan condition)
          (mergeCreateHelperSpecs (createHelperSpecsFromStmtPlans thenBody) (createHelperSpecsFromStmtPlans elseBody))
    | .boundedFor _ _ _ body =>
        createHelperSpecsFromStmtPlans body

  partial def createHelperSpecsFromStmtPlans (statements : Array StmtPlan) : Array CreateHelperSpec :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeCreateHelperSpecs acc (createHelperSpecsFromStmtPlan stmt)
end

def buildCreateHelperPlansFromEntrypoints
    (entrypoints : Array EntrypointPlan) : Array CreateHelperSpec :=
  entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeCreateHelperSpecs acc (createHelperSpecsFromStmtPlans entrypoint.body)

def localArrayGetLengthsForDynamicExprTarget
    (env : TypeEnv)
    (array index : Expr) : Array Nat :=
  match literalArrayIndex? index with
  | some _ => #[]
  | none =>
      match array with
      | .local name =>
          match findLocal? env name with
          | some { type := .fixedArray _ length, .. } => #[length]
          | _ => #[]
      | .arrayLit _ values => #[values.size]
      | _ => #[]

def nestedLocalArrayGetShapesForDynamicExprTarget
    (env : TypeEnv)
    (array index : Expr) : Array (Array Nat) :=
  let fullExpr := Expr.arrayGet array index
  match collectLocalArrayGetPath fullExpr with
  | some (name, path) =>
      if path.size > 1 && arrayIndexPathHasDynamic path then
        match findLocal? env name with
        | some binding =>
            match fixedArrayPathShape "fixed array index" binding.type path with
            | .ok (lengths, leafType) =>
                match leafType with
                | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .structType _ => #[lengths]
                | .unit | .fixedArray _ _ | .bytes | .string | .array _ => #[]
            | .error _ => #[]
        | none => #[]
      else
        #[]
  | none => #[]

mutual
  partial def localArrayGetLengthsExpr (env : TypeEnv) : Expr → Array Nat
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeNatSets acc (localArrayGetLengthsExpr env value)
    | .arrayGet array index =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env array) (localArrayGetLengthsExpr env index)
        mergeNatSets nested (localArrayGetLengthsForDynamicExprTarget env array index)
    | .memoryArrayNew _ length =>
        localArrayGetLengthsExpr env length
    | .memoryArrayLength array =>
        localArrayGetLengthsExpr env array
    | .memoryArrayGet array index =>
        mergeNatSets (localArrayGetLengthsExpr env array) (localArrayGetLengthsExpr env index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)
    | .field base _ =>
        localArrayGetLengthsExpr env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeNatSets (localArrayGetLengthsExpr env lhs) (localArrayGetLengthsExpr env rhs)
    | .cast value _ | .boolNot value | .hash value =>
        localArrayGetLengthsExpr env value
    | .hashValue a b c d =>
        mergeNatSets
          (mergeNatSets (localArrayGetLengthsExpr env a) (localArrayGetLengthsExpr env b))
          (mergeNatSets (localArrayGetLengthsExpr env c) (localArrayGetLengthsExpr env d))
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env target) (localArrayGetLengthsExpr env methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeNatSets acc (localArrayGetLengthsExpr env arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env target) (localArrayGetLengthsExpr env methodId)
        let nested := mergeNatSets nested (localArrayGetLengthsExpr env callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeNatSets acc (localArrayGetLengthsExpr env arg)
    | .crosscallCreate callValue _ =>
        localArrayGetLengthsExpr env callValue
    | .crosscallCreate2 callValue salt _ =>
        mergeNatSets (localArrayGetLengthsExpr env callValue) (localArrayGetLengthsExpr env salt)
    | .nearPromiseThen p m args d =>
        mergeNatSets (mergeNatSets (localArrayGetLengthsExpr env p) (localArrayGetLengthsExpr env m))
          (mergeNatSets (localArrayGetLengthsExpr env d) (args.foldl (fun acc arg => mergeNatSets acc (localArrayGetLengthsExpr env arg)) #[]))
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        mergeNatSets (mergeNatSets (localArrayGetLengthsExpr env accountIndex) (localArrayGetLengthsExpr env methodId))
          (mergeNatSets (localArrayGetLengthsExpr env deposit)
            (args.foldl (fun acc arg => mergeNatSets acc (localArrayGetLengthsExpr env arg)) #[]))
    | .nearPromiseResultsCount => #[]
    | .nearPromiseResultStatus i => localArrayGetLengthsExpr env i
    | .nearPromiseResultU64 i => localArrayGetLengthsExpr env i
    | .effect effect =>
        localArrayGetLengthsEffect env effect

  partial def localArrayGetLengthsEffect (env : TypeEnv) : Effect → Array Nat
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        localArrayGetLengthsExpr env value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        localArrayGetLengthsExpr env key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value =>
        mergeNatSets (localArrayGetLengthsExpr env key) (localArrayGetLengthsExpr env value)
    | .storageDynamicArrayPush _ value =>
        localArrayGetLengthsExpr env value
    | .storageDynamicArrayPop _ =>
        #[]
    | .memoryArraySet array index value =>
        mergeNatSets
          (mergeNatSets (localArrayGetLengthsExpr env array) (localArrayGetLengthsExpr env index))
          (localArrayGetLengthsExpr env value)
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment =>
          mergeNatSets acc (localArrayGetLengthsStoragePathSegment env segment)
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        let pathLengths := path.foldl (init := #[]) fun acc segment =>
          mergeNatSets acc (localArrayGetLengthsStoragePathSegment env segment)
        mergeNatSets pathLengths (localArrayGetLengthsExpr env value)
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedLengths := indexedFields.foldl (init := #[]) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)
        dataFields.foldl (init := indexedLengths) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)

  partial def localArrayGetLengthsStoragePathSegment (env : TypeEnv) : StoragePathSegment → Array Nat
    | .field _ => #[]
    | .index index => localArrayGetLengthsExpr env index
    | .mapKey key => localArrayGetLengthsExpr env key

  partial def localArrayGetLengthsAssignTarget (env : TypeEnv) : Expr → Array Nat
    | .arrayGet (.local _) index =>
        localArrayGetLengthsExpr env index
    | .field (.local _) _ =>
        #[]
    | target =>
        localArrayGetLengthsExpr env target

  partial def localArrayGetLengthsStatement
      (env : TypeEnv) : Statement → Except LowerError (Array Nat × TypeEnv)
    | .letBind name type value => do
        let nextEnv ← addLocal env name type false
        .ok (localArrayGetLengthsExpr env value, nextEnv)
    | .letMutBind name type value => do
        let nextEnv ← addLocal env name type true
        .ok (localArrayGetLengthsExpr env value, nextEnv)
    | .assign target value | .assignOp target _ value =>
        .ok (mergeNatSets (localArrayGetLengthsAssignTarget env target) (localArrayGetLengthsExpr env value), env)
    | .effect effect =>
        .ok (localArrayGetLengthsEffect env effect, env)
    | .assert condition _ _ =>
        .ok (localArrayGetLengthsExpr env condition, env)
    | .assertEq lhs rhs _ _ =>
        .ok (mergeNatSets (localArrayGetLengthsExpr env lhs) (localArrayGetLengthsExpr env rhs), env)
    | .release _ =>
        .ok (#[], env)
    | .revert _ => .ok (#[], env)
    | .revertWithError _ => .ok (#[], env)
    | .ifElse condition thenBody elseBody => do
        let (thenLengths, _) ← localArrayGetLengthsStatements env thenBody
        let (elseLengths, _) ← localArrayGetLengthsStatements env elseBody
        let bodyLengths := mergeNatSets thenLengths elseLengths
        .ok (mergeNatSets (localArrayGetLengthsExpr env condition) bodyLengths, env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodyLengths, _) ← localArrayGetLengthsStatements loopEnv body
        .ok (bodyLengths, env)
    | .whileLoop _ _ => .ok (#[], env)
    | .return value =>
        .ok (localArrayGetLengthsExpr env value, env)

  partial def localArrayGetLengthsStatements
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array Nat × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (lengths, currentEnv) := acc
      let (stmtLengths, nextEnv) ← localArrayGetLengthsStatement currentEnv stmt
      .ok (mergeNatSets lengths stmtLengths, nextEnv)
end

def buildLocalArrayGetLengths (module : Module) : Except LowerError (Array Nat) := do
  let mut lengths : Array Nat := #[]
  for entrypoint in module.entrypoints do
    let (entrypointLengths, _) ← localArrayGetLengthsStatements (entrypointTypeEnv entrypoint) entrypoint.body
    lengths := mergeNatSets lengths entrypointLengths
  .ok lengths

mutual
  partial def nestedLocalArrayGetShapesExpr (env : TypeEnv) : Expr → Array (Array Nat)
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env value)
    | .arrayGet array index =>
        let nested :=
          mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index)
        mergeNatArraySets nested (nestedLocalArrayGetShapesForDynamicExprTarget env array index)
    | .memoryArrayNew _ length =>
        nestedLocalArrayGetShapesExpr env length
    | .memoryArrayLength array =>
        nestedLocalArrayGetShapesExpr env array
    | .memoryArrayGet array index =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)
    | .field base _ =>
        nestedLocalArrayGetShapesExpr env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env lhs) (nestedLocalArrayGetShapesExpr env rhs)
    | .cast value _ | .boolNot value | .hash value =>
        nestedLocalArrayGetShapesExpr env value
    | .hashValue a b c d =>
        mergeNatArraySets
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env a) (nestedLocalArrayGetShapesExpr env b))
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env c) (nestedLocalArrayGetShapesExpr env d))
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested :=
          mergeNatArraySets (nestedLocalArrayGetShapesExpr env target) (nestedLocalArrayGetShapesExpr env methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested :=
          mergeNatArraySets (nestedLocalArrayGetShapesExpr env target) (nestedLocalArrayGetShapesExpr env methodId)
        let nested := mergeNatArraySets nested (nestedLocalArrayGetShapesExpr env callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env arg)
    | .crosscallCreate callValue _ =>
        nestedLocalArrayGetShapesExpr env callValue
    | .crosscallCreate2 callValue salt _ =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env callValue) (nestedLocalArrayGetShapesExpr env salt)
    | .nearPromiseThen p m args d =>
        let acc := mergeNatArraySets (nestedLocalArrayGetShapesExpr env p) (nestedLocalArrayGetShapesExpr env m)
        let acc := mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env d)
        args.foldl (fun a arg => mergeNatArraySets a (nestedLocalArrayGetShapesExpr env arg)) acc
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        let acc := mergeNatArraySets (nestedLocalArrayGetShapesExpr env accountIndex) (nestedLocalArrayGetShapesExpr env methodId)
        let acc := mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env deposit)
        args.foldl (fun a arg => mergeNatArraySets a (nestedLocalArrayGetShapesExpr env arg)) acc
    | .nearPromiseResultsCount => #[]
    | .nearPromiseResultStatus i => nestedLocalArrayGetShapesExpr env i
    | .nearPromiseResultU64 i => nestedLocalArrayGetShapesExpr env i
    | .effect effect =>
        nestedLocalArrayGetShapesEffect env effect

  partial def nestedLocalArrayGetShapesEffect (env : TypeEnv) : Effect → Array (Array Nat)
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .contextRead _ => #[]
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value =>
        nestedLocalArrayGetShapesExpr env value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ =>
        nestedLocalArrayGetShapesExpr env key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env key) (nestedLocalArrayGetShapesExpr env value)
    | .storageDynamicArrayPush _ value =>
        nestedLocalArrayGetShapesExpr env value
    | .storageDynamicArrayPop _ =>
        #[]
    | .memoryArraySet array index value =>
        mergeNatArraySets
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index))
          (nestedLocalArrayGetShapesExpr env value)
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesStoragePathSegment env segment)
    | .storagePathWrite _ path value | .storagePathAssignOp _ path _ value =>
        let pathShapes := path.foldl (init := #[]) fun acc segment =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesStoragePathSegment env segment)
        mergeNatArraySets pathShapes (nestedLocalArrayGetShapesExpr env value)
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedShapes := indexedFields.foldl (init := #[]) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)
        dataFields.foldl (init := indexedShapes) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)

  partial def nestedLocalArrayGetShapesStoragePathSegment (env : TypeEnv) :
      StoragePathSegment → Array (Array Nat)
    | .field _ => #[]
    | .index index => nestedLocalArrayGetShapesExpr env index
    | .mapKey key => nestedLocalArrayGetShapesExpr env key

  partial def nestedLocalArrayGetShapesAssignTarget (env : TypeEnv) : Expr → Array (Array Nat)
    | .arrayGet array index =>
        let nested :=
          mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index)
        mergeNatArraySets nested (nestedLocalArrayGetShapesForDynamicExprTarget env array index)
    | .field target _ =>
        nestedLocalArrayGetShapesExpr env target
    | _ => #[]

  partial def nestedLocalArrayGetShapesStatement
      (env : TypeEnv) : Statement → Except LowerError (Array (Array Nat) × TypeEnv)
    | .letBind name type value => do
        let nextEnv ← addLocal env name type false
        .ok (nestedLocalArrayGetShapesExpr env value, nextEnv)
    | .letMutBind name type value => do
        let nextEnv ← addLocal env name type true
        .ok (nestedLocalArrayGetShapesExpr env value, nextEnv)
    | .assign target value | .assignOp target _ value =>
        .ok (
          mergeNatArraySets
            (nestedLocalArrayGetShapesAssignTarget env target)
            (nestedLocalArrayGetShapesExpr env value),
          env
        )
    | .effect effect =>
        .ok (nestedLocalArrayGetShapesEffect env effect, env)
    | .assert condition _ _ =>
        .ok (nestedLocalArrayGetShapesExpr env condition, env)
    | .assertEq lhs rhs _ _ =>
        .ok (mergeNatArraySets (nestedLocalArrayGetShapesExpr env lhs) (nestedLocalArrayGetShapesExpr env rhs), env)
    | .release _ =>
        .ok (#[], env)
    | .revert _ => .ok (#[], env)
    | .revertWithError _ => .ok (#[], env)
    | .ifElse condition thenBody elseBody => do
        let (thenShapes, _) ← nestedLocalArrayGetShapesStatements env thenBody
        let (elseShapes, _) ← nestedLocalArrayGetShapesStatements env elseBody
        .ok (
          mergeNatArraySets
            (nestedLocalArrayGetShapesExpr env condition)
            (mergeNatArraySets thenShapes elseShapes),
          env
        )
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodyShapes, _) ← nestedLocalArrayGetShapesStatements loopEnv body
        .ok (bodyShapes, env)
    | .whileLoop _ _ => .ok (#[], env)
    | .return value =>
        .ok (nestedLocalArrayGetShapesExpr env value, env)

  partial def nestedLocalArrayGetShapesStatements
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array (Array Nat) × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (shapes, currentEnv) := acc
      let (stmtShapes, nextEnv) ← nestedLocalArrayGetShapesStatement currentEnv stmt
      .ok (mergeNatArraySets shapes stmtShapes, nextEnv)
end

def buildNestedLocalArrayGetShapes (module : Module) : Except LowerError (Array (Array Nat)) := do
  let mut shapes : Array (Array Nat) := #[]
  for entrypoint in module.entrypoints do
    let (entrypointShapes, _) ← nestedLocalArrayGetShapesStatements (entrypointTypeEnv entrypoint) entrypoint.body
    shapes := mergeNatArraySets shapes entrypointShapes
  .ok shapes

/-! ## Module plan assembly -/

/-- Assemble the final `ModulePlan` from a precomputed `basePlan` (produced by
either `buildModulePlan` or `buildModulePlanWithTargetPlan`) plus the
entrypoint/event/helper analysis that is independent of how the base plan was
built. Both `buildFullModulePlan` and `buildFullModulePlanWithTargetPlan` route
through this to avoid duplicating the ~45-line assembly body. -/
def assembleFullPlan (basePlan : ModulePlan) (module : Module) : Except LowerError ModulePlan := do
  let entrypointPlans ← buildEntrypointPlans module
  let dispatchEntrypointPlans := entrypointPlans.filterMap fun plan =>
    match module.entrypoints.find? (fun ep => ep.name == plan.name) with
    | some ep => if ep.kind == .fallback || ep.kind == .receive then none else some plan
    | none => some plan
  let dispatchPlan := moduleDispatchPlan module dispatchEntrypointPlans
  let eventPlans ← buildEventPlans module
  let crosscallPlans ← buildCrosscallHelperPlansFromEntrypoints module entrypointPlans
  let createPlans := buildCreateHelperPlansFromEntrypoints entrypointPlans
  let localArrayRequirements := buildLocalArrayHelperRequirementsFromEntrypoints entrypointPlans
  let localArrayGetLengths := localArrayRequirements.fst
  let nestedLocalArrayGetShapes := localArrayRequirements.snd
  let usesCheckedArithmetic := entrypointsUseCheckedArithmetic entrypointPlans
  let contextOps := buildContextOpsFromEntrypoints entrypointPlans
  let memoryArrayHelpers := buildMemoryArrayHelpersFromEntrypoints entrypointPlans
  let hashHelpers := buildHashHelpersFromEntrypoints entrypointPlans
  let storageArrayHelpers := buildStorageArrayHelpersFromEntrypoints entrypointPlans
  let mapHelpers := buildMapHelpersFromEntrypoints entrypointPlans
  let helpers := replaceHashHelpers
    (replaceMemoryArrayHelpers
      (replaceStorageArrayHelpers
        (replaceMapHelpers basePlan.helpers mapHelpers)
        storageArrayHelpers)
      memoryArrayHelpers)
    hashHelpers
  let mapAssignOps := helperMapAssignOps helpers
  let metadata := {
    moduleName := module.name
    entrypoints := entrypointPlans
    events := eventPlans
    capabilities := basePlan.targetPlan.capabilities
  }
  .ok { basePlan with
    entrypoints := entrypointPlans
    dispatch := dispatchPlan
    events := eventPlans
    crosscalls := crosscallPlans
    creates := createPlans
    localArrayGetLengths := localArrayGetLengths
    nestedLocalArrayGetShapes := nestedLocalArrayGetShapes
    usesCheckedArithmetic := usesCheckedArithmetic
    contextOps := contextOps
    helpers := helpers
    mapAssignOps := mapAssignOps
    metadata := metadata
  }

def buildFullModulePlan (module : Module) : Except LowerError ModulePlan := do
  let basePlan ←
    match buildModulePlan module with
    | .ok plan => .ok plan
    | .error err => .error (planError err)
  assembleFullPlan basePlan module

def buildFullModulePlanWithTargetPlan
    (module : Module)
    (targetPlan : CapabilityPlan) :
    Except LowerError ModulePlan := do
  let basePlan ←
    match buildModulePlanWithTargetPlan module targetPlan with
    | .ok plan => .ok plan
    | .error err => .error (planError err)
  assembleFullPlan basePlan module

end ProofForge.Backend.Evm.Lower
