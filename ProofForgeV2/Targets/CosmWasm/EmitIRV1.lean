import ProofForgeV2.Targets.CosmWasm.ValidatePlanV1

/-!
# CosmWasm EmitIRV1 — Plan → IR → WAT emission

CosmWasm-owned host-call recipe IR with Region/JSON entry ABI:
* imports: `env.db_read` / `env.db_write` / `env.db_remove` / `env.abort`
* exports: `allocate` / `deallocate` / `interface_version_8` /
  `instantiate` / `execute` / `query`
* memory: exactly one linear memory, min=1, no maximum
* Region = 12-byte `{offset:u32, capacity:u32, length:u32}`
* entry JSON subset: flat instantiate params; execute/query
  `{"method":{...params...}}` with decimal integer fields
* results: `ContractResult` JSON (`ok` Response with attributes, or `error`)
* emit → Response attributes; revert → `{"error":...}` / `abort`

Not wasmd runtime / cosmwasm-check acceptance (A2). Not formal D4.
-/

namespace ProofForgeV2.Targets.CosmWasm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

inductive Operation where
  | requireLayoutAbsent (marker : KeyRegion)
  | requireLayout (marker : KeyRegion) (value : UInt64)
  | zeroState (field : KeyRegion)
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination inputOffset : Nat)
  | loadState (destination : Nat) (field : KeyRegion)
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
  | storeState (field : KeyRegion) (value : Nat)
  | setLayout (marker : KeyRegion) (value : UInt64)
  | setReturnData (value : Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat)
  | emitEvent (eventIndex : Nat) (args : Array Nat)
  | revertError (errorIndex : Nat) (args : Array Nat)
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

/-- Typed CosmWasm host-call/Wasm recipe.
    Private `mk`: public Plan→IR construction is capability-gated only. -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  imports : Array HostImport
  keys : Array KeyRegion
  memory : MemoryLayout
  methods : Array MethodIR
  fns : Array FnIR
  deriving BEq, Repr

private def align8 (value : Nat) : Nat :=
  ((value + 7) / 8) * 8

/-- Pack key bytes contiguously from offset 64 (leave low addresses for
    allocator metadata / small scratch). Each KeyRegion.offset points at the
    UTF-8 key bytes; Regions for db_* are built at runtime over these bytes. -/
private def makeKeyRegions (plan : Plan) : Array KeyRegion := Id.run do
  let mut regions : Array KeyRegion := #[]
  let mut offset := 64
  let markerLength := plan.storage.markerKey.toUTF8.size
  regions := regions.push { key := plan.storage.markerKey, offset, length := markerLength }
  offset := offset + markerLength
  for field in plan.storage.fields do
    let length := field.key.toUTF8.size
    regions := regions.push { key := field.key, offset, length }
    offset := offset + length
  return regions

/-- CosmWasm memory: one page min, no maximum (exported). Static key data in low
    memory; bump heap starts at 4096; JSON/result scratch at 2048. -/
private def makeMemoryLayout (plan : Plan) (keys : Array KeyRegion) : MemoryLayout :=
  let keysEnd := keys.foldl (fun current key => max current (key.offset + key.length)) 64
  let scratchOffset := align8 (max keysEnd 256)
  {
    minPages := plan.resourceLimits.wasmMemoryPages
    inputOffset := scratchOffset          -- reused as JSON/result scratch base
    inputCapacity := 1536
    depositOffset := scratchOffset + 1536 -- attribute buffer base
    valueOffset := scratchOffset + 1536 + 512  -- 8-byte value cell / region temp
  }

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private def fieldRegion (keys : Array KeyRegion) (fieldIndex : Nat) : KeyRegion :=
  keys[fieldIndex + 1]!

private partial def lowerExpr (keys : Array KeyRegion) (next : Nat)
    (paramAsTemp : Bool) (localEnv : Array (Nat × Nat)) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .bigLiteral _ value =>
      -- Multiword FC at plan; defensive: truncate to low 64.
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
      {
        operations := #[.loadState next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .narrowStateLoad _ fieldIndex =>
      {
        operations := #[.loadState next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedMul lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedDiv lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedMod lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedAdd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedAdd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedSub lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedSub rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedMul lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMul rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedDiv lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedDiv rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCheckedMod lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMod rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .signedCompare op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.signedCompare rhs.next lhs.value rhs.value op]
        value := rhs.next, next := rhs.next + 1 }
  | .checkedNeg operand =>
      let op := lowerExpr keys next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.checkedNeg op.next op.value]
        value := op.next, next := op.next + 1 }
  | .bitAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .bitOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .bitXor lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .shl lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shl rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .shr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .sar lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.sar rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .bitNot operand =>
      let op := lowerExpr keys next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.bitNot op.next op.value]
        value := op.next, next := op.next + 1 }
  | .narrowCheckedAdd _ lhs rhs | .narrowCheckedSub _ lhs rhs
  | .narrowCheckedMul _ lhs rhs | .narrowCheckedDiv _ lhs rhs
  | .narrowCheckedMod _ lhs rhs =>
      -- Multi-width FC: treat as full-width checked (only reached via hand-built Plan).
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitAnd _ lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitOr _ lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitXor _ lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowBitNot _ operand =>
      let op := lowerExpr keys next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.bitNot op.next op.value]
        value := op.next, next := op.next + 1 }
  | .narrowShl _ lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shl rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .narrowShr _ lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.shr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .boolNot operand =>
      let op := lowerExpr keys next paramAsTemp localEnv operand
      { operations := op.operations ++ #[.boolNot op.next op.value]
        value := op.next, next := op.next + 1 }
  | .boolAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.boolAnd rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .boolOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.boolOr rhs.next lhs.value rhs.value]
        value := rhs.next, next := rhs.next + 1 }
  | .compare op lhs rhs | .wideCompare _ op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      { operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next, next := rhs.next + 1 }
  | .callFn fnIndex args =>
      Id.run do
        let mut ops : Array Operation := #[]
        let mut cur := next
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let lowered := lowerExpr keys cur paramAsTemp localEnv arg
          ops := ops ++ lowered.operations
          argTemps := argTemps.push lowered.value
          cur := lowered.next
        ops := ops.push (.callFn fnIndex cur argTemps)
        pure { operations := ops, value := cur, next := cur + 1 }

