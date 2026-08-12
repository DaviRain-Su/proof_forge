/-
  Tests.Semantic.OutcomeWireV1 — engineering suite for the retained Outcome
  artifact codec (EVM-first formal lighthouse packaging prerequisite).

  Not formal TASK-D2-07 / TST-SEM-002/003 completion: no EV retained binding,
  no target adapter, no formal evidence claim. Pins:
    * encode → transport decode → re-encode identity
    * digest stability over Counter Reference steps
    * fail-closed trailing / bad-magic / bad-fault-tag
-/

import ProofForgeV2.Semantic.OutcomeWireV1
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Semantic.OutcomeWireV1

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

private unsafe def loadSource
    (session : Language.Loader.ParserSession) (source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source
      "Tests/Semantic/OutcomeWireV1.lean" "Tests.CounterOutcomeWire" none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"counter corpus: load failed: {error.render}"

private def u64Bytes (n : UInt64) : ByteArray :=
  let v := n.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  let b4 := UInt8.ofNat ((v / 4294967296) % 256)
  let b5 := UInt8.ofNat ((v / 1099511627776) % 256)
  let b6 := UInt8.ofNat ((v / 281474976710656) % 256)
  let b7 := UInt8.ofNat ((v / 72057594037927936) % 256)
  (((((((ByteArray.empty.push b0).push b1).push b2).push b3).push b4).push b5).push b6).push b7

private def logicalSlot (valueBytes : ByteArray) : ByteArray :=
  (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes

private def refU64 (tid : TypeIdV1) (n : UInt64) : ReferenceValueV1 :=
  ⟨tid, u64Bytes n⟩

private def inv (id : CallableIdV1) (args : Array ReferenceValueV1) : InvocationV1 :=
  ⟨id, args, #[]⟩

private def roundTrip (label : String) (outcome : OutcomeV1) : IO Digest := do
  let artifact ← match mintReferenceOutcomeArtifactV1 outcome with
    | .ok a => pure a
    | .error e =>
        throw <| IO.userError s!"{label}: mint failed: {repr e}"
  let decoded ← match decodeReferenceOutcomeArtifactV1 artifact.canonicalBytes with
    | .ok a => pure a
    | .error e =>
        throw <| IO.userError s!"{label}: carrier decode failed: {repr e}"
  expect (decoded.canonicalBytes == artifact.canonicalBytes)
    s!"{label}: carrier bytes must be identical"
  let outcome' ← match outcomeOfArtifactV1 decoded with
    | .ok o => pure o
    | .error e =>
        throw <| IO.userError s!"{label}: outcomeOfArtifact failed: {repr e}"
  expect (outcome' == outcome)
    s!"{label}: structural Outcome round-trip mismatch"
  let again ← match mintReferenceOutcomeArtifactV1 outcome' with
    | .ok a => pure a
    | .error e =>
        throw <| IO.userError s!"{label}: remint failed: {repr e}"
  expect (again.canonicalBytes == artifact.canonicalBytes)
    s!"{label}: remint must be byte-identical"
  pure (referenceOutcomeDigestV1 artifact)

private def testLeafRoundTrips : IO Unit := do
  let logical : LogicalStateV1 := ⟨true, logicalSlot (u64Bytes 7)⟩
  let _ ← roundTrip "returned-unit" (.returned logical none #[])
  let value := refU64 0 12
  let _ ← roundTrip "returned-u64" (.returned logical (some value) #[])
  let _ ← roundTrip "reverted-overflow"
    (.reverted (.standard .arithmeticOverflow) logical)
  let _ ← roundTrip "trapped-invalidInvocation"
    (.trapped .invalidInvocation logical)
  let occ : EffectOccurrenceV1 := ⟨0, 0⟩
  let qn ← match parseQualifiedName #["Ext", "call"] with
    | .ok n => pure n
    | .error _ => throw <| IO.userError "leaf: QualifiedName"
  let effect : OrderedEffectV1 :=
    ⟨occ, .externalCall qn #[value]⟩
  let _ ← roundTrip "returned-with-effect"
    (.returned logical (some value) #[effect])
  let _ ← roundTrip "reverted-external"
    (.reverted (.externalCallReverted occ) logical)
  pure ()

private def testFailClosed : IO Unit := do
  let logical : LogicalStateV1 := ⟨false, ByteArray.empty⟩
  let artifact ← match mintReferenceOutcomeArtifactV1 (.trapped .invalidCore logical) with
    | .ok a => pure a
    | .error e => throw <| IO.userError s!"fail-closed mint: {repr e}"
  -- Trailing byte after a valid envelope.
  let trailing := artifact.canonicalBytes.push 0
  match decodeReferenceOutcomeArtifactV1 trailing with
  | .error .trailingBytes => pure ()
  | .error e =>
      throw <| IO.userError s!"fail-closed trailing: expected trailingBytes, got {repr e}"
  | .ok _ =>
      throw <| IO.userError "fail-closed trailing: unexpectedly accepted"
  -- Wrong magic.
  let wrongMagic :=
    (encodeMagicPrefix "pf.not-outcome.v1").append
      (match encodeOutcomeDataV1 (.trapped .invalidCore logical) with
       | .ok b => b
       | .error _ => ByteArray.empty)
  match decodeOutcomeEnvelopeDataV1 wrongMagic with
  | .error _ => pure ()
  | .ok _ =>
      throw <| IO.userError "fail-closed magic: unexpectedly accepted"
  -- Mutate a fault tag byte inside a trapped envelope (force nonCanonical or
  -- badScalar on carrier path).
  let mut tampered := artifact.canonicalBytes
  -- Flip last byte; carrier re-encode identity must reject.
  if tampered.size > 0 then
    let i := tampered.size - 1
    tampered := tampered.set! i (tampered.get! i <<< 1 ||| 1)
  match decodeReferenceOutcomeArtifactV1 tampered with
  | .error _ => pure ()
  | .ok _ =>
      throw <| IO.userError "fail-closed tamper: unexpectedly accepted"

private unsafe def testCounterReferenceOutcomeCorpus
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "CounterOutcomeWire" <|
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
        throw <| IO.userError s!"counter corpus: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e =>
        throw <| IO.userError s!"counter corpus: validate failed: {repr e}"
  let admitted ← match admitReferenceProgramSliceV1 carrier with
    | .ok a => pure a
    | .error e =>
        throw <| IO.userError s!"counter corpus: admit failed: {repr e}"
  let u64Tid : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e =>
        throw <| IO.userError s!"counter corpus: initial state: {repr e}"
  let afterInit :=
    stepReferenceSliceV1 admitted initial (inv 0 #[refU64 u64Tid 7]) #[]
  let dInit ← roundTrip "counter-init" afterInit
  let expectedInitPost : LogicalStateV1 := ⟨true, logicalSlot (u64Bytes 7)⟩
  let afterInc :=
    stepReferenceSliceV1 admitted expectedInitPost
      (inv 1 #[refU64 u64Tid 5]) #[]
  let dInc ← roundTrip "counter-inc" afterInc
  let expectedIncPost : LogicalStateV1 := ⟨true, logicalSlot (u64Bytes 12)⟩
  let afterView :=
    stepReferenceSliceV1 admitted expectedIncPost (inv 2 #[]) #[]
  let dView ← roundTrip "counter-view" afterView
  let maxPre : LogicalStateV1 :=
    ⟨true, logicalSlot (u64Bytes 18446744073709551615)⟩
  let overflow :=
    stepReferenceSliceV1 admitted maxPre (inv 1 #[refU64 u64Tid 1]) #[]
  let dOvf ← roundTrip "counter-overflow" overflow
  -- Digests must differ across distinct lifecycle outcomes; view of the same
  -- post-state/value is byte-identical to the increment return (same Outcome).
  expect (dInit != dInc) "counter corpus: init digest ≠ inc digest"
  expect (dInc == dView) "counter corpus: inc and view Outcomes are identical"
  expect (dView != dOvf) "counter corpus: view digest ≠ overflow digest"
  -- Determinism: repeat mint of the same overflow outcome.
  let dOvf2 ← roundTrip "counter-overflow-repeat" overflow
  expect (dOvf == dOvf2) "counter corpus: overflow digest must be stable"

unsafe def run : IO Unit := do
  testLeafRoundTrips
  testFailClosed
  let session ← Tests.Language.ParserSession.shared
  testCounterReferenceOutcomeCorpus session
  IO.println "Tests.Semantic.OutcomeWireV1: ok"

end Tests.Semantic.OutcomeWireV1
