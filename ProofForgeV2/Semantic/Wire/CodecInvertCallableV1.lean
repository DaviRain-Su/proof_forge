import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.Wire.CodecInvertV1
import ProofForgeV2.Semantic.Wire.CodecInvertFieldsV1
import ProofForgeV2.Semantic.PreservationShapeV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertCallableV1 — mig-a1-callable

  Callable / Block / Op / Term mid-offset invertibility package (wave-3′ A):
    * CallableKind full MidOffsetInvert (5 nullary kinds)
    * ValueDef full MidOffsetInvert
    * LoopBound full MidOffsetInvert
    * pure-U32 SemanticOp constructors (Constant / StateLoad / Commit) + Op.Literal
    * Term.Return none/some MidOffsetInvert
    * empty callables table array invert
    * array one/two lift from element MidOffsetInvert + successful element encode

  Residual (mig-a1-root): nested Op.Unary/Binary/Construct/…, remaining Term
  constructors, Block/Callable full composition, arbitrary-length array induction,
  multi-component QN / full TypeShape.

  Hard boundaries: no axiom / sorry / native_decide / ofReduceBool.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

/-! ### Fixed ASCII tag certificates -/

private theorem utf8_Callable_Initializer :
    "Callable.Initializer".toUTF8 =
      ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 105, 116, 105, 97,
        108, 105, 122, 101, 114] := by rfl

private theorem isAsciiTagBytes_Callable_Initializer :
    isAsciiTagBytesV1 "Callable.Initializer".toUTF8 = true := by
  rw [utf8_Callable_Initializer]
  exact isAsciiTagBytes_of_list_all
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 105, 116, 105, 97, 108, 105,
      122, 101, 114] (by decide)

private theorem utf8_Callable_Entry :
    "Callable.Entry".toUTF8 =
      ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121] := by
  rfl

private theorem isAsciiTagBytes_Callable_Entry :
    isAsciiTagBytesV1 "Callable.Entry".toUTF8 = true := by
  rw [utf8_Callable_Entry]
  exact isAsciiTagBytes_of_list_all
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121] (by decide)

private theorem utf8_Callable_View :
    "Callable.View".toUTF8 =
      ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119] := by rfl

private theorem isAsciiTagBytes_Callable_View :
    isAsciiTagBytesV1 "Callable.View".toUTF8 = true := by
  rw [utf8_Callable_View]
  exact isAsciiTagBytes_of_list_all
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119] (by decide)

private theorem utf8_Callable_PureFn :
    "Callable.PureFn".toUTF8 =
      ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 80, 117, 114, 101, 70, 110] := by
  rfl

private theorem isAsciiTagBytes_Callable_PureFn :
    isAsciiTagBytesV1 "Callable.PureFn".toUTF8 = true := by
  rw [utf8_Callable_PureFn]
  exact isAsciiTagBytes_of_list_all
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 80, 117, 114, 101, 70, 110] (by decide)

private theorem utf8_Callable_Invariant :
    "Callable.Invariant".toUTF8 =
      ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105,
        97, 110, 116] := by rfl

private theorem isAsciiTagBytes_Callable_Invariant :
    isAsciiTagBytesV1 "Callable.Invariant".toUTF8 = true := by
  rw [utf8_Callable_Invariant]
  exact isAsciiTagBytes_of_list_all
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110,
      116] (by decide)

private theorem utf8_ValueDef :
    "ValueDef".toUTF8 = ByteArray.mk #[86, 97, 108, 117, 101, 68, 101, 102] := by rfl

private theorem isAsciiTagBytes_ValueDef :
    isAsciiTagBytesV1 "ValueDef".toUTF8 = true := by
  rw [utf8_ValueDef]
  exact isAsciiTagBytes_of_list_all
    [86, 97, 108, 117, 101, 68, 101, 102] (by decide)

private theorem utf8_LoopBound :
    "LoopBound".toUTF8 =
      ByteArray.mk #[76, 111, 111, 112, 66, 111, 117, 110, 100] := by rfl

private theorem isAsciiTagBytes_LoopBound :
    isAsciiTagBytesV1 "LoopBound".toUTF8 = true := by
  rw [utf8_LoopBound]
  exact isAsciiTagBytes_of_list_all
    [76, 111, 111, 112, 66, 111, 117, 110, 100] (by decide)

private theorem utf8_Op_Literal :
    "Op.Literal".toUTF8 =
      ByteArray.mk #[79, 112, 46, 76, 105, 116, 101, 114, 97, 108] := by rfl

private theorem isAsciiTagBytes_Op_Literal :
    isAsciiTagBytesV1 "Op.Literal".toUTF8 = true := by
  rw [utf8_Op_Literal]
  exact isAsciiTagBytes_of_list_all
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] (by decide)

private theorem utf8_Op_Constant :
    "Op.Constant".toUTF8 =
      ByteArray.mk #[79, 112, 46, 67, 111, 110, 115, 116, 97, 110, 116] := by rfl

private theorem isAsciiTagBytes_Op_Constant :
    isAsciiTagBytesV1 "Op.Constant".toUTF8 = true := by
  rw [utf8_Op_Constant]
  exact isAsciiTagBytes_of_list_all
    [79, 112, 46, 67, 111, 110, 115, 116, 97, 110, 116] (by decide)

private theorem utf8_Op_StateLoad :
    "Op.StateLoad".toUTF8 =
      ByteArray.mk #[79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] := by rfl

private theorem isAsciiTagBytes_Op_StateLoad :
    isAsciiTagBytesV1 "Op.StateLoad".toUTF8 = true := by
  rw [utf8_Op_StateLoad]
  exact isAsciiTagBytes_of_list_all
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] (by decide)

private theorem utf8_Op_Commit :
    "Op.Commit".toUTF8 =
      ByteArray.mk #[79, 112, 46, 67, 111, 109, 109, 105, 116] := by rfl

private theorem isAsciiTagBytes_Op_Commit :
    isAsciiTagBytesV1 "Op.Commit".toUTF8 = true := by
  rw [utf8_Op_Commit]
  exact isAsciiTagBytes_of_list_all
    [79, 112, 46, 67, 111, 109, 109, 105, 116] (by decide)

private theorem utf8_Term_Return :
    "Term.Return".toUTF8 =
      ByteArray.mk #[84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] := by rfl

private theorem isAsciiTagBytes_Term_Return :
    isAsciiTagBytesV1 "Term.Return".toUTF8 = true := by
  rw [utf8_Term_Return]
  exact isAsciiTagBytes_of_list_all
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] (by decide)

/-! ### Tagged layout helpers -/

theorem taggedBytes_two_fields (tag : String) (f0 f1 : ByteArray) :
    taggedBytesV1 tag #[f0, f1] = taggedHeaderBytesV1 tag 2 ++ f0 ++ f1 := by
  have h := taggedBytesV1_eq_header_payload tag #[f0, f1]
  have hfold :
      (#[f0, f1] : Array ByteArray).foldl (fun out f => out.append f) ByteArray.empty =
        f0 ++ f1 := by
    simp [List.foldl]
  have hsz : (#[f0, f1] : Array ByteArray).size = 2 := rfl
  rw [h, hfold, hsz]
  simp [ByteArray.append_assoc]

private theorem encodeNullary_ok_taggedHeader (tag : String)
    (hnonempty : tag.isEmpty = false)
    (hascii : isAsciiTagV1 tag = true)
    (hlimit : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (b : ByteArray)
    (h : encodeNullary tag = .ok b) :
    b = taggedHeaderBytesV1 tag 0 := by
  have hok := encodeNullary_eq_okV1 tag hnonempty hascii hlimit
  have hb := Except.ok.inj (h.symm.trans hok)
  rw [hb]
  simp only [taggedHeaderBytesV1]
  rfl

/-! ### Nullary tag+fieldCount mid-offset (for CallableKind) -/

private theorem decodeNullaryTagged_midV1
    (tag : String) (left right : ByteArray) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true) :
    decodeTag ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right, left.size, nesting⟩ =
        .ok (tag,
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
            left.size + 4 + tag.toUTF8.size, nesting⟩) ∧
      decodeFieldCount 0
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
            left.size + 4 + tag.toUTF8.size, nesting⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
            left.size + (taggedHeaderBytesV1 tag 0).size, nesting⟩) := by
  have henc :
      taggedHeaderBytesV1 tag 0 =
        encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          encodeU16le 0 := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have hin :
      left ++ taggedHeaderBytesV1 tag 0 ++ right =
        left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          (encodeU16le 0 ++ right) := by
    simp [henc, ByteArray.append_assoc]
  have htag :
      decodeTag ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right, left.size, nesting⟩ =
        .ok (tag,
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
            left.size + 4 + tag.toUTF8.size, nesting⟩) := by
    rw [hin]
    have h :=
      decodeTag_encode_midV1 left (encodeU16le 0 ++ right) tag nesting
        hnonempty hmax hfit hasciiBytes hasciiTag
    simpa [hin.symm, ByteArray.append_assoc] using h
  have hszFinal :
      left.size + 4 + tag.toUTF8.size + 2 =
        left.size + (taggedHeaderBytesV1 tag 0).size := by
    simp only [taggedHeaderBytesV1_size]; omega
  have hfc :
      decodeFieldCount 0
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
            left.size + 4 + tag.toUTF8.size, nesting⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
            left.size + (taggedHeaderBytesV1 tag 0).size, nesting⟩) := by
    have hassoc :
        left ++ taggedHeaderBytesV1 tag 0 ++ right =
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
            encodeU16le 0 ++ right := by
      simp [henc, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8).size =
          left.size + 4 + tag.toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1 (left ++ taggedHeaderBytesV1 tag 0 ++ right)
            (left.size + 4 + tag.toUTF8.size) =
          .ok (0, left.size + 4 + tag.toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8)
          right 0
    rw [← hszFinal]
    exact decodeFieldCount_eq_of_readU16leV1 0
      ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
        left.size + 4 + tag.toUTF8.size, nesting⟩
      0 (left.size + 4 + tag.toUTF8.size + 2) hread
  exact And.intro htag hfc

/-! ### CallableKind full MidOffsetInvert -/

private theorem decodeCallableKindBodyV1_initializer (c afterTag afterFields : Cursor)
    (htag : decodeTag c = .ok ("Callable.Initializer", afterTag))
    (hfields : decodeFieldCount 0 afterTag = .ok ((), afterFields)) :
    decodeCallableKindBodyV1 c = .ok (.initializer, afterFields) := by
  simp only [decodeCallableKindBodyV1, htag, hfields, Bind.bind, Pure.pure,
    Except.bind, Except.pure]

theorem encodeCallableKind_initializer_eq :
    encodeCallableKindV1 .initializer =
      .ok (taggedHeaderBytesV1 "Callable.Initializer" 0) := by
  change encodeNullary "Callable.Initializer" =
    .ok (taggedHeaderBytesV1 "Callable.Initializer" 0)
  have h := encodeNullary_eq_okV1 "Callable.Initializer" (by decide) (by decide) (by decide)
  have heq :
      (((encodeU32le (UInt32.ofNat "Callable.Initializer".toUTF8.size)).append
          "Callable.Initializer".toUTF8).append (encodeU16le 0)) =
        taggedHeaderBytesV1 "Callable.Initializer" 0 := by
    simp only [taggedHeaderBytesV1]; rfl
  rwa [heq] at h

theorem encodeCallableKind_entry_eq :
    encodeCallableKindV1 .entry = .ok (taggedHeaderBytesV1 "Callable.Entry" 0) := by
  change encodeNullary "Callable.Entry" = .ok (taggedHeaderBytesV1 "Callable.Entry" 0)
  have h := encodeNullary_eq_okV1 "Callable.Entry" (by decide) (by decide) (by decide)
  have heq :
      (((encodeU32le (UInt32.ofNat "Callable.Entry".toUTF8.size)).append
          "Callable.Entry".toUTF8).append (encodeU16le 0)) =
        taggedHeaderBytesV1 "Callable.Entry" 0 := by
    simp only [taggedHeaderBytesV1]; rfl
  rwa [heq] at h

theorem encodeCallableKind_view_eq :
    encodeCallableKindV1 .view = .ok (taggedHeaderBytesV1 "Callable.View" 0) := by
  change encodeNullary "Callable.View" = .ok (taggedHeaderBytesV1 "Callable.View" 0)
  have h := encodeNullary_eq_okV1 "Callable.View" (by decide) (by decide) (by decide)
  have heq :
      (((encodeU32le (UInt32.ofNat "Callable.View".toUTF8.size)).append
          "Callable.View".toUTF8).append (encodeU16le 0)) =
        taggedHeaderBytesV1 "Callable.View" 0 := by
    simp only [taggedHeaderBytesV1]; rfl
  rwa [heq] at h

theorem encodeCallableKind_pureFn_eq :
    encodeCallableKindV1 .pureFn = .ok (taggedHeaderBytesV1 "Callable.PureFn" 0) := by
  change encodeNullary "Callable.PureFn" = .ok (taggedHeaderBytesV1 "Callable.PureFn" 0)
  have h := encodeNullary_eq_okV1 "Callable.PureFn" (by decide) (by decide) (by decide)
  have heq :
      (((encodeU32le (UInt32.ofNat "Callable.PureFn".toUTF8.size)).append
          "Callable.PureFn".toUTF8).append (encodeU16le 0)) =
        taggedHeaderBytesV1 "Callable.PureFn" 0 := by
    simp only [taggedHeaderBytesV1]; rfl
  rwa [heq] at h

theorem encodeCallableKind_invariant_eq :
    encodeCallableKindV1 .invariant =
      .ok (taggedHeaderBytesV1 "Callable.Invariant" 0) := by
  change encodeNullary "Callable.Invariant" =
    .ok (taggedHeaderBytesV1 "Callable.Invariant" 0)
  have h := encodeNullary_eq_okV1 "Callable.Invariant" (by decide) (by decide) (by decide)
  have heq :
      (((encodeU32le (UInt32.ofNat "Callable.Invariant".toUTF8.size)).append
          "Callable.Invariant".toUTF8).append (encodeU16le 0)) =
        taggedHeaderBytesV1 "Callable.Invariant" 0 := by
    simp only [taggedHeaderBytesV1]; rfl
  rwa [heq] at h

private theorem decodeCallableKind_nullary_midV1
    (tag : String) (kind : CallableKindV1)
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true)
    (hbody :
      ∀ (c afterTag afterFields : Cursor),
        decodeTag c = .ok (tag, afterTag) →
        decodeFieldCount 0 afterTag = .ok ((), afterFields) →
        decodeCallableKindBodyV1 c = .ok (kind, afterFields)) :
    decodeCallableKindV1
        ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right, left.size, nesting⟩ =
      .ok (kind,
        ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
          left.size + (taggedHeaderBytesV1 tag 0).size, nesting⟩) := by
  obtain ⟨htag, hfc⟩ :=
    decodeNullaryTagged_midV1 tag left right (nesting + 1) hnonempty hmax hfit
      hasciiBytes hasciiTag
  refine decodeCallableKindV1_eq_of_bodyV1
    ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right, left.size, nesting⟩ kind
    ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
      left.size + (taggedHeaderBytesV1 tag 0).size, nesting + 1⟩ hdepth ?_
  exact hbody _ _ _ htag hfc

