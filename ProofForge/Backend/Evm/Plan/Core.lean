import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.Evm.Plan
import ProofForge.Target.HostOps.Evm
import ProofForge.Target.InterfaceOps.Evm
import ProofForge.Backend.Evm.Plan.Storage
import ProofForge.Target.Plan
import ProofForge.Target.ProtocolMaterialize

/-! # Build Existing EVM Plan from Canonical Core

This module maps a `CheckedCanonicalContract` to the existing EVM `ModulePlan`.
It does not create a parallel plan type — it reuses `Evm.Plan.ModulePlan`,
`ExprPlan`, `EffectPlan`, and `StmtPlan` directly.

The Core builder must not consume `IR.Expr`, `IR.Effect`, `IR.Statement`, or
`IR.Module`. All input is typed Core ANF/CFG.
-/

namespace ProofForge.Backend.Evm.Plan.Core

open ProofForge.IR.Core
open ProofForge.IR
open ProofForge.IR.Canonical
open ProofForge.Target
open ProofForge.Backend.Evm.Plan

/-- Map a Core type to an EVM ValueType. -/
def coreTypeToValueType : CoreType → ValueType
  | .unit => .unit
  | .bool => .bool
  | .u8 => .u8
  | .u32 => .u32
  | .u64 => .u64
  | .u128 => .u128
  | .address => .address
  | .bytes => .bytes
  | .string => .string
  | .hash => .hash
  | .fixedArray elem len => .fixedArray (coreTypeToValueType elem) len
  | .array elem => .array (coreTypeToValueType elem)
  | .memoryRef elem => .array (coreTypeToValueType elem)
  | .structType tid => .structType (toString tid.value)

/-- Infer the EVM ValueType from a Core literal. -/
def coreLiteralType : CoreLiteral → ValueType
  | .unitLit => .unit
  | .boolLit _ => .bool
  | .u8Lit _ => .u8
  | .u32Lit _ => .u32
  | .u64Lit _ => .u64
  | .u128Lit _ => .u128
  | .addressLit _ => .address
  | .bytesLit _ => .bytes
  | .stringLit _ => .string
  | .hashLit _ => .hash

/-- Map a Core literal to an EVM expression. Dynamic and identity literals
must not be replaced with zero while their target representation is pending. -/
def coreLiteralToExprPlan : CoreLiteral → Except PlanError ExprPlan
  | .unitLit => .ok (.literalWord 0)
  | .boolLit b => .ok (.literalWord (if b then 1 else 0))
  | .u8Lit n => .ok (.literalWord n)
  | .u32Lit n => .ok (.literalWord n)
  | .u64Lit n => .ok (.literalWord n)
  | .u128Lit n => .ok (.literalWord n)
  | .addressLit value =>
      match value.toNat? with
      | some word => .ok (.literalWord word)
      | none => .error { message := "non-numeric address literals are not yet materialized by the EVM Core plan" }
  | .bytesLit _ => .error { message := "bytes literals are not yet materialized by the EVM Core plan" }
  | .stringLit value =>
      match value.toNat? with
      | some word => .ok (.literalWord word)
      | none => .error { message := "non-numeric string literals are not yet materialized by the EVM Core plan" }
  | .hashLit value =>
      match value.toNat? with
      | some word => .ok (.literalWord word)
      | none => .error { message := "non-numeric hash literals are not yet materialized by the EVM Core plan" }

private def coreLiteralPlanType : CoreLiteral → Except PlanError ValueType
  | .stringLit value =>
      if value.toNat?.isSome then .ok .u64
      else .error { message := "non-numeric string literals are not yet materialized by the EVM Core plan" }
  | literal => .ok (coreLiteralType literal)

/-- Map a Core arithmetic op to the EVM assign op. -/
def coreArithToAssignOp : ArithmeticOp → AssignOp
  | .add => .add
  | .sub => .sub
  | .mul => .mul
  | .div => .div
  | .mod => .mod
  | .and => .bitAnd
  | .or => .bitOr
  | .xor => .bitXor
  | .shl => .shiftLeft
  | .shr => .shiftRight

private def coreNarrowArithmeticPlan
    (op : ArithmeticOp)
    (mode : OverflowMode)
    (type : CoreType)
    (lhs rhs : ExprPlan) : Except PlanError ExprPlan := do
  let assignOp := coreArithToAssignOp op
  let byteWidth := (coreTypeToValueType type).byteWidth
  if byteWidth == 0 then
    throw { message := "EVM Core arithmetic has no scalar result width" }
  if byteWidth >= 32 then
    return .checkedArith assignOp lhs rhs (mode == .checked) none
  let mask := ExprPlan.literalWord ((2 ^ (byteWidth * 8)) - 1)
  match op with
  | .add | .sub | .mul =>
      if mode == .checked then
        let bound (value : ExprPlan) := ExprPlan.helperCall .checkedWidth #[value, mask]
        return bound (.checkedArith assignOp (bound lhs) (bound rhs) true none)
      else
        return .builtin "and" #[.checkedArith assignOp lhs rhs false none, mask]
  | .shl =>
      throw { message := "narrow shift-left arithmetic is not yet materialized by the EVM Core plan" }
  | .div | .mod | .and | .or | .xor | .shr =>
      return .checkedArith assignOp lhs rhs (mode == .checked) none

/-- Map a Core compare op to the EVM builtin name. -/
private def isEvmSelector (selector : String) : Bool :=
  selector.length == 8 && selector.toList.all (fun ch =>
    "0123456789abcdefABCDEF".toList.contains ch)

private def coreAbiTypeSupported : CoreType → Bool
  | .unit | .bool | .u8 | .u32 | .u64 | .u128 | .address | .hash => true
  | .bytes | .string | .fixedArray .. | .array .. | .memoryRef .. |
      .structType .. => false

/-- Map a Core context field to the EVM context expr plan.
`msg.value` maps to `ExprPlan.nativeValue`, not a context field — returned
as `none` so the caller can special-case it. -/
def coreContextToPlan? : Core.ContextField → Option ContextExprPlan
  | .sender => some .userId
  | .blockNumber => some .checkpointId
  | .blockTimestamp => some .timestamp
  | .gas => some .gasLeft
  | .contractAddress => some .contractId
  | .value => none  -- handled via ExprPlan.nativeValue, not a context field

