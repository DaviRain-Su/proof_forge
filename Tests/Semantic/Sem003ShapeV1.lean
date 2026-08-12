/-
  Tests.Semantic.Sem003ShapeV1 — engineering TST-SEM-003 *shape* pin.

  Public `step` + OutcomeWire. Pins overflow / declared revert / assert
  rollback: exact reason constructor, pre-state bytes unchanged, zero
  committed effects.

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

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testOverflowRollback session
  testDeclaredEmitRollback session
  testAssertRollback session
  IO.println "Tests.Semantic.Sem003ShapeV1: ok (engineering; not formal TST-SEM-003)"

end Tests.Semantic.Sem003ShapeV1
