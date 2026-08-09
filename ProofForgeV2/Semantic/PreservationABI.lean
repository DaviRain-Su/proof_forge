import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.ReferenceV1

/-
  ProofForgeV2.Semantic.PreservationABI — generic L1 step-preservation ABI.

  Engineering foundation only:
    * exact initializer discovery from the sole validated callable table
    * positive product-initial-state obligations for both lifecycle shapes
    * positive Reference admission (never implication/vacuous admission)
    * universal one-step preservation over invocation/context, responses, vault,
      and the full OutcomeV1 returned/reverted/trapped surface

  ProofKindV1 syntax/inventory/certifier integration is owned by the Source,
  Language, and Compiler layers; this module remains the sole generic preserving
  proposition and does not claim formal TASK-D2-07 / TST-SEM closure. Program
  instances supply proofs of this proposition; they do not supply a second
  State/Effect/step machine.
-/

namespace ProofForgeV2.Semantic.PreservationABI

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Machine helper: reverted outcomes carry the exact pre-state. -/
def OutcomeRevertedUnchangedV1
    (pre : LogicalStateV1)
    (_reason : SemanticRevertV1)
    (unchanged : LogicalStateV1) : Prop :=
  unchanged = pre

/-- Machine helper: trapped outcomes carry the exact pre-state. -/
def OutcomeTrappedUnchangedV1
    (pre : LogicalStateV1)
    (_fault : SemanticFaultV1)
    (unchanged : LogicalStateV1) : Prop :=
  unchanged = pre

/-- Executable exact validated callable-id classifier shared by initializer
    presence and initializer-invocation scope. Args/context/lifecycle remain
    solely owned by `stepReferenceSliceV1`; this helper only classifies the
    selected root kind. -/
def isInitializerCallableIdV1
    (program : SemanticProgramV1)
    (callableId : CallableIdV1) : Bool :=
  match validateSemanticProgramV1 program with
  | .error _ => false
  | .ok data =>
      match data.callables[callableId.toNat]? with
      | none => false
      | some callable => callable.kind == .initializer

private def IsInitializerCallableIdV1
    (program : SemanticProgramV1)
    (callableId : CallableIdV1) : Prop :=
  isInitializerCallableIdV1 program callableId = true

/-- The validated callable table contains the unique optional initializer. -/
def HasInitializerV1 (program : SemanticProgramV1) : Prop :=
  ∃ callableId : CallableIdV1, IsInitializerCallableIdV1 program callableId

/-- Executable invocation-shaped view of the exact callable-id classifier. -/
def isInitializerInvocationV1
    (program : SemanticProgramV1)
    (invocation : InvocationV1) : Bool :=
  isInitializerCallableIdV1 program invocation.callableId

/-- The invocation selects the validated initializer callable by exact id. -/
def IsInitializerInvocationV1
    (program : SemanticProgramV1)
    (invocation : InvocationV1) : Prop :=
  isInitializerInvocationV1 program invocation = true

instance isInitializerInvocationV1Decidable
    (program : SemanticProgramV1)
    (invocation : InvocationV1) :
    Decidable (IsInitializerInvocationV1 program invocation) := by
  change Decidable (isInitializerInvocationV1 program invocation = true)
  infer_instance

/-- Positive no-initializer base: the product initial-state constructor succeeds,
    the result conforms, and the selected invariant returns true. -/
def PreservationBaseNoInitializerV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1) : Prop :=
  ∃ initial : LogicalStateV1,
    initialLogicalStateV1 program = .ok initial ∧
    StateConformsV1 program initial ∧
    evalInvariantV1 program ordinal initial = .returnedTrue

/-- Initializer base: the product initial-state constructor succeeds, and every
    invocation selecting the initializer preserves the invariant on return or
    reports the exact unchanged pre-state on revert/trap. -/
def PreservationBaseWithInitializerV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1) : Prop :=
  ∃ initial : LogicalStateV1,
    initialLogicalStateV1 program = .ok initial ∧
    ∀ (invocation : InvocationV1)
      (responses : ExternalResponsesV1)
      (vault : ReferenceVaultSeedV1),
      IsInitializerInvocationV1 program invocation →
        match stepReferenceSliceV1 admitted initial invocation responses vault with
        | .returned postState _value _effects =>
            evalInvariantV1 program ordinal postState = .returnedTrue
        | .reverted reason unchangedState =>
            OutcomeRevertedUnchangedV1 initial reason unchangedState
        | .trapped fault unchangedState =>
            OutcomeTrappedUnchangedV1 initial fault unchangedState

/-- Exactly one lifecycle base applies, selected by the validated callable table. -/
def PreservationBaseV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1) : Prop :=
  (HasInitializerV1 program ∧
      PreservationBaseWithInitializerV1 program ordinal admitted) ∨
  (¬ HasInitializerV1 program ∧
      PreservationBaseNoInitializerV1 program ordinal)

/-- Universal one-step preservation over the full Reference input surface and
    all three normalized outcomes. -/
