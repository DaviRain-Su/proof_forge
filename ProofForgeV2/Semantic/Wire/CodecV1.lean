import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1

/-!
  ProofForgeV2.Semantic.Wire.CodecV1 — primitive and structure tagged codecs,
  cursor, nesting fuel, and magic/version helpers for SemanticProgramV1.

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-! ### Primitive encode -/

def encodeU8 (value : UInt8) : ByteArray :=
  ByteArray.empty.push value

def encodeU16le (value : UInt16) : ByteArray :=
  let v := value.toNat
  (ByteArray.empty.push (UInt8.ofNat (v % 256))).push (UInt8.ofNat ((v / 256) % 256))

def encodeU32le (value : UInt32) : ByteArray :=
  let v := value.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  ((((ByteArray.empty.push b0).push b1).push b2).push b3)

def encodeU64le (value : UInt64) : ByteArray := Id.run do
  let v := value.toNat
  let mut out := ByteArray.emptyWithCapacity 8
  let mut n := v
  for _ in [:8] do
    out := out.push (UInt8.ofNat (n % 256))
    n := n / 256
  pure out

def encodeBool (value : Bool) : ByteArray :=
  encodeU8 (if value then 1 else 0)

private def encodeNatAsU32le (count : Nat) : Except SemanticWireErrorV1 ByteArray := do
  unless count ≤ UInt32.size - 1 do
    return ← err .limitExceeded
  pure (encodeU32le (UInt32.ofNat count))

private def encodeNatAsU16le (count : Nat) : Except SemanticWireErrorV1 ByteArray := do
  unless count ≤ UInt16.size - 1 do
    return ← err .limitExceeded
  pure (encodeU16le (UInt16.ofNat count))

def encodeOption (encode : α → Except SemanticWireErrorV1 ByteArray) :
    Option α → Except SemanticWireErrorV1 ByteArray
  | none => pure (encodeU8 0)
  | some value => do
      let payload ← encode value
      pure ((encodeU8 1).append payload)

def encodeArray (encode : α → Except SemanticWireErrorV1 ByteArray)
    (values : Array α) : Except SemanticWireErrorV1 ByteArray := do
  unless values.size ≤ maxArrayElements do
    return ← err .limitExceeded
  let header ← encodeNatAsU32le values.size
  let mut payload := ByteArray.empty
  for value in values do
    let chunk ← encode value
    payload := payload.append chunk
  pure (header.append payload)

def encodeByteArray (value : ByteArray) : Except SemanticWireErrorV1 ByteArray := do
  unless value.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  let header ← encodeNatAsU32le value.size
  pure (header.append value)

def encodeString (value : String) : Except SemanticWireErrorV1 ByteArray := do
  mapCommon (requireNfc value)
  let raw := value.toUTF8
  unless raw.size ≤ maxStringBytes do
    return ← err .limitExceeded
  let header ← encodeNatAsU32le raw.size
  pure (header.append raw)

def encodeDigest (digest : Digest) : Except SemanticWireErrorV1 ByteArray := do
  mapCommon (validateDigest digest)
  pure digest.bytes

def encodeNodeId (nodeId : NodeId) : Except SemanticWireErrorV1 ByteArray := do
  mapCommon (validateNodeId nodeId)
  pure nodeId.bytes

def encodeSchemaId (schema : SchemaId) : Except SemanticWireErrorV1 ByteArray := do
  let s ← mapCommon (renderSchemaId schema)
  encodeString s

def encodeSemVer (version : SemVer) : Except SemanticWireErrorV1 ByteArray := do
  let s ← mapCommon (renderSemVer version)
  encodeString s

def encodeQualifiedName (name : QualifiedName) : Except SemanticWireErrorV1 ByteArray := do
  let components ← mapCommon (renderQualifiedNameComponents name)
  encodeArray encodeString components

def encodeProjectRelativePath (path : ProjectRelativePath) :
    Except SemanticWireErrorV1 ByteArray := do
  mapCommon (validateProjectRelativePath path)
  encodeString path.value

def encodeSourceOrigin (origin : SourceOrigin) : Except SemanticWireErrorV1 ByteArray := do
  mapCommon (validateSourceOrigin origin)
  let pathB ← encodeProjectRelativePath origin.sourcePath
  let startB := encodeU64le origin.startByte
  let endB := encodeU64le origin.endByte
  let nodeB ← encodeNodeId origin.nodeId
  pure (((pathB.append startB).append endB).append nodeB)

private def isAsciiTag (tag : String) : Bool := Id.run do
  for c in tag.toList do
    unless (c : Char).val ≤ 127 do
      return false
  return true

def encodeTagged (tag : String) (fields : Array ByteArray) :
    Except SemanticWireErrorV1 ByteArray := do
  if tag.isEmpty then
    return ← err .badTag
  unless isAsciiTag tag do
    return ← err .badTag
  let tagBytes := tag.toUTF8
  unless tagBytes.size ≤ maxTagAsciiBytes do
    return ← err .limitExceeded
  let tagLen ← encodeNatAsU32le tagBytes.size
  let fieldCount ← encodeNatAsU16le fields.size
  let mut out := (tagLen.append tagBytes).append fieldCount
  for field in fields do
    out := out.append field
  pure out

def encodeNullary (tag : String) : Except SemanticWireErrorV1 ByteArray :=
  encodeTagged tag #[]

/-! ### Primitive decode cursor -/

/-- Decode cursor. Fields are public within the WireV1 module family so
    ValueBytes and other codec leaves can share the same transport spine;
    product consumers should use `start` / `remaining` / `finish` only. -/
structure Cursor where
  input : ByteArray
  offset : Nat
  /-- Tagged-value nesting depth (0 at root entry). Shared by all tagged readers. -/
  nesting : Nat

abbrev Decoder (α : Type) := Cursor → Except SemanticWireErrorV1 (α × Cursor)

def start (input : ByteArray) : Cursor :=
  ⟨input, 0, 0⟩

/-- Start a cursor at a synthetic nesting depth (nesting-limit tests). -/
def startAtNesting (input : ByteArray) (nesting : Nat) : Cursor :=
  ⟨input, 0, nesting⟩

/-- Remaining length on the transparent proof spine. -/
def spineRemainingV1 (bytes : List UInt8) (offset : Nat) : Nat :=
  bytes.length - offset

/-- Remaining length primitive used by the production cursor. -/
def remainingBytesAtV1 (bytes : ByteArray) (offset : Nat) : Nat :=
  bytes.size - offset

def remaining (c : Cursor) : Nat :=
  remainingBytesAtV1 c.input c.offset

/-- Remaining-length refinement for a `ByteArray` built from the transparent
    spine. -/
theorem remainingBytesAtV1_refinesSpine (bytes : List UInt8) (offset : Nat) :
    remainingBytesAtV1 (ByteArray.mk bytes.toArray) offset =
      spineRemainingV1 bytes offset := by
  rfl

def cursorNesting (c : Cursor) : Nat :=
  c.nesting

def finish (c : Cursor) : Except SemanticWireErrorV1 Unit := do
  unless remaining c == 0 do
    return ← err .trailingBytes
  pure ()

/-- Transparent proof-facing byte spine. This is deliberately only the
    primitive read seam, not an independent semantic decoder. -/
abbrev TransparentByteSpineV1 := List UInt8

/-- Read one byte from the transparent proof spine. Bounds failure has the
    same closed wire error as the production cursor. -/
def readSpineByteV1 (bytes : TransparentByteSpineV1) (offset : Nat) :
    Except SemanticWireErrorV1 UInt8 :=
  match bytes[offset]? with
  | some byte => .ok byte
  | none => .error .truncated

/-- Production `ByteArray` primitive corresponding to `readSpineByteV1`.
    Cursor decoding calls this definition, so the refinement theorem below
    relates the proof spine to the runtime authority rather than to a copied
    validator. -/
def readByteAtV1 (bytes : ByteArray) (offset : Nat) :
    Except SemanticWireErrorV1 UInt8 :=
  match bytes.data[offset]? with
  | some byte => .ok byte
  | none => .error .truncated

/-- Primitive byte-read refinement, including the exact out-of-bounds error.
    `List.toArray` and `ByteArray.mk` are transparent, so this theorem is
    kernel-checkable without reducing `ByteArray.extract`/`copySlice`. -/
theorem readByteAtV1_refinesSpine (bytes : TransparentByteSpineV1) (offset : Nat) :
    readByteAtV1 (ByteArray.mk bytes.toArray) offset = readSpineByteV1 bytes offset := by
  simp [readByteAtV1, readSpineByteV1, List.getElem?_toArray]

/-- Read one little-endian u16 from the transparent proof spine. -/
def readSpineU16leV1 (bytes : TransparentByteSpineV1) (offset : Nat) :
    Except SemanticWireErrorV1 (UInt16 × Nat) := do
  let b0 ← readSpineByteV1 bytes offset
  let b1 ← readSpineByteV1 bytes (offset + 1)
  pure (UInt16.ofNat (b0.toNat + b1.toNat * 256), offset + 2)

