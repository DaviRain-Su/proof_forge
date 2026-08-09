import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.CodecV1
import Init.Data.ByteArray.Lemmas
import Init.Data.Array.Lemmas

/-!
  ProofForgeV2.Semantic.Wire.CodecRoundtripV1 — reusable encode→decode
  transport composition lemmas for Semantic wire (B-SC-DEC foundation).

  Purpose: replace per-program 1k-line fixture decode scripts with parametric
  spine constructors and mid-offset refinements over transparent List spines
  **and** production ByteArray mid-offset encode→decode composition.

  Scope (this slice):
    * mid-offset List get / single-byte / u16 / u32 spine reads
    * fixed small LE values used by SimpleClosure (0/1/2/3/4/9/64)
    * array-count header success from a u32le spine
    * sized UTF-8/ASCII string decode composition (NFC via isAscii)
    * **production** ByteArray mid-offset: u32 encode/decode, extract/take,
      general NFC UTF-8 string sized decode (not just ASCII), identifier→NFC/size
    * option none/some marker composition
    * nullary/fixed tagged header composition
    * root framing glue already in WireV1 (`decodeSemanticProgramDataV1_eq_of_framing`)

  Explicitly out of scope here:
    * full generic `encodeSemanticProgramDataV1 data = .ok bytes →
      decodeSemanticProgramDataV1 bytes = .ok data` for arbitrary data
      (needs inductive field-level roundtrips across every record family)
    * structure gate / re-encode identity (B-SC-STRUCT / carrier)

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
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

/-! ### Production ByteArray mid-offset encode→decode (B-SC-DEC) -/

/-- Mid-offset data membership of payload byte `i`. -/
theorem data_get_mid_payloadV1 (left payload right : ByteArray) (i : Nat)
    (hi : i < payload.size) :
    (left ++ payload ++ right).data[left.size + i]? = payload.data[i]? := by
  have hassoc : left ++ payload ++ right = left ++ (payload ++ right) := by
    simp [ByteArray.append_assoc]
  rw [hassoc, ByteArray.data_append]
  have : left.size = left.data.size := rfl
  rw [this, Array.getElem?_append_right (Nat.le_add_right _ _)]
  simp only [Nat.add_sub_cancel_left]
  rw [ByteArray.data_append, Array.getElem?_append_left hi]

/-- Production single-byte read of payload[i] at mid offset. -/
theorem readByte_mid_payloadV1 (left payload right : ByteArray) (i : Nat) (b : UInt8)
    (hi : i < payload.size) (hb : payload.data[i]? = some b) :
    readByteAtV1 (left ++ payload ++ right) (left.size + i) = .ok b := by
  change
    (match (left ++ payload ++ right).data[left.size + i]? with
     | some byte => Except.ok byte
     | none => Except.error SemanticWireErrorV1.truncated) = Except.ok b
  rw [data_get_mid_payloadV1 left payload right i hi, hb]

theorem encodeU32le_sizeV1 (v : UInt32) : (encodeU32le v).size = 4 := by
  simp [encodeU32le, ByteArray.size_push, ByteArray.size_empty]

theorem encodeU32le_data0V1 (v : UInt32) :
    (encodeU32le v).data[0]? = some (UInt8.ofNat (v.toNat % 256)) := by
  simp [encodeU32le, ByteArray.data_push, ByteArray.data_empty]

theorem encodeU32le_data1V1 (v : UInt32) :
    (encodeU32le v).data[1]? = some (UInt8.ofNat ((v.toNat / 256) % 256)) := by
  simp [encodeU32le, ByteArray.data_push, ByteArray.data_empty]

theorem encodeU32le_data2V1 (v : UInt32) :
    (encodeU32le v).data[2]? = some (UInt8.ofNat ((v.toNat / 65536) % 256)) := by
  simp [encodeU32le, ByteArray.data_push, ByteArray.data_empty]

theorem encodeU32le_data3V1 (v : UInt32) :
    (encodeU32le v).data[3]? = some (UInt8.ofNat ((v.toNat / 16777216) % 256)) := by
  simp [encodeU32le, ByteArray.data_push, ByteArray.data_empty]

theorem UInt8_toNat_ofNat_mod256V1 (n : Nat) :
    (UInt8.ofNat (n % 256)).toNat = n % 256 := by
  have : n % 256 < 256 := Nat.mod_lt _ (by decide)
  simp [UInt8.toNat, UInt8.ofNat, Nat.mod_eq_of_lt this]

/-- Little-endian u32 encode/decode identity on the reconstructed Nat. -/
theorem u32le_roundtripV1 (v : UInt32) :
    UInt32.ofNat
      ((UInt8.ofNat (v.toNat % 256)).toNat +
       (UInt8.ofNat ((v.toNat / 256) % 256)).toNat * 256 +
       (UInt8.ofNat ((v.toNat / 65536) % 256)).toNat * 65536 +
       (UInt8.ofNat ((v.toNat / 16777216) % 256)).toNat * 16777216) = v := by
  simp only [UInt8_toNat_ofNat_mod256V1]
  have hv : v.toNat < 4294967296 := UInt32.toNat_lt_size v
  have h :
      v.toNat % 256 +
      (v.toNat / 256) % 256 * 256 +
      (v.toNat / 65536) % 256 * 65536 +
      (v.toNat / 16777216) % 256 * 16777216 = v.toNat := by
    omega
  rw [h, UInt32.ofNat_toNat]

