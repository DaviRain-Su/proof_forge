import ProofForgeV2.Targets.Near.ValidatePlanV1

/-!
# Near EmitIRV1 — Plan → IR emission

Host-call recipe IR, validateIR, lower/emitFromIR.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

inductive Operation where
  | checkInputLen (bytes : Nat)
  | requireZeroAttachedDeposit
  | requireLayoutAbsent (marker : KeyRegion)
  | requireLayout (marker : KeyRegion) (value : UInt64)
  | zeroState (field : KeyRegion)
  /-- Narrow field zero on init (`bitWidth ∈ {8,16,32}`); UInt64 keeps `zeroState`. -/
  | narrowZeroState (bitWidth : Nat) (field : KeyRegion)
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination inputOffset : Nat)
  /-- Narrow ABI param load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `loadParam`. -/
  | narrowLoadParam (bitWidth destination inputOffset : Nat)
  | loadState (destination : Nat) (field : KeyRegion)
  /-- Narrow ABI state load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `loadState`. -/
  | narrowLoadState (bitWidth destination : Nat) (field : KeyRegion)
  | checkedAdd (destination lhs rhs : Nat)
  | checkedSub (destination lhs rhs : Nat)
  | signedCheckedAdd (destination lhs rhs : Nat)
  | signedCheckedSub (destination lhs rhs : Nat)
  | signedCheckedMul (destination lhs rhs : Nat)
  | signedCheckedDiv (destination lhs rhs : Nat)
  | signedCheckedMod (destination lhs rhs : Nat)
  | signedCompare (destination lhs rhs : Nat) (op : ComparisonOp)
  | checkedNeg (destination source : Nat)
  | sar (destination lhs rhs : Nat)
  | storeState (field : KeyRegion) (value : Nat)
  /-- Narrow field store (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `storeState`. -/
  | narrowStoreState (bitWidth : Nat) (field : KeyRegion) (value : Nat)
  | setLayout (marker : KeyRegion) (value : UInt64)
  /-- Host `value_return` payload: `byteLen` ∈ {1,2,4,8} from MethodResultKind. -/
  | setReturnData (byteLen value : Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat)
  | emitEvent (eventIndex : Nat) (args : Array Nat)
  | revertError (errorIndex : Nat) (args : Array Nat)
  | returnNone
  | ifRegion (condition : Nat) (thenOps elseOps : Array Operation)
  | switchRegion (scrutinee : Nat) (cases : Array (UInt64 × Array Operation))
      (defaultOps : Array Operation)
  /-- Structured bounded loop. Host/WAT re-run `condOps` each iteration;
      `varTemp` is seeded from `initial` then rewritten from `updateValue`
      after each body. `counterTemp` counts completed bodies; the static bound
      is checked at the back edge after the body (reference `noteBackEdge`
      placement): body runs first, then trap if `counterTemp ≥ maxIterations`,
      then increment + update. A body `return`/`revert` exits before the check. -/
  | forRegion (varTemp : Nat) (initial : Nat) (counterTemp : Nat)
      (maxIterations : Nat)
      (condOps : Array Operation) (condition : Nat)
      (bodyOps : Array Operation)
      (updateOps : Array Operation) (updateValue : Nat)
  | callFn (fnIndex : Nat) (destination : Nat) (args : Array Nat)
  | returnValue (value : Nat)
  | checkedMul (destination lhs rhs : Nat)
  | checkedDiv (destination lhs rhs : Nat)
  | checkedMod (destination lhs rhs : Nat)
  | bitAnd (destination lhs rhs : Nat)
  | bitOr (destination lhs rhs : Nat)
  | bitXor (destination lhs rhs : Nat)
  /-- Count guard (≥ 64 → trap) then i64.shl then overflow round-trip guard. -/
  | shl (destination lhs rhs : Nat)
  /-- Count guard (≥ 64 → trap) then i64.shr_u. -/
  | shr (destination lhs rhs : Nat)
  | bitNot (destination source : Nat)
  /-- Narrow body checked arithmetic (`bitWidth ∈ {8,16,32}`); UInt64 keeps historical. -/
  | narrowCheckedAdd (bitWidth destination lhs rhs : Nat)
  | narrowCheckedSub (bitWidth destination lhs rhs : Nat)
  | narrowCheckedMul (bitWidth destination lhs rhs : Nat)
  | narrowCheckedDiv (bitWidth destination lhs rhs : Nat)
  | narrowCheckedMod (bitWidth destination lhs rhs : Nat)
  | narrowBitAnd (bitWidth destination lhs rhs : Nat)
  | narrowBitOr (bitWidth destination lhs rhs : Nat)
  | narrowBitXor (bitWidth destination lhs rhs : Nat)
  | narrowBitNot (bitWidth destination source : Nat)
  /-- Count ≥ 64 trap; shl; high bits above bitWidth must be 0. -/
  | narrowShl (bitWidth destination lhs rhs : Nat)
  /-- Count ≥ 64 trap; shr_u. -/
  | narrowShr (bitWidth destination lhs rhs : Nat)
  | boolNot (destination source : Nat)
  /-- Strict Bool AND: i64.and on 0/1 words. -/
  | boolAnd (destination lhs rhs : Nat)
  /-- Strict Bool OR: i64.or on 0/1 words. -/
  | boolOr (destination lhs rhs : Nat)
  /-- Async schedule → `promise_batch_create` + `promise_batch_action_function_call`.
      Args are temp indices whose i64 values are stored LE into the scratch
      payload. Deposit (u128 = 0,0) and gas (0) are explicit artifact
      placeholders, not economics. Fire-and-forget: no response, no revert
      propagation. -/
  | promiseAccount (receiver : String) (method : String) (args : Array Nat)
  deriving BEq, Inhabited, Repr

structure MethodIR where
  name : String
  params : Array Param
  mode : MethodMode
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Pure-function recipe: params occupy temps `0..paramCount-1`; body ops use
    `returnValue` (Wasm `return`) rather than host `value_return`. -/
structure FnIR where
  name : String
  paramCount : Nat
  resultIsBool : Bool
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed NEAR host-call/Wasm recipe. Rendering WAT is deliberately later than
the exact Plan-to-recipe binding check.
    Private `mk`: public Plan→IR construction is capability-gated only
    (`irFromCapability`); the private packaging ctor is not a product emission API. -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  imports : Array HostImport
  registers : RegisterLayout
  keys : Array KeyRegion
  memory : MemoryLayout
  methods : Array MethodIR
  fns : Array FnIR
  -- No Inhabited: IR embeds Plan → TargetDescriptor identities.
  deriving BEq, Repr

private def align8 (value : Nat) : Nat :=
  ((value + 7) / 8) * 8

private def makeKeyRegions (plan : Plan) : Array KeyRegion := Id.run do
  let mut regions : Array KeyRegion := #[]
  let mut offset := 0
  let markerLength := plan.storage.markerKey.toUTF8.size
  regions := regions.push { key := plan.storage.markerKey, offset, length := markerLength }
  offset := offset + markerLength
  for field in plan.storage.fields do
    let length := field.key.toUTF8.size
    regions := regions.push { key := field.key, offset, length }
    offset := offset + length
  return regions

private def maxInputLen (plan : Plan) : Nat :=
  plan.entries.foldl (fun current method => max current method.exactInputLen)
    plan.initializer.exactInputLen

private def makeMemoryLayout (plan : Plan) (keys : Array KeyRegion) : MemoryLayout :=
  let keysEnd := keys.foldl (fun current key => max current (key.offset + key.length)) 0
  let inputOffset := align8 keysEnd
  let inputCapacity := maxInputLen plan
  let depositOffset := align8 (inputOffset + inputCapacity)
  {
    minPages := plan.resourceLimits.wasmMemoryPages
    inputOffset
    inputCapacity
    depositOffset
    valueOffset := depositOffset + 16
  }

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private def fieldRegion (keys : Array KeyRegion) (fieldIndex : Nat) : KeyRegion :=
  keys[fieldIndex + 1]!

/-- `paramAsTemp`: pureFn bodies bind params to temps `0..n-1` (Wasm params),
    so `.param` is a direct temp reference rather than a host input load.
    `localEnv` maps plan `.localTemp` indices to IR temps (loop induction). -/
private partial def lowerExpr (keys : Array KeyRegion) (next : Nat)
    (paramAsTemp : Bool) (localEnv : Array (Nat × Nat)) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .param inputOffset =>
      if paramAsTemp then
        { operations := #[], value := inputOffset / 8, next := next }
      else
        { operations := #[.loadParam next inputOffset], value := next, next := next + 1 }
  | .narrowParam bitWidth inputOffset =>
      if paramAsTemp then
        -- pureFn params still occupy one Wasm i64 slot each (8-byte pitch).
        { operations := #[], value := inputOffset / 8, next := next }
      else
        { operations := #[.narrowLoadParam bitWidth next inputOffset],
          value := next, next := next + 1 }
  | .localTemp index =>
      match localEnv.find? (fun p => p.1 == index) with
      | some (_, irTemp) =>
          { operations := #[], value := irTemp, next := next }
      | none =>
          -- Unresolved local: allocate a sink temp so validation still binds;
          -- well-formed plans always resolve induction locals via forLoop.
          { operations := #[.literal next 0], value := next, next := next + 1 }
  | .stateLoad fieldIndex =>
      {
        operations := #[.loadState next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .narrowStateLoad bitWidth fieldIndex =>
      {
        operations := #[.narrowLoadState bitWidth next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMul lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedDiv lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMod lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitXor lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .shl lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.shl rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .shr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.shr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitNot operand =>
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++ #[.bitNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .narrowCheckedAdd bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedAdd bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedSub bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedSub bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedMul bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMul bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedDiv bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedDiv bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowCheckedMod bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowCheckedMod bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowBitAnd bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitAnd bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowBitOr bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitOr bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowBitXor bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowBitXor bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowBitNot bitWidth operand =>
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++
          #[.narrowBitNot bitWidth operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .narrowShl bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowShl bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .narrowShr bitWidth lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.narrowShr bitWidth rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .boolNot operand =>
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++ #[.boolNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .boolAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolAnd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .boolOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolOr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .compare op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedAdd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedAdd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedSub lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedSub rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedMul lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMul rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedDiv lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedDiv rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCheckedMod lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCheckedMod rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .signedCompare op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.signedCompare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedNeg operand =>
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++ #[.checkedNeg operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .sar lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.sar rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .callFn fnIndex args => Id.run do
      let mut operations : Array Operation := #[]
      let mut next := next
      let mut argTemps : Array Nat := #[]
      for arg in args do
        let lowered := lowerExpr keys next paramAsTemp localEnv arg
        operations := operations ++ lowered.operations
        argTemps := argTemps.push lowered.value
        next := lowered.next
      pure {
        operations := operations.push (.callFn fnIndex next argTemps)
        value := next
        next := next + 1
      }

/-- Whether every path through a statement list ends in a return (valued or
    bare marker), matching the region emitter's closedness: a list closes iff
    its last statement is a return or a region whose arms all close. An empty
    else/default arm is a fallthrough (open). Used to append a hard `return`
    after arms whose value_return would otherwise fall through into the
    region's continuation (the host call does not halt execution). -/
private partial def statementListClosesV1 : List Statement → Bool
  | [] => false
  | [statement] =>
      match statement with
      | .returnValue _ | .returnNone | .revertError .. => true
      | .ifThenElse _ thenBody elseBody =>
          !elseBody.isEmpty && statementListClosesV1 thenBody.toList &&
            statementListClosesV1 elseBody.toList
      | .switchOn _ cases defaultBody =>
          !defaultBody.isEmpty && statementListClosesV1 defaultBody.toList &&
            cases.all fun (_, caseBody) => statementListClosesV1 caseBody.toList
      | .store _ | .assert _ | .emitEvent .. | .forLoop .. | .promiseAccount .. => false
  | _ :: _ :: rest => statementListClosesV1 rest

/-- Append the hard return after a closed region arm, unless the arm already
    ends in a halting statement (the initializer's bare-return marker, a
    declared revert, or — in pureFn mode — a valued `return` which is already
    a Wasm `return`). -/
private def armOpsWithHardReturn (arm : Array Statement)
    (operations : Array Operation) (fnMode : Bool) : Array Operation :=
  let alreadyHalts := match arm.back? with
    | some .returnNone | some (.revertError ..) => true
    | some (.returnValue _) => fnMode
    | _ => false
  if statementListClosesV1 arm.toList && !alreadyHalts then
    operations.push .returnNone
  else
    operations

private partial def lowerBodyOps
    (keys : Array KeyRegion) (next : Nat) (statements : Array Statement)
    (fnMode : Bool) (localEnv : Array (Nat × Nat))
    (returnByteLen : Nat) :
    Array Operation × Nat := Id.run do
  let mut operations : Array Operation := #[]
  let mut next := next
  let mut localEnv := localEnv
  for statement in statements do
    match statement with
    | .store store =>
        let value := lowerExpr keys next fnMode localEnv store.value
        operations := operations ++ value.operations
        let storeOp : Operation :=
          if store.byteWidth == 8 then
            .storeState (fieldRegion keys store.fieldIndex) value.value
          else
            .narrowStoreState (store.byteWidth * 8) (fieldRegion keys store.fieldIndex) value.value
        operations := operations.push storeOp
        next := value.next
    | .returnValue value =>
        let value := lowerExpr keys next fnMode localEnv value
        operations := operations ++ value.operations
        if fnMode then
          operations := operations.push (.returnValue value.value)
        else
          operations := operations.push (.setReturnData returnByteLen value.value)
        next := value.next
    | .returnNone =>
        -- Valid only inside region arms (validated); the initializer's own
        -- final marker is stripped by lowerMethod before lowering.
        operations := operations.push .returnNone
    | .emitEvent eventIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.emitEvent eventIndex argTemps)
    | .promiseAccount receiver method args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.promiseAccount receiver method argTemps)
    | .revertError errorIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.revertError errorIndex argTemps)
    | .assert condition =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations
        operations := operations.push (.assert value.value)
        next := value.next
    | .ifThenElse condition thenBody elseBody =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations
        let (thenOps, next1) := lowerBodyOps keys value.next thenBody fnMode localEnv returnByteLen
        let (elseOps, next2) := lowerBodyOps keys next1 elseBody fnMode localEnv returnByteLen
        operations := operations.push (.ifRegion value.value
          (armOpsWithHardReturn thenBody thenOps fnMode)
          (armOpsWithHardReturn elseBody elseOps fnMode))
        next := next2
    | .switchOn scrutinee cases defaultBody =>
        let value := lowerExpr keys next fnMode localEnv scrutinee
        operations := operations ++ value.operations
        let mut caseOps : Array (UInt64 × Array Operation) := #[]
        let mut nextC := value.next
        for (caseValue, caseBody) in cases do
          let (ops, next1) := lowerBodyOps keys nextC caseBody fnMode localEnv returnByteLen
          caseOps := caseOps.push (caseValue, armOpsWithHardReturn caseBody ops fnMode)
          nextC := next1
        let (defaultOps, nextD) := lowerBodyOps keys nextC defaultBody fnMode localEnv returnByteLen
        operations := operations.push (.switchRegion value.value caseOps
          (armOpsWithHardReturn defaultBody defaultOps fnMode))
        next := nextD
    | .forLoop varTemp initial condition update maxIterations body =>
        let initL := lowerExpr keys next fnMode localEnv initial
        operations := operations ++ initL.operations
        let irVar := initL.next
        let counterTemp := initL.next + 1
        next := initL.next + 2
        -- Seed the induction temp from the initial expression.
        -- forRegion copies initial → varTemp at entry and zeroes counterTemp.
        let localEnv' := localEnv.push (varTemp, irVar)
        let condL := lowerExpr keys next fnMode localEnv' condition
        let condOps := condL.operations
        let condTemp := condL.value
        next := condL.next
        let (bodyOps, nextB) := lowerBodyOps keys next body fnMode localEnv' returnByteLen
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


private def methodResultByteLen : MethodResultKind → Nat
  | .unit => 8
  | .uint64 | .int64 | .bool => 8
  | .uint8 => 1
  | .uint16 => 2
  | .uint32 => 4

private def lowerMethod (plan : Plan) (keys : Array KeyRegion)
    (method : Method) : MethodIR := Id.run do
  let marker := keys[0]!
  let mut operations : Array Operation := #[.checkInputLen method.exactInputLen]
  if method.depositPolicy == .requireZero then
    operations := operations.push .requireZeroAttachedDeposit
  if method.mode == .initialize then
    operations := operations.push (.requireLayoutAbsent marker)
    for index in [0:plan.storage.fields.size] do
      let field := plan.storage.fields[index]!
      let zeroOp : Operation :=
        if field.byteWidth == 8 then
          .zeroState (fieldRegion keys index)
        else
          .narrowZeroState (field.byteWidth * 8) (fieldRegion keys index)
      operations := operations.push zeroOp
  else
    operations := operations.push (.requireLayout marker plan.storage.markerValue)
  -- The initializer's final bare-return marker is the natural fall-through;
  -- in-arm markers are rejected by validatePlan and never reach this point.
  let body := if method.body.back? == some .returnNone then
    method.body.pop
  else
    method.body
  let (bodyOps, next) := lowerBodyOps keys 0 body false #[] (methodResultByteLen method.resultKind)
  operations := operations ++ bodyOps
  if method.mode == .initialize then
    operations := operations.push (.setLayout marker plan.storage.markerValue)
  return {
    name := method.name
    params := method.params
    mode := method.mode
    tempCount := next
    operations
  }

private def lowerFn (keys : Array KeyRegion) (fn : FnBinding) : FnIR :=
  let paramCount := fn.params.size
  -- Temps `0..paramCount-1` are the Wasm parameters; body lowering starts after.
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

/-- PureFn ops may not touch host storage, layout, deposits, or method returns. -/
private partial def opIsMethodOnlyV1 : Operation → Bool
  | .checkInputLen _ | .requireZeroAttachedDeposit
  | .requireLayoutAbsent _ | .requireLayout _ _
  | .zeroState _ | .narrowZeroState _ _
  | .loadState _ _ | .narrowLoadState _ _ _
  | .storeState _ _ | .narrowStoreState _ _ _
  | .setLayout _ _ | .setReturnData _ _ | .loadParam _ _
  | .narrowLoadParam _ _ _ => true
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

/-- Validate the typed host-call recipe and bind it exactly to its source Plan. -/
def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName do
    throw <| .planInvariant .near "typed NEAR IR identity is not bound to its source Plan"
  unless ir.imports == ir.sourcePlan.hostImports && ir.registers == canonicalRegisters do
    throw <| .planInvariant .near "typed NEAR IR host imports/registers are not canonical"
  let expectedKeys := makeKeyRegions ir.sourcePlan
  unless ir.keys == expectedKeys do
    throw <| .planInvariant .near "typed NEAR IR key regions are not bound to the Plan KV layout"
  let expectedMemory := makeMemoryLayout ir.sourcePlan expectedKeys
  unless ir.memory == expectedMemory &&
      ir.memory.minPages == ir.sourcePlan.resourceLimits.wasmMemoryPages &&
      ir.memory.valueOffset + 8 <= ir.memory.minPages * wasmPageBytes do
    throw <| .planInvariant .near "typed NEAR IR memory layout is not canonical or exceeds one page"
  if ir.methods.size != ir.sourcePlan.entries.size + 1 then
    throw <| .planInvariant .near "typed NEAR IR export count does not match its source Plan"
  if ir.fns.size != ir.sourcePlan.fns.size then
    throw <| .planInvariant .near "typed NEAR IR pureFn count does not match its source Plan"
  for method in ir.methods do
    if method.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .near
        s!"typed NEAR IR method '{method.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if method.operations.any opIsFnReturnValueV1 then
      throw <| .planInvariant .near
        s!"typed NEAR IR method '{method.name}' must not use pureFn returnValue ops"
  for fn in ir.fns do
    if fn.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .near
        s!"typed NEAR IR pureFn '{fn.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if fn.operations.any opIsMethodOnlyV1 then
      throw <| .planInvariant .near
        s!"typed NEAR IR pureFn '{fn.name}' must not use method-only host ops"
  let operationCount :=
    ir.methods.foldl (fun total method =>
      total + method.params.size + method.operations.size) 0 +
    ir.fns.foldl (fun total fn =>
      total + fn.paramCount + fn.operations.size) 0
  if operationCount > ir.sourcePlan.resourceLimits.maxRecipeNodes then
    throw <| .planInvariant .near
      s!"typed NEAR IR exceeds recipe node limit {ir.sourcePlan.resourceLimits.maxRecipeNodes}"
  let expected := expectedMethods ir.sourcePlan expectedKeys
  unless ir.methods == expected do
    throw <| .planInvariant .near
      "typed NEAR IR methods/operations are not the exact lowering of their source Plan"
  let expectedFnIR := expectedFns ir.sourcePlan expectedKeys
  unless ir.fns == expectedFnIR do
    throw <| .planInvariant .near
      "typed NEAR IR pureFn operations are not the exact lowering of their source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let keys := makeKeyRegions plan
  let memory := makeMemoryLayout plan keys
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    imports := plan.hostImports
    registers := canonicalRegisters
    keys
    memory
    methods := expectedMethods plan keys
    fns := expectedFns plan keys
  }
  validateIR ir
  return ir

private def uint64Hex (value : UInt64) : String :=
  let raw := String.ofList (Nat.toDigits 16 value.toNat)
  let raw := if raw.isEmpty then "0" else raw
  String.ofList (List.replicate (16 - raw.length) '0') ++ raw

private def renderImport : HostImport → String
  | .input => "  (import \"env\" \"input\" (func $pf_input (param i64)))\n"
  | .registerLen =>
      "  (import \"env\" \"register_len\" (func $pf_register_len (param i64) (result i64)))\n"
  | .readRegister =>
      "  (import \"env\" \"read_register\" (func $pf_read_register (param i64 i64)))\n"
  | .storageRead =>
      "  (import \"env\" \"storage_read\" (func $pf_storage_read (param i64 i64 i64) (result i64)))\n"
  | .storageWrite =>
      "  (import \"env\" \"storage_write\" (func $pf_storage_write (param i64 i64 i64 i64 i64) (result i64)))\n"
  | .valueReturn =>
      "  (import \"env\" \"value_return\" (func $pf_value_return (param i64 i64)))\n"
  | .attachedDeposit =>
      "  (import \"env\" \"attached_deposit\" (func $pf_attached_deposit (param i64)))\n"
  | .logUtf8 =>
      "  (import \"env\" \"log_utf8\" (func $pf_log_utf8 (param i64 i64)))\n"
  | .panicUtf8 =>
      "  (import \"env\" \"panic_utf8\" (func $pf_panic_utf8 (param i64 i64)))\n"
  | .promiseBatchCreate =>
      -- account_id_len, account_id_ptr → promise_index
      "  (import \"env\" \"promise_batch_create\" (func $pf_promise_batch_create (param i64 i64) (result i64)))\n"
  | .promiseBatchActionFunctionCall =>
      -- promise_idx, method_len, method_ptr, args_len, args_ptr,
      -- amount_low, amount_high, gas. Deposit/gas are always zero placeholders
      -- in this pilot (explicit in the call site, not silent economics).
      "  (import \"env\" \"promise_batch_action_function_call\" (func $pf_promise_batch_action_function_call (param i64 i64 i64 i64 i64 i64 i64 i64)))\n"

/-- Load a LE integer of `byteWidth` from `addr` into an i64 local (zero-extend). -/
private def renderLoadLeToI64 (indent : String) (destination addr byteWidth : Nat) : String :=
  match byteWidth with
  | 1 =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i32.load8_u (i32.const {addr}))))\n"
  | 2 =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i32.load16_u (i32.const {addr}))))\n"
  | 4 =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i32.load (i32.const {addr}))))\n"
  | _ =>
      s!"{indent}(local.set $t{destination} (i64.load (i32.const {addr})))\n"

