/-
  Tests.Semantic.ReferenceV1 — engineering suite for the D2-07 reference
  interpreter / InvariantABI state helpers.

  Engineering subset only (not formal TST-SEM-002/003 / TASK-D2-07). Pins the
  planned production modules:

    * `ProofForgeV2.Semantic.InvariantABI`
        LogicalStateV1, defaultValueV1, initialLogicalStateV1,
        stateConformsBoolV1
    * `ProofForgeV2.Semantic.ReferenceV1`
        ReferenceValueV1 / InvocationV1 / ExternalResponsesV1 /
        OrderedEffectV1 / OutcomeV1 carriers,
        admitReferenceProgramSliceV1, stepReferenceSliceV1

  Coverage (focused engineering contract):
    1. NormalizeV1 S1 Counter carrier admission + init/entry/view + UInt64
       overflow standard revert with pre-state rollback.
    2. Hand-built structure-gated primitive-effect program: Emit → ExternalCall
       → Schedule ordered effect log, state commit on returned, zero committed
       effects + unchanged state on external reverted.
    3. Response cursor: missing / reordered / extra; matched external revert +
       trailing extra; declared/standard program revert + trailing response —
       all unique `.trapped(.invalidExternalResponse, pre)`.
    4. Emit-then-revert discards overlay/effects; wrong callable
       id/kind/arity/type/noncanonical args → invalidInvocation; entry before
       init / init twice; determinism.
    5. Admission fail-closed on unsupported Int / aggregate / PureCall /
       ContextRead / Commit / view stateStore / view Emit (errors separated
       from Outcome).
    6. Lifecycle + trailing: uninit/alreadyInit + trailing →
       invalidExternalResponse; invalidInvocation + trailing stays
       invalidInvocation.
    7. Unit `return_ none` ok; Unit `return_ (some unit)` → invalidCore.
    8. Switch miss / Term.Trap → unreachable; trap+trailing overrides to
       invalidExternalResponse.
    9. Bounded loop same EffectId twice → occurrences (0,0)/(0,1); over-bound
       → boundExceeded + pre rollback.
   10. Compact UInt underflow / div-zero / invalidShift standard reverts.

  Hand fixtures always pass through `encodeSemanticProgramDataV1` then
  `decodeSemanticProgramV1` (no carrier bypass).
-/
import Tests.Language.ParserSession
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Semantic.ReferenceV1

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def bytesEqual (a b : ByteArray) : Bool := a == b

private def moduleName : String := "Tests.ReferenceV1"

private def testSourcePath (label : String) : String :=
  "tests/reference-" ++ label ++ ".pf"

