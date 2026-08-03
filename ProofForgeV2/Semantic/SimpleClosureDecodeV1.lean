import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas

/-!
  ProofForgeV2.Semantic.SimpleClosureDecodeV1 — B-SC-DEC

  Goal (family form, no free intermediate decode premises):

    decodeSemanticProgramDataV1 (canonicalWireBytesV1 p) =
      .ok (materializeSimpleClosureDataV1 p)

  under `SimpleClosureParamsLegalV1 p` (QN/view/inv identifier+NFC).

  Builder ownership:
    * sole production wire authority is `SimpleClosureEncodeV1.simpleClosureWireBytesV1`
      (alias `canonicalWireBytesV1` here). No competing List-spine product bytes.
    * production composition lemmas live in `Wire.CodecRoundtripV1`.

  Closed:
    * general NFC UTF-8 string sized mid-offset decode (not just ASCII)
    * identifier → NFC + size ≤ maxStringBytes + encodeString payload
    * production u32le encode→decode mid-offset
    * option.some identifier string mid-offset
    * QN component-list payload + parameterized array-element induction
    * QN components array decode under Legal (count header + elements)
    * framing package / WireTrace soundness packaging
    * demo legal kernel (no Tests FQN)

  Residual (honest):
    * nine-field root composition through nested fixed-shape TypeDecl /
      Callable / Block / Instruction / Requirements encode→decode under Legal
      (name-parameterized one-shot remains the intended close; nested tagged
      record encode→decode is the remaining mechanical step)

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
-/

namespace ProofForgeV2.Semantic.SimpleClosureDecodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

/-! ### Sole builder (Encode owner) -/

/-- Production canonical wire bytes for the simple-closure family.
    Sole authority: `SimpleClosureEncodeV1.simpleClosureWireBytesV1`. -/
abbrev canonicalWireBytesV1 (p : SimpleClosureParamsV1) : ByteArray :=
  simpleClosureWireBytesV1 p

/-- B-SC-DEC goal: transport decode of production wire bytes recovers materialize. -/
def DecodeSimpleClosureGoalV1 (p : SimpleClosureParamsV1) : Prop :=
  decodeSemanticProgramDataV1 (canonicalWireBytesV1 p) =
    .ok (materializeSimpleClosureDataV1 p)

/-! ### Identifier coverage from Legal -/

