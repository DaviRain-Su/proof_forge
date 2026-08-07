import ProofForgeV2.Semantic.PreservationABI
import Tests.Semantic.InvariantABI

/-
  Tests.Semantic.PreservationABI — focused engineering tests for the generic
  L1 preservation proposition. These tests pin the ABI shape and exercise both
  lifecycle bases on the product Reference machine. They do not implement the
  ProofKind/inventory/certifier cutover or claim formal TST-SEM completion.
-/

namespace Tests.Semantic.PreservationABI

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open Tests.Semantic.InvariantABI.CanonicalInvariantFixtureV1

/-! Definitional ABI pins: positive initial-state result, positive admission,
full input quantification, and the unflattened OutcomeV1 match are deliberate. -/

example (pre unchanged : LogicalStateV1) (reason : SemanticRevertV1) :
    OutcomeRevertedUnchangedV1 pre reason unchanged ↔ unchanged = pre := Iff.rfl

example (pre unchanged : LogicalStateV1) (fault : SemanticFaultV1) :
    OutcomeTrappedUnchangedV1 pre fault unchanged ↔ unchanged = pre := Iff.rfl

example (program : SemanticProgramV1) (ordinal : InvariantOrdinalV1) :
    PreservationBaseNoInitializerV1 program ordinal ↔
      ∃ initial : LogicalStateV1,
        initialLogicalStateV1 program = .ok initial ∧
        StateConformsV1 program initial ∧
        evalInvariantV1 program ordinal initial = .returnedTrue := Iff.rfl

example (program : SemanticProgramV1) (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1) :
    PreservationBaseWithInitializerV1 program ordinal admitted ↔
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
                OutcomeTrappedUnchangedV1 initial fault unchangedState := Iff.rfl

example (program : SemanticProgramV1) (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1) :
    PreservationStepV1 program ordinal admitted ↔
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
              OutcomeTrappedUnchangedV1 pre fault unchangedState := Iff.rfl

example (program : SemanticProgramV1) (ordinal : InvariantOrdinalV1) :
    PreservationTheoremV1 program ordinal ↔
      (ordinal.toNat < program.invariants.size ∧
        ∃ admitted : AdmittedReferenceSliceV1,
          admitReferenceProgramSliceV1 program = .ok admitted ∧
          PreservationBaseV1 program ordinal admitted ∧
          PreservationStepV1 program ordinal admitted) := Iff.rfl

example (program : SemanticProgramV1) :
    HasInitializerV1 program ↔
      ∃ callableId : CallableIdV1,
        isInitializerCallableIdV1 program callableId = true := Iff.rfl

example (program : SemanticProgramV1) (invocation : InvocationV1) :
    IsInitializerInvocationV1 program invocation ↔
      isInitializerInvocationV1 program invocation = true := Iff.rfl

example (program : SemanticProgramV1) (invocation : InvocationV1) :
    Decidable (IsInitializerInvocationV1 program invocation) :=
  inferInstance

example (program : SemanticProgramV1) (ordinal : InvariantOrdinalV1)
    (hoob : ¬ ordinal.toNat < program.invariants.size) :
    ¬ PreservationTheoremV1 program ordinal :=
  not_preservationTheoremV1_of_oob_ordinal program ordinal hoob

example (program : SemanticProgramV1) (ordinal : InvariantOrdinalV1)
    (error : ReferenceAdmissionErrorV1)
    (herror : admitReferenceProgramSliceV1 program = .error error) :
    ¬ PreservationTheoremV1 program ordinal :=
  not_preservationTheoremV1_of_admission_error program ordinal error herror

example (program : SemanticProgramV1) (invocation : InvocationV1)
    (hinit : IsInitializerInvocationV1 program invocation) :
    HasInitializerV1 program :=
  isInitializerInvocationV1_implies_hasInitializerV1 program invocation hinit

example (program : SemanticProgramV1) (hinit : HasInitializerV1 program) :
    ∃ invocation : InvocationV1,
      IsInitializerInvocationV1 program invocation :=
  hasInitializerV1_implies_exists_invocation program hinit

example (program : SemanticProgramV1) (ordinal : InvariantOrdinalV1)
    (error : SemanticWireErrorV1)
    (herror : initialLogicalStateV1 program = .error error) :
    ¬ PreservationBaseNoInitializerV1 program ordinal :=
  not_preservationBaseNoInitializerV1_of_initial_error
    program ordinal error herror

