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

#check ProofForgeV2.Semantic.StateModelV1.encodeBool_boolOfDecodedStateValueV1

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
#check TypedStateSurface.Model.encode_exists
#check TypedStateSurface.Model.decodeState
#check TypedStateSurface.Model.decode_encode
#check TypedStateSurface.Model.encode_injective_of_eq_ok
#check TypedStateSurface.Model.decode_existsUnique_of_conforms
#check TypedStateSurface.Model.encode_decode_of_conforms
#check TypedStateSurface.Model.conforms_of_encode
#check TypedStateSurface.Model.conforms_iff_exists_encode
#check TypedStateSurface.Model.safe
#check TypedStateSurface.Model.Invariant.safe_iff_eval

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

/- Encoder totality concludes through the generated wrapper around the sole
   production codec. -/
example (typedState : TypedStateSurface.Model.State) :
    ∃ logicalState : LogicalStateV1,
      TypedStateSurface.Model.encodeState typedState =
        .ok logicalState :=
  TypedStateSurface.Model.encode_exists typedState

/-- The generated author predicate is definitionally only the exact production
    state encoder plus `evalInvariantV1` at the lowered invariant ordinal. -/
example (typedState : TypedStateSurface.Model.State) :
    TypedStateSurface.Model.safe typedState =
      TypedInvariantV1 TypedStateSurface.Model.encodeState
        TypedStateSurface.Proof.subjectProgramV1 0 typedState := rfl

/-- Once encoding fixes the logical carrier, the generated bridge is an exact
    equivalence with the sole production invariant evaluator. -/
example
    (typedState : TypedStateSurface.Model.State)
    (logicalState : LogicalStateV1)
    (hencode :
      TypedStateSurface.Model.encodeState typedState = .ok logicalState) :
    TypedStateSurface.Model.safe typedState ↔
      evalInvariantV1 TypedStateSurface.Proof.subjectProgramV1 0 logicalState =
        .returnedTrue :=
  TypedStateSurface.Model.Invariant.safe_iff_eval
    typedState logicalState hencode

/-- The generic typed predicate itself exposes the production encoder and
    evaluator directly; no generated invariant interpreter is hidden here. -/