/-- Production offset primitive for one little-endian u16. -/
def readU16leAtV1 (bytes : ByteArray) (offset : Nat) :
    Except SemanticWireErrorV1 (UInt16 × Nat) := do
  let b0 ← readByteAtV1 bytes offset
  let b1 ← readByteAtV1 bytes (offset + 1)
  pure (UInt16.ofNat (b0.toNat + b1.toNat * 256), offset + 2)

/-- Little-endian u16 refinement, including truncation after either byte. -/
theorem readU16leAtV1_refinesSpine (bytes : TransparentByteSpineV1) (offset : Nat) :
    readU16leAtV1 (ByteArray.mk bytes.toArray) offset = readSpineU16leV1 bytes offset := by
  unfold readU16leAtV1 readSpineU16leV1
  rw [readByteAtV1_refinesSpine]
  cases h0 : readSpineByteV1 bytes offset with
  | error e => rfl
  | ok b0 =>
    rw [readByteAtV1_refinesSpine]

/-- Read one little-endian u32 from the transparent proof spine. -/
def readSpineU32leV1 (bytes : TransparentByteSpineV1) (offset : Nat) :
    Except SemanticWireErrorV1 (UInt32 × Nat) := do
  let b0 ← readSpineByteV1 bytes offset
  let b1 ← readSpineByteV1 bytes (offset + 1)
  let b2 ← readSpineByteV1 bytes (offset + 2)
  let b3 ← readSpineByteV1 bytes (offset + 3)
  let value :=
    b0.toNat + b1.toNat * 256 + b2.toNat * 65536 + b3.toNat * 16777216
  pure (UInt32.ofNat value, offset + 4)

/-- Production offset primitive for one little-endian u32. -/
def readU32leAtV1 (bytes : ByteArray) (offset : Nat) :
    Except SemanticWireErrorV1 (UInt32 × Nat) := do
  let b0 ← readByteAtV1 bytes offset
  let b1 ← readByteAtV1 bytes (offset + 1)
  let b2 ← readByteAtV1 bytes (offset + 2)
  let b3 ← readByteAtV1 bytes (offset + 3)
  let value :=
    b0.toNat + b1.toNat * 256 + b2.toNat * 65536 + b3.toNat * 16777216
  pure (UInt32.ofNat value, offset + 4)

/-- Little-endian u32 refinement, including truncation after any byte. -/
theorem readU32leAtV1_refinesSpine (bytes : TransparentByteSpineV1) (offset : Nat) :
    readU32leAtV1 (ByteArray.mk bytes.toArray) offset = readSpineU32leV1 bytes offset := by
  unfold readU32leAtV1 readSpineU32leV1
  rw [readByteAtV1_refinesSpine]
  cases h0 : readSpineByteV1 bytes offset with
  | error e => rfl
  | ok b0 =>
    rw [readByteAtV1_refinesSpine]
    cases h1 : readSpineByteV1 bytes (offset + 1) with
    | error e => rfl
    | ok b1 =>
      rw [readByteAtV1_refinesSpine]
      cases h2 : readSpineByteV1 bytes (offset + 2) with
      | error e => rfl
      | ok b2 =>
        rw [readByteAtV1_refinesSpine]

/-- Take exactly `count` bytes from the transparent proof spine. Unlike bare
    `List.take`, a short input fails closed with the production wire error. -/
def takeSpineBytesV1 (bytes : TransparentByteSpineV1) (offset count : Nat) :
    Except SemanticWireErrorV1 (List UInt8) :=
  if count ≤ spineRemainingV1 bytes offset then
    .ok ((bytes.drop offset).take count)
  else
    .error .truncated

/-- Production exact-slice primitive. It retains `ByteArray.extract` for the
    runtime implementation; proofs cross to `takeSpineBytesV1` via the theorem
    below instead of reducing `copySlice`. -/
def takeBytesAtV1 (bytes : ByteArray) (offset count : Nat) :
    Except SemanticWireErrorV1 ByteArray :=
  if count ≤ remainingBytesAtV1 bytes offset then
    .ok (bytes.extract offset (offset + count))
  else
    .error .truncated

/-- Exact-slice refinement. Mapping the production slice back to its logical
    byte list yields the transparent spine result, including short-input
    failure. The proof uses library extract correctness, not `copySlice`
    reduction. -/
theorem takeBytesAtV1_refinesSpine (bytes : TransparentByteSpineV1)
    (offset count : Nat) :
    (takeBytesAtV1 (ByteArray.mk bytes.toArray) offset count).map
        (fun slice => slice.data.toList) =
      takeSpineBytesV1 bytes offset count := by
  have hs : remainingBytesAtV1 (ByteArray.mk bytes.toArray) offset =
      spineRemainingV1 bytes offset := remainingBytesAtV1_refinesSpine bytes offset
  unfold takeBytesAtV1 takeSpineBytesV1
  rw [hs]
  split <;> rename_i h
  · simp only [Except.map]
    congr 1
    rw [ByteArray.data_extract, Array.toList_extract]
    simp [List.extract_eq_take_drop]
  · rfl

/-- Read a u32-length-prefixed byte payload on the transparent spine. The
    declared limit is checked before payload bounds, matching production error
    precedence. -/
def readSizedSpineBytesV1 (input : TransparentByteSpineV1) (offset maxLen : Nat) :
    Except SemanticWireErrorV1 (List UInt8 × Nat) :=
  match readSpineU32leV1 input offset with
  | .error e => .error e
  | .ok (lenU, afterLen) =>
      let len := lenU.toNat
      if len > maxLen then
        .error .limitExceeded
      else
        match takeSpineBytesV1 input afterLen len with
        | .error e => .error e
        | .ok payload => .ok (payload, afterLen + len)

/-- Production u32-length-prefixed byte payload primitive. -/
def readSizedBytesAtV1 (input : ByteArray) (offset maxLen : Nat) :
    Except SemanticWireErrorV1 (ByteArray × Nat) :=
  match readU32leAtV1 input offset with
  | .error e => .error e
  | .ok (lenU, afterLen) =>
      let len := lenU.toNat
      if len > maxLen then
        .error .limitExceeded
      else
        match takeBytesAtV1 input afterLen len with
        | .error e => .error e
        | .ok payload => .ok (payload, afterLen + len)

/-- Length-prefixed byte payload refinement through u32 decode, limit
    precedence, exact slice, and next-offset calculation. -/
theorem readSizedBytesAtV1_refinesSpine (input : TransparentByteSpineV1)
    (offset maxLen : Nat) :
    (readSizedBytesAtV1 (ByteArray.mk input.toArray) offset maxLen).map
        (fun (payload, next) => (payload.data.toList, next)) =
      readSizedSpineBytesV1 input offset maxLen := by
  unfold readSizedBytesAtV1 readSizedSpineBytesV1
  rw [readU32leAtV1_refinesSpine]
  cases hread : readSpineU32leV1 input offset with
  | error e => rfl
  | ok pair =>
    rcases pair with ⟨lenU, afterLen⟩
    by_cases hv : lenU.toNat > maxLen
    · simp only [if_pos hv, Except.map]
    · simp only [if_neg hv]
      have hr := remainingBytesAtV1_refinesSpine input afterLen
      unfold takeBytesAtV1 takeSpineBytesV1
      rw [hr]
      by_cases ht : lenU.toNat ≤ spineRemainingV1 input afterLen
      · simp only [if_pos ht, Except.map]
        congr 1
        · rw [ByteArray.data_extract, Array.toList_extract]
          simp [List.extract_eq_take_drop]
      · simp only [if_neg ht]
        rfl

/-- Decode and limit-check an array count on the transparent spine. Element
    decoding is deliberately outside this primitive. -/
def readArrayCountSpineV1 (input : TransparentByteSpineV1) (offset maxCount : Nat) :
    Except SemanticWireErrorV1 (Nat × Nat) :=
  match readSpineU32leV1 input offset with
  | .error e => .error e
  | .ok (countU, afterCount) =>
      let count := countU.toNat
      if count > maxCount then
        .error .limitExceeded
      else
        .ok (count, afterCount)

/-- Production array-count header primitive. -/
def readArrayCountAtV1 (input : ByteArray) (offset maxCount : Nat) :
    Except SemanticWireErrorV1 (Nat × Nat) :=
  match readU32leAtV1 input offset with
  | .error e => .error e
  | .ok (countU, afterCount) =>
      let count := countU.toNat
      if count > maxCount then
        .error .limitExceeded
      else
        .ok (count, afterCount)

/-- Array-count header refinement, including truncated prefix and limit
    precedence. -/
theorem readArrayCountAtV1_refinesSpine (input : TransparentByteSpineV1)
    (offset maxCount : Nat) :
    readArrayCountAtV1 (ByteArray.mk input.toArray) offset maxCount =
      readArrayCountSpineV1 input offset maxCount := by
  unfold readArrayCountAtV1 readArrayCountSpineV1
  rw [readU32leAtV1_refinesSpine]

