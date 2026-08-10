import ProofForgeV2.Semantic.PreservationShapeV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.SubjectDataBridgeV1
import ProofForgeV2.Semantic.Wire.CodecInvertCallableV1
import ProofForgeV2.Semantic.Wire.CodecInvertFieldsV1

/-
  ProofForgeV2.Semantic.UInt64ParitySubjectV1 — generic subject-shape bridge
  for one public UInt64 state slot with increment-by-two preservation.

  This module owns only contract-agnostic data/shape/encode/validate packaging.
  It has no closed byte golden, no pin lookup, no alternate decoder, and no
  alternate Reference admission or step.
-/

namespace ProofForgeV2.Semantic.UInt64ParitySubjectV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.SubjectDataBridgeV1
open ProofForgeV2.Semantic.WireV1

/-- Canonical TypeId 0 shape for the family. -/
def uint64Type0V1 : TypeDeclV1 :=
  { id := 0, name := none, shape := .uint 64 }

/-- Canonical TypeId 1 shape for the family. -/
def boolType1V1 : TypeDeclV1 :=
  { id := 1, name := none, shape := .bool }

/-- Canonical type table for the family. -/
def typesV1 : Array TypeDeclV1 := #[uint64Type0V1, boolType1V1]

/-- Public StateId 0 declaration for the family. -/
def publicUInt64State0V1 (stateName : String) : StateDeclV1 :=
  { id := 0, name := stateName, typeId := 0, visibility := .public_ }

/-- Requirement row helper using the production S2 version/digests. -/
def requirementV1 (id : String) (digestBytes : ByteArray) : RequirementRequestV1 := {
  id
  version := s2RequirementVersionV1
  digest := { algorithm := .sha256, bytes := digestBytes }
  predicates := #[]
}

/-- Atomic rollback requirement for the family. -/
def rollbackRequirementV1 : RequirementRequestV1 :=
  requirementV1 "failure.atomic-rollback" s2FailureAtomicRollbackDigestBytesV1

/-- Persistent state requirement for the family. -/
def persistentStateRequirementV1 : RequirementRequestV1 :=
  requirementV1 "state.persistent" s2StatePersistentDigestBytesV1

/-- Checked arithmetic requirement for the family. -/
def checkedArithmeticRequirementV1 : RequirementRequestV1 :=
  requirementV1 "value.checked-arithmetic" s2ValueCheckedArithmeticDigestBytesV1

/-- Contract-agnostic decoded semantic data for the one-slot UInt64 parity shape. -/
def subjectDataV1
    (qualifiedName : QualifiedName)
    (stateName entryName viewName invariantName : String) : SemanticProgramDataV1 := {
  qualifiedName
  types := typesV1
  constants := #[]
  logicalState := #[publicUInt64State0V1 stateName]
  events := #[]
  errors := #[]
  callables := #[
    incrementAddTwoCallableV1 0 (some entryName) 0 0,
    viewLoadCallableV1 1 (some viewName) 0 0,
    uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)]
  invariants := #[{ id := 0, name := invariantName, callableId := 2 }]
  requirements := {
    items := #[rollbackRequirementV1, persistentStateRequirementV1,
      checkedArithmeticRequirementV1]
  }
}

/-- Generated transparent subject data for this family has the exact generic
    constructor shape. -/
def ShapeMatchV1 (data : SemanticProgramDataV1) : Prop :=
  ∃ qualifiedName stateName entryName viewName invariantName,
    data = subjectDataV1 qualifiedName stateName entryName viewName invariantName

/-- The body encoder used by generated subject bytes is the production body
    authority, not a second encoder. -/
def bodyEncodeOkV1 (data : SemanticProgramDataV1) (bytes : ByteArray) : Prop :=
  encodeSemanticProgramDataBodyV1 data = .ok bytes

/-! ### Fixed root-depth packages for the non-callable fields -/

/-- The canonical UInt64/Bool table is invertible at the root field depth. -/
theorem exactAtRoot_typesV1 :
    ExactMidOffsetInvertAtV1 (encodeArray encodeTypeDeclV1)
      (decodeArray maxTableElements decodeTypeDeclV1) typesV1 1 := by
  intro b left right henc
  cases huint : encodeTypeDeclV1 uint64Type0V1 with
  | error error =>
      have harray : encodeArray encodeTypeDeclV1 typesV1 = .error error := by
        simpa [typesV1] using
          encodeArray_two_error_firstV1 encodeTypeDeclV1 uint64Type0V1 boolType1V1
            error huint
      rw [harray] at henc
      cases henc
  | ok uintB =>
      cases hbool : encodeTypeDeclV1 boolType1V1 with
      | error error =>
          have harray : encodeArray encodeTypeDeclV1 typesV1 = .error error := by
            simpa [typesV1] using
              encodeArray_two_error_secondV1 encodeTypeDeclV1 uint64Type0V1 boolType1V1
                uintB error huint hbool
          rw [harray] at henc
          cases henc
      | ok boolB =>
          simpa [typesV1, uint64Type0V1, boolType1V1] using
            decodeTypes_uint64_bool_table_of_encode_midV1 uintB boolB
              (by simpa [uint64Type0V1] using huint)
              (by simpa [boolType1V1] using hbool)
              b left right 1 (by decide) henc

/-- A singleton public UInt64 state table is invertible at root depth. -/
theorem exactAtRoot_publicUInt64StateV1
    (stateName : String)
    (hstateName : validateIdentifierComponent stateName = .ok ()) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeStateDeclV1)
      (decodeArray maxTableElements decodeStateDeclV1)
      #[publicUInt64State0V1 stateName] 1 := by
  intro b left right henc
  cases hstate : encodeStateDeclV1 (publicUInt64State0V1 stateName) with
  | error error =>
      have harray : encodeArray encodeStateDeclV1
          #[publicUInt64State0V1 stateName] = .error error :=
        encodeArray_one_errorV1 encodeStateDeclV1
          (publicUInt64State0V1 stateName) error hstate
      rw [harray] at henc
      cases henc
  | ok stateB =>
      simpa [publicUInt64State0V1] using
        decodeStateDecl_singleton_public_table_of_encode_midV1 stateName hstateName
          stateB (by simpa [publicUInt64State0V1] using hstate)
          b left right 1 (by decide) henc

