import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.CodecV1

/-!
  ProofForgeV2.Semantic.Wire.CodecRoundtripV1 — reusable encode→decode
  transport composition lemmas for Semantic wire (B-SC-DEC foundation).

  Purpose: replace per-program 1k-line fixture decode scripts with parametric
  spine constructors and mid-offset refinements over transparent List spines.

  Scope (this slice):
    * mid-offset List get / single-byte / u16 / u32 spine reads
    * fixed small LE values used by SimpleClosure (0/1/2/3/4/9/64)
    * array-count header success from a u32le spine
    * sized UTF-8/ASCII string decode composition (NFC via isAscii)
    * option none/some marker composition
    * nullary/fixed tagged header composition
    * root framing glue already in WireV1 (`decodeSemanticProgramDataV1_eq_of_framing`)

  Explicitly out of scope here:
    * full generic `encodeSemanticProgramDataV1 data = .ok bytes →
      decodeSemanticProgramDataV1 bytes = .ok data` for arbitrary data
      (needs inductive field-level roundtrips across every record family)
    * structure gate / re-encode identity (B-SC-STRUCT / carrier)
    * name grammar / NFC non-ASCII tables

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Unicode

/-! ### Mid-offset transparent-spine byte access -/

/-- Exact single-byte membership of a mid-offset cons cell. -/
theorem list_getElem?_midV1 (left : List UInt8) (b : UInt8) (right : List UInt8) :
    (left ++ b :: right)[left.length]? = some b := by
  rw [List.getElem?_append_right (Nat.le_refl _)]
  simp

/-- Production transparent single-byte read at a mid offset. -/
theorem readSpineByteV1_of_mid (left right : List UInt8) (b : UInt8) :
    readSpineByteV1 (left ++ b :: right) left.length = .ok b := by
  unfold readSpineByteV1
  rw [list_getElem?_midV1]

/-- Rewrite a four-byte mid slice into cons form for successive mid reads. -/
theorem list_mid_four_eq_cons (left right : List UInt8) (b0 b1 b2 b3 : UInt8) :
    left ++ [b0, b1, b2, b3] ++ right =
      left ++ b0 :: b1 :: b2 :: b3 :: right := by
  simp

/-- Little-endian u32 mid-offset read from four fixed payload bytes. -/
theorem readSpineU32leV1_of_four_bytes
    (left right : List UInt8) (b0 b1 b2 b3 : UInt8) (value : UInt32)
    (hval :
      UInt32.ofNat
          (b0.toNat + b1.toNat * 256 + b2.toNat * 65536 + b3.toNat * 16777216) =
        value) :
    readSpineU32leV1 (left ++ [b0, b1, b2, b3] ++ right) left.length =
      .ok (value, left.length + 4) := by
  have h0 :
      readSpineByteV1 (left ++ [b0, b1, b2, b3] ++ right) left.length = .ok b0 := by
    rw [list_mid_four_eq_cons]
    exact readSpineByteV1_of_mid left (b1 :: b2 :: b3 :: right) b0
  have h1 :
      readSpineByteV1 (left ++ [b0, b1, b2, b3] ++ right) (left.length + 1) =
        .ok b1 := by
    have eq : left ++ [b0, b1, b2, b3] ++ right =
        (left ++ [b0]) ++ b1 :: b2 :: b3 :: right := by simp
    have len : (left ++ [b0]).length = left.length + 1 := by simp
    rw [eq, ← len]
    exact readSpineByteV1_of_mid (left ++ [b0]) (b2 :: b3 :: right) b1
  have h2 :
      readSpineByteV1 (left ++ [b0, b1, b2, b3] ++ right) (left.length + 2) =
        .ok b2 := by
    have eq : left ++ [b0, b1, b2, b3] ++ right =
        (left ++ [b0, b1]) ++ b2 :: b3 :: right := by simp
    have len : (left ++ [b0, b1]).length = left.length + 2 := by simp
    rw [eq, ← len]
    exact readSpineByteV1_of_mid (left ++ [b0, b1]) (b3 :: right) b2
  have h3 :
      readSpineByteV1 (left ++ [b0, b1, b2, b3] ++ right) (left.length + 3) =
        .ok b3 := by
    have eq : left ++ [b0, b1, b2, b3] ++ right =
        (left ++ [b0, b1, b2]) ++ b3 :: right := by simp
    have len : (left ++ [b0, b1, b2]).length = left.length + 3 := by simp
    rw [eq, ← len]
    exact readSpineByteV1_of_mid (left ++ [b0, b1, b2]) right b3
  unfold readSpineU32leV1
  simp only [h0, h1, h2, h3, Bind.bind, Pure.pure, Except.bind, Except.pure, hval]

