import ProofForgeV2.Semantic.Wire.CodecInvertFieldsV1

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertFieldReadV1 — reusable "field read"
  algebra for generic encode→decode invertibility.

  Every production record codec is `taggedHeaderBytes ++ chunk₀ ++ … ++ chunkₙ`,
  and every per-field proof in `Wire.CodecInvertFieldsV1` /
  `Wire.CodecInvertCallableV1` repeats the same three steps for each chunk:
  re-associate the buffer, rewrite the running offset into `pre.size`, and apply
  a mid-offset lemma for the field decoder.

  This module names that pattern once:

    `FieldReadV1 dec chunk value nesting`

  and provides

    * `FieldReadV1.read` — read a chunk anywhere inside a larger buffer,
    * leaf instances for the production scalar / string / bytes / option codecs,
    * `expectTag` and `withTaggedNesting` composition,
    * bridges to `ExactMidOffsetInvertAtV1` / `MidOffsetInvertV1` and to the
      production array lift.

  It introduces no encoder, no decoder, and no second traversal: every lemma is
  proved from the sole production codecs and the existing mid-offset lemmas.

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

/-! ### The field-read predicate -/

/-- `FieldReadV1 dec chunk value nesting`: at nesting depth `nesting`, the
    production decoder `dec` consumes exactly `chunk` and yields `value`, at any
    mid-offset of a larger buffer. -/
def FieldReadV1 {α : Type} (dec : Decoder α) (chunk : ByteArray) (value : α)
    (nesting : Nat) : Prop :=
  ∀ (pre post : ByteArray),
    dec ⟨pre ++ chunk ++ post, pre.size, nesting⟩ =
      .ok (value, ⟨pre ++ chunk ++ post, pre.size + chunk.size, nesting⟩)

/-- Read a field chunk at a known position of a fixed buffer. `hbuf` splits the
    buffer around the chunk and `hoff` identifies the running offset; the result
    offset advances by exactly `chunk.size`. -/
theorem FieldReadV1.read {α : Type} {dec : Decoder α} {chunk : ByteArray}
    {value : α} {nesting : Nat} (h : FieldReadV1 dec chunk value nesting)
    (buf : ByteArray) (off : Nat) (pre post : ByteArray)
    (hbuf : buf = pre ++ chunk ++ post) (hoff : off = pre.size) :
    dec ⟨buf, off, nesting⟩ = .ok (value, ⟨buf, off + chunk.size, nesting⟩) := by
  subst hbuf
  subst hoff
  exact h pre post

/-! ### Bridges to the mid-offset invert predicates -/

/-- A fixed-depth exact inversion plus the produced bytes gives a field read. -/
theorem FieldReadV1.ofExactAt {α : Type}
    {encode : α → Except SemanticWireErrorV1 ByteArray} {decode : Decoder α}
    {value : α} {nesting : Nat} {b : ByteArray}
    (h : ExactMidOffsetInvertAtV1 encode decode value nesting)
    (henc : encode value = .ok b) :
    FieldReadV1 decode b value nesting :=
  fun pre post => h b pre post henc

/-- A global inversion specializes to a field read for any produced bytes. -/
theorem FieldReadV1.ofGlobal {α : Type}
    {encode : α → Except SemanticWireErrorV1 ByteArray} {decode : Decoder α}
    {value : α} {nesting : Nat} {b : ByteArray}
    (h : MidOffsetInvertV1 encode decode) (hdepth : nesting < maxNesting)
    (henc : encode value = .ok b) :
    FieldReadV1 decode b value nesting :=
  fun pre post => h value b pre post nesting hdepth henc

/-- Field reads for every successful encoding give fixed-depth exact inversion. -/
theorem exactMidOffsetInvertAt_of_fieldReadV1 {α : Type}
    {encode : α → Except SemanticWireErrorV1 ByteArray} {decode : Decoder α}
    {value : α} {nesting : Nat}
    (h : ∀ b, encode value = .ok b → FieldReadV1 decode b value nesting) :
    ExactMidOffsetInvertAtV1 encode decode value nesting :=
  fun b left right henc => h b henc left right

/-- Field reads at every legal depth give global mid-offset inversion. -/
theorem midOffsetInvert_of_fieldReadV1 {α : Type}
    {encode : α → Except SemanticWireErrorV1 ByteArray} {decode : Decoder α}
    (h : ∀ (x : α) (b : ByteArray) (nesting : Nat), nesting < maxNesting →
      encode x = .ok b → FieldReadV1 decode b x nesting) :
    MidOffsetInvertV1 encode decode :=
  fun x b left right nesting hdepth henc => h x b nesting hdepth henc left right

