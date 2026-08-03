import ProofForgeV2.Targets.Ton.ValidatePlanV1

/-!
# Ton EmitIRV1 — Plan → IR → Tolk 1.4 source emission

TON-owned TVM/Tolk recipe IR:
* storage: flat `struct Storage { __layout: uint64; fields... }` in c4
* entry: `onInternalMessage` with 32-bit op + 64-bit query_id dispatch
* view: `get fun` methods
* arithmetic: TVM int257 + explicit UInt64 range checks (`assert … throw`)
* emit → `createExternalLogMessage` + `SEND_MODE_PAY_FEES_SEPARATELY`
* schedule → `createMessage` internal out-message:
    bounce=`BounceMode.NoBounce`, value=`0`, send=`SEND_MODE_PAY_FEES_SEPARATELY`,
    dest=`(0, SHA-256(UTF-8 target path) as uint256)` stub, body=
    `op32 · query_id=0 · arg64*` (see `Statement.promiseAccount` docstring)
* revert → `throw(error_code)`

Not sandbox/mainnet runtime (TON-3). Not formal D4.
-/

namespace ProofForgeV2.Targets.Ton

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Stable exit codes for the UInt64 pilot (TVM exception codes). -/
def errOverflow : Nat := 100
def errDivZero : Nat := 101
def errInvalidShift : Nat := 102
def errAssert : Nat := 103
def errLoopBound : Nat := 104
def errLayout : Nat := 105
def errUserBase : Nat := 200

inductive Operation where
  | requireLayoutAbsent
  | requireLayout (marker : UInt64)
  | zeroState (fieldIndex : Nat)
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination inputOffset : Nat)
  | loadState (destination fieldIndex : Nat)
  | checkedAdd (destination lhs rhs : Nat)
  | checkedSub (destination lhs rhs : Nat)
  | checkedMul (destination lhs rhs : Nat)
  | checkedDiv (destination lhs rhs : Nat)
  | checkedMod (destination lhs rhs : Nat)
  | signedCheckedAdd (destination lhs rhs : Nat)
  | signedCheckedSub (destination lhs rhs : Nat)
  | signedCheckedMul (destination lhs rhs : Nat)
  | signedCheckedDiv (destination lhs rhs : Nat)
  | signedCheckedMod (destination lhs rhs : Nat)
  | signedCompare (destination lhs rhs : Nat) (op : ComparisonOp)
  | checkedNeg (destination source : Nat)
  | sar (destination lhs rhs : Nat)
  | storeState (fieldIndex value : Nat)
  | setLayout (marker : UInt64)
  | setReturnData (value : Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat)
  | emitEvent (eventIndex : Nat) (args : Array Nat)
  | revertError (errorIndex : Nat) (args : Array Nat)
  /-- Schedule → async internal out-message.
      `receiver` is the static QN target path; `destHashHex` is the 64-char
      lower-case SHA-256 hex of UTF-8(receiver); `methodOp` is the 32-bit op
      derived from the method name; `args` are UInt64 temps for the body. -/
  | promiseAccount (receiver : String) (destHashHex : String) (method : String)
      (methodOp : UInt32) (args : Array Nat)
  | returnNone
  | ifRegion (condition : Nat) (thenOps elseOps : Array Operation)
  | switchRegion (scrutinee : Nat) (cases : Array (UInt64 × Array Operation))
      (defaultOps : Array Operation)
  | forRegion (varTemp : Nat) (initial : Nat) (counterTemp : Nat)
      (maxIterations : Nat)
      (condOps : Array Operation) (condition : Nat)
      (bodyOps : Array Operation)
      (updateOps : Array Operation) (updateValue : Nat)
  | callFn (fnIndex : Nat) (destination : Nat) (args : Array Nat)
  | returnValue (value : Nat)
  | bitAnd (destination lhs rhs : Nat)
  | bitOr (destination lhs rhs : Nat)
  | bitXor (destination lhs rhs : Nat)
  | shl (destination lhs rhs : Nat)
  | shr (destination lhs rhs : Nat)
  | bitNot (destination source : Nat)
  | boolNot (destination source : Nat)
  | boolAnd (destination lhs rhs : Nat)
  | boolOr (destination lhs rhs : Nat)
  deriving BEq, Inhabited, Repr

structure MethodIR where
  name : String
  params : Array Param
  mode : MethodMode
  resultKind : MethodResultKind
  /-- Stable 32-bit op code for mutate/init message receivers. Views use 0. -/
  opCode : UInt32
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