/-- Production u32le mid-offset: decode of `encodeU32le v` recovers `v`. -/
theorem readU32le_encode_midV1 (left right : ByteArray) (v : UInt32) :
    readU32leAtV1 (left ++ encodeU32le v ++ right) left.size =
      .ok (v, left.size + 4) := by
  have hs : (encodeU32le v).size = 4 := encodeU32le_sizeV1 v
  have h0 : readByteAtV1 (left ++ encodeU32le v ++ right) (left.size + 0) =
      .ok (UInt8.ofNat (v.toNat % 256)) :=
    readByte_mid_payloadV1 left (encodeU32le v) right 0 _
      (by rw [hs]; decide) (encodeU32le_data0V1 v)
  have h1 : readByteAtV1 (left ++ encodeU32le v ++ right) (left.size + 1) =
      .ok (UInt8.ofNat ((v.toNat / 256) % 256)) :=
    readByte_mid_payloadV1 left (encodeU32le v) right 1 _
      (by rw [hs]; decide) (encodeU32le_data1V1 v)
  have h2 : readByteAtV1 (left ++ encodeU32le v ++ right) (left.size + 2) =
      .ok (UInt8.ofNat ((v.toNat / 65536) % 256)) :=
    readByte_mid_payloadV1 left (encodeU32le v) right 2 _
      (by rw [hs]; decide) (encodeU32le_data2V1 v)
  have h3 : readByteAtV1 (left ++ encodeU32le v ++ right) (left.size + 3) =
      .ok (UInt8.ofNat ((v.toNat / 16777216) % 256)) :=
    readByte_mid_payloadV1 left (encodeU32le v) right 3 _
      (by rw [hs]; decide) (encodeU32le_data3V1 v)
  have h0' : readByteAtV1 (left ++ encodeU32le v ++ right) left.size =
      .ok (UInt8.ofNat (v.toNat % 256)) := by
    simpa using h0
  unfold readU32leAtV1
  simp only [h0', h1, h2, h3, Bind.bind, Pure.pure, Except.bind, Except.pure,
    u32le_roundtripV1]

/-- Mid-offset extract of an exact payload slice. -/
theorem extract_mid_payloadV1 (left payload right : ByteArray) :
    (left ++ payload ++ right).extract left.size (left.size + payload.size) =
      payload := by
  have hassoc : left ++ payload ++ right = left ++ (payload ++ right) := by
    simp [ByteArray.append_assoc]
  rw [hassoc]
  have heq := ByteArray.extract_append_size_add (a := left) (b := payload ++ right)
    (i := 0) (j := payload.size)
  simp only [Nat.add_zero] at heq
  rw [heq]
  exact ByteArray.extract_append_eq_left (a := payload) (b := right) rfl

/-- Production takeBytes of an exact mid payload. -/
theorem takeBytes_mid_payloadV1 (left payload right : ByteArray) :
    takeBytesAtV1 (left ++ payload ++ right) left.size payload.size = .ok payload := by
  unfold takeBytesAtV1
  have hrem :
      payload.size ≤ remainingBytesAtV1 (left ++ payload ++ right) left.size := by
    simp [remainingBytesAtV1, ByteArray.size_append]
    omega
  simp only [if_pos hrem]
  rw [extract_mid_payloadV1]

/-- UTF-8 roundtrip: every Lean String re-decodes from its own toUTF8 bytes. -/
theorem fromUTF8?_toUTF8V1 (s : String) : String.fromUTF8? s.toUTF8 = some s := by
  simp [String.fromUTF8?, String.toUTF8, String.fromUTF8, s.isValidUTF8]

/-- Production string payload = u32le length header ++ UTF-8 body. -/
def stringPayloadBytesV1 (s : String) : ByteArray :=
  (encodeU32le (UInt32.ofNat s.toUTF8.size)).append s.toUTF8

theorem stringPayloadBytesV1_eq (s : String) :
    stringPayloadBytesV1 s =
      encodeU32le (UInt32.ofNat s.toUTF8.size) ++ s.toUTF8 := by
  simp [stringPayloadBytesV1, ByteArray.append_eq]

