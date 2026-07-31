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
    5. Admission fail-closed on view stateStore / view Emit (errors separated
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
   11. Invariant reference slice: carried metadata fuel, canonical Bool true/false,
       transitive PureCall, revert/trap mapping, and fail-closed state/ordinal;
       normal Invocation remains invalid.
   13. Struct canonical codec seam plus Construct/FieldGet/FieldSet in entry,
       nested immutable update, PureCall, and invariant-root execution.
   14. ContextRead exact selected-root/PureCall-closure invocation gate and
       immutable shared snapshot execution.
   15. Commit exact requirement admission and target-neutral identity execution
       across roots/PureCall, including aggregate bytes and repeated Commit.
   16. Lower invariant runner bypasses narrower whole-program engineering
       admission while preserving exact carried fuel and result mapping.
   17. Unit Construct and canonical/type revalidation at machine value,
       PureCall, CFG, and return boundaries; Principal canonical equality.
   18. Complete fixed-width UInt/Int lower runner: all legal widths and
       canonical boundaries, arithmetic/bitwise/shift semantics, and all four
       CheckedCast families (including UInt256/Int256), with exact reverts.
   19. BN254 Field lower runner: canonical boundaries, modular arithmetic,
       inverse/division, Eq/Ne, exact division-by-zero, whole-program admission,
       and selected-invariant independence from unrelated Principal support.

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

private def exceptIsError (result : Except ε α) : Bool :=
  match result with
  | .error _ => true
  | .ok _ => false

private def expectSemanticError (label : String) (expected : SemanticWireErrorV1)
    (result : Except SemanticWireErrorV1 α) : IO Unit := do
  match result with
  | .error actual =>
      expect (actual == expected)
        s!"{label}: expected {repr expected}, got {repr actual}"
  | .ok _ => throw <| IO.userError s!"{label}: expected error, got ok"

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

private def beBytesToNat (bytes : ByteArray) : Nat := Id.run do
  let mut out := 0
  for byte in bytes do
    out := out * 256 + byte.toNat
  pure out

private def u64Bytes (n : Nat) : ByteArray := leBytesFromNat n 8

private def stateSlot (valueBytes : ByteArray) : ByteArray :=
  (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes

private def refU64 (typeId : TypeIdV1) (n : Nat) : ReferenceValueV1 :=
  { typeId, valueBytes := u64Bytes n }

private def refBool (typeId : TypeIdV1) (b : Nat) : ReferenceValueV1 :=
  { typeId, valueBytes := ByteArray.mk #[b.toUInt8] }

private def emptyContext : Array ContextInputV1 := #[]

private def emptyResponses : ExternalResponsesV1 := #[]

private def inv (callableId : CallableIdV1) (args : Array ReferenceValueV1) :
    InvocationV1 :=
  { callableId, args, context := emptyContext }

private def invWithContext (callableId : CallableIdV1)
    (args : Array ReferenceValueV1) (context : Array ContextInputV1) : InvocationV1 :=
  { callableId, args, context }

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

/-- Bounded for loops and immutable lets on the admitted reference machine:
    sum accumulation, zero-trip, exact boundExceeded semantics (the back edge
    after the (N+1)-th body execution reverts), and let single-evaluation. -/
private unsafe def testLetForReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "LoopRef" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry addUp(n : UInt64) : UInt64 do\n" ++
    "    let limit : UInt64 := n + 4\n" ++
    "    for i in n ..< limit bounded 8 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  entry scan(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n bounded 2 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n" ++
    "  entry addUpTight(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n + 4 bounded 3 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  entry never(n : UInt64) : UInt64 do\n" ++
    "    let one : UInt64 := 1\n" ++
    "    for i in one ..< n bounded 0 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  entry square(dummy : UInt64) : UInt64 do\n" ++
    "    let x : UInt64 := count + 1\n" ++
    "    count := x * x\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "loop-ref" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"loop-ref: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"loop-ref: validate failed: {repr e}"
  let admitted ← admitOk "loop-ref" carrier
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let initId : CallableIdV1 := 0
  let addUpId : CallableIdV1 := 1
  let scanId : CallableIdV1 := 2
  let tightId : CallableIdV1 := 3
  let neverId : CallableIdV1 := 4
  let squareId : CallableIdV1 := 5
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"loop-ref: initialLogicalState: {repr e}"
  let initPost :=
    stepReferenceSliceV1 admitted initial (inv initId #[refU64 u64Tid 0]) emptyResponses
  let zeroState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 0) }
  expectReturned "loop-ref-init" initPost zeroState none #[]
  -- addUp(1): limit = 5, i ∈ {1,2,3,4} → count = 10.
  let added :=
    stepReferenceSliceV1 admitted zeroState (inv addUpId #[refU64 u64Tid 1]) emptyResponses
  let tenState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 10) }
  expectReturned "loop-ref-addUp" added tenState (some (refU64 u64Tid 10)) #[]
  -- addUp(6): limit = 10, i ∈ {6,7,8,9} → count = 10 + 30 = 40.
  let added2 :=
    stepReferenceSliceV1 admitted tenState (inv addUpId #[refU64 u64Tid 6]) emptyResponses
  let fortyState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 40) }
  expectReturned "loop-ref-addUp2" added2 fortyState (some (refU64 u64Tid 40)) #[]
  -- scan(7): start == end → zero iterations, state and result unchanged.
  let scanned :=
    stepReferenceSliceV1 admitted fortyState (inv scanId #[refU64 u64Tid 7]) emptyResponses
  expectReturned "loop-ref-scan" scanned fortyState (some (refU64 u64Tid 40)) #[]
  -- addUpTight(1): four iterations exceed bound 3; the back edge after the
  -- fourth body execution reverts boundExceeded with the pre-state kept.
  let tight :=
    stepReferenceSliceV1 admitted fortyState (inv tightId #[refU64 u64Tid 1]) emptyResponses
  match tight with
  | .reverted (.standard code) st =>
      expect (code == .boundExceeded) s!"loop-ref-tight: code, got {repr code}"
      expect (logicalStateEq st fortyState) "loop-ref-tight: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"loop-ref-tight: expected standard revert, got {repr other}"
  -- never(2): bound 0 rejects the first back edge; never(1) is a zero-trip.
  let never2 :=
    stepReferenceSliceV1 admitted fortyState (inv neverId #[refU64 u64Tid 2]) emptyResponses
  match never2 with
  | .reverted (.standard code) st =>
      expect (code == .boundExceeded) s!"loop-ref-never2: code, got {repr code}"
      expect (logicalStateEq st fortyState) "loop-ref-never2: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"loop-ref-never2: expected standard revert, got {repr other}"
  let never1 :=
    stepReferenceSliceV1 admitted fortyState (inv neverId #[refU64 u64Tid 1]) emptyResponses
  expectReturned "loop-ref-never1" never1 fortyState (some (refU64 u64Tid 40)) #[]
  -- square: let x = count + 1 evaluated once → count = 41 * 41 = 1681.
  let squared :=
    stepReferenceSliceV1 admitted fortyState (inv squareId #[refU64 u64Tid 0]) emptyResponses
  let squareState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 1681) }
  expectReturned "loop-ref-square" squared squareState (some (refU64 u64Tid 1681)) #[]

/-- Shift, bitwise, and strict logical binaries on the admitted reference
    machine: shift results and guards (shl overflow, invalidShift for counts
    ≥ 64), bitwise masks, and the strict logical-or truth table (both sides
    always evaluate, including a failing division). -/
private unsafe def testShiftBitwiseLogicalReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "BitRef" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry shiftMask(x : UInt64) : UInt64 do\n" ++
    "    count := (x << 2) & 15 | (x >> 1) ^ 3\n" ++
    "    return count\n" ++
    "  entry shl2(x : UInt64) : UInt64 do\n" ++
    "    return x << 2\n" ++
    "  entry shrK(x : UInt64) : UInt64 do\n" ++
    "    return x >> (32 + 32)\n" ++
    "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
    "    return a > 0 && b > 0\n" ++
    "  entry strictOr(a : UInt64, b : UInt64) : Bool do\n" ++
    "    let one : UInt64 := 1\n" ++
    "    return a > 0 || (one / b) == one\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "bit-ref" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"bit-ref: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"bit-ref: validate failed: {repr e}"
  let admitted ← admitOk "bit-ref" carrier
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
  let initId : CallableIdV1 := 0
  let shiftMaskId : CallableIdV1 := 1
  let shl2Id : CallableIdV1 := 2
  let shrKId : CallableIdV1 := 3
  let bothId : CallableIdV1 := 4
  let strictOrId : CallableIdV1 := 5
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"bit-ref: initialLogicalState: {repr e}"
  let initPost :=
    stepReferenceSliceV1 admitted initial (inv initId #[refU64 u64Tid 0]) emptyResponses
  let zeroState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 0) }
  expectReturned "bit-ref-init" initPost zeroState none #[]
  -- shiftMask(20): (20<<2)&15 = 0; (20>>1)^3 = 9; 0|9 = 9.
  let masked :=
    stepReferenceSliceV1 admitted zeroState (inv shiftMaskId #[refU64 u64Tid 20]) emptyResponses
  let nineState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 9) }
  expectReturned "bit-ref-shiftMask" masked nineState (some (refU64 u64Tid 9)) #[]
  -- shl2(2^63): 2^65 exceeds UInt64 → arithmeticOverflow.
  let shlOverflow :=
    stepReferenceSliceV1 admitted nineState
      (inv shl2Id #[refU64 u64Tid 9223372036854775808]) emptyResponses
  match shlOverflow with
  | .reverted (.standard code) st =>
      expect (code == .arithmeticOverflow) s!"bit-ref-shlovf: code, got {repr code}"
      expect (logicalStateEq st nineState) "bit-ref-shlovf: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"bit-ref-shlovf: expected standard revert, got {repr other}"
  -- shrK(7): the computed count 32 + 32 = 64 ≥ 64 → invalidShift.
  let badShift :=
    stepReferenceSliceV1 admitted nineState (inv shrKId #[refU64 u64Tid 7]) emptyResponses
  match badShift with
  | .reverted (.standard code) st =>
      expect (code == .invalidShift) s!"bit-ref-shrK: code, got {repr code}"
      expect (logicalStateEq st nineState) "bit-ref-shrK: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"bit-ref-shrK: expected standard revert, got {repr other}"
  -- both(1,2) = true; both(0,2) = false.
  let bothTrue :=
    stepReferenceSliceV1 admitted nineState (inv bothId #[refU64 u64Tid 1, refU64 u64Tid 2]) emptyResponses
  expectReturned "bit-ref-both-t" bothTrue nineState (some (refBool boolTid 1)) #[]
  let bothFalse :=
    stepReferenceSliceV1 admitted nineState (inv bothId #[refU64 u64Tid 0, refU64 u64Tid 2]) emptyResponses
  expectReturned "bit-ref-both-f" bothFalse nineState (some (refBool boolTid 0)) #[]
  -- strictOr(0,1) = true; strictOr(0,2) = false; strictOr(1,0) reverts even
  -- though the left side is true (no short-circuit).
  let orTrue :=
    stepReferenceSliceV1 admitted nineState (inv strictOrId #[refU64 u64Tid 0, refU64 u64Tid 1]) emptyResponses
  expectReturned "bit-ref-or-t" orTrue nineState (some (refBool boolTid 1)) #[]
  let orFalse :=
    stepReferenceSliceV1 admitted nineState (inv strictOrId #[refU64 u64Tid 0, refU64 u64Tid 2]) emptyResponses
  expectReturned "bit-ref-or-f" orFalse nineState (some (refBool boolTid 0)) #[]
  let orStrict :=
    stepReferenceSliceV1 admitted nineState (inv strictOrId #[refU64 u64Tid 1, refU64 u64Tid 0]) emptyResponses
  match orStrict with
  | .reverted (.standard code) st =>
      expect (code == .divisionByZero) s!"bit-ref-strict: code, got {repr code}"
      expect (logicalStateEq st nineState) "bit-ref-strict: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"bit-ref-strict: expected standard revert, got {repr other}"

/-- External call/schedule through the source pipeline into the admitted
    machine: shared EffectId occurrences, returned responses continue,
    reverted responses revert with the exact occurrence, and trailing or
    missing responses trap invalidExternalResponse. -/
private unsafe def testCallScheduleReferenceSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ExtRef" <|
    "  state count : UInt64\n" ++
    "  event Ping(x : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Ping(count)\n" ++
    "    call Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  entry later(delta : UInt64) : UInt64 do\n" ++
    "    schedule Ledger.daily(count)\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let validated ← loadSource session "ext-ref" source
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"ext-ref: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"ext-ref: validate failed: {repr e}"
  let admitted ← admitOk "ext-ref" carrier
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let initId : CallableIdV1 := 0
  let bumpId : CallableIdV1 := 1
  let laterId : CallableIdV1 := 2
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"ext-ref: initialLogicalState: {repr e}"
  let initPost :=
    stepReferenceSliceV1 admitted initial (inv initId #[refU64 u64Tid 0]) emptyResponses
  let zeroState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 0) }
  expectReturned "ext-ref-init" initPost zeroState none #[]
  let occEmit : EffectOccurrenceV1 := { effectId := 0, occurrence := 0 }
  let occCall : EffectOccurrenceV1 := { effectId := 1, occurrence := 0 }
  let occSched : EffectOccurrenceV1 := { effectId := 0, occurrence := 0 }
  -- Returned response: emit + call effects commit in order, count = 5.
  let okResponses : ExternalResponsesV1 := #[
    { occurrence := occCall, disposition := .returned }
  ]
  let okOut :=
    stepReferenceSliceV1 admitted zeroState (inv bumpId #[refU64 u64Tid 5]) okResponses
  let fiveState : LogicalStateV1 :=
    { initialized := true, canonicalValues := stateSlot (u64Bytes 5) }
  let okEffects : Array OrderedEffectV1 := #[
    { occurrence := occEmit, payload := .event 0 #[refU64 u64Tid 0] },
    { occurrence := occCall,
      payload := .externalCall
        (← qn2 "Oracle" "feed")
        #[refU64 u64Tid 0] }
  ]
  expectReturned "ext-ref-returned" okOut fiveState (some (refU64 u64Tid 5)) okEffects
  -- Reverted response: externalCallReverted with the exact occurrence, pre kept.
  let revResponses : ExternalResponsesV1 := #[
    { occurrence := occCall, disposition := .reverted }
  ]
  let revOut :=
    stepReferenceSliceV1 admitted zeroState (inv bumpId #[refU64 u64Tid 5]) revResponses
  match revOut with
  | .reverted (.externalCallReverted o) st =>
      expect (occurrenceEq o occCall) s!"ext-ref-reverted: occurrence"
      expect (logicalStateEq st zeroState) "ext-ref-reverted: revert must keep pre-state"
  | other =>
      throw <| IO.userError s!"ext-ref-reverted: expected external revert, got {repr other}"
  -- Missing response for the call: invalidExternalResponse.
  let missingOut :=
    stepReferenceSliceV1 admitted zeroState (inv bumpId #[refU64 u64Tid 5]) emptyResponses
  expectTrapped "ext-ref-missing" missingOut .invalidExternalResponse zeroState
  -- Trailing unconsumed response after a matched call: same trap.
  let extraResponses : ExternalResponsesV1 := #[
    { occurrence := occCall, disposition := .returned },
    { occurrence := { effectId := 9, occurrence := 0 }, disposition := .returned }
  ]
  let extraOut :=
    stepReferenceSliceV1 admitted zeroState (inv bumpId #[refU64 u64Tid 5]) extraResponses
  expectTrapped "ext-ref-extra" extraOut .invalidExternalResponse zeroState
  -- Schedule consumes no response at all (fire-and-forget): it commits its
  -- effect occurrence and the caller continues. Any provided response would
  -- trail unconsumed into the exhaustion trap.
  let schedOut :=
    stepReferenceSliceV1 admitted fiveState (inv laterId #[refU64 u64Tid 2]) emptyResponses
  let schedEffects : Array OrderedEffectV1 := #[
    { occurrence := occSched,
      payload := .schedule
        (← qn2 "Ledger" "daily")
        #[refU64 u64Tid 5] }
  ]
  expectReturned "ext-ref-schedule" schedOut fiveState (some (refU64 u64Tid 5)) schedEffects

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

/-- Admission fail-closed for unsupported shapes/ops (not Outcome), plus the
    now-admitted Commit boundary. -/
private def testAdmissionUnsupported : IO Unit := do
  -- Map declarations are admitted when their conservative theoretical shape
  -- fits the Wire byte/work limits.
  let typesAgg : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .map 0 0 },
    { id := 2, name := none, shape := .unit }
  ]
  let entryAgg := mkEntry 0 "e" #[] 2 #[] (.return_ none)
  let baseA ← emptyData "AdmAgg"
  let dataA : SemanticProgramDataV1 := {
    baseA with types := typesAgg, callables := #[entryAgg]
  }
  let cA ← encodeCarrier "adm-agg" dataA
  let _ ← admitOk "adm-agg" cA

  -- PureCall in entry body: now admitted (pureFn kind + arity checked at
  -- admission; a wrong-kind or wrong-arity callee still fails closed).
  let typesP : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .unit }
  ]
  let pureFn := mkPureFn 0 "id" #[] 0
    #[] (.return_ none)
  let entryPC := mkEntry 1 "caller" #[] 0
    #[instr (some { valueId := 0, typeId := 0 }) (.pureCall 0 #[])]
    (.return_ none)
  let baseP ← emptyData "AdmPureCall"
  let dataP : SemanticProgramDataV1 := {
    baseP with types := typesP, callables := #[pureFn, entryPC]
  }
  let cP ← encodeCarrier "adm-purecall" dataP
  let admittedP ← match admitReferenceProgramSliceV1 cP with
    | .ok admitted => pure admitted
    | .error e =>
      throw <| IO.userError s!"adm-purecall: admission must now succeed, got {repr e}"
  let preP ← match initialLogicalStateV1 cP with
    | .ok initial => pure initial
    | .error e => throw <| IO.userError s!"adm-purecall initial state: {repr e}"
  expectReturned "unit-purecall-execution"
    (stepReferenceSliceV1 admittedP preP (inv 1 #[]) #[]) preP none #[]

  -- The root initializer flag survives a PureCall frame and is published on
  -- successful return.
  let initPC := mkInit 0 #[] 0
    #[instr (some { valueId := 0, typeId := 0 }) (.pureCall 1 #[])]
    (.return_ none)
  let initPureFn := mkPureFn 1 "initHelper" #[] 0 #[] (.return_ none)
  let postInitEntry := mkEntry 2 "postInit" #[] 0 #[] (.return_ none)
  let initBase ← emptyData "InitPureCall"
  let initCarrier ← encodeCarrier "init-purecall" {
    initBase with types := typesP, callables := #[initPC, initPureFn, postInitEntry]
  }
  let initAdmitted ← admitOk "init-purecall" initCarrier
  let preInitPC ← match initialLogicalStateV1 initCarrier with
    | .ok initial => pure initial
    | .error e => throw <| IO.userError s!"init-purecall initial state: {repr e}"
  expectReturned "init-purecall"
    (stepReferenceSliceV1 initAdmitted preInitPC (inv 0 #[]) #[])
    { preInitPC with initialized := true } none #[]

  -- Commit is admitted and preserves the operand's exact type/bytes without
  -- state or effects.
  let typesCm : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit }
  ]
  let entryCm := mkEntry 0 "cm" #[] 0
    #[
      instr (some { valueId := 0, typeId := 0 })
        (.literal 0 (ByteArray.mk #[1])),
      instr (some { valueId := 1, typeId := 0 }) (.commit 0)
    ]
    (.return_ (some 1))
  let baseCm ← emptyData "AdmCommit"
  let commitRequirement ← match commitmentDisclosureRequirementV1 with
    | .ok row => pure row
    | .error e => throw <| IO.userError s!"Commit requirement: {e}"
  let dataCm : SemanticProgramDataV1 := {
    baseCm with
      types := typesCm
      callables := #[entryCm]
      requirements := { items := #[commitRequirement] }
  }
  let cCm ← encodeCarrier "adm-commit" dataCm
  let admittedCm ← admitOk "adm-commit" cCm
  let preCm ← match initialLogicalStateV1 cCm with
    | .ok initial => pure initial
    | .error e => throw <| IO.userError s!"adm-commit initial state: {repr e}"
  expectReturned "commit-bool-identity"
    (stepReferenceSliceV1 admittedCm preCm (inv 0 #[]) emptyResponses)
    preCm (some (refBool 0 1)) #[]

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

/-- ContextRead uses the exact selected-root PureCall closure and one immutable
    invocation snapshot; malformed context fails before lifecycle/responses. -/
private def testContextReadReferenceSlice : IO Unit := do
  let key := unixTimeSecondsContextKeyV1
  let requirement ← match unixTimeSecondsContextRequirementV1 with
    | .ok row => pure row
    | .error e => throw <| IO.userError s!"context-read requirement: {e}"
  let commitRequirement ← match commitmentDisclosureRequirementV1 with
    | .ok row => pure row
    | .error e => throw <| IO.userError s!"Commit requirement: {e}"
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .uint 64 },
    { id := 1, name := none, shape := .unit }
  ]
  let leaf := mkPureFn 0 "readClock" #[] 0
    #[instr (some (vd 0 0)) (.contextRead key),
      instr (some (vd 1 0)) (.commit 0),
      instr (some (vd 2 0)) (.commit 1)]
    (.return_ (some 2))
  let nested := mkPureFn 1 "nestedClock" #[] 0
    #[instr (some (vd 0 0)) (.pureCall 0 #[])]
    (.return_ (some 0))
  let initializer := mkInit 2 #[] 1
    #[instr (some (vd 0 0)) (.contextRead key),
      instr (some (vd 1 0)) (.commit 0)]
    (.return_ none)
  let direct := mkEntry 3 "directClock" #[] 0
    #[instr (some (vd 0 0)) (.contextRead key)]
    (.return_ (some 0))
  let throughNested := mkView 4 "nestedView" #[] 0
    #[instr (some (vd 0 0)) (.pureCall 1 #[])]
    (.return_ (some 0))
  let noContext := mkEntry 5 "noContext" #[] 1 #[] (.return_ none)
  let repeated := mkEntry 6 "repeatedClock" #[] 0
    #[instr (some (vd 0 0)) (.contextRead key),
      instr (some (vd 1 0)) (.contextRead key)]
    (.return_ (some 1))
  let base ← emptyData "ContextReadRuntime"
  let data : SemanticProgramDataV1 := {
    base with
      types
      callables := #[leaf, nested, initializer, direct, throughNested, noContext, repeated]
      requirements := { items := #[requirement, commitRequirement] }
  }
  let carrier ← encodeCarrier "context-read-runtime" data
  let admitted ← admitOk "context-read-runtime" carrier
  let initial ← match initialLogicalStateV1 carrier with
    | .ok st => pure st
    | .error e => throw <| IO.userError s!"context-read initial state: {repr e}"
  let value := refU64 0 1700000000
  let context : Array ContextInputV1 := #[{ key, value }]

  -- Missing initializer context is invalid invocation even with a response;
  -- a valid initializer read still publishes the initialized lifecycle bit.
  expectTrapped "context-init-missing+response"
    (stepReferenceSliceV1 admitted initial (inv 2 #[]) trailingResp)
    .invalidInvocation initial
  let initialized : LogicalStateV1 := { initial with initialized := true }
  expectReturned "context-init"
    (stepReferenceSliceV1 admitted initial (invWithContext 2 #[] context) emptyResponses)
    initialized none #[]

  expectReturned "context-entry-direct"
    (stepReferenceSliceV1 admitted initialized (invWithContext 3 #[] context) emptyResponses)
    initialized (some value) #[]
  expectReturned "context-view-nested-purecall"
    (stepReferenceSliceV1 admitted initialized (invWithContext 4 #[] context) emptyResponses)
    initialized (some value) #[]
  expectReturned "context-repeated-snapshot"
    (stepReferenceSliceV1 admitted initialized (invWithContext 6 #[] context) emptyResponses)
    initialized (some value) #[]

  -- Required keys are selected-root scoped, not program-wide.
  expectReturned "context-unreachable-not-required"
    (stepReferenceSliceV1 admitted initialized (inv 5 #[]) emptyResponses)
    initialized none #[]
  expectTrapped "context-extra-for-empty-root"
    (stepReferenceSliceV1 admitted initialized (invWithContext 5 #[] context) emptyResponses)
    .invalidInvocation initialized

  expectTrapped "context-required-missing"
    (stepReferenceSliceV1 admitted initialized (inv 3 #[]) emptyResponses)
    .invalidInvocation initialized
  expectTrapped "context-required-missing+response"
    (stepReferenceSliceV1 admitted initialized (inv 3 #[]) trailingResp)
    .invalidInvocation initialized
  expectTrapped "context-duplicate"
    (stepReferenceSliceV1 admitted initialized
      (invWithContext 3 #[] #[{ key, value }, { key, value }]) emptyResponses)
    .invalidInvocation initialized
  expectTrapped "context-wrong-type"
    (stepReferenceSliceV1 admitted initialized
      (invWithContext 3 #[] #[{ key, value := { typeId := 1, valueBytes := ByteArray.empty } }])
      emptyResponses)
    .invalidInvocation initialized
  expectTrapped "context-noncanonical-value"
    (stepReferenceSliceV1 admitted initialized
      (invWithContext 3 #[] #[{ key, value := { typeId := 0, valueBytes := ByteArray.mk #[1] } }])
      emptyResponses)
    .invalidInvocation initialized
  let later : SchemaId := { value := "proof-forge.context.z.v1" }
  let earlier : SchemaId := { value := "proof-forge.context.a.v1" }
  expectTrapped "context-nonascending-extra"
    (stepReferenceSliceV1 admitted initialized
      (invWithContext 5 #[] #[{ key := later, value }, { key := earlier, value }])
      emptyResponses)
    .invalidInvocation initialized

  -- Once context shape is valid, lifecycle candidates retain the established
  -- trailing-response precedence.
  expectTrapped "context-init-twice+response"
    (stepReferenceSliceV1 admitted initialized
      (invWithContext 2 #[] context) trailingResp)
    .invalidExternalResponse initialized

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

/-- Struct canonical bytes and reference execution, including nested immutable
    update, PureCall reuse, and invariant-root reuse of the same machine. -/
private def testStructReferenceSlice : IO Unit := do
  let pairFields : Array StructFieldV1 := #[
    { name := "flag", typeId := 2 },
    { name := "number", typeId := 3 }
  ]
  let outerFields : Array StructFieldV1 := #[
    { name := "inner", typeId := 0 },
    { name := "tail", typeId := 3 }
  ]
  -- Named Struct declarations occupy the required contiguous prefix.
  let types : Array TypeDeclV1 := #[
    { id := 0, name := some "Pair", shape := .struct pairFields },
    { id := 1, name := some "Outer", shape := .struct outerFields },
    { id := 2, name := none, shape := .bool },
    { id := 3, name := none, shape := .uint 8 },
    { id := 4, name := none, shape := .unit }
  ]

  -- The public Wire seam uses the sole canonical recursive decoder.
  let pairBytes := ByteArray.mk #[1, 7]
  match splitCanonicalStructValueV1 types 0 pairBytes with
  | .ok chunks =>
      expect (chunks.size == 2) "struct codec: exact field count"
      expect (bytesEqual chunks[0]! (ByteArray.mk #[1]))
        "struct codec: first field"
      expect (bytesEqual chunks[1]! (ByteArray.mk #[7]))
        "struct codec: later field"
  | .error e => throw <| IO.userError s!"struct codec split failed: {repr e}"
  match encodeCanonicalStructValueV1 types 0
      #[ByteArray.mk #[1], ByteArray.mk #[7]] with
  | .ok bytes => expect (bytesEqual bytes pairBytes) "struct codec: re-encode"
  | .error e => throw <| IO.userError s!"struct codec encode failed: {repr e}"
  expect (exceptIsError
    (splitCanonicalStructValueV1 types 0 (ByteArray.mk #[1])))
    "struct codec: truncated value fails closed"
  expect (exceptIsError
    (splitCanonicalStructValueV1 types 0 (ByteArray.mk #[2, 7])))
    "struct codec: noncanonical field fails closed"
  expect (exceptIsError
    (splitCanonicalStructValueV1 types 0 (ByteArray.mk #[1, 7, 0])))
    "struct codec: trailing bytes fail closed"
  expect (exceptIsError
    (encodeCanonicalStructValueV1 types 0 #[ByteArray.mk #[1]]))
    "struct codec: wrong field count fails closed"
  expect (exceptIsError (encodeCanonicalStructValueV1 types 0
    #[ByteArray.mk #[2], ByteArray.mk #[7]]))
    "struct codec: wrong field value fails closed"
  expect (exceptIsError
    (splitCanonicalStructValueV1 types 3 (ByteArray.mk #[7])))
    "struct codec: non-Struct type fails closed"

  -- Exact nesting parity: 255 outer Struct levels plus a Bool leaf consume
  -- maxNesting=256; one additional Struct must fail in both split and encode.
  let nestedTypes (structCount : Nat) : Array TypeDeclV1 := Id.run do
    let mut out : Array TypeDeclV1 := #[]
    for i in [:structCount] do
      out := out.push {
        id := UInt32.ofNat i
        name := some s!"Nest{i}"
        shape := .struct #[{ name := "next", typeId := UInt32.ofNat (i + 1) }]
      }
    out := out.push {
      id := UInt32.ofNat structCount, name := none, shape := .bool
    }
    pure out
  let depth256 := nestedTypes 255
  match encodeCanonicalStructValueV1 depth256 0 #[ByteArray.mk #[1]] with
  | .ok bytes => do
      expect (bytesEqual bytes (ByteArray.mk #[1]))
        "struct codec: exact max nesting encodes"
  | .error e => throw <| IO.userError s!"struct max nesting: {repr e}"
  let depth257 := nestedTypes 256
  expectSemanticError "struct codec nesting encode" .limitExceeded
    (encodeCanonicalStructValueV1 depth257 0 #[ByteArray.mk #[1]])
  expectSemanticError "struct codec nesting split" .limitExceeded
    (splitCanonicalStructValueV1 depth257 0 (ByteArray.mk #[1]))

  -- Entry path pins first/later get, old-value preservation after FieldSet,
  -- and nested Struct get/set. Assertions make all intermediate observations
  -- semantically observable rather than only checking the final return.
  let structEntry := mkEntry 0 "structOps" #[] 3 #[
    instr (some (vd 0 2)) (.literal 2 (ByteArray.mk #[1])),
    instr (some (vd 1 3)) (.literal 3 (ByteArray.mk #[7])),
    instr (some (vd 2 0)) (.construct 0 0 #[0, 1]),
    instr (some (vd 3 2)) (.fieldGet 2 0),
    instr none (.assert_ 3 none #[]),
    instr (some (vd 4 3)) (.fieldGet 2 1),
    instr (some (vd 5 2)) (.binary .eq 4 1),
    instr none (.assert_ 5 none #[]),
    instr (some (vd 6 3)) (.literal 3 (ByteArray.mk #[9])),
    instr (some (vd 7 0)) (.fieldSet 2 1 6),
    instr (some (vd 8 3)) (.fieldGet 2 1),
    instr (some (vd 9 2)) (.binary .eq 8 1),
    instr none (.assert_ 9 none #[]),
    instr (some (vd 10 3)) (.fieldGet 7 1),
    instr (some (vd 11 2)) (.binary .eq 10 6),
    instr none (.assert_ 11 none #[]),
    instr (some (vd 12 1)) (.construct 1 0 #[2, 6]),
    instr (some (vd 13 0)) (.fieldGet 12 0),
    instr (some (vd 14 0)) (.fieldSet 13 1 6),
    instr (some (vd 15 1)) (.fieldSet 12 0 14),
    instr (some (vd 16 0)) (.fieldGet 15 0),
    instr (some (vd 17 3)) (.fieldGet 16 1)
  ] (.return_ (some 17))
  let base ← emptyData "StructOps"
  let carrier ← encodeCarrier "struct-ops" {
    base with types, callables := #[structEntry]
  }
  let admitted ← admitOk "struct-ops" carrier
  let pre : LogicalStateV1 := { initialized := true, canonicalValues := ByteArray.empty }
  expectReturned "struct-ops"
    (stepReferenceSliceV1 admitted pre (inv 0 #[]) #[])
    pre (some { typeId := 3, valueBytes := ByteArray.mk #[9] }) #[]

  -- Struct construction inside a pureFn, consumed by an entry caller.
  let flagParam : ParameterV1 :=
    { valueId := 0, name := "flag", typeId := 2, visibility := .public_ }
  let numberParam : ParameterV1 :=
    { valueId := 1, name := "number", typeId := 3, visibility := .public_ }
  let makePair := mkPureFn 0 "makePair" #[flagParam, numberParam] 0
    #[instr (some (vd 2 0)) (.construct 0 0 #[0, 1])]
    (.return_ (some 2))
  let pureCaller := mkEntry 1 "pureStruct" #[] 3 #[
    instr (some (vd 0 2)) (.literal 2 (ByteArray.mk #[1])),
    instr (some (vd 1 3)) (.literal 3 (ByteArray.mk #[11])),
    instr (some (vd 2 0)) (.pureCall 0 #[0, 1]),
    instr (some (vd 3 3)) (.fieldGet 2 1)
  ] (.return_ (some 3))
  let pureBase ← emptyData "PureStruct"
  let pureCarrier ← encodeCarrier "pure-struct" {
    pureBase with types, callables := #[makePair, pureCaller]
  }
  let pureAdmitted ← admitOk "pure-struct" pureCarrier
  expectReturned "pure-struct"
    (stepReferenceSliceV1 pureAdmitted pre (inv 1 #[]) #[])
    pre (some { typeId := 3, valueBytes := ByteArray.mk #[11] }) #[]

  -- The same Struct operations execute in an invariant root. Exact fuel is
  -- frame entry + four instructions + return terminator = 6.
  let gate := mkEntry 0 "gate" #[] 4 #[] (.return_ none)
  let structInvariant : CallableV1 := {
    id := 1, kind := .invariant, name := some "structInvariant", params := #[]
    result := { typeId := 2, visibility := .public_ }
    entryBlock := 0
    blocks := #[blk 0 #[
      instr (some (vd 0 2)) (.literal 2 (ByteArray.mk #[1])),
      instr (some (vd 1 3)) (.literal 3 (ByteArray.mk #[5])),
      instr (some (vd 2 0)) (.construct 0 0 #[0, 1]),
      instr (some (vd 3 2)) (.fieldGet 2 0)
    ] (.return_ (some 3))]
    loopBounds := #[]
    invariantSteps := some 6
  }
  let invBase ← emptyData "StructInvariant"
  let invCarrier ← encodeCarrier "struct-invariant" {
    invBase with
    types
    callables := #[gate, structInvariant]
    invariants := #[{ id := 0, name := "structInvariant", callableId := 1 }]
  }
  let invAdmitted ← admitOk "struct-invariant" invCarrier
  expect (evalInvariantReferenceSliceV1 invAdmitted 0 pre == .returnedTrue)
    "struct-invariant: returned true"

  -- Unit constructor 0 with no args produces canonical empty bytes; the
  -- callable still returns Unit through `return none`.
  let unitConstruct := mkEntry 0 "unitConstruct" #[] 4
    #[instr (some (vd 0 4)) (.construct 4 0 #[])] (.return_ none)
  let unitBase ← emptyData "UnitConstruct"
  let unitCarrier ← encodeCarrier "unit-construct" {
    unitBase with types, callables := #[unitConstruct]
  }
  let unitAdmitted ← admitOk "unit-construct" unitCarrier
  expectReturned "unit-construct"
    (stepReferenceSliceV1 unitAdmitted pre (inv 0 #[]) #[]) pre none #[]

  -- Admission computes widths/depths/work without materializing defaults. A
  -- compact doubling Struct DAG exceeds the work cap; a deep chain exceeds
  -- maxNesting. The oversized type is also a state row, pinning rejection
  -- before state init.
  let doublingTypes (structCount : Nat) : Array TypeDeclV1 := Id.run do
    let mut out : Array TypeDeclV1 := #[]
    for i in [:structCount] do
      let child := UInt32.ofNat (i + 1)
      out := out.push {
        id := UInt32.ofNat i
        name := some s!"Wide{i}"
        shape := .struct #[
          { name := "left", typeId := child },
          { name := "right", typeId := child }
        ]
      }
    out := out.push {
      id := UInt32.ofNat structCount, name := none, shape := .bytes 4096
    }
    pure out
  let wideTypes := doublingTypes 13
  let wideGate := mkEntry 0 "wideGate" #[] 13 #[] (.return_ none)
  let wideBase ← emptyData "WideStruct"
  let wideCarrier ← encodeCarrier "wide-struct" {
    wideBase with
    types := wideTypes
    logicalState := #[
      { id := 0, name := "wide", typeId := 0, visibility := .public_ }
    ]
    callables := #[wideGate]
  }
  admitUnsupported "wide-struct" wideCarrier
    (fun detail => detail.contains "construction work") "Struct construction work"

  -- Zero-width leaves still cost recursive visits. The compact doubling DAG
  -- must not bypass the work cap merely because its canonical bytes are empty.
  let zeroDoublingTypes (structCount : Nat) : Array TypeDeclV1 := Id.run do
    let mut out : Array TypeDeclV1 := #[]
    for i in [:structCount] do
      let child := UInt32.ofNat (i + 1)
      out := out.push {
        id := UInt32.ofNat i
        name := some s!"Zero{i}"
        shape := .struct #[
          { name := "left", typeId := child },
          { name := "right", typeId := child }
        ]
      }
    out := out.push {
      id := UInt32.ofNat structCount, name := none, shape := .unit
    }
    pure out
  let zeroWorkBase ← emptyData "ZeroWorkStruct"
  let zeroWorkGate := mkEntry 0 "zeroWorkGate" #[] 25 #[] (.return_ none)
  let zeroWorkCarrier ← encodeCarrier "zero-work-struct" {
    zeroWorkBase with types := zeroDoublingTypes 25, callables := #[zeroWorkGate]
  }
  admitUnsupported "zero-work-struct" zeroWorkCarrier
    (fun detail => detail.contains "construction work")
    "zero-width Struct construction work"
  let boundedZeroWorkGate := mkEntry 0 "boundedZeroWorkGate" #[] 24 #[] (.return_ none)
  let boundedZeroWorkCarrier ← encodeCarrier "bounded-zero-work-struct" {
    zeroWorkBase with
    types := zeroDoublingTypes 24
    callables := #[boundedZeroWorkGate]
  }
  let _ ← admitOk "bounded-zero-work-struct" boundedZeroWorkCarrier

  let overwideFields : Array StructFieldV1 := Id.run do
    let mut fields : Array StructFieldV1 := #[]
    for i in [:4097] do
      fields := fields.push { name := s!"f{i}", typeId := 1 }
    pure fields
  let overwideTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "Overwide", shape := .struct overwideFields },
    { id := 1, name := none, shape := .bytes 4096 }
  ]
  let overwideGate := mkEntry 0 "overwideGate" #[] 1 #[] (.return_ none)
  let overwideBase ← emptyData "OverwideStruct"
  let overwideCarrier ← encodeCarrier "overwide-struct" {
    overwideBase with types := overwideTypes, callables := #[overwideGate]
  }
  admitUnsupported "overwide-struct" overwideCarrier
    (fun detail => detail.contains "byte limit") "Struct byte limit"

  -- Individually legal flat Struct defaults must also be bounded by aggregate
  -- construction work across state rows before materialization.
  let flatFields : Array StructFieldV1 := Id.run do
    let mut fields : Array StructFieldV1 := #[]
    for i in [:1024] do
      fields := fields.push { name := s!"f{i}", typeId := 1 }
    pure fields
  let flatTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "FlatWide", shape := .struct flatFields },
    { id := 1, name := none, shape := .bytes 4096 }
  ]
  let aggregateGate := mkEntry 0 "aggregateGate" #[] 1 #[] (.return_ none)
  let aggregateBase ← emptyData "AggregateStateStruct"
  let aggregateCarrier ← encodeCarrier "aggregate-state-struct" {
    aggregateBase with
    types := flatTypes
    logicalState := #[
      { id := 0, name := "wide0", typeId := 0, visibility := .public_ },
      { id := 1, name := "wide1", typeId := 0, visibility := .public_ },
      { id := 2, name := "wide2", typeId := 0, visibility := .public_ }
    ]
    callables := #[aggregateGate]
  }
  admitUnsupported "aggregate-state-struct" aggregateCarrier
    (fun detail => detail.contains "aggregate work limit")
    "logical-state aggregate work limit"

  let boundedAggregateCarrier ← encodeCarrier "bounded-aggregate-state-struct" {
    aggregateBase with
    types := flatTypes
    logicalState := #[
      { id := 0, name := "wide0", typeId := 0, visibility := .public_ },
      { id := 1, name := "wide1", typeId := 0, visibility := .public_ }
    ]
    callables := #[aggregateGate]
  }
  let _ ← admitOk "bounded-aggregate-state-struct" boundedAggregateCarrier

  -- A wide value hidden behind many one-field wrappers stays under final
  -- width/depth limits but exceeds cumulative recursive construction work.
  let workTypes (wrappers : Nat) : Array TypeDeclV1 := Id.run do
    let mut out : Array TypeDeclV1 := #[]
    for i in [:wrappers] do
      out := out.push {
        id := UInt32.ofNat i
        name := some s!"Work{i}"
        shape := .struct #[{ name := "next", typeId := UInt32.ofNat (i + 1) }]
      }
    let mut wideFields : Array StructFieldV1 := #[]
    for i in [:1024] do
      wideFields := wideFields.push {
        name := s!"f{i}", typeId := UInt32.ofNat (wrappers + 1)
      }
    out := out.push {
      id := UInt32.ofNat wrappers
      name := some "WorkWide"
      shape := .struct wideFields
    }
    out := out.push {
      id := UInt32.ofNat (wrappers + 1), name := none, shape := .bytes 4096
    }
    pure out
  let workGate := mkEntry 0 "workGate" #[] 15 #[] (.return_ none)
  let workBase ← emptyData "WorkStruct"
  let workCarrier ← encodeCarrier "work-struct" {
    workBase with types := workTypes 14, callables := #[workGate]
  }
  admitUnsupported "work-struct" workCarrier
    (fun detail => detail.contains "construction work")
    "Struct construction work"

  let boundedWorkGate := mkEntry 0 "boundedWorkGate" #[] 14 #[] (.return_ none)
  let boundedWorkCarrier ← encodeCarrier "bounded-work-struct" {
    workBase with types := workTypes 13, callables := #[boundedWorkGate]
  }
  let _ ← admitOk "bounded-work-struct" boundedWorkCarrier

  let deepGate := mkEntry 0 "deepGate" #[] 256 #[] (.return_ none)
  let deepBase ← emptyData "DeepStruct"
  let deepCarrier ← encodeCarrier "deep-struct" {
    deepBase with types := depth257, callables := #[deepGate]
  }
  admitUnsupported "deep-struct" deepCarrier
    (fun detail => detail.contains "nesting limit") "Struct nesting limit"

/-- Fixed Array/Bytes construction and immutable index behavior. -/
private def testArrayBytesReferenceSlice : IO Unit := do
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .uint 8 },
    { id := 1, name := none, shape := .uint 32 },
    { id := 2, name := none, shape := .array 0 3 },
    { id := 3, name := none, shape := .bytes 3 },
    { id := 4, name := none, shape := .unit },
    { id := 5, name := none, shape := .bool }
  ]
  let arrayBytes := ByteArray.mk #[4, 5, 6]
  match splitCanonicalArrayValueV1 types 2 arrayBytes with
  | .ok chunks =>
      expect (chunks.size == 3 && chunks[1]! == ByteArray.mk #[5])
        "array codec split"
  | .error e => throw <| IO.userError s!"array codec split: {repr e}"
  match encodeCanonicalArrayValueV1 types 2
      #[ByteArray.mk #[4], ByteArray.mk #[5], ByteArray.mk #[6]] with
  | .ok bytes => expect (bytes == arrayBytes) "array codec encode"
  | .error e => throw <| IO.userError s!"array codec encode: {repr e}"
  expect (exceptIsError (splitCanonicalArrayValueV1 types 2 (ByteArray.mk #[4, 5])))
    "array codec truncated"
  expect (exceptIsError (splitCanonicalArrayValueV1 types 2
    (ByteArray.mk #[4, 5, 6, 7]))) "array codec trailing"
  expect (exceptIsError (encodeCanonicalArrayValueV1 types 2 #[ByteArray.mk #[4]]))
    "array codec count"
  expect (exceptIsError (splitCanonicalArrayValueV1 types 3 arrayBytes))
    "array codec wrong shape"
  -- Public codecs accept raw TypeDecl tables, so they must defend the shape
  -- limit themselves before iterating or reserving an output array.
  let rawOverlong : Array TypeDeclV1 := #[
    { id := 0, name := none,
      shape := .array 1 (UInt32.ofNat (maxTypeLengthV1 + 1)) },
    { id := 1, name := none, shape := .unit }
  ]
  expectSemanticError "array codec raw overlong split" .limitExceeded
    (splitCanonicalArrayValueV1 rawOverlong 0 ByteArray.empty)
  expectSemanticError "array codec raw overlong encode" .limitExceeded
    (encodeCanonicalArrayValueV1 rawOverlong 0 #[])

  -- Get first/later, set later, then observe both the old and new SSA values.
  let arrayEntry := mkEntry 0 "arrayBytes" #[] 0 #[
    instr (some (vd 0 0)) (.literal 0 (ByteArray.mk #[4])),
    instr (some (vd 1 0)) (.literal 0 (ByteArray.mk #[5])),
    instr (some (vd 2 0)) (.literal 0 (ByteArray.mk #[6])),
    instr (some (vd 3 2)) (.construct 2 0 #[0, 1, 2]),
    instr (some (vd 4 1)) (.literal 1 (leBytesFromNat 1 4)),
    instr (some (vd 5 0)) (.indexGet 3 4),
    instr (some (vd 6 0)) (.literal 0 (ByteArray.mk #[9])),
    instr (some (vd 7 2)) (.indexSet 3 4 6),
    instr (some (vd 8 0)) (.indexGet 3 4),
    instr (some (vd 9 0)) (.indexGet 7 4),
    instr (some (vd 10 0)) (.literal 0 (ByteArray.mk #[5])),
    instr (some (vd 11 5)) (.binary .eq 8 10),
    instr none (.assert_ 11 none #[]),
    instr (some (vd 12 0)) (.literal 0 (ByteArray.mk #[9])),
    instr (some (vd 13 5)) (.binary .eq 9 12),
    instr none (.assert_ 13 none #[]),
    instr (some (vd 14 3)) (.literal 3 arrayBytes),
    instr (some (vd 15 3)) (.indexSet 14 4 6),
    instr (some (vd 16 0)) (.indexGet 15 4)
  ] (.return_ (some 16))
  let base ← emptyData "ArrayBytes"
  let carrier ← encodeCarrier "array-bytes" { base with types, callables := #[arrayEntry] }
  let admitted ← admitOk "array-bytes" carrier
  let pre : LogicalStateV1 := { initialized := true, canonicalValues := ByteArray.empty }
  expectReturned "array-bytes" (stepReferenceSliceV1 admitted pre (inv 0 #[]) #[])
    pre (some { typeId := 0, valueBytes := ByteArray.mk #[9] }) #[]

  let oor := mkEntry 0 "arrayOor" #[] 4 #[
    instr (some (vd 0 2)) (.literal 2 arrayBytes),
    instr (some (vd 1 1)) (.literal 1 (leBytesFromNat 3 4)),
    instr (some (vd 2 0)) (.indexGet 0 1)
  ] (.return_ none)
  let oorCarrier ← encodeCarrier "array-oor" { base with types, callables := #[oor] }
  let oorAdmitted ← admitOk "array-oor" oorCarrier
  expectRevertedStandard "array-oor"
    (stepReferenceSliceV1 oorAdmitted pre (inv 0 #[]) #[]) .indexOutOfBounds pre

  let arraySetOor := mkEntry 0 "arraySetOor" #[] 4 #[
    instr (some (vd 0 2)) (.literal 2 arrayBytes),
    instr (some (vd 1 1)) (.literal 1 (leBytesFromNat 3 4)),
    instr (some (vd 2 0)) (.literal 0 (ByteArray.mk #[9])),
    instr (some (vd 3 2)) (.indexSet 0 1 2)
  ] (.return_ none)
  let arraySetOorCarrier ← encodeCarrier "array-set-oor"
    { base with types, callables := #[arraySetOor] }
  let arraySetOorAdmitted ← admitOk "array-set-oor" arraySetOorCarrier
  expectRevertedStandard "array-set-oor"
    (stepReferenceSliceV1 arraySetOorAdmitted pre (inv 0 #[]) #[])
    .indexOutOfBounds pre

  let bytesGetOor := mkEntry 0 "bytesGetOor" #[] 4 #[
    instr (some (vd 0 3)) (.literal 3 arrayBytes),
    instr (some (vd 1 1)) (.literal 1 (leBytesFromNat 3 4)),
    instr (some (vd 2 0)) (.indexGet 0 1)
  ] (.return_ none)
  let bytesGetOorCarrier ← encodeCarrier "bytes-get-oor"
    { base with types, callables := #[bytesGetOor] }
  let bytesGetOorAdmitted ← admitOk "bytes-get-oor" bytesGetOorCarrier
  expectRevertedStandard "bytes-get-oor"
    (stepReferenceSliceV1 bytesGetOorAdmitted pre (inv 0 #[]) #[])
    .indexOutOfBounds pre

  let bytesSetOor := mkEntry 0 "bytesSetOor" #[] 4 #[
    instr (some (vd 0 3)) (.literal 3 arrayBytes),
    instr (some (vd 1 1)) (.literal 1 (leBytesFromNat 3 4)),
    instr (some (vd 2 0)) (.literal 0 (ByteArray.mk #[9])),
    instr (some (vd 3 3)) (.indexSet 0 1 2)
  ] (.return_ none)
  let bytesSetOorCarrier ← encodeCarrier "bytes-set-oor"
    { base with types, callables := #[bytesSetOor] }
  let bytesSetOorAdmitted ← admitOk "bytes-set-oor" bytesSetOorCarrier
  expectRevertedStandard "bytes-set-oor"
    (stepReferenceSliceV1 bytesSetOorAdmitted pre (inv 0 #[]) #[])
    .indexOutOfBounds pre

  let indexPure := mkPureFn 1 "indexPure" #[
    { valueId := 0, name := "xs", typeId := 2, visibility := .public_ },
    { valueId := 1, name := "i", typeId := 1, visibility := .public_ }
  ] 0 #[instr (some (vd 2 0)) (.indexGet 0 1)] (.return_ (some 2))
  let pureEntry := mkEntry 0 "indexPureEntry" #[] 0 #[
    instr (some (vd 0 2)) (.literal 2 arrayBytes),
    instr (some (vd 1 1)) (.literal 1 (leBytesFromNat 2 4)),
    instr (some (vd 2 0)) (.pureCall 1 #[0, 1])
  ] (.return_ (some 2))
  let pureCarrier ← encodeCarrier "array-index-pure"
    { base with types, callables := #[pureEntry, indexPure] }
  let pureAdmitted ← admitOk "array-index-pure" pureCarrier
  expectReturned "array-index-pure"
    (stepReferenceSliceV1 pureAdmitted pre (inv 0 #[]) #[]) pre
    (some { typeId := 0, valueBytes := ByteArray.mk #[6] }) #[]

  let indexInvariant : CallableV1 := {
    id := 1, kind := .invariant, name := some "indexInvariant", params := #[]
    result := { typeId := 5, visibility := .public_ }
    entryBlock := 0
    blocks := #[blk 0 #[
      instr (some (vd 0 2)) (.literal 2 arrayBytes),
      instr (some (vd 1 1)) (.literal 1 (leBytesFromNat 1 4)),
      instr (some (vd 2 0)) (.indexGet 0 1),
      instr (some (vd 3 0)) (.literal 0 (ByteArray.mk #[5])),
      instr (some (vd 4 5)) (.binary .eq 2 3)
    ] (.return_ (some 4))]
    loopBounds := #[]
    invariantSteps := some 7
  }
  let invariantGate := mkEntry 0 "indexInvariantGate" #[] 4 #[] (.return_ none)
  let invariantCarrier ← encodeCarrier "array-index-invariant" {
    base with
    types
    callables := #[invariantGate, indexInvariant]
    invariants := #[{ id := 0, name := "indexInvariant", callableId := 1 }]
  }
  let invariantAdmitted ← admitOk "array-index-invariant" invariantCarrier
  expect (evalInvariantReferenceSliceV1 invariantAdmitted 0 pre == .returnedTrue)
    "array-index-invariant: returned true"

  let nestedTypes := types.push { id := 6, name := none, shape := .option 0 }
  let nestedTypes := nestedTypes.push { id := 7, name := none, shape := .array 6 3 }
  match splitCanonicalArrayValueV1 nestedTypes 7 (ByteArray.mk #[0, 1, 7, 0]) with
  | .ok chunks =>
      expect (chunks.size == 3 && chunks[1]! == ByteArray.mk #[1, 7])
        "nested Array<Option<UInt8>> split"
  | .error e => throw <| IO.userError s!"nested array codec: {repr e}"

  -- Reference work exactly mirrors Wire's entry+children+output recurrence.
  let nestedWorkTypes (outerLength : UInt32) : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .unit },
    { id := 1, name := none, shape := .array 0 4096 },
    { id := 2, name := none, shape := .array 1 4096 },
    { id := 3, name := none, shape := .array 2 outerLength },
    { id := 4, name := none, shape := .bool }
  ]
  let workGate := mkEntry 0 "arrayWorkGate" #[] 4 #[] (.return_ none)
  let workBase ← emptyData "ArrayWork"
  let boundedWorkCarrier ← encodeCarrier "bounded-array-work" {
    workBase with types := nestedWorkTypes 1, callables := #[workGate]
  }
  let _ ← admitOk "bounded-array-work" boundedWorkCarrier
  let overWorkCarrier ← encodeCarrier "over-array-work" {
    workBase with types := nestedWorkTypes 2, callables := #[workGate]
  }
  admitUnsupported "over-array-work" overWorkCarrier
    (fun detail => detail.contains "construction work") "Array construction work"

  let widthTypes (outerLength : UInt32) : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bytes 4096 },
    { id := 1, name := none, shape := .array 0 4096 },
    { id := 2, name := none, shape := .array 1 outerLength },
    { id := 3, name := none, shape := .bool }
  ]
  let widthGate := mkEntry 0 "arrayWidthGate" #[] 3 #[] (.return_ none)
  let widthBase ← emptyData "ArrayWidth"
  let boundedWidthCarrier ← encodeCarrier "bounded-array-width" {
    widthBase with types := widthTypes 1, callables := #[widthGate]
  }
  let _ ← admitOk "bounded-array-width" boundedWidthCarrier
  let overWidthCarrier ← encodeCarrier "over-array-width" {
    widthBase with types := widthTypes 2, callables := #[widthGate]
  }
  admitUnsupported "over-array-width" overWidthCarrier
    (fun detail => detail.contains "byte limit") "Array byte limit"

  -- Map mechanics stay Wire-owned. UInt8 fixed-width keys cannot exercise a
  -- prefix relation, so ordering coverage uses differing unsigned bytes.
  let mapTypes := types.push { id := 6, name := none, shape := .map 0 0 }
  let mapBase ← emptyData "MapIndex"
  let mapTypes := mapTypes.push { id := 7, name := none, shape := .option 0 }
  let emptyMap ← match encodeCanonicalEmptyMapValueV1 mapTypes 6 with
    | .ok bytes => pure bytes
    | .error e => throw <| IO.userError s!"map empty codec: {repr e}"
  expect (emptyMap == ByteArray.mk #[0, 0, 0, 0]) "map canonical empty"
  let inserted ← match upsertCanonicalMapValueV1 mapTypes 6 emptyMap
      (ByteArray.mk #[20]) (ByteArray.mk #[9]) with
    | .ok bytes => pure bytes
    | .error e => throw <| IO.userError s!"map insert codec: {repr e}"
  let before ← match upsertCanonicalMapValueV1 mapTypes 6 inserted
      (ByteArray.mk #[10]) (ByteArray.mk #[8]) with
    | .ok bytes => pure bytes
    | .error e => throw <| IO.userError s!"map before codec: {repr e}"
  let after ← match upsertCanonicalMapValueV1 mapTypes 6 before
      (ByteArray.mk #[30]) (ByteArray.mk #[7]) with
    | .ok bytes => pure bytes
    | .error e => throw <| IO.userError s!"map after codec: {repr e}"
  let replaced ← match upsertCanonicalMapValueV1 mapTypes 6 after
      (ByteArray.mk #[20]) (ByteArray.mk #[6]) with
    | .ok bytes => pure bytes
    | .error e => throw <| IO.userError s!"map replace codec: {repr e}"
  match splitCanonicalMapValueV1 mapTypes 6 replaced with
  | .ok entries =>
      expect (entries.size == 3 && entries[0]!.keyBytes == ByteArray.mk #[10] &&
        entries[1]!.valueBytes == ByteArray.mk #[6] &&
        entries[2]!.keyBytes == ByteArray.mk #[30]) "map sorted insert/replace"
  | .error e => throw <| IO.userError s!"map split codec: {repr e}"
  let middle ← match upsertCanonicalMapValueV1 mapTypes 6 replaced
      (ByteArray.mk #[15]) (ByteArray.mk #[5]) with
    | .ok bytes => pure bytes
    | .error e => throw <| IO.userError s!"map middle codec: {repr e}"
  match splitCanonicalMapValueV1 mapTypes 6 middle with
  | .ok entries =>
      expect (entries.size == 4 && entries[0]!.keyBytes == ByteArray.mk #[10] &&
        entries[1]!.keyBytes == ByteArray.mk #[15] &&
        entries[2]!.keyBytes == ByteArray.mk #[20] &&
        entries[3]!.keyBytes == ByteArray.mk #[30]) "map middle insertion"
  | .error e => throw <| IO.userError s!"map middle split: {repr e}"
  expect (exceptIsError (splitCanonicalMapValueV1 mapTypes 6
    (replaced.append (ByteArray.mk #[0])))) "map trailing rejected"
  expect (exceptIsError (splitCanonicalMapValueV1 mapTypes 6
    (ByteArray.mk #[2,0,0,0, 1,0,0,0, 20, 1,0,0,0,9,
      1,0,0,0, 10, 1,0,0,0,8]))) "map unsorted rejected"
  expect (exceptIsError (splitCanonicalMapValueV1 mapTypes 6
    (ByteArray.mk #[2,0,0,0, 1,0,0,0, 10, 1,0,0,0,9,
      1,0,0,0, 10, 1,0,0,0,8]))) "map duplicate rejected"
  expect (match upsertCanonicalMapValueV1 mapTypes 6
      (encodeU32le (UInt32.ofNat (maxMapEntriesV1 + 1)))
      (ByteArray.mk #[10]) (ByteArray.mk #[9]) with
    | .error (.invalidInput .limitExceeded) => true
    | _ => false) "map malformed limit is invalid input"
  expect (match upsertCanonicalMapValueV1 mapTypes 6 emptyMap
      (ByteArray.mk #[10, 11]) (ByteArray.mk #[9]) with
    | .error (.invalidInput .nonCanonical) => true
    | _ => false) "map malformed key is invalid input"

  let mut nestingTypes : Array TypeDeclV1 := #[]
  for i in [:maxNesting - 1] do
    nestingTypes := nestingTypes.push {
      id := UInt32.ofNat i, name := none, shape := .option (UInt32.ofNat (i + 1)) }
  nestingTypes := nestingTypes.push {
    id := UInt32.ofNat (maxNesting - 1), name := none, shape := .unit }
  let nestingKeyId := UInt32.ofNat maxNesting
  nestingTypes := nestingTypes.push {
    id := nestingKeyId, name := none, shape := .uint 8 }
  let nestingMapId := UInt32.ofNat (maxNesting + 1)
  nestingTypes := nestingTypes.push {
    id := nestingMapId, name := none, shape := .map nestingKeyId 0 }
  let nestingValue := ByteArray.mk (Array.replicate (maxNesting - 1) 1)
  match validateValueBytesV1 nestingTypes 0 nestingValue with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"map standalone nesting boundary: {repr e}"
  let nestingEmpty ← match encodeCanonicalEmptyMapValueV1 nestingTypes nestingMapId with
    | .ok bytes => pure bytes
    | .error e => throw <| IO.userError s!"map nesting empty: {repr e}"
  expect (match upsertCanonicalMapValueV1 nestingTypes nestingMapId nestingEmpty
      (ByteArray.mk #[0]) nestingValue with
    | .error (.invalidInput .limitExceeded) => true
    | _ => false) "map insertion reserves outer nesting"

  let mapEntry := mkEntry 0 "mapIndex" #[] 7 #[
    instr (some (vd 0 6)) (.construct 6 0 #[]),
    instr (some (vd 1 0)) (.literal 0 (ByteArray.mk #[20])),
    instr (some (vd 2 7)) (.indexGet 0 1),
    instr (some (vd 3 0)) (.literal 0 (ByteArray.mk #[9])),
    instr (some (vd 4 6)) (.indexSet 0 1 3),
    instr (some (vd 5 7)) (.indexGet 0 1),
    instr (some (vd 6 7)) (.indexGet 4 1)
  ] (.return_ (some 6))
  let mapCarrier ← encodeCarrier "map-index" {
    mapBase with types := mapTypes, callables := #[mapEntry]
  }
  let mapAdmitted ← admitOk "map-index" mapCarrier
  let mapDefault ← match defaultValueV1 mapCarrier 6 with
    | .ok bytes => pure bytes
    | .error e => throw <| IO.userError s!"map default: {repr e}"
  expect (mapDefault == emptyMap) "map default is canonical empty"
  expectReturned "map-index" (stepReferenceSliceV1 mapAdmitted
    { initialized := true, canonicalValues := ByteArray.empty } (inv 0 #[]) #[])
    { initialized := true, canonicalValues := ByteArray.empty }
    (some { typeId := 7, valueBytes := ByteArray.mk #[1, 9] }) #[]

  let mapMissing := mkEntry 0 "mapMissing" #[] 7 #[
    instr (some (vd 0 6)) (.construct 6 0 #[]),
    instr (some (vd 1 0)) (.literal 0 (ByteArray.mk #[20])),
    instr (some (vd 2 7)) (.indexGet 0 1)
  ] (.return_ (some 2))
  let mapMissingCarrier ← encodeCarrier "map-missing" {
    mapBase with types := mapTypes, callables := #[mapMissing]
  }
  let mapMissingAdmitted ← admitOk "map-missing" mapMissingCarrier
  expectReturned "map-missing" (stepReferenceSliceV1 mapMissingAdmitted
    { initialized := true, canonicalValues := ByteArray.empty } (inv 0 #[]) #[])
    { initialized := true, canonicalValues := ByteArray.empty }
    (some { typeId := 7, valueBytes := ByteArray.mk #[0] }) #[]

  let mapOld := mkEntry 0 "mapOld" #[] 7 #[
    instr (some (vd 0 6)) (.construct 6 0 #[]),
    instr (some (vd 1 0)) (.literal 0 (ByteArray.mk #[20])),
    instr (some (vd 2 0)) (.literal 0 (ByteArray.mk #[9])),
    instr (some (vd 3 6)) (.indexSet 0 1 2),
    instr (some (vd 4 7)) (.indexGet 0 1)
  ] (.return_ (some 4))
  let mapOldCarrier ← encodeCarrier "map-old" {
    mapBase with types := mapTypes, callables := #[mapOld]
  }
  let mapOldAdmitted ← admitOk "map-old" mapOldCarrier
  expectReturned "map-old" (stepReferenceSliceV1 mapOldAdmitted
    { initialized := true, canonicalValues := ByteArray.empty } (inv 0 #[]) #[])
    { initialized := true, canonicalValues := ByteArray.empty }
    (some { typeId := 7, valueBytes := ByteArray.mk #[0] }) #[]

  let mapLookupPure := mkPureFn 1 "mapLookupPure" #[
    { valueId := 0, name := "m", typeId := 6, visibility := .public_ },
    { valueId := 1, name := "k", typeId := 0, visibility := .public_ }
  ] 7 #[instr (some (vd 2 7)) (.indexGet 0 1)] (.return_ (some 2))
  let mapPureEntry := mkEntry 0 "mapPureEntry" #[] 7 #[
    instr (some (vd 0 6)) (.construct 6 0 #[]),
    instr (some (vd 1 0)) (.literal 0 (ByteArray.mk #[20])),
    instr (some (vd 2 0)) (.literal 0 (ByteArray.mk #[9])),
    instr (some (vd 3 6)) (.indexSet 0 1 2),
    instr (some (vd 4 7)) (.pureCall 1 #[3, 1])
  ] (.return_ (some 4))
  let mapPureCarrier ← encodeCarrier "map-pure" {
    mapBase with types := mapTypes, callables := #[mapPureEntry, mapLookupPure]
  }
  let mapPureAdmitted ← admitOk "map-pure" mapPureCarrier
  expectReturned "map-pure" (stepReferenceSliceV1 mapPureAdmitted
    { initialized := true, canonicalValues := ByteArray.empty } (inv 0 #[]) #[])
    { initialized := true, canonicalValues := ByteArray.empty }
    (some { typeId := 7, valueBytes := ByteArray.mk #[1, 9] }) #[]

  let mapInvariant : CallableV1 := {
    id := 1, kind := .invariant, name := some "mapInvariant", params := #[]
    result := { typeId := 5, visibility := .public_ }
    entryBlock := 0
    blocks := #[blk 0 #[
      instr (some (vd 0 6)) (.construct 6 0 #[]),
      instr (some (vd 1 0)) (.literal 0 (ByteArray.mk #[20])),
      instr (some (vd 2 0)) (.literal 0 (ByteArray.mk #[9])),
      instr (some (vd 3 6)) (.indexSet 0 1 2),
      instr (some (vd 4 7)) (.indexGet 3 1),
      instr (some (vd 5 1)) (.variantTag 4),
      instr (some (vd 6 1)) (.literal 1 (leBytesFromNat 1 4)),
      instr (some (vd 7 5)) (.binary .eq 5 6)
    ] (.return_ (some 7))]
    loopBounds := #[]
    invariantSteps := some 10
  }
  let mapInvariantGate := mkEntry 0 "mapInvariantGate" #[] 4 #[] (.return_ none)
  let mapInvariantCarrier ← encodeCarrier "map-invariant" {
    mapBase with
    types := mapTypes
    callables := #[mapInvariantGate, mapInvariant]
    invariants := #[{ id := 0, name := "mapInvariant", callableId := 1 }]
  }
  let mapInvariantAdmitted ← admitOk "map-invariant" mapInvariantCarrier
  expect (evalInvariantReferenceSliceV1 mapInvariantAdmitted 0
    { initialized := true, canonicalValues := ByteArray.empty } == .returnedTrue)
    "map-invariant: returned true"

  let mapWorkTypes (fieldCount : Nat) : Array TypeDeclV1 := Id.run do
    let mut fields : Array StructFieldV1 := #[]
    for i in [:fieldCount] do
      fields := fields.push { name := s!"f{i}", typeId := 2 }
    pure #[
      { id := 0, name := some "MapValue", shape := .struct fields },
      { id := 1, name := none, shape := .uint 32 },
      { id := 2, name := none, shape := .unit },
      { id := 3, name := none, shape := .map 1 0 },
      { id := 4, name := none, shape := .bool }
    ]
  let mapWorkGate := mkEntry 0 "mapWorkGate" #[] 4 #[] (.return_ none)
  let mapWorkBase ← emptyData "MapWork"
  let boundedMapWorkCarrier ← encodeCarrier "bounded-map-work" {
    mapWorkBase with types := mapWorkTypes 17, callables := #[mapWorkGate]
  }
  let _ ← admitOk "bounded-map-work" boundedMapWorkCarrier
  let overMapWorkCarrier ← encodeCarrier "over-map-work" {
    mapWorkBase with types := mapWorkTypes 18, callables := #[mapWorkGate]
  }
  admitUnsupported "over-map-work" overMapWorkCarrier
    (fun detail => detail.contains "Map canonical update work") "Map update work"

  let recursiveMapTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "MapLoop", shape := .enum #[
      { name := "Stop", payloadTypes := #[] },
      { name := "More", payloadTypes := #[1] }] },
    { id := 1, name := none, shape := .map 3 2 },
    { id := 2, name := none, shape := .option 0 },
    { id := 3, name := none, shape := .uint 8 },
    { id := 4, name := none, shape := .unit }
  ]
  let recursiveMapGate := mkEntry 0 "recursiveMapGate" #[] 4 #[] (.return_ none)
  let recursiveMapBase ← emptyData "RecursiveMap"
  let recursiveMapCarrier ← encodeCarrier "recursive-map" {
    recursiveMapBase with types := recursiveMapTypes, callables := #[recursiveMapGate]
  }
  admitUnsupported "recursive-map" recursiveMapCarrier
    (fun detail => detail.contains "recursive" && detail.contains "resource bounds")
    "recursive Map boundary"

/-- Option/Enum canonical seam and runtime Construct/tag/payload behavior. -/
private def testVariantReferenceSlice : IO Unit := do
  let types : Array TypeDeclV1 := #[
    { id := 0, name := some "Choice", shape := .enum #[
      { name := "Empty", payloadTypes := #[] },
      { name := "Pair", payloadTypes := #[1, 2] },
      { name := "Other", payloadTypes := #[5] }] },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := none, shape := .uint 8 },
    { id := 3, name := none, shape := .uint 32 },
    { id := 4, name := none, shape := .option 2 },
    { id := 5, name := none, shape := .unit }
  ]
  let enumBytes := ByteArray.mk #[1, 0, 0, 0, 1, 9]
  match splitCanonicalVariantValueV1 types 0 enumBytes with
  | .ok (tag, chunks) =>
      expect (tag == 1 && chunks.size == 2) "variant codec: enum tag/payload count"
  | .error e => throw <| IO.userError s!"variant codec split: {repr e}"
  match encodeCanonicalVariantValueV1 types 4 1 #[ByteArray.mk #[9]] with
  | .ok bytes => expect (bytesEqual bytes (ByteArray.mk #[1, 9])) "variant codec: some"
  | .error e => throw <| IO.userError s!"variant codec encode: {repr e}"
  match encodeCanonicalVariantValueV1 types 4 0 #[] with
  | .ok bytes =>
      expect (bytesEqual bytes (ByteArray.mk #[0])) "variant codec: none"
      match splitCanonicalVariantValueV1 types 4 bytes with
      | .ok (tag, chunks) =>
          expect (tag == 0 && chunks.isEmpty) "variant codec: split none"
      | .error e => throw <| IO.userError s!"variant codec split none: {repr e}"
  | .error e => throw <| IO.userError s!"variant codec encode none: {repr e}"
  expect (exceptIsError (splitCanonicalVariantValueV1 types 4 (ByteArray.mk #[2])))
    "variant codec: bad Option tag fails closed"
  expect (exceptIsError (splitCanonicalVariantValueV1 types 0
    (enumBytes.append (ByteArray.mk #[0])))) "variant codec: trailing fails closed"
  expect (exceptIsError (encodeCanonicalVariantValueV1 types 0 1
    #[ByteArray.mk #[2], ByteArray.mk #[9]])) "variant codec: noncanonical payload"
  expect (exceptIsError (encodeCanonicalVariantValueV1 types 2 0 #[]))
    "variant codec: wrong type"

  let variantEntry := mkEntry 0 "variantOps" #[] 2 #[
    instr (some (vd 0 1)) (.literal 1 (ByteArray.mk #[1])),
    instr (some (vd 1 2)) (.literal 2 (ByteArray.mk #[9])),
    instr (some (vd 2 0)) (.construct 0 1 #[0, 1]),
    instr (some (vd 3 3)) (.variantTag 2),
    instr (some (vd 4 2)) (.variantPayload 2 1 1),
    instr (some (vd 5 4)) (.construct 4 1 #[4]),
    instr (some (vd 6 2)) (.variantPayload 5 1 0)
  ] (.return_ (some 6))
  let base ← emptyData "VariantOps"
  let carrier ← encodeCarrier "variant-ops" { base with types, callables := #[variantEntry] }
  let admitted ← admitOk "variant-ops" carrier
  let pre : LogicalStateV1 := { initialized := true, canonicalValues := ByteArray.empty }
  expectReturned "variant-ops" (stepReferenceSliceV1 admitted pre (inv 0 #[]) #[])
    pre (some { typeId := 2, valueBytes := ByteArray.mk #[9] }) #[]

  -- Commit is not restricted to a primitive allowlist: aggregate canonical
  -- bytes pass through exactly, including repeated Commit.
  let commitRequirement ← match commitmentDisclosureRequirementV1 with
    | .ok row => pure row
    | .error e => throw <| IO.userError s!"variant Commit requirement: {e}"
  let optionCommit := mkEntry 0 "optionCommit" #[] 4 #[
    instr (some (vd 0 2)) (.literal 2 (ByteArray.mk #[9])),
    instr (some (vd 1 4)) (.construct 4 1 #[0]),
    instr (some (vd 2 4)) (.commit 1),
    instr (some (vd 3 4)) (.commit 2)
  ] (.return_ (some 3))
  let optionCommitCarrier ← encodeCarrier "variant-option-commit" {
    base with
      types
      callables := #[optionCommit]
      requirements := { items := #[commitRequirement] }
  }
  let optionCommitAdmitted ← admitOk "variant-option-commit" optionCommitCarrier
  expectReturned "variant-option-commit"
    (stepReferenceSliceV1 optionCommitAdmitted pre (inv 0 #[]) #[]) pre
    (some { typeId := 4, valueBytes := ByteArray.mk #[1, 9] }) #[]

  let noneTag := mkEntry 0 "noneTag" #[] 3 #[
    instr (some (vd 0 4)) (.construct 4 0 #[]),
    instr (some (vd 1 3)) (.variantTag 0)
  ] (.return_ (some 1))
  let noneTagCarrier ← encodeCarrier "variant-none-tag"
    { base with types, callables := #[noneTag] }
  let noneTagAdmitted ← admitOk "variant-none-tag" noneTagCarrier
  expectReturned "variant-none-tag"
    (stepReferenceSliceV1 noneTagAdmitted pre (inv 0 #[]) #[]) pre
    (some { typeId := 3, valueBytes := ByteArray.mk #[0, 0, 0, 0] }) #[]

  let nonePayload := mkEntry 0 "nonePayload" #[] 2 #[
    instr (some (vd 0 4)) (.construct 4 0 #[]),
    instr (some (vd 1 2)) (.variantPayload 0 1 0)
  ] (.return_ (some 1))
  let nonePayloadCarrier ← encodeCarrier "variant-none-payload"
    { base with types, callables := #[nonePayload] }
  let nonePayloadAdmitted ← admitOk "variant-none-payload" nonePayloadCarrier
  expectTrapped "variant-none-payload"
    (stepReferenceSliceV1 nonePayloadAdmitted pre (inv 0 #[]) #[]) .invalidCore pre

  let emptyTag := mkEntry 0 "emptyTag" #[] 3 #[
    instr (some (vd 0 0)) (.construct 0 0 #[]),
    instr (some (vd 1 3)) (.variantTag 0)
  ] (.return_ (some 1))
  let emptyTagCarrier ← encodeCarrier "variant-empty-tag"
    { base with types, callables := #[emptyTag] }
  let emptyTagAdmitted ← admitOk "variant-empty-tag" emptyTagCarrier
  expectReturned "variant-empty-tag"
    (stepReferenceSliceV1 emptyTagAdmitted pre (inv 0 #[]) #[]) pre
    (some { typeId := 3, valueBytes := ByteArray.mk #[0, 0, 0, 0] }) #[]

  let optionPure := mkPureFn 1 "optionPure"
    #[{ valueId := 0, name := "x", typeId := 2, visibility := .public_ }] 2 #[
      instr (some (vd 1 4)) (.construct 4 1 #[0]),
      instr (some (vd 2 2)) (.variantPayload 1 1 0)
    ] (.return_ (some 2))
  let pureEntry := mkEntry 0 "variantPureCall" #[] 2 #[
    instr (some (vd 0 2)) (.literal 2 (ByteArray.mk #[9])),
    instr (some (vd 1 2)) (.pureCall 1 #[0])
  ] (.return_ (some 1))
  let pureCarrier ← encodeCarrier "variant-pure-call"
    { base with types, callables := #[pureEntry, optionPure] }
  let pureAdmitted ← admitOk "variant-pure-call" pureCarrier
  expectReturned "variant-pure-call"
    (stepReferenceSliceV1 pureAdmitted pre (inv 0 #[]) #[]) pre
    (some { typeId := 2, valueBytes := ByteArray.mk #[9] }) #[]

  let variantInvariant : CallableV1 := {
    id := 1
    kind := .invariant
    name := some "variantInvariant"
    params := #[]
    result := { typeId := 1, visibility := .public_ }
    entryBlock := 0
    blocks := #[blk 0 #[
      instr (some (vd 0 0)) (.construct 0 0 #[]),
      instr (some (vd 1 3)) (.variantTag 0),
      instr (some (vd 2 3)) (.literal 3 (ByteArray.mk #[0, 0, 0, 0])),
      instr (some (vd 3 1)) (.binary .eq 1 2)
    ] (.return_ (some 3))]
    loopBounds := #[]
    invariantSteps := some 6
  }
  let invariantGate := mkEntry 0 "invariantGate" #[] 5 #[] (.return_ none)
  let invariantCarrier ← encodeCarrier "variant-invariant" {
    base with
    types
    callables := #[invariantGate, variantInvariant]
    invariants := #[{ id := 0, name := "variantInvariant", callableId := 1 }]
  }
  let invariantAdmitted ← admitOk "variant-invariant" invariantCarrier
  expect (evalInvariantReferenceSliceV1 invariantAdmitted 0 pre == .returnedTrue)
    "variant-invariant: returned true"

  -- Static indices are valid, but disagree with the runtime constructor tag.
  let mismatch := mkEntry 0 "tagMismatch" #[] 5 #[
    instr (some (vd 0 1)) (.literal 1 (ByteArray.mk #[1])),
    instr (some (vd 1 2)) (.literal 2 (ByteArray.mk #[9])),
    instr (some (vd 2 0)) (.construct 0 1 #[0, 1]),
    instr (some (vd 3 5)) (.variantPayload 2 2 0)
  ] (.return_ (some 3))
  let mismatchCarrier ← encodeCarrier "variant-mismatch"
    { base with types, callables := #[mismatch] }
  let mismatchAdmitted ← admitOk "variant-mismatch" mismatchCarrier
  expectTrapped "variant-mismatch"
    (stepReferenceSliceV1 mismatchAdmitted pre (inv 0 #[]) #[]) .invalidCore pre

  -- Wire permits recursion through a named Enum and an anonymous Option, but
  -- this finite maximum-resource engineering subset rejects that graph.
  let recursiveTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "Loop", shape := .enum #[
      { name := "Stop", payloadTypes := #[] },
      { name := "More", payloadTypes := #[1] }] },
    { id := 1, name := none, shape := .option 0 },
    { id := 2, name := none, shape := .bool }
  ]
  let recursiveGate := mkEntry 0 "recursiveGate" #[] 2 #[] (.return_ none)
  let recursiveBase ← emptyData "RecursiveVariant"
  let recursiveCarrier ← encodeCarrier "recursive-variant" {
    recursiveBase with types := recursiveTypes, callables := #[recursiveGate]
  }
  admitUnsupported "recursive-variant" recursiveCarrier
    (fun detail => detail.contains "recursive" && detail.contains "resource bounds")
    "recursive aggregate boundary"

  -- Enum alternatives use a maximum (only one constructor exists at runtime),
  -- while repeated payload occurrences within one constructor are all charged.
  let enumWorkTypes (duplicatePayload : Bool) : Array TypeDeclV1 := Id.run do
    let payloads : Array TypeIdV1 := if duplicatePayload then #[1, 1] else #[1]
    let mut out : Array TypeDeclV1 := #[{
      id := 0, name := some "WorkChoice"
      shape := .enum #[{ name := "Payload", payloadTypes := payloads }]
    }]
    for i in [:23] do
      let tid := i + 1
      let child := UInt32.ofNat (tid + 1)
      out := out.push {
        id := UInt32.ofNat tid
        name := some s!"WorkNode{i}"
        shape := .struct #[
          { name := "left", typeId := child },
          { name := "right", typeId := child }
        ]
      }
    out := out.push { id := 24, name := none, shape := .unit }
    pure out
  let enumWorkGate := mkEntry 0 "enumWorkGate" #[] 24 #[] (.return_ none)
  let enumWorkBase ← emptyData "EnumWork"
  let boundedEnumWorkCarrier ← encodeCarrier "bounded-enum-work" {
    enumWorkBase with types := enumWorkTypes false, callables := #[enumWorkGate]
  }
  let _ ← admitOk "bounded-enum-work" boundedEnumWorkCarrier
  let repeatedEnumWorkCarrier ← encodeCarrier "repeated-enum-work" {
    enumWorkBase with types := enumWorkTypes true, callables := #[enumWorkGate]
  }
  admitUnsupported "repeated-enum-work" repeatedEnumWorkCarrier
    (fun detail => detail.contains "construction work")
    "repeated Enum payload work"

/-- Structure-gated invariant roots execute only through the dedicated slice. -/
private def testInvariantReferenceSlice : IO Unit := do
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit }
  ]
  let gate := mkEntry 0 "gate" #[] 1 #[] (.return_ none)
  let mkInv (id : CallableIdV1) (name : String)
      (instructions : Array InstructionV1) (term : TerminatorV1)
      (steps : UInt64) : CallableV1 := {
    id, kind := .invariant, name := some name, params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[blk 0 instructions term]
    loopBounds := #[]
    invariantSteps := some steps
  }
  let runCase (label name : String) (invCallable : CallableV1)
      (expected : InvariantEvalResultV1) : IO Unit := do
    let base ← emptyData name
    let data : SemanticProgramDataV1 := {
      base with
      types
      callables := #[gate, invCallable]
      invariants := #[{ id := 0, name, callableId := 1 }]
    }
    let carrier ← encodeCarrier label data
    let admitted ← admitOk label carrier
    let pre : LogicalStateV1 := { initialized := true, canonicalValues := ByteArray.empty }
    expect (evalInvariantReferenceSliceV1 admitted 0 pre == expected)
      s!"{label}: invariant result mismatch"
    expectTrapped (label ++ "-normal-invocation")
      (stepReferenceSliceV1 admitted pre (inv 1 #[]) emptyResponses)
      .invalidInvocation pre
    expect (evalInvariantReferenceSliceV1 admitted 1 pre == .trapped)
      s!"{label}: bad ordinal must trap"
    expect (evalInvariantReferenceSliceV1 admitted 0
      { initialized := false, canonicalValues := ByteArray.empty } == .trapped)
      s!"{label}: uninitialized state must trap"
    expect (evalInvariantReferenceSliceV1 admitted 0
      { initialized := true, canonicalValues := ByteArray.mk #[255] } == .trapped)
      s!"{label}: malformed state must trap"

  runCase "invariant-true" "truth"
    (mkInv 1 "truth"
      #[instr (some (vd 0 0)) (.literal 0 (ByteArray.mk #[1]))]
      (.return_ (some 0)) 3)
    .returnedTrue
  runCase "invariant-false" "falsehood"
    (mkInv 1 "falsehood"
      #[instr (some (vd 0 0)) (.literal 0 (ByteArray.mk #[0]))]
      (.return_ (some 0)) 3)
    .returnedFalse
  runCase "invariant-checked-revert" "checkedRevert"
    (mkInv 1 "checkedRevert"
      #[instr (some (vd 0 0)) (.literal 0 (ByteArray.mk #[0])),
        instr none (.assert_ 0 none #[])]
      (.return_ (some 0)) 4)
    .reverted
  runCase "invariant-trap" "traps"
    (mkInv 1 "traps" #[] (.trap .unreachable) 2)
    .trapped

  -- Shared fuel includes both root and callee frame-entry charges: leaf=3,
  -- root=1 + (PureCall instruction + Return terminator) + leaf=6.
  let leaf : CallableV1 := {
    id := 1, kind := .pureFn, name := some "leaf", params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[blk 0
      #[instr (some (vd 0 0)) (.literal 0 (ByteArray.mk #[1]))]
      (.return_ (some 0))]
    loopBounds := #[]
    invariantSteps := some 3
  }
  let root := mkInv 2 "throughLeaf"
    #[instr (some (vd 0 0)) (.pureCall 1 #[])] (.return_ (some 0)) 6
  let base ← emptyData "InvariantPureCall"
  let typedBase : SemanticProgramDataV1 := { base with types }
  let data : SemanticProgramDataV1 := {
    typedBase with
    callables := #[gate, leaf, root]
    invariants := #[{ id := 0, name := "throughLeaf", callableId := 2 }]
  }
  let carrier ← encodeCarrier "invariant-pure-call" data
  let admitted ← admitOk "invariant-pure-call" carrier
  let pre : LogicalStateV1 := { initialized := true, canonicalValues := ByteArray.empty }
  expect (evalInvariantReferenceSliceV1 admitted 0 pre == .returnedTrue)
    "invariant-pure-call: exact carried shared fuel succeeds"
  let pureCallData ← match validateSemanticProgramV1 carrier with
    | .ok data => pure data
    | .error e => throw <| IO.userError s!"invariant-pure-call validate: {repr e}"
  expect (runInvariantCallableV1 pureCallData 2 pre == .returnedTrue)
    "invariant-pure-call lower runner: exact carried fuel 6 succeeds"
  -- Defensive lower-seam test: mutate already decoded, structure-valid data
  -- without sending deliberately stale metadata back through Wire validation.
  -- Lower only the root metadata; the leaf remains at its exact carried fuel 3.
  let pureCallRootFuel5 : SemanticProgramDataV1 := {
    pureCallData with
    callables := pureCallData.callables.map fun callable =>
      if callable.id == 2 then { callable with invariantSteps := some 5 }
      else callable
  }
  expect (runInvariantCallableV1 pureCallRootFuel5 2 pre == .trapped)
    "invariant-pure-call lower runner: root fuel 5 must trap after root+callee entry charges"

  -- The lower invariant runner is selected-callable scoped. An unrelated
  -- Int64 declaration cannot poison this Bool invariant.
  let broadTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .int 64 },
    { id := 2, name := none, shape := .unit }
  ]
  let broadGate := mkEntry 0 "broadGate" #[] 2 #[] (.return_ none)
  let broadRoot : CallableV1 := {
    id := 1, kind := .invariant, name := some "broadTruth", params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[blk 0
      #[instr (some (vd 0 0)) (.literal 0 (ByteArray.mk #[1]))]
      (.return_ (some 0))]
    loopBounds := #[]
    invariantSteps := some 3
  }
  let broadBase ← emptyData "InvariantLowerRunner"
  let broadCarrier ← encodeCarrier "invariant-lower-runner" {
    broadBase with
      types := broadTypes
      callables := #[broadGate, broadRoot]
      invariants := #[{ id := 0, name := "broadTruth", callableId := 1 }]
  }
  let broadData ← match validateSemanticProgramV1 broadCarrier with
    | .ok data => pure data
    | .error e => throw <| IO.userError s!"invariant-lower-runner validate: {repr e}"
  expect (runInvariantCallableV1 broadData 1 pre == .returnedTrue)
    "invariant-lower-runner: unrelated unsupported type must not poison selected invariant"
  -- As above, this intentionally bypasses Wire revalidation: the lower runner
  -- must defensively enforce fuel even when decoded metadata is later mutated.
  let broadRootFuel2 : SemanticProgramDataV1 := {
    broadData with
    callables := broadData.callables.map fun callable =>
      if callable.id == 1 then { callable with invariantSteps := some 2 }
      else callable
  }
  expect (runInvariantCallableV1 broadRootFuel2 1 pre == .trapped)
    "invariant-lower-runner: straight-line exact fuel 3 lowered to 2 must trap"
  expect (runInvariantCallableV1 broadData 99 pre == .trapped)
    "invariant-lower-runner: missing callable must trap"
  expect (runInvariantCallableV1 broadData 1
      { initialized := false, canonicalValues := ByteArray.empty } == .trapped)
    "invariant-lower-runner: uninitialized state must trap"
  expect (runInvariantCallableV1 broadData 1
      { initialized := true, canonicalValues := ByteArray.mk #[255] } == .trapped)
    "invariant-lower-runner: malformed state must trap"

  -- Principal equality is canonical typed-byte equality. This also executes
  -- Unit Construct inside an invariant through the formal-compatible seam;
  -- whole-program engineering admission remains intentionally narrower.
  let principalTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .principal },
    { id := 2, name := none, shape := .unit }
  ]
  let principalBytes := (encodeU32le 1).append (ByteArray.mk #[7])
  let principalRoot : CallableV1 := {
    id := 1, kind := .invariant, name := some "principalTruth", params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[blk 0 #[
      instr (some (vd 0 2)) (.construct 2 0 #[]),
      instr (some (vd 1 1)) (.literal 1 principalBytes),
      instr (some (vd 2 1)) (.literal 1 principalBytes),
      instr (some (vd 3 0)) (.binary .eq 1 2)
    ] (.return_ (some 3))]
    loopBounds := #[]
    invariantSteps := some 6
  }
  let principalBase ← emptyData "InvariantPrincipalEquality"
  let principalCarrier ← encodeCarrier "invariant-principal-equality" {
    principalBase with
      types := principalTypes
      callables := #[mkEntry 0 "principalGate" #[] 2 #[] (.return_ none), principalRoot]
      invariants := #[{ id := 0, name := "principalTruth", callableId := 1 }]
  }
  admitUnsupported "invariant-principal-admission" principalCarrier
    (fun detail => detail.contains "Principal") "unrelated Principal"
  let principalData ← match validateSemanticProgramV1 principalCarrier with
    | .ok data => pure data
    | .error e => throw <| IO.userError s!"invariant-principal validate: {repr e}"
  expect (runInvariantCallableV1 principalData 1 pre == .returnedTrue)
    "invariant-principal: canonical equality and Unit Construct must execute"

/-- Complete fixed-width integer semantics through the selected invariant lower runner. -/
private def testFixedWidthIntegerLowerRunner : IO Unit := do
  let widths := #[8, 16, 32, 64, 128, 256]
  let uintId (i : Nat) : TypeIdV1 := UInt32.ofNat (2 + i)
  let intId (i : Nat) : TypeIdV1 := UInt32.ofNat (8 + i)
  let bytes (n width : Nat) := leBytesFromNat n (width / 8)
  let signedBytes (n : Int) (width : Nat) :=
    let modulus := Nat.pow 2 width
    bytes (if n < 0 then (n + Int.ofNat modulus).toNat else n.toNat) width
  let mut types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit }
  ]
  for i in [:widths.size] do
    let w := widths[i]!
    types := types.push { id := uintId i, name := none, shape := .uint (UInt16.ofNat w) }
  for i in [:widths.size] do
    let w := widths[i]!
    types := types.push { id := intId i, name := none, shape := .int (UInt16.ofNat w) }
  let integerTypes := types
  -- An unrelated catalog Field proves selection is callable-scoped.
  types := types.push {
    id := UInt32.ofNat types.size, name := none, shape := .field bn254FrFieldSpecV1 }
  let gate := mkEntry 0 "integerGate" #[] 1 #[] (.return_ none)
  let pre : LogicalStateV1 := { initialized := true, canonicalValues := ByteArray.empty }
  let run (label : String) (is : Array InstructionV1) (expected : InvariantEvalResultV1) : IO Unit := do
    let root : CallableV1 := {
      id := 1, kind := .invariant, name := some "integerInvariant", params := #[]
      result := { typeId := 0, visibility := .public_ }
      entryBlock := 0
      blocks := #[blk 0 is (.return_ (some (UInt32.ofNat (is.size - 1))))]
      loopBounds := #[], invariantSteps := some (UInt64.ofNat (is.size + 2))
    }
    let base ← emptyData "IntegerRuntime"
    let carrier ← encodeCarrier label {
      base with
      types := types
      callables := #[gate, root]
      invariants := #[{ id := 0, name := "integerInvariant", callableId := 1 }]
    }
    let data ← match validateSemanticProgramV1 carrier with
      | .ok d => pure d
      | .error e => throw <| IO.userError s!"{label}: validate: {repr e}"
    expect (runInvariantCallableV1 data 1 pre == expected)
      s!"{label}: expected {repr expected}"
  let trueResult (label : String) (is : Array InstructionV1) := run label is .returnedTrue
  let binaryTrue (label : String) (tid : TypeIdV1) (op : BinaryOpV1)
      (a b expected : ByteArray) : IO Unit :=
    trueResult label #[
      instr (some (vd 0 tid)) (.literal tid a),
      instr (some (vd 1 tid)) (.literal tid b),
      instr (some (vd 2 tid)) (.binary op 0 1),
      instr (some (vd 3 tid)) (.literal tid expected),
      instr (some (vd 4 0)) (.binary .eq 2 3)]
  let unaryTrue (label : String) (tid : TypeIdV1) (op : UnaryOpV1)
      (a expected : ByteArray) : IO Unit :=
    trueResult label #[
      instr (some (vd 0 tid)) (.literal tid a),
      instr (some (vd 1 tid)) (.unary op 0),
      instr (some (vd 2 tid)) (.literal tid expected),
      instr (some (vd 3 0)) (.binary .eq 1 2)]
  let binaryRevert (label : String) (tid : TypeIdV1) (op : BinaryOpV1)
      (a b : ByteArray) : IO Unit :=
    run label #[instr (some (vd 0 tid)) (.literal tid a),
      instr (some (vd 1 tid)) (.literal tid b),
      instr (some (vd 2 tid)) (.binary op 0 1),
      instr (some (vd 3 0)) (.literal 0 (ByteArray.mk #[1]))] .reverted
  let shiftTrue (label : String) (tid : TypeIdV1) (op : BinaryOpV1)
      (a count expected : ByteArray) : IO Unit :=
    trueResult label #[instr (some (vd 0 tid)) (.literal tid a),
      instr (some (vd 1 (uintId 2))) (.literal (uintId 2) count),
      instr (some (vd 2 tid)) (.binary op 0 1),
      instr (some (vd 3 tid)) (.literal tid expected),
      instr (some (vd 4 0)) (.binary .eq 2 3)]
  let shiftRevert (label : String) (tid : TypeIdV1) (op : BinaryOpV1)
      (a count : ByteArray) : IO Unit :=
    run label #[instr (some (vd 0 tid)) (.literal tid a),
      instr (some (vd 1 (uintId 2))) (.literal (uintId 2) count),
      instr (some (vd 2 tid)) (.binary op 0 1),
      instr (some (vd 3 0)) (.literal 0 (ByteArray.mk #[1]))] .reverted

  -- Every legal width and the complete canonical boundary set. The final Bool
  -- is a conjunction, so every literal/equality is semantically observed.
  let mut canonical : Array InstructionV1 := #[]
  let mut next : Nat := 0
  let mut acc : Option ValueIdV1 := none
  for i in [:widths.size] do
    let w := widths[i]!
    let umax := Nat.pow 2 w - 1
    let imin := -(Int.ofNat (Nat.pow 2 (w - 1)))
    let imax := Int.ofNat (Nat.pow 2 (w - 1)) - 1
    let vals : Array (TypeIdV1 × ByteArray) := #[(uintId i, bytes umax w),
      (intId i, signedBytes imin w), (intId i, signedBytes (-1) w),
      (intId i, signedBytes 0 w), (intId i, signedBytes 1 w),
      (intId i, signedBytes imax w)]
    for pair in vals do
      let a := UInt32.ofNat next; let b := UInt32.ofNat (next + 1)
      let eqv := UInt32.ofNat (next + 2)
      canonical := canonical.push (instr (some (vd a pair.1)) (.literal pair.1 pair.2))
      canonical := canonical.push (instr (some (vd b pair.1)) (.literal pair.1 pair.2))
      canonical := canonical.push (instr (some (vd eqv 0)) (.binary .eq a b))
      next := next + 3
      match acc with
      | none => acc := some eqv
      | some old =>
          canonical := canonical.push
            (instr (some (vd (UInt32.ofNat next) 0)) (.binary .and old eqv))
          acc := some (UInt32.ofNat next); next := next + 1
  trueResult "integer-canonical-width-table" canonical

  let u8 := uintId 0; let i8 := intId 0; let u256 := uintId 5; let i256 := intId 5
  binaryRevert "uint-overflow" u8 .add (bytes 255 8) (bytes 1 8)
  binaryRevert "uint-underflow" u8 .sub (bytes 0 8) (bytes 1 8)
  binaryTrue "uint-div" u8 .div (bytes 17 8) (bytes 5 8) (bytes 3 8)
  binaryTrue "uint-mod" u8 .mod (bytes 17 8) (bytes 5 8) (bytes 2 8)
  binaryTrue "uint-bitxor" u8 .bitXor (bytes 0xaa 8) (bytes 0x0f 8) (bytes 0xa5 8)
  shiftTrue "uint-shift-zero" u8 .shl (bytes 3 8) (bytes 0 32) (bytes 3 8)
  shiftTrue "uint-shift-width-minus-one" u8 .shr (bytes 128 8) (bytes 7 32) (bytes 1 8)
  shiftRevert "uint-shift-width" u8 .shl (bytes 1 8) (bytes 8 32)
  shiftRevert "uint-shl-overflow" u8 .shl (bytes 128 8) (bytes 1 32)

  binaryTrue "int-add" i8 .add (signedBytes (-5) 8) (signedBytes 3 8) (signedBytes (-2) 8)
  binaryTrue "int-sub" i8 .sub (signedBytes 5 8) (signedBytes 7 8) (signedBytes (-2) 8)
  binaryTrue "int-mul" i8 .mul (signedBytes (-6) 8) (signedBytes 7 8) (signedBytes (-42) 8)
  unaryTrue "int-neg" i8 .neg (signedBytes (-7) 8) (signedBytes 7 8)
  run "int-min-neg-overflow" #[instr (some (vd 0 i8)) (.literal i8 (signedBytes (-128) 8)),
    instr (some (vd 1 i8)) (.unary .neg 0),
    instr (some (vd 2 0)) (.literal 0 (ByteArray.mk #[1]))] .reverted
  binaryTrue "int-trunc-div" i8 .div (signedBytes (-7) 8) (signedBytes 3 8) (signedBytes (-2) 8)
  binaryTrue "int-dividend-sign-rem" i8 .mod (signedBytes (-7) 8) (signedBytes 3 8) (signedBytes (-1) 8)
  binaryTrue "int-negative-divisor-div" i8 .div (signedBytes 7 8) (signedBytes (-3) 8) (signedBytes (-2) 8)
  binaryTrue "int-negative-divisor-rem" i8 .mod (signedBytes 7 8) (signedBytes (-3) 8) (signedBytes 1 8)
  binaryTrue "int-both-negative-div" i8 .div (signedBytes (-7) 8) (signedBytes (-3) 8) (signedBytes 2 8)
  binaryTrue "int-both-negative-rem" i8 .mod (signedBytes (-7) 8) (signedBytes (-3) 8) (signedBytes (-1) 8)
  binaryRevert "int-min-div-minus-one" i8 .div (signedBytes (-128) 8) (signedBytes (-1) 8)
  binaryTrue "int-min-rem-minus-one" i8 .mod
    (signedBytes (-128) 8) (signedBytes (-1) 8) (signedBytes 0 8)
  trueResult "int-signed-lt" #[
    instr (some (vd 0 i8)) (.literal i8 (signedBytes (-1) 8)),
    instr (some (vd 1 i8)) (.literal i8 (signedBytes 1 8)),
    instr (some (vd 2 0)) (.binary .lt 0 1),
    instr (some (vd 3 0)) (.literal 0 (ByteArray.mk #[1])),
    instr (some (vd 4 0)) (.binary .eq 2 3)]
  binaryTrue "int-bitand" i8 .bitAnd (signedBytes (-2) 8) (signedBytes 3 8) (signedBytes 2 8)
  shiftTrue "int-shl" i8 .shl (signedBytes (-2) 8) (bytes 2 32) (signedBytes (-8) 8)
  shiftTrue "int-arithmetic-shr" i8 .shr (signedBytes (-3) 8) (bytes 1 32) (signedBytes (-2) 8)

  let castTrue (label : String) (src dst : TypeIdV1) (a expected : ByteArray) :=
    trueResult label #[instr (some (vd 0 src)) (.literal src a),
      instr (some (vd 1 dst)) (.checkedCast 0 dst),
      instr (some (vd 2 dst)) (.literal dst expected),
      instr (some (vd 3 0)) (.binary .eq 1 2)]
  let castRevert (label : String) (src dst : TypeIdV1) (a : ByteArray) :=
    run label #[instr (some (vd 0 src)) (.literal src a),
      instr (some (vd 1 dst)) (.checkedCast 0 dst),
      instr (some (vd 2 0)) (.literal 0 (ByteArray.mk #[1]))] .reverted
  castTrue "cast-uu-widen" u8 u256 (bytes 255 8) (bytes 255 256)
  castTrue "cast-uu-narrow-boundary" u256 u8 (bytes 255 256) (bytes 255 8)
  castRevert "cast-uu-out" u256 u8 (bytes 256 256)
  castTrue "cast-ui-widen" u8 i256 (bytes 255 8) (signedBytes 255 256)
  castTrue "cast-ui-narrow-boundary" u256 i8 (bytes 127 256) (signedBytes 127 8)
  castRevert "cast-ui-out" u256 i8 (bytes 128 256)
  castTrue "cast-iu-widen" i8 u256 (signedBytes 127 8) (bytes 127 256)
  castRevert "cast-iu-negative" i256 u8 (signedBytes (-1) 256)
  castTrue "cast-ii-widen" i8 i256 (signedBytes (-128) 8) (signedBytes (-128) 256)
  castTrue "cast-ii-narrow-boundary" i256 i8 (signedBytes 127 256) (signedBytes 127 8)
  castRevert "cast-ii-out" i256 i8 (signedBytes 128 256)

  -- A compact, separate fixture without Field exercises the engineering
  -- whole-program admission and preserves the exact standard revert reason;
  -- the lower invariant runner intentionally collapses all reverts above.
  let runWhole (label : String) (is : Array InstructionV1)
      (code : StandardRevertCodeV1) : IO Unit := do
    let entryCallable := mkEntry 0 "integerRuntime" #[] 1 is (.return_ none)
    let base ← emptyData "IntegerWholeProgram"
    let carrier ← encodeCarrier (label ++ "-whole") {
      base with types := integerTypes, callables := #[entryCallable]
    }
    let admitted ← match admitReferenceProgramSliceV1 carrier with
      | .ok admitted => pure admitted
      | .error e => throw <| IO.userError s!"{label}: admission failed: {repr e}"
    expectRevertedStandard label
      (stepReferenceSliceV1 admitted pre (inv 0 #[]) emptyResponses) code pre
  let wholeBinary (label : String) (op : BinaryOpV1) (a b : Int)
      (code : StandardRevertCodeV1) : IO Unit :=
    runWhole label #[
      instr (some (vd 0 i8)) (.literal i8 (signedBytes a 8)),
      instr (some (vd 1 i8)) (.literal i8 (signedBytes b 8)),
      instr (some (vd 2 i8)) (.binary op 0 1)] code
  let wholeShift (label : String) (a : Int) (count : Nat)
      (code : StandardRevertCodeV1) : IO Unit :=
    runWhole label #[
      instr (some (vd 0 i8)) (.literal i8 (signedBytes a 8)),
      instr (some (vd 1 (uintId 2))) (.literal (uintId 2) (bytes count 32)),
      instr (some (vd 2 i8)) (.binary .shl 0 1)] code
  let wholeCast (label : String) (src dst : TypeIdV1) (value : ByteArray) : IO Unit :=
    runWhole label #[
      instr (some (vd 0 src)) (.literal src value),
      instr (some (vd 1 dst)) (.checkedCast 0 dst)] .castOutOfRange

  wholeBinary "int-add-below-min-exact" .add (-128) (-1) .arithmeticUnderflow
  wholeBinary "int-sub-below-min-exact" .sub (-128) 1 .arithmeticUnderflow
  wholeBinary "int-mul-below-min-exact" .mul (-65) 2 .arithmeticUnderflow
  wholeBinary "int-add-above-max-exact" .add 127 1 .arithmeticOverflow
  wholeBinary "int-sub-above-max-exact" .sub 127 (-1) .arithmeticOverflow
  wholeBinary "int-mul-above-max-exact" .mul 64 2 .arithmeticOverflow
  wholeBinary "int-div-zero-exact" .div 1 0 .divisionByZero
  wholeBinary "int-mod-zero-exact" .mod 1 0 .divisionByZero
  runWhole "uint-mod-zero-exact" #[
    instr (some (vd 0 u8)) (.literal u8 (bytes 1 8)),
    instr (some (vd 1 u8)) (.literal u8 (bytes 0 8)),
    instr (some (vd 2 u8)) (.binary .mod 0 1)] .divisionByZero
  runWhole "int-neg-min-exact" #[
    instr (some (vd 0 i8)) (.literal i8 (signedBytes (-128) 8)),
    instr (some (vd 1 i8)) (.unary .neg 0)] .arithmeticOverflow
  wholeBinary "int-min-div-minus-one-exact" .div (-128) (-1) .arithmeticOverflow
  wholeShift "int-shl-below-min-exact" (-65) 1 .arithmeticUnderflow
  wholeShift "int-shl-above-max-exact" 64 1 .arithmeticOverflow
  wholeShift "int-shift-width-exact" 1 8 .invalidShift
  wholeCast "cast-uint-uint-exact" u256 u8 (bytes 256 256)
  wholeCast "cast-uint-int-exact" u256 i8 (bytes 128 256)
  wholeCast "cast-int-uint-exact" i256 u8 (signedBytes (-1) 256)
  wholeCast "cast-int-int-exact" i256 i8 (signedBytes 128 256)

/-- Focused BN254 scalar-field semantics, separate from fixed-width integers. -/
private def testBn254FieldLowerRunner : IO Unit := do
  let fieldTid : TypeIdV1 := 2
  let p := beBytesToNat bn254FrFieldSpecV1.modulusBE
  let fieldBytes (n : Nat) := leBytesFromNat n bn254FrFieldSpecV1.modulusBE.size
  let pre : LogicalStateV1 := { initialized := true, canonicalValues := ByteArray.empty }
  let baseTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit },
    { id := fieldTid, name := none, shape := .field bn254FrFieldSpecV1 }
  ]
  let gate := mkEntry 0 "fieldGate" #[] 1 #[] (.return_ none)
  let runLower (label : String) (is : Array InstructionV1)
      (expected : InvariantEvalResultV1 := .returnedTrue) : IO Unit := do
    let root : CallableV1 := {
      id := 1, kind := .invariant, name := some "fieldInvariant", params := #[]
      result := { typeId := 0, visibility := .public_ }
      entryBlock := 0
      blocks := #[blk 0 is (.return_ (some (UInt32.ofNat (is.size - 1))))]
      loopBounds := #[], invariantSteps := some (UInt64.ofNat (is.size + 2))
    }
    let base ← emptyData "Bn254FieldRuntime"
    -- Principal is deliberately unrelated to the selected invariant. Wire
    -- validates it, while the lower runner must not require broad admission.
    let types := baseTypes.push { id := 3, name := none, shape := .principal }
    let carrier ← encodeCarrier label {
      base with
      types := types
      callables := #[gate, root]
      invariants := #[{ id := 0, name := "fieldInvariant", callableId := 1 }]
    }
    let data ← match validateSemanticProgramV1 carrier with
      | .ok d => pure d
      | .error e => throw <| IO.userError s!"{label}: validate: {repr e}"
    expect (runInvariantCallableV1 data 1 pre == expected)
      s!"{label}: expected {repr expected}"
  let binaryTrue (label : String) (op : BinaryOpV1) (a b expected : Nat) :=
    runLower label #[
      instr (some (vd 0 fieldTid)) (.literal fieldTid (fieldBytes a)),
      instr (some (vd 1 fieldTid)) (.literal fieldTid (fieldBytes b)),
      instr (some (vd 2 fieldTid)) (.binary op 0 1),
      instr (some (vd 3 fieldTid)) (.literal fieldTid (fieldBytes expected)),
      instr (some (vd 4 0)) (.binary .eq 2 3)]
  let unaryTrue (label : String) (a expected : Nat) :=
    runLower label #[
      instr (some (vd 0 fieldTid)) (.literal fieldTid (fieldBytes a)),
      instr (some (vd 1 fieldTid)) (.unary .neg 0),
      instr (some (vd 2 fieldTid)) (.literal fieldTid (fieldBytes expected)),
      instr (some (vd 3 0)) (.binary .eq 1 2)]

  -- The modulus comes only from Wire's catalog object. Observe all three
  -- canonical boundary values in one conjunction-producing fixture.
  runLower "field-canonical-0-1-pminus1" #[
    instr (some (vd 0 fieldTid)) (.literal fieldTid (fieldBytes 0)),
    instr (some (vd 1 fieldTid)) (.literal fieldTid (fieldBytes 0)),
    instr (some (vd 2 0)) (.binary .eq 0 1),
    instr (some (vd 3 fieldTid)) (.literal fieldTid (fieldBytes 1)),
    instr (some (vd 4 fieldTid)) (.literal fieldTid (fieldBytes 1)),
    instr (some (vd 5 0)) (.binary .eq 3 4),
    instr (some (vd 6 0)) (.binary .and 2 5),
    instr (some (vd 7 fieldTid)) (.literal fieldTid (fieldBytes (p - 1))),
    instr (some (vd 8 fieldTid)) (.literal fieldTid (fieldBytes (p - 1))),
    instr (some (vd 9 0)) (.binary .eq 7 8),
    instr (some (vd 10 0)) (.binary .and 6 9)]
  binaryTrue "field-add-wrap" .add (p - 1) 1 0
  binaryTrue "field-sub-wrap" .sub 0 1 (p - 1)
  binaryTrue "field-mul-reduction" .mul (p - 1) (p - 1) 1
  unaryTrue "field-neg-zero" 0 0
  unaryTrue "field-neg-one" 1 (p - 1)
  -- Representative inverse identity: (a / b) * b = a.
  runLower "field-division-inverse-identity" #[
    instr (some (vd 0 fieldTid)) (.literal fieldTid (fieldBytes 7)),
    instr (some (vd 1 fieldTid)) (.literal fieldTid (fieldBytes 5)),
    instr (some (vd 2 fieldTid)) (.binary .div 0 1),
    instr (some (vd 3 fieldTid)) (.binary .mul 2 1),
    instr (some (vd 4 0)) (.binary .eq 3 0)]
  binaryTrue "field-division-by-one" .div (p - 1) 1 (p - 1)
  runLower "field-ne" #[
    instr (some (vd 0 fieldTid)) (.literal fieldTid (fieldBytes 0)),
    instr (some (vd 1 fieldTid)) (.literal fieldTid (fieldBytes 1)),
    instr (some (vd 2 0)) (.binary .ne 0 1)]

  -- Whole-program engineering admission accepts the supported Field-only
  -- fixture and preserves the exact standard division-by-zero reason.
  let base ← emptyData "Bn254FieldWholeProgram"
  let entryCallable := mkEntry 0 "fieldRuntime" #[] 1 #[
    instr (some (vd 0 fieldTid)) (.literal fieldTid (fieldBytes 7)),
    instr (some (vd 1 fieldTid)) (.literal fieldTid (fieldBytes 0)),
    instr (some (vd 2 fieldTid)) (.binary .div 0 1)] (.return_ none)
  let carrier ← encodeCarrier "field-division-zero-whole" {
    base with types := baseTypes, callables := #[entryCallable]
  }
  let admitted ← match admitReferenceProgramSliceV1 carrier with
    | .ok a => pure a
    | .error e => throw <| IO.userError s!"field whole admission failed: {repr e}"
  expectRevertedStandard "field-division-zero-exact"
    (stepReferenceSliceV1 admitted pre (inv 0 #[]) emptyResponses)
    .divisionByZero pre

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
  testLetForReferenceSlice session
  testShiftBitwiseLogicalReferenceSlice session
  testCallScheduleReferenceSlice session
  testPrimitiveEffectLogAndResponses
  testProgramRevertWithTrailingResponse
  testEmitThenRevertDiscardsEffects
  testInvalidInvocationAndInitLifecycle session
  testAdmissionUnsupported
  testContextReadReferenceSlice
  testUnitReturnShape
  testSwitchTrapAndTrailing
  testBoundedLoopEmitOccurrences
  testUIntStandardReverts
  testStructReferenceSlice
  testArrayBytesReferenceSlice
  testVariantReferenceSlice
  testInvariantReferenceSlice
  testFixedWidthIntegerLowerRunner
  testBn254FieldLowerRunner
  IO.println "Tests.Semantic.ReferenceV1: engineering suite finished"

end Tests.Semantic.ReferenceV1