/-- ASCII predicate used by the transparent tagged-header spine. -/
def isAsciiTagSpineBytesV1 (bytes : List UInt8) : Bool :=
  bytes.all fun byte => byte.toNat ≤ 127

/-- Production byte-level ASCII predicate for tagged headers. -/
def isAsciiTagBytesV1 (bytes : ByteArray) : Bool :=
  bytes.data.all fun byte => byte.toNat ≤ 127

/-- Read and validate the length-prefixed raw tag bytes on the transparent
    spine. Empty/oversized/non-ASCII tags are `.badTag`; short prefixes or
    payloads preserve `.truncated`. -/
def readTagSpineBytesV1 (input : TransparentByteSpineV1) (offset : Nat) :
    Except SemanticWireErrorV1 (List UInt8 × Nat) :=
  match readSpineU32leV1 input offset with
  | .error e => .error e
  | .ok (lenU, afterLen) =>
      let len := lenU.toNat
      if !(1 ≤ len && len ≤ maxTagAsciiBytes) then
        .error .badTag
      else
        match takeSpineBytesV1 input afterLen len with
        | .error e => .error e
        | .ok raw =>
            if isAsciiTagSpineBytesV1 raw then
              .ok (raw, afterLen + len)
            else
              .error .badTag

/-- Production byte-level tagged-header reader. It retains `ByteArray` slices
    and is shared by the String-facing decoder below. -/
def readTagBytesAtV1 (input : ByteArray) (offset : Nat) :
    Except SemanticWireErrorV1 (ByteArray × Nat) :=
  match readU32leAtV1 input offset with
  | .error e => .error e
  | .ok (lenU, afterLen) =>
      let len := lenU.toNat
      if !(1 ≤ len && len ≤ maxTagAsciiBytes) then
        .error .badTag
      else
        match takeBytesAtV1 input afterLen len with
        | .error e => .error e
        | .ok raw =>
            if isAsciiTagBytesV1 raw then
              .ok (raw, afterLen + len)
            else
              .error .badTag

/-- Raw tagged-header refinement through length decode, bounds, exact slice,
    and ASCII validation. -/
theorem readTagBytesAtV1_refinesSpine (input : TransparentByteSpineV1) (offset : Nat) :
    (readTagBytesAtV1 (ByteArray.mk input.toArray) offset).map
        (fun (raw, next) => (raw.data.toList, next)) =
      readTagSpineBytesV1 input offset := by
  unfold readTagBytesAtV1 readTagSpineBytesV1
  rw [readU32leAtV1_refinesSpine]
  cases hread : readSpineU32leV1 input offset with
  | error e => rfl
  | ok pair =>
    rcases pair with ⟨lenU, afterLen⟩
    by_cases hv : !(1 ≤ lenU.toNat && lenU.toNat ≤ maxTagAsciiBytes)
    · simp only [if_pos hv, Except.map]
    · simp only [if_neg hv]
      have hr := remainingBytesAtV1_refinesSpine input afterLen
      unfold takeBytesAtV1 takeSpineBytesV1
      rw [hr]
      by_cases ht : lenU.toNat ≤ spineRemainingV1 input afterLen
      · simp only [if_pos ht]
        let rawB :=
          (ByteArray.mk input.toArray).extract afterLen (afterLen + lenU.toNat)
        let rawS := (input.drop afterLen).take lenU.toNat
        have hraw : rawB.data.toList = rawS := by
          unfold rawB rawS
          rw [ByteArray.data_extract, Array.toList_extract]
          simp [List.extract_eq_take_drop]
        have hascii : isAsciiTagBytesV1 rawB = isAsciiTagSpineBytesV1 rawS := by
          unfold isAsciiTagBytesV1 isAsciiTagSpineBytesV1
          rw [← Array.all_toList, hraw]
        change (Except.map (fun (raw, next) => (raw.data.toList, next))
          (if isAsciiTagBytesV1 rawB then
            Except.ok (rawB, afterLen + lenU.toNat)
          else Except.error SemanticWireErrorV1.badTag)) =
          (if isAsciiTagSpineBytesV1 rawS then
            Except.ok (rawS, afterLen + lenU.toNat)
          else Except.error SemanticWireErrorV1.badTag)
        rw [hascii]
        by_cases ha : isAsciiTagSpineBytesV1 rawS
        · simp only [if_pos ha, Except.map]
          rw [hraw]
        · simp only [if_neg ha, Except.map]
      · simp only [if_neg ht]
        rfl

/-- Exact expected-tag plus field-count check on the transparent spine. -/
def expectTaggedHeaderSpineV1 (input : TransparentByteSpineV1) (offset : Nat)
    (want : List UInt8) (fieldCount : Nat) : Except SemanticWireErrorV1 Nat :=
  match readTagSpineBytesV1 input offset with
  | .error e => .error e
  | .ok (raw, next) =>
      if raw != want then
        .error .badTag
      else
        match readSpineU16leV1 input next with
        | .error e => .error e
        | .ok (count, afterCount) =>
            if count.toNat == fieldCount then
              .ok afterCount
            else
              .error .badFieldCount

/-- Production exact expected-tag plus field-count primitive. Expected and raw
    tags remain `ByteArray`s at runtime; List projection is proof-only. -/
def expectTaggedHeaderBytesAtV1 (input : ByteArray) (offset : Nat)
    (want : ByteArray) (fieldCount : Nat) : Except SemanticWireErrorV1 Nat :=
  match readTagBytesAtV1 input offset with
  | .error e => .error e
  | .ok (raw, next) =>
      if raw != want then
        .error .badTag
      else
        match readU16leAtV1 input next with
        | .error e => .error e
        | .ok (count, afterCount) =>
            if count.toNat == fieldCount then
              .ok afterCount
            else
              .error .badFieldCount

/-- Full expected tagged-header refinement: tag length/bytes/ASCII, exact tag
    comparison, u16 field count, and exact error precedence. -/
theorem expectTaggedHeaderBytesAtV1_refinesSpine (input want : List UInt8)
    (offset fieldCount : Nat) :
    expectTaggedHeaderBytesAtV1 (ByteArray.mk input.toArray) offset
        (ByteArray.mk want.toArray) fieldCount =
      expectTaggedHeaderSpineV1 input offset want fieldCount := by
  unfold expectTaggedHeaderBytesAtV1 expectTaggedHeaderSpineV1
  have ht := readTagBytesAtV1_refinesSpine input offset
  cases hs : readTagSpineBytesV1 input offset with
  | error e =>
    rw [hs] at ht
    cases hp : readTagBytesAtV1 (ByteArray.mk input.toArray) offset with
    | error ep =>
      rw [hp] at ht
      simp only [Except.map, Except.error.injEq] at ht
      subst ep
      rfl
    | ok productionPair =>
      rw [hp] at ht
      contradiction
  | ok spinePair =>
    rcases spinePair with ⟨rawS, next⟩
    rw [hs] at ht
    cases hp : readTagBytesAtV1 (ByteArray.mk input.toArray) offset with
    | error ep =>
      rw [hp] at ht
      contradiction
    | ok productionPair =>
      rcases productionPair with ⟨rawB, nextB⟩
      rw [hp] at ht
      simp only [Except.map, Except.ok.injEq, Prod.mk.injEq] at ht
      rcases ht with ⟨hraw, hnext⟩
      subst nextB
      have heq : (rawB == ByteArray.mk want.toArray) = (rawS == want) := by
        change (rawB.data == want.toArray) = (rawS == want)
        rw [← Array.beq_toList, hraw]
      have hne : (rawB != ByteArray.mk want.toArray) = (rawS != want) := by
        change (!(rawB == ByteArray.mk want.toArray)) = (!(rawS == want))
        rw [heq]
      simp only
      rw [hne]
      by_cases hm : rawS != want
      · simp only [if_pos hm]
      · simp only [if_neg hm]
        rw [readU16leAtV1_refinesSpine]

/-- Consume one exact magic/version prefix on the transparent proof spine.
    Short input remains `.truncated`; an equal-length mismatch is `.badMagic`. -/
def consumeMagicSpineBytesV1 (input : TransparentByteSpineV1) (offset : Nat)
    (want : List UInt8) : Except SemanticWireErrorV1 Nat :=
  match takeSpineBytesV1 input offset want.length with
  | .error e => .error e
  | .ok got =>
      if got == want then .ok (offset + want.length) else .error .badMagic

/-- Production exact magic/version-prefix primitive. -/
def consumeMagicBytesAtV1 (input : ByteArray) (offset : Nat) (want : ByteArray) :
    Except SemanticWireErrorV1 Nat :=
  match takeBytesAtV1 input offset want.size with
  | .error e => .error e
  | .ok got =>
      if got == want then .ok (offset + want.size) else .error .badMagic

/-- Magic/version-prefix refinement, preserving the `.truncated` versus
    `.badMagic` error boundary and the exact next offset. -/