/-- Store low `byteWidth` bytes of an i64 local to `addr` (LE). -/
private def renderStoreI64Le (indent : String) (addr valueTemp byteWidth : Nat) : String :=
  match byteWidth with
  | 1 =>
      s!"{indent}(i32.store8 (i32.const {addr}) (i32.wrap_i64 (local.get $t{valueTemp})))\n"
  | 2 =>
      s!"{indent}(i32.store16 (i32.const {addr}) (i32.wrap_i64 (local.get $t{valueTemp})))\n"
  | 4 =>
      s!"{indent}(i32.store (i32.const {addr}) (i32.wrap_i64 (local.get $t{valueTemp})))\n"
  | _ =>
      s!"{indent}(i64.store (i32.const {addr}) (local.get $t{valueTemp}))\n"

/-- Zero `byteWidth` bytes at `addr`. -/
private def renderZeroLe (indent : String) (addr byteWidth : Nat) : String :=
  match byteWidth with
  | 1 => s!"{indent}(i32.store8 (i32.const {addr}) (i32.const 0))\n"
  | 2 => s!"{indent}(i32.store16 (i32.const {addr}) (i32.const 0))\n"
  | 4 => s!"{indent}(i32.store (i32.const {addr}) (i32.const 0))\n"
  | _ => s!"{indent}(i64.store (i32.const {addr}) (i64.const 0))\n"