/-! ### Scalar leaves -/

/-- Mid-offset decode of `encodeU8 v` (single production byte). -/
theorem decodeU8_encode_midV1 (left right : ByteArray) (v : UInt8) (nesting : Nat) :
    decodeU8 ⟨left ++ encodeU8 v ++ right, left.size, nesting⟩ =
      .ok (v, ⟨left ++ encodeU8 v ++ right, left.size + 1, nesting⟩) := by
  have hsize : (encodeU8 v).size = 1 := by
    simp [encodeU8, ByteArray.size_push, ByteArray.size_empty]
  have hget : (encodeU8 v).data[0]? = some v := by
    simp [encodeU8, ByteArray.data_push, ByteArray.data_empty]
  apply decodeU8_eq_of_readV1
  exact readByte_mid_payloadV1 left (encodeU8 v) right 0 v (by simp [hsize]) hget

theorem encodeU8_sizeV1 (v : UInt8) : (encodeU8 v).size = 1 := by
  simp [encodeU8, ByteArray.size_push, ByteArray.size_empty]

theorem fieldRead_u32V1 (v : UInt32) (nesting : Nat) :
    FieldReadV1 decodeU32le (encodeU32le v) v nesting := by
  intro pre post
  simpa [encodeU32le_sizeV1] using decodeU32le_encode_midV1 pre post v nesting

theorem fieldRead_u16V1 (v : UInt16) (nesting : Nat) :
    FieldReadV1 decodeU16le (encodeU16le v) v nesting := by
  intro pre post
  simpa [encodeU16le_sizeV1] using decodeU16le_encode_midV1 pre post v nesting

/-- Production u64le mid-offset read of `encodeU64le v`. -/
theorem readU64le_encode_midV1 (left right : ByteArray) (v : UInt64) :
    readU64leAtV1 (left ++ encodeU64le v ++ right) left.size = .ok (v, left.size + 8) := by
  have hs : (encodeU64le v).size = 8 := encodeU64le_size v
  have h0 := readByte_mid_payloadV1 left (encodeU64le v) right 0
    (UInt8.ofNat (v.toNat % 256)) (by rw [hs]; decide) (by simp [encodeU64le])
  have h1 := readByte_mid_payloadV1 left (encodeU64le v) right 1
    (UInt8.ofNat ((v.toNat / 256) % 256)) (by rw [hs]; decide) (by simp [encodeU64le])
  have h2 := readByte_mid_payloadV1 left (encodeU64le v) right 2
    (UInt8.ofNat ((v.toNat / 65536) % 256)) (by rw [hs]; decide) (by simp [encodeU64le])
  have h3 := readByte_mid_payloadV1 left (encodeU64le v) right 3
    (UInt8.ofNat ((v.toNat / 16777216) % 256)) (by rw [hs]; decide)
    (by simp [encodeU64le])
  have h4 := readByte_mid_payloadV1 left (encodeU64le v) right 4
    (UInt8.ofNat ((v.toNat / 4294967296) % 256)) (by rw [hs]; decide)
    (by simp [encodeU64le])
  have h5 := readByte_mid_payloadV1 left (encodeU64le v) right 5
    (UInt8.ofNat ((v.toNat / 1099511627776) % 256)) (by rw [hs]; decide)
    (by simp [encodeU64le])
  have h6 := readByte_mid_payloadV1 left (encodeU64le v) right 6
    (UInt8.ofNat ((v.toNat / 281474976710656) % 256)) (by rw [hs]; decide)
    (by simp [encodeU64le])
  have h7 := readByte_mid_payloadV1 left (encodeU64le v) right 7
    (UInt8.ofNat ((v.toNat / 72057594037927936) % 256)) (by rw [hs]; decide)
    (by simp [encodeU64le])
  have h0' : readByteAtV1 (left ++ encodeU64le v ++ right) left.size =
      .ok (UInt8.ofNat (v.toNat % 256)) := by simpa using h0
  unfold readU64leAtV1
  simp only [h0', h1, h2, h3, h4, h5, h6, h7, Bind.bind, Pure.pure, Except.bind,
    Except.pure, UInt8_toNat_ofNat_mod256V1]
  have hlt : v.toNat < 18446744073709551616 := v.toNat_lt_size
  have harith : (v.toNat % 256) + ((v.toNat / 256) % 256) * 256 +
      ((v.toNat / 65536) % 256) * 65536 + ((v.toNat / 16777216) % 256) * 16777216 +
      ((v.toNat / 4294967296) % 256) * 4294967296 +
      ((v.toNat / 1099511627776) % 256) * 1099511627776 +
      ((v.toNat / 281474976710656) % 256) * 281474976710656 +
      ((v.toNat / 72057594037927936) % 256) * 72057594037927936 = v.toNat := by omega
  rw [harith, UInt64.ofNat_toNat]

