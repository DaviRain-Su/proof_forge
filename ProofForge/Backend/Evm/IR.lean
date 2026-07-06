import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Evm.IR.Validate
import ProofForge.Backend.Evm.IR.Expr
import ProofForge.Backend.Evm.IR.Body
import ProofForge.Backend.Evm.Lower
import ProofForge.Backend.Evm.Metadata
import ProofForge.Backend.SharedValidate
import ProofForge.IR.Contract
import ProofForge.IR.Semantics
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Compiler.Yul.AST
import ProofForge.Compiler.Yul.Printer

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

def lowerEntrypointWithPlan
    (module : Module)
    (entrypoint : Entrypoint)
    (entrypointPlan : ProofForge.Backend.Evm.Plan.EntrypointPlan) :
    Except LowerError Lean.Compiler.Yul.Statement := do
  if entrypointPlan.name != entrypoint.name then
    .error {
      message :=
        s!"EVM entrypoint function plan mismatch: expected `{entrypoint.name}`, got `{entrypointPlan.name}`"
    }
  else
    pure ()
  match entrypoint.returns with
  | .unit => pure ()
  | _ =>
      if entrypoint.kind == .fallback || entrypoint.kind == .receive then
        .error { message := s!"entrypoint `{entrypoint.name}` is a fallback/receive and must return unit" }
      else if statementsAlwaysReturn entrypoint.body then
        pure ()
      else
        .error { message := s!"entrypoint `{entrypoint.name}` returns `{entrypoint.returns.name}` but does not return on every control-flow path" }
  validateEntrypointTypes module entrypoint
  let body ←
    match ← lowerEntrypointBodyWithPlan? module entrypoint entrypointPlan with
    | some plannedBody => .ok plannedBody
    | none =>
        lowerStatements module entrypoint.name entrypoint.returns (entrypointTypeEnv entrypoint) false entrypoint.body
  let dynamicParamAliases :=
    entrypointPlan.params.foldl
      (fun acc param =>
        if param.isDynamic then
          acc.push (Lean.Compiler.Yul.Statement.varDecl
            #[({ name := param.name } : Lean.Compiler.Yul.TypedName)]
            (some (Lean.Compiler.Yul.Expr.id (ProofForge.Backend.Evm.ToYul.dynamicParamDataPtrName param.name))))
        else
          acc)
      #[]
  let bodyStatements := dynamicParamAliases ++ body
  -- Fallback/receive functions use a fixed name and have no params/returns
  if entrypoint.kind == .fallback || entrypoint.kind == .receive then
    .ok (ProofForge.Backend.Evm.ToYul.fallbackReceiveFunctionDefinition
           (ProofForge.Backend.Evm.ToYul.fallbackReceiveFunctionName entrypoint.kind)
           bodyStatements)
  else
    .ok (ProofForge.Backend.Evm.ToYul.entrypointFunctionDefinition module.name entrypointPlan bodyStatements)

def lowerEntrypoint (module : Module) (entrypoint : Entrypoint) : Except LowerError Lean.Compiler.Yul.Statement := do
  let entrypointPlan ←
    match ProofForge.Backend.Evm.Lower.buildEntrypointSurfacePlan module entrypoint with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  lowerEntrypointWithPlan module entrypoint entrypointPlan

def entrypointCallExprWithPlan
    (module : Module)
    (entrypoint : Entrypoint)
    (entrypointPlan : ProofForge.Backend.Evm.Plan.EntrypointPlan) :
    Except LowerError Lean.Compiler.Yul.Expr := do
  if entrypointPlan.name != entrypoint.name then
    .error {
      message :=
        s!"EVM entrypoint call plan mismatch: expected `{entrypoint.name}`, got `{entrypointPlan.name}`"
    }
  else
    .ok (ProofForge.Backend.Evm.ToYul.entrypointCallExpr module.name entrypointPlan)

def entrypointCallExpr (module : Module) (entrypoint : Entrypoint) : Except LowerError Lean.Compiler.Yul.Expr := do
  let entrypointPlan ←
    match ProofForge.Backend.Evm.Lower.buildEntrypointSurfacePlan module entrypoint with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  entrypointCallExprWithPlan module entrypoint entrypointPlan