theorem decodeCallableKind_of_encode_midV1
    (kind : CallableKindV1) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeCallableKindV1 kind = .ok b) :
    decodeCallableKindV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (kind, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  match kind with
  | .initializer =>
      have hb : b = taggedHeaderBytesV1 "Callable.Initializer" 0 :=
        Except.ok.inj (henc.symm.trans encodeCallableKind_initializer_eq)
      subst b
      exact decodeCallableKind_nullary_midV1 "Callable.Initializer" .initializer
        left right nesting hdepth (by decide) (by decide) (by decide)
        isAsciiTagBytes_Callable_Initializer (by decide)
        (fun c afterTag afterFields htag hfields =>
          decodeCallableKindBodyV1_initializer c afterTag afterFields htag hfields)
  | .entry =>
      have hb : b = taggedHeaderBytesV1 "Callable.Entry" 0 :=
        Except.ok.inj (henc.symm.trans encodeCallableKind_entry_eq)
      subst b
      exact decodeCallableKind_nullary_midV1 "Callable.Entry" .entry
        left right nesting hdepth (by decide) (by decide) (by decide)
        isAsciiTagBytes_Callable_Entry (by decide)
        (fun c afterTag afterFields htag hfields =>
          decodeCallableKindBodyV1_entry c afterTag afterFields htag hfields)
  | .view =>
      have hb : b = taggedHeaderBytesV1 "Callable.View" 0 :=
        Except.ok.inj (henc.symm.trans encodeCallableKind_view_eq)
      subst b
      exact decodeCallableKind_nullary_midV1 "Callable.View" .view
        left right nesting hdepth (by decide) (by decide) (by decide)
        isAsciiTagBytes_Callable_View (by decide)
        (fun c afterTag afterFields htag hfields =>
          decodeCallableKindBodyV1_view c afterTag afterFields htag hfields)
  | .pureFn =>
      have hb : b = taggedHeaderBytesV1 "Callable.PureFn" 0 :=
        Except.ok.inj (henc.symm.trans encodeCallableKind_pureFn_eq)
      subst b
      exact decodeCallableKind_nullary_midV1 "Callable.PureFn" .pureFn
        left right nesting hdepth (by decide) (by decide) (by decide)
        isAsciiTagBytes_Callable_PureFn (by decide)
        (fun c afterTag afterFields htag hfields =>
          decodeCallableKindBodyV1_pureFn c afterTag afterFields htag hfields)
  | .invariant =>
      have hb : b = taggedHeaderBytesV1 "Callable.Invariant" 0 :=
        Except.ok.inj (henc.symm.trans encodeCallableKind_invariant_eq)
      subst b
      exact decodeCallableKind_nullary_midV1 "Callable.Invariant" .invariant
        left right nesting hdepth (by decide) (by decide) (by decide)
        isAsciiTagBytes_Callable_Invariant (by decide)
        (fun c afterTag afterFields htag hfields =>
          decodeCallableKindBodyV1_invariant c afterTag afterFields htag hfields)

theorem midOffsetInvert_encodeCallableKind_decodeCallableKind :
    MidOffsetInvertV1 encodeCallableKindV1 decodeCallableKindV1 := by
  intro kind b left right nesting hdepth henc
  exact decodeCallableKind_of_encode_midV1 kind b left right nesting hdepth henc

/-! ### ValueDef MidOffsetInvert -/

theorem encodeValueDef_ok_eqV1 (v : ValueDefV1) (b : ByteArray)
    (h : encodeValueDefV1 v = .ok b) :
    b = taggedBytesV1 "ValueDef" #[encodeU32le v.valueId, encodeU32le v.typeId] := by
  simp only [encodeValueDefV1] at h
  have htag := encodeTagged_ok_eq_taggedBytesV1 "ValueDef"
    #[encodeU32le v.valueId, encodeU32le v.typeId] b h
  exact htag.1

theorem decodeValueDef_of_encode_midV1
    (v : ValueDefV1) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeValueDefV1 v = .ok b) :
    decodeValueDefV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (v, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeValueDef_ok_eqV1 v b henc
  subst b
  have hbodyBytes :=
    taggedBytes_two_fields "ValueDef" (encodeU32le v.valueId) (encodeU32le v.typeId)
  have hflatIn :
      left ++
          (taggedHeaderBytesV1 "ValueDef" 2 ++
            encodeU32le v.valueId ++ encodeU32le v.typeId) ++
          right =
        left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
          encodeU32le v.valueId ++ encodeU32le v.typeId ++ right := by
    simp [ByteArray.append_assoc]
  rw [hbodyBytes, hflatIn]
  have hexpect :
      expectTag "ValueDef" 2
          ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
              encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
            left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
              encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
            left.size + (taggedHeaderBytesV1 "ValueDef" 2).size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
            encodeU32le v.valueId ++ encodeU32le v.typeId ++ right =
          left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
            (encodeU32le v.valueId ++ encodeU32le v.typeId) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "ValueDef" 2
      (encodeU32le v.valueId ++ encodeU32le v.typeId) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiTagBytes_ValueDef (by decide)
  have hvalue :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
              encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
            left.size + (taggedHeaderBytesV1 "ValueDef" 2).size, nesting + 1⟩ =
        .ok (v.valueId,
          ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
              encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
            left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
            encodeU32le v.valueId ++ encodeU32le v.typeId ++ right =
          (left ++ taggedHeaderBytesV1 "ValueDef" 2) ++ encodeU32le v.valueId ++
            (encodeU32le v.typeId ++ right) := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "ValueDef" 2).size =
          left.size + (taggedHeaderBytesV1 "ValueDef" 2).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hszL]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "ValueDef" 2)
      (encodeU32le v.typeId ++ right) v.valueId (nesting + 1)
  have htype :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
              encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
            left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4, nesting + 1⟩ =
        .ok (v.typeId,
          ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
              encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
            left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4 + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
            encodeU32le v.valueId ++ encodeU32le v.typeId ++ right =
          (left ++ taggedHeaderBytesV1 "ValueDef" 2 ++ encodeU32le v.valueId) ++
            encodeU32le v.typeId ++ right := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "ValueDef" 2 ++ encodeU32le v.valueId).size =
          left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [hin, ← hszL]
    exact decodeU32le_encode_midV1
      (left ++ taggedHeaderBytesV1 "ValueDef" 2 ++ encodeU32le v.valueId)
      right v.typeId (nesting + 1)
  have hshell :=
    decodeValueDefV1_eq_of_fieldsV1
      ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
          encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
        left.size, nesting⟩
      ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
          encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
        left.size + (taggedHeaderBytesV1 "ValueDef" 2).size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
          encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
        left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "ValueDef" 2 ++
          encodeU32le v.valueId ++ encodeU32le v.typeId ++ right,
        left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4 + 4, nesting + 1⟩
      v.valueId v.typeId hdepth hexpect hvalue htype
  have heq : ({ valueId := v.valueId, typeId := v.typeId } : ValueDefV1) = v := by
    cases v; rfl
  have hsz :
      left.size + (taggedHeaderBytesV1 "ValueDef" 2).size + 4 + 4 =
        left.size +
          (taggedHeaderBytesV1 "ValueDef" 2 ++
            encodeU32le v.valueId ++ encodeU32le v.typeId).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  have h0 := hshell
  rw [heq] at h0
  rw [h0, hsz]

theorem midOffsetInvert_encodeValueDef_decodeValueDef :
    MidOffsetInvertV1 encodeValueDefV1 decodeValueDefV1 := by
  intro v b left right nesting hdepth henc
  exact decodeValueDef_of_encode_midV1 v b left right nesting hdepth henc

/-! ### LoopBound MidOffsetInvert -/

theorem encodeLoopBound_ok_eqV1 (lb : LoopBoundV1) (b : ByteArray)
    (h : encodeLoopBoundV1 lb = .ok b) :
    b = taggedBytesV1 "LoopBound"
      #[encodeU32le lb.header, encodeU32le lb.backEdgeFrom,
        encodeU32le lb.maxIterations] := by
  simp only [encodeLoopBoundV1] at h
  have htag := encodeTagged_ok_eq_taggedBytesV1 "LoopBound"
    #[encodeU32le lb.header, encodeU32le lb.backEdgeFrom, encodeU32le lb.maxIterations]
    b h
  exact htag.1

theorem decodeLoopBound_of_encode_midV1
    (lb : LoopBoundV1) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeLoopBoundV1 lb = .ok b) :
    decodeLoopBoundV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (lb, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeLoopBound_ok_eqV1 lb b henc
  subst b
  have hbodyBytes :=
    taggedBytes_three_fields "LoopBound" (encodeU32le lb.header)
      (encodeU32le lb.backEdgeFrom) (encodeU32le lb.maxIterations)
  have hflatIn :
      left ++
          (taggedHeaderBytesV1 "LoopBound" 3 ++
            encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
              encodeU32le lb.maxIterations) ++
          right =
        left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
          encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
            encodeU32le lb.maxIterations ++ right := by
    simp [ByteArray.append_assoc]
  rw [hbodyBytes, hflatIn]
  have hexpect :
      expectTag "LoopBound" 3
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size + (taggedHeaderBytesV1 "LoopBound" 3).size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
            encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
              encodeU32le lb.maxIterations ++ right =
          left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
            (encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
              encodeU32le lb.maxIterations) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "LoopBound" 3
      (encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
        encodeU32le lb.maxIterations) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiTagBytes_LoopBound (by decide)
  have hheader :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size + (taggedHeaderBytesV1 "LoopBound" 3).size, nesting + 1⟩ =
        .ok (lb.header,
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
            encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
              encodeU32le lb.maxIterations ++ right =
          (left ++ taggedHeaderBytesV1 "LoopBound" 3) ++ encodeU32le lb.header ++
            (encodeU32le lb.backEdgeFrom ++ encodeU32le lb.maxIterations ++ right) := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "LoopBound" 3).size =
          left.size + (taggedHeaderBytesV1 "LoopBound" 3).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hszL]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "LoopBound" 3)
      (encodeU32le lb.backEdgeFrom ++ encodeU32le lb.maxIterations ++ right)
      lb.header (nesting + 1)
  have hback :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4, nesting + 1⟩ =
        .ok (lb.backEdgeFrom,
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4 + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
            encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
              encodeU32le lb.maxIterations ++ right =
          (left ++ taggedHeaderBytesV1 "LoopBound" 3 ++ encodeU32le lb.header) ++
            encodeU32le lb.backEdgeFrom ++
              (encodeU32le lb.maxIterations ++ right) := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "LoopBound" 3 ++ encodeU32le lb.header).size =
          left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [hin, ← hszL]
    exact decodeU32le_encode_midV1
      (left ++ taggedHeaderBytesV1 "LoopBound" 3 ++ encodeU32le lb.header)
      (encodeU32le lb.maxIterations ++ right) lb.backEdgeFrom (nesting + 1)
  have hmaxI :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4 + 4,
            nesting + 1⟩ =
        .ok (lb.maxIterations,
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4 + 4 + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
            encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
              encodeU32le lb.maxIterations ++ right =
          (left ++ taggedHeaderBytesV1 "LoopBound" 3 ++ encodeU32le lb.header ++
              encodeU32le lb.backEdgeFrom) ++
            encodeU32le lb.maxIterations ++ right := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "LoopBound" 3 ++ encodeU32le lb.header ++
            encodeU32le lb.backEdgeFrom).size =
          left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4 + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [hin, ← hszL]
    exact decodeU32le_encode_midV1
      (left ++ taggedHeaderBytesV1 "LoopBound" 3 ++ encodeU32le lb.header ++
        encodeU32le lb.backEdgeFrom)
      right lb.maxIterations (nesting + 1)
  have hshell :=
    decodeLoopBoundV1_eq_of_fieldsV1
      ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
          encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
            encodeU32le lb.maxIterations ++ right,
        left.size, nesting⟩
      ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
          encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
            encodeU32le lb.maxIterations ++ right,
        left.size + (taggedHeaderBytesV1 "LoopBound" 3).size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
          encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
            encodeU32le lb.maxIterations ++ right,
        left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
          encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
            encodeU32le lb.maxIterations ++ right,
        left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4 + 4, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
          encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
            encodeU32le lb.maxIterations ++ right,
        left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4 + 4 + 4, nesting + 1⟩
      lb.header lb.backEdgeFrom lb.maxIterations hdepth hexpect hheader hback hmaxI
  have hsz :
      left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4 + 4 + 4 =
        left.size +
          (taggedHeaderBytesV1 "LoopBound" 3 ++
            encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
              encodeU32le lb.maxIterations).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  -- Structure η: reconstructed fields recover `lb`.
  have h0 :
      decodeLoopBoundV1
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size, nesting⟩ =
        .ok (lb,
          ⟨left ++ taggedHeaderBytesV1 "LoopBound" 3 ++
              encodeU32le lb.header ++ encodeU32le lb.backEdgeFrom ++
                encodeU32le lb.maxIterations ++ right,
            left.size + (taggedHeaderBytesV1 "LoopBound" 3).size + 4 + 4 + 4,
            nesting⟩) := by
    cases lb
    simpa using hshell
  rw [h0, hsz]

theorem midOffsetInvert_encodeLoopBound_decodeLoopBound :
    MidOffsetInvertV1 encodeLoopBoundV1 decodeLoopBoundV1 := by
  intro lb b left right nesting hdepth henc
  exact decodeLoopBound_of_encode_midV1 lb b left right nesting hdepth henc

/-! ### SemanticOp pure-U32 + Literal -/

private theorem decodeSemanticOpBodyV1_constant
    (c afterTag afterFields afterId : Cursor) (constantId : UInt32)
    (htag : decodeTag c = .ok ("Op.Constant", afterTag))
    (hfields : decodeFieldCount 1 afterTag = .ok ((), afterFields))
    (hid : decodeU32le afterFields = .ok (constantId, afterId)) :
    decodeSemanticOpBodyV1 c = .ok (.constant constantId, afterId) := by
  simp only [decodeSemanticOpBodyV1, htag, hfields, hid, Bind.bind, Pure.pure,
    Except.bind, Except.pure]

private theorem decodeSemanticOpBodyV1_stateLoad
    (c afterTag afterFields afterId : Cursor) (stateId : UInt32)
    (htag : decodeTag c = .ok ("Op.StateLoad", afterTag))
    (hfields : decodeFieldCount 1 afterTag = .ok ((), afterFields))
    (hid : decodeU32le afterFields = .ok (stateId, afterId)) :
    decodeSemanticOpBodyV1 c = .ok (.stateLoad stateId, afterId) := by
  simp only [decodeSemanticOpBodyV1, htag, hfields, hid, Bind.bind, Pure.pure,
    Except.bind, Except.pure]

private theorem decodeSemanticOpBodyV1_commit
    (c afterTag afterFields afterId : Cursor) (value : UInt32)
    (htag : decodeTag c = .ok ("Op.Commit", afterTag))
    (hfields : decodeFieldCount 1 afterTag = .ok ((), afterFields))
    (hid : decodeU32le afterFields = .ok (value, afterId)) :
    decodeSemanticOpBodyV1 c = .ok (.commit value, afterId) := by
  simp only [decodeSemanticOpBodyV1, htag, hfields, hid, Bind.bind, Pure.pure,
    Except.bind, Except.pure]

private theorem decodeSemanticOp_one_u32_midV1
    (tag : String) (mk : UInt32 → SemanticOpV1) (id : UInt32)
    (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true)
    (hbody :
      ∀ (c afterTag afterFields afterId : Cursor),
        decodeTag c = .ok (tag, afterTag) →
        decodeFieldCount 1 afterTag = .ok ((), afterFields) →
        decodeU32le afterFields = .ok (id, afterId) →
        decodeSemanticOpBodyV1 c = .ok (mk id, afterId)) :
    decodeSemanticOpV1
        ⟨left ++ taggedBytesV1 tag #[encodeU32le id] ++ right, left.size, nesting⟩ =
      .ok (mk id,
        ⟨left ++ taggedBytesV1 tag #[encodeU32le id] ++ right,
          left.size + (taggedBytesV1 tag #[encodeU32le id]).size, nesting⟩) := by
  have hlayout := taggedBytes_one_field tag (encodeU32le id)
  have hflatIn :
      left ++ (taggedHeaderBytesV1 tag 1 ++ encodeU32le id) ++ right =
        left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflatIn]
  have henc :
      taggedHeaderBytesV1 tag 1 =
        encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          encodeU16le 1 := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
            left.size, nesting + 1⟩ =
        .ok (tag,
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
            left.size + 4 + tag.toUTF8.size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right =
          left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
            (encodeU16le 1 ++ encodeU32le id ++ right) := by
      simp [henc, ByteArray.append_assoc]
    rw [hin]
    simpa [ByteArray.append_assoc] using
      decodeTag_encode_midV1 left (encodeU16le 1 ++ encodeU32le id ++ right) tag
        (nesting + 1) hnonempty hmax hfit hasciiBytes hasciiTag
  have hfc :
      decodeFieldCount 1
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
            left.size + 4 + tag.toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
            left.size + (taggedHeaderBytesV1 tag 1).size, nesting + 1⟩) := by
    have hassoc :
        left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right =
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
            encodeU16le 1 ++ (encodeU32le id ++ right) := by
      simp [henc, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8).size =
          left.size + 4 + tag.toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1 (left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right)
            (left.size + 4 + tag.toUTF8.size) =
          .ok (1, left.size + 4 + tag.toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8)
          (encodeU32le id ++ right) 1
    have hszFinal :
        left.size + 4 + tag.toUTF8.size + 2 =
          left.size + (taggedHeaderBytesV1 tag 1).size := by
      simp only [taggedHeaderBytesV1_size]; omega
    rw [← hszFinal]
    exact decodeFieldCount_eq_of_readU16leV1 1
      ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
        left.size + 4 + tag.toUTF8.size, nesting + 1⟩
      1 (left.size + 4 + tag.toUTF8.size + 2) hread
  have hid :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
            left.size + (taggedHeaderBytesV1 tag 1).size, nesting + 1⟩ =
        .ok (id,
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
            left.size + (taggedHeaderBytesV1 tag 1).size + 4, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right =
          (left ++ taggedHeaderBytesV1 tag 1) ++ encodeU32le id ++ right := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 tag 1).size =
          left.size + (taggedHeaderBytesV1 tag 1).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hszL]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 tag 1) right id
      (nesting + 1)
  have hbody' :=
    hbody
      ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
        left.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
        left.size + 4 + tag.toUTF8.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
        left.size + (taggedHeaderBytesV1 tag 1).size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
        left.size + (taggedHeaderBytesV1 tag 1).size + 4, nesting + 1⟩
      htag hfc hid
  have hshell :=
    decodeSemanticOpV1_eq_of_bodyV1
      ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right, left.size, nesting⟩
      (mk id)
      ⟨left ++ taggedHeaderBytesV1 tag 1 ++ encodeU32le id ++ right,
        left.size + (taggedHeaderBytesV1 tag 1).size + 4, nesting + 1⟩
      hdepth hbody'
  have hsz :
      left.size + (taggedHeaderBytesV1 tag 1).size + 4 =
        left.size + (taggedHeaderBytesV1 tag 1 ++ encodeU32le id).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  have h0 := hshell
  rw [h0, hsz]

theorem encodeSemanticOp_constant_ok_eq (id : UInt32) (b : ByteArray)
    (h : encodeSemanticOpV1 (.constant id) = .ok b) :
    b = taggedBytesV1 "Op.Constant" #[encodeU32le id] := by
  simp only [encodeSemanticOpV1] at h
  exact (encodeTagged_ok_eq_taggedBytesV1 "Op.Constant" #[encodeU32le id] b h).1

theorem decodeSemanticOp_constant_of_encode_midV1
    (id : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.constant id) = .ok b) :
    decodeSemanticOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.constant id, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeSemanticOp_constant_ok_eq id b henc
  subst b
  exact decodeSemanticOp_one_u32_midV1 "Op.Constant" SemanticOpV1.constant id
    left right nesting hdepth (by decide) (by decide) (by decide)
    isAsciiTagBytes_Op_Constant (by decide)
    (fun c afterTag afterFields afterId htag hfields hid =>
      decodeSemanticOpBodyV1_constant c afterTag afterFields afterId id htag hfields hid)

theorem encodeSemanticOp_stateLoad_ok_eq (id : UInt32) (b : ByteArray)
    (h : encodeSemanticOpV1 (.stateLoad id) = .ok b) :
    b = taggedBytesV1 "Op.StateLoad" #[encodeU32le id] := by
  simp only [encodeSemanticOpV1] at h
  exact (encodeTagged_ok_eq_taggedBytesV1 "Op.StateLoad" #[encodeU32le id] b h).1

theorem decodeSemanticOp_stateLoad_of_encode_midV1
    (id : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.stateLoad id) = .ok b) :
    decodeSemanticOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.stateLoad id, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeSemanticOp_stateLoad_ok_eq id b henc
  subst b
  exact decodeSemanticOp_one_u32_midV1 "Op.StateLoad" SemanticOpV1.stateLoad id
    left right nesting hdepth (by decide) (by decide) (by decide)
    isAsciiTagBytes_Op_StateLoad (by decide)
    (fun c afterTag afterFields afterId htag hfields hid =>
      decodeSemanticOpBodyV1_stateLoad c afterTag afterFields afterId id htag hfields hid)