theorem consumeMagicBytesAtV1_refinesSpine (input want : List UInt8) (offset : Nat) :
    consumeMagicBytesAtV1 (ByteArray.mk input.toArray) offset
        (ByteArray.mk want.toArray) =
      consumeMagicSpineBytesV1 input offset want := by
  have hs : (ByteArray.mk want.toArray).size = want.length := rfl
  have hr := remainingBytesAtV1_refinesSpine input offset
  unfold consumeMagicBytesAtV1 consumeMagicSpineBytesV1
    takeBytesAtV1 takeSpineBytesV1
  rw [hs, hr]
  by_cases h : want.length ≤ spineRemainingV1 input offset
  · simp only [if_pos h]
    change (if ((ByteArray.mk input.toArray).extract offset (offset + want.length)).data ==
        want.toArray then Except.ok (offset + want.length)
      else Except.error SemanticWireErrorV1.badMagic) =
      (if (input.drop offset).take want.length == want then
        Except.ok (offset + want.length)
      else Except.error SemanticWireErrorV1.badMagic)
    rw [ByteArray.data_extract, ← Array.beq_toList, Array.toList_extract]
    simp [List.extract_eq_take_drop]
  · simp only [if_neg h]

private def takeByte (c : Cursor) : Except SemanticWireErrorV1 (UInt8 × Cursor) := do
  let byte ← readByteAtV1 c.input c.offset
  pure (byte, ⟨c.input, c.offset + 1, c.nesting⟩)

private def takeBytes (c : Cursor) (n : Nat) :
    Except SemanticWireErrorV1 (ByteArray × Cursor) := do
  let bytes ← takeBytesAtV1 c.input c.offset n
  pure (bytes, ⟨c.input, c.offset + n, c.nesting⟩)

/-- Shared nesting frame for every tagged wire value (records + sums).
    Enter fails with `.limitExceeded` when `nesting ≥ maxNesting`.
    Non-tagged scalar/array-header readers do not call this. -/
def withTaggedNesting (body : Decoder α) : Decoder α := fun c => do
  unless c.nesting < maxNesting do
    return ← err .limitExceeded
  let parent := c.nesting
  let c : Cursor := ⟨c.input, c.offset, parent + 1⟩
  let (v, c) ← body c
  pure (v, ⟨c.input, c.offset, parent⟩)

def decodeU8 : Decoder UInt8 := takeByte

def decodeU16le : Decoder UInt16 := fun c => do
  let (value, offset) ← readU16leAtV1 c.input c.offset
  pure (value, ⟨c.input, offset, c.nesting⟩)

def decodeU32le : Decoder UInt32 := fun c => do
  let (value, offset) ← readU32leAtV1 c.input c.offset
  pure (value, ⟨c.input, offset, c.nesting⟩)

