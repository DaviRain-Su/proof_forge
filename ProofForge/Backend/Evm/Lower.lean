import ProofForge.Backend.Evm.Plan
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

/-! ## Entrypoint plan construction -/

def abiParamPlan
    (module : Module)
    (context : String)
    (name : String)
    (type : ValueType) : Except LowerError AbiParamPlan := do
  let wordTypes ← abiValueWordTypes module s!"{context} parameter `{name}`" type
  .ok { name, type, wordTypes }

def entrypointParamPlans (module : Module) (entrypoint : Entrypoint) :
    Except LowerError (Array AbiParamPlan) :=
  entrypoint.params.foldlM (init := #[]) fun acc param => do
    .ok (acc.push (← abiParamPlan module s!"entrypoint `{entrypoint.name}`" param.fst param.snd))

def returnPlan (module : Module) (context : String) (returnType : ValueType) :
    Except LowerError ReturnPlan := do
  let wordTypes ←
    match returnType with
    | .unit => .ok #[]
    | _ => abiValueWordTypes module s!"{context} return value" returnType
  .ok { returnType, wordTypes }

def entrypointSelector (entrypoint : Entrypoint) : Except LowerError String :=
  match entrypoint.selector? with
  | some selector => .ok selector
  | none => .error { message := s!"entrypoint `{entrypoint.name}` has no EVM selector metadata" }

/-! Entrypoint body plans carry structural `StmtPlan` / `ExprPlan` nodes.

`IR.lean` remains the compatibility facade that assembles final Yul today, but
the semantic plan now owns a target-validated statement/expression view of each
entrypoint body. Later migration slices can consume these plan nodes directly
instead of re-walking the portable IR at Yul assembly time. -/

def literalPlan : Literal → Except LowerError ExprPlan
  | .u32 value => .ok (.literalWord value)
  | .u64 value => .ok (.literalWord value)
  | .bool value => .ok (.literalWord (if value then 1 else 0))
  | .hash4 a b c d => do
      .ok (.literalWord (← packedHashLiteral a b c d))
  | .address value => .ok (.literalWord value)

def eventPlanForFields
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (indexedFields dataFields : Array (String × Expr)) :
    Except LowerError EventPlan := do
  validateIndexedEventFieldCount name indexedFields.size
  let fields := indexedFields ++ dataFields
  let signature ← eventSignature module env name fields
  let mut fieldPlans : Array EventFieldPlan := #[]
  for field in indexedFields do
    let fieldType ← inferEventFieldExprType module env field.snd
    fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType true)
  for field in dataFields do
    let fieldType ← inferEventFieldExprType module env field.snd
    fieldPlans := fieldPlans.push (EventFieldPlan.mk field.fst fieldType false)
  .ok (EventPlan.mk name signature fieldPlans)

def assignExprPlan (op : AssignOp) (lhs rhs : ExprPlan) : ExprPlan :=
  .checkedArith op lhs rhs