/-- A singleton invariant declaration table is invertible at root depth. -/
theorem exactAtRoot_singletonInvariantV1 (invariantName : String) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1)
      #[{ id := 0, name := invariantName, callableId := 2 }] 1 := by
  intro b left right henc
  let decl : InvariantDeclV1 := { id := 0, name := invariantName, callableId := 2 }
  cases hdecl : encodeInvariantDeclV1 decl with
  | error error =>
      have harray : encodeArray encodeInvariantDeclV1 #[decl] = .error error :=
        encodeArray_one_errorV1 encodeInvariantDeclV1 decl error hdecl
      rw [show (#[decl] : Array InvariantDeclV1) =
          #[{ id := 0, name := invariantName, callableId := 2 }] by rfl] at harray
      rw [harray] at henc
      cases henc
  | ok declB =>
      have hinvert := exactMidOffsetInvert_singleton_invariant_table decl declB hdecl
      simpa [decl] using hinvert b left right 1 (by decide) henc

/-- The three exact S2 rows used by this family are invertible at root depth. -/
theorem exactAtRoot_requirementsV1 :
    ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1
      ({ items := #[rollbackRequirementV1, persistentStateRequirementV1,
        checkedArithmeticRequirementV1] } : ProgramRequirementsV1) 1 := by
  intro b left right henc
  let digest0 : Digest :=
    { algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1 }
  let digest1 : Digest :=
    { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
  let digest2 : Digest :=
    { algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1 }
  let row0 : RequirementRequestV1 := rollbackRequirementV1
  let row1 : RequirementRequestV1 := persistentStateRequirementV1
  let row2 : RequirementRequestV1 := checkedArithmeticRequirementV1
  cases hrow0 : encodeRequirementRequestV1 row0 with
  | error error =>
      have hitems : encodeArray encodeRequirementRequestV1 #[row0, row1, row2] =
          .error error :=
        encodeArray_three_error_firstV1 encodeRequirementRequestV1 row0 row1 row2
          error hrow0
      have hrequirements : encodeProgramRequirementsV1
          ({ items := #[row0, row1, row2] } : ProgramRequirementsV1) = .error error := by
        simp only [encodeProgramRequirementsV1, hitems, Bind.bind, Except.bind]
      rw [show (#[row0, row1, row2] : Array RequirementRequestV1) =
          #[rollbackRequirementV1, persistentStateRequirementV1,
            checkedArithmeticRequirementV1] by rfl] at hrequirements
      rw [hrequirements] at henc
      cases henc
  | ok row0B =>
      cases hrow1 : encodeRequirementRequestV1 row1 with
      | error error =>
          have hitems : encodeArray encodeRequirementRequestV1 #[row0, row1, row2] =
              .error error :=
            encodeArray_three_error_secondV1 encodeRequirementRequestV1 row0 row1 row2
              row0B error hrow0 hrow1
          have hrequirements : encodeProgramRequirementsV1
              ({ items := #[row0, row1, row2] } : ProgramRequirementsV1) = .error error := by
            simp only [encodeProgramRequirementsV1, hitems, Bind.bind, Except.bind]
          rw [show (#[row0, row1, row2] : Array RequirementRequestV1) =
              #[rollbackRequirementV1, persistentStateRequirementV1,
                checkedArithmeticRequirementV1] by rfl] at hrequirements
          rw [hrequirements] at henc
          cases henc
      | ok row1B =>
          cases hrow2 : encodeRequirementRequestV1 row2 with
          | error error =>
              have hitems : encodeArray encodeRequirementRequestV1 #[row0, row1, row2] =
                  .error error :=
                encodeArray_three_error_thirdV1 encodeRequirementRequestV1 row0 row1 row2
                  row0B row1B error hrow0 hrow1 hrow2
              have hrequirements : encodeProgramRequirementsV1
                  ({ items := #[row0, row1, row2] } : ProgramRequirementsV1) = .error error := by
                simp only [encodeProgramRequirementsV1, hitems, Bind.bind, Except.bind]
              rw [show (#[row0, row1, row2] : Array RequirementRequestV1) =
                  #[rollbackRequirementV1, persistentStateRequirementV1,
                    checkedArithmeticRequirementV1] by rfl] at hrequirements
              rw [hrequirements] at henc
              cases henc
          | ok row2B =>
              have hdecode :=
                decodeProgramRequirements_three_emptyPredicates_of_encode_midV1
                  "failure.atomic-rollback" "state.persistent" "value.checked-arithmetic"
                  s2RequirementVersionV1 s2RequirementVersionV1 s2RequirementVersionV1
                  digest0 digest1 digest2
                  scalarMidOffsetInvert_semVer_s2RequirementVersion
                  scalarMidOffsetInvert_semVer_s2RequirementVersion
                  scalarMidOffsetInvert_semVer_s2RequirementVersion
                  row0B row1B row2B b left right 1 (by decide)
                  (by
                    simpa [row0, rollbackRequirementV1, requirementV1, digest0] using hrow0)
                  (by
                    simpa [row1, persistentStateRequirementV1, requirementV1, digest1] using hrow1)
                  (by
                    simpa [row2, checkedArithmeticRequirementV1, requirementV1, digest2] using hrow2)
                  (by
                    simpa [row0, row1, row2, rollbackRequirementV1,
                      persistentStateRequirementV1, checkedArithmeticRequirementV1,
                      requirementV1, digest0, digest1, digest2] using henc)
              simpa [row0, row1, row2, rollbackRequirementV1,
                persistentStateRequirementV1, checkedArithmeticRequirementV1,
                requirementV1, digest0, digest1, digest2] using hdecode


/-! ### Fixed-depth callable packages for the generic parity family -/

/-- Local instruction constructor for value-producing shape proofs. -/
private def valueInstructionShapeV1
    (valueId typeId : UInt32) (op : SemanticOpV1) : InstructionV1 := {
  result := some { valueId, typeId }
  op
}

/-- Local instruction constructor for void shape proofs. -/
private def voidInstructionShapeV1 (op : SemanticOpV1) : InstructionV1 := {
  result := none
  op
}

/-- The single block of the increment-by-two entry callable. -/
private def incrementAddTwoBlockV1 : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[
    valueInstructionShapeV1 0 0 (.stateLoad 0),
    valueInstructionShapeV1 1 0 (.literal 0 two8BytesV1),
    valueInstructionShapeV1 2 0 (.binary .add 0 1),
    voidInstructionShapeV1 (.stateStore 0 2),
    valueInstructionShapeV1 3 0 (.stateLoad 0)]
  terminator := .return_ (some 3)
}

/-- The single block of the view-load callable. -/
private def viewLoadBlockV1 : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[valueInstructionShapeV1 0 0 (.stateLoad 0)]
  terminator := .return_ (some 0)
}

/-- The single block of the UInt64 parity invariant callable. -/
private def uint64ParityInvariantBlockV1 : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[
    valueInstructionShapeV1 0 0 (.stateLoad 0),
    valueInstructionShapeV1 1 0 (.literal 0 two8BytesV1),
    valueInstructionShapeV1 2 0 (.binary .mod 0 1),
    valueInstructionShapeV1 3 0 (.literal 0 zero8BytesV1),
    valueInstructionShapeV1 4 1 (.binary .eq 2 3)]
  terminator := .return_ (some 4)
}

/-- The increment-by-two block is invertible at callable-block depth. -/
private theorem exactAt_incrementAddTwoBlockV1 :
    ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1 incrementAddTwoBlockV1 2 := by
  simpa [incrementAddTwoBlockV1, valueInstructionShapeV1, voidInstructionShapeV1] using
    exactAt_block_of_fieldsV1 incrementAddTwoBlockV1 2 (by decide)
      (exactAt_array_emptyV1 encodeBlockParameterV1 decodeBlockParameterV1 maxArrayElements 3)
      (exactAt_array_five_of_exactAtV1 encodeInstructionV1 decodeInstructionV1
        maxArrayElements (by decide)
        (valueInstructionShapeV1 0 0 (.stateLoad 0))
        (valueInstructionShapeV1 1 0 (.literal 0 two8BytesV1))
        (valueInstructionShapeV1 2 0 (.binary .add 0 1))
        (voidInstructionShapeV1 (.stateStore 0 2))
        (valueInstructionShapeV1 3 0 (.stateLoad 0)) 3
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 0 0 (.stateLoad 0) 3 (by decide)
              (by decide) (exactAt_semanticOp_stateLoadV1 0 4 (by decide)))
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 1 0 (.literal 0 two8BytesV1) 3
              (by decide) (by decide)
              (exactAt_semanticOp_literalV1 0 two8BytesV1 4 (by decide)))
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 2 0 (.binary .add 0 1) 3
              (by decide) (by decide)
              (exactAt_semanticOp_binaryAddV1 0 1 4 (by decide) (by decide)))
        (by
          simpa [voidInstructionShapeV1] using
            exactAt_voidInstruction_of_opV1 (.stateStore 0 2) 3 (by decide)
              (exactAt_semanticOp_stateStoreV1 0 2 4 (by decide)))
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 3 0 (.stateLoad 0) 3 (by decide)
              (by decide) (exactAt_semanticOp_stateLoadV1 0 4 (by decide))))
      (exactAt_terminatorReturnV1 (some 3) 3 (by decide))

/-- The view-load block is invertible at callable-block depth. -/
private theorem exactAt_viewLoadBlockV1 :
    ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1 viewLoadBlockV1 2 := by
  simpa [viewLoadBlockV1, valueInstructionShapeV1] using
    exactAt_block_of_fieldsV1 viewLoadBlockV1 2 (by decide)
      (exactAt_array_emptyV1 encodeBlockParameterV1 decodeBlockParameterV1 maxArrayElements 3)
      (exactAt_array_one_of_exactAtV1 encodeInstructionV1 decodeInstructionV1
        maxArrayElements (by decide)
        (valueInstructionShapeV1 0 0 (.stateLoad 0)) 3
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 0 0 (.stateLoad 0) 3 (by decide)
              (by decide) (exactAt_semanticOp_stateLoadV1 0 4 (by decide))))
      (exactAt_terminatorReturnV1 (some 0) 3 (by decide))

