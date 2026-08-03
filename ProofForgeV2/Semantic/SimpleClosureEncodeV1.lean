import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1
import Init.Data.ByteArray.Lemmas

/-
  ProofForgeV2.Semantic.SimpleClosureEncodeV1 — B-SC-ENC

  Name-parameterized canonical wire-byte builder for the literal-true
  simple-closure family (`SimpleClosureParamsV1` / `materializeSimpleClosureDataV1`).

  Hard boundaries:
    * sole production field encoders + framing (`encodeQualifiedName`,
      `encodeArray encodeTypeDeclV1`, `encodeCallableV1`, …, `encodeTagged`,
      `encodeMagicPrefix`) — **not** a second codec authority
    * **does not** call / wrap `encodeSemanticProgramDataV1` inside the builder
    * no hardcoded Tests FQN / fixture bytes
    * no axiom / sorry / native_decide / ofReduceBool
    * structure legality remains a free production premise (B-SC-STRUCT);
      this module closes the encode-spine side under that premise + field-ok

  Composition (same field order as production root encode after gates):

    materializeSimpleClosureDataV1 p
      ── encodeSimpleClosureDataFieldsV1   (QN/types/empty×4/callables/
         invariants/requirements + tagged body + magic; no structure gate)
      ──► simpleClosureWireBytesV1 p

  Target identity (under structure + pre-gates + field success):

    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p)
      = .ok (simpleClosureWireBytesV1 p)

  ProgramElaboration may evaluate `simpleClosureWireBytesV1` / the field-path
  Except on concrete params and quote a literal `ByteArray` spine for
  comparison with Normalize carrier runtime bytes.
-/

namespace ProofForgeV2.Semantic.SimpleClosureEncodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

/-! ### Production field-path encode (no structure gate, no root wrapper) -/

/-- Shared production field sequence + root framing for any
    `SemanticProgramDataV1`. Same authorities and wire order as the
    post-structure body of `encodeSemanticProgramDataV1`. Not a second codec. -/
def encodeSemanticProgramDataFieldsOnlyV1 (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let qnB ← encodeQualifiedName data.qualifiedName
  let typesB ← encodeArray encodeTypeDeclV1 data.types
  let constantsB ← encodeArray encodeConstantV1 data.constants
  let stateB ← encodeArray encodeStateDeclV1 data.logicalState
  let eventsB ← encodeArray encodeEventDeclV1 data.events
  let errorsB ← encodeArray encodeErrorDeclV1 data.errors
  let callablesB ← encodeArray encodeCallableV1 data.callables
  let invariantsB ← encodeArray encodeInvariantDeclV1 data.invariants
  let reqB ← encodeProgramRequirementsV1 data.requirements
  let body ← encodeTagged "SemanticProgram.Data" #[
    qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB, invariantsB, reqB
  ]
  let out := (encodeMagicPrefix semanticProgramMagicV1).append body
  unless out.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  pure out

/-- Sole production field sequence + root framing for `materialize p`.
    Does **not** re-run QN-shape / table-size / structure gates. -/
def encodeSimpleClosureDataFieldsV1 (p : SimpleClosureParamsV1) :
    Except SemanticWireErrorV1 ByteArray :=
  encodeSemanticProgramDataFieldsOnlyV1 (materializeSimpleClosureDataV1 p)

/-- Total name-parameterized wire bytes. On field-path success this is the
    exact production canonical encoding of `materialize p` (once structure /
    pre-gates also succeed). Failure collapses to empty — only legal params
    are certificate subjects. -/
def simpleClosureWireBytesV1 (p : SimpleClosureParamsV1) : ByteArray :=
  match encodeSimpleClosureDataFieldsV1 p with
  | .ok b => b
  | .error _ => ByteArray.empty

