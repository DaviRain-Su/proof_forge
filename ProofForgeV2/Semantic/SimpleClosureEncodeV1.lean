import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1
import Init.Data.ByteArray.Lemmas

/-
  ProofForgeV2.Semantic.SimpleClosureEncodeV1 — B-SC-ENC

  Sole production post-gate body is `encodeSemanticProgramDataBodyV1`
  (root `encodeSemanticProgramDataV1` = gates then body). This module owns
  the name-parameterized wire-byte carrier for the simple-closure family and
  closes encode success under `SimpleClosureParamsLegalV1` without a second
  field-composition authority.

  Target:

    SimpleClosureParamsLegalV1 p
      ⊢ encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p)
          = .ok (simpleClosureWireBytesV1 p)

  No Tests FQN, second encoder, axiom, sorry, native_decide, ofReduceBool,
  unsafe, meta, or IO proof escape.
-/

set_option maxHeartbeats 8000000
set_option maxRecDepth 400000

namespace ProofForgeV2.Semantic.SimpleClosureEncodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

/-! ### Sole wireBytes owner = production body of materialize(p) -/

def encodeSimpleClosureDataFieldsV1 (p : SimpleClosureParamsV1) :
    Except SemanticWireErrorV1 ByteArray :=
  encodeSemanticProgramDataBodyV1 (materializeSimpleClosureDataV1 p)

def simpleClosureWireBytesV1 (p : SimpleClosureParamsV1) : ByteArray :=
  match encodeSimpleClosureDataFieldsV1 p with
  | .ok b => b
  | .error _ => ByteArray.empty

def simpleClosureWireBytesV1? (p : SimpleClosureParamsV1) : Option ByteArray :=
  match encodeSimpleClosureDataFieldsV1 p with
  | .ok b => some b
  | .error _ => none