/-- The UInt64 parity invariant block is invertible at callable-block depth. -/
private theorem exactAt_uint64ParityInvariantBlockV1 :
    ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1 uint64ParityInvariantBlockV1 2 := by
  simpa [uint64ParityInvariantBlockV1, valueInstructionShapeV1] using
    exactAt_block_of_fieldsV1 uint64ParityInvariantBlockV1 2 (by decide)
      (exactAt_array_emptyV1 encodeBlockParameterV1 decodeBlockParameterV1 maxArrayElements 3)
      (exactAt_array_five_of_exactAtV1 encodeInstructionV1 decodeInstructionV1
        maxArrayElements (by decide)
        (valueInstructionShapeV1 0 0 (.stateLoad 0))
        (valueInstructionShapeV1 1 0 (.literal 0 two8BytesV1))
        (valueInstructionShapeV1 2 0 (.binary .mod 0 1))
        (valueInstructionShapeV1 3 0 (.literal 0 zero8BytesV1))
        (valueInstructionShapeV1 4 1 (.binary .eq 2 3)) 3
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 0 0 (.stateLoad 0) 3 (by decide)
              (by decide) (exactAt_semanticOp_stateLoadV1 0 4 (by decide)))
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 1 0 (.literal 0 two8BytesV1) 3
              (by decide) (by decide)
              (exactAt_semanticOp_literalV1 0 two8BytesV1 4 (by decide)))
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 2 0 (.binary .mod 0 1) 3
              (by decide) (by decide)
              (exactAt_semanticOp_binaryModV1 0 1 4 (by decide) (by decide)))
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 3 0 (.literal 0 zero8BytesV1) 3
              (by decide) (by decide)
              (exactAt_semanticOp_literalV1 0 zero8BytesV1 4 (by decide)))
        (by
          simpa [valueInstructionShapeV1] using
            exactAt_valueInstruction_of_opV1 4 1 (.binary .eq 2 3) 3
              (by decide) (by decide)
              (exactAt_semanticOp_binaryEqV1 2 3 4 (by decide) (by decide))))
      (exactAt_terminatorReturnV1 (some 4) 3 (by decide))