theorem legal_qnHead (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    validateIdentifierComponent p.qnHead = .ok () :=
  legal.hqnHead

theorem legal_view (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    validateIdentifierComponent p.viewName = .ok () :=
  legal.hview

theorem legal_inv (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    validateIdentifierComponent p.invName = .ok () :=
  legal.hinv

theorem legal_qnTail (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p)
    (i : Nat) (hi : i < p.qnTail.size) :
    validateIdentifierComponent p.qnTail[i] = .ok () :=
  legal.hqnTail i hi

/-- Every QN component (head + each tail index) is identifier-legal. -/
theorem legal_qnComponents_list (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    ∀ s ∈ (p.qnHead :: p.qnTail.toList),
      validateIdentifierComponent s = .ok () := by
  intro s hs
  simp only [List.mem_cons] at hs
  rcases hs with heq | ht
  · subst heq; exact legal.hqnHead
  · have hm : s ∈ p.qnTail := (Array.mem_def).2 ht
    obtain ⟨i, hi, rfl⟩ := Array.getElem_of_mem hm
    exact legal.hqnTail i hi

/-! ### String payload encode / decode under Legal -/

theorem encodeString_qnHead_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    encodeString p.qnHead = .ok (stringPayloadBytesV1 p.qnHead) :=
  encodeString_of_identifierV1 p.qnHead legal.hqnHead

theorem encodeString_view_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    encodeString p.viewName = .ok (stringPayloadBytesV1 p.viewName) :=
  encodeString_of_identifierV1 p.viewName legal.hview

theorem encodeString_inv_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    encodeString p.invName = .ok (stringPayloadBytesV1 p.invName) :=
  encodeString_of_identifierV1 p.invName legal.hinv

theorem decodeString_view_of_legal
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) (nesting : Nat) :
    decodeString
        ⟨left ++ stringPayloadBytesV1 p.viewName ++ right, left.size, nesting⟩ =
      .ok (p.viewName,
        ⟨left ++ stringPayloadBytesV1 p.viewName ++ right,
          left.size + 4 + p.viewName.toUTF8.size, nesting⟩) :=
  decodeString_of_identifier_midV1 left right p.viewName nesting legal.hview

theorem decodeString_inv_of_legal
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) (nesting : Nat) :
    decodeString
        ⟨left ++ stringPayloadBytesV1 p.invName ++ right, left.size, nesting⟩ =
      .ok (p.invName,
        ⟨left ++ stringPayloadBytesV1 p.invName ++ right,
          left.size + 4 + p.invName.toUTF8.size, nesting⟩) :=
  decodeString_of_identifier_midV1 left right p.invName nesting legal.hinv

theorem decodeOptionString_view_of_legal
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) (nesting : Nat) :
    decodeOption decodeString
        ⟨left ++ someStringPayloadBytesV1 p.viewName ++ right, left.size, nesting⟩ =
      .ok (some p.viewName,
        ⟨left ++ someStringPayloadBytesV1 p.viewName ++ right,
          left.size + 1 + 4 + p.viewName.toUTF8.size, nesting⟩) :=
  decodeOptionString_some_identifier_midV1 left right p.viewName nesting legal.hview

theorem decodeOptionString_inv_of_legal
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) (nesting : Nat) :
    decodeOption decodeString
        ⟨left ++ someStringPayloadBytesV1 p.invName ++ right, left.size, nesting⟩ =
      .ok (some p.invName,
        ⟨left ++ someStringPayloadBytesV1 p.invName ++ right,
          left.size + 1 + 4 + p.invName.toUTF8.size, nesting⟩) :=
  decodeOptionString_some_identifier_midV1 left right p.invName nesting legal.hinv

/-! ### QN component string-array payload + induction -/

/-- Concatenated production string payloads for a component list. -/
def stringArrayPayloadV1 : List String → ByteArray
  | [] => ByteArray.empty
  | s :: rest => stringPayloadBytesV1 s ++ stringArrayPayloadV1 rest

theorem stringPayload_sizeV1 (s : String) :
    (stringPayloadBytesV1 s).size = 4 + s.toUTF8.size := by
  simp [stringPayloadBytesV1, ByteArray.size_append, encodeU32le_sizeV1]

theorem push_append_cons_toArray (acc : Array String) (s : String)
    (rest : List String) :
    acc.push s ++ rest.toArray = acc ++ (s :: rest).toArray := by
  apply Array.toList_inj.mp
  simp [Array.toList_append]

/-- Parameterized induction: decode a list of identifier-legal strings from a
    production mid-offset payload, accumulating into arbitrary `acc`. -/