/-- Production sized-byte read of a length-prefixed UTF-8 string payload. -/
theorem readSizedBytes_string_midV1 (left right : ByteArray) (s : String)
    (hsize : s.toUTF8.size ≤ maxStringBytes) :
    readSizedBytesAtV1 (left ++ stringPayloadBytesV1 s ++ right) left.size
        maxStringBytes =
      .ok (s.toUTF8, left.size + 4 + s.toUTF8.size) := by
  rw [stringPayloadBytesV1_eq]
  have hassoc :
      left ++ (encodeU32le (UInt32.ofNat s.toUTF8.size) ++ s.toUTF8) ++ right =
        left ++ encodeU32le (UInt32.ofNat s.toUTF8.size) ++ (s.toUTF8 ++ right) := by
    simp [ByteArray.append_assoc]
  rw [hassoc]
  have hread :=
    readU32le_encode_midV1 left (s.toUTF8 ++ right) (UInt32.ofNat s.toUTF8.size)
  unfold readSizedBytesAtV1
  simp only [hread]
  have hfit : (UInt32.ofNat s.toUTF8.size).toNat = s.toUTF8.size := by
    have : s.toUTF8.size ≤ UInt32.size - 1 :=
      Nat.le_trans hsize (by decide : maxStringBytes ≤ UInt32.size - 1)
    exact Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt this (by decide))
  simp only [hfit]
  have hlim : ¬(s.toUTF8.size > maxStringBytes) := Nat.not_lt.mpr hsize
  simp only [hlim, ↓reduceIte]
  have htake :
      takeBytesAtV1
          (left ++ encodeU32le (UInt32.ofNat s.toUTF8.size) ++ (s.toUTF8 ++ right))
          (left.size + 4) s.toUTF8.size = .ok s.toUTF8 := by
    have hs4 : (encodeU32le (UInt32.ofNat s.toUTF8.size)).size = 4 :=
      encodeU32le_sizeV1 _
    have hoff :
        (left ++ encodeU32le (UInt32.ofNat s.toUTF8.size)).size = left.size + 4 := by
      rw [ByteArray.size_append, hs4]
    have hA :
        left ++ encodeU32le (UInt32.ofNat s.toUTF8.size) ++ (s.toUTF8 ++ right) =
          (left ++ encodeU32le (UInt32.ofNat s.toUTF8.size)) ++ s.toUTF8 ++ right := by
      simp [ByteArray.append_assoc]
    rw [hA, ← hoff]
    exact takeBytes_mid_payloadV1 _ s.toUTF8 right
  simp only [htake]

/-- General NFC UTF-8 string decode at a production mid-offset payload.
    Not restricted to ASCII — only requires `requireNfc` + size. -/
theorem decodeString_nfc_midV1 (left right : ByteArray) (s : String) (nesting : Nat)
    (hnfc : requireNfc s = .ok ())
    (hsize : s.toUTF8.size ≤ maxStringBytes) :
    decodeString ⟨left ++ stringPayloadBytesV1 s ++ right, left.size, nesting⟩ =
      .ok (s,
        ⟨left ++ stringPayloadBytesV1 s ++ right,
          left.size + 4 + s.toUTF8.size, nesting⟩) := by
  have hread := readSizedBytes_string_midV1 left right s hsize
  exact decodeString_eq_of_valueV1 _ s.toUTF8 (left.size + 4 + s.toUTF8.size) s
    hread (fromUTF8?_toUTF8V1 s) hnfc

/-- Successful encodeString yields the production string payload bytes. -/
theorem encodeString_eq_stringPayloadV1 (s : String)
    (hnfc : requireNfc s = .ok ())
    (hsize : s.toUTF8.size ≤ maxStringBytes) :
    encodeString s = .ok (stringPayloadBytesV1 s) := by
  rw [encodeString_eq_okV1 s hnfc hsize, stringPayloadBytesV1_eq]
  rfl

/-- Identifier component success implies NFC (transport string gate). -/
theorem requireNfc_of_identifierV1 (s : String)
    (h : validateIdentifierComponent s = .ok ()) :
    requireNfc s = .ok () := by
  unfold validateIdentifierComponent at h
  match hsz : (decide (1 ≤ s.utf8ByteSize) && decide (s.utf8ByteSize ≤ 240)) with
  | false =>
      simp [hsz, Bind.bind, Pure.pure, Except.bind, Except.pure] at h
  | true =>
      simp [hsz, Bind.bind, Pure.pure, Except.bind, Except.pure] at h
      cases hnfc : requireNfc s with
      | error e => simp [hnfc] at h
      | ok u => rfl

/-- Identifier component success implies UTF-8 size ≤ maxStringBytes. -/
theorem utf8_size_le_maxString_of_identifierV1 (s : String)
    (h : validateIdentifierComponent s = .ok ()) :
    s.toUTF8.size ≤ maxStringBytes := by
  unfold validateIdentifierComponent at h
  by_cases hgate : 1 ≤ s.utf8ByteSize ∧ s.utf8ByteSize ≤ 240
  · have hsz : s.toUTF8.size = s.utf8ByteSize := rfl
    rw [hsz]
    exact Nat.le_trans hgate.2 (by decide : 240 ≤ maxStringBytes)
  · simp [hgate, Pure.pure, Except.pure, Bind.bind, Except.bind] at h