example
    {State : Type}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (semanticProgram : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (typedState : State) :
    TypedInvariantV1 encodeState semanticProgram ordinal typedState ↔
      ∃ logicalState,
        encodeState typedState = .ok logicalState ∧
          evalInvariantV1 semanticProgram ordinal logicalState =
            .returnedTrue := by
  rfl

/-- Encoder failure cannot satisfy the predicate by choosing another logical
    state; the evaluator-backed projection is positive rather than vacuous. -/
example (semanticProgram : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1) :
    ¬ TypedInvariantV1
      (fun _ : Unit => .error .nonCanonical) semanticProgram ordinal () := by
  simp [TypedInvariantV1]

/- The first ordinary mathematical invariant view is recognized from the
   exact lowered CFG. Nonzero state IDs and invariant ordinal ensure the
   emitter does not assume either table starts at the equality operands. -/
program TypedInvariantFieldEqualitySurface where
  state nonce : UInt64
  state reserves : UInt64
  state shares : UInt64
  view alive() : Bool do
    return true
  invariant primary : true
  invariant solvent : reserves == shares
  invariant nonsolvent : reserves != shares
  proof primary using TypedInvariantFieldEqualitySurfaceProof.primary
  proof solvent using TypedInvariantFieldEqualitySurfaceProof.solvent
  proof nonsolvent using TypedInvariantFieldEqualitySurfaceProof.nonsolvent

#check TypedInvariantFieldEqualitySurface.Model.solvent
#check TypedInvariantFieldEqualitySurface.Model.encode_exists
#check TypedInvariantFieldEqualitySurface.Model.Invariant.solvent_iff_eval
#check TypedInvariantFieldEqualitySurface.Model.Invariant.solvent_iff_fields

example
    (typedState : TypedInvariantFieldEqualitySurface.Model.State)
    (hvalidate :
      validateSemanticProgramV1
          TypedInvariantFieldEqualitySurface.Proof.subjectProgramV1 =
        .ok TypedInvariantFieldEqualitySurface.Proof.subjectDataV1) :
    TypedInvariantFieldEqualitySurface.Model.solvent typedState ↔
      typedState.reserves = typedState.shares :=
  TypedInvariantFieldEqualitySurface.Model.Invariant.solvent_iff_fields
    typedState hvalidate

/- Unsupported invariant CFGs keep their evaluator bridge but fail closed for
    the optional field-level mathematical theorem. -/
run_cmd do
  let env ← getEnv
  let unsupportedFieldBridge :=
    `Tests.Language.InlineProofAuthoringV1.TypedInvariantFieldEqualitySurface.Model.Invariant.primary_iff_fields
  if env.contains unsupportedFieldBridge then
    throwError "literal-true invariant must not emit a field equality bridge"
  let nearMissFieldBridge :=
    `Tests.Language.InlineProofAuthoringV1.TypedInvariantFieldEqualitySurface.Model.Invariant.nonsolvent_iff_fields
  if env.contains nearMissFieldBridge then
    throwError "not-equal invariant must not emit a field equality bridge"

/- Invariant predicates are selected from the exact lowered invariant table;
   in particular, a second declaration is not silently hard-coded to zero. -/
program TypedInvariantOrdinalSurface where
  state count : UInt64
  view alive() : Bool do
    return true
  invariant primary : true
  invariant secondary : true
  proof primary using TypedInvariantOrdinalSurfaceProof.primary
  proof secondary using TypedInvariantOrdinalSurfaceProof.secondary

#check TypedInvariantOrdinalSurface.Model.primary
#check TypedInvariantOrdinalSurface.Model.secondary
#check TypedInvariantOrdinalSurface.Model.Invariant.primary_iff_eval
#check TypedInvariantOrdinalSurface.Model.Invariant.secondary_iff_eval

example (typedState : TypedInvariantOrdinalSurface.Model.State) :
    TypedInvariantOrdinalSurface.Model.secondary typedState =
      TypedInvariantV1 TypedInvariantOrdinalSurface.Model.encodeState
        TypedInvariantOrdinalSurface.Proof.subjectProgramV1 1 typedState := rfl

example :
    TypedInvariantOrdinalSurface.Proof.subjectDataV1.invariants[1]?.map
        (fun invariant => invariant.name) =
      some "secondary" := rfl

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
#check TypedCallableSurface.Model.add.Result
#check TypedCallableSurface.Model.add.encodeResult
#check TypedCallableSurface.Model.add.decodeResult
#check TypedCallableSurface.Model.add.decode_encode_result
#check TypedCallableSurface.Model.add.decodeResult_complete_of_conforms
#check TypedCallableSurface.Model.add.decodeResult_existsUnique_of_conforms
#check TypedCallableSurface.Model.add.decodeResult_complete_of_returned
#check TypedCallableSurface.Model.add.decodeResult_existsUnique_of_returned
#check TypedCallableSurface.Model.add.decodeState_complete_of_returned
#check TypedCallableSurface.Model.add.decodeState_existsUnique_of_returned
#check TypedCallableSurface.Model.add.encodeResult_injective
#check TypedCallableSurface.Model.add.Outcome
#check TypedCallableSurface.Model.add.Transition
#check TypedCallableSurface.Model.add.transition_returned_of_step
#check TypedCallableSurface.Model.add.transition_reverted_of_step
#check TypedCallableSurface.Model.add.transition_trapped_of_step
#check TypedCallableSurface.Model.add.transition_exists
#check TypedCallableSurface.Model.add.outcome_unique
#check TypedCallableSurface.Model.alive.invocation
#check TypedCallableSurface.Model.alive.Result
#check TypedCallableSurface.Model.alive.encodeResult
#check TypedCallableSurface.Model.alive.decodeResult
#check TypedCallableSurface.Model.alive.decode_encode_result
#check TypedCallableSurface.Model.alive.decodeResult_complete_of_conforms
#check TypedCallableSurface.Model.alive.decodeResult_existsUnique_of_conforms
#check TypedCallableSurface.Model.alive.decodeResult_complete_of_returned
#check TypedCallableSurface.Model.alive.decodeResult_existsUnique_of_returned
#check TypedCallableSurface.Model.alive.decodeState_complete_of_returned
#check TypedCallableSurface.Model.alive.decodeState_existsUnique_of_returned
#check TypedCallableSurface.Model.alive.encodeResult_injective
#check TypedCallableSurface.Model.alive.Outcome
#check TypedCallableSurface.Model.alive.Transition
#check TypedCallableSurface.Model.alive.transition_returned_of_step
#check TypedCallableSurface.Model.alive.transition_reverted_of_step
#check TypedCallableSurface.Model.alive.transition_trapped_of_step
#check TypedCallableSurface.Model.alive.transition_exists
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

/-- Generated result decoding checks the exact lowered TypeId and delegates
    canonical payload validation to the production valueBytes validator. -/
example : TypedCallableSurface.Model.add.decodeResult
    (TypedCallableSurface.Model.add.encodeResult 9) = .ok 9 :=
  TypedCallableSurface.Model.add.decode_encode_result 9

example : TypedCallableSurface.Model.alive.decodeResult
    (TypedCallableSurface.Model.alive.encodeResult false) = .ok false :=
  TypedCallableSurface.Model.alive.decode_encode_result false

example
    (referenceValue : Option ReferenceValueV1)
    (hconforms :
      ReferenceResultConformsV1 TypedCallableSurface.Proof.subjectDataV1
        (TypedCallableSurface.Proof.subjectDataV1.callables[0]'(by decide)).result
        referenceValue) :
    ∃ value : TypedCallableSurface.Model.add.Result,
      TypedCallableSurface.Model.add.decodeResult referenceValue = .ok value ∧
        ∀ other : TypedCallableSurface.Model.add.Result,
          TypedCallableSurface.Model.add.decodeResult referenceValue = .ok other →
            value = other :=
  TypedCallableSurface.Model.add.decodeResult_existsUnique_of_conforms
    referenceValue hconforms

example
    (referenceValue : Option ReferenceValueV1)
    (hconforms :
      ReferenceResultConformsV1 TypedCallableSurface.Proof.subjectDataV1
        (TypedCallableSurface.Proof.subjectDataV1.callables[1]'(by decide)).result
        referenceValue) :
    ∃ value : TypedCallableSurface.Model.alive.Result,
      TypedCallableSurface.Model.alive.decodeResult referenceValue = .ok value ∧
        ∀ other : TypedCallableSurface.Model.alive.Result,
          TypedCallableSurface.Model.alive.decodeResult referenceValue = .ok other →
            value = other :=
  TypedCallableSurface.Model.alive.decodeResult_existsUnique_of_conforms
    referenceValue hconforms

/-- A conforming Bool result does not merely decode: canonical re-encoding
    recovers the exact Reference carrier needed by the typed relation. -/
example
    (referenceValue : Option ReferenceValueV1)
    (hconforms :
      ReferenceResultConformsV1 TypedCallableSurface.Proof.subjectDataV1
        (TypedCallableSurface.Proof.subjectDataV1.callables[1]'(by decide)).result
        referenceValue) :
    ∃ value : TypedCallableSurface.Model.alive.Result,
      TypedCallableSurface.Model.alive.decodeResult referenceValue = .ok value ∧
        TypedCallableSurface.Model.alive.encodeResult value = referenceValue ∧
          ∀ other : TypedCallableSurface.Model.alive.Result,
            TypedCallableSurface.Model.alive.decodeResult referenceValue = .ok other →
              value = other :=
  TypedCallableSurface.Model.alive.decodeResult_complete_of_conforms
    referenceValue hconforms

example : TypedCallableSurface.Model.alive.decodeResult
    (TypedCallableSurface.Model.alive.encodeResult true) = .ok true :=
  TypedCallableSurface.Model.alive.decode_encode_result true

/-- A payload with another lowered TypeId is rejected before projection. -/
example : TypedCallableSurface.Model.alive.decodeResult (some {
    typeId := 0
    valueBytes := encodeBool true
  }) = .error .nonCanonical := by
  rfl

/-- The exact Bool TypeId is still insufficient when production canonical
    valueBytes validation rejects the payload. -/
example : TypedCallableSurface.Model.alive.decodeResult (some {
    typeId := 1
    valueBytes := ByteArray.mk #[2]
  }) = .error .nonCanonical := by
  rfl

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

/- Initializer authoring has a separate production lifecycle pre-state. It is
   not emitted as an ordinary initialized callable relation. -/
program TypedInitializerSurface where
  state count : UInt64
  init(seed : UInt64) do
    count := seed
  view get() : UInt64 do
    return count
  invariant safe : true
  proof safe using TypedInitializerSurfaceProof.safe

#check TypedInitializerSurface.Model.LifecycleState
#check TypedInitializerSurface.Model.initialLifecycleState
#check TypedInitializerSurface.Model.init.invocation
#check TypedInitializerSurface.Model.init.Result
#check TypedInitializerSurface.Model.init.encodeResult
#check TypedInitializerSurface.Model.init.decodeResult
#check TypedInitializerSurface.Model.init.decode_encode_result
#check TypedInitializerSurface.Model.init.decodeResult_complete_of_conforms
#check TypedInitializerSurface.Model.init.decodeResult_complete_of_returned
#check TypedInitializerSurface.Model.init.decodeState_complete_of_returned
#check TypedInitializerSurface.Model.init.encodeResult_injective
#check TypedInitializerSurface.Model.init.Outcome
#check TypedInitializerSurface.Model.init.Transition
#check TypedInitializerSurface.Model.init.transition_returned_of_step
#check TypedInitializerSurface.Model.init.transition_reverted_of_step
#check TypedInitializerSurface.Model.init.transition_trapped_of_step
#check TypedInitializerSurface.Model.init.transition_exists
#check TypedInitializerSurface.Model.init.outcome_unique
#check TypedInitializerSurface.Model.get.Transition
#check TypedInitializerSurface.Model.safe

/-- Initializer lifecycle input remains a separate type: invariant predicates
    are properties only of initialized generated business states. -/
example : TypedInitializerSurface.Model.State → Prop :=
  TypedInitializerSurface.Model.safe

example : TypedInitializerSurface.Model.init.invocation 7 #[] = ({
    callableId := 0
    args := #[{ typeId := 0, valueBytes := encodeU64le 7 }]
    context := #[]
  } : InvocationV1) := rfl

example :
    TypedInitializerSurface.Proof.subjectDataV1.callables[0]?.map
        (fun callable => callable.kind) =
      some CallableKindV1.initializer := rfl

example : TypedInitializerSurface.Model.get.invocation #[] = ({
    callableId := 1
    args := #[]
    context := #[]
  } : InvocationV1) := rfl

