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

/-- Positive admission carrier for one exact semantic subject. Generated typed
    callable relations share one value of this type, rather than selecting an
    existential admitted witness independently per business lemma. -/
structure AdmittedSubjectV1 (program : SemanticProgramV1) where
  admitted : AdmittedReferenceSliceV1
  hadmit : admitReferenceProgramSliceV1 program = .ok admitted

/-- Run the sole production admission function and retain its exact success
    equality in the positive subject carrier. This is only admission packaging;
    it does not interpret an invocation. -/
def admitSubjectV1 (program : SemanticProgramV1) :
    Except ReferenceAdmissionErrorV1 (AdmittedSubjectV1 program) :=
  match hadmit : admitReferenceProgramSliceV1 program with
  | .ok admitted => .ok ⟨admitted, hadmit⟩
  | .error error => .error error

/-- Exact product initial-state carrier. Generated initializer proof views use
    this type instead of pretending the pre-initialization state is an
    initialized business `State`. The equality binds the carrier directly to
    the sole production `initialLogicalStateV1` constructor. -/
structure InitialLifecycleStateV1 (program : SemanticProgramV1) where
  logical : LogicalStateV1
  hinitial : initialLogicalStateV1 program = .ok logical

/-- Run the production initial-state constructor and retain its exact success
    equality. This packages lifecycle identity only; it does not execute an
    initializer or reconstruct state defaults. -/
def initialLifecycleStateV1 (program : SemanticProgramV1) :
    Except SemanticWireErrorV1 (InitialLifecycleStateV1 program) :=
  match hinitial : initialLogicalStateV1 program with
  | .ok logical => .ok ⟨logical, hinitial⟩
  | .error error => .error error

/-- Typed invariant predicate backed by the exact production state encoder and
    `evalInvariantV1`. This is a proof view, not a second invariant evaluator:
    a typed state satisfies the predicate precisely when it encodes and the
    sole production evaluator returns true at the selected ordinal. -/
def TypedInvariantV1
    {State : Type}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (state : State) : Prop :=
  ∃ logical,
    encodeState state = .ok logical ∧
      evalInvariantV1 program ordinal logical = .returnedTrue

/-- Exact bridge from an encoded typed state to the production invariant
    evaluator. The successful encoder equality fixes the same logical carrier
    on both sides; no validation, execution, or expression reinterpretation is
    hidden in this theorem. -/
theorem typedInvariantV1_iff_eval_of_encode
    {State : Type}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (state : State)
    (logical : LogicalStateV1)
    (hencode : encodeState state = .ok logical) :
    TypedInvariantV1 encodeState program ordinal state ↔
      evalInvariantV1 program ordinal logical = .returnedTrue := by
  constructor
  · rintro ⟨other, hother, heval⟩
    have hlogical : other = logical :=
      Except.ok.inj (hother.symm.trans hencode)
    simpa [hlogical] using heval
  · intro heval
    exact ⟨logical, hencode, heval⟩

/-- Typed author view of the three canonical Reference outcomes. Returned
    states/results are typed projections; revert/trap retain the production
    reason/fault, while exact unchanged-state behavior is enforced by
    `TypedCallableRelationV1` below. -/
inductive TypedOutcomeV1 (State Result : Type) where
  | returned (postState : State) (value : Result)
      (effects : Array OrderedEffectV1)
  | reverted (reason : SemanticRevertV1)
  | trapped (fault : SemanticFaultV1)

/-- Canonical typed callable relation. This is deliberately a `Prop`, not a
    second executable step:

    * pre/post state conversion is supplied by the generated wrapper around the
      sole production logical-state codec;
    * result conversion only projects the callable's exact canonical type;
    * invocation/context, responses, vault, effects, and all outcome branches
      remain explicit;
    * every branch is an equality headed by `stepReferenceSliceV1`.

    The returned branch carries explicit encode successes because generated
    state encoders remain `Except`-valued. Revert/trap require the exact encoded
    pre-state as the canonical unchanged state. -/
def TypedCallableRelationV1
    {State Result : Type}
    {program : SemanticProgramV1}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (encodeResult : Result → Option ReferenceValueV1)
    (subject : AdmittedSubjectV1 program)
    (pre : State)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedOutcomeV1 State Result) : Prop :=
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
            .trapped fault logicalPre