/-- Identifier-legal strings decode at production mid-offset payloads. -/
theorem decodeString_of_identifier_midV1 (left right : ByteArray) (s : String)
    (nesting : Nat) (h : validateIdentifierComponent s = .ok ()) :
    decodeString ⟨left ++ stringPayloadBytesV1 s ++ right, left.size, nesting⟩ =
      .ok (s,
        ⟨left ++ stringPayloadBytesV1 s ++ right,
          left.size + 4 + s.toUTF8.size, nesting⟩) :=
  decodeString_nfc_midV1 left right s nesting
    (requireNfc_of_identifierV1 s h)
    (utf8_size_le_maxString_of_identifierV1 s h)

/-- Identifier-legal strings encode to the production payload. -/
theorem encodeString_of_identifierV1 (s : String)
    (h : validateIdentifierComponent s = .ok ()) :
    encodeString s = .ok (stringPayloadBytesV1 s) :=
  encodeString_eq_stringPayloadV1 s
    (requireNfc_of_identifierV1 s h)
    (utf8_size_le_maxString_of_identifierV1 s h)

/-- Decode u32le at production mid-offset of `encodeU32le v`. -/
theorem decodeU32le_encode_midV1 (left right : ByteArray) (v : UInt32)
    (nesting : Nat) :
    decodeU32le ⟨left ++ encodeU32le v ++ right, left.size, nesting⟩ =
      .ok (v, ⟨left ++ encodeU32le v ++ right, left.size + 4, nesting⟩) := by
  apply decodeU32le_eq_of_readV1
  exact readU32le_encode_midV1 left right v