mutual
  partial def buildExprPlan (module : Module) (env : TypeEnv) : Expr → Except LowerError ExprPlan
    | .literal value => literalPlan value
    | .local name => .ok (.local name)
    | .arrayLit elementType values => do
        let planned ← values.mapM (buildExprPlan module env)
        .ok (.arrayLit elementType planned)
    | .arrayGet array index => do
        .ok (.arrayGet (← buildExprPlan module env array) (← buildExprPlan module env index))
    | .structLit typeName fields => do
        let mut planned : Array (String × ExprPlan) := #[]
        for field in fields do
          planned := planned.push (field.fst, ← buildExprPlan module env field.snd)
        .ok (.structLit typeName planned)
    | .field base fieldName => do
        .ok (.structField (← buildExprPlan module env base) fieldName)
    | .add lhs rhs => do
        .ok (assignExprPlan .add (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .sub lhs rhs => do
        .ok (assignExprPlan .sub (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .mul lhs rhs => do
        .ok (assignExprPlan .mul (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .div lhs rhs => do
        .ok (assignExprPlan .div (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .mod lhs rhs => do
        .ok (assignExprPlan .mod (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .pow lhs rhs => do
        .ok (.builtin "exp" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .bitAnd lhs rhs => do
        .ok (assignExprPlan .bitAnd (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .bitOr lhs rhs => do
        .ok (assignExprPlan .bitOr (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .bitXor lhs rhs => do
        .ok (assignExprPlan .bitXor (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .shiftLeft lhs rhs => do
        .ok (assignExprPlan .shiftLeft (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .shiftRight lhs rhs => do
        .ok (assignExprPlan .shiftRight (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .cast value targetType => do
        .ok (.cast (← buildExprPlan module env value) targetType)
    | .eq lhs rhs => do
        .ok (.builtin "eq" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .ne lhs rhs => do
        .ok (.builtin "iszero" #[.builtin "eq" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs]])
    | .lt lhs rhs => do
        .ok (.builtin "lt" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .le lhs rhs => do
        .ok (.builtin "iszero" #[.builtin "gt" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs]])
    | .gt lhs rhs => do
        .ok (.builtin "gt" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .ge lhs rhs => do
        .ok (.builtin "iszero" #[.builtin "lt" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs]])
    | .boolAnd lhs rhs => do
        .ok (.builtin "and" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .boolOr lhs rhs => do
        .ok (.builtin "or" #[← buildExprPlan module env lhs, ← buildExprPlan module env rhs])
    | .boolNot value => do
        .ok (.builtin "iszero" #[← buildExprPlan module env value])
    | .hashValue a b c d => do
        .ok (.hashValue
          (← buildExprPlan module env a)
          (← buildExprPlan module env b)
          (← buildExprPlan module env c)
          (← buildExprPlan module env d))
    | .hash preimage => do
        .ok (.hash (← buildExprPlan module env preimage))
    | .hashTwoToOne lhs rhs => do
        .ok (.hashTwoToOne (← buildExprPlan module env lhs) (← buildExprPlan module env rhs))
    | .nativeValue =>
        .ok .nativeValue
    | .crosscallInvoke target methodId args => do
        .ok (.crosscall .call
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          none
          (← args.mapM (buildExprPlan module env))
          .u64)
    | .crosscallInvokeTyped target methodId args returnType => do
        .ok (.crosscall .call
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          none
          (← args.mapM (buildExprPlan module env))
          returnType)
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        .ok (.crosscall .callValue
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          (some (← buildExprPlan module env callValue))
          (← args.mapM (buildExprPlan module env))
          returnType)
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        .ok (.crosscall .staticcall
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          none
          (← args.mapM (buildExprPlan module env))
          returnType)
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        .ok (.crosscall .delegatecall
          (← buildExprPlan module env target)
          (← buildExprPlan module env methodId)
          none
          (← args.mapM (buildExprPlan module env))
          returnType)
    | .crosscallCreate callValue initCodeHex => do
        .ok (.create .create (← buildExprPlan module env callValue) none initCodeHex)
    | .crosscallCreate2 callValue salt initCodeHex => do
        .ok (.create .create2
          (← buildExprPlan module env callValue)
          (some (← buildExprPlan module env salt))
          initCodeHex)
    | .effect effect => do
        .ok (.effect (← buildEffectPlan module env effect))

  partial def buildEffectPlan (module : Module) (env : TypeEnv) : Effect → Except LowerError EffectPlan
    | .storageScalarRead stateId =>
        .ok (.storageScalarRead stateId)
    | .storageScalarWrite stateId value => do
        .ok (.storageScalarWrite stateId (← buildExprPlan module env value))
    | .storageScalarAssignOp stateId op value => do
        .ok (.storageScalarAssignOp stateId op (← buildExprPlan module env value))
    | .storageMapContains stateId key => do
        .ok (.storageMapContains stateId (← buildExprPlan module env key))
    | .storageMapGet stateId key => do
        .ok (.storageMapGet stateId (← buildExprPlan module env key))
    | .storageMapInsert stateId key value => do
        .ok (.storageMapInsert stateId (← buildExprPlan module env key) (← buildExprPlan module env value))
    | .storageMapSet stateId key value => do
        .ok (.storageMapSet stateId (← buildExprPlan module env key) (← buildExprPlan module env value))
    | .storageArrayRead stateId index => do
        .ok (.storageArrayRead stateId (← buildExprPlan module env index))
    | .storageArrayWrite stateId index value => do
        .ok (.storageArrayWrite stateId (← buildExprPlan module env index) (← buildExprPlan module env value))
    | .storageArrayStructFieldRead stateId index fieldName => do
        .ok (.storageArrayStructFieldRead stateId (← buildExprPlan module env index) fieldName)
    | .storageArrayStructFieldWrite stateId index fieldName value => do
        .ok (.storageArrayStructFieldWrite stateId (← buildExprPlan module env index) fieldName (← buildExprPlan module env value))
    | .storageStructFieldRead stateId fieldName =>
        .ok (.storageStructFieldRead stateId fieldName)
    | .storageStructFieldWrite stateId fieldName value => do
        .ok (.storageStructFieldWrite stateId fieldName (← buildExprPlan module env value))
    | .storagePathRead stateId path =>
        .ok (.storagePathRead stateId path)
    | .storagePathWrite stateId path value => do
        .ok (.storagePathWrite stateId path (← buildExprPlan module env value))
    | .storagePathAssignOp stateId path op value => do
        .ok (.storagePathAssignOp stateId path op (← buildExprPlan module env value))
    | .contextRead field =>
        .ok (.contextRead field)
    | .eventEmit name fields => do
        let eventPlan ← eventPlanForFields module env name #[] fields
        let plannedFields ← fields.mapM fun field => buildExprPlan module env field.snd
        .ok (.eventEmit eventPlan plannedFields)
    | .eventEmitIndexed name indexedFields dataFields => do
        let eventPlan ← eventPlanForFields module env name indexedFields dataFields
        let plannedIndexed ← indexedFields.mapM fun field => buildExprPlan module env field.snd
        let plannedData ← dataFields.mapM fun field => buildExprPlan module env field.snd
        .ok (.eventEmitIndexed eventPlan plannedIndexed plannedData)

  partial def buildStatementPlan
      (module : Module)
      (entrypoint : Entrypoint)
      (env : TypeEnv) :
      Statement → Except LowerError (StmtPlan × TypeEnv)
    | .letBind name type value => do
        ensureType s!"let binding `{name}`" type (← inferExprType module env value)
        let valuePlan ← buildExprPlan module env value
        let nextEnv ← addLocal env name type false
        .ok (.letBind name type valuePlan, nextEnv)
    | .letMutBind name type value => do
        ensureType s!"mutable let binding `{name}`" type (← inferExprType module env value)
        let valuePlan ← buildExprPlan module env value
        let nextEnv ← addLocal env name type true
        .ok (.letMutBind name type valuePlan, nextEnv)
    | .assign target value => do
        let targetPlan ← buildExprPlan module env target
        let valuePlan ← buildExprPlan module env value
        .ok (.assign targetPlan valuePlan, env)
    | .assignOp target op value => do
        let targetPlan ← buildExprPlan module env target
        let valuePlan ← buildExprPlan module env value
        .ok (.assignOp targetPlan op valuePlan, env)
    | .effect effect => do
        .ok (.effect (← buildEffectPlan module env effect), env)
    | .assert condition message errorRef? => do
        ensureType "assert condition" .bool (← inferExprType module env condition)
        .ok (.assert (← buildExprPlan module env condition) message errorRef?, env)
    | .assertEq lhs rhs message errorRef? => do
        let lhsType ← inferExprType module env lhs
        ensureType "assert_eq right operand" lhsType (← inferExprType module env rhs)
        ensureEqType "assert_eq" lhsType
        .ok (.assertEq (← buildExprPlan module env lhs) (← buildExprPlan module env rhs) message errorRef?, env)
    | .release name =>
        .ok (.release name, env)
    | .ifElse condition thenBody elseBody => do
        ensureType "if condition" .bool (← inferExprType module env condition)
        let (thenPlans, _) ← buildStatementPlans module entrypoint env thenBody
        let (elsePlans, _) ← buildStatementPlans module entrypoint env elseBody
        .ok (.ifElse (← buildExprPlan module env condition) thenPlans elsePlans, env)
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let loopEnv ← addLocal env indexName .u32 false
        let (bodyPlans, _) ← buildStatementPlans module entrypoint loopEnv body
        .ok (.boundedFor indexName start stopExclusive bodyPlans, env)
    | .return value => do
        ensureType "return value" entrypoint.returns (← inferExprType module env value)
        .ok (.return (← buildExprPlan module env value), env)

  partial def buildStatementPlans
      (module : Module)
      (entrypoint : Entrypoint)
      (env : TypeEnv)
      (statements : Array Statement) :
      Except LowerError (Array StmtPlan × TypeEnv) := do
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (plans, currentEnv) := acc
      let (stmtPlan, nextEnv) ← buildStatementPlan module entrypoint currentEnv stmt
      .ok (plans.push stmtPlan, nextEnv)
end

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
        | .release _ => pure ()
        | .ifElse condition thenBody elseBody => do
            acc ← collectEventPlansFromExpr module current acc condition
            acc ← collectEventPlansFromStatements module current acc thenBody
            acc ← collectEventPlansFromStatements module current acc elseBody
        | .boundedFor indexName _ _ body => do
            let loopEnv ← addLocal current indexName .u32 false
            acc ← collectEventPlansFromStatements module loopEnv acc body
        | .return value => do
            acc ← collectEventPlansFromExpr module current acc value
      pure acc
end

def buildEventPlans (module : Module) : Except LowerError (Array EventPlan) := do
  let mut collector : EventCollector := {}
  for entrypoint in module.entrypoints do
    collector ← collectEventPlansFromStatements module (entrypointTypeEnv entrypoint) collector entrypoint.body
  .ok collector.plans

/-! ## Module plan assembly -/

def buildFullModulePlan (module : Module) : Except LowerError ModulePlan := do
  let basePlan ←
    match buildModulePlan module with
    | .ok plan => .ok plan
    | .error err => .error (planError err)
  let entrypointPlans ← buildEntrypointPlans module
  let eventPlans ← buildEventPlans module
  let metadata := {
    moduleName := module.name
    entrypoints := entrypointPlans
    events := eventPlans
    capabilities := basePlan.targetPlan.capabilities
  }
  .ok { basePlan with
    entrypoints := entrypointPlans
    events := eventPlans
    metadata := metadata
  }

def buildFullModulePlanWithTargetPlan
    (module : Module)
    (targetPlan : CapabilityPlan) :
    Except LowerError ModulePlan := do
  let basePlan ←
    match buildModulePlanWithTargetPlan module targetPlan with
    | .ok plan => .ok plan
    | .error err => .error (planError err)
  let entrypointPlans ← buildEntrypointPlans module
  let eventPlans ← buildEventPlans module
  let metadata := {
    moduleName := module.name
    entrypoints := entrypointPlans
    events := eventPlans
    capabilities := basePlan.targetPlan.capabilities
  }
  .ok { basePlan with
    entrypoints := entrypointPlans
    events := eventPlans
    metadata := metadata
  }

end ProofForge.Backend.Evm.Lower