example (program : SemanticProgramV1) (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (error : SemanticWireErrorV1)
    (herror : initialLogicalStateV1 program = .error error) :
    ¬ PreservationBaseWithInitializerV1 program ordinal admitted :=
  not_preservationBaseWithInitializerV1_of_initial_error
    program ordinal admitted error herror

example (pre changed : LogicalStateV1) (reason : SemanticRevertV1)
    (hne : changed ≠ pre) :
    ¬ OutcomeRevertedUnchangedV1 pre reason changed := by
  simpa [OutcomeRevertedUnchangedV1] using hne

example (pre changed : LogicalStateV1) (fault : SemanticFaultV1)
    (hne : changed ≠ pre) :
    ¬ OutcomeTrappedUnchangedV1 pre fault changed := by
  simpa [OutcomeTrappedUnchangedV1] using hne

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectInitializerInvocation
    (label : String)
    (program : SemanticProgramV1)
    (invocation : InvocationV1) : IO Unit := do
  if hinit : IsInitializerInvocationV1 program invocation then
    have _hhas : HasInitializerV1 program :=
      isInitializerInvocationV1_implies_hasInitializerV1
        program invocation hinit
    pure ()
  else
    throw <| IO.userError
      s!"{label}: expected actual initializer classifier to accept invocation"

private def expectNotInitializerInvocation
    (label : String)
    (program : SemanticProgramV1)
    (invocation : InvocationV1) : IO Unit := do
  if _hinit : IsInitializerInvocationV1 program invocation then
    throw <| IO.userError
      s!"{label}: expected actual initializer classifier to reject invocation"
  else
    pure ()

private def expectCarrier
    (label : String) (data : SemanticProgramDataV1) : IO SemanticProgramV1 := do
  let bytes ← match encodeSemanticProgramDataV1 data with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"{label}: encode failed: {repr error}"
  match decodeSemanticProgramV1 bytes with
  | .ok program => pure program
  | .error error =>
      throw <| IO.userError s!"{label}: carrier decode failed: {repr error}"

private def emptyReturnBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[]
  terminator := .return_ none
}

private def initializerCallable : CallableV1 := {
  id := 0
  kind := .initializer
  name := none
  params := #[]
  result := { typeId := 1, visibility := .public_ }
  entryBlock := 0
  blocks := #[emptyReturnBlock]
  loopBounds := #[]
  invariantSteps := none
}

private def entryCallable : CallableV1 := {
  id := 1
  kind := .entry
  name := some "entry_gate"
  params := #[]
  result := { typeId := 1, visibility := .public_ }
  entryBlock := 0
  blocks := #[emptyReturnBlock]
  loopBounds := #[]
  invariantSteps := none
}

private def truthCallable : CallableV1 := {
  id := 2
  kind := .invariant
  name := some "truth"
  params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[{
      result := some { valueId := 0, typeId := 0 }
      op := .literal 0 (ByteArray.mk #[1])
    }]
    terminator := .return_ (some 0)
  }]
  loopBounds := #[]
  invariantSteps := some 3
}

private def initializerData : SemanticProgramDataV1 := {
  qualifiedName := { components := ⟨"Tests", #["PreservationInitializer"]⟩ }
  types := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .unit }
  ]
  constants := #[]
  logicalState := #[]
  events := #[]
  errors := #[]
  callables := #[initializerCallable, entryCallable, truthCallable]
  invariants := #[{ id := 0, name := "truth", callableId := 2 }]
  requirements := { items := #[] }
}

private def admit (label : String) (program : SemanticProgramV1) :
    IO AdmittedReferenceSliceV1 := do
  match admitReferenceProgramSliceV1 program with
  | .ok admitted => pure admitted
  | .error error =>
      throw <| IO.userError s!"{label}: admission failed: {repr error}"