/-- Derive the result name for an instruction from its result ValueDef array. -/
private def resultName (instr : Instruction) : String :=
  match instr.results[0]? with
  | some r => s!"v{r.id.value}"
  | none => "_"

structure CorePlanEnv where
  values : Array (ValueId × String) := #[]
  literals : Array (ValueId × CoreLiteral) := #[]
  stateNames : Array (StateId × String) := #[]
  storage : StorageLayout := { states := #[] }
  events : Array (EventId × EventPlan) := #[]
  errors : Array (ErrorId × Option EvmErrorPlan) := #[]
  crosscallStrings : Array String := #[]

private def lookupValueName (env : CorePlanEnv) (id : ValueId) : Except PlanError String :=
  match env.values.find? (fun entry => entry.fst == id) with
  | some entry => .ok entry.snd
  | none => .error { message := s!"EVM Core plan references unknown value {id.value}" }

private def valueExpr (env : CorePlanEnv) (value : ValueRef) : Except PlanError ExprPlan := do
  match env.literals.find? (fun entry => entry.fst == value.id) with
  | some (_, .stringLit literal) =>
      unless literal.toNat?.isSome do
        throw { message := "non-numeric string literals are plan metadata and cannot be runtime EVM values" }
  | some (_, .bytesLit _) =>
      throw { message := "bytes literals are not yet materialized as runtime EVM values" }
  | _ => pure ()
  .ok (.local (← lookupValueName env value.id))

private def literalString (env : CorePlanEnv) (value : ValueRef) : Except PlanError String :=
  match env.literals.find? (fun entry => entry.fst == value.id) with
  | some (_, .stringLit literal) => .ok literal
  | _ => .error { message := "EVM create init code must be a compile-time string literal" }

private def lookupStateName (env : CorePlanEnv) (id : StateId) : Except PlanError String :=
  match env.stateNames.find? (fun entry => entry.fst == id) with
  | some entry => .ok entry.snd
  | none => .error { message := s!"EVM Core plan references unknown state symbol {id.value}" }

private def lookupStorageState (env : CorePlanEnv) (id : StateId) : Except PlanError StorageStatePlan := do
  let name ← lookupStateName env id
  match env.storage.find? name with
  | some state => .ok state
  | none => .error { message := s!"EVM Core plan references unplanned storage state `{name}`" }

private def scalarReadTarget (env : CorePlanEnv) (id : StateId) : Except PlanError ScalarStorageTargetPlan := do
  let state ← lookupStorageState env id
  unless state.kind == .scalar do
    throw { message := s!"EVM Core scalar load references non-scalar state `{state.id}`" }
  return {
    slot := .scalarSlot state.slot
    byteOffset := state.byteOffset
    byteWidth := state.byteWidth
  }

private def scalarWriteTarget (env : CorePlanEnv) (id : StateId) : Except PlanError ScalarStorageTargetPlan := do
  let target ← scalarReadTarget env id
  return { target with writeSemantics := .checked }

private def mapReadTarget (env : CorePlanEnv) (id : StateId) : Except PlanError MapReadTargetPlan := do
  let state ← lookupStorageState env id
  match state.kind with
  | .map .. => return { rootSlot := state.slot }
  | _ => throw { message := s!"EVM Core map load references non-map state `{state.id}`" }

private def mapWriteTarget (env : CorePlanEnv) (id : StateId) : Except PlanError MapWriteTargetPlan := do
  let state ← lookupStorageState env id
  match state.kind with
  | .map .. => return { rootSlot := state.slot }
  | _ => throw { message := s!"EVM Core map store references non-map state `{state.id}`" }

private def arrayReadTarget (env : CorePlanEnv) (id : StateId) : Except PlanError ArrayReadTargetPlan := do
  let state ← lookupStorageState env id
  match state.kind with
  | .array length => return { rootSlot := state.slot, length }
  | _ => throw { message := s!"EVM Core array load references non-array state `{state.id}`" }

private def arrayWriteTarget (env : CorePlanEnv) (id : StateId) : Except PlanError ArrayWriteTargetPlan := do
  let state ← lookupStorageState env id
  match state.kind with
  | .array length => return { rootSlot := state.slot, length }
  | _ => throw { message := s!"EVM Core array store references non-array state `{state.id}`" }

private def lookupEventPlan (env : CorePlanEnv) (id : EventId) : Except PlanError EventPlan :=
  match env.events.find? (fun entry => entry.fst == id) with
  | some entry => .ok entry.snd
  | none => .error { message := s!"EVM Core plan references unknown event {id.value}" }

private def lookupErrorPlan (env : CorePlanEnv) (error : CoreErrorRef) :
    Except PlanError (Option EvmErrorPlan) := do
  let template ← match env.errors.find? (fun entry => entry.fst == error.id) with
    | some entry => pure entry.snd
    | none => throw { message := s!"EVM Core plan references unknown error {error.id.value}" }
  match template with
  | none =>
      unless error.args.isEmpty do
        throw { message := s!"plain Core error {error.id.value} unexpectedly carries arguments" }
      pure none
  | some plan =>
      let args ← error.args.mapM (valueExpr env)
      unless plan.solidityArgWords.isEmpty || args.isEmpty do
        throw { message := s!"EVM error {error.id.value} mixes static and runtime arguments" }
      unless plan.solidityArgTypes.size == plan.solidityArgWords.size + args.size do
        throw { message := s!"EVM error {error.id.value} argument schema does not match Core arguments" }
      pure (some { plan with solidityArgExprs := args })

private def bindInstructionResults (env : CorePlanEnv) (instr : Instruction) : CorePlanEnv :=
  let values := instr.results.foldl
    (fun values result => values.push (result.id, s!"v{result.id.value}")) env.values
  let literals := match instr.op, instr.results[0]? with
    | .pure (.literal literal), some result => env.literals.push (result.id, literal)
    | _, _ => env.literals
  { env with values, literals }

private def crosscallTargetExpr (env : CorePlanEnv) (target : ValueRef) : Except PlanError ExprPlan := do
  let some (_, .addressLit poolIndex) := env.literals.find? (fun entry => entry.fst == target.id)
    | valueExpr env target
  let some index := poolIndex.toNat?
    | valueExpr env target
  let some host := env.crosscallStrings[index]?
    | valueExpr env target
  let some address := ProofForge.Target.ProtocolMaterialize.parseEvmAddressHex? host
    | valueExpr env target
  return .literalWord address

private def crosscallMethodExpr (env : CorePlanEnv) (method : ValueRef) : Except PlanError ExprPlan := do
  let some (_, literal) := env.literals.find? (fun entry => entry.fst == method.id)
    | valueExpr env method
  let index? := match literal with
    | .addressLit poolIndex | .stringLit poolIndex => poolIndex.toNat?
    | _ => none
  let some index := index?
    | valueExpr env method
  let some name := env.crosscallStrings[index]?
    | valueExpr env method
  let some selector := ProofForge.Target.ProtocolMaterialize.evmSelector? name
    | valueExpr env method
  return .literalWord selector

/-- Compute the slot span for a Core state declaration.
Mirrors the existing `stateSlotSpan` logic: scalar/map/dynamicArray = 1,
fixedArray = length (× struct field count if element is a struct). -/
def coreStateSlotSpan (m : Core.Module) (decl : Core.StateDecl) : Nat :=
  match decl.shape with
  | .scalar _ => 1
  | .map _ _ _ => 1
  | .mapN _ _ _ => 1
  | .fixedArray elem len =>
      match elem with
      | .structType tid =>
          match m.structs.find? (fun s => s.id == tid) with
          | some s => len * s.fields.size
          | none => len
      | _ => len
  | .dynamicArray _ => 1
  | .record tid =>
      match m.structs.find? (fun s => s.id == tid) with
      | some s => s.fields.size
      | none => 1

/-- Build a StorageLayout from Core state declarations.
Logical StateId values are assigned slots in declaration order (0, 1, 2, ...).
The `StateKind` and slot span are preserved from the Core `StateShape` so
downstream helper discovery and Yul slot math work correctly. -/
def coreStorageLayout (module : Core.Module) (materialization : MaterializationContract) :
    Except PlanError StorageLayout := do
  let mut states := #[]
  let mut slot := 0
  for decl in module.state do
    let symbol ← match materialization.stateSymbols.find? (fun symbol => symbol.stateId == decl.id) with
      | some symbol => pure symbol
      | none => throw { message := s!"missing EVM state symbol for Core state {decl.id.value}" }
    let (kind, type) ← match decl.shape with
      | .scalar type => pure (StateKind.scalar, coreTypeToValueType type)
      | .map keyType valueType capacity =>
          pure (StateKind.map (coreTypeToValueType keyType) (capacity.getD 0),
            coreTypeToValueType valueType)
      | .mapN .. => throw { message := "nested-map state is not yet materialized by the EVM Core plan" }
      | .fixedArray element length =>
          pure (StateKind.array length, coreTypeToValueType element)
      | .dynamicArray .. => throw { message := "dynamic-array state is not yet materialized by the EVM Core plan" }
      | .record .. => throw { message := "record state is not yet materialized by the EVM Core plan" }
    states := states.push {
      id := symbol.name
      slot
      span := coreStateSlotSpan module decl
      kind
      type
    }
    slot := slot + 1
  return { states }

/-- Map a Core instruction op to EVM StmtPlan entries.
Scalar load/store, context read, arithmetic, event emit, assert, and return
are mapped. Unsupported ops fail closed. -/
def coreInstructionToStmtPlans (env : CorePlanEnv) (instr : Instruction) :
    Except PlanError (Array StmtPlan) :=
  match instr.op with
  | .pure (.literal (.stringLit literal)) =>
      if literal.toNat?.isSome then do
        .ok #[StmtPlan.letBind (resultName instr) (← coreLiteralPlanType (.stringLit literal))
          (← coreLiteralToExprPlan (.stringLit literal))]
      else
        .ok #[]
  | .pure (.literal lit) => do
      .ok #[StmtPlan.letBind (resultName instr) (← coreLiteralPlanType lit)
        (← coreLiteralToExprPlan lit)]
  | .pure (.structLit _ _) =>
      throw { message := "canonical struct literals are not yet materialized by the EVM Core plan" }
  | .pure (.unary op arg) => do
      let argExpr ← valueExpr env arg
      match op with
      | .not => .ok #[StmtPlan.letBind (resultName instr) .bool
        (.builtin "iszero" #[argExpr])]
      | .neg => do
          let resultType := coreTypeToValueType arg.type
          let byteWidth := resultType.byteWidth
          if byteWidth == 0 || byteWidth >= 32 then
            throw { message := "unary negation type is not yet materialized by the EVM Core plan" }
          let mask := ExprPlan.literalWord ((2 ^ (byteWidth * 8)) - 1)
          .ok #[StmtPlan.letBind (resultName instr) resultType
            (.builtin "and" #[.builtin "sub" #[.literalWord 0, argExpr], mask])]
  | .pure (.arithmetic op mode lhs rhs) => do
      let lhsExpr ← valueExpr env lhs
      let rhsExpr ← valueExpr env rhs
      /- Result type follows the operand type (both sides must agree in
      well-typed Core). -/
      let vt := coreTypeToValueType lhs.type
      let result := StmtPlan.letBind (resultName instr) vt
        (← coreNarrowArithmeticPlan op mode lhs.type lhsExpr rhsExpr)
      match op with
      | .div | .mod =>
          .ok #[
            StmtPlan.assert
              (.builtin "iszero" #[.builtin "iszero" #[rhsExpr]])
              "division by zero"
              none,
            result
          ]
      | _ => .ok #[result]
  | .pure (.compare op lhs rhs) => do
      let lhsExpr ← valueExpr env lhs
      let rhsExpr ← valueExpr env rhs
      let expr := match op with
        | .eq => .builtin "eq" #[lhsExpr, rhsExpr]
        | .ne => .builtin "iszero" #[.builtin "eq" #[lhsExpr, rhsExpr]]
        | .lt => .builtin "lt" #[lhsExpr, rhsExpr]
        | .le => .builtin "iszero" #[.builtin "gt" #[lhsExpr, rhsExpr]]
        | .gt => .builtin "gt" #[lhsExpr, rhsExpr]
        | .ge => .builtin "iszero" #[.builtin "lt" #[lhsExpr, rhsExpr]]
      .ok #[StmtPlan.letBind (resultName instr) .bool
        expr]
  | .pure (.cast toType arg) => do
      let vt := coreTypeToValueType toType
      .ok #[StmtPlan.letBind (resultName instr) vt
        (.cast (← valueExpr env arg) vt)]
  | .pure (.hash arg) => do
      .ok #[StmtPlan.letBind (resultName instr) .hash
        (.hash (← valueExpr env arg))]
  | .pure (.hashTwoToOne lhs rhs) => do
      .ok #[StmtPlan.letBind (resultName instr) .hash
        (.hashTwoToOne (← valueExpr env lhs) (← valueExpr env rhs))]
  | .storageLoad path => do
      match path.path with
      | #[] =>
        let vt := coreTypeToValueType path.resultType
        .ok #[StmtPlan.letBind (resultName instr) vt
          (.effect (.storageScalarReadTarget (← scalarReadTarget env path.root)))]
      | #[.mapKey key] =>
        let vt := coreTypeToValueType path.resultType
        .ok #[StmtPlan.letBind (resultName instr) vt
          (.effect (.storageMapGetTarget (← mapReadTarget env path.root) (← valueExpr env key)))]
      | #[.index index] =>
        let vt := coreTypeToValueType path.resultType
        .ok #[StmtPlan.letBind (resultName instr) vt
          (.effect (.storageArrayReadTarget (← arrayReadTarget env path.root) (← valueExpr env index)))]
      | _ => .error { message := "EVM Core plan supports one mapKey or index storage-load segment" }
  | .storageStore path value => do
      match path.path with
      | #[] =>
        .ok #[StmtPlan.effect (.storageScalarWriteTarget (← scalarWriteTarget env path.root)
          (← valueExpr env value))]
      | #[.mapKey key] =>
        .ok #[StmtPlan.effect (.storageMapSetTarget (← mapWriteTarget env path.root)
          (← valueExpr env key) (← valueExpr env value))]
      | #[.index index] =>
        .ok #[StmtPlan.effect (.storageArrayWriteTarget (← arrayWriteTarget env path.root)
          (← valueExpr env index) (← valueExpr env value))]
      | _ => .error { message := "EVM Core plan supports one mapKey or index storage-store segment" }
  | .storageRemove _ =>
      .error { message := "canonical storage removal is not yet materialized by the EVM Core plan" }
  | .contextRead field => do
      let resultType ← match instr.results[0]? with
        | some result => pure (coreTypeToValueType result.type)
        | none => throw { message := "contextRead is missing its Core result" }
      match coreContextToPlan? field with
      | some ctxPlan =>
          .ok #[StmtPlan.letBind (resultName instr) resultType (.context ctxPlan)]
      | none =>
        if field == .value then
          /- `.value` has no ContextExprPlan variant; it maps to
          `ExprPlan.nativeValue`. -/
          .ok #[StmtPlan.letBind (resultName instr) resultType .nativeValue]
        else
          .error { message := s!"EVM Core plan does not support context field `{repr field}`" }
  | .emit event args => do
      let eventPlan ← lookupEventPlan env event
      if eventPlan.fields.size != args.size then
        throw { message := s!"event {event.value} argument count does not match its interface schema" }
      let mut indexedFields : Array (Array ExprPlan) := #[]
      let mut dataFields : Array (Array ExprPlan) := #[]
      for idx in [:args.size] do
        let value := #[← valueExpr env args[idx]!]
        if eventPlan.fields[idx]!.indexed then
          indexedFields := indexedFields.push value
        else
          dataFields := dataFields.push value
      if indexedFields.isEmpty then
        .ok #[StmtPlan.effect (.eventEmitWords eventPlan dataFields)]
      else
        .ok #[StmtPlan.effect (.eventEmitIndexedWords eventPlan indexedFields dataFields)]
  | .assert cond error => do
      /- Resolve the Core error identity through canonical materialization.
      Fallback errors remain plain reverts; envelope/custom forms carry the
      exact source-facing code and Solidity encoding. -/
      .ok #[StmtPlan.assertPlanned (← valueExpr env cond)
        s!"assertion failed" (← lookupErrorPlan env error)]
  | .hostCall call =>
      if call.id == ProofForge.Target.HostOps.Evm.originSig.id then do
        unless call.args.isEmpty do
          throw ({ message := s!"target extension `{call.id.render}` expects no arguments" } : PlanError)
        .ok #[StmtPlan.letBind (resultName instr) .address (.context .origin)]
      else if call.id == ProofForge.Target.HostOps.Evm.prevRandaoSig.id then do
        unless call.args.isEmpty do
          throw ({ message := s!"target extension `{call.id.render}` expects no arguments" } : PlanError)
        .ok #[StmtPlan.letBind (resultName instr) .hash (.context .prevRandao)]
      else if call.id == ProofForge.Target.HostOps.Evm.gasPriceSig.id then do
        unless call.args.isEmpty do
          throw ({ message := s!"target extension `{call.id.render}` expects no arguments" } : PlanError)
        .ok #[StmtPlan.letBind (resultName instr) .u64 (.context .gasPrice)]
      else if call.id == ProofForge.Target.HostOps.Evm.baseFeeSig.id then do
        unless call.args.isEmpty do
          throw ({ message := s!"target extension `{call.id.render}` expects no arguments" } : PlanError)
        .ok #[StmtPlan.letBind (resultName instr) .u64 (.context .baseFee)]
      else if call.id == ProofForge.Target.HostOps.Evm.coinbaseSig.id then do
        unless call.args.isEmpty do
          throw ({ message := s!"target extension `{call.id.render}` expects no arguments" } : PlanError)
        .ok #[StmtPlan.letBind (resultName instr) .hash (.context .coinbase)]
      else if call.id == ProofForge.Target.HostOps.Evm.blockHashSig.id then
        match call.args with
        | #[blockNumber] => do
            .ok #[StmtPlan.letBind (resultName instr) .hash
              (.context (.blockHash (← valueExpr env blockNumber)))]
        | _ => .error { message := s!"target extension `{call.id.render}` expects 1 argument" }
      else if call.id == ProofForge.Target.HostOps.Evm.ecrecoverSig.id then
        match call.args with
        | #[digest, v, r, s] => do
            .ok #[StmtPlan.letBind (resultName instr) .u64 (.ecrecover
              (← valueExpr env digest) (← valueExpr env v)
              (← valueExpr env r) (← valueExpr env s))]
        | _ => .error { message := s!"target extension `{call.id.render}` expects 4 arguments" }
      else if call.id == ProofForge.Target.HostOps.Evm.eip712PermitDigestSig.id then
        match call.args with
        | #[owner, spender, value, nonce, deadline, domainSep] => do
            .ok #[StmtPlan.letBind (resultName instr) .hash (.eip712PermitDigest
              (← valueExpr env owner) (← valueExpr env spender)
              (← valueExpr env value) (← valueExpr env nonce)
              (← valueExpr env deadline) (← valueExpr env domainSep))]
        | _ => .error { message := s!"target extension `{call.id.render}` expects 6 arguments" }
      else if call.id == ProofForge.Target.HostOps.Evm.create2Sig.id then
        match call.args with
        | #[callValue, salt, initCode] => do
            .ok #[StmtPlan.letBind (resultName instr) .address
              (.create .create2 (← valueExpr env callValue) (some (← valueExpr env salt))
                (← literalString env initCode))]
        | _ => .error { message := s!"target extension `{call.id.render}` expects 3 arguments" }
      else if call.id == ProofForge.Target.HostOps.Evm.erc721ReceivedSig.id then
        match call.args with
        | #[operator, fromAddr, toAddr, tokenId] => do
            .ok #[StmtPlan.effect (.checkErc721Received
              (← valueExpr env operator) (← valueExpr env fromAddr)
              (← valueExpr env toAddr) (← valueExpr env tokenId))]
        | _ => .error { message := s!"target extension `{call.id.render}` expects 4 arguments" }
      else if call.id == ProofForge.Target.HostOps.Evm.erc1155ReceivedSig.id then
        match call.args with
        | #[operator, fromAddr, toAddr, tokenId, amount] => do
            .ok #[StmtPlan.effect (.checkErc1155Received
              (← valueExpr env operator) (← valueExpr env fromAddr)
              (← valueExpr env toAddr) (← valueExpr env tokenId) (← valueExpr env amount))]
        | _ => .error { message := s!"target extension `{call.id.render}` expects 5 arguments" }
      else if call.id == ProofForge.Target.HostOps.Evm.erc1155BatchReceivedSig.id then
        match call.args with
        | #[operator, fromAddr, toAddr, ids, amounts] => do
            .ok #[StmtPlan.effect (.checkErc1155BatchReceived
              (← valueExpr env operator) (← valueExpr env fromAddr)
              (← valueExpr env toAddr) (← valueExpr env ids) (← valueExpr env amounts))]
        | _ => .error { message := s!"target extension `{call.id.render}` expects 5 arguments" }
      else
        .error { message := s!"EVM Core plan does not support target extension `{call.id.render}`" }
  | .crosscall spec args => do
      if spec.gas.isSome then
        throw { message := "crosscall gas override is not yet materialized by the EVM Core plan" }
      if spec.returnType == .unit then
        throw { message := "unit crosscall is not yet materialized by the EVM Core plan" }
      unless coreAbiTypeSupported spec.returnType do
        throw { message := "crosscall return type is not yet materialized by the EVM Core plan" }
      let mode ← match spec.mode, spec.value with
        | .invoke, none => pure CrosscallMode.call
        | .invoke, some _ => pure CrosscallMode.callValue
        | .staticInvoke, none => pure CrosscallMode.staticcall
        | .delegateInvoke, none => pure CrosscallMode.delegatecall
        | .staticInvoke, some _ | .delegateInvoke, some _ =>
            throw { message := "static/delegate crosscall cannot carry value" }
        | .namedInvoke, _ | .continuation, _ =>
            throw { message := "NEAR promise crosscall modes are unsupported by the EVM Core plan" }
      let mut argPlans := #[]
      for arg in args do
        unless coreAbiTypeSupported arg.type && arg.type != .unit do
          throw { message := "crosscall argument type is not yet materialized by the EVM Core plan" }
        argPlans := argPlans.push (CrosscallArgWordPlan.expr (← valueExpr env arg))
      let callValue? ← spec.value.mapM (valueExpr env)
      .ok #[StmtPlan.letBind (resultName instr) (coreTypeToValueType spec.returnType)
        (.crosscall mode
          (← crosscallTargetExpr env spec.target)
          (← crosscallMethodExpr env spec.method)
          callValue?
          argPlans
          (coreTypeToValueType spec.returnType))]
  | .storageContains _ =>
      .error { message := "storageContains not yet supported in EVM Core plan builder" }
  | .storageLength _ =>
      .error { message := "storageLength not yet supported in EVM Core plan builder" }
  | .storageResize _ _ =>
      .error { message := "storageResize not yet supported in EVM Core plan builder" }
  | .memoryAlloc _ _ =>
      .error { message := "memoryAlloc not yet supported in EVM Core plan builder" }
  | .memoryLoad _ _ =>
      .error { message := "memoryLoad not yet supported in EVM Core plan builder" }
  | .memoryStore _ _ _ =>
      .error { message := "memoryStore not yet supported in EVM Core plan builder" }
  | .memoryRelease _ =>
      .error { message := "memoryRelease not yet supported in EVM Core plan builder" }