private def renderReadKey (registers : RegisterLayout) (memory : MemoryLayout)
    (indent : String) (destination : Nat) (field : KeyRegion)
    (byteWidth : Nat := 8) : String :=
  s!"{indent}(if (i64.ne (call $pf_storage_read (i64.const {field.length}) (i64.const {field.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
    s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const {byteWidth})) (then unreachable))\n" ++
    s!"{indent}(call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n" ++
    renderLoadLeToI64 indent destination memory.valueOffset byteWidth

/-- Offset of the transient interface-message scratch region (right after the
    8-byte value-return cell; bounded well inside the first memory page). -/
private def messageOffset (memory : MemoryLayout) : Nat :=
  memory.valueOffset + 8

/-- Render a u64 temp as 16 lowercase-hex chars (MSB first) at consecutive
    scratch offsets. `c = d + 48 + 39·(d > 9)` per nibble. -/
private def renderHexArg (indent : String) (offset : Nat) (arg : Nat) : String := Id.run do
  let mut output := ""
  for nibble in [0:16] do
    let shift := 60 - 4 * nibble
    let digit :=
      s!"(i64.and (i64.shr_u (local.get $t{arg}) (i64.const {shift})) (i64.const 15))"
    output := output ++
      s!"{indent}(i32.store8 (i32.const {offset + nibble}) (i32.add (i32.add (i32.const 48) (i32.wrap_i64 {digit})) (i32.mul (i32.const 39) (i64.gt_u {digit} (i64.const 9)))))\n"
  return output

