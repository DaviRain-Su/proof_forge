import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Lower.Body
import ProofForge.Backend.Evm.Lower.Requirements
import ProofForge.Backend.Evm.Lower.Helpers
import ProofForge.Backend.Evm.Validate
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.ProtocolMaterialize
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
    target := ← buildExprPlan module env
      (ProtocolMaterialize.resolveEvmTargetExpr module.nearCrosscallStrings target)
    methodId := ← buildExprPlan module env
      (ProtocolMaterialize.resolveEvmMethodExpr module.nearCrosscallStrings methodId)
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
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs => do
        let collector ← collectEventPlansFromExpr module env collector lhs
        collectEventPlansFromExpr module env collector rhs
    | .ecrecover a b c d => do
        let collector ← collectEventPlansFromExpr module env collector a
        let collector ← collectEventPlansFromExpr module env collector b
        let collector ← collectEventPlansFromExpr module env collector c
        collectEventPlansFromExpr module env collector d
    | .eip712PermitDigest a b c d e f => do
        let collector ← collectEventPlansFromExpr module env collector a
        let collector ← collectEventPlansFromExpr module env collector b
        let collector ← collectEventPlansFromExpr module env collector c
        let collector ← collectEventPlansFromExpr module env collector d
        let collector ← collectEventPlansFromExpr module env collector e
        collectEventPlansFromExpr module env collector f
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        collectEventPlansFromExpr module env collector target
    | .cast value _ | .boolNot value | .hash value =>
        collectEventPlansFromExpr module env collector value
    | .hashValue a b c d => do
        let collector ← collectEventPlansFromExpr module env collector a
        let collector ← collectEventPlansFromExpr module env collector b
        let collector ← collectEventPlansFromExpr module env collector c
        collectEventPlansFromExpr module env collector d
    | .crosscallInvoke _ _ _ | .crosscallInvokeTyped _ _ _ _ | .crosscallInvokeValueTyped _ _ _ _ _
    | .crosscallInvokeStaticTyped _ _ _ _ | .crosscallInvokeDelegateTyped _ _ _ _ => pure collector
    | .crosscallCreate _ _ | .crosscallCreate2 _ _ _ | .crosscallNamed _ _ _ _ => pure collector
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
    | .storageMapContains _ key | .storageMapGet _ key | .storageMapDelete _ key =>
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
    | .checkErc721Received a b c d => do
        let collector ← collectEventPlansFromExpr module env collector a
        let collector ← collectEventPlansFromExpr module env collector b
        let collector ← collectEventPlansFromExpr module env collector c
        collectEventPlansFromExpr module env collector d
    | .checkErc1155Received a b c d e => do
        let collector ← collectEventPlansFromExpr module env collector a
        let collector ← collectEventPlansFromExpr module env collector b
        let collector ← collectEventPlansFromExpr module env collector c
        let collector ← collectEventPlansFromExpr module env collector d
        collectEventPlansFromExpr module env collector e

    | .checkErc1155BatchReceived a b c d e =>
        #[a, b, c, d, e].foldlM (init := collector)
          (collectEventPlansFromExpr module env)

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

def validateEventAbiWords
    (module : Module) (plans : Array EventPlan) : Except LowerError Unit := do
  let mut seen : Array (String × String) := #[]
  for override in module.eventAbiWords do
    let key := (override.eventName, override.fieldName)
    if seen.contains key then
      .error {
        message :=
          s!"event `{override.eventName}` field `{override.fieldName}` has duplicate ABI overrides"
      }
    seen := seen.push key
    let some event := plans.find? (fun event => event.name == override.eventName)
      | .error {
          message := s!"event ABI override names unknown event `{override.eventName}`"
        }
    if !(event.fields.any fun field => field.name == override.fieldName) then
      .error {
        message :=
          s!"event `{override.eventName}` ABI override names unknown field `{override.fieldName}`"
      }