structure FnIR where
  name : String
  paramCount : Nat
  resultIsBool : Bool
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed Ton TVM/Tolk recipe.
    Private `mk`: public Plan→IR construction is capability-gated only. -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  imports : Array HostImport
  methods : Array MethodIR
  fns : Array FnIR
  deriving BEq, Repr

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private partial def lowerExpr (next : Nat)
    (paramAsTemp : Bool) (localEnv : Array (Nat × Nat)) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .bigLiteral _ value =>
      { operations := #[.literal next (UInt64.ofNat value)], value := next, next := next + 1 }
  | .param inputOffset =>
      if paramAsTemp then
        { operations := #[], value := inputOffset / 8, next := next }
      else
        { operations := #[.loadParam next inputOffset], value := next, next := next + 1 }
  | .narrowParam _ inputOffset =>
      if paramAsTemp then
        { operations := #[], value := inputOffset / 8, next := next }
      else
        { operations := #[.loadParam next inputOffset], value := next, next := next + 1 }
  | .localTemp index =>
      match localEnv.find? (fun p => p.1 == index) with
      | some (_, irTemp) =>
          { operations := #[], value := irTemp, next := next }
      | none =>
          { operations := #[.literal next 0], value := next, next := next + 1 }
  | .stateLoad fieldIndex =>
      { operations := #[.loadState next fieldIndex], value := next, next := next + 1 }
  | .narrowStateLoad _ fieldIndex =>
      { operations := #[.loadState next fieldIndex], value := next, next := next + 1 }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedMul lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedDiv lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedMod lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedAdd lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedAdd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedSub lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedSub rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedMul lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMul rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedDiv lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedDiv rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedMod lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMod rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCompare op lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCompare rhs.next lhs.value rhs.value op]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedNeg operand =>
      let op := lowerExpr next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.checkedNeg op.next op.value]
        value := op.next, next := op.next + 1 }
  | .bitAnd lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .bitOr lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .bitXor lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .shl lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shl rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .shr lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .sar lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.sar rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .bitNot operand =>
      let op := lowerExpr next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.bitNot op.next op.value]
        value := op.next, next := op.next + 1 }
  | .narrowCheckedAdd _ lhs rhs | .narrowCheckedSub _ lhs rhs
  | .narrowCheckedMul _ lhs rhs | .narrowCheckedDiv _ lhs rhs
  | .narrowCheckedMod _ lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitAnd _ lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitOr _ lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitXor _ lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitNot _ operand =>
      let op := lowerExpr next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.bitNot op.next op.value]
        value := op.next, next := op.next + 1 }
  | .narrowShl _ lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shl rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowShr _ lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .boolNot operand =>
      let op := lowerExpr next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.boolNot op.next op.value]
        value := op.next, next := op.next + 1 }
  | .boolAnd lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.boolAnd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .boolOr lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.boolOr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .compare op lhs rhs | .wideCompare _ op lhs rhs =>
      let lhs := lowerExpr next paramAsTemp localEnv lhs
      let rhs := lowerExpr lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next, next := rhs.next + 1 }
  | .callFn fnIndex args => Id.run do
      let mut ops : Array Operation := #[]
      let mut cur := next
      let mut argTemps : Array Nat := #[]
      for arg in args do
        let lowered := lowerExpr cur paramAsTemp localEnv arg
        ops := ops ++ lowered.operations
        argTemps := argTemps.push lowered.value
        cur := lowered.next
      ops := ops.push (.callFn fnIndex cur argTemps)
      pure { operations := ops, value := cur, next := cur + 1 }

