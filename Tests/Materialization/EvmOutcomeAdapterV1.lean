/-
  Tests.Materialization.EvmOutcomeAdapterV1 — engineering EVM-first lighthouse
  slice-2b: Reference OutcomeWire mint + honest shared-observation projection
  contract for StateCell overflow-hold.

  Proves:
    * stepReferenceSliceV1 Outcomes mint `pf.reference-outcome.v1` digests
    * returned / standard-overflow reverted constructors are retained
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

private def emptyResponses : ExternalResponsesV1 := #[]

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

private unsafe def testStateCellOutcomeDigests
    (session : Language.Loader.ParserSession) : IO Unit := do
  let absPath := System.FilePath.mk "Examples/StateCell.lean"
  let src ← IO.FS.readFile absPath
  let validated ←
    match ← session.selectProgramV1 src "Examples/StateCell.lean"
        "Examples.StateCell" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"StateCell load: {e.render}"
  let carrier ←
    match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"StateCell normalize: {repr e}"
  let data ←
    match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"StateCell validate: {repr e}"
  let admitted ←
    match admitReferenceProgramSliceV1 carrier with
    | .ok a => pure a
    | .error e => throw <| IO.userError s!"StateCell admit: {repr e}"
  let u64 ← findU64TypeId data
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

  let o0 := step initial initId #[7]
  expectReturned "deploy" o0
  let d0 ← mintDigest "deploy" o0
  expect (d0.length == 64) "deploy digest hex length"

  let post0 :=
    match o0 with
    | .returned s _ _ => s
    | _ => initial
  let o1 := step post0 incId #[5]
  expectReturned "inc" o1
  let d1 ← mintDigest "inc" o1
  expect (d0 != d1) "distinct digests for distinct Outcomes"

  let post1 :=
    match o1 with
    | .returned s _ _ => s
    | _ => post0
  let o2 := step post1 getId #[]
  expectReturned "get" o2
  let _ ← mintDigest "get" o2

  let maxN : Nat := (2 ^ 64) - 1
  let o3 := step initial initId #[maxN]
  expectReturned "deploy-max" o3
  let post3 :=
    match o3 with
    | .returned s _ _ => s
    | _ => initial
  let o4 := step post3 incId #[1]
  expectStandardOverflow "overflow" o4
  let d4 ← mintDigest "overflow" o4
  expect (d4.length == 64) "overflow digest hex length"
  -- Reverted Outcome digest must differ from the successful deploy-max digest.
  let d3 ← mintDigest "deploy-max" o3
  expect (d3 != d4) "overflow digest ≠ deploy-max digest"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testStateCellOutcomeDigests session
  IO.println "EvmOutcomeAdapterV1: ok (engineering; not formal TST-SEM/C-3)"

end Tests.Materialization.EvmOutcomeAdapterV1