/-- Little-endian u16 mid-offset read from two fixed payload bytes. -/
theorem readSpineU16leV1_of_two_bytes
    (left right : List UInt8) (b0 b1 : UInt8) (value : UInt16)
    (hval : UInt16.ofNat (b0.toNat + b1.toNat * 256) = value) :
    readSpineU16leV1 (left ++ [b0, b1] ++ right) left.length =
      .ok (value, left.length + 2) := by
  have h0 :
      readSpineByteV1 (left ++ [b0, b1] ++ right) left.length = .ok b0 := by
    have eq : left ++ [b0, b1] ++ right = left ++ b0 :: b1 :: right := by simp
    rw [eq]
    exact readSpineByteV1_of_mid left (b1 :: right) b0
  have h1 :
      readSpineByteV1 (left ++ [b0, b1] ++ right) (left.length + 1) = .ok b1 := by
    have eq : left ++ [b0, b1] ++ right = (left ++ [b0]) ++ b1 :: right := by simp
    have len : (left ++ [b0]).length = left.length + 1 := by simp
    rw [eq, ← len]
    exact readSpineByteV1_of_mid (left ++ [b0]) right b1
  unfold readSpineU16leV1
  simp only [h0, h1, Bind.bind, Pure.pure, Except.bind, Except.pure, hval]

/-! ### Fixed LE spines used by SimpleClosure / wire tables -/

/-- Transparent spine for `encodeU32le 0`. -/
def u32leSpine0V1 : TransparentByteSpineV1 := [0, 0, 0, 0]

/-- Transparent spine for `encodeU32le 1`. -/
def u32leSpine1V1 : TransparentByteSpineV1 := [1, 0, 0, 0]

/-- Transparent spine for `encodeU32le 2`. -/
def u32leSpine2V1 : TransparentByteSpineV1 := [2, 0, 0, 0]

/-- Transparent spine for `encodeU32le 3`. -/
def u32leSpine3V1 : TransparentByteSpineV1 := [3, 0, 0, 0]

/-- Transparent spine for `encodeU32le 4`. -/
def u32leSpine4V1 : TransparentByteSpineV1 := [4, 0, 0, 0]

/-- Transparent spine for `encodeU32le 9` (SemanticProgram.Data field count path). -/
def u32leSpine9V1 : TransparentByteSpineV1 := [9, 0, 0, 0]

/-- Transparent spine for `encodeU16le 0`. -/
def u16leSpine0V1 : TransparentByteSpineV1 := [0, 0]

/-- Transparent spine for `encodeU16le 1`. -/
def u16leSpine1V1 : TransparentByteSpineV1 := [1, 0]

/-- Transparent spine for `encodeU16le 2`. -/
def u16leSpine2V1 : TransparentByteSpineV1 := [2, 0]

/-- Transparent spine for `encodeU16le 3`. -/
def u16leSpine3V1 : TransparentByteSpineV1 := [3, 0]

/-- Transparent spine for `encodeU16le 4`. -/
def u16leSpine4V1 : TransparentByteSpineV1 := [4, 0]

/-- Transparent spine for `encodeU16le 9`. -/
def u16leSpine9V1 : TransparentByteSpineV1 := [9, 0]

/-- Transparent spine for `encodeU16le 64` (UInt64 width). -/
def u16leSpine64V1 : TransparentByteSpineV1 := [64, 0]