def PreservationStepV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1) : Prop :=
  ∀ (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1),
    StateConformsV1 program pre →
    evalInvariantV1 program ordinal pre = .returnedTrue →
      match stepReferenceSliceV1 admitted pre invocation responses vault with
      | .returned postState _value _effects =>
          evalInvariantV1 program ordinal postState = .returnedTrue
      | .reverted reason unchangedState =>
          OutcomeRevertedUnchangedV1 pre reason unchangedState
      | .trapped fault unchangedState =>
          OutcomeTrappedUnchangedV1 pre fault unchangedState

/-- Generic L1 preservation proposition. Reference admission is a positive
    existential obligation, so unsupported programs cannot satisfy it vacuously. -/
def PreservationTheoremV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1) : Prop :=
  ordinal.toNat < program.invariants.size ∧
  ∃ admitted : AdmittedReferenceSliceV1,
    admitReferenceProgramSliceV1 program = .ok admitted ∧
    PreservationBaseV1 program ordinal admitted ∧
    PreservationStepV1 program ordinal admitted

theorem outcomeRevertedUnchangedV1_rfl
    (pre : LogicalStateV1) (reason : SemanticRevertV1) :
    OutcomeRevertedUnchangedV1 pre reason pre := rfl

theorem outcomeTrappedUnchangedV1_rfl
    (pre : LogicalStateV1) (fault : SemanticFaultV1) :
    OutcomeTrappedUnchangedV1 pre fault pre := rfl

/-- Initializer-target classification always witnesses initializer presence. -/
theorem isInitializerInvocationV1_implies_hasInitializerV1
    (program : SemanticProgramV1)
    (invocation : InvocationV1)
    (hinit : IsInitializerInvocationV1 program invocation) :
    HasInitializerV1 program :=
  ⟨invocation.callableId, hinit⟩

/-- Initializer presence yields an invocation-shaped witness with the same root
    id. Args/context remain intentionally empty here because validity is owned
    by the Reference invocation gate, not this kind classifier. -/
theorem hasInitializerV1_implies_exists_invocation
    (program : SemanticProgramV1)
    (hinit : HasInitializerV1 program) :
    ∃ invocation : InvocationV1,
      IsInitializerInvocationV1 program invocation := by
  rcases hinit with ⟨callableId, hcallable⟩
  exact ⟨{ callableId, args := #[], context := #[] }, hcallable⟩

/-- A validated callable table whose exact initializer predicate is false has
    no initializer witness. This refines the same lookup used by
    `isInitializerCallableIdV1`; it does not introduce a second classifier. -/
theorem not_hasInitializerV1_of_validate_and_any_eq_false
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hnone : data.callables.any (fun callable => callable.kind == .initializer) = false) :
    ¬ HasInitializerV1 program := by
  intro hinit
  rcases hinit with ⟨callableId, hcallable⟩
  unfold IsInitializerCallableIdV1 isInitializerCallableIdV1 at hcallable
  rw [hvalidate] at hcallable
  cases hlookup : data.callables[callableId.toNat]? with
  | none => simp [hlookup] at hcallable
  | some callable =>
      have hkind : (callable.kind == .initializer) = true := by
        simpa [hlookup] using hcallable
      rcases (Array.getElem?_eq_some_iff).mp hlookup with ⟨hbound, heq⟩
      have hall := Array.any_eq_false.mp hnone callableId.toNat hbound
      apply hall
      simpa only [heq] using hkind

/-- Failure of the product initial-state constructor makes the positive
    no-initializer base false. -/
theorem not_preservationBaseNoInitializerV1_of_initial_error
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (error : SemanticWireErrorV1)
    (herror : initialLogicalStateV1 program = .error error) :
    ¬ PreservationBaseNoInitializerV1 program ordinal := by
  intro hbase
  rcases hbase with ⟨initial, hinitial, _hconforms, _heval⟩
  rw [herror] at hinitial
  contradiction

/-- Failure of the product initial-state constructor also makes the
    initializer base false; it cannot hide behind the universal invocation. -/
theorem not_preservationBaseWithInitializerV1_of_initial_error
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (error : SemanticWireErrorV1)
    (herror : initialLogicalStateV1 program = .error error) :
    ¬ PreservationBaseWithInitializerV1 program ordinal admitted := by
  intro hbase
  rcases hbase with ⟨initial, hinitial, _hsteps⟩
  rw [herror] at hinitial
  contradiction

/-- Ordinal mutation is rejected before any preservation obligation. -/
theorem not_preservationTheoremV1_of_oob_ordinal
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (hoob : ¬ ordinal.toNat < program.invariants.size) :
    ¬ PreservationTheoremV1 program ordinal := by
  intro hpreserves
  exact hoob hpreserves.1

/-- Failed Reference admission makes the preservation proposition false. -/
theorem not_preservationTheoremV1_of_admission_error
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (error : ReferenceAdmissionErrorV1)
    (herror : admitReferenceProgramSliceV1 program = .error error) :
    ¬ PreservationTheoremV1 program ordinal := by
  intro hpreserves
  rcases hpreserves.2 with ⟨admitted, hadmit, _hbase, _hstep⟩
  rw [herror] at hadmit
  contradiction

end ProofForgeV2.Semantic.PreservationABI