/-- Array count header from production `encodeU32le n` when `n ≤ maxCount`. -/
theorem readArrayCount_encode_midV1 (left right : ByteArray) (n maxCount : Nat)
    (hfit : n ≤ UInt32.size - 1) (hle : n ≤ maxCount) :
    readArrayCountAtV1
        (left ++ encodeU32le (UInt32.ofNat n) ++ right) left.size maxCount =
      .ok (n, left.size + 4) := by
  unfold readArrayCountAtV1
  have hread :=
    readU32le_encode_midV1 left right (UInt32.ofNat n)
  simp only [hread]
  have hto : (UInt32.ofNat n).toNat = n :=
    Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt hfit (by decide))
  simp only [hto]
  have hle' : ¬(n > maxCount) := Nat.not_lt.mpr hle
  simp only [hle', ↓reduceIte]

/-- Zero-count array decode from production `encodeU32le 0` mid-offset. -/
theorem decodeArray_encode_zero_midV1 (maxCount : Nat) (decode : Decoder α)
    (left right : ByteArray) (nesting : Nat) :
    decodeArray maxCount decode
        ⟨left ++ encodeU32le 0 ++ right, left.size, nesting⟩ =
      .ok (#[], ⟨left ++ encodeU32le 0 ++ right, left.size + 4, nesting⟩) := by
  apply decodeArray_zeroV1
  have hread := readU32le_encode_midV1 left right 0
  unfold readArrayCountAtV1
  simp only [hread]
  have : ¬((0 : Nat) > maxCount) := Nat.not_lt.mpr (Nat.zero_le _)
  simp only [UInt32.toNat_ofNat, Nat.zero_mod, this, ↓reduceIte]

/-- Option.some string mid-offset: marker 1 ++ string payload. -/
def someStringPayloadBytesV1 (s : String) : ByteArray :=
  (encodeU8 1).append (stringPayloadBytesV1 s)

theorem someStringPayloadBytesV1_eq (s : String) :
    someStringPayloadBytesV1 s =
      ByteArray.empty.push 1 ++ stringPayloadBytesV1 s := by
  simp [someStringPayloadBytesV1, encodeU8, ByteArray.append_eq]

/-- Marker-1 decode at production mid-offset of `empty.push 1`. -/
theorem decodeU8_one_payload_midV1 (left right : ByteArray) (nesting : Nat) :
    decodeU8 ⟨left ++ ByteArray.empty.push 1 ++ right, left.size, nesting⟩ =
      .ok (1, ⟨left ++ ByteArray.empty.push 1 ++ right, left.size + 1, nesting⟩) := by
  have hone : (ByteArray.empty.push 1).size = 1 := by
    simp [ByteArray.size_push, ByteArray.size_empty]
  have hget : (ByteArray.empty.push 1).data[0]? = some 1 := by
    simp [ByteArray.data_push, ByteArray.data_empty]
  apply decodeU8_eq_of_readV1
  exact readByte_mid_payloadV1 left (ByteArray.empty.push 1) right 0 1
    (by simp [hone]) hget

/-- Option.some of an identifier-legal string at production mid-offset.
    Composes `decodeOption_someV1` from production marker + string payload. -/
theorem decodeOptionString_some_identifier_midV1
    (left right : ByteArray) (s : String) (nesting : Nat)
    (h : validateIdentifierComponent s = .ok ()) :
    decodeOption decodeString
        ⟨left ++ someStringPayloadBytesV1 s ++ right, left.size, nesting⟩ =
      .ok (some s,
        ⟨left ++ someStringPayloadBytesV1 s ++ right,
          left.size + 1 + 4 + s.toUTF8.size, nesting⟩) := by
  -- Normalize wire shape to `left ++ push1 ++ stringPayload ++ right`.
  have hin :
      left ++ someStringPayloadBytesV1 s ++ right =
        left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right := by
    simp [someStringPayloadBytesV1_eq, ByteArray.append_assoc]
  rw [hin]
  have hassoc :
      left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right =
        left ++ ByteArray.empty.push 1 ++ (stringPayloadBytesV1 s ++ right) := by
    simp [ByteArray.append_assoc]
  -- Marker at left.size.
  have hmarker :
      decodeU8
          ⟨left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right,
            left.size, nesting⟩ =
        .ok (1,
          ⟨left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right,
            left.size + 1, nesting⟩) := by
    rw [hassoc]
    simpa [ByteArray.append_assoc] using
      decodeU8_one_payload_midV1 left (stringPayloadBytesV1 s ++ right) nesting
  -- String at left.size + 1 via left' = left ++ push1.
  have hleft1 : (left ++ ByteArray.empty.push 1).size = left.size + 1 := by
    simp [ByteArray.size_append, ByteArray.size_push, ByteArray.size_empty]
  have hin2 :
      left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right =
        (left ++ ByteArray.empty.push 1) ++ stringPayloadBytesV1 s ++ right := by
    simp [ByteArray.append_assoc]
  have hstr :
      decodeString
          ⟨left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right,
            left.size + 1, nesting⟩ =
        .ok (s,
          ⟨left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right,
            left.size + 1 + 4 + s.toUTF8.size, nesting⟩) := by
    rw [hin2]
    have hdec :=
      decodeString_of_identifier_midV1 (left ++ ByteArray.empty.push 1) right s nesting h
    simpa [hleft1] using hdec
  exact decodeOption_someV1 decodeString
    ⟨left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right,
      left.size, nesting⟩
    ⟨left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right,
      left.size + 1, nesting⟩
    ⟨left ++ ByteArray.empty.push 1 ++ stringPayloadBytesV1 s ++ right,
      left.size + 1 + 4 + s.toUTF8.size, nesting⟩
    s hmarker hstr

/-! ### Production encode success → decode (string / magic / finish) -/

theorem ByteArray_beq_reflV1 (a : ByteArray) : (a == a) = true := by
  change (a.data == a.data) = true
  simp

theorem takeBytes_left_payloadV1 (left right : ByteArray) :
    takeBytesAtV1 (left ++ right) 0 left.size = .ok left := by
  unfold takeBytesAtV1
  have hrem : left.size ≤ remainingBytesAtV1 (left ++ right) 0 := by
    simp [remainingBytesAtV1, ByteArray.size_append]
  simp only [if_pos hrem]
  have hex : (left ++ right).extract 0 (0 + left.size) = left := by
    have : 0 + left.size = left.size := Nat.zero_add _
    rw [this]
    exact ByteArray.extract_append_eq_left rfl
  rw [hex]

theorem consumeMagicBytes_appendV1 (magic : String) (body : ByteArray) :
    consumeMagicBytesAtV1 (encodeMagicPrefix magic ++ body) 0
        (encodeMagicPrefix magic) =
      .ok (encodeMagicPrefix magic).size := by
  unfold consumeMagicBytesAtV1
  have htake := takeBytes_left_payloadV1 (encodeMagicPrefix magic) body
  have heq : (encodeMagicPrefix magic == encodeMagicPrefix magic) = true :=
    ByteArray_beq_reflV1 _
  simp only [htake, heq, ↓reduceIte, Nat.zero_add]

theorem consumeMagic_append_bodyV1 (magic : String) (body : ByteArray) :
    consumeMagic magic (start (encodeMagicPrefix magic ++ body)) =
      .ok ((), ⟨encodeMagicPrefix magic ++ body,
        (encodeMagicPrefix magic).size, 0⟩) := by
  apply consumeMagic_eq_of_bytesV1
  exact consumeMagicBytes_appendV1 magic body

theorem finish_at_endV1 (bytes : ByteArray) (nesting : Nat) :
    finish ⟨bytes, bytes.size, nesting⟩ = .ok () :=
  finish_eq_ok_of_offset_sizeV1 ⟨bytes, bytes.size, nesting⟩ rfl

/-- Successful `encodeString` yields exact production payload + NFC + size. -/
theorem encodeString_ok_eq_payloadV1 (s : String) (b : ByteArray)
    (h : encodeString s = .ok b) :
    b = stringPayloadBytesV1 s ∧
      requireNfc s = .ok () ∧
      s.toUTF8.size ≤ maxStringBytes := by
  have horig := h
  have hnfc : requireNfc s = .ok () := by
    have h' := horig
    simp only [encodeString, mapCommon] at h'
    generalize hr : requireNfc s = r at h' ⊢
    cases r with
    | error e => simp [Bind.bind, Except.bind] at h'
    | ok u => cases u; rfl
  have hsz : s.toUTF8.size ≤ maxStringBytes := by
    have h' := horig
    simp only [encodeString, mapCommon, hnfc, Bind.bind, Pure.pure, Except.bind,
      Except.pure] at h'
    by_cases hs : s.toUTF8.size ≤ maxStringBytes
    · exact hs
    · simp only [hs, ↓reduceIte, err] at h'
      cases h'
  have hok := encodeString_eq_okV1 s hnfc hsz
  have hb : b = (encodeU32le (UInt32.ofNat s.toUTF8.size)).append s.toUTF8 :=
    Except.ok.inj (horig.symm.trans hok)
  have hb' : b = stringPayloadBytesV1 s := by
    rw [hb, stringPayloadBytesV1_eq]; rfl
  exact And.intro hb' (And.intro hnfc hsz)

/-- Decode recovers any successfully encoded string at a production mid-offset. -/
theorem decodeString_of_encodeString_okV1
    (left right : ByteArray) (s : String) (b : ByteArray) (nesting : Nat)
    (h : encodeString s = .ok b) :
    decodeString ⟨left ++ b ++ right, left.size, nesting⟩ =
      .ok (s, ⟨left ++ b ++ right, left.size + b.size, nesting⟩) := by
  obtain ⟨hb, hnfc, hsz⟩ := encodeString_ok_eq_payloadV1 s b h
  subst b
  have hdec := decodeString_nfc_midV1 left right s nesting hnfc hsz
  have hszp : left.size + 4 + s.toUTF8.size =
      left.size + (stringPayloadBytesV1 s).size := by
    simp [stringPayloadBytesV1, ByteArray.size_append, encodeU32le_sizeV1]
    omega
  rw [hszp] at hdec
  exact hdec

theorem encodeU16le_sizeV1 (v : UInt16) : (encodeU16le v).size = 2 := by
  simp [encodeU16le, ByteArray.size_push, ByteArray.size_empty]

theorem UInt8_toNat_ofNat_mod256_u16V1 (n : Nat) :
    (UInt8.ofNat (n % 256)).toNat = n % 256 := by
  have : n % 256 < 256 := Nat.mod_lt _ (by decide)
  simp [UInt8.toNat, UInt8.ofNat, Nat.mod_eq_of_lt this]

theorem u16le_roundtripV1 (v : UInt16) :
    UInt16.ofNat
      ((UInt8.ofNat (v.toNat % 256)).toNat +
        (UInt8.ofNat ((v.toNat / 256) % 256)).toNat * 256) = v := by
  simp only [UInt8_toNat_ofNat_mod256_u16V1]
  have hv : v.toNat < 65536 := UInt16.toNat_lt_size v
  have h : v.toNat % 256 + (v.toNat / 256) % 256 * 256 = v.toNat := by omega
  rw [h, UInt16.ofNat_toNat]

/-- Mid-offset u16le encode/decode identity. -/
theorem readU16le_encode_midV1 (left right : ByteArray) (v : UInt16) :
    readU16leAtV1 (left ++ encodeU16le v ++ right) left.size =
      .ok (v, left.size + 2) := by
  have hs : (encodeU16le v).size = 2 := encodeU16le_sizeV1 v
  have h0 : (encodeU16le v).data[0]? =
      some (UInt8.ofNat (v.toNat % 256)) := by
    simp [encodeU16le, ByteArray.data_push, ByteArray.data_empty]
  have h1 : (encodeU16le v).data[1]? =
      some (UInt8.ofNat ((v.toNat / 256) % 256)) := by
    simp [encodeU16le, ByteArray.data_push, ByteArray.data_empty]
  have r0 := readByte_mid_payloadV1 left (encodeU16le v) right 0 _
    (by rw [hs]; decide) h0
  have r1 := readByte_mid_payloadV1 left (encodeU16le v) right 1 _
    (by rw [hs]; decide) h1
  have r0' : readByteAtV1 (left ++ encodeU16le v ++ right) left.size =
      .ok (UInt8.ofNat (v.toNat % 256)) := by simpa using r0
  unfold readU16leAtV1
  simp only [r0', r1, Bind.bind, Pure.pure, Except.bind, Except.pure, u16le_roundtripV1]

/-! ### Generic tagged-header mid-offset (product foundation for codec invert) -/

/-- Production tagged header = `u32le(|tag|) ++ tag ++ u16le(fieldCount)`. -/
def taggedHeaderBytesV1 (tag : String) (fieldCount : Nat) : ByteArray :=
  ((encodeU32le (UInt32.ofNat tag.toUTF8.size)).append tag.toUTF8).append
    (encodeU16le (UInt16.ofNat fieldCount))

theorem taggedHeaderBytesV1_size (tag : String) (fieldCount : Nat) :
    (taggedHeaderBytesV1 tag fieldCount).size = 4 + tag.toUTF8.size + 2 := by
  unfold taggedHeaderBytesV1
  change ((encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
      encodeU16le (UInt16.ofNat fieldCount)).size = 4 + tag.toUTF8.size + 2
  rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1,
    encodeU16le_sizeV1]

theorem ByteArray_bne_self_eq_falseV1 (a : ByteArray) : (a != a) = false := by
  simp [bne, ByteArray_beq_reflV1]

/-- Production length-prefixed ASCII tag read at mid-offset of
    `u32le(|tag|) ++ tagBytes`. -/
theorem readTagBytes_encode_midV1
    (left right : ByteArray) (tagBytes : ByteArray)
    (hnonempty : 1 ≤ tagBytes.size)
    (hmax : tagBytes.size ≤ maxTagAsciiBytes)
    (hfit : tagBytes.size ≤ UInt32.size - 1)
    (hascii : isAsciiTagBytesV1 tagBytes = true) :
    readTagBytesAtV1
        (left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ tagBytes ++ right)
        left.size =
      .ok (tagBytes, left.size + 4 + tagBytes.size) := by
  have hassoc :
      left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ tagBytes ++ right =
        left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ (tagBytes ++ right) := by
    simp [ByteArray.append_assoc]
  rw [hassoc]
  have hread :=
    readU32le_encode_midV1 left (tagBytes ++ right) (UInt32.ofNat tagBytes.size)
  have hto : (UInt32.ofNat tagBytes.size).toNat = tagBytes.size :=
    Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt hfit (by decide))
  have htake :
      takeBytesAtV1
          (left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ (tagBytes ++ right))
          (left.size + 4) tagBytes.size = .ok tagBytes := by
    have hs4 : (encodeU32le (UInt32.ofNat tagBytes.size)).size = 4 :=
      encodeU32le_sizeV1 _
    have hA :
        left ++ encodeU32le (UInt32.ofNat tagBytes.size) ++ (tagBytes ++ right) =
          (left ++ encodeU32le (UInt32.ofNat tagBytes.size)) ++ tagBytes ++ right := by
      simp [ByteArray.append_assoc]
    have hoff :
        (left ++ encodeU32le (UInt32.ofNat tagBytes.size)).size = left.size + 4 := by
      rw [ByteArray.size_append, hs4]
    rw [hA, ← hoff]
    exact takeBytes_mid_payloadV1 _ tagBytes right
  unfold readTagBytesAtV1
  rw [hread]
  dsimp only
  have h1 : decide (1 ≤ tagBytes.size) = true := by simp [hnonempty]
  have h2 : decide (tagBytes.size ≤ maxTagAsciiBytes) = true := by simp [hmax]
  simp only [hto, h1, h2, Bool.and_self, Bool.not_true]
  rw [if_neg (by decide : ¬(false = true))]
  rw [htake]
  simp only [hascii, ↓reduceIte]

/-- Production expectTaggedHeader at mid-offset of
    `taggedHeaderBytesV1 tag fieldCount ++ fieldsPayload`. -/
theorem expectTaggedHeader_encode_midV1
    (left right : ByteArray) (tag : String) (fieldCount : Nat)
    (fieldsPayload : ByteArray)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hcountFit : fieldCount ≤ UInt16.size - 1) :
    expectTaggedHeaderBytesAtV1
        (left ++ taggedHeaderBytesV1 tag fieldCount ++ fieldsPayload ++ right)
        left.size tag.toUTF8 fieldCount =
      .ok (left.size + (taggedHeaderBytesV1 tag fieldCount).size) := by
  have henc :
      taggedHeaderBytesV1 tag fieldCount =
        encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          encodeU16le (UInt16.ofNat fieldCount) := by
    simp [taggedHeaderBytesV1, ByteArray.append_assoc]
  have hin :
      left ++ taggedHeaderBytesV1 tag fieldCount ++ fieldsPayload ++ right =
        left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          (encodeU16le (UInt16.ofNat fieldCount) ++ fieldsPayload ++ right) := by
    simp [henc, ByteArray.append_assoc]
  rw [hin]
  have htag :=
    readTagBytes_encode_midV1 left
      (encodeU16le (UInt16.ofNat fieldCount) ++ fieldsPayload ++ right)
      tag.toUTF8 hnonempty hmax hfit hasciiBytes
  unfold expectTaggedHeaderBytesAtV1
  rw [htag]
  dsimp only
  rw [ByteArray_bne_self_eq_falseV1]
  rw [if_neg (by decide : ¬(false = true))]
  have hassoc2 :
      left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
          (encodeU16le (UInt16.ofNat fieldCount) ++ fieldsPayload ++ right) =
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8) ++
          encodeU16le (UInt16.ofNat fieldCount) ++ (fieldsPayload ++ right) := by
    simp [ByteArray.append_assoc]
  have hszL :
      (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8).size =
        left.size + 4 + tag.toUTF8.size := by
    rw [ByteArray.size_append, ByteArray.size_append, encodeU32le_sizeV1]
  have hcount :
      readU16leAtV1
          (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++
            (encodeU16le (UInt16.ofNat fieldCount) ++ fieldsPayload ++ right))
          (left.size + 4 + tag.toUTF8.size) =
        .ok (UInt16.ofNat fieldCount,
          left.size + 4 + tag.toUTF8.size + 2) := by
    rw [hassoc2, ← hszL]
    simpa [hszL] using
      readU16le_encode_midV1
        (left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8)
        (fieldsPayload ++ right) (UInt16.ofNat fieldCount)
  rw [hcount]
  dsimp only
  have htoC : (UInt16.ofNat fieldCount).toNat = fieldCount :=
    Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt hcountFit (by decide))
  have heq : ((UInt16.ofNat fieldCount).toNat == fieldCount) = true := by
    simp [htoC]
  rw [heq, if_pos rfl]
  have : left.size + 4 + tag.toUTF8.size + 2 =
      left.size + (taggedHeaderBytesV1 tag fieldCount).size := by
    rw [taggedHeaderBytesV1_size]; omega
  exact congrArg Except.ok this