private partial def lowerBodyOps (next : Nat)
    (body : Array Statement) (fnMode : Bool) (localEnv : Array (Nat × Nat)) :
    Array Operation × Nat := Id.run do
  let mut operations : Array Operation := #[]
  let mut next := next
  let mut localEnv := localEnv
  for stmt in body do
    match stmt with
    | .store op =>
        let value := lowerExpr next fnMode localEnv op.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState op.fieldIndex value.value)
        next := value.next
    | .storeAtomic leaves =>
        let mut vals : Array (Nat × Nat) := #[]
        for leaf in leaves do
          let value := lowerExpr next fnMode localEnv leaf.value
          operations := operations ++ value.operations
          vals := vals.push (leaf.fieldIndex, value.value)
          next := value.next
        for (fieldIndex, temp) in vals do
          operations := operations.push (.storeState fieldIndex temp)
    | .returnValue value =>
        let value := lowerExpr next fnMode localEnv value
        operations := operations ++ value.operations
        if fnMode then
          operations := operations.push (.returnValue value.value)
        else
          operations := operations.push (.setReturnData value.value)
        next := value.next
    | .returnNone =>
        operations := operations.push .returnNone
    | .assert condition =>
        let value := lowerExpr next fnMode localEnv condition
        operations := operations ++ value.operations ++ #[.assert value.value]
        next := value.next
    | .emitEvent eventIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.emitEvent eventIndex argTemps)
    | .revertError errorIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.revertError errorIndex argTemps)
    | .promiseAccount receiver method args =>
        let destHashHex := scheduleDestHashHexV1 receiver
        let methodOp := scheduleMethodOpCodeV1 method
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push
          (.promiseAccount receiver destHashHex method methodOp argTemps)
    | .ifThenElse condition thenBody elseBody =>
        let value := lowerExpr next fnMode localEnv condition
        operations := operations ++ value.operations
        let (thenOps, next1) := lowerBodyOps value.next thenBody fnMode localEnv
        let (elseOps, next2) := lowerBodyOps next1 elseBody fnMode localEnv
        operations := operations.push (.ifRegion value.value thenOps elseOps)
        next := next2
    | .switchOn scrutinee cases defaultBody =>
        let value := lowerExpr next fnMode localEnv scrutinee
        operations := operations ++ value.operations
        let mut caseOps : Array (UInt64 × Array Operation) := #[]
        let mut nextC := value.next
        for (caseValue, caseBody) in cases do
          let (ops, next1) := lowerBodyOps nextC caseBody fnMode localEnv
          caseOps := caseOps.push (caseValue, ops)
          nextC := next1
        let (defaultOps, nextD) := lowerBodyOps nextC defaultBody fnMode localEnv
        operations := operations.push (.switchRegion value.value caseOps defaultOps)
        next := nextD
    | .forLoop varTemp initial condition update maxIterations body =>
        let initL := lowerExpr next fnMode localEnv initial
        operations := operations ++ initL.operations
        let irVar := initL.next
        let counterTemp := initL.next + 1
        next := initL.next + 2
        let localEnv' := localEnv.push (varTemp, irVar)
        let condL := lowerExpr next fnMode localEnv' condition
        let condOps := condL.operations
        let condTemp := condL.value
        next := condL.next
        let (bodyOps, nextB) := lowerBodyOps next body fnMode localEnv'
        next := nextB
        let updateL := lowerExpr next fnMode localEnv' update
        let updateOps := updateL.operations
        let updateTemp := updateL.value
        next := updateL.next
        operations := operations.push
          (.forRegion irVar initL.value counterTemp maxIterations
            condOps condTemp bodyOps updateOps updateTemp)
        localEnv := localEnv'
  pure (operations, next)

/-- Op codes: init = 0; mutate entries get 1..n in plan order; views unused (0). -/
private def assignOpCode (isInit : Bool) (mode : MethodMode) (mutateIndex : Nat) : UInt32 :=
  if isInit then 0
  else if mode == .mutate then UInt32.ofNat (mutateIndex + 1)
  else 0

private def lowerMethod (plan : Plan) (isInit : Bool) (mutateIndex : Nat)
    (method : Method) : MethodIR := Id.run do
  let mut operations : Array Operation := #[]
  if method.mode == .initialize then
    operations := operations.push .requireLayoutAbsent
    for index in [0:plan.storage.fields.size] do
      operations := operations.push (.zeroState index)
  else if method.mode == .mutate then
    operations := operations.push (.requireLayout plan.storage.markerValue)
  -- views: no layout gate required for get-method reads; still require layout
  else
    operations := operations.push (.requireLayout plan.storage.markerValue)
  let body := if method.body.back? == some .returnNone then
    method.body.pop
  else
    method.body
  let (bodyOps, next) := lowerBodyOps 0 body false #[]
  operations := operations ++ bodyOps
  if method.mode == .initialize then
    operations := operations.push (.setLayout plan.storage.markerValue)
  return {
    name := method.name
    params := method.params
    mode := method.mode
    resultKind := method.resultKind
    opCode := assignOpCode isInit method.mode mutateIndex
    tempCount := next
    operations
  }

private def lowerFn (fn : FnBinding) : FnIR :=
  let paramCount := fn.params.size
  let (bodyOps, next) := lowerBodyOps paramCount fn.body true #[]
  {
    name := fn.name
    paramCount
    resultIsBool := fn.resultIsBool
    tempCount := next
    operations := bodyOps
  }

private def expectedMethods (plan : Plan) : Array MethodIR := Id.run do
  let mut out : Array MethodIR := #[lowerMethod plan true 0 plan.initializer]
  let mut mutateIdx : Nat := 0
  for method in plan.entries do
    if method.mode == .mutate then
      out := out.push (lowerMethod plan false mutateIdx method)
      mutateIdx := mutateIdx + 1
    else
      out := out.push (lowerMethod plan false 0 method)
  pure out

