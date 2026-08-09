import ProofForgeV2.Language.ProgramElaborationV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1

open ProofForgeV2.Language
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1
open Lean
open Lean.Elab.Command

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
#check Proofed.Model.State
#check Proofed.Model.encodeState
#check Proofed.Model.decodeState
#check Proofed.Model.decode_encode
#check Proofed.Model.encode_injective_of_eq_ok
#check Proofed.Model.decode_existsUnique_of_conforms
#check Proofed.Model.encode_decode_of_conforms
#check Proofed.Model.conforms_of_encode
#check Proofed.Model.conforms_iff_exists_encode

example : Proofed.Proof.safe =
    InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0 := rfl

example : Proofed.Model.State = Unit := rfl

example : Proofed.Model.encodeState () = .ok {
    initialized := true
    canonicalValues := ByteArray.empty
  } := rfl

example
    (hvalidate :
      validateSemanticProgramV1 Proofed.Proof.subjectProgramV1 =
        .ok Proofed.Proof.subjectDataV1) :
    ∃ typedState : Proofed.Model.State,
      Proofed.Model.decodeState {
        initialized := true
        canonicalValues := ByteArray.empty
      } = .ok typedState ∧
      Proofed.Model.encodeState typedState = .ok {
        initialized := true
        canonicalValues := ByteArray.empty
      } := by
  apply Proofed.Model.encode_decode_of_conforms _ hvalidate
  apply Proofed.Model.conforms_of_encode () _ hvalidate
  rfl

#check Proofed.Proof.subjectBytesV1
-- Structured subject data (mig-a3-elab): preferred author surface; encode of
-- this spine must recover product subject bytes (runtime check in `run`).
#check Proofed.Proof.subjectDataV1
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

program TypedStateSurface where
  state count : UInt64
  state total : UInt64
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using TypedStateSurfaceProof.safe

#check TypedStateSurface.Model.State
#check TypedStateSurface.Model.State.count
#check TypedStateSurface.Model.State.total
#check TypedStateSurface.Model.encodeState
#check TypedStateSurface.Model.decodeState
#check TypedStateSurface.Model.decode_encode
#check TypedStateSurface.Model.encode_injective_of_eq_ok
#check TypedStateSurface.Model.decode_existsUnique_of_conforms
#check TypedStateSurface.Model.encode_decode_of_conforms
#check TypedStateSurface.Model.conforms_of_encode
#check TypedStateSurface.Model.conforms_iff_exists_encode

private def typedStateSampleV1 : TypedStateSurface.Model.State := {
  count := 7
  total := 11
}

private def typedStateLogicalV1 : LogicalStateV1 := {
  initialized := true
  canonicalValues :=
    encodeU32le 8 ++ encodeU64le 7 ++ encodeU32le 8 ++ encodeU64le 11
}

/-- Generated fields preserve StateId/source order in the production wire
    layout; no contract-specific codec participates in this equality. -/
example : TypedStateSurface.Model.encodeState typedStateSampleV1 =
    .ok typedStateLogicalV1 := by
  rfl

/-- The generated author-facing theorem is the generic production-codec
    inverse specialized to this exact lowered subject. -/
example : TypedStateSurface.Model.decodeState typedStateLogicalV1 =
    .ok typedStateSampleV1 := by
  apply TypedStateSurface.Model.decode_encode
  rfl

example
    (hvalidate :
      validateSemanticProgramV1 TypedStateSurface.Proof.subjectProgramV1 =
        .ok TypedStateSurface.Proof.subjectDataV1) :
    StateConformsV1 TypedStateSurface.Proof.subjectProgramV1 typedStateLogicalV1 := by
  apply TypedStateSurface.Model.conforms_of_encode typedStateSampleV1
    typedStateLogicalV1 hvalidate
  rfl

/-- Production conformance is sufficient for existence and uniqueness of the
    generated typed projection; no contract-local decoder premise is needed. -/
example
    (hvalidate :
      validateSemanticProgramV1 TypedStateSurface.Proof.subjectProgramV1 =
        .ok TypedStateSurface.Proof.subjectDataV1) :
    ∃ typedState : TypedStateSurface.Model.State,
      TypedStateSurface.Model.decodeState typedStateLogicalV1 = .ok typedState ∧
        ∀ other : TypedStateSurface.Model.State,
          TypedStateSurface.Model.decodeState typedStateLogicalV1 = .ok other →
            typedState = other := by
  apply TypedStateSurface.Model.decode_existsUnique_of_conforms
    typedStateLogicalV1 hvalidate
  apply TypedStateSurface.Model.conforms_of_encode typedStateSampleV1
    typedStateLogicalV1 hvalidate
  rfl

/-- Production conformance also selects a typed projection whose generated
    encoding is byte-for-byte the original production logical state. -/