/-- Production `expectTag` at mid-offset of a successful tagged header. -/
theorem expectTag_encode_midV1
    (left right : ByteArray) (tag : String) (fieldCount : Nat)
    (fieldsPayload : ByteArray) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hcountFit : fieldCount ≤ UInt16.size - 1) :
    expectTag tag fieldCount
        ⟨left ++ taggedHeaderBytesV1 tag fieldCount ++ fieldsPayload ++ right,
          left.size, nesting⟩ =
      .ok ((),
        ⟨left ++ taggedHeaderBytesV1 tag fieldCount ++ fieldsPayload ++ right,
          left.size + (taggedHeaderBytesV1 tag fieldCount).size, nesting⟩) := by
  apply expectTag_eq_of_headerV1
  exact expectTaggedHeader_encode_midV1 left right tag fieldCount fieldsPayload
    hnonempty hmax hfit hasciiBytes hcountFit

/-- Production `decodeTag` at mid-offset of `u32le(|tag|) ++ tag`. -/
theorem decodeTag_encode_midV1
    (left right : ByteArray) (tag : String) (nesting : Nat)
    (hnonempty : 1 ≤ tag.toUTF8.size)
    (hmax : tag.toUTF8.size ≤ maxTagAsciiBytes)
    (hfit : tag.toUTF8.size ≤ UInt32.size - 1)
    (hasciiBytes : isAsciiTagBytesV1 tag.toUTF8 = true)
    (hasciiTag : isAsciiTagV1 tag = true) :
    decodeTag
        ⟨left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ right,
          left.size, nesting⟩ =
      .ok (tag,
        ⟨left ++ encodeU32le (UInt32.ofNat tag.toUTF8.size) ++ tag.toUTF8 ++ right,
          left.size + 4 + tag.toUTF8.size, nesting⟩) := by
  apply decodeTag_eq_of_valueV1
  · exact readTagBytes_encode_midV1 left right tag.toUTF8 hnonempty hmax hfit hasciiBytes
  · exact fromUTF8?_toUTF8V1 tag
  · exact hasciiTag