private def expectedFns (plan : Plan) : Array FnIR :=
  plan.fns.map lowerFn

private partial def opIsMethodOnlyV1 : Operation → Bool
  | .requireLayoutAbsent | .requireLayout _
  | .zeroState _ | .loadState _ _ | .storeState _ _
  | .setLayout _ | .setReturnData _ | .loadParam _ _ => true
  | .ifRegion _ thenOps elseOps =>
      thenOps.any opIsMethodOnlyV1 || elseOps.any opIsMethodOnlyV1
  | .switchRegion _ cases defaultOps =>
      defaultOps.any opIsMethodOnlyV1 ||
        cases.any fun (_, ops) => ops.any opIsMethodOnlyV1
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      condOps.any opIsMethodOnlyV1 || bodyOps.any opIsMethodOnlyV1 ||
        updateOps.any opIsMethodOnlyV1
  | _ => false

private partial def opIsFnReturnValueV1 : Operation → Bool
  | .returnValue _ => true
  | .ifRegion _ thenOps elseOps =>
      thenOps.any opIsFnReturnValueV1 || elseOps.any opIsFnReturnValueV1
  | .switchRegion _ cases defaultOps =>
      defaultOps.any opIsFnReturnValueV1 ||
        cases.any fun (_, ops) => ops.any opIsFnReturnValueV1
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      condOps.any opIsFnReturnValueV1 || bodyOps.any opIsFnReturnValueV1 ||
        updateOps.any opIsFnReturnValueV1
  | _ => false

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName do
    throw <| .planInvariant .ton "typed Ton IR identity is not bound to its source Plan"
  unless ir.imports == ir.sourcePlan.hostImports do
    throw <| .planInvariant .ton "typed Ton IR host imports are not canonical"
  if ir.methods.size != ir.sourcePlan.entries.size + 1 then
    throw <| .planInvariant .ton "typed Ton IR export count does not match its source Plan"
  if ir.fns.size != ir.sourcePlan.fns.size then
    throw <| .planInvariant .ton "typed Ton IR pureFn count does not match its source Plan"
  for method in ir.methods do
    if method.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .ton
        s!"typed Ton IR method '{method.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if method.operations.any opIsFnReturnValueV1 then
      throw <| .planInvariant .ton
        s!"typed Ton IR method '{method.name}' must not use pureFn returnValue ops"
  for fn in ir.fns do
    if fn.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .ton
        s!"typed Ton IR pureFn '{fn.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if fn.operations.any opIsMethodOnlyV1 then
      throw <| .planInvariant .ton
        s!"typed Ton IR pureFn '{fn.name}' must not use method-only host ops"
  let expected := expectedMethods ir.sourcePlan
  unless ir.methods == expected do
    throw <| .planInvariant .ton
      "typed Ton IR methods/operations are not the exact lowering of their source Plan"
  let expectedFnIR := expectedFns ir.sourcePlan
  unless ir.fns == expectedFnIR do
    throw <| .planInvariant .ton
      "typed Ton IR pureFn operations are not the exact lowering of their source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    imports := plan.hostImports
    methods := expectedMethods plan
    fns := expectedFns plan
  }
  validateIR ir
  return ir

def withMethods (ir : IR) (methods : Array MethodIR) : IR :=
  { ir with methods }

def withFns (ir : IR) (fns : Array FnIR) : IR :=
  { ir with fns }

/-! ### Tolk 1.4 rendering -/

private def indent (n : Nat) : String :=
  String.ofList (List.replicate (n * 4) ' ')

private def tempName (i : Nat) : String := s!"t{i}"

private def fieldName (plan : Plan) (fieldIndex : Nat) : String :=
  if fieldIndex < plan.storage.fields.size then
    plan.storage.fields[fieldIndex]!.name
  else
    s!"f{fieldIndex}"

private def paramName (method : MethodIR) (inputOffset : Nat) : String :=
  match method.params.find? (·.inputOffset == inputOffset) with
  | some p => p.name
  | none => s!"p{inputOffset}"

private def fnParamName (_fn : FnIR) (index : Nat) : String :=
  s!"a{index}"

private def cmpOp : ComparisonOp → String
  | .eq => "==" | .ne => "!=" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="

private def uint64RangeCheck (dst : String) : String :=
  s!"assert (0 <= {dst} && {dst} < (1 << 64)) throw {errOverflow};"

private def int64RangeCheck (dst : String) : String :=
  -- signed Int64 range on int257
  s!"assert (-(1 << 63) <= {dst} && {dst} < (1 << 63)) throw {errOverflow};"