theorem simpleClosureWireBytesV1_eq_of_fields_ok
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (h : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    simpleClosureWireBytesV1 p = b := by
  simp [simpleClosureWireBytesV1, h]

theorem simpleClosureWireBytesV1?_eq_of_fields_ok
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (h : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    simpleClosureWireBytesV1? p = some b := by
  simp [simpleClosureWireBytesV1?, h]

theorem simpleClosureWireBytesV1?_eq_some_wireBytes
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (h : simpleClosureWireBytesV1? p = some b) :
    simpleClosureWireBytesV1 p = b := by
  cases hfields : encodeSimpleClosureDataFieldsV1 p with
  | error e => simp [simpleClosureWireBytesV1?, hfields] at h
  | ok b' =>
      have hb := simpleClosureWireBytesV1_eq_of_fields_ok p b' hfields
      have hb' : b' = b := by
        have := simpleClosureWireBytesV1?_eq_of_fields_ok p b' hfields
        rw [this] at h
        exact Option.some.inj h
      rw [hb, hb']

/-! ### Identifier → encodeString -/

theorem utf8ByteSize_le_240_of_ident
    (value : String) (h : validateIdentifierComponent value = .ok ()) :
    value.utf8ByteSize ≤ 240 := by
  unfold validateIdentifierComponent at h
  by_cases hgate : 1 ≤ value.utf8ByteSize ∧ value.utf8ByteSize ≤ 240
  · exact hgate.2
  · simp [hgate, Pure.pure, Except.pure, Bind.bind, Except.bind] at h

theorem utf8ByteSize_pos_of_ident
    (value : String) (h : validateIdentifierComponent value = .ok ()) :
    1 ≤ value.utf8ByteSize :=
  utf8ByteSize_pos_of_identifierOk value h

/-- Identifier success implies NFC success. When `requireNfc` fails the sole
    identifier validator cannot return `.ok` (size gate is independent). -/
theorem requireNfc_eq_ok_of_validateIdentifierComponent
    (value : String) (h : validateIdentifierComponent value = .ok ()) :
    requireNfc value = .ok () := by
  cases hnfc : requireNfc value with
  | ok u =>
      cases u
      rfl
  | error e =>
      -- size bounds from h
      have hpos := utf8ByteSize_pos_of_ident value h
      have h240 := utf8ByteSize_le_240_of_ident value h
      have hgate : 1 ≤ value.utf8ByteSize ∧ value.utf8ByteSize ≤ 240 :=
        ⟨hpos, h240⟩
      -- Expand validator: size gate passes, then requireNfc fails ⇒ overall error
      have hfail : validateIdentifierComponent value = .error e := by
        unfold validateIdentifierComponent
        -- unless size: passes
        have hcond :
            (1 ≤ value.utf8ByteSize && value.utf8ByteSize ≤ 240) = true := by
          simp [hgate]
        simp only [hcond, ↓reduceIte, hnfc, Bind.bind, Except.bind]
        -- remaining binds never run
        rfl
      rw [hfail] at h
      cases h

theorem toUTF8_size_le_maxString_of_validateIdentifierComponent
    (value : String) (h : validateIdentifierComponent value = .ok ()) :
    value.toUTF8.size ≤ maxStringBytes := by
  have hutf : value.toUTF8.size = value.utf8ByteSize := by
    simp [String.toUTF8_eq_toByteArray, String.size_toByteArray]
  rw [hutf]
  exact Nat.le_trans (utf8ByteSize_le_240_of_ident value h)
    (by decide : 240 ≤ maxStringBytes)

theorem encodeString_eq_ok_of_validateIdentifierComponent
    (value : String) (h : validateIdentifierComponent value = .ok ()) :
    encodeString value =
      .ok ((encodeU32le (UInt32.ofNat value.toUTF8.size)).append value.toUTF8) :=
  encodeString_eq_okV1 value
    (requireNfc_eq_ok_of_validateIdentifierComponent value h)
    (toUTF8_size_le_maxString_of_validateIdentifierComponent value h)

theorem encodeString_eq_ok_of_nfc
    (value : String) (hnfc : requireNfc value = .ok ())
    (hsize : value.toUTF8.size ≤ maxStringBytes) :
    encodeString value =
      .ok ((encodeU32le (UInt32.ofNat value.toUTF8.size)).append value.toUTF8) :=
  encodeString_eq_okV1 value hnfc hsize

theorem encodeString_eq_ok_of_ascii
    (value : String) (hascii : isAscii value = true)
    (hsize : value.toUTF8.size ≤ maxStringBytes) :
    encodeString value =
      .ok ((encodeU32le (UInt32.ofNat value.toUTF8.size)).append value.toUTF8) :=
  encodeString_eq_ok_of_nfc value (requireNfc_eq_ok_of_isAscii value hascii) hsize

theorem encodeOptionString_some_eq_ok
    (value : String) (payload : ByteArray)
    (hstr : encodeString value = .ok payload) :
    encodeOption encodeString (some value) = .ok ((encodeU8 1).append payload) := by
  simp only [encodeOption, hstr, Bind.bind, Pure.pure, Except.bind, Except.pure]

def simpleClosureEmptyTableBytesV1 : ByteArray := encodeU32le 0

theorem encodeEmptyConstants_materialize (p : SimpleClosureParamsV1) :
    encodeArray encodeConstantV1 (materializeSimpleClosureDataV1 p).constants =
      .ok simpleClosureEmptyTableBytesV1 := by
  simp [materializeSimpleClosureDataV1, simpleClosureEmptyTableBytesV1,
    encodeArray_zeroV1]

theorem encodeEmptyLogicalState_materialize (p : SimpleClosureParamsV1) :
    encodeArray encodeStateDeclV1 (materializeSimpleClosureDataV1 p).logicalState =
      .ok simpleClosureEmptyTableBytesV1 := by
  simp [materializeSimpleClosureDataV1, simpleClosureEmptyTableBytesV1,
    encodeArray_zeroV1]

theorem encodeEmptyEvents_materialize (p : SimpleClosureParamsV1) :
    encodeArray encodeEventDeclV1 (materializeSimpleClosureDataV1 p).events =
      .ok simpleClosureEmptyTableBytesV1 := by
  simp [materializeSimpleClosureDataV1, simpleClosureEmptyTableBytesV1,
    encodeArray_zeroV1]

theorem encodeEmptyErrors_materialize (p : SimpleClosureParamsV1) :
    encodeArray encodeErrorDeclV1 (materializeSimpleClosureDataV1 p).errors =
      .ok simpleClosureEmptyTableBytesV1 := by
  simp [materializeSimpleClosureDataV1, simpleClosureEmptyTableBytesV1,
    encodeArray_zeroV1]

/-! ### Pre-gates -/

theorem materialize_types_size (p : SimpleClosureParamsV1) :
    (materializeSimpleClosureDataV1 p).types.size = 2 := by
  simp [materializeSimpleClosureDataV1]

theorem materialize_constants_size (p : SimpleClosureParamsV1) :
    (materializeSimpleClosureDataV1 p).constants.size = 0 := by
  simp [materializeSimpleClosureDataV1]

theorem materialize_logicalState_size (p : SimpleClosureParamsV1) :
    (materializeSimpleClosureDataV1 p).logicalState.size = 0 := by
  simp [materializeSimpleClosureDataV1]

theorem materialize_events_size (p : SimpleClosureParamsV1) :
    (materializeSimpleClosureDataV1 p).events.size = 0 := by
  simp [materializeSimpleClosureDataV1]

theorem materialize_errors_size (p : SimpleClosureParamsV1) :
    (materializeSimpleClosureDataV1 p).errors.size = 0 := by
  simp [materializeSimpleClosureDataV1]

theorem materialize_callables_size (p : SimpleClosureParamsV1) :
    (materializeSimpleClosureDataV1 p).callables.size = 2 := by
  simp [materializeSimpleClosureDataV1]

theorem materialize_invariants_size (p : SimpleClosureParamsV1) :
    (materializeSimpleClosureDataV1 p).invariants.size = 1 := by
  simp [materializeSimpleClosureDataV1]

theorem checkTableSize_ok_of_le (n : Nat) (h : n ≤ maxTableElements) :
    checkTableSize n = .ok () := by
  simp only [checkTableSize, h, ↓reduceIte, Pure.pure, Except.pure, Bind.bind,
    Except.bind]

theorem checkTableSize_materialize_types (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).types.size = .ok () := by
  rw [materialize_types_size]; exact checkTableSize_ok_of_le 2 (by decide)

theorem checkTableSize_materialize_constants (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).constants.size = .ok () := by
  rw [materialize_constants_size]; exact checkTableSize_ok_of_le 0 (by decide)

theorem checkTableSize_materialize_logicalState (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).logicalState.size = .ok () := by
  rw [materialize_logicalState_size]; exact checkTableSize_ok_of_le 0 (by decide)

theorem checkTableSize_materialize_events (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).events.size = .ok () := by
  rw [materialize_events_size]; exact checkTableSize_ok_of_le 0 (by decide)

theorem checkTableSize_materialize_errors (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).errors.size = .ok () := by
  rw [materialize_errors_size]; exact checkTableSize_ok_of_le 0 (by decide)

theorem checkTableSize_materialize_callables (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).callables.size = .ok () := by
  rw [materialize_callables_size]; exact checkTableSize_ok_of_le 2 (by decide)

theorem checkTableSize_materialize_invariants (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).invariants.size = .ok () := by
  rw [materialize_invariants_size]; exact checkTableSize_ok_of_le 1 (by decide)

theorem validateProgramQualifiedNameShape_materialize_of_qnSize
    (p : SimpleClosureParamsV1) (hqn : 2 ≤ p.qnSize) :
    validateProgramQualifiedNameShapeV1
      (materializeSimpleClosureDataV1 p).qualifiedName = .ok () := by
  have hsize :
      (materializeSimpleClosureDataV1 p).qualifiedName.components.toArray.size =
        p.qnSize := by
    simp [materializeSimpleClosureDataV1, SimpleClosureParamsV1.toQualifiedName,
      SimpleClosureParamsV1.qnSize, NonEmptyArray.toArray, Nat.add_comm]
  simp only [validateProgramQualifiedNameShapeV1, hsize, hqn, ↓reduceIte,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem validateProgramQualifiedNameShape_materialize_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    validateProgramQualifiedNameShapeV1
      (materializeSimpleClosureDataV1 p).qualifiedName = .ok () :=
  validateProgramQualifiedNameShape_materialize_of_qnSize p legal.hqnSize

theorem validateProgramQualifiedNameShape_materialize_of_wf
    (p : SimpleClosureParamsV1) (hwf : SimpleClosureParamsWellFormedV1 p) :
    validateProgramQualifiedNameShapeV1
      (materializeSimpleClosureDataV1 p).qualifiedName = .ok () :=
  validateProgramQualifiedNameShape_materialize_of_qnSize p hwf.hqnSize

/-! ### QN encode from legal -/

theorem materialize_qn_components (p : SimpleClosureParamsV1) :
    (materializeSimpleClosureDataV1 p).qualifiedName.components.toArray =
      #[p.qnHead] ++ p.qnTail := by
  simp [materializeSimpleClosureDataV1, SimpleClosureParamsV1.toQualifiedName,
    NonEmptyArray.toArray]

theorem qn_idents_list_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    ∀ s ∈ (p.qnHead :: p.qnTail.toList),
      validateIdentifierComponent s = .ok () := by
  intro s hs
  cases hs with
  | head => exact legal.hqnHead
  | tail _ hmem =>
      obtain ⟨i, hi, rfl⟩ := List.mem_iff_getElem.mp hmem
      have hi' : i < p.qnTail.size := by
        simpa using hi
      simpa using legal.hqnTail i hi'

theorem validateQualifiedName_materialize_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    validateQualifiedName (materializeSimpleClosureDataV1 p).qualifiedName =
      .ok () := by
  simp only [validateQualifiedName, materialize_qn_components]
  have hsize : (#[p.qnHead] ++ p.qnTail).size ≤ 256 := by
    simpa [Array.size_append, SimpleClosureParamsV1.qnSize, Nat.add_comm]
      using legal.hqnCap
  simp only [hsize, ↓reduceIte, Bind.bind, Pure.pure, Except.bind, Except.pure]
  have hlist :
      (#[p.qnHead] ++ p.qnTail).toList = p.qnHead :: p.qnTail.toList := by
    simp [Array.toList_append]
  rw [hlist]
  exact validateIdentifierComponentsListV1_ok_of_forall _
    (qn_idents_list_of_legal p legal)

theorem renderQualifiedNameComponents_materialize_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    renderQualifiedNameComponents
        (materializeSimpleClosureDataV1 p).qualifiedName =
      .ok (#[p.qnHead] ++ p.qnTail) := by
  simp only [renderQualifiedNameComponents,
    validateQualifiedName_materialize_of_legal p legal, materialize_qn_components,
    Bind.bind, Pure.pure, Except.bind, Except.pure]

theorem encodeQualifiedName_materialize_ok_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    ∃ b, encodeQualifiedName (materializeSimpleClosureDataV1 p).qualifiedName =
      .ok b := by
  have hcomp := renderQualifiedNameComponents_materialize_of_legal p legal
  have hmap :
      mapCommon
          (renderQualifiedNameComponents
            (materializeSimpleClosureDataV1 p).qualifiedName) =
        .ok (#[p.qnHead] ++ p.qnTail) := by
    simp only [mapCommon, hcomp]
  have hsize : (#[p.qnHead] ++ p.qnTail).size ≤ maxArrayElements := by
    simpa [Array.size_append, SimpleClosureParamsV1.qnSize, Nat.add_comm]
      using Nat.le_trans legal.hqnCap (by decide : 256 ≤ maxArrayElements)
  have hsizeU32 : (#[p.qnHead] ++ p.qnTail).size ≤ UInt32.size - 1 := by
    simpa [Array.size_append, SimpleClosureParamsV1.qnSize, Nat.add_comm]
      using Nat.le_trans legal.hqnCap (by decide : 256 ≤ UInt32.size - 1)
  have hidents :
      ∀ s ∈ (#[p.qnHead] ++ p.qnTail).toList,
        validateIdentifierComponent s = .ok () := by
    intro s hs
    have : (#[p.qnHead] ++ p.qnTail).toList = p.qnHead :: p.qnTail.toList := by
      simp [Array.toList_append]
    rw [this] at hs
    exact qn_idents_list_of_legal p legal s hs
  obtain ⟨payload, hpayload⟩ :=
    encodeArray_ok_of_forall encodeString (#[p.qnHead] ++ p.qnTail) hsize hsizeU32
      (fun s hs =>
        ⟨_, encodeString_eq_ok_of_validateIdentifierComponent s (hidents s hs)⟩)
  refine ⟨payload, ?_⟩
  simp only [encodeQualifiedName, hmap, hpayload, Bind.bind, Except.bind]

/-! ### Packaging: gates + body success ⇒ root = wireBytes -/

theorem encodeSemanticProgramDataV1_eq_ok_of_body_ok
    (data : SemanticProgramDataV1) (b : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 data.qualifiedName = .ok ())
    (htypesSize : checkTableSize data.types.size = .ok ())
    (hconstantsSize : checkTableSize data.constants.size = .ok ())
    (hstateSize : checkTableSize data.logicalState.size = .ok ())
    (heventsSize : checkTableSize data.events.size = .ok ())
    (herrorsSize : checkTableSize data.errors.size = .ok ())
    (hcallablesSize : checkTableSize data.callables.size = .ok ())
    (hinvariantsSize : checkTableSize data.invariants.size = .ok ())
    (hstructure : validateSemanticProgramStructureV1 data = .ok ())
    (hbody : encodeSemanticProgramDataBodyV1 data = .ok b) :
    encodeSemanticProgramDataV1 data = .ok b := by
  rw [encodeSemanticProgramDataV1_eq_body_of_gates data hnameShape htypesSize
    hconstantsSize hstateSize heventsSize herrorsSize hcallablesSize
    hinvariantsSize hstructure, hbody]

/-- Core packaging: legal + body success ⇒ root encode = wireBytes. -/
theorem encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1_of_body_ok
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (hbody : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok (simpleClosureWireBytesV1 p) := by
  have hb := simpleClosureWireBytesV1_eq_of_fields_ok p b hbody
  have hbody' :
      encodeSemanticProgramDataBodyV1 (materializeSimpleClosureDataV1 p) = .ok b := by
    simpa [encodeSimpleClosureDataFieldsV1] using hbody
  have hroot :=
    encodeSemanticProgramDataV1_eq_ok_of_body_ok
      (materializeSimpleClosureDataV1 p) b
      (validateProgramQualifiedNameShape_materialize_of_legal p legal)
      (checkTableSize_materialize_types p)
      (checkTableSize_materialize_constants p)
      (checkTableSize_materialize_logicalState p)
      (checkTableSize_materialize_events p)
      (checkTableSize_materialize_errors p)
      (checkTableSize_materialize_callables p)
      (checkTableSize_materialize_invariants p)
      (structure_of_legal p legal) hbody'
  rw [hroot, hb]

/-- Legacy packaging under free structure + free field-ok (still useful for
    incremental callers). Prefer the legal-only theorem when body success is
    discharged. -/
theorem encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1
    (p : SimpleClosureParamsV1)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hstructure :
      validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) = .ok ())
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok (simpleClosureWireBytesV1 p)) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok (simpleClosureWireBytesV1 p) := by
  have hbody' :
      encodeSemanticProgramDataBodyV1 (materializeSimpleClosureDataV1 p) =
        .ok (simpleClosureWireBytesV1 p) := by
    simpa [encodeSimpleClosureDataFieldsV1] using hfields
  exact encodeSemanticProgramDataV1_eq_ok_of_body_ok
    (materializeSimpleClosureDataV1 p) (simpleClosureWireBytesV1 p)
    (validateProgramQualifiedNameShape_materialize_of_wf p hwf)
    (checkTableSize_materialize_types p)
    (checkTableSize_materialize_constants p)
    (checkTableSize_materialize_logicalState p)
    (checkTableSize_materialize_events p)
    (checkTableSize_materialize_errors p)
    (checkTableSize_materialize_callables p)
    (checkTableSize_materialize_invariants p)
    hstructure hbody'

theorem encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1_of_ok
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hstructure :
      validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) = .ok ())
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok (simpleClosureWireBytesV1 p) := by
  have hb := simpleClosureWireBytesV1_eq_of_fields_ok p b hfields
  have hfields' :
      encodeSimpleClosureDataFieldsV1 p = .ok (simpleClosureWireBytesV1 p) := by
    rw [hb]; exact hfields
  exact encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1
    p hwf hstructure hfields'

/-! ### Body success packaging (legal-only discharge lives in EncodeFieldsV1) -/

/-- B-SC-ENC main goal. Closed by `SimpleClosureEncodeFieldsV1.encodeSimpleClosure_of_legal`
    from `SimpleClosureParamsLegalV1` alone (no body-ok / field-ok / size free premises). -/
def EncodeSimpleClosureGoalV1 (p : SimpleClosureParamsV1) : Prop :=
  encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
    .ok (simpleClosureWireBytesV1 p)

theorem encodeSimpleClosureGoal_of_body_ok
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p)
    (hbody : encodeSimpleClosureDataFieldsV1 p = .ok (simpleClosureWireBytesV1 p)) :
    EncodeSimpleClosureGoalV1 p :=
  encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1_of_body_ok
    p (simpleClosureWireBytesV1 p) legal hbody

/-- Body success alone determines wireBytes and the goal under legal. -/
theorem encodeSimpleClosureGoal_of_body_exists
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p)
    (hbody : ∃ b, encodeSimpleClosureDataFieldsV1 p = .ok b) :
    EncodeSimpleClosureGoalV1 p := by
  obtain ⟨b, hb⟩ := hbody
  have hwire := simpleClosureWireBytesV1_eq_of_fields_ok p b hb
  have hb' : encodeSimpleClosureDataFieldsV1 p = .ok (simpleClosureWireBytesV1 p) := by
    rw [hwire]; exact hb
  exact encodeSimpleClosureGoal_of_body_ok p legal hb'

/-! ### Field-path success inversion (B-SC-DEC dual) -/

/-- Production field-byte witness extracted from a successful field-only encode.
    Type-valued so ByteArray payloads can be projected. -/
structure SemanticProgramFieldsOkV1 (data : SemanticProgramDataV1) (b : ByteArray) where
  qnB : ByteArray
  typesB : ByteArray
  constantsB : ByteArray
  stateB : ByteArray
  eventsB : ByteArray
  errorsB : ByteArray
  callablesB : ByteArray
  invariantsB : ByteArray
  requirementsB : ByteArray
  body : ByteArray
  hqn : encodeQualifiedName data.qualifiedName = .ok qnB
  htypes : encodeArray encodeTypeDeclV1 data.types = .ok typesB
  hconstants : encodeArray encodeConstantV1 data.constants = .ok constantsB
  hstate : encodeArray encodeStateDeclV1 data.logicalState = .ok stateB
  hevents : encodeArray encodeEventDeclV1 data.events = .ok eventsB
  herrors : encodeArray encodeErrorDeclV1 data.errors = .ok errorsB
  hcallables : encodeArray encodeCallableV1 data.callables = .ok callablesB
  hinvariants : encodeArray encodeInvariantDeclV1 data.invariants = .ok invariantsB
  hrequirements : encodeProgramRequirementsV1 data.requirements = .ok requirementsB
  hbody : encodeTagged "SemanticProgram.Data"
      #[qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB,
        invariantsB, requirementsB] = .ok body
  hb : b = (encodeMagicPrefix semanticProgramMagicV1).append body
  hsize : b.size ≤ maxCanonicalProgramBytes

/-- Invert sole field-path encode success into production field bytes + framing. -/
def encodeFieldsOnly_ok_inv
    (data : SemanticProgramDataV1) (b : ByteArray)
    (h : encodeSemanticProgramDataBodyV1 data = .ok b) :
    SemanticProgramFieldsOkV1 data b := by
  simp only [encodeSemanticProgramDataBodyV1] at h
  cases hqn : encodeQualifiedName data.qualifiedName with
  | error e => simp [hqn, Bind.bind, Except.bind] at h
  | ok qnB =>
  cases htypes : encodeArray encodeTypeDeclV1 data.types with
  | error e => simp [hqn, htypes, Bind.bind, Except.bind] at h
  | ok typesB =>
  cases hconst : encodeArray encodeConstantV1 data.constants with
  | error e => simp [hqn, htypes, hconst, Bind.bind, Except.bind] at h
  | ok constantsB =>
  cases hstate : encodeArray encodeStateDeclV1 data.logicalState with
  | error e => simp [hqn, htypes, hconst, hstate, Bind.bind, Except.bind] at h
  | ok stateB =>
  cases hevents : encodeArray encodeEventDeclV1 data.events with
  | error e => simp [hqn, htypes, hconst, hstate, hevents, Bind.bind, Except.bind] at h
  | ok eventsB =>
  cases herrors : encodeArray encodeErrorDeclV1 data.errors with
  | error e => simp [hqn, htypes, hconst, hstate, hevents, herrors, Bind.bind, Except.bind] at h
  | ok errorsB =>
  cases hcall : encodeArray encodeCallableV1 data.callables with
  | error e => simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, Bind.bind, Except.bind] at h
  | ok callablesB =>
  cases hinv : encodeArray encodeInvariantDeclV1 data.invariants with
  | error e => simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, hinv, Bind.bind, Except.bind] at h
  | ok invariantsB =>
  cases hreq : encodeProgramRequirementsV1 data.requirements with
  | error e => simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, hinv, hreq, Bind.bind, Except.bind] at h
  | ok requirementsB =>
  cases hbody : encodeTagged "SemanticProgram.Data"
      #[qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB, invariantsB, requirementsB] with
  | error e =>
      simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, hinv, hreq, hbody,
        Bind.bind, Except.bind] at h
  | ok body =>
  simp [hqn, htypes, hconst, hstate, hevents, herrors, hcall, hinv, hreq, hbody,
    Bind.bind, Pure.pure, Except.bind, Except.pure, err] at h
  by_cases hs :
      (encodeMagicPrefix semanticProgramMagicV1).size + body.size ≤ maxCanonicalProgramBytes
  · simp only [hs, ↓reduceIte, Except.ok.injEq] at h
    exact {
      qnB := qnB, typesB := typesB, constantsB := constantsB, stateB := stateB,
      eventsB := eventsB, errorsB := errorsB, callablesB := callablesB,
      invariantsB := invariantsB, requirementsB := requirementsB, body := body,
      hqn := hqn, htypes := htypes, hconstants := hconst, hstate := hstate,
      hevents := hevents, herrors := herrors, hcallables := hcall, hinvariants := hinv,
      hrequirements := hreq, hbody := hbody,
      hb := by simpa [ByteArray.append_eq] using h.symm
      hsize := by
        have hb' : b = encodeMagicPrefix semanticProgramMagicV1 ++ body := by
          simpa [ByteArray.append_eq] using h.symm
        rw [hb', ByteArray.size_append]
        exact hs
    }
  · simp only [hs, ↓reduceIte] at h
    cases h

def encodeSimpleClosureFields_ok_inv
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (h : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b :=
  encodeFieldsOnly_ok_inv (materializeSimpleClosureDataV1 p) b (by
    simpa [encodeSimpleClosureDataFieldsV1] using h)

end ProofForgeV2.Semantic.SimpleClosureEncodeV1

/-!
  ## B-SC-ENC status

  Closed (see `SimpleClosureEncodeFieldsV1`):
    * sole production body authority (`encodeSemanticProgramDataBodyV1` in WireV1)
    * `simpleClosureWireBytesV1` sole owner via that body
    * identifier → encodeString for arbitrary legal Unicode/NFC names (UTF-8 ≤240)
    * fixed Bool/UInt64 types, lit-true block, view+inv callables, InvariantDecl,
      value.bool requirements encode success under legal
    * tagged root + magic size ≤ maxCanonicalProgramBytes via qnCap ≤256
    * **legal-only main**: `encodeSimpleClosure_of_legal` /
      `EncodeSimpleClosureGoalV1` with no body-ok/field-ok/size free premises
    * Demo kernel instance; parametric Unicode capability (no ASCII restriction)
-/