def buildEventPlans (module : Module) : Except LowerError (Array EventPlan) := do
  let mut collector : EventCollector := {}
  for entrypoint in module.entrypoints do
    collector ← collectEventPlansFromStatements module (entrypointTypeEnv entrypoint) collector entrypoint.body
  validateEventAbiWords module collector.plans
  .ok collector.plans

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
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeNatSets (localArrayGetLengthsExpr env lhs) (localArrayGetLengthsExpr env rhs)
    | .ecrecover a b c d =>
        mergeNatSets
          (mergeNatSets (localArrayGetLengthsExpr env a) (localArrayGetLengthsExpr env b))
          (mergeNatSets (localArrayGetLengthsExpr env c) (localArrayGetLengthsExpr env d))
    | .eip712PermitDigest a b c d e f =>
        mergeNatSets
          (mergeNatSets
            (mergeNatSets (localArrayGetLengthsExpr env a) (localArrayGetLengthsExpr env b))
            (mergeNatSets (localArrayGetLengthsExpr env c) (localArrayGetLengthsExpr env d)))
          (mergeNatSets (localArrayGetLengthsExpr env e) (localArrayGetLengthsExpr env f))
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        localArrayGetLengthsExpr env target
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
    | .crosscallNamed _ _ args _ => args.foldl (fun acc arg => mergeNatSets acc (localArrayGetLengthsExpr env arg)) #[]
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
    | .storageMapDelete _ key
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
    | .checkErc721Received a b c d =>
        mergeNatSets
          (mergeNatSets (localArrayGetLengthsExpr env a) (localArrayGetLengthsExpr env b))
          (mergeNatSets (localArrayGetLengthsExpr env c) (localArrayGetLengthsExpr env d))
    | .checkErc1155Received a b c d e =>
        mergeNatSets
          (mergeNatSets
            (mergeNatSets (localArrayGetLengthsExpr env a) (localArrayGetLengthsExpr env b))
            (mergeNatSets (localArrayGetLengthsExpr env c) (localArrayGetLengthsExpr env d)))
          (localArrayGetLengthsExpr env e)

    | .checkErc1155BatchReceived a b c d e =>
        #[a, b, c, d, e].foldl (init := #[]) fun acc expr =>
          mergeNatSets acc (localArrayGetLengthsExpr env expr)

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
    | .add lhs rhs _ | .sub lhs rhs _ | .mul lhs rhs _ | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env lhs) (nestedLocalArrayGetShapesExpr env rhs)
    | .ecrecover a b c d =>
        mergeNatArraySets
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env a) (nestedLocalArrayGetShapesExpr env b))
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env c) (nestedLocalArrayGetShapesExpr env d))
    | .eip712PermitDigest a b c d e f =>
        mergeNatArraySets
          (mergeNatArraySets
            (mergeNatArraySets (nestedLocalArrayGetShapesExpr env a) (nestedLocalArrayGetShapesExpr env b))
            (mergeNatArraySets (nestedLocalArrayGetShapesExpr env c) (nestedLocalArrayGetShapesExpr env d)))
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env e) (nestedLocalArrayGetShapesExpr env f))
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ =>
        nestedLocalArrayGetShapesExpr env target
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
    | .crosscallNamed _ _ args _ => args.foldl (fun acc arg => mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env arg)) #[]
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
    | .storageMapDelete _ key
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
    | .checkErc721Received a b c d =>
        mergeNatArraySets
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env a) (nestedLocalArrayGetShapesExpr env b))
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env c) (nestedLocalArrayGetShapesExpr env d))
    | .checkErc1155Received a b c d e =>
        mergeNatArraySets
          (mergeNatArraySets
            (mergeNatArraySets (nestedLocalArrayGetShapesExpr env a) (nestedLocalArrayGetShapesExpr env b))
            (mergeNatArraySets (nestedLocalArrayGetShapesExpr env c) (nestedLocalArrayGetShapesExpr env d)))
          (nestedLocalArrayGetShapesExpr env e)

    | .checkErc1155BatchReceived a b c d e =>
        #[a, b, c, d, e].foldl (init := #[]) fun acc expr =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env expr)

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
    overflowChecked := module.overflowChecked
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
