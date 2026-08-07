import ProofForgeV2.Language.ProgramElaborationV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1

open ProofForgeV2.Language
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

namespace Tests.Language.InlineProofAuthoringV1

program Proofed where
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using ProofedProof.safe

theorem ProofedProof.safe : Proofed.Proof.safe := by
  exact Proofed.Proof.generatedSafeV1

#check Proofed.Proof.subjectProgramV1
#check Proofed.Proof.safe

example : Proofed.Proof.safe =
    InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0 := rfl

#check Proofed.Proof.subjectBytesV1
-- Name/module-parameterized certificate AST emitted for the literal-true
-- simple-closure family (foundation for product-positive cert generation).
#check Proofed.Proof.simpleClosureParamsV1
#check Proofed.Proof.simpleClosureDataV1

-- B-SC-ELAB-THM close: concrete Legal witness, compatibility bridge, and
-- premise-free generated theorem consumed by the ordinary adjacent theorem.
#check Proofed.Proof.simpleClosureQnTailLegalV1
#check Proofed.Proof.simpleClosureParamsLegalV1
#check Proofed.Proof.generatedSafeV1Name
#check Proofed.Proof.generatedSafeV1_of_wireTrace
#check Proofed.Proof.generatedSafeV1
#check ProofedProof.safe

example : Proofed.Proof.generatedSafeV1Name = "generatedSafeV1" := rfl

example : Proofed.Proof.safe := Proofed.Proof.generatedSafeV1
example : Proofed.Proof.safe := ProofedProof.safe

example : generatedSimpleClosureTheoremNameV1 "safe" = "generatedSafeV1" := rfl
example : generatedSimpleClosureTheoremNameV1 "balance" = "generatedBalanceV1" := rfl
example : generatedSimpleClosureTheoremBridgeNameV1 "safe" =
    "generatedSafeV1_of_wireTrace" := rfl
example : generatedSimpleClosureTheoremNameDefV1 "safe" =
    "generatedSafeV1Name" := rfl

program PreservingSurface where
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe preserving using PreservingSurfaceProof.safe

#check PreservingSurface.Proof.subjectProgramV1
#check PreservingSurface.ProofPreserving.safe

example : PreservingSurface.ProofPreserving.safe =
    ProofForgeV2.Semantic.PreservationABI.PreservationTheoremV1
      PreservingSurface.Proof.subjectProgramV1 0 := rfl

program DualKindSurface where
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using DualKindSurfaceProof.holds
  proof safe preserving using DualKindSurfaceProof.keeps

#check DualKindSurface.Proof.subjectProgramV1
#check DualKindSurface.Proof.safe
#check DualKindSurface.ProofPreserving.safe
#check DualKindSurface.Proof.generatedSafeV1

example : DualKindSurface.ProofPreserving.safe =
    ProofForgeV2.Semantic.PreservationABI.PreservationTheoremV1
      DualKindSurface.Proof.subjectProgramV1 0 := rfl

/-- Bridge has the exact product Prop-alias conclusion under a wire-trace
    premise (no free hyps beyond `t`). -/
example :
    (Proofed.Proof.generatedSafeV1_of_wireTrace :
      SimpleClosureWireTraceV1
          Proofed.Proof.simpleClosureParamsV1
          Proofed.Proof.subjectBytesV1 →
        Proofed.Proof.safe) =
      Proofed.Proof.generatedSafeV1_of_wireTrace :=
  rfl

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let subject := Proofed.Proof.subjectProgramV1
  expect (subject.canonicalBytes.size > 0)
    "inline subjectProgramV1 must embed non-empty product bytes (transparent spine)"
  expect (Proofed.Proof.subjectBytesV1.size == subject.canonicalBytes.size)
    "subjectBytesV1 matches subjectProgramV1 carrier"
  expect (Proofed.Proof.generatedSafeV1Name == "generatedSafeV1")
    "generated theorem product name for inv safe"
  expect (generatedSimpleClosureTheoremNameV1 "safe" ==
      Proofed.Proof.generatedSafeV1Name)
    "naming helper matches elaborator Name def"
  match validateSemanticProgramV1 subject with
  | .error error =>
      throw <| IO.userError s!"generated inline proof subject invalid: {repr error}"
  | .ok data =>
      expect (data.invariants.size == 1) "generated invariant count"
      let invariant ← match data.invariants[0]? with
        | some value => pure value
        | none => throw <| IO.userError "generated invariant missing"
      expect (invariant.name == "safe") "generated invariant name"
      expect (invariant.id == 0) "generated invariant ordinal"
      let callable ← match data.callables[invariant.callableId.toNat]? with
        | some value => pure value
        | none => throw <| IO.userError "generated invariant callable missing"
      expect (callable.kind == CallableKindV1.invariant)
        "generated invariant callable kind"
      expect (callable.invariantSteps == some 3) "literal-true invariant fuel is 3"
      -- Happy path: ordinal 0 returns true on initialized empty state.
      let st ← match initialLogicalStateV1 subject with
        | .ok s => pure { s with initialized := true }
        | .error e => throw <| IO.userError s!"initial state: {repr e}"
      expect (stateConformsBoolV1 subject st) "conforming empty state"
      match evalInvariantV1 subject 0 st with
      | .returnedTrue => pure ()
      | other => throw <| IO.userError s!"safe ordinal must return true: {repr other}"
      -- Byte mutation of the generated subject fails closed.
      let mutated :=
        Id.run do
          let mut out := subject.canonicalBytes
          let b0 := out.get! 0
          out := out.set! 0 (b0 <<< 1 ||| 1)
          pure out
      expect ((subject.canonicalBytes == mutated) == false) "subject mutation changes bytes"
      match validateSemanticProgramV1 ⟨mutated⟩ with
      | .ok _ => throw <| IO.userError "mutated inline subject must not validate"
      | .error _ => pure ()
      -- Ordinal mutation: OOR traps.
      match evalInvariantV1 subject 1 st with
      | .trapped => pure ()
      | other => throw <| IO.userError s!"OOR ordinal must trap: {repr other}"
  IO.println "Tests.Language.InlineProofAuthoringV1: ok"

end Tests.Language.InlineProofAuthoringV1