theorem encodeSemanticOp_commit_ok_eq (id : UInt32) (b : ByteArray)
    (h : encodeSemanticOpV1 (.commit id) = .ok b) :
    b = taggedBytesV1 "Op.Commit" #[encodeU32le id] := by
  simp only [encodeSemanticOpV1] at h
  exact (encodeTagged_ok_eq_taggedBytesV1 "Op.Commit" #[encodeU32le id] b h).1

theorem decodeSemanticOp_commit_of_encode_midV1
    (id : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.commit id) = .ok b) :
    decodeSemanticOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.commit id, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeSemanticOp_commit_ok_eq id b henc
  subst b
  exact decodeSemanticOp_one_u32_midV1 "Op.Commit" SemanticOpV1.commit id
    left right nesting hdepth (by decide) (by decide) (by decide)
    isAsciiTagBytes_Op_Commit (by decide)
    (fun c afterTag afterFields afterId htag hfields hid =>
      decodeSemanticOpBodyV1_commit c afterTag afterFields afterId id htag hfields hid)

theorem encodeSemanticOp_literal_ok_eq (typeId : UInt32) (valueBytes b : ByteArray)
    (h : encodeSemanticOpV1 (.literal typeId valueBytes) = .ok b) :
    ∃ vb,
      encodeByteArray valueBytes = .ok vb ∧
        b = taggedBytesV1 "Op.Literal" #[encodeU32le typeId, vb] := by
  simp only [encodeSemanticOpV1] at h
  match hv : encodeByteArray valueBytes with
  | .error e => simp only [hv, Bind.bind, Except.bind] at h; cases h
  | .ok vb =>
      simp only [hv, Bind.bind, Except.bind] at h
      exact ⟨vb, rfl,
        (encodeTagged_ok_eq_taggedBytesV1 "Op.Literal" #[encodeU32le typeId, vb] b h).1⟩

theorem decodeSemanticOp_literal_of_encode_midV1
    (typeId : UInt32) (valueBytes b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.literal typeId valueBytes) = .ok b) :
    decodeSemanticOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.literal typeId valueBytes,
        ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨vb, hvb, hb⟩ := encodeSemanticOp_literal_ok_eq typeId valueBytes b henc
  subst b
  have hlayout :=
    taggedBytes_two_fields "Op.Literal" (encodeU32le typeId) vb
  have hflatIn :
      left ++ (taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb) ++
          right =
        left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
          right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflatIn]
  have hencH :
      taggedHeaderBytesV1 "Op.Literal" 2 =
        encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++ "Op.Literal".toUTF8 ++
          encodeU16le 2 := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
              right,
            left.size, nesting + 1⟩ =
        .ok ("Op.Literal",
          ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
              right,
            left.size + 4 + "Op.Literal".toUTF8.size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
            right =
          left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++
            "Op.Literal".toUTF8 ++
              (encodeU16le 2 ++ encodeU32le typeId ++ vb ++ right) := by
      simp [hencH, ByteArray.append_assoc]
    rw [hin]
    simpa [ByteArray.append_assoc] using
      decodeTag_encode_midV1 left
        (encodeU16le 2 ++ encodeU32le typeId ++ vb ++ right) "Op.Literal"
        (nesting + 1) (by decide) (by decide) (by decide)
        isAsciiTagBytes_Op_Literal (by decide)
  have hfc :
      decodeFieldCount 2
          ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
              right,
            left.size + 4 + "Op.Literal".toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
              right,
            left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size, nesting + 1⟩) := by
    have hassoc :
        left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
            right =
          (left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++
              "Op.Literal".toUTF8) ++
            encodeU16le 2 ++ (encodeU32le typeId ++ vb ++ right) := by
      simp [hencH, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++
            "Op.Literal".toUTF8).size =
          left.size + 4 + "Op.Literal".toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1
            (left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
              right)
            (left.size + 4 + "Op.Literal".toUTF8.size) =
          .ok (2, left.size + 4 + "Op.Literal".toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat "Op.Literal".toUTF8.size) ++
            "Op.Literal".toUTF8)
          (encodeU32le typeId ++ vb ++ right) 2
    have hszFinal :
        left.size + 4 + "Op.Literal".toUTF8.size + 2 =
          left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size := by
      simp only [taggedHeaderBytesV1_size]; omega
    rw [← hszFinal]
    exact decodeFieldCount_eq_of_readU16leV1 2
      ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++ right,
        left.size + 4 + "Op.Literal".toUTF8.size, nesting + 1⟩
      2 (left.size + 4 + "Op.Literal".toUTF8.size + 2) hread
  have htype :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
              right,
            left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size, nesting + 1⟩ =
        .ok (typeId,
          ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
              right,
            left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
            right =
          (left ++ taggedHeaderBytesV1 "Op.Literal" 2) ++ encodeU32le typeId ++
            (vb ++ right) := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "Op.Literal" 2).size =
          left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hszL]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "Op.Literal" 2)
      (vb ++ right) typeId (nesting + 1)
  have hbytes :
      decodeByteArray maxCanonicalProgramBytes
          ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
              right,
            left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size + 4,
            nesting + 1⟩ =
        .ok (valueBytes,
          ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
              right,
            left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size + 4 + vb.size,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++
            right =
          (left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId) ++
            vb ++ right := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId).size =
          left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [hin, ← hszL]
    exact decodeByteArray_of_encode_midV1
      (left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId)
      right valueBytes vb (nesting + 1) hvb
  have hshell :=
    decodeSemanticOpV1_literal
      ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++ right,
        left.size, nesting⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++ right,
        left.size + 4 + "Op.Literal".toUTF8.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++ right,
        left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++ right,
        left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size + 4, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb ++ right,
        left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size + 4 + vb.size,
        nesting + 1⟩
      typeId valueBytes hdepth htag hfc htype hbytes
  have hsz :
      left.size + (taggedHeaderBytesV1 "Op.Literal" 2).size + 4 + vb.size =
        left.size +
          (taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  have h0 := hshell
  rw [h0, hsz]

/-! ### Term.Return MidOffsetInvert -/

theorem encodeTerminator_return_none_ok_eq (b : ByteArray)
    (h : encodeTerminatorV1 (.return_ none) = .ok b) :
    b = taggedBytesV1 "Term.Return" #[encodeU8 0] := by
  simp only [encodeTerminatorV1, encodeOption] at h
  exact (encodeTagged_ok_eq_taggedBytesV1 "Term.Return" #[encodeU8 0] b h).1

theorem encodeTerminator_return_some_ok_eq (id : UInt32) (b : ByteArray)
    (h : encodeTerminatorV1 (.return_ (some id)) = .ok b) :
    b = taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le id] := by
  simp only [encodeTerminatorV1, encodeOption, Pure.pure, Bind.bind, Except.bind,
    Except.pure] at h
  have htag :=
    encodeTagged_ok_eq_taggedBytesV1 "Term.Return"
      #[(encodeU8 1).append (encodeU32le id)] b h
  exact htag.1.trans (by simp [ByteArray.append_eq])

private theorem decodeTag_fieldCount_midV1
    (tag : String) (fieldCount : UInt16) (payload left right : ByteArray) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true) :
    decodeTag
        ⟨left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right, left.size, nesting⟩ =
      .ok (tag,
        ⟨left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right,
          left.size + 4 + tag.toUTF8.size, nesting⟩) ∧
    decodeFieldCount fieldCount.toNat
        ⟨left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right,
          left.size + 4 + tag.toUTF8.size, nesting⟩ =
      .ok ((),
        ⟨left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right,
          left.size + (taggedHeaderBytesV1 tag fieldCount.toNat).size, nesting⟩) := by
  have henc :
      taggedHeaderBytesV1 tag fieldCount.toNat =
        encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          encodeU16le fieldCount := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right, left.size, nesting⟩ =
        .ok (tag,
          ⟨left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right,
            left.size + 4 + tag.toUTF8.size, nesting⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right =
          left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
            (encodeU16le fieldCount ++ payload ++ right) := by
      simp [henc, ByteArray.append_assoc]
    rw [hin]
    simpa [ByteArray.append_assoc] using
      decodeTag_encode_midV1 left (encodeU16le fieldCount ++ payload ++ right) tag nesting
        hnonempty hmax hfit hasciiBytes hasciiTag
  have hfc :
      decodeFieldCount fieldCount.toNat
          ⟨left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right,
            left.size + 4 + tag.toUTF8.size, nesting⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right,
            left.size + (taggedHeaderBytesV1 tag fieldCount.toNat).size, nesting⟩) := by
    have hassoc :
        left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right =
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
            encodeU16le fieldCount ++ (payload ++ right) := by
      simp [henc, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8).size =
          left.size + 4 + tag.toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1 (left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right)
            (left.size + 4 + tag.toUTF8.size) =
          .ok (fieldCount, left.size + 4 + tag.toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8)
          (payload ++ right) fieldCount
    have hszFinal :
        left.size + 4 + tag.toUTF8.size + 2 =
          left.size + (taggedHeaderBytesV1 tag fieldCount.toNat).size := by
      simp only [taggedHeaderBytesV1_size]; omega
    rw [← hszFinal]
    have h := decodeFieldCount_eq_of_readU16leV1 fieldCount.toNat
      ⟨left ++ taggedHeaderBytesV1 tag fieldCount.toNat ++ payload ++ right,
        left.size + 4 + tag.toUTF8.size, nesting⟩
      fieldCount (left.size + 4 + tag.toUTF8.size + 2) hread
    simpa using h
  exact And.intro htag hfc

theorem decodeTerminator_return_none_of_encode_midV1
    (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeTerminatorV1 (.return_ none) = .ok b) :
    decodeTerminatorV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.return_ none, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeTerminator_return_none_ok_eq b henc
  subst b
  have hlayout := taggedBytes_one_field "Term.Return" (encodeU8 0)
  have hflatIn :
      left ++ (taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0) ++ right =
        left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0 ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflatIn]
  obtain ⟨htag, hfc⟩ :=
    decodeTag_fieldCount_midV1 "Term.Return" 1 (encodeU8 0) left right (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiTagBytes_Term_Return (by decide)
  have hopt :
      decodeOption decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0 ++ right,
            left.size + (taggedHeaderBytesV1 "Term.Return" 1).size, nesting + 1⟩ =
        .ok (none,
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0 ++ right,
            left.size + (taggedHeaderBytesV1 "Term.Return" 1).size + 1,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0 ++ right =
          (left ++ taggedHeaderBytesV1 "Term.Return" 1) ++ encodeU8 0 ++ right := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "Term.Return" 1).size =
          left.size + (taggedHeaderBytesV1 "Term.Return" 1).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hszL]
    exact decodeOption_none_encode_midV1 decodeU32le
      (left ++ taggedHeaderBytesV1 "Term.Return" 1) right (nesting + 1)
  have hshell :=
    decodeTerminatorV1_return
      ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0 ++ right,
        left.size, nesting⟩
      ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0 ++ right,
        left.size + 4 + "Term.Return".toUTF8.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0 ++ right,
        left.size + (taggedHeaderBytesV1 "Term.Return" 1).size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0 ++ right,
        left.size + (taggedHeaderBytesV1 "Term.Return" 1).size + 1, nesting + 1⟩
      none hdepth htag hfc hopt
  have hsz :
      left.size + (taggedHeaderBytesV1 "Term.Return" 1).size + 1 =
        left.size + (taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 0).size := by
    simp [ByteArray.size_append, encodeU8_size]; omega
  have h0 := hshell
  rw [h0, hsz]

theorem decodeTerminator_return_some_of_encode_midV1
    (id : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeTerminatorV1 (.return_ (some id)) = .ok b) :
    decodeTerminatorV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.return_ (some id), ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeTerminator_return_some_ok_eq id b henc
  subst b
  have hlayout :=
    taggedBytes_one_field "Term.Return" (encodeU8 1 ++ encodeU32le id)
  have hflatIn :
      left ++
          (taggedHeaderBytesV1 "Term.Return" 1 ++ (encodeU8 1 ++ encodeU32le id)) ++
          right =
        left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id ++
          right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflatIn]
  -- Work with left-associated payload blob so tag/field lemmas apply, then reassoc.
  obtain ⟨htag0, hfc0⟩ :=
    decodeTag_fieldCount_midV1 "Term.Return" 1 (encodeU8 1 ++ encodeU32le id)
      left right (nesting + 1) (by decide) (by decide) (by decide)
      isAsciiTagBytes_Term_Return (by decide)
  have hbuf :
      left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ (encodeU8 1 ++ encodeU32le id) ++
          right =
        left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id ++
          right := by
    simp [ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++
              encodeU32le id ++ right,
            left.size, nesting + 1⟩ =
        .ok ("Term.Return",
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++
              encodeU32le id ++ right,
            left.size + 4 + "Term.Return".toUTF8.size, nesting + 1⟩) := by
    simpa [hbuf] using htag0
  have hfc :
      decodeFieldCount 1
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++
              encodeU32le id ++ right,
            left.size + 4 + "Term.Return".toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++
              encodeU32le id ++ right,
            left.size + (taggedHeaderBytesV1 "Term.Return" 1).size, nesting + 1⟩) := by
    simpa [hbuf] using hfc0
  have hopt :
      decodeOption decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++
              encodeU32le id ++ right,
            left.size + (taggedHeaderBytesV1 "Term.Return" 1).size, nesting + 1⟩ =
        .ok (some id,
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++
              encodeU32le id ++ right,
            left.size + (taggedHeaderBytesV1 "Term.Return" 1).size + 1 + 4,
            nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++
            encodeU32le id ++ right =
          (left ++ taggedHeaderBytesV1 "Term.Return" 1) ++ encodeU8 1 ++
            encodeU32le id ++ right := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ taggedHeaderBytesV1 "Term.Return" 1).size =
          left.size + (taggedHeaderBytesV1 "Term.Return" 1).size := by
      simp [ByteArray.size_append]
    have hinv :
        decodeU32le
            ⟨(left ++ taggedHeaderBytesV1 "Term.Return" 1) ++ encodeU8 1 ++
                encodeU32le id ++ right,
              (left ++ taggedHeaderBytesV1 "Term.Return" 1).size + 1, nesting + 1⟩ =
          .ok (id,
            ⟨(left ++ taggedHeaderBytesV1 "Term.Return" 1) ++ encodeU8 1 ++
                encodeU32le id ++ right,
              (left ++ taggedHeaderBytesV1 "Term.Return" 1).size + 1 + 4,
              nesting + 1⟩) := by
      have hin2 :
          (left ++ taggedHeaderBytesV1 "Term.Return" 1) ++ encodeU8 1 ++
              encodeU32le id ++ right =
            (left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1) ++
              encodeU32le id ++ right := by
        simp [ByteArray.append_assoc]
      have hszL2 :
          (left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1).size =
            (left ++ taggedHeaderBytesV1 "Term.Return" 1).size + 1 := by
        simp [ByteArray.size_append, encodeU8_size]
      rw [hin2, ← hszL2]
      exact decodeU32le_encode_midV1
        (left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1) right id
        (nesting + 1)
    have hopt0 :=
      decodeOption_some_of_encode_midV1
        (fun x : UInt32 => pure (encodeU32le x)) decodeU32le id (encodeU32le id)
        (left ++ taggedHeaderBytesV1 "Term.Return" 1) right (nesting + 1)
        rfl hinv
    -- hopt0 offset uses (encodeU32le id).size; align to 4.
    have hidsz : (encodeU32le id).size = 4 := encodeU32le_sizeV1 id
    -- hopt0 buffer is left' ++ encodeU8 1 ++ encodeU32le id ++ right
    simpa [hin.symm, hszL, hidsz, ByteArray.append_assoc] using hopt0
  have hshell :=
    decodeTerminatorV1_return
      ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id ++
          right,
        left.size, nesting⟩
      ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id ++
          right,
        left.size + 4 + "Term.Return".toUTF8.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id ++
          right,
        left.size + (taggedHeaderBytesV1 "Term.Return" 1).size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id ++
          right,
        left.size + (taggedHeaderBytesV1 "Term.Return" 1).size + 1 + 4, nesting + 1⟩
      (some id) hdepth htag hfc hopt
  have hsz :
      left.size + (taggedHeaderBytesV1 "Term.Return" 1).size + 1 + 4 =
        left.size +
          (taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id).size := by
    simp [ByteArray.size_append, encodeU8_size, encodeU32le_sizeV1]; omega
  have hflat :
      decodeTerminatorV1
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++
              encodeU32le id ++ right,
            left.size, nesting⟩ =
        .ok (.return_ (some id),
          ⟨left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++
              encodeU32le id ++ right,
            left.size +
              (taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id).size,
            nesting⟩) := by
    have h0 := hshell
    -- Reduce cursor nesting field and align final offset.
    simpa [hsz] using h0
  -- Goal buffer is still associated as left ++ (header ++ payload) ++ right after subst.
  have hgoalBuf :
      left ++
          (taggedHeaderBytesV1 "Term.Return" 1 ++ (encodeU8 1 ++ encodeU32le id)) ++
          right =
        left ++ taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id ++
          right := by
    simp [ByteArray.append_assoc]
  have hgoalSz :
      (taggedHeaderBytesV1 "Term.Return" 1 ++ (encodeU8 1 ++ encodeU32le id)).size =
        (taggedHeaderBytesV1 "Term.Return" 1 ++ encodeU8 1 ++ encodeU32le id).size := by
    simp [ByteArray.size_append, ByteArray.append_assoc]
  simpa [hgoalBuf.symm, hgoalSz] using hflat

theorem midOffsetInvert_encodeTerminator_return
    (v : Option UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeTerminatorV1 (.return_ v) = .ok b) :
    decodeTerminatorV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.return_ v, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  match v with
  | none => exact decodeTerminator_return_none_of_encode_midV1 b left right nesting hdepth henc
  | some id =>
      exact decodeTerminator_return_some_of_encode_midV1 id b left right nesting hdepth henc