/-- Render the canonical interface message `pf-{tag}:{name}:{hex,...}` into the
    scratch region and the host call consuming it. -/
private def renderInterfaceMessage (registers : RegisterLayout) (memory : MemoryLayout)
    (indent : String) (tag : String) (hostCall : String)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (isEvent : Bool) (declIndex : Nat) (args : Array Nat) : String := Id.run do
  let _ := registers
  let binding := (if isEvent then events else errors)[declIndex]!
  let prefixBytes := s!"pf-{tag}:{binding.name}".toUTF8
  let offset := messageOffset memory
  let mut output := ""
  for i in [0:prefixBytes.size] do
    output := output ++
      s!"{indent}(i32.store8 (i32.const {offset + i}) (i32.const {prefixBytes[i]!.toNat}))\n"
  let mut cursor := offset + prefixBytes.size
  if !args.isEmpty then
    output := output ++
      s!"{indent}(i32.store8 (i32.const {cursor}) (i32.const 58))\n"
    cursor := cursor + 1
    for j in [0:args.size] do
      if j > 0 then
        output := output ++
          s!"{indent}(i32.store8 (i32.const {cursor}) (i32.const 44))\n"
        cursor := cursor + 1
      output := output ++ renderHexArg indent cursor args[j]!
      cursor := cursor + 16
  output := output ++
    s!"{indent}(call ${hostCall} (i64.const {cursor - offset}) (i64.const {offset}))\n"
  return output