/-- The generated lifecycle carrier is definitionally bound to the exact
    production initial-state constructor. -/
example (pre : TypedInitializerSurface.Model.LifecycleState) :
    initialLogicalStateV1 TypedInitializerSurface.Proof.subjectProgramV1 =
      .ok pre.logical :=
  pre.hinitial

/-- Expanding the initializer relation reaches the sole generic production
    Reference relation, with different pre/post state types. -/
example
    (subject : TypedInitializerSurface.Model.ReferenceSubject)
    (pre : TypedInitializerSurface.Model.LifecycleState)
    (seed : UInt64)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedInitializerSurface.Model.init.Outcome) :
    TypedInitializerSurface.Model.init.Transition
        subject pre seed context responses vault outcome ↔
      TypedInitializerRelationV1
        TypedInitializerSurface.Model.encodeState
        TypedInitializerSurface.Model.init.encodeResult subject pre
        (TypedInitializerSurface.Model.init.invocation seed context)
        responses vault outcome := by
  rfl

/-- The generic initializer relation itself unfolds directly to the production
    step in every outcome branch; it does not hide a generated evaluator. -/
example
    {State Result : Type}
    {semanticProgram : SemanticProgramV1}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (encodeResult : Result → Option ReferenceValueV1)
    (subject : AdmittedSubjectV1 semanticProgram)
    (pre : InitialLifecycleStateV1 semanticProgram)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedOutcomeV1 State Result) :
    TypedInitializerRelationV1 encodeState encodeResult subject pre invocation
        responses vault outcome ↔
      match outcome with
      | .returned post value effects =>
          ∃ logicalPost,
            encodeState post = .ok logicalPost ∧
              stepReferenceSliceV1 subject.admitted pre.logical invocation
                  responses vault =
                .returned logicalPost (encodeResult value) effects
      | .reverted reason =>
          stepReferenceSliceV1 subject.admitted pre.logical invocation
              responses vault =
            .reverted reason pre.logical
      | .trapped fault =>
          stepReferenceSliceV1 subject.admitted pre.logical invocation
              responses vault =
            .trapped fault pre.logical := by
  unfold TypedInitializerRelationV1
  rfl