/-! ### Empty callables table + array lift from MidOffsetInvert -/

theorem midOffsetInvert_empty_callables_table :
    ∀ (b left right : ByteArray) (nesting : Nat),
      encodeArray encodeCallableV1 (#[] : Array CallableV1) = .ok b →
      decodeArray maxTableElements decodeCallableV1
          ⟨left ++ b ++ right, left.size, nesting⟩ =
        .ok (#[], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  fun b left right nesting h =>
    decodeArray_table_empty_of_encode_midV1 encodeCallableV1 decodeCallableV1
      b left right nesting h

/-- Parametric one-element array lift from element MidOffsetInvert + element encode. -/
theorem midOffsetInvert_array_one_of_element
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat)
    (hmax : 1 ≤ maxCount)
    (hElem : MidOffsetInvertV1 encode decode)
    (v0 : α) (b0 left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (h0 : encode v0 = .ok b0) :
    decodeArray maxCount decode
        ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size, nesting⟩ =
      .ok (#[v0],
        ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size + 4 + b0.size, nesting⟩) := by
  have henc : encodeArray encode #[v0] = .ok (encodeU32le 1 ++ b0) :=
    encodeArray_oneV1 encode v0 b0 h0
  have hinv :
      decode ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size + 4, nesting⟩ =
        .ok (v0, ⟨left ++ encodeU32le 1 ++ b0 ++ right,
          left.size + 4 + b0.size, nesting⟩) := by
    have hin :
        left ++ encodeU32le 1 ++ b0 ++ right =
          (left ++ encodeU32le 1) ++ b0 ++ right := by
      simp [ByteArray.append_assoc]
    have hszL : (left ++ encodeU32le 1).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have hmid := hElem v0 b0 (left ++ encodeU32le 1) right nesting hdepth h0
    simpa [hin.symm, hszL] using hmid
  have h :=
    decodeArray_of_encodeArray_one_ok_midV1 encode decode maxCount v0
      (encodeU32le 1 ++ b0) b0 left right nesting hmax h0 henc hinv
  -- Align association of buffer and final offset.
  have hflat :
      left ++ (encodeU32le 1 ++ b0) ++ right =
        left ++ encodeU32le 1 ++ b0 ++ right := by
    simp [ByteArray.append_assoc]
  have hsz1 : (encodeU32le (1 : UInt32)).size = 4 := encodeU32le_sizeV1 1
  simpa [hflat, hsz1, Nat.add_assoc, Nat.add_left_comm, Nat.add_comm] using h

/-- Parametric two-element array lift from element MidOffsetInvert + element encodes. -/
theorem midOffsetInvert_array_two_of_element
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat)
    (hmax : 2 ≤ maxCount)
    (hElem : MidOffsetInvertV1 encode decode)
    (v0 v1 : α) (b0 b1 left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (h0 : encode v0 = .ok b0) (h1 : encode v1 = .ok b1) :
    decodeArray maxCount decode
        ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right, left.size, nesting⟩ =
      .ok (#[v0, v1],
        ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right,
          left.size + 4 + b0.size + b1.size, nesting⟩) := by
  have henc : encodeArray encode #[v0, v1] = .ok (encodeU32le 2 ++ b0 ++ b1) := by
    have h2 := encodeArray_twoV1 encode v0 v1 b0 b1 h0 h1
    -- encodeArray_two yields encodeU32le 2 ++ (b0.append b1)
    have heq : (encodeU32le 2).append (b0.append b1) = encodeU32le 2 ++ b0 ++ b1 := by
      simp [ByteArray.append_assoc]
    rwa [heq] at h2
  have hinv0 :
      decode ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right, left.size + 4, nesting⟩ =
        .ok (v0, ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right,
          left.size + 4 + b0.size, nesting⟩) := by
    have hin :
        left ++ encodeU32le 2 ++ b0 ++ b1 ++ right =
          (left ++ encodeU32le 2) ++ b0 ++ (b1 ++ right) := by
      simp [ByteArray.append_assoc]
    have hszL : (left ++ encodeU32le 2).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have hmid := hElem v0 b0 (left ++ encodeU32le 2) (b1 ++ right) nesting hdepth h0
    simpa [hin.symm, hszL, ByteArray.append_assoc] using hmid
  have hinv1 :
      decode ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right,
          left.size + 4 + b0.size, nesting⟩ =
        .ok (v1, ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right,
          left.size + 4 + b0.size + b1.size, nesting⟩) := by
    have hin :
        left ++ encodeU32le 2 ++ b0 ++ b1 ++ right =
          (left ++ encodeU32le 2 ++ b0) ++ b1 ++ right := by
      simp [ByteArray.append_assoc]
    have hszL :
        (left ++ encodeU32le 2 ++ b0).size = left.size + 4 + b0.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    have hmid := hElem v1 b1 (left ++ encodeU32le 2 ++ b0) right nesting hdepth h1
    simpa [hin.symm, hszL] using hmid
  have h :=
    decodeArray_of_encodeArray_two_ok_midV1 encode decode maxCount v0 v1
      (encodeU32le 2 ++ b0 ++ b1) b0 b1 left right nesting hmax h0 h1 henc hinv0 hinv1
  have hflat :
      left ++ (encodeU32le 2 ++ b0 ++ b1) ++ right =
        left ++ encodeU32le 2 ++ b0 ++ b1 ++ right := by
    simp [ByteArray.append_assoc]
  have hsz2 : (encodeU32le (2 : UInt32)).size = 4 := encodeU32le_sizeV1 2
  simpa [hflat, hsz2, Nat.add_assoc, Nat.add_left_comm, Nat.add_comm,
    ByteArray.size_append] using h

/-- Convenience: ValueDef array one-element mid-offset invert. -/
theorem midOffsetInvert_array_one_valueDef
    (v0 : ValueDefV1) (b0 left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (h0 : encodeValueDefV1 v0 = .ok b0) :
    decodeArray maxArrayElements decodeValueDefV1
        ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size, nesting⟩ =
      .ok (#[v0],
        ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size + 4 + b0.size, nesting⟩) :=
  midOffsetInvert_array_one_of_element encodeValueDefV1 decodeValueDefV1
    maxArrayElements (by decide) midOffsetInvert_encodeValueDef_decodeValueDef
    v0 b0 left right nesting hdepth h0

/-- Convenience: LoopBound array two-element mid-offset invert. -/
theorem midOffsetInvert_array_two_loopBound
    (v0 v1 : LoopBoundV1) (b0 b1 left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (h0 : encodeLoopBoundV1 v0 = .ok b0) (h1 : encodeLoopBoundV1 v1 = .ok b1) :
    decodeArray maxArrayElements decodeLoopBoundV1
        ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right, left.size, nesting⟩ =
      .ok (#[v0, v1],
        ⟨left ++ encodeU32le 2 ++ b0 ++ b1 ++ right,
          left.size + 4 + b0.size + b1.size, nesting⟩) :=
  midOffsetInvert_array_two_of_element encodeLoopBoundV1 decodeLoopBoundV1
    maxArrayElements (by decide) midOffsetInvert_encodeLoopBound_decodeLoopBound
    v0 v1 b0 b1 left right nesting hdepth h0 h1

/-! ### Callable shape codec layer for PreservationShapeV1 constructors -/

open ProofForgeV2.Semantic.PreservationShapeV1

private theorem utf8_Binary_Add :
    "Binary.Add".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 65, 100, 100] := by rfl
private theorem isAsciiTagBytes_Binary_Add :
    isAsciiTagBytesV1 "Binary.Add".toUTF8 = true := by
  rw [utf8_Binary_Add]
  exact isAsciiTagBytes_of_list_all [66, 105, 110, 97, 114, 121, 46, 65, 100, 100] (by decide)

private theorem utf8_Binary_Mod :
    "Binary.Mod".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 77, 111, 100] := by rfl
private theorem isAsciiTagBytes_Binary_Mod :
    isAsciiTagBytesV1 "Binary.Mod".toUTF8 = true := by
  rw [utf8_Binary_Mod]
  exact isAsciiTagBytes_of_list_all [66, 105, 110, 97, 114, 121, 46, 77, 111, 100] (by decide)

private theorem utf8_Binary_Eq :
    "Binary.Eq".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 69, 113] := by rfl
private theorem isAsciiTagBytes_Binary_Eq :
    isAsciiTagBytesV1 "Binary.Eq".toUTF8 = true := by
  rw [utf8_Binary_Eq]
  exact isAsciiTagBytes_of_list_all [66, 105, 110, 97, 114, 121, 46, 69, 113] (by decide)

private theorem utf8_Op_StateStore :
    "Op.StateStore".toUTF8 =
      ByteArray.mk #[79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101] := by rfl
private theorem isAsciiTagBytes_Op_StateStore :
    isAsciiTagBytesV1 "Op.StateStore".toUTF8 = true := by
  rw [utf8_Op_StateStore]
  exact isAsciiTagBytes_of_list_all
    [79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101] (by decide)

private theorem utf8_Op_Binary :
    "Op.Binary".toUTF8 = ByteArray.mk #[79, 112, 46, 66, 105, 110, 97, 114, 121] := by rfl
private theorem isAsciiTagBytes_Op_Binary :
    isAsciiTagBytesV1 "Op.Binary".toUTF8 = true := by
  rw [utf8_Op_Binary]
  exact isAsciiTagBytes_of_list_all [79, 112, 46, 66, 105, 110, 97, 114, 121] (by decide)

private theorem utf8_Instruction :
    "Instruction".toUTF8 = ByteArray.mk #[73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] := by rfl
private theorem isAsciiTagBytes_Instruction :
    isAsciiTagBytesV1 "Instruction".toUTF8 = true := by
  rw [utf8_Instruction]
  exact isAsciiTagBytes_of_list_all [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by decide)

private theorem utf8_CallableResult :
    "CallableResult".toUTF8 =
      ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] := by rfl
private theorem isAsciiTagBytes_CallableResult :
    isAsciiTagBytesV1 "CallableResult".toUTF8 = true := by
  rw [utf8_CallableResult]
  exact isAsciiTagBytes_of_list_all
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by decide)

private theorem utf8_Block :
    "Block".toUTF8 = ByteArray.mk #[66, 108, 111, 99, 107] := by rfl
private theorem isAsciiTagBytes_Block :
    isAsciiTagBytesV1 "Block".toUTF8 = true := by
  rw [utf8_Block]
  exact isAsciiTagBytes_of_list_all [66, 108, 111, 99, 107] (by decide)

private theorem utf8_Callable :
    "Callable".toUTF8 = ByteArray.mk #[67, 97, 108, 108, 97, 98, 108, 101] := by rfl
private theorem isAsciiTagBytes_Callable :
    isAsciiTagBytesV1 "Callable".toUTF8 = true := by
  rw [utf8_Callable]
  exact isAsciiTagBytes_of_list_all [67, 97, 108, 108, 97, 98, 108, 101] (by decide)