private partial def renderOps (plan : Plan) (method? : Option MethodIR)
    (fn? : Option FnIR) (ops : Array Operation) (depth : Nat)
    (storageVar : String) (needsSave : Bool) : String × Bool := Id.run do
  let mut out := ""
  let mut dirty := needsSave
  let pad := indent depth
  for op in ops do
    match op with
    | .requireLayoutAbsent =>
        out := out ++ pad ++
          s!"assert ({storageVar}.__layout == 0) throw {errLayout};\n"
    | .requireLayout marker =>
        out := out ++ pad ++
          s!"assert ({storageVar}.__layout == {marker}) throw {errLayout};\n"
    | .zeroState fieldIndex =>
        out := out ++ pad ++
          s!"{storageVar}.{fieldName plan fieldIndex} = 0;\n"
        dirty := true
    | .literal dest value =>
        out := out ++ pad ++ s!"val {tempName dest} = {value};\n"
    | .loadParam dest inputOffset =>
        let pname :=
          match method?, fn? with
          | some m, _ => paramName m inputOffset
          | none, some f => fnParamName f (inputOffset / 8)
          | none, none => s!"p{inputOffset}"
        out := out ++ pad ++ s!"val {tempName dest} = {pname};\n"
    | .loadState dest fieldIndex =>
        out := out ++ pad ++
          s!"val {tempName dest} = {storageVar}.{fieldName plan fieldIndex};\n"
    | .storeState fieldIndex value =>
        out := out ++ pad ++
          s!"{storageVar}.{fieldName plan fieldIndex} = {tempName value};\n"
        dirty := true
    | .setLayout marker =>
        out := out ++ pad ++ s!"{storageVar}.__layout = {marker};\n"
        dirty := true
    | .checkedAdd dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} + {tempName rhs};\n"
        out := out ++ pad ++ uint64RangeCheck (tempName dest) ++ "\n"
    | .checkedSub dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} - {tempName rhs};\n"
        out := out ++ pad ++ uint64RangeCheck (tempName dest) ++ "\n"
    | .checkedMul dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} * {tempName rhs};\n"
        out := out ++ pad ++ uint64RangeCheck (tempName dest) ++ "\n"
    | .checkedDiv dest lhs rhs =>
        out := out ++ pad ++
          s!"assert ({tempName rhs} != 0) throw {errDivZero};\n"
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} / {tempName rhs};\n"
        out := out ++ pad ++ uint64RangeCheck (tempName dest) ++ "\n"
    | .checkedMod dest lhs rhs =>
        out := out ++ pad ++
          s!"assert ({tempName rhs} != 0) throw {errDivZero};\n"
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} % {tempName rhs};\n"
        out := out ++ pad ++ uint64RangeCheck (tempName dest) ++ "\n"
    | .signedCheckedAdd dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} + {tempName rhs};\n"
        out := out ++ pad ++ int64RangeCheck (tempName dest) ++ "\n"
    | .signedCheckedSub dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} - {tempName rhs};\n"
        out := out ++ pad ++ int64RangeCheck (tempName dest) ++ "\n"
    | .signedCheckedMul dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} * {tempName rhs};\n"
        out := out ++ pad ++ int64RangeCheck (tempName dest) ++ "\n"
    | .signedCheckedDiv dest lhs rhs =>
        out := out ++ pad ++
          s!"assert ({tempName rhs} != 0) throw {errDivZero};\n"
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} / {tempName rhs};\n"
        out := out ++ pad ++ int64RangeCheck (tempName dest) ++ "\n"
    | .signedCheckedMod dest lhs rhs =>
        out := out ++ pad ++
          s!"assert ({tempName rhs} != 0) throw {errDivZero};\n"
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} % {tempName rhs};\n"
        out := out ++ pad ++ int64RangeCheck (tempName dest) ++ "\n"
    | .checkedNeg dest source =>
        out := out ++ pad ++
          s!"val {tempName dest} = -{tempName source};\n"
        out := out ++ pad ++ int64RangeCheck (tempName dest) ++ "\n"
    | .bitAnd dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = ({tempName lhs} & {tempName rhs}) & ((1 << 64) - 1);\n"
    | .bitOr dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = ({tempName lhs} | {tempName rhs}) & ((1 << 64) - 1);\n"
    | .bitXor dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = ({tempName lhs} ^ {tempName rhs}) & ((1 << 64) - 1);\n"
    | .bitNot dest source =>
        -- Tolk has `~`; mask to UInt64 width.
        out := out ++ pad ++
          s!"val {tempName dest} = (~{tempName source}) & ((1 << 64) - 1);\n"
    | .shl dest lhs rhs =>
        out := out ++ pad ++
          s!"assert (0 <= {tempName rhs} && {tempName rhs} < 64) throw {errInvalidShift};\n"
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} << {tempName rhs};\n"
        out := out ++ pad ++ uint64RangeCheck (tempName dest) ++ "\n"
    | .shr dest lhs rhs =>
        out := out ++ pad ++
          s!"assert (0 <= {tempName rhs} && {tempName rhs} < 64) throw {errInvalidShift};\n"
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} >> {tempName rhs};\n"
    | .sar dest lhs rhs =>
        out := out ++ pad ++
          s!"assert (0 <= {tempName rhs} && {tempName rhs} < 64) throw {errInvalidShift};\n"
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} >> {tempName rhs};\n"
    | .boolNot dest source =>
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName source} == 0 ? 1 : 0;\n"
    | .boolAnd dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = ({tempName lhs} != 0) & ({tempName rhs} != 0) ? 1 : 0;\n"
    | .boolOr dest lhs rhs =>
        out := out ++ pad ++
          s!"val {tempName dest} = ({tempName lhs} != 0) | ({tempName rhs} != 0) ? 1 : 0;\n"
    | .compare dest lhs rhs cop | .signedCompare dest lhs rhs cop =>
        out := out ++ pad ++
          s!"val {tempName dest} = {tempName lhs} {cmpOp cop} {tempName rhs} ? 1 : 0;\n"
    | .assert condition =>
        out := out ++ pad ++
          s!"assert ({tempName condition} != 0) throw {errAssert};\n"
    | .emitEvent eventIndex args =>
        out := out ++ pad ++ "val __pf_eb = beginCell().storeUint(" ++
          s!"{eventIndex}, 32)"
        for a in args do
          out := out ++ s!".storeUint({tempName a}, 64)"
        out := out ++ ".endCell();\n"
        out := out ++ pad ++
          "createExternalLogMessage({ dest: createAddressNone(), body: __pf_eb })" ++
          ".send(SEND_MODE_PAY_FEES_SEPARATELY);\n"
    | .promiseAccount receiver destHashHex method methodOp args =>
        -- Async internal out-message (schedule). Fixed policy documented on
        -- Plan Statement.promiseAccount:
        --   bounce = NoBounce; value = 0; send = PAY_FEES_SEPARATELY;
        --   dest = (0, SHA-256(UTF-8 receiver)) stub — not a live address;
        --   body = op32 · query_id=0 · arg64* (product internal-msg envelope).
        -- Message value economics are a later slice (MVP value is always 0).
        let _ := method  -- method name retained for audit; op is hash-derived
        let _ := receiver
        out := out ++ pad ++ "val __pf_sb = beginCell().storeUint(" ++
          s!"{methodOp}, 32).storeUint(0, 64)"
        for a in args do
          out := out ++ s!".storeUint({tempName a}, 64)"
        out := out ++ ".endCell();\n"
        out := out ++ pad ++
          "createMessage({\n"
        out := out ++ pad ++
          "    bounce: BounceMode.NoBounce,\n"
        out := out ++ pad ++
          "    value: 0,\n"
        out := out ++ pad ++
          s!"    dest: (0, 0x{destHashHex} as uint256),\n"
        out := out ++ pad ++
          "    body: __pf_sb\n"
        out := out ++ pad ++
          "}).send(SEND_MODE_PAY_FEES_SEPARATELY);\n"
    | .revertError errorIndex _args =>
        out := out ++ pad ++ s!"throw {errUserBase + errorIndex};\n"
    | .setReturnData value =>
        -- Message receivers cannot return stack values to callers; persist only.
        -- Get-methods use a separate render path that returns the value.
        out := out ++ pad ++ s!"// return value {tempName value} (message path: ignored)\n"
        out := out ++ pad ++ s!"val __pf_ret = {tempName value};\n"
    | .returnNone =>
        out := out ++ pad ++ "return;\n"
    | .returnValue value =>
        out := out ++ pad ++ s!"return {tempName value};\n"
    | .callFn fnIndex dest args =>
        let fname :=
          if fnIndex < plan.fns.size then plan.fns[fnIndex]!.name
          else s!"fn{fnIndex}"
        let argList := String.intercalate ", " (args.toList.map tempName)
        out := out ++ pad ++
          s!"val {tempName dest} = pf_fn_{fname}({argList});\n"
    | .ifRegion cond thenOps elseOps =>
        out := out ++ pad ++ s!"if ({tempName cond} != 0) \{\n"
        let (tBody, d1) := renderOps plan method? fn? thenOps (depth + 1) storageVar dirty
        out := out ++ tBody
        out := out ++ pad ++ "} else {\n"
        let (eBody, d2) := renderOps plan method? fn? elseOps (depth + 1) storageVar dirty
        out := out ++ eBody
        out := out ++ pad ++ "}\n"
        dirty := d1 || d2
    | .switchRegion scrut cases defaultOps =>
        out := out ++ pad ++ "do {\n"
        let mut first := true
        for (caseValue, caseOps) in cases do
          if first then
            out := out ++ pad ++ s!"    if ({tempName scrut} == {caseValue}) \{\n"
            first := false
          else
            out := out ++ pad ++ s!"    else if ({tempName scrut} == {caseValue}) \{\n"
          let (cBody, dC) := renderOps plan method? fn? caseOps (depth + 2) storageVar dirty
          out := out ++ cBody
          dirty := dirty || dC
          out := out ++ pad ++ "        break;\n"
          out := out ++ pad ++ "    }\n"
        out := out ++ pad ++ "    else {\n"
        let (dBody, dD) := renderOps plan method? fn? defaultOps (depth + 2) storageVar dirty
        out := out ++ dBody
        dirty := dirty || dD
        out := out ++ pad ++ "    }\n"
        out := out ++ pad ++ "} while (false);\n"
    | .forRegion varTemp initial counterTemp maxIter condOps condTemp
        bodyOps updateOps updateValue =>
        out := out ++ pad ++ s!"var {tempName varTemp} = {tempName initial};\n"
        out := out ++ pad ++ s!"var {tempName counterTemp} = 0;\n"
        out := out ++ pad ++ "while (true) {\n"
        let (cBody, _) := renderOps plan method? fn? condOps (depth + 1) storageVar dirty
        out := out ++ cBody
        out := out ++ pad ++ s!"    if (!({tempName condTemp} != 0)) \{ break; }\n"
        let (bBody, dB) := renderOps plan method? fn? bodyOps (depth + 1) storageVar dirty
        out := out ++ bBody
        dirty := dirty || dB
        out := out ++ pad ++
          s!"    {tempName counterTemp} = {tempName counterTemp} + 1;\n"
        out := out ++ pad ++
          s!"    assert ({tempName counterTemp} <= {maxIter}) throw {errLoopBound};\n"
        let (uBody, _) := renderOps plan method? fn? updateOps (depth + 1) storageVar dirty
        out := out ++ uBody
        out := out ++ pad ++
          s!"    {tempName varTemp} = {tempName updateValue};\n"
        out := out ++ pad ++ "}\n"
  pure (out, dirty)