theorem encodeU32le_0_eq_spine : encodeU32le 0 = ByteArray.mk u32leSpine0V1.toArray := by
  rfl

theorem encodeU32le_1_eq_spine : encodeU32le 1 = ByteArray.mk u32leSpine1V1.toArray := by
  rfl

theorem encodeU32le_2_eq_spine : encodeU32le 2 = ByteArray.mk u32leSpine2V1.toArray := by
  rfl

theorem encodeU16le_0_eq_spine : encodeU16le 0 = ByteArray.mk u16leSpine0V1.toArray := by
  rfl

theorem encodeU16le_1_eq_spine : encodeU16le 1 = ByteArray.mk u16leSpine1V1.toArray := by
  rfl

theorem encodeU16le_64_eq_spine : encodeU16le 64 = ByteArray.mk u16leSpine64V1.toArray := by
  rfl

theorem encodeU8_eq_mk (v : UInt8) : encodeU8 v = ByteArray.mk #[v] := by
  rfl

/-! ### Fixed-value mid-offset u32/u16 reads -/

theorem readSpineU32leV1_zero_mid (left right : List UInt8) :
    readSpineU32leV1 (left ++ u32leSpine0V1 ++ right) left.length =
      .ok (0, left.length + 4) := by
  apply readSpineU32leV1_of_four_bytes
  simp

theorem readSpineU32leV1_one_mid (left right : List UInt8) :
    readSpineU32leV1 (left ++ u32leSpine1V1 ++ right) left.length =
      .ok (1, left.length + 4) := by
  apply readSpineU32leV1_of_four_bytes
  simp

theorem readSpineU32leV1_two_mid (left right : List UInt8) :
    readSpineU32leV1 (left ++ u32leSpine2V1 ++ right) left.length =
      .ok (2, left.length + 4) := by
  apply readSpineU32leV1_of_four_bytes
  simp

theorem readSpineU32leV1_three_mid (left right : List UInt8) :
    readSpineU32leV1 (left ++ u32leSpine3V1 ++ right) left.length =
      .ok (3, left.length + 4) := by
  apply readSpineU32leV1_of_four_bytes
  simp

theorem readSpineU32leV1_four_mid (left right : List UInt8) :
    readSpineU32leV1 (left ++ u32leSpine4V1 ++ right) left.length =
      .ok (4, left.length + 4) := by
  apply readSpineU32leV1_of_four_bytes
  simp

theorem readSpineU16leV1_zero_mid (left right : List UInt8) :
    readSpineU16leV1 (left ++ u16leSpine0V1 ++ right) left.length =
      .ok (0, left.length + 2) := by
  apply readSpineU16leV1_of_two_bytes
  simp

theorem readSpineU16leV1_one_mid (left right : List UInt8) :
    readSpineU16leV1 (left ++ u16leSpine1V1 ++ right) left.length =
      .ok (1, left.length + 2) := by
  apply readSpineU16leV1_of_two_bytes
  simp

theorem readSpineU16leV1_two_mid (left right : List UInt8) :
    readSpineU16leV1 (left ++ u16leSpine2V1 ++ right) left.length =
      .ok (2, left.length + 2) := by
  apply readSpineU16leV1_of_two_bytes
  simp

theorem readSpineU16leV1_three_mid (left right : List UInt8) :
    readSpineU16leV1 (left ++ u16leSpine3V1 ++ right) left.length =
      .ok (3, left.length + 2) := by
  apply readSpineU16leV1_of_two_bytes
  simp

theorem readSpineU16leV1_four_mid (left right : List UInt8) :
    readSpineU16leV1 (left ++ u16leSpine4V1 ++ right) left.length =
      .ok (4, left.length + 2) := by
  apply readSpineU16leV1_of_two_bytes
  simp

theorem readSpineU16leV1_nine_mid (left right : List UInt8) :
    readSpineU16leV1 (left ++ u16leSpine9V1 ++ right) left.length =
      .ok (9, left.length + 2) := by
  apply readSpineU16leV1_of_two_bytes
  simp