/-- Canonical initializer relation from the exact production lifecycle state
    to an initialized typed business state. Unlike `TypedCallableRelationV1`,
    the pre and returned state types are intentionally different. Every branch
    is still headed by the sole `stepReferenceSliceV1`; this is a proof
    relation, not an executable initializer implementation. -/
def TypedInitializerRelationV1
    {State Result : Type}
    {program : SemanticProgramV1}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (encodeResult : Result → Option ReferenceValueV1)
    (subject : AdmittedSubjectV1 program)
    (pre : InitialLifecycleStateV1 program)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedOutcomeV1 State Result) : Prop :=
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
        .trapped fault pre.logical

/-- The canonical typed callable relation is proof-functional whenever the
    generated state and result projections are injective. Determinism comes
    directly from the single `stepReferenceSliceV1` equality in each relation;
    this theorem does not evaluate the callable or choose an outcome. -/
theorem typedCallableRelationV1_outcome_unique
    {State Result : Type}
    {program : SemanticProgramV1}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (encodeResult : Result → Option ReferenceValueV1)
    (encodeStateInjective : ∀ left right logical,
      encodeState left = .ok logical →
      encodeState right = .ok logical → left = right)
    (encodeResultInjective : Function.Injective encodeResult)
    (subject : AdmittedSubjectV1 program)
    (pre : State)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (left right : TypedOutcomeV1 State Result)
    (hleft : TypedCallableRelationV1 encodeState encodeResult subject pre
      invocation responses vault left)
    (hright : TypedCallableRelationV1 encodeState encodeResult subject pre
      invocation responses vault right) :
    left = right := by
  cases left with
  | returned leftPost leftValue leftEffects =>
      rcases hleft with
        ⟨leftPre, hleftPre, leftLogicalPost, hleftPost, hleftStep⟩
      cases right with
      | returned rightPost rightValue rightEffects =>
          rcases hright with
            ⟨rightPre, hrightPre, rightLogicalPost, hrightPost, hrightStep⟩
          have hpre : leftPre = rightPre :=
            Except.ok.inj (hleftPre.symm.trans hrightPre)
          subst rightPre
          obtain ⟨hlogicalPost, hvalue, heffects⟩ :=
            OutcomeV1.returned.inj (hleftStep.symm.trans hrightStep)
          subst rightLogicalPost
          have hpost : leftPost = rightPost :=
            encodeStateInjective
              leftPost rightPost leftLogicalPost hleftPost hrightPost
          have htypedValue : leftValue = rightValue :=
            encodeResultInjective hvalue
          subst rightPost
          subst rightValue
          subst rightEffects
          rfl
      | reverted _rightReason =>
          rcases hright with ⟨rightPre, hrightPre, hrightStep⟩
          have hpre : leftPre = rightPre :=
            Except.ok.inj (hleftPre.symm.trans hrightPre)
          subst rightPre
          cases hleftStep.symm.trans hrightStep
      | trapped _rightFault =>
          rcases hright with ⟨rightPre, hrightPre, hrightStep⟩
          have hpre : leftPre = rightPre :=
            Except.ok.inj (hleftPre.symm.trans hrightPre)
          subst rightPre
          cases hleftStep.symm.trans hrightStep
  | reverted leftReason =>
      rcases hleft with ⟨leftPre, hleftPre, hleftStep⟩
      cases right with
      | returned _rightPost _rightValue _rightEffects =>
          rcases hright with
            ⟨rightPre, hrightPre, _rightLogicalPost, _hrightPost, hrightStep⟩
          have hpre : leftPre = rightPre :=
            Except.ok.inj (hleftPre.symm.trans hrightPre)
          subst rightPre
          cases hleftStep.symm.trans hrightStep
      | reverted rightReason =>
          rcases hright with ⟨rightPre, hrightPre, hrightStep⟩
          have hpre : leftPre = rightPre :=
            Except.ok.inj (hleftPre.symm.trans hrightPre)
          subst rightPre
          obtain ⟨hreasons, _⟩ :=
            OutcomeV1.reverted.inj (hleftStep.symm.trans hrightStep)
          subst rightReason
          rfl
      | trapped _rightFault =>
          rcases hright with ⟨rightPre, hrightPre, hrightStep⟩
          have hpre : leftPre = rightPre :=
            Except.ok.inj (hleftPre.symm.trans hrightPre)
          subst rightPre
          cases hleftStep.symm.trans hrightStep
  | trapped leftFault =>
      rcases hleft with ⟨leftPre, hleftPre, hleftStep⟩
      cases right with
      | returned _rightPost _rightValue _rightEffects =>
          rcases hright with
            ⟨rightPre, hrightPre, _rightLogicalPost, _hrightPost, hrightStep⟩
          have hpre : leftPre = rightPre :=
            Except.ok.inj (hleftPre.symm.trans hrightPre)
          subst rightPre
          cases hleftStep.symm.trans hrightStep
      | reverted _rightReason =>
          rcases hright with ⟨rightPre, hrightPre, hrightStep⟩
          have hpre : leftPre = rightPre :=
            Except.ok.inj (hleftPre.symm.trans hrightPre)
          subst rightPre
          cases hleftStep.symm.trans hrightStep
      | trapped rightFault =>
          rcases hright with ⟨rightPre, hrightPre, hrightStep⟩
          have hpre : leftPre = rightPre :=
            Except.ok.inj (hleftPre.symm.trans hrightPre)
          subst rightPre
          obtain ⟨hfaults, _⟩ :=
            OutcomeV1.trapped.inj (hleftStep.symm.trans hrightStep)
          subst rightFault
          rfl

