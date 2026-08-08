import ProofForgeV2.ProofInstances.ZeroCounterV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Core.Unicode

/-!
  Production transport decoder certificate for the closed ZeroCounter instance.

  Proves `decodeSemanticProgramDataV1 ZeroCounterV1.canonicalBytes = .ok ZeroCounterV1.data`
  solely via production decoder composition/refinement theorems and the exact
  `canonicalSpine`. No second decoder, sorry, axiom, native_decide, ofReduceBool,
  run_tac, unsafe, meta, or IO.
-/

namespace ProofForgeV2.ProofInstances.ZeroCounterDecodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.ProofInstances.ZeroCounterV1

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

private theorem readZeroCounterBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 53 maxStringBytes =
      .ok (ByteArray.mk
        [90, 101, 114, 111, 67, 111, 117, 110, 116, 101, 114].toArray, 68) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 53 maxStringBytes =
    .ok (ByteArray.mk
      [90, 101, 114, 111, 67, 111, 117, 110, 116, 101, 114].toArray, 68)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
      [90, 101, 114, 111, 67, 111, 117, 110, 116, 101, 114]
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

private theorem decodeZeroCounterV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 53 maxStringBytes =
      .ok (ByteArray.mk
        [90, 101, 114, 111, 67, 111, 117, 110, 116, 101, 114].toArray, 68)) :
    decodeString ⟨bytes, 53, 1⟩ = .ok ("ZeroCounter", ⟨bytes, 68, 1⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "ZeroCounter" (by decide)

private theorem decodeQualifiedName_canonicalBytes :
    decodeQualifiedName ⟨canonicalBytes, 41, 1⟩ =
      .ok (qualifiedName, ⟨canonicalBytes, 68, 1⟩) := by
  apply decodeQualifiedName_eq_of_arrayV1
  · apply decodeArray_twoV1
    · exact readQualifiedNameCount_canonicalBytes
    · exact decodeRootV1_of_read canonicalBytes readRootBytes_canonicalBytes
    · exact decodeZeroCounterV1_of_read canonicalBytes
        readZeroCounterBytes_canonicalBytes
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


/-! ### clear instruction 0: Literal 0 -/


private theorem expectClrI0Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 347, 4⟩ =
      .ok ((), ⟨canonicalBytes, 364, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 347 364 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectClrI0VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 365, 5⟩ =
      .ok ((), ⟨canonicalBytes, 379, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 365 379 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI0VID :
    decodeU32le ⟨canonicalBytes, 379, 5⟩ =
      .ok (0, ⟨canonicalBytes, 383, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI0TID :
    decodeU32le ⟨canonicalBytes, 383, 5⟩ =
      .ok (0, ⟨canonicalBytes, 387, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI0ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 365, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 387, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 365, 4⟩
    ⟨canonicalBytes, 379, 5⟩ ⟨canonicalBytes, 383, 5⟩
    ⟨canonicalBytes, 387, 5⟩ 0 0 (by decide)
  · exact expectClrI0VD
  · exact decodeClrI0VID
  · exact decodeClrI0TID

private theorem decodeClrI0ResMark :
    decodeU8 ⟨canonicalBytes, 364, 4⟩ =
      .ok (1, ⟨canonicalBytes, 365, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI0Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 364, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨canonicalBytes, 387, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 364, 4⟩
    ⟨canonicalBytes, 365, 4⟩
    ⟨canonicalBytes, 387, 4⟩
    { valueId := 0, typeId := 0 }
  · exact decodeClrI0ResMark
  · exact decodeClrI0ValueDef

private theorem decodeClrI0OpTag :
    decodeTag ⟨canonicalBytes, 387, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 401, 5⟩) := by
  apply decodeCanonicalTagV1 387 401 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI0OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 401, 5⟩ =
      .ok ((), ⟨canonicalBytes, 403, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI0LitType :
    decodeU32le ⟨canonicalBytes, 403, 5⟩ =
      .ok (0, ⟨canonicalBytes, 407, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI0LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 407, 5⟩ =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 419, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 407 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 419) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 407
      maxCanonicalProgramBytes = .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 419)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0, 0, 0, 0, 0, 0, 0, 0]
        407 maxCanonicalProgramBytes 8 411
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeClrI0Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 387, 4⟩ =
      .ok (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray),
        ⟨canonicalBytes, 419, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 387, 4⟩
    ⟨canonicalBytes, 401, 5⟩ ⟨canonicalBytes, 403, 5⟩
    ⟨canonicalBytes, 407, 5⟩ ⟨canonicalBytes, 419, 5⟩
    0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray) (by decide)
  · exact decodeClrI0OpTag
  · exact decodeClrI0OpFc
  · exact decodeClrI0LitType
  · exact decodeClrI0LitBytes

private theorem decodeClrI0Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 347, 3⟩ =
      .ok (valueInstruction 0 0 (.literal 0 zeroBytes), ⟨canonicalBytes, 419, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 347, 3⟩
    ⟨canonicalBytes, 364, 4⟩ ⟨canonicalBytes, 387, 4⟩ ⟨canonicalBytes, 419, 4⟩
    (some { valueId := 0, typeId := 0 })
    (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray)) (by decide)
    expectClrI0Instr decodeClrI0Result decodeClrI0Op
  simpa [valueInstruction, valueDef, zeroBytes] using h

/-! ### clear instruction 1: StateStore -/


private theorem expectClrI1Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 419, 4⟩ =
      .ok ((), ⟨canonicalBytes, 436, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 419 436 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI1ResMark :
    decodeU8 ⟨canonicalBytes, 436, 4⟩ =
      .ok (0, ⟨canonicalBytes, 437, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI1Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 436, 4⟩ =
      .ok (none, ⟨canonicalBytes, 437, 4⟩) := by
  apply decodeOption_noneV1
  exact decodeClrI1ResMark

private theorem decodeClrI1OpTag :
    decodeTag ⟨canonicalBytes, 437, 5⟩ =
      .ok ("Op.StateStore", ⟨canonicalBytes, 454, 5⟩) := by
  apply decodeCanonicalTagV1 437 454 5
    [79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101] "Op.StateStore"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI1OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 454, 5⟩ =
      .ok ((), ⟨canonicalBytes, 456, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI1StateId :
    decodeU32le ⟨canonicalBytes, 456, 5⟩ =
      .ok (0, ⟨canonicalBytes, 460, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI1Value :
    decodeU32le ⟨canonicalBytes, 460, 5⟩ =
      .ok (0, ⟨canonicalBytes, 464, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI1Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 437, 4⟩ =
      .ok (.stateStore 0 0, ⟨canonicalBytes, 464, 4⟩) := by
  apply decodeSemanticOpV1_stateStore ⟨canonicalBytes, 437, 4⟩
    ⟨canonicalBytes, 454, 5⟩ ⟨canonicalBytes, 456, 5⟩
    ⟨canonicalBytes, 460, 5⟩ ⟨canonicalBytes, 464, 5⟩
    0 0 (by decide)
  · exact decodeClrI1OpTag
  · exact decodeClrI1OpFc
  · exact decodeClrI1StateId
  · exact decodeClrI1Value

private theorem decodeClrI1Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 419, 3⟩ =
      .ok (voidInstruction (.stateStore 0 0), ⟨canonicalBytes, 464, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 419, 3⟩
    ⟨canonicalBytes, 436, 4⟩ ⟨canonicalBytes, 437, 4⟩ ⟨canonicalBytes, 464, 4⟩
    none (.stateStore 0 0) (by decide)
    expectClrI1Instr decodeClrI1Result decodeClrI1Op
  simpa [voidInstruction] using h

/-! ### clear instruction 2: StateLoad reload -/


private theorem expectClrI2Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 464, 4⟩ =
      .ok ((), ⟨canonicalBytes, 481, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 464 481 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectClrI2VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 482, 5⟩ =
      .ok ((), ⟨canonicalBytes, 496, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 482 496 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI2VID :
    decodeU32le ⟨canonicalBytes, 496, 5⟩ =
      .ok (1, ⟨canonicalBytes, 500, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI2TID :
    decodeU32le ⟨canonicalBytes, 500, 5⟩ =
      .ok (0, ⟨canonicalBytes, 504, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI2ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 482, 4⟩ =
      .ok ({ valueId := 1, typeId := 0 }, ⟨canonicalBytes, 504, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 482, 4⟩
    ⟨canonicalBytes, 496, 5⟩ ⟨canonicalBytes, 500, 5⟩
    ⟨canonicalBytes, 504, 5⟩ 1 0 (by decide)
  · exact expectClrI2VD
  · exact decodeClrI2VID
  · exact decodeClrI2TID

private theorem decodeClrI2ResMark :
    decodeU8 ⟨canonicalBytes, 481, 4⟩ =
      .ok (1, ⟨canonicalBytes, 482, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI2Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 481, 4⟩ =
      .ok (some { valueId := 1, typeId := 0 },
        ⟨canonicalBytes, 504, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 481, 4⟩
    ⟨canonicalBytes, 482, 4⟩
    ⟨canonicalBytes, 504, 4⟩
    { valueId := 1, typeId := 0 }
  · exact decodeClrI2ResMark
  · exact decodeClrI2ValueDef

private theorem decodeClrI2OpTag :
    decodeTag ⟨canonicalBytes, 504, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 520, 5⟩) := by
  apply decodeCanonicalTagV1 504 520 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI2OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 520, 5⟩ =
      .ok ((), ⟨canonicalBytes, 522, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI2StateId :
    decodeU32le ⟨canonicalBytes, 522, 5⟩ =
      .ok (0, ⟨canonicalBytes, 526, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI2Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 504, 4⟩ =
      .ok (.stateLoad 0, ⟨canonicalBytes, 526, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 504, 4⟩
    ⟨canonicalBytes, 520, 5⟩ ⟨canonicalBytes, 522, 5⟩
    ⟨canonicalBytes, 526, 5⟩ 0 (by decide)
  · exact decodeClrI2OpTag
  · exact decodeClrI2OpFc
  · exact decodeClrI2StateId

private theorem decodeClrI2Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 464, 3⟩ =
      .ok (valueInstruction 1 0 (.stateLoad 0), ⟨canonicalBytes, 526, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 464, 3⟩
    ⟨canonicalBytes, 481, 4⟩ ⟨canonicalBytes, 504, 4⟩ ⟨canonicalBytes, 526, 4⟩
    (some { valueId := 1, typeId := 0 }) (.stateLoad 0) (by decide)
    expectClrI2Instr decodeClrI2Result decodeClrI2Op
  simpa [valueInstruction, valueDef] using h

/-! ### clear terminator -/


private theorem decodeClrTermTag :
    decodeTag ⟨canonicalBytes, 526, 4⟩ =
      .ok ("Term.Return", ⟨canonicalBytes, 541, 4⟩) := by
  apply decodeCanonicalTagV1 526 541 4
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrTermFc :
    decodeFieldCount 1 ⟨canonicalBytes, 541, 4⟩ =
      .ok ((), ⟨canonicalBytes, 543, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrTermMark :
    decodeU8 ⟨canonicalBytes, 543, 4⟩ =
      .ok (1, ⟨canonicalBytes, 544, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrTermVal :
    decodeU32le ⟨canonicalBytes, 544, 4⟩ =
      .ok (1, ⟨canonicalBytes, 548, 4⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrReturn :
    decodeTerminatorV1 ⟨canonicalBytes, 526, 3⟩ =
      .ok (.return_ (some 1), ⟨canonicalBytes, 548, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 526, 3⟩
    ⟨canonicalBytes, 541, 4⟩ ⟨canonicalBytes, 543, 4⟩
    ⟨canonicalBytes, 548, 4⟩
    (some 1) (by decide)
  · exact decodeClrTermTag
  · exact decodeClrTermFc
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 543, 4⟩
      ⟨canonicalBytes, 544, 4⟩ ⟨canonicalBytes, 548, 4⟩ 1
    · exact decodeClrTermMark
    · exact decodeClrTermVal


private theorem decodeClrInstructions :
    decodeArray maxArrayElements decodeInstructionV1 ⟨canonicalBytes, 343, 3⟩ =
      .ok (clearBlock.instructions, ⟨canonicalBytes, 526, 3⟩) := by
  have h := decodeArray_threeV1 maxArrayElements decodeInstructionV1
    ⟨canonicalBytes, 343, 3⟩ 347
    (valueInstruction 0 0 (.literal 0 zeroBytes))
    (voidInstruction (.stateStore 0 0))
    (valueInstruction 1 0 (.stateLoad 0))
    ⟨canonicalBytes, 419, 3⟩ ⟨canonicalBytes, 464, 3⟩ ⟨canonicalBytes, 526, 3⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 343
        maxArrayElements = .ok (3, 347)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeClrI0Instruction decodeClrI1Instruction decodeClrI2Instruction
  simpa [clearBlock, valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectClrBlock :
    expectTag "Block" 4 ⟨canonicalBytes, 324, 3⟩ =
      .ok ((), ⟨canonicalBytes, 335, 3⟩) := by
  apply expectTag_of_spine "Block" 4 324 335 3
    [66, 108, 111, 99, 107] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeClrBlockId :
    decodeU32le ⟨canonicalBytes, 335, 3⟩ = .ok (0, ⟨canonicalBytes, 339, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrBlock :
    decodeBlockV1 ⟨canonicalBytes, 324, 2⟩ =
      .ok (clearBlock, ⟨canonicalBytes, 548, 2⟩) := by
  apply decodeBlockV1_eq_of_fieldsV1 ⟨canonicalBytes, 324, 2⟩
    ⟨canonicalBytes, 335, 3⟩ ⟨canonicalBytes, 339, 3⟩
    ⟨canonicalBytes, 343, 3⟩ ⟨canonicalBytes, 526, 3⟩ ⟨canonicalBytes, 548, 3⟩
    0 #[] clearBlock.instructions (.return_ (some 1)) (by decide)
  · exact expectClrBlock
  · exact decodeClrBlockId
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 339
      maxArrayElements = .ok (0, 343)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeClrInstructions
  · exact decodeClrReturn


/-! ### clear callable -/

private theorem expectClrCallable :
    expectTag "Callable" 9 ⟨canonicalBytes, 217, 2⟩ =
      .ok ((), ⟨canonicalBytes, 231, 2⟩) := by
  apply expectTag_of_spine "Callable" 9 217 231 2
    [67, 97, 108, 108, 97, 98, 108, 101] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeClrId :
    decodeU32le ⟨canonicalBytes, 231, 2⟩ =
      .ok (0, ⟨canonicalBytes, 235, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrKindTag :
    decodeTag ⟨canonicalBytes, 235, 3⟩ =
      .ok ("Callable.Entry", ⟨canonicalBytes, 253, 3⟩) := by
  apply decodeCanonicalTagV1 235 253 3
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121] "Callable.Entry"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrKindFc :
    decodeFieldCount 0 ⟨canonicalBytes, 253, 3⟩ =
      .ok ((), ⟨canonicalBytes, 255, 3⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrKind :
    decodeCallableKindV1 ⟨canonicalBytes, 235, 2⟩ =
      .ok (.entry, ⟨canonicalBytes, 255, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 235, 2⟩ .entry
    ⟨canonicalBytes, 255, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_entry
  · exact decodeClrKindTag
  · exact decodeClrKindFc

private theorem decodeClrNameMark :
    decodeU8 ⟨canonicalBytes, 255, 2⟩ =
      .ok (1, ⟨canonicalBytes, 256, 2⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrNameStr :
    decodeString ⟨canonicalBytes, 256, 2⟩ =
      .ok ("clear", ⟨canonicalBytes, 265, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 256 maxStringBytes =
      .ok (ByteArray.mk [99, 108, 101, 97, 114].toArray, 265)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [99, 108, 101, 97, 114]
        256 maxStringBytes 5 260
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "clear" (by decide)

private theorem decodeClrName :
    decodeOption decodeString ⟨canonicalBytes, 255, 2⟩ =
      .ok (some "clear", ⟨canonicalBytes, 265, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 255, 2⟩
    ⟨canonicalBytes, 256, 2⟩ ⟨canonicalBytes, 265, 2⟩ "clear"
  · exact decodeClrNameMark
  · exact decodeClrNameStr

private theorem expectClrResult :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 269, 3⟩ =
      .ok ((), ⟨canonicalBytes, 289, 3⟩) := by
  apply expectTag_of_spine "CallableResult" 2 269 289 3
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeClrResultType :
    decodeU32le ⟨canonicalBytes, 289, 3⟩ =
      .ok (0, ⟨canonicalBytes, 293, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrVisTag :
    decodeTag ⟨canonicalBytes, 293, 4⟩ =
      .ok ("Visibility.Public", ⟨canonicalBytes, 314, 4⟩) := by
  apply decodeCanonicalTagV1 293 314 4
    [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
    "Visibility.Public"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrVisFc :
    decodeFieldCount 0 ⟨canonicalBytes, 314, 4⟩ =
      .ok ((), ⟨canonicalBytes, 316, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrVisibility :
    decodeVisibilityV1 ⟨canonicalBytes, 293, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 316, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 293, 3⟩ .public_
    ⟨canonicalBytes, 316, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · exact decodeClrVisTag
  · exact decodeClrVisFc

private theorem decodeClrResult :
    decodeCallableResultV1 ⟨canonicalBytes, 269, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨canonicalBytes, 316, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 269, 2⟩
    { typeId := 0, visibility := .public_ } ⟨canonicalBytes, 316, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectClrResult
  · exact decodeClrResultType
  · exact decodeClrVisibility

private theorem decodeClrEntryBlock :
    decodeU32le ⟨canonicalBytes, 316, 2⟩ =
      .ok (0, ⟨canonicalBytes, 320, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrCallable :
    decodeCallableV1 ⟨canonicalBytes, 217, 1⟩ =
      .ok (clearCallable, ⟨canonicalBytes, 553, 1⟩) := by
  apply decodeCallableV1_singleBlockV1 ⟨canonicalBytes, 217, 1⟩
    ⟨canonicalBytes, 231, 2⟩ ⟨canonicalBytes, 235, 2⟩ ⟨canonicalBytes, 255, 2⟩
    ⟨canonicalBytes, 265, 2⟩ ⟨canonicalBytes, 316, 2⟩ ⟨canonicalBytes, 320, 2⟩
    ⟨canonicalBytes, 548, 2⟩ ⟨canonicalBytes, 553, 2⟩
    269 324 552 0 0 .entry (some "clear")
    { typeId := 0, visibility := .public_ } clearBlock none (by decide)
  · exact expectClrCallable
  · exact decodeClrId
  · exact decodeClrKind
  · exact decodeClrName
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 265
      maxArrayElements = .ok (0, 269)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeClrResult
  · exact decodeClrEntryBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 320
      maxArrayElements = .ok (1, 324)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeClrBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 548
      maxArrayElements = .ok (0, 552)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · apply decodeOption_noneV1
    apply decodeCanonicalU8V1; rfl

/-! ### get instruction 0: StateLoad -/


private theorem expectGetI0Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 680, 4⟩ =
      .ok ((), ⟨canonicalBytes, 697, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 680 697 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectGetI0VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 698, 5⟩ =
      .ok ((), ⟨canonicalBytes, 712, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 698 712 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeGetI0VID :
    decodeU32le ⟨canonicalBytes, 712, 5⟩ =
      .ok (0, ⟨canonicalBytes, 716, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetI0TID :
    decodeU32le ⟨canonicalBytes, 716, 5⟩ =
      .ok (0, ⟨canonicalBytes, 720, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetI0ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 698, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 720, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 698, 4⟩
    ⟨canonicalBytes, 712, 5⟩ ⟨canonicalBytes, 716, 5⟩
    ⟨canonicalBytes, 720, 5⟩ 0 0 (by decide)
  · exact expectGetI0VD
  · exact decodeGetI0VID
  · exact decodeGetI0TID

private theorem decodeGetI0ResMark :
    decodeU8 ⟨canonicalBytes, 697, 4⟩ =
      .ok (1, ⟨canonicalBytes, 698, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeGetI0Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 697, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨canonicalBytes, 720, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 697, 4⟩
    ⟨canonicalBytes, 698, 4⟩
    ⟨canonicalBytes, 720, 4⟩
    { valueId := 0, typeId := 0 }
  · exact decodeGetI0ResMark
  · exact decodeGetI0ValueDef

private theorem decodeGetI0OpTag :
    decodeTag ⟨canonicalBytes, 720, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 736, 5⟩) := by
  apply decodeCanonicalTagV1 720 736 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetI0OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 736, 5⟩ =
      .ok ((), ⟨canonicalBytes, 738, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetI0StateId :
    decodeU32le ⟨canonicalBytes, 738, 5⟩ =
      .ok (0, ⟨canonicalBytes, 742, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetI0Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 720, 4⟩ =
      .ok (.stateLoad 0, ⟨canonicalBytes, 742, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 720, 4⟩
    ⟨canonicalBytes, 736, 5⟩ ⟨canonicalBytes, 738, 5⟩
    ⟨canonicalBytes, 742, 5⟩ 0 (by decide)
  · exact decodeGetI0OpTag
  · exact decodeGetI0OpFc
  · exact decodeGetI0StateId

private theorem decodeGetI0Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 680, 3⟩ =
      .ok (valueInstruction 0 0 (.stateLoad 0), ⟨canonicalBytes, 742, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 680, 3⟩
    ⟨canonicalBytes, 697, 4⟩ ⟨canonicalBytes, 720, 4⟩ ⟨canonicalBytes, 742, 4⟩
    (some { valueId := 0, typeId := 0 }) (.stateLoad 0) (by decide)
    expectGetI0Instr decodeGetI0Result decodeGetI0Op
  simpa [valueInstruction, valueDef] using h

/-! ### get terminator -/


private theorem decodeGetTermTag :
    decodeTag ⟨canonicalBytes, 742, 4⟩ =
      .ok ("Term.Return", ⟨canonicalBytes, 757, 4⟩) := by
  apply decodeCanonicalTagV1 742 757 4
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetTermFc :
    decodeFieldCount 1 ⟨canonicalBytes, 757, 4⟩ =
      .ok ((), ⟨canonicalBytes, 759, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetTermMark :
    decodeU8 ⟨canonicalBytes, 759, 4⟩ =
      .ok (1, ⟨canonicalBytes, 760, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeGetTermVal :
    decodeU32le ⟨canonicalBytes, 760, 4⟩ =
      .ok (0, ⟨canonicalBytes, 764, 4⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetReturn :
    decodeTerminatorV1 ⟨canonicalBytes, 742, 3⟩ =
      .ok (.return_ (some 0), ⟨canonicalBytes, 764, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 742, 3⟩
    ⟨canonicalBytes, 757, 4⟩ ⟨canonicalBytes, 759, 4⟩
    ⟨canonicalBytes, 764, 4⟩
    (some 0) (by decide)
  · exact decodeGetTermTag
  · exact decodeGetTermFc
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 759, 4⟩
      ⟨canonicalBytes, 760, 4⟩ ⟨canonicalBytes, 764, 4⟩ 0
    · exact decodeGetTermMark
    · exact decodeGetTermVal


private theorem decodeGetInstructions :
    decodeArray maxArrayElements decodeInstructionV1 ⟨canonicalBytes, 676, 3⟩ =
      .ok (getBlock.instructions, ⟨canonicalBytes, 742, 3⟩) := by
  have h := decodeArray_oneV1 maxArrayElements decodeInstructionV1
    ⟨canonicalBytes, 676, 3⟩ 680
    (valueInstruction 0 0 (.stateLoad 0))
    ⟨canonicalBytes, 742, 3⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 676
        maxArrayElements = .ok (1, 680)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeGetI0Instruction
  simpa [getBlock, valueInstruction, valueDef] using h

private theorem expectGetBlock :
    expectTag "Block" 4 ⟨canonicalBytes, 657, 3⟩ =
      .ok ((), ⟨canonicalBytes, 668, 3⟩) := by
  apply expectTag_of_spine "Block" 4 657 668 3
    [66, 108, 111, 99, 107] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeGetBlockId :
    decodeU32le ⟨canonicalBytes, 668, 3⟩ = .ok (0, ⟨canonicalBytes, 672, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetBlock :
    decodeBlockV1 ⟨canonicalBytes, 657, 2⟩ =
      .ok (getBlock, ⟨canonicalBytes, 764, 2⟩) := by
  apply decodeBlockV1_eq_of_fieldsV1 ⟨canonicalBytes, 657, 2⟩
    ⟨canonicalBytes, 668, 3⟩ ⟨canonicalBytes, 672, 3⟩
    ⟨canonicalBytes, 676, 3⟩ ⟨canonicalBytes, 742, 3⟩ ⟨canonicalBytes, 764, 3⟩
    0 #[] getBlock.instructions (.return_ (some 0)) (by decide)
  · exact expectGetBlock
  · exact decodeGetBlockId
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 672
      maxArrayElements = .ok (0, 676)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeGetInstructions
  · exact decodeGetReturn


/-! ### get callable -/

private theorem expectGetCallable :
    expectTag "Callable" 9 ⟨canonicalBytes, 553, 2⟩ =
      .ok ((), ⟨canonicalBytes, 567, 2⟩) := by
  apply expectTag_of_spine "Callable" 9 553 567 2
    [67, 97, 108, 108, 97, 98, 108, 101] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeGetId :
    decodeU32le ⟨canonicalBytes, 567, 2⟩ =
      .ok (1, ⟨canonicalBytes, 571, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetKindTag :
    decodeTag ⟨canonicalBytes, 571, 3⟩ =
      .ok ("Callable.View", ⟨canonicalBytes, 588, 3⟩) := by
  apply decodeCanonicalTagV1 571 588 3
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119] "Callable.View"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetKindFc :
    decodeFieldCount 0 ⟨canonicalBytes, 588, 3⟩ =
      .ok ((), ⟨canonicalBytes, 590, 3⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetKind :
    decodeCallableKindV1 ⟨canonicalBytes, 571, 2⟩ =
      .ok (.view, ⟨canonicalBytes, 590, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 571, 2⟩ .view
    ⟨canonicalBytes, 590, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_view
  · exact decodeGetKindTag
  · exact decodeGetKindFc

private theorem decodeGetNameMark :
    decodeU8 ⟨canonicalBytes, 590, 2⟩ =
      .ok (1, ⟨canonicalBytes, 591, 2⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeGetNameStr :
    decodeString ⟨canonicalBytes, 591, 2⟩ =
      .ok ("get", ⟨canonicalBytes, 598, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 591 maxStringBytes =
      .ok (ByteArray.mk [103, 101, 116].toArray, 598)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [103, 101, 116]
        591 maxStringBytes 3 595
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "get" (by decide)

private theorem decodeGetName :
    decodeOption decodeString ⟨canonicalBytes, 590, 2⟩ =
      .ok (some "get", ⟨canonicalBytes, 598, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 590, 2⟩
    ⟨canonicalBytes, 591, 2⟩ ⟨canonicalBytes, 598, 2⟩ "get"
  · exact decodeGetNameMark
  · exact decodeGetNameStr

private theorem expectGetResult :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 602, 3⟩ =
      .ok ((), ⟨canonicalBytes, 622, 3⟩) := by
  apply expectTag_of_spine "CallableResult" 2 602 622 3
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeGetResultType :
    decodeU32le ⟨canonicalBytes, 622, 3⟩ =
      .ok (0, ⟨canonicalBytes, 626, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetVisTag :
    decodeTag ⟨canonicalBytes, 626, 4⟩ =
      .ok ("Visibility.Public", ⟨canonicalBytes, 647, 4⟩) := by
  apply decodeCanonicalTagV1 626 647 4
    [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
    "Visibility.Public"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetVisFc :
    decodeFieldCount 0 ⟨canonicalBytes, 647, 4⟩ =
      .ok ((), ⟨canonicalBytes, 649, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetVisibility :
    decodeVisibilityV1 ⟨canonicalBytes, 626, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 649, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 626, 3⟩ .public_
    ⟨canonicalBytes, 649, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · exact decodeGetVisTag
  · exact decodeGetVisFc

private theorem decodeGetResult :
    decodeCallableResultV1 ⟨canonicalBytes, 602, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨canonicalBytes, 649, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 602, 2⟩
    { typeId := 0, visibility := .public_ } ⟨canonicalBytes, 649, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectGetResult
  · exact decodeGetResultType
  · exact decodeGetVisibility

private theorem decodeGetEntryBlock :
    decodeU32le ⟨canonicalBytes, 649, 2⟩ =
      .ok (0, ⟨canonicalBytes, 653, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetCallable :
    decodeCallableV1 ⟨canonicalBytes, 553, 1⟩ =
      .ok (getCallable, ⟨canonicalBytes, 769, 1⟩) := by
  apply decodeCallableV1_singleBlockV1 ⟨canonicalBytes, 553, 1⟩
    ⟨canonicalBytes, 567, 2⟩ ⟨canonicalBytes, 571, 2⟩ ⟨canonicalBytes, 590, 2⟩
    ⟨canonicalBytes, 598, 2⟩ ⟨canonicalBytes, 649, 2⟩ ⟨canonicalBytes, 653, 2⟩
    ⟨canonicalBytes, 764, 2⟩ ⟨canonicalBytes, 769, 2⟩
    602 657 768 1 0 .view (some "get")
    { typeId := 0, visibility := .public_ } getBlock none (by decide)
  · exact expectGetCallable
  · exact decodeGetId
  · exact decodeGetKind
  · exact decodeGetName
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 598
      maxArrayElements = .ok (0, 602)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeGetResult
  · exact decodeGetEntryBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 653
      maxArrayElements = .ok (1, 657)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeGetBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 764
      maxArrayElements = .ok (0, 768)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · apply decodeOption_noneV1
    apply decodeCanonicalU8V1; rfl

/-! ### zero instruction 0: StateLoad -/


private theorem expectZeroI0Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 902, 4⟩ =
      .ok ((), ⟨canonicalBytes, 919, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 902 919 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectZeroI0VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 920, 5⟩ =
      .ok ((), ⟨canonicalBytes, 934, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 920 934 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeZeroI0VID :
    decodeU32le ⟨canonicalBytes, 934, 5⟩ =
      .ok (0, ⟨canonicalBytes, 938, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI0TID :
    decodeU32le ⟨canonicalBytes, 938, 5⟩ =
      .ok (0, ⟨canonicalBytes, 942, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI0ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 920, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 942, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 920, 4⟩
    ⟨canonicalBytes, 934, 5⟩ ⟨canonicalBytes, 938, 5⟩
    ⟨canonicalBytes, 942, 5⟩ 0 0 (by decide)
  · exact expectZeroI0VD
  · exact decodeZeroI0VID
  · exact decodeZeroI0TID

private theorem decodeZeroI0ResMark :
    decodeU8 ⟨canonicalBytes, 919, 4⟩ =
      .ok (1, ⟨canonicalBytes, 920, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeZeroI0Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 919, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨canonicalBytes, 942, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 919, 4⟩
    ⟨canonicalBytes, 920, 4⟩
    ⟨canonicalBytes, 942, 4⟩
    { valueId := 0, typeId := 0 }
  · exact decodeZeroI0ResMark
  · exact decodeZeroI0ValueDef

private theorem decodeZeroI0OpTag :
    decodeTag ⟨canonicalBytes, 942, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 958, 5⟩) := by
  apply decodeCanonicalTagV1 942 958 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeZeroI0OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 958, 5⟩ =
      .ok ((), ⟨canonicalBytes, 960, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeZeroI0StateId :
    decodeU32le ⟨canonicalBytes, 960, 5⟩ =
      .ok (0, ⟨canonicalBytes, 964, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI0Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 942, 4⟩ =
      .ok (.stateLoad 0, ⟨canonicalBytes, 964, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 942, 4⟩
    ⟨canonicalBytes, 958, 5⟩ ⟨canonicalBytes, 960, 5⟩
    ⟨canonicalBytes, 964, 5⟩ 0 (by decide)
  · exact decodeZeroI0OpTag
  · exact decodeZeroI0OpFc
  · exact decodeZeroI0StateId

private theorem decodeZeroI0Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 902, 3⟩ =
      .ok (valueInstruction 0 0 (.stateLoad 0), ⟨canonicalBytes, 964, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 902, 3⟩
    ⟨canonicalBytes, 919, 4⟩ ⟨canonicalBytes, 942, 4⟩ ⟨canonicalBytes, 964, 4⟩
    (some { valueId := 0, typeId := 0 }) (.stateLoad 0) (by decide)
    expectZeroI0Instr decodeZeroI0Result decodeZeroI0Op
  simpa [valueInstruction, valueDef] using h

/-! ### zero instruction 1: Literal 0 -/


private theorem expectZeroI1Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 964, 4⟩ =
      .ok ((), ⟨canonicalBytes, 981, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 964 981 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectZeroI1VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 982, 5⟩ =
      .ok ((), ⟨canonicalBytes, 996, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 982 996 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeZeroI1VID :
    decodeU32le ⟨canonicalBytes, 996, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1000, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI1TID :
    decodeU32le ⟨canonicalBytes, 1000, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1004, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI1ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 982, 4⟩ =
      .ok ({ valueId := 1, typeId := 0 }, ⟨canonicalBytes, 1004, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 982, 4⟩
    ⟨canonicalBytes, 996, 5⟩ ⟨canonicalBytes, 1000, 5⟩
    ⟨canonicalBytes, 1004, 5⟩ 1 0 (by decide)
  · exact expectZeroI1VD
  · exact decodeZeroI1VID
  · exact decodeZeroI1TID

private theorem decodeZeroI1ResMark :
    decodeU8 ⟨canonicalBytes, 981, 4⟩ =
      .ok (1, ⟨canonicalBytes, 982, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeZeroI1Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 981, 4⟩ =
      .ok (some { valueId := 1, typeId := 0 },
        ⟨canonicalBytes, 1004, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 981, 4⟩
    ⟨canonicalBytes, 982, 4⟩
    ⟨canonicalBytes, 1004, 4⟩
    { valueId := 1, typeId := 0 }
  · exact decodeZeroI1ResMark
  · exact decodeZeroI1ValueDef

private theorem decodeZeroI1OpTag :
    decodeTag ⟨canonicalBytes, 1004, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 1018, 5⟩) := by
  apply decodeCanonicalTagV1 1004 1018 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeZeroI1OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 1018, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1020, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeZeroI1LitType :
    decodeU32le ⟨canonicalBytes, 1020, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1024, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI1LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 1024, 5⟩ =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 1036, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 1024 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1036) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1024
      maxCanonicalProgramBytes = .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1036)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0, 0, 0, 0, 0, 0, 0, 0]
        1024 maxCanonicalProgramBytes 8 1028
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeZeroI1Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1004, 4⟩ =
      .ok (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray),
        ⟨canonicalBytes, 1036, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 1004, 4⟩
    ⟨canonicalBytes, 1018, 5⟩ ⟨canonicalBytes, 1020, 5⟩
    ⟨canonicalBytes, 1024, 5⟩ ⟨canonicalBytes, 1036, 5⟩
    0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray) (by decide)
  · exact decodeZeroI1OpTag
  · exact decodeZeroI1OpFc
  · exact decodeZeroI1LitType
  · exact decodeZeroI1LitBytes

private theorem decodeZeroI1Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 964, 3⟩ =
      .ok (valueInstruction 1 0 (.literal 0 zeroBytes), ⟨canonicalBytes, 1036, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 964, 3⟩
    ⟨canonicalBytes, 981, 4⟩ ⟨canonicalBytes, 1004, 4⟩ ⟨canonicalBytes, 1036, 4⟩
    (some { valueId := 1, typeId := 0 })
    (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray)) (by decide)
    expectZeroI1Instr decodeZeroI1Result decodeZeroI1Op
  simpa [valueInstruction, valueDef, zeroBytes] using h

/-! ### zero instruction 2: Binary.Eq -/


private theorem expectZeroI2Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1036, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1053, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1036 1053 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectZeroI2VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1054, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1068, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1054 1068 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeZeroI2VID :
    decodeU32le ⟨canonicalBytes, 1068, 5⟩ =
      .ok (2, ⟨canonicalBytes, 1072, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI2TID :
    decodeU32le ⟨canonicalBytes, 1072, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1076, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI2ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1054, 4⟩ =
      .ok ({ valueId := 2, typeId := 1 }, ⟨canonicalBytes, 1076, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1054, 4⟩
    ⟨canonicalBytes, 1068, 5⟩ ⟨canonicalBytes, 1072, 5⟩
    ⟨canonicalBytes, 1076, 5⟩ 2 1 (by decide)
  · exact expectZeroI2VD
  · exact decodeZeroI2VID
  · exact decodeZeroI2TID

private theorem decodeZeroI2ResMark :
    decodeU8 ⟨canonicalBytes, 1053, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1054, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeZeroI2Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1053, 4⟩ =
      .ok (some { valueId := 2, typeId := 1 },
        ⟨canonicalBytes, 1076, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1053, 4⟩
    ⟨canonicalBytes, 1054, 4⟩
    ⟨canonicalBytes, 1076, 4⟩
    { valueId := 2, typeId := 1 }
  · exact decodeZeroI2ResMark
  · exact decodeZeroI2ValueDef

private theorem decodeZeroI2OpTag :
    decodeTag ⟨canonicalBytes, 1076, 5⟩ =
      .ok ("Op.Binary", ⟨canonicalBytes, 1089, 5⟩) := by
  apply decodeCanonicalTagV1 1076 1089 5
    [79, 112, 46, 66, 105, 110, 97, 114, 121] "Op.Binary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeZeroI2OpFc :
    decodeFieldCount 3 ⟨canonicalBytes, 1089, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1091, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeZeroI2BinTag :
    decodeTag ⟨canonicalBytes, 1091, 6⟩ =
      .ok ("Binary.Eq", ⟨canonicalBytes, 1104, 6⟩) := by
  apply decodeCanonicalTagV1 1091 1104 6
    [66, 105, 110, 97, 114, 121, 46, 69, 113] "Binary.Eq"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeZeroI2BinFc :
    decodeFieldCount 0 ⟨canonicalBytes, 1104, 6⟩ =
      .ok ((), ⟨canonicalBytes, 1106, 6⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeZeroI2BinOp :
    decodeBinaryOpV1 ⟨canonicalBytes, 1091, 5⟩ =
      .ok (.eq, ⟨canonicalBytes, 1106, 5⟩) := by
  apply decodeBinaryOpV1_eqOp ⟨canonicalBytes, 1091, 5⟩
    ⟨canonicalBytes, 1104, 6⟩
    ⟨canonicalBytes, 1106, 6⟩ (by decide)
  · exact decodeZeroI2BinTag
  · exact decodeZeroI2BinFc

private theorem decodeZeroI2Lhs :
    decodeU32le ⟨canonicalBytes, 1106, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1110, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI2Rhs :
    decodeU32le ⟨canonicalBytes, 1110, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1114, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroI2Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1076, 4⟩ =
      .ok (.binary .eq 0 1, ⟨canonicalBytes, 1114, 4⟩) := by
  apply decodeSemanticOpV1_binary ⟨canonicalBytes, 1076, 4⟩
    ⟨canonicalBytes, 1089, 5⟩ ⟨canonicalBytes, 1091, 5⟩
    ⟨canonicalBytes, 1106, 5⟩ ⟨canonicalBytes, 1110, 5⟩
    ⟨canonicalBytes, 1114, 5⟩ .eq 0 1 (by decide)
  · exact decodeZeroI2OpTag
  · exact decodeZeroI2OpFc
  · exact decodeZeroI2BinOp
  · exact decodeZeroI2Lhs
  · exact decodeZeroI2Rhs

private theorem decodeZeroI2Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1036, 3⟩ =
      .ok (valueInstruction 2 1 (.binary .eq 0 1), ⟨canonicalBytes, 1114, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1036, 3⟩
    ⟨canonicalBytes, 1053, 4⟩ ⟨canonicalBytes, 1076, 4⟩ ⟨canonicalBytes, 1114, 4⟩
    (some { valueId := 2, typeId := 1 }) (.binary .eq 0 1) (by decide)
    expectZeroI2Instr decodeZeroI2Result decodeZeroI2Op
  simpa [valueInstruction, valueDef] using h

/-! ### zero terminator -/


private theorem decodeZeroTermTag :
    decodeTag ⟨canonicalBytes, 1114, 4⟩ =
      .ok ("Term.Return", ⟨canonicalBytes, 1129, 4⟩) := by
  apply decodeCanonicalTagV1 1114 1129 4
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeZeroTermFc :
    decodeFieldCount 1 ⟨canonicalBytes, 1129, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1131, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeZeroTermMark :
    decodeU8 ⟨canonicalBytes, 1131, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1132, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeZeroTermVal :
    decodeU32le ⟨canonicalBytes, 1132, 4⟩ =
      .ok (2, ⟨canonicalBytes, 1136, 4⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroReturn :
    decodeTerminatorV1 ⟨canonicalBytes, 1114, 3⟩ =
      .ok (.return_ (some 2), ⟨canonicalBytes, 1136, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 1114, 3⟩
    ⟨canonicalBytes, 1129, 4⟩ ⟨canonicalBytes, 1131, 4⟩
    ⟨canonicalBytes, 1136, 4⟩
    (some 2) (by decide)
  · exact decodeZeroTermTag
  · exact decodeZeroTermFc
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 1131, 4⟩
      ⟨canonicalBytes, 1132, 4⟩ ⟨canonicalBytes, 1136, 4⟩ 2
    · exact decodeZeroTermMark
    · exact decodeZeroTermVal


private theorem decodeZeroInstructions :
    decodeArray maxArrayElements decodeInstructionV1 ⟨canonicalBytes, 898, 3⟩ =
      .ok (zeroBlock.instructions, ⟨canonicalBytes, 1114, 3⟩) := by
  have h := decodeArray_threeV1 maxArrayElements decodeInstructionV1
    ⟨canonicalBytes, 898, 3⟩ 902
    (valueInstruction 0 0 (.stateLoad 0))
    (valueInstruction 1 0 (.literal 0 zeroBytes))
    (valueInstruction 2 1 (.binary .eq 0 1))
    ⟨canonicalBytes, 964, 3⟩ ⟨canonicalBytes, 1036, 3⟩ ⟨canonicalBytes, 1114, 3⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 898
        maxArrayElements = .ok (3, 902)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeZeroI0Instruction decodeZeroI1Instruction decodeZeroI2Instruction
  simpa [zeroBlock, valueInstruction, valueDef, zeroBytes] using h

private theorem expectZeroBlock :
    expectTag "Block" 4 ⟨canonicalBytes, 879, 3⟩ =
      .ok ((), ⟨canonicalBytes, 890, 3⟩) := by
  apply expectTag_of_spine "Block" 4 879 890 3
    [66, 108, 111, 99, 107] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeZeroBlockId :
    decodeU32le ⟨canonicalBytes, 890, 3⟩ = .ok (0, ⟨canonicalBytes, 894, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroBlock :
    decodeBlockV1 ⟨canonicalBytes, 879, 2⟩ =
      .ok (zeroBlock, ⟨canonicalBytes, 1136, 2⟩) := by
  apply decodeBlockV1_eq_of_fieldsV1 ⟨canonicalBytes, 879, 2⟩
    ⟨canonicalBytes, 890, 3⟩ ⟨canonicalBytes, 894, 3⟩
    ⟨canonicalBytes, 898, 3⟩ ⟨canonicalBytes, 1114, 3⟩ ⟨canonicalBytes, 1136, 3⟩
    0 #[] zeroBlock.instructions (.return_ (some 2)) (by decide)
  · exact expectZeroBlock
  · exact decodeZeroBlockId
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 894
      maxArrayElements = .ok (0, 898)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeZeroInstructions
  · exact decodeZeroReturn


/-! ### zero callable -/

private theorem expectZeroCallable :
    expectTag "Callable" 9 ⟨canonicalBytes, 769, 2⟩ =
      .ok ((), ⟨canonicalBytes, 783, 2⟩) := by
  apply expectTag_of_spine "Callable" 9 769 783 2
    [67, 97, 108, 108, 97, 98, 108, 101] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeZeroId :
    decodeU32le ⟨canonicalBytes, 783, 2⟩ =
      .ok (2, ⟨canonicalBytes, 787, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroKindTag :
    decodeTag ⟨canonicalBytes, 787, 3⟩ =
      .ok ("Callable.Invariant", ⟨canonicalBytes, 809, 3⟩) := by
  apply decodeCanonicalTagV1 787 809 3
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116]
    "Callable.Invariant"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeZeroKindFc :
    decodeFieldCount 0 ⟨canonicalBytes, 809, 3⟩ =
      .ok ((), ⟨canonicalBytes, 811, 3⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeZeroKind :
    decodeCallableKindV1 ⟨canonicalBytes, 787, 2⟩ =
      .ok (.invariant, ⟨canonicalBytes, 811, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 787, 2⟩ .invariant
    ⟨canonicalBytes, 811, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_invariant
  · exact decodeZeroKindTag
  · exact decodeZeroKindFc

private theorem decodeZeroNameMark :
    decodeU8 ⟨canonicalBytes, 811, 2⟩ =
      .ok (1, ⟨canonicalBytes, 812, 2⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeZeroNameStr :
    decodeString ⟨canonicalBytes, 812, 2⟩ =
      .ok ("zero", ⟨canonicalBytes, 820, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 812 maxStringBytes =
      .ok (ByteArray.mk [122, 101, 114, 111].toArray, 820)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [122, 101, 114, 111]
        812 maxStringBytes 4 816
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "zero" (by decide)

private theorem decodeZeroName :
    decodeOption decodeString ⟨canonicalBytes, 811, 2⟩ =
      .ok (some "zero", ⟨canonicalBytes, 820, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 811, 2⟩
    ⟨canonicalBytes, 812, 2⟩ ⟨canonicalBytes, 820, 2⟩ "zero"
  · exact decodeZeroNameMark
  · exact decodeZeroNameStr

private theorem expectZeroResult :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 824, 3⟩ =
      .ok ((), ⟨canonicalBytes, 844, 3⟩) := by
  apply expectTag_of_spine "CallableResult" 2 824 844 3
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeZeroResultType :
    decodeU32le ⟨canonicalBytes, 844, 3⟩ =
      .ok (1, ⟨canonicalBytes, 848, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroVisTag :
    decodeTag ⟨canonicalBytes, 848, 4⟩ =
      .ok ("Visibility.Public", ⟨canonicalBytes, 869, 4⟩) := by
  apply decodeCanonicalTagV1 848 869 4
    [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
    "Visibility.Public"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeZeroVisFc :
    decodeFieldCount 0 ⟨canonicalBytes, 869, 4⟩ =
      .ok ((), ⟨canonicalBytes, 871, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeZeroVisibility :
    decodeVisibilityV1 ⟨canonicalBytes, 848, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 871, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 848, 3⟩ .public_
    ⟨canonicalBytes, 871, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · exact decodeZeroVisTag
  · exact decodeZeroVisFc

private theorem decodeZeroResult :
    decodeCallableResultV1 ⟨canonicalBytes, 824, 2⟩ =
      .ok ({ typeId := 1, visibility := .public_ }, ⟨canonicalBytes, 871, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 824, 2⟩
    { typeId := 1, visibility := .public_ } ⟨canonicalBytes, 871, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectZeroResult
  · exact decodeZeroResultType
  · exact decodeZeroVisibility

private theorem decodeZeroEntryBlock :
    decodeU32le ⟨canonicalBytes, 871, 2⟩ =
      .ok (0, ⟨canonicalBytes, 875, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroCallable :
    decodeCallableV1 ⟨canonicalBytes, 769, 1⟩ =
      .ok (zeroCallable, ⟨canonicalBytes, 1149, 1⟩) := by
  apply decodeCallableV1_singleBlockV1 ⟨canonicalBytes, 769, 1⟩
    ⟨canonicalBytes, 783, 2⟩ ⟨canonicalBytes, 787, 2⟩ ⟨canonicalBytes, 811, 2⟩
    ⟨canonicalBytes, 820, 2⟩ ⟨canonicalBytes, 871, 2⟩ ⟨canonicalBytes, 875, 2⟩
    ⟨canonicalBytes, 1136, 2⟩ ⟨canonicalBytes, 1149, 2⟩
    824 879 1140 2 0 .invariant (some "zero")
    { typeId := 1, visibility := .public_ } zeroBlock (some 5) (by decide)
  · exact expectZeroCallable
  · exact decodeZeroId
  · exact decodeZeroKind
  · exact decodeZeroName
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 820
      maxArrayElements = .ok (0, 824)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeZeroResult
  · exact decodeZeroEntryBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 875
      maxArrayElements = .ok (1, 879)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeZeroBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1136
      maxArrayElements = .ok (0, 1140)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · -- some 5 as UInt64
    apply decodeOption_someV1 decodeU64le ⟨canonicalBytes, 1140, 2⟩
      ⟨canonicalBytes, 1141, 2⟩ ⟨canonicalBytes, 1149, 2⟩ 5
    · apply decodeCanonicalU8V1; rfl
    · apply decodeCanonicalU64V1; rfl


private theorem readCallablesCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 213 maxTableElements = .ok (3, 217) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 213 maxTableElements =
    .ok (3, 217)
  rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem decodeCallables_canonicalBytes :
    decodeArray maxTableElements decodeCallableV1 ⟨canonicalBytes, 213, 1⟩ =
      .ok (#[clearCallable, getCallable, zeroCallable],
        ⟨canonicalBytes, 1149, 1⟩) := by
  exact decodeArray_threeV1 maxTableElements decodeCallableV1
    ⟨canonicalBytes, 213, 1⟩ 217 clearCallable getCallable zeroCallable
    ⟨canonicalBytes, 553, 1⟩ ⟨canonicalBytes, 769, 1⟩ ⟨canonicalBytes, 1149, 1⟩
    readCallablesCount_canonicalBytes decodeClrCallable decodeGetCallable
    decodeZeroCallable


/-! ### invariants -/

private theorem readInvariantsCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 1149 maxTableElements = .ok (1, 1153) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1149 maxTableElements =
    .ok (1, 1153)
  rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem expectZeroInvDecl :
    expectTag "InvariantDecl" 3 ⟨canonicalBytes, 1153, 2⟩ =
      .ok ((), ⟨canonicalBytes, 1172, 2⟩) := by
  apply expectTag_of_spine "InvariantDecl" 3 1153 1172 2
    [73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeZeroInvId :
    decodeU32le ⟨canonicalBytes, 1172, 2⟩ =
      .ok (0, ⟨canonicalBytes, 1176, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroInvName :
    decodeString ⟨canonicalBytes, 1176, 2⟩ =
      .ok ("zero", ⟨canonicalBytes, 1184, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1176 maxStringBytes =
      .ok (ByteArray.mk [122, 101, 114, 111].toArray, 1184)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [122, 101, 114, 111]
        1176 maxStringBytes 4 1180
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "zero" (by decide)

private theorem decodeZeroInvCallable :
    decodeU32le ⟨canonicalBytes, 1184, 2⟩ =
      .ok (2, ⟨canonicalBytes, 1188, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeZeroInvDecl :
    decodeInvariantDeclV1 ⟨canonicalBytes, 1153, 1⟩ =
      .ok (zeroInvariant, ⟨canonicalBytes, 1188, 1⟩) := by
  refine decodeInvariantDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 1153, 1⟩ zeroInvariant
    ⟨canonicalBytes, 1188, 2⟩ (by decide) ?_
  apply decodeInvariantDeclBodyV1_eq_of_fields
  · exact expectZeroInvDecl
  · exact decodeZeroInvId
  · exact decodeZeroInvName
  · exact decodeZeroInvCallable

private theorem decodeInvariants_canonicalBytes :
    decodeArray maxTableElements decodeInvariantDeclV1 ⟨canonicalBytes, 1149, 1⟩ =
      .ok (#[zeroInvariant], ⟨canonicalBytes, 1188, 1⟩) := by
  exact decodeArray_oneV1 maxTableElements decodeInvariantDeclV1
    ⟨canonicalBytes, 1149, 1⟩ 1153 zeroInvariant ⟨canonicalBytes, 1188, 1⟩
    readInvariantsCount_canonicalBytes decodeZeroInvDecl

/-! ### requirements -/

private theorem expectProgramRequirements :
    expectTag "ProgramRequirements" 1 ⟨canonicalBytes, 1188, 2⟩ =
      .ok ((), ⟨canonicalBytes, 1213, 2⟩) := by
  apply expectTag_of_spine "ProgramRequirements" 1 1188 1213 2
    [80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 115] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectRollbackReq :
    expectTag "RequirementRequest" 4 ⟨canonicalBytes, 1217, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1241, 3⟩) := by
  apply expectTag_of_spine "RequirementRequest" 4 1217 1241 3
    [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeRollbackReqId :
    decodeString ⟨canonicalBytes, 1241, 3⟩ =
      .ok ("failure.atomic-rollback", ⟨canonicalBytes, 1268, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1241 maxStringBytes =
      .ok (ByteArray.mk [102, 97, 105, 108, 117, 114, 101, 46, 97, 116, 111, 109, 105, 99, 45, 114, 111, 108, 108, 98, 97, 99, 107].toArray, 1268)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [102, 97, 105, 108, 117, 114, 101, 46, 97, 116, 111, 109, 105, 99, 45, 114, 111, 108, 108, 98, 97, 99, 107]
        1241 maxStringBytes 23 1245
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "failure.atomic-rollback" (by decide)

private theorem decodeRollbackReqVer :
    decodeString ⟨canonicalBytes, 1268, 3⟩ =
      .ok ("1.0.0", ⟨canonicalBytes, 1277, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1268 maxStringBytes =
      .ok (ByteArray.mk [49, 46, 48, 46, 48].toArray, 1277)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [49, 46, 48, 46, 48]
        1268 maxStringBytes 5 1272
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "1.0.0" (by decide)

private theorem decodeRollbackReqSemVer :
    decodeSemVer ⟨canonicalBytes, 1268, 3⟩ =
      .ok (s2RequirementVersionV1, ⟨canonicalBytes, 1277, 3⟩) := by
  apply decodeSemVer_eq_of_stringV1
  · exact decodeRollbackReqVer
  · -- s2RequirementVersionV1 = s2CatalogSemVerCoreV1 definitionally
    simpa [s2RequirementVersionV1, s2CatalogSemVerCoreV1] using parseSemVer_1_0_0

private theorem decodeRollbackReqDigest :
    decodeDigest ⟨canonicalBytes, 1277, 3⟩ =
      .ok ({ algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1 },
        ⟨canonicalBytes, 1309, 3⟩) := by
  apply decodeDigest_eq_of_takeV1
  · have h : takeBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1277 32 =
        .ok (ByteArray.mk ([254, 98, 216, 232, 64, 20, 227, 236, 31, 23, 247, 108, 127, 85, 250, 195, 25, 2, 68, 236, 163, 173, 18, 77, 208, 78, 23, 195, 201, 209, 17, 101]).toArray) := by
      apply takeBytesAtV1_eq_of_spine canonicalSpine ([254, 98, 216, 232, 64, 20, 227, 236, 31, 23, 247, 108, 127, 85, 250, 195, 25, 2, 68, 236, 163, 173, 18, 77, 208, 78, 23, 195, 201, 209, 17, 101]) 1277
      unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    simpa [canonicalBytes, s2FailureAtomicRollbackDigestBytesV1] using h
  · simp [s2FailureAtomicRollbackDigestBytesV1, validateDigest]
    rfl

private theorem decodeRollbackReq :
    decodeRequirementRequestV1 ⟨canonicalBytes, 1217, 2⟩ =
      .ok (requirement "failure.atomic-rollback" s2FailureAtomicRollbackDigestBytesV1,
        ⟨canonicalBytes, 1313, 2⟩) := by
  apply decodeRequirementRequestV1_eq_of_fields ⟨canonicalBytes, 1217, 2⟩
    ⟨canonicalBytes, 1241, 3⟩ ⟨canonicalBytes, 1268, 3⟩
    ⟨canonicalBytes, 1277, 3⟩ ⟨canonicalBytes, 1309, 3⟩
    ⟨canonicalBytes, 1313, 3⟩
    "failure.atomic-rollback" s2RequirementVersionV1
    { algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1 } #[] (by decide)
  · exact expectRollbackReq
  · exact decodeRollbackReqId
  · exact decodeRollbackReqSemVer
  · exact decodeRollbackReqDigest
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1309
      maxArrayElements = .ok (0, 1313)
    rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem expectPersistentReq :
    expectTag "RequirementRequest" 4 ⟨canonicalBytes, 1313, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1337, 3⟩) := by
  apply expectTag_of_spine "RequirementRequest" 4 1313 1337 3
    [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodePersistentReqId :
    decodeString ⟨canonicalBytes, 1337, 3⟩ =
      .ok ("state.persistent", ⟨canonicalBytes, 1357, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1337 maxStringBytes =
      .ok (ByteArray.mk [115, 116, 97, 116, 101, 46, 112, 101, 114, 115, 105, 115, 116, 101, 110, 116].toArray, 1357)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [115, 116, 97, 116, 101, 46, 112, 101, 114, 115, 105, 115, 116, 101, 110, 116]
        1337 maxStringBytes 16 1341
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "state.persistent" (by decide)

private theorem decodePersistentReqVer :
    decodeString ⟨canonicalBytes, 1357, 3⟩ =
      .ok ("1.0.0", ⟨canonicalBytes, 1366, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1357 maxStringBytes =
      .ok (ByteArray.mk [49, 46, 48, 46, 48].toArray, 1366)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [49, 46, 48, 46, 48]
        1357 maxStringBytes 5 1361
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "1.0.0" (by decide)

private theorem decodePersistentReqSemVer :
    decodeSemVer ⟨canonicalBytes, 1357, 3⟩ =
      .ok (s2RequirementVersionV1, ⟨canonicalBytes, 1366, 3⟩) := by
  apply decodeSemVer_eq_of_stringV1
  · exact decodePersistentReqVer
  · -- s2RequirementVersionV1 = s2CatalogSemVerCoreV1 definitionally
    simpa [s2RequirementVersionV1, s2CatalogSemVerCoreV1] using parseSemVer_1_0_0

private theorem decodePersistentReqDigest :
    decodeDigest ⟨canonicalBytes, 1366, 3⟩ =
      .ok ({ algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 },
        ⟨canonicalBytes, 1398, 3⟩) := by
  apply decodeDigest_eq_of_takeV1
  · have h : takeBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1366 32 =
        .ok (ByteArray.mk ([2, 63, 255, 245, 41, 95, 167, 238, 77, 158, 78, 73, 144, 154, 62, 183, 241, 252, 12, 86, 31, 142, 126, 160, 111, 18, 66, 52, 12, 20, 110, 229]).toArray) := by
      apply takeBytesAtV1_eq_of_spine canonicalSpine ([2, 63, 255, 245, 41, 95, 167, 238, 77, 158, 78, 73, 144, 154, 62, 183, 241, 252, 12, 86, 31, 142, 126, 160, 111, 18, 66, 52, 12, 20, 110, 229]) 1366
      unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    simpa [canonicalBytes, s2StatePersistentDigestBytesV1] using h
  · simp [s2StatePersistentDigestBytesV1, validateDigest]
    rfl

private theorem decodePersistentReq :
    decodeRequirementRequestV1 ⟨canonicalBytes, 1313, 2⟩ =
      .ok (requirement "state.persistent" s2StatePersistentDigestBytesV1,
        ⟨canonicalBytes, 1402, 2⟩) := by
  apply decodeRequirementRequestV1_eq_of_fields ⟨canonicalBytes, 1313, 2⟩
    ⟨canonicalBytes, 1337, 3⟩ ⟨canonicalBytes, 1357, 3⟩
    ⟨canonicalBytes, 1366, 3⟩ ⟨canonicalBytes, 1398, 3⟩
    ⟨canonicalBytes, 1402, 3⟩
    "state.persistent" s2RequirementVersionV1
    { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 } #[] (by decide)
  · exact expectPersistentReq
  · exact decodePersistentReqId
  · exact decodePersistentReqSemVer
  · exact decodePersistentReqDigest
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1398
      maxArrayElements = .ok (0, 1402)
    rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem expectCheckedReq :
    expectTag "RequirementRequest" 4 ⟨canonicalBytes, 1402, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1426, 3⟩) := by
  apply expectTag_of_spine "RequirementRequest" 4 1402 1426 3
    [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeCheckedReqId :
    decodeString ⟨canonicalBytes, 1426, 3⟩ =
      .ok ("value.checked-arithmetic", ⟨canonicalBytes, 1454, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1426 maxStringBytes =
      .ok (ByteArray.mk [118, 97, 108, 117, 101, 46, 99, 104, 101, 99, 107, 101, 100, 45, 97, 114, 105, 116, 104, 109, 101, 116, 105, 99].toArray, 1454)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [118, 97, 108, 117, 101, 46, 99, 104, 101, 99, 107, 101, 100, 45, 97, 114, 105, 116, 104, 109, 101, 116, 105, 99]
        1426 maxStringBytes 24 1430
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "value.checked-arithmetic" (by decide)

private theorem decodeCheckedReqVer :
    decodeString ⟨canonicalBytes, 1454, 3⟩ =
      .ok ("1.0.0", ⟨canonicalBytes, 1463, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1454 maxStringBytes =
      .ok (ByteArray.mk [49, 46, 48, 46, 48].toArray, 1463)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [49, 46, 48, 46, 48]
        1454 maxStringBytes 5 1458
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "1.0.0" (by decide)

private theorem decodeCheckedReqSemVer :
    decodeSemVer ⟨canonicalBytes, 1454, 3⟩ =
      .ok (s2RequirementVersionV1, ⟨canonicalBytes, 1463, 3⟩) := by
  apply decodeSemVer_eq_of_stringV1
  · exact decodeCheckedReqVer
  · -- s2RequirementVersionV1 = s2CatalogSemVerCoreV1 definitionally
    simpa [s2RequirementVersionV1, s2CatalogSemVerCoreV1] using parseSemVer_1_0_0

private theorem decodeCheckedReqDigest :
    decodeDigest ⟨canonicalBytes, 1463, 3⟩ =
      .ok ({ algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1 },
        ⟨canonicalBytes, 1495, 3⟩) := by
  apply decodeDigest_eq_of_takeV1
  · have h : takeBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1463 32 =
        .ok (ByteArray.mk ([226, 24, 107, 1, 207, 88, 19, 81, 17, 247, 78, 197, 106, 83, 227, 51, 135, 188, 48, 22, 72, 104, 7, 27, 31, 82, 74, 242, 34, 184, 191, 205]).toArray) := by
      apply takeBytesAtV1_eq_of_spine canonicalSpine ([226, 24, 107, 1, 207, 88, 19, 81, 17, 247, 78, 197, 106, 83, 227, 51, 135, 188, 48, 22, 72, 104, 7, 27, 31, 82, 74, 242, 34, 184, 191, 205]) 1463
      unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    simpa [canonicalBytes, s2ValueCheckedArithmeticDigestBytesV1] using h
  · simp [s2ValueCheckedArithmeticDigestBytesV1, validateDigest]
    rfl

private theorem decodeCheckedReq :
    decodeRequirementRequestV1 ⟨canonicalBytes, 1402, 2⟩ =
      .ok (requirement "value.checked-arithmetic" s2ValueCheckedArithmeticDigestBytesV1,
        ⟨canonicalBytes, 1499, 2⟩) := by
  apply decodeRequirementRequestV1_eq_of_fields ⟨canonicalBytes, 1402, 2⟩
    ⟨canonicalBytes, 1426, 3⟩ ⟨canonicalBytes, 1454, 3⟩
    ⟨canonicalBytes, 1463, 3⟩ ⟨canonicalBytes, 1495, 3⟩
    ⟨canonicalBytes, 1499, 3⟩
    "value.checked-arithmetic" s2RequirementVersionV1
    { algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1 } #[] (by decide)
  · exact expectCheckedReq
  · exact decodeCheckedReqId
  · exact decodeCheckedReqSemVer
  · exact decodeCheckedReqDigest
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1495
      maxArrayElements = .ok (0, 1499)
    rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem decodeRequirements_canonicalBytes :
    decodeProgramRequirementsV1 ⟨canonicalBytes, 1188, 1⟩ =
      .ok ({ items := #[rollbackRequirement, persistentStateRequirement,
          checkedArithmeticRequirement] }, ⟨canonicalBytes, 1499, 1⟩) := by
  refine decodeProgramRequirementsV1_eq_of_bodyV1 ⟨canonicalBytes, 1188, 1⟩
    { items := #[rollbackRequirement, persistentStateRequirement,
        checkedArithmeticRequirement] }
    ⟨canonicalBytes, 1499, 2⟩ (by decide) ?_
  apply decodeProgramRequirementsBodyV1_eq_of_fields
  · exact expectProgramRequirements
  · exact decodeArray_threeV1 maxArrayElements decodeRequirementRequestV1
      ⟨canonicalBytes, 1213, 2⟩ 1217
      rollbackRequirement persistentStateRequirement checkedArithmeticRequirement
      ⟨canonicalBytes, 1313, 2⟩ ⟨canonicalBytes, 1402, 2⟩ ⟨canonicalBytes, 1499, 2⟩
      (by
        change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1213
          maxArrayElements = .ok (3, 1217)
        rw [readArrayCountAtV1_refinesSpine]; rfl)
      (by simpa [rollbackRequirement, requirement] using decodeRollbackReq)
      (by simpa [persistentStateRequirement, requirement] using decodePersistentReq)
      (by simpa [checkedArithmeticRequirement, requirement] using decodeCheckedReq)


/-! ### Root tagged composition + public decode_ok -/

private theorem decodeTaggedData_canonicalBytes :
    decodeSemanticProgramDataTaggedV1 ⟨canonicalBytes, 15, 0⟩ =
      .ok (data, ⟨canonicalBytes, 1499, 0⟩) := by
  have h := decodeSemanticProgramDataTaggedV1_eq_of_fields
    ⟨canonicalBytes, 15, 0⟩ ⟨canonicalBytes, 41, 1⟩
    ⟨canonicalBytes, 68, 1⟩ ⟨canonicalBytes, 142, 1⟩
    ⟨canonicalBytes, 146, 1⟩ ⟨canonicalBytes, 205, 1⟩
    ⟨canonicalBytes, 209, 1⟩ ⟨canonicalBytes, 213, 1⟩
    ⟨canonicalBytes, 1149, 1⟩ ⟨canonicalBytes, 1188, 1⟩
    ⟨canonicalBytes, 1499, 1⟩ qualifiedName types #[] #[countState] #[] #[]
    #[clearCallable, getCallable, zeroCallable] #[zeroInvariant]
    { items := #[rollbackRequirement, persistentStateRequirement,
        checkedArithmeticRequirement] } (by decide)
    expectRootTag_canonicalBytes decodeQualifiedName_canonicalBytes
    decodeTypes_canonicalBytes decodeConstants_canonicalBytes
    decodeLogicalState_canonicalBytes decodeEvents_canonicalBytes
    decodeErrors_canonicalBytes decodeCallables_canonicalBytes
    decodeInvariants_canonicalBytes decodeRequirements_canonicalBytes
  simpa [data] using h

/-- Production transport decoder certificate for the closed ZeroCounter instance. -/
theorem decode_ok :
    decodeSemanticProgramDataV1 ZeroCounterV1.canonicalBytes =
      .ok ZeroCounterV1.data := by
  apply decodeSemanticProgramDataV1_eq_of_framing canonicalBytes
    ⟨canonicalBytes, 15, 0⟩ ⟨canonicalBytes, 1499, 0⟩ data
  · change canonicalSpine.length ≤ maxCanonicalProgramBytes
    rw [canonicalSpine_length]
    decide
  · exact consumeMagic_canonicalBytes
  · exact decodeTaggedData_canonicalBytes
  · apply finish_eq_ok_of_offset_sizeV1
    change 1499 = canonicalSpine.length
    exact canonicalSpine_length.symm

end ProofForgeV2.ProofInstances.ZeroCounterDecodeV1