theorem readSpineU16leV1_64_mid (left right : List UInt8) :
    readSpineU16leV1 (left ++ u16leSpine64V1 ++ right) left.length =
      .ok (64, left.length + 2) := by
  apply readSpineU16leV1_of_two_bytes
  simp

/-! ### Array-count header from u32le mid spines -/

/-- Zero-count array header at a mid offset (any maxCount ≥ 0). -/
theorem readArrayCountSpineV1_zero_mid (left right : List UInt8) (maxCount : Nat) :
    readArrayCountSpineV1 (left ++ u32leSpine0V1 ++ right) left.length maxCount =
      .ok (0, left.length + 4) := by
  simp only [readArrayCountSpineV1, readSpineU32leV1_zero_mid left right,
    UInt32.toNat_ofNat, Nat.zero_mod]
  have hle : ¬(0 > maxCount) := Nat.not_lt.mpr (Nat.zero_le _)
  simp only [hle, ↓reduceIte]

/-- One-count array header at a mid offset (requires maxCount ≥ 1). -/
theorem readArrayCountSpineV1_one_mid (left right : List UInt8) (maxCount : Nat)
    (hmax : 1 ≤ maxCount) :
    readArrayCountSpineV1 (left ++ u32leSpine1V1 ++ right) left.length maxCount =
      .ok (1, left.length + 4) := by
  simp only [readArrayCountSpineV1, readSpineU32leV1_one_mid left right]
  have hfit : (1 : UInt32).toNat = 1 := rfl
  simp only [hfit]
  have hle : ¬(1 > maxCount) := Nat.not_lt.mpr hmax
  simp only [hle, ↓reduceIte]

/-- Two-count array header at a mid offset (requires maxCount ≥ 2). -/
theorem readArrayCountSpineV1_two_mid (left right : List UInt8) (maxCount : Nat)
    (hmax : 2 ≤ maxCount) :
    readArrayCountSpineV1 (left ++ u32leSpine2V1 ++ right) left.length maxCount =
      .ok (2, left.length + 4) := by
  simp only [readArrayCountSpineV1, readSpineU32leV1_two_mid left right]
  have hfit : (2 : UInt32).toNat = 2 := rfl
  simp only [hfit]
  have hle : ¬(2 > maxCount) := Nat.not_lt.mpr hmax
  simp only [hle, ↓reduceIte]

/-- Production array-count refinement of the zero mid-offset spine. -/
theorem readArrayCountAtV1_zero_mid (left right : List UInt8) (maxCount : Nat) :
    readArrayCountAtV1
        (ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray) left.length maxCount =
      .ok (0, left.length + 4) := by
  rw [readArrayCountAtV1_refinesSpine]
  exact readArrayCountSpineV1_zero_mid left right maxCount

/-- Production array-count refinement of the one mid-offset spine. -/
theorem readArrayCountAtV1_one_mid (left right : List UInt8) (maxCount : Nat)
    (hmax : 1 ≤ maxCount) :
    readArrayCountAtV1
        (ByteArray.mk (left ++ u32leSpine1V1 ++ right).toArray) left.length maxCount =
      .ok (1, left.length + 4) := by
  rw [readArrayCountAtV1_refinesSpine]
  exact readArrayCountSpineV1_one_mid left right maxCount hmax

/-- Production array-count refinement of the two mid-offset spine. -/
theorem readArrayCountAtV1_two_mid (left right : List UInt8) (maxCount : Nat)
    (hmax : 2 ≤ maxCount) :
    readArrayCountAtV1
        (ByteArray.mk (left ++ u32leSpine2V1 ++ right).toArray) left.length maxCount =
      .ok (2, left.length + 4) := by
  rw [readArrayCountAtV1_refinesSpine]
  exact readArrayCountSpineV1_two_mid left right maxCount hmax

/-! ### Empty-array decoder success (zero count, no element calls) -/