/-- The generic increment-by-two entry callable is invertible at root callable depth. -/
theorem exactAt_incrementAddTwoCallableV1
    (entryName : String)
    (hentryName : validateIdentifierComponent entryName = .ok ()) :
    ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
      (incrementAddTwoCallableV1 0 (some entryName) 0 0) 1 := by
  simpa [incrementAddTwoCallableV1, incrementAddTwoBlockV1, valueInstructionShapeV1,
    voidInstructionShapeV1] using
    exactAt_callable_of_fieldsV1 (incrementAddTwoCallableV1 0 (some entryName) 0 0) 1
      (by decide)
      (exactAt_callableKindV1 .entry 2 (by decide))
      (exactAt_optionString_some_identifierV1 entryName hentryName 2)
      (exactAt_array_emptyV1 encodeParameterV1 decodeParameterV1 maxArrayElements 2)
      (exactAt_callableResultV1 ({ typeId := 0, visibility := .public_ } : CallableResultV1)
        2 (by decide) (by decide))
      (exactAt_array_one_of_exactAtV1 encodeBlockV1 decodeBlockV1 maxArrayElements
        (by decide) incrementAddTwoBlockV1 2 exactAt_incrementAddTwoBlockV1)
      (exactAt_array_emptyV1 encodeLoopBoundV1 decodeLoopBoundV1 maxArrayElements 2)
      (exactAt_option_noneV1 (fun value : UInt64 => pure (encodeU64le value)) decodeU64le 2)

/-- The generic UInt64 view-load callable is invertible at root callable depth. -/
theorem exactAt_viewLoadCallableV1
    (viewName : String)
    (hviewName : validateIdentifierComponent viewName = .ok ()) :
    ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
      (viewLoadCallableV1 1 (some viewName) 0 0) 1 := by
  simpa [viewLoadCallableV1, viewLoadBlockV1, valueInstructionShapeV1] using
    exactAt_callable_of_fieldsV1 (viewLoadCallableV1 1 (some viewName) 0 0) 1
      (by decide)
      (exactAt_callableKindV1 .view 2 (by decide))
      (exactAt_optionString_some_identifierV1 viewName hviewName 2)
      (exactAt_array_emptyV1 encodeParameterV1 decodeParameterV1 maxArrayElements 2)
      (exactAt_callableResultV1 ({ typeId := 0, visibility := .public_ } : CallableResultV1)
        2 (by decide) (by decide))
      (exactAt_array_one_of_exactAtV1 encodeBlockV1 decodeBlockV1 maxArrayElements
        (by decide) viewLoadBlockV1 2 exactAt_viewLoadBlockV1)
      (exactAt_array_emptyV1 encodeLoopBoundV1 decodeLoopBoundV1 maxArrayElements 2)
      (exactAt_option_noneV1 (fun value : UInt64 => pure (encodeU64le value)) decodeU64le 2)

/-- The generic UInt64 parity invariant callable is invertible at root callable depth. -/
theorem exactAt_uint64ParityInvariantCallableV1
    (invariantName : String)
    (hinvariantName : validateIdentifierComponent invariantName = .ok ()) :
    ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
      (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)) 1 := by
  simpa [uint64ParityInvariantCallableV1, uint64ParityInvariantBlockV1,
    valueInstructionShapeV1] using
    exactAt_callable_of_fieldsV1
      (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)) 1
      (by decide)
      (exactAt_callableKindV1 .invariant 2 (by decide))
      (exactAt_optionString_some_identifierV1 invariantName hinvariantName 2)
      (exactAt_array_emptyV1 encodeParameterV1 decodeParameterV1 maxArrayElements 2)
      (exactAt_callableResultV1 ({ typeId := 1, visibility := .public_ } : CallableResultV1)
        2 (by decide) (by decide))
      (exactAt_array_one_of_exactAtV1 encodeBlockV1 decodeBlockV1 maxArrayElements
        (by decide) uint64ParityInvariantBlockV1 2 exactAt_uint64ParityInvariantBlockV1)
      (exactAt_array_emptyV1 encodeLoopBoundV1 decodeLoopBoundV1 maxArrayElements 2)
      (exactAt_optionU64_someSevenV1 2)

/-- The concrete three-callable table for this family is invertible at root depth. -/
theorem exactAtRoot_callablesV1
    (entryName viewName invariantName : String)
    (hentryName : validateIdentifierComponent entryName = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ()) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeCallableV1)
      (decodeArray maxTableElements decodeCallableV1)
      #[incrementAddTwoCallableV1 0 (some entryName) 0 0,
        viewLoadCallableV1 1 (some viewName) 0 0,
        uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)] 1 :=
  exactAt_array_three_of_exactAtV1 encodeCallableV1 decodeCallableV1 maxTableElements
    (by decide)
    (incrementAddTwoCallableV1 0 (some entryName) 0 0)
    (viewLoadCallableV1 1 (some viewName) 0 0)
    (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7))
    1
    (exactAt_incrementAddTwoCallableV1 entryName hentryName)
    (exactAt_viewLoadCallableV1 viewName hviewName)
    (exactAt_uint64ParityInvariantCallableV1 invariantName hinvariantName)