/-- Optional form for elaborators / runtime checks. -/
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
  | error e =>
      simp [simpleClosureWireBytesV1?, hfields] at h
  | ok b' =>
      have hb : simpleClosureWireBytesV1 p = b' :=
        simpleClosureWireBytesV1_eq_of_fields_ok p b' hfields
      have hb' : b' = b := by
        have : simpleClosureWireBytesV1? p = some b' :=
          simpleClosureWireBytesV1?_eq_of_fields_ok p b' hfields
        rw [this] at h
        exact Option.some.inj h
      rw [hb, hb']

/-! ### Reusable string / header spine lemmas (production encoders only) -/

/-- Successful `encodeString` through sole NFC + UTF-8 length gates. -/
theorem encodeString_eq_ok_of_nfc
    (value : String)
    (hnfc : requireNfc value = .ok ())
    (hsize : value.toUTF8.size ≤ maxStringBytes) :
    encodeString value =
      .ok ((encodeU32le (UInt32.ofNat value.toUTF8.size)).append value.toUTF8) :=
  encodeString_eq_okV1 value hnfc hsize

/-- ASCII identifiers satisfy NFC without expanding Unicode tables. -/
theorem encodeString_eq_ok_of_ascii
    (value : String)
    (hascii : isAscii value = true)
    (hsize : value.toUTF8.size ≤ maxStringBytes) :
    encodeString value =
      .ok ((encodeU32le (UInt32.ofNat value.toUTF8.size)).append value.toUTF8) :=
  encodeString_eq_ok_of_nfc value (requireNfc_eq_ok_of_isAscii value hascii) hsize

/-- `encodeOption encodeString (some name)` under a successful string encode. -/
theorem encodeOptionString_some_eq_ok
    (value : String) (payload : ByteArray)
    (hstr : encodeString value = .ok payload) :
    encodeOption encodeString (some value) = .ok ((encodeU8 1).append payload) := by
  simp only [encodeOption, hstr, Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- Empty array framing (production `encodeArray`). -/
theorem encodeArray_empty_u32le_zero
    (encode : α → Except SemanticWireErrorV1 ByteArray) :
    encodeArray encode #[] = .ok (encodeU32le 0) :=
  encodeArray_zeroV1 encode

/-- Fixed empty-table spine used by materialize (constants/state/events/errors). -/
def simpleClosureEmptyTableBytesV1 : ByteArray :=
  encodeU32le 0

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

/-! ### Materialize table-size / QN-shape pre-gates (always closed for family) -/

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
  rw [materialize_types_size]
  exact checkTableSize_ok_of_le 2 (by decide)

theorem checkTableSize_materialize_constants (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).constants.size = .ok () := by
  rw [materialize_constants_size]
  exact checkTableSize_ok_of_le 0 (by decide)

theorem checkTableSize_materialize_logicalState (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).logicalState.size = .ok () := by
  rw [materialize_logicalState_size]
  exact checkTableSize_ok_of_le 0 (by decide)

theorem checkTableSize_materialize_events (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).events.size = .ok () := by
  rw [materialize_events_size]
  exact checkTableSize_ok_of_le 0 (by decide)

theorem checkTableSize_materialize_errors (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).errors.size = .ok () := by
  rw [materialize_errors_size]
  exact checkTableSize_ok_of_le 0 (by decide)

theorem checkTableSize_materialize_callables (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).callables.size = .ok () := by
  rw [materialize_callables_size]
  exact checkTableSize_ok_of_le 2 (by decide)

theorem checkTableSize_materialize_invariants (p : SimpleClosureParamsV1) :
    checkTableSize (materializeSimpleClosureDataV1 p).invariants.size = .ok () := by
  rw [materialize_invariants_size]
  exact checkTableSize_ok_of_le 1 (by decide)

/-- QN root shape from certificate well-formedness (≥2 components). -/
theorem validateProgramQualifiedNameShape_materialize_of_wf
    (p : SimpleClosureParamsV1)
    (hwf : SimpleClosureParamsWellFormedV1 p) :
    validateProgramQualifiedNameShapeV1
      (materializeSimpleClosureDataV1 p).qualifiedName = .ok () := by
  have hqn : 2 ≤ p.qnSize := hwf.hqnSize
  have hsize :
      (materializeSimpleClosureDataV1 p).qualifiedName.components.toArray.size =
        p.qnSize := by
    simp [materializeSimpleClosureDataV1, SimpleClosureParamsV1.toQualifiedName,
      SimpleClosureParamsV1.qnSize, NonEmptyArray.toArray, Nat.add_comm]
  simp only [validateProgramQualifiedNameShapeV1, hsize, hqn, ↓reduceIte,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-! ### Fixed family field encodes (name-independent helpers) -/

/-- Anonymous Bool + UInt64 type table is fixed for every `p`. -/
theorem encodeTypes_materialize (p : SimpleClosureParamsV1) (typesB : ByteArray)
    (h : encodeArray encodeTypeDeclV1
      #[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1] = .ok typesB) :
    encodeArray encodeTypeDeclV1 (materializeSimpleClosureDataV1 p).types =
      .ok typesB := by
  simpa [materializeSimpleClosureDataV1] using h

/-- Sole `value.bool` requirements row is fixed for every `p`. -/
theorem encodeRequirements_materialize (p : SimpleClosureParamsV1) (reqB : ByteArray)
    (h : encodeProgramRequirementsV1 { items := #[simpleClosureBoolRequirementV1] } =
      .ok reqB) :
    encodeProgramRequirementsV1 (materializeSimpleClosureDataV1 p).requirements =
      .ok reqB := by
  simpa [materializeSimpleClosureDataV1] using h

/-- Callables array is exactly view(name) + inv(name). -/
theorem encodeCallables_materialize_of_two
    (p : SimpleClosureParamsV1) (viewB invB : ByteArray)
    (hview : encodeCallableV1 (simpleClosureViewCallableV1 p.viewName) = .ok viewB)
    (hinv : encodeCallableV1 (simpleClosureInvCallableV1 p.invName) = .ok invB) :
    encodeArray encodeCallableV1 (materializeSimpleClosureDataV1 p).callables =
      .ok ((encodeU32le 2).append (viewB.append invB)) := by
  have htwo :=
    encodeArray_twoV1 encodeCallableV1
      (simpleClosureViewCallableV1 p.viewName)
      (simpleClosureInvCallableV1 p.invName)
      viewB invB hview hinv
  simpa [materializeSimpleClosureDataV1] using htwo

/-- Invariants array is the single dense row for `invName`. -/
theorem encodeInvariants_materialize_of_one
    (p : SimpleClosureParamsV1) (invDeclB : ByteArray)
    (h : encodeInvariantDeclV1 (simpleClosureInvariantDeclV1 p.invName) = .ok invDeclB) :
    encodeArray encodeInvariantDeclV1 (materializeSimpleClosureDataV1 p).invariants =
      .ok ((encodeU32le 1).append invDeclB) := by
  have hone :=
    encodeArray_oneV1 encodeInvariantDeclV1
      (simpleClosureInvariantDeclV1 p.invName) invDeclB h
  simpa [materializeSimpleClosureDataV1] using hone

/-! ### Root encode ↔ field-path composition -/

/-- Under production pre-gates + structure, root encode reduces to the shared
    field-only path. Proved via the existing `encodeSemanticProgramDataV1_eq_of_fields`
    seam once field-path success supplies every field byte. -/
theorem encodeSemanticProgramDataV1_eq_ok_of_fieldsOnly_ok
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
    (hfields : encodeSemanticProgramDataFieldsOnlyV1 data = .ok b) :
    encodeSemanticProgramDataV1 data = .ok b := by
  -- Expand field-only success into the root encoder's post-gate body.
  -- Both paths share the same field authorities in the same order.
  revert hfields
  simp only [encodeSemanticProgramDataFieldsOnlyV1, encodeSemanticProgramDataV1,
    hnameShape, htypesSize, hconstantsSize, hstateSize, heventsSize, herrorsSize,
    hcallablesSize, hinvariantsSize, hstructure, Bind.bind, Pure.pure, Except.bind,
    Except.pure]
  intro hfields
  exact hfields

/-- Materialize form: wf discharges QN shape + table sizes. -/
theorem encodeSemanticProgramDataV1_materialize_eq_ok_of_fields_ok
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hstructure :
      validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) = .ok ())
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) = .ok b := by
  have hfields' :
      encodeSemanticProgramDataFieldsOnlyV1 (materializeSimpleClosureDataV1 p) =
        .ok b := by
    simpa [encodeSimpleClosureDataFieldsV1] using hfields
  exact encodeSemanticProgramDataV1_eq_ok_of_fieldsOnly_ok
    (materializeSimpleClosureDataV1 p) b
    (validateProgramQualifiedNameShape_materialize_of_wf p hwf)
    (checkTableSize_materialize_types p)
    (checkTableSize_materialize_constants p)
    (checkTableSize_materialize_logicalState p)
    (checkTableSize_materialize_events p)
    (checkTableSize_materialize_errors p)
    (checkTableSize_materialize_callables p)
    (checkTableSize_materialize_invariants p)
    hstructure hfields'

/-- Core B-SC-ENC identity: structure + wf + field-path success ⇒ root encode
    yields the name-parameterized wire bytes. -/
theorem encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1
    (p : SimpleClosureParamsV1)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hstructure :
      validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) = .ok ())
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok (simpleClosureWireBytesV1 p)) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok (simpleClosureWireBytesV1 p) :=
  encodeSemanticProgramDataV1_materialize_eq_ok_of_fields_ok p
    (simpleClosureWireBytesV1 p) hwf hstructure hfields