def dispatchReturnStatements
    (_module : Module)
    (entrypoint : Entrypoint)
    (params : Array ProofForge.Backend.Evm.Plan.AbiParamPlan)
    (returns : ProofForge.Backend.Evm.Plan.ReturnPlan)
    (callExpr : Lean.Compiler.Yul.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let validationStmts ← abiParamValidationAndDecodeStmts params
  match entrypoint.returns with
  | .bytes | .string | .array _ =>
      ProofForge.Backend.Evm.ToYul.dynamicDispatchReturnStatements
        toYulError
        validationStmts
        returns
        callExpr
  | _ => do
      ProofForge.Backend.Evm.ToYul.staticDispatchReturnStatements
        toYulError
        validationStmts
        returns
        callExpr

def dispatchCaseWithEntrypointPlan
    (module : Module)
    (entrypoint : Entrypoint)
    (entrypointPlan : ProofForge.Backend.Evm.Plan.EntrypointPlan) :
    Except LowerError Lean.Compiler.Yul.Case := do
  if entrypointPlan.name != entrypoint.name then
    .error {
      message :=
        s!"EVM dispatch plan entrypoint mismatch: expected `{entrypoint.name}`, got `{entrypointPlan.name}`"
    }
  else
    pure ()
  let callExpr ← entrypointCallExprWithPlan module entrypoint entrypointPlan
  let bodyStmts ← dispatchReturnStatements module entrypoint entrypointPlan.params entrypointPlan.returns callExpr
  ProofForge.Backend.Evm.ToYul.entrypointDispatchCase toYulError entrypointPlan bodyStmts

def dispatchCaseWithPlan (module : Module) (entrypoint : Entrypoint) :
    Except LowerError (ProofForge.Backend.Evm.Plan.EntrypointPlan × Lean.Compiler.Yul.Case) := do
  let entrypointPlan ←
    match ProofForge.Backend.Evm.Lower.buildEntrypointSurfacePlan module entrypoint with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let dispatchCase ← dispatchCaseWithEntrypointPlan module entrypoint entrypointPlan
  .ok (entrypointPlan, dispatchCase)

def dispatchCase (module : Module) (entrypoint : Entrypoint) : Except LowerError Lean.Compiler.Yul.Case := do
  .ok (← dispatchCaseWithPlan module entrypoint).snd

def dispatchCasesWithPlan
    (module : Module)
    (dispatch : ProofForge.Backend.Evm.Plan.DispatchPlan) :
    Except LowerError (Array Lean.Compiler.Yul.Case) := do
  let (idx, cases) ← module.entrypoints.foldlM (init := (0, #[])) fun acc entrypoint => do
    let (idx, cases) := acc
    -- Skip fallback/receive entrypoints — they are handled by the default case
    if entrypoint.kind == .fallback || entrypoint.kind == .receive then
      .ok (idx, cases)
    else
      match dispatch.entrypoints[idx]? with
      | some entrypointPlan => do
          let dispatchCase ← dispatchCaseWithEntrypointPlan module entrypoint entrypointPlan
          .ok (idx + 1, cases.push dispatchCase)
      | none =>
          .error {
            message :=
              s!"EVM dispatch plan has fewer entrypoints ({dispatch.entrypoints.size}) than module `{module.name}` ({module.entrypoints.size})"
          }
  if idx != dispatch.entrypoints.size then
    .error {
      message :=
        s!"EVM dispatch plan has {dispatch.entrypoints.size} entrypoints but module `{module.name}` has {module.entrypoints.size}"
    }
  else
    .ok cases

def dispatchBlockWithPlan
    (module : Module)
    (dispatch : ProofForge.Backend.Evm.Plan.DispatchPlan) :
    Except LowerError Lean.Compiler.Yul.Statement := do
  let cases ← dispatchCasesWithPlan module dispatch
  .ok (ProofForge.Backend.Evm.ToYul.dispatchPlanStatement dispatch cases)

def dispatchPlanForModule (module : Module) :
    Except LowerError ProofForge.Backend.Evm.Plan.DispatchPlan := do
  let entrypointPlans ← module.entrypoints.foldlM (init := #[]) fun acc entrypoint => do
    -- Skip fallback/receive entrypoints — they don't have selectors
    if entrypoint.kind == .fallback || entrypoint.kind == .receive then
      .ok acc
    else
      let entrypointPlan ←
        match ProofForge.Backend.Evm.Lower.buildEntrypointSurfacePlan module entrypoint with
        | .ok plan => .ok plan
        | .error err => .error { message := err.message }
      .ok (acc.push entrypointPlan)
  .ok (ProofForge.Backend.Evm.Plan.moduleDispatchPlan module entrypointPlans)

def dispatchBlock (module : Module) : Except LowerError Lean.Compiler.Yul.Statement := do
  let dispatchPlan ← dispatchPlanForModule module
  dispatchBlockWithPlan module dispatchPlan


abbrev CrosscallHelperSpec := ProofForge.Backend.Evm.Plan.CrosscallHelperSpec

def moduleCrosscallHelperSpecs (module : Module) : Except LowerError (Array CrosscallHelperSpec) :=
  lowerValidate (ProofForge.Backend.Evm.Lower.buildCrosscallHelperPlans module)

def crosscallHelperFunctions (_module : Module) (specs : Array CrosscallHelperSpec) : Except LowerError (Array Lean.Compiler.Yul.Statement) :=
  specs.mapM fun spec => ProofForge.Backend.Evm.ToYul.crosscallHelperFunction toYulError spec

abbrev CreateHelperSpec := ProofForge.Backend.Evm.Plan.CreateHelperSpec

def moduleCreateHelperSpecs (module : Module) : Array CreateHelperSpec :=
  ProofForge.Backend.Evm.Lower.buildCreateHelperPlans module

def createHelperFunctions (specs : Array CreateHelperSpec) : Except LowerError (Array Lean.Compiler.Yul.Statement) :=
  specs.mapM fun spec => ProofForge.Backend.Evm.ToYul.createHelperFunction toYulError spec

def moduleLocalArrayGetLengths (module : Module) : Except LowerError (Array Nat) :=
  lowerValidate (ProofForge.Backend.Evm.Lower.buildLocalArrayGetLengths module)

def moduleNestedLocalArrayGetShapes (module : Module) : Except LowerError (Array (Array Nat)) :=
  lowerValidate (ProofForge.Backend.Evm.Lower.buildNestedLocalArrayGetShapes module)

def validateDistinctStructName (seen : Array String) (name : String) : Except LowerError (Array String) :=
  if name.isEmpty then
    .error { message := "struct name must be non-empty for IR EVM v0" }
  else if seen.contains name then
    .error { message := s!"duplicate struct `{name}`" }
  else
    .ok (seen.push name)

def validateDistinctStructFieldName (structName : String) (seen : Array String) (fieldName : String) : Except LowerError (Array String) :=
  if fieldName.isEmpty then
    .error { message := s!"struct `{structName}` field name must be non-empty" }
  else if seen.contains fieldName then
    .error { message := s!"duplicate field `{fieldName}` in struct `{structName}`" }
  else
    .ok (seen.push fieldName)

def validateStructs (module : Module) : Except LowerError Unit := do
  let _ ← module.structs.foldlM (init := #[]) fun seen decl =>
    validateDistinctStructName seen decl.name
  for decl in module.structs do
    if decl.fields.isEmpty then
      .error { message := s!"struct `{decl.name}` must declare at least one field" }
    let _ ← decl.fields.foldlM (init := #[]) fun seen field =>
      validateDistinctStructFieldName decl.name seen field.id
    for field in decl.fields do
      ensureStructLocalFieldType decl.name field.id field.type

def validateStorageStructState (context typeName : String) (module : Module) : Except LowerError Unit := do
  let some decl := findStruct? module typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; EVM IR v0 storage structs must have at least one field" }
  for field in decl.fields do
    ensureStructLocalFieldType decl.name field.id field.type

def validateState (module : Module) : Except LowerError Unit := do
  for state in module.state do
    match state.kind, state.type with
    | .scalar, .u8 => pure ()
    | .scalar, .u32 => pure ()
    | .scalar, .u64 => pure ()
    | .scalar, .u128 => pure ()
    | .scalar, .bool => pure ()
    | .scalar, .hash => pure ()
    | .scalar, .address => pure ()
    | .scalar, .structType typeName =>
        validateStorageStructState s!"state `{state.id}`" typeName module
    | .scalar, other =>
        .error { message := s!"state `{state.id}` has unsupported EVM IR v0 type `{other.name}`" }
    | .map keyType capacity, valueType =>
        if isStorageWordType keyType && isStorageWordType valueType then
          pure ()
        else
          .error {
            message := s!"map state `{state.id}` has unsupported EVM IR v0 type `{mapShapeName keyType valueType capacity}`; storage maps support key/value word types U32, U64, Bool, or Hash"
          }
    | .array 0, _ =>
        .error { message := s!"array state `{state.id}` must have non-zero length" }
    | .array _, .u8 => pure ()
    | .array _, .u32 => pure ()
    | .array _, .u64 => pure ()
    | .array _, .u128 => pure ()
    | .array _, .bool => pure ()
    | .array _, .hash => pure ()
    | .array _, .structType typeName =>
        validateStorageStructState s!"array state `{state.id}`" typeName module
    | .array _, other =>
        .error { message := s!"array state `{state.id}` has unsupported EVM IR v0 element type `{other.name}`; storage arrays support U32, U64, Bool, Hash, or flat struct arrays" }
    | .dynamicArray, elementType =>
        if isStorageWordType elementType then
          pure ()
        else
          .error {
            message :=
              s!"dynamic array state `{state.id}` has unsupported EVM IR v0 element type `{elementType.name}`; " ++
              "dynamic storage arrays support U8, U32, U64, U128, Bool, Hash, or Address"
          }

def validateCapabilities (module : Module) : Except LowerError Unit :=
  match resolveModule Target.evm module with
  | .ok _ => .ok ()
  | .error err => .error (diagnosticError err)

def plannedMapHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  let helpers : Array Lean.Compiler.Yul.Statement := #[]
  let helpers :=
    if plan.hasHelper .mapSlot then
      helpers.push ProofForge.Backend.Evm.ToYul.mapSlotHelperFunction
    else
      helpers
  let helpers :=
    if plan.hasHelper .mapPresenceSlot then
      helpers.push ProofForge.Backend.Evm.ToYul.mapPresenceSlotHelperFunction
    else
      helpers
  let helpers :=
    if plan.hasHelper .mapWrite then
      helpers.push ProofForge.Backend.Evm.ToYul.mapWriteHelperFunction
    else
      helpers
  let helpers :=
    if plan.hasHelper .mapSetReturn then
      helpers.push ProofForge.Backend.Evm.ToYul.mapSetReturnHelperFunction
    else
      helpers
  helpers ++ plan.mapAssignOps.map ProofForge.Backend.Evm.ToYul.mapAssignHelperFunction

def plannedArrayHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  if plan.hasHelper .arraySlot then ProofForge.Backend.Evm.ToYul.arrayHelperFunctions else #[]

def plannedDynamicArrayHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  if plan.hasHelper .dynamicArraySlot then ProofForge.Backend.Evm.ToYul.dynamicArrayHelperFunctions else #[]

def plannedStructArrayHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  if plan.hasHelper .structArraySlot then ProofForge.Backend.Evm.ToYul.structArrayHelperFunctions else #[]

def plannedHashHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  let helpers : Array Lean.Compiler.Yul.Statement := #[]
  let helpers :=
    if plan.hasHelper .hashWord then
      helpers.push ProofForge.Backend.Evm.ToYul.hashWordHelperFunction
    else
      helpers
  if plan.hasHelper .hashPair then
    helpers.push ProofForge.Backend.Evm.ToYul.hashPairHelperFunction
  else
    helpers

def plannedMemoryArrayHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  let helpers : Array Lean.Compiler.Yul.Statement := #[]
  let helpers :=
    if plan.hasHelper .memoryArrayNew then
      helpers.push ProofForge.Backend.Evm.ToYul.memoryArrayNewHelperFunction
    else
      helpers
  if plan.hasHelper .memoryArrayGet then
    helpers.push ProofForge.Backend.Evm.ToYul.memoryArrayGetHelperFunction
  else
    helpers

/-! Detect whether a module uses any `.add`/`.sub`/`.mul` `Expr` or compound
    assignment op that would route to the checked-arithmetic helpers. Used to
    avoid emitting the helpers when a module only uses div/mod/bitwise/shift. -/
mutual
  partial def effectUsesCheckedArithmetic : Effect → Bool
    | .storageScalarWrite _ v => exprUsesCheckedArithmetic v
    | .storageScalarAssignOp _ op v =>
        ProofForge.Backend.Evm.Validate.needsCheckedArithmetic op || exprUsesCheckedArithmetic v
    | .storageMapInsert _ _ v => exprUsesCheckedArithmetic v
    | .storageMapSet _ _ v => exprUsesCheckedArithmetic v
    | .storageArrayWrite _ _ v => exprUsesCheckedArithmetic v
    | .storageArrayStructFieldWrite _ _ _ v => exprUsesCheckedArithmetic v
    | .storageDynamicArrayPush _ v => exprUsesCheckedArithmetic v
    | .storageDynamicArrayPop _ => false
    | .memoryArraySet _ i v => exprUsesCheckedArithmetic i || exprUsesCheckedArithmetic v
    | .storageStructFieldWrite _ _ v => exprUsesCheckedArithmetic v
    | .storagePathWrite _ _ v => exprUsesCheckedArithmetic v
    | .storagePathAssignOp _ _ op v =>
        ProofForge.Backend.Evm.Validate.needsCheckedArithmetic op || exprUsesCheckedArithmetic v
    | .storageScalarRead _ | .storageMapContains _ _ | .storageMapGet _ _
    | .storageArrayRead _ _ | .storageArrayStructFieldRead _ _ _
    | .storageStructFieldRead _ _ | .storagePathRead _ _
    | .contextRead _ | .eventEmit _ _ | .eventEmitIndexed _ _ _ => false

  partial def exprUsesCheckedArithmetic : Expr → Bool
    | .add _ _ | .sub _ _ | .mul _ _ => true
    | .literal _ | .local _ | .nativeValue => false
    | .arrayLit _ xs => xs.any exprUsesCheckedArithmetic
    | .arrayGet a i => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic i
    | .memoryArrayNew _ l => exprUsesCheckedArithmetic l
    | .memoryArrayLength a => exprUsesCheckedArithmetic a
    | .memoryArrayGet a i => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic i
    | .structLit _ fs => fs.any (fun (_, v) => exprUsesCheckedArithmetic v)
    | .field b _ => exprUsesCheckedArithmetic b
    | .div l r | .mod l r | .pow l r
    | .bitAnd l r | .bitOr l r | .bitXor l r
    | .shiftLeft l r | .shiftRight l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .cast v _ => exprUsesCheckedArithmetic v
    | .eq l r | .ne l r | .lt l r | .le l r | .gt l r | .ge l r
    | .boolAnd l r | .boolOr l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .boolNot v => exprUsesCheckedArithmetic v
    | .hashValue a b c d => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic b
        || exprUsesCheckedArithmetic c || exprUsesCheckedArithmetic d
    | .hash p => exprUsesCheckedArithmetic p
    | .hashTwoToOne l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .crosscallInvoke t m args | .crosscallInvokeTyped t m args _
    | .crosscallInvokeValueTyped t m _ args _
    | .crosscallInvokeStaticTyped t m args _ | .crosscallInvokeDelegateTyped t m args _ =>
        exprUsesCheckedArithmetic t || exprUsesCheckedArithmetic m || args.any exprUsesCheckedArithmetic
    | .crosscallCreate v _ => exprUsesCheckedArithmetic v
    | .crosscallCreate2 v s _ => exprUsesCheckedArithmetic v || exprUsesCheckedArithmetic s
    | .nearPromiseThen p m args d =>
        exprUsesCheckedArithmetic p || exprUsesCheckedArithmetic m || exprUsesCheckedArithmetic d ||
          args.any exprUsesCheckedArithmetic
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        exprUsesCheckedArithmetic accountIndex || exprUsesCheckedArithmetic methodId ||
          exprUsesCheckedArithmetic deposit || args.any exprUsesCheckedArithmetic
    | .nearPromiseResultsCount => false
    | .nearPromiseResultStatus i => exprUsesCheckedArithmetic i
    | .nearPromiseResultU64 i => exprUsesCheckedArithmetic i
    | .effect e => effectUsesCheckedArithmetic e

  partial def stmtUsesCheckedArithmetic : Statement → Bool
    | .letBind _ _ v | .letMutBind _ _ v | .assign _ v | .assignOp _ _ v | .return v =>
        exprUsesCheckedArithmetic v
    | .assert _ _ _ | .assertEq _ _ _ _ | .release _ | .revert _ | .revertWithError _ => false
    | .effect e => effectUsesCheckedArithmetic e
    | .ifElse c thenBody elseBody =>
        exprUsesCheckedArithmetic c || thenBody.any stmtUsesCheckedArithmetic
          || elseBody.any stmtUsesCheckedArithmetic
    | .boundedFor _ _ _ body => body.any stmtUsesCheckedArithmetic
    | .whileLoop c body => exprUsesCheckedArithmetic c || body.any stmtUsesCheckedArithmetic
end

def moduleUsesCheckedArithmetic (module : Module) : Bool :=
  module.entrypoints.any (fun ep => ep.body.any stmtUsesCheckedArithmetic)

def plannedCheckedArithmeticHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  if plan.usesCheckedArithmetic then ProofForge.Backend.Evm.ToYul.checkedArithmeticHelperFunctions else #[]

def plannedCrosscallHelperFunctions
    (specs : Array ProofForge.Backend.Evm.Plan.CrosscallHelperSpec) :
    Except LowerError (Array Lean.Compiler.Yul.Statement) :=
  specs.mapM fun spec => ProofForge.Backend.Evm.ToYul.crosscallHelperFunction toYulError spec

def plannedCreateHelperFunctions
    (specs : Array ProofForge.Backend.Evm.Plan.CreateHelperSpec) :
    Except LowerError (Array Lean.Compiler.Yul.Statement) :=
  specs.mapM fun spec => ProofForge.Backend.Evm.ToYul.createHelperFunction toYulError spec

def lowerEntrypointsWithPlan
    (module : Module)
    (entrypoints : Array ProofForge.Backend.Evm.Plan.EntrypointPlan) :
    Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let (idx, functions) ← module.entrypoints.foldlM (init := (0, #[])) fun acc entrypoint => do
    let (idx, functions) := acc
    match entrypoints[idx]? with
    | some entrypointPlan => do
        let function ← lowerEntrypointWithPlan module entrypoint entrypointPlan
        .ok (idx + 1, functions.push function)
    | none =>
        .error {
          message :=
            s!"EVM entrypoint plan has fewer entrypoints ({entrypoints.size}) than module `{module.name}` ({module.entrypoints.size})"
        }
  if idx != entrypoints.size then
    .error {
      message :=
        s!"EVM entrypoint plan has {entrypoints.size} entrypoints but module `{module.name}` has {module.entrypoints.size}"
    }
  else
    .ok functions

def entrypointBodyPlanIsComplete
    (module : Module)
    (entrypoints : Array ProofForge.Backend.Evm.Plan.EntrypointPlan) : Bool :=
  entrypoints.size == module.entrypoints.size

def dispatchEntrypointPlanIsComplete
    (module : Module)
    (entrypoints : Array ProofForge.Backend.Evm.Plan.EntrypointPlan) : Bool :=
  -- Only function entrypoints (not fallback/receive) need dispatch plans
  let functionCount := module.entrypoints.foldl (init := 0) fun acc ep =>
    if ep.kind == .fallback || ep.kind == .receive then acc else acc + 1
  entrypoints.size == functionCount

def lowerEntrypointsBestEffort
    (module : Module)
    (entrypoints : Array ProofForge.Backend.Evm.Plan.EntrypointPlan) :
    Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  if entrypointBodyPlanIsComplete module entrypoints then
    lowerEntrypointsWithPlan module entrypoints
  else
    module.entrypoints.foldlM (init := #[]) fun acc entrypoint => do
      .ok (acc.push (← lowerEntrypoint module entrypoint))

def lowerModuleWithPlan
    (module : Module)
    (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Except LowerError Lean.Compiler.Yul.Object := do
  validateStructs module
  validateState module
  let functions ← lowerEntrypointsBestEffort module plan.entrypoints
  let dispatch ←
    if dispatchEntrypointPlanIsComplete module plan.dispatch.entrypoints then
      dispatchBlockWithPlan module plan.dispatch
    else
      dispatchBlock module
  let helpers := plannedMapHelperFunctions plan
  let helpers := helpers ++ plannedArrayHelperFunctions plan
  let helpers := helpers ++ plannedDynamicArrayHelperFunctions plan
  let helpers := helpers ++ plannedStructArrayHelperFunctions plan
  let helpers := helpers ++ plannedHashHelperFunctions plan
  let helpers := helpers ++ plannedMemoryArrayHelperFunctions plan
  let completePlan := entrypointBodyPlanIsComplete module plan.entrypoints
  let helpers :=
    if completePlan then
      helpers ++ plannedCheckedArithmeticHelperFunctions plan
    else
      helpers ++
        (if ProofForge.Backend.Evm.Validate.moduleUsesCheckedArithmetic module then
          ProofForge.Backend.Evm.ToYul.checkedArithmeticHelperFunctions
        else
          #[])
  let helpers ←
    if completePlan then
      .ok (helpers ++ (← plannedCrosscallHelperFunctions plan.crosscalls))
    else
      let crosscallSpecs ← lowerValidate (ProofForge.Backend.Evm.Lower.buildCrosscallHelperPlans module)
      .ok (helpers ++ (← plannedCrosscallHelperFunctions crosscallSpecs))
  let helpers ←
    if completePlan then
      .ok (helpers ++ (← plannedCreateHelperFunctions plan.creates))
    else
      let createSpecs := ProofForge.Backend.Evm.Lower.buildCreateHelperPlans module
      .ok (helpers ++ (← plannedCreateHelperFunctions createSpecs))
  let helpers ←
    if completePlan then
      .ok (helpers ++ ProofForge.Backend.Evm.ToYul.localArrayGetHelperFunctions plan.localArrayGetLengths)
    else
      let localArrayGetLengths ← lowerValidate (ProofForge.Backend.Evm.Lower.buildLocalArrayGetLengths module)
      .ok (helpers ++ ProofForge.Backend.Evm.ToYul.localArrayGetHelperFunctions localArrayGetLengths)
  let helpers ←
    if completePlan then
      .ok (helpers ++ ProofForge.Backend.Evm.ToYul.nestedLocalArrayGetHelperFunctions plan.nestedLocalArrayGetShapes)
    else
      let nestedLocalArrayGetShapes ← lowerValidate (ProofForge.Backend.Evm.Lower.buildNestedLocalArrayGetShapes module)
      .ok (helpers ++ ProofForge.Backend.Evm.ToYul.nestedLocalArrayGetHelperFunctions nestedLocalArrayGetShapes)
  .ok {
    name := module.name
    code := { statements := #[dispatch] ++ functions ++ helpers }
  }

/-- Build the full EVM semantic plan for `module` before lowering to Yul.

The plan is constructed by `Lower.buildFullModulePlan`, which populates
`EntrypointPlan` nodes (selector, ABI params, return shape), `EventPlan` nodes
(signature, field layout), and `MetadataPlan`. Helper specs (crosscall, create,
local-array-get, nested-local-array-get) and the checked-arithmetic flag are
discovered from the IR and recorded on the plan so `ToYul` and metadata passes
can consume them without re-discovering facts from rendered Yul. -/

def buildSemanticPlan (module : Module) : Except LowerError ProofForge.Backend.Evm.Plan.ModulePlan := do
  match ProofForge.Backend.Evm.Lower.buildFullModulePlan module with
  | .ok plan => .ok plan
  | .error err => .error { message := err.message }

/-- Build the semantic plan best-effort, catching plan-construction errors so
    diagnostic smokes that intentionally feed unsupported shapes still render
    the expected diagnostic message rather than aborting at plan time. -/

def buildSemanticPlanBestEffort (module : Module) : ProofForge.Backend.Evm.Plan.ModulePlan :=
  match buildSemanticPlan module with
  | .ok plan => plan
  | .error _ =>
    match ProofForge.Backend.Evm.Plan.buildModulePlan module with
    | .ok plan => plan
    | .error _ => {
      name := module.name
      targetPlan := { targetId := Target.evm.id, calls := #[] }
      storage := ProofForge.Backend.Evm.Plan.storageLayout module
      helpers := #[]
      mapAssignOps := #[]
      entrypoints := #[]
      dispatch := ProofForge.Backend.Evm.Plan.moduleDispatchPlan module #[]
      events := #[]
      crosscalls := #[]
      creates := #[]
      localArrayGetLengths := #[]
      nestedLocalArrayGetShapes := #[]
      usesCheckedArithmetic := false
      metadata := {
        moduleName := module.name
        entrypoints := #[]
        events := #[]
        capabilities := #[]
      }
      contextOps := ProofForge.Backend.Evm.Plan.contextOpsFromModule module
    }

def lowerModuleBestEffort (module : Module) : Except LowerError Lean.Compiler.Yul.Object := do
  let fullPlan := buildSemanticPlanBestEffort module
  lowerModuleWithPlan module fullPlan

def renderModuleBestEffort (module : Module) : Except LowerError String := do
  .ok (Lean.Compiler.Yul.Printer.render (← lowerModuleBestEffort module))

def lowerModule (module : Module) : Except LowerError Lean.Compiler.Yul.Object := do
  let fullPlan ← buildSemanticPlan module
  lowerModuleWithPlan module fullPlan

def renderModule (module : Module) : Except LowerError String := do
  .ok (Lean.Compiler.Yul.Printer.render (← lowerModule module))

/-- Render the EVM semantic plan for inspection without producing Yul. -/

def renderSemanticPlan (module : Module) : Except LowerError String := do
  let plan ← buildSemanticPlan module
  let mut parts : Array String := #[]
  parts := parts.push s!"module: {plan.name}"
  parts := parts.push s!"target: {plan.targetPlan.targetId}"
  let capIds := plan.capabilities.map (·.id)
  parts := parts.push s!"capabilities: {String.intercalate ", " capIds.toList}"
  parts := parts.push "storage:"
  for state in plan.storage.states do
    parts := parts.push s!"  {state.id}: slot {state.slot}, span {state.span}"
  parts := parts.push "entrypoints:"
  for ep in plan.entrypoints do
    parts := parts.push s!"  {ep.name}: selector 0x{ep.selector}, {ep.params.size} param(s), returns {ep.returns.returnType.name}"
  parts := parts.push "events:"
  for ev in plan.events do
    parts := parts.push s!"  {ev.name}: {ev.signature}, {ev.fields.size} field(s)"
  parts := parts.push s!"crosscalls: {plan.crosscalls.size}"
  parts := parts.push s!"creates: {plan.creates.size}"
  parts := parts.push s!"localArrayGetLengths: {plan.localArrayGetLengths}"
  parts := parts.push s!"usesCheckedArithmetic: {plan.usesCheckedArithmetic}"
  let helperNames := plan.helpers.map ProofForge.Backend.Evm.Plan.Helper.name
  parts := parts.push s!"helpers: {String.intercalate ", " helperNames.toList}"
  .ok (String.intercalate "\n" parts.toList)

/-- Build artifact metadata from the semantic plan (RFC 0004 Metadata pass). -/

def buildPlanArtifactMetadata (module : Module) : Except LowerError ProofForge.Backend.Evm.Metadata.ArtifactMetadata := do
  let plan ← buildSemanticPlan module
  .ok (ProofForge.Backend.Evm.Metadata.buildArtifactMetadata plan)

/-- Build deploy metadata from the semantic plan (RFC 0004 Metadata pass). -/

def buildPlanDeployMetadata (module : Module) : Except LowerError ProofForge.Backend.Evm.Metadata.DeployMetadata := do
  let plan ← buildSemanticPlan module
  .ok (ProofForge.Backend.Evm.Metadata.buildDeployMetadata plan)

end ProofForge.Backend.Evm.IR