/- Initializer invocation identity comes from the lowered callable row rather
   than assuming source `init` is callable zero. -/
program NonzeroInitializerSurface where
  state count : UInt64
  view get() : UInt64 do
    return count
  init(seed : UInt64) do
    count := seed
  invariant safe : true
  proof safe using NonzeroInitializerSurfaceProof.safe

example : NonzeroInitializerSurface.Model.get.invocation #[] = ({
    callableId := 0
    args := #[]
    context := #[]
  } : InvocationV1) := rfl

example : NonzeroInitializerSurface.Model.init.invocation 9 #[] = ({
    callableId := 1
    args := #[{ typeId := 0, valueBytes := encodeU64le 9 }]
    context := #[]
  } : InvocationV1) := rfl

example :
    NonzeroInitializerSurface.Proof.subjectDataV1.callables[1]?.map
        (fun callable => callable.kind) =
      some CallableKindV1.initializer := rfl

/- An initializer outside the supported typed parameter subset withholds only
   the optional initializer lifecycle surface. Supported ordinary callables
   continue to receive initialized-state relations. -/
program UnsupportedInitializerModelSurface where
  state count : UInt64
  init(_seed : UInt128) do
    count := 0
  view get() : UInt64 do
    return count
  invariant safe : true
  proof safe using UnsupportedInitializerModelSurfaceProof.safe