private partial def lowerBodyOps (keys : Array KeyRegion) (next : Nat)
    (body : Array Statement) (fnMode : Bool) (localEnv : Array (Nat × Nat))
    (_returnByteLen : Nat) : Array Operation × Nat := Id.run do
  let mut operations : Array Operation := #[]
  let mut next := next
  let mut localEnv := localEnv
  for stmt in body do
    match stmt with
    | .store op =>
        let value := lowerExpr keys next fnMode localEnv op.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState (fieldRegion keys op.fieldIndex) value.value)
        next := value.next
    | .storeAtomic leaves =>
        -- Evaluate all leaf exprs first, then write (pre-store snapshot).
        let mut vals : Array (Nat × Nat) := #[]  -- (fieldIndex, temp)
        for leaf in leaves do
          let value := lowerExpr keys next fnMode localEnv leaf.value
          operations := operations ++ value.operations
          vals := vals.push (leaf.fieldIndex, value.value)
          next := value.next
        for (fieldIndex, temp) in vals do
          operations := operations.push (.storeState (fieldRegion keys fieldIndex) temp)
    | .returnValue value =>
        let value := lowerExpr keys next fnMode localEnv value
        operations := operations ++ value.operations
        if fnMode then
          operations := operations.push (.returnValue value.value)
        else
          operations := operations.push (.setReturnData value.value)
        next := value.next
    | .returnNone =>
        operations := operations.push .returnNone
    | .assert condition =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations ++ #[.assert value.value]
        next := value.next
    | .emitEvent eventIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.emitEvent eventIndex argTemps)
    | .revertError errorIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.revertError errorIndex argTemps)
    | .promiseAccount .. =>
        -- Plan validate rejects; defensive no-op sink.
        pure ()
    | .ifThenElse condition thenBody elseBody =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations
        let (thenOps, next1) := lowerBodyOps keys value.next thenBody fnMode localEnv _returnByteLen
        let (elseOps, next2) := lowerBodyOps keys next1 elseBody fnMode localEnv _returnByteLen
        operations := operations.push (.ifRegion value.value thenOps elseOps)
        next := next2
    | .switchOn scrutinee cases defaultBody =>
        let value := lowerExpr keys next fnMode localEnv scrutinee
        operations := operations ++ value.operations
        let mut caseOps : Array (UInt64 × Array Operation) := #[]
        let mut nextC := value.next
        for (caseValue, caseBody) in cases do
          let (ops, next1) := lowerBodyOps keys nextC caseBody fnMode localEnv _returnByteLen
          caseOps := caseOps.push (caseValue, ops)
          nextC := next1
        let (defaultOps, nextD) := lowerBodyOps keys nextC defaultBody fnMode localEnv _returnByteLen
        operations := operations.push (.switchRegion value.value caseOps defaultOps)
        next := nextD
    | .forLoop varTemp initial condition update maxIterations body =>
        let initL := lowerExpr keys next fnMode localEnv initial
        operations := operations ++ initL.operations
        let irVar := initL.next
        let counterTemp := initL.next + 1
        next := initL.next + 2
        let localEnv' := localEnv.push (varTemp, irVar)
        let condL := lowerExpr keys next fnMode localEnv' condition
        let condOps := condL.operations
        let condTemp := condL.value
        next := condL.next
        let (bodyOps, nextB) := lowerBodyOps keys next body fnMode localEnv' _returnByteLen
        next := nextB
        let updateL := lowerExpr keys next fnMode localEnv' update
        let updateOps := updateL.operations
        let updateTemp := updateL.value
        next := updateL.next
        operations := operations.push
          (.forRegion irVar initL.value counterTemp maxIterations
            condOps condTemp bodyOps updateOps updateTemp)
        localEnv := localEnv'
  pure (operations, next)

private def lowerMethod (plan : Plan) (keys : Array KeyRegion)
    (method : Method) : MethodIR := Id.run do
  let marker := keys[0]!
  let mut operations : Array Operation := #[]
  if method.mode == .initialize then
    operations := operations.push (.requireLayoutAbsent marker)
    for index in [0:plan.storage.fields.size] do
      operations := operations.push (.zeroState (fieldRegion keys index))
  else
    operations := operations.push (.requireLayout marker plan.storage.markerValue)
  let body := if method.body.back? == some .returnNone then
    method.body.pop
  else
    method.body
  let (bodyOps, next) := lowerBodyOps keys 0 body false #[] 8
  operations := operations ++ bodyOps
  if method.mode == .initialize then
    operations := operations.push (.setLayout marker plan.storage.markerValue)
  return {
    name := method.name
    params := method.params
    mode := method.mode
    resultKind := method.resultKind
    tempCount := next
    operations
  }

private def lowerFn (keys : Array KeyRegion) (fn : FnBinding) : FnIR :=
  let paramCount := fn.params.size
  let (bodyOps, next) := lowerBodyOps keys paramCount fn.body true #[] 8
  {
    name := fn.name
    paramCount
    resultIsBool := fn.resultIsBool
    tempCount := next
    operations := bodyOps
  }

private def expectedMethods (plan : Plan) (keys : Array KeyRegion) : Array MethodIR :=
  #[lowerMethod plan keys plan.initializer] ++ plan.entries.map (lowerMethod plan keys)

private def expectedFns (plan : Plan) (keys : Array KeyRegion) : Array FnIR :=
  plan.fns.map (lowerFn keys)

private partial def opIsMethodOnlyV1 : Operation → Bool
  | .requireLayoutAbsent _ | .requireLayout _ _
  | .zeroState _ | .loadState _ _ | .storeState _ _
  | .setLayout _ _ | .setReturnData _ | .loadParam _ _ => true
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
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR identity is not bound to its source Plan"
  unless ir.imports == ir.sourcePlan.hostImports do
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR host imports are not canonical"
  let expectedKeys := makeKeyRegions ir.sourcePlan
  unless ir.keys == expectedKeys do
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR key regions are not bound to the Plan KV layout"
  let expectedMemory := makeMemoryLayout ir.sourcePlan expectedKeys
  unless ir.memory == expectedMemory &&
      ir.memory.minPages == ir.sourcePlan.resourceLimits.wasmMemoryPages do
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR memory layout is not canonical"
  if ir.methods.size != ir.sourcePlan.entries.size + 1 then
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR export count does not match its source Plan"
  if ir.fns.size != ir.sourcePlan.fns.size then
    throw <| .planInvariant .cosmwasm "typed CosmWasm IR pureFn count does not match its source Plan"
  for method in ir.methods do
    if method.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .cosmwasm
        s!"typed CosmWasm IR method '{method.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if method.operations.any opIsFnReturnValueV1 then
      throw <| .planInvariant .cosmwasm
        s!"typed CosmWasm IR method '{method.name}' must not use pureFn returnValue ops"
  for fn in ir.fns do
    if fn.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .cosmwasm
        s!"typed CosmWasm IR pureFn '{fn.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if fn.operations.any opIsMethodOnlyV1 then
      throw <| .planInvariant .cosmwasm
        s!"typed CosmWasm IR pureFn '{fn.name}' must not use method-only host ops"
  let expected := expectedMethods ir.sourcePlan expectedKeys
  unless ir.methods == expected do
    throw <| .planInvariant .cosmwasm
      "typed CosmWasm IR methods/operations are not the exact lowering of their source Plan"
  let expectedFnIR := expectedFns ir.sourcePlan expectedKeys
  unless ir.fns == expectedFnIR do
    throw <| .planInvariant .cosmwasm
      "typed CosmWasm IR pureFn operations are not the exact lowering of their source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let keys := makeKeyRegions plan
  let memory := makeMemoryLayout plan keys
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    imports := plan.hostImports
    keys
    memory
    methods := expectedMethods plan keys
    fns := expectedFns plan keys
  }
  validateIR ir
  return ir

/-- Replace methods on an existing IR (private `mk`; for validateIR characterization). -/
def withMethods (ir : IR) (methods : Array MethodIR) : IR :=
  { ir with methods }

def withFns (ir : IR) (fns : Array FnIR) : IR :=
  { ir with fns }

/-! ### WAT rendering (CosmWasm Region / JSON / db_*) -/

private def renderImport : HostImport → String
  | .dbRead =>
      "  (import \"env\" \"db_read\" (func $db_read (param i32) (result i32)))\n"
  | .dbWrite =>
      "  (import \"env\" \"db_write\" (func $db_write (param i32 i32)))\n"
  | .dbRemove =>
      "  (import \"env\" \"db_remove\" (func $db_remove (param i32)))\n"
  | .abort =>
      "  (import \"env\" \"abort\" (func $abort (param i32)))\n"

/-- Shared runtime helpers: bump allocate, Region builders, db load/store U64,
    JSON ok/error result builders, minimal JSON integer field scan. -/