/-- First-seen order of schedule receiver/method strings across the IR, used to
    pin account-id/method bytes as `(data ...)` segments so the WAT artifact
    contains the literal strings (not only store8 immediates). -/
private partial def collectPromiseStringsFromOps (ops : Array Operation) : Array String :=
  ops.foldl (fun acc op =>
    match op with
    | .promiseAccount receiver method _ =>
        let acc := if acc.contains receiver then acc else acc.push receiver
        if acc.contains method then acc else acc.push method
    | .ifRegion _ thenOps elseOps =>
        acc ++ collectPromiseStringsFromOps thenOps ++ collectPromiseStringsFromOps elseOps
    | .switchRegion _ cases defaultOps =>
        cases.foldl (fun a (_, caseOps) => a ++ collectPromiseStringsFromOps caseOps)
          (acc ++ collectPromiseStringsFromOps defaultOps)
    | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
        acc ++ collectPromiseStringsFromOps condOps ++
          collectPromiseStringsFromOps bodyOps ++
          collectPromiseStringsFromOps updateOps
    | _ => acc) #[]

private def collectPromiseStrings (ir : IR) : Array String :=
  ir.methods.foldl (fun acc m => acc ++ collectPromiseStringsFromOps m.operations) #[] ++
    ir.fns.foldl (fun acc f => acc ++ collectPromiseStringsFromOps f.operations) #[]