def decodeU64le : Decoder UInt64 := fun c => do
  let mut n : Nat := 0
  let mut place : Nat := 1
  let mut c := c
  for _ in [:8] do
    let (b, c') ← takeByte c
    c := c'
    n := n + b.toNat * place
    place := place * 256
  pure (UInt64.ofNat n, c)

def decodeBool : Decoder Bool := fun c => do
  let (m, c) ← decodeU8 c
  match m.toNat with
  | 0 => pure (false, c)
  | 1 => pure (true, c)
  | _ => err .badScalar

def decodeOption (decode : Decoder α) : Decoder (Option α) := fun c => do
  let (m, c) ← decodeU8 c
  match m.toNat with
  | 0 => pure (none, c)
  | 1 =>
    let (v, c) ← decode c
    pure (some v, c)
  | _ => err .badScalar

/-- Sole production array-element iteration authority. Keeping the loop in a
    structurally recursive definition gives kernel proofs a stable unfolding
    seam without introducing a proof-side decoder. -/
def decodeArrayElementsV1 (decode : Decoder α) :
    Nat → Array α → Cursor → Except SemanticWireErrorV1 (Array α × Cursor)
  | 0, acc, c => .ok (acc, c)
  | count + 1, acc, c =>
      match decode c with
      | .error e => .error e
      | .ok (v, c') => decodeArrayElementsV1 decode count (acc.push v) c'

def decodeArray (maxCount : Nat) (decode : Decoder α) : Decoder (Array α) := fun c =>
  match readArrayCountAtV1 c.input c.offset maxCount with
  | .error e => .error e
  | .ok (count, offset) =>
      decodeArrayElementsV1 decode count #[] ⟨c.input, offset, c.nesting⟩

/-- Compose an established count-header result with the sole production
    element iterator. -/
theorem decodeArray_eq_elementsV1 (maxCount : Nat) (decode : Decoder α) (c : Cursor)
    (count offset : Nat)
    (hcount : readArrayCountAtV1 c.input c.offset maxCount = .ok (count, offset)) :
    decodeArray maxCount decode c =
      decodeArrayElementsV1 decode count #[] ⟨c.input, offset, c.nesting⟩ := by
  simp only [decodeArray, hcount]

def decodeByteArray (maxLen : Nat) : Decoder ByteArray := fun c => do
  let (payload, offset) ← readSizedBytesAtV1 c.input c.offset maxLen
  pure (payload, ⟨c.input, offset, c.nesting⟩)

def decodeString : Decoder String := fun c => do
  let (raw, offset) ← readSizedBytesAtV1 c.input c.offset maxStringBytes
  let c : Cursor := ⟨c.input, offset, c.nesting⟩
  match String.fromUTF8? raw with
  | none => err .badScalar
  | some s => do
      match requireNfc s with
      | .error _ => err .badScalar
      | .ok _ => pure (s, c)

def decodeDigest : Decoder Digest := fun c => do
  let (bytes, c) ← takeBytes c 32
  let digest : Digest := { algorithm := .sha256, bytes }
  match validateDigest digest with
  | .error _ => err .badScalar
  | .ok _ => pure (digest, c)

def decodeNodeId : Decoder NodeId := fun c => do
  let (bytes, c) ← takeBytes c 16
  let nodeId : NodeId := { bytes }
  match validateNodeId nodeId with
  | .error _ => err .badScalar
  | .ok _ => pure (nodeId, c)

def decodeSchemaId : Decoder SchemaId := fun c => do
  let (s, c) ← decodeString c
  match parseSchemaId s with
  | .error _ => err .badScalar
  | .ok schema => pure (schema, c)

def decodeSemVer : Decoder SemVer := fun c => do
  let (s, c) ← decodeString c
  match parseSemVer s with
  | .error _ => err .badScalar
  | .ok version => pure (version, c)

def decodeQualifiedName : Decoder QualifiedName := fun c => do
  let (components, c) ← decodeArray 256 decodeString c
  match parseQualifiedName components with
  | .error _ => err .badScalar
  | .ok name => pure (name, c)

def decodeProjectRelativePath : Decoder ProjectRelativePath := fun c => do
  let (s, c) ← decodeString c
  match parseProjectRelativePath s with
  | .error _ => err .badScalar
  | .ok path => pure (path, c)

def decodeSourceOrigin : Decoder SourceOrigin := fun c => do
  let (sourcePath, c) ← decodeProjectRelativePath c
  let (startByte, c) ← decodeU64le c
  let (endByte, c) ← decodeU64le c
  let (nodeId, c) ← decodeNodeId c
  let origin : SourceOrigin := { sourcePath, startByte, endByte, nodeId }
  match validateSourceOrigin origin with
  | .error _ => err .badScalar
  | .ok _ => pure (origin, c)

def decodeTag : Decoder String := fun c => do
  let (raw, offset) ← readTagBytesAtV1 c.input c.offset
  let c : Cursor := ⟨c.input, offset, c.nesting⟩
  match String.fromUTF8? raw with
  | none => err .badTag
  | some tag => do
      unless isAsciiTag tag do
        return ← err .badTag
      pure (tag, c)

def decodeFieldCount (expected : Nat) : Decoder Unit := fun c => do
  let (count, c) ← decodeU16le c
  unless count.toNat == expected do
    return ← err .badFieldCount
  pure ((), c)

def expectTag (want : String) (fieldCount : Nat) : Decoder Unit := fun c => do
  let offset ← expectTaggedHeaderBytesAtV1 c.input c.offset want.toUTF8 fieldCount
  pure ((), ⟨c.input, offset, c.nesting⟩)

private def decodeNullary (want : String) : Decoder Unit :=
  expectTag want 0

/-! ### Visibility / type / callable kind encode+decode -/

def encodeVisibilityV1 : VisibilityV1 → Except SemanticWireErrorV1 ByteArray
  | .public_ => encodeNullary "Visibility.Public"
  | .private_ => encodeNullary "Visibility.Private"
  | .commitment => encodeNullary "Visibility.Commitment"

def decodeVisibilityV1 : Decoder VisibilityV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Visibility.Public" => pure (.public_, c)
  | "Visibility.Private" => pure (.private_, c)
  | "Visibility.Commitment" => pure (.commitment, c)
  | _ => err .badTag

def encodeFieldSpecV1 (spec : FieldSpecV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB ← encodeSchemaId spec.id
  let modB ← encodeByteArray spec.modulusBE
  encodeTagged "FieldSpec" #[idB, modB]

def decodeFieldSpecV1 : Decoder FieldSpecV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "FieldSpec" 2 c
  let (id, c) ← decodeSchemaId c
  let (modulusBE, c) ← decodeByteArray maxCanonicalProgramBytes c
  pure ({ id, modulusBE }, c)

def encodeStructFieldV1 (f : StructFieldV1) : Except SemanticWireErrorV1 ByteArray := do
  let nameB ← encodeString f.name
  let typeB := encodeU32le f.typeId
  encodeTagged "StructField" #[nameB, typeB]

def decodeStructFieldV1 : Decoder StructFieldV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "StructField" 2 c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  pure ({ name, typeId }, c)

def encodeEnumVariantV1 (v : EnumVariantV1) : Except SemanticWireErrorV1 ByteArray := do
  let nameB ← encodeString v.name
  let payloadB ← encodeArray (fun id => pure (encodeU32le id)) v.payloadTypes
  encodeTagged "EnumVariant" #[nameB, payloadB]

def decodeEnumVariantV1 : Decoder EnumVariantV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "EnumVariant" 2 c
  let (name, c) ← decodeString c
  let (payloadTypes, c) ← decodeArray maxArrayElements decodeU32le c
  pure ({ name, payloadTypes }, c)

def encodeTypeShapeV1 : TypeShapeV1 → Except SemanticWireErrorV1 ByteArray
  | .bool => encodeNullary "Type.Bool"
  | .uint w => do
      encodeTagged "Type.UInt" #[encodeU16le w]
  | .int w => do
      encodeTagged "Type.Int" #[encodeU16le w]
  | .principal => encodeNullary "Type.Principal"
  | .unit => encodeNullary "Type.Unit"
  | .bytes len => do
      encodeTagged "Type.Bytes" #[encodeU32le len]
  | .array element length => do
      encodeTagged "Type.Array" #[encodeU32le element, encodeU32le length]
  | .map key value => do
      encodeTagged "Type.Map" #[encodeU32le key, encodeU32le value]
  | .option element => do
      encodeTagged "Type.Option" #[encodeU32le element]
  | .field spec => do
      let specB ← encodeFieldSpecV1 spec
      encodeTagged "Type.Field" #[specB]
  | .struct fields => do
      let fieldsB ← encodeArray encodeStructFieldV1 fields
      encodeTagged "Type.Struct" #[fieldsB]
  | .enum variants => do
      let variantsB ← encodeArray encodeEnumVariantV1 variants
      encodeTagged "Type.Enum" #[variantsB]

def decodeTypeShapeV1 : Decoder TypeShapeV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Type.Bool" => do
      let ((), c) ← decodeFieldCount 0 c
      pure (.bool, c)
  | "Type.UInt" => do
      let ((), c) ← decodeFieldCount 1 c
      let (w, c) ← decodeU16le c
      pure (.uint w, c)
  | "Type.Int" => do
      let ((), c) ← decodeFieldCount 1 c
      let (w, c) ← decodeU16le c
      pure (.int w, c)
  | "Type.Principal" => do
      let ((), c) ← decodeFieldCount 0 c
      pure (.principal, c)
  | "Type.Unit" => do
      let ((), c) ← decodeFieldCount 0 c
      pure (.unit, c)
  | "Type.Bytes" => do
      let ((), c) ← decodeFieldCount 1 c
      let (len, c) ← decodeU32le c
      pure (.bytes len, c)
  | "Type.Array" => do
      let ((), c) ← decodeFieldCount 2 c
      let (element, c) ← decodeU32le c
      let (length, c) ← decodeU32le c
      pure (.array element length, c)
  | "Type.Map" => do
      let ((), c) ← decodeFieldCount 2 c
      let (key, c) ← decodeU32le c
      let (value, c) ← decodeU32le c
      pure (.map key value, c)
  | "Type.Option" => do
      let ((), c) ← decodeFieldCount 1 c
      let (element, c) ← decodeU32le c
      pure (.option element, c)
  | "Type.Field" => do
      let ((), c) ← decodeFieldCount 1 c
      let (spec, c) ← decodeFieldSpecV1 c
      pure (.field spec, c)
  | "Type.Struct" => do
      let ((), c) ← decodeFieldCount 1 c
      let (fields, c) ← decodeArray maxArrayElements decodeStructFieldV1 c
      pure (.struct fields, c)
  | "Type.Enum" => do
      let ((), c) ← decodeFieldCount 1 c
      let (variants, c) ← decodeArray maxArrayElements decodeEnumVariantV1 c
      pure (.enum variants, c)
  | _ => err .badTag

def encodeTypeDeclV1 (d : TypeDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeOption encodeString d.name
  let shapeB ← encodeTypeShapeV1 d.shape
  encodeTagged "TypeDecl" #[idB, nameB, shapeB]

def decodeTypeDeclV1 : Decoder TypeDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "TypeDecl" 3 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeOption decodeString c
  let (shape, c) ← decodeTypeShapeV1 c
  pure ({ id, name, shape }, c)

def encodeConstantV1 (d : ConstantV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeString d.name
  let typeB := encodeU32le d.typeId
  let valueB ← encodeByteArray d.valueBytes
  encodeTagged "Constant" #[idB, nameB, typeB, valueB]

def decodeConstantV1 : Decoder ConstantV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Constant" 4 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  let (valueBytes, c) ← decodeByteArray maxCanonicalProgramBytes c
  pure ({ id, name, typeId, valueBytes }, c)

def encodeStateDeclV1 (d : StateDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeString d.name
  let typeB := encodeU32le d.typeId
  let visB ← encodeVisibilityV1 d.visibility
  encodeTagged "StateDecl" #[idB, nameB, typeB, visB]

def decodeStateDeclV1 : Decoder StateDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "StateDecl" 4 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  let (visibility, c) ← decodeVisibilityV1 c
  pure ({ id, name, typeId, visibility }, c)

def encodeInterfaceFieldV1 (f : InterfaceFieldV1) : Except SemanticWireErrorV1 ByteArray := do
  let nameB ← encodeString f.name
  let typeB := encodeU32le f.typeId
  let visB ← encodeVisibilityV1 f.visibility
  encodeTagged "InterfaceField" #[nameB, typeB, visB]

def decodeInterfaceFieldV1 : Decoder InterfaceFieldV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "InterfaceField" 3 c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  let (visibility, c) ← decodeVisibilityV1 c
  pure ({ name, typeId, visibility }, c)

def encodeEventDeclV1 (d : EventDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeString d.name
  let fieldsB ← encodeArray encodeInterfaceFieldV1 d.fields
  encodeTagged "EventDecl" #[idB, nameB, fieldsB]

def decodeEventDeclV1 : Decoder EventDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "EventDecl" 3 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (fields, c) ← decodeArray maxArrayElements decodeInterfaceFieldV1 c
  pure ({ id, name, fields }, c)

def encodeErrorDeclV1 (d : ErrorDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeString d.name
  let fieldsB ← encodeArray encodeInterfaceFieldV1 d.fields
  encodeTagged "ErrorDecl" #[idB, nameB, fieldsB]

def decodeErrorDeclV1 : Decoder ErrorDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "ErrorDecl" 3 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (fields, c) ← decodeArray maxArrayElements decodeInterfaceFieldV1 c
  pure ({ id, name, fields }, c)

def encodeCallableKindV1 : CallableKindV1 → Except SemanticWireErrorV1 ByteArray
  | .initializer => encodeNullary "Callable.Initializer"
  | .entry => encodeNullary "Callable.Entry"
  | .view => encodeNullary "Callable.View"
  | .pureFn => encodeNullary "Callable.PureFn"
  | .invariant => encodeNullary "Callable.Invariant"

def decodeCallableKindV1 : Decoder CallableKindV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Callable.Initializer" => pure (.initializer, c)
  | "Callable.Entry" => pure (.entry, c)
  | "Callable.View" => pure (.view, c)
  | "Callable.PureFn" => pure (.pureFn, c)
  | "Callable.Invariant" => pure (.invariant, c)
  | _ => err .badTag

def encodeParameterV1 (p : ParameterV1) : Except SemanticWireErrorV1 ByteArray := do
  let valueB := encodeU32le p.valueId
  let nameB ← encodeString p.name
  let typeB := encodeU32le p.typeId
  let visB ← encodeVisibilityV1 p.visibility
  encodeTagged "Parameter" #[valueB, nameB, typeB, visB]

def decodeParameterV1 : Decoder ParameterV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Parameter" 4 c
  let (valueId, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  let (visibility, c) ← decodeVisibilityV1 c
  pure ({ valueId, name, typeId, visibility }, c)

def encodeCallableResultV1 (r : CallableResultV1) : Except SemanticWireErrorV1 ByteArray := do
  let typeB := encodeU32le r.typeId
  let visB ← encodeVisibilityV1 r.visibility
  encodeTagged "CallableResult" #[typeB, visB]

def decodeCallableResultV1 : Decoder CallableResultV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "CallableResult" 2 c
  let (typeId, c) ← decodeU32le c
  let (visibility, c) ← decodeVisibilityV1 c
  pure ({ typeId, visibility }, c)

def encodeValueDefV1 (v : ValueDefV1) : Except SemanticWireErrorV1 ByteArray := do
  encodeTagged "ValueDef" #[encodeU32le v.valueId, encodeU32le v.typeId]

def decodeValueDefV1 : Decoder ValueDefV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "ValueDef" 2 c
  let (valueId, c) ← decodeU32le c
  let (typeId, c) ← decodeU32le c
  pure ({ valueId, typeId }, c)

def encodeBlockParameterV1 (p : BlockParameterV1) : Except SemanticWireErrorV1 ByteArray := do
  encodeTagged "BlockParameter" #[encodeU32le p.valueId, encodeU32le p.typeId]

def decodeBlockParameterV1 : Decoder BlockParameterV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "BlockParameter" 2 c
  let (valueId, c) ← decodeU32le c
  let (typeId, c) ← decodeU32le c
  pure ({ valueId, typeId }, c)

def encodeUnaryOpV1 : UnaryOpV1 → Except SemanticWireErrorV1 ByteArray
  | .neg => encodeNullary "Unary.Neg"
  | .not => encodeNullary "Unary.Not"
  | .bitNot => encodeNullary "Unary.BitNot"

def decodeUnaryOpV1 : Decoder UnaryOpV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Unary.Neg" => pure (.neg, c)
  | "Unary.Not" => pure (.not, c)
  | "Unary.BitNot" => pure (.bitNot, c)
  | _ => err .badTag

def encodeBinaryOpV1 : BinaryOpV1 → Except SemanticWireErrorV1 ByteArray
  | .add => encodeNullary "Binary.Add"
  | .sub => encodeNullary "Binary.Sub"
  | .mul => encodeNullary "Binary.Mul"
  | .div => encodeNullary "Binary.Div"
  | .mod => encodeNullary "Binary.Mod"
  | .eq => encodeNullary "Binary.Eq"
  | .ne => encodeNullary "Binary.Ne"
  | .lt => encodeNullary "Binary.Lt"
  | .le => encodeNullary "Binary.Le"
  | .gt => encodeNullary "Binary.Gt"
  | .ge => encodeNullary "Binary.Ge"
  | .and => encodeNullary "Binary.And"
  | .or => encodeNullary "Binary.Or"
  | .bitAnd => encodeNullary "Binary.BitAnd"
  | .bitOr => encodeNullary "Binary.BitOr"
  | .bitXor => encodeNullary "Binary.BitXor"
  | .shl => encodeNullary "Binary.Shl"
  | .shr => encodeNullary "Binary.Shr"

def decodeBinaryOpV1 : Decoder BinaryOpV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Binary.Add" => pure (.add, c)
  | "Binary.Sub" => pure (.sub, c)
  | "Binary.Mul" => pure (.mul, c)
  | "Binary.Div" => pure (.div, c)
  | "Binary.Mod" => pure (.mod, c)
  | "Binary.Eq" => pure (.eq, c)
  | "Binary.Ne" => pure (.ne, c)
  | "Binary.Lt" => pure (.lt, c)
  | "Binary.Le" => pure (.le, c)
  | "Binary.Gt" => pure (.gt, c)
  | "Binary.Ge" => pure (.ge, c)
  | "Binary.And" => pure (.and, c)
  | "Binary.Or" => pure (.or, c)
  | "Binary.BitAnd" => pure (.bitAnd, c)
  | "Binary.BitOr" => pure (.bitOr, c)
  | "Binary.BitXor" => pure (.bitXor, c)
  | "Binary.Shl" => pure (.shl, c)
  | "Binary.Shr" => pure (.shr, c)
  | _ => err .badTag

def encodeValueIdArray (args : Array ValueIdV1) : Except SemanticWireErrorV1 ByteArray :=
  encodeArray (fun id => pure (encodeU32le id)) args

def encodeSemanticOpV1 : SemanticOpV1 → Except SemanticWireErrorV1 ByteArray
  | .literal typeId valueBytes => do
      let vb ← encodeByteArray valueBytes
      encodeTagged "Op.Literal" #[encodeU32le typeId, vb]
  | .constant constantId =>
      encodeTagged "Op.Constant" #[encodeU32le constantId]
  | .stateLoad stateId =>
      encodeTagged "Op.StateLoad" #[encodeU32le stateId]
  | .stateStore stateId value =>
      encodeTagged "Op.StateStore" #[encodeU32le stateId, encodeU32le value]
  | .construct typeId constructorIndex args => do
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.Construct" #[encodeU32le typeId, encodeU32le constructorIndex, argsB]
  | .fieldGet base fieldIndex =>
      encodeTagged "Op.FieldGet" #[encodeU32le base, encodeU32le fieldIndex]
  | .fieldSet base fieldIndex value =>
      encodeTagged "Op.FieldSet" #[encodeU32le base, encodeU32le fieldIndex, encodeU32le value]
  | .variantTag base =>
      encodeTagged "Op.VariantTag" #[encodeU32le base]
  | .variantPayload base variantIndex payloadIndex =>
      encodeTagged "Op.VariantPayload"
        #[encodeU32le base, encodeU32le variantIndex, encodeU32le payloadIndex]
  | .indexGet base index =>
      encodeTagged "Op.IndexGet" #[encodeU32le base, encodeU32le index]
  | .indexSet base index value =>
      encodeTagged "Op.IndexSet" #[encodeU32le base, encodeU32le index, encodeU32le value]
  | .checkedCast value toType =>
      encodeTagged "Op.CheckedCast" #[encodeU32le value, encodeU32le toType]
  | .unary op operand => do
      let opB ← encodeUnaryOpV1 op
      encodeTagged "Op.Unary" #[opB, encodeU32le operand]
  | .binary op lhs rhs => do
      let opB ← encodeBinaryOpV1 op
      encodeTagged "Op.Binary" #[opB, encodeU32le lhs, encodeU32le rhs]
  | .pureCall callableId args => do
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.PureCall" #[encodeU32le callableId, argsB]
  | .contextRead key => do
      let keyB ← encodeSchemaId key
      encodeTagged "Op.ContextRead" #[keyB]
  | .commit value =>
      encodeTagged "Op.Commit" #[encodeU32le value]
  | .assert_ condition errorId args => do
      let errB ← encodeOption (fun id => pure (encodeU32le id)) errorId
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.Assert" #[encodeU32le condition, errB, argsB]
  | .emit effectId eventId args => do
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.Emit" #[encodeU32le effectId, encodeU32le eventId, argsB]
  | .externalCall effectId callee args => do
      let calleeB ← encodeQualifiedName callee
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.ExternalCall" #[encodeU32le effectId, calleeB, argsB]
  | .schedule effectId callee args => do
      let calleeB ← encodeQualifiedName callee
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.Schedule" #[encodeU32le effectId, calleeB, argsB]

def decodeSemanticOpV1 : Decoder SemanticOpV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Op.Literal" => do
      let ((), c) ← decodeFieldCount 2 c
      let (typeId, c) ← decodeU32le c
      let (valueBytes, c) ← decodeByteArray maxCanonicalProgramBytes c
      pure (.literal typeId valueBytes, c)
  | "Op.Constant" => do
      let ((), c) ← decodeFieldCount 1 c
      let (constantId, c) ← decodeU32le c
      pure (.constant constantId, c)
  | "Op.StateLoad" => do
      let ((), c) ← decodeFieldCount 1 c
      let (stateId, c) ← decodeU32le c
      pure (.stateLoad stateId, c)
  | "Op.StateStore" => do
      let ((), c) ← decodeFieldCount 2 c
      let (stateId, c) ← decodeU32le c
      let (value, c) ← decodeU32le c
      pure (.stateStore stateId value, c)
  | "Op.Construct" => do
      let ((), c) ← decodeFieldCount 3 c
      let (typeId, c) ← decodeU32le c
      let (constructorIndex, c) ← decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.construct typeId constructorIndex args, c)
  | "Op.FieldGet" => do
      let ((), c) ← decodeFieldCount 2 c
      let (base, c) ← decodeU32le c
      let (fieldIndex, c) ← decodeU32le c
      pure (.fieldGet base fieldIndex, c)
  | "Op.FieldSet" => do
      let ((), c) ← decodeFieldCount 3 c
      let (base, c) ← decodeU32le c
      let (fieldIndex, c) ← decodeU32le c
      let (value, c) ← decodeU32le c
      pure (.fieldSet base fieldIndex value, c)
  | "Op.VariantTag" => do
      let ((), c) ← decodeFieldCount 1 c
      let (base, c) ← decodeU32le c
      pure (.variantTag base, c)
  | "Op.VariantPayload" => do
      let ((), c) ← decodeFieldCount 3 c
      let (base, c) ← decodeU32le c
      let (variantIndex, c) ← decodeU32le c
      let (payloadIndex, c) ← decodeU32le c
      pure (.variantPayload base variantIndex payloadIndex, c)
  | "Op.IndexGet" => do
      let ((), c) ← decodeFieldCount 2 c
      let (base, c) ← decodeU32le c
      let (index, c) ← decodeU32le c
      pure (.indexGet base index, c)
  | "Op.IndexSet" => do
      let ((), c) ← decodeFieldCount 3 c
      let (base, c) ← decodeU32le c
      let (index, c) ← decodeU32le c
      let (value, c) ← decodeU32le c
      pure (.indexSet base index value, c)
  | "Op.CheckedCast" => do
      let ((), c) ← decodeFieldCount 2 c
      let (value, c) ← decodeU32le c
      let (toType, c) ← decodeU32le c
      pure (.checkedCast value toType, c)
  | "Op.Unary" => do
      let ((), c) ← decodeFieldCount 2 c
      let (op, c) ← decodeUnaryOpV1 c
      let (operand, c) ← decodeU32le c
      pure (.unary op operand, c)
  | "Op.Binary" => do
      let ((), c) ← decodeFieldCount 3 c
      let (op, c) ← decodeBinaryOpV1 c
      let (lhs, c) ← decodeU32le c
      let (rhs, c) ← decodeU32le c
      pure (.binary op lhs rhs, c)
  | "Op.PureCall" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.pureCall callableId args, c)
  | "Op.ContextRead" => do
      let ((), c) ← decodeFieldCount 1 c
      let (key, c) ← decodeSchemaId c
      pure (.contextRead key, c)
  | "Op.Commit" => do
      let ((), c) ← decodeFieldCount 1 c
      let (value, c) ← decodeU32le c
      pure (.commit value, c)
  | "Op.Assert" => do
      let ((), c) ← decodeFieldCount 3 c
      let (condition, c) ← decodeU32le c
      let (errorId, c) ← decodeOption decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.assert_ condition errorId args, c)
  | "Op.Emit" => do
      let ((), c) ← decodeFieldCount 3 c
      let (effectId, c) ← decodeU32le c
      let (eventId, c) ← decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.emit effectId eventId args, c)
  | "Op.ExternalCall" => do
      let ((), c) ← decodeFieldCount 3 c
      let (effectId, c) ← decodeU32le c
      let (callee, c) ← decodeQualifiedName c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.externalCall effectId callee args, c)
  | "Op.Schedule" => do
      let ((), c) ← decodeFieldCount 3 c
      let (effectId, c) ← decodeU32le c
      let (callee, c) ← decodeQualifiedName c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.schedule effectId callee args, c)
  | _ => err .badTag

def encodeInstructionV1 (i : InstructionV1) : Except SemanticWireErrorV1 ByteArray := do
  let resultB ← encodeOption encodeValueDefV1 i.result
  let opB ← encodeSemanticOpV1 i.op
  encodeTagged "Instruction" #[resultB, opB]

def decodeInstructionV1 : Decoder InstructionV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Instruction" 2 c
  let (result, c) ← decodeOption decodeValueDefV1 c
  let (op, c) ← decodeSemanticOpV1 c
  pure ({ result, op }, c)

def encodeJumpTargetV1 (t : JumpTargetV1) : Except SemanticWireErrorV1 ByteArray := do
  let argsB ← encodeValueIdArray t.args
  encodeTagged "JumpTarget" #[encodeU32le t.blockId, argsB]

def decodeJumpTargetV1 : Decoder JumpTargetV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "JumpTarget" 2 c
  let (blockId, c) ← decodeU32le c
  let (args, c) ← decodeArray maxArrayElements decodeU32le c
  pure ({ blockId, args }, c)

def encodeSwitchCaseV1 (sc : SwitchCaseV1) : Except SemanticWireErrorV1 ByteArray := do
  let vb ← encodeByteArray sc.valueBytes
  let tb ← encodeJumpTargetV1 sc.target
  encodeTagged "SwitchCase" #[encodeU32le sc.typeId, vb, tb]

def decodeSwitchCaseV1 : Decoder SwitchCaseV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "SwitchCase" 3 c
  let (typeId, c) ← decodeU32le c
  let (valueBytes, c) ← decodeByteArray maxCanonicalProgramBytes c
  let (target, c) ← decodeJumpTargetV1 c
  pure ({ typeId, valueBytes, target }, c)

def encodeSemanticTrapCodeV1 : SemanticTrapCodeV1 → Except SemanticWireErrorV1 ByteArray
  | .unreachable => encodeNullary "Trap.Unreachable"
  | .invalidExternalResponse => encodeNullary "Trap.InvalidExternalResponse"
  | .resourceExhausted => encodeNullary "Trap.ResourceExhausted"
  | .internalInvariant => encodeNullary "Trap.InternalInvariant"

def decodeSemanticTrapCodeV1 : Decoder SemanticTrapCodeV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Trap.Unreachable" => pure (.unreachable, c)
  | "Trap.InvalidExternalResponse" => pure (.invalidExternalResponse, c)
  | "Trap.ResourceExhausted" => pure (.resourceExhausted, c)
  | "Trap.InternalInvariant" => pure (.internalInvariant, c)
  | _ => err .badTag

def encodeTerminatorV1 : TerminatorV1 → Except SemanticWireErrorV1 ByteArray
  | .jump target => do
      let tb ← encodeJumpTargetV1 target
      encodeTagged "Term.Jump" #[tb]
  | .branch condition thenTarget elseTarget => do
      let tB ← encodeJumpTargetV1 thenTarget
      let eB ← encodeJumpTargetV1 elseTarget
      encodeTagged "Term.Branch" #[encodeU32le condition, tB, eB]
  | .switch scrutinee cases defaultTarget => do
      let casesB ← encodeArray encodeSwitchCaseV1 cases
      let defB ← encodeOption encodeJumpTargetV1 defaultTarget
      encodeTagged "Term.Switch" #[encodeU32le scrutinee, casesB, defB]
  | .return_ value => do
      let vB ← encodeOption (fun id => pure (encodeU32le id)) value
      encodeTagged "Term.Return" #[vB]
  | .revert errorId args => do
      let argsB ← encodeValueIdArray args
      encodeTagged "Term.Revert" #[encodeU32le errorId, argsB]
  | .trap code => do
      let codeB ← encodeSemanticTrapCodeV1 code
      encodeTagged "Term.Trap" #[codeB]

def decodeTerminatorV1 : Decoder TerminatorV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Term.Jump" => do
      let ((), c) ← decodeFieldCount 1 c
      let (target, c) ← decodeJumpTargetV1 c
      pure (.jump target, c)
  | "Term.Branch" => do
      let ((), c) ← decodeFieldCount 3 c
      let (condition, c) ← decodeU32le c
      let (thenTarget, c) ← decodeJumpTargetV1 c
      let (elseTarget, c) ← decodeJumpTargetV1 c
      pure (.branch condition thenTarget elseTarget, c)
  | "Term.Switch" => do
      let ((), c) ← decodeFieldCount 3 c
      let (scrutinee, c) ← decodeU32le c
      let (cases, c) ← decodeArray maxArrayElements decodeSwitchCaseV1 c
      let (defaultTarget, c) ← decodeOption decodeJumpTargetV1 c
      pure (.switch scrutinee cases defaultTarget, c)
  | "Term.Return" => do
      let ((), c) ← decodeFieldCount 1 c
      let (value, c) ← decodeOption decodeU32le c
      pure (.return_ value, c)
  | "Term.Revert" => do
      let ((), c) ← decodeFieldCount 2 c
      let (errorId, c) ← decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.revert errorId args, c)
  | "Term.Trap" => do
      let ((), c) ← decodeFieldCount 1 c
      let (code, c) ← decodeSemanticTrapCodeV1 c
      pure (.trap code, c)
  | _ => err .badTag

def encodeBlockV1 (b : BlockV1) : Except SemanticWireErrorV1 ByteArray := do
  let paramsB ← encodeArray encodeBlockParameterV1 b.params
  let instrB ← encodeArray encodeInstructionV1 b.instructions
  let termB ← encodeTerminatorV1 b.terminator
  encodeTagged "Block" #[encodeU32le b.id, paramsB, instrB, termB]

def decodeBlockV1 : Decoder BlockV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Block" 4 c
  let (id, c) ← decodeU32le c
  let (params, c) ← decodeArray maxArrayElements decodeBlockParameterV1 c
  let (instructions, c) ← decodeArray maxArrayElements decodeInstructionV1 c
  let (terminator, c) ← decodeTerminatorV1 c
  pure ({ id, params, instructions, terminator }, c)

def encodeLoopBoundV1 (lb : LoopBoundV1) : Except SemanticWireErrorV1 ByteArray := do
  encodeTagged "LoopBound"
    #[encodeU32le lb.header, encodeU32le lb.backEdgeFrom, encodeU32le lb.maxIterations]

def decodeLoopBoundV1 : Decoder LoopBoundV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "LoopBound" 3 c
  let (header, c) ← decodeU32le c
  let (backEdgeFrom, c) ← decodeU32le c
  let (maxIterations, c) ← decodeU32le c
  pure ({ header, backEdgeFrom, maxIterations }, c)

def encodeCallableV1 (c : CallableV1) : Except SemanticWireErrorV1 ByteArray := do
  let kindB ← encodeCallableKindV1 c.kind
  let nameB ← encodeOption encodeString c.name
  let paramsB ← encodeArray encodeParameterV1 c.params
  let resultB ← encodeCallableResultV1 c.result
  let blocksB ← encodeArray encodeBlockV1 c.blocks
  let loopB ← encodeArray encodeLoopBoundV1 c.loopBounds
  let stepsB ← encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps
  encodeTagged "Callable" #[
    encodeU32le c.id, kindB, nameB, paramsB, resultB,
    encodeU32le c.entryBlock, blocksB, loopB, stepsB
  ]

def decodeCallableV1 : Decoder CallableV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Callable" 9 c
  let (id, c) ← decodeU32le c
  let (kind, c) ← decodeCallableKindV1 c
  let (name, c) ← decodeOption decodeString c
  let (params, c) ← decodeArray maxArrayElements decodeParameterV1 c
  let (result, c) ← decodeCallableResultV1 c
  let (entryBlock, c) ← decodeU32le c
  let (blocks, c) ← decodeArray maxArrayElements decodeBlockV1 c
  let (loopBounds, c) ← decodeArray maxArrayElements decodeLoopBoundV1 c
  let (invariantSteps, c) ← decodeOption decodeU64le c
  pure ({ id, kind, name, params, result, entryBlock, blocks, loopBounds, invariantSteps }, c)

def encodeInvariantDeclV1 (d : InvariantDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let nameB ← encodeString d.name
  encodeTagged "InvariantDecl" #[encodeU32le d.id, nameB, encodeU32le d.callableId]

def decodeInvariantDeclV1 : Decoder InvariantDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "InvariantDecl" 3 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (callableId, c) ← decodeU32le c
  pure ({ id, name, callableId }, c)

def encodeRequirementPredicateV1 :
    RequirementPredicateV1 → Except SemanticWireErrorV1 ByteArray
  | .uintAtLeast name value => do
      let nameB ← encodeString name
      encodeTagged "Req.UintAtLeast" #[nameB, encodeU64le value]
  | .uintAtMost name value => do
      let nameB ← encodeString name
      encodeTagged "Req.UintAtMost" #[nameB, encodeU64le value]
  | .boolEquals name value => do
      let nameB ← encodeString name
      encodeTagged "Req.BoolEquals" #[nameB, encodeBool value]
  | .enumContains name values => do
      let nameB ← encodeString name
      let valuesB ← encodeArray encodeString values
      encodeTagged "Req.EnumContains" #[nameB, valuesB]
  | .digestEquals name value => do
      let nameB ← encodeString name
      let digB ← encodeDigest value
      encodeTagged "Req.DigestEquals" #[nameB, digB]

def decodeRequirementPredicateV1 : Decoder RequirementPredicateV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Req.UintAtLeast" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (value, c) ← decodeU64le c
      pure (.uintAtLeast name value, c)
  | "Req.UintAtMost" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (value, c) ← decodeU64le c
      pure (.uintAtMost name value, c)
  | "Req.BoolEquals" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (value, c) ← decodeBool c
      pure (.boolEquals name value, c)
  | "Req.EnumContains" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (values, c) ← decodeArray maxArrayElements decodeString c
      pure (.enumContains name values, c)
  | "Req.DigestEquals" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (value, c) ← decodeDigest c
      pure (.digestEquals name value, c)
  | _ => err .badTag

def encodeRequirementRequestV1 (r : RequirementRequestV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let idB ← encodeString r.id
  let verB ← encodeSemVer r.version
  let digB ← encodeDigest r.digest
  let predB ← encodeArray encodeRequirementPredicateV1 r.predicates
  encodeTagged "RequirementRequest" #[idB, verB, digB, predB]

def decodeRequirementRequestV1 : Decoder RequirementRequestV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "RequirementRequest" 4 c
  let (id, c) ← decodeString c
  let (version, c) ← decodeSemVer c
  let (digest, c) ← decodeDigest c
  let (predicates, c) ← decodeArray maxArrayElements decodeRequirementPredicateV1 c
  pure ({ id, version, digest, predicates }, c)

def encodeProgramRequirementsV1 (r : ProgramRequirementsV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let itemsB ← encodeArray encodeRequirementRequestV1 r.items
  encodeTagged "ProgramRequirements" #[itemsB]

def decodeProgramRequirementsV1 : Decoder ProgramRequirementsV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "ProgramRequirements" 1 c
  let (items, c) ← decodeArray maxArrayElements decodeRequirementRequestV1 c
  pure ({ items }, c)

def encodeSemanticEntityRefV1 : SemanticEntityRefV1 → Except SemanticWireErrorV1 ByteArray
  | .typeRef id => encodeTagged "Entity.Type" #[encodeU32le id]
  | .constant id => encodeTagged "Entity.Constant" #[encodeU32le id]
  | .state id => encodeTagged "Entity.State" #[encodeU32le id]
  | .event id => encodeTagged "Entity.Event" #[encodeU32le id]
  | .errorRef id => encodeTagged "Entity.Error" #[encodeU32le id]
  | .callable id => encodeTagged "Entity.Callable" #[encodeU32le id]
  | .block callableId blockId =>
      encodeTagged "Entity.Block" #[encodeU32le callableId, encodeU32le blockId]
  | .instruction callableId blockId instructionIndex =>
      encodeTagged "Entity.Instruction"
        #[encodeU32le callableId, encodeU32le blockId, encodeU32le instructionIndex]
  | .terminator callableId blockId =>
      encodeTagged "Entity.Terminator" #[encodeU32le callableId, encodeU32le blockId]
  | .value callableId valueId =>
      encodeTagged "Entity.Value" #[encodeU32le callableId, encodeU32le valueId]
  | .effect callableId effectId =>
      encodeTagged "Entity.Effect" #[encodeU32le callableId, encodeU32le effectId]
  | .invariant id => encodeTagged "Entity.Invariant" #[encodeU32le id]
  | .requirement index => encodeTagged "Entity.Requirement" #[encodeU32le index]

def decodeSemanticEntityRefV1 : Decoder SemanticEntityRefV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Entity.Type" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.typeRef id, c)
  | "Entity.Constant" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.constant id, c)
  | "Entity.State" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.state id, c)
  | "Entity.Event" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.event id, c)
  | "Entity.Error" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.errorRef id, c)
  | "Entity.Callable" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.callable id, c)
  | "Entity.Block" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (blockId, c) ← decodeU32le c
      pure (.block callableId blockId, c)
  | "Entity.Instruction" => do
      let ((), c) ← decodeFieldCount 3 c
      let (callableId, c) ← decodeU32le c
      let (blockId, c) ← decodeU32le c
      let (instructionIndex, c) ← decodeU32le c
      pure (.instruction callableId blockId instructionIndex, c)
  | "Entity.Terminator" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (blockId, c) ← decodeU32le c
      pure (.terminator callableId blockId, c)
  | "Entity.Value" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (valueId, c) ← decodeU32le c
      pure (.value callableId valueId, c)
  | "Entity.Effect" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (effectId, c) ← decodeU32le c
      pure (.effect callableId effectId, c)
  | "Entity.Invariant" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.invariant id, c)
  | "Entity.Requirement" => do
      let ((), c) ← decodeFieldCount 1 c
      let (index, c) ← decodeU32le c
      pure (.requirement index, c)
  | _ => err .badTag