/-- The complete generic family subject has a production root-codec inversion
    package for any qualified name accepted by the sole production encoder.
    Module and namespace depth are not part of the theorem surface. -/
theorem rootFieldInvertV1
    (qualifiedName : QualifiedName)
    (stateName entryName viewName invariantName : String)
    (hstateName : validateIdentifierComponent stateName = .ok ())
    (hentryName : validateIdentifierComponent entryName = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ()) :
    RootFieldInvertV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) := by
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
      (exactAt_array_emptyV1 encodeConstantV1 decodeConstantV1 maxTableElements 1)
  · simpa [subjectDataV1] using
      exactAtRoot_publicUInt64StateV1 stateName hstateName
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeEventDeclV1 decodeEventDeclV1 maxTableElements 1)
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeErrorDeclV1 decodeErrorDeclV1 maxTableElements 1)
  · simpa [subjectDataV1] using
      exactAtRoot_callablesV1 entryName viewName invariantName
        hentryName hviewName hinvariantName
  · simpa [subjectDataV1] using exactAtRoot_singletonInvariantV1 invariantName
  · simpa [subjectDataV1] using exactAtRoot_requirementsV1

/-! ### Generic production structure certificate -/

private def uint64TypeShapeBytesV1 : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64, 0]

private def boolTypeShapeBytesV1 : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0]

private theorem encodeTypeShape_uint64V1 :
    encodeTypeShapeV1 (.uint 64) = .ok uint64TypeShapeBytesV1 := by
  change encodeTagged "Type.UInt" #[encodeU16le 64] = .ok uint64TypeShapeBytesV1
  rw [encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
    (by decide) (by decide) (by decide) (by decide) (by decide)]
  rfl

private theorem encodeTypeShape_boolV1 :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok boolTypeShapeBytesV1 := by
  change encodeNullary "Type.Bool" = .ok boolTypeShapeBytesV1
  rw [encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)]
  congr 1

private theorem compare_uint64_boolV1 :
    compareByteArrayLex uint64TypeShapeBytesV1 boolTypeShapeBytesV1 = .gt := by
  rw [compareByteArrayLex]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 0 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 1 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 2 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 3 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 4 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 5 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 6 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 7 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 8 (by decide) (by decide)]
  apply compareByteArrayLexLoopV1_eq_gt
  · decide
  · decide

private theorem typeKeyNamedPrefixV1 :
    validateNamedPrefixRankV1 typesV1 = .ok () := by
  simp [typesV1, uint64Type0V1, boolType1V1, validateNamedPrefixRankV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem typeKeyPrimitiveLeafV1 :
    validatePrimitiveAnonymousTypeKeyUniquenessV1 typesV1 = .ok () := by
  simp [typesV1, uint64Type0V1, boolType1V1,
    validatePrimitiveAnonymousTypeKeyUniquenessV1,
    encodeTypeShape_uint64V1, encodeTypeShape_boolV1, compare_uint64_boolV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem typeKeyRecursiveAnonymousV1 :
    validateRecursiveAnonymousTypeKeyUniquenessV1 typesV1 = .ok () := by
  simp [typesV1, uint64Type0V1, boolType1V1,
    validateRecursiveAnonymousTypeKeyUniquenessV1, Pure.pure, Except.pure]

private theorem typeKeyNamedBodyCycleV1 :
    validateNamedBodyOptionCycleLegalityV1 typesV1 = .ok () := by
  simp [typesV1, uint64Type0V1, boolType1V1,
    validateNamedBodyOptionCycleLegalityV1, Pure.pure, Except.pure]

private theorem typeKeyPhasesV1 :
    validateTypeKeyPhasesV1 typesV1 = .ok () := by
  apply validateTypeKeyPhasesV1_eq_ok_of_phases
  · exact typeKeyNamedPrefixV1
  · exact typeKeyPrimitiveLeafV1
  · exact typeKeyRecursiveAnonymousV1
  · exact typeKeyNamedBodyCycleV1

private theorem structurePreludeV1
    (qualifiedName : QualifiedName)
    (stateName entryName viewName invariantName : String)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()) :
    validateSemanticProgramStructurePreludeV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  simp [subjectDataV1, typesV1, uint64Type0V1, boolType1V1,
    publicUInt64State0V1, incrementAddTwoCallableV1, viewLoadCallableV1,
    uint64ParityInvariantCallableV1, validateSemanticProgramStructurePreludeV1,
    checkTableIdsV1, checkTypeShapeRefs, checkTypeIdInRange,
    checkCallableIdInRange, checkIdEqualsIndex, hnameShape,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem typesStructureV1 :
    validateTypesStructureV1 typesV1 = .ok () := by
  simp [typesV1, uint64Type0V1, boolType1V1, validateTypesStructureV1,
    validateTypeDeclShapeV1, validateTypeDeclNamedRuleV1,
    legalIntegerWidthV1_64, Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem namedTypeNamesV1 :
    validateNamedTypeNameUniquenessV1 typesV1 = .ok () := by
  simp [typesV1, uint64Type0V1, boolType1V1, validateNamedTypeNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem constantsValueBytesV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateConstantsValueBytesV1 typesV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName).constants
      maxCanonicalProgramBytes = .ok maxCanonicalProgramBytes := by
  simp [subjectDataV1, validateConstantsValueBytesV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

private theorem callablesValueBytesV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateCallablesValueBytesV1 typesV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName).callables
      maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 27) := by
  have htwo0 :
      validateOpValueBytesV1 typesV1 (.literal 0 two8BytesV1)
        maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 9) := by
    simpa [typesV1, uint64Type0V1, two8BytesV1] using
      validateOpValueBytesV1_literal_uint64_eq_ok typesV1 0 uint64Type0V1
        2 0 0 0 0 0 0 0 maxCanonicalProgramBytes (by rfl) (by rfl)
        (by decide)
  have htwo1 :
      validateOpValueBytesV1 typesV1 (.literal 0 two8BytesV1)
        (maxCanonicalProgramBytes - 9) = .ok (maxCanonicalProgramBytes - 18) := by
    have h := validateOpValueBytesV1_literal_uint64_eq_ok typesV1 0 uint64Type0V1
      2 0 0 0 0 0 0 0 (maxCanonicalProgramBytes - 9) (by rfl) (by rfl)
      (by decide)
    have hbudget : maxCanonicalProgramBytes - 9 - 9 =
        maxCanonicalProgramBytes - 18 := by omega
    rw [hbudget] at h
    simpa [typesV1, uint64Type0V1, two8BytesV1] using h
  have hzero :
      validateOpValueBytesV1 typesV1 (.literal 0 zero8BytesV1)
        (maxCanonicalProgramBytes - 18) = .ok (maxCanonicalProgramBytes - 27) := by
    have h := validateOpValueBytesV1_literal_uint64_eq_ok typesV1 0 uint64Type0V1
      0 0 0 0 0 0 0 0 (maxCanonicalProgramBytes - 18) (by rfl) (by rfl)
      (by decide)
    have hbudget : maxCanonicalProgramBytes - 18 - 9 =
        maxCanonicalProgramBytes - 27 := by omega
    rw [hbudget] at h
    simpa [typesV1, uint64Type0V1, zero8BytesV1] using h
  have hload (stateId : StateIdV1) (budget : Nat) :
      validateOpValueBytesV1 typesV1 (.stateLoad stateId) budget = .ok budget := rfl
  have hstore (stateId : StateIdV1) (value : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 typesV1 (.stateStore stateId value) budget = .ok budget := rfl
  have hbinary (op : BinaryOpV1) (left right : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 typesV1 (.binary op left right) budget = .ok budget := rfl
  have hreturn (value : Option ValueIdV1) (budget : Nat) :
      validateTerminatorValueBytesV1 typesV1 (.return_ value) budget = .ok budget := rfl
  simp [subjectDataV1, incrementAddTwoCallableV1, viewLoadCallableV1,
    uint64ParityInvariantCallableV1, validateCallablesValueBytesV1,
    hload, hstore, hbinary, hreturn, htwo0, htwo1, hzero,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem constantNamesV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateConstantNameUniquenessV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName).constants = .ok () := by
  simp [subjectDataV1, validateConstantNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]

private theorem logicalStateNamesV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateLogicalStateNameUniquenessV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName).logicalState = .ok () := by
  simp [subjectDataV1, publicUInt64State0V1, validateLogicalStateNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]

private theorem eventNamesV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateEventNameUniquenessV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName).events = .ok () := by
  simp [subjectDataV1, validateEventNameUniquenessV1, checkUniqueDeclarationNamesV1,
    Pure.pure, Except.pure]

private theorem errorNamesV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateErrorNameUniquenessV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName).errors = .ok () := by
  simp [subjectDataV1, validateErrorNameUniquenessV1, checkUniqueDeclarationNamesV1,
    Pure.pure, Except.pure]