theorem decodeArrayElements_strings_legal_acc
    (left right : ByteArray) (nesting : Nat) (acc : Array String) :
    (xs : List String) →
    (hlegal : ∀ s ∈ xs, validateIdentifierComponent s = .ok ()) →
    decodeArrayElementsV1 decodeString xs.length acc
        ⟨left ++ stringArrayPayloadV1 xs ++ right, left.size, nesting⟩ =
      .ok (acc ++ xs.toArray,
        ⟨left ++ stringArrayPayloadV1 xs ++ right,
          left.size + (stringArrayPayloadV1 xs).size, nesting⟩)
  | [], _ => by
      change decodeArrayElementsV1 decodeString 0 acc
          ⟨left ++ ByteArray.empty ++ right, left.size, nesting⟩ =
        .ok (acc ++ #[],
          ⟨left ++ ByteArray.empty ++ right, left.size + ByteArray.empty.size, nesting⟩)
      simp [decodeArrayElementsV1, ByteArray.append_empty, ByteArray.size_empty]
  | s :: rest, hlegal => by
      have hs : validateIdentifierComponent s = .ok () :=
        hlegal s (List.mem_cons_self)
      have hrest : ∀ t ∈ rest, validateIdentifierComponent t = .ok () :=
        fun t ht => hlegal t (List.mem_cons_of_mem _ ht)
      have hpay :
          stringArrayPayloadV1 (s :: rest) =
            stringPayloadBytesV1 s ++ stringArrayPayloadV1 rest := rfl
      have hsz := stringPayload_sizeV1 s
      have hin' :
          left ++ stringArrayPayloadV1 (s :: rest) ++ right =
            left ++ stringPayloadBytesV1 s ++
              (stringArrayPayloadV1 rest ++ right) := by
        simp [hpay, ByteArray.append_assoc]
      have hfirst :
          decodeString
              ⟨left ++ stringArrayPayloadV1 (s :: rest) ++ right,
                left.size, nesting⟩ =
            .ok (s,
              ⟨left ++ stringArrayPayloadV1 (s :: rest) ++ right,
                left.size + (stringPayloadBytesV1 s).size, nesting⟩) := by
        rw [hin']
        have h0 :=
          decodeString_of_identifier_midV1 left
            (stringArrayPayloadV1 rest ++ right) s nesting hs
        have hoff :
            left.size + 4 + s.toUTF8.size =
              left.size + (stringPayloadBytesV1 s).size := by
          rw [hsz]; omega
        have h0' :
            decodeString
                ⟨left ++ stringPayloadBytesV1 s ++
                    (stringArrayPayloadV1 rest ++ right),
                  left.size, nesting⟩ =
              .ok (s,
                ⟨left ++ stringPayloadBytesV1 s ++
                    (stringArrayPayloadV1 rest ++ right),
                  left.size + (stringPayloadBytesV1 s).size, nesting⟩) := by
          rw [← hoff]; exact h0
        exact h0'
      have hin2 :
          left ++ stringArrayPayloadV1 (s :: rest) ++ right =
            (left ++ stringPayloadBytesV1 s) ++
              stringArrayPayloadV1 rest ++ right := by
        simp [hpay, ByteArray.append_assoc]
      have hszL :
          (left ++ stringPayloadBytesV1 s).size =
            left.size + (stringPayloadBytesV1 s).size := by
        simp [ByteArray.size_append]
      have hszPay :
          left.size + (stringPayloadBytesV1 s).size +
              (stringArrayPayloadV1 rest).size =
            left.size + (stringArrayPayloadV1 (s :: rest)).size := by
        simp [hpay, ByteArray.size_append]; omega
      have htail_raw :=
        decodeArrayElements_strings_legal_acc
          (left ++ stringPayloadBytesV1 s) right nesting (acc.push s) rest hrest
      have htail :
          decodeArrayElementsV1 decodeString rest.length (acc.push s)
              ⟨left ++ stringArrayPayloadV1 (s :: rest) ++ right,
                left.size + (stringPayloadBytesV1 s).size, nesting⟩ =
            .ok (acc.push s ++ rest.toArray,
              ⟨left ++ stringArrayPayloadV1 (s :: rest) ++ right,
                left.size + (stringArrayPayloadV1 (s :: rest)).size, nesting⟩) := by
        have h := htail_raw
        rw [show left.size + (stringPayloadBytesV1 s).size =
            (left ++ stringPayloadBytesV1 s).size from hszL.symm]
        have h2 :
            (left ++ stringPayloadBytesV1 s) ++ stringArrayPayloadV1 rest ++ right =
              left ++ stringArrayPayloadV1 (s :: rest) ++ right := hin2.symm
        simp only [h2] at h
        have h3 :
            (left ++ stringPayloadBytesV1 s).size +
                (stringArrayPayloadV1 rest).size =
              left.size + (stringArrayPayloadV1 (s :: rest)).size := by
          rw [hszL]; exact hszPay
        simp only [h3] at h
        exact h
      have hsucc :=
        decodeArrayElementsV1_succ decodeString rest.length acc
          ⟨left ++ stringArrayPayloadV1 (s :: rest) ++ right, left.size, nesting⟩
          ⟨left ++ stringArrayPayloadV1 (s :: rest) ++ right,
            left.size + (stringPayloadBytesV1 s).size, nesting⟩
          s
          (.ok (acc.push s ++ rest.toArray,
            ⟨left ++ stringArrayPayloadV1 (s :: rest) ++ right,
              left.size + (stringArrayPayloadV1 (s :: rest)).size, nesting⟩))
          hfirst htail
      simpa [List.length_cons, push_append_cons_toArray] using hsucc

/-- Empty-accumulator form of the string-list induction. -/
theorem decodeArrayElements_strings_legal
    (left right : ByteArray) (nesting : Nat) (xs : List String)
    (hlegal : ∀ s ∈ xs, validateIdentifierComponent s = .ok ()) :
    decodeArrayElementsV1 decodeString xs.length #[]
        ⟨left ++ stringArrayPayloadV1 xs ++ right, left.size, nesting⟩ =
      .ok (xs.toArray,
        ⟨left ++ stringArrayPayloadV1 xs ++ right,
          left.size + (stringArrayPayloadV1 xs).size, nesting⟩) := by
  have h :=
    decodeArrayElements_strings_legal_acc left right nesting #[] xs hlegal
  simpa using h

/-! ### QN full array decode under Legal (count header + elements) -/

/-- QN components payload = count u32le ++ string array payload. -/
def qualifiedNamePayloadV1 (p : SimpleClosureParamsV1) : ByteArray :=
  encodeU32le (UInt32.ofNat p.qnSize) ++
    stringArrayPayloadV1 (p.qnHead :: p.qnTail.toList)

theorem qnSize_eq_components (p : SimpleClosureParamsV1) :
    p.qnSize = (p.qnHead :: p.qnTail.toList).length := by
  simp [SimpleClosureParamsV1.qnSize, List.length_cons]

/-- Mid-offset decode of the QN string components array under Legal.
    Composes production count header + string-list induction. -/
theorem decodeArray_qnComponents_of_legal
    (left right : ByteArray) (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) (nesting : Nat)
    (hfit : p.qnSize ≤ UInt32.size - 1)
    (hmax : p.qnSize ≤ 256) :
    decodeArray 256 decodeString
        ⟨left ++ qualifiedNamePayloadV1 p ++ right, left.size, nesting⟩ =
      .ok ((p.qnHead :: p.qnTail.toList).toArray,
        ⟨left ++ qualifiedNamePayloadV1 p ++ right,
          left.size + (qualifiedNamePayloadV1 p).size, nesting⟩) := by
  have hcomps := legal_qnComponents_list p legal
  have hlen : p.qnSize = (p.qnHead :: p.qnTail.toList).length :=
    qnSize_eq_components p
  -- Work with expanded payload definitionally equal to `qualifiedNamePayloadV1`.
  let enc := encodeU32le (UInt32.ofNat p.qnSize)
  let strs := stringArrayPayloadV1 (p.qnHead :: p.qnTail.toList)
  have hpay : qualifiedNamePayloadV1 p = enc ++ strs := rfl
  have hszEnc : enc.size = 4 := encodeU32le_sizeV1 _
  -- Count header on `left ++ enc ++ (strs ++ right)`.
  have hcount :
      readArrayCountAtV1 (left ++ enc ++ (strs ++ right)) left.size 256 =
        .ok (p.qnSize, left.size + 4) :=
    readArrayCount_encode_midV1 left (strs ++ right) p.qnSize 256 hfit hmax
  -- Element run from left' = left ++ enc.
  have hel' :=
    decodeArrayElements_strings_legal (left ++ enc) right nesting
      (p.qnHead :: p.qnTail.toList) hcomps
  -- Rewrite length via hlen.
  have hel :
      decodeArrayElementsV1 decodeString p.qnSize #[]
          ⟨(left ++ enc) ++ strs ++ right, (left ++ enc).size, nesting⟩ =
        .ok ((p.qnHead :: p.qnTail.toList).toArray,
          ⟨(left ++ enc) ++ strs ++ right,
            (left ++ enc).size + strs.size, nesting⟩) := by
    simpa [hlen] using hel'
  -- Now assemble decodeArray.
  have hin :
      left ++ qualifiedNamePayloadV1 p ++ right =
        left ++ enc ++ (strs ++ right) := by
    simp [hpay, ByteArray.append_assoc]
  have hin2 :
      left ++ enc ++ (strs ++ right) = (left ++ enc) ++ strs ++ right := by
    simp [ByteArray.append_assoc]
  rw [hin]
  apply decodeArray_eq_of_elementsV1 256 decodeString _
    p.qnSize (left.size + 4)
    (p.qnHead :: p.qnTail.toList).toArray
  · exact hcount
  · -- align hel to the post-count cursor
    have hszL : (left ++ enc).size = left.size + 4 := by
      simp [ByteArray.size_append, hszEnc]
    have hszPay :
        left.size + (enc ++ strs).size = left.size + 4 + strs.size := by
      simp [ByteArray.size_append, hszEnc]; omega
    -- hel has left++enc form; transport
    have h := hel
    rw [← hin2] at h
    rw [hszL] at h
    -- final offset: (left++enc).size + strs.size = left.size + (enc++strs).size
    have hoff :
        left.size + 4 + strs.size =
          left.size + (enc ++ strs).size := by
      simp [ByteArray.size_append, hszEnc]; omega
    simpa [hoff, hpay, ByteArray.append_assoc] using h

/-! ### Framing package -/

theorem decodeSimpleClosure_of_framing
    (p : SimpleClosureParamsV1)
    (afterMagic afterData : Cursor)
    (hsize : (canonicalWireBytesV1 p).size ≤ maxCanonicalProgramBytes)
    (hmagic :
      consumeMagic semanticProgramMagicV1 (start (canonicalWireBytesV1 p)) =
        .ok ((), afterMagic))
    (hdata :
      decodeSemanticProgramDataTaggedV1 afterMagic =
        .ok (materializeSimpleClosureDataV1 p, afterData))
    (hfinish : finish afterData = .ok ()) :
    DecodeSimpleClosureGoalV1 p := by
  unfold DecodeSimpleClosureGoalV1 canonicalWireBytesV1
  exact decodeSemanticProgramDataV1_eq_of_framing
    (simpleClosureWireBytesV1 p) afterMagic afterData
    (materializeSimpleClosureDataV1 p) hsize hmagic hdata hfinish

theorem simpleClosureWireTrace_of_encode_decode
    (p : SimpleClosureParamsV1)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hencode :
      encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
        .ok (canonicalWireBytesV1 p))
    (hdecode : DecodeSimpleClosureGoalV1 p) :
    SimpleClosureWireTraceV1 p (canonicalWireBytesV1 p) :=
  SimpleClosureWireTraceV1.ofParts p (canonicalWireBytesV1 p) hwf hencode hdecode