example
    (hvalidate :
      validateSemanticProgramV1 TypedStateSurface.Proof.subjectProgramV1 =
        .ok TypedStateSurface.Proof.subjectDataV1) :
    ∃ typedState : TypedStateSurface.Model.State,
      TypedStateSurface.Model.decodeState typedStateLogicalV1 = .ok typedState ∧
        TypedStateSurface.Model.encodeState typedState =
          .ok typedStateLogicalV1 := by
  apply TypedStateSurface.Model.encode_decode_of_conforms
    typedStateLogicalV1 hvalidate
  apply TypedStateSurface.Model.conforms_of_encode typedStateSampleV1
    typedStateLogicalV1 hvalidate
  rfl

example
    (hvalidate :
      validateSemanticProgramV1 TypedStateSurface.Proof.subjectProgramV1 =
        .ok TypedStateSurface.Proof.subjectDataV1) :
    StateConformsV1 TypedStateSurface.Proof.subjectProgramV1 typedStateLogicalV1 ↔
      ∃ typedState : TypedStateSurface.Model.State,
        TypedStateSurface.Model.encodeState typedState =
          .ok typedStateLogicalV1 :=
  TypedStateSurface.Model.conforms_iff_exists_encode
    typedStateLogicalV1 hvalidate

private def typedStateUninitializedV1 : LogicalStateV1 :=
  { typedStateLogicalV1 with initialized := false }

example : TypedStateSurface.Model.decodeState typedStateUninitializedV1 =
    .error .nonCanonical := by
  rfl

program TypedCallableSurface where
  state count : UInt64
  entry add(delta : UInt64) : UInt64 do
    count := count + delta
    return count
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using TypedCallableSurfaceProof.safe

#check TypedCallableSurface.Model.ReferenceSubject
#check TypedCallableSurface.Model.admitReferenceSubject
#check TypedCallableSurface.Model.Outcome
#check TypedCallableSurface.Model.add.invocation
#check TypedCallableSurface.Model.add.Outcome
#check TypedCallableSurface.Model.add.Transition
#check TypedCallableSurface.Model.add.outcome_unique
#check TypedCallableSurface.Model.alive.invocation
#check TypedCallableSurface.Model.alive.Outcome
#check TypedCallableSurface.Model.alive.Transition
#check TypedCallableSurface.Model.alive.outcome_unique

/-- Typed arguments are encoded as canonical Reference values using the exact
    callable and TypeIds from the generated semantic subject. -/
example : TypedCallableSurface.Model.add.invocation 3 #[] = ({
    callableId := 0
    args := #[{ typeId := 0, valueBytes := encodeU64le 3 }]
    context := #[]
  } : InvocationV1) := rfl

example : TypedCallableSurface.Model.alive.invocation #[] = ({
    callableId := 1
    args := #[]
    context := #[]
  } : InvocationV1) := rfl

/-- The generated relation is only a typed view over the generic relation. It
    retains context, responses, and vault instead of silently fixing them. -/
example
    (subject : TypedCallableSurface.Model.ReferenceSubject)
    (pre : TypedCallableSurface.Model.State)
    (delta : UInt64)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedCallableSurface.Model.add.Outcome) :
    TypedCallableSurface.Model.add.Transition
        subject pre delta context responses vault outcome =
      TypedCallableRelationV1
        TypedCallableSurface.Model.encodeState
        (fun value : UInt64 => some {
          typeId := 0
          valueBytes := encodeU64le value
        })
        subject pre
        (TypedCallableSurface.Model.add.invocation delta context)
        responses vault outcome := rfl

/-- Bool callable results retain their exact lowered TypeId and use the
    production Bool value codec; this does not add Bool logical-state support. -/
example
    (subject : TypedCallableSurface.Model.ReferenceSubject)
    (pre : TypedCallableSurface.Model.State)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedCallableSurface.Model.alive.Outcome) :
    TypedCallableSurface.Model.alive.Transition
        subject pre context responses vault outcome =
      TypedCallableRelationV1
        TypedCallableSurface.Model.encodeState
        (fun value : Bool => some {
          typeId := 1
          valueBytes := encodeBool value
        })
        subject pre
        (TypedCallableSurface.Model.alive.invocation context)
        responses vault outcome := rfl

/-- Fixed typed inputs cannot relate to two distinct typed outcomes. The
    generated theorem combines the single Reference step with state/result
    codec injectivity; it does not execute the callable. -/
example
    (subject : TypedCallableSurface.Model.ReferenceSubject)
    (pre : TypedCallableSurface.Model.State)
    (delta : UInt64)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (left right : TypedCallableSurface.Model.add.Outcome)
    (hleft : TypedCallableSurface.Model.add.Transition
      subject pre delta context responses vault left)
    (hright : TypedCallableSurface.Model.add.Transition
      subject pre delta context responses vault right) :
    left = right :=
  TypedCallableSurface.Model.add.outcome_unique
    subject pre delta context responses vault left right hleft hright

/-- Expanding the sole generic relation exposes the exact production step and
    all three canonical outcomes; there is no generated evaluator. -/