/-- Empty array decode through production zero-count mid-offset header. -/
theorem decodeArray_zero_midV1 (maxCount : Nat) (decode : Decoder α)
    (left right : List UInt8) (nesting : Nat) :
    decodeArray maxCount decode
        ⟨ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray, left.length, nesting⟩ =
      .ok (#[],
        ⟨ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray,
          left.length + 4, nesting⟩) := by
  apply decodeArray_zeroV1
  exact readArrayCountAtV1_zero_mid left right maxCount

/-! ### Option marker mid-offset -/

theorem readSpineByteV1_zero_mid (left right : List UInt8) :
    readSpineByteV1 (left ++ (0 : UInt8) :: right) left.length = .ok 0 :=
  readSpineByteV1_of_mid left right 0

theorem readSpineByteV1_one_mid (left right : List UInt8) :
    readSpineByteV1 (left ++ (1 : UInt8) :: right) left.length = .ok 1 :=
  readSpineByteV1_of_mid left right 1

theorem decodeU8_zero_mid (left right : List UInt8) (nesting : Nat) :
    decodeU8 ⟨ByteArray.mk (left ++ (0 : UInt8) :: right).toArray, left.length, nesting⟩ =
      .ok (0, ⟨ByteArray.mk (left ++ (0 : UInt8) :: right).toArray,
        left.length + 1, nesting⟩) := by
  apply decodeU8_eq_of_readV1
  change readByteAtV1 (ByteArray.mk (left ++ (0 : UInt8) :: right).toArray) left.length =
    .ok 0
  rw [readByteAtV1_refinesSpine, readSpineByteV1_zero_mid]

theorem decodeU8_one_mid (left right : List UInt8) (nesting : Nat) :
    decodeU8 ⟨ByteArray.mk (left ++ (1 : UInt8) :: right).toArray, left.length, nesting⟩ =
      .ok (1, ⟨ByteArray.mk (left ++ (1 : UInt8) :: right).toArray,
        left.length + 1, nesting⟩) := by
  apply decodeU8_eq_of_readV1
  change readByteAtV1 (ByteArray.mk (left ++ (1 : UInt8) :: right).toArray) left.length =
    .ok 1
  rw [readByteAtV1_refinesSpine, readSpineByteV1_one_mid]

/-- Option.none composition at a mid-offset 0 marker. -/
theorem decodeOption_none_midV1 (decode : Decoder α)
    (left right : List UInt8) (nesting : Nat) :
    decodeOption decode
        ⟨ByteArray.mk (left ++ (0 : UInt8) :: right).toArray, left.length, nesting⟩ =
      .ok (none,
        ⟨ByteArray.mk (left ++ (0 : UInt8) :: right).toArray, left.length + 1, nesting⟩) := by
  exact decodeOption_noneV1 decode _ _
    (decodeU8_zero_mid left right nesting)

/-! ### Sized ASCII string mid-offset composition -/

/-- Transparent length-prefixed raw payload spine (u32le length + raw). -/
def sizedBytesSpineV1 (raw : TransparentByteSpineV1) : TransparentByteSpineV1 :=
  encodeU32leSpineOfNatV1 raw.length ++ raw
where
  /-- Local LE u32 of a Nat known to fit (caller gate). -/
  encodeU32leSpineOfNatV1 (n : Nat) : TransparentByteSpineV1 :=
    [UInt8.ofNat (n % 256), UInt8.ofNat ((n / 256) % 256),
     UInt8.ofNat ((n / 65536) % 256), UInt8.ofNat ((n / 16777216) % 256)]

/-- Exact take of a mid-offset payload when the length header equals `raw.length`. -/
theorem takeSpineBytesV1_of_mid_exact
    (left raw right : List UInt8) :
    takeSpineBytesV1 (left ++ raw ++ right) left.length raw.length = .ok raw := by
  unfold takeSpineBytesV1 spineRemainingV1
  have hlen : raw.length ≤ (left ++ raw ++ right).length - left.length := by
    simp [List.length_append]
  have hassoc : left ++ raw ++ right = left ++ (raw ++ right) := by
    simp [List.append_assoc]
  have hdrop :
      ((left ++ raw ++ right).drop left.length).take raw.length = raw := by
    rw [hassoc, List.drop_left, List.take_left]
  simp only [if_pos hlen, hdrop]