theorem invariantTheorem_of_simpleClosure_encode_decode
    (p : SimpleClosureParamsV1)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hencode :
      encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
        .ok (canonicalWireBytesV1 p))
    (hdecode : DecodeSimpleClosureGoalV1 p) :
    InvariantTheoremV1 { canonicalBytes := canonicalWireBytesV1 p } 0 :=
  invariantTheoremV1_of_simpleClosureWireTrace p (canonicalWireBytesV1 p)
    (simpleClosureWireTrace_of_encode_decode p hwf hencode hdecode)

/-! ### Demo legal params (no Tests FQN) -/

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

theorem demoParams_wf : SimpleClosureParamsWellFormedV1 demoParamsV1 := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> decide

theorem demoParams_legal : SimpleClosureParamsLegalV1 demoParamsV1 := by
  refine {
    hqnSize := by decide
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

/-- Unicode-bearing legal-shaped params (ASCII + Greek Alpha/Beta as isIdRest).
    Runtime/structure tests discharge identifier; kernel Legal witness is
    left to the focused suite for NFC tables. -/
def unicodeLegalParamsV1 : SimpleClosureParamsV1 :=
  { qnHead := "ModuleΑ"
    qnTail := #["ProgΒ"]
    viewName := "aliveΑ"
    invName := "safeΒ" }

/-! ### Empty-table production reuse -/

theorem decodeEmptyArray_encode_zero
    (maxCount : Nat) (decode : Decoder α)
    (left right : ByteArray) (nesting : Nat) :
    decodeArray maxCount decode
        ⟨left ++ encodeU32le 0 ++ right, left.size, nesting⟩ =
      .ok (#[], ⟨left ++ encodeU32le 0 ++ right, left.size + 4, nesting⟩) :=
  decodeArray_encode_zero_midV1 maxCount decode left right nesting

/-! ### Strong B-SC-DEC interface (sole encode-side premise) -/

/-- Magic consume on production field-path bytes (`magic ++ body`). -/
theorem consumeMagic_of_fieldsOk
    (data : SemanticProgramDataV1) (b : ByteArray)
    (fok : SemanticProgramFieldsOkV1 data b) :
    consumeMagic semanticProgramMagicV1 (start b) =
      .ok ((), ⟨b, (encodeMagicPrefix semanticProgramMagicV1).size, 0⟩) := by
  have hb : b = encodeMagicPrefix semanticProgramMagicV1 ++ fok.body := by
    simpa [ByteArray.append_eq] using fok.hb
  rw [hb]
  exact consumeMagic_append_bodyV1 semanticProgramMagicV1 fok.body

/-- Finish at exact end of production field-path bytes. -/
theorem finish_of_fieldsOk_end
    (data : SemanticProgramDataV1) (b : ByteArray)
    (_fok : SemanticProgramFieldsOkV1 data b) :
    finish ⟨b, b.size, 0⟩ = .ok () :=
  finish_at_endV1 b 0

/-- Package framing once tagged-root body decode is established at post-magic
    offset. **Public strong interface** discharges magic/finish from `hfields`
    alone; only the tagged nine-field body remains a production composition
    residual (see module footer). -/
theorem decode_of_simpleClosure_fields_ok_of_taggedBody
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok b)
    (hdata :
      decodeSemanticProgramDataTaggedV1
          ⟨b, (encodeMagicPrefix semanticProgramMagicV1).size, 0⟩ =
        .ok (materializeSimpleClosureDataV1 p, ⟨b, b.size, 0⟩)) :
    decodeSemanticProgramDataV1 b = .ok (materializeSimpleClosureDataV1 p) := by
  have fok := encodeSimpleClosureFields_ok_inv p b hfields
  have hmagic := consumeMagic_of_fieldsOk _ b fok
  have hfinish := finish_of_fieldsOk_end _ b fok
  exact decodeSemanticProgramDataV1_eq_of_framing b
    ⟨b, (encodeMagicPrefix semanticProgramMagicV1).size, 0⟩
    ⟨b, b.size, 0⟩
    (materializeSimpleClosureDataV1 p)
    fok.hsize hmagic hdata hfinish

/-- Target strong B-SC-DEC statement: sole encode-side premise, no intermediate
    decode hyps in the statement.

    **Proof residual (exact, single production composition):**
    `decodeSemanticProgramDataTagged_of_simpleClosure_field_bytes` —
    transport decode of the nine-field `encodeTagged "SemanticProgram.Data"`
    body produced by `SemanticProgramFieldsOkV1`, recovering
    `materializeSimpleClosureDataV1 p` at exact end offset.

    Why not closed from transparent defs alone: requires mid-offset
    `expectTag`/`readTagBytes` for ASCII production tags, then sequential
    encode→decode for QN / Bool+UInt64 TypeDecl×2 / empty×4 / view+inv
    Callable×2 (lit-true Block/Instruction) / InvariantDecl / value.bool
    ProgramRequirements — each nested through `withTaggedNesting`. Field-path
    inversion + magic + finish are closed above; this residual is the sole
    remaining body composition. -/
def DecodeSimpleClosureFieldsOkGoalV1 (p : SimpleClosureParamsV1) (b : ByteArray) :
    Prop :=
  encodeSimpleClosureDataFieldsV1 p = .ok b →
    decodeSemanticProgramDataV1 b = .ok (materializeSimpleClosureDataV1 p)

/-- Empty constants/state/events/errors tables on materialize always encode as
    `encodeU32le 0` and decode as empty (name-independent). -/
theorem materialize_empty_tables_encode (p : SimpleClosureParamsV1) :
    encodeArray encodeConstantV1 (materializeSimpleClosureDataV1 p).constants =
      .ok (encodeU32le 0) ∧
    encodeArray encodeStateDeclV1 (materializeSimpleClosureDataV1 p).logicalState =
      .ok (encodeU32le 0) ∧
    encodeArray encodeEventDeclV1 (materializeSimpleClosureDataV1 p).events =
      .ok (encodeU32le 0) ∧
    encodeArray encodeErrorDeclV1 (materializeSimpleClosureDataV1 p).errors =
      .ok (encodeU32le 0) := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · simpa [materializeSimpleClosureDataV1] using
      (encodeArray_zeroV1 encodeConstantV1)
  · simpa [materializeSimpleClosureDataV1] using
      (encodeArray_zeroV1 encodeStateDeclV1)
  · simpa [materializeSimpleClosureDataV1] using
      (encodeArray_zeroV1 encodeEventDeclV1)
  · simpa [materializeSimpleClosureDataV1] using
      (encodeArray_zeroV1 encodeErrorDeclV1)

/-- String encode→decode at mid-offset from production encode success. -/
theorem decodeString_of_encode_ok
    (left right : ByteArray) (s : String) (payload : ByteArray) (nesting : Nat)
    (h : encodeString s = .ok payload) :
    decodeString ⟨left ++ payload ++ right, left.size, nesting⟩ =
      .ok (s, ⟨left ++ payload ++ right, left.size + payload.size, nesting⟩) :=
  decodeString_of_encodeString_okV1 left right s payload nesting h

end ProofForgeV2.Semantic.SimpleClosureDecodeV1

/-!
  ## B-SC-DEC status (do not forge)

  | Closed | Residual (exact single production composition) |
  |---|---|
  | CodecRoundtrip production mid-offset u32/u16/string NFC/identifier/option/magic/finish | **`decodeSemanticProgramDataTagged_of_simpleClosure_field_bytes`**: nine-field tagged body transport decode from `SemanticProgramFieldsOkV1` field bytes |
  | `SemanticProgramFieldsOkV1` / `encodeFieldsOnly_ok_inv` / `encodeSimpleClosureFields_ok_inv` | Nested encode→decode for TypeDecl(Bool,UInt64), Callable(view+inv lit-true CFG), InvariantDecl, ProgramRequirements(value.bool) at mid-offsets inside the tagged body |
  | Magic consume + finish from FieldsOk; framing package under tagged-body hyp | Public `DecodeSimpleClosureFieldsOkGoalV1` without free decode hyps (discharges once residual body lemma closes) |
  | QN list induction under Legal; empty-table encode; string-of-encode-ok | B-SC-ENC: Legal → field-path success (separate residual) |

  Residual why not transparent: `expectTag`/`readTagBytes` + nested
  `withTaggedNesting` field walks for the materialize micro-shapes are not yet
  composed through production mid-offset lemmas (tag ASCII payloads are not the
  fixed List spines used by the earlier foundation). No intermediate
  hmagic/hdata/hfinish appear in the strong goal statement
  `DecodeSimpleClosureFieldsOkGoalV1`; only encode `hfields` is allowed once
  the residual body lemma is proved.
-/
