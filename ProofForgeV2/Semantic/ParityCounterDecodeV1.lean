import ProofForgeV2.Semantic.ParityCounterShapeV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Core.Unicode

/-!
  Production transport decoder certificate for the closed EvenCounter instance.

  Proves `decodeSemanticProgramDataV1 ParityCounterShapeV1.canonicalBytes = .ok ParityCounterShapeV1.data`
  solely via production decoder composition/refinement theorems and the exact
  `canonicalSpine`. No second decoder, sorry, axiom, native_decide, ofReduceBool,
  run_tac, unsafe, meta, or IO.
-/

namespace ProofForgeV2.Semantic.ParityCounterDecodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Semantic.ParityCounterShapeV1

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

/-! ### Local production-composition helpers -/

private theorem decodeCanonicalTagV1 (offset after nesting : Nat)
    (raw : TransparentByteSpineV1) (value : String)
    (hspine : readTagSpineBytesV1 canonicalSpine offset = .ok (raw, after))
    (hutf8 : String.fromUTF8? (ByteArray.mk raw.toArray) = some value)
    (hascii : isAsciiTagV1 value = true) :
    decodeTag ⟨canonicalBytes, offset, nesting⟩ =
      .ok (value, ⟨canonicalBytes, after, nesting⟩) := by
  apply decodeTag_eq_of_valueV1 _ _ _ _ _ hutf8 hascii
  change readTagBytesAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (ByteArray.mk raw.toArray, after)
  exact readTagBytesAtV1_eq_of_spine canonicalSpine raw offset after hspine

private theorem decodeCanonicalFieldCountV1 (expected offset after nesting : Nat)
    (hspine : readSpineU16leV1 canonicalSpine offset =
      .ok (UInt16.ofNat expected, after))
    (hbound : expected < 65536) :
    decodeFieldCount expected ⟨canonicalBytes, offset, nesting⟩ =
      .ok ((), ⟨canonicalBytes, after, nesting⟩) := by
  have hread : readU16leAtV1 canonicalBytes offset =
      .ok (UInt16.ofNat expected, after) := by
    change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
      .ok (UInt16.ofNat expected, after)
    rw [readU16leAtV1_refinesSpine, hspine]
  have h := decodeFieldCount_eq_of_readU16leV1 expected
    ⟨canonicalBytes, offset, nesting⟩ (UInt16.ofNat expected) after hread
  have hmod : (UInt16.ofNat expected).toNat = expected := by
    simp [UInt16.toNat, UInt16.ofNat, Nat.mod_eq_of_lt hbound]
  rw [h, hmod]
  simp

private theorem decodeCanonicalU32V1 (offset after nesting value : Nat)
    (hspine : readSpineU32leV1 canonicalSpine offset =
      .ok (UInt32.ofNat value, after)) :
    decodeU32le ⟨canonicalBytes, offset, nesting⟩ =
      .ok (UInt32.ofNat value, ⟨canonicalBytes, after, nesting⟩) := by
  apply decodeU32le_eq_of_readV1
  change readU32leAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (UInt32.ofNat value, after)
  rw [readU32leAtV1_refinesSpine, hspine]

private theorem decodeCanonicalU16V1 (offset after nesting value : Nat)
    (hspine : readSpineU16leV1 canonicalSpine offset =
      .ok (UInt16.ofNat value, after)) :
    decodeU16le ⟨canonicalBytes, offset, nesting⟩ =
      .ok (UInt16.ofNat value, ⟨canonicalBytes, after, nesting⟩) := by
  apply decodeU16le_eq_of_readV1
  change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (UInt16.ofNat value, after)
  rw [readU16leAtV1_refinesSpine, hspine]

private theorem decodeCanonicalU64V1 (offset after nesting value : Nat)
    (hspine : readSpineU64leV1 canonicalSpine offset =
      .ok (UInt64.ofNat value, after)) :
    decodeU64le ⟨canonicalBytes, offset, nesting⟩ =
      .ok (UInt64.ofNat value, ⟨canonicalBytes, after, nesting⟩) := by
  apply decodeU64le_eq_of_readV1
  change readU64leAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (UInt64.ofNat value, after)
  rw [readU64leAtV1_refinesSpine, hspine]

private theorem decodeCanonicalU8V1 (offset nesting : Nat) (value : UInt8)
    (hspine : readSpineByteV1 canonicalSpine offset = .ok value) :
    decodeU8 ⟨canonicalBytes, offset, nesting⟩ =
      .ok (value, ⟨canonicalBytes, offset + 1, nesting⟩) := by
  apply decodeU8_eq_of_readV1
  change readByteAtV1 (ByteArray.mk canonicalSpine.toArray) offset = .ok value
  rw [readByteAtV1_refinesSpine, hspine]

private theorem expectTag_of_spine (want : String) (fields offset after nesting : Nat)
    (raw : TransparentByteSpineV1)
    (hwant : want.toUTF8 = ByteArray.mk raw.toArray)
    (hspine : expectTaggedHeaderSpineV1 canonicalSpine offset raw fields = .ok after) :
    expectTag want fields ⟨canonicalBytes, offset, nesting⟩ =
      .ok ((), ⟨canonicalBytes, after, nesting⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) offset
      want.toUTF8 fields = .ok after
  rw [hwant, expectTaggedHeaderBytesAtV1_refinesSpine, hspine]

private theorem decodeSemanticOpBodyV1_stateLoad
    (c afterTag afterFields afterState : Cursor) (stateId : UInt32)
    (htag : decodeTag c = .ok ("Op.StateLoad", afterTag))
    (hfields : decodeFieldCount 1 afterTag = .ok ((), afterFields))
    (hstate : decodeU32le afterFields = .ok (stateId, afterState)) :
    decodeSemanticOpBodyV1 c = .ok (.stateLoad stateId, afterState) := by
  simp only [decodeSemanticOpBodyV1, htag, hfields, hstate, Bind.bind, Pure.pure,
    Except.bind, Except.pure]