theorem fieldRead_u64V1 (v : UInt64) (nesting : Nat) :
    FieldReadV1 decodeU64le (encodeU64le v) v nesting := by
  intro pre post
  have h := decodeU64le_eq_of_readV1
    ⟨pre ++ encodeU64le v ++ post, pre.size, nesting⟩ v (pre.size + 8)
    (readU64le_encode_midV1 pre post v)
  simpa [encodeU64le_size] using h

theorem fieldRead_stringV1 (s : String) (b : ByteArray) (nesting : Nat)
    (henc : encodeString s = .ok b) :
    FieldReadV1 decodeString b s nesting :=
  fun pre post => decodeString_of_encodeString_okV1 pre post s b nesting henc

theorem fieldRead_byteArrayV1 (payload b : ByteArray) (nesting : Nat)
    (henc : encodeByteArray payload = .ok b) :
    FieldReadV1 (decodeByteArray maxCanonicalProgramBytes) b payload nesting :=
  fun pre post => decodeByteArray_of_encode_midV1 pre post payload b nesting henc

/-! ### Tagged framing -/

/-- The production tagged header is a field read for `expectTag`. -/
theorem fieldRead_expectTagV1 (tag : String) (fieldCount : Nat) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hcountFit : fieldCount ≤ UInt16.size - 1) :
    FieldReadV1 (expectTag tag fieldCount) (taggedHeaderBytesV1 tag fieldCount)
      () nesting := by
  intro pre post
  have h := expectTag_encode_midV1 pre ByteArray.empty tag fieldCount post nesting
    hnonempty hmax hfit hasciiBytes hcountFit
  have hbuf :
      pre ++ taggedHeaderBytesV1 tag fieldCount ++ post ++ ByteArray.empty =
        pre ++ taggedHeaderBytesV1 tag fieldCount ++ post := by
    simp
  rw [hbuf] at h
  exact h

/-- Lift a body field read through the sole tagged nesting authority. -/
theorem fieldRead_withTaggedNestingV1 {α : Type} (body : Decoder α)
    (chunk : ByteArray) (value : α) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (hbody : FieldReadV1 body chunk value (nesting + 1)) :
    FieldReadV1 (withTaggedNesting body) chunk value nesting := by
  intro pre post
  rw [withTaggedNesting_eqV1]
  simp only [hdepth, ↓reduceIte]
  rw [hbody pre post]

/-- Production `decodeFieldCount` over an encoded `u16le` count. -/
theorem decodeFieldCount_encode_midV1 (left right : ByteArray) (expected nesting : Nat)
    (hfit : expected ≤ UInt16.size - 1) :
    decodeFieldCount expected
        ⟨left ++ encodeU16le (UInt16.ofNat expected) ++ right, left.size, nesting⟩ =
      .ok ((),
        ⟨left ++ encodeU16le (UInt16.ofNat expected) ++ right, left.size + 2,
          nesting⟩) := by
  let c : Cursor :=
    ⟨left ++ encodeU16le (UInt16.ofNat expected) ++ right, left.size, nesting⟩
  have hread : readU16leAtV1 c.input c.offset =
      .ok (UInt16.ofNat expected, left.size + 2) :=
    readU16le_encode_midV1 left right (UInt16.ofNat expected)
  have h := decodeFieldCount_eq_of_readU16leV1 expected c
    (UInt16.ofNat expected) (left.size + 2) hread
  have hto : (UInt16.ofNat expected).toNat = expected :=
    Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt hfit (by decide))
  simp only [c, h, hto, beq_self_eq_true, ↓reduceIte]