private theorem interfaceFieldNamesV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateInterfaceFieldNameUniquenessV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName).events
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName).errors = .ok () := by
  simp [subjectDataV1, validateInterfaceFieldNameUniquenessV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem callableSignaturesV1
    (entryName viewName invariantName : String)
    (hentryView : entryName ≠ viewName)
    (hentryInvariant : entryName ≠ invariantName)
    (hviewInvariant : viewName ≠ invariantName) :
    validateCallableSignaturePhasesV1 typesV1
      #[incrementAddTwoCallableV1 0 (some entryName) 0 0,
        viewLoadCallableV1 1 (some viewName) 0 0,
        uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)] = .ok () := by
  have hEntryViewBeq : (entryName == viewName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hentryView)
  have hEntryInvBeq : (entryName == invariantName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hentryInvariant)
  have hViewInvBeq : (viewName == invariantName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hviewInvariant)
  have hEntryInit : ((.entry : CallableKindV1) == .initializer) = false := by decide
  have hViewInit : ((.view : CallableKindV1) == .initializer) = false := by decide
  have hInvInit : ((.invariant : CallableKindV1) == .initializer) = false := by decide
  have hEntryInv : ((.entry : CallableKindV1) == .invariant) = false := by decide
  have hViewInv : ((.view : CallableKindV1) == .invariant) = false := by decide
  have hInvInv : ((.invariant : CallableKindV1) == .invariant) = true := by decide
  have hPublic : ((.public_ : VisibilityV1) == .public_) = true := by decide
  apply validateCallableSignaturePhasesV1_eq_ok_of_phases
  all_goals
    simp [typesV1, uint64Type0V1, boolType1V1, incrementAddTwoCallableV1,
      viewLoadCallableV1, uint64ParityInvariantCallableV1,
      validateCallableKindNamePresenceV1, validateCallableNameUniquenessV1,
      validateCallableParameterNameUniquenessV1,
      validateCallableEntryViewPresenceV1, validateInitializerCardinalityV1,
      validateInitializerResultShapeV1, validateInvariantResultShapeV1,
      validateInvariantParameterShapeV1, validateInvariantLoopBoundsShapeV1,
      validateNonClosureCallableInvariantStepsV1,
      validateInvariantRootStepsPresenceV1, hEntryInit, hViewInit, hInvInit,
      hEntryInv, hViewInv, hInvInv, hPublic, hEntryViewBeq,
      hEntryInvBeq, hViewInvBeq, Pure.pure, Except.pure,
      Bind.bind, Except.bind]