private def renderRuntimeHelpers (memory : MemoryLayout) : String :=
  let heapInit := 4096
  let scratch := memory.inputOffset
  let attrBase := memory.depositOffset
  let valueCell := memory.valueOffset
  -- Keep helpers compact but complete for Counter MVP.
  s!"  (global $heap (mut i32) (i32.const {heapInit}))\n" ++
  s!"  (global $attr_len (mut i32) (i32.const 0))\n" ++
  s!"  (global $ret_kind (mut i32) (i32.const 0))\n" ++  -- 0=none 1=u64 2=bool 3=i64
  s!"  (global $ret_val (mut i64) (i64.const 0))\n" ++
  -- allocate(size) -> region_ptr: Region{offset=data, capacity=size, length=size}
  "  (func $pf_allocate (param $size i32) (result i32)\n" ++
  "    (local $region i32) (local $data i32) (local $h i32)\n" ++
  "    (local.set $h (global.get $heap))\n" ++
  "    (local.set $region (local.get $h))\n" ++
  "    (local.set $data (i32.add (local.get $h) (i32.const 16)))\n" ++
  "    (i32.store (local.get $region) (local.get $data))\n" ++
  "    (i32.store offset=4 (local.get $region) (local.get $size))\n" ++
  "    (i32.store offset=8 (local.get $region) (local.get $size))\n" ++
  "    (global.set $heap (i32.add (local.get $data) (i32.and (i32.add (local.get $size) (i32.const 7)) (i32.const -8))))\n" ++
  "    (local.get $region)\n" ++
  "  )\n" ++
  -- region over static key bytes (length fixed, no copy)
  "  (func $pf_key_region (param $off i32) (param $len i32) (result i32)\n" ++
  "    (local $region i32)\n" ++
  "    (local.set $region (global.get $heap))\n" ++
  "    (global.set $heap (i32.add (local.get $region) (i32.const 16)))\n" ++
  "    (i32.store (local.get $region) (local.get $off))\n" ++
  "    (i32.store offset=4 (local.get $region) (local.get $len))\n" ++
  "    (i32.store offset=8 (local.get $region) (local.get $len))\n" ++
  "    (local.get $region)\n" ++
  "  )\n" ++
  -- write u64 value into a fresh region
  "  (func $pf_u64_region (param $v i64) (result i32)\n" ++
  "    (local $region i32) (local $data i32)\n" ++
  "    (local.set $region (call $pf_allocate (i32.const 8)))\n" ++
  "    (local.set $data (i32.load (local.get $region)))\n" ++
  "    (i64.store (local.get $data) (local.get $v))\n" ++
  "    (local.get $region)\n" ++
  "  )\n" ++
  -- db_read key → u64 (trap if missing or wrong len)
  "  (func $pf_db_load_u64 (param $key_off i32) (param $key_len i32) (result i64)\n" ++
  "    (local $key_r i32) (local $val_r i32) (local $data i32) (local $len i32)\n" ++
  "    (local.set $key_r (call $pf_key_region (local.get $key_off) (local.get $key_len)))\n" ++
  "    (local.set $val_r (call $db_read (local.get $key_r)))\n" ++
  "    (if (i32.eqz (local.get $val_r)) (then unreachable))\n" ++
  "    (local.set $len (i32.load offset=8 (local.get $val_r)))\n" ++
  "    (if (i32.ne (local.get $len) (i32.const 8)) (then unreachable))\n" ++
  "    (local.set $data (i32.load (local.get $val_r)))\n" ++
  "    (i64.load (local.get $data))\n" ++
  "  )\n" ++
  -- db_write key ← u64
  "  (func $pf_db_store_u64 (param $key_off i32) (param $key_len i32) (param $v i64)\n" ++
  "    (local $key_r i32) (local $val_r i32)\n" ++
  "    (local.set $key_r (call $pf_key_region (local.get $key_off) (local.get $key_len)))\n" ++
  "    (local.set $val_r (call $pf_u64_region (local.get $v)))\n" ++
  "    (call $db_write (local.get $key_r) (local.get $val_r))\n" ++
  "  )\n" ++
  -- db_read presence (0/1)
  "  (func $pf_db_has (param $key_off i32) (param $key_len i32) (result i32)\n" ++
  "    (local $key_r i32) (local $val_r i32)\n" ++
  "    (local.set $key_r (call $pf_key_region (local.get $key_off) (local.get $key_len)))\n" ++
  "    (local.set $val_r (call $db_read (local.get $key_r)))\n" ++
  "    (i32.ne (local.get $val_r) (i32.const 0))\n" ++
  "  )\n" ++
  -- build error JSON region {"error":"<msg>"} and return it (for ContractResult::Err)
  "  (func $pf_error_result (param $msg_off i32) (param $msg_len i32) (result i32)\n" ++
  s!"    (local $region i32) (local $data i32) (local $i i32) (local $p i32)\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.add (local.get $msg_len) (i32.const 16))))\n" ++
  s!"    (local.set $data (i32.load (local.get $region)))\n" ++
  -- {"error":"
  s!"    (i32.store8 (local.get $data) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=1 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $data) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=3 (local.get $data) (i32.const 114))\n" ++
  s!"    (i32.store8 offset=4 (local.get $data) (i32.const 114))\n" ++
  s!"    (i32.store8 offset=5 (local.get $data) (i32.const 111))\n" ++
  s!"    (i32.store8 offset=6 (local.get $data) (i32.const 114))\n" ++
  s!"    (i32.store8 offset=7 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=8 (local.get $data) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=9 (local.get $data) (i32.const 34))\n" ++
  s!"    (local.set $p (i32.add (local.get $data) (i32.const 10)))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $copy_done\n" ++
  s!"      (loop $copy\n" ++
  s!"        (br_if $copy_done (i32.ge_u (local.get $i) (local.get $msg_len)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $p) (local.get $i)) (i32.load8_u (i32.add (local.get $msg_off) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $copy)))\n" ++
  s!"    (i32.store8 (i32.add (local.get $p) (local.get $msg_len)) (i32.const 34))\n" ++
  s!"    (i32.store8 (i32.add (i32.add (local.get $p) (local.get $msg_len)) (i32.const 1)) (i32.const 125))\n" ++
  s!"    (i32.store offset=8 (local.get $region) (i32.add (local.get $msg_len) (i32.const 12)))\n" ++
  s!"    (local.get $region)\n" ++
  "  )\n" ++
  -- format unsigned decimal of i64 into scratch; returns length
  s!"  (func $pf_fmt_u64 (param $v i64) (param $dst i32) (result i32)\n" ++
  s!"    (local $tmp i64) (local $n i32) (local $i i32) (local $d i32)\n" ++
  s!"    (if (i64.eqz (local.get $v)) (then\n" ++
  s!"      (i32.store8 (local.get $dst) (i32.const 48))\n" ++
  s!"      (return (i32.const 1))))\n" ++
  s!"    (local.set $tmp (local.get $v))\n" ++
  s!"    (local.set $n (i32.const 0))\n" ++
  s!"    (block $done_count\n" ++
  s!"      (loop $count\n" ++
  s!"        (br_if $done_count (i64.eqz (local.get $tmp)))\n" ++
  s!"        (local.set $tmp (i64.div_u (local.get $tmp) (i64.const 10)))\n" ++
  s!"        (local.set $n (i32.add (local.get $n) (i32.const 1)))\n" ++
  s!"        (br $count)))\n" ++
  s!"    (local.set $tmp (local.get $v))\n" ++
  s!"    (local.set $i (local.get $n))\n" ++
  s!"    (block $done_write\n" ++
  s!"      (loop $write\n" ++
  s!"        (br_if $done_write (i32.eqz (local.get $i)))\n" ++
  s!"        (local.set $i (i32.sub (local.get $i) (i32.const 1)))\n" ++
  s!"        (local.set $d (i32.wrap_i64 (i64.rem_u (local.get $tmp) (i64.const 10))))\n" ++
  s!"        (i32.store8 (i32.add (local.get $dst) (local.get $i)) (i32.add (local.get $d) (i32.const 48)))\n" ++
  s!"        (local.set $tmp (i64.div_u (local.get $tmp) (i64.const 10)))\n" ++
  s!"        (br $write)))\n" ++
  s!"    (local.get $n)\n" ++
  "  )\n" ++
  -- build ok Response JSON with attributes buffer + optional result attribute
  -- attributes are pre-built at attrBase as comma-separated {"key":"...","value":"..."} items
  s!"  (func $pf_ok_result (result i32)\n" ++
  s!"    (local $region i32) (local $data i32) (local $p i32) (local $n i32) (local $alen i32) (local $i i32)\n" ++
  "    ;; prefix: ok Response JSON with attributes array\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.const 1024)))\n" ++
  s!"    (local.set $data (i32.load (local.get $region)))\n" ++
  s!"    (local.set $p (local.get $data))\n" ++
  -- write fixed prefix via i32 stores of ASCII
  s!"    (i32.store8 (local.get $p) (i32.const 123))\n" ++  -- {
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 111))\n" ++  -- o
  s!"    (i32.store8 offset=3 (local.get $p) (i32.const 107))\n" ++  -- k
  s!"    (i32.store8 offset=4 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=5 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=6 (local.get $p) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=7 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=8 (local.get $p) (i32.const 109))\n" ++  -- messages
  s!"    (i32.store8 offset=9 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=10 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=11 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=12 (local.get $p) (i32.const 97))\n" ++
  s!"    (i32.store8 offset=13 (local.get $p) (i32.const 103))\n" ++
  s!"    (i32.store8 offset=14 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=15 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=16 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=17 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=18 (local.get $p) (i32.const 91))\n" ++
  s!"    (i32.store8 offset=19 (local.get $p) (i32.const 93))\n" ++
  s!"    (i32.store8 offset=20 (local.get $p) (i32.const 44))\n" ++
  s!"    (i32.store8 offset=21 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=22 (local.get $p) (i32.const 97))\n" ++  -- attributes
  s!"    (i32.store8 offset=23 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=24 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=25 (local.get $p) (i32.const 114))\n" ++
  s!"    (i32.store8 offset=26 (local.get $p) (i32.const 105))\n" ++
  s!"    (i32.store8 offset=27 (local.get $p) (i32.const 98))\n" ++
  s!"    (i32.store8 offset=28 (local.get $p) (i32.const 117))\n" ++
  s!"    (i32.store8 offset=29 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=30 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=31 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=32 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=33 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=34 (local.get $p) (i32.const 91))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 35)))\n" ++
  -- append collected attributes
  s!"    (local.set $alen (global.get $attr_len))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $acopy_done\n" ++
  s!"      (loop $acopy\n" ++
  s!"        (br_if $acopy_done (i32.ge_u (local.get $i) (local.get $alen)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $p) (local.get $i)) (i32.load8_u (i32.add (i32.const {attrBase}) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $acopy)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $alen)))\n" ++
  -- if return value present, append result attribute
  s!"    (if (i32.ne (global.get $ret_kind) (i32.const 0)) (then\n" ++
  s!"      (if (i32.ne (local.get $alen) (i32.const 0)) (then\n" ++
  s!"        (i32.store8 (local.get $p) (i32.const 44))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))))\n" ++
  "      ;; result attribute object\n" ++
  s!"      (i32.store8 (local.get $p) (i32.const 123))\n" ++
  s!"      (i32.store8 offset=1 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=2 (local.get $p) (i32.const 107))\n" ++
  s!"      (i32.store8 offset=3 (local.get $p) (i32.const 101))\n" ++
  s!"      (i32.store8 offset=4 (local.get $p) (i32.const 121))\n" ++
  s!"      (i32.store8 offset=5 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=6 (local.get $p) (i32.const 58))\n" ++
  s!"      (i32.store8 offset=7 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=8 (local.get $p) (i32.const 114))\n" ++
  s!"      (i32.store8 offset=9 (local.get $p) (i32.const 101))\n" ++
  s!"      (i32.store8 offset=10 (local.get $p) (i32.const 115))\n" ++
  s!"      (i32.store8 offset=11 (local.get $p) (i32.const 117))\n" ++
  s!"      (i32.store8 offset=12 (local.get $p) (i32.const 108))\n" ++
  s!"      (i32.store8 offset=13 (local.get $p) (i32.const 116))\n" ++
  s!"      (i32.store8 offset=14 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=15 (local.get $p) (i32.const 44))\n" ++
  s!"      (i32.store8 offset=16 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=17 (local.get $p) (i32.const 118))\n" ++
  s!"      (i32.store8 offset=18 (local.get $p) (i32.const 97))\n" ++
  s!"      (i32.store8 offset=19 (local.get $p) (i32.const 108))\n" ++
  s!"      (i32.store8 offset=20 (local.get $p) (i32.const 117))\n" ++
  s!"      (i32.store8 offset=21 (local.get $p) (i32.const 101))\n" ++
  s!"      (i32.store8 offset=22 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=23 (local.get $p) (i32.const 58))\n" ++
  s!"      (i32.store8 offset=24 (local.get $p) (i32.const 34))\n" ++
  s!"      (local.set $p (i32.add (local.get $p) (i32.const 25)))\n" ++
  s!"      (local.set $n (call $pf_fmt_u64 (global.get $ret_val) (local.get $p)))\n" ++
  s!"      (local.set $p (i32.add (local.get $p) (local.get $n)))\n" ++
  s!"      (i32.store8 (local.get $p) (i32.const 34))\n" ++
  s!"      (i32.store8 offset=1 (local.get $p) (i32.const 125))\n" ++
  s!"      (local.set $p (i32.add (local.get $p) (i32.const 2)))))\n" ++
  -- close: ],"events":[],"data":null}}
  s!"    (i32.store8 (local.get $p) (i32.const 93))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 44))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=3 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=4 (local.get $p) (i32.const 118))\n" ++
  s!"    (i32.store8 offset=5 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=6 (local.get $p) (i32.const 110))\n" ++
  s!"    (i32.store8 offset=7 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=8 (local.get $p) (i32.const 115))\n" ++
  s!"    (i32.store8 offset=9 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=10 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=11 (local.get $p) (i32.const 91))\n" ++
  s!"    (i32.store8 offset=12 (local.get $p) (i32.const 93))\n" ++
  s!"    (i32.store8 offset=13 (local.get $p) (i32.const 44))\n" ++
  s!"    (i32.store8 offset=14 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=15 (local.get $p) (i32.const 100))\n" ++
  s!"    (i32.store8 offset=16 (local.get $p) (i32.const 97))\n" ++
  s!"    (i32.store8 offset=17 (local.get $p) (i32.const 116))\n" ++
  s!"    (i32.store8 offset=18 (local.get $p) (i32.const 97))\n" ++
  s!"    (i32.store8 offset=19 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=20 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=21 (local.get $p) (i32.const 110))\n" ++
  s!"    (i32.store8 offset=22 (local.get $p) (i32.const 117))\n" ++
  s!"    (i32.store8 offset=23 (local.get $p) (i32.const 108))\n" ++
  s!"    (i32.store8 offset=24 (local.get $p) (i32.const 108))\n" ++
  s!"    (i32.store8 offset=25 (local.get $p) (i32.const 125))\n" ++
  s!"    (i32.store8 offset=26 (local.get $p) (i32.const 125))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 27)))\n" ++
  s!"    (i32.store offset=8 (local.get $region) (i32.sub (local.get $p) (local.get $data)))\n" ++
  s!"    (local.get $region)\n" ++
  "  )\n" ++
  -- query ok: {"ok":"<decimal>"} as binary-as-utf8 (not base64 — MVP query data is decimal text)
  s!"  (func $pf_query_ok (param $v i64) (result i32)\n" ++
  s!"    (local $region i32) (local $data i32) (local $p i32) (local $n i32)\n" ++
  s!"    (local.set $region (call $pf_allocate (i32.const 64)))\n" ++
  s!"    (local.set $data (i32.load (local.get $region)))\n" ++
  s!"    (i32.store8 (local.get $data) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=1 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $data) (i32.const 111))\n" ++
  s!"    (i32.store8 offset=3 (local.get $data) (i32.const 107))\n" ++
  s!"    (i32.store8 offset=4 (local.get $data) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=5 (local.get $data) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=6 (local.get $data) (i32.const 34))\n" ++
  s!"    (local.set $p (i32.add (local.get $data) (i32.const 7)))\n" ++
  s!"    (local.set $n (call $pf_fmt_u64 (local.get $v) (local.get $p)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $n)))\n" ++
  s!"    (i32.store8 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 125))\n" ++
  s!"    (i32.store offset=8 (local.get $region) (i32.add (local.get $n) (i32.const 9)))\n" ++
  s!"    (local.get $region)\n" ++
  "  )\n" ++
  -- find substring needle in haystack (byte compare); return start index or 0xFFFFFFFF
  s!"  (func $pf_find (param $hay i32) (param $hay_len i32) (param $needle i32) (param $needle_len i32) (result i32)\n" ++
  s!"    (local $i i32) (local $j i32) (local $ok i32)\n" ++
  s!"    (if (i32.gt_u (local.get $needle_len) (local.get $hay_len)) (then (return (i32.const -1))))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $outer_done\n" ++
  s!"      (loop $outer\n" ++
  s!"        (br_if $outer_done (i32.gt_u (i32.add (local.get $i) (local.get $needle_len)) (local.get $hay_len)))\n" ++
  s!"        (local.set $j (i32.const 0))\n" ++
  s!"        (local.set $ok (i32.const 1))\n" ++
  s!"        (block $inner_done\n" ++
  s!"          (loop $inner\n" ++
  s!"            (br_if $inner_done (i32.ge_u (local.get $j) (local.get $needle_len)))\n" ++
  s!"            (if (i32.ne (i32.load8_u (i32.add (local.get $hay) (i32.add (local.get $i) (local.get $j))))\n" ++
  s!"                       (i32.load8_u (i32.add (local.get $needle) (local.get $j)))) (then\n" ++
  s!"              (local.set $ok (i32.const 0))\n" ++
  s!"              (br $inner_done)))\n" ++
  s!"            (local.set $j (i32.add (local.get $j) (i32.const 1)))\n" ++
  s!"            (br $inner)))\n" ++
  s!"        (if (local.get $ok) (then (return (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $outer)))\n" ++
  s!"    (i32.const -1)\n" ++
  "  )\n" ++
  -- parse unsigned decimal after a field name \"name\":NUMBER starting search at from
  s!"  (func $pf_parse_u64_field (param $hay i32) (param $hay_len i32) (param $name i32) (param $name_len i32) (result i64)\n" ++
  s!"    (local $idx i32) (local $p i32) (local $end i32) (local $c i32) (local $v i64) (local $any i32)\n" ++
  s!"    (local.set $idx (call $pf_find (local.get $hay) (local.get $hay_len) (local.get $name) (local.get $name_len)))\n" ++
  s!"    (if (i32.eq (local.get $idx) (i32.const -1)) (then unreachable))\n" ++
  s!"    (local.set $p (i32.add (i32.add (local.get $hay) (local.get $idx)) (local.get $name_len)))\n" ++
  s!"    (local.set $end (i32.add (local.get $hay) (local.get $hay_len)))\n" ++
  -- skip to ':'
  s!"    (block $find_colon\n" ++
  s!"      (loop $sc\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then unreachable))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br_if $find_colon (i32.eq (local.get $c) (i32.const 58)))\n" ++
  s!"        (br $sc)))\n" ++
  -- skip spaces
  s!"    (block $skip_sp\n" ++
  s!"      (loop $sp\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then (br $skip_sp)))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (br_if $skip_sp (i32.ne (local.get $c) (i32.const 32)))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $sp)))\n" ++
  s!"    (local.set $v (i64.const 0))\n" ++
  s!"    (local.set $any (i32.const 0))\n" ++
  s!"    (block $num_done\n" ++
  s!"      (loop $num\n" ++
  s!"        (if (i32.ge_u (local.get $p) (local.get $end)) (then (br $num_done)))\n" ++
  s!"        (local.set $c (i32.load8_u (local.get $p)))\n" ++
  s!"        (br_if $num_done (i32.or (i32.lt_u (local.get $c) (i32.const 48)) (i32.gt_u (local.get $c) (i32.const 57))))\n" ++
  s!"        (local.set $v (i64.add (i64.mul (local.get $v) (i64.const 10)) (i64.extend_i32_u (i32.sub (local.get $c) (i32.const 48)))))\n" ++
  s!"        (local.set $any (i32.const 1))\n" ++
  s!"        (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"        (br $num)))\n" ++
  s!"    (if (i32.eqz (local.get $any)) (then unreachable))\n" ++
  s!"    (local.get $v)\n" ++
  "  )\n" ++
  -- region payload view: (offset, length) from region ptr
  s!"  (func $pf_region_off (param $r i32) (result i32) (i32.load (local.get $r)))\n" ++
  s!"  (func $pf_region_len (param $r i32) (result i32) (i32.load offset=8 (local.get $r)))\n" ++
  -- reset per-entry attribute/return state
  s!"  (func $pf_reset_result\n" ++
  s!"    (global.set $attr_len (i32.const 0))\n" ++
  s!"    (global.set $ret_kind (i32.const 0))\n" ++
  s!"    (global.set $ret_val (i64.const 0))\n" ++
  "  )\n" ++
  -- append attribute {"key":"K","value":"V"} where V is decimal of u64 temp
  s!"  (func $pf_push_attr_u64 (param $key_off i32) (param $key_len i32) (param $v i64)\n" ++
  s!"    (local $p i32) (local $n i32) (local $i i32)\n" ++
  s!"    (local.set $p (i32.add (i32.const {attrBase}) (global.get $attr_len)))\n" ++
  s!"    (if (i32.ne (global.get $attr_len) (i32.const 0)) (then\n" ++
  s!"      (i32.store8 (local.get $p) (i32.const 44))\n" ++
  s!"      (local.set $p (i32.add (local.get $p) (i32.const 1)))\n" ++
  s!"      (global.set $attr_len (i32.add (global.get $attr_len) (i32.const 1)))))\n" ++
  s!"    (i32.store8 (local.get $p) (i32.const 123))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 107))\n" ++
  s!"    (i32.store8 offset=3 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=4 (local.get $p) (i32.const 121))\n" ++
  s!"    (i32.store8 offset=5 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=6 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=7 (local.get $p) (i32.const 34))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 8)))\n" ++
  s!"    (local.set $i (i32.const 0))\n" ++
  s!"    (block $kdone\n" ++
  s!"      (loop $kcopy\n" ++
  s!"        (br_if $kdone (i32.ge_u (local.get $i) (local.get $key_len)))\n" ++
  s!"        (i32.store8 (i32.add (local.get $p) (local.get $i)) (i32.load8_u (i32.add (local.get $key_off) (local.get $i))))\n" ++
  s!"        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  s!"        (br $kcopy)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $key_len)))\n" ++
  s!"    (i32.store8 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 44))\n" ++
  s!"    (i32.store8 offset=2 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=3 (local.get $p) (i32.const 118))\n" ++
  s!"    (i32.store8 offset=4 (local.get $p) (i32.const 97))\n" ++
  s!"    (i32.store8 offset=5 (local.get $p) (i32.const 108))\n" ++
  s!"    (i32.store8 offset=6 (local.get $p) (i32.const 117))\n" ++
  s!"    (i32.store8 offset=7 (local.get $p) (i32.const 101))\n" ++
  s!"    (i32.store8 offset=8 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=9 (local.get $p) (i32.const 58))\n" ++
  s!"    (i32.store8 offset=10 (local.get $p) (i32.const 34))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (i32.const 11)))\n" ++
  s!"    (local.set $n (call $pf_fmt_u64 (local.get $v) (local.get $p)))\n" ++
  s!"    (local.set $p (i32.add (local.get $p) (local.get $n)))\n" ++
  s!"    (i32.store8 (local.get $p) (i32.const 34))\n" ++
  s!"    (i32.store8 offset=1 (local.get $p) (i32.const 125))\n" ++
  s!"    (global.set $attr_len (i32.sub (i32.add (local.get $p) (i32.const 2)) (i32.const {attrBase})))\n" ++
  "  )\n" ++
  s!"  ;; scratch base marker (unused direct; value cell at {valueCell})\n"