private def renderStorageStruct (plan : Plan) : String := Id.run do
  let mut out := "struct Storage {\n"
  out := out ++ "    __layout: uint64\n"
  for field in plan.storage.fields do
    out := out ++ s!"    {field.name}: uint64\n"
  out := out ++ "}\n\n"
  out := out ++ "fun Storage.load(): Storage {\n"
  out := out ++ "    return Storage.fromCell(contract.getData());\n"
  out := out ++ "}\n\n"
  out := out ++ "fun Storage.save(self) {\n"
  out := out ++ "    contract.setData(self.toCell());\n"
  out := out ++ "}\n\n"
  pure out

private def renderPureFn (plan : Plan) (fn : FnIR) : String := Id.run do
  let mut params := ""
  for i in [0:fn.paramCount] do
    if i > 0 then params := params ++ ", "
    params := params ++ s!"{fnParamName fn i}: int"
  let mut out := s!"fun pf_fn_{fn.name}({params}): int \{\n"
  -- pureFn has no storage; dummy storage var unused
  let (body, _) := renderOps plan none (some fn) fn.operations 1 "storage" false
  out := out ++ body
  out := out ++ "}\n\n"
  pure out

private def renderViewMethod (plan : Plan) (method : MethodIR) : String := Id.run do
  let mut params := ""
  for i in [0:method.params.size] do
    if i > 0 then params := params ++ ", "
    let p := method.params[i]!
    params := params ++ s!"{p.name}: int"
  let mut out := s!"get fun {method.name}({params}): int \{\n"
  out := out ++ "    var storage = Storage.load();\n"
  let (body, _) := renderOps plan (some method) none method.operations 1 "storage" false
  out := out ++ body
  -- Ensure a return: setReturnData becomes __pf_ret
  out := out ++ "    return __pf_ret;\n"
  out := out ++ "}\n\n"
  pure out