/-- Place promise strings in a fixed free region after the value/scratch area so
    they never collide with KV key data, input packing, or deposit cells.
    Returns (string → offset) pairs in first-seen order. -/
private def layoutPromiseStrings (memory : MemoryLayout) (strings : Array String) :
    Array (String × Nat) := Id.run do
  -- valueOffset+8 is the interface-message scratch; leave 1 KiB for event/
  -- error/arg payloads, then pin schedule account/method bytes.
  let mut offset := memory.valueOffset + 1024
  let mut table : Array (String × Nat) := #[]
  for s in strings do
    unless table.any (fun p => p.1 == s) do
      table := table.push (s, offset)
      offset := offset + s.toUTF8.size
  pure table

private def promiseStringOffset (table : Array (String × Nat)) (s : String) : Nat :=
  match table.find? (fun p => p.1 == s) with
  | some (_, off) => off
  | none => 0

private partial def renderOperation (registers : RegisterLayout) (memory : MemoryLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fnNames : Array String) (promiseStr : Array (String × Nat))
    (indent : String) : Operation → String
  | .checkInputLen bytes =>
      s!"{indent}(call $pf_input (i64.const {registers.input}))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.input})) (i64.const {bytes})) (then unreachable))\n" ++
        (if bytes == 0 then "" else
          s!"{indent}(call $pf_read_register (i64.const {registers.input}) (i64.const {memory.inputOffset}))\n")
  | .requireZeroAttachedDeposit =>
      s!"{indent}(call $pf_attached_deposit (i64.const {memory.depositOffset}))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset})) (i64.const 0)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset + 8})) (i64.const 0)) (then unreachable))\n"
  | .requireLayoutAbsent marker =>
      s!"{indent}(if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 0)) (then unreachable))\n"
  | .requireLayout marker value =>
      s!"{indent}(if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const 8)) (then unreachable))\n" ++
        s!"{indent}(call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.valueOffset})) (i64.const {value.toNat})) (then unreachable))\n"
  | .zeroState field =>
      renderZeroLe indent memory.valueOffset 8 ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .narrowZeroState bitWidth field =>
      let bw := bitWidth / 8
      renderZeroLe indent memory.valueOffset bw ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const {bw}) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .literal destination value =>
      s!"{indent}(local.set $t{destination} (i64.const {value.toNat}))\n"
  | .loadParam destination inputOffset =>
      s!"{indent}(local.set $t{destination} (i64.load (i32.const {memory.inputOffset + inputOffset})))\n"
  | .narrowLoadParam bitWidth destination inputOffset =>
      renderLoadLeToI64 indent destination (memory.inputOffset + inputOffset) (bitWidth / 8)
  | .loadState destination field =>
      renderReadKey registers memory indent destination field 8
  | .narrowLoadState bitWidth destination field =>
      renderReadKey registers memory indent destination field (bitWidth / 8)
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
      -- i64 add with signed overflow: ((a^r)&(b^r)) sign bit set.
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
      let insn :=
        match op with
        | .eq => "i64.eq"
        | .ne => "i64.ne"
        | .lt => "i64.lt_s"
        | .le => "i64.le_s"
        | .gt => "i64.gt_s"
        | .ge => "i64.ge_s"
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .checkedNeg destination source =>
      s!"{indent}(if (i64.eq (local.get $t{source}) (i64.const -9223372036854775808)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.sub (i64.const 0) (local.get $t{source})))\n"
  | .sar destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitAnd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitXor destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .shl destination lhs rhs =>
      -- Wasm i64.shl masks the count mod 64; guard count ≥ 64 first so the
      -- host trap matches the wire invalidShift semantics, then emit the
      -- shift and a round-trip overflow guard exact for k < 64.
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shl (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (local.get $t{rhs})) (local.get $t{lhs})) (then unreachable))\n"
  | .shr destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{source}) (i64.const -1)))\n"
  | .narrowCheckedAdd bitWidth destination lhs rhs =>
      -- i64.add then high bits above bitWidth must be zero.
      s!"{indent}(local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowCheckedSub _bitWidth destination lhs rhs =>
      -- Underflow guard identical to UInt64; result auto in-range for UInt.
      s!"{indent}(if (i64.lt_u (local.get $t{lhs}) (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowCheckedMul bitWidth destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowCheckedDiv _bitWidth destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.div_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowCheckedMod _bitWidth destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.rem_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitAnd _bitWidth destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitOr _bitWidth destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitXor _bitWidth destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .narrowBitNot bitWidth destination source =>
      let mask :=
        match bitWidth with
        | 8 => "255"
        | 16 => "65535"
        | 32 => "4294967295"
        | _ => "18446744073709551615"
      s!"{indent}(local.set $t{destination} (i64.and (i64.xor (local.get $t{source}) (i64.const -1)) (i64.const {mask})))\n"
  | .narrowShl bitWidth destination lhs rhs =>
      -- Count ≥ 64 trap; shl; high bits above bitWidth must be 0.
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shl (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (i64.const {bitWidth})) (i64.const 0)) (then unreachable))\n"
  | .narrowShr _bitWidth destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i64.eqz (local.get $t{source}))))\n"
  | .boolAnd destination lhs rhs =>
      -- Bitwise == logical on 0/1 Bool words; both sides already evaluated.
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .compare destination lhs rhs op =>
      let insn :=
        match op with
        | .eq => "i64.eq"
        | .ne => "i64.ne"
        | .lt => "i64.lt_u"
        | .le => "i64.le_u"
        | .gt => "i64.gt_u"
        | .ge => "i64.ge_u"
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .assert condition =>
      s!"{indent}(if (i64.eqz (local.get $t{condition})) (then unreachable))\n"
  | .returnNone =>
      s!"{indent}(return)\n"
  | .emitEvent eventIndex args =>
      renderInterfaceMessage registers memory indent "event" "pf_log_utf8"
        events errors true eventIndex args
  | .promiseAccount receiver method args =>
      -- Account id / method come from module `(data ...)` segments (literal
      -- strings in the WAT). Args are a deterministic u64-LE payload written
      -- into the interface-message scratch (each arg 8-byte LE via i64.store,
      -- source order). Deposit u128=(0,0) and gas=0 are explicit zero
      -- placeholders — not economics. Fire-and-forget: promise failure never
      -- propagates to the caller.
      Id.run do
        let _ := registers
        let _ := events
        let _ := errors
        let _ := fnNames
        let accountOffset := promiseStringOffset promiseStr receiver
        let methodOffset := promiseStringOffset promiseStr method
        let accountLen := receiver.toUTF8.size
        let methodLen := method.toUTF8.size
        let argsOffset := messageOffset memory
        let mut output := ""
        for j in [0:args.size] do
          output := output ++
            s!"{indent}(i64.store (i32.const {argsOffset + 8 * j}) (local.get $t{args[j]!}))\n"
        let argsLen := 8 * args.size
        pure <| output ++
          s!"{indent}(call $pf_promise_batch_action_function_call\n" ++
          s!"{indent}  (call $pf_promise_batch_create (i64.const {accountLen}) (i64.const {accountOffset}))\n" ++
          s!"{indent}  (i64.const {methodLen}) (i64.const {methodOffset})\n" ++
          s!"{indent}  (i64.const {argsLen}) (i64.const {argsOffset})\n" ++
          s!"{indent}  (i64.const 0) (i64.const 0) (i64.const 0))\n"
  | .revertError errorIndex args =>
      renderInterfaceMessage registers memory indent "error" "pf_panic_utf8"
        events errors false errorIndex args
  | .storeState field value =>
      s!"{indent}(i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))\n" ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.evicted})) (i64.const 8)) (then unreachable))\n"
  | .narrowStoreState bitWidth field value =>
      let bw := bitWidth / 8
      renderStoreI64Le indent memory.valueOffset value bw ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const {bw}) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.evicted})) (i64.const {bw})) (then unreachable))\n"
  | .setLayout marker value =>
      s!"{indent}(i64.store (i32.const {memory.valueOffset}) (i64.const {value.toNat}))\n" ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .setReturnData byteLen value =>
      s!"{indent}(i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))\n" ++
        s!"{indent}(call $pf_value_return (i64.const {byteLen}) (i64.const {memory.valueOffset}))\n"
  | .callFn fnIndex destination args =>
      let name := match fnNames[fnIndex]? with
        | some n => n
        | none => "unknown"
      let argGets := String.intercalate " " <| args.toList.map fun a =>
        s!"(local.get $t{a})"
      let callArgs := if args.isEmpty then "" else " " ++ argGets
      s!"{indent}(local.set $t{destination} (call $fn_{name}{callArgs}))\n"
  | .returnValue value =>
      s!"{indent}(return (local.get $t{value}))\n"
  | .ifRegion condition thenOps elseOps =>
      let thenText := thenOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          (indent ++ "  ") operation) ""
      let elseText := elseOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          (indent ++ "  ") operation) ""
      s!"{indent}(if (local.get $t{condition})\n{indent}  (then\n" ++ thenText ++
        s!"{indent}  )\n" ++
        (if elseOps.isEmpty then "" else
          s!"{indent}  (else\n" ++ elseText ++ s!"{indent}  )\n") ++
        s!"{indent})\n"
  | .forRegion varTemp initial counterTemp maxIterations
        condOps condition bodyOps updateOps updateValue =>
      -- Canonical Wasm loop. Labels are deterministic from the induction temp
      -- index. Bound check sits at the back edge after the body (reference
      -- noteBackEdge): bodies 1..N pass; the (N+1)-th body runs then traps.
      -- A body return exits before the check. The latch `i := i+1` is
      -- unguarded: Normalize only runs the body while `i < end ≤ UInt64.max`.
      let inner := indent ++ "  "
      let deeper := indent ++ "    "
      let condText := condOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          deeper operation) ""
      let bodyText := bodyOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          deeper operation) ""
      let updateText := updateOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          deeper operation) ""
      s!"{indent}(local.set $t{varTemp} (local.get $t{initial}))\n" ++
        s!"{indent}(local.set $t{counterTemp} (i64.const 0))\n" ++
        s!"{indent}(block $pf_exit{varTemp}\n" ++
        s!"{inner}(loop $pf_loop{varTemp}\n" ++
        condText ++
        s!"{deeper}(br_if $pf_exit{varTemp} (i64.eqz (local.get $t{condition})))\n" ++
        bodyText ++
        s!"{deeper}(if (i64.ge_u (local.get $t{counterTemp}) (i64.const {maxIterations})) (then unreachable))\n" ++
        s!"{deeper}(local.set $t{counterTemp} (i64.add (local.get $t{counterTemp}) (i64.const 1)))\n" ++
        updateText ++
        s!"{deeper}(local.set $t{varTemp} (local.get $t{updateValue}))\n" ++
        s!"{deeper}(br $pf_loop{varTemp})\n" ++
        s!"{inner})\n" ++
        s!"{indent})\n"
  | .switchRegion scrutinee cases defaultOps =>
      -- Right-nested if/else chain: first matching case wins, else default.
      let rec renderCases (indent : String) (remaining : Array (UInt64 × Array Operation)) : String :=
        match remaining.toList with
        | [] =>
            let defaultText := defaultOps.foldl (fun output operation =>
              output ++ renderOperation registers memory events errors fnNames promiseStr
                (indent ++ "  ") operation) ""
            s!"{indent}(then\n" ++ defaultText ++ s!"{indent})\n"
        | (caseValue, caseOps) :: rest =>
            let caseText := caseOps.foldl (fun output operation =>
              output ++ renderOperation registers memory events errors fnNames promiseStr
                (indent ++ "  ") operation) ""
            s!"{indent}(if (i64.eq (local.get $t{scrutinee}) (i64.const {caseValue.toNat}))\n" ++
              s!"{indent}  (then\n" ++ caseText ++ s!"{indent}  )\n" ++
              s!"{indent}  (else\n" ++ renderCases (indent ++ "  ") rest.toArray ++
              s!"{indent})\n"
      match cases.toList with
      | [] =>
          defaultOps.foldl (fun output operation =>
            output ++ renderOperation registers memory events errors fnNames promiseStr
              indent operation) ""
      | (caseValue, caseOps) :: rest =>
          let caseText := caseOps.foldl (fun output operation =>
            output ++ renderOperation registers memory events errors fnNames promiseStr
              (indent ++ "  ") operation) ""
          s!"{indent}(if (i64.eq (local.get $t{scrutinee}) (i64.const {caseValue.toNat}))\n" ++
            s!"{indent}  (then\n" ++ caseText ++ s!"{indent}  )\n" ++
            s!"{indent}  (else\n" ++ renderCases (indent ++ "  ") rest.toArray ++
            s!"{indent})\n"