/-- Split of a production tagged header into its three encoded parts. -/
theorem taggedHeaderBytesV1_eq_partsV1 (tag : String) (fieldCount : Nat) :
    taggedHeaderBytesV1 tag fieldCount =
      encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
        encodeU16le (UInt16.ofNat fieldCount) := by
  simp [taggedHeaderBytesV1, ByteArray.append_assoc]

/-- `decodeTag` over a production tagged header (sum-body entry step). -/
theorem decodeTag_taggedHeader_midV1 (pre post : ByteArray) (tag : String)
    (fieldCount nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true) :
    decodeTag ⟨pre ++ taggedHeaderBytesV1 tag fieldCount ++ post, pre.size, nesting⟩ =
      .ok (tag,
        ⟨pre ++ taggedHeaderBytesV1 tag fieldCount ++ post,
          pre.size + 4 + tag.toUTF8.size, nesting⟩) := by
  have hin :
      pre ++ taggedHeaderBytesV1 tag fieldCount ++ post =
        pre ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          (encodeU16le (UInt16.ofNat fieldCount) ++ post) := by
    simp [taggedHeaderBytesV1_eq_partsV1, ByteArray.append_assoc]
  rw [hin]
  exact decodeTag_encode_midV1 pre (encodeU16le (UInt16.ofNat fieldCount) ++ post)
    tag nesting hnonempty hmax hfit hasciiBytes hasciiTag

/-- `decodeFieldCount` immediately after the tag of a production tagged header. -/
theorem decodeFieldCount_taggedHeader_midV1 (pre post : ByteArray) (tag : String)
    (fieldCount nesting : Nat) (hcountFit : fieldCount ≤ UInt16.size - 1) :
    decodeFieldCount fieldCount
        ⟨pre ++ taggedHeaderBytesV1 tag fieldCount ++ post,
          pre.size + 4 + tag.toUTF8.size, nesting⟩ =
      .ok ((),
        ⟨pre ++ taggedHeaderBytesV1 tag fieldCount ++ post,
          pre.size + (taggedHeaderBytesV1 tag fieldCount).size, nesting⟩) := by
  have hin :
      pre ++ taggedHeaderBytesV1 tag fieldCount ++ post =
        (pre ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
          encodeU16le (UInt16.ofNat fieldCount) ++ post := by
    simp [taggedHeaderBytesV1_eq_partsV1, ByteArray.append_assoc]
  have hsz :
      (pre ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8).size =
        pre.size + 4 + tag.toUTF8.size := by
    simp [ByteArray.size_append, encodeU32le_sizeV1]
  have h := decodeFieldCount_encode_midV1
    (pre ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) post fieldCount
    nesting hcountFit
  rw [hsz] at h
  rw [hin]
  have hoff : pre.size + 4 + tag.toUTF8.size + 2 =
      pre.size + (taggedHeaderBytesV1 tag fieldCount).size := by
    rw [taggedHeaderBytesV1_size]; omega
  rw [← hoff]
  exact h

/-- `decodeTag` of a production tagged header located inside a larger buffer. -/
theorem decodeTag_header_readV1 (buf : ByteArray) (off : Nat) (pre post : ByteArray)
    (tag : String) (fieldCount nesting : Nat)
    (hbuf : buf = pre ++ taggedHeaderBytesV1 tag fieldCount ++ post)
    (hoff : off = pre.size)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true) :
    decodeTag ⟨buf, off, nesting⟩ =
      .ok (tag, ⟨buf, pre.size + 4 + tag.toUTF8.size, nesting⟩) := by
  subst hbuf
  subst hoff
  exact decodeTag_taggedHeader_midV1 pre post tag fieldCount nesting hnonempty hmax
    hfit hasciiBytes hasciiTag

/-- `decodeFieldCount` of a production tagged header inside a larger buffer. -/
theorem decodeFieldCount_header_readV1 (buf : ByteArray) (off : Nat)
    (pre post : ByteArray) (tag : String) (fieldCount nesting : Nat)
    (hbuf : buf = pre ++ taggedHeaderBytesV1 tag fieldCount ++ post)
    (hoff : off = pre.size + 4 + tag.toUTF8.size)
    (hcountFit : fieldCount ≤ UInt16.size - 1) :
    decodeFieldCount fieldCount ⟨buf, off, nesting⟩ =
      .ok ((), ⟨buf, pre.size + (taggedHeaderBytesV1 tag fieldCount).size, nesting⟩) := by
  subst hbuf
  subst hoff
  exact decodeFieldCount_taggedHeader_midV1 pre post tag fieldCount nesting hcountFit