private def renderMessageHandler (plan : Plan) (method : MethodIR) : String := Id.run do
  let mut out := s!"// op {method.opCode} → {method.name}\n"
  out := out ++ s!"if (op == {method.opCode}) \{\n"
  for p in method.params do
    out := out ++ s!"    val {p.name} = body.loadUint(64);\n"
  out := out ++ "    var storage = Storage.load();\n"
  let (body, dirty) := renderOps plan (some method) none method.operations 1 "storage" false
  out := out ++ body
  if dirty then
    out := out ++ "    storage.save();\n"
  out := out ++ "    return;\n"
  out := out ++ "}\n"
  pure out

private def renderTolk (ir : IR) : String := Id.run do
  let plan := ir.sourcePlan
  let mut out :=
    "// Generated by ProofForge V2 TON materializer (ton-tolk-boc-v1)\n" ++
    s!"// program: {plan.programName}\n" ++
    "// family: TVM stack-account; c4 flat Storage cell; async-only messaging\n" ++
    s!"// hostAbi: {plan.hostAbi}\n" ++
    s!"// inputAbi: {plan.inputAbi} (32-bit op + 64-bit query_id + u64 params)\n\n"
  out := out ++ renderStorageStruct plan
  for fn in ir.fns do
    out := out ++ renderPureFn plan fn
  -- Op constants
  for method in ir.methods do
    if method.mode == .initialize || method.mode == .mutate then
      out := out ++ s!"const OP_{method.name}: uint32 = {method.opCode};\n"
  out := out ++ "\n"
  out := out ++ "fun onInternalMessage(in: InMessage) {\n"
  out := out ++ "    var body = in.body;\n"
  out := out ++ "    // Require at least op (32) + query_id (64).\n"
  out := out ++ "    if (body.remainingBitsCount() < 96) {\n"
  out := out ++ "        return;\n"
  out := out ++ "    }\n"
  out := out ++ "    val op = body.loadUint(32);\n"
  out := out ++ "    val queryId = body.loadUint(64);\n"
  for method in ir.methods do
    if method.mode == .initialize || method.mode == .mutate then
      let handler := renderMessageHandler plan method
      -- indent handler one level
      for line in handler.splitOn "\n" do
        if line.isEmpty then
          out := out ++ "\n"
        else
          out := out ++ "    " ++ line ++ "\n"
  out := out ++ "    // Unknown op: ignore (no throw) for bounce safety.\n"
  out := out ++ "}\n\n"
  for method in ir.methods do
    if method.mode == .view then
      out := out ++ renderViewMethod plan method
  pure out