private def renderMethod (ir : IR) (promiseStr : Array (String × Nat))
    (method : MethodIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let locals := String.intercalate "" <| (Array.range method.tempCount).toList.map fun index =>
    s!" (local $t{index} i64)"
  let operations := String.intercalate "" <| method.operations.toList.map
    (renderOperation ir.registers ir.memory
      ir.sourcePlan.events ir.sourcePlan.errors fnNames promiseStr "    ")
  s!"  (func (export \"{method.name}\"){locals}\n" ++ operations ++ "  )\n"

/-- PureFn WAT: params occupy the first local indices (`$t0..`), extra temps
    follow, and the body ends with Wasm `return` of the result value. -/
private def renderFn (ir : IR) (promiseStr : Array (String × Nat)) (fn : FnIR) : String :=
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
    (renderOperation ir.registers ir.memory
      ir.sourcePlan.events ir.sourcePlan.errors fnNames promiseStr "    ")
  s!"  (func $fn_{fn.name}{params} (result i64){extraLocals}\n" ++
    operations ++ "  )\n"

private def renderWat (ir : IR) : String :=
  let imports := String.intercalate "" <| ir.imports.toList.map renderImport
  let promiseStr := layoutPromiseStrings ir.memory (collectPromiseStrings ir)
  let keyData := String.intercalate "" <| ir.keys.toList.map fun key =>
    s!"  (data (i32.const {key.offset}) \"{key.key}\")\n"
  -- Escape is unnecessary: account-id grammar and identifier method names are
  -- restricted to safe ASCII (no quotes/backslashes).
  let promiseData := String.intercalate "" <| promiseStr.toList.map fun (s, off) =>
    s!"  (data (i32.const {off}) \"{s}\")\n"
  let fns := String.intercalate "" <| ir.fns.toList.map (renderFn ir promiseStr)
  let methods := String.intercalate "" <| ir.methods.toList.map (renderMethod ir promiseStr)
  "(module\n" ++ imports ++
    s!"  (memory (export \"memory\") {ir.memory.minPages})\n" ++
    keyData ++ promiseData ++ fns ++ methods ++ ")\n"

private def renderMode : MethodMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderDepositPolicy : DepositPolicy → String
  | .requireZero => "zero-required"
  | .queryOnly => "query-only"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"{abiScalarTypeString param.byteWidth}\",\"inputOffset\":{param.inputOffset}}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderFieldJson (field : StorageField) : String :=
  s!"\{\"name\":\"{Targets.escapeJson field.name}\",\"sourceId\":{field.sourceId},\"key\":\"{Targets.escapeJson field.key}\",\"type\":\"{abiScalarTypeString field.byteWidth}\"}"

private def renderResultKindJson : MethodResultKind → String
  | .unit => "null"
  | .uint64 => "\"u64-le\""
  | .bool => "\"bool\""
  | .int64 => "\"i64-le\""
  | .uint8 => "\"u8-le\""
  | .uint16 => "\"u16-le\""
  | .uint32 => "\"u32-le\""

private def renderMethodJson (method : Method) : String :=
  let returns := renderResultKindJson method.resultKind
  "{" ++
    s!"\"name\":\"{Targets.escapeJson method.name}\"," ++
    s!"\"mode\":\"{renderMode method.mode}\"," ++
    s!"\"depositPolicy\":\"{renderDepositPolicy method.depositPolicy}\"," ++
    s!"\"exactInputLen\":{method.exactInputLen}," ++
    s!"\"args\":[{renderParamsJson method.params}],\"returns\":{returns}" ++
    "}"

private def renderAbi (plan : Plan) : String :=
  let fields := String.intercalate "," (plan.storage.fields.toList.map renderFieldJson)
  let methods := #[plan.initializer] ++ plan.entries
  let exports := String.intercalate ",\n    " (methods.toList.map renderMethodJson)
  "{\n" ++
    "  \"schema\": \"proof-forge-near-abi/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson plan.programName}\",\n" ++
    s!"  \"codegenProfile\": \"{plan.codegenProfile}\",\n" ++
    s!"  \"hostAbi\": \"{plan.hostAbi}\",\n" ++
    s!"  \"encoding\": \"{plan.inputAbi}\",\n" ++
    "  \"storage\": {" ++
    s!"\"markerKey\":\"{plan.storage.markerKey}\"," ++
    s!"\"layoutMarker\":\"0x{uint64Hex plan.storage.markerValue}\"," ++
    "\"initializerPayloadPolicy\":\"zero-all-fields\"," ++
    s!"\"fields\":[{fields}]" ++
    "},\n" ++
    "  \"exports\": [\n    " ++ exports ++ "\n  ]\n" ++
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
      path := s!"{ir.name}.near-abi.json"
      mediaType := "application/json"
      contents := renderAbi ir.sourcePlan
    }
  ]

/-- Replace methods on an existing IR (private `mk`; for validateIR characterization). -/
def withMethods (ir : IR) (methods : Array MethodIR) : IR :=
  { ir with methods }

/-- Replace pureFns on an existing IR (private `mk`; for validateIR characterization). -/
def withFns (ir : IR) (fns : Array FnIR) : IR :=
  { ir with fns }


/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files.
    Not a residual Plan→IR bypass. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

/-- Capability-gated public materialize entry (S6). -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

end ProofForgeV2.Targets.Near