def encodeOriginBindingV1 (b : OriginBindingV1) : Except SemanticWireErrorV1 ByteArray := do
  let entityB ← encodeSemanticEntityRefV1 b.entity
  unless b.origins.size ≤ maxOriginsPerBinding do
    return ← err .limitExceeded
  let originsB ← encodeArray encodeSourceOrigin b.origins
  encodeTagged "OriginBinding" #[entityB, originsB]

def decodeOriginBindingV1 : Decoder OriginBindingV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "OriginBinding" 2 c
  let (entity, c) ← decodeSemanticEntityRefV1 c
  let (origins, c) ← decodeArray maxOriginsPerBinding decodeSourceOrigin c
  pure ({ entity, origins }, c)

/-! ### Root program / provenance encode+decode -/

/-- Internal WireV1 magic-prefix encoder (not a public contract). -/
def encodeMagicPrefix (magic : String) : ByteArray :=
  magic.toUTF8.push 0

/-- Internal WireV1 magic-prefix consumer (not a public contract). -/
def consumeMagic (magic : String) : Decoder Unit := fun c => do
  let want := encodeMagicPrefix magic
  let offset ← consumeMagicBytesAtV1 c.input c.offset want
  pure ((), ⟨c.input, offset, c.nesting⟩)

/-- Internal WireV1 table-size limit helper (not a public contract). -/
def checkTableSize (size : Nat) : Except SemanticWireErrorV1 Unit := do
  unless size ≤ maxTableElements do
    return ← err .limitExceeded
  pure ()

end ProofForgeV2.Semantic.WireV1
