/-
  Tests.Semantic.Sem003ShapeV1 — engineering TST-SEM-003 *shape* pin.

  Public `step` + OutcomeWire. Pins:
    * overflow / declared Cap / assert rollback (LH-7)
    * every SemanticFaultV1 trap + pre held + OutcomeWire (LH-8)
    * matched external revert + trailing → invalidExternalResponse (LH-8)
    * program standard/declared revert + unconsumed response → same (LH-8)
    * arithmeticUnderflow / divisionByZero / boundExceeded (LH-8)
    * invalidShift / castOutOfRange / indexOutOfBounds /
      uninitialized / alreadyInitialized (LH-10)
    * Core/resource Term.Trap + unconsumed response → unique
      invalidExternalResponse (LH-13; Reference precedence)

  Does **not** close formal TASK-D2-07 / TST-SEM-003.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.OutcomeWireV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1
import Tests.Language.ParserSession

namespace Tests.Semantic.Sem003ShapeV1

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.OutcomeWireV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

private def wrap (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ body

private def leBytesFromNat (n : Nat) (len : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity len
  let mut v := n
  for _ in [:len] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

private def u64Bytes (n : Nat) : ByteArray := leBytesFromNat n 8

private def encodeCarrierData
    (label : String) (data : SemanticProgramDataV1) : IO SemanticProgramV1 := do
  let bytes ← match encodeSemanticProgramDataV1 data with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"{label}: encode: {repr e}"
  match decodeSemanticProgramV1 bytes with
  | .ok c => pure c
  | .error e => throw <| IO.userError s!"{label}: carrier: {repr e}"

private def emptyProgramData (name : String) : IO SemanticProgramDataV1 := do
  let qn ← match parseQualifiedName #["Tests", name] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"{name}: qn: {e}"
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

private def vd (valueId : ValueIdV1) (typeId : TypeIdV1) : ValueDefV1 :=
  { valueId, typeId }

private def instr (result : Option ValueDefV1) (op : SemanticOpV1) : InstructionV1 :=
  { result, op }

private def mkEntryInstrs
    (id : CallableIdV1) (name : String) (resultTypeId : TypeIdV1)
    (instructions : Array InstructionV1) (terminator : TerminatorV1) :
    CallableV1 :=
  {
    id
    kind := CallableKindV1.entry
    name := some name
    params := #[]
    result := { typeId := resultTypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{ id := 0, params := #[], instructions, terminator }]
    loopBounds := #[]
    invariantSteps := none
  }

private def logicalSlot (valueBytes : ByteArray) : ByteArray :=
  (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes

private def refU64 (tid : TypeIdV1) (n : Nat) : ReferenceValueV1 :=
  { typeId := tid, valueBytes := u64Bytes n }

private def inv (id : CallableIdV1) (args : Array ReferenceValueV1) : InvocationV1 :=
  { callableId := id, args, context := #[] }

private def mintOk (label : String) (outcome : OutcomeV1) : IO Unit := do
  let artifact ← match mintReferenceOutcomeArtifactV1 outcome with
    | .ok a => pure a
    | .error e => throw <| IO.userError s!"{label}: mint: {repr e}"
  match decodeReferenceOutcomeArtifactV1 artifact.canonicalBytes with
  | .ok again =>
      expect (again.canonicalBytes == artifact.canonicalBytes)
        s!"{label}: carrier identity"
  | .error e =>
      throw <| IO.userError s!"{label}: decode: {repr e}"

private def findU64 (data : SemanticProgramDataV1) : IO TypeIdV1 :=
  match data.types.findIdx? fun t =>
      t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
  | some i => pure (UInt32.ofNat i)
  | none => throw <| IO.userError "missing anonymous UInt64"

private def findCallable (data : SemanticProgramDataV1) (name : Option String) :
    IO CallableIdV1 := do
  let mut i : Nat := 0
  for c in data.callables do
    match name, c.name with
    | none, none => return UInt32.ofNat i
    | some want, some got =>
        if got == want then return UInt32.ofNat i
    | _, _ => pure ()
    i := i + 1
  throw <| IO.userError s!"callable not found: {repr name}"

private unsafe def loadNormalize
    (session : Language.Loader.ParserSession)
    (moduleName src : String) :
    IO (SemanticProgramV1 × SemanticProgramDataV1 × TypeIdV1) := do
  let validated ←
    match ← session.selectProgramV1 src
        "Tests/Semantic/Sem003ShapeV1.lean" moduleName none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"{moduleName}: load: {e.render}"
  let carrier ←
    match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"{moduleName}: normalize: {repr e}"
  let data ←
    match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"{moduleName}: validate: {repr e}"
  let u64 ← findU64 data
  pure (carrier, data, u64)

private def expectRollback
    (label : String) (outcome : OutcomeV1) (pre : LogicalStateV1)
    (want : SemanticRevertV1 → Bool) : IO Unit := do
  match outcome with
  | .reverted reason st =>
      expect (want reason) s!"{label}: unexpected reason {repr reason}"
      expect (st.initialized == pre.initialized) s!"{label}: initialized held"
      expect (st.canonicalValues == pre.canonicalValues)
        s!"{label}: canonicalValues held (unchanged pre-state)"
  | .returned _ _ effects =>
      throw <| IO.userError
        s!"{label}: expected revert, got returned effects={effects.size}"
  | .trapped f _ =>
      throw <| IO.userError s!"{label}: expected revert, trapped {repr f}"

/-- Trap path: exact fault, pre held. `OutcomeV1.trapped` has no effects field
    (zero committed effects by construction). -/
private def expectTrapped
    (label : String) (outcome : OutcomeV1) (want : SemanticFaultV1)
    (pre : LogicalStateV1) : IO Unit := do
  match outcome with
  | .trapped f st =>
      expect (f == want) s!"{label}: fault want {repr want} got {repr f}"
      expect (st.initialized == pre.initialized) s!"{label}: initialized held"
      expect (st.canonicalValues == pre.canonicalValues)
        s!"{label}: canonicalValues held (unchanged pre-state)"
  | .returned _ _ effects =>
      throw <| IO.userError
        s!"{label}: expected trap, got returned effects={effects.size}"
  | .reverted reason _ =>
      throw <| IO.userError
        s!"{label}: expected trap, got reverted {repr reason}"

/-- Minimal structure-gated Unit entry that terminates with `Term.Trap`. -/
private def encodeTrapEntryCarrier
    (name label : String) (code : SemanticTrapCodeV1) : IO SemanticProgramV1 := do
  let qn ← match parseQualifiedName #["Tests", name] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"{label}: qn: {e}"
  let boom : CallableV1 := {
    id := 0
    kind := CallableKindV1.entry
    name := some "boom"
    params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[]
      terminator := TerminatorV1.trap code
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let data : SemanticProgramDataV1 := {
    qualifiedName := qn
    types := #[{ id := 0, name := none, shape := TypeShapeV1.unit }]
    constants := #[]
    logicalState := #[]
    events := #[]
    errors := #[]
    callables := #[boom]
    invariants := #[]
    requirements := { items := #[] }
  }
  let bytes ← match encodeSemanticProgramDataV1 data with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"{label}: encode: {repr e}"
  match decodeSemanticProgramV1 bytes with
  | .ok c => pure c
  | .error e => throw <| IO.userError s!"{label}: carrier: {repr e}"

/-- First `Op.ExternalCall` EffectId in callable (source block/instr order). -/
private def firstExternalCallOcc (c : CallableV1) : IO EffectOccurrenceV1 := do
  for b in c.blocks do
    for i in b.instructions do
      match i.op with
      | .externalCall eid _ _ =>
          return { effectId := eid, occurrence := 0 }
      | _ => pure ()
  throw <| IO.userError "no ExternalCall in callable"

/-- Checked add overflow: standard arithmeticOverflow, pre-state held. -/
private unsafe def testOverflowRollback
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrap "Sem003Ovf" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n"
  let (carrier, data, u64) ← loadNormalize session "Sem003Ovf" src
  let initId ← findCallable data none
  let incId ← findCallable data (some "increment")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"ovf initial: {repr e}"
  let maxN : Nat := (2 ^ 64) - 1
  let afterInit := step carrier initial (inv initId #[refU64 u64 maxN]) #[]
  let pre ←
    match afterInit with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"ovf init: {repr other}"
  expect (pre.canonicalValues == logicalSlot (u64Bytes maxN)) "ovf pre is max"
  let ovf := step carrier pre (inv incId #[refU64 u64 1]) #[]
  expectRollback "ovf" ovf pre fun
    | .standard .arithmeticOverflow => true
    | _ => false
  mintOk "ovf" ovf

/-- Declared Cap revert after emit: effects discarded, state held. -/
private unsafe def testDeclaredEmitRollback
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrap "Sem003Cap" <|
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
    "    return count\n"
  let (carrier, data, u64) ← loadNormalize session "Sem003Cap" src
  let initId ← findCallable data none
  let bumpId ← findCallable data (some "bump")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"cap initial: {repr e}"
  let afterInit := step carrier initial (inv initId #[refU64 u64 5]) #[]
  let pre ←
    match afterInit with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"cap init: {repr other}"
  let cap := step carrier pre (inv bumpId #[refU64 u64 3]) #[]
  expectRollback "cap" cap pre fun
    | .declared _ args => args.size == 1
    | _ => false
  match cap with
  | .reverted _ _ => pure ()
  | _ => throw <| IO.userError "cap: expected reverted"
  mintOk "cap" cap

/-- Bare assert rollback: standard assertionFailed, pre-state held. -/
private unsafe def testAssertRollback
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrap "Sem003Assert" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry boom() : UInt64 do\n" ++
    "    assert count == 0\n" ++
    "    return count\n"
  let (carrier, data, u64) ← loadNormalize session "Sem003Assert" src
  let initId ← findCallable data none
  let boomId ← findCallable data (some "boom")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"assert initial: {repr e}"
  let afterInit := step carrier initial (inv initId #[refU64 u64 9]) #[]
  let pre ←
    match afterInit with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"assert init: {repr other}"
  let boom := step carrier pre (inv boomId #[]) #[]
  expectRollback "assert" boom pre fun
    | .standard .assertionFailed => true
    | _ => false
  mintOk "assert" boom

/-- Every SemanticFaultV1 via public `step`: trapped + pre held + OutcomeWire. -/
private unsafe def testAllSemanticFaults
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- invalidInvocation (Loader/Normalize; OOR callableId)
  let srcInv := wrap "Sem003Inv" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n"
  let (cInv, dataInv, u64Inv) ← loadNormalize session "Sem003Inv" srcInv
  let initInv ← findCallable dataInv none
  let initialInv ←
    match initialLogicalStateV1 cInv with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"fault-inv initial: {repr e}"
  let afterInitInv := step cInv initialInv (inv initInv #[refU64 u64Inv 1]) #[]
  let preInv ←
    match afterInitInv with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"fault-inv init: {repr other}"
  let badInv := step cInv preInv (inv 99 #[]) #[]
  expectTrapped "fault/invalidInvocation" badInv .invalidInvocation preInv
  mintOk "fault/invalidInvocation" badInv

  -- invalidExternalResponse (Loader/Normalize; missing call response)
  let srcExt := wrap "Sem003ExtMiss" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n"
  let (cExt, dataExt, u64Ext) ← loadNormalize session "Sem003ExtMiss" srcExt
  let initExt ← findCallable dataExt none
  let bumpExt ← findCallable dataExt (some "bump")
  let initialExt ←
    match initialLogicalStateV1 cExt with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"fault-ext initial: {repr e}"
  let afterInitExt := step cExt initialExt (inv initExt #[refU64 u64Ext 0]) #[]
  let preExt ←
    match afterInitExt with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"fault-ext init: {repr other}"
  let miss := step cExt preExt (inv bumpExt #[refU64 u64Ext 1]) #[]
  expectTrapped "fault/invalidExternalResponse" miss .invalidExternalResponse preExt
  mintOk "fault/invalidExternalResponse" miss

  -- invalidCore (garbage carrier; admit fails → façade trap)
  let garbage : SemanticProgramV1 := ⟨ByteArray.empty⟩
  let preCore : LogicalStateV1 :=
    { initialized := false, canonicalValues := ByteArray.mk #[7, 8, 9] }
  let core :=
    step garbage preCore { callableId := 0, args := #[], context := #[] } #[]
  expectTrapped "fault/invalidCore" core .invalidCore preCore
  mintOk "fault/invalidCore" core

  -- resourceExhausted / unreachable / internalInvariant (hand-built Term.Trap;
  -- product source cannot reliably emit these as sole entry).
  -- LH-13: nonempty unconsumed responses override the trap fault to unique
  -- invalidExternalResponse with exact pre (docs/05-test-spec.md precedence).
  let trailing : ExternalResponsesV1 := #[
    { occurrence := { effectId := 0, occurrence := 0 }, disposition := .returned }
  ]
  let runTrap (label : String) (code : SemanticTrapCodeV1)
      (fault : SemanticFaultV1) : IO Unit := do
    let carrier ← encodeTrapEntryCarrier ("Sem003" ++ label) label code
    let pre ←
      match initialLogicalStateV1 carrier with
      | .ok s => pure s
      | .error e => throw <| IO.userError s!"{label} initial: {repr e}"
    let clean := step carrier pre (inv 0 #[]) #[]
    expectTrapped label clean fault pre
    mintOk label clean
    let trail := step carrier pre (inv 0 #[]) trailing
    expectTrapped (label ++ "+trail") trail .invalidExternalResponse pre
    mintOk (label ++ "+trail") trail
  runTrap "TrapResource" .resourceExhausted .resourceExhausted
  runTrap "TrapUnreachable" .unreachable .unreachable
  runTrap "TrapInternal" .internalInvariant .internalInvariant

/-- Matched external revert + unconsumed trailing response → trap (not revert). -/
private unsafe def testExternalRevertTrailing
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrap "Sem003ExtRevTrail" <|
    "  state count : UInt64\n" ++
    "  event Ping(x : UInt64)\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    emit Ping(count)\n" ++
    "    call Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n"
  let (carrier, data, u64) ← loadNormalize session "Sem003ExtRevTrail" src
  let initId ← findCallable data none
  let bumpId ← findCallable data (some "bump")
  let bumpCallable ←
    match data.callables[bumpId.toNat]? with
    | some c => pure c
    | none => throw <| IO.userError "ext-rev: missing bump"
  let occCall ← firstExternalCallOcc bumpCallable
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"ext-rev initial: {repr e}"
  let afterInit := step carrier initial (inv initId #[refU64 u64 0]) #[]
  let pre ←
    match afterInit with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"ext-rev init: {repr other}"
  let responses : ExternalResponsesV1 := #[
    { occurrence := occCall, disposition := .reverted },
    { occurrence := { effectId := 9, occurrence := 0 }, disposition := .returned }
  ]
  let out := step carrier pre (inv bumpId #[refU64 u64 5]) responses
  expectTrapped "ext-rev+trail" out .invalidExternalResponse pre
  mintOk "ext-rev+trail" out

/-- Declared Cap / standard assert revert with trailing response → trap. -/
private unsafe def testProgramRevertUnconsumedResponse
    (session : Language.Loader.ParserSession) : IO Unit := do
  let trailing : ExternalResponsesV1 := #[
    { occurrence := { effectId := 0, occurrence := 0 }, disposition := .returned }
  ]

  -- Declared Cap (emit then revert) + unconsumed trailing
  let srcCap := wrap "Sem003CapTrail" <|
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
    "    return count\n"
  let (cCap, dCap, u64Cap) ← loadNormalize session "Sem003CapTrail" srcCap
  let initCap ← findCallable dCap none
  let bumpCap ← findCallable dCap (some "bump")
  let initialCap ←
    match initialLogicalStateV1 cCap with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"cap-trail initial: {repr e}"
  let afterCap := step cCap initialCap (inv initCap #[refU64 u64Cap 5]) #[]
  let preCap ←
    match afterCap with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"cap-trail init: {repr other}"
  let capTrail :=
    step cCap preCap (inv bumpCap #[refU64 u64Cap 3]) trailing
  expectTrapped "declared+trail" capTrail .invalidExternalResponse preCap
  mintOk "declared+trail" capTrail

  -- Standard assert + unconsumed trailing
  let srcAssert := wrap "Sem003AssertTrail" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry boom() : UInt64 do\n" ++
    "    assert count == 0\n" ++
    "    return count\n"
  let (cAs, dAs, u64As) ← loadNormalize session "Sem003AssertTrail" srcAssert
  let initAs ← findCallable dAs none
  let boomAs ← findCallable dAs (some "boom")
  let initialAs ←
    match initialLogicalStateV1 cAs with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"assert-trail initial: {repr e}"
  let afterAs := step cAs initialAs (inv initAs #[refU64 u64As 9]) #[]
  let preAs ←
    match afterAs with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"assert-trail init: {repr other}"
  let assertTrail := step cAs preAs (inv boomAs #[]) trailing
  expectTrapped "standard+trail" assertTrail .invalidExternalResponse preAs
  mintOk "standard+trail" assertTrail

/-- Standard underflow / div-zero / boundExceeded with pre held + OutcomeWire. -/
private unsafe def testStandardArithAndBoundReverts
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- arithmeticUnderflow via checked UInt sub
  let srcSub := wrap "Sem003Under" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry drop(delta : UInt64) : UInt64 do\n" ++
    "    count := count - delta\n" ++
    "    return count\n"
  let (cSub, dSub, u64Sub) ← loadNormalize session "Sem003Under" srcSub
  let initSub ← findCallable dSub none
  let dropId ← findCallable dSub (some "drop")
  let initialSub ←
    match initialLogicalStateV1 cSub with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"under initial: {repr e}"
  let afterSub := step cSub initialSub (inv initSub #[refU64 u64Sub 3]) #[]
  let preSub ←
    match afterSub with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"under init: {repr other}"
  let under := step cSub preSub (inv dropId #[refU64 u64Sub 5]) #[]
  expectRollback "under" under preSub fun
    | .standard .arithmeticUnderflow => true
    | _ => false
  mintOk "under" under

  -- divisionByZero
  let srcDiv := wrap "Sem003Div0" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry scale(a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    count := a / b\n" ++
    "    return count\n"
  let (cDiv, dDiv, u64Div) ← loadNormalize session "Sem003Div0" srcDiv
  let initDiv ← findCallable dDiv none
  let scaleId ← findCallable dDiv (some "scale")
  let initialDiv ←
    match initialLogicalStateV1 cDiv with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"div0 initial: {repr e}"
  let afterDiv := step cDiv initialDiv (inv initDiv #[refU64 u64Div 7]) #[]
  let preDiv ←
    match afterDiv with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"div0 init: {repr other}"
  let div0 :=
    step cDiv preDiv (inv scaleId #[refU64 u64Div 1, refU64 u64Div 0]) #[]
  expectRollback "div0" div0 preDiv fun
    | .standard .divisionByZero => true
    | _ => false
  mintOk "div0" div0

  -- boundExceeded (tight for bound; back edge after body N+1)
  let srcLoop := wrap "Sem003Bound" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry addUpTight(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n + 4 bounded 3 do\n" ++
    "      count := count + i\n" ++
    "    return count\n"
  let (cLoop, dLoop, u64Loop) ← loadNormalize session "Sem003Bound" srcLoop
  let initLoop ← findCallable dLoop none
  let tightId ← findCallable dLoop (some "addUpTight")
  let initialLoop ←
    match initialLogicalStateV1 cLoop with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"bound initial: {repr e}"
  let afterLoop := step cLoop initialLoop (inv initLoop #[refU64 u64Loop 0]) #[]
  let preLoop ←
    match afterLoop with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"bound init: {repr other}"
  let bound := step cLoop preLoop (inv tightId #[refU64 u64Loop 1]) #[]
  expectRollback "bound" bound preLoop fun
    | .standard .boundExceeded => true
    | _ => false
  mintOk "bound" bound

/-- Remaining StandardRevertCodeV1 pins (LH-10): invalidShift, castOutOfRange,
    indexOutOfBounds, uninitialized, alreadyInitialized. -/
private unsafe def testRemainingStandardReverts
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- invalidShift: UInt64 shift count ≥ 64 (Loader/Normalize; Reference BitRef)
  let srcShift := wrap "Sem003Shift" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry shrK(x : UInt64) : UInt64 do\n" ++
    "    return x >> (32 + 32)\n"
  let (cShift, dShift, u64Shift) ← loadNormalize session "Sem003Shift" srcShift
  let initShift ← findCallable dShift none
  let shrId ← findCallable dShift (some "shrK")
  let initialShift ←
    match initialLogicalStateV1 cShift with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"shift initial: {repr e}"
  let afterShift :=
    step cShift initialShift (inv initShift #[refU64 u64Shift 0]) #[]
  let preShift ←
    match afterShift with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"shift init: {repr other}"
  let badShift := step cShift preShift (inv shrId #[refU64 u64Shift 7]) #[]
  expectRollback "shift" badShift preShift fun
    | .standard .invalidShift => true
    | _ => false
  mintOk "shift" badShift

  -- castOutOfRange: UInt256 256 → UInt8 (hand-built; Reference wholeCast)
  let castTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := TypeShapeV1.unit },
    { id := 1, name := none, shape := TypeShapeV1.uint 256 },
    { id := 2, name := none, shape := TypeShapeV1.uint 8 }
  ]
  let castCallable := mkEntryInstrs 0 "castOor" 0
    #[
      instr (some (vd 0 1)) (.literal 1 (leBytesFromNat 256 32)),
      instr (some (vd 1 2)) (.checkedCast 0 2)
    ]
    (.return_ none)
  let castBase ← emptyProgramData "Sem003CastOor"
  let castCarrier ← encodeCarrierData "cast-oor" {
    castBase with types := castTypes, callables := #[castCallable]
  }
  let preCast : LogicalStateV1 :=
    { initialized := true, canonicalValues := ByteArray.empty }
  let castOut := step castCarrier preCast (inv 0 #[]) #[]
  expectRollback "cast" castOut preCast fun
    | .standard .castOutOfRange => true
    | _ => false
  mintOk "cast" castOut

  -- indexOutOfBounds: Array UInt8 len=3 get index 3 (hand-built; Reference array-oor)
  let arrTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := TypeShapeV1.uint 8 },
    { id := 1, name := none, shape := TypeShapeV1.uint 32 },
    { id := 2, name := none, shape := TypeShapeV1.array 0 3 },
    { id := 3, name := none, shape := TypeShapeV1.unit }
  ]
  let arrayBytes := ByteArray.mk #[4, 5, 6]
  let arrCallable := mkEntryInstrs 0 "arrayOor" 3
    #[
      instr (some (vd 0 2)) (.literal 2 arrayBytes),
      instr (some (vd 1 1)) (.literal 1 (leBytesFromNat 3 4)),
      instr (some (vd 2 0)) (.indexGet 0 1)
    ]
    (.return_ none)
  let arrBase ← emptyProgramData "Sem003ArrayOor"
  let arrCarrier ← encodeCarrierData "array-oor" {
    arrBase with types := arrTypes, callables := #[arrCallable]
  }
  let preArr : LogicalStateV1 :=
    { initialized := true, canonicalValues := ByteArray.empty }
  let arrOor := step arrCarrier preArr (inv 0 #[]) #[]
  expectRollback "array-oor" arrOor preArr fun
    | .standard .indexOutOfBounds => true
    | _ => false
  mintOk "array-oor" arrOor

  -- uninitialized / alreadyInitialized (Loader Counter lifecycle)
  let srcLife := wrap "Sem003Life" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n"
  let (cLife, dLife, u64Life) ← loadNormalize session "Sem003Life" srcLife
  let initLife ← findCallable dLife none
  let bumpLife ← findCallable dLife (some "bump")
  let initialLife ←
    match initialLogicalStateV1 cLife with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"life initial: {repr e}"
  expect (initialLife.initialized == false) "life: default uninitialized"
  let beforeInit :=
    step cLife initialLife (inv bumpLife #[refU64 u64Life 1]) #[]
  expectRollback "uninit" beforeInit initialLife fun
    | .standard .uninitialized => true
    | _ => false
  mintOk "uninit" beforeInit

  let afterInit :=
    step cLife initialLife (inv initLife #[refU64 u64Life 1]) #[]
  let postInit ←
    match afterInit with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"life init: {repr other}"
  expect (postInit.initialized == true) "life: init sets flag"
  let secondInit :=
    step cLife postInit (inv initLife #[refU64 u64Life 2]) #[]
  expectRollback "already-init" secondInit postInit fun
    | .standard .alreadyInitialized => true
    | _ => false
  mintOk "already-init" secondInit

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testOverflowRollback session
  testDeclaredEmitRollback session
  testAssertRollback session
  testAllSemanticFaults session
  testExternalRevertTrailing session
  testProgramRevertUnconsumedResponse session
  testStandardArithAndBoundReverts session
  testRemainingStandardReverts session
  IO.println "Tests.Semantic.Sem003ShapeV1: ok (engineering; not formal TST-SEM-003)"

end Tests.Semantic.Sem003ShapeV1