private def testNoInitializerReferenceBaseAndStep : IO Unit := do
  let program : SemanticProgramV1 := ⟨canonicalBytes⟩
  let data ← match validateSemanticProgramV1 program with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"no-init: validation failed: {repr error}"
  expect (!(data.callables.any fun callable => callable.kind == .initializer))
    "no-init: canonical fixture must not contain an initializer"
  for callable in data.callables do
    let candidate : InvocationV1 := {
      callableId := callable.id
      args := #[]
      context := #[]
    }
    expectNotInitializerInvocation
      s!"no-init: callable {callable.id}" program candidate
  let initial ← match initialLogicalStateV1 program with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"no-init: initial state failed: {repr error}"
  expect initial.initialized "no-init: product initial state must be initialized"
  expect (stateConformsBoolV1 program initial)
    "no-init: product initial state must conform"
  expect (evalInvariantV1 program 0 initial == .returnedTrue)
    "no-init: ordinal zero must hold on product initial state"
  let admitted ← admit "no-init" program
  let invocation : InvocationV1 := { callableId := 0, args := #[], context := #[] }
  expect (data.callables[0]?.map (fun callable => callable.kind) == some .entry)
    "no-init: callable zero must remain the entry gate"
  match stepReferenceSliceV1 admitted initial invocation #[] with
  | .returned postState none effects =>
      expect (postState == initial)
        "no-init: read-only entry must return the exact pre-state"
      expect effects.isEmpty "no-init: entry gate must emit no effects"
      expect (evalInvariantV1 program 0 postState == .returnedTrue)
        "no-init: returned post-state must preserve ordinal zero"
  | outcome =>
      throw <| IO.userError s!"no-init: expected returned outcome, got {repr outcome}"
  let invalid : InvocationV1 := { callableId := 99, args := #[], context := #[] }
  expectNotInitializerInvocation "no-init: out-of-range callable" program invalid
  match stepReferenceSliceV1 admitted initial invalid #[] with
  | .trapped .invalidInvocation unchanged =>
      expect (unchanged == initial)
        "no-init: trapped invalid invocation must carry the exact pre-state"
  | outcome =>
      throw <| IO.userError s!"no-init: expected invalidInvocation, got {repr outcome}"

private def testInitializerReferenceBase : IO Unit := do
  let program ← expectCarrier "with-init" initializerData
  let data ← match validateSemanticProgramV1 program with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"with-init: validation failed: {repr error}"
  expect (data.callables.any fun callable => callable.kind == .initializer)
    "with-init: validated callable table must contain the initializer"
  let initInvocation : InvocationV1 := { callableId := 0, args := #[], context := #[] }
  let entryInvocation : InvocationV1 := { callableId := 1, args := #[], context := #[] }
  let truthInvocation : InvocationV1 := { callableId := 2, args := #[], context := #[] }
  expect (data.callables[initInvocation.callableId.toNat]?.map
      (fun callable => callable.kind) == some .initializer)
    "with-init: callable zero must be the initializer"
  expect (data.callables[entryInvocation.callableId.toNat]?.map
      (fun callable => callable.kind) == some .entry)
    "with-init: callable one must remain the entry gate"
  expectInitializerInvocation "with-init: initializer root" program initInvocation
  expectNotInitializerInvocation "with-init: entry root" program entryInvocation
  expectNotInitializerInvocation "with-init: invariant root" program truthInvocation
  let initial ← match initialLogicalStateV1 program with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"with-init: initial state failed: {repr error}"
  expect (!initial.initialized)
    "with-init: product initial state must remain uninitialized"
  let admitted ← admit "with-init" program
  let malformedInit : InvocationV1 := {
    callableId := 0
    args := #[{ typeId := 1, valueBytes := ByteArray.empty }]
    context := #[]
  }
  expectInitializerInvocation
    "with-init: malformed args still select initializer root"
    program malformedInit
  match stepReferenceSliceV1 admitted initial malformedInit #[] with
  | .trapped .invalidInvocation unchanged =>
      expect (unchanged == initial)
        "with-init: malformed initializer trap must carry the exact pre-state"
  | outcome =>
      throw <| IO.userError
        s!"with-init: expected malformed init trap, got {repr outcome}"
  let initialized ← match stepReferenceSliceV1 admitted initial initInvocation #[] with
    | .returned postState none effects =>
        expect postState.initialized
          "with-init: successful initializer must publish initialized=true"
        expect (postState.canonicalValues == initial.canonicalValues)
          "with-init: empty-state initializer must preserve canonical bytes"
        expect effects.isEmpty "with-init: initializer must emit no effects"
        expect (stateConformsBoolV1 program postState)
          "with-init: returned initializer state must conform"
        expect (evalInvariantV1 program 0 postState == .returnedTrue)
          "with-init: returned initializer state must satisfy the invariant"
        pure postState
    | outcome =>
        throw <| IO.userError s!"with-init: expected returned init, got {repr outcome}"
  match stepReferenceSliceV1 admitted initialized initInvocation #[] with
  | .reverted (.standard .alreadyInitialized) unchanged =>
      expect (unchanged == initialized)
        "with-init: repeated initializer revert must carry the exact pre-state"
  | outcome =>
      throw <| IO.userError s!"with-init: expected alreadyInitialized, got {repr outcome}"

/-- Suite entry (engineering only — not formal TST-SEM/TASK-D2-07). -/
def run : IO Unit := do
  testNoInitializerReferenceBaseAndStep
  testInitializerReferenceBase
  IO.println "Tests.Semantic.PreservationABI: engineering suite finished"

end Tests.Semantic.PreservationABI