private partial def renderOperation (memory : MemoryLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fnNames : Array String)
    (indent : String) : Operation → String
  | .requireLayoutAbsent marker =>
      s!"{indent}(if (call $pf_db_has (i32.const {marker.offset}) (i32.const {marker.length})) (then unreachable))\n"
  | .requireLayout marker value =>
      s!"{indent}(if (i32.eqz (call $pf_db_has (i32.const {marker.offset}) (i32.const {marker.length}))) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (call $pf_db_load_u64 (i32.const {marker.offset}) (i32.const {marker.length})) (i64.const {value.toNat})) (then unreachable))\n"
  | .zeroState field =>
      s!"{indent}(call $pf_db_store_u64 (i32.const {field.offset}) (i32.const {field.length}) (i64.const 0))\n"
  | .literal destination value =>
      s!"{indent}(local.set $t{destination} (i64.const {value.toNat}))\n"
  | .loadParam destination inputOffset =>
      -- Params live in locals $p{inputOffset/8} filled by JSON parse before body.
      s!"{indent}(local.set $t{destination} (local.get $p{inputOffset / 8}))\n"
  | .loadState destination field =>
      s!"{indent}(local.set $t{destination} (call $pf_db_load_u64 (i32.const {field.offset}) (i32.const {field.length})))\n"
  | .storeState field value =>
      s!"{indent}(call $pf_db_store_u64 (i32.const {field.offset}) (i32.const {field.length}) (local.get $t{value}))\n"
  | .setLayout marker value =>
      s!"{indent}(call $pf_db_store_u64 (i32.const {marker.offset}) (i32.const {marker.length}) (i64.const {value.toNat}))\n"
  | .setReturnData value =>
      s!"{indent}(global.set $ret_kind (i32.const 1))\n" ++
        s!"{indent}(global.set $ret_val (local.get $t{value}))\n"
  | .returnNone =>
      s!"{indent};; return none\n"
  | .returnValue value =>
      s!"{indent}(return (local.get $t{value}))\n"
  | .checkedAdd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.lt_u (local.get $t{destination}) (local.get $t{lhs})) (then unreachable))\n"
  | .checkedSub destination lhs rhs =>
      s!"{indent}(if (i64.lt_u (local.get $t{lhs}) (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .checkedMul destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (local.get $t{lhs}) (i64.const 0)) (then (if (i64.ne (i64.div_u (local.get $t{destination}) (local.get $t{lhs})) (local.get $t{rhs})) (then unreachable))))\n"
  | .checkedDiv destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.div_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .checkedMod destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.rem_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .signedCheckedAdd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.lt_s (i64.and (i64.xor (local.get $t{lhs}) (local.get $t{destination})) (i64.xor (local.get $t{rhs}) (local.get $t{destination}))) (i64.const 0)) (then unreachable))\n"
  | .signedCheckedSub destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.lt_s (i64.and (i64.xor (local.get $t{lhs}) (local.get $t{rhs})) (i64.xor (local.get $t{lhs}) (local.get $t{destination}))) (i64.const 0)) (then unreachable))\n"
  | .signedCheckedMul destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (local.get $t{lhs}) (i64.const 0)) (then (if (i64.ne (local.get $t{lhs}) (i64.const -1)) (then (if (i64.ne (i64.div_s (local.get $t{destination}) (local.get $t{lhs})) (local.get $t{rhs})) (then unreachable))))))\n"
  | .signedCheckedDiv destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(if (i64.eq (local.get $t{lhs}) (i64.const -9223372036854775808)) (then (if (i64.eq (local.get $t{rhs}) (i64.const -1)) (then unreachable))))\n" ++
        s!"{indent}(local.set $t{destination} (i64.div_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .signedCheckedMod destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.rem_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .signedCompare destination lhs rhs op =>
      let insn := match op with
        | .eq => "i64.eq" | .ne => "i64.ne" | .lt => "i64.lt_s"
        | .le => "i64.le_s" | .gt => "i64.gt_s" | .ge => "i64.ge_s"
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .checkedNeg destination source =>
      s!"{indent}(if (i64.eq (local.get $t{source}) (i64.const -9223372036854775808)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.sub (i64.const 0) (local.get $t{source})))\n"
  | .compare destination lhs rhs op =>
      let insn := match op with
        | .eq => "i64.eq" | .ne => "i64.ne" | .lt => "i64.lt_u"
        | .le => "i64.le_u" | .gt => "i64.gt_u" | .ge => "i64.ge_u"
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .assert condition =>
      s!"{indent}(if (i64.eqz (local.get $t{condition})) (then unreachable))\n"
  | .bitAnd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitXor destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{source}) (i64.const -1)))\n"
  | .shl destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shl (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (local.get $t{rhs})) (local.get $t{lhs})) (then unreachable))\n"
  | .shr destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .sar destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i64.eqz (local.get $t{source}))))\n"
  | .boolAnd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .callFn fnIndex destination args =>
      let name := fnNames[fnIndex]!
      let argList := String.intercalate " " (args.toList.map fun a => s!"(local.get $t{a})")
      s!"{indent}(local.set $t{destination} (call $fn_{name} {argList}))\n"
  | .emitEvent eventIndex args =>
      let binding := events[eventIndex]!
      -- Attribute key = event name; value = first arg decimal (MVP multi-arg: first only + count)
      if args.isEmpty then
        s!"{indent};; emit {binding.name} (no args)\n" ++
          s!"{indent}(call $pf_push_attr_u64 (i32.const 0) (i32.const 0) (i64.const 0))\n"
      else
        -- Use event name from static data — embed via immediate store of name bytes into scratch
        Id.run do
          let nameBytes := binding.name.toUTF8
          let mut out := s!"{indent};; emit event {binding.name}\n"
          -- write event name to a fixed scratch slot at valueOffset+16
          let nameOff := memory.valueOffset + 16
          for i in [0:nameBytes.size] do
            out := out ++
              s!"{indent}(i32.store8 (i32.const {nameOff + i}) (i32.const {nameBytes[i]!.toNat}))\n"
          out := out ++
            s!"{indent}(call $pf_push_attr_u64 (i32.const {nameOff}) (i32.const {nameBytes.size}) (local.get $t{args[0]!}))\n"
          pure out
  | .revertError errorIndex args =>
      let binding := errors[errorIndex]!
      let nameBytes := binding.name.toUTF8
      Id.run do
        let nameOff := memory.valueOffset + 16
        let mut out := s!"{indent};; revert {binding.name}\n"
        for i in [0:nameBytes.size] do
          out := out ++
            s!"{indent}(i32.store8 (i32.const {nameOff + i}) (i32.const {nameBytes[i]!.toNat}))\n"
        -- Build error result and return it (caller entrypoints use block+br or direct return)
        out := out ++
          s!"{indent}(return (call $pf_error_result (i32.const {nameOff}) (i32.const {nameBytes.size})))\n"
        pure out
  | .ifRegion condition thenOps elseOps =>
      let thenText := thenOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "  ") op) ""
      let elseText := elseOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "  ") op) ""
      let thenBody := if thenText.isEmpty then s!"{indent}  nop\n" else thenText
      let elseBody := if elseText.isEmpty then s!"{indent}  nop\n" else elseText
      s!"{indent}(if (i64.ne (local.get $t{condition}) (i64.const 0))\n" ++
        s!"{indent}  (then\n" ++ thenBody ++
        s!"{indent}  )\n" ++
        s!"{indent}  (else\n" ++ elseBody ++
        s!"{indent}  )\n" ++
        s!"{indent})\n"
  | .switchRegion scrutinee cases defaultOps =>
      let rec renderCases (indent : String) (remaining : List (UInt64 × Array Operation)) : String :=
        match remaining with
        | [] =>
            defaultOps.foldl (fun o op =>
              o ++ renderOperation memory events errors fnNames indent op) ""
        | (caseValue, caseOps) :: rest =>
            let caseText := caseOps.foldl (fun o op =>
              o ++ renderOperation memory events errors fnNames (indent ++ "  ") op) ""
            let elseText := renderCases (indent ++ "  ") rest
            let elseBody := if elseText.isEmpty then s!"{indent}  nop\n" else elseText
            let caseBody := if caseText.isEmpty then s!"{indent}    nop\n" else caseText
            s!"{indent}(if (i64.eq (local.get $t{scrutinee}) (i64.const {caseValue.toNat}))\n" ++
              s!"{indent}  (then\n" ++ caseBody ++
              s!"{indent}  )\n" ++
              s!"{indent}  (else\n" ++ elseBody ++
              s!"{indent}  )\n" ++
              s!"{indent})\n"
      renderCases indent cases.toList
  | .forRegion varTemp initial counterTemp maxIterations condOps condition bodyOps updateOps updateValue =>
      let condText := condOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "    ") op) ""
      let bodyText := bodyOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "    ") op) ""
      let updateText := updateOps.foldl (fun o op =>
        o ++ renderOperation memory events errors fnNames (indent ++ "    ") op) ""
      s!"{indent}(local.set $t{varTemp} (local.get $t{initial}))\n" ++
        s!"{indent}(local.set $t{counterTemp} (i64.const 0))\n" ++
        s!"{indent}(block $for_break_{varTemp}\n" ++
        s!"{indent}  (loop $for_loop_{varTemp}\n" ++
        condText ++
        s!"{indent}    (br_if $for_break_{varTemp} (i64.eqz (local.get $t{condition})))\n" ++
        bodyText ++
        -- back-edge bound: after body, if counter >= maxIterations trap (N+1 body then trap)
        s!"{indent}    (if (i64.ge_u (local.get $t{counterTemp}) (i64.const {maxIterations})) (then unreachable))\n" ++
        s!"{indent}    (local.set $t{counterTemp} (i64.add (local.get $t{counterTemp}) (i64.const 1)))\n" ++
        updateText ++
        s!"{indent}    (local.set $t{varTemp} (local.get $t{updateValue}))\n" ++
        s!"{indent}    (br $for_loop_{varTemp})\n" ++
        s!"{indent}  )\n" ++
        s!"{indent})\n"