/-- Field-path success alone determines wire bytes; package with structure. -/
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

/-- Compose successful root encode from production field-encoder results via
    the shared `encodeSemanticProgramDataV1_eq_of_fields` seam. -/
theorem encodeSemanticProgramDataV1_materialize_eq_of_field_bytes
    (p : SimpleClosureParamsV1)
    (qnB typesB constantsB stateB eventsB errorsB callablesB invariantsB
      requirementsB body : ByteArray)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hstructure :
      validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) = .ok ())
    (hname : encodeQualifiedName (materializeSimpleClosureDataV1 p).qualifiedName =
      .ok qnB)
    (htypes : encodeArray encodeTypeDeclV1 (materializeSimpleClosureDataV1 p).types =
      .ok typesB)
    (hconstants :
      encodeArray encodeConstantV1 (materializeSimpleClosureDataV1 p).constants =
        .ok constantsB)
    (hstate :
      encodeArray encodeStateDeclV1 (materializeSimpleClosureDataV1 p).logicalState =
        .ok stateB)
    (hevents :
      encodeArray encodeEventDeclV1 (materializeSimpleClosureDataV1 p).events =
        .ok eventsB)
    (herrors :
      encodeArray encodeErrorDeclV1 (materializeSimpleClosureDataV1 p).errors =
        .ok errorsB)
    (hcallables :
      encodeArray encodeCallableV1 (materializeSimpleClosureDataV1 p).callables =
        .ok callablesB)
    (hinvariants :
      encodeArray encodeInvariantDeclV1 (materializeSimpleClosureDataV1 p).invariants =
        .ok invariantsB)
    (hrequirements :
      encodeProgramRequirementsV1 (materializeSimpleClosureDataV1 p).requirements =
        .ok requirementsB)
    (hbody : encodeTagged "SemanticProgram.Data" #[qnB, typesB, constantsB, stateB,
      eventsB, errorsB, callablesB, invariantsB, requirementsB] = .ok body)
    (houtSize :
      ((encodeMagicPrefix semanticProgramMagicV1).append body).size ≤
        maxCanonicalProgramBytes) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok ((encodeMagicPrefix semanticProgramMagicV1).append body) :=
  encodeSemanticProgramDataV1_eq_of_fields
    (materializeSimpleClosureDataV1 p)
    qnB typesB constantsB stateB eventsB errorsB callablesB invariantsB
    requirementsB body
    (validateProgramQualifiedNameShape_materialize_of_wf p hwf)
    (checkTableSize_materialize_types p)
    (checkTableSize_materialize_constants p)
    (checkTableSize_materialize_logicalState p)
    (checkTableSize_materialize_events p)
    (checkTableSize_materialize_errors p)
    (checkTableSize_materialize_callables p)
    (checkTableSize_materialize_invariants p)
    hstructure hname htypes hconstants hstate hevents herrors hcallables
    hinvariants hrequirements hbody houtSize