private theorem invariantDeclarationJoinV1
    (entryName viewName invariantName : String) :
    validateInvariantDeclarationJoinV1
      #[incrementAddTwoCallableV1 0 (some entryName) 0 0,
        viewLoadCallableV1 1 (some viewName) 0 0,
        uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)]
      #[{ id := 0, name := invariantName, callableId := 2 }] = .ok () := by
  have hEntryInv : ((.entry : CallableKindV1) == .invariant) = false := by decide
  have hViewInv : ((.view : CallableKindV1) == .invariant) = false := by decide
  have hInvInv : ((.invariant : CallableKindV1) == .invariant) = true := by decide
  simp [validateInvariantDeclarationJoinV1, incrementAddTwoCallableV1,
    viewLoadCallableV1, uint64ParityInvariantCallableV1, hEntryInv, hViewInv,
    hInvInv, Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem declarationIdentifierNamesV1
    (qualifiedName : QualifiedName)
    (stateName entryName viewName invariantName : String)
    (hstateName : validateIdentifierComponent stateName = .ok ())
    (hentryName : validateIdentifierComponent entryName = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ()) :
    validateDeclarationIdentifierNamesV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  have hstate := validateIdentifierNameV1_eq_ok_of_common stateName hstateName
  have hentry := validateIdentifierNameV1_eq_ok_of_common entryName hentryName
  have hview := validateIdentifierNameV1_eq_ok_of_common viewName hviewName
  have hinv := validateIdentifierNameV1_eq_ok_of_common invariantName hinvariantName
  simp [subjectDataV1, typesV1, uint64Type0V1, boolType1V1,
    publicUInt64State0V1, incrementAddTwoCallableV1,
    viewLoadCallableV1, uint64ParityInvariantCallableV1,
    validateDeclarationIdentifierNamesV1, validateTypeShapeIdentifierNamesV1,
    hstate, hentry, hview, hinv, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

private theorem programRequirementsStructureV1 :
    validateProgramRequirementsStructure
      ({ items := #[rollbackRequirementV1, persistentStateRequirementV1,
        checkedArithmeticRequirementV1] } : ProgramRequirementsV1) = .ok () := by
  simpa [rollbackRequirementV1, persistentStateRequirementV1,
    checkedArithmeticRequirementV1, requirementV1] using
    (validateProgramRequirementsStructure_failure_state_checked_eq_ok
      s2RequirementVersionV1 s2RequirementVersionV1 s2RequirementVersionV1
      { algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1 }
      { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
      { algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1 })

private theorem contextReadRequirementsV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateContextReadRequirementsV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  rfl

private theorem commitRequirementsV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateCommitRequirementsV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  rfl

private theorem envReadRequirementsV1
    (qualifiedName : QualifiedName) (stateName entryName viewName invariantName : String) :
    validateEnvReadRequirementsV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  rfl

private theorem incrementCfgV1
    (entryName : String) :
    validateCallableCfgShape (incrementAddTwoCallableV1 0 (some entryName) 0 0)
      typesV1.size typesV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    (incrementAddTwoCallableV1 0 (some entryName) 0 0) typesV1.size typesV1
    (subjectDataV1 qualifiedName stateName entryName viewName invariantName) #[true]
    ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases
      (incrementAddTwoCallableV1 0 (some entryName) 0 0) #[true]
      #[(0, 0), (1, 0), (2, 0), (3, 0)]
    · rfl
    · rfl
    · simp [checkValueIdUsesExist, incrementAddTwoCallableV1, opValueUses,
        terminatorValueUses, Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem getCfgV1
    (viewName : String) :
    validateCallableCfgShape (viewLoadCallableV1 1 (some viewName) 0 0)
      typesV1.size typesV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    (viewLoadCallableV1 1 (some viewName) 0 0) typesV1.size typesV1
    (subjectDataV1 qualifiedName stateName entryName viewName invariantName) #[true]
    ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases
      (viewLoadCallableV1 1 (some viewName) 0 0) #[true] #[(0, 0)]
    · rfl
    · rfl
    · simp [checkValueIdUsesExist, viewLoadCallableV1, opValueUses,
        terminatorValueUses, Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem evenCfgV1
    (invariantName : String) :
    validateCallableCfgShape
      (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7))
      typesV1.size typesV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7))
    typesV1.size typesV1
    (subjectDataV1 qualifiedName stateName entryName viewName invariantName) #[true]
    ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases
      (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7))
      #[true] #[(0, 0), (1, 0), (2, 0), (3, 0), (4, 0)]
    · rfl
    · rfl
    · simp [checkValueIdUsesExist, uint64ParityInvariantCallableV1, opValueUses,
        terminatorValueUses, Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem genericCfgPhasesV1
    (qualifiedName : QualifiedName)
    (stateName entryName viewName invariantName : String) :
    validateGenericCfgPhasesV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  apply validateGenericCfgPhasesV1_three_eq_ok
    (subjectDataV1 qualifiedName stateName entryName viewName invariantName)
    (incrementAddTwoCallableV1 0 (some entryName) 0 0)
    (viewLoadCallableV1 1 (some viewName) 0 0)
    (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7))
  · rfl
  · exact incrementCfgV1 entryName
  · exact getCfgV1 viewName
  · exact evenCfgV1 invariantName
  · rfl

private def closureMembersV1 : Array Bool := #[false, false, true]

private theorem closureMembershipResultV1
    (entryName viewName invariantName : String) :
    invariantClosureMembershipResultV1
      #[incrementAddTwoCallableV1 0 (some entryName) 0 0,
        viewLoadCallableV1 1 (some viewName) 0 0,
        uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)] =
      .ok closureMembersV1 := by
  simp [invariantClosureMembershipResultV1, closureMembersV1,
    incrementAddTwoCallableV1, viewLoadCallableV1, uint64ParityInvariantCallableV1]
  rfl