private def renderFn (ir : IR) (fn : FnIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let params := String.intercalate "" <| (Array.range fn.paramCount).toList.map fun index =>
    s!" (param $t{index} i64)"
  let extraLocals :=
    if fn.tempCount <= fn.paramCount then ""
    else
      String.intercalate "" <|
        (List.range (fn.tempCount - fn.paramCount)).map fun i =>
          s!" (local $t{fn.paramCount + i} i64)"
  let operations := String.intercalate "" <| fn.operations.toList.map
    (renderOperation ir.memory ir.sourcePlan.events ir.sourcePlan.errors fnNames "    ")
  s!"  (func $fn_{fn.name}{params} (result i64){extraLocals}\n" ++
    operations ++ "  )\n"

/-- Render method body as an internal func `$m_<name>` used by entry dispatch.
    Params arrive in `$p0..` locals (filled by JSON parse at call site). -/
private def renderMethodBody (ir : IR) (method : MethodIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let paramLocals := String.intercalate "" <| (Array.range method.params.size).toList.map fun i =>
    s!" (param $p{i} i64)"
  let temps := String.intercalate "" <| (Array.range method.tempCount).toList.map fun i =>
    s!" (local $t{i} i64)"
  let operations := String.intercalate "" <| method.operations.toList.map
    (renderOperation ir.memory ir.sourcePlan.events ir.sourcePlan.errors fnNames "    ")
  -- Methods return i32 region ptr for ContractResult (via setReturnData globals + pf_ok_result)
  let epilogue :=
    match method.mode with
    | .view =>
        "    (return (call $pf_query_ok (global.get $ret_val)))\n"
    | .initialize | .mutate =>
        "    (return (call $pf_ok_result))\n"
  s!"  (func $m_{method.name}{paramLocals} (result i32){temps}\n" ++
    "    (call $pf_reset_result)\n" ++
    operations ++ epilogue ++ "  )\n"

/-- Static data: key strings + quoted method/param names for JSON scan. -/
private def renderDataSection (ir : IR) : String := Id.run do
  let mut out := ""
  for key in ir.keys do
    out := out ++ s!"  (data (i32.const {key.offset}) \"{key.key}\")\n"
  -- Place method name needles at 3000+ for JSON dispatch (after keys, before heap)
  let mut off := 3000
  for method in ir.methods do
    -- store `"name"` including quotes for find
    let needle := s!"\"{method.name}\""
    out := out ++ s!"  (data (i32.const {off}) \"{Targets.escapeJson needle}\")\n"
    -- Actually escapeJson is wrong for data strings — method names are identifiers
    out := out  -- keep; rewrite below properly
  pure out

/-- Rebuild data section correctly (identifiers only, no JSON escape). -/
private def renderDataSectionV2 (ir : IR) : String × Array (String × Nat × Nat) × Array (String × Nat × Nat) :=
  Id.run do
    let mut out := ""
    for key in ir.keys do
      out := out ++ s!"  (data (i32.const {key.offset}) \"{key.key}\")\n"
    let mut off := 3000
    let mut methodNeedles : Array (String × Nat × Nat) := #[]
    for method in ir.methods do
      -- WAT string containing the bytes of `"name"` (quotes included for JSON find).
      let needleBytes := s!"\"{method.name}\"".toUTF8
      out := out ++ s!"  (data (i32.const {off}) \"\\\"{method.name}\\\"\")\n"
      methodNeedles := methodNeedles.push (method.name, off, needleBytes.size)
      off := off + needleBytes.size + 1
    let mut paramNeedles : Array (String × Nat × Nat) := #[]
    for method in ir.methods do
      for p in method.params do
        let needleBytes := s!"\"{p.name}\"".toUTF8
        out := out ++ s!"  (data (i32.const {off}) \"\\\"{p.name}\\\"\")\n"
        paramNeedles := paramNeedles.push (s!"{method.name}.{p.name}", off, needleBytes.size)
        off := off + needleBytes.size + 1
    pure (out, methodNeedles, paramNeedles)

private def findNeedle (needles : Array (String × Nat × Nat)) (key : String) : Nat × Nat :=
  match needles.find? (fun p => p.1 == key) with
  | some (_, off, len) => (off, len)
  | none => (0, 0)

private def renderInstantiate (ir : IR) (paramNeedles : Array (String × Nat × Nat)) : String :=
  Id.run do
    let init := ir.methods[0]!  -- initializer is always first
    let mut parse := ""
    for i in [0:init.params.size] do
      let p := init.params[i]!
      let (off, len) := findNeedle paramNeedles s!"{init.name}.{p.name}"
      parse := parse ++
        s!"    (local.set $p{i} (call $pf_parse_u64_field (local.get $msg_off) (local.get $msg_len) (i32.const {off}) (i32.const {len})))\n"
    let args := String.intercalate " " <| (Array.range init.params.size).toList.map fun i =>
      s!"(local.get $p{i})"
    let paramLocals := String.intercalate "" <| (Array.range init.params.size).toList.map fun i =>
      s!" (local $p{i} i64)"
    pure <|
      "  (func (export \"instantiate\") (param $env_ptr i32) (param $info_ptr i32) (param $msg_ptr i32) (result i32)\n" ++
        "    (local $msg_off i32) (local $msg_len i32)" ++ paramLocals ++ "\n" ++
        "    (local.set $msg_off (call $pf_region_off (local.get $msg_ptr)))\n" ++
        "    (local.set $msg_len (call $pf_region_len (local.get $msg_ptr)))\n" ++
        parse ++
        s!"    (return (call $m_{init.name} {args}))\n" ++
        "  )\n"

private def renderExecute (ir : IR) (methodNeedles paramNeedles : Array (String × Nat × Nat)) : String :=
  Id.run do
    let entries := ir.methods[1:].toArray.filter (fun m => m.mode == .mutate)
    let mut dispatch := ""
    for method in entries do
      let (mOff, mLen) := findNeedle methodNeedles method.name
      let mut parse := ""
      for i in [0:method.params.size] do
        let p := method.params[i]!
        let (off, len) := findNeedle paramNeedles s!"{method.name}.{p.name}"
        parse := parse ++
          s!"        (local.set $p{i} (call $pf_parse_u64_field (local.get $msg_off) (local.get $msg_len) (i32.const {off}) (i32.const {len})))\n"
      let args := String.intercalate " " <| (Array.range method.params.size).toList.map fun i =>
        s!"(local.get $p{i})"
      dispatch := dispatch ++
        s!"    (if (i32.ne (call $pf_find (local.get $msg_off) (local.get $msg_len) (i32.const {mOff}) (i32.const {mLen})) (i32.const -1)) (then\n" ++
        parse ++
        s!"        (return (call $m_{method.name} {args}))\n" ++
        "      ))\n"
    let maxParams := entries.foldl (fun n m => max n m.params.size) 0
    let paramLocals := String.intercalate "" <| (Array.range maxParams).toList.map fun i =>
      s!" (local $p{i} i64)"
    pure <|
      "  (func (export \"execute\") (param $env_ptr i32) (param $info_ptr i32) (param $msg_ptr i32) (result i32)\n" ++
        "    (local $msg_off i32) (local $msg_len i32)" ++ paramLocals ++ "\n" ++
        "    (local.set $msg_off (call $pf_region_off (local.get $msg_ptr)))\n" ++
        "    (local.set $msg_len (call $pf_region_len (local.get $msg_ptr)))\n" ++
        dispatch ++
        "    (return (call $pf_error_result (i32.const 0) (i32.const 0)))\n" ++
        "  )\n"

private def renderQuery (ir : IR) (methodNeedles paramNeedles : Array (String × Nat × Nat)) : String :=
  Id.run do
    let views := ir.methods[1:].toArray.filter (fun m => m.mode == .view)
    let mut dispatch := ""
    for method in views do
      let (mOff, mLen) := findNeedle methodNeedles method.name
      let mut parse := ""
      for i in [0:method.params.size] do
        let p := method.params[i]!
        let (off, len) := findNeedle paramNeedles s!"{method.name}.{p.name}"
        parse := parse ++
          s!"        (local.set $p{i} (call $pf_parse_u64_field (local.get $msg_off) (local.get $msg_len) (i32.const {off}) (i32.const {len})))\n"
      let args := String.intercalate " " <| (Array.range method.params.size).toList.map fun i =>
        s!"(local.get $p{i})"
      dispatch := dispatch ++
        s!"    (if (i32.ne (call $pf_find (local.get $msg_off) (local.get $msg_len) (i32.const {mOff}) (i32.const {mLen})) (i32.const -1)) (then\n" ++
        parse ++
        s!"        (return (call $m_{method.name} {args}))\n" ++
        "      ))\n"
    let maxParams := views.foldl (fun n m => max n m.params.size) 0
    let paramLocals := String.intercalate "" <| (Array.range maxParams).toList.map fun i =>
      s!" (local $p{i} i64)"
    pure <|
      "  (func (export \"query\") (param $env_ptr i32) (param $msg_ptr i32) (result i32)\n" ++
        "    (local $msg_off i32) (local $msg_len i32)" ++ paramLocals ++ "\n" ++
        "    (local.set $msg_off (call $pf_region_off (local.get $msg_ptr)))\n" ++
        "    (local.set $msg_len (call $pf_region_len (local.get $msg_ptr)))\n" ++
        dispatch ++
        "    (return (call $pf_error_result (i32.const 0) (i32.const 0)))\n" ++
        "  )\n"

private def renderWat (ir : IR) : String :=
  let imports := String.intercalate "" <| ir.imports.toList.map renderImport
  let (dataSec, methodNeedles, paramNeedles) := renderDataSectionV2 ir
  let helpers := renderRuntimeHelpers ir.memory
  let fns := String.intercalate "" <| ir.fns.toList.map (renderFn ir)
  let methodBodies := String.intercalate "" <| ir.methods.toList.map (renderMethodBody ir)
  let allocateExport :=
    "  (func (export \"allocate\") (param $size i32) (result i32)\n" ++
    "    (call $pf_allocate (local.get $size))\n" ++
    "  )\n"
  let deallocateExport :=
    "  (func (export \"deallocate\") (param $region_ptr i32)\n" ++
    "    nop\n" ++
    "  )\n"
  let versionExport :=
    "  (func (export \"interface_version_8\") (result i32)\n" ++
    "    (i32.const 8)\n" ++
    "  )\n"
  "(module\n" ++ imports ++
    "  (memory (export \"memory\") 1)\n" ++
    dataSec ++
    helpers ++
    allocateExport ++ deallocateExport ++ versionExport ++
    fns ++ methodBodies ++
    renderInstantiate ir paramNeedles ++
    renderExecute ir methodNeedles paramNeedles ++
    renderQuery ir methodNeedles paramNeedles ++
    ")\n"

private def renderMode : MethodMode → String
  | .initialize => "instantiate"
  | .mutate => "execute"
  | .view => "query"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"u64\"}"

private def renderMethodJson (method : Method) : String :=
  let returns :=
    match method.resultKind with
    | .unit => "null"
    | .uint64 => "\"u64\""
    | .bool => "\"bool\""
    | .int64 => "\"i64\""
    | _ => "\"u64\""
  "{" ++
    s!"\"name\":\"{Targets.escapeJson method.name}\"," ++
    s!"\"export\":\"{renderMode method.mode}\"," ++
    s!"\"mode\":\"{renderMode method.mode}\"," ++
    s!"\"args\":[{String.intercalate "," (method.params.toList.map renderParamJson)}]," ++
    s!"\"returns\":{returns}" ++
    "}"

private def renderAbi (plan : Plan) : String :=
  let fields := String.intercalate "," (plan.storage.fields.toList.map fun f =>
    s!"\{\"name\":\"{Targets.escapeJson f.name}\",\"key\":\"{Targets.escapeJson f.key}\",\"type\":\"u64\"}")
  let methods := #[plan.initializer] ++ plan.entries
  let exports := String.intercalate ",\n    " (methods.toList.map renderMethodJson)
  "{\n" ++
    "  \"schema\": \"proof-forge-cosmwasm-abi/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson plan.programName}\",\n" ++
    s!"  \"codegenProfile\": \"{plan.codegenProfile}\",\n" ++
    s!"  \"hostAbi\": \"{plan.hostAbi}\",\n" ++
    s!"  \"encoding\": \"{plan.inputAbi}\",\n" ++
    "  \"entrypoints\": [\"instantiate\",\"execute\",\"query\",\"allocate\",\"deallocate\",\"interface_version_8\"],\n" ++
    "  \"imports\": [\"env.db_read\",\"env.db_write\",\"env.db_remove\",\"env.abort\"],\n" ++
    "  \"region\": {\"size\":12,\"fields\":[\"offset:u32\",\"capacity:u32\",\"length:u32\"]},\n" ++
    "  \"jsonSubset\": \"flat-instantiate-params | {\\\"method\\\":{params}} decimal integers\",\n" ++
    "  \"storage\": {" ++
    s!"\"markerKey\":\"{plan.storage.markerKey}\"," ++
    s!"\"fields\":[{fields}]" ++
    "},\n" ++
    "  \"methods\": [\n    " ++ exports ++ "\n  ]\n" ++
    "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  return #[
    {
      path := s!"{ir.name}.wat"
      mediaType := "application/wasm-text"
      contents := renderWat ir
    },
    {
      path := s!"{ir.name}.cosmwasm-abi.json"
      mediaType := "application/json"
      contents := renderAbi ir.sourcePlan
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

end ProofForgeV2.Targets.CosmWasm