/-- Map a Core function to EVM entrypoint plan entries (body statements).
Only the entry block is mapped for the initial fragment; control flow
mapping (branches, loops) will be added as needed. -/
private def lowerBlockInstructions (env : CorePlanEnv) (block : Block) :
    Except PlanError (Array StmtPlan × CorePlanEnv) := do
  let mut statements := #[]
  let mut currentEnv := env
  for instruction in block.instructions do
    statements := statements ++ (← coreInstructionToStmtPlans currentEnv instruction)
    currentEnv := bindInstructionResults currentEnv instruction
  return (statements, currentEnv)

private def returnPlan (env : CorePlanEnv) (values : Array ValueRef) :
    Except PlanError (Array StmtPlan) := do
  if values.size > 1 then throw { message := "EVM Core function returns multiple values" }
  if let some value := values[0]? then return #[.return (← valueExpr env value)]
  return #[]

def coreFunctionToStmtPlans (env : CorePlanEnv) (func : Function) : Except PlanError (Array StmtPlan) := do
  let block ← match func.blocks[0]? with
    | some block => pure block
    | none => throw { message := s!"function {func.id.value} has no entry block" }
  if block.id != func.entry then
    throw { message := s!"function {func.id.value} first block is not its entry" }
  if !block.params.isEmpty then
    throw { message := s!"function {func.id.value} entry block parameters are not yet materialized by the EVM Core plan" }
  let (entryStatements, currentEnv) ← lowerBlockInstructions env block
  let mut stmts := entryStatements
  match block.terminator with
  | .return vals => stmts := stmts ++ (← returnPlan currentEnv vals)
  | .branch condition onTrue onFalse =>
      let trueBlock ← match func.blocks.find? (fun candidate => candidate.id == onTrue) with
        | some block => pure block
        | none => throw { message := "EVM Core branch true block is missing" }
      let falseBlock ← match func.blocks.find? (fun candidate => candidate.id == onFalse) with
        | some block => pure block
        | none => throw { message := "EVM Core branch false block is missing" }
      let (trueBody, _) ← lowerBlockInstructions currentEnv trueBlock
      let (falseBody, _) ← lowerBlockInstructions currentEnv falseBlock
      let (continuation, trueArgs) ← match trueBlock.terminator with
        | .jump target args _ => pure (target, args)
        | _ => throw { message := "EVM Core structured branch true arm must jump to a continuation" }
      let (falseContinuation, falseArgs) ← match falseBlock.terminator with
        | .jump target args _ => pure (target, args)
        | _ => throw { message := "EVM Core structured branch false arm must jump to a continuation" }
      unless continuation == falseContinuation && trueArgs.isEmpty && falseArgs.isEmpty do
        throw { message := "EVM Core structured branch arms must join without block arguments" }
      stmts := stmts.push (.ifElse (← valueExpr currentEnv condition) trueBody falseBody)
      let continuationBlock ← match func.blocks.find? (fun candidate => candidate.id == continuation) with
        | some block => pure block
        | none => throw { message := "EVM Core branch continuation is missing" }
      let (continuationBody, continuationEnv) ← lowerBlockInstructions currentEnv continuationBlock
      stmts := stmts ++ continuationBody
      match continuationBlock.terminator with
      | .return values => stmts := stmts ++ (← returnPlan continuationEnv values)
      | _ => throw { message := "EVM Core branch continuation must return" }
  | .jump .. =>
      throw { message := s!"function {func.id.value} CFG control flow entry jump is not yet materialized by the EVM Core plan" }
  | .revert error =>
      match ← lookupErrorPlan currentEnv error with
      | some plan => stmts := stmts.push (.revertPlanned plan)
      | none => stmts := stmts.push (.revert "")
  return stmts