/-- ASCII string decode through sole sized-byte + UTF-8 + NFC authorities.
    Caller supplies the production sized-byte success and UTF-8 identity. -/
theorem decodeString_ascii_of_sizedV1
    (c : Cursor) (raw : ByteArray) (offset : Nat) (value : String)
    (hread : readSizedBytesAtV1 c.input c.offset maxStringBytes = .ok (raw, offset))
    (hutf8 : String.fromUTF8? raw = some value)
    (hascii : isAscii value = true) :
    decodeString c = .ok (value, ⟨c.input, offset, c.nesting⟩) :=
  decodeString_eq_of_valueV1 c raw offset value hread hutf8
    (requireNfc_eq_ok_of_isAscii value hascii)

/-! ### Spine append / length helpers (encode/decode certificates share these) -/

/-- Append identity for transparent spines. -/
theorem appendSpineBytesV1 (left right : TransparentByteSpineV1) :
    (ByteArray.mk left.toArray).append (ByteArray.mk right.toArray) =
      ByteArray.mk (left ++ right).toArray := by
  apply ByteArray.ext
  simp [ByteArray.append]

/-- Length of a mid-offset concatenation. -/
theorem length_mid_append (left mid right : List UInt8) :
    (left ++ mid ++ right).length = left.length + mid.length + right.length := by
  simp [List.length_append, Nat.add_assoc]

/-- Decode u32le at mid-offset through production cursor (zero). -/
theorem decodeU32le_zero_mid (left right : List UInt8) (nesting : Nat) :
    decodeU32le
        ⟨ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray, left.length, nesting⟩ =
      .ok (0,
        ⟨ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray,
          left.length + 4, nesting⟩) := by
  apply decodeU32le_eq_of_readV1
  change readU32leAtV1 (ByteArray.mk (left ++ u32leSpine0V1 ++ right).toArray)
      left.length = .ok (0, left.length + 4)
  rw [readU32leAtV1_refinesSpine, readSpineU32leV1_zero_mid]

/-- Decode u32le at mid-offset through production cursor (one). -/
theorem decodeU32le_one_mid (left right : List UInt8) (nesting : Nat) :
    decodeU32le
        ⟨ByteArray.mk (left ++ u32leSpine1V1 ++ right).toArray, left.length, nesting⟩ =
      .ok (1,
        ⟨ByteArray.mk (left ++ u32leSpine1V1 ++ right).toArray,
          left.length + 4, nesting⟩) := by
  apply decodeU32le_eq_of_readV1
  change readU32leAtV1 (ByteArray.mk (left ++ u32leSpine1V1 ++ right).toArray)
      left.length = .ok (1, left.length + 4)
  rw [readU32leAtV1_refinesSpine, readSpineU32leV1_one_mid]

/-- Decode u16le field-count 0 at mid-offset. -/
theorem decodeFieldCount_zero_mid (left right : List UInt8) (nesting : Nat) :
    decodeFieldCount 0
        ⟨ByteArray.mk (left ++ u16leSpine0V1 ++ right).toArray, left.length, nesting⟩ =
      .ok ((),
        ⟨ByteArray.mk (left ++ u16leSpine0V1 ++ right).toArray,
          left.length + 2, nesting⟩) := by
  have hread :
      readU16leAtV1 (ByteArray.mk (left ++ u16leSpine0V1 ++ right).toArray)
        left.length = .ok (0, left.length + 2) := by
    rw [readU16leAtV1_refinesSpine, readSpineU16leV1_zero_mid]
  exact decodeFieldCount_eq_of_readU16leV1 0 _ 0 (left.length + 2) hread