/-- Field-path success implies wire bytes equal the magic-appended body. -/
theorem simpleClosureWireBytesV1_eq_magic_append_of_fields_ok
    (p : SimpleClosureParamsV1) (body : ByteArray)
    (hfields :
      encodeSimpleClosureDataFieldsV1 p =
        .ok ((encodeMagicPrefix semanticProgramMagicV1).append body)) :
    simpleClosureWireBytesV1 p =
      (encodeMagicPrefix semanticProgramMagicV1).append body :=
  simpleClosureWireBytesV1_eq_of_fields_ok p _ hfields

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
    (h : encodeSemanticProgramDataFieldsOnlyV1 data = .ok b) :
    SemanticProgramFieldsOkV1 data b := by
  simp only [encodeSemanticProgramDataFieldsOnlyV1] at h
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

  Closed here:
    * transparent name-parameterized field-path builder
      (`encodeSimpleClosureDataFieldsV1` / `simpleClosureWireBytesV1`)
    * shared `encodeSemanticProgramDataFieldsOnlyV1` (production field order)
    * reusable string NFC/ASCII encode lemmas (`encodeString_eq_okV1` + wrappers)
    * empty-table / materialize size / QN-shape pre-gate lemmas
    * root encode = `.ok b` under wf + structure + field-path success
    * root encode = `.ok (simpleClosureWireBytesV1 p)` under the same premises

  Residual (not forged):
    * parametric discharge of field-path success from structure alone
      (identifier NFC/UTF-8 inversion through the full structure gate;
       concrete ASCII params discharge by reduction / runtime check)
    * B-SC-STRUCT parametric structure for all well-formed `p`
    * B-SC-DEC dual decode spine
-/