private def renderPfAbi (plan : Plan) (ir : IR) : String := Id.run do
  let fields := String.intercalate "," (plan.storage.fields.toList.map fun f =>
    s!"\{\"name\":\"{Targets.escapeJson f.name}\",\"type\":\"uint64\"}")
  let mut methodsJson : List String := []
  for m in ir.methods do
    let mode :=
      match m.mode with
      | .initialize => "init"
      | .mutate => "entry"
      | .view => "view"
    let params := String.intercalate "," (m.params.toList.map fun p =>
      s!"\{\"name\":\"{Targets.escapeJson p.name}\",\"type\":\"uint64\"}")
    methodsJson := methodsJson ++ [
      s!"\{\"name\":\"{Targets.escapeJson m.name}\",\"mode\":\"{mode}\",\"op\":{m.opCode},\"params\":[{params}]}"
    ]
  let methods := String.intercalate ",\n    " methodsJson
  pure <|
    "{\n" ++
    "  \"schema\": \"proof-forge-ton-abi/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson plan.programName}\",\n" ++
    s!"  \"codegenProfile\": \"{plan.codegenProfile}\",\n" ++
    s!"  \"hostAbi\": \"{plan.hostAbi}\",\n" ++
    s!"  \"encoding\": \"{plan.inputAbi}\",\n" ++
    "  \"messageEnvelope\": {\"opBits\":32,\"queryIdBits\":64,\"paramBits\":64},\n" ++
    "  \"storage\": {\"kind\":\"c4-flat-struct\",\"fields\":[" ++ fields ++
    s!",\"layoutMarker\":{plan.storage.markerValue}]" ++ "},\n" ++
    "  \"methods\": [\n    " ++ methods ++ "\n  ],\n" ++
    "  \"errorCodes\": {" ++
    s!"\"overflow\":{errOverflow},\"divZero\":{errDivZero},\"invalidShift\":{errInvalidShift}," ++
    s!"\"assert\":{errAssert},\"loopBound\":{errLoopBound},\"layout\":{errLayout},\"userBase\":{errUserBase}" ++
    "}\n" ++
    "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  return #[
    {
      path := s!"{ir.name}.tolk"
      mediaType := "text/x-tolk"
      contents := renderTolk ir
    },
    {
      path := s!"{ir.name}.ton-abi.json"
      mediaType := "application/json"
      contents := renderPfAbi ir.sourcePlan ir
    }
  ]

def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

end ProofForgeV2.Targets.Ton