private def wrap (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ body

private unsafe def loadSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source (testSourcePath label) moduleName none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"{label}: load failed: {error.render}"

private def leBytesFromNat (n : Nat) (len : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity len
  let mut v := n
  for _ in [:len] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

private def u64Bytes (n : Nat) : ByteArray := leBytesFromNat n 8

private def stateSlot (valueBytes : ByteArray) : ByteArray :=
  (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes

private def refU64 (typeId : TypeIdV1) (n : Nat) : ReferenceValueV1 :=
  { typeId, valueBytes := u64Bytes n }

private def emptyContext : Array ContextInputV1 := #[]

private def emptyResponses : ExternalResponsesV1 := #[]

private def inv (callableId : CallableIdV1) (args : Array ReferenceValueV1) :
    InvocationV1 :=
  { callableId, args, context := emptyContext }

private def logicalStateEq (a b : LogicalStateV1) : Bool :=
  a.initialized == b.initialized && bytesEqual a.canonicalValues b.canonicalValues

private def refValueEq (a b : ReferenceValueV1) : Bool :=
  a.typeId == b.typeId && bytesEqual a.valueBytes b.valueBytes

private def optionRefEq (a b : Option ReferenceValueV1) : Bool :=
  match a, b with
  | none, none => true
  | some x, some y => refValueEq x y
  | _, _ => false

private def occurrenceEq (a b : EffectOccurrenceV1) : Bool :=
  a.effectId == b.effectId && a.occurrence == b.occurrence

private def payloadEq (a b : OrderedEffectPayloadV1) : Bool :=
  match a, b with
  | .event ea aa, .event eb ab =>
      ea == eb && aa.size == ab.size &&
        (List.range aa.size).all fun i =>
          match aa[i]?, ab[i]? with
          | some x, some y => refValueEq x y
          | _, _ => false
  | .externalCall ca aa, .externalCall cb ab =>
      ca == cb && aa.size == ab.size &&
        (List.range aa.size).all fun i =>
          match aa[i]?, ab[i]? with
          | some x, some y => refValueEq x y
          | _, _ => false
  | .schedule ca aa, .schedule cb ab =>
      ca == cb && aa.size == ab.size &&
        (List.range aa.size).all fun i =>
          match aa[i]?, ab[i]? with
          | some x, some y => refValueEq x y
          | _, _ => false
  | _, _ => false

private def effectEq (a b : OrderedEffectV1) : Bool :=
  occurrenceEq a.occurrence b.occurrence && payloadEq a.payload b.payload

private def effectsEq (a b : Array OrderedEffectV1) : Bool :=
  a.size == b.size &&
    (List.range a.size).all fun i =>
      match a[i]?, b[i]? with
      | some x, some y => effectEq x y
      | _, _ => false

private def expectReturned
    (label : String) (outcome : OutcomeV1)
    (post : LogicalStateV1) (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1) : IO Unit := do
  match outcome with
  | .returned post' value' effects' =>
      expect (logicalStateEq post' post)
        s!"{label}: returned post-state mismatch"
      expect (optionRefEq value' value)
        s!"{label}: returned value mismatch"
      expect (effectsEq effects' effects)
        s!"{label}: returned effects mismatch (got size {effects'.size})"
  | .reverted reason _ =>
      throw <| IO.userError s!"{label}: expected returned, got reverted {repr reason}"
  | .trapped fault _ =>
      throw <| IO.userError s!"{label}: expected returned, got trapped {repr fault}"

private def expectRevertedStandard
    (label : String) (outcome : OutcomeV1)
    (code : StandardRevertCodeV1) (pre : LogicalStateV1) : IO Unit := do
  match outcome with
  | .reverted (.standard c) st =>
      expect (c == code) s!"{label}: standard code, got {repr c}"
      expect (logicalStateEq st pre) s!"{label}: revert must keep pre-state"
  | .reverted reason _ =>
      throw <| IO.userError s!"{label}: expected standard {repr code}, got {repr reason}"
  | .returned _ _ _ =>
      throw <| IO.userError s!"{label}: expected standard revert, got returned"
  | .trapped fault _ =>
      throw <| IO.userError s!"{label}: expected standard revert, got trapped {repr fault}"

private def expectRevertedDeclared
    (label : String) (outcome : OutcomeV1)
    (errorId : ErrorIdV1) (pre : LogicalStateV1) : IO Unit := do
  match outcome with
  | .reverted (.declared eid args) st =>
      expect (eid == errorId) s!"{label}: declared errorId, got {eid}"
      expect args.isEmpty s!"{label}: declared args empty"
      expect (logicalStateEq st pre) s!"{label}: declared revert keeps pre-state"
  | .reverted reason _ =>
      throw <| IO.userError s!"{label}: expected declared, got {repr reason}"
  | other =>
      throw <| IO.userError s!"{label}: expected declared revert, got {repr other}"

private def expectTrapped
    (label : String) (outcome : OutcomeV1)
    (fault : SemanticFaultV1) (pre : LogicalStateV1) : IO Unit := do
  match outcome with
  | .trapped f st =>
      expect (f == fault) s!"{label}: fault, expected {repr fault}, got {repr f}"
      expect (logicalStateEq st pre) s!"{label}: trap must keep pre-state"
  | .returned _ _ effects =>
      throw <| IO.userError
        s!"{label}: expected trap {repr fault}, got returned effects={effects.size}"
  | .reverted reason _ =>
      throw <| IO.userError
        s!"{label}: expected trap {repr fault}, got reverted {repr reason}"

private def encodeCarrier (label : String) (data : SemanticProgramDataV1) :
    IO SemanticProgramV1 := do
  let bytes ← match encodeSemanticProgramDataV1 data with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"{label}: encode failed: {repr e}"
  match decodeSemanticProgramV1 bytes with
  | .ok c => pure c
  | .error e => throw <| IO.userError s!"{label}: carrier decode failed: {repr e}"

private def admitOk (label : String) (carrier : SemanticProgramV1) :
    IO AdmittedReferenceSliceV1 := do
  match admitReferenceProgramSliceV1 carrier with
  | .ok a => pure a
  | .error e => throw <| IO.userError s!"{label}: admit failed: {repr e}"

private def admitUnsupported (label : String) (carrier : SemanticProgramV1)
    (detailPred : String → Bool) (hint : String) : IO Unit := do
  match admitReferenceProgramSliceV1 carrier with
  | .ok _ =>
      throw <| IO.userError s!"{label}: expected admission unsupported, got ok"
  | .error (.unsupported detail) =>
      expect (detailPred detail)
        s!"{label}: unsupported detail should mention {hint}, got {detail}"
  | .error e =>
      throw <| IO.userError
        s!"{label}: expected .unsupported (not Outcome), got {repr e}"

private def emptyData (name : String) : IO SemanticProgramDataV1 := do
  let qn ← match parseQualifiedName #["Tests", name] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  pure {
    qualifiedName := qn
    types := #[]
    constants := #[]
    logicalState := #[]
    events := #[]
    errors := #[]
    callables := #[]
    invariants := #[]
    requirements := { items := #[] }
  }

private def mkEntry
    (id : CallableIdV1) (name : String) (params : Array ParameterV1)
    (resultTypeId : TypeIdV1) (instructions : Array InstructionV1)
    (terminator : TerminatorV1) : CallableV1 :=
  {
    id
    kind := .entry
    name := some name
    params
    result := { typeId := resultTypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{ id := 0, params := #[], instructions, terminator }]
    loopBounds := #[]
    invariantSteps := none
  }

private def mkView
    (id : CallableIdV1) (name : String) (params : Array ParameterV1)
    (resultTypeId : TypeIdV1) (instructions : Array InstructionV1)
    (terminator : TerminatorV1) : CallableV1 :=
  {
    id
    kind := .view
    name := some name
    params
    result := { typeId := resultTypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{ id := 0, params := #[], instructions, terminator }]
    loopBounds := #[]
    invariantSteps := none
  }

private def mkInit
    (id : CallableIdV1) (params : Array ParameterV1)
    (unitTypeId : TypeIdV1) (instructions : Array InstructionV1)
    (terminator : TerminatorV1) : CallableV1 :=
  {
    id
    kind := .initializer
    name := none
    params
    result := { typeId := unitTypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{ id := 0, params := #[], instructions, terminator }]
    loopBounds := #[]
    invariantSteps := none
  }

private def mkPureFn
    (id : CallableIdV1) (name : String) (params : Array ParameterV1)
    (resultTypeId : TypeIdV1) (instructions : Array InstructionV1)
    (terminator : TerminatorV1) : CallableV1 :=
  {
    id
    kind := .pureFn
    name := some name
    params
    result := { typeId := resultTypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{ id := 0, params := #[], instructions, terminator }]
    loopBounds := #[]
    invariantSteps := none
  }

/-- Multi-block entry callable (loops / switch / trap control-flow fixtures). -/
private def mkEntryBlocks
    (id : CallableIdV1) (name : String) (params : Array ParameterV1)
    (resultTypeId : TypeIdV1) (blocks : Array BlockV1)
    (loopBounds : Array LoopBoundV1 := #[]) : CallableV1 :=
  {
    id
    kind := .entry
    name := some name
    params
    result := { typeId := resultTypeId, visibility := .public_ }
    entryBlock := 0
    blocks
    loopBounds
    invariantSteps := none
  }

private def blk (id : BlockIdV1) (instructions : Array InstructionV1)
    (terminator : TerminatorV1) : BlockV1 :=
  { id, params := #[], instructions, terminator }

private def jumpTo (blockId : BlockIdV1) : TerminatorV1 :=
  .jump { blockId, args := #[] }

private def instr (result : Option ValueDefV1) (op : SemanticOpV1) : InstructionV1 :=
  { result, op }

private def vd (valueId : ValueIdV1) (typeId : TypeIdV1) : ValueDefV1 :=
  { valueId, typeId }

private def trailingResp : ExternalResponsesV1 :=
  #[{ occurrence := { effectId := 0, occurrence := 0 }, disposition := .returned }]

private def qn2 (a b : String) : IO QualifiedName := do
  match parseQualifiedName #[a, b] with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"qn2: {e}"

/-- NormalizeV1 Counter path: admission, init/entry/view, overflow rollback. -/
private unsafe def testIfMatchReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Multi-block CFG: if/else branches and switch on UInt64 literals.
  let ifSource := wrap "IfRef" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      count := count + delta\n" ++
    "    else\n" ++
    "      count := delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let ifValidated ← loadSource session "if-ref" ifSource
  let ifCarrier ← match normalizeProgramV1 ifValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"if-ref: normalize failed: {repr e}"
  let ifData ← match validateSemanticProgramV1 ifCarrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"if-ref: validate failed: {repr e}"
  let ifAdmitted ← admitOk "if-ref" ifCarrier
  let u64Tid : TypeIdV1 :=
    match ifData.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let ifInit : CallableIdV1 := 0
  let ifBump : CallableIdV1 := 1
  let ifGet : CallableIdV1 := 2
  let ifInitial ← match initialLogicalStateV1 ifCarrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"if-ref: initialLogicalState: {repr e}"
  let zeroPost :=
    stepReferenceSliceV1 ifAdmitted ifInitial (inv ifInit #[refU64 u64Tid 0]) emptyResponses
  let zeroState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 0) }
  expectReturned "if-ref-init" zeroPost zeroState none #[]
  -- count=0 → else branch: count := delta (3)
  let elseRes :=
    stepReferenceSliceV1 ifAdmitted zeroState (inv ifBump #[refU64 u64Tid 3]) emptyResponses
  let threeState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 3) }
  expectReturned "if-ref-else" elseRes threeState (some (refU64 u64Tid 3)) #[]
  -- count=3>0 → then branch: count := 3+2 = 5
  let thenRes :=
    stepReferenceSliceV1 ifAdmitted threeState (inv ifBump #[refU64 u64Tid 2]) emptyResponses
  let fiveState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 5) }
  expectReturned "if-ref-then" thenRes fiveState (some (refU64 u64Tid 5)) #[]
  let afterGet :=
    stepReferenceSliceV1 ifAdmitted fiveState (inv ifGet #[]) emptyResponses
  expectReturned "if-ref-get" afterGet fiveState (some (refU64 u64Tid 5)) #[]

  -- Switch on UInt64 literals with wildcard.
  let matchSource := wrap "MatchRef" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry apply(delta : UInt64) : UInt64 do\n" ++
    "    match delta with\n" ++
    "    | 0 => do\n" ++
    "      return count\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | _ => do\n" ++
    "      count := delta\n" ++
    "    return count\n"
  let matchValidated ← loadSource session "match-ref" matchSource
  let matchCarrier ← match normalizeProgramV1 matchValidated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"match-ref: normalize failed: {repr e}"
  let matchAdmitted ← admitOk "match-ref" matchCarrier
  let matchInit : CallableIdV1 := 0
  let matchApply : CallableIdV1 := 1
  let matchInitial ← match initialLogicalStateV1 matchCarrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"match-ref: initialLogicalState: {repr e}"
  let mInitPost :=
    stepReferenceSliceV1 matchAdmitted matchInitial
      (inv matchInit #[refU64 u64Tid 7]) emptyResponses
  let sevenState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 7) }
  expectReturned "match-ref-init" mInitPost sevenState none #[]
  -- delta=0 → case 0: return count (7), state unchanged
  let case0 :=
    stepReferenceSliceV1 matchAdmitted sevenState
      (inv matchApply #[refU64 u64Tid 0]) emptyResponses
  expectReturned "match-ref-case0" case0 sevenState (some (refU64 u64Tid 7)) #[]
  -- delta=1 → case 1: count := 7+1 = 8, return 8
  let case1 :=
    stepReferenceSliceV1 matchAdmitted sevenState
      (inv matchApply #[refU64 u64Tid 1]) emptyResponses
  let eightState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 8) }
  expectReturned "match-ref-case1" case1 eightState (some (refU64 u64Tid 8)) #[]
  -- delta=5 → default: count := 5, return 5
  let caseD :=
    stepReferenceSliceV1 matchAdmitted eightState
      (inv matchApply #[refU64 u64Tid 5]) emptyResponses
  let fiveStateM : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 5) }
  expectReturned "match-ref-default" caseD fiveStateM (some (refU64 u64Tid 5)) #[]

private unsafe def testEmitRevertReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Declared events/errors: emit commits ordered effects on returned;
  -- revert discards them and reports the declared error with args.
  let source := wrap "EventRef" <|
    "  state count : UInt64\n" ++
    "  event Moved(src : UInt64, dst : UInt64)\n" ++
    "  error Cap(limit : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Moved(count, delta)\n" ++
    "    if count > delta then\n" ++
    "      revert Cap(delta)\n" ++
    "    else\n" ++
    "      count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "event-ref" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"event-ref: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"event-ref: validate failed: {repr e}"
  let admitted ← admitOk "event-ref" carrier
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let initId : CallableIdV1 := 0
  let bumpId : CallableIdV1 := 1
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"event-ref: initialLogicalState: {repr e}"
  let initPost :=
    stepReferenceSliceV1 admitted initial (inv initId #[refU64 u64Tid 5]) emptyResponses
  let fiveState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 5) }
  expectReturned "event-ref-init" initPost fiveState none #[]
  -- count=5 > delta=3 → revert Cap(3): the Moved(5,3) effect is discarded and
  -- the pre-state is preserved.
  let reverting :=
    stepReferenceSliceV1 admitted fiveState (inv bumpId #[refU64 u64Tid 3]) emptyResponses
  match reverting with
  | .reverted (.declared eid args) st =>
      expect (eid == 0) s!"event-ref-revert: declared error id, got {eid}"
      expect (args == #[refU64 u64Tid 3])
        "event-ref-revert: declared args must carry delta"
      expect (logicalStateEq st fiveState)
        "event-ref-revert: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"event-ref-revert: expected declared revert, got {repr other}"
  -- count=5 < delta=7 → else: emit Moved(5,7) commits; count := 12; return 12.
  let emitted :=
    stepReferenceSliceV1 admitted fiveState (inv bumpId #[refU64 u64Tid 7]) emptyResponses
  let twelveState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 12) }
  let movedEffect : OrderedEffectV1 := {
    occurrence := { effectId := 0, occurrence := 0 }
    payload := .event 0 #[refU64 u64Tid 5, refU64 u64Tid 7]
  }
  expectReturned "event-ref-emit" emitted twelveState (some (refU64 u64Tid 12)) #[movedEffect]

private unsafe def testFnLocalCallReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Pure-fn calls: nested fn→fn evaluation, and a declared revert inside an
  -- fn propagating through the calling entry.
  let source := wrap "FnRef" <|
    "  state count : UInt64\n" ++
    "  error Cap(limit : UInt64)\n" ++
    "  fn double(x : UInt64) : UInt64 do\n" ++
    "    return x + x\n" ++
    "  fn check(x : UInt64, lim : UInt64) : UInt64 do\n" ++
    "    if x > lim then\n" ++
    "      revert Cap(lim)\n" ++
    "    else\n" ++
    "      return double(x)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := check(delta, 10) + double(count)\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "fn-ref" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"fn-ref: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"fn-ref: validate failed: {repr e}"
  let admitted ← admitOk "fn-ref" carrier
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let initId : CallableIdV1 := 2
  let bumpId : CallableIdV1 := 3
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"fn-ref: initialLogicalState: {repr e}"
  let initPost :=
    stepReferenceSliceV1 admitted initial (inv initId #[refU64 u64Tid 3]) emptyResponses
  let threeState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 3) }
  expectReturned "fn-ref-init" initPost threeState none #[]
  -- delta=4 ≤ 10 → check returns double(4)=8; double(count)=6; count=14.
  let callOk :=
    stepReferenceSliceV1 admitted threeState (inv bumpId #[refU64 u64Tid 4]) emptyResponses
  let fourteenState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 14) }
  expectReturned "fn-ref-call" callOk fourteenState (some (refU64 u64Tid 14)) #[]
  -- delta=20 > 10 → check reverts Cap(10) inside the fn; pre-state preserved.
  let reverting :=
    stepReferenceSliceV1 admitted fourteenState (inv bumpId #[refU64 u64Tid 20]) emptyResponses
  match reverting with
  | .reverted (.declared eid args) st =>
      expect (eid == 0) s!"fn-ref-revert: declared error id, got {eid}"
      expect (args == #[refU64 u64Tid 10])
        "fn-ref-revert: declared args must carry lim"
      expect (logicalStateEq st fourteenState)
        "fn-ref-revert: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"fn-ref-revert: expected declared revert, got {repr other}"

/-- Reference trace: mul ok/overflow, div ok/zero, mod ok/zero, neg 0/nonzero,
    bitNot, not. -/
private unsafe def testArithUnaryReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ArithRef" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry scale(factor : UInt64, divisor : UInt64) : UInt64 do\n" ++
    "    count := count * factor / divisor + count % divisor\n" ++
    "    return count\n" ++
    "  entry neg(x : UInt64) : UInt64 do\n" ++
    "    return -x\n" ++
    "  entry bits(x : UInt64) : UInt64 do\n" ++
    "    return ~x\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "arith-ref" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"arith-ref: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"arith-ref: validate failed: {repr e}"
  let admitted ← admitOk "arith-ref" carrier
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let initId : CallableIdV1 := 0
  let scaleId : CallableIdV1 := 1
  let negId : CallableIdV1 := 2
  let bitsId : CallableIdV1 := 3
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"arith-ref: initialLogicalState: {repr e}"
  let initPost :=
    stepReferenceSliceV1 admitted initial (inv initId #[refU64 u64Tid 6]) emptyResponses
  let sixState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 6) }
  expectReturned "arith-ref-init" initPost sixState none #[]
  -- 6*7/3 + 6%3 = 14 + 0 = 14.
  let scaled :=
    stepReferenceSliceV1 admitted sixState (inv scaleId #[refU64 u64Tid 7, refU64 u64Tid 3]) emptyResponses
  let fourteenState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 14) }
  expectReturned "arith-ref-scale" scaled fourteenState (some (refU64 u64Tid 14)) #[]
  -- Div by zero: standard divisionByZero, pre-state preserved.
  let divZero :=
    stepReferenceSliceV1 admitted fourteenState (inv scaleId #[refU64 u64Tid 1, refU64 u64Tid 0]) emptyResponses
  match divZero with
  | .reverted (.standard code) st =>
      expect (code == .divisionByZero) s!"arith-ref-div0: code, got {repr code}"
      expect (logicalStateEq st fourteenState) "arith-ref-div0: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"arith-ref-div0: expected standard revert, got {repr other}"
  -- Mul overflow: standard arithmeticOverflow.
  let maxPost : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 18446744073709551615) }
  let mulOverflow :=
    stepReferenceSliceV1 admitted maxPost (inv scaleId #[refU64 u64Tid 2, refU64 u64Tid 1]) emptyResponses
  match mulOverflow with
  | .reverted (.standard code) st =>
      expect (code == .arithmeticOverflow) s!"arith-ref-mulovf: code, got {repr code}"
      expect (logicalStateEq st maxPost) "arith-ref-mulovf: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"arith-ref-mulovf: expected standard revert, got {repr other}"
  -- Checked negation: -0 = 0; -3 underflows.
  let negZero :=
    stepReferenceSliceV1 admitted fourteenState (inv negId #[refU64 u64Tid 0]) emptyResponses
  expectReturned "arith-ref-neg0" negZero fourteenState (some (refU64 u64Tid 0)) #[]
  let negThree :=
    stepReferenceSliceV1 admitted fourteenState (inv negId #[refU64 u64Tid 3]) emptyResponses
  match negThree with
  | .reverted (.standard code) st =>
      expect (code == .arithmeticUnderflow) s!"arith-ref-neg3: code, got {repr code}"
      expect (logicalStateEq st fourteenState) "arith-ref-neg3: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"arith-ref-neg3: expected standard revert, got {repr other}"
  -- Bit-not: ~0 = maxU64.
  let bits :=
    stepReferenceSliceV1 admitted fourteenState (inv bitsId #[refU64 u64Tid 0]) emptyResponses
  expectReturned "arith-ref-bitnot" bits fourteenState
    (some (refU64 u64Tid 18446744073709551615)) #[]

private unsafe def testBoolResultReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Bool entry/view results: comparison and Bool literal return values.
  let source := wrap "BoolRef" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  entry equalsCount(delta : UInt64) : Bool do\n" ++
    "    return count == delta\n" ++
    "  view positive() : Bool do\n" ++
    "    return count > 0\n"
  let validated ← loadSource session "bool-result" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"bool-result: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"bool-result: validate failed: {repr e}"
  let admitted ← admitOk "bool-result" carrier
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let boolTid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .bool => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  expect (data.callables.size == 4) "bool-result: init + bump + equalsCount + positive"
  let initId : CallableIdV1 := 0
  let bumpId : CallableIdV1 := 1
  let equalsId : CallableIdV1 := 2
  let posId : CallableIdV1 := 3

  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"bool-result: initialLogicalState: {repr e}"
  let afterInit :=
    stepReferenceSliceV1 admitted initial (inv initId #[refU64 u64Tid 0]) emptyResponses
  let zeroPost : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 0) }
  expectReturned "bool-result-init" afterInit zeroPost none #[]

  -- positive() on count=0 → false (Bool 0x00)
  let afterPos0 :=
    stepReferenceSliceV1 admitted zeroPost (inv posId #[]) emptyResponses
  expectReturned "bool-result-pos0" afterPos0 zeroPost
    (some { typeId := boolTid, valueBytes := ByteArray.mk #[0] }) #[]

  -- equalsCount(0) on count=0 → true; equalsCount(1) → false
  let afterEqT :=
    stepReferenceSliceV1 admitted zeroPost (inv equalsId #[refU64 u64Tid 0]) emptyResponses
  expectReturned "bool-result-eqT" afterEqT zeroPost
    (some { typeId := boolTid, valueBytes := ByteArray.mk #[1] }) #[]
  let afterEqF :=
    stepReferenceSliceV1 admitted zeroPost (inv equalsId #[refU64 u64Tid 1]) emptyResponses
  expectReturned "bool-result-eqF" afterEqF zeroPost
    (some { typeId := boolTid, valueBytes := ByteArray.mk #[0] }) #[]

  -- bump(5) → count=5; positive() → true
  let afterBump :=
    stepReferenceSliceV1 admitted zeroPost (inv bumpId #[refU64 u64Tid 5]) emptyResponses
  let fivePost : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 5) }
  expectReturned "bool-result-bump" afterBump fivePost (some (refU64 u64Tid 5)) #[]
  let afterPos1 :=
    stepReferenceSliceV1 admitted fivePost (inv posId #[]) emptyResponses
  expectReturned "bool-result-pos1" afterPos1 fivePost
    (some { typeId := boolTid, valueBytes := ByteArray.mk #[1] }) #[]

private unsafe def testGuardedCounterReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Guarded counter: assert gates the subtraction (comparison + assert slice).
  let source := wrap "GuardedRef" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry decrement(delta : UInt64) : UInt64 do\n" ++
    "    assert count >= delta\n" ++
    "    count := count - delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "guarded" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"guarded: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"guarded: validate failed: {repr e}"
  let admitted ← admitOk "guarded" carrier
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  expect (data.callables.size == 3) "guarded: 3 callables (init/entry/view)"
  let initId : CallableIdV1 := 0
  let entryId : CallableIdV1 := 1
  let viewId : CallableIdV1 := 2

  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"guarded: initialLogicalState: {repr e}"
  let afterInit :=
    stepReferenceSliceV1 admitted initial (inv initId #[refU64 u64Tid 5]) emptyResponses
  let expectedInitPost : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 5) }
  expectReturned "guarded-init" afterInit expectedInitPost none #[]

  -- decrement(3) → returned 2, state=2
  let afterDec :=
    stepReferenceSliceV1 admitted expectedInitPost
      (inv entryId #[refU64 u64Tid 3]) emptyResponses
  let expectedDecPost : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 2) }
  expectReturned "guarded-dec" afterDec expectedDecPost (some (refU64 u64Tid 2)) #[]

  -- view get → returns 2, no state change
  let afterView :=
    stepReferenceSliceV1 admitted expectedDecPost (inv viewId #[]) emptyResponses
  expectReturned "guarded-view" afterView expectedDecPost (some (refU64 u64Tid 2)) #[]

  -- decrement(4): 2 >= 4 is false → assertionFailed, state untouched
  let guarded :=
    stepReferenceSliceV1 admitted expectedDecPost
      (inv entryId #[refU64 u64Tid 4]) emptyResponses
  expectRevertedStandard "guarded-assert" guarded .assertionFailed expectedDecPost

private unsafe def testCounterReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "CounterRef" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "counter" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"counter: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"counter: validate failed: {repr e}"
  let admitted ← admitOk "counter" carrier
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  expect (data.callables.size == 3) "counter: 3 callables (init/entry/view)"
  let initId : CallableIdV1 := 0
  let entryId : CallableIdV1 := 1
  let viewId : CallableIdV1 := 2

  -- initialLogicalStateV1: has initializer ⇒ initialized=false
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"counter: initialLogicalState: {repr e}"
  expect (initial.initialized == false)
    "counter: initial state initialized=false when initializer present"
  expect (stateConformsBoolV1 carrier initial == false)
    "counter: stateConformsBoolV1 requires initialized=true"
  let defU64 ← match defaultValueV1 carrier u64Tid with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"counter: defaultValue UInt64: {repr e}"
  expect (bytesEqual defU64 (u64Bytes 0)) "counter: default UInt64 is 0"
  expect (bytesEqual initial.canonicalValues (stateSlot (u64Bytes 0)))
    "counter: initial canonicalValues = default slot"

  -- init(7) → returned true-state, Unit result = none
  let afterInit :=
    stepReferenceSliceV1 admitted initial (inv initId #[refU64 u64Tid 7]) emptyResponses
  let expectedInitPost : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 7) }
  expectReturned "counter-init" afterInit expectedInitPost none #[]
  expect (stateConformsBoolV1 carrier expectedInitPost)
    "counter: post-init state conforms"

  -- entry increment(5) → returned 12, state=12
  let afterInc :=
    stepReferenceSliceV1 admitted expectedInitPost
      (inv entryId #[refU64 u64Tid 5]) emptyResponses
  let expectedIncPost : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 12) }
  expectReturned "counter-inc" afterInc expectedIncPost (some (refU64 u64Tid 12)) #[]

  -- view get → returns 12, no state change
  let afterView :=
    stepReferenceSliceV1 admitted expectedIncPost (inv viewId #[]) emptyResponses
  expectReturned "counter-view" afterView expectedIncPost (some (refU64 u64Tid 12)) #[]

  -- UInt64 max+1 → arithmeticOverflow, unchanged pre
  let maxPre : LogicalStateV1 :=
    { initialized := true
      canonicalValues := stateSlot (u64Bytes 18446744073709551615) }
  let overflow :=
    stepReferenceSliceV1 admitted maxPre
      (inv entryId #[refU64 u64Tid 1]) emptyResponses
  expectRevertedStandard "counter-overflow" overflow .arithmeticOverflow maxPre

private def primitiveEffectProgram : IO
    (SemanticProgramV1 × SemanticProgramDataV1 × QualifiedName × QualifiedName) := do
  -- types: 0 = Bool, 1 = Unit (anonymous leaves)
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit }
  ]
  -- Avoid identifier `state` (Language.Syntax keyword via open ProofForgeV2).
  let stateRows : Array StateDeclV1 := #[
    { id := 0, name := "flag", typeId := 0, visibility := .public_ }
  ]
  let events : Array EventDeclV1 := #[
    { id := 0, name := "Ping", fields := #[] }
  ]
  let extCallee ← qn2 "ext" "service"
  let wfCallee ← qn2 "wf" "job"
  -- Avoid identifier `entry` (Language.Syntax keyword via open ProofForgeV2).
  let entryCallable := mkEntry 0 "runEffects" #[] 1
    #[
      instr none (.emit 0 0 #[]),
      instr none (.externalCall 1 extCallee #[]),
      instr none (.schedule 2 wfCallee #[]),
      instr (some { valueId := 0, typeId := 0 })
        (.literal 0 (ByteArray.mk #[1])),
      instr none (.stateStore 0 0)
    ]
    (.return_ none)
  let base ← emptyData "PrimitiveEffects"
  let data : SemanticProgramDataV1 := {
    base with
    types
    logicalState := stateRows
    events
    callables := #[entryCallable]
  }
  let carrier ← encodeCarrier "primitive-effects" data
  pure (carrier, data, extCallee, wfCallee)

/-- Ordered effect log + response cursor + external-revert rollback. -/
private def testPrimitiveEffectLogAndResponses : IO Unit := do
  let (carrier, _data, extCallee, wfCallee) ← primitiveEffectProgram
  let admitted ← admitOk "effects" carrier
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"effects: initial: {repr e}"
  -- no initializer ⇒ already initialized with Bool default false
  expect initial.initialized "effects: no-init program starts initialized=true"
  expect (bytesEqual initial.canonicalValues (stateSlot (ByteArray.mk #[0])))
    "effects: default Bool false slot"
  let pre := initial
  let occ0 : EffectOccurrenceV1 := { effectId := 0, occurrence := 0 }
  let occ1 : EffectOccurrenceV1 := { effectId := 1, occurrence := 0 }
  let occ2 : EffectOccurrenceV1 := { effectId := 2, occurrence := 0 }
  let wantEffects : Array OrderedEffectV1 := #[
    { occurrence := occ0, payload := .event 0 #[] },
    { occurrence := occ1, payload := .externalCall extCallee #[] },
    { occurrence := occ2, payload := .schedule wfCallee #[] }
  ]
  let okResponses : ExternalResponsesV1 := #[
    { occurrence := occ1, disposition := .returned }
  ]
  let postTrue : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (ByteArray.mk #[1]) }
  let outOk :=
    stepReferenceSliceV1 admitted pre (inv 0 #[]) okResponses
  expectReturned "effects-returned" outOk postTrue none wantEffects

  -- external reverted (matched, exhausted) → unchanged pre, zero committed effects
  let revResponses : ExternalResponsesV1 := #[
    { occurrence := occ1, disposition := .reverted }
  ]
  let outRev :=
    stepReferenceSliceV1 admitted pre (inv 0 #[]) revResponses
  match outRev with
  | .reverted (.externalCallReverted o) st =>
      expect (occurrenceEq o occ1) "effects-ext-rev: occurrence"
      expect (logicalStateEq st pre) "effects-ext-rev: pre-state"
  | other =>
      throw <| IO.userError s!"effects-ext-rev: unexpected {repr other}"

  -- missing response
  let outMissing :=
    stepReferenceSliceV1 admitted pre (inv 0 #[]) emptyResponses
  expectTrapped "effects-missing-resp" outMissing .invalidExternalResponse pre

  -- reordered / wrong occurrence pair (emit's effectId instead of external)
  let wrongOcc : ExternalResponsesV1 := #[
    { occurrence := occ0, disposition := .returned }
  ]
  let outReorder :=
    stepReferenceSliceV1 admitted pre (inv 0 #[]) wrongOcc
  expectTrapped "effects-reordered-resp" outReorder .invalidExternalResponse pre

  -- extra trailing response after matched returned
  let extraResponses : ExternalResponsesV1 := #[
    { occurrence := occ1, disposition := .returned },
    { occurrence := { effectId := 9, occurrence := 0 }, disposition := .returned }
  ]
  let outExtra :=
    stepReferenceSliceV1 admitted pre (inv 0 #[]) extraResponses
  expectTrapped "effects-extra-resp" outExtra .invalidExternalResponse pre

  -- matched external revert + trailing extra → same invalidExternalResponse precedence
  let revPlusExtra : ExternalResponsesV1 := #[
    { occurrence := occ1, disposition := .reverted },
    { occurrence := { effectId := 9, occurrence := 0 }, disposition := .returned }
  ]
  let outRevExtra :=
    stepReferenceSliceV1 admitted pre (inv 0 #[]) revPlusExtra
  expectTrapped "effects-rev+extra" outRevExtra .invalidExternalResponse pre

/-- Declared/standard program revert with unconsumed trailing response. -/
private def testProgramRevertWithTrailingResponse : IO Unit := do
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .unit },
    { id := 1, name := none, shape := .bool }
  ]
  let errors : Array ErrorDeclV1 := #[
    { id := 0, name := "Abort", fields := #[] }
  ]
  -- declared revert only (no external call)
  let declaredEntry := mkEntry 0 "boom" #[] 0 #[] (.revert 0 #[])
  let baseD ← emptyData "DeclaredTrail"
  let dataD : SemanticProgramDataV1 := {
    baseD with
    types
    errors
    callables := #[declaredEntry]
  }
  let carrierD ← encodeCarrier "declared-trail" dataD
  let admittedD ← admitOk "declared-trail" carrierD
  let preD ← match initialLogicalStateV1 carrierD with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"declared-trail initial: {repr e}"
  let trailing : ExternalResponsesV1 := #[
    { occurrence := { effectId := 0, occurrence := 0 }, disposition := .returned }
  ]
  let outD :=
    stepReferenceSliceV1 admittedD preD (inv 0 #[]) trailing
  expectTrapped "declared+trailing" outD .invalidExternalResponse preD

  -- standard assert-false with trailing response
  let stdEntry := mkEntry 0 "assertFail" #[] 0
    #[
      instr (some { valueId := 0, typeId := 1 })
        (.literal 1 (ByteArray.mk #[0])),
      instr none (.assert_ 0 none #[])
    ]
    (.return_ none)
  let baseS ← emptyData "StandardTrail"
  let dataS : SemanticProgramDataV1 := {
    baseS with
    types
    callables := #[stdEntry]
  }
  let carrierS ← encodeCarrier "standard-trail" dataS
  let admittedS ← admitOk "standard-trail" carrierS
  let preS ← match initialLogicalStateV1 carrierS with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"standard-trail initial: {repr e}"
  let outS :=
    stepReferenceSliceV1 admittedS preS (inv 0 #[]) trailing
  expectTrapped "standard+trailing" outS .invalidExternalResponse preS

  -- clean declared revert (no trailing) still reverts declared
  let outClean :=
    stepReferenceSliceV1 admittedD preD (inv 0 #[]) emptyResponses
  expectRevertedDeclared "declared-clean" outClean 0 preD

/-- Emit then declared revert: discard overlay/effects. -/
private def testEmitThenRevertDiscardsEffects : IO Unit := do
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit }
  ]
  -- Avoid identifier `state` (Language.Syntax keyword via open ProofForgeV2).
  let stateRows : Array StateDeclV1 := #[
    { id := 0, name := "flag", typeId := 0, visibility := .public_ }
  ]
  let events : Array EventDeclV1 := #[
    { id := 0, name := "Ping", fields := #[] }
  ]
  let errors : Array ErrorDeclV1 := #[
    { id := 0, name := "Abort", fields := #[] }
  ]
  -- Avoid identifier `entry` (Language.Syntax keyword via open ProofForgeV2).
  let entryCallable := mkEntry 0 "emitThenAbort" #[] 1
    #[
      instr none (.emit 0 0 #[]),
      instr (some { valueId := 0, typeId := 0 })
        (.literal 0 (ByteArray.mk #[1])),
      instr none (.stateStore 0 0)
    ]
    (.revert 0 #[])
  let base ← emptyData "EmitThenRevert"
  let data : SemanticProgramDataV1 := {
    base with
    types
    logicalState := stateRows
    events
    errors
    callables := #[entryCallable]
  }
  let carrier ← encodeCarrier "emit-then-revert" data
  let admitted ← admitOk "emit-then-revert" carrier
  let pre ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"emit-then-revert initial: {repr e}"
  let out :=
    stepReferenceSliceV1 admitted pre (inv 0 #[]) emptyResponses
  match out with
  | .reverted (.declared 0 args) st =>
      expect args.isEmpty "emit-then-revert: empty args"
      expect (logicalStateEq st pre)
        "emit-then-revert: overlay discarded (pre-state)"
  | other =>
      throw <| IO.userError s!"emit-then-revert: unexpected {repr other}"

/-- Invalid invocation matrix + init lifecycle. -/
private unsafe def testInvalidInvocationAndInitLifecycle
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "CounterInv" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "inv" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"inv: normalize: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"inv: validate: {repr e}"
  let admitted ← admitOk "inv" carrier
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"inv initial: {repr e}"

  -- wrong callable id
  let badId :=
    stepReferenceSliceV1 admitted initial (inv 99 #[refU64 u64Tid 1]) emptyResponses
  expectTrapped "inv-bad-id" badId .invalidInvocation initial

  -- wrong kind: pureFn is not invocable via step — build a structure-gated
  -- program with pureFn + entry, then attempt pureFn callableId.
  let unitTid : TypeIdV1 := 0
  let boolTid : TypeIdV1 := 1
  let typesPK : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .unit },
    { id := 1, name := none, shape := .bool }
  ]
  let pureFn := mkPureFn 0 "helper" #[] unitTid #[] (.return_ none)
  let entryGate := mkEntry 1 "gate" #[] unitTid #[] (.return_ none)
  let basePK ← emptyData "PureKind"
  let dataPK : SemanticProgramDataV1 := {
    basePK with
    types := typesPK
    callables := #[pureFn, entryGate]
  }
  let carrierPK ← encodeCarrier "pure-kind" dataPK
  let admittedPK ← admitOk "pure-kind" carrierPK
  let prePK ← match initialLogicalStateV1 carrierPK with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"pure-kind initial: {repr e}"
  let badKind :=
    stepReferenceSliceV1 admittedPK prePK (inv 0 #[]) emptyResponses
  expectTrapped "inv-bad-kind" badKind .invalidInvocation prePK

  -- wrong arity (entry expects 1 arg)
  let afterInit :=
    stepReferenceSliceV1 admitted initial (inv 0 #[refU64 u64Tid 1]) emptyResponses
  let postInit : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 1) }
  expectReturned "inv-init" afterInit postInit none #[]
  let badArity :=
    stepReferenceSliceV1 admitted postInit (inv 1 #[]) emptyResponses
  expectTrapped "inv-bad-arity" badArity .invalidInvocation postInit

  -- wrong type (Bool bytes for UInt64 param)
  let badType :=
    stepReferenceSliceV1 admitted postInit
      (inv 1 #[{ typeId := u64Tid, valueBytes := ByteArray.mk #[1] }])
      emptyResponses
  expectTrapped "inv-bad-type-bytes" badType .invalidInvocation postInit

  -- noncanonical / wrong TypeId on arg
  let badTypeId :=
    stepReferenceSliceV1 admitted postInit
      (inv 1 #[{ typeId := 99, valueBytes := u64Bytes 1 }])
      emptyResponses
  expectTrapped "inv-bad-typeid" badTypeId .invalidInvocation postInit

  -- entry before init (uninitialized)
  let beforeInit :=
    stepReferenceSliceV1 admitted initial (inv 1 #[refU64 u64Tid 1]) emptyResponses
  expectRevertedStandard "inv-uninitialized" beforeInit .uninitialized initial

  -- entry-before-init + trailing response → invalidExternalResponse (lifecycle)
  let beforeInitTrail :=
    stepReferenceSliceV1 admitted initial (inv 1 #[refU64 u64Tid 1]) trailingResp
  expectTrapped "inv-uninit+trail" beforeInitTrail .invalidExternalResponse initial

  -- init twice
  let secondInit :=
    stepReferenceSliceV1 admitted postInit (inv 0 #[refU64 u64Tid 2]) emptyResponses
  expectRevertedStandard "inv-already-init" secondInit .alreadyInitialized postInit

  -- init-twice + trailing response → invalidExternalResponse (lifecycle)
  let secondInitTrail :=
    stepReferenceSliceV1 admitted postInit (inv 0 #[refU64 u64Tid 2]) trailingResp
  expectTrapped "inv-already+trail" secondInitTrail .invalidExternalResponse postInit

  -- invalidInvocation + trailing response stays invalidInvocation (shape gate)
  let badIdTrail :=
    stepReferenceSliceV1 admitted initial (inv 99 #[refU64 u64Tid 1]) trailingResp
  expectTrapped "inv-bad-id+trail" badIdTrail .invalidInvocation initial
  let badArityTrail :=
    stepReferenceSliceV1 admitted postInit (inv 1 #[]) trailingResp
  expectTrapped "inv-bad-arity+trail" badArityTrail .invalidInvocation postInit

  -- determinism: two identical steps yield identical post-state/value
  let a1 :=
    stepReferenceSliceV1 admitted postInit (inv 1 #[refU64 u64Tid 3]) emptyResponses
  let a2 :=
    stepReferenceSliceV1 admitted postInit (inv 1 #[refU64 u64Tid 3]) emptyResponses
  match a1, a2 with
  | .returned p1 v1 e1, .returned p2 v2 e2 =>
      expect (logicalStateEq p1 p2) "det: post-state"
      expect (optionRefEq v1 v2) "det: value"
      expect (effectsEq e1 e2) "det: effects"
  | _, _ => throw <| IO.userError "det: both steps must return"

  let _ := boolTid
  pure ()

/-- Admission fail-closed for unsupported shapes/ops (not Outcome). -/
private def testAdmissionUnsupported : IO Unit := do
  -- Int
  let typesInt : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .int 64 },
    { id := 1, name := none, shape := .unit }
  ]
  let entryInt := mkEntry 0 "e" #[] 1 #[] (.return_ none)
  let baseI ← emptyData "AdmInt"
  let dataI : SemanticProgramDataV1 := {
    baseI with types := typesInt, callables := #[entryInt]
  }
  let cI ← encodeCarrier "adm-int" dataI
  admitUnsupported "adm-int" cI
    (fun d => d.toLower.contains "int") "int"

  -- aggregate (Array)
  let typesAgg : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 2 },
    { id := 2, name := none, shape := .unit }
  ]
  let entryAgg := mkEntry 0 "e" #[] 2 #[] (.return_ none)
  let baseA ← emptyData "AdmAgg"
  let dataA : SemanticProgramDataV1 := {
    baseA with types := typesAgg, callables := #[entryAgg]
  }
  let cA ← encodeCarrier "adm-agg" dataA
  admitUnsupported "adm-agg" cA
    (fun d =>
      let l := d.toLower
      l.contains "array" || l.contains "aggregate" || l.contains "map" ||
        l.contains "option")
    "aggregate"

  -- PureCall in entry body: now admitted (pureFn kind + arity checked at
  -- admission; a wrong-kind or wrong-arity callee still fails closed).
  let typesP : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .unit }
  ]
  let pureFn := mkPureFn 0 "id" #[] 0
    #[] (.return_ none)
  let entryPC := mkEntry 1 "caller" #[] 0
    #[instr (some { valueId := 0, typeId := 0 }) (.pureCall 0 #[])]
    (.return_ (some 0))
  let baseP ← emptyData "AdmPureCall"
  let dataP : SemanticProgramDataV1 := {
    baseP with types := typesP, callables := #[pureFn, entryPC]
  }
  let cP ← encodeCarrier "adm-purecall" dataP
  match admitReferenceProgramSliceV1 cP with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError s!"adm-purecall: admission must now succeed, got {repr e}"

  -- ContextRead
  let ctxKey ← match parseSchemaId "proof-forge.context.example.v1" with
    | .ok k => pure k
    | .error e => throw <| IO.userError s!"parseSchemaId: {e}"
  let typesC : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit }
  ]
  let entryCR := mkEntry 0 "ctx" #[] 1
    #[instr (some { valueId := 0, typeId := 0 }) (.contextRead ctxKey)]
    (.return_ none)
  let baseC ← emptyData "AdmCtx"
  let dataC : SemanticProgramDataV1 := {
    baseC with types := typesC, callables := #[entryCR]
  }
  let cC ← encodeCarrier "adm-ctx" dataC
  admitUnsupported "adm-ctx" cC
    (fun d =>
      let l := d.toLower
      l.contains "contextread" || l.contains "context_read" ||
        l.contains "context read")
    "ContextRead"

  -- Commit
  let entryCm := mkEntry 0 "cm" #[] 1
    #[
      instr (some { valueId := 0, typeId := 0 })
        (.literal 0 (ByteArray.mk #[1])),
      instr (some { valueId := 1, typeId := 0 }) (.commit 0)
    ]
    (.return_ none)
  let baseCm ← emptyData "AdmCommit"
  let dataCm : SemanticProgramDataV1 := {
    baseCm with types := typesC, callables := #[entryCm]
  }
  let cCm ← encodeCarrier "adm-commit" dataCm
  admitUnsupported "adm-commit" cCm
    (fun d => d.toLower.contains "commit") "Commit"

  -- Wire-structure-valid view with stateStore rejected at admission (not Outcome).
  let typesV : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit }
  ]
  let stateRowsV : Array StateDeclV1 := #[
    { id := 0, name := "flag", typeId := 0, visibility := .public_ }
  ]
  let viewWrite := mkView 0 "dirty" #[] 1
    #[
      instr (some (vd 0 0)) (.literal 0 (ByteArray.mk #[1])),
      instr none (.stateStore 0 0)
    ]
    (.return_ none)
  let baseV ← emptyData "AdmViewStore"
  let dataV : SemanticProgramDataV1 := {
    baseV with
    types := typesV
    logicalState := stateRowsV
    callables := #[viewWrite]
  }
  let cV ← encodeCarrier "adm-view-store" dataV
  admitUnsupported "adm-view-store" cV
    (fun d =>
      let l := d.toLower
      l.contains "view" && (l.contains "statestore" || l.contains "state store" ||
        l.contains "statewrite" || l.contains "write"))
    "view stateStore"

  -- Wire-structure-valid view with Emit rejected at admission.
  let eventsV : Array EventDeclV1 := #[
    { id := 0, name := "Ping", fields := #[] }
  ]
  let viewEmit := mkView 0 "noisy" #[] 1
    #[instr none (.emit 0 0 #[])]
    (.return_ none)
  let baseVE ← emptyData "AdmViewEmit"
  let dataVE : SemanticProgramDataV1 := {
    baseVE with
    types := typesV
    events := eventsV
    callables := #[viewEmit]
  }
  let cVE ← encodeCarrier "adm-view-emit" dataVE
  admitUnsupported "adm-view-emit" cVE
    (fun d =>
      let l := d.toLower
      l.contains "view" && (l.contains "emit" || l.contains "effect"))
    "view Emit"

/-- Unit return shape: return_ none ok; return_ (some unit) → invalidCore. -/
private def testUnitReturnShape : IO Unit := do
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .unit }
  ]
  let okEntry := mkEntry 0 "unitNone" #[] 0 #[] (.return_ none)
  let baseOk ← emptyData "UnitNone"
  let dataOk : SemanticProgramDataV1 := {
    baseOk with types, callables := #[okEntry]
  }
  let carrierOk ← encodeCarrier "unit-none" dataOk
  let admittedOk ← admitOk "unit-none" carrierOk
  let preOk ← match initialLogicalStateV1 carrierOk with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"unit-none initial: {repr e}"
  expectReturned "unit-none" (stepReferenceSliceV1 admittedOk preOk (inv 0 #[]) emptyResponses)
    preOk none #[]

  let badEntry := mkEntry 0 "unitSome" #[] 0
    #[instr (some (vd 0 0)) (.literal 0 ByteArray.empty)]
    (.return_ (some 0))
  let baseBad ← emptyData "UnitSome"
  let dataBad : SemanticProgramDataV1 := {
    baseBad with types, callables := #[badEntry]
  }
  let carrierBad ← encodeCarrier "unit-some" dataBad
  -- Admitted (shape is legal Wire); runtime traps invalidCore.
  let admittedBad ← admitOk "unit-some" carrierBad
  let preBad ← match initialLogicalStateV1 carrierBad with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"unit-some initial: {repr e}"
  expectTrapped "unit-some"
    (stepReferenceSliceV1 admittedBad preBad (inv 0 #[]) emptyResponses)
    .invalidCore preBad

/-- Switch miss / Term.Trap + trailing-response override. -/
private def testSwitchTrapAndTrailing : IO Unit := do
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .unit },
    { id := 1, name := none, shape := .uint 8 }
  ]
  -- Switch: scrut=7, only case 0, no default → unreachable
  let switchEntry := mkEntryBlocks 0 "sw" #[] 0
    #[
      blk 0
        #[instr (some (vd 0 1)) (.literal 1 (ByteArray.mk #[7]))]
        (.switch 0
          #[{ typeId := 1, valueBytes := ByteArray.mk #[0],
              target := { blockId := 1, args := #[] } }]
          none),
      blk 1 #[] (.return_ none)
    ]
  let baseSw ← emptyData "SwitchMiss"
  let dataSw : SemanticProgramDataV1 := {
    baseSw with types, callables := #[switchEntry]
  }
  let carrierSw ← encodeCarrier "switch-miss" dataSw
  let admittedSw ← admitOk "switch-miss" carrierSw
  let preSw ← match initialLogicalStateV1 carrierSw with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"switch-miss initial: {repr e}"
  expectTrapped "switch-miss"
    (stepReferenceSliceV1 admittedSw preSw (inv 0 #[]) emptyResponses)
    .unreachable preSw

  -- Term.Trap clean → unreachable
  let trapEntry := mkEntry 0 "trapClean" #[] 0 #[] (.trap .unreachable)
  let baseT ← emptyData "TrapClean"
  let dataT : SemanticProgramDataV1 := {
    baseT with
    types := #[{ id := 0, name := none, shape := .unit }]
    callables := #[trapEntry]
  }
  let carrierT ← encodeCarrier "trap-clean" dataT
  let admittedT ← admitOk "trap-clean" carrierT
  let preT ← match initialLogicalStateV1 carrierT with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"trap-clean initial: {repr e}"
  expectTrapped "trap-clean"
    (stepReferenceSliceV1 admittedT preT (inv 0 #[]) emptyResponses)
    .unreachable preT

  -- Term.Trap + trailing response → invalidExternalResponse overrides
  expectTrapped "trap+trail"
    (stepReferenceSliceV1 admittedT preT (inv 0 #[]) trailingResp)
    .invalidExternalResponse preT

/-- Bounded loop: same Emit EffectId twice → occurrences (0,0)/(0,1); over-bound. -/
private def testBoundedLoopEmitOccurrences : IO Unit := do
  -- types: 0=Bool, 1=Unit, 2=UInt8 (state counter)
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit },
    { id := 2, name := none, shape := .uint 8 }
  ]
  let stateRows : Array StateDeclV1 := #[
    { id := 0, name := "n", typeId := 2, visibility := .public_ }
  ]
  let events : Array EventDeclV1 := #[
    { id := 0, name := "Tick", fields := #[] }
  ]
  -- Block 0 (header): emit EffectId 0; load; +1; store; eq 2?; branch exit / back
  -- Block 1: jump header (back edge)
  -- Block 2: return none
  -- Start state 0 → two emits, one back edge, final state 2.
  let loopBody : Array InstructionV1 := #[
    instr none (.emit 0 0 #[]),
    instr (some (vd 0 2)) (.stateLoad 0),
    instr (some (vd 1 2)) (.literal 2 (ByteArray.mk #[1])),
    instr (some (vd 2 2)) (.binary .add 0 1),
    instr none (.stateStore 0 2),
    instr (some (vd 3 2)) (.literal 2 (ByteArray.mk #[2])),
    instr (some (vd 4 0)) (.binary .eq 2 3)
  ]
  let blocksOk : Array BlockV1 := #[
    blk 0 loopBody
      (.branch 4
        { blockId := 2, args := #[] }
        { blockId := 1, args := #[] }),
    blk 1 #[] (jumpTo 0),
    blk 2 #[] (.return_ none)
  ]
  let boundsOk : Array LoopBoundV1 := #[
    { header := 0, backEdgeFrom := 1, maxIterations := 2 }
  ]
  let entryOk := mkEntryBlocks 0 "loop2" #[] 1 blocksOk boundsOk
  let baseOk ← emptyData "LoopEmit2"
  let dataOk : SemanticProgramDataV1 := {
    baseOk with
    types
    logicalState := stateRows
    events
    callables := #[entryOk]
  }
  let carrierOk ← encodeCarrier "loop-emit-2" dataOk
  let admittedOk ← admitOk "loop-emit-2" carrierOk
  let preOk ← match initialLogicalStateV1 carrierOk with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"loop-emit-2 initial: {repr e}"
  expect (bytesEqual preOk.canonicalValues (stateSlot (ByteArray.mk #[0])))
    "loop-emit-2: default UInt8 0"
  let wantEffects : Array OrderedEffectV1 := #[
    { occurrence := { effectId := 0, occurrence := 0 },
      payload := .event 0 #[] },
    { occurrence := { effectId := 0, occurrence := 1 },
      payload := .event 0 #[] }
  ]
  let postOk : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (ByteArray.mk #[2]) }
  expectReturned "loop-emit-2"
    (stepReferenceSliceV1 admittedOk preOk (inv 0 #[]) emptyResponses)
    postOk none wantEffects

  -- Over-bound: maxIterations=0 → first back edge reverts boundExceeded, no commit
  let boundsOver : Array LoopBoundV1 := #[
    { header := 0, backEdgeFrom := 1, maxIterations := 0 }
  ]
  let entryOver := mkEntryBlocks 0 "loopOver" #[] 1 blocksOk boundsOver
  let baseOver ← emptyData "LoopOver"
  let dataOver : SemanticProgramDataV1 := {
    baseOver with
    types
    logicalState := stateRows
    events
    callables := #[entryOver]
  }
  let carrierOver ← encodeCarrier "loop-over" dataOver
  let admittedOver ← admitOk "loop-over" carrierOver
  let preOver ← match initialLogicalStateV1 carrierOver with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"loop-over initial: {repr e}"
  let outOver :=
    stepReferenceSliceV1 admittedOver preOver (inv 0 #[]) emptyResponses
  expectRevertedStandard "loop-over" outOver .boundExceeded preOver
  match outOver with
  | .reverted _ st =>
      expect (logicalStateEq st preOver) "loop-over: exact pre rollback"
  | _ => pure ()

/-- Compact UInt standard-revert table: underflow / div-zero / invalid shift. -/
private def testUIntStandardReverts : IO Unit := do
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .unit },
    { id := 1, name := none, shape := .uint 8 },
    { id := 2, name := none, shape := .uint 32 }
  ]
  let runBin (name label : String) (op : BinaryOpV1)
      (lhsTid : TypeIdV1) (lhsBytes : ByteArray)
      (rhsTid : TypeIdV1) (rhsBytes : ByteArray)
      (code : StandardRevertCodeV1) : IO Unit := do
    let entryCallable := mkEntry 0 name #[] 0
      #[
        instr (some (vd 0 lhsTid)) (.literal lhsTid lhsBytes),
        instr (some (vd 1 rhsTid)) (.literal rhsTid rhsBytes),
        instr (some (vd 2 lhsTid)) (.binary op 0 1)
      ]
      (.return_ none)
    let base ← emptyData name
    let data : SemanticProgramDataV1 := {
      base with types, callables := #[entryCallable]
    }
    let carrier ← encodeCarrier label data
    let admitted ← admitOk label carrier
    let pre ← match initialLogicalStateV1 carrier with
      | .ok s => pure s
      | .error e => throw <| IO.userError s!"{label} initial: {repr e}"
    expectRevertedStandard label
      (stepReferenceSliceV1 admitted pre (inv 0 #[]) emptyResponses)
      code pre

  -- UInt8 0 - 1 → underflow
  runBin "UintUnderflow" "uint-underflow" .sub
    1 (ByteArray.mk #[0]) 1 (ByteArray.mk #[1]) .arithmeticUnderflow
  -- UInt8 1 / 0 → divisionByZero
  runBin "UintDiv0" "uint-div0" .div
    1 (ByteArray.mk #[1]) 1 (ByteArray.mk #[0]) .divisionByZero
  -- UInt8 1 << 8 (rhs UInt32) → invalidShift (shift ≥ width)
  runBin "UintBadShift" "uint-badshift" .shl
    1 (ByteArray.mk #[1]) 2 (leBytesFromNat 8 4) .invalidShift

/-- Suite entry (engineering only — not formal TST-SEM). -/
unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testCounterReferenceSlice session
  testGuardedCounterReferenceSlice session
  testBoolResultReferenceSlice session
  testIfMatchReferenceSlice session
  testEmitRevertReferenceSlice session
  testFnLocalCallReferenceSlice session
  testArithUnaryReferenceSlice session
  testPrimitiveEffectLogAndResponses
  testProgramRevertWithTrailingResponse
  testEmitThenRevertDiscardsEffects
  testInvalidInvocationAndInitLifecycle session
  testAdmissionUnsupported
  testUnitReturnShape
  testSwitchTrapAndTrailing
  testBoundedLoopEmitOccurrences
  testUIntStandardReverts
  IO.println "Tests.Semantic.ReferenceV1: engineering suite finished"

end Tests.Semantic.ReferenceV1