/-- `taggedBytesV1` expands to header ++ foldl-append of fields. -/
theorem taggedBytesV1_eq_header_payload (tag : String) (fields : Array ByteArray) :
    taggedBytesV1 tag fields =
      taggedHeaderBytesV1 tag fields.size ++
        fields.foldl (fun out f => out.append f) ByteArray.empty := by
  simp only [taggedBytesV1, taggedBytesFromBytesV1, taggedHeaderBytesV1,
    appendTaggedFieldsV1]
  have hfold (init : ByteArray) (xs : List ByteArray) :
      xs.foldl (fun out f => out.append f) init =
        init ++ xs.foldl (fun out f => out.append f) ByteArray.empty := by
    induction xs generalizing init with
    | nil =>
        simp only [List.foldl_nil, ByteArray.append_empty]
    | cons x xs ih =>
        -- foldl_cons reduces both sides to recursive form.
        simp only [List.foldl_cons]
        -- LHS: foldl (init.append x) xs
        -- RHS: init ++ foldl (empty.append x) xs
        rw [ih (init.append x), ih (ByteArray.empty.append x)]
        -- Normalize method append to ++
        change (init ++ x) ++ List.foldl (fun out f => out.append f) ByteArray.empty xs =
          init ++ ((ByteArray.empty ++ x) ++
            List.foldl (fun out f => out.append f) ByteArray.empty xs)
        rw [ByteArray.empty_append, ByteArray.append_assoc]
  have hlist (init : ByteArray) :
      fields.foldl (fun out field => out.append field) init =
        fields.toList.foldl (fun out field => out.append field) init := by
    simp [Array.foldl_toList]
  let header :=
    ((encodeU32le (UInt32.ofNat tag.toUTF8.size)).append tag.toUTF8).append
      (encodeU16le (UInt16.ofNat fields.size))
  change fields.foldl (fun out field => out.append field) header =
    header ++ fields.foldl (fun out field => out.append field) ByteArray.empty
  rw [hlist header, hlist ByteArray.empty, hfold header fields.toList]

end ProofForgeV2.Semantic.WireV1
