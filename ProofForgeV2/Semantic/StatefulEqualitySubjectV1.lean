import ProofForgeV2.Semantic.FieldComparisonSubjectV1

/-!
  ProofForgeV2.Semantic.StatefulEqualitySubjectV1 — parameterized production
  subject data and root-codec certificate for a unary state-changing entry
  that restores a two-field equality invariant.

  This module fixes only the lowering shape. Qualified name and all source
  declaration names remain parameters. Execution stays exclusively in
  `ReferenceMachineV1`; this module defines no State, Effect, step, evaluator,
  alternate validator, or pinned whole-program bytes.
-/

namespace ProofForgeV2.Semantic.StatefulEqualitySubjectV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.WireV1

/-- Reuse the exact production anonymous UInt64/Bool type table. -/
def typesV1 : Array TypeDeclV1 :=
  ProofForgeV2.Semantic.FieldComparisonSubjectV1.typesV1

/-- Reuse the exact production `state.persistent` / `value.bool` requests. -/
def requirementsV1 : ProgramRequirementsV1 :=
  ProofForgeV2.Semantic.FieldComparisonSubjectV1.requirementsV1

def callablesV1
    (entryName parameterName invariantName : String) : Array CallableV1 := #[
  storeParameterTwoReturnCallableV1 0 (some entryName) parameterName
    0 0 1 .public_,
  twoStateCompareInvariantCallableV1 1 (some invariantName)
    0 1 0 1 .eq .public_ (some 5)
]

/-- Contract-name-parametric semantic data for the state-changing equality
    family. -/
def subjectDataV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    SemanticProgramDataV1 := {
  qualifiedName
  types := typesV1
  constants := #[]
  logicalState := #[
    { id := 0, name := state0Name, typeId := 0, visibility := .public_ },
    { id := 1, name := state1Name, typeId := 0, visibility := .public_ }
  ]
  events := #[]
  errors := #[]
  callables := callablesV1 entryName parameterName invariantName
  invariants := #[{ id := 0, name := invariantName, callableId := 1 }]
  requirements := requirementsV1
}

theorem exactAtRoot_typesV1 :
    ExactMidOffsetInvertAtV1 (encodeArray encodeTypeDeclV1)
      (decodeArray maxTableElements decodeTypeDeclV1)
      typesV1 1 := by
  simpa [typesV1, ProofForgeV2.Semantic.FieldComparisonSubjectV1.typesV1] using
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.exactAtRoot_typesV1

theorem exactAtRoot_statesV1
    (state0Name state1Name : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ()) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeStateDeclV1)
      (decodeArray maxTableElements decodeStateDeclV1)
      #[{ id := 0, name := state0Name, typeId := 0, visibility := .public_ },
        { id := 1, name := state1Name, typeId := 0,
          visibility := .public_ }] 1 :=
  exactAt_array_two_of_exactAtV1 encodeStateDeclV1 decodeStateDeclV1
    maxTableElements (by decide) (by decide)
    (StateDeclV1.mk 0 state0Name 0 .public_)
    (StateDeclV1.mk 1 state1Name 0 .public_) 1
    (exactAt_stateDecl_publicV1 0 0 state0Name hstate0Name 1 (by decide))
    (exactAt_stateDecl_publicV1 1 0 state1Name hstate1Name 1 (by decide))

theorem exactAtRoot_invariantsV1 (invariantName : String) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1)
      #[{ id := 0, name := invariantName, callableId := 1 }] 1 :=
  exactAt_array_one_of_exactAtV1 encodeInvariantDeclV1 decodeInvariantDeclV1
    maxTableElements (by decide)
    ({ id := 0, name := invariantName, callableId := 1 } : InvariantDeclV1) 1
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl _ (by decide))

theorem exactAtRoot_requirementsV1 :
    ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1 requirementsV1 1 := by
  simpa [requirementsV1,
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.requirementsV1] using
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.exactAtRoot_requirementsV1

/-- Whole-program production-codec inversion for the parameterized family.
    This certificate alone does not imply structure or validation success. -/
theorem rootFieldInvertV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hentryName : validateIdentifierComponent entryName = .ok ())
    (hparameterName : validateIdentifierComponent parameterName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ()) :
    RootFieldInvertV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName) := by
  refine {
    qualifiedName := ?_
    types := ?_
    constants := ?_
    logicalState := ?_
    events := ?_
    errors := ?_
    callables := ?_
    invariants := ?_
    requirements := ?_
  }
  · simpa [subjectDataV1] using
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_qualifiedName qualifiedName)
        (by decide : 1 < maxNesting))
  · simpa [subjectDataV1] using exactAtRoot_typesV1
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeConstantV1 decodeConstantV1
        maxTableElements 1)
  · simpa [subjectDataV1] using
      exactAtRoot_statesV1 state0Name state1Name hstate0Name hstate1Name
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeEventDeclV1 decodeEventDeclV1
        maxTableElements 1)
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeErrorDeclV1 decodeErrorDeclV1
        maxTableElements 1)
  · simpa [subjectDataV1, callablesV1] using
      exactAt_storeParameterEqualityCallableTableV1 0 1 entryName
        parameterName invariantName 0 1 0 1 hentryName hparameterName
        hinvariantName
  · simpa [subjectDataV1] using exactAtRoot_invariantsV1 invariantName
  · simpa [subjectDataV1] using exactAtRoot_requirementsV1

end ProofForgeV2.Semantic.StatefulEqualitySubjectV1