private inductive EvmDispatchKind
  | function | fallback | receive
  deriving BEq

private inductive EvmProxyPattern
  | uups | transparent

private def evmProxyPattern (extensions : Array InterfaceExtension) :
    Except PlanError (Option EvmProxyPattern) := do
  let some extension := extensions.find? fun extension =>
      extension.id == ProofForge.Target.InterfaceOps.Evm.proxyPatternId &&
        extension.subject == .contract
    | pure none
  match extension.args with
  | #[.string "uups"] => pure (some .uups)
  | #[.string "transparent"] => pure (some .transparent)
  | _ => throw { message := "invalid EVM proxy-pattern interface extension" }

private def evmEntrypointKind (extensions : Array InterfaceExtension)
    (functionId : FunctionId) : Except PlanError EvmDispatchKind := do
  let fallback := extensions.any fun extension =>
    extension.id == ProofForge.Target.InterfaceOps.Evm.fallbackDispatchId &&
      extension.subject == .entrypoint functionId
  let receive := extensions.any fun extension =>
    extension.id == ProofForge.Target.InterfaceOps.Evm.receiveDispatchId &&
      extension.subject == .entrypoint functionId
  if fallback && receive then
    throw { message := s!"entrypoint {functionId.value} cannot be both EVM fallback and receive" }
  else if fallback then pure .fallback
  else if receive then pure .receive
  else pure .function

