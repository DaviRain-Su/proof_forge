import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.SimpleClosureDecodeCallableV1
import ProofForgeV2.Semantic.SimpleClosureDecodeFixedFieldsV1
import ProofForgeV2.Semantic.SimpleClosureDecodeRootQnV1
import ProofForgeV2.Semantic.SimpleClosureDecodeV1
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureEncodeFieldsV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecInvertCallableV1
import ProofForgeV2.Semantic.Wire.CodecInvertFieldsV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas
import Init.Data.Array.Extract
import Init.Data.List.ToArray

/-!
  ProofForgeV2.Semantic.SimpleClosureDecodeComposeV1 — B-SC-DEC final composition

  Closes the nine-field tagged body transport decode from sole
  `SimpleClosureParamsLegalV1` + field-path encode success, with no free
  intermediate decode / tag / parse premises on the public surface.

  Public:

    decodeSemanticProgramDataTagged_of_simpleClosure_field_bytes
      (p b legal fok)

    decodeSimpleClosure_of_fields_ok_legal
      (p b legal hfields) :
        decodeSemanticProgramDataV1 b =
          .ok (materializeSimpleClosureDataV1 p)

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
-/

set_option maxHeartbeats 8000000
set_option maxRecDepth 400000

namespace ProofForgeV2.Semantic.SimpleClosureDecodeComposeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.SimpleClosureCertV1
open ProofForgeV2.Semantic.SimpleClosureDecodeV1
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureEncodeFieldsV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

-- Prefer RootQn header/tag constants; product Wire owns taggedHeaderBytesV1.
open ProofForgeV2.Semantic.SimpleClosureDecodeRootQnV1
  (semanticProgramDataTagV1 semanticProgramDataHeaderSizeV1
    header_size fieldsOk_body_eq
    expectTag_of_fieldsOk expectTag_data_midV1)

open ProofForgeV2.Semantic.SimpleClosureDecodeFixedFieldsV1
  (typesArrayBytesV1 emptyTableBytesV1
    encodeTypes_materialize_eq_ok
    decodeTypes_simpleClosure_midV1
    decodeEmptyTable_midV1
    invariantsArrayBytesV1
    encodeInvariants_materialize_of_legal
    decodeInvariants_array_of_legal_midV1
    programRequirementsValueBoolBytesV1
    encodeRequirements_materialize_eq_ok
    decodeProgramRequirements_valueBool_midV1)

open ProofForgeV2.Semantic.SimpleClosureDecodeCallableV1
  (callablesArrayBytesV1 encode_callablesArray_of_legal
    decodeCallableArrayV1_simpleClosure_of_legal)

/-! ### QN encode: production encodeArrayChunks → stringArrayPayload -/

theorem encodeArrayChunks_strings_legal
    (xs : List String)
    (hlegal : ∀ s ∈ xs, validateIdentifierComponent s = .ok ())
    (acc : ByteArray) :
    encodeArrayChunksV1 encodeString xs acc =
      .ok (acc ++ stringArrayPayloadV1 xs) := by
  induction xs generalizing acc with
  | nil =>
      simp only [encodeArrayChunksV1, stringArrayPayloadV1, ByteArray.append_empty,
        Pure.pure, Except.pure]
  | cons s rest ih =>
      have hs : validateIdentifierComponent s = .ok () :=
        hlegal s (List.mem_cons_self)
      have hrest : ∀ t ∈ rest, validateIdentifierComponent t = .ok () :=
        fun t ht => hlegal t (List.mem_cons_of_mem _ ht)
      have hchunk : encodeString s = .ok (stringPayloadBytesV1 s) :=
        encodeString_of_identifierV1 s hs
      have htail := ih hrest (acc ++ stringPayloadBytesV1 s)
      have hpay :
          stringArrayPayloadV1 (s :: rest) =
            stringPayloadBytesV1 s ++ stringArrayPayloadV1 rest := rfl
      have hassoc :
          (acc ++ stringPayloadBytesV1 s) ++ stringArrayPayloadV1 rest =
            acc ++ stringArrayPayloadV1 (s :: rest) := by
        simp only [hpay, ByteArray.append_assoc]
      have htail' :
          encodeArrayChunksV1 encodeString rest (acc.append (stringPayloadBytesV1 s)) =
            .ok (acc ++ stringArrayPayloadV1 (s :: rest)) := by
        simpa [ByteArray.append_eq, hassoc] using htail
      exact encodeArrayChunksV1_cons encodeString s rest acc
        (stringPayloadBytesV1 s) (acc ++ stringArrayPayloadV1 (s :: rest))
        hchunk htail'

theorem encodeArrayChunks_strings_legal_empty
    (xs : List String)
    (hlegal : ∀ s ∈ xs, validateIdentifierComponent s = .ok ()) :
    encodeArrayChunksV1 encodeString xs ByteArray.empty =
      .ok (stringArrayPayloadV1 xs) := by
  have h := encodeArrayChunks_strings_legal xs hlegal ByteArray.empty
  simpa [ByteArray.empty_append] using h