/-! ### Tagged encode inversion by arity -/

/-- Inversion of a successful `Except` bind: the prefix succeeded. -/
theorem except_bind_ok_inversionV1 {ε α β : Type} (e : Except ε α)
    (f : α → Except ε β) (b : β) (h : (e >>= f) = .ok b) :
    ∃ a, e = .ok a ∧ f a = .ok b := by
  cases e with
  | error err => simp only [Bind.bind, Except.bind] at h; cases h
  | ok a => exact ⟨a, rfl, h⟩

theorem encodeTagged_ok_eq_one_fieldV1 (tag : String) (f0 b : ByteArray)
    (h : encodeTagged tag #[f0] = .ok b) :
    b = taggedHeaderBytesV1 tag 1 ++ f0 := by
  rw [(encodeTagged_ok_eq_taggedBytesV1 tag #[f0] b h).1, taggedBytes_one_field]

theorem encodeTagged_ok_eq_two_fieldsV1 (tag : String) (f0 f1 b : ByteArray)
    (h : encodeTagged tag #[f0, f1] = .ok b) :
    b = taggedHeaderBytesV1 tag 2 ++ f0 ++ f1 := by
  rw [(encodeTagged_ok_eq_taggedBytesV1 tag #[f0, f1] b h).1,
    taggedBytes_two_fields_fields]

theorem encodeTagged_ok_eq_three_fieldsV1 (tag : String) (f0 f1 f2 b : ByteArray)
    (h : encodeTagged tag #[f0, f1, f2] = .ok b) :
    b = taggedHeaderBytesV1 tag 3 ++ f0 ++ f1 ++ f2 := by
  rw [(encodeTagged_ok_eq_taggedBytesV1 tag #[f0, f1, f2] b h).1,
    taggedBytes_three_fields]

theorem encodeTagged_ok_eq_four_fieldsV1 (tag : String) (f0 f1 f2 f3 b : ByteArray)
    (h : encodeTagged tag #[f0, f1, f2, f3] = .ok b) :
    b = taggedHeaderBytesV1 tag 4 ++ f0 ++ f1 ++ f2 ++ f3 := by
  rw [(encodeTagged_ok_eq_taggedBytesV1 tag #[f0, f1, f2, f3] b h).1,
    taggedBytes_four_fields]

/-! ### Option -/

theorem fieldRead_option_noneV1 {α : Type} (dec : Decoder α) (nesting : Nat) :
    FieldReadV1 (decodeOption dec) (encodeU8 0) none nesting := by
  intro pre post
  have hmarker := decodeU8_encode_midV1 pre post 0 nesting
  have h := decodeOption_noneV1 dec ⟨pre ++ encodeU8 0 ++ post, pre.size, nesting⟩
    ⟨pre ++ encodeU8 0 ++ post, pre.size + 1, nesting⟩ hmarker
  simpa [encodeU8_sizeV1] using h

theorem fieldRead_option_someV1 {α : Type} (dec : Decoder α) (payload : ByteArray)
    (value : α) (nesting : Nat) (h : FieldReadV1 dec payload value nesting) :
    FieldReadV1 (decodeOption dec) (encodeU8 1 ++ payload) (some value) nesting := by
  intro pre post
  have hmarker :
      decodeU8 ⟨pre ++ (encodeU8 1 ++ payload) ++ post, pre.size, nesting⟩ =
        .ok (1, ⟨pre ++ (encodeU8 1 ++ payload) ++ post, pre.size + 1, nesting⟩) := by
    have h1 := decodeU8_encode_midV1 pre (payload ++ post) 1 nesting
    have hbuf : pre ++ encodeU8 1 ++ (payload ++ post) =
        pre ++ (encodeU8 1 ++ payload) ++ post := by
      simp [ByteArray.append_assoc]
    simpa [hbuf, encodeU8_sizeV1] using h1
  have hvalue :
      dec ⟨pre ++ (encodeU8 1 ++ payload) ++ post, pre.size + 1, nesting⟩ =
        .ok (value, ⟨pre ++ (encodeU8 1 ++ payload) ++ post,
          pre.size + 1 + payload.size, nesting⟩) := by
    refine h.read _ _ (pre ++ encodeU8 1) post ?_ ?_
    · simp [ByteArray.append_assoc]
    · simp [ByteArray.size_append, encodeU8_sizeV1]
  have hres := decodeOption_someV1 dec
    ⟨pre ++ (encodeU8 1 ++ payload) ++ post, pre.size, nesting⟩
    ⟨pre ++ (encodeU8 1 ++ payload) ++ post, pre.size + 1, nesting⟩
    ⟨pre ++ (encodeU8 1 ++ payload) ++ post, pre.size + 1 + payload.size, nesting⟩
    value hmarker hvalue
  have hsz : pre.size + 1 + payload.size =
      pre.size + (encodeU8 1 ++ payload).size := by
    simp [ByteArray.size_append, encodeU8_sizeV1]
    omega
  rw [hsz] at hres
  exact hres

/-- Field read for the production `encodeOption` of any successful payload. -/
theorem fieldRead_optionV1 {α : Type}
    (encode : α → Except SemanticWireErrorV1 ByteArray) (dec : Decoder α)
    (value : Option α) (b : ByteArray) (nesting : Nat)
    (henc : encodeOption encode value = .ok b)
    (hpayload : ∀ (x : α) (payload : ByteArray), value = some x →
      encode x = .ok payload → FieldReadV1 dec payload x nesting) :
    FieldReadV1 (decodeOption dec) b value nesting := by
  cases value with
  | none =>
      have hb : b = encodeU8 0 := by
        simpa [encodeOption, Pure.pure, Except.pure] using henc.symm
      subst hb
      exact fieldRead_option_noneV1 dec nesting
  | some x =>
      cases hx : encode x with
      | error e =>
          simp [encodeOption, hx, Bind.bind, Except.bind] at henc
      | ok payload =>
          have hb : b = encodeU8 1 ++ payload := by
            have := henc
            simp only [encodeOption, hx, Bind.bind, Pure.pure, Except.bind,
              Except.pure] at this
            exact (Except.ok.inj this).symm
          subst hb
          exact fieldRead_option_someV1 dec payload x nesting
            (hpayload x payload rfl hx)

/-- Field read for the production `encodeOption` of a total (pure) payload
    encoder. -/
theorem fieldRead_option_pureV1 {α : Type} (enc : α → ByteArray) (dec : Decoder α)
    (value : Option α) (b : ByteArray) (nesting : Nat)
    (henc : encodeOption (fun x => pure (enc x)) value = .ok b)
    (hleaf : ∀ x, FieldReadV1 dec (enc x) x nesting) :
    FieldReadV1 (decodeOption dec) b value nesting := by
  refine fieldRead_optionV1 _ dec value b nesting henc ?_
  intro x payload _ hp
  have hpay : payload = enc x := (Except.ok.inj hp).symm
  subst hpay
  exact hleaf x

/-! ### SchemaId -/

/-- The production SchemaId codec inverts: `renderSchemaId` emits the validated
    `value` and `parseSchemaId` re-validates it. -/
theorem fieldRead_schemaIdV1 (schema : SchemaId) (b : ByteArray) (nesting : Nat)
    (henc : encodeSchemaId schema = .ok b) :
    FieldReadV1 decodeSchemaId b schema nesting := by
  have hrender : ∃ s, renderSchemaId schema = .ok s ∧ encodeString s = .ok b := by
    cases hr : renderSchemaId schema with
    | error e =>
        simp [encodeSchemaId, hr, mapCommon, Bind.bind, Except.bind] at henc
    | ok s =>
        refine ⟨s, rfl, ?_⟩
        simpa [encodeSchemaId, hr, mapCommon, Bind.bind, Except.bind] using henc
  obtain ⟨s, hr, hstr⟩ := hrender
  have hvalidate : validateSchemaId schema = .ok () := by
    cases hv : validateSchemaId schema with
    | error e => simp [renderSchemaId, hv, Bind.bind, Except.bind] at hr
    | ok u => cases u; rfl
  have hvalue : s = schema.value := by
    have := hr
    simp only [renderSchemaId, hvalidate, Bind.bind, Pure.pure, Except.bind,
      Except.pure] at this
    exact (Except.ok.inj this).symm
  subst hvalue
  have hparse : parseSchemaId schema.value = .ok schema := by
    simp only [parseSchemaId, hvalidate, Bind.bind, Pure.pure, Except.bind,
      Except.pure]
  intro pre post
  have hread := fieldRead_stringV1 schema.value b nesting hstr pre post
  simp only [decodeSchemaId, hread, hparse, Bind.bind, Pure.pure, Except.bind,
    Except.pure]

/-! ### Arrays -/

/-- Every element of a successful chunk run encodes successfully. -/
theorem encodeArrayChunksV1_forall_ok_of_okV1 {α : Type}
    (encode : α → Except SemanticWireErrorV1 ByteArray) :
    ∀ (xs : List α) (acc payload : ByteArray),
      encodeArrayChunksV1 encode xs acc = .ok payload →
      ∀ x ∈ xs, ∃ eb, encode x = .ok eb := by
  intro xs
  induction xs with
  | nil => intro _ _ _ x hx; cases hx
  | cons y ys ih =>
      intro acc payload hc x hx
      cases hy : encode y with
      | error e => simp [encodeArrayChunksV1, hy, Bind.bind, Except.bind] at hc
      | ok chunk =>
          have htail : encodeArrayChunksV1 encode ys (acc.append chunk) = .ok payload := by
            simpa [encodeArrayChunksV1, hy, Bind.bind, Except.bind] using hc
          cases hx with
          | head => exact ⟨chunk, hy⟩
          | tail _ hmem => exact ih (acc.append chunk) payload htail x hmem

/-- Inversion of a successful production array encode: the element count is
    within the shared array bound and every element encoded successfully. -/
theorem encodeArray_ok_inversionV1 {α : Type}
    (encode : α → Except SemanticWireErrorV1 ByteArray) (values : Array α)
    (b : ByteArray) (h : encodeArray encode values = .ok b) :
    values.size ≤ maxArrayElements ∧ ∀ x ∈ values.toList, ∃ eb, encode x = .ok eb := by
  have hsize : values.size ≤ maxArrayElements := by
    by_cases hs : values.size ≤ maxArrayElements
    · exact hs
    · simp [encodeArray, hs, err, Bind.bind, Except.bind] at h
  refine ⟨hsize, ?_⟩
  cases hc : encodeArrayChunksV1 encode values.toList ByteArray.empty with
  | error e =>
      exfalso
      simp only [encodeArray, hc, Bind.bind, Except.bind, Pure.pure, Except.pure,
        hsize, ↓reduceIte] at h
      split at h <;> cases h
  | ok payload =>
      exact encodeArrayChunksV1_forall_ok_of_okV1 encode values.toList
        ByteArray.empty payload hc

/-- Field read for the production array codec from element field reads. -/
theorem fieldRead_arrayV1 {α : Type}
    (encode : α → Except SemanticWireErrorV1 ByteArray) (dec : Decoder α)
    (maxCount : Nat) (values : Array α) (b : ByteArray) (nesting : Nat)
    (hmax : values.size ≤ maxCount)
    (hmaxArray : maxCount ≤ maxArrayElements)
    (hsizeU32 : values.size ≤ UInt32.size - 1)
    (hencElems : ∀ x ∈ values.toList, ∃ eb, encode x = .ok eb)
    (helem : ∀ x ∈ values.toList, ExactMidOffsetInvertAtV1 encode dec x nesting)
    (henc : encodeArray encode values = .ok b) :
    FieldReadV1 (decodeArray maxCount dec) b values nesting :=
  fun pre post =>
    exactMidOffsetInvertAt_array_of_forall_encoded_exactAt encode dec maxCount
      values nesting hmax hmaxArray hsizeU32 hencElems helem b pre post henc

/-- Field read for the production array codec with a total (pure) element
    encoder. -/
theorem fieldRead_pureArrayV1 {α : Type} (enc : α → ByteArray) (dec : Decoder α)
    (values : Array α) (b : ByteArray) (nesting : Nat)
    (hleaf : ∀ x, FieldReadV1 dec (enc x) x nesting)
    (henc : encodeArray (fun x => pure (enc x)) values = .ok b) :
    FieldReadV1 (decodeArray maxArrayElements dec) b values nesting := by
  obtain ⟨hsize, _⟩ := encodeArray_ok_inversionV1 _ values b henc
  refine fieldRead_arrayV1 _ dec maxArrayElements values b nesting hsize
    (Nat.le_refl _) (Nat.le_trans hsize (by decide)) ?_ ?_ henc
  · intro x _
    exact ⟨enc x, rfl⟩
  · intro x _
    refine exactMidOffsetInvertAt_of_fieldReadV1 ?_
    intro eb hx
    have hb : eb = enc x := (Except.ok.inj hx).symm
    subst hb
    exact hleaf x

end ProofForgeV2.Semantic.WireV1