private theorem taggedBytes_five_fields (tag : String) (f0 f1 f2 f3 f4 : ByteArray) :
    taggedBytesV1 tag #[f0, f1, f2, f3, f4] =
      taggedHeaderBytesV1 tag 5 ++ f0 ++ f1 ++ f2 ++ f3 ++ f4 := by
  have h := taggedBytesV1_eq_header_payload tag #[f0, f1, f2, f3, f4]
  have hfold :
      (#[f0, f1, f2, f3, f4] : Array ByteArray).foldl (fun out f => out.append f) ByteArray.empty =
        f0 ++ f1 ++ f2 ++ f3 ++ f4 := by
    simp [List.foldl]
  have hsz : (#[f0, f1, f2, f3, f4] : Array ByteArray).size = 5 := rfl
  rw [h, hfold, hsz]
  simp [ByteArray.append_assoc]

private theorem taggedBytes_nine_fields (tag : String)
    (f0 f1 f2 f3 f4 f5 f6 f7 f8 : ByteArray) :
    taggedBytesV1 tag #[f0, f1, f2, f3, f4, f5, f6, f7, f8] =
      taggedHeaderBytesV1 tag 9 ++ f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
  have h := taggedBytesV1_eq_header_payload tag #[f0, f1, f2, f3, f4, f5, f6, f7, f8]
  have hfold :
      (#[f0, f1, f2, f3, f4, f5, f6, f7, f8] : Array ByteArray).foldl (fun out f => out.append f) ByteArray.empty =
        f0 ++ f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6 ++ f7 ++ f8 := by
    simp [List.foldl]
  have hsz : (#[f0, f1, f2, f3, f4, f5, f6, f7, f8] : Array ByteArray).size = 9 := rfl
  rw [h, hfold, hsz]
  simp [ByteArray.append_assoc]

theorem encodeBinaryOp_add_eq :
    encodeBinaryOpV1 .add = .ok (taggedHeaderBytesV1 "Binary.Add" 0) := by
  change encodeNullary "Binary.Add" = .ok (taggedHeaderBytesV1 "Binary.Add" 0)
  have h := encodeNullary_eq_okV1 "Binary.Add" (by decide) (by decide) (by decide)
  simpa [taggedHeaderBytesV1, ByteArray.append_assoc] using h

theorem encodeBinaryOp_mod_eq :
    encodeBinaryOpV1 .mod = .ok (taggedHeaderBytesV1 "Binary.Mod" 0) := by
  change encodeNullary "Binary.Mod" = .ok (taggedHeaderBytesV1 "Binary.Mod" 0)
  have h := encodeNullary_eq_okV1 "Binary.Mod" (by decide) (by decide) (by decide)
  simpa [taggedHeaderBytesV1, ByteArray.append_assoc] using h

theorem encodeBinaryOp_eq_eq :
    encodeBinaryOpV1 .eq = .ok (taggedHeaderBytesV1 "Binary.Eq" 0) := by
  change encodeNullary "Binary.Eq" = .ok (taggedHeaderBytesV1 "Binary.Eq" 0)
  have h := encodeNullary_eq_okV1 "Binary.Eq" (by decide) (by decide) (by decide)
  simpa [taggedHeaderBytesV1, ByteArray.append_assoc] using h

private theorem decodeBinaryOp_nullary_midV1
    (tag : String) (op : BinaryOpV1) (left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (hnonempty : 1 ≤ tag.toUTF8.size) (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true)
    (hbody : ∀ (c afterTag afterFields : Cursor),
      decodeTag c = .ok (tag, afterTag) →
      decodeFieldCount 0 afterTag = .ok ((), afterFields) →
      decodeBinaryOpBodyV1 c = .ok (op, afterFields)) :
    decodeBinaryOpV1 ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right, left.size, nesting⟩ =
      .ok (op, ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
        left.size + (taggedHeaderBytesV1 tag 0).size, nesting⟩) := by
  obtain ⟨htag, hfc⟩ :=
    decodeNullaryTagged_midV1 tag left right (nesting + 1) hnonempty hmax hfit
      hasciiBytes hasciiTag
  refine decodeBinaryOpV1_eq_of_bodyV1
    ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right, left.size, nesting⟩ op
    ⟨left ++ taggedHeaderBytesV1 tag 0 ++ right,
      left.size + (taggedHeaderBytesV1 tag 0).size, nesting + 1⟩ hdepth ?_
  exact hbody _ _ _ htag hfc

theorem decodeBinaryOp_add_of_encode_midV1
    (b left right : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeBinaryOpV1 .add = .ok b) :
    decodeBinaryOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.add, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb : b = taggedHeaderBytesV1 "Binary.Add" 0 :=
    Except.ok.inj (henc.symm.trans encodeBinaryOp_add_eq)
  subst b
  exact decodeBinaryOp_nullary_midV1 "Binary.Add" .add left right nesting hdepth
    (by decide) (by decide) (by decide) isAsciiTagBytes_Binary_Add (by decide)
    (fun c afterTag afterFields htag hfields => by
      simp only [decodeBinaryOpBodyV1, htag, hfields, Bind.bind, Pure.pure, Except.bind,
        Except.pure])

theorem decodeBinaryOp_mod_of_encode_midV1
    (b left right : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeBinaryOpV1 .mod = .ok b) :
    decodeBinaryOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.mod, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb : b = taggedHeaderBytesV1 "Binary.Mod" 0 :=
    Except.ok.inj (henc.symm.trans encodeBinaryOp_mod_eq)
  subst b
  exact decodeBinaryOp_nullary_midV1 "Binary.Mod" .mod left right nesting hdepth
    (by decide) (by decide) (by decide) isAsciiTagBytes_Binary_Mod (by decide)
    (fun c afterTag afterFields htag hfields => by
      simp only [decodeBinaryOpBodyV1, htag, hfields, Bind.bind, Pure.pure, Except.bind,
        Except.pure])

theorem decodeBinaryOp_eq_of_encode_midV1
    (b left right : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeBinaryOpV1 .eq = .ok b) :
    decodeBinaryOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.eq, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb : b = taggedHeaderBytesV1 "Binary.Eq" 0 :=
    Except.ok.inj (henc.symm.trans encodeBinaryOp_eq_eq)
  subst b
  exact decodeBinaryOp_nullary_midV1 "Binary.Eq" .eq left right nesting hdepth
    (by decide) (by decide) (by decide) isAsciiTagBytes_Binary_Eq (by decide)
    (fun c afterTag afterFields htag hfields => by
      simp only [decodeBinaryOpBodyV1, htag, hfields, Bind.bind, Pure.pure, Except.bind,
        Except.pure])

private theorem exactBinaryOp_add : ExactMidOffsetInvertV1 encodeBinaryOpV1 decodeBinaryOpV1 .add :=
  fun b left right nesting hdepth henc => decodeBinaryOp_add_of_encode_midV1 b left right nesting hdepth henc
private theorem exactBinaryOp_mod : ExactMidOffsetInvertV1 encodeBinaryOpV1 decodeBinaryOpV1 .mod :=
  fun b left right nesting hdepth henc => decodeBinaryOp_mod_of_encode_midV1 b left right nesting hdepth henc
private theorem exactBinaryOp_eq : ExactMidOffsetInvertV1 encodeBinaryOpV1 decodeBinaryOpV1 .eq :=
  fun b left right nesting hdepth henc => decodeBinaryOp_eq_of_encode_midV1 b left right nesting hdepth henc

theorem encodeSemanticOp_stateStore_ok_eq (stateId value : UInt32) (b : ByteArray)
    (h : encodeSemanticOpV1 (.stateStore stateId value) = .ok b) :
    b = taggedBytesV1 "Op.StateStore" #[encodeU32le stateId, encodeU32le value] := by
  simp only [encodeSemanticOpV1] at h
  exact (encodeTagged_ok_eq_taggedBytesV1 "Op.StateStore"
    #[encodeU32le stateId, encodeU32le value] b h).1

theorem decodeSemanticOp_stateStore_of_encode_midV1
    (stateId value : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.stateStore stateId value) = .ok b) :
    decodeSemanticOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.stateStore stateId value, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeSemanticOp_stateStore_ok_eq stateId value b henc
  subst b
  have hlayout := taggedBytes_two_fields "Op.StateStore" (encodeU32le stateId) (encodeU32le value)
  have hflat :
      left ++ (taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value) ++ right =
        left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflat]
  obtain ⟨htag, hfc⟩ :=
    decodeTag_fieldCount_midV1 "Op.StateStore" 2 (encodeU32le stateId ++ encodeU32le value)
      left right (nesting + 1) (by decide) (by decide) (by decide)
      isAsciiTagBytes_Op_StateStore (by decide)
  have hbuf :
      left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ (encodeU32le stateId ++ encodeU32le value) ++ right =
        left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right := by
    simp [ByteArray.append_assoc]
  have htag' :
      decodeTag ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
          left.size, nesting + 1⟩ =
        .ok ("Op.StateStore",
          ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
            left.size + 4 + "Op.StateStore".toUTF8.size, nesting + 1⟩) := by
    simpa [hbuf] using htag
  have hfc' :
      decodeFieldCount 2
          ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
            left.size + 4 + "Op.StateStore".toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
            left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size, nesting + 1⟩) := by
    simpa [hbuf] using hfc
  have hstate :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
            left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size, nesting + 1⟩ =
        .ok (stateId,
          ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
            left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size + 4, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right =
          (left ++ taggedHeaderBytesV1 "Op.StateStore" 2) ++ encodeU32le stateId ++ (encodeU32le value ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Op.StateStore" 2).size =
        left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "Op.StateStore" 2)
      (encodeU32le value ++ right) stateId (nesting + 1)
  have hvalue :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
            left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size + 4, nesting + 1⟩ =
        .ok (value,
          ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
            left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size + 4 + 4, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right =
          (left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId) ++ encodeU32le value ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId).size =
        left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1
      (left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId) right value (nesting + 1)
  have hshell := decodeSemanticOpV1_eq_of_bodyV1
    ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
      left.size, nesting⟩ (.stateStore stateId value)
    ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
      left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size + 4 + 4, nesting + 1⟩ hdepth
    (decodeSemanticOpBodyV1_stateStore
      ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
        left.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
        left.size + 4 + "Op.StateStore".toUTF8.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
        left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
        left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size + 4, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value ++ right,
        left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size + 4 + 4, nesting + 1⟩
      stateId value htag' hfc' hstate hvalue)
  have hsz :
      left.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size + 4 + 4 =
        left.size + (taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  simpa [hsz] using hshell

theorem encodeSemanticOp_binary_ok_eq (op : BinaryOpV1) (lhs rhs : UInt32) (b : ByteArray)
    (h : encodeSemanticOpV1 (.binary op lhs rhs) = .ok b) :
    ∃ opB,
      encodeBinaryOpV1 op = .ok opB ∧
        b = taggedBytesV1 "Op.Binary" #[opB, encodeU32le lhs, encodeU32le rhs] := by
  simp only [encodeSemanticOpV1] at h
  cases hop : encodeBinaryOpV1 op with
  | error e =>
      simp only [hop, Bind.bind, Except.bind] at h
      cases h
  | ok opB =>
      simp only [hop, Bind.bind, Except.bind] at h
      exact ⟨opB, rfl,
        (encodeTagged_ok_eq_taggedBytesV1 "Op.Binary"
          #[opB, encodeU32le lhs, encodeU32le rhs] b h).1⟩

theorem decodeSemanticOp_binary_of_encode_midV1
    (op : BinaryOpV1) (lhs rhs : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthOp : nesting + 1 < maxNesting)
    (hopExact : ExactMidOffsetInvertV1 encodeBinaryOpV1 decodeBinaryOpV1 op)
    (henc : encodeSemanticOpV1 (.binary op lhs rhs) = .ok b) :
    decodeSemanticOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.binary op lhs rhs, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨opB, hopEnc, hb⟩ := encodeSemanticOp_binary_ok_eq op lhs rhs b henc
  subst b
  have hlayout := taggedBytes_three_fields "Op.Binary" opB (encodeU32le lhs) (encodeU32le rhs)
  have hflat :
      left ++ (taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs) ++ right =
        left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflat]
  obtain ⟨htag0, hfc0⟩ :=
    decodeTag_fieldCount_midV1 "Op.Binary" 3 (opB ++ encodeU32le lhs ++ encodeU32le rhs)
      left right (nesting + 1) (by decide) (by decide) (by decide)
      isAsciiTagBytes_Op_Binary (by decide)
  have hbuf :
      left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ (opB ++ encodeU32le lhs ++ encodeU32le rhs) ++ right =
        left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right := by
    simp [ByteArray.append_assoc]
  have htag :
      decodeTag ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
          left.size, nesting + 1⟩ =
        .ok ("Op.Binary",
          ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
            left.size + 4 + "Op.Binary".toUTF8.size, nesting + 1⟩) := by
    simpa [hbuf] using htag0
  have hfc :
      decodeFieldCount 3
          ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
            left.size + 4 + "Op.Binary".toUTF8.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
            left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size, nesting + 1⟩) := by
    simpa [hbuf] using hfc0
  have hopDec :
      decodeBinaryOpV1
          ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
            left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size, nesting + 1⟩ =
        .ok (op,
          ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
            left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right =
          (left ++ taggedHeaderBytesV1 "Op.Binary" 3) ++ opB ++ (encodeU32le lhs ++ encodeU32le rhs ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Op.Binary" 3).size =
        left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size := by
      simp [ByteArray.size_append]
    have hmid := hopExact opB (left ++ taggedHeaderBytesV1 "Op.Binary" 3)
      (encodeU32le lhs ++ encodeU32le rhs ++ right) (nesting + 1) hdepthOp hopEnc
    simpa [hin.symm, hsz, ByteArray.append_assoc] using hmid
  have hlhs :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
            left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size, nesting + 1⟩ =
        .ok (lhs,
          ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
            left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size + 4, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right =
          (left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB) ++ encodeU32le lhs ++ (encodeU32le rhs ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB).size =
        left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size := by
      simp [ByteArray.size_append]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB)
      (encodeU32le rhs ++ right) lhs (nesting + 1)
  have hrhs :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
            left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size + 4, nesting + 1⟩ =
        .ok (rhs,
          ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
            left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size + 4 + 4, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right =
          (left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs) ++ encodeU32le rhs ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs).size =
        left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1
      (left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs) right rhs (nesting + 1)
  have hshell := decodeSemanticOpV1_eq_of_bodyV1
    ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
      left.size, nesting⟩ (.binary op lhs rhs)
    ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
      left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size + 4 + 4, nesting + 1⟩ hdepth
    (decodeSemanticOpBodyV1_binary
      ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
        left.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
        left.size + 4 + "Op.Binary".toUTF8.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
        left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
        left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
        left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size + 4, nesting + 1⟩
      ⟨left ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs ++ right,
        left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size + 4 + 4, nesting + 1⟩
      op lhs rhs htag hfc hopDec hlhs hrhs)
  have hsz :
      left.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size + 4 + 4 =
        left.size + (taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++ encodeU32le rhs).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  simpa [hsz] using hshell

theorem decodeSemanticOp_binary_add_of_encode_midV1
    (lhs rhs : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthOp : nesting + 1 < maxNesting)
    (henc : encodeSemanticOpV1 (.binary .add lhs rhs) = .ok b) :
    decodeSemanticOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.binary .add lhs rhs, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  decodeSemanticOp_binary_of_encode_midV1 .add lhs rhs b left right nesting hdepth hdepthOp exactBinaryOp_add henc

theorem decodeSemanticOp_binary_mod_of_encode_midV1
    (lhs rhs : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthOp : nesting + 1 < maxNesting)
    (henc : encodeSemanticOpV1 (.binary .mod lhs rhs) = .ok b) :
    decodeSemanticOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.binary .mod lhs rhs, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  decodeSemanticOp_binary_of_encode_midV1 .mod lhs rhs b left right nesting hdepth hdepthOp exactBinaryOp_mod henc

theorem decodeSemanticOp_binary_eq_of_encode_midV1
    (lhs rhs : UInt32) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthOp : nesting + 1 < maxNesting)
    (henc : encodeSemanticOpV1 (.binary .eq lhs rhs) = .ok b) :
    decodeSemanticOpV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (.binary .eq lhs rhs, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  decodeSemanticOp_binary_of_encode_midV1 .eq lhs rhs b left right nesting hdepth hdepthOp exactBinaryOp_eq henc

theorem decodeOptionValueDef_none_of_encode_midV1
    (b left right : ByteArray) (nesting : Nat)
    (henc : encodeOption encodeValueDefV1 (none : Option ValueDefV1) = .ok b) :
    decodeOption decodeValueDefV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (none, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  simp only [encodeOption, Pure.pure, Except.pure] at henc
  have hb : b = encodeU8 0 := Except.ok.inj henc.symm
  subst b
  exact decodeOption_none_encode_midV1 decodeValueDefV1 left right nesting

theorem decodeOptionValueDef_some_of_encode_midV1
    (v : ValueDefV1) (b left right : ByteArray) (nesting : Nat)
    (hdepthValue : nesting < maxNesting)
    (henc : encodeOption encodeValueDefV1 (some v) = .ok b) :
    decodeOption decodeValueDefV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (some v, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  simp only [encodeOption, Bind.bind, Except.bind] at henc
  cases hv : encodeValueDefV1 v with
  | error e => simp only [hv, Bind.bind, Except.bind] at henc; cases henc
  | ok payload =>
      simp only [hv, Bind.bind, Except.bind, Pure.pure, Except.pure] at henc
      have hb : b = encodeU8 1 ++ payload := Except.ok.inj henc.symm
      subst b
      have hinv :
          decodeValueDefV1 ⟨left ++ encodeU8 1 ++ payload ++ right, left.size + 1, nesting⟩ =
            .ok (v, ⟨left ++ encodeU8 1 ++ payload ++ right,
              left.size + 1 + payload.size, nesting⟩) := by
        have hmid := decodeValueDef_of_encode_midV1 v payload (left ++ encodeU8 1) right
          nesting hdepthValue hv
        have hin : (left ++ encodeU8 1) ++ payload ++ right =
            left ++ encodeU8 1 ++ payload ++ right := by simp [ByteArray.append_assoc]
        have hsz : (left ++ encodeU8 1).size = left.size + 1 := by
          simp [ByteArray.size_append, encodeU8_size]
        simpa [hin, hsz] using hmid
      have hopt := decodeOption_some_of_encode_midV1 encodeValueDefV1 decodeValueDefV1
        v payload left right nesting hv hinv
      have hszPayload : (encodeU8 1 ++ payload).size = 1 + payload.size := by
        simp [ByteArray.size_append, encodeU8_size]
      simpa [hszPayload, ByteArray.append_assoc, Nat.add_assoc, Nat.add_left_comm,
        Nat.add_comm] using hopt

theorem decodeOptionValueDef_of_encode_midV1
    (result : Option ValueDefV1) (b left right : ByteArray) (nesting : Nat)
    (hdepthValue : nesting < maxNesting)
    (henc : encodeOption encodeValueDefV1 result = .ok b) :
    decodeOption decodeValueDefV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (result, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  cases result with
  | none => exact decodeOptionValueDef_none_of_encode_midV1 b left right nesting henc
  | some v => exact decodeOptionValueDef_some_of_encode_midV1 v b left right nesting hdepthValue henc

theorem encodeInstruction_ok_eqV1 (i : InstructionV1) (b : ByteArray)
    (h : encodeInstructionV1 i = .ok b) :
    ∃ resultB opB,
      encodeOption encodeValueDefV1 i.result = .ok resultB ∧
      encodeSemanticOpV1 i.op = .ok opB ∧
      b = taggedBytesV1 "Instruction" #[resultB, opB] := by
  simp only [encodeInstructionV1] at h
  cases hresult : encodeOption encodeValueDefV1 i.result with
  | error e => simp only [hresult, Bind.bind, Except.bind] at h; cases h
  | ok resultB =>
      cases hop : encodeSemanticOpV1 i.op with
      | error e => simp only [hresult, hop, Bind.bind, Except.bind] at h; cases h
      | ok opB =>
          simp only [hresult, hop, Bind.bind, Except.bind] at h
          exact ⟨resultB, opB, rfl, rfl,
            (encodeTagged_ok_eq_taggedBytesV1 "Instruction" #[resultB, opB] b h).1⟩

theorem decodeInstruction_of_encode_fields_midV1
    (i : InstructionV1) (resultB opB b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (hresultEnc : encodeOption encodeValueDefV1 i.result = .ok resultB)
    (hopEnc : encodeSemanticOpV1 i.op = .ok opB)
    (henc : encodeInstructionV1 i = .ok b)
    (hresultDec :
      decodeOption decodeValueDefV1
        ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
          left.size + (taggedHeaderBytesV1 "Instruction" 2).size, nesting + 1⟩ =
        .ok (i.result,
          ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
            left.size + (taggedHeaderBytesV1 "Instruction" 2).size + resultB.size,
            nesting + 1⟩))
    (hopDec :
      decodeSemanticOpV1
        ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
          left.size + (taggedHeaderBytesV1 "Instruction" 2).size + resultB.size,
          nesting + 1⟩ =
        .ok (i.op,
          ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
            left.size + (taggedHeaderBytesV1 "Instruction" 2).size + resultB.size + opB.size,
            nesting + 1⟩)) :
    decodeInstructionV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (i, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb : b = taggedBytesV1 "Instruction" #[resultB, opB] := by
    simp only [encodeInstructionV1, hresultEnc, hopEnc, Bind.bind, Except.bind] at henc
    exact (encodeTagged_ok_eq_taggedBytesV1 "Instruction" #[resultB, opB] b henc).1
  subst b
  have hlayout := taggedBytes_two_fields "Instruction" resultB opB
  have hflat :
      left ++ (taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB) ++ right =
        left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflat]
  have hexpect :
      expectTag "Instruction" 2
          ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
            left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
            left.size + (taggedHeaderBytesV1 "Instruction" 2).size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right =
          left ++ taggedHeaderBytesV1 "Instruction" 2 ++ (resultB ++ opB) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "Instruction" 2 (resultB ++ opB) (nesting + 1)
      (by decide) (by decide) (by decide) isAsciiTagBytes_Instruction (by decide)
  have hshell := decodeInstructionV1_eq_of_fieldsV1
    ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
      left.size, nesting⟩
    ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
      left.size + (taggedHeaderBytesV1 "Instruction" 2).size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
      left.size + (taggedHeaderBytesV1 "Instruction" 2).size + resultB.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right,
      left.size + (taggedHeaderBytesV1 "Instruction" 2).size + resultB.size + opB.size,
      nesting + 1⟩
    i.result i.op hdepth hexpect hresultDec hopDec
  have hη : ({ result := i.result, op := i.op } : InstructionV1) = i := by
    cases i; rfl
  have hsz :
      left.size + (taggedHeaderBytesV1 "Instruction" 2).size + resultB.size + opB.size =
        left.size + (taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB).size := by
    simp [ByteArray.size_append]; omega
  rw [hη] at hshell
  simpa [hsz] using hshell

theorem decodeInstruction_of_encode_exact_midV1
    (i : InstructionV1) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthInner : nesting + 1 < maxNesting)
    (hresultExact : ExactMidOffsetInvertV1 (encodeOption encodeValueDefV1)
      (decodeOption decodeValueDefV1) i.result)
    (hopExact : ExactMidOffsetInvertV1 encodeSemanticOpV1 decodeSemanticOpV1 i.op)
    (henc : encodeInstructionV1 i = .ok b) :
    decodeInstructionV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (i, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨resultB, opB, hresultEnc, hopEnc, _hb⟩ := encodeInstruction_ok_eqV1 i b henc
  refine decodeInstruction_of_encode_fields_midV1 i resultB opB b left right nesting hdepth
    hresultEnc hopEnc henc ?_ ?_
  · have hmid := hresultExact resultB (left ++ taggedHeaderBytesV1 "Instruction" 2)
      (opB ++ right) (nesting + 1) hdepthInner hresultEnc
    have hin :
        (left ++ taggedHeaderBytesV1 "Instruction" 2) ++ resultB ++ (opB ++ right) =
          left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Instruction" 2).size =
        left.size + (taggedHeaderBytesV1 "Instruction" 2).size := by
      simp [ByteArray.size_append]
    simpa [hin, hsz, ByteArray.append_assoc] using hmid
  · have hmid := hopExact opB (left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB)
      right (nesting + 1) hdepthInner hopEnc
    have hin :
        (left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB) ++ opB ++ right =
          left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB ++ opB ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB).size =
        left.size + (taggedHeaderBytesV1 "Instruction" 2).size + resultB.size := by
      simp [ByteArray.size_append]
    simpa [hin, hsz] using hmid

theorem encodeArray_ok_five_eqV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (v0 v1 v2 v3 v4 : α) (b b0 b1 b2 b3 b4 : ByteArray)
    (h0 : encode v0 = .ok b0) (h1 : encode v1 = .ok b1)
    (h2 : encode v2 = .ok b2) (h3 : encode v3 = .ok b3)
    (h4 : encode v4 = .ok b4)
    (h : encodeArray encode #[v0, v1, v2, v3, v4] = .ok b) :
    b = encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 := by
  have h5 := encodeArray_fiveV1 encode v0 v1 v2 v3 v4 b0 b1 b2 b3 b4
    h0 h1 h2 h3 h4
  have hb := Except.ok.inj (h.symm.trans h5)
  simpa [ByteArray.append_assoc] using hb

theorem decodeArray_of_encodeArray_five_ok_midV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat)
    (v0 v1 v2 v3 v4 : α) (b b0 b1 b2 b3 b4 left right : ByteArray) (nesting : Nat)
    (hmax : 5 ≤ maxCount)
    (h0 : encode v0 = .ok b0) (h1 : encode v1 = .ok b1)
    (h2 : encode v2 = .ok b2) (h3 : encode v3 = .ok b3)
    (h4 : encode v4 = .ok b4)
    (henc : encodeArray encode #[v0, v1, v2, v3, v4] = .ok b)
    (hinv0 :
      decode ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4, nesting⟩ =
        .ok (v0, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size, nesting⟩))
    (hinv1 :
      decode ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4 + b0.size, nesting⟩ =
        .ok (v1, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size + b1.size, nesting⟩))
    (hinv2 :
      decode ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4 + b0.size + b1.size, nesting⟩ =
        .ok (v2, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size + b1.size + b2.size, nesting⟩))
    (hinv3 :
      decode ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4 + b0.size + b1.size + b2.size, nesting⟩ =
        .ok (v3, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size + b1.size + b2.size + b3.size, nesting⟩))
    (hinv4 :
      decode ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4 + b0.size + b1.size + b2.size + b3.size, nesting⟩ =
        .ok (v4, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size + b1.size + b2.size + b3.size + b4.size, nesting⟩)) :
    decodeArray maxCount decode ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (#[v0, v1, v2, v3, v4], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb := encodeArray_ok_five_eqV1 encode v0 v1 v2 v3 v4 b b0 b1 b2 b3 b4
    h0 h1 h2 h3 h4 henc
  subst b
  have hcount :
      readArrayCountAtV1
          (left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right) left.size maxCount =
        .ok (5, left.size + 4) := by
    have hassoc :
        left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right =
          left ++ encodeU32le 5 ++ (b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right) := by
      simp [ByteArray.append_assoc]
    rw [hassoc]
    exact readArrayCount_encode_midV1 left (b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right)
      5 maxCount (by decide) hmax
  have helems :
      decodeArrayElementsV1 decode 5 #[]
        ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4, nesting⟩ =
        .ok (#[v0, v1, v2, v3, v4],
          ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
            left.size + 4 + b0.size + b1.size + b2.size + b3.size + b4.size, nesting⟩) := by
    simp [decodeArrayElementsV1, hinv0, hinv1, hinv2, hinv3, hinv4]
  have hdec := decodeArray_eq_of_elementsV1 maxCount decode
    ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
      left.size, nesting⟩ 5 (left.size + 4) #[v0, v1, v2, v3, v4]
    ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
      left.size + 4 + b0.size + b1.size + b2.size + b3.size + b4.size, nesting⟩
    hcount helems
  have hsz :
      left.size + 4 + b0.size + b1.size + b2.size + b3.size + b4.size =
        left.size + (encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  simpa [hsz, ByteArray.append_assoc] using hdec

theorem decodeInstructionArray_one_of_encode_midV1
    (i0 : InstructionV1) (b b0 left right : ByteArray) (nesting : Nat)
    (h0 : encodeInstructionV1 i0 = .ok b0)
    (henc : encodeArray encodeInstructionV1 #[i0] = .ok b)
    (hinv0 :
      decodeInstructionV1 ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size + 4, nesting⟩ =
        .ok (i0, ⟨left ++ encodeU32le 1 ++ b0 ++ right, left.size + 4 + b0.size, nesting⟩)) :
    decodeArray maxArrayElements decodeInstructionV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (#[i0], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  decodeArray_of_encodeArray_one_ok_midV1 encodeInstructionV1 decodeInstructionV1
    maxArrayElements i0 b b0 left right nesting (by decide) h0 henc hinv0

theorem decodeInstructionArray_five_of_encode_midV1
    (i0 i1 i2 i3 i4 : InstructionV1) (b b0 b1 b2 b3 b4 left right : ByteArray)
    (nesting : Nat)
    (h0 : encodeInstructionV1 i0 = .ok b0) (h1 : encodeInstructionV1 i1 = .ok b1)
    (h2 : encodeInstructionV1 i2 = .ok b2) (h3 : encodeInstructionV1 i3 = .ok b3)
    (h4 : encodeInstructionV1 i4 = .ok b4)
    (henc : encodeArray encodeInstructionV1 #[i0, i1, i2, i3, i4] = .ok b)
    (hinv0 : decodeInstructionV1 ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4, nesting⟩ =
        .ok (i0, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size, nesting⟩))
    (hinv1 : decodeInstructionV1 ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4 + b0.size, nesting⟩ =
        .ok (i1, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size + b1.size, nesting⟩))
    (hinv2 : decodeInstructionV1 ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4 + b0.size + b1.size, nesting⟩ =
        .ok (i2, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size + b1.size + b2.size, nesting⟩))
    (hinv3 : decodeInstructionV1 ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4 + b0.size + b1.size + b2.size, nesting⟩ =
        .ok (i3, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size + b1.size + b2.size + b3.size, nesting⟩))
    (hinv4 : decodeInstructionV1 ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
        left.size + 4 + b0.size + b1.size + b2.size + b3.size, nesting⟩ =
        .ok (i4, ⟨left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3 ++ b4 ++ right,
          left.size + 4 + b0.size + b1.size + b2.size + b3.size + b4.size, nesting⟩)) :
    decodeArray maxArrayElements decodeInstructionV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (#[i0, i1, i2, i3, i4], ⟨left ++ b ++ right, left.size + b.size, nesting⟩) :=
  decodeArray_of_encodeArray_five_ok_midV1 encodeInstructionV1 decodeInstructionV1
    maxArrayElements i0 i1 i2 i3 i4 b b0 b1 b2 b3 b4 left right nesting (by decide)
    h0 h1 h2 h3 h4 henc hinv0 hinv1 hinv2 hinv3 hinv4

/-! ### CallableResult exact inversion -/

theorem encodeCallableResult_ok_eqV1 (r : CallableResultV1) (b : ByteArray)
    (h : encodeCallableResultV1 r = .ok b) :
    ∃ visB,
      encodeVisibilityV1 r.visibility = .ok visB ∧
        b = taggedBytesV1 "CallableResult" #[encodeU32le r.typeId, visB] := by
  simp only [encodeCallableResultV1] at h
  cases hv : encodeVisibilityV1 r.visibility with
  | error e => simp only [hv, Bind.bind, Except.bind] at h; cases h
  | ok visB =>
      simp only [hv, Bind.bind, Except.bind] at h
      exact ⟨visB, rfl,
        (encodeTagged_ok_eq_taggedBytesV1 "CallableResult" #[encodeU32le r.typeId, visB] b h).1⟩

theorem decodeCallableResult_of_encode_midV1
    (r : CallableResultV1) (b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthVis : nesting + 1 < maxNesting)
    (henc : encodeCallableResultV1 r = .ok b) :
    decodeCallableResultV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (r, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨visB, hvisEnc, hb⟩ := encodeCallableResult_ok_eqV1 r b henc
  subst b
  have hlayout := taggedBytes_two_fields "CallableResult" (encodeU32le r.typeId) visB
  have hflat :
      left ++ (taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB) ++ right =
        left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflat]
  have hexpect :
      expectTag "CallableResult" 2
          ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right,
            left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right,
            left.size + (taggedHeaderBytesV1 "CallableResult" 2).size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right =
          left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ (encodeU32le r.typeId ++ visB) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "CallableResult" 2 (encodeU32le r.typeId ++ visB)
      (nesting + 1) (by decide) (by decide) (by decide) isAsciiTagBytes_CallableResult (by decide)
  have htype :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right,
            left.size + (taggedHeaderBytesV1 "CallableResult" 2).size, nesting + 1⟩ =
        .ok (r.typeId,
          ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right,
            left.size + (taggedHeaderBytesV1 "CallableResult" 2).size + 4, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right =
          (left ++ taggedHeaderBytesV1 "CallableResult" 2) ++ encodeU32le r.typeId ++ (visB ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "CallableResult" 2).size =
        left.size + (taggedHeaderBytesV1 "CallableResult" 2).size := by
      simp [ByteArray.size_append]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "CallableResult" 2)
      (visB ++ right) r.typeId (nesting + 1)
  have hvis :
      decodeVisibilityV1
          ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right,
            left.size + (taggedHeaderBytesV1 "CallableResult" 2).size + 4, nesting + 1⟩ =
        .ok (r.visibility,
          ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right,
            left.size + (taggedHeaderBytesV1 "CallableResult" 2).size + 4 + visB.size,
            nesting + 1⟩) := by
    have hmid := decodeVisibility_of_encode_midV1 r.visibility visB
      (left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId) right
      (nesting + 1) hdepthVis hvisEnc
    have hin :
        (left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId) ++ visB ++ right =
          left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId).size =
        left.size + (taggedHeaderBytesV1 "CallableResult" 2).size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz] using hmid
  have hshell := decodeCallableResultV1_eq_of_bodyV1
    ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right,
      left.size, nesting⟩ r
    ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB ++ right,
      left.size + (taggedHeaderBytesV1 "CallableResult" 2).size + 4 + visB.size,
      nesting + 1⟩ hdepth
    (by
      cases r with
      | mk typeId visibility =>
          exact decodeCallableResultBodyV1_eq_of_fields
            ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le typeId ++ visB ++ right,
              left.size, nesting + 1⟩
            ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le typeId ++ visB ++ right,
              left.size + (taggedHeaderBytesV1 "CallableResult" 2).size, nesting + 1⟩
            ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le typeId ++ visB ++ right,
              left.size + (taggedHeaderBytesV1 "CallableResult" 2).size + 4, nesting + 1⟩
            ⟨left ++ taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le typeId ++ visB ++ right,
              left.size + (taggedHeaderBytesV1 "CallableResult" 2).size + 4 + visB.size, nesting + 1⟩
            typeId visibility hexpect htype hvis)
  have hsz :
      left.size + (taggedHeaderBytesV1 "CallableResult" 2).size + 4 + visB.size =
        left.size + (taggedHeaderBytesV1 "CallableResult" 2 ++ encodeU32le r.typeId ++ visB).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  simpa [hsz] using hshell

/-! ### Block exact inversion (shape-parametric fields) -/

theorem encodeBlock_ok_eqV1 (blk : BlockV1) (b : ByteArray)
    (h : encodeBlockV1 blk = .ok b) :
    ∃ paramsB instrB termB,
      encodeArray encodeBlockParameterV1 blk.params = .ok paramsB ∧
      encodeArray encodeInstructionV1 blk.instructions = .ok instrB ∧
      encodeTerminatorV1 blk.terminator = .ok termB ∧
      b = taggedBytesV1 "Block" #[encodeU32le blk.id, paramsB, instrB, termB] := by
  simp only [encodeBlockV1] at h
  cases hp : encodeArray encodeBlockParameterV1 blk.params with
  | error e => simp only [hp, Bind.bind, Except.bind] at h; cases h
  | ok paramsB =>
      cases hi : encodeArray encodeInstructionV1 blk.instructions with
      | error e => simp only [hp, hi, Bind.bind, Except.bind] at h; cases h
      | ok instrB =>
          cases ht : encodeTerminatorV1 blk.terminator with
          | error e => simp only [hp, hi, ht, Bind.bind, Except.bind] at h; cases h
          | ok termB =>
              simp only [hp, hi, ht, Bind.bind, Except.bind] at h
              exact ⟨paramsB, instrB, termB, rfl, rfl, rfl,
                (encodeTagged_ok_eq_taggedBytesV1 "Block"
                  #[encodeU32le blk.id, paramsB, instrB, termB] b h).1⟩

theorem decodeBlock_of_encode_fields_midV1
    (blk : BlockV1) (paramsB instrB termB b left right : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (hparamsEnc : encodeArray encodeBlockParameterV1 blk.params = .ok paramsB)
    (hinstrEnc : encodeArray encodeInstructionV1 blk.instructions = .ok instrB)
    (htermEnc : encodeTerminatorV1 blk.terminator = .ok termB)
    (henc : encodeBlockV1 blk = .ok b)
    (hparamsDec :
      decodeArray maxArrayElements decodeBlockParameterV1
        ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
          left.size + (taggedHeaderBytesV1 "Block" 4).size + 4, nesting + 1⟩ =
        .ok (blk.params,
          ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
            left.size + (taggedHeaderBytesV1 "Block" 4).size + 4 + paramsB.size, nesting + 1⟩))
    (hinstrDec :
      decodeArray maxArrayElements decodeInstructionV1
        ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
          left.size + (taggedHeaderBytesV1 "Block" 4).size + 4 + paramsB.size, nesting + 1⟩ =
        .ok (blk.instructions,
          ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
            left.size + (taggedHeaderBytesV1 "Block" 4).size + 4 + paramsB.size + instrB.size, nesting + 1⟩))
    (htermDec :
      decodeTerminatorV1
        ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
          left.size + (taggedHeaderBytesV1 "Block" 4).size + 4 + paramsB.size + instrB.size, nesting + 1⟩ =
        .ok (blk.terminator,
          ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
            left.size + (taggedHeaderBytesV1 "Block" 4).size + 4 + paramsB.size + instrB.size + termB.size,
            nesting + 1⟩)) :
    decodeBlockV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (blk, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb : b = taggedBytesV1 "Block" #[encodeU32le blk.id, paramsB, instrB, termB] := by
    simp only [encodeBlockV1, hparamsEnc, hinstrEnc, htermEnc, Bind.bind, Except.bind] at henc
    exact (encodeTagged_ok_eq_taggedBytesV1 "Block"
      #[encodeU32le blk.id, paramsB, instrB, termB] b henc).1
  subst b
  have hlayout := taggedBytes_four_fields "Block" (encodeU32le blk.id) paramsB instrB termB
  have hflat :
      left ++ (taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB) ++ right =
        left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflat]
  have hexpect :
      expectTag "Block" 4
          ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
            left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
            left.size + (taggedHeaderBytesV1 "Block" 4).size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right =
          left ++ taggedHeaderBytesV1 "Block" 4 ++ (encodeU32le blk.id ++ paramsB ++ instrB ++ termB) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "Block" 4 (encodeU32le blk.id ++ paramsB ++ instrB ++ termB)
      (nesting + 1) (by decide) (by decide) (by decide) isAsciiTagBytes_Block (by decide)
  have hid :
      decodeU32le
          ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
            left.size + (taggedHeaderBytesV1 "Block" 4).size, nesting + 1⟩ =
        .ok (blk.id,
          ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
            left.size + (taggedHeaderBytesV1 "Block" 4).size + 4, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right =
          (left ++ taggedHeaderBytesV1 "Block" 4) ++ encodeU32le blk.id ++ (paramsB ++ instrB ++ termB ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Block" 4).size =
        left.size + (taggedHeaderBytesV1 "Block" 4).size := by simp [ByteArray.size_append]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "Block" 4)
      (paramsB ++ instrB ++ termB ++ right) blk.id (nesting + 1)
  have hshell := decodeBlockV1_eq_of_fieldsV1
    ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
      left.size, nesting⟩
    ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
      left.size + (taggedHeaderBytesV1 "Block" 4).size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
      left.size + (taggedHeaderBytesV1 "Block" 4).size + 4, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
      left.size + (taggedHeaderBytesV1 "Block" 4).size + 4 + paramsB.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
      left.size + (taggedHeaderBytesV1 "Block" 4).size + 4 + paramsB.size + instrB.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB ++ right,
      left.size + (taggedHeaderBytesV1 "Block" 4).size + 4 + paramsB.size + instrB.size + termB.size, nesting + 1⟩
    blk.id blk.params blk.instructions blk.terminator hdepth hexpect hid hparamsDec hinstrDec htermDec
  have hsz :
      left.size + (taggedHeaderBytesV1 "Block" 4).size + 4 + paramsB.size + instrB.size + termB.size =
        left.size + (taggedHeaderBytesV1 "Block" 4 ++ encodeU32le blk.id ++ paramsB ++ instrB ++ termB).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  cases blk
  simpa [hsz] using hshell

/-! ### Callable exact inversion (shape-parametric fields) -/

theorem encodeCallable_ok_eqV1 (c : CallableV1) (b : ByteArray)
    (h : encodeCallableV1 c = .ok b) :
    ∃ kindB nameB paramsB resultB blocksB loopB stepsB,
      encodeCallableKindV1 c.kind = .ok kindB ∧
      encodeOption encodeString c.name = .ok nameB ∧
      encodeArray encodeParameterV1 c.params = .ok paramsB ∧
      encodeCallableResultV1 c.result = .ok resultB ∧
      encodeArray encodeBlockV1 c.blocks = .ok blocksB ∧
      encodeArray encodeLoopBoundV1 c.loopBounds = .ok loopB ∧
      encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps = .ok stepsB ∧
      b = taggedBytesV1 "Callable"
        #[encodeU32le c.id, kindB, nameB, paramsB, resultB,
          encodeU32le c.entryBlock, blocksB, loopB, stepsB] := by
  simp only [encodeCallableV1] at h
  cases hk : encodeCallableKindV1 c.kind with
  | error e => simp only [hk, Bind.bind, Except.bind] at h; cases h
  | ok kindB =>
  cases hn : encodeOption encodeString c.name with
  | error e => simp only [hk, hn, Bind.bind, Except.bind] at h; cases h
  | ok nameB =>
  cases hp : encodeArray encodeParameterV1 c.params with
  | error e => simp only [hk, hn, hp, Bind.bind, Except.bind] at h; cases h
  | ok paramsB =>
  cases hr : encodeCallableResultV1 c.result with
  | error e => simp only [hk, hn, hp, hr, Bind.bind, Except.bind] at h; cases h
  | ok resultB =>
  cases hbks : encodeArray encodeBlockV1 c.blocks with
  | error e => simp only [hk, hn, hp, hr, hbks, Bind.bind, Except.bind] at h; cases h
  | ok blocksB =>
  cases hl : encodeArray encodeLoopBoundV1 c.loopBounds with
  | error e => simp only [hk, hn, hp, hr, hbks, hl, Bind.bind, Except.bind] at h; cases h
  | ok loopB =>
  cases hs : encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps with
  | error e => simp only [hk, hn, hp, hr, hbks, hl, hs, Bind.bind, Except.bind] at h; cases h
  | ok stepsB =>
      simp only [hk, hn, hp, hr, hbks, hl, hs, Bind.bind, Except.bind] at h
      exact ⟨kindB, nameB, paramsB, resultB, blocksB, loopB, stepsB,
        rfl, rfl, rfl, rfl, rfl, rfl, rfl,
        (encodeTagged_ok_eq_taggedBytesV1 "Callable"
          #[encodeU32le c.id, kindB, nameB, paramsB, resultB,
            encodeU32le c.entryBlock, blocksB, loopB, stepsB] b h).1⟩

/-- Callable field-composition exact inversion through the production codec.
    This is intentionally shape-parametric: concrete PreservationShapeV1 packages
    supply exact decoders for their name/params/result/block/loop/steps fields. -/
theorem decodeCallable_of_encode_fields_midV1
    (c : CallableV1)
    (kindB nameB paramsB resultB blocksB loopB stepsB b left right : ByteArray)
    (nesting : Nat) (hdepth : nesting < maxNesting)
    (hkindEnc : encodeCallableKindV1 c.kind = .ok kindB)
    (hnameEnc : encodeOption encodeString c.name = .ok nameB)
    (hparamsEnc : encodeArray encodeParameterV1 c.params = .ok paramsB)
    (hresultEnc : encodeCallableResultV1 c.result = .ok resultB)
    (hblocksEnc : encodeArray encodeBlockV1 c.blocks = .ok blocksB)
    (hloopEnc : encodeArray encodeLoopBoundV1 c.loopBounds = .ok loopB)
    (hstepsEnc : encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps = .ok stepsB)
    (henc : encodeCallableV1 c = .ok b)
    (hkindDec : decodeCallableKindV1
      ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
        left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4, nesting + 1⟩ =
      .ok (c.kind,
        ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
          left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size, nesting + 1⟩))
    (hnameDec : decodeOption decodeString
      ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
        left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size, nesting + 1⟩ =
      .ok (c.name,
        ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
          left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size, nesting + 1⟩))
    (hparamsDec : decodeArray maxArrayElements decodeParameterV1
      ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
        left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size, nesting + 1⟩ =
      .ok (c.params,
        ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
          left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size, nesting + 1⟩))
    (hresultDec : decodeCallableResultV1
      ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
        left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size, nesting + 1⟩ =
      .ok (c.result,
        ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
          left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size, nesting + 1⟩))
    (hblocksDec : decodeArray maxArrayElements decodeBlockV1
      ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
        left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4, nesting + 1⟩ =
      .ok (c.blocks,
        ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
          left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4 + blocksB.size, nesting + 1⟩))
    (hloopsDec : decodeArray maxArrayElements decodeLoopBoundV1
      ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
        left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4 + blocksB.size, nesting + 1⟩ =
      .ok (c.loopBounds,
        ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
          left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4 + blocksB.size + loopB.size, nesting + 1⟩))
    (hstepsDec : decodeOption decodeU64le
      ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
        left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4 + blocksB.size + loopB.size, nesting + 1⟩ =
      .ok (c.invariantSteps,
        ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
          left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4 + blocksB.size + loopB.size + stepsB.size, nesting + 1⟩)) :
    decodeCallableV1 ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (c, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  have hb : b = taggedBytesV1 "Callable"
        #[encodeU32le c.id, kindB, nameB, paramsB, resultB,
          encodeU32le c.entryBlock, blocksB, loopB, stepsB] := by
    simp only [encodeCallableV1, hkindEnc, hnameEnc, hparamsEnc, hresultEnc,
      hblocksEnc, hloopEnc, hstepsEnc, Bind.bind, Except.bind] at henc
    exact (encodeTagged_ok_eq_taggedBytesV1 "Callable"
      #[encodeU32le c.id, kindB, nameB, paramsB, resultB,
        encodeU32le c.entryBlock, blocksB, loopB, stepsB] b henc).1
  subst b
  have hlayout := taggedBytes_nine_fields "Callable" (encodeU32le c.id) kindB nameB paramsB
    resultB (encodeU32le c.entryBlock) blocksB loopB stepsB
  have hflat :
      left ++ (taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB) ++ right =
        left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right := by
    simp [ByteArray.append_assoc]
  rw [hlayout, hflat]
  have htag :
      expectTag "Callable" 9
          ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
            left.size, nesting + 1⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
            left.size + (taggedHeaderBytesV1 "Callable" 9).size, nesting + 1⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right =
          left ++ taggedHeaderBytesV1 "Callable" 9 ++ (encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB) ++ right := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact expectTag_encode_midV1 left right "Callable" 9
      (encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB)
      (nesting + 1) (by decide) (by decide) (by decide) isAsciiTagBytes_Callable (by decide)
  have hid : decodeU32le
      ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
        left.size + (taggedHeaderBytesV1 "Callable" 9).size, nesting + 1⟩ =
      .ok (c.id,
        ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
          left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4, nesting + 1⟩) := by
    have hin :
      left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right =
        (left ++ taggedHeaderBytesV1 "Callable" 9) ++ encodeU32le c.id ++ (kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Callable" 9).size =
        left.size + (taggedHeaderBytesV1 "Callable" 9).size := by simp [ByteArray.size_append]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1 (left ++ taggedHeaderBytesV1 "Callable" 9)
      (kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right) c.id (nesting + 1)
  have hentry : decodeU32le
      ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
        left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size, nesting + 1⟩ =
      .ok (c.entryBlock,
        ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right,
          left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4, nesting + 1⟩) := by
    have hin :
      left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right =
        (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB) ++ encodeU32le c.entryBlock ++ (blocksB ++ loopB ++ stepsB ++ right) := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB).size =
        left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    rw [hin, ← hsz]
    exact decodeU32le_encode_midV1
      (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB)
      (blocksB ++ loopB ++ stepsB ++ right) c.entryBlock (nesting + 1)
  have hshell := decodeCallableV1_eq_of_fieldsV1
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size, nesting⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4 + blocksB.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4 + blocksB.size + loopB.size, nesting + 1⟩
    ⟨left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right, left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4 + blocksB.size + loopB.size + stepsB.size, nesting + 1⟩
    c.id c.entryBlock c.kind c.name c.params c.result c.blocks c.loopBounds c.invariantSteps
    hdepth htag hid hkindDec hnameDec hparamsDec hresultDec hentry hblocksDec hloopsDec hstepsDec
  have hsz :
    left.size + (taggedHeaderBytesV1 "Callable" 9).size + 4 + kindB.size + nameB.size + paramsB.size + resultB.size + 4 + blocksB.size + loopB.size + stepsB.size =
      left.size + (taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le c.id ++ kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le c.entryBlock ++ blocksB ++ loopB ++ stepsB).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]; omega
  cases c
  simpa [hsz] using hshell

/-! ### Fixed-depth composition packages used by root callables -/

/-- Fixed-depth absent-option inversion for any payload codec. -/
theorem exactAt_option_noneV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (nesting : Nat) :
    ExactMidOffsetInvertAtV1 (encodeOption encode) (decodeOption decode)
      (none : Option α) nesting := by
  intro b left right henc
  simp only [encodeOption, Pure.pure, Except.pure] at henc
  have hb : b = encodeU8 0 := Except.ok.inj henc.symm
  subst b
  simpa [encodeU8_size] using
    decodeOption_none_encode_midV1 decode left right nesting

/-- Fixed-depth present string inversion under the production identifier gate. -/
theorem exactAt_optionString_some_identifierV1
    (value : String) (hvalue : validateIdentifierComponent value = .ok ())
    (nesting : Nat) :
    ExactMidOffsetInvertAtV1 (encodeOption encodeString) (decodeOption decodeString)
      (some value) nesting := by
  intro b left right henc
  have hstr : encodeString value = .ok (stringPayloadBytesV1 value) :=
    encodeString_of_identifierV1 value hvalue
  simp only [encodeOption, hstr, Bind.bind, Except.bind, Pure.pure, Except.pure] at henc
  have hb : b = encodeU8 1 ++ stringPayloadBytesV1 value := Except.ok.inj henc.symm
  subst b
  have hdec := decodeOptionString_some_identifier_midV1 left right value nesting hvalue
  have hoff : left.size + 1 + 4 + value.toUTF8.size =
      left.size + (1 + (4 + value.toUTF8.size)) := by
    omega
  rw [hoff] at hdec
  simpa [someStringPayloadBytesV1, stringPayloadBytesV1, ByteArray.size_append,
    encodeU8_size, encodeU32le_sizeV1, ByteArray.append_assoc] using hdec

/-- Production U64 decoder recovers the fixed invariant-fuel value `7`. -/
theorem decodeU64le_seven_encode_midV1
    (left right : ByteArray) (nesting : Nat) :
    decodeU64le ⟨left ++ encodeU64le 7 ++ right, left.size, nesting⟩ =
      .ok (7, ⟨left ++ encodeU64le 7 ++ right, left.size + 8, nesting⟩) := by
  apply decodeU64le_eq_of_readV1
  have h0 : readByteAtV1 (left ++ encodeU64le 7 ++ right) (left.size + 0) = .ok 7 := by
    exact readByte_mid_payloadV1 left (encodeU64le 7) right 0 7 (by decide) (by decide)
  have h1 : readByteAtV1 (left ++ encodeU64le 7 ++ right) (left.size + 1) = .ok 0 := by
    exact readByte_mid_payloadV1 left (encodeU64le 7) right 1 0 (by decide) (by decide)
  have h2 : readByteAtV1 (left ++ encodeU64le 7 ++ right) (left.size + 2) = .ok 0 := by
    exact readByte_mid_payloadV1 left (encodeU64le 7) right 2 0 (by decide) (by decide)
  have h3 : readByteAtV1 (left ++ encodeU64le 7 ++ right) (left.size + 3) = .ok 0 := by
    exact readByte_mid_payloadV1 left (encodeU64le 7) right 3 0 (by decide) (by decide)
  have h4 : readByteAtV1 (left ++ encodeU64le 7 ++ right) (left.size + 4) = .ok 0 := by
    exact readByte_mid_payloadV1 left (encodeU64le 7) right 4 0 (by decide) (by decide)
  have h5 : readByteAtV1 (left ++ encodeU64le 7 ++ right) (left.size + 5) = .ok 0 := by
    exact readByte_mid_payloadV1 left (encodeU64le 7) right 5 0 (by decide) (by decide)
  have h6 : readByteAtV1 (left ++ encodeU64le 7 ++ right) (left.size + 6) = .ok 0 := by
    exact readByte_mid_payloadV1 left (encodeU64le 7) right 6 0 (by decide) (by decide)
  have h7 : readByteAtV1 (left ++ encodeU64le 7 ++ right) (left.size + 7) = .ok 0 := by
    exact readByte_mid_payloadV1 left (encodeU64le 7) right 7 0 (by decide) (by decide)
  have h0' :
      readByteAtV1 (left ++ encodeU64le 7 ++ right) left.size = .ok 7 := by
    simpa using h0
  unfold readU64leAtV1
  simp only [h0', h1, h2, h3, h4, h5, h6, h7, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  congr 2

/-- Fixed-depth present invariant-fuel option for the closed value `7`. -/
theorem exactAt_optionU64_someSevenV1 (nesting : Nat) :
    ExactMidOffsetInvertAtV1
      (encodeOption (fun value : UInt64 => pure (encodeU64le value)))
      (decodeOption decodeU64le) (some 7) nesting := by
  intro b left right henc
  simp only [encodeOption, Bind.bind, Except.bind, Pure.pure, Except.pure] at henc
  have hb : b = encodeU8 1 ++ encodeU64le 7 := Except.ok.inj henc.symm
  subst b
  have hdec := decodeOption_some_of_encode_midV1
    (fun value : UInt64 => pure (encodeU64le value)) decodeU64le 7 (encodeU64le 7)
    left right nesting rfl (by
      have h := decodeU64le_seven_encode_midV1 (left ++ encodeU8 1) right nesting
      simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU8_size,
        encodeU64le_size] using h)
  simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU8_size,
    encodeU64le_size, Nat.add_assoc] using hdec

/-! ### Fixed-depth array composition -/

/-- Empty arrays do not consume tagged nesting and are invertible at every fixed depth. -/
theorem exactAt_array_emptyV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount nesting : Nat) :
    ExactMidOffsetInvertAtV1 (encodeArray encode) (decodeArray maxCount decode)
      (#[] : Array α) nesting := by
  intro b left right henc
  exact decodeArray_of_encodeArray_zero_ok_midV1 encode decode maxCount
    b left right nesting henc

/-- One-element fixed-depth array lift. -/
theorem exactAt_array_one_of_encodedAtV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (hmax : 1 ≤ maxCount)
    (v0 : α) (b0 : ByteArray) (nesting : Nat)
    (henc0 : encode v0 = .ok b0)
    (h0 : ExactMidOffsetInvertAtV1 encode decode v0 nesting) :
    ExactMidOffsetInvertAtV1 (encodeArray encode) (decodeArray maxCount decode)
      #[v0] nesting := by
  intro b left right henc
  refine decodeArray_of_encodeArray_one_ok_midV1 encode decode maxCount
    v0 b b0 left right nesting hmax henc0 henc ?_
  have hmid := h0 b0 (left ++ encodeU32le 1) right henc0
  have hin : (left ++ encodeU32le 1) ++ b0 ++ right =
      left ++ encodeU32le 1 ++ b0 ++ right := by
    simp [ByteArray.append_assoc]
  have hsz : (left ++ encodeU32le 1).size = left.size + 4 := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]
  simpa [hin, hsz, ByteArray.append_assoc, encodeU32le_sizeV1,
    Nat.add_assoc] using hmid

/-- One-element fixed-depth array lift without a caller-supplied element byte witness. -/
theorem exactAt_array_one_of_exactAtV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (hmax : 1 ≤ maxCount)
    (v0 : α) (nesting : Nat)
    (h0 : ExactMidOffsetInvertAtV1 encode decode v0 nesting) :
    ExactMidOffsetInvertAtV1 (encodeArray encode) (decodeArray maxCount decode)
      #[v0] nesting := by
  cases henc0 : encode v0 with
  | error error =>
      intro b left right henc
      have harr := encodeArray_one_errorV1 encode v0 error henc0
      rw [harr] at henc
      cases henc
  | ok b0 =>
      exact exactAt_array_one_of_encodedAtV1 encode decode maxCount hmax
        v0 b0 nesting henc0 h0

/-- Three-element fixed-depth array lift from production element bytes. -/
theorem exactAt_array_three_of_encodedAtV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (hmax : 3 ≤ maxCount)
    (v0 v1 v2 : α) (b0 b1 b2 : ByteArray) (nesting : Nat)
    (henc0 : encode v0 = .ok b0) (henc1 : encode v1 = .ok b1)
    (henc2 : encode v2 = .ok b2)
    (h0 : ExactMidOffsetInvertAtV1 encode decode v0 nesting)
    (h1 : ExactMidOffsetInvertAtV1 encode decode v1 nesting)
    (h2 : ExactMidOffsetInvertAtV1 encode decode v2 nesting) :
    ExactMidOffsetInvertAtV1 (encodeArray encode) (decodeArray maxCount decode)
      #[v0, v1, v2] nesting := by
  intro b left right henc
  have hinv0 :
      decode ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
        left.size + 4, nesting⟩ =
        .ok (v0, ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
          left.size + 4 + b0.size, nesting⟩) := by
    have hmid := h0 b0 (left ++ encodeU32le 3) (b1 ++ b2 ++ right) henc0
    have hin : (left ++ encodeU32le 3) ++ b0 ++ (b1 ++ b2 ++ right) =
        left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 3).size = left.size + 4 := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz, ByteArray.append_assoc, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  have hinv1 :
      decode ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
        left.size + 4 + b0.size, nesting⟩ =
        .ok (v1, ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
          left.size + 4 + b0.size + b1.size, nesting⟩) := by
    have hmid := h1 b1 (left ++ encodeU32le 3 ++ b0) (b2 ++ right) henc1
    have hin : (left ++ encodeU32le 3 ++ b0) ++ b1 ++ (b2 ++ right) =
        left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 3 ++ b0).size =
        left.size + 4 + b0.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz, ByteArray.append_assoc, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  have hinv2 :
      decode ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
        left.size + 4 + b0.size + b1.size, nesting⟩ =
        .ok (v2, ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
          left.size + 4 + b0.size + b1.size + b2.size, nesting⟩) := by
    have hmid := h2 b2 (left ++ encodeU32le 3 ++ b0 ++ b1) right henc2
    have hin : (left ++ encodeU32le 3 ++ b0 ++ b1) ++ b2 ++ right =
        left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right := by
      simp [ByteArray.append_assoc]
    have hsz : (left ++ encodeU32le 3 ++ b0 ++ b1).size =
        left.size + 4 + b0.size + b1.size := by
      simp [ByteArray.size_append, encodeU32le_sizeV1]
    simpa [hin, hsz, ByteArray.append_assoc, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  have hcount :
      readArrayCountAtV1 (left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right)
        left.size maxCount = .ok (3, left.size + 4) := by
    have hin : left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right =
        left ++ encodeU32le 3 ++ (b0 ++ b1 ++ b2 ++ right) := by
      simp [ByteArray.append_assoc]
    rw [hin]
    exact readArrayCount_encode_midV1 left (b0 ++ b1 ++ b2 ++ right)
      3 maxCount (by decide) hmax
  have harr := decodeArray_threeV1 maxCount decode
    ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right, left.size, nesting⟩
    (left.size + 4) v0 v1 v2
    ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
      left.size + 4 + b0.size, nesting⟩
    ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
      left.size + 4 + b0.size + b1.size, nesting⟩
    ⟨left ++ encodeU32le 3 ++ b0 ++ b1 ++ b2 ++ right,
      left.size + 4 + b0.size + b1.size + b2.size, nesting⟩
    hcount hinv0 hinv1 hinv2
  have hb : b = (encodeU32le 3).append ((b0.append b1).append b2) := by
    have harray := encodeArray_threeV1 encode v0 v1 v2 b0 b1 b2
      henc0 henc1 henc2
    exact Except.ok.inj (henc.symm.trans harray)
  subst b
  have hfinal : left.size + 4 + b0.size + b1.size + b2.size =
      left.size + ((encodeU32le 3).append ((b0.append b1).append b2)).size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]
    omega
  simpa [hfinal, ByteArray.append_assoc] using harr

/-- Three-element fixed-depth array lift without caller-supplied element bytes. -/
theorem exactAt_array_three_of_exactAtV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (hmax : 3 ≤ maxCount)
    (v0 v1 v2 : α) (nesting : Nat)
    (h0 : ExactMidOffsetInvertAtV1 encode decode v0 nesting)
    (h1 : ExactMidOffsetInvertAtV1 encode decode v1 nesting)
    (h2 : ExactMidOffsetInvertAtV1 encode decode v2 nesting) :
    ExactMidOffsetInvertAtV1 (encodeArray encode) (decodeArray maxCount decode)
      #[v0, v1, v2] nesting := by
  cases henc0 : encode v0 with
  | error error =>
      intro b left right henc
      have harr := encodeArray_three_error_firstV1 encode v0 v1 v2 error henc0
      rw [harr] at henc
      cases henc
  | ok b0 =>
      cases henc1 : encode v1 with
      | error error =>
          intro b left right henc
          have harr := encodeArray_three_error_secondV1 encode v0 v1 v2
            b0 error henc0 henc1
          rw [harr] at henc
          cases henc
      | ok b1 =>
          cases henc2 : encode v2 with
          | error error =>
              intro b left right henc
              have harr := encodeArray_three_error_thirdV1 encode v0 v1 v2
                b0 b1 error henc0 henc1 henc2
              rw [harr] at henc
              cases henc
          | ok b2 =>
              exact exactAt_array_three_of_encodedAtV1 encode decode maxCount hmax
                v0 v1 v2 b0 b1 b2 nesting henc0 henc1 henc2 h0 h1 h2

/-- Five-element fixed-depth array lift from production element bytes. -/
theorem exactAt_array_five_of_encodedAtV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (hmax : 5 ≤ maxCount)
    (v0 v1 v2 v3 v4 : α) (b0 b1 b2 b3 b4 : ByteArray) (nesting : Nat)
    (henc0 : encode v0 = .ok b0) (henc1 : encode v1 = .ok b1)
    (henc2 : encode v2 = .ok b2) (henc3 : encode v3 = .ok b3)
    (henc4 : encode v4 = .ok b4)
    (h0 : ExactMidOffsetInvertAtV1 encode decode v0 nesting)
    (h1 : ExactMidOffsetInvertAtV1 encode decode v1 nesting)
    (h2 : ExactMidOffsetInvertAtV1 encode decode v2 nesting)
    (h3 : ExactMidOffsetInvertAtV1 encode decode v3 nesting)
    (h4 : ExactMidOffsetInvertAtV1 encode decode v4 nesting) :
    ExactMidOffsetInvertAtV1 (encodeArray encode) (decodeArray maxCount decode)
      #[v0, v1, v2, v3, v4] nesting := by
  intro b left right henc
  refine decodeArray_of_encodeArray_five_ok_midV1 encode decode maxCount
    v0 v1 v2 v3 v4 b b0 b1 b2 b3 b4 left right nesting hmax
    henc0 henc1 henc2 henc3 henc4 henc ?_ ?_ ?_ ?_ ?_
  · have hmid := h0 b0 (left ++ encodeU32le 5)
      (b1 ++ b2 ++ b3 ++ b4 ++ right) henc0
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := h1 b1 (left ++ encodeU32le 5 ++ b0)
      (b2 ++ b3 ++ b4 ++ right) henc1
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := h2 b2 (left ++ encodeU32le 5 ++ b0 ++ b1)
      (b3 ++ b4 ++ right) henc2
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := h3 b3 (left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2)
      (b4 ++ right) henc3
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := h4 b4 (left ++ encodeU32le 5 ++ b0 ++ b1 ++ b2 ++ b3)
      right henc4
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid

/-- Five-element fixed-depth array lift without caller-supplied element bytes. -/
theorem exactAt_array_five_of_exactAtV1
    (encode : α → Except SemanticWireErrorV1 ByteArray)
    (decode : Decoder α) (maxCount : Nat) (hmax : 5 ≤ maxCount)
    (v0 v1 v2 v3 v4 : α) (nesting : Nat)
    (h0 : ExactMidOffsetInvertAtV1 encode decode v0 nesting)
    (h1 : ExactMidOffsetInvertAtV1 encode decode v1 nesting)
    (h2 : ExactMidOffsetInvertAtV1 encode decode v2 nesting)
    (h3 : ExactMidOffsetInvertAtV1 encode decode v3 nesting)
    (h4 : ExactMidOffsetInvertAtV1 encode decode v4 nesting) :
    ExactMidOffsetInvertAtV1 (encodeArray encode) (decodeArray maxCount decode)
      #[v0, v1, v2, v3, v4] nesting := by
  cases henc0 : encode v0 with
  | error error =>
      intro b left right henc
      have harr := encodeArray_five_error_firstV1 encode v0 v1 v2 v3 v4 error henc0
      rw [harr] at henc
      cases henc
  | ok b0 =>
      cases henc1 : encode v1 with
      | error error =>
          intro b left right henc
          have harr := encodeArray_five_error_secondV1 encode v0 v1 v2 v3 v4
            b0 error henc0 henc1
          rw [harr] at henc
          cases henc
      | ok b1 =>
          cases henc2 : encode v2 with
          | error error =>
              intro b left right henc
              have harr := encodeArray_five_error_thirdV1 encode v0 v1 v2 v3 v4
                b0 b1 error henc0 henc1 henc2
              rw [harr] at henc
              cases henc
          | ok b2 =>
              cases henc3 : encode v3 with
              | error error =>
                  intro b left right henc
                  have harr := encodeArray_five_error_fourthV1 encode v0 v1 v2 v3 v4
                    b0 b1 b2 error henc0 henc1 henc2 henc3
                  rw [harr] at henc
                  cases henc
              | ok b3 =>
                  cases henc4 : encode v4 with
                  | error error =>
                      intro b left right henc
                      have harr := encodeArray_five_error_fifthV1 encode v0 v1 v2 v3 v4
                        b0 b1 b2 b3 error henc0 henc1 henc2 henc3 henc4
                      rw [harr] at henc
                      cases henc
                  | ok b4 =>
                      exact exactAt_array_five_of_encodedAtV1 encode decode maxCount hmax
                        v0 v1 v2 v3 v4 b0 b1 b2 b3 b4 nesting
                        henc0 henc1 henc2 henc3 henc4 h0 h1 h2 h3 h4

/-! ### Fixed-depth callable leaf composition -/

/-- Callable kinds inherit the global codec theorem at a checked fixed depth. -/
theorem exactAt_callableKindV1 (kind : CallableKindV1) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeCallableKindV1 decodeCallableKindV1 kind nesting :=
  ExactMidOffsetInvertAtV1.ofGlobal
    midOffsetInvert_encodeCallableKind_decodeCallableKind kind hdepth

/-- Optional ValueDef inversion at a checked fixed depth. -/
theorem exactAt_optionValueDefV1 (result : Option ValueDefV1) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    ExactMidOffsetInvertAtV1 (encodeOption encodeValueDefV1)
      (decodeOption decodeValueDefV1) result nesting := by
  intro b left right henc
  exact decodeOptionValueDef_of_encode_midV1 result b left right nesting hdepth henc

/-- State-load operation inversion at a checked fixed depth. -/
theorem exactAt_semanticOp_stateLoadV1 (stateId : UInt32) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      (.stateLoad stateId) nesting := by
  intro b left right henc
  exact decodeSemanticOp_stateLoad_of_encode_midV1 stateId b left right nesting
    hdepth henc

/-- Literal operation inversion at a checked fixed depth. -/
theorem exactAt_semanticOp_literalV1 (typeId : UInt32) (valueBytes : ByteArray)
    (nesting : Nat) (hdepth : nesting < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      (.literal typeId valueBytes) nesting := by
  intro b left right henc
  exact decodeSemanticOp_literal_of_encode_midV1 typeId valueBytes b left right
    nesting hdepth henc

/-- State-store operation inversion at a checked fixed depth. -/
theorem exactAt_semanticOp_stateStoreV1 (stateId value : UInt32) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      (.stateStore stateId value) nesting := by
  intro b left right henc
  exact decodeSemanticOp_stateStore_of_encode_midV1 stateId value b left right
    nesting hdepth henc

/-- Binary-add operation inversion at the two checked tagged depths. -/
theorem exactAt_semanticOp_binaryAddV1 (lhs rhs : UInt32) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthOp : nesting + 1 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      (.binary .add lhs rhs) nesting := by
  intro b left right henc
  exact decodeSemanticOp_binary_add_of_encode_midV1 lhs rhs b left right nesting
    hdepth hdepthOp henc

/-- Binary-mod operation inversion at the two checked tagged depths. -/
theorem exactAt_semanticOp_binaryModV1 (lhs rhs : UInt32) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthOp : nesting + 1 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      (.binary .mod lhs rhs) nesting := by
  intro b left right henc
  exact decodeSemanticOp_binary_mod_of_encode_midV1 lhs rhs b left right nesting
    hdepth hdepthOp henc

/-- Binary-equality operation inversion at the two checked tagged depths. -/
theorem exactAt_semanticOp_binaryEqV1 (lhs rhs : UInt32) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthOp : nesting + 1 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      (.binary .eq lhs rhs) nesting := by
  intro b left right henc
  exact decodeSemanticOp_binary_eq_of_encode_midV1 lhs rhs b left right nesting
    hdepth hdepthOp henc

/-- Return terminators inherit their exact production theorem at fixed depth. -/
theorem exactAt_terminatorReturnV1 (value : Option UInt32) (nesting : Nat)
    (hdepth : nesting < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeTerminatorV1 decodeTerminatorV1
      (.return_ value) nesting := by
  intro b left right henc
  exact midOffsetInvert_encodeTerminator_return value b left right nesting hdepth henc

/-- Callable result inversion at fixed outer and visibility depths. -/
theorem exactAt_callableResultV1 (result : CallableResultV1) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthVis : nesting + 1 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeCallableResultV1 decodeCallableResultV1
      result nesting := by
  intro b left right henc
  exact decodeCallableResult_of_encode_midV1 result b left right nesting
    hdepth hdepthVis henc

/-- Instruction composition from fixed-depth result and operation packages. -/
theorem exactAt_instruction_of_fieldsV1
    (instruction : InstructionV1) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (hresult : ExactMidOffsetInvertAtV1
      (encodeOption encodeValueDefV1) (decodeOption decodeValueDefV1)
      instruction.result (nesting + 1))
    (hop : ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      instruction.op (nesting + 1)) :
    ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
      instruction nesting := by
  intro b left right henc
  obtain ⟨resultB, opB, hresultEnc, hopEnc, _⟩ :=
    encodeInstruction_ok_eqV1 instruction b henc
  refine decodeInstruction_of_encode_fields_midV1 instruction resultB opB b
    left right nesting hdepth hresultEnc hopEnc henc ?_ ?_
  · have hmid := hresult resultB
      (left ++ taggedHeaderBytesV1 "Instruction" 2) (opB ++ right) hresultEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, Nat.add_assoc] using hmid
  · have hmid := hop opB
      (left ++ taggedHeaderBytesV1 "Instruction" 2 ++ resultB) right hopEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, Nat.add_assoc] using hmid

/-- Value-producing instruction composition from a fixed-depth operation package. -/
theorem exactAt_valueInstruction_of_opV1
    (valueId typeId : UInt32) (op : SemanticOpV1) (nesting : Nat)
    (hdepth : nesting < maxNesting) (hdepthInner : nesting + 1 < maxNesting)
    (hop : ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      op (nesting + 1)) :
    ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
      ({ result := some { valueId, typeId }, op } : InstructionV1) nesting :=
  exactAt_instruction_of_fieldsV1
    ({ result := some { valueId, typeId }, op } : InstructionV1) nesting hdepth
    (exactAt_optionValueDefV1 (some { valueId, typeId }) (nesting + 1) hdepthInner)
    hop

/-- Void instruction composition from a fixed-depth operation package. -/
theorem exactAt_voidInstruction_of_opV1
    (op : SemanticOpV1) (nesting : Nat) (hdepth : nesting < maxNesting)
    (hop : ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1
      op (nesting + 1)) :
    ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
      ({ result := none, op } : InstructionV1) nesting :=
  exactAt_instruction_of_fieldsV1 ({ result := none, op } : InstructionV1)
    nesting hdepth
    (exactAt_option_noneV1 encodeValueDefV1 decodeValueDefV1 (nesting + 1)) hop

/-- Block composition from fixed-depth params, instructions, and terminator packages. -/
theorem exactAt_block_of_fieldsV1
    (block : BlockV1) (nesting : Nat) (hdepth : nesting < maxNesting)
    (hparams : ExactMidOffsetInvertAtV1
      (encodeArray encodeBlockParameterV1)
      (decodeArray maxArrayElements decodeBlockParameterV1)
      block.params (nesting + 1))
    (hinstructions : ExactMidOffsetInvertAtV1
      (encodeArray encodeInstructionV1)
      (decodeArray maxArrayElements decodeInstructionV1)
      block.instructions (nesting + 1))
    (hterminator : ExactMidOffsetInvertAtV1 encodeTerminatorV1 decodeTerminatorV1
      block.terminator (nesting + 1)) :
    ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1 block nesting := by
  intro b left right henc
  obtain ⟨paramsB, instrB, termB, hparamsEnc, hinstrEnc, htermEnc, _⟩ :=
    encodeBlock_ok_eqV1 block b henc
  refine decodeBlock_of_encode_fields_midV1 block paramsB instrB termB b
    left right nesting hdepth hparamsEnc hinstrEnc htermEnc henc ?_ ?_ ?_
  · have hmid := hparams paramsB
      (left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le block.id)
      (instrB ++ termB ++ right) hparamsEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := hinstructions instrB
      (left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le block.id ++ paramsB)
      (termB ++ right) hinstrEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := hterminator termB
      (left ++ taggedHeaderBytesV1 "Block" 4 ++ encodeU32le block.id ++ paramsB ++ instrB)
      right htermEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid

/-- Callable composition from fixed-depth packages for all nested fields. -/
theorem exactAt_callable_of_fieldsV1
    (callable : CallableV1) (nesting : Nat) (hdepth : nesting < maxNesting)
    (hkind : ExactMidOffsetInvertAtV1 encodeCallableKindV1 decodeCallableKindV1
      callable.kind (nesting + 1))
    (hname : ExactMidOffsetInvertAtV1 (encodeOption encodeString)
      (decodeOption decodeString) callable.name (nesting + 1))
    (hparams : ExactMidOffsetInvertAtV1 (encodeArray encodeParameterV1)
      (decodeArray maxArrayElements decodeParameterV1)
      callable.params (nesting + 1))
    (hresult : ExactMidOffsetInvertAtV1 encodeCallableResultV1
      decodeCallableResultV1 callable.result (nesting + 1))
    (hblocks : ExactMidOffsetInvertAtV1 (encodeArray encodeBlockV1)
      (decodeArray maxArrayElements decodeBlockV1)
      callable.blocks (nesting + 1))
    (hloops : ExactMidOffsetInvertAtV1 (encodeArray encodeLoopBoundV1)
      (decodeArray maxArrayElements decodeLoopBoundV1)
      callable.loopBounds (nesting + 1))
    (hsteps : ExactMidOffsetInvertAtV1
      (encodeOption (fun value : UInt64 => pure (encodeU64le value)))
      (decodeOption decodeU64le) callable.invariantSteps (nesting + 1)) :
    ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1 callable nesting := by
  intro b left right henc
  obtain ⟨kindB, nameB, paramsB, resultB, blocksB, loopB, stepsB,
      hkindEnc, hnameEnc, hparamsEnc, hresultEnc, hblocksEnc, hloopEnc,
      hstepsEnc, _⟩ := encodeCallable_ok_eqV1 callable b henc
  refine decodeCallable_of_encode_fields_midV1 callable kindB nameB paramsB
    resultB blocksB loopB stepsB b left right nesting hdepth hkindEnc
    hnameEnc hparamsEnc hresultEnc hblocksEnc hloopEnc hstepsEnc henc
    ?_ ?_ ?_ ?_ ?_ ?_ ?_
  · have hmid := hkind kindB
      (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le callable.id)
      (nameB ++ paramsB ++ resultB ++ encodeU32le callable.entryBlock ++
        blocksB ++ loopB ++ stepsB ++ right) hkindEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := hname nameB
      (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le callable.id ++ kindB)
      (paramsB ++ resultB ++ encodeU32le callable.entryBlock ++ blocksB ++
        loopB ++ stepsB ++ right) hnameEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := hparams paramsB
      (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le callable.id ++
        kindB ++ nameB)
      (resultB ++ encodeU32le callable.entryBlock ++ blocksB ++ loopB ++
        stepsB ++ right) hparamsEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := hresult resultB
      (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le callable.id ++
        kindB ++ nameB ++ paramsB)
      (encodeU32le callable.entryBlock ++ blocksB ++ loopB ++ stepsB ++ right)
      hresultEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := hblocks blocksB
      (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le callable.id ++
        kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le callable.entryBlock)
      (loopB ++ stepsB ++ right) hblocksEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := hloops loopB
      (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le callable.id ++
        kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le callable.entryBlock ++
        blocksB)
      (stepsB ++ right) hloopEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid
  · have hmid := hsteps stepsB
      (left ++ taggedHeaderBytesV1 "Callable" 9 ++ encodeU32le callable.id ++
        kindB ++ nameB ++ paramsB ++ resultB ++ encodeU32le callable.entryBlock ++
        blocksB ++ loopB)
      right hstepsEnc
    simpa [ByteArray.append_assoc, ByteArray.size_append, encodeU32le_sizeV1,
      Nat.add_assoc] using hmid

/- Remaining composition layer is generated below as compact shape-specific exact packages. -/

end ProofForgeV2.Semantic.WireV1