private theorem decodeSemanticOpV1_stateLoad
    (c afterTag afterFields afterState : Cursor) (stateId : UInt32)
    (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Op.StateLoad", afterTag))
    (hfields : decodeFieldCount 1 afterTag = .ok ((), afterFields))
    (hstate : decodeU32le afterFields = .ok (stateId, afterState)) :
    decodeSemanticOpV1 c = .ok (.stateLoad stateId,
      ⟨afterState.input, afterState.offset, c.nesting⟩) :=
  decodeSemanticOpV1_eq_of_bodyV1 c (.stateLoad stateId) afterState hdepth
    (decodeSemanticOpBodyV1_stateLoad ⟨c.input, c.offset, c.nesting + 1⟩ afterTag
      afterFields afterState stateId htag hfields hstate)

private theorem decodeSemanticOpBodyV1_stateStore
    (c afterTag afterFields afterState afterValue : Cursor)
    (stateId value : UInt32)
    (htag : decodeTag c = .ok ("Op.StateStore", afterTag))
    (hfields : decodeFieldCount 2 afterTag = .ok ((), afterFields))
    (hstate : decodeU32le afterFields = .ok (stateId, afterState))
    (hvalue : decodeU32le afterState = .ok (value, afterValue)) :
    decodeSemanticOpBodyV1 c = .ok (.stateStore stateId value, afterValue) := by
  simp only [decodeSemanticOpBodyV1, htag, hfields, hstate, hvalue, Bind.bind,
    Pure.pure, Except.bind, Except.pure]

private theorem decodeSemanticOpV1_stateStore
    (c afterTag afterFields afterState afterValue : Cursor)
    (stateId value : UInt32) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Op.StateStore", afterTag))
    (hfields : decodeFieldCount 2 afterTag = .ok ((), afterFields))
    (hstate : decodeU32le afterFields = .ok (stateId, afterState))
    (hvalue : decodeU32le afterState = .ok (value, afterValue)) :
    decodeSemanticOpV1 c = .ok (.stateStore stateId value,
      ⟨afterValue.input, afterValue.offset, c.nesting⟩) :=
  decodeSemanticOpV1_eq_of_bodyV1 c (.stateStore stateId value) afterValue hdepth
    (decodeSemanticOpBodyV1_stateStore ⟨c.input, c.offset, c.nesting + 1⟩ afterTag
      afterFields afterState afterValue stateId value htag hfields hstate hvalue)

private theorem decodeBinaryOpV1_add
    (c afterTag afterFields : Cursor) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Binary.Add", afterTag))
    (hfields : decodeFieldCount 0 afterTag = .ok ((), afterFields)) :
    decodeBinaryOpV1 c = .ok (.add, ⟨afterFields.input, afterFields.offset, c.nesting⟩) := by
  unfold decodeBinaryOpV1 withTaggedNesting
  simp only [hdepth, ↓reduceIte, htag, hfields, Bind.bind, Pure.pure, Except.bind,
    Except.pure]

private theorem decodeBinaryOpV1_mod
    (c afterTag afterFields : Cursor) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Binary.Mod", afterTag))
    (hfields : decodeFieldCount 0 afterTag = .ok ((), afterFields)) :
    decodeBinaryOpV1 c = .ok (.mod, ⟨afterFields.input, afterFields.offset, c.nesting⟩) := by
  unfold decodeBinaryOpV1 withTaggedNesting
  simp only [hdepth, ↓reduceIte, htag, hfields, Bind.bind, Pure.pure, Except.bind,
    Except.pure]

private theorem decodeBinaryOpV1_eqOp
    (c afterTag afterFields : Cursor) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Binary.Eq", afterTag))
    (hfields : decodeFieldCount 0 afterTag = .ok ((), afterFields)) :
    decodeBinaryOpV1 c = .ok (.eq, ⟨afterFields.input, afterFields.offset, c.nesting⟩) := by
  unfold decodeBinaryOpV1 withTaggedNesting
  simp only [hdepth, ↓reduceIte, htag, hfields, Bind.bind, Pure.pure, Except.bind,
    Except.pure]

private theorem decodeSemanticOpBodyV1_binary
    (c afterTag afterFields afterOp afterLhs afterRhs : Cursor)
    (op : BinaryOpV1) (lhs rhs : UInt32)
    (htag : decodeTag c = .ok ("Op.Binary", afterTag))
    (hfields : decodeFieldCount 3 afterTag = .ok ((), afterFields))
    (hop : decodeBinaryOpV1 afterFields = .ok (op, afterOp))
    (hlhs : decodeU32le afterOp = .ok (lhs, afterLhs))
    (hrhs : decodeU32le afterLhs = .ok (rhs, afterRhs)) :
    decodeSemanticOpBodyV1 c = .ok (.binary op lhs rhs, afterRhs) := by
  simp only [decodeSemanticOpBodyV1, htag, hfields, hop, hlhs, hrhs, Bind.bind,
    Pure.pure, Except.bind, Except.pure]

private theorem decodeSemanticOpV1_binary
    (c afterTag afterFields afterOp afterLhs afterRhs : Cursor)
    (op : BinaryOpV1) (lhs rhs : UInt32) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Op.Binary", afterTag))
    (hfields : decodeFieldCount 3 afterTag = .ok ((), afterFields))
    (hop : decodeBinaryOpV1 afterFields = .ok (op, afterOp))
    (hlhs : decodeU32le afterOp = .ok (lhs, afterLhs))
    (hrhs : decodeU32le afterLhs = .ok (rhs, afterRhs)) :
    decodeSemanticOpV1 c = .ok (.binary op lhs rhs,
      ⟨afterRhs.input, afterRhs.offset, c.nesting⟩) :=
  decodeSemanticOpV1_eq_of_bodyV1 c (.binary op lhs rhs) afterRhs hdepth
    (decodeSemanticOpBodyV1_binary ⟨c.input, c.offset, c.nesting + 1⟩ afterTag
      afterFields afterOp afterLhs afterRhs op lhs rhs htag hfields hop hlhs hrhs)

private theorem decodeArray_fiveV1 (maxCount : Nat) (decode : Decoder α) (c : Cursor)
    (offset : Nat) (v0 v1 v2 v3 v4 : α) (c1 c2 c3 c4 c5 : Cursor)
    (hcount : readArrayCountAtV1 c.input c.offset maxCount = .ok (5, offset))
    (h0 : decode ⟨c.input, offset, c.nesting⟩ = .ok (v0, c1))
    (h1 : decode c1 = .ok (v1, c2))
    (h2 : decode c2 = .ok (v2, c3))
    (h3 : decode c3 = .ok (v3, c4))
    (h4 : decode c4 = .ok (v4, c5)) :
    decodeArray maxCount decode c = .ok (#[v0, v1, v2, v3, v4], c5) := by
  apply decodeArray_eq_of_elementsV1 maxCount decode c 5 offset
    #[v0, v1, v2, v3, v4] c5 hcount
  simp [decodeArrayElementsV1, h0, h1, h2, h3, h4]

private theorem decodeRequirementRequestV1_eq_of_fields
    (c afterTag afterId afterVersion afterDigest afterPreds : Cursor)
    (id : String) (version : SemVer) (digest : Digest)
    (predicates : Array RequirementPredicateV1)
    (hdepth : c.nesting < maxNesting)
    (htag : expectTag "RequirementRequest" 4 ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ((), afterTag))
    (hid : decodeString afterTag = .ok (id, afterId))
    (hversion : decodeSemVer afterId = .ok (version, afterVersion))
    (hdigest : decodeDigest afterVersion = .ok (digest, afterDigest))
    (hpreds : decodeArray maxArrayElements decodeRequirementPredicateV1 afterDigest =
      .ok (predicates, afterPreds)) :
    decodeRequirementRequestV1 c =
      .ok ({ id, version, digest, predicates },
        ⟨afterPreds.input, afterPreds.offset, c.nesting⟩) := by
  unfold decodeRequirementRequestV1 withTaggedNesting
  simp only [hdepth, ↓reduceIte, htag, hid, hversion, hdigest, hpreds, Bind.bind,
    Pure.pure, Except.bind, Except.pure]

/-! ### Framing -/

private theorem consumeMagic_canonicalBytes :
    consumeMagic semanticProgramMagicV1 (start canonicalBytes) =
      .ok ((), ⟨canonicalBytes, 15, 0⟩) := by
  apply consumeMagic_eq_of_bytesV1
  change consumeMagicBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 0
      (ByteArray.mk [112, 102, 46, 115, 101, 109, 97, 110, 116, 105, 99, 46, 118,
        49, 0].toArray) = .ok 15
  rw [consumeMagicBytesAtV1_refinesSpine]
  unfold consumeMagicSpineBytesV1 takeSpineBytesV1 spineRemainingV1
  rw [canonicalSpine_length]
  rfl

private theorem expectRootTag_canonicalBytes :
    expectTag "SemanticProgram.Data" 9 ⟨canonicalBytes, 15, 1⟩ =
      .ok ((), ⟨canonicalBytes, 41, 1⟩) := by
  apply expectTag_eq_of_headerV1
  change expectTaggedHeaderBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 15
      (ByteArray.mk [83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103,
        114, 97, 109, 46, 68, 97, 116, 97].toArray) 9 = .ok 41
  rw [expectTaggedHeaderBytesAtV1_refinesSpine]
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

/-! ### QualifiedName -/

private theorem readQualifiedNameCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 41 256 = .ok (2, 45) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 41 256 = .ok (2, 45)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem readRootBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 45 maxStringBytes =
      .ok (ByteArray.mk [82, 111, 111, 116].toArray, 53) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 45 maxStringBytes =
    .ok (ByteArray.mk [82, 111, 111, 116].toArray, 53)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [82, 111, 111, 116]
      45 maxStringBytes 4 49
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem readEvenCounterBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 53 maxStringBytes =
      .ok (ByteArray.mk
        [69, 118, 101, 110, 67, 111, 117, 110, 116, 101, 114].toArray, 68) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 53 maxStringBytes =
    .ok (ByteArray.mk
      [69, 118, 101, 110, 67, 111, 117, 110, 116, 101, 114].toArray, 68)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
      [69, 118, 101, 110, 67, 111, 117, 110, 116, 101, 114]
      53 maxStringBytes 11 57
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeRootV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 45 maxStringBytes =
      .ok (ByteArray.mk [82, 111, 111, 116].toArray, 53)) :
    decodeString ⟨bytes, 45, 1⟩ = .ok ("Root", ⟨bytes, 53, 1⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "Root" (by decide)

private theorem decodeParityCounterV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 53 maxStringBytes =
      .ok (ByteArray.mk
        [69, 118, 101, 110, 67, 111, 117, 110, 116, 101, 114].toArray, 68)) :
    decodeString ⟨bytes, 53, 1⟩ = .ok ("EvenCounter", ⟨bytes, 68, 1⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "EvenCounter" (by decide)

private theorem decodeQualifiedName_canonicalBytes :
    decodeQualifiedName ⟨canonicalBytes, 41, 1⟩ =
      .ok (qualifiedName, ⟨canonicalBytes, 68, 1⟩) := by
  apply decodeQualifiedName_eq_of_arrayV1
  · apply decodeArray_twoV1
    · exact readQualifiedNameCount_canonicalBytes
    · exact decodeRootV1_of_read canonicalBytes readRootBytes_canonicalBytes
    · exact decodeParityCounterV1_of_read canonicalBytes
        readEvenCounterBytes_canonicalBytes
  · rfl

/-! ### Types (UInt64, Bool) 68→142 -/

private theorem readTypesCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 68 maxTableElements = .ok (2, 72) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 68 maxTableElements =
    .ok (2, 72)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem expectTypeDecl0_canonicalBytes :
    expectTag "TypeDecl" 3 ⟨canonicalBytes, 72, 2⟩ =
      .ok ((), ⟨canonicalBytes, 86, 2⟩) := by
  apply expectTag_of_spine "TypeDecl" 3 72 86 2
    [84, 121, 112, 101, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeTypeId0_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 86, 2⟩ = .ok (0, ⟨canonicalBytes, 90, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeNoTypeName0_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 90, 2⟩ =
      .ok (none, ⟨canonicalBytes, 91, 2⟩) := by
  apply decodeOption_noneV1
  apply decodeCanonicalU8V1
  rfl

private theorem decodeTypeShapeUInt64_canonicalBytes :
    decodeTypeShapeV1 ⟨canonicalBytes, 91, 2⟩ =
      .ok (.uint 64, ⟨canonicalBytes, 108, 2⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1 ⟨canonicalBytes, 91, 2⟩ (.uint 64)
    ⟨canonicalBytes, 108, 3⟩ (by decide) ?_
  apply decodeTypeShapeBodyV1_uint
  · apply decodeCanonicalTagV1 91 104 3
      [84, 121, 112, 101, 46, 85, 73, 110, 116] "Type.UInt"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 1 104 106 3 (by rfl) (by decide)
  · apply decodeCanonicalU16V1 106 108 3 64
    rfl

private theorem decodeTypeDecl0_canonicalBytes :
    decodeTypeDeclV1 ⟨canonicalBytes, 72, 1⟩ =
      .ok (uint64Type, ⟨canonicalBytes, 108, 1⟩) := by
  refine decodeTypeDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 72, 1⟩ uint64Type
    ⟨canonicalBytes, 108, 2⟩ (by decide) ?_
  apply decodeTypeDeclBodyV1_eq_of_fields
  · exact expectTypeDecl0_canonicalBytes
  · exact decodeTypeId0_canonicalBytes
  · exact decodeNoTypeName0_canonicalBytes
  · exact decodeTypeShapeUInt64_canonicalBytes

private theorem expectTypeDecl1_canonicalBytes :
    expectTag "TypeDecl" 3 ⟨canonicalBytes, 108, 2⟩ =
      .ok ((), ⟨canonicalBytes, 122, 2⟩) := by
  apply expectTag_of_spine "TypeDecl" 3 108 122 2
    [84, 121, 112, 101, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeTypeId1_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 122, 2⟩ = .ok (1, ⟨canonicalBytes, 126, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeNoTypeName1_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 126, 2⟩ =
      .ok (none, ⟨canonicalBytes, 127, 2⟩) := by
  apply decodeOption_noneV1
  apply decodeCanonicalU8V1
  rfl

private theorem decodeTypeShapeBool_canonicalBytes :
    decodeTypeShapeV1 ⟨canonicalBytes, 127, 2⟩ =
      .ok (.bool, ⟨canonicalBytes, 142, 2⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1 ⟨canonicalBytes, 127, 2⟩ .bool
    ⟨canonicalBytes, 142, 3⟩ (by decide) ?_
  apply decodeTypeShapeBodyV1_bool
  · apply decodeCanonicalTagV1 127 140 3
      [84, 121, 112, 101, 46, 66, 111, 111, 108] "Type.Bool"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 140 142 3 (by rfl) (by decide)

private theorem decodeTypeDecl1_canonicalBytes :
    decodeTypeDeclV1 ⟨canonicalBytes, 108, 1⟩ =
      .ok (boolType, ⟨canonicalBytes, 142, 1⟩) := by
  refine decodeTypeDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 108, 1⟩ boolType
    ⟨canonicalBytes, 142, 2⟩ (by decide) ?_
  apply decodeTypeDeclBodyV1_eq_of_fields
  · exact expectTypeDecl1_canonicalBytes
  · exact decodeTypeId1_canonicalBytes
  · exact decodeNoTypeName1_canonicalBytes
  · exact decodeTypeShapeBool_canonicalBytes

private theorem decodeTypes_canonicalBytes :
    decodeArray maxTableElements decodeTypeDeclV1 ⟨canonicalBytes, 68, 1⟩ =
      .ok (types, ⟨canonicalBytes, 142, 1⟩) := by
  have h := decodeArray_twoV1 maxTableElements decodeTypeDeclV1
    ⟨canonicalBytes, 68, 1⟩ 72 uint64Type boolType
    ⟨canonicalBytes, 108, 1⟩ ⟨canonicalBytes, 142, 1⟩
    readTypesCount_canonicalBytes decodeTypeDecl0_canonicalBytes
    decodeTypeDecl1_canonicalBytes
  simpa [types] using h

/-! ### Empty constants / events / errors + state -/

private theorem decodeConstants_canonicalBytes :
    decodeArray maxTableElements decodeConstantV1 ⟨canonicalBytes, 142, 1⟩ =
      .ok (#[], ⟨canonicalBytes, 146, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 142 maxTableElements =
    .ok (0, 146)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem readStateCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 146 maxTableElements = .ok (1, 150) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 146 maxTableElements =
    .ok (1, 150)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem expectStateDecl_canonicalBytes :
    expectTag "StateDecl" 4 ⟨canonicalBytes, 150, 2⟩ =
      .ok ((), ⟨canonicalBytes, 165, 2⟩) := by
  apply expectTag_of_spine "StateDecl" 4 150 165 2
    [83, 116, 97, 116, 101, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeStateId_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 165, 2⟩ = .ok (0, ⟨canonicalBytes, 169, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem readCountNameBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 169 maxStringBytes =
      .ok (ByteArray.mk [99, 111, 117, 110, 116].toArray, 178) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 169 maxStringBytes =
    .ok (ByteArray.mk [99, 111, 117, 110, 116].toArray, 178)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [99, 111, 117, 110, 116]
      169 maxStringBytes 5 173
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeStateName_canonicalBytes :
    decodeString ⟨canonicalBytes, 169, 2⟩ =
      .ok ("count", ⟨canonicalBytes, 178, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · exact readCountNameBytes_canonicalBytes
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "count" (by decide)

private theorem decodeStateTypeId_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 178, 2⟩ = .ok (0, ⟨canonicalBytes, 182, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeStateVisibility_canonicalBytes :
    decodeVisibilityV1 ⟨canonicalBytes, 182, 2⟩ =
      .ok (.public_, ⟨canonicalBytes, 205, 2⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 182, 2⟩ .public_
    ⟨canonicalBytes, 205, 3⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · apply decodeCanonicalTagV1 182 203 3
      [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
      "Visibility.Public"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 203 205 3 (by rfl) (by decide)

private theorem decodeStateDecl_canonicalBytes :
    decodeStateDeclV1 ⟨canonicalBytes, 150, 1⟩ =
      .ok (countState, ⟨canonicalBytes, 205, 1⟩) := by
  refine decodeStateDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 150, 1⟩ countState
    ⟨canonicalBytes, 205, 2⟩ (by decide) ?_
  apply decodeStateDeclBodyV1_eq_of_fields
  · exact expectStateDecl_canonicalBytes
  · exact decodeStateId_canonicalBytes
  · exact decodeStateName_canonicalBytes
  · exact decodeStateTypeId_canonicalBytes
  · exact decodeStateVisibility_canonicalBytes

private theorem decodeLogicalState_canonicalBytes :
    decodeArray maxTableElements decodeStateDeclV1 ⟨canonicalBytes, 146, 1⟩ =
      .ok (#[countState], ⟨canonicalBytes, 205, 1⟩) := by
  exact decodeArray_oneV1 maxTableElements decodeStateDeclV1
    ⟨canonicalBytes, 146, 1⟩ 150 countState ⟨canonicalBytes, 205, 1⟩
    readStateCount_canonicalBytes decodeStateDecl_canonicalBytes

private theorem decodeEvents_canonicalBytes :
    decodeArray maxTableElements decodeEventDeclV1 ⟨canonicalBytes, 205, 1⟩ =
      .ok (#[], ⟨canonicalBytes, 209, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 205 maxTableElements =
    .ok (0, 209)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem decodeErrors_canonicalBytes :
    decodeArray maxTableElements decodeErrorDeclV1 ⟨canonicalBytes, 209, 1⟩ =
      .ok (#[], ⟨canonicalBytes, 213, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 209 maxTableElements =
    .ok (0, 213)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

/-! ### increment instruction 0: StateLoad -/

private theorem expectIncI0Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 351, 4⟩ =
      .ok ((), ⟨canonicalBytes, 368, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 351 368 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectIncI0VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 369, 5⟩ =
      .ok ((), ⟨canonicalBytes, 383, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 369 383 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeIncI0VID :
    decodeU32le ⟨canonicalBytes, 383, 5⟩ =
      .ok (0, ⟨canonicalBytes, 387, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI0TID :
    decodeU32le ⟨canonicalBytes, 387, 5⟩ =
      .ok (0, ⟨canonicalBytes, 391, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI0ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 369, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 391, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 369, 4⟩
    ⟨canonicalBytes, 383, 5⟩ ⟨canonicalBytes, 387, 5⟩
    ⟨canonicalBytes, 391, 5⟩ 0 0 (by decide)
  · exact expectIncI0VD
  · exact decodeIncI0VID
  · exact decodeIncI0TID

private theorem decodeIncI0ResMark :
    decodeU8 ⟨canonicalBytes, 368, 4⟩ =
      .ok (1, ⟨canonicalBytes, 369, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeIncI0Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 368, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨canonicalBytes, 391, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 368, 4⟩
    ⟨canonicalBytes, 369, 4⟩
    ⟨canonicalBytes, 391, 4⟩
    { valueId := 0, typeId := 0 }
  · exact decodeIncI0ResMark
  · exact decodeIncI0ValueDef

private theorem decodeIncI0OpTag :
    decodeTag ⟨canonicalBytes, 391, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 407, 5⟩) := by
  apply decodeCanonicalTagV1 391 407 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeIncI0OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 407, 5⟩ =
      .ok ((), ⟨canonicalBytes, 409, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeIncI0StateId :
    decodeU32le ⟨canonicalBytes, 409, 5⟩ =
      .ok (0, ⟨canonicalBytes, 413, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI0Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 391, 4⟩ =
      .ok (.stateLoad 0, ⟨canonicalBytes, 413, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 391, 4⟩
    ⟨canonicalBytes, 407, 5⟩ ⟨canonicalBytes, 409, 5⟩
    ⟨canonicalBytes, 413, 5⟩ 0 (by decide)
  · exact decodeIncI0OpTag
  · exact decodeIncI0OpFc
  · exact decodeIncI0StateId

private theorem decodeIncI0Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 351, 3⟩ =
      .ok (valueInstruction 0 0 (.stateLoad 0), ⟨canonicalBytes, 413, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 351, 3⟩
    ⟨canonicalBytes, 368, 4⟩ ⟨canonicalBytes, 391, 4⟩ ⟨canonicalBytes, 413, 4⟩
    (some { valueId := 0, typeId := 0 }) (.stateLoad 0) (by decide)
    expectIncI0Instr decodeIncI0Result decodeIncI0Op
  simpa [valueInstruction, valueDef] using h

/-! ### increment instruction 1: Literal 2 -/

private theorem expectIncI1Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 413, 4⟩ =
      .ok ((), ⟨canonicalBytes, 430, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 413 430 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectIncI1VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 431, 5⟩ =
      .ok ((), ⟨canonicalBytes, 445, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 431 445 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeIncI1VID :
    decodeU32le ⟨canonicalBytes, 445, 5⟩ =
      .ok (1, ⟨canonicalBytes, 449, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI1TID :
    decodeU32le ⟨canonicalBytes, 449, 5⟩ =
      .ok (0, ⟨canonicalBytes, 453, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI1ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 431, 4⟩ =
      .ok ({ valueId := 1, typeId := 0 }, ⟨canonicalBytes, 453, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 431, 4⟩
    ⟨canonicalBytes, 445, 5⟩ ⟨canonicalBytes, 449, 5⟩
    ⟨canonicalBytes, 453, 5⟩ 1 0 (by decide)
  · exact expectIncI1VD
  · exact decodeIncI1VID
  · exact decodeIncI1TID

private theorem decodeIncI1ResMark :
    decodeU8 ⟨canonicalBytes, 430, 4⟩ =
      .ok (1, ⟨canonicalBytes, 431, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeIncI1Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 430, 4⟩ =
      .ok (some { valueId := 1, typeId := 0 },
        ⟨canonicalBytes, 453, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 430, 4⟩
    ⟨canonicalBytes, 431, 4⟩
    ⟨canonicalBytes, 453, 4⟩
    { valueId := 1, typeId := 0 }
  · exact decodeIncI1ResMark
  · exact decodeIncI1ValueDef

private theorem decodeIncI1OpTag :
    decodeTag ⟨canonicalBytes, 453, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 467, 5⟩) := by
  apply decodeCanonicalTagV1 453 467 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeIncI1OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 467, 5⟩ =
      .ok ((), ⟨canonicalBytes, 469, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeIncI1LitType :
    decodeU32le ⟨canonicalBytes, 469, 5⟩ =
      .ok (0, ⟨canonicalBytes, 473, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI1LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 473, 5⟩ =
      .ok (ByteArray.mk [2, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 485, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 473 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [2, 0, 0, 0, 0, 0, 0, 0].toArray, 485) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 473
      maxCanonicalProgramBytes = .ok (ByteArray.mk [2, 0, 0, 0, 0, 0, 0, 0].toArray, 485)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [2, 0, 0, 0, 0, 0, 0, 0]
        473 maxCanonicalProgramBytes 8 477
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeIncI1Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 453, 4⟩ =
      .ok (.literal 0 (ByteArray.mk [2, 0, 0, 0, 0, 0, 0, 0].toArray),
        ⟨canonicalBytes, 485, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 453, 4⟩
    ⟨canonicalBytes, 467, 5⟩ ⟨canonicalBytes, 469, 5⟩
    ⟨canonicalBytes, 473, 5⟩ ⟨canonicalBytes, 485, 5⟩
    0 (ByteArray.mk [2, 0, 0, 0, 0, 0, 0, 0].toArray) (by decide)
  · exact decodeIncI1OpTag
  · exact decodeIncI1OpFc
  · exact decodeIncI1LitType
  · exact decodeIncI1LitBytes

private theorem decodeIncI1Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 413, 3⟩ =
      .ok (valueInstruction 1 0 (.literal 0 twoBytes), ⟨canonicalBytes, 485, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 413, 3⟩
    ⟨canonicalBytes, 430, 4⟩ ⟨canonicalBytes, 453, 4⟩ ⟨canonicalBytes, 485, 4⟩
    (some { valueId := 1, typeId := 0 }) (.literal 0 twoBytes) (by decide)
    expectIncI1Instr decodeIncI1Result decodeIncI1Op
  simpa [valueInstruction, valueDef, twoBytes] using h

/-! ### increment instruction 2: Binary.Add -/

private theorem expectIncI2Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 485, 4⟩ =
      .ok ((), ⟨canonicalBytes, 502, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 485 502 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectIncI2VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 503, 5⟩ =
      .ok ((), ⟨canonicalBytes, 517, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 503 517 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeIncI2VID :
    decodeU32le ⟨canonicalBytes, 517, 5⟩ =
      .ok (2, ⟨canonicalBytes, 521, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI2TID :
    decodeU32le ⟨canonicalBytes, 521, 5⟩ =
      .ok (0, ⟨canonicalBytes, 525, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI2ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 503, 4⟩ =
      .ok ({ valueId := 2, typeId := 0 }, ⟨canonicalBytes, 525, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 503, 4⟩
    ⟨canonicalBytes, 517, 5⟩ ⟨canonicalBytes, 521, 5⟩
    ⟨canonicalBytes, 525, 5⟩ 2 0 (by decide)
  · exact expectIncI2VD
  · exact decodeIncI2VID
  · exact decodeIncI2TID

private theorem decodeIncI2ResMark :
    decodeU8 ⟨canonicalBytes, 502, 4⟩ =
      .ok (1, ⟨canonicalBytes, 503, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeIncI2Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 502, 4⟩ =
      .ok (some { valueId := 2, typeId := 0 },
        ⟨canonicalBytes, 525, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 502, 4⟩
    ⟨canonicalBytes, 503, 4⟩
    ⟨canonicalBytes, 525, 4⟩
    { valueId := 2, typeId := 0 }
  · exact decodeIncI2ResMark
  · exact decodeIncI2ValueDef

private theorem decodeIncI2OpTag :
    decodeTag ⟨canonicalBytes, 525, 5⟩ =
      .ok ("Op.Binary", ⟨canonicalBytes, 538, 5⟩) := by
  apply decodeCanonicalTagV1 525 538 5
    [79, 112, 46, 66, 105, 110, 97, 114, 121] "Op.Binary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeIncI2OpFc :
    decodeFieldCount 3 ⟨canonicalBytes, 538, 5⟩ =
      .ok ((), ⟨canonicalBytes, 540, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeIncI2BinTag :
    decodeTag ⟨canonicalBytes, 540, 6⟩ =
      .ok ("Binary.Add", ⟨canonicalBytes, 554, 6⟩) := by
  apply decodeCanonicalTagV1 540 554 6
    [66, 105, 110, 97, 114, 121, 46, 65, 100, 100] "Binary.Add"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeIncI2BinFc :
    decodeFieldCount 0 ⟨canonicalBytes, 554, 6⟩ =
      .ok ((), ⟨canonicalBytes, 556, 6⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeIncI2BinOp :
    decodeBinaryOpV1 ⟨canonicalBytes, 540, 5⟩ =
      .ok (.add, ⟨canonicalBytes, 556, 5⟩) := by
  apply decodeBinaryOpV1_add ⟨canonicalBytes, 540, 5⟩
    ⟨canonicalBytes, 554, 6⟩
    ⟨canonicalBytes, 556, 6⟩ (by decide)
  · exact decodeIncI2BinTag
  · exact decodeIncI2BinFc

private theorem decodeIncI2Lhs :
    decodeU32le ⟨canonicalBytes, 556, 5⟩ =
      .ok (0, ⟨canonicalBytes, 560, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI2Rhs :
    decodeU32le ⟨canonicalBytes, 560, 5⟩ =
      .ok (1, ⟨canonicalBytes, 564, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI2Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 525, 4⟩ =
      .ok (.binary .add 0 1, ⟨canonicalBytes, 564, 4⟩) := by
  apply decodeSemanticOpV1_binary ⟨canonicalBytes, 525, 4⟩
    ⟨canonicalBytes, 538, 5⟩ ⟨canonicalBytes, 540, 5⟩
    ⟨canonicalBytes, 556, 5⟩ ⟨canonicalBytes, 560, 5⟩
    ⟨canonicalBytes, 564, 5⟩ .add 0 1 (by decide)
  · exact decodeIncI2OpTag
  · exact decodeIncI2OpFc
  · exact decodeIncI2BinOp
  · exact decodeIncI2Lhs
  · exact decodeIncI2Rhs

private theorem decodeIncI2Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 485, 3⟩ =
      .ok (valueInstruction 2 0 (.binary .add 0 1), ⟨canonicalBytes, 564, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 485, 3⟩
    ⟨canonicalBytes, 502, 4⟩ ⟨canonicalBytes, 525, 4⟩ ⟨canonicalBytes, 564, 4⟩
    (some { valueId := 2, typeId := 0 }) (.binary .add 0 1) (by decide)
    expectIncI2Instr decodeIncI2Result decodeIncI2Op
  simpa [valueInstruction, valueDef] using h

/-! ### increment instruction 3: StateStore -/

private theorem expectIncI3Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 564, 4⟩ =
      .ok ((), ⟨canonicalBytes, 581, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 564 581 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeIncI3ResMark :
    decodeU8 ⟨canonicalBytes, 581, 4⟩ =
      .ok (0, ⟨canonicalBytes, 582, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeIncI3Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 581, 4⟩ =
      .ok (none, ⟨canonicalBytes, 582, 4⟩) := by
  apply decodeOption_noneV1
  exact decodeIncI3ResMark

private theorem decodeIncI3OpTag :
    decodeTag ⟨canonicalBytes, 582, 5⟩ =
      .ok ("Op.StateStore", ⟨canonicalBytes, 599, 5⟩) := by
  apply decodeCanonicalTagV1 582 599 5
    [79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101] "Op.StateStore"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeIncI3OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 599, 5⟩ =
      .ok ((), ⟨canonicalBytes, 601, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeIncI3StateId :
    decodeU32le ⟨canonicalBytes, 601, 5⟩ =
      .ok (0, ⟨canonicalBytes, 605, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI3Value :
    decodeU32le ⟨canonicalBytes, 605, 5⟩ =
      .ok (2, ⟨canonicalBytes, 609, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI3Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 582, 4⟩ =
      .ok (.stateStore 0 2, ⟨canonicalBytes, 609, 4⟩) := by
  apply decodeSemanticOpV1_stateStore ⟨canonicalBytes, 582, 4⟩
    ⟨canonicalBytes, 599, 5⟩ ⟨canonicalBytes, 601, 5⟩
    ⟨canonicalBytes, 605, 5⟩ ⟨canonicalBytes, 609, 5⟩
    0 2 (by decide)
  · exact decodeIncI3OpTag
  · exact decodeIncI3OpFc
  · exact decodeIncI3StateId
  · exact decodeIncI3Value

private theorem decodeIncI3Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 564, 3⟩ =
      .ok (voidInstruction (.stateStore 0 2), ⟨canonicalBytes, 609, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 564, 3⟩
    ⟨canonicalBytes, 581, 4⟩ ⟨canonicalBytes, 582, 4⟩ ⟨canonicalBytes, 609, 4⟩
    none (.stateStore 0 2) (by decide)
    expectIncI3Instr decodeIncI3Result decodeIncI3Op
  simpa [voidInstruction] using h

/-! ### increment instruction 4: StateLoad reload -/

private theorem expectIncI4Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 609, 4⟩ =
      .ok ((), ⟨canonicalBytes, 626, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 609 626 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectIncI4VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 627, 5⟩ =
      .ok ((), ⟨canonicalBytes, 641, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 627 641 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeIncI4VID :
    decodeU32le ⟨canonicalBytes, 641, 5⟩ =
      .ok (3, ⟨canonicalBytes, 645, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI4TID :
    decodeU32le ⟨canonicalBytes, 645, 5⟩ =
      .ok (0, ⟨canonicalBytes, 649, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI4ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 627, 4⟩ =
      .ok ({ valueId := 3, typeId := 0 }, ⟨canonicalBytes, 649, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 627, 4⟩
    ⟨canonicalBytes, 641, 5⟩ ⟨canonicalBytes, 645, 5⟩
    ⟨canonicalBytes, 649, 5⟩ 3 0 (by decide)
  · exact expectIncI4VD
  · exact decodeIncI4VID
  · exact decodeIncI4TID

private theorem decodeIncI4ResMark :
    decodeU8 ⟨canonicalBytes, 626, 4⟩ =
      .ok (1, ⟨canonicalBytes, 627, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeIncI4Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 626, 4⟩ =
      .ok (some { valueId := 3, typeId := 0 },
        ⟨canonicalBytes, 649, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 626, 4⟩
    ⟨canonicalBytes, 627, 4⟩
    ⟨canonicalBytes, 649, 4⟩
    { valueId := 3, typeId := 0 }
  · exact decodeIncI4ResMark
  · exact decodeIncI4ValueDef

private theorem decodeIncI4OpTag :
    decodeTag ⟨canonicalBytes, 649, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 665, 5⟩) := by
  apply decodeCanonicalTagV1 649 665 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeIncI4OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 665, 5⟩ =
      .ok ((), ⟨canonicalBytes, 667, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeIncI4StateId :
    decodeU32le ⟨canonicalBytes, 667, 5⟩ =
      .ok (0, ⟨canonicalBytes, 671, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncI4Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 649, 4⟩ =
      .ok (.stateLoad 0, ⟨canonicalBytes, 671, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 649, 4⟩
    ⟨canonicalBytes, 665, 5⟩ ⟨canonicalBytes, 667, 5⟩
    ⟨canonicalBytes, 671, 5⟩ 0 (by decide)
  · exact decodeIncI4OpTag
  · exact decodeIncI4OpFc
  · exact decodeIncI4StateId

private theorem decodeIncI4Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 609, 3⟩ =
      .ok (valueInstruction 3 0 (.stateLoad 0), ⟨canonicalBytes, 671, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 609, 3⟩
    ⟨canonicalBytes, 626, 4⟩ ⟨canonicalBytes, 649, 4⟩ ⟨canonicalBytes, 671, 4⟩
    (some { valueId := 3, typeId := 0 }) (.stateLoad 0) (by decide)
    expectIncI4Instr decodeIncI4Result decodeIncI4Op
  simpa [valueInstruction, valueDef] using h

/-! ### increment terminator -/

private theorem decodeIncTermTag :
    decodeTag ⟨canonicalBytes, 671, 4⟩ =
      .ok ("Term.Return", ⟨canonicalBytes, 686, 4⟩) := by
  apply decodeCanonicalTagV1 671 686 4
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeIncTermFc :
    decodeFieldCount 1 ⟨canonicalBytes, 686, 4⟩ =
      .ok ((), ⟨canonicalBytes, 688, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeIncTermMark :
    decodeU8 ⟨canonicalBytes, 688, 4⟩ =
      .ok (1, ⟨canonicalBytes, 689, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeIncTermVal :
    decodeU32le ⟨canonicalBytes, 689, 4⟩ =
      .ok (3, ⟨canonicalBytes, 693, 4⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncReturn :
    decodeTerminatorV1 ⟨canonicalBytes, 671, 3⟩ =
      .ok (.return_ (some 3), ⟨canonicalBytes, 693, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 671, 3⟩
    ⟨canonicalBytes, 686, 4⟩ ⟨canonicalBytes, 688, 4⟩ ⟨canonicalBytes, 693, 4⟩
    (some 3) (by decide)
  · exact decodeIncTermTag
  · exact decodeIncTermFc
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 688, 4⟩
      ⟨canonicalBytes, 689, 4⟩ ⟨canonicalBytes, 693, 4⟩ 3
    · exact decodeIncTermMark
    · exact decodeIncTermVal

private theorem decodeIncInstructions :
    decodeArray maxArrayElements decodeInstructionV1 ⟨canonicalBytes, 347, 3⟩ =
      .ok (incrementBlock.instructions, ⟨canonicalBytes, 671, 3⟩) := by
  have h := decodeArray_fiveV1 maxArrayElements decodeInstructionV1
    ⟨canonicalBytes, 347, 3⟩ 351
    (valueInstruction 0 0 (.stateLoad 0))
    (valueInstruction 1 0 (.literal 0 twoBytes))
    (valueInstruction 2 0 (.binary .add 0 1))
    (voidInstruction (.stateStore 0 2))
    (valueInstruction 3 0 (.stateLoad 0))
    ⟨canonicalBytes, 413, 3⟩ ⟨canonicalBytes, 485, 3⟩ ⟨canonicalBytes, 564, 3⟩
    ⟨canonicalBytes, 609, 3⟩ ⟨canonicalBytes, 671, 3⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 347
        maxArrayElements = .ok (5, 351)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeIncI0Instruction decodeIncI1Instruction decodeIncI2Instruction
    decodeIncI3Instruction decodeIncI4Instruction
  simpa [incrementBlock, valueInstruction, valueDef, voidInstruction, twoBytes] using h

private theorem expectIncBlock :
    expectTag "Block" 4 ⟨canonicalBytes, 328, 3⟩ =
      .ok ((), ⟨canonicalBytes, 339, 3⟩) := by
  apply expectTag_of_spine "Block" 4 328 339 3
    [66, 108, 111, 99, 107] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeIncBlockId :
    decodeU32le ⟨canonicalBytes, 339, 3⟩ = .ok (0, ⟨canonicalBytes, 343, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncBlock :
    decodeBlockV1 ⟨canonicalBytes, 328, 2⟩ =
      .ok (incrementBlock, ⟨canonicalBytes, 693, 2⟩) := by
  apply decodeBlockV1_eq_of_fieldsV1 ⟨canonicalBytes, 328, 2⟩
    ⟨canonicalBytes, 339, 3⟩ ⟨canonicalBytes, 343, 3⟩
    ⟨canonicalBytes, 347, 3⟩ ⟨canonicalBytes, 671, 3⟩ ⟨canonicalBytes, 693, 3⟩
    0 #[] incrementBlock.instructions (.return_ (some 3)) (by decide)
  · exact expectIncBlock
  · exact decodeIncBlockId
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 343
      maxArrayElements = .ok (0, 347)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeIncInstructions
  · exact decodeIncReturn

/-! ### increment callable -/

private theorem expectIncCallable :
    expectTag "Callable" 9 ⟨canonicalBytes, 217, 2⟩ =
      .ok ((), ⟨canonicalBytes, 231, 2⟩) := by
  apply expectTag_of_spine "Callable" 9 217 231 2
    [67, 97, 108, 108, 97, 98, 108, 101] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeIncId :
    decodeU32le ⟨canonicalBytes, 231, 2⟩ =
      .ok (0, ⟨canonicalBytes, 235, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncKindTag :
    decodeTag ⟨canonicalBytes, 235, 3⟩ =
      .ok ("Callable.Entry", ⟨canonicalBytes, 253, 3⟩) := by
  apply decodeCanonicalTagV1 235 253 3
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121] "Callable.Entry"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeIncKindFc :
    decodeFieldCount 0 ⟨canonicalBytes, 253, 3⟩ =
      .ok ((), ⟨canonicalBytes, 255, 3⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeIncKind :
    decodeCallableKindV1 ⟨canonicalBytes, 235, 2⟩ =
      .ok (.entry, ⟨canonicalBytes, 255, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 235, 2⟩ .entry
    ⟨canonicalBytes, 255, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_entry
  · exact decodeIncKindTag
  · exact decodeIncKindFc

private theorem decodeIncNameMark :
    decodeU8 ⟨canonicalBytes, 255, 2⟩ =
      .ok (1, ⟨canonicalBytes, 256, 2⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeIncNameStr :
    decodeString ⟨canonicalBytes, 256, 2⟩ =
      .ok ("increment", ⟨canonicalBytes, 269, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 256 maxStringBytes =
      .ok (ByteArray.mk [105, 110, 99, 114, 101, 109, 101, 110, 116].toArray, 269)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [105, 110, 99, 114, 101, 109, 101, 110, 116]
        256 maxStringBytes 9 260
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "increment" (by decide)

private theorem decodeIncName :
    decodeOption decodeString ⟨canonicalBytes, 255, 2⟩ =
      .ok (some "increment", ⟨canonicalBytes, 269, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 255, 2⟩
    ⟨canonicalBytes, 256, 2⟩ ⟨canonicalBytes, 269, 2⟩ "increment"
  · exact decodeIncNameMark
  · exact decodeIncNameStr

private theorem expectIncResult :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 273, 3⟩ =
      .ok ((), ⟨canonicalBytes, 293, 3⟩) := by
  apply expectTag_of_spine "CallableResult" 2 273 293 3
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeIncResultType :
    decodeU32le ⟨canonicalBytes, 293, 3⟩ =
      .ok (0, ⟨canonicalBytes, 297, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncVisTag :
    decodeTag ⟨canonicalBytes, 297, 4⟩ =
      .ok ("Visibility.Public", ⟨canonicalBytes, 318, 4⟩) := by
  apply decodeCanonicalTagV1 297 318 4
    [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99] "Visibility.Public"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeIncVisFc :
    decodeFieldCount 0 ⟨canonicalBytes, 318, 4⟩ =
      .ok ((), ⟨canonicalBytes, 320, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeIncVisibility :
    decodeVisibilityV1 ⟨canonicalBytes, 297, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 320, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 297, 3⟩ .public_
    ⟨canonicalBytes, 320, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · exact decodeIncVisTag
  · exact decodeIncVisFc

private theorem decodeIncResult :
    decodeCallableResultV1 ⟨canonicalBytes, 273, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨canonicalBytes, 320, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 273, 2⟩
    { typeId := 0, visibility := .public_ } ⟨canonicalBytes, 320, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectIncResult
  · exact decodeIncResultType
  · exact decodeIncVisibility

private theorem decodeIncEntryBlock :
    decodeU32le ⟨canonicalBytes, 320, 2⟩ =
      .ok (0, ⟨canonicalBytes, 324, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeIncCallable :
    decodeCallableV1 ⟨canonicalBytes, 217, 1⟩ =
      .ok (incrementCallable, ⟨canonicalBytes, 698, 1⟩) := by
  apply decodeCallableV1_singleBlockV1 ⟨canonicalBytes, 217, 1⟩
    ⟨canonicalBytes, 231, 2⟩ ⟨canonicalBytes, 235, 2⟩ ⟨canonicalBytes, 255, 2⟩
    ⟨canonicalBytes, 269, 2⟩ ⟨canonicalBytes, 320, 2⟩ ⟨canonicalBytes, 324, 2⟩
    ⟨canonicalBytes, 693, 2⟩ ⟨canonicalBytes, 698, 2⟩
    273 328 697 0 0 .entry (some "increment")
    { typeId := 0, visibility := .public_ } incrementBlock none (by decide)
  · exact expectIncCallable
  · exact decodeIncId
  · exact decodeIncKind
  · exact decodeIncName
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 269
      maxArrayElements = .ok (0, 273)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeIncResult
  · exact decodeIncEntryBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 324
      maxArrayElements = .ok (1, 328)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeIncBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 693
      maxArrayElements = .ok (0, 697)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · apply decodeOption_noneV1
    apply decodeCanonicalU8V1; rfl

/-! ### get callable -/

private theorem expectGetCallable :
    expectTag "Callable" 9 ⟨canonicalBytes, 698, 2⟩ =
      .ok ((), ⟨canonicalBytes, 712, 2⟩) := by
  apply expectTag_of_spine "Callable" 9 698 712 2
    [67, 97, 108, 108, 97, 98, 108, 101] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeGetId :
    decodeU32le ⟨canonicalBytes, 712, 2⟩ =
      .ok (1, ⟨canonicalBytes, 716, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetKindTag :
    decodeTag ⟨canonicalBytes, 716, 3⟩ =
      .ok ("Callable.View", ⟨canonicalBytes, 733, 3⟩) := by
  apply decodeCanonicalTagV1 716 733 3
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119] "Callable.View"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetKindFc :
    decodeFieldCount 0 ⟨canonicalBytes, 733, 3⟩ =
      .ok ((), ⟨canonicalBytes, 735, 3⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetKind :
    decodeCallableKindV1 ⟨canonicalBytes, 716, 2⟩ =
      .ok (.view, ⟨canonicalBytes, 735, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 716, 2⟩ .view
    ⟨canonicalBytes, 735, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_view
  · exact decodeGetKindTag
  · exact decodeGetKindFc

private theorem decodeGetNameMark :
    decodeU8 ⟨canonicalBytes, 735, 2⟩ =
      .ok (1, ⟨canonicalBytes, 736, 2⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeGetNameStr :
    decodeString ⟨canonicalBytes, 736, 2⟩ =
      .ok ("get", ⟨canonicalBytes, 743, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 736 maxStringBytes =
      .ok (ByteArray.mk [103, 101, 116].toArray, 743)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [103, 101, 116]
        736 maxStringBytes 3 740
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "get" (by decide)

private theorem decodeGetName :
    decodeOption decodeString ⟨canonicalBytes, 735, 2⟩ =
      .ok (some "get", ⟨canonicalBytes, 743, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 735, 2⟩
    ⟨canonicalBytes, 736, 2⟩ ⟨canonicalBytes, 743, 2⟩ "get"
  · exact decodeGetNameMark
  · exact decodeGetNameStr

private theorem expectGetResult :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 747, 3⟩ =
      .ok ((), ⟨canonicalBytes, 767, 3⟩) := by
  apply expectTag_of_spine "CallableResult" 2 747 767 3
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeGetResultType :
    decodeU32le ⟨canonicalBytes, 767, 3⟩ =
      .ok (0, ⟨canonicalBytes, 771, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetVisTag :
    decodeTag ⟨canonicalBytes, 771, 4⟩ =
      .ok ("Visibility.Public", ⟨canonicalBytes, 792, 4⟩) := by
  apply decodeCanonicalTagV1 771 792 4
    [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99] "Visibility.Public"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetVisFc :
    decodeFieldCount 0 ⟨canonicalBytes, 792, 4⟩ =
      .ok ((), ⟨canonicalBytes, 794, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetVisibility :
    decodeVisibilityV1 ⟨canonicalBytes, 771, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 794, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 771, 3⟩ .public_
    ⟨canonicalBytes, 794, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · exact decodeGetVisTag
  · exact decodeGetVisFc

private theorem decodeGetResult :
    decodeCallableResultV1 ⟨canonicalBytes, 747, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨canonicalBytes, 794, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 747, 2⟩
    { typeId := 0, visibility := .public_ } ⟨canonicalBytes, 794, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectGetResult
  · exact decodeGetResultType
  · exact decodeGetVisibility

private theorem decodeGetEntryBlock :
    decodeU32le ⟨canonicalBytes, 794, 2⟩ =
      .ok (0, ⟨canonicalBytes, 798, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

/-! ### get instruction -/

private theorem expectGetI0Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 825, 4⟩ =
      .ok ((), ⟨canonicalBytes, 842, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 825 842 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectGetI0VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 843, 5⟩ =
      .ok ((), ⟨canonicalBytes, 857, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 843 857 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeGetI0VID :
    decodeU32le ⟨canonicalBytes, 857, 5⟩ =
      .ok (0, ⟨canonicalBytes, 861, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetI0TID :
    decodeU32le ⟨canonicalBytes, 861, 5⟩ =
      .ok (0, ⟨canonicalBytes, 865, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetI0ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 843, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 865, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 843, 4⟩
    ⟨canonicalBytes, 857, 5⟩ ⟨canonicalBytes, 861, 5⟩
    ⟨canonicalBytes, 865, 5⟩ 0 0 (by decide)
  · exact expectGetI0VD
  · exact decodeGetI0VID
  · exact decodeGetI0TID

private theorem decodeGetI0ResMark :
    decodeU8 ⟨canonicalBytes, 842, 4⟩ =
      .ok (1, ⟨canonicalBytes, 843, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeGetI0Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 842, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨canonicalBytes, 865, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 842, 4⟩
    ⟨canonicalBytes, 843, 4⟩ ⟨canonicalBytes, 865, 4⟩
    { valueId := 0, typeId := 0 }
  · exact decodeGetI0ResMark
  · exact decodeGetI0ValueDef

private theorem decodeGetI0OpTag :
    decodeTag ⟨canonicalBytes, 865, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 881, 5⟩) := by
  apply decodeCanonicalTagV1 865 881 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetI0OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 881, 5⟩ =
      .ok ((), ⟨canonicalBytes, 883, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetI0StateId :
    decodeU32le ⟨canonicalBytes, 883, 5⟩ =
      .ok (0, ⟨canonicalBytes, 887, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetI0Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 865, 4⟩ =
      .ok (.stateLoad 0, ⟨canonicalBytes, 887, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 865, 4⟩
    ⟨canonicalBytes, 881, 5⟩ ⟨canonicalBytes, 883, 5⟩
    ⟨canonicalBytes, 887, 5⟩ 0 (by decide)
  · exact decodeGetI0OpTag
  · exact decodeGetI0OpFc
  · exact decodeGetI0StateId

private theorem decodeGetI0Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 825, 3⟩ =
      .ok (valueInstruction 0 0 (.stateLoad 0), ⟨canonicalBytes, 887, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 825, 3⟩
    ⟨canonicalBytes, 842, 4⟩ ⟨canonicalBytes, 865, 4⟩ ⟨canonicalBytes, 887, 4⟩
    (some { valueId := 0, typeId := 0 }) (.stateLoad 0) (by decide)
    expectGetI0Instr decodeGetI0Result decodeGetI0Op
  simpa [valueInstruction, valueDef] using h

private theorem decodeGetTermTag :
    decodeTag ⟨canonicalBytes, 887, 4⟩ =
      .ok ("Term.Return", ⟨canonicalBytes, 902, 4⟩) := by
  apply decodeCanonicalTagV1 887 902 4
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetTermFc :
    decodeFieldCount 1 ⟨canonicalBytes, 902, 4⟩ =
      .ok ((), ⟨canonicalBytes, 904, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetTermMark :
    decodeU8 ⟨canonicalBytes, 904, 4⟩ =
      .ok (1, ⟨canonicalBytes, 905, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeGetTermVal :
    decodeU32le ⟨canonicalBytes, 905, 4⟩ =
      .ok (0, ⟨canonicalBytes, 909, 4⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetReturn :
    decodeTerminatorV1 ⟨canonicalBytes, 887, 3⟩ =
      .ok (.return_ (some 0), ⟨canonicalBytes, 909, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 887, 3⟩
    ⟨canonicalBytes, 902, 4⟩ ⟨canonicalBytes, 904, 4⟩ ⟨canonicalBytes, 909, 4⟩
    (some 0) (by decide)
  · exact decodeGetTermTag
  · exact decodeGetTermFc
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 904, 4⟩
      ⟨canonicalBytes, 905, 4⟩ ⟨canonicalBytes, 909, 4⟩ 0
    · exact decodeGetTermMark
    · exact decodeGetTermVal

private theorem expectGetBlock :
    expectTag "Block" 4 ⟨canonicalBytes, 802, 3⟩ =
      .ok ((), ⟨canonicalBytes, 813, 3⟩) := by
  apply expectTag_of_spine "Block" 4 802 813 3
    [66, 108, 111, 99, 107] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeGetBlock :
    decodeBlockV1 ⟨canonicalBytes, 802, 2⟩ =
      .ok (getBlock, ⟨canonicalBytes, 909, 2⟩) := by
  apply decodeBlockV1_oneInstructionV1 ⟨canonicalBytes, 802, 2⟩
    ⟨canonicalBytes, 813, 3⟩ ⟨canonicalBytes, 817, 3⟩
    ⟨canonicalBytes, 887, 3⟩ ⟨canonicalBytes, 909, 3⟩
    821 825 0 (valueInstruction 0 0 (.stateLoad 0))
    (.return_ (some 0)) (by decide)
  · exact expectGetBlock
  · apply decodeCanonicalU32V1; rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 817
      maxArrayElements = .ok (0, 821)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 821
      maxArrayElements = .ok (1, 825)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeGetI0Instruction
  · exact decodeGetReturn

private theorem decodeGetCallable :
    decodeCallableV1 ⟨canonicalBytes, 698, 1⟩ =
      .ok (getCallable, ⟨canonicalBytes, 914, 1⟩) := by
  apply decodeCallableV1_singleBlockV1 ⟨canonicalBytes, 698, 1⟩
    ⟨canonicalBytes, 712, 2⟩ ⟨canonicalBytes, 716, 2⟩ ⟨canonicalBytes, 735, 2⟩
    ⟨canonicalBytes, 743, 2⟩ ⟨canonicalBytes, 794, 2⟩ ⟨canonicalBytes, 798, 2⟩
    ⟨canonicalBytes, 909, 2⟩ ⟨canonicalBytes, 914, 2⟩
    747 802 913 1 0 .view (some "get")
    { typeId := 0, visibility := .public_ } getBlock none (by decide)
  · exact expectGetCallable
  · exact decodeGetId
  · exact decodeGetKind
  · exact decodeGetName
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 743
      maxArrayElements = .ok (0, 747)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeGetResult
  · exact decodeGetEntryBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 798
      maxArrayElements = .ok (1, 802)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeGetBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 909
      maxArrayElements = .ok (0, 913)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · apply decodeOption_noneV1
    apply decodeCanonicalU8V1; rfl

/-! ### even invariant callable -/

private theorem expectEvenCallable :
    expectTag "Callable" 9 ⟨canonicalBytes, 914, 2⟩ =
      .ok ((), ⟨canonicalBytes, 928, 2⟩) := by
  apply expectTag_of_spine "Callable" 9 914 928 2
    [67, 97, 108, 108, 97, 98, 108, 101] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEvenId :
    decodeU32le ⟨canonicalBytes, 928, 2⟩ =
      .ok (2, ⟨canonicalBytes, 932, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenKindTag :
    decodeTag ⟨canonicalBytes, 932, 3⟩ =
      .ok ("Callable.Invariant", ⟨canonicalBytes, 954, 3⟩) := by
  apply decodeCanonicalTagV1 932 954 3
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116] "Callable.Invariant"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenKindFc :
    decodeFieldCount 0 ⟨canonicalBytes, 954, 3⟩ =
      .ok ((), ⟨canonicalBytes, 956, 3⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenKind :
    decodeCallableKindV1 ⟨canonicalBytes, 932, 2⟩ =
      .ok (.invariant, ⟨canonicalBytes, 956, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 932, 2⟩ .invariant
    ⟨canonicalBytes, 956, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_invariant
  · exact decodeEvenKindTag
  · exact decodeEvenKindFc

private theorem decodeEvenNameMark :
    decodeU8 ⟨canonicalBytes, 956, 2⟩ =
      .ok (1, ⟨canonicalBytes, 957, 2⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEvenNameStr :
    decodeString ⟨canonicalBytes, 957, 2⟩ =
      .ok ("even", ⟨canonicalBytes, 965, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 957 maxStringBytes =
      .ok (ByteArray.mk [101, 118, 101, 110].toArray, 965)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [101, 118, 101, 110]
        957 maxStringBytes 4 961
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "even" (by decide)

private theorem decodeEvenName :
    decodeOption decodeString ⟨canonicalBytes, 956, 2⟩ =
      .ok (some "even", ⟨canonicalBytes, 965, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 956, 2⟩
    ⟨canonicalBytes, 957, 2⟩ ⟨canonicalBytes, 965, 2⟩ "even"
  · exact decodeEvenNameMark
  · exact decodeEvenNameStr

private theorem expectEvenResult :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 969, 3⟩ =
      .ok ((), ⟨canonicalBytes, 989, 3⟩) := by
  apply expectTag_of_spine "CallableResult" 2 969 989 3
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEvenResultType :
    decodeU32le ⟨canonicalBytes, 989, 3⟩ =
      .ok (1, ⟨canonicalBytes, 993, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenVisTag :
    decodeTag ⟨canonicalBytes, 993, 4⟩ =
      .ok ("Visibility.Public", ⟨canonicalBytes, 1014, 4⟩) := by
  apply decodeCanonicalTagV1 993 1014 4
    [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99] "Visibility.Public"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenVisFc :
    decodeFieldCount 0 ⟨canonicalBytes, 1014, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1016, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenVisibility :
    decodeVisibilityV1 ⟨canonicalBytes, 993, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 1016, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 993, 3⟩ .public_
    ⟨canonicalBytes, 1016, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · exact decodeEvenVisTag
  · exact decodeEvenVisFc

private theorem decodeEvenResult :
    decodeCallableResultV1 ⟨canonicalBytes, 969, 2⟩ =
      .ok ({ typeId := 1, visibility := .public_ }, ⟨canonicalBytes, 1016, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 969, 2⟩
    { typeId := 1, visibility := .public_ } ⟨canonicalBytes, 1016, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectEvenResult
  · exact decodeEvenResultType
  · exact decodeEvenVisibility

private theorem decodeEvenEntryBlock :
    decodeU32le ⟨canonicalBytes, 1016, 2⟩ =
      .ok (0, ⟨canonicalBytes, 1020, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

/-! ### even instructions -/

private theorem expectEvenI0Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1047, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1064, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1047 1064 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEvenI0VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1065, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1079, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1065 1079 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEvenI0VID :
    decodeU32le ⟨canonicalBytes, 1079, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1083, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI0TID :
    decodeU32le ⟨canonicalBytes, 1083, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1087, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI0ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1065, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 1087, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1065, 4⟩
    ⟨canonicalBytes, 1079, 5⟩ ⟨canonicalBytes, 1083, 5⟩
    ⟨canonicalBytes, 1087, 5⟩ 0 0 (by decide)
  · exact expectEvenI0VD
  · exact decodeEvenI0VID
  · exact decodeEvenI0TID

private theorem decodeEvenI0ResMark :
    decodeU8 ⟨canonicalBytes, 1064, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1065, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEvenI0Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1064, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨canonicalBytes, 1087, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1064, 4⟩
    ⟨canonicalBytes, 1065, 4⟩ ⟨canonicalBytes, 1087, 4⟩
    { valueId := 0, typeId := 0 }
  · exact decodeEvenI0ResMark
  · exact decodeEvenI0ValueDef

private theorem decodeEvenI0OpTag :
    decodeTag ⟨canonicalBytes, 1087, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 1103, 5⟩) := by
  apply decodeCanonicalTagV1 1087 1103 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenI0OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 1103, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1105, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenI0StateId :
    decodeU32le ⟨canonicalBytes, 1105, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1109, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI0Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1087, 4⟩ =
      .ok (.stateLoad 0, ⟨canonicalBytes, 1109, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 1087, 4⟩
    ⟨canonicalBytes, 1103, 5⟩ ⟨canonicalBytes, 1105, 5⟩
    ⟨canonicalBytes, 1109, 5⟩ 0 (by decide)
  · exact decodeEvenI0OpTag
  · exact decodeEvenI0OpFc
  · exact decodeEvenI0StateId

private theorem decodeEvenI0Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1047, 3⟩ =
      .ok (valueInstruction 0 0 (.stateLoad 0), ⟨canonicalBytes, 1109, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1047, 3⟩
    ⟨canonicalBytes, 1064, 4⟩ ⟨canonicalBytes, 1087, 4⟩ ⟨canonicalBytes, 1109, 4⟩
    (some { valueId := 0, typeId := 0 }) (.stateLoad 0) (by decide)
    expectEvenI0Instr decodeEvenI0Result decodeEvenI0Op
  simpa [valueInstruction, valueDef] using h

private theorem expectEvenI1Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1109, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1126, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1109 1126 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEvenI1VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1127, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1141, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1127 1141 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEvenI1VID :
    decodeU32le ⟨canonicalBytes, 1141, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1145, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI1TID :
    decodeU32le ⟨canonicalBytes, 1145, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1149, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI1ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1127, 4⟩ =
      .ok ({ valueId := 1, typeId := 0 }, ⟨canonicalBytes, 1149, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1127, 4⟩
    ⟨canonicalBytes, 1141, 5⟩ ⟨canonicalBytes, 1145, 5⟩
    ⟨canonicalBytes, 1149, 5⟩ 1 0 (by decide)
  · exact expectEvenI1VD
  · exact decodeEvenI1VID
  · exact decodeEvenI1TID

private theorem decodeEvenI1ResMark :
    decodeU8 ⟨canonicalBytes, 1126, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1127, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEvenI1Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1126, 4⟩ =
      .ok (some { valueId := 1, typeId := 0 },
        ⟨canonicalBytes, 1149, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1126, 4⟩
    ⟨canonicalBytes, 1127, 4⟩ ⟨canonicalBytes, 1149, 4⟩
    { valueId := 1, typeId := 0 }
  · exact decodeEvenI1ResMark
  · exact decodeEvenI1ValueDef

private theorem decodeEvenI1OpTag :
    decodeTag ⟨canonicalBytes, 1149, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 1163, 5⟩) := by
  apply decodeCanonicalTagV1 1149 1163 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenI1OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 1163, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1165, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenI1LitType :
    decodeU32le ⟨canonicalBytes, 1165, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1169, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI1LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 1169, 5⟩ =
      .ok (ByteArray.mk [2, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 1181, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 1169 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [2, 0, 0, 0, 0, 0, 0, 0].toArray, 1181) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1169
      maxCanonicalProgramBytes = .ok (ByteArray.mk [2, 0, 0, 0, 0, 0, 0, 0].toArray, 1181)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [2, 0, 0, 0, 0, 0, 0, 0]
        1169 maxCanonicalProgramBytes 8 1173
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeEvenI1Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1149, 4⟩ =
      .ok (.literal 0 twoBytes, ⟨canonicalBytes, 1181, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 1149, 4⟩
    ⟨canonicalBytes, 1163, 5⟩ ⟨canonicalBytes, 1165, 5⟩
    ⟨canonicalBytes, 1169, 5⟩ ⟨canonicalBytes, 1181, 5⟩
    0 twoBytes (by decide)
  · exact decodeEvenI1OpTag
  · exact decodeEvenI1OpFc
  · exact decodeEvenI1LitType
  · simpa [twoBytes] using decodeEvenI1LitBytes

private theorem decodeEvenI1Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1109, 3⟩ =
      .ok (valueInstruction 1 0 (.literal 0 twoBytes), ⟨canonicalBytes, 1181, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1109, 3⟩
    ⟨canonicalBytes, 1126, 4⟩ ⟨canonicalBytes, 1149, 4⟩ ⟨canonicalBytes, 1181, 4⟩
    (some { valueId := 1, typeId := 0 }) (.literal 0 twoBytes) (by decide)
    expectEvenI1Instr decodeEvenI1Result decodeEvenI1Op
  simpa [valueInstruction, valueDef, twoBytes] using h

private theorem expectEvenI2Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1181, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1198, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1181 1198 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEvenI2VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1199, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1213, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1199 1213 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEvenI2VID :
    decodeU32le ⟨canonicalBytes, 1213, 5⟩ =
      .ok (2, ⟨canonicalBytes, 1217, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI2TID :
    decodeU32le ⟨canonicalBytes, 1217, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1221, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI2ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1199, 4⟩ =
      .ok ({ valueId := 2, typeId := 0 }, ⟨canonicalBytes, 1221, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1199, 4⟩
    ⟨canonicalBytes, 1213, 5⟩ ⟨canonicalBytes, 1217, 5⟩
    ⟨canonicalBytes, 1221, 5⟩ 2 0 (by decide)
  · exact expectEvenI2VD
  · exact decodeEvenI2VID
  · exact decodeEvenI2TID

private theorem decodeEvenI2ResMark :
    decodeU8 ⟨canonicalBytes, 1198, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1199, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEvenI2Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1198, 4⟩ =
      .ok (some { valueId := 2, typeId := 0 },
        ⟨canonicalBytes, 1221, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1198, 4⟩
    ⟨canonicalBytes, 1199, 4⟩ ⟨canonicalBytes, 1221, 4⟩
    { valueId := 2, typeId := 0 }
  · exact decodeEvenI2ResMark
  · exact decodeEvenI2ValueDef

private theorem decodeEvenI2OpTag :
    decodeTag ⟨canonicalBytes, 1221, 5⟩ =
      .ok ("Op.Binary", ⟨canonicalBytes, 1234, 5⟩) := by
  apply decodeCanonicalTagV1 1221 1234 5
    [79, 112, 46, 66, 105, 110, 97, 114, 121] "Op.Binary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenI2OpFc :
    decodeFieldCount 3 ⟨canonicalBytes, 1234, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1236, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenI2BinTag :
    decodeTag ⟨canonicalBytes, 1236, 6⟩ =
      .ok ("Binary.Mod", ⟨canonicalBytes, 1250, 6⟩) := by
  apply decodeCanonicalTagV1 1236 1250 6
    [66, 105, 110, 97, 114, 121, 46, 77, 111, 100] "Binary.Mod"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenI2BinFc :
    decodeFieldCount 0 ⟨canonicalBytes, 1250, 6⟩ =
      .ok ((), ⟨canonicalBytes, 1252, 6⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenI2BinOp :
    decodeBinaryOpV1 ⟨canonicalBytes, 1236, 5⟩ =
      .ok (.mod, ⟨canonicalBytes, 1252, 5⟩) := by
  apply decodeBinaryOpV1_mod ⟨canonicalBytes, 1236, 5⟩
    ⟨canonicalBytes, 1250, 6⟩
    ⟨canonicalBytes, 1252, 6⟩ (by decide)
  · exact decodeEvenI2BinTag
  · exact decodeEvenI2BinFc

private theorem decodeEvenI2Lhs :
    decodeU32le ⟨canonicalBytes, 1252, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1256, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI2Rhs :
    decodeU32le ⟨canonicalBytes, 1256, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1260, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI2Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1221, 4⟩ =
      .ok (.binary .mod 0 1, ⟨canonicalBytes, 1260, 4⟩) := by
  apply decodeSemanticOpV1_binary ⟨canonicalBytes, 1221, 4⟩
    ⟨canonicalBytes, 1234, 5⟩ ⟨canonicalBytes, 1236, 5⟩
    ⟨canonicalBytes, 1252, 5⟩ ⟨canonicalBytes, 1256, 5⟩
    ⟨canonicalBytes, 1260, 5⟩ .mod 0 1 (by decide)
  · exact decodeEvenI2OpTag
  · exact decodeEvenI2OpFc
  · exact decodeEvenI2BinOp
  · exact decodeEvenI2Lhs
  · exact decodeEvenI2Rhs

private theorem decodeEvenI2Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1181, 3⟩ =
      .ok (valueInstruction 2 0 (.binary .mod 0 1), ⟨canonicalBytes, 1260, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1181, 3⟩
    ⟨canonicalBytes, 1198, 4⟩ ⟨canonicalBytes, 1221, 4⟩ ⟨canonicalBytes, 1260, 4⟩
    (some { valueId := 2, typeId := 0 }) (.binary .mod 0 1) (by decide)
    expectEvenI2Instr decodeEvenI2Result decodeEvenI2Op
  simpa [valueInstruction, valueDef] using h

private theorem expectEvenI3Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1260, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1277, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1260 1277 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEvenI3VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1278, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1292, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1278 1292 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEvenI3VID :
    decodeU32le ⟨canonicalBytes, 1292, 5⟩ =
      .ok (3, ⟨canonicalBytes, 1296, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI3TID :
    decodeU32le ⟨canonicalBytes, 1296, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1300, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI3ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1278, 4⟩ =
      .ok ({ valueId := 3, typeId := 0 }, ⟨canonicalBytes, 1300, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1278, 4⟩
    ⟨canonicalBytes, 1292, 5⟩ ⟨canonicalBytes, 1296, 5⟩
    ⟨canonicalBytes, 1300, 5⟩ 3 0 (by decide)
  · exact expectEvenI3VD
  · exact decodeEvenI3VID
  · exact decodeEvenI3TID

private theorem decodeEvenI3ResMark :
    decodeU8 ⟨canonicalBytes, 1277, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1278, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEvenI3Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1277, 4⟩ =
      .ok (some { valueId := 3, typeId := 0 },
        ⟨canonicalBytes, 1300, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1277, 4⟩
    ⟨canonicalBytes, 1278, 4⟩ ⟨canonicalBytes, 1300, 4⟩
    { valueId := 3, typeId := 0 }
  · exact decodeEvenI3ResMark
  · exact decodeEvenI3ValueDef

private theorem decodeEvenI3OpTag :
    decodeTag ⟨canonicalBytes, 1300, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 1314, 5⟩) := by
  apply decodeCanonicalTagV1 1300 1314 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenI3OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 1314, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1316, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenI3LitType :
    decodeU32le ⟨canonicalBytes, 1316, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1320, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI3LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 1320, 5⟩ =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 1332, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 1320 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1332) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1320
      maxCanonicalProgramBytes = .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1332)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0, 0, 0, 0, 0, 0, 0, 0]
        1320 maxCanonicalProgramBytes 8 1324
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeEvenI3Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1300, 4⟩ =
      .ok (.literal 0 zeroBytes, ⟨canonicalBytes, 1332, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 1300, 4⟩
    ⟨canonicalBytes, 1314, 5⟩ ⟨canonicalBytes, 1316, 5⟩
    ⟨canonicalBytes, 1320, 5⟩ ⟨canonicalBytes, 1332, 5⟩
    0 zeroBytes (by decide)
  · exact decodeEvenI3OpTag
  · exact decodeEvenI3OpFc
  · exact decodeEvenI3LitType
  · simpa [zeroBytes] using decodeEvenI3LitBytes

private theorem decodeEvenI3Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1260, 3⟩ =
      .ok (valueInstruction 3 0 (.literal 0 zeroBytes), ⟨canonicalBytes, 1332, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1260, 3⟩
    ⟨canonicalBytes, 1277, 4⟩ ⟨canonicalBytes, 1300, 4⟩ ⟨canonicalBytes, 1332, 4⟩
    (some { valueId := 3, typeId := 0 }) (.literal 0 zeroBytes) (by decide)
    expectEvenI3Instr decodeEvenI3Result decodeEvenI3Op
  simpa [valueInstruction, valueDef, zeroBytes] using h

private theorem expectEvenI4Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1332, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1349, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1332 1349 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEvenI4VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1350, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1364, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1350 1364 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEvenI4VID :
    decodeU32le ⟨canonicalBytes, 1364, 5⟩ =
      .ok (4, ⟨canonicalBytes, 1368, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI4TID :
    decodeU32le ⟨canonicalBytes, 1368, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1372, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI4ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1350, 4⟩ =
      .ok ({ valueId := 4, typeId := 1 }, ⟨canonicalBytes, 1372, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1350, 4⟩
    ⟨canonicalBytes, 1364, 5⟩ ⟨canonicalBytes, 1368, 5⟩
    ⟨canonicalBytes, 1372, 5⟩ 4 1 (by decide)
  · exact expectEvenI4VD
  · exact decodeEvenI4VID
  · exact decodeEvenI4TID

private theorem decodeEvenI4ResMark :
    decodeU8 ⟨canonicalBytes, 1349, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1350, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEvenI4Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1349, 4⟩ =
      .ok (some { valueId := 4, typeId := 1 },
        ⟨canonicalBytes, 1372, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1349, 4⟩
    ⟨canonicalBytes, 1350, 4⟩ ⟨canonicalBytes, 1372, 4⟩
    { valueId := 4, typeId := 1 }
  · exact decodeEvenI4ResMark
  · exact decodeEvenI4ValueDef

private theorem decodeEvenI4OpTag :
    decodeTag ⟨canonicalBytes, 1372, 5⟩ =
      .ok ("Op.Binary", ⟨canonicalBytes, 1385, 5⟩) := by
  apply decodeCanonicalTagV1 1372 1385 5
    [79, 112, 46, 66, 105, 110, 97, 114, 121] "Op.Binary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenI4OpFc :
    decodeFieldCount 3 ⟨canonicalBytes, 1385, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1387, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenI4BinTag :
    decodeTag ⟨canonicalBytes, 1387, 6⟩ =
      .ok ("Binary.Eq", ⟨canonicalBytes, 1400, 6⟩) := by
  apply decodeCanonicalTagV1 1387 1400 6
    [66, 105, 110, 97, 114, 121, 46, 69, 113] "Binary.Eq"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenI4BinFc :
    decodeFieldCount 0 ⟨canonicalBytes, 1400, 6⟩ =
      .ok ((), ⟨canonicalBytes, 1402, 6⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenI4BinOp :
    decodeBinaryOpV1 ⟨canonicalBytes, 1387, 5⟩ =
      .ok (.eq, ⟨canonicalBytes, 1402, 5⟩) := by
  apply decodeBinaryOpV1_eqOp ⟨canonicalBytes, 1387, 5⟩
    ⟨canonicalBytes, 1400, 6⟩
    ⟨canonicalBytes, 1402, 6⟩ (by decide)
  · exact decodeEvenI4BinTag
  · exact decodeEvenI4BinFc

private theorem decodeEvenI4Lhs :
    decodeU32le ⟨canonicalBytes, 1402, 5⟩ =
      .ok (2, ⟨canonicalBytes, 1406, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI4Rhs :
    decodeU32le ⟨canonicalBytes, 1406, 5⟩ =
      .ok (3, ⟨canonicalBytes, 1410, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenI4Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1372, 4⟩ =
      .ok (.binary .eq 2 3, ⟨canonicalBytes, 1410, 4⟩) := by
  apply decodeSemanticOpV1_binary ⟨canonicalBytes, 1372, 4⟩
    ⟨canonicalBytes, 1385, 5⟩ ⟨canonicalBytes, 1387, 5⟩
    ⟨canonicalBytes, 1402, 5⟩ ⟨canonicalBytes, 1406, 5⟩
    ⟨canonicalBytes, 1410, 5⟩ .eq 2 3 (by decide)
  · exact decodeEvenI4OpTag
  · exact decodeEvenI4OpFc
  · exact decodeEvenI4BinOp
  · exact decodeEvenI4Lhs
  · exact decodeEvenI4Rhs

private theorem decodeEvenI4Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1332, 3⟩ =
      .ok (valueInstruction 4 1 (.binary .eq 2 3), ⟨canonicalBytes, 1410, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1332, 3⟩
    ⟨canonicalBytes, 1349, 4⟩ ⟨canonicalBytes, 1372, 4⟩ ⟨canonicalBytes, 1410, 4⟩
    (some { valueId := 4, typeId := 1 }) (.binary .eq 2 3) (by decide)
    expectEvenI4Instr decodeEvenI4Result decodeEvenI4Op
  simpa [valueInstruction, valueDef] using h

private theorem decodeEvenTermTag :
    decodeTag ⟨canonicalBytes, 1410, 4⟩ =
      .ok ("Term.Return", ⟨canonicalBytes, 1425, 4⟩) := by
  apply decodeCanonicalTagV1 1410 1425 4
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEvenTermFc :
    decodeFieldCount 1 ⟨canonicalBytes, 1425, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1427, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEvenTermMark :
    decodeU8 ⟨canonicalBytes, 1427, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1428, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEvenTermVal :
    decodeU32le ⟨canonicalBytes, 1428, 4⟩ =
      .ok (4, ⟨canonicalBytes, 1432, 4⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenReturn :
    decodeTerminatorV1 ⟨canonicalBytes, 1410, 3⟩ =
      .ok (.return_ (some 4), ⟨canonicalBytes, 1432, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 1410, 3⟩
    ⟨canonicalBytes, 1425, 4⟩ ⟨canonicalBytes, 1427, 4⟩ ⟨canonicalBytes, 1432, 4⟩
    (some 4) (by decide)
  · exact decodeEvenTermTag
  · exact decodeEvenTermFc
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 1427, 4⟩
      ⟨canonicalBytes, 1428, 4⟩ ⟨canonicalBytes, 1432, 4⟩ 4
    · exact decodeEvenTermMark
    · exact decodeEvenTermVal

private theorem decodeEvenInstructions :
    decodeArray maxArrayElements decodeInstructionV1 ⟨canonicalBytes, 1043, 3⟩ =
      .ok (evenBlock.instructions, ⟨canonicalBytes, 1410, 3⟩) := by
  have h := decodeArray_fiveV1 maxArrayElements decodeInstructionV1
    ⟨canonicalBytes, 1043, 3⟩ 1047
    (valueInstruction 0 0 (.stateLoad 0))
    (valueInstruction 1 0 (.literal 0 twoBytes))
    (valueInstruction 2 0 (.binary .mod 0 1))
    (valueInstruction 3 0 (.literal 0 zeroBytes))
    (valueInstruction 4 1 (.binary .eq 2 3))
    ⟨canonicalBytes, 1109, 3⟩ ⟨canonicalBytes, 1181, 3⟩ ⟨canonicalBytes, 1260, 3⟩
    ⟨canonicalBytes, 1332, 3⟩ ⟨canonicalBytes, 1410, 3⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1043
        maxArrayElements = .ok (5, 1047)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeEvenI0Instruction decodeEvenI1Instruction decodeEvenI2Instruction
    decodeEvenI3Instruction decodeEvenI4Instruction
  simpa [evenBlock, valueInstruction, valueDef, twoBytes, zeroBytes] using h

private theorem expectEvenBlock :
    expectTag "Block" 4 ⟨canonicalBytes, 1024, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1035, 3⟩) := by
  apply expectTag_of_spine "Block" 4 1024 1035 3
    [66, 108, 111, 99, 107] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeEvenBlock :
    decodeBlockV1 ⟨canonicalBytes, 1024, 2⟩ =
      .ok (evenBlock, ⟨canonicalBytes, 1432, 2⟩) := by
  apply decodeBlockV1_eq_of_fieldsV1 ⟨canonicalBytes, 1024, 2⟩
    ⟨canonicalBytes, 1035, 3⟩ ⟨canonicalBytes, 1039, 3⟩
    ⟨canonicalBytes, 1043, 3⟩ ⟨canonicalBytes, 1410, 3⟩ ⟨canonicalBytes, 1432, 3⟩
    0 #[] evenBlock.instructions (.return_ (some 4)) (by decide)
  · exact expectEvenBlock
  · apply decodeCanonicalU32V1; rfl
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1039
      maxArrayElements = .ok (0, 1043)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeEvenInstructions
  · exact decodeEvenReturn

private theorem decodeEvenSteps :
    decodeOption decodeU64le ⟨canonicalBytes, 1436, 2⟩ =
      .ok (some 7, ⟨canonicalBytes, 1445, 2⟩) := by
  apply decodeOption_someV1 decodeU64le ⟨canonicalBytes, 1436, 2⟩
    ⟨canonicalBytes, 1437, 2⟩ ⟨canonicalBytes, 1445, 2⟩ 7
  · apply decodeCanonicalU8V1; rfl
  · apply decodeCanonicalU64V1; rfl

private theorem decodeEvenCallable :
    decodeCallableV1 ⟨canonicalBytes, 914, 1⟩ =
      .ok (evenCallable, ⟨canonicalBytes, 1445, 1⟩) := by
  apply decodeCallableV1_singleBlockV1 ⟨canonicalBytes, 914, 1⟩
    ⟨canonicalBytes, 928, 2⟩ ⟨canonicalBytes, 932, 2⟩ ⟨canonicalBytes, 956, 2⟩
    ⟨canonicalBytes, 965, 2⟩ ⟨canonicalBytes, 1016, 2⟩ ⟨canonicalBytes, 1020, 2⟩
    ⟨canonicalBytes, 1432, 2⟩ ⟨canonicalBytes, 1445, 2⟩
    969 1024 1436 2 0 .invariant (some "even")
    { typeId := 1, visibility := .public_ } evenBlock (some 7) (by decide)
  · exact expectEvenCallable
  · exact decodeEvenId
  · exact decodeEvenKind
  · exact decodeEvenName
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 965
      maxArrayElements = .ok (0, 969)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeEvenResult
  · exact decodeEvenEntryBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1020
      maxArrayElements = .ok (1, 1024)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeEvenBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1432
      maxArrayElements = .ok (0, 1436)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeEvenSteps

private theorem readCallablesCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 213 maxTableElements = .ok (3, 217) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 213 maxTableElements =
    .ok (3, 217)
  rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem decodeCallables_canonicalBytes :
    decodeArray maxTableElements decodeCallableV1 ⟨canonicalBytes, 213, 1⟩ =
      .ok (#[incrementCallable, getCallable, evenCallable],
        ⟨canonicalBytes, 1445, 1⟩) := by
  exact decodeArray_threeV1 maxTableElements decodeCallableV1
    ⟨canonicalBytes, 213, 1⟩ 217 incrementCallable getCallable evenCallable
    ⟨canonicalBytes, 698, 1⟩ ⟨canonicalBytes, 914, 1⟩ ⟨canonicalBytes, 1445, 1⟩
    readCallablesCount_canonicalBytes decodeIncCallable decodeGetCallable
    decodeEvenCallable

/-! ### invariants -/

private theorem readInvariantsCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 1445 maxTableElements = .ok (1, 1449) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1445 maxTableElements =
    .ok (1, 1449)
  rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem expectEvenInvDecl :
    expectTag "InvariantDecl" 3 ⟨canonicalBytes, 1449, 2⟩ =
      .ok ((), ⟨canonicalBytes, 1468, 2⟩) := by
  apply expectTag_of_spine "InvariantDecl" 3 1449 1468 2
    [73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEvenInvId :
    decodeU32le ⟨canonicalBytes, 1468, 2⟩ =
      .ok (0, ⟨canonicalBytes, 1472, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenInvName :
    decodeString ⟨canonicalBytes, 1472, 2⟩ =
      .ok ("even", ⟨canonicalBytes, 1480, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1472 maxStringBytes =
      .ok (ByteArray.mk [101, 118, 101, 110].toArray, 1480)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [101, 118, 101, 110]
        1472 maxStringBytes 4 1476
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "even" (by decide)

private theorem decodeEvenInvCallable :
    decodeU32le ⟨canonicalBytes, 1480, 2⟩ =
      .ok (2, ⟨canonicalBytes, 1484, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEvenInvDecl :
    decodeInvariantDeclV1 ⟨canonicalBytes, 1449, 1⟩ =
      .ok (evenInvariant, ⟨canonicalBytes, 1484, 1⟩) := by
  refine decodeInvariantDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 1449, 1⟩ evenInvariant
    ⟨canonicalBytes, 1484, 2⟩ (by decide) ?_
  apply decodeInvariantDeclBodyV1_eq_of_fields
  · exact expectEvenInvDecl
  · exact decodeEvenInvId
  · exact decodeEvenInvName
  · exact decodeEvenInvCallable

private theorem decodeInvariants_canonicalBytes :
    decodeArray maxTableElements decodeInvariantDeclV1 ⟨canonicalBytes, 1445, 1⟩ =
      .ok (#[evenInvariant], ⟨canonicalBytes, 1484, 1⟩) := by
  exact decodeArray_oneV1 maxTableElements decodeInvariantDeclV1
    ⟨canonicalBytes, 1445, 1⟩ 1449 evenInvariant ⟨canonicalBytes, 1484, 1⟩
    readInvariantsCount_canonicalBytes decodeEvenInvDecl

/-! ### requirements -/

private theorem expectProgramRequirements :
    expectTag "ProgramRequirements" 1 ⟨canonicalBytes, 1484, 2⟩ =
      .ok ((), ⟨canonicalBytes, 1509, 2⟩) := by
  apply expectTag_of_spine "ProgramRequirements" 1 1484 1509 2
    [80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 115] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectRollbackReq :
    expectTag "RequirementRequest" 4 ⟨canonicalBytes, 1513, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1537, 3⟩) := by
  apply expectTag_of_spine "RequirementRequest" 4 1513 1537 3
    [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeRollbackReqId :
    decodeString ⟨canonicalBytes, 1537, 3⟩ =
      .ok ("failure.atomic-rollback", ⟨canonicalBytes, 1564, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1537 maxStringBytes =
      .ok (ByteArray.mk [102, 97, 105, 108, 117, 114, 101, 46, 97, 116, 111, 109, 105, 99, 45, 114, 111, 108, 108, 98, 97, 99, 107].toArray, 1564)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [102, 97, 105, 108, 117, 114, 101, 46, 97, 116, 111, 109, 105, 99, 45, 114, 111, 108, 108, 98, 97, 99, 107]
        1537 maxStringBytes 23 1541
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "failure.atomic-rollback" (by decide)

private theorem decodeRollbackReqVer :
    decodeString ⟨canonicalBytes, 1564, 3⟩ =
      .ok ("1.0.0", ⟨canonicalBytes, 1573, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1564 maxStringBytes =
      .ok (ByteArray.mk [49, 46, 48, 46, 48].toArray, 1573)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [49, 46, 48, 46, 48]
        1564 maxStringBytes 5 1568
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "1.0.0" (by decide)

private theorem decodeRollbackReqSemVer :
    decodeSemVer ⟨canonicalBytes, 1564, 3⟩ =
      .ok (s2RequirementVersionV1, ⟨canonicalBytes, 1573, 3⟩) := by
  apply decodeSemVer_eq_of_stringV1
  · exact decodeRollbackReqVer
  · -- s2RequirementVersionV1 = s2CatalogSemVerCoreV1 definitionally
    simpa [s2RequirementVersionV1, s2CatalogSemVerCoreV1] using parseSemVer_1_0_0

private theorem decodeRollbackReqDigest :
    decodeDigest ⟨canonicalBytes, 1573, 3⟩ =
      .ok ({ algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1 },
        ⟨canonicalBytes, 1605, 3⟩) := by
  apply decodeDigest_eq_of_takeV1
  · have h : takeBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1573 32 =
        .ok (ByteArray.mk ([254, 98, 216, 232, 64, 20, 227, 236, 31, 23, 247, 108, 127, 85, 250, 195, 25, 2, 68, 236, 163, 173, 18, 77, 208, 78, 23, 195, 201, 209, 17, 101]).toArray) := by
      apply takeBytesAtV1_eq_of_spine canonicalSpine ([254, 98, 216, 232, 64, 20, 227, 236, 31, 23, 247, 108, 127, 85, 250, 195, 25, 2, 68, 236, 163, 173, 18, 77, 208, 78, 23, 195, 201, 209, 17, 101]) 1573
      unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    simpa [canonicalBytes, s2FailureAtomicRollbackDigestBytesV1] using h
  · simp [s2FailureAtomicRollbackDigestBytesV1, validateDigest]
    rfl

private theorem decodeRollbackReq :
    decodeRequirementRequestV1 ⟨canonicalBytes, 1513, 2⟩ =
      .ok (requirement "failure.atomic-rollback" s2FailureAtomicRollbackDigestBytesV1,
        ⟨canonicalBytes, 1609, 2⟩) := by
  apply decodeRequirementRequestV1_eq_of_fields ⟨canonicalBytes, 1513, 2⟩
    ⟨canonicalBytes, 1537, 3⟩ ⟨canonicalBytes, 1564, 3⟩
    ⟨canonicalBytes, 1573, 3⟩ ⟨canonicalBytes, 1605, 3⟩
    ⟨canonicalBytes, 1609, 3⟩
    "failure.atomic-rollback" s2RequirementVersionV1
    { algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1 } #[] (by decide)
  · exact expectRollbackReq
  · exact decodeRollbackReqId
  · exact decodeRollbackReqSemVer
  · exact decodeRollbackReqDigest
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1605
      maxArrayElements = .ok (0, 1609)
    rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem expectPersistentReq :
    expectTag "RequirementRequest" 4 ⟨canonicalBytes, 1609, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1633, 3⟩) := by
  apply expectTag_of_spine "RequirementRequest" 4 1609 1633 3
    [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodePersistentReqId :
    decodeString ⟨canonicalBytes, 1633, 3⟩ =
      .ok ("state.persistent", ⟨canonicalBytes, 1653, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1633 maxStringBytes =
      .ok (ByteArray.mk [115, 116, 97, 116, 101, 46, 112, 101, 114, 115, 105, 115, 116, 101, 110, 116].toArray, 1653)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [115, 116, 97, 116, 101, 46, 112, 101, 114, 115, 105, 115, 116, 101, 110, 116]
        1633 maxStringBytes 16 1637
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "state.persistent" (by decide)

private theorem decodePersistentReqVer :
    decodeString ⟨canonicalBytes, 1653, 3⟩ =
      .ok ("1.0.0", ⟨canonicalBytes, 1662, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1653 maxStringBytes =
      .ok (ByteArray.mk [49, 46, 48, 46, 48].toArray, 1662)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [49, 46, 48, 46, 48]
        1653 maxStringBytes 5 1657
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "1.0.0" (by decide)

private theorem decodePersistentReqSemVer :
    decodeSemVer ⟨canonicalBytes, 1653, 3⟩ =
      .ok (s2RequirementVersionV1, ⟨canonicalBytes, 1662, 3⟩) := by
  apply decodeSemVer_eq_of_stringV1
  · exact decodePersistentReqVer
  · -- s2RequirementVersionV1 = s2CatalogSemVerCoreV1 definitionally
    simpa [s2RequirementVersionV1, s2CatalogSemVerCoreV1] using parseSemVer_1_0_0

private theorem decodePersistentReqDigest :
    decodeDigest ⟨canonicalBytes, 1662, 3⟩ =
      .ok ({ algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 },
        ⟨canonicalBytes, 1694, 3⟩) := by
  apply decodeDigest_eq_of_takeV1
  · have h : takeBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1662 32 =
        .ok (ByteArray.mk ([2, 63, 255, 245, 41, 95, 167, 238, 77, 158, 78, 73, 144, 154, 62, 183, 241, 252, 12, 86, 31, 142, 126, 160, 111, 18, 66, 52, 12, 20, 110, 229]).toArray) := by
      apply takeBytesAtV1_eq_of_spine canonicalSpine ([2, 63, 255, 245, 41, 95, 167, 238, 77, 158, 78, 73, 144, 154, 62, 183, 241, 252, 12, 86, 31, 142, 126, 160, 111, 18, 66, 52, 12, 20, 110, 229]) 1662
      unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    simpa [canonicalBytes, s2StatePersistentDigestBytesV1] using h
  · simp [s2StatePersistentDigestBytesV1, validateDigest]
    rfl

private theorem decodePersistentReq :
    decodeRequirementRequestV1 ⟨canonicalBytes, 1609, 2⟩ =
      .ok (requirement "state.persistent" s2StatePersistentDigestBytesV1,
        ⟨canonicalBytes, 1698, 2⟩) := by
  apply decodeRequirementRequestV1_eq_of_fields ⟨canonicalBytes, 1609, 2⟩
    ⟨canonicalBytes, 1633, 3⟩ ⟨canonicalBytes, 1653, 3⟩
    ⟨canonicalBytes, 1662, 3⟩ ⟨canonicalBytes, 1694, 3⟩
    ⟨canonicalBytes, 1698, 3⟩
    "state.persistent" s2RequirementVersionV1
    { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 } #[] (by decide)
  · exact expectPersistentReq
  · exact decodePersistentReqId
  · exact decodePersistentReqSemVer
  · exact decodePersistentReqDigest
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1694
      maxArrayElements = .ok (0, 1698)
    rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem expectCheckedReq :
    expectTag "RequirementRequest" 4 ⟨canonicalBytes, 1698, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1722, 3⟩) := by
  apply expectTag_of_spine "RequirementRequest" 4 1698 1722 3
    [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeCheckedReqId :
    decodeString ⟨canonicalBytes, 1722, 3⟩ =
      .ok ("value.checked-arithmetic", ⟨canonicalBytes, 1750, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1722 maxStringBytes =
      .ok (ByteArray.mk [118, 97, 108, 117, 101, 46, 99, 104, 101, 99, 107, 101, 100, 45, 97, 114, 105, 116, 104, 109, 101, 116, 105, 99].toArray, 1750)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [118, 97, 108, 117, 101, 46, 99, 104, 101, 99, 107, 101, 100, 45, 97, 114, 105, 116, 104, 109, 101, 116, 105, 99]
        1722 maxStringBytes 24 1726
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "value.checked-arithmetic" (by decide)

private theorem decodeCheckedReqVer :
    decodeString ⟨canonicalBytes, 1750, 3⟩ =
      .ok ("1.0.0", ⟨canonicalBytes, 1759, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1750 maxStringBytes =
      .ok (ByteArray.mk [49, 46, 48, 46, 48].toArray, 1759)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [49, 46, 48, 46, 48]
        1750 maxStringBytes 5 1754
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "1.0.0" (by decide)

private theorem decodeCheckedReqSemVer :
    decodeSemVer ⟨canonicalBytes, 1750, 3⟩ =
      .ok (s2RequirementVersionV1, ⟨canonicalBytes, 1759, 3⟩) := by
  apply decodeSemVer_eq_of_stringV1
  · exact decodeCheckedReqVer
  · -- s2RequirementVersionV1 = s2CatalogSemVerCoreV1 definitionally
    simpa [s2RequirementVersionV1, s2CatalogSemVerCoreV1] using parseSemVer_1_0_0

private theorem decodeCheckedReqDigest :
    decodeDigest ⟨canonicalBytes, 1759, 3⟩ =
      .ok ({ algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1 },
        ⟨canonicalBytes, 1791, 3⟩) := by
  apply decodeDigest_eq_of_takeV1
  · have h : takeBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1759 32 =
        .ok (ByteArray.mk ([226, 24, 107, 1, 207, 88, 19, 81, 17, 247, 78, 197, 106, 83, 227, 51, 135, 188, 48, 22, 72, 104, 7, 27, 31, 82, 74, 242, 34, 184, 191, 205]).toArray) := by
      apply takeBytesAtV1_eq_of_spine canonicalSpine ([226, 24, 107, 1, 207, 88, 19, 81, 17, 247, 78, 197, 106, 83, 227, 51, 135, 188, 48, 22, 72, 104, 7, 27, 31, 82, 74, 242, 34, 184, 191, 205]) 1759
      unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    simpa [canonicalBytes, s2ValueCheckedArithmeticDigestBytesV1] using h
  · simp [s2ValueCheckedArithmeticDigestBytesV1, validateDigest]
    rfl

private theorem decodeCheckedReq :
    decodeRequirementRequestV1 ⟨canonicalBytes, 1698, 2⟩ =
      .ok (requirement "value.checked-arithmetic" s2ValueCheckedArithmeticDigestBytesV1,
        ⟨canonicalBytes, 1795, 2⟩) := by
  apply decodeRequirementRequestV1_eq_of_fields ⟨canonicalBytes, 1698, 2⟩
    ⟨canonicalBytes, 1722, 3⟩ ⟨canonicalBytes, 1750, 3⟩
    ⟨canonicalBytes, 1759, 3⟩ ⟨canonicalBytes, 1791, 3⟩
    ⟨canonicalBytes, 1795, 3⟩
    "value.checked-arithmetic" s2RequirementVersionV1
    { algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1 } #[] (by decide)
  · exact expectCheckedReq
  · exact decodeCheckedReqId
  · exact decodeCheckedReqSemVer
  · exact decodeCheckedReqDigest
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1791
      maxArrayElements = .ok (0, 1795)
    rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem decodeRequirements_canonicalBytes :
    decodeProgramRequirementsV1 ⟨canonicalBytes, 1484, 1⟩ =
      .ok ({ items := #[rollbackRequirement, persistentStateRequirement,
          checkedArithmeticRequirement] }, ⟨canonicalBytes, 1795, 1⟩) := by
  refine decodeProgramRequirementsV1_eq_of_bodyV1 ⟨canonicalBytes, 1484, 1⟩
    { items := #[rollbackRequirement, persistentStateRequirement,
        checkedArithmeticRequirement] }
    ⟨canonicalBytes, 1795, 2⟩ (by decide) ?_
  apply decodeProgramRequirementsBodyV1_eq_of_fields
  · exact expectProgramRequirements
  · exact decodeArray_threeV1 maxArrayElements decodeRequirementRequestV1
      ⟨canonicalBytes, 1509, 2⟩ 1513
      rollbackRequirement persistentStateRequirement checkedArithmeticRequirement
      ⟨canonicalBytes, 1609, 2⟩ ⟨canonicalBytes, 1698, 2⟩ ⟨canonicalBytes, 1795, 2⟩
      (by
        change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1509
          maxArrayElements = .ok (3, 1513)
        rw [readArrayCountAtV1_refinesSpine]; rfl)
      (by simpa [rollbackRequirement, requirement] using decodeRollbackReq)
      (by simpa [persistentStateRequirement, requirement] using decodePersistentReq)
      (by simpa [checkedArithmeticRequirement, requirement] using decodeCheckedReq)

/-! ### Root tagged composition + public decode_ok -/

private theorem decodeTaggedData_canonicalBytes :
    decodeSemanticProgramDataTaggedV1 ⟨canonicalBytes, 15, 0⟩ =
      .ok (data, ⟨canonicalBytes, 1795, 0⟩) := by
  have h := decodeSemanticProgramDataTaggedV1_eq_of_fields
    ⟨canonicalBytes, 15, 0⟩ ⟨canonicalBytes, 41, 1⟩
    ⟨canonicalBytes, 68, 1⟩ ⟨canonicalBytes, 142, 1⟩
    ⟨canonicalBytes, 146, 1⟩ ⟨canonicalBytes, 205, 1⟩
    ⟨canonicalBytes, 209, 1⟩ ⟨canonicalBytes, 213, 1⟩
    ⟨canonicalBytes, 1445, 1⟩ ⟨canonicalBytes, 1484, 1⟩
    ⟨canonicalBytes, 1795, 1⟩ qualifiedName types #[] #[countState] #[] #[]
    #[incrementCallable, getCallable, evenCallable] #[evenInvariant]
    { items := #[rollbackRequirement, persistentStateRequirement,
        checkedArithmeticRequirement] } (by decide)
    expectRootTag_canonicalBytes decodeQualifiedName_canonicalBytes
    decodeTypes_canonicalBytes decodeConstants_canonicalBytes
    decodeLogicalState_canonicalBytes decodeEvents_canonicalBytes
    decodeErrors_canonicalBytes decodeCallables_canonicalBytes
    decodeInvariants_canonicalBytes decodeRequirements_canonicalBytes
  simpa [data] using h

/-- Production transport decoder certificate for the closed EvenCounter instance. -/
theorem decode_ok :
    decodeSemanticProgramDataV1 ParityCounterShapeV1.canonicalBytes =
      .ok ParityCounterShapeV1.data := by
  apply decodeSemanticProgramDataV1_eq_of_framing canonicalBytes
    ⟨canonicalBytes, 15, 0⟩ ⟨canonicalBytes, 1795, 0⟩ data
  · change canonicalSpine.length ≤ maxCanonicalProgramBytes
    rw [canonicalSpine_length]
    decide
  · exact consumeMagic_canonicalBytes
  · exact decodeTaggedData_canonicalBytes
  · apply finish_eq_ok_of_offset_sizeV1
    change 1795 = canonicalSpine.length
    exact canonicalSpine_length.symm

end ProofForgeV2.Semantic.ParityCounterDecodeV1
