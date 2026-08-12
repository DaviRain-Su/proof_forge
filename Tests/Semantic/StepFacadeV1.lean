/-
  Tests.Semantic.StepFacadeV1 — engineering suite for the SPEC-SEM-001-shaped
  public `step` façade over the admitted-slice reference machine.

  Not formal TASK-D2-07 / TST-SEM-002/003 / formal corpus closure. Pins:
    * Counter init/increment/view/overflow via `step` matches
      `stepReferenceSliceV1` outcomes byte-for-byte
    * garbage SemanticProgram carrier → `.trapped .invalidCore` with exact pre
-/

import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1
import Tests.Language.ParserSession

namespace Tests.Semantic.StepFacadeV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
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

private unsafe def loadSource
    (session : Language.Loader.ParserSession) (source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source
      "Tests/Semantic/StepFacadeV1.lean" "Tests.CounterStepFacade" none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"step façade: load failed: {error.render}"

private def u64Bytes (n : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity 8
  let mut v := n
  for _ in [:8] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

private def logicalSlot (valueBytes : ByteArray) : ByteArray :=
  (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes

private def refU64 (tid : TypeIdV1) (n : Nat) : ReferenceValueV1 :=
  { typeId := tid, valueBytes := u64Bytes n }

private def inv (id : CallableIdV1) (args : Array ReferenceValueV1) : InvocationV1 :=
  { callableId := id, args, context := #[] }

private def outcomeEq (a b : OutcomeV1) : Bool := a == b

/-- Counter path: public `step` matches admitted-machine outcomes. -/
private unsafe def testCounterStepMatchesSlice
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "CounterStepFacade" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← loadSource session source
  let carrier ← match normalizeProgramV1 parsed with
    | .ok c => pure c
    | .error e =>
        throw <| IO.userError s!"step façade counter: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e =>
        throw <| IO.userError s!"step façade counter: validate failed: {repr e}"
  let admitted ← match admitReferenceProgramSliceV1 carrier with
    | .ok a => pure a
    | .error e =>
        throw <| IO.userError s!"step façade counter: admit failed: {repr e}"
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e =>
        throw <| IO.userError s!"step façade counter: initial state: {repr e}"

  let afterInitSlice :=
    stepReferenceSliceV1 admitted initial (inv 0 #[refU64 u64Tid 7]) #[]
  let afterInitStep :=
    step carrier initial (inv 0 #[refU64 u64Tid 7]) #[]
  expect (outcomeEq afterInitSlice afterInitStep)
    "step façade: init outcome must match stepReferenceSliceV1"
  let expectedInitPost : LogicalStateV1 :=
    { initialized := true, canonicalValues := logicalSlot (u64Bytes 7) }

  let afterIncSlice :=
    stepReferenceSliceV1 admitted expectedInitPost
      (inv 1 #[refU64 u64Tid 5]) #[]
  let afterIncStep :=
    step carrier expectedInitPost (inv 1 #[refU64 u64Tid 5]) #[]
  expect (outcomeEq afterIncSlice afterIncStep)
    "step façade: increment outcome must match stepReferenceSliceV1"
  let expectedIncPost : LogicalStateV1 :=
    { initialized := true, canonicalValues := logicalSlot (u64Bytes 12) }

  let afterViewSlice :=
    stepReferenceSliceV1 admitted expectedIncPost (inv 2 #[]) #[]
  let afterViewStep :=
    step carrier expectedIncPost (inv 2 #[]) #[]
  expect (outcomeEq afterViewSlice afterViewStep)
    "step façade: view outcome must match stepReferenceSliceV1"

  let maxPre : LogicalStateV1 :=
    { initialized := true
      canonicalValues := logicalSlot (u64Bytes 18446744073709551615) }
  let overflowSlice :=
    stepReferenceSliceV1 admitted maxPre (inv 1 #[refU64 u64Tid 1]) #[]
  let overflowStep :=
    step carrier maxPre (inv 1 #[refU64 u64Tid 1]) #[]
  expect (outcomeEq overflowSlice overflowStep)
    "step façade: overflow outcome must match stepReferenceSliceV1"
  match overflowStep with
  | .reverted (.standard .arithmeticOverflow) st =>
      expect (st == maxPre) "step façade: overflow must keep exact pre-state"
  | other =>
      throw <| IO.userError
        s!"step façade: expected arithmeticOverflow revert, got {repr other}"

/-- Garbage carrier: admit fails → invalidCore with exact pre. -/
private def testGarbageCarrierInvalidCore : IO Unit := do
  let garbage : SemanticProgramV1 := ⟨ByteArray.empty⟩
  let pre : LogicalStateV1 :=
    { initialized := false, canonicalValues := ByteArray.mk #[1, 2, 3] }
  let invocation : InvocationV1 := { callableId := 0, args := #[], context := #[] }
  -- Nonempty responses must still be ignored on admission failure.
  let responses : ExternalResponsesV1 :=
    #[{ occurrence := ⟨0, 0⟩, disposition := .returned, returnValue? := none }]
  match admitReferenceProgramSliceV1 garbage with
  | .ok _ =>
      throw <| IO.userError "step façade garbage: expected admit error"
  | .error _ => pure ()
  let out := step garbage pre invocation responses
  match out with
  | .trapped .invalidCore st =>
      expect (st == pre) "step façade garbage: must keep exact pre-state"
  | other =>
      throw <| IO.userError
        s!"step façade garbage: expected invalidCore trap, got {repr other}"

unsafe def run : IO Unit := do
  testGarbageCarrierInvalidCore
  let session ← Tests.Language.ParserSession.shared
  testCounterStepMatchesSlice session
  IO.println "Tests.Semantic.StepFacadeV1: ok"

end Tests.Semantic.StepFacadeV1