/-- The canonical initializer relation is proof-functional whenever the
    generated post-state and result projections are injective. Determinism is
    inherited directly from the single production Reference step. -/
theorem typedInitializerRelationV1_outcome_unique
    {State Result : Type}
    {program : SemanticProgramV1}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (encodeResult : Result → Option ReferenceValueV1)
    (encodeStateInjective : ∀ left right logical,
      encodeState left = .ok logical →
      encodeState right = .ok logical → left = right)
    (encodeResultInjective : Function.Injective encodeResult)
    (subject : AdmittedSubjectV1 program)
    (pre : InitialLifecycleStateV1 program)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (left right : TypedOutcomeV1 State Result)
    (hleft : TypedInitializerRelationV1 encodeState encodeResult subject pre
      invocation responses vault left)
    (hright : TypedInitializerRelationV1 encodeState encodeResult subject pre
      invocation responses vault right) :
    left = right := by
  cases left with
  | returned leftPost leftValue leftEffects =>
      rcases hleft with ⟨leftLogicalPost, hleftPost, hleftStep⟩
      cases right with
      | returned rightPost rightValue rightEffects =>
          rcases hright with ⟨rightLogicalPost, hrightPost, hrightStep⟩
          obtain ⟨hlogicalPost, hvalue, heffects⟩ :=
            OutcomeV1.returned.inj (hleftStep.symm.trans hrightStep)
          subst rightLogicalPost
          have hpost : leftPost = rightPost :=
            encodeStateInjective
              leftPost rightPost leftLogicalPost hleftPost hrightPost
          have htypedValue : leftValue = rightValue :=
            encodeResultInjective hvalue
          subst rightPost
          subst rightValue
          subst rightEffects
          rfl
      | reverted _rightReason =>
          cases hleftStep.symm.trans hright
      | trapped _rightFault =>
          cases hleftStep.symm.trans hright
  | reverted leftReason =>
      cases right with
      | returned _rightPost _rightValue _rightEffects =>
          rcases hright with
            ⟨_rightLogicalPost, _hrightPost, hrightStep⟩
          cases hleft.symm.trans hrightStep
      | reverted rightReason =>
          obtain ⟨hreasons, _⟩ :=
            OutcomeV1.reverted.inj (hleft.symm.trans hright)
          subst rightReason
          rfl
      | trapped _rightFault =>
          cases hleft.symm.trans hright
  | trapped leftFault =>
      cases right with
      | returned _rightPost _rightValue _rightEffects =>
          rcases hright with
            ⟨_rightLogicalPost, _hrightPost, hrightStep⟩
          cases hleft.symm.trans hrightStep
      | reverted _rightReason =>
          cases hleft.symm.trans hright
      | trapped rightFault =>
          obtain ⟨hfaults, _⟩ :=
            OutcomeV1.trapped.inj (hleft.symm.trans hright)
          subst rightFault
          rfl

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