example
    {State Result : Type}
    {semanticProgram : SemanticProgramV1}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (encodeResult : Result → Option ReferenceValueV1)
    (subject : AdmittedSubjectV1 semanticProgram)
    (pre : State)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedOutcomeV1 State Result) :
    TypedCallableRelationV1 encodeState encodeResult subject pre invocation
        responses vault outcome ↔
      ∃ logicalPre,
        encodeState pre = .ok logicalPre ∧
          match outcome with
          | .returned post value effects =>
              ∃ logicalPost,
                encodeState post = .ok logicalPost ∧
                  stepReferenceSliceV1 subject.admitted logicalPre invocation
                      responses vault =
                    .returned logicalPost (encodeResult value) effects
          | .reverted reason =>
              stepReferenceSliceV1 subject.admitted logicalPre invocation
                  responses vault =
                .reverted reason logicalPre
          | .trapped fault =>
              stepReferenceSliceV1 subject.admitted logicalPre invocation
                  responses vault =
                .trapped fault logicalPre :=
  by
    unfold TypedCallableRelationV1
    rfl

/- Unit is represented by `none` on the canonical Reference result surface.
    A declared-revert entry supplies an accepted lowering path for exercising
    the generated Unit relation without inventing a Unit-valued return literal. -/
program TypedUnitCallableSurface where
  state count : UInt64
  error Nope
  entry clear() do
    revert Nope()
  invariant safe : true
  proof safe using TypedUnitCallableSurfaceProof.safe

#check TypedUnitCallableSurface.Model.clear.invocation
#check TypedUnitCallableSurface.Model.clear.Outcome
#check TypedUnitCallableSurface.Model.clear.Transition
#check TypedUnitCallableSurface.Model.clear.outcome_unique

example : TypedUnitCallableSurface.Model.clear.Outcome =
    TypedOutcomeV1 TypedUnitCallableSurface.Model.State Unit := rfl

program UnsupportedCallableModelSurface where
  state count : UInt64
  entry addWide(delta : UInt128) : UInt64 do
    return count
  view alive() : Bool do
    return true
  entry Outcome() : UInt64 do
    return count
  invariant safe : true
  proof safe using UnsupportedCallableModelSurfaceProof.safe

#check UnsupportedCallableModelSurface.Model.State
#check UnsupportedCallableModelSurface.Model.alive.Transition

run_cmd do
  let env ← getEnv
  let unsupportedTransition :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedCallableModelSurface.Model.addWide.Transition
  if env.contains unsupportedTransition then
    throwError "unsupported callable params must not emit a typed transition relation"
  let reservedTransition :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedCallableModelSurface.Model.Outcome.Transition
  if env.contains reservedTransition then
    throwError "reserved Model surface names must not emit a callable transition relation"

/- `rec` is legal in the DSL but owned by generated Lean structures. The
    existing program and Proof surfaces must keep elaborating; only the optional
    typed Model surface is withheld. -/
program ModelReservedStateName where
  state «rec» : UInt64
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe preserving using ModelReservedStateNameProof.safe

#check ModelReservedStateName.Proof.subjectProgramV1
#check ModelReservedStateName.Proof.subjectDataV1
#check ModelReservedStateName.ProofPreserving.safe

run_cmd do
  let env ← getEnv
  let modelStateName :=
    `Tests.Language.InlineProofAuthoringV1.ModelReservedStateName.Model.State
  if env.contains modelStateName then
    throwError "reserved structure field name must withhold only the Model surface"

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
  -- mig-a3-elab: structured subjectData encodes to the same product bytes.
  match encodeSemanticProgramDataV1 Proofed.Proof.subjectDataV1 with
  | .ok encoded =>
      expect (encoded == Proofed.Proof.subjectBytesV1)
        "subjectDataV1 encode must recover subjectBytesV1"
  | .error error =>
      throw <| IO.userError s!"subjectDataV1 encode failed: {repr error}"
  expect (Proofed.Proof.generatedSafeV1Name == "generatedSafeV1")
    "generated theorem product name for inv safe"
  expect (generatedSimpleClosureTheoremNameV1 "safe" ==
      Proofed.Proof.generatedSafeV1Name)
    "naming helper matches elaborator Name def"
  match TypedStateSurface.Model.decodeState typedStateLogicalV1 with
  | .ok decoded =>
      expect (decoded == typedStateSampleV1)
        "typed state decode must preserve all fields in source order"
  | .error error =>
      throw <| IO.userError s!"typed state decode failed: {repr error}"
  let missingSlot : LogicalStateV1 := {
    initialized := true
    canonicalValues := encodeU32le 8 ++ encodeU64le 7
  }
  match TypedStateSurface.Model.decodeState missingSlot with
  | .ok _ => throw <| IO.userError "typed state decode must reject a missing slot"
  | .error _ => pure ()
  let extraSlot : LogicalStateV1 := {
    initialized := true
    canonicalValues := typedStateLogicalV1.canonicalValues ++ encodeU32le 0
  }
  match TypedStateSurface.Model.decodeState extraSlot with
  | .ok _ => throw <| IO.userError "typed state decode must reject trailing slot bytes"
  | .error _ => pure ()
  match validateSemanticProgramV1 subject with
  | .error error =>
      throw <| IO.userError s!"generated inline proof subject invalid: {repr error}"
  | .ok data =>
      expect (data == Proofed.Proof.subjectDataV1)
        "subjectDataV1 must equal structure-gated validated data"
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