#check UnsupportedInitializerModelSurface.Model.State
#check UnsupportedInitializerModelSurface.Model.get.Transition

run_cmd do
  let env ← getEnv
  let lifecycleState :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInitializerModelSurface.Model.LifecycleState
  if env.contains lifecycleState then
    throwError "unsupported initializer params must not emit a lifecycle state surface"
  let initializerTransition :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInitializerModelSurface.Model.init.Transition
  if env.contains initializerTransition then
    throwError "unsupported initializer params must not emit a typed transition relation"

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
#check TypedUnitCallableSurface.Model.clear.Result
#check TypedUnitCallableSurface.Model.clear.encodeResult
#check TypedUnitCallableSurface.Model.clear.decodeResult
#check TypedUnitCallableSurface.Model.clear.decode_encode_result
#check TypedUnitCallableSurface.Model.clear.decodeResult_complete_of_conforms
#check TypedUnitCallableSurface.Model.clear.decodeResult_existsUnique_of_conforms
#check TypedUnitCallableSurface.Model.clear.decodeResult_complete_of_returned
#check TypedUnitCallableSurface.Model.clear.decodeResult_existsUnique_of_returned
#check TypedUnitCallableSurface.Model.clear.decodeState_complete_of_returned
#check TypedUnitCallableSurface.Model.clear.decodeState_existsUnique_of_returned
#check TypedUnitCallableSurface.Model.clear.encodeResult_injective
#check TypedUnitCallableSurface.Model.clear.Outcome
#check TypedUnitCallableSurface.Model.clear.Transition
#check TypedUnitCallableSurface.Model.clear.transition_returned_of_step
#check TypedUnitCallableSurface.Model.clear.transition_reverted_of_step
#check TypedUnitCallableSurface.Model.clear.transition_trapped_of_step
#check TypedUnitCallableSurface.Model.clear.transition_exists
#check TypedUnitCallableSurface.Model.clear.outcome_unique

example : TypedUnitCallableSurface.Model.clear.Outcome =
    TypedOutcomeV1 TypedUnitCallableSurface.Model.State Unit := rfl

example : TypedUnitCallableSurface.Model.clear.decodeResult
    (TypedUnitCallableSurface.Model.clear.encodeResult ()) = .ok () :=
  TypedUnitCallableSurface.Model.clear.decode_encode_result ()