/-- Decode u16le field-count 1 at mid-offset. -/
theorem decodeFieldCount_one_mid (left right : List UInt8) (nesting : Nat) :
    decodeFieldCount 1
        ⟨ByteArray.mk (left ++ u16leSpine1V1 ++ right).toArray, left.length, nesting⟩ =
      .ok ((),
        ⟨ByteArray.mk (left ++ u16leSpine1V1 ++ right).toArray,
          left.length + 2, nesting⟩) := by
  have hread :
      readU16leAtV1 (ByteArray.mk (left ++ u16leSpine1V1 ++ right).toArray)
        left.length = .ok (1, left.length + 2) := by
    rw [readU16leAtV1_refinesSpine, readSpineU16leV1_one_mid]
  exact decodeFieldCount_eq_of_readU16leV1 1 _ 1 (left.length + 2) hread

/-- Decode u16le field-count 2 at mid-offset. -/
theorem decodeFieldCount_two_mid (left right : List UInt8) (nesting : Nat) :
    decodeFieldCount 2
        ⟨ByteArray.mk (left ++ u16leSpine2V1 ++ right).toArray, left.length, nesting⟩ =
      .ok ((),
        ⟨ByteArray.mk (left ++ u16leSpine2V1 ++ right).toArray,
          left.length + 2, nesting⟩) := by
  have hread :
      readU16leAtV1 (ByteArray.mk (left ++ u16leSpine2V1 ++ right).toArray)
        left.length = .ok (2, left.length + 2) := by
    rw [readU16leAtV1_refinesSpine, readSpineU16leV1_two_mid]
  exact decodeFieldCount_eq_of_readU16leV1 2 _ 2 (left.length + 2) hread

/-- Decode u16le field-count 3 at mid-offset. -/
theorem decodeFieldCount_three_mid (left right : List UInt8) (nesting : Nat) :
    decodeFieldCount 3
        ⟨ByteArray.mk (left ++ u16leSpine3V1 ++ right).toArray, left.length, nesting⟩ =
      .ok ((),
        ⟨ByteArray.mk (left ++ u16leSpine3V1 ++ right).toArray,
          left.length + 2, nesting⟩) := by
  have hread :
      readU16leAtV1 (ByteArray.mk (left ++ u16leSpine3V1 ++ right).toArray)
        left.length = .ok (3, left.length + 2) := by
    rw [readU16leAtV1_refinesSpine, readSpineU16leV1_three_mid]
  exact decodeFieldCount_eq_of_readU16leV1 3 _ 3 (left.length + 2) hread

/-- Decode u16le field-count 4 at mid-offset. -/
theorem decodeFieldCount_four_mid (left right : List UInt8) (nesting : Nat) :
    decodeFieldCount 4
        ⟨ByteArray.mk (left ++ u16leSpine4V1 ++ right).toArray, left.length, nesting⟩ =
      .ok ((),
        ⟨ByteArray.mk (left ++ u16leSpine4V1 ++ right).toArray,
          left.length + 2, nesting⟩) := by
  have hread :
      readU16leAtV1 (ByteArray.mk (left ++ u16leSpine4V1 ++ right).toArray)
        left.length = .ok (4, left.length + 2) := by
    rw [readU16leAtV1_refinesSpine, readSpineU16leV1_four_mid]
  exact decodeFieldCount_eq_of_readU16leV1 4 _ 4 (left.length + 2) hread

/-- Decode u16le field-count 9 at mid-offset (SemanticProgram.Data). -/
theorem decodeFieldCount_nine_mid (left right : List UInt8) (nesting : Nat) :
    decodeFieldCount 9
        ⟨ByteArray.mk (left ++ u16leSpine9V1 ++ right).toArray, left.length, nesting⟩ =
      .ok ((),
        ⟨ByteArray.mk (left ++ u16leSpine9V1 ++ right).toArray,
          left.length + 2, nesting⟩) := by
  have hread :
      readU16leAtV1 (ByteArray.mk (left ++ u16leSpine9V1 ++ right).toArray)
        left.length = .ok (9, left.length + 2) := by
    rw [readU16leAtV1_refinesSpine, readSpineU16leV1_nine_mid]
  exact decodeFieldCount_eq_of_readU16leV1 9 _ 9 (left.length + 2) hread

end ProofForgeV2.Semantic.WireV1
