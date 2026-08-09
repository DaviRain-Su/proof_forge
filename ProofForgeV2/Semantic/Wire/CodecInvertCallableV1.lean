import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.Wire.CodecInvertV1
import ProofForgeV2.Semantic.Wire.CodecInvertFieldsV1
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

private theorem decodeTag_fieldCount_one_midV1
    (tag : String) (payload left right : ByteArray) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true) :
    decodeTag
        ⟨left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right, left.size, nesting⟩ =
      .ok (tag,
        ⟨left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right,
          left.size + 4 + tag.toUTF8.size, nesting⟩) ∧
    decodeFieldCount 1
        ⟨left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right,
          left.size + 4 + tag.toUTF8.size, nesting⟩ =
      .ok ((),
        ⟨left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right,
          left.size + (taggedHeaderBytesV1 tag 1).size, nesting⟩) := by
  have henc :
      taggedHeaderBytesV1 tag 1 =
        encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          encodeU16le 1 := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have htag :
      decodeTag
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right, left.size, nesting⟩ =
        .ok (tag,
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right,
            left.size + 4 + tag.toUTF8.size, nesting⟩) := by
    have hin :
        left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right =
          left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
            (encodeU16le 1 ++ payload ++ right) := by
      simp [henc, ByteArray.append_assoc]
    rw [hin]
    simpa [ByteArray.append_assoc] using
      decodeTag_encode_midV1 left (encodeU16le 1 ++ payload ++ right) tag nesting
        hnonempty hmax hfit hasciiBytes hasciiTag
  have hfc :
      decodeFieldCount 1
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right,
            left.size + 4 + tag.toUTF8.size, nesting⟩ =
        .ok ((),
          ⟨left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right,
            left.size + (taggedHeaderBytesV1 tag 1).size, nesting⟩) := by
    have hassoc :
        left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right =
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
            encodeU16le 1 ++ (payload ++ right) := by
      simp [henc, ByteArray.append_assoc]
    have hsz :
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8).size =
          left.size + 4 + tag.toUTF8.size := by
      rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
    have hread :
        readU16leAtV1 (left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right)
            (left.size + 4 + tag.toUTF8.size) =
          .ok (1, left.size + 4 + tag.toUTF8.size + 2) := by
      rw [hassoc, ← hsz]
      simpa [hsz] using
        readU16le_encode_midV1
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8)
          (payload ++ right) 1
    have hszFinal :
        left.size + 4 + tag.toUTF8.size + 2 =
          left.size + (taggedHeaderBytesV1 tag 1).size := by
      simp only [taggedHeaderBytesV1_size]; omega
    rw [← hszFinal]
    exact decodeFieldCount_eq_of_readU16leV1 1
      ⟨left ++ taggedHeaderBytesV1 tag 1 ++ payload ++ right,
        left.size + 4 + tag.toUTF8.size, nesting⟩
      1 (left.size + 4 + tag.toUTF8.size + 2) hread
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
    decodeTag_fieldCount_one_midV1 "Term.Return" (encodeU8 0) left right (nesting + 1)
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
    decodeTag_fieldCount_one_midV1 "Term.Return" (encodeU8 1 ++ encodeU32le id)
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

end ProofForgeV2.Semantic.WireV1