/-- Map a Core InterfaceEntrypoint to an EVM EntrypointPlan. -/
private def coreEntrypointToPlan (m : Core.Module) (baseEnv : CorePlanEnv)
    (kind : EvmDispatchKind) (ep : InterfaceEntrypoint) :
    Except PlanError EntrypointPlan := do
  /- Find the Core function by functionId. -/
  match m.functions.find? (fun f => f.id == ep.functionId) with
  | none => .error { message := s!"entrypoint {ep.name} references unknown function {ep.functionId.value}" }
  | some func =>
      let selector ← match kind, ep.selector? with
        | .function, some selector => pure selector
        | .function, none => throw { message := s!"entrypoint {ep.name} is missing its EVM selector" }
        | .fallback, none | .receive, none => pure ""
        | .fallback, some _ | .receive, some _ =>
            throw { message := s!"EVM fallback/receive entrypoint {ep.name} cannot have a selector" }
      if kind == .function && !isEvmSelector selector then
        throw { message := s!"entrypoint {ep.name} has invalid EVM selector `{selector}`" }
      if kind != .function && (!ep.params.isEmpty || ep.retType != .unit) then
        throw { message := s!"EVM fallback/receive entrypoint {ep.name} must have no parameters and Unit return" }
      for param in ep.params do
        unless coreAbiTypeSupported param.type do
          throw { message := s!"entrypoint {ep.name} parameter `{param.name}` has an EVM ABI type not yet materialized by the Core plan" }
      unless coreAbiTypeSupported ep.retType do
        throw { message := s!"entrypoint {ep.name} return type is not yet materialized by the EVM Core plan" }
      let valueNames := ep.params.foldl
        (fun values param => values.push (param.valueId, param.name)) baseEnv.values
      let body ← coreFunctionToStmtPlans { baseEnv with values := valueNames } func
      let params := ep.params.mapIdx fun idx p =>
        { name := p.name, type := coreTypeToValueType p.type,
          abiWord? := p.abiWord?, wordTypes := #[coreTypeToValueType p.type],
          headWordIndex := idx, localNames := #[p.name] : AbiParamPlan }
      let returnType := coreTypeToValueType ep.retType
      .ok {
        name := ep.name
        selector
        params
        returns := {
          returnType
          wordTypes := if returnType == .unit then #[] else #[returnType]
          localNames := returnLocalNames returnType (if returnType == .unit then #[] else #[returnType])
        }
        body
      }

private def coreEventAbiType (field : InterfaceEventField) : Except PlanError String :=
  match field.abiWord? with
  | some abiType => .ok abiType
  | none =>
      match field.type with
      | .u8 => .ok "uint8"
      | .u32 => .ok "uint32"
      | .u64 => .ok "uint64"
      | .u128 => .ok "uint128"
      | .bool => .ok "bool"
      | .hash => .ok "bytes32"
      | .address => .ok "address"
      | .bytes => .ok "bytes"
      | .string => .ok "string"
      | _ => .error { message := s!"event field {field.name} has an EVM ABI type not yet materialized by the Core plan" }

private def coreEventToPlan (event : InterfaceEvent) : Except PlanError EventPlan := do
  let abiTypes ← event.fields.mapM coreEventAbiType
  let fields := event.fields.map fun field =>
    EventFieldPlan.mk field.name (coreTypeToValueType field.type) field.indexed
  return EventPlan.mk event.name
    s!"{event.name}({String.intercalate "," abiTypes.toList})" fields

private def isEvmErrorSelector (selector : String) : Bool :=
  selector.length == 8 && selector.toList.all (fun ch =>
    "0123456789abcdefABCDEF".toList.contains ch)

private def evmErrorAbiCompatible (type : CoreType) (abiType : String) : Bool :=
  match type, abiType with
  | .u8, "uint8" | .u32, "uint32" | .u64, "uint64"
  | .u128, "uint128" | .bool, "bool" | .address, "address"
  | .hash, "uint256" | .hash, "bytes32" => true
  | _, _ => false

private def coreErrorPlans
    (interface : InterfaceContract)
    (materialization : MaterializationContract)
    (extensions : Array InterfaceExtension) :
    Except PlanError (Array (ErrorId × Option EvmErrorPlan)) := do
  let mut errors := #[]
  for encoding in materialization.errorEncodings do
    let interfaceError ← match interface.errors.find? (·.errorId == encoding.errorId) with
      | some error => pure error
      | none => throw { message := s!"missing EVM interface error {encoding.errorId.value}" }
    let customExtension? := extensions.find? fun extension =>
      extension.id == ProofForge.Target.InterfaceOps.Evm.solidityCustomErrorId &&
        extension.subject == .error encoding.errorId
    let customPlan? ← match customExtension? with
      | none => pure none
      | some extension => match extension.args with
        | #[.string selector, .strings argTypes] => do
          unless isEvmErrorSelector selector do
            throw { message := s!"invalid EVM custom-error selector `{selector}`" }
          unless argTypes.size == interfaceError.params.size do
            throw { message := s!"EVM custom-error schema mismatch for {encoding.errorId.value}" }
          for (type, abiType) in interfaceError.params.zip argTypes do
            unless evmErrorAbiCompatible type abiType do
              throw { message := s!"unsupported EVM custom-error ABI type `{abiType}`" }
          pure (some {
            assertionId := UInt32.ofNat interfaceError.code
            userCode? := interfaceError.userCode?
            soliditySelector? := some selector
            solidityArgTypes := argTypes
          })
        | _ => throw { message := s!"invalid EVM custom-error interface extension for {encoding.errorId.value}" }
    let errorRef? := match customPlan? with
      | some plan => some plan
      | none => match encoding.form with
      | .assertFallback | .revertMessage => none
      | .proofForgeEnvelope => some {
          assertionId := UInt32.ofNat interfaceError.code
          userCode? := interfaceError.userCode?
        }
    errors := errors.push (encoding.errorId, errorRef?)
  return errors

private def pushCreateSpec
    (specs : Array CreateHelperSpec) (spec : CreateHelperSpec) : Array CreateHelperSpec :=
  if specs.contains spec then specs else specs.push spec

mutual
  private partial def coreCreateSpecsFromStmtPlan : StmtPlan → Array CreateHelperSpec
    | .letBind _ _ (.create mode _ _ initCodeHex)
    | .letMutBind _ _ (.create mode _ _ initCodeHex) =>
        #[{ mode, initCodeHex }]
    | .ifElse _ thenBody elseBody =>
        coreCreateSpecsFromStmtPlans thenBody |>.foldl pushCreateSpec
          (coreCreateSpecsFromStmtPlans elseBody)
    | .boundedFor _ _ _ body => coreCreateSpecsFromStmtPlans body
    | _ => #[]

  private partial def coreCreateSpecsFromStmtPlans
      (statements : Array StmtPlan) : Array CreateHelperSpec :=
    statements.foldl (init := #[]) fun specs statement =>
      (coreCreateSpecsFromStmtPlan statement).foldl pushCreateSpec specs
end

private def coreCreateHelperSpecs
    (entrypoints : Array EntrypointPlan) : Array CreateHelperSpec :=
  entrypoints.foldl (init := #[]) fun specs entrypoint =>
    (coreCreateSpecsFromStmtPlans entrypoint.body).foldl pushCreateSpec specs

/-- Build an EVM ModulePlan from a checked canonical contract.
This reuses the existing ModulePlan structure — no parallel plan types. -/
def buildFromCore (checked : CheckedCanonicalContract)
    (capPlan : CapabilityPlan) :
    Except PlanError ModulePlan := do
  if capPlan.targetId != ProofForge.Target.evm.id then
    .error { message := s!"EVM buildFromCore requires target `{ProofForge.Target.evm.id}`, got `{capPlan.targetId}`" }
  let m := checked.contract.module
  let iface := checked.contract.interface
  let proxyPattern? ← evmProxyPattern checked.contract.interfaceExtensions
  /- Build storage layout from Core state declarations. -/
  let storage ← coreStorageLayout m checked.contract.materialization
  let events ← iface.events.mapM coreEventToPlan
  let errors ← coreErrorPlans iface checked.contract.materialization
    checked.contract.interfaceExtensions
  let baseEnv : CorePlanEnv := {
    stateNames := checked.contract.materialization.stateSymbols.map
      (fun symbol => (symbol.stateId, symbol.name))
    storage
    events := (iface.events.zip events).map (fun entry => (entry.fst.eventId, entry.snd))
    errors
    crosscallStrings := checked.contract.materialization.crosscallStrings
  }
  /- Build entrypoint plans from interface. -/
  let mut entrypoints := #[]
  let mut dispatchEntrypoints := #[]
  let mut fallbackFunction? := none
  let mut receiveFunction? := none
  for ep in iface.entrypoints do
    let kind ← evmEntrypointKind checked.contract.interfaceExtensions ep.functionId
    let epPlan ← coreEntrypointToPlan m baseEnv kind ep
    entrypoints := entrypoints.push epPlan
    match kind with
    | .function => dispatchEntrypoints := dispatchEntrypoints.push epPlan
    | .fallback =>
        if fallbackFunction?.isSome then
          throw { message := "EVM interface has multiple fallback entrypoints" }
        fallbackFunction? := some s!"f_{iface.contractName}_{ep.name}"
    | .receive =>
        if receiveFunction?.isSome then
          throw { message := "EVM interface has multiple receive entrypoints" }
        receiveFunction? := some s!"f_{iface.contractName}_{ep.name}"
  /- Determine if any entrypoint uses checked arithmetic. -/
  let usesCheckedArithmetic := m.functions.any fun function =>
    function.blocks.any fun block =>
      block.instructions.any fun instruction =>
        match instruction.op with
        | .pure (.arithmetic op .checked _ _) =>
            match op with
            | .add | .sub | .mul => true
            | _ => false
        | _ => false
  let usesCheckedWidth := m.functions.any fun function =>
    function.blocks.any fun block =>
      block.instructions.any fun instruction =>
        match instruction.op with
        | .pure (.arithmetic op .checked lhs _) =>
            match op with
            | .add | .sub | .mul =>
                (coreTypeToValueType lhs.type).byteWidth < 32
            | _ => false
        | _ => false
  let usesMapRead := m.functions.any fun function => function.blocks.any fun block =>
    block.instructions.any fun instruction => match instruction.op with
      | .storageLoad { path := #[.mapKey _], .. } => true
      | _ => false
  let usesMapWrite := m.functions.any fun function => function.blocks.any fun block =>
    block.instructions.any fun instruction => match instruction.op with
      | .storageStore { path := #[.mapKey _], .. } _ => true
      | _ => false
  let usesArrayAccess := m.functions.any fun function => function.blocks.any fun block =>
    block.instructions.any fun instruction => match instruction.op with
      | .storageLoad { path := #[.index _], .. }
      | .storageStore { path := #[.index _], .. } _ => true
      | _ => false
  let usesHashWord := m.functions.any fun function => function.blocks.any fun block =>
    block.instructions.any fun instruction => match instruction.op with
      | .pure (.hash _) => true
      | _ => false
  let usesHashPair := m.functions.any fun function => function.blocks.any fun block =>
    block.instructions.any fun instruction => match instruction.op with
      | .pure (.hashTwoToOne ..) => true
      | _ => false
  let helpers :=
    (if usesCheckedWidth then #[Helper.checkedWidth] else #[]) ++
    (if usesArrayAccess then #[Helper.arraySlot] else #[]) ++
    (if usesMapRead || usesMapWrite then #[Helper.mapSlot] else #[]) ++
    (if usesMapWrite then #[Helper.mapPresenceSlot, Helper.mapWrite] else #[]) ++
    (if usesHashWord then #[Helper.hashWord] else #[]) ++
    (if usesHashPair then #[Helper.hashPair] else #[])
  let mut crosscalls := #[]
  for function in m.functions do
    for block in function.blocks do
      for instruction in block.instructions do
        match instruction.op with
        | .crosscall spec args =>
            let mode := match spec.mode, spec.value with
              | .invoke, none => CrosscallMode.call
              | .invoke, some _ => CrosscallMode.callValue
              | .staticInvoke, _ => CrosscallMode.staticcall
              | .delegateInvoke, _ => CrosscallMode.delegatecall
              | .namedInvoke, _ | .continuation, _ => CrosscallMode.call
            let returnType := coreTypeToValueType spec.returnType
            let helper : CrosscallHelperSpec := {
              arity := args.size
              returnType
              wordTypes := if returnType == .unit then #[] else #[returnType]
              mode
            }
            unless crosscalls.contains helper do
              crosscalls := crosscalls.push helper
        | _ => pure ()
  let dispatchDefault ← match proxyPattern? with
    | some .uups => pure DispatchDefaultPlan.uupsProxy
    | some .transparent =>
        throw { message := "EVM transparent proxy materialization is not implemented" }
    | none =>
        if receiveFunction?.isSome then
          pure DispatchDefaultPlan.receive
        else if fallbackFunction?.isSome then
          pure DispatchDefaultPlan.fallback
        else
          pure DispatchDefaultPlan.revert
  let creates := coreCreateHelperSpecs entrypoints
  .ok {
    name := iface.contractName
    targetPlan := capPlan
    storage
    helpers
    mapAssignOps := #[]
    entrypoints
    dispatch := {
      entrypoints := dispatchEntrypoints
      fallbackFunction?
      receiveFunction?
      default := dispatchDefault
    }
    events
    crosscalls
    creates
    localArrayGetLengths := #[]
    nestedLocalArrayGetShapes := #[]
    usesCheckedArithmetic
    overflowChecked := usesCheckedArithmetic
    metadata := {
      moduleName := iface.contractName
      entrypoints
      events
      capabilities := capPlan.capabilities
    }
    contextOps := #[]
  }

end ProofForge.Backend.Evm.Plan.Core
