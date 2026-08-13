/-
  Tests.Materialization.EvmOutcomeAdapterV1 — engineering EVM-first lighthouse
  slice-5 / LH-16: Reference OutcomeWire mint + honest shared-observation
  projection for StateCell / Accumulator / ArithOps / EventFlow / OwnableLike.

  Proves:
    * stepReferenceSliceV1 Outcomes mint `pf.reference-outcome.v1` digests
    * returned / standard-overflow / declared-Cap reverted constructors are retained
    * EventFlow emit is a returned Outcome with a nonempty event effect
    * OwnableLike unauthorized assert is a standard assertionFailed revert
    * remint is digest-stable; distinct Outcomes differ
    * OutcomeV1 constructor → shared status ("success"|"revert"|"trap") equals
      committed case `expectedSharedStatus` for all 28 Reference corpus steps
      (in-process only; no Anvil reason/fault/typed-bytes invention)
    * evidence-style shared observations are NOT Outcome wire (documented;
      projection helpers live in scripts/evm_corpus_v1.py)

  Not formal TASK-D2-07 / TST-SEM-002/003 / C-3 / Anvil→Outcome lossless.
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

namespace Tests.Materialization.EvmOutcomeAdapterV1

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

private def leBytesFromNat (n : Nat) (len : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity len
  let mut v := n
  for _ in [:len] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

private def u64Bytes (n : Nat) : ByteArray := leBytesFromNat n 8

private def refU64 (typeId : TypeIdV1) (n : Nat) : ReferenceValueV1 :=
  { typeId, valueBytes := u64Bytes n }

private def inv (callableId : CallableIdV1) (args : Array ReferenceValueV1) :
    InvocationV1 :=
  { callableId, args, context := #[] }

private def invCtx (callableId : CallableIdV1) (args : Array ReferenceValueV1)
    (context : Array ContextInputV1) : InvocationV1 :=
  { callableId, args, context }

/-- ADR-0025 EVM caller Principal valueBytes: `u32le(20) || address20`. -/
private def principalCaller20 (fill : UInt8) : ByteArray :=
  let body := ByteArray.mk (Array.replicate 20 fill)
  (encodeU32le 20).append body

private def findPrincipalTypeId (data : SemanticProgramDataV1) : IO TypeIdV1 :=
  match data.types.findIdx? fun t =>
      t.name.isNone && match t.shape with | .principal => true | _ => false with
  | some i => pure (UInt32.ofNat i)
  | none => throw <| IO.userError "missing anonymous Principal TypeId"

private def emptyResponses : ExternalResponsesV1 := #[]

/-- LH-16: project only the OutcomeV1 constructor to shared corpus status.
    Does not invent Anvil reason/fault/typed valueBytes. -/
private def sharedStatusOf (outcome : OutcomeV1) : String :=
  match outcome with
  | .returned _ _ _ => "success"
  | .reverted _ _ => "revert"
  | .trapped _ _ => "trap"

/-- Hardcoded from testdata/evm-corpus/v1/cases/*.expectedSharedStatus (read-only). -/
private def expectedStateCellStatuses : Array String :=
  #["success", "success", "success", "success", "revert", "success"]

private def expectedAccumulatorStatuses : Array String :=
  #["success", "success", "success", "success", "revert", "success"]

private def expectedArithOpsStatuses : Array String :=
  #["success", "success", "success", "success", "success", "revert"]

private def expectedEventFlowStatuses : Array String :=
  #["success", "success", "success", "revert", "success"]

private def expectedOwnableLikeStatuses : Array String :=
  #["success", "success", "success", "revert", "success"]

private def expectSharedStatus
    (label : String) (outcome : OutcomeV1) (want : String) : IO Unit := do
  let got := sharedStatusOf outcome
  expect (got == want)
    s!"{label}: sharedStatus want={want} got={got}"

private def digestHex (d : Digest) : IO String :=
  match renderDigest d with
  | .ok s =>
      match s.dropPrefix? "sha256:" with
      | some rest => pure rest.toString
      | none => pure s
  | .error e => throw <| IO.userError e

private def findU64TypeId (data : SemanticProgramDataV1) : IO TypeIdV1 :=
  match data.types.findIdx? fun t =>
      t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
  | some i => pure (UInt32.ofNat i)
  | none => throw <| IO.userError "missing anonymous UInt64 TypeId"

private def findCallableId (data : SemanticProgramDataV1) (name : Option String) :
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

private def mintDigest (label : String) (outcome : OutcomeV1) : IO String := do
  let artifact ← match mintReferenceOutcomeArtifactV1 outcome with
    | .ok a => pure a
    | .error e => throw <| IO.userError s!"{label}: mint: {repr e}"
  match decodeReferenceOutcomeArtifactV1 artifact.canonicalBytes with
  | .ok again =>
      expect (again.canonicalBytes == artifact.canonicalBytes)
        s!"{label}: carrier identity"
  | .error e =>
      throw <| IO.userError s!"{label}: carrier decode: {repr e}"
  digestHex (referenceOutcomeDigestV1 artifact)

/-- Remint the same Outcome twice; digests must be byte-identical. -/
private def expectRemintStable (label : String) (outcome : OutcomeV1) : IO String := do
  let d1 ← mintDigest s!"{label}/a" outcome
  let d2 ← mintDigest s!"{label}/b" outcome
  expect (d1 == d2) s!"{label}: remint digests differ"
  expect (d1.length == 64) s!"{label}: digest hex length"
  pure d1

/-- Structural tag check without claiming observation can rebuild reason/value. -/
private def expectReturned (label : String) (outcome : OutcomeV1) : IO Unit :=
  match outcome with
  | .returned _ _ _ => pure ()
  | .reverted _ _ => throw <| IO.userError s!"{label}: expected returned"
  | .trapped _ _ => throw <| IO.userError s!"{label}: expected returned"

private def expectStandardOverflow (label : String) (outcome : OutcomeV1) : IO Unit :=
  match outcome with
  | .reverted (.standard .arithmeticOverflow) _ => pure ()
  | .reverted reason _ =>
      throw <| IO.userError s!"{label}: expected arithmeticOverflow, got {repr reason}"
  | .returned _ _ _ => throw <| IO.userError s!"{label}: expected reverted"
  | .trapped _ _ => throw <| IO.userError s!"{label}: expected reverted"

private def expectReturnedWithEvent (label : String) (outcome : OutcomeV1) : IO Unit :=
  match outcome with
  | .returned _ _ effects =>
      match effects.toList with
      | [] => throw <| IO.userError s!"{label}: expected nonempty event effects"
      | e :: _ =>
          match e.payload with
          | .event _ _ => pure ()
          | .externalCall _ _ =>
              throw <| IO.userError s!"{label}: expected event payload"
          | .schedule _ _ =>
              throw <| IO.userError s!"{label}: expected event payload"
  | .reverted _ _ => throw <| IO.userError s!"{label}: expected returned"
  | .trapped _ _ => throw <| IO.userError s!"{label}: expected returned"

private def expectDeclaredRevert (label : String) (outcome : OutcomeV1) : IO Unit :=
  match outcome with
  | .reverted (.declared _ args) _ =>
      unless args.size == 1 do
        throw <| IO.userError s!"{label}: declared Cap arity, got {args.size}"
  | .reverted reason _ =>
      throw <| IO.userError s!"{label}: expected declared revert, got {repr reason}"
  | .returned _ _ _ => throw <| IO.userError s!"{label}: expected reverted"
  | .trapped _ _ => throw <| IO.userError s!"{label}: expected reverted"

private def expectAssertionFailed (label : String) (outcome : OutcomeV1) : IO Unit :=
  match outcome with
  | .reverted (.standard .assertionFailed) _ => pure ()
  | .reverted reason _ =>
      throw <| IO.userError s!"{label}: expected assertionFailed, got {repr reason}"
  | .returned _ _ _ => throw <| IO.userError s!"{label}: expected reverted"
  | .trapped _ _ => throw <| IO.userError s!"{label}: expected reverted"

private def postState (outcome : OutcomeV1) : LogicalStateV1 :=
  match outcome with
  | .returned s _ _ => s
  | .reverted _ s => s
  | .trapped _ s => s

private unsafe def loadAdmit
    (session : Language.Loader.ParserSession)
    (relPath moduleName label : String) :
    IO (SemanticProgramV1 × SemanticProgramDataV1 × AdmittedReferenceSliceV1 ×
        TypeIdV1) := do
  let absPath := System.FilePath.mk relPath
  let src ← IO.FS.readFile absPath
  let validated ←
    match ← session.selectProgramV1 src relPath moduleName none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"{label} load: {e.render}"
  let carrier ←
    match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"{label} normalize: {repr e}"
  let data ←
    match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"{label} validate: {repr e}"
  let admitted ←
    match admitReferenceProgramSliceV1 carrier with
    | .ok a => pure a
    | .error e => throw <| IO.userError s!"{label} admit: {repr e}"
  let u64 ← findU64TypeId data
  pure (carrier, data, admitted, u64)

private unsafe def testStateCellOutcomeDigests
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (carrier, data, admitted, u64) ←
    loadAdmit session "Examples/StateCell.lean" "Examples.StateCell" "StateCell"
  let initId ← findCallableId data none
  let incId ← findCallableId data (some "increment")
  let getId ← findCallableId data (some "get")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"StateCell initial: {repr e}"
  let step (pre : LogicalStateV1) (cid : CallableIdV1) (args : Array Nat) :
      OutcomeV1 :=
    let refArgs := args.map (fun n => refU64 u64 n)
    stepReferenceSliceV1 admitted pre (inv cid refArgs) emptyResponses

  let want := expectedStateCellStatuses
  expect (want.size == 6) "StateCell: expected 6 corpus statuses"
  let o0 := step initial initId #[7]
  expectReturned "StateCell/deploy" o0
  expectSharedStatus "StateCell/0" o0 want[0]!
  let d0 ← expectRemintStable "StateCell/deploy" o0

  let post0 := postState o0
  let o1 := step post0 incId #[5]
  expectReturned "StateCell/inc" o1
  expectSharedStatus "StateCell/1" o1 want[1]!
  let d1 ← expectRemintStable "StateCell/inc" o1
  expect (d0 != d1) "StateCell: distinct digests for distinct Outcomes"

  let post1 := postState o1
  let o2 := step post1 getId #[]
  expectReturned "StateCell/get" o2
  expectSharedStatus "StateCell/2" o2 want[2]!
  let _ ← expectRemintStable "StateCell/get" o2

  let maxN : Nat := (2 ^ 64) - 1
  let o3 := step initial initId #[maxN]
  expectReturned "StateCell/deploy-max" o3
  expectSharedStatus "StateCell/3" o3 want[3]!
  let d3 ← expectRemintStable "StateCell/deploy-max" o3
  let post3 := postState o3
  let o4 := step post3 incId #[1]
  expectStandardOverflow "StateCell/overflow" o4
  expectSharedStatus "StateCell/4" o4 want[4]!
  let d4 ← expectRemintStable "StateCell/overflow" o4
  expect (d3 != d4) "StateCell: overflow digest ≠ deploy-max digest"
  -- Corpus step 5: view after overflow hold (pre unchanged).
  let o5 := step (postState o4) getId #[]
  expectReturned "StateCell/get-after-overflow" o5
  expectSharedStatus "StateCell/5" o5 want[5]!
  let _ ← expectRemintStable "StateCell/get-after-overflow" o5

private unsafe def testAccumulatorOutcomeDigests
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (carrier, data, admitted, u64) ←
    loadAdmit session "Examples/Accumulator.lean" "Examples.Accumulator"
      "Accumulator"
  let initId ← findCallableId data none
  let addId ← findCallableId data (some "add")
  let curId ← findCallableId data (some "current")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"Accumulator initial: {repr e}"
  let step (pre : LogicalStateV1) (cid : CallableIdV1) (args : Array Nat) :
      OutcomeV1 :=
    let refArgs := args.map (fun n => refU64 u64 n)
    stepReferenceSliceV1 admitted pre (inv cid refArgs) emptyResponses

  let want := expectedAccumulatorStatuses
  expect (want.size == 6) "Accumulator: expected 6 corpus statuses"
  let o0 := step initial initId #[7]
  expectReturned "Accumulator/deploy" o0
  expectSharedStatus "Accumulator/0" o0 want[0]!
  let d0 ← expectRemintStable "Accumulator/deploy" o0

  let post0 := postState o0
  let o1 := step post0 addId #[5]
  expectReturned "Accumulator/add" o1
  expectSharedStatus "Accumulator/1" o1 want[1]!
  let d1 ← expectRemintStable "Accumulator/add" o1
  expect (d0 != d1) "Accumulator: distinct digests for distinct Outcomes"

  let post1 := postState o1
  let o2 := step post1 curId #[]
  expectReturned "Accumulator/current" o2
  expectSharedStatus "Accumulator/2" o2 want[2]!
  let _ ← expectRemintStable "Accumulator/current" o2

  let maxN : Nat := (2 ^ 64) - 1
  let o3 := step initial initId #[maxN]
  expectReturned "Accumulator/deploy-max" o3
  expectSharedStatus "Accumulator/3" o3 want[3]!
  let d3 ← expectRemintStable "Accumulator/deploy-max" o3
  let post3 := postState o3
  let o4 := step post3 addId #[1]
  expectStandardOverflow "Accumulator/overflow" o4
  expectSharedStatus "Accumulator/4" o4 want[4]!
  let d4 ← expectRemintStable "Accumulator/overflow" o4
  expect (d3 != d4) "Accumulator: overflow digest ≠ deploy-max digest"
  let o5 := step (postState o4) curId #[]
  expectReturned "Accumulator/current-after-overflow" o5
  expectSharedStatus "Accumulator/5" o5 want[5]!
  let _ ← expectRemintStable "Accumulator/current-after-overflow" o5

private unsafe def testArithOpsOutcomeDigests
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (carrier, data, admitted, u64) ←
    loadAdmit session "testdata/valid/ArithOps.lean" "ArithOps" "ArithOps"
  let initId ← findCallableId data none
  let scaleId ← findCallableId data (some "scale")
  let bitsId ← findCallableId data (some "bits")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"ArithOps initial: {repr e}"
  let step (pre : LogicalStateV1) (cid : CallableIdV1) (args : Array Nat) :
      OutcomeV1 :=
    let refArgs := args.map (fun n => refU64 u64 n)
    stepReferenceSliceV1 admitted pre (inv cid refArgs) emptyResponses

  let want := expectedArithOpsStatuses
  expect (want.size == 6) "ArithOps: expected 6 corpus statuses"
  let o0 := step initial initId #[7]
  expectReturned "ArithOps/deploy" o0
  expectSharedStatus "ArithOps/0" o0 want[0]!
  let post0 := postState o0

  -- Returned success with a non-Unit return value (bits).
  let o1 := step post0 bitsId #[0]
  expectReturned "ArithOps/bits0" o1
  expectSharedStatus "ArithOps/1" o1 want[1]!
  let dBits ← expectRemintStable "ArithOps/bits0" o1

  let post1 := postState o1
  let o2 := step post1 bitsId #[5]
  expectReturned "ArithOps/bits5" o2
  expectSharedStatus "ArithOps/2" o2 want[2]!
  let dBits5 ← expectRemintStable "ArithOps/bits5" o2
  expect (dBits != dBits5) "ArithOps: distinct returned digests differ"

  let post2 := postState o2
  let o3 := step post2 scaleId #[3, 2]
  expectReturned "ArithOps/scale" o3
  expectSharedStatus "ArithOps/3" o3 want[3]!
  let dScale ← expectRemintStable "ArithOps/scale" o3
  expect (dScale != dBits) "ArithOps: scale digest ≠ bits digest"

  let maxN : Nat := (2 ^ 64) - 1
  let o4 := step initial initId #[maxN]
  expectReturned "ArithOps/deploy-max" o4
  expectSharedStatus "ArithOps/4" o4 want[4]!
  let post4 := postState o4
  let o5 := step post4 scaleId #[2, 1]
  expectStandardOverflow "ArithOps/scale-overflow" o5
  expectSharedStatus "ArithOps/5" o5 want[5]!
  let dOverflow ← expectRemintStable "ArithOps/scale-overflow" o5
  expect (dOverflow != dScale)
    "ArithOps: overflow digest ≠ successful scale digest"
  expect (dOverflow != dBits)
    "ArithOps: overflow digest ≠ returned bits digest"

private unsafe def testEventFlowOutcomeDigests
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (carrier, data, admitted, u64) ←
    loadAdmit session "testdata/evm-corpus/v1/programs/EventFlow.lean"
      "EventFlow" "EventFlow"
  let initId ← findCallableId data none
  let bumpId ← findCallableId data (some "bump")
  let getId ← findCallableId data (some "get")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"EventFlow initial: {repr e}"
  let step (pre : LogicalStateV1) (cid : CallableIdV1) (args : Array Nat) :
      OutcomeV1 :=
    let refArgs := args.map (fun n => refU64 u64 n)
    stepReferenceSliceV1 admitted pre (inv cid refArgs) emptyResponses

  let want := expectedEventFlowStatuses
  expect (want.size == 5) "EventFlow: expected 5 corpus statuses"
  let o0 := step initial initId #[0]
  expectReturned "EventFlow/deploy" o0
  expectSharedStatus "EventFlow/0" o0 want[0]!
  let d0 ← expectRemintStable "EventFlow/deploy" o0
  let post0 := postState o0

  let o1 := step post0 bumpId #[5]
  expectReturnedWithEvent "EventFlow/bump-emit" o1
  expectSharedStatus "EventFlow/1" o1 want[1]!
  let d1 ← expectRemintStable "EventFlow/bump-emit" o1
  expect (d0 != d1) "EventFlow: emit digest ≠ deploy digest"

  let post1 := postState o1
  let o2 := step post1 getId #[]
  expectReturned "EventFlow/get" o2
  expectSharedStatus "EventFlow/2" o2 want[2]!
  let d2 ← expectRemintStable "EventFlow/get" o2
  expect (d2 != d1) "EventFlow: view digest ≠ emit digest"

  let post2 := postState o2
  let o3 := step post2 bumpId #[3]
  expectDeclaredRevert "EventFlow/cap" o3
  expectSharedStatus "EventFlow/3" o3 want[3]!
  let d3 ← expectRemintStable "EventFlow/cap" o3
  expect (d3 != d1) "EventFlow: declared Cap digest ≠ emit digest"
  expect (d3 != d0) "EventFlow: declared Cap digest ≠ deploy digest"
  let o4 := step (postState o3) getId #[]
  expectReturned "EventFlow/get-after-cap" o4
  expectSharedStatus "EventFlow/4" o4 want[4]!
  let _ ← expectRemintStable "EventFlow/get-after-cap" o4

private unsafe def testOwnableLikeOutcomeDigests
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (carrier, data, admitted, u64) ←
    loadAdmit session "testdata/evm-corpus/v1/programs/OwnableLike.lean"
      "Tests.EvmCorpus.OwnableLike" "OwnableLike"
  let initId ← findCallableId data none
  let setId ← findCallableId data (some "setValue")
  let getId ← findCallableId data (some "getValue")
  let pTid ← findPrincipalTypeId data
  let ownerVal : ReferenceValueV1 :=
    { typeId := pTid, valueBytes := principalCaller20 0x11 }
  let strangerVal : ReferenceValueV1 :=
    { typeId := pTid, valueBytes := principalCaller20 0x22 }
  let key := callerContextKeyV1
  let ownerCtx : Array ContextInputV1 := #[{ key, value := ownerVal }]
  let strangerCtx : Array ContextInputV1 := #[{ key, value := strangerVal }]
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"OwnableLike initial: {repr e}"
  let want := expectedOwnableLikeStatuses
  expect (want.size == 5) "OwnableLike: expected 5 corpus statuses"
  let o0 := stepReferenceSliceV1 admitted initial
    (invCtx initId #[] ownerCtx) emptyResponses
  expectReturned "OwnableLike/deploy" o0
  expectSharedStatus "OwnableLike/0" o0 want[0]!
  let d0 ← expectRemintStable "OwnableLike/deploy" o0
  let post0 := postState o0
  let o1 := stepReferenceSliceV1 admitted post0
    (invCtx setId #[refU64 u64 42] ownerCtx) emptyResponses
  expectReturned "OwnableLike/set-owner" o1
  expectSharedStatus "OwnableLike/1" o1 want[1]!
  let d1 ← expectRemintStable "OwnableLike/set-owner" o1
  expect (d0 != d1) "OwnableLike: owner-set digest ≠ deploy digest"
  let post1 := postState o1
  let o2 := stepReferenceSliceV1 admitted post1
    (invCtx getId #[] #[]) emptyResponses
  expectReturned "OwnableLike/get" o2
  expectSharedStatus "OwnableLike/2" o2 want[2]!
  let _ ← expectRemintStable "OwnableLike/get" o2
  let o3 := stepReferenceSliceV1 admitted (postState o2)
    (invCtx setId #[refU64 u64 7] strangerCtx) emptyResponses
  expectAssertionFailed "OwnableLike/stranger" o3
  expectSharedStatus "OwnableLike/3" o3 want[3]!
  let d3 ← expectRemintStable "OwnableLike/stranger" o3
  expect (d3 != d1) "OwnableLike: assertionFailed digest ≠ owner-set digest"
  let o4 := stepReferenceSliceV1 admitted (postState o3)
    (invCtx getId #[] #[]) emptyResponses
  expectReturned "OwnableLike/get-after-stranger" o4
  expectSharedStatus "OwnableLike/4" o4 want[4]!
  let _ ← expectRemintStable "OwnableLike/get-after-stranger" o4

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testStateCellOutcomeDigests session
  testAccumulatorOutcomeDigests session
  testArithOpsOutcomeDigests session
  testEventFlowOutcomeDigests session
  testOwnableLikeOutcomeDigests session
  IO.println "EvmOutcomeAdapterV1: ok (engineering; not formal TST-SEM/C-3)"

end Tests.Materialization.EvmOutcomeAdapterV1