theorem qnComponents_toList (p : SimpleClosureParamsV1) :
    (#[p.qnHead] ++ p.qnTail).toList = p.qnHead :: p.qnTail.toList := by
  simp [Array.toList_append]

theorem qnComponents_toArray (p : SimpleClosureParamsV1) :
    (p.qnHead :: p.qnTail.toList).toArray = #[p.qnHead] ++ p.qnTail := by
  rw [List.toArray_cons]

theorem qnComponents_size (p : SimpleClosureParamsV1) :
    (#[p.qnHead] ++ p.qnTail).size = p.qnSize := by
  simp [SimpleClosureParamsV1.qnSize, Array.size_append, Nat.add_comm]

theorem encodeArray_qnComponents_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    encodeArray encodeString (#[p.qnHead] ++ p.qnTail) =
      .ok (qualifiedNamePayloadV1 p) := by
  have hsize : (#[p.qnHead] ++ p.qnTail).size ≤ maxArrayElements := by
    have h := Nat.le_trans legal.hqnCap (by decide : 256 ≤ maxArrayElements)
    simpa [qnComponents_size p] using h
  have hsizeU32 : (#[p.qnHead] ++ p.qnTail).size ≤ UInt32.size - 1 := by
    have h := Nat.le_trans legal.hqnCap (by decide : 256 ≤ UInt32.size - 1)
    simpa [qnComponents_size p] using h
  have hlist := qn_idents_list_of_legal p legal
  have hchunks :
      encodeArrayChunksV1 encodeString (#[p.qnHead] ++ p.qnTail).toList ByteArray.empty =
        .ok (stringArrayPayloadV1 (p.qnHead :: p.qnTail.toList)) := by
    have hlegal' : ∀ s ∈ (#[p.qnHead] ++ p.qnTail).toList,
        validateIdentifierComponent s = .ok () := by
      intro s hs
      rw [qnComponents_toList] at hs
      exact hlist s hs
    have h := encodeArrayChunks_strings_legal_empty
      (#[p.qnHead] ++ p.qnTail).toList hlegal'
    simpa [qnComponents_toList] using h
  have henc :=
    encodeArray_eq_of_chunksV1 encodeString (#[p.qnHead] ++ p.qnTail)
      (stringArrayPayloadV1 (p.qnHead :: p.qnTail.toList))
      hsize hsizeU32 hchunks
  have hsz : (#[p.qnHead] ++ p.qnTail).size = p.qnSize := qnComponents_size p
  have hpay :
      qualifiedNamePayloadV1 p =
        encodeU32le (UInt32.ofNat p.qnSize) ++
          stringArrayPayloadV1 (p.qnHead :: p.qnTail.toList) := rfl
  rw [henc, hpay, hsz]
  simp only [ByteArray.append_eq]

theorem encodeQualifiedName_materialize_eq_payload_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    encodeQualifiedName (materializeSimpleClosureDataV1 p).qualifiedName =
      .ok (qualifiedNamePayloadV1 p) := by
  have hcomp := renderQualifiedNameComponents_materialize_of_legal p legal
  have hmap :
      mapCommon
          (renderQualifiedNameComponents
            (materializeSimpleClosureDataV1 p).qualifiedName) =
        .ok (#[p.qnHead] ++ p.qnTail) := by
    simp only [mapCommon, hcomp]
  have harr := encodeArray_qnComponents_of_legal p legal
  simp only [encodeQualifiedName, hmap, harr, Bind.bind, Except.bind]

/-! ### parseQualifiedName restores `p.toQualifiedName` under Legal -/

theorem ofArray_qnComponents (p : SimpleClosureParamsV1)
    (hpos : 0 < (#[p.qnHead] ++ p.qnTail).size) :
    NonEmptyArray.ofArray (#[p.qnHead] ++ p.qnTail) =
      .ok { head := p.qnHead, tail := p.qnTail } := by
  unfold NonEmptyArray.ofArray
  simp only [hpos, ↓reduceDIte]
  have hlt : 0 < (#[p.qnHead] : Array String).size := by simp
  have hhead :
      (#[p.qnHead] ++ p.qnTail)[0]'(hpos) = p.qnHead := by
    rw [Array.getElem_append_left (hlt := hlt)]
    simp
  have htail :
      (#[p.qnHead] ++ p.qnTail).extract 1 (#[p.qnHead] ++ p.qnTail).size =
        p.qnTail := by
    have hsz : (#[p.qnHead] ++ p.qnTail).size = 1 + p.qnTail.size := by
      simp [Array.size_append]
    have h1 :
        (#[p.qnHead] ++ p.qnTail).extract 1 (1 + p.qnTail.size) =
          (#[p.qnHead] : Array String).extract 1 (1 + p.qnTail.size) ++
            p.qnTail.extract 0 p.qnTail.size := by
      simpa using
        (Array.extract_append (as := #[p.qnHead]) (bs := p.qnTail)
          (i := 1) (j := 1 + p.qnTail.size))
    have hempty :
        (#[p.qnHead] : Array String).extract 1 (1 + p.qnTail.size) = #[] :=
      Array.extract_eq_empty_of_le (by simp)
    have hself : p.qnTail.extract 0 p.qnTail.size = p.qnTail :=
      Array.extract_eq_self_of_le (by omega)
    have hgoal :
        (#[p.qnHead] ++ p.qnTail).extract 1 (1 + p.qnTail.size) = p.qnTail := by
      rw [h1, hempty, hself]; simp
    simpa [hsz] using hgoal
  -- Rewrite the ofArray result using the two field equalities.
  simp only [hhead, htail]

theorem parseQualifiedName_qnComponents_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    parseQualifiedName (#[p.qnHead] ++ p.qnTail) = .ok (p.toQualifiedName) := by
  have hpos : 0 < (#[p.qnHead] ++ p.qnTail).size := by
    have : 2 ≤ p.qnSize := legal.hqnSize
    have hsz := qnComponents_size p
    omega
  have hof := ofArray_qnComponents p hpos
  have hval := validateQualifiedName_materialize_of_legal p legal
  have hmat :
      (materializeSimpleClosureDataV1 p).qualifiedName = p.toQualifiedName := by
    simp [materializeSimpleClosureDataV1]
  rw [hmat] at hval
  -- Unfold parse after ofArray success; discharge validate with hval.
  have hqn :
      ({ head := p.qnHead, tail := p.qnTail } : NonEmptyArray String) =
        p.toQualifiedName.components := by
    simp only [SimpleClosureParamsV1.toQualifiedName]
  simp only [parseQualifiedName, hof, Bind.bind, Except.bind]
  -- Goal: match validateQualifiedName {components := {head,tail}} ...
  have hval' :
      validateQualifiedName { components := { head := p.qnHead, tail := p.qnTail } } =
        .ok () := by
    simpa [SimpleClosureParamsV1.toQualifiedName] using hval
  simp only [hval', Pure.pure, Except.pure, SimpleClosureParamsV1.toQualifiedName]

theorem parseQualifiedName_list_toArray_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    parseQualifiedName ((p.qnHead :: p.qnTail.toList).toArray) =
      .ok (p.toQualifiedName) := by
  simpa [qnComponents_toArray] using parseQualifiedName_qnComponents_of_legal p legal

/-! ### QN mid-offset decode under Legal (no free hparse/hdecode) -/

theorem decodeQualifiedName_of_legal_midV1
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) (nesting : Nat) :
    decodeQualifiedName
        ⟨left ++ qualifiedNamePayloadV1 p ++ right, left.size, nesting⟩ =
      .ok (p.toQualifiedName,
        ⟨left ++ qualifiedNamePayloadV1 p ++ right,
          left.size + (qualifiedNamePayloadV1 p).size, nesting⟩) := by
  have hfit : p.qnSize ≤ UInt32.size - 1 :=
    Nat.le_trans legal.hqnCap (by decide : 256 ≤ UInt32.size - 1)
  have hmax : p.qnSize ≤ 256 := legal.hqnCap
  have harr :=
    decodeArray_qnComponents_of_legal left right p legal nesting hfit hmax
  have hparse := parseQualifiedName_list_toArray_of_legal p legal
  exact decodeQualifiedName_eq_of_arrayV1
    ⟨left ++ qualifiedNamePayloadV1 p ++ right, left.size, nesting⟩
    ⟨left ++ qualifiedNamePayloadV1 p ++ right,
      left.size + (qualifiedNamePayloadV1 p).size, nesting⟩
    ((p.qnHead :: p.qnTail.toList).toArray) (p.toQualifiedName)
    harr hparse

/-! ### FieldsOk → three leaf canonical byte spines (Except.ok injectivity) -/

theorem fieldsOk_qnB_eq
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.qnB = qualifiedNamePayloadV1 p := by
  have hprod := encodeQualifiedName_materialize_eq_payload_of_legal p legal
  exact Except.ok.inj (fok.hqn.symm.trans hprod)

theorem fieldsOk_typesB_eq
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.typesB = typesArrayBytesV1 := by
  have hprod := encodeTypes_materialize_eq_ok p
  exact Except.ok.inj (fok.htypes.symm.trans hprod)

theorem fieldsOk_constantsB_eq
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.constantsB = emptyTableBytesV1 := by
  have hprod := encodeEmptyConstants_materialize p
  have hdef : simpleClosureEmptyTableBytesV1 = emptyTableBytesV1 := rfl
  exact Except.ok.inj (fok.hconstants.symm.trans (by simpa [hdef] using hprod))

theorem fieldsOk_stateB_eq
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.stateB = emptyTableBytesV1 := by
  have hprod := encodeEmptyLogicalState_materialize p
  have hdef : simpleClosureEmptyTableBytesV1 = emptyTableBytesV1 := rfl
  exact Except.ok.inj (fok.hstate.symm.trans (by simpa [hdef] using hprod))

theorem fieldsOk_eventsB_eq
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.eventsB = emptyTableBytesV1 := by
  have hprod := encodeEmptyEvents_materialize p
  have hdef : simpleClosureEmptyTableBytesV1 = emptyTableBytesV1 := rfl
  exact Except.ok.inj (fok.hevents.symm.trans (by simpa [hdef] using hprod))

theorem fieldsOk_errorsB_eq
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.errorsB = emptyTableBytesV1 := by
  have hprod := encodeEmptyErrors_materialize p
  have hdef : simpleClosureEmptyTableBytesV1 = emptyTableBytesV1 := rfl
  exact Except.ok.inj (fok.herrors.symm.trans (by simpa [hdef] using hprod))

theorem encode_callables_materialize_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    encodeArray encodeCallableV1 (materializeSimpleClosureDataV1 p).callables =
      .ok (callablesArrayBytesV1 p) := by
  simpa [materializeSimpleClosureDataV1] using encode_callablesArray_of_legal p legal

theorem fieldsOk_callablesB_eq
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.callablesB = callablesArrayBytesV1 p := by
  have hprod := encode_callables_materialize_of_legal p legal
  exact Except.ok.inj (fok.hcallables.symm.trans hprod)

theorem fieldsOk_invariantsB_eq
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.invariantsB = invariantsArrayBytesV1 p.invName := by
  have hprod := encodeInvariants_materialize_of_legal p legal
  exact Except.ok.inj (fok.hinvariants.symm.trans hprod)

theorem fieldsOk_requirementsB_eq
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.requirementsB = programRequirementsValueBoolBytesV1 := by
  have hprod := encodeRequirements_materialize_eq_ok p
  exact Except.ok.inj (fok.hrequirements.symm.trans hprod)

/-! ### Nine-field body layout on production `b` -/

theorem fieldsOk_body_layout_of_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    fok.body =
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
        qualifiedNamePayloadV1 p ++ typesArrayBytesV1 ++
        emptyTableBytesV1 ++ emptyTableBytesV1 ++
        emptyTableBytesV1 ++ emptyTableBytesV1 ++
        callablesArrayBytesV1 p ++
        invariantsArrayBytesV1 p.invName ++
        programRequirementsValueBoolBytesV1 := by
  have hbase := fieldsOk_body_eq (materializeSimpleClosureDataV1 p) b fok
  rw [hbase,
    fieldsOk_qnB_eq p b legal fok,
    fieldsOk_typesB_eq p b fok,
    fieldsOk_constantsB_eq p b fok,
    fieldsOk_stateB_eq p b fok,
    fieldsOk_eventsB_eq p b fok,
    fieldsOk_errorsB_eq p b fok,
    fieldsOk_callablesB_eq p b legal fok,
    fieldsOk_invariantsB_eq p b legal fok,
    fieldsOk_requirementsB_eq p b fok]

theorem fieldsOk_bytes_layout_of_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    b =
      encodeMagicPrefix semanticProgramMagicV1 ++
        taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
        qualifiedNamePayloadV1 p ++ typesArrayBytesV1 ++
        emptyTableBytesV1 ++ emptyTableBytesV1 ++
        emptyTableBytesV1 ++ emptyTableBytesV1 ++
        callablesArrayBytesV1 p ++
        invariantsArrayBytesV1 p.invName ++
        programRequirementsValueBoolBytesV1 := by
  have hb : b = encodeMagicPrefix semanticProgramMagicV1 ++ fok.body := by
    simpa [ByteArray.append_eq] using fok.hb
  rw [hb, fieldsOk_body_layout_of_legal p b legal fok]
  simp only [ByteArray.append_assoc]

/-! ### Cursor offsets after magic + header + successive fields -/

private abbrev magicSizeV1 : Nat := (encodeMagicPrefix semanticProgramMagicV1).size
private abbrev headerSizeV1 : Nat := semanticProgramDataHeaderSizeV1

private def oTag (_p : SimpleClosureParamsV1) : Nat :=
  magicSizeV1 + headerSizeV1

private def oTypes (p : SimpleClosureParamsV1) : Nat :=
  oTag p + (qualifiedNamePayloadV1 p).size

private def oConst (p : SimpleClosureParamsV1) : Nat :=
  oTypes p + typesArrayBytesV1.size

private def oState (p : SimpleClosureParamsV1) : Nat :=
  oConst p + emptyTableBytesV1.size

private def oEvents (p : SimpleClosureParamsV1) : Nat :=
  oState p + emptyTableBytesV1.size

private def oErrors (p : SimpleClosureParamsV1) : Nat :=
  oEvents p + emptyTableBytesV1.size

private def oCallables (p : SimpleClosureParamsV1) : Nat :=
  oErrors p + emptyTableBytesV1.size

private def oInvariants (p : SimpleClosureParamsV1) : Nat :=
  oCallables p + (callablesArrayBytesV1 p).size

private def oRequirements (p : SimpleClosureParamsV1) : Nat :=
  oInvariants p + (invariantsArrayBytesV1 p.invName).size

private def oEnd (p : SimpleClosureParamsV1) : Nat :=
  oRequirements p + programRequirementsValueBoolBytesV1.size

theorem fieldsOk_end_offset
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    oEnd p = b.size := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  have hhs : (taggedHeaderBytesV1 semanticProgramDataTagV1 9).size = headerSizeV1 :=
    header_size
  have hszEmpty : emptyTableBytesV1.size = 4 := encodeU32le_sizeV1 0
  -- Expand both sides to the same size sum.
  change
    magicSizeV1 + headerSizeV1 +
        (qualifiedNamePayloadV1 p).size + typesArrayBytesV1.size +
        emptyTableBytesV1.size + emptyTableBytesV1.size +
        emptyTableBytesV1.size + emptyTableBytesV1.size +
        (callablesArrayBytesV1 p).size +
        (invariantsArrayBytesV1 p.invName).size +
        programRequirementsValueBoolBytesV1.size =
      b.size
  rw [hlayout]
  simp only [ByteArray.size_append, hhs, hszEmpty]

/-! ### Nine field successes at nesting = 1 on production `b` -/

theorem expectTag_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (_legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    expectTag "SemanticProgram.Data" 9 ⟨b, magicSizeV1, 1⟩ =
      .ok ((), ⟨b, oTag p, 1⟩) := by
  have h := expectTag_of_fieldsOk (materializeSimpleClosureDataV1 p) b fok 1
  simpa [magicSizeV1, oTag, headerSizeV1] using h

theorem decodeQualifiedName_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeQualifiedName ⟨b, oTag p, 1⟩ =
      .ok (p.toQualifiedName, ⟨b, oTypes p, 1⟩) := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  let L := encodeMagicPrefix semanticProgramMagicV1 ++
    taggedHeaderBytesV1 semanticProgramDataTagV1 9
  let R :=
    typesArrayBytesV1 ++ emptyTableBytesV1 ++ emptyTableBytesV1 ++
      emptyTableBytesV1 ++ emptyTableBytesV1 ++ callablesArrayBytesV1 p ++
      invariantsArrayBytesV1 p.invName ++ programRequirementsValueBoolBytesV1
  have hin : b = L ++ qualifiedNamePayloadV1 p ++ R := by
    rw [hlayout]
    simp only [L, R, ByteArray.append_assoc]
  have hL : L.size = oTag p := by
    simp only [L, oTag, magicSizeV1, headerSizeV1, ByteArray.size_append,
      header_size]
  have hoff : oTag p + (qualifiedNamePayloadV1 p).size = oTypes p := by
    simp only [oTypes, oTag]
  have h := decodeQualifiedName_of_legal_midV1 L R p legal 1
  rw [← hin, hL, hoff] at h
  exact h

theorem decodeTypes_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeArray maxTableElements decodeTypeDeclV1 ⟨b, oTypes p, 1⟩ =
      .ok (#[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1],
        ⟨b, oConst p, 1⟩) := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  let L :=
    encodeMagicPrefix semanticProgramMagicV1 ++
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
      qualifiedNamePayloadV1 p
  let R :=
    emptyTableBytesV1 ++ emptyTableBytesV1 ++ emptyTableBytesV1 ++
      emptyTableBytesV1 ++ callablesArrayBytesV1 p ++
      invariantsArrayBytesV1 p.invName ++ programRequirementsValueBoolBytesV1
  have hin : b = L ++ typesArrayBytesV1 ++ R := by
    rw [hlayout]; simp only [L, R, ByteArray.append_assoc]
  have hL : L.size = oTypes p := by
    simp only [L, oTypes, oTag, magicSizeV1, headerSizeV1, ByteArray.size_append,
      header_size]
  have hoff : oTypes p + typesArrayBytesV1.size = oConst p := by
    simp only [oConst, oTypes]
  have hdepth : (1 : Nat) + 1 < maxNesting := by decide
  have h := decodeTypes_simpleClosure_midV1 L R 1 hdepth
  rw [← hin, hL, hoff] at h
  exact h

private theorem decodeEmpty_at
    (decode : Decoder α) (left right : ByteArray) (nesting : Nat) :
    decodeArray maxTableElements decode
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, nesting⟩ =
      .ok (#[], ⟨left ++ emptyTableBytesV1 ++ right, left.size + 4, nesting⟩) :=
  decodeEmptyTable_midV1 maxTableElements decode left right nesting

theorem decodeConstants_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeArray maxTableElements decodeConstantV1 ⟨b, oConst p, 1⟩ =
      .ok (#[], ⟨b, oState p, 1⟩) := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  let L :=
    encodeMagicPrefix semanticProgramMagicV1 ++
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
      qualifiedNamePayloadV1 p ++ typesArrayBytesV1
  let R :=
    emptyTableBytesV1 ++ emptyTableBytesV1 ++ emptyTableBytesV1 ++
      callablesArrayBytesV1 p ++ invariantsArrayBytesV1 p.invName ++
      programRequirementsValueBoolBytesV1
  have hin : b = L ++ emptyTableBytesV1 ++ R := by
    rw [hlayout]; simp only [L, R, ByteArray.append_assoc]
  have hL : L.size = oConst p := by
    simp only [L, oConst, oTypes, oTag, magicSizeV1, headerSizeV1,
      ByteArray.size_append, header_size]
  have hszEmpty : emptyTableBytesV1.size = 4 := encodeU32le_sizeV1 0
  have hoff : oConst p + 4 = oState p := by
    simp only [oState, oConst, hszEmpty]
  have h := decodeEmpty_at decodeConstantV1 L R 1
  rw [← hin, hL, hoff] at h
  exact h

theorem decodeState_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeArray maxTableElements decodeStateDeclV1 ⟨b, oState p, 1⟩ =
      .ok (#[], ⟨b, oEvents p, 1⟩) := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  let L :=
    encodeMagicPrefix semanticProgramMagicV1 ++
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
      qualifiedNamePayloadV1 p ++ typesArrayBytesV1 ++ emptyTableBytesV1
  let R :=
    emptyTableBytesV1 ++ emptyTableBytesV1 ++ callablesArrayBytesV1 p ++
      invariantsArrayBytesV1 p.invName ++ programRequirementsValueBoolBytesV1
  have hin : b = L ++ emptyTableBytesV1 ++ R := by
    rw [hlayout]; simp only [L, R, ByteArray.append_assoc]
  have hL : L.size = oState p := by
    simp only [L, oState, oConst, oTypes, oTag, magicSizeV1, headerSizeV1,
      ByteArray.size_append, header_size]
  have hszEmpty : emptyTableBytesV1.size = 4 := encodeU32le_sizeV1 0
  have hoff : oState p + 4 = oEvents p := by
    simp only [oEvents, oState, hszEmpty]
  have h := decodeEmpty_at decodeStateDeclV1 L R 1
  rw [← hin, hL, hoff] at h
  exact h

theorem decodeEvents_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeArray maxTableElements decodeEventDeclV1 ⟨b, oEvents p, 1⟩ =
      .ok (#[], ⟨b, oErrors p, 1⟩) := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  let L :=
    encodeMagicPrefix semanticProgramMagicV1 ++
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
      qualifiedNamePayloadV1 p ++ typesArrayBytesV1 ++ emptyTableBytesV1 ++
      emptyTableBytesV1
  let R :=
    emptyTableBytesV1 ++ callablesArrayBytesV1 p ++
      invariantsArrayBytesV1 p.invName ++ programRequirementsValueBoolBytesV1
  have hin : b = L ++ emptyTableBytesV1 ++ R := by
    rw [hlayout]; simp only [L, R, ByteArray.append_assoc]
  have hL : L.size = oEvents p := by
    simp only [L, oEvents, oState, oConst, oTypes, oTag, magicSizeV1, headerSizeV1,
      ByteArray.size_append, header_size]
  have hszEmpty : emptyTableBytesV1.size = 4 := encodeU32le_sizeV1 0
  have hoff : oEvents p + 4 = oErrors p := by
    simp only [oErrors, oEvents, hszEmpty]
  have h := decodeEmpty_at decodeEventDeclV1 L R 1
  rw [← hin, hL, hoff] at h
  exact h

theorem decodeErrors_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeArray maxTableElements decodeErrorDeclV1 ⟨b, oErrors p, 1⟩ =
      .ok (#[], ⟨b, oCallables p, 1⟩) := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  let L :=
    encodeMagicPrefix semanticProgramMagicV1 ++
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
      qualifiedNamePayloadV1 p ++ typesArrayBytesV1 ++ emptyTableBytesV1 ++
      emptyTableBytesV1 ++ emptyTableBytesV1
  let R :=
    callablesArrayBytesV1 p ++ invariantsArrayBytesV1 p.invName ++
      programRequirementsValueBoolBytesV1
  have hin : b = L ++ emptyTableBytesV1 ++ R := by
    rw [hlayout]; simp only [L, R, ByteArray.append_assoc]
  have hL : L.size = oErrors p := by
    simp only [L, oErrors, oEvents, oState, oConst, oTypes, oTag, magicSizeV1,
      headerSizeV1, ByteArray.size_append, header_size]
  have hszEmpty : emptyTableBytesV1.size = 4 := encodeU32le_sizeV1 0
  have hoff : oErrors p + 4 = oCallables p := by
    simp only [oCallables, oErrors, hszEmpty]
  have h := decodeEmpty_at decodeErrorDeclV1 L R 1
  rw [← hin, hL, hoff] at h
  exact h

theorem decodeCallables_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeArray maxTableElements decodeCallableV1 ⟨b, oCallables p, 1⟩ =
      .ok (#[simpleClosureViewCallableV1 p.viewName,
            simpleClosureInvCallableV1 p.invName],
        ⟨b, oInvariants p, 1⟩) := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  let L :=
    encodeMagicPrefix semanticProgramMagicV1 ++
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
      qualifiedNamePayloadV1 p ++ typesArrayBytesV1 ++ emptyTableBytesV1 ++
      emptyTableBytesV1 ++ emptyTableBytesV1 ++ emptyTableBytesV1
  let R :=
    invariantsArrayBytesV1 p.invName ++ programRequirementsValueBoolBytesV1
  have hin : b = L ++ callablesArrayBytesV1 p ++ R := by
    rw [hlayout]; simp only [L, R, ByteArray.append_assoc]
  have hL : L.size = oCallables p := by
    simp only [L, oCallables, oErrors, oEvents, oState, oConst, oTypes, oTag,
      magicSizeV1, headerSizeV1, ByteArray.size_append, header_size]
  have hoff : oCallables p + (callablesArrayBytesV1 p).size = oInvariants p := by
    simp only [oInvariants, oCallables]
  have hdepth : (1 : Nat) + 3 < maxNesting := by decide
  have h := decodeCallableArrayV1_simpleClosure_of_legal L R p legal 1 hdepth
  rw [← hin, hL, hoff] at h
  exact h

theorem decodeInvariants_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeArray maxTableElements decodeInvariantDeclV1 ⟨b, oInvariants p, 1⟩ =
      .ok (#[simpleClosureInvariantDeclV1 p.invName],
        ⟨b, oRequirements p, 1⟩) := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  let L :=
    encodeMagicPrefix semanticProgramMagicV1 ++
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
      qualifiedNamePayloadV1 p ++ typesArrayBytesV1 ++ emptyTableBytesV1 ++
      emptyTableBytesV1 ++ emptyTableBytesV1 ++ emptyTableBytesV1 ++
      callablesArrayBytesV1 p
  let R := programRequirementsValueBoolBytesV1
  have hin : b = L ++ invariantsArrayBytesV1 p.invName ++ R := by
    simpa [L, R, ByteArray.append_assoc] using hlayout
  have hL : L.size = oInvariants p := by
    simp only [L, oInvariants, oCallables, oErrors, oEvents, oState, oConst,
      oTypes, oTag, magicSizeV1, headerSizeV1, ByteArray.size_append, header_size]
  have hoff : oInvariants p + (invariantsArrayBytesV1 p.invName).size = oRequirements p := by
    simp only [oRequirements, oInvariants]
  have hdepth : (1 : Nat) < maxNesting := by decide
  have h := decodeInvariants_array_of_legal_midV1 L R p legal 1 hdepth
  rw [← hin, hL, hoff] at h
  exact h

theorem decodeRequirements_body_of_fieldsOk_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeProgramRequirementsV1 ⟨b, oRequirements p, 1⟩ =
      .ok ({ items := #[simpleClosureBoolRequirementV1] },
        ⟨b, oEnd p, 1⟩) := by
  have hlayout := fieldsOk_bytes_layout_of_legal p b legal fok
  let L :=
    encodeMagicPrefix semanticProgramMagicV1 ++
      taggedHeaderBytesV1 semanticProgramDataTagV1 9 ++
      qualifiedNamePayloadV1 p ++ typesArrayBytesV1 ++ emptyTableBytesV1 ++
      emptyTableBytesV1 ++ emptyTableBytesV1 ++ emptyTableBytesV1 ++
      callablesArrayBytesV1 p ++ invariantsArrayBytesV1 p.invName
  have hin : b = L ++ programRequirementsValueBoolBytesV1 ++ ByteArray.empty := by
    rw [hlayout]
    simp only [L, ByteArray.append_assoc, ByteArray.append_empty]
  have hL : L.size = oRequirements p := by
    simp only [L, oRequirements, oInvariants, oCallables, oErrors, oEvents,
      oState, oConst, oTypes, oTag, magicSizeV1, headerSizeV1, ByteArray.size_append,
      header_size]
  have hoff : oRequirements p + programRequirementsValueBoolBytesV1.size = oEnd p := by
    simp only [oEnd, oRequirements]
  have hdepth : (1 : Nat) + 1 < maxNesting := by decide
  have h :=
    decodeProgramRequirements_valueBool_midV1 L ByteArray.empty 1 hdepth
  rw [← hin, hL, hoff] at h
  -- Absorb trailing empty on the reconstructed input identity.
  simpa [ByteArray.append_empty] using h

/-! ### Materialize equality for assembled data -/

theorem materialize_eq_fields
    (p : SimpleClosureParamsV1) :
    materializeSimpleClosureDataV1 p =
      {
        qualifiedName := p.toQualifiedName
        types := #[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1]
        constants := #[]
        logicalState := #[]
        events := #[]
        errors := #[]
        callables :=
          #[simpleClosureViewCallableV1 p.viewName,
            simpleClosureInvCallableV1 p.invName]
        invariants := #[simpleClosureInvariantDeclV1 p.invName]
        requirements := { items := #[simpleClosureBoolRequirementV1] }
      } :=
  rfl

/-! ### Public tagged body composition -/

/-- Sole Legal + FieldsOk ⇒ tagged root transport decode recovers materialize.
    No free htag/hname/htypes/…/hfinish premises. -/
theorem decodeSemanticProgramDataTagged_of_simpleClosure_field_bytes
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (fok : SemanticProgramFieldsOkV1 (materializeSimpleClosureDataV1 p) b) :
    decodeSemanticProgramDataTaggedV1 ⟨b, magicSizeV1, 0⟩ =
      .ok (materializeSimpleClosureDataV1 p, ⟨b, b.size, 0⟩) := by
  have hdepth : (0 : Nat) < maxNesting := by decide
  have htag := expectTag_body_of_fieldsOk_legal p b legal fok
  have hname := decodeQualifiedName_body_of_fieldsOk_legal p b legal fok
  have htypes := decodeTypes_body_of_fieldsOk_legal p b legal fok
  have hconst := decodeConstants_body_of_fieldsOk_legal p b legal fok
  have hstate := decodeState_body_of_fieldsOk_legal p b legal fok
  have hevents := decodeEvents_body_of_fieldsOk_legal p b legal fok
  have herrors := decodeErrors_body_of_fieldsOk_legal p b legal fok
  have hcall := decodeCallables_body_of_fieldsOk_legal p b legal fok
  have hinv := decodeInvariants_body_of_fieldsOk_legal p b legal fok
  have hreq := decodeRequirements_body_of_fieldsOk_legal p b legal fok
  have hend := fieldsOk_end_offset p b legal fok
  have htagged :=
    decodeSemanticProgramDataTaggedV1_eq_of_fields
      ⟨b, magicSizeV1, 0⟩
      ⟨b, oTag p, 1⟩
      ⟨b, oTypes p, 1⟩
      ⟨b, oConst p, 1⟩
      ⟨b, oState p, 1⟩
      ⟨b, oEvents p, 1⟩
      ⟨b, oErrors p, 1⟩
      ⟨b, oCallables p, 1⟩
      ⟨b, oInvariants p, 1⟩
      ⟨b, oRequirements p, 1⟩
      ⟨b, oEnd p, 1⟩
      (p.toQualifiedName)
      #[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1]
      #[] #[] #[] #[]
      #[simpleClosureViewCallableV1 p.viewName,
        simpleClosureInvCallableV1 p.invName]
      #[simpleClosureInvariantDeclV1 p.invName]
      { items := #[simpleClosureBoolRequirementV1] }
      hdepth htag hname htypes hconst hstate hevents herrors hcall hinv hreq
  have hmat := materialize_eq_fields p
  have h' :
      decodeSemanticProgramDataTaggedV1 ⟨b, magicSizeV1, 0⟩ =
        .ok (materializeSimpleClosureDataV1 p, ⟨b, oEnd p, 0⟩) := by
    simpa [hmat] using htagged
  simpa [hend] using h'

/-! ### Public full transport decode (sole Legal + encode body success) -/

/-- B-SC-DEC composition close: Legal + field-path encode success ⇒
    transport decode recovers materialize. No intermediate decode premises. -/
theorem decodeSimpleClosure_of_fields_ok_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    decodeSemanticProgramDataV1 b = .ok (materializeSimpleClosureDataV1 p) := by
  have fok := encodeSimpleClosureFields_ok_inv p b hfields
  have hdata :=
    decodeSemanticProgramDataTagged_of_simpleClosure_field_bytes p b legal fok
  have hdata' :
      decodeSemanticProgramDataTaggedV1
          ⟨b, (encodeMagicPrefix semanticProgramMagicV1).size, 0⟩ =
        .ok (materializeSimpleClosureDataV1 p, ⟨b, b.size, 0⟩) := by
    simpa [magicSizeV1] using hdata
  exact decode_of_simpleClosure_fields_ok_of_taggedBody p b hfields hdata'

/-- Parameterized kernel goal form under Legal + body encode success. -/
theorem decodeSimpleClosureGoal_of_fields_ok_legal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    DecodeSimpleClosureGoalV1 p := by
  have hb := simpleClosureWireBytesV1_eq_of_fields_ok p b hfields
  have hdec := decodeSimpleClosure_of_fields_ok_legal p b legal hfields
  unfold DecodeSimpleClosureGoalV1 canonicalWireBytesV1
  rw [hb]
  exact hdec

/-- B-SC-DEC legal-only close. The sole body encoder is proven successful by
    `SimpleClosureEncodeFieldsV1`; no encode/decode premise remains. -/
theorem decodeSimpleClosureGoal_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    DecodeSimpleClosureGoalV1 p := by
  obtain ⟨b, hfields⟩ := encodeSimpleClosureDataFields_ok_of_legal p legal
  exact decodeSimpleClosureGoal_of_fields_ok_legal p b legal hfields

/-- Expanded legal-only transport equality. -/
theorem decodeSimpleClosure_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    decodeSemanticProgramDataV1 (simpleClosureWireBytesV1 p) =
      .ok (materializeSimpleClosureDataV1 p) := by
  simpa [DecodeSimpleClosureGoalV1, canonicalWireBytesV1] using
    decodeSimpleClosureGoal_of_legal p legal

/-- The nine production root-field codecs invert for every legal simple
    closure. This package is parameterized by names and arbitrary framing; it
    does not pin a complete contract byte string. -/
theorem rootFieldInvertV1_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    RootFieldInvertV1 (materializeSimpleClosureDataV1 p) := by
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
  · simpa [materializeSimpleClosureDataV1] using
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_qualifiedName p.toQualifiedName)
        (by decide : 1 < maxNesting))
  · intro b left right hencode
    have hb : b = typesArrayBytesV1 :=
      Except.ok.inj (hencode.symm.trans (encodeTypes_materialize_eq_ok p))
    subst b
    simpa [materializeSimpleClosureDataV1] using
      decodeTypes_simpleClosure_midV1 left right 1 (by decide)
  · simpa [materializeSimpleClosureDataV1] using
      (exactAt_array_emptyV1 encodeConstantV1 decodeConstantV1
        maxTableElements 1)
  · simpa [materializeSimpleClosureDataV1] using
      (exactAt_array_emptyV1 encodeStateDeclV1 decodeStateDeclV1
        maxTableElements 1)
  · simpa [materializeSimpleClosureDataV1] using
      (exactAt_array_emptyV1 encodeEventDeclV1 decodeEventDeclV1
        maxTableElements 1)
  · simpa [materializeSimpleClosureDataV1] using
      (exactAt_array_emptyV1 encodeErrorDeclV1 decodeErrorDeclV1
        maxTableElements 1)
  · intro b left right hencode
    have hb : b = callablesArrayBytesV1 p :=
      Except.ok.inj
        (hencode.symm.trans (encode_callablesArray_of_legal p legal))
    subst b
    simpa [materializeSimpleClosureDataV1] using
      decodeCallableArrayV1_simpleClosure_of_legal
        left right p legal 1 (by decide)
  · intro b left right hencode
    have hb : b = invariantsArrayBytesV1 p.invName :=
      Except.ok.inj
        (hencode.symm.trans (encodeInvariants_materialize_of_legal p legal))
    subst b
    simpa [materializeSimpleClosureDataV1] using
      decodeInvariants_array_of_legal_midV1 left right p legal 1 (by decide)
  · intro b left right hencode
    have hb : b = programRequirementsValueBoolBytesV1 :=
      Except.ok.inj
        (hencode.symm.trans (encodeRequirements_materialize_eq_ok p))
    subst b
    simpa [materializeSimpleClosureDataV1] using
      decodeProgramRequirements_valueBool_midV1 left right 1 (by decide)

/-- Fully closed ordinal-0 invariant theorem for every legal simple-closure
    parameter set. This composes only production encode/decode equalities and
    the literal-true witness; it does not require a caller-supplied wire trace. -/
theorem invariantTheoremV1_of_simpleClosure_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    InvariantTheoremV1 { canonicalBytes := simpleClosureWireBytesV1 p } 0 := by
  let data := materializeSimpleClosureDataV1 p
  let bytes := simpleClosureWireBytesV1 p
  have hencode : encodeSemanticProgramDataV1 data = .ok bytes := by
    simpa [data, bytes, EncodeSimpleClosureGoalV1] using
      encodeSimpleClosure_of_legal p legal
  have hdecode : decodeSemanticProgramDataV1 bytes = .ok data := by
    simpa [data, bytes] using decodeSimpleClosure_of_legal p legal
  have hwitness :
      LiteralTrueInvariantWitnessV1 data 0
        (simpleClosureInvariantDeclV1 p.invName)
        0 (some p.invName) .public_ none := by
    simpa [data] using literalTrueWitness_of_materialize p
  let cert :=
    ProofForgeV2.Semantic.AuthorWireCertV1.LiteralTrueAuthorWireCertV1.ofParts
      data bytes 0 (simpleClosureInvariantDeclV1 p.invName)
      0 (some p.invName) .public_ none hencode hdecode hwitness
  exact
    ProofForgeV2.Semantic.AuthorWireCertV1.invariantTheoremV1_of_literalTrueAuthorWireCert
      data bytes 0 (simpleClosureInvariantDeclV1 p.invName)
      0 (some p.invName) .public_ none cert

/-! ### Demo + Unicode kernel witnesses (no Tests FQN) -/

def demoParamsV1 : SimpleClosureParamsV1 :=
  { qnHead := "Module"
    qnTail := #["Prog"]
    viewName := "alive"
    invName := "safe" }

private theorem ident_Module :
    validateIdentifierComponent "Module" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Module" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem ident_Prog :
    validateIdentifierComponent "Prog" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Prog" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem ident_alive :
    validateIdentifierComponent "alive" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "alive" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem ident_safe :
    validateIdentifierComponent "safe" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "safe" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

theorem demoParams_legal : SimpleClosureParamsLegalV1 demoParamsV1 := by
  refine {
    hqnSize := by decide
    hqnCap := by decide
    hdistinct := by decide
    hqnHead := ident_Module
    hqnTail := ?_
    hview := ident_alive
    hinv := ident_safe
  }
  intro i hi
  have : i = 0 := by
    simp [demoParamsV1] at hi
    omega
  subst this
  exact ident_Prog

/-- Unicode-bearing legal-shaped params (runtime Legal / structure). -/
def unicodeLegalParamsV1 : SimpleClosureParamsV1 :=
  { qnHead := "ModuleΑ"
    qnTail := #["ProgΒ"]
    viewName := "aliveΑ"
    invName := "safeΒ" }

end ProofForgeV2.Semantic.SimpleClosureDecodeComposeV1