example
    (referenceValue : Option ReferenceValueV1)
    (hconforms :
      ReferenceResultConformsV1 TypedUnitCallableSurface.Proof.subjectDataV1
        (TypedUnitCallableSurface.Proof.subjectDataV1.callables[0]'(by decide)).result
        referenceValue) :
    ∃ value : TypedUnitCallableSurface.Model.clear.Result,
      TypedUnitCallableSurface.Model.clear.decodeResult referenceValue = .ok value ∧
        ∀ other : TypedUnitCallableSurface.Model.clear.Result,
          TypedUnitCallableSurface.Model.clear.decodeResult referenceValue = .ok other →
            value = other :=
  TypedUnitCallableSurface.Model.clear.decodeResult_existsUnique_of_conforms
    referenceValue hconforms

example : TypedUnitCallableSurface.Model.clear.decodeResult (some {
    typeId := 0
    valueBytes := ByteArray.empty
  }) = .error .nonCanonical := by
  rfl

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
  let invariantBridgeName :=
    `Tests.Language.InlineProofAuthoringV1.ModelReservedStateName.Model.Invariant.safe_iff_eval
  if env.contains invariantBridgeName then
    throwError "unsupported typed state must not emit a dangling invariant bridge"

/- A generated-root collision with an invariant name withholds only that
   optional typed invariant predicate/bridge, preserving Proof subject aliases. -/
program ReservedInvariantModelSurface where
  state count : UInt64
  view alive() : Bool do
    return true
  invariant Outcome : true
  invariant Invariant : true
  invariant safe : true
  proof Outcome using ReservedInvariantModelSurfaceProof.holds
  proof Invariant using ReservedInvariantModelSurfaceProof.namespaceCollision
  proof safe using ReservedInvariantModelSurfaceProof.safe

#check ReservedInvariantModelSurface.Proof.subjectProgramV1
#check ReservedInvariantModelSurface.Proof.Outcome
#check ReservedInvariantModelSurface.Proof.Invariant
#check ReservedInvariantModelSurface.Proof.safe
#check ReservedInvariantModelSurface.Model.State
#check ReservedInvariantModelSurface.Model.safe
#check ReservedInvariantModelSurface.Model.Invariant.safe_iff_eval

/-- Filtering reserved Model names must not renumber surviving evaluator rows. -/
example (typedState : ReservedInvariantModelSurface.Model.State) :
    ReservedInvariantModelSurface.Model.safe typedState =
      TypedInvariantV1 ReservedInvariantModelSurface.Model.encodeState
        ReservedInvariantModelSurface.Proof.subjectProgramV1 2 typedState := rfl

example
    (typedState : ReservedInvariantModelSurface.Model.State)
    (logicalState : LogicalStateV1)
    (hencode :
      ReservedInvariantModelSurface.Model.encodeState typedState =
        .ok logicalState) :
    ReservedInvariantModelSurface.Model.safe typedState ↔
      evalInvariantV1 ReservedInvariantModelSurface.Proof.subjectProgramV1 2
          logicalState = .returnedTrue :=
  ReservedInvariantModelSurface.Model.Invariant.safe_iff_eval
    typedState logicalState hencode

run_cmd do
  let env ← getEnv
  let outcomeBridgeName :=
    `Tests.Language.InlineProofAuthoringV1.ReservedInvariantModelSurface.Model.Invariant.Outcome_iff_eval
  if env.contains outcomeBridgeName then
    throwError "reserved Model invariant name must not emit an evaluator bridge"
  let namespaceBridgeName :=
    `Tests.Language.InlineProofAuthoringV1.ReservedInvariantModelSurface.Model.Invariant.Invariant_iff_eval
  if env.contains namespaceBridgeName then
    throwError "Model.Invariant namespace collision must not emit an evaluator bridge"

/- Accepted state shapes outside the current generated scalar subset must keep
   their Proof aliases while withholding the whole optional Model surface. -/
program UnsupportedInvariantStateSurface where
  state wide : UInt128
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using UnsupportedInvariantStateSurfaceProof.safe

#check UnsupportedInvariantStateSurface.Proof.subjectProgramV1
#check UnsupportedInvariantStateSurface.Proof.safe

run_cmd do
  let env ← getEnv
  let modelStateName :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInvariantStateSurface.Model.State
  if env.contains modelStateName then
    throwError "unsupported state scalar must not emit a typed Model.State"
  let predicateName :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInvariantStateSurface.Model.safe
  if env.contains predicateName then
    throwError "unsupported state scalar must not emit a typed invariant predicate"
  let bridgeName :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInvariantStateSurface.Model.Invariant.safe_iff_eval
  if env.contains bridgeName then
    throwError "unsupported state scalar must not emit a dangling invariant bridge"

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