private theorem closureMembershipPhasesV1
    (entryName viewName invariantName : String) :
    validateInvariantClosureMembershipPhasesV1
      #[incrementAddTwoCallableV1 0 (some entryName) 0 0,
        viewLoadCallableV1 1 (some viewName) 0 0,
        uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)] =
      .ok closureMembersV1 := by
  apply validateInvariantClosureMembershipPhasesV1_eq_ok
  · rfl
  · exact closureMembershipResultV1 entryName viewName invariantName
  · apply validatePureFnInvariantClosureMembershipThreeV1
      (incrementAddTwoCallableV1 0 (some entryName) 0 0)
      (viewLoadCallableV1 1 (some viewName) 0 0)
      (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)) <;> rfl

private theorem closureDagPhasesV1
    (entryName viewName invariantName : String) :
    validateInvariantClosureDagPhasesV1
      #[incrementAddTwoCallableV1 0 (some entryName) 0 0,
        viewLoadCallableV1 1 (some viewName) 0 0,
        uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)] =
      .ok closureMembersV1 := by
  apply validateInvariantClosureDagPhasesV1_eq_ok
  · exact closureMembershipPhasesV1 entryName viewName invariantName
  · apply validateInvariantClosureDagCanonicalThreeV1
    · simp [incrementAddTwoCallableV1, viewLoadCallableV1,
        uint64ParityInvariantCallableV1]
      rfl
    · rfl
    · rfl

private theorem invariantClosurePhasesV1
    (entryName viewName invariantName : String) :
    validateInvariantClosurePhasesV1
      #[incrementAddTwoCallableV1 0 (some entryName) 0 0,
        viewLoadCallableV1 1 (some viewName) 0 0,
        uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)] =
      .ok closureMembersV1 := by
  apply validateInvariantClosurePhasesV1_eq_ok
  · exact closureDagPhasesV1 entryName viewName invariantName
  · exact (validateInvariantClosurePostDagCanonicalThreeV1
      (incrementAddTwoCallableV1 0 (some entryName) 0 0)
      (viewLoadCallableV1 1 (some viewName) 0 0)
      (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7))
      uint64ParityInvariantBlockV1 (by rfl) (by rfl) (by rfl)).1
  · exact (validateInvariantClosurePostDagCanonicalThreeV1
      (incrementAddTwoCallableV1 0 (some entryName) 0 0)
      (viewLoadCallableV1 1 (some viewName) 0 0)
      (uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7))
      uint64ParityInvariantBlockV1 (by rfl) (by rfl) (by rfl)).2

private theorem invariantFuelPhasesV1
    (entryName viewName invariantName : String) :
    validateInvariantFuelPhasesV1
      #[incrementAddTwoCallableV1 0 (some entryName) 0 0,
        viewLoadCallableV1 1 (some viewName) 0 0,
        uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)]
      closureMembersV1 = .ok () := by
  rfl

private theorem cfgInvariantPhasesV1
    (qualifiedName : QualifiedName)
    (stateName entryName viewName invariantName : String) :
    validateCfgInvariantPhasesV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok
    (subjectDataV1 qualifiedName stateName entryName viewName invariantName) closureMembersV1
  · exact genericCfgPhasesV1 qualifiedName stateName entryName viewName invariantName
  · exact invariantClosurePhasesV1 entryName viewName invariantName
  · exact invariantFuelPhasesV1 entryName viewName invariantName

/-- Every production Semantic structure phase accepts the generic one-slot UInt64
    parity subject whenever the caller supplies the production name gates and
    exact callable-name distinctness required by the same structure validator. -/
theorem structureOkV1
    (qualifiedName : QualifiedName)
    (stateName entryName viewName invariantName : String)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ())
    (hstateName : validateIdentifierComponent stateName = .ok ())
    (hentryName : validateIdentifierComponent entryName = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ())
    (hentryView : entryName ≠ viewName)
    (hentryInvariant : entryName ≠ invariantName)
    (hviewInvariant : viewName ≠ invariantName) :
    validateSemanticProgramStructureV1
      (subjectDataV1 qualifiedName stateName entryName viewName invariantName) = .ok () := by
  apply validateSemanticProgramStructureV1_eq_ok_of_phases
    (subjectDataV1 qualifiedName stateName entryName viewName invariantName)
    maxCanonicalProgramBytes (maxCanonicalProgramBytes - 27)
  · exact structurePreludeV1 qualifiedName stateName entryName viewName invariantName hnameShape
  · exact typesStructureV1
  · exact typeKeyPhasesV1
  · exact namedTypeNamesV1
  · exact constantsValueBytesV1 qualifiedName stateName entryName viewName invariantName
  · exact callablesValueBytesV1 qualifiedName stateName entryName viewName invariantName
  · exact constantNamesV1 qualifiedName stateName entryName viewName invariantName
  · exact logicalStateNamesV1 qualifiedName stateName entryName viewName invariantName
  · exact eventNamesV1 qualifiedName stateName entryName viewName invariantName
  · exact errorNamesV1 qualifiedName stateName entryName viewName invariantName
  · exact interfaceFieldNamesV1 qualifiedName stateName entryName viewName invariantName
  · simpa [subjectDataV1] using
      callableSignaturesV1 entryName viewName invariantName hentryView
        hentryInvariant hviewInvariant
  · simpa [subjectDataV1] using invariantDeclarationJoinV1 entryName viewName invariantName
  · exact declarationIdentifierNamesV1 qualifiedName stateName entryName viewName invariantName
      hstateName hentryName hviewName hinvariantName
  · exact cfgInvariantPhasesV1 qualifiedName stateName entryName viewName invariantName
  · simpa [subjectDataV1] using programRequirementsStructureV1
  · exact contextReadRequirementsV1 qualifiedName stateName entryName viewName invariantName
  · exact commitRequirementsV1 qualifiedName stateName entryName viewName invariantName
  · exact envReadRequirementsV1 qualifiedName stateName entryName viewName invariantName

end ProofForgeV2.Semantic.UInt64ParitySubjectV1
