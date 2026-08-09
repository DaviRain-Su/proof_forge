import ProofForgeV2.ProofInstances.MiniAmmEmptyPoolV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Core.Unicode

/-!
  Production transport decoder certificate for closed MiniAmmEmptyPool (bf3-preserve).

  Proves `decodeSemanticProgramDataV1 MiniAmmEmptyPoolV1.canonicalBytes = .ok MiniAmmEmptyPoolV1.data`
  solely via production decoder composition/refinement theorems and the exact
  `canonicalSpine`. No second decoder, sorry, axiom, native_decide, ofReduceBool,
  run_tac, unsafe, meta, or IO.
-/

namespace ProofForgeV2.ProofInstances.MiniAmmEmptyPoolDecodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.ProofInstances.MiniAmmEmptyPoolV1

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

private theorem decodeCanonicalU64V1 (offset after nesting value : Nat)
    (hspine : readSpineU64leV1 canonicalSpine offset =
      .ok (UInt64.ofNat value, after)) :
    decodeU64le ⟨canonicalBytes, offset, nesting⟩ =
      .ok (UInt64.ofNat value, ⟨canonicalBytes, after, nesting⟩) := by
  apply decodeU64le_eq_of_readV1
  change readU64leAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (UInt64.ofNat value, after)
  rw [readU64leAtV1_refinesSpine, hspine]

private theorem decodeCanonicalU16V1 (offset after nesting value : Nat)
    (hspine : readSpineU16leV1 canonicalSpine offset =
      .ok (UInt16.ofNat value, after)) :
    decodeU16le ⟨canonicalBytes, offset, nesting⟩ =
      .ok (UInt16.ofNat value, ⟨canonicalBytes, after, nesting⟩) := by
  apply decodeU16le_eq_of_readV1
  change readU16leAtV1 (ByteArray.mk canonicalSpine.toArray) offset =
    .ok (UInt16.ofNat value, after)
  rw [readU16leAtV1_refinesSpine, hspine]

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

private theorem decodeBinaryOpV1_eqOp
    (c afterTag afterFields : Cursor) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Binary.Eq", afterTag))
    (hfields : decodeFieldCount 0 afterTag = .ok ((), afterFields)) :
    decodeBinaryOpV1 c = .ok (.eq, ⟨afterFields.input, afterFields.offset, c.nesting⟩) := by
  unfold decodeBinaryOpV1 withTaggedNesting
  simp only [hdepth, ↓reduceIte, htag, hfields, Bind.bind, Pure.pure, Except.bind,
    Except.pure]

private theorem decodeBinaryOpV1_andOp
    (c afterTag afterFields : Cursor) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Binary.And", afterTag))
    (hfields : decodeFieldCount 0 afterTag = .ok ((), afterFields)) :
    decodeBinaryOpV1 c = .ok (.and, ⟨afterFields.input, afterFields.offset, c.nesting⟩) := by
  unfold decodeBinaryOpV1 withTaggedNesting
  simp only [hdepth, ↓reduceIte, htag, hfields, Bind.bind, Pure.pure, Except.bind,
    Except.pure]

private theorem decodeBinaryOpV1_orOp
    (c afterTag afterFields : Cursor) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Binary.Or", afterTag))
    (hfields : decodeFieldCount 0 afterTag = .ok ((), afterFields)) :
    decodeBinaryOpV1 c = .ok (.or, ⟨afterFields.input, afterFields.offset, c.nesting⟩) := by
  unfold decodeBinaryOpV1 withTaggedNesting
  simp only [hdepth, ↓reduceIte, htag, hfields, Bind.bind, Pure.pure, Except.bind,
    Except.pure]

private theorem decodeUnaryOpV1_notOp
    (c afterTag afterFields : Cursor) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Unary.Not", afterTag))
    (hfields : decodeFieldCount 0 afterTag = .ok ((), afterFields)) :
    decodeUnaryOpV1 c = .ok (.not, ⟨afterFields.input, afterFields.offset, c.nesting⟩) := by
  unfold decodeUnaryOpV1 withTaggedNesting
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

private theorem decodeSemanticOpBodyV1_unary
    (c afterTag afterFields afterOp afterOperand : Cursor)
    (op : UnaryOpV1) (operand : UInt32)
    (htag : decodeTag c = .ok ("Op.Unary", afterTag))
    (hfields : decodeFieldCount 2 afterTag = .ok ((), afterFields))
    (hop : decodeUnaryOpV1 afterFields = .ok (op, afterOp))
    (hopnd : decodeU32le afterOp = .ok (operand, afterOperand)) :
    decodeSemanticOpBodyV1 c = .ok (.unary op operand, afterOperand) := by
  simp only [decodeSemanticOpBodyV1, htag, hfields, hop, hopnd, Bind.bind,
    Pure.pure, Except.bind, Except.pure]

private theorem decodeSemanticOpV1_unary
    (c afterTag afterFields afterOp afterOperand : Cursor)
    (op : UnaryOpV1) (operand : UInt32) (hdepth : c.nesting < maxNesting)
    (htag : decodeTag ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ("Op.Unary", afterTag))
    (hfields : decodeFieldCount 2 afterTag = .ok ((), afterFields))
    (hop : decodeUnaryOpV1 afterFields = .ok (op, afterOp))
    (hopnd : decodeU32le afterOp = .ok (operand, afterOperand)) :
    decodeSemanticOpV1 c = .ok (.unary op operand,
      ⟨afterOperand.input, afterOperand.offset, c.nesting⟩) :=
  decodeSemanticOpV1_eq_of_bodyV1 c (.unary op operand) afterOperand hdepth
    (decodeSemanticOpBodyV1_unary ⟨c.input, c.offset, c.nesting + 1⟩ afterTag
      afterFields afterOp afterOperand op operand htag hfields hop hopnd)

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

private theorem decodeArray_threeV1 (maxCount : Nat) (decode : Decoder α) (c : Cursor)
    (offset : Nat) (v0 v1 v2 : α) (c1 c2 c3 : Cursor)
    (hcount : readArrayCountAtV1 c.input c.offset maxCount = .ok (3, offset))
    (h0 : decode ⟨c.input, offset, c.nesting⟩ = .ok (v0, c1))
    (h1 : decode c1 = .ok (v1, c2))
    (h2 : decode c2 = .ok (v2, c3)) :
    decodeArray maxCount decode c = .ok (#[v0, v1, v2], c3) := by
  apply decodeArray_eq_of_elementsV1 maxCount decode c 3 offset
    #[v0, v1, v2] c3 hcount
  simp [decodeArrayElementsV1, h0, h1, h2]

private theorem decodeArray_sevenV1 (maxCount : Nat) (decode : Decoder α) (c : Cursor)
    (offset : Nat) (v0 v1 v2 v3 v4 v5 v6 : α)
    (c1 c2 c3 c4 c5 c6 c7 : Cursor)
    (hcount : readArrayCountAtV1 c.input c.offset maxCount = .ok (7, offset))
    (h0 : decode ⟨c.input, offset, c.nesting⟩ = .ok (v0, c1))
    (h1 : decode c1 = .ok (v1, c2))
    (h2 : decode c2 = .ok (v2, c3))
    (h3 : decode c3 = .ok (v3, c4))
    (h4 : decode c4 = .ok (v4, c5))
    (h5 : decode c5 = .ok (v5, c6))
    (h6 : decode c6 = .ok (v6, c7)) :
    decodeArray maxCount decode c = .ok (#[v0, v1, v2, v3, v4, v5, v6], c7) := by
  apply decodeArray_eq_of_elementsV1 maxCount decode c 7 offset
    #[v0, v1, v2, v3, v4, v5, v6] c7 hcount
  simp [decodeArrayElementsV1, h0, h1, h2, h3, h4, h5, h6]

private theorem decodeArray_twelveV1 (maxCount : Nat) (decode : Decoder α) (c : Cursor)
    (offset : Nat)
    (v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 : α)
    (c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 : Cursor)
    (hcount : readArrayCountAtV1 c.input c.offset maxCount = .ok (12, offset))
    (h0 : decode ⟨c.input, offset, c.nesting⟩ = .ok (v0, c1))
    (h1 : decode c1 = .ok (v1, c2))
    (h2 : decode c2 = .ok (v2, c3))
    (h3 : decode c3 = .ok (v3, c4))
    (h4 : decode c4 = .ok (v4, c5))
    (h5 : decode c5 = .ok (v5, c6))
    (h6 : decode c6 = .ok (v6, c7))
    (h7 : decode c7 = .ok (v7, c8))
    (h8 : decode c8 = .ok (v8, c9))
    (h9 : decode c9 = .ok (v9, c10))
    (h10 : decode c10 = .ok (v10, c11))
    (h11 : decode c11 = .ok (v11, c12)) :
    decodeArray maxCount decode c =
      .ok (#[v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11], c12) := by
  apply decodeArray_eq_of_elementsV1 maxCount decode c 12 offset
    #[v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11] c12 hcount
  simp [decodeArrayElementsV1, h0, h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11]


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

private theorem readMiniAmmEmptyPoolBytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 53 maxStringBytes =
      .ok (ByteArray.mk
        [77, 105, 110, 105, 65, 109, 109, 69, 109, 112, 116, 121, 80, 111, 111, 108].toArray, 73) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 53 maxStringBytes =
    .ok (ByteArray.mk
      [77, 105, 110, 105, 65, 109, 109, 69, 109, 112, 116, 121, 80, 111, 111, 108].toArray, 73)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
      [77, 105, 110, 105, 65, 109, 109, 69, 109, 112, 116, 121, 80, 111, 111, 108]
      53 maxStringBytes 16 57
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

private theorem decodeMiniAmmEmptyPoolV1_of_read (bytes : ByteArray)
    (hread : readSizedBytesAtV1 bytes 53 maxStringBytes =
      .ok (ByteArray.mk
        [77, 105, 110, 105, 65, 109, 109, 69, 109, 112, 116, 121, 80, 111, 111, 108].toArray, 73)) :
    decodeString ⟨bytes, 53, 1⟩ = .ok ("MiniAmmEmptyPool", ⟨bytes, 73, 1⟩) := by
  apply decodeString_eq_of_valueV1 _ _ _ _ hread
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "MiniAmmEmptyPool" (by decide)

private theorem decodeQualifiedName_canonicalBytes :
    decodeQualifiedName ⟨canonicalBytes, 41, 1⟩ =
      .ok (qualifiedName, ⟨canonicalBytes, 73, 1⟩) := by
  apply decodeQualifiedName_eq_of_arrayV1
  · apply decodeArray_twoV1
    · exact readQualifiedNameCount_canonicalBytes
    · exact decodeRootV1_of_read canonicalBytes readRootBytes_canonicalBytes
    · exact decodeMiniAmmEmptyPoolV1_of_read canonicalBytes
        readMiniAmmEmptyPoolBytes_canonicalBytes
  · rfl

/-! ### Types (UInt64, Bool) 73→147 -/

private theorem readTypesCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 73 maxTableElements = .ok (2, 77) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 73 maxTableElements =
    .ok (2, 77)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem expectTypeDecl0_canonicalBytes :
    expectTag "TypeDecl" 3 ⟨canonicalBytes, 77, 2⟩ =
      .ok ((), ⟨canonicalBytes, 91, 2⟩) := by
  apply expectTag_of_spine "TypeDecl" 3 77 91 2
    [84, 121, 112, 101, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeTypeId0_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 91, 2⟩ = .ok (0, ⟨canonicalBytes, 95, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeNoTypeName0_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 95, 2⟩ =
      .ok (none, ⟨canonicalBytes, 96, 2⟩) := by
  apply decodeOption_noneV1
  apply decodeCanonicalU8V1
  rfl

private theorem decodeTypeShapeUInt64_canonicalBytes :
    decodeTypeShapeV1 ⟨canonicalBytes, 96, 2⟩ =
      .ok (.uint 64, ⟨canonicalBytes, 113, 2⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1 ⟨canonicalBytes, 96, 2⟩ (.uint 64)
    ⟨canonicalBytes, 113, 3⟩ (by decide) ?_
  apply decodeTypeShapeBodyV1_uint
  · apply decodeCanonicalTagV1 96 109 3
      [84, 121, 112, 101, 46, 85, 73, 110, 116] "Type.UInt"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 1 109 111 3 (by rfl) (by decide)
  · apply decodeCanonicalU16V1 111 113 3 64
    rfl

private theorem decodeTypeDecl0_canonicalBytes :
    decodeTypeDeclV1 ⟨canonicalBytes, 77, 1⟩ =
      .ok (uint64Type, ⟨canonicalBytes, 113, 1⟩) := by
  refine decodeTypeDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 77, 1⟩ uint64Type
    ⟨canonicalBytes, 113, 2⟩ (by decide) ?_
  apply decodeTypeDeclBodyV1_eq_of_fields
  · exact expectTypeDecl0_canonicalBytes
  · exact decodeTypeId0_canonicalBytes
  · exact decodeNoTypeName0_canonicalBytes
  · exact decodeTypeShapeUInt64_canonicalBytes

private theorem expectTypeDecl1_canonicalBytes :
    expectTag "TypeDecl" 3 ⟨canonicalBytes, 113, 2⟩ =
      .ok ((), ⟨canonicalBytes, 127, 2⟩) := by
  apply expectTag_of_spine "TypeDecl" 3 113 127 2
    [84, 121, 112, 101, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeTypeId1_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 127, 2⟩ = .ok (1, ⟨canonicalBytes, 131, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeNoTypeName1_canonicalBytes :
    decodeOption decodeString ⟨canonicalBytes, 131, 2⟩ =
      .ok (none, ⟨canonicalBytes, 132, 2⟩) := by
  apply decodeOption_noneV1
  apply decodeCanonicalU8V1
  rfl

private theorem decodeTypeShapeBool_canonicalBytes :
    decodeTypeShapeV1 ⟨canonicalBytes, 132, 2⟩ =
      .ok (.bool, ⟨canonicalBytes, 147, 2⟩) := by
  refine decodeTypeShapeV1_eq_of_bodyV1 ⟨canonicalBytes, 132, 2⟩ .bool
    ⟨canonicalBytes, 147, 3⟩ (by decide) ?_
  apply decodeTypeShapeBodyV1_bool
  · apply decodeCanonicalTagV1 132 145 3
      [84, 121, 112, 101, 46, 66, 111, 111, 108] "Type.Bool"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 145 147 3 (by rfl) (by decide)

private theorem decodeTypeDecl1_canonicalBytes :
    decodeTypeDeclV1 ⟨canonicalBytes, 113, 1⟩ =
      .ok (boolType, ⟨canonicalBytes, 147, 1⟩) := by
  refine decodeTypeDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 113, 1⟩ boolType
    ⟨canonicalBytes, 147, 2⟩ (by decide) ?_
  apply decodeTypeDeclBodyV1_eq_of_fields
  · exact expectTypeDecl1_canonicalBytes
  · exact decodeTypeId1_canonicalBytes
  · exact decodeNoTypeName1_canonicalBytes
  · exact decodeTypeShapeBool_canonicalBytes

private theorem decodeTypes_canonicalBytes :
    decodeArray maxTableElements decodeTypeDeclV1 ⟨canonicalBytes, 73, 1⟩ =
      .ok (types, ⟨canonicalBytes, 147, 1⟩) := by
  have h := decodeArray_twoV1 maxTableElements decodeTypeDeclV1
    ⟨canonicalBytes, 73, 1⟩ 77 uint64Type boolType
    ⟨canonicalBytes, 113, 1⟩ ⟨canonicalBytes, 147, 1⟩
    readTypesCount_canonicalBytes decodeTypeDecl0_canonicalBytes
    decodeTypeDecl1_canonicalBytes
  simpa [types] using h

/-! ### Empty constants / events / errors + three states -/

private theorem decodeConstants_canonicalBytes :
    decodeArray maxTableElements decodeConstantV1 ⟨canonicalBytes, 147, 1⟩ =
      .ok (#[], ⟨canonicalBytes, 151, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 147 maxTableElements =
    .ok (0, 151)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem readStateCount_canonicalBytes :
    readArrayCountAtV1 canonicalBytes 151 maxTableElements = .ok (3, 155) := by
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 151 maxTableElements =
    .ok (3, 155)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem expectStateDecl0_canonicalBytes :
    expectTag "StateDecl" 4 ⟨canonicalBytes, 155, 2⟩ =
      .ok ((), ⟨canonicalBytes, 170, 2⟩) := by
  apply expectTag_of_spine "StateDecl" 4 155 170 2
    [83, 116, 97, 116, 101, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeStateId0_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 170, 2⟩ = .ok (0, ⟨canonicalBytes, 174, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem readStateName0Bytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 174 maxStringBytes =
      .ok (ByteArray.mk [114, 101, 115, 101, 114, 118, 101, 48].toArray, 186) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 174 maxStringBytes =
    .ok (ByteArray.mk [114, 101, 115, 101, 114, 118, 101, 48].toArray, 186)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [114, 101, 115, 101, 114, 118, 101, 48]
      174 maxStringBytes 8 178
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeStateName0_canonicalBytes :
    decodeString ⟨canonicalBytes, 174, 2⟩ =
      .ok ("reserve0", ⟨canonicalBytes, 186, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · exact readStateName0Bytes_canonicalBytes
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "reserve0" (by decide)

private theorem decodeStateTypeId0_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 186, 2⟩ = .ok (0, ⟨canonicalBytes, 190, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeStateVisibility0_canonicalBytes :
    decodeVisibilityV1 ⟨canonicalBytes, 190, 2⟩ =
      .ok (.public_, ⟨canonicalBytes, 213, 2⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 190, 2⟩ .public_
    ⟨canonicalBytes, 213, 3⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · apply decodeCanonicalTagV1 190 211 3
      [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
      "Visibility.Public"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 211 213 3 (by rfl) (by decide)

private theorem decodeStateDecl0_canonicalBytes :
    decodeStateDeclV1 ⟨canonicalBytes, 155, 1⟩ =
      .ok (reserve0State, ⟨canonicalBytes, 213, 1⟩) := by
  refine decodeStateDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 155, 1⟩ reserve0State
    ⟨canonicalBytes, 213, 2⟩ (by decide) ?_
  apply decodeStateDeclBodyV1_eq_of_fields
  · exact expectStateDecl0_canonicalBytes
  · exact decodeStateId0_canonicalBytes
  · exact decodeStateName0_canonicalBytes
  · exact decodeStateTypeId0_canonicalBytes
  · exact decodeStateVisibility0_canonicalBytes

private theorem expectStateDecl1_canonicalBytes :
    expectTag "StateDecl" 4 ⟨canonicalBytes, 213, 2⟩ =
      .ok ((), ⟨canonicalBytes, 228, 2⟩) := by
  apply expectTag_of_spine "StateDecl" 4 213 228 2
    [83, 116, 97, 116, 101, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeStateId1_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 228, 2⟩ = .ok (1, ⟨canonicalBytes, 232, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem readStateName1Bytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 232 maxStringBytes =
      .ok (ByteArray.mk [114, 101, 115, 101, 114, 118, 101, 49].toArray, 244) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 232 maxStringBytes =
    .ok (ByteArray.mk [114, 101, 115, 101, 114, 118, 101, 49].toArray, 244)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [114, 101, 115, 101, 114, 118, 101, 49]
      232 maxStringBytes 8 236
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeStateName1_canonicalBytes :
    decodeString ⟨canonicalBytes, 232, 2⟩ =
      .ok ("reserve1", ⟨canonicalBytes, 244, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · exact readStateName1Bytes_canonicalBytes
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "reserve1" (by decide)

private theorem decodeStateTypeId1_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 244, 2⟩ = .ok (0, ⟨canonicalBytes, 248, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeStateVisibility1_canonicalBytes :
    decodeVisibilityV1 ⟨canonicalBytes, 248, 2⟩ =
      .ok (.public_, ⟨canonicalBytes, 271, 2⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 248, 2⟩ .public_
    ⟨canonicalBytes, 271, 3⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · apply decodeCanonicalTagV1 248 269 3
      [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
      "Visibility.Public"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 269 271 3 (by rfl) (by decide)

private theorem decodeStateDecl1_canonicalBytes :
    decodeStateDeclV1 ⟨canonicalBytes, 213, 1⟩ =
      .ok (reserve1State, ⟨canonicalBytes, 271, 1⟩) := by
  refine decodeStateDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 213, 1⟩ reserve1State
    ⟨canonicalBytes, 271, 2⟩ (by decide) ?_
  apply decodeStateDeclBodyV1_eq_of_fields
  · exact expectStateDecl1_canonicalBytes
  · exact decodeStateId1_canonicalBytes
  · exact decodeStateName1_canonicalBytes
  · exact decodeStateTypeId1_canonicalBytes
  · exact decodeStateVisibility1_canonicalBytes

private theorem expectStateDecl2_canonicalBytes :
    expectTag "StateDecl" 4 ⟨canonicalBytes, 271, 2⟩ =
      .ok ((), ⟨canonicalBytes, 286, 2⟩) := by
  apply expectTag_of_spine "StateDecl" 4 271 286 2
    [83, 116, 97, 116, 101, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeStateId2_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 286, 2⟩ = .ok (2, ⟨canonicalBytes, 290, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem readStateName2Bytes_canonicalBytes :
    readSizedBytesAtV1 canonicalBytes 290 maxStringBytes =
      .ok (ByteArray.mk [116, 111, 116, 97, 108, 83, 117, 112, 112, 108, 121].toArray, 305) := by
  change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 290 maxStringBytes =
    .ok (ByteArray.mk [116, 111, 116, 97, 108, 83, 117, 112, 112, 108, 121].toArray, 305)
  apply readSizedBytesAtV1_eq_of_spine
  apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [116, 111, 116, 97, 108, 83, 117, 112, 112, 108, 121]
      290 maxStringBytes 11 294
  · rfl
  · decide
  · decide
  · unfold takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]
    rfl

private theorem decodeStateName2_canonicalBytes :
    decodeString ⟨canonicalBytes, 290, 2⟩ =
      .ok ("totalSupply", ⟨canonicalBytes, 305, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · exact readStateName2Bytes_canonicalBytes
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "totalSupply" (by decide)

private theorem decodeStateTypeId2_canonicalBytes :
    decodeU32le ⟨canonicalBytes, 305, 2⟩ = .ok (0, ⟨canonicalBytes, 309, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeStateVisibility2_canonicalBytes :
    decodeVisibilityV1 ⟨canonicalBytes, 309, 2⟩ =
      .ok (.public_, ⟨canonicalBytes, 332, 2⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 309, 2⟩ .public_
    ⟨canonicalBytes, 332, 3⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · apply decodeCanonicalTagV1 309 330 3
      [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
      "Visibility.Public"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 330 332 3 (by rfl) (by decide)

private theorem decodeStateDecl2_canonicalBytes :
    decodeStateDeclV1 ⟨canonicalBytes, 271, 1⟩ =
      .ok (totalSupplyState, ⟨canonicalBytes, 332, 1⟩) := by
  refine decodeStateDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 271, 1⟩ totalSupplyState
    ⟨canonicalBytes, 332, 2⟩ (by decide) ?_
  apply decodeStateDeclBodyV1_eq_of_fields
  · exact expectStateDecl2_canonicalBytes
  · exact decodeStateId2_canonicalBytes
  · exact decodeStateName2_canonicalBytes
  · exact decodeStateTypeId2_canonicalBytes
  · exact decodeStateVisibility2_canonicalBytes

private theorem decodeLogicalState_canonicalBytes :
    decodeArray maxTableElements decodeStateDeclV1 ⟨canonicalBytes, 151, 1⟩ =
      .ok (#[reserve0State, reserve1State, totalSupplyState], ⟨canonicalBytes, 332, 1⟩) := by
  exact decodeArray_threeV1 maxTableElements decodeStateDeclV1
    ⟨canonicalBytes, 151, 1⟩ 155 reserve0State reserve1State totalSupplyState
    ⟨canonicalBytes, 213, 1⟩ ⟨canonicalBytes, 271, 1⟩ ⟨canonicalBytes, 332, 1⟩
    readStateCount_canonicalBytes
    decodeStateDecl0_canonicalBytes decodeStateDecl1_canonicalBytes
    decodeStateDecl2_canonicalBytes

private theorem decodeEvents_canonicalBytes :
    decodeArray maxTableElements decodeEventDeclV1 ⟨canonicalBytes, 332, 1⟩ =
      .ok (#[], ⟨canonicalBytes, 336, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 332 maxTableElements =
    .ok (0, 336)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

private theorem decodeErrors_canonicalBytes :
    decodeArray maxTableElements decodeErrorDeclV1 ⟨canonicalBytes, 336, 1⟩ =
      .ok (#[], ⟨canonicalBytes, 340, 1⟩) := by
  apply decodeArray_zeroV1
  change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 336 maxTableElements =
    .ok (0, 340)
  rw [readArrayCountAtV1_refinesSpine]
  rfl

/-! ### clear callable -/

private theorem expectClrI0Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 474, 4⟩ =
      .ok ((), ⟨canonicalBytes, 491, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 474 491 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectClrI0VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 492, 5⟩ =
      .ok ((), ⟨canonicalBytes, 506, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 492 506 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI0VID :
    decodeU32le ⟨canonicalBytes, 506, 5⟩ =
      .ok (0, ⟨canonicalBytes, 510, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI0TID :
    decodeU32le ⟨canonicalBytes, 510, 5⟩ =
      .ok (0, ⟨canonicalBytes, 514, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI0ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 492, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 514, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 492, 4⟩
    ⟨canonicalBytes, 506, 5⟩ ⟨canonicalBytes, 510, 5⟩
    ⟨canonicalBytes, 514, 5⟩ 0 0 (by decide)
  · exact expectClrI0VD
  · exact decodeClrI0VID
  · exact decodeClrI0TID

private theorem decodeClrI0ResMark :
    decodeU8 ⟨canonicalBytes, 491, 4⟩ =
      .ok (1, ⟨canonicalBytes, 492, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI0Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 491, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨canonicalBytes, 514, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 491, 4⟩
    ⟨canonicalBytes, 492, 4⟩
    ⟨canonicalBytes, 514, 4⟩
    { valueId := 0, typeId := 0 }
  · exact decodeClrI0ResMark
  · exact decodeClrI0ValueDef

private theorem decodeClrI0OpTag :
    decodeTag ⟨canonicalBytes, 514, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 528, 5⟩) := by
  apply decodeCanonicalTagV1 514 528 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI0OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 528, 5⟩ =
      .ok ((), ⟨canonicalBytes, 530, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI0LitType :
    decodeU32le ⟨canonicalBytes, 530, 5⟩ =
      .ok (0, ⟨canonicalBytes, 534, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI0LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 534, 5⟩ =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 546, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 534 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 546) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 534
      maxCanonicalProgramBytes = .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 546)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0, 0, 0, 0, 0, 0, 0, 0]
        534 maxCanonicalProgramBytes 8 538
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeClrI0Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 514, 4⟩ =
      .ok (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray),
        ⟨canonicalBytes, 546, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 514, 4⟩
    ⟨canonicalBytes, 528, 5⟩ ⟨canonicalBytes, 530, 5⟩
    ⟨canonicalBytes, 534, 5⟩ ⟨canonicalBytes, 546, 5⟩
    0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray) (by decide)
  · exact decodeClrI0OpTag
  · exact decodeClrI0OpFc
  · exact decodeClrI0LitType
  · exact decodeClrI0LitBytes

private theorem decodeClrI0Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 474, 3⟩ =
      .ok (valueInstruction 0 0 (.literal 0 zeroBytes), ⟨canonicalBytes, 546, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 474, 3⟩
    ⟨canonicalBytes, 491, 4⟩ ⟨canonicalBytes, 514, 4⟩ ⟨canonicalBytes, 546, 4⟩
    (some { valueId := 0, typeId := 0 }) (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray)) (by decide)
    expectClrI0Instr decodeClrI0Result decodeClrI0Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectClrI1Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 546, 4⟩ =
      .ok ((), ⟨canonicalBytes, 563, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 546 563 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI1ResMark :
    decodeU8 ⟨canonicalBytes, 563, 4⟩ =
      .ok (0, ⟨canonicalBytes, 564, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI1Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 563, 4⟩ =
      .ok (none, ⟨canonicalBytes, 564, 4⟩) := by
  apply decodeOption_noneV1
  exact decodeClrI1ResMark

private theorem decodeClrI1OpTag :
    decodeTag ⟨canonicalBytes, 564, 5⟩ =
      .ok ("Op.StateStore", ⟨canonicalBytes, 581, 5⟩) := by
  apply decodeCanonicalTagV1 564 581 5
    [79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101] "Op.StateStore"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI1OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 581, 5⟩ =
      .ok ((), ⟨canonicalBytes, 583, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI1StateId :
    decodeU32le ⟨canonicalBytes, 583, 5⟩ =
      .ok (0, ⟨canonicalBytes, 587, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI1Value :
    decodeU32le ⟨canonicalBytes, 587, 5⟩ =
      .ok (0, ⟨canonicalBytes, 591, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI1Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 564, 4⟩ =
      .ok (.stateStore 0 0, ⟨canonicalBytes, 591, 4⟩) := by
  apply decodeSemanticOpV1_stateStore ⟨canonicalBytes, 564, 4⟩
    ⟨canonicalBytes, 581, 5⟩ ⟨canonicalBytes, 583, 5⟩
    ⟨canonicalBytes, 587, 5⟩ ⟨canonicalBytes, 591, 5⟩
    0 0 (by decide)
  · exact decodeClrI1OpTag
  · exact decodeClrI1OpFc
  · exact decodeClrI1StateId
  · exact decodeClrI1Value

private theorem decodeClrI1Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 546, 3⟩ =
      .ok (voidInstruction (.stateStore 0 0), ⟨canonicalBytes, 591, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 546, 3⟩
    ⟨canonicalBytes, 563, 4⟩ ⟨canonicalBytes, 564, 4⟩ ⟨canonicalBytes, 591, 4⟩
    (none) (.stateStore 0 0) (by decide)
    expectClrI1Instr decodeClrI1Result decodeClrI1Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectClrI2Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 591, 4⟩ =
      .ok ((), ⟨canonicalBytes, 608, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 591 608 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectClrI2VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 609, 5⟩ =
      .ok ((), ⟨canonicalBytes, 623, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 609 623 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI2VID :
    decodeU32le ⟨canonicalBytes, 623, 5⟩ =
      .ok (1, ⟨canonicalBytes, 627, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI2TID :
    decodeU32le ⟨canonicalBytes, 627, 5⟩ =
      .ok (0, ⟨canonicalBytes, 631, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI2ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 609, 4⟩ =
      .ok ({ valueId := 1, typeId := 0 }, ⟨canonicalBytes, 631, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 609, 4⟩
    ⟨canonicalBytes, 623, 5⟩ ⟨canonicalBytes, 627, 5⟩
    ⟨canonicalBytes, 631, 5⟩ 1 0 (by decide)
  · exact expectClrI2VD
  · exact decodeClrI2VID
  · exact decodeClrI2TID

private theorem decodeClrI2ResMark :
    decodeU8 ⟨canonicalBytes, 608, 4⟩ =
      .ok (1, ⟨canonicalBytes, 609, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI2Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 608, 4⟩ =
      .ok (some { valueId := 1, typeId := 0 },
        ⟨canonicalBytes, 631, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 608, 4⟩
    ⟨canonicalBytes, 609, 4⟩
    ⟨canonicalBytes, 631, 4⟩
    { valueId := 1, typeId := 0 }
  · exact decodeClrI2ResMark
  · exact decodeClrI2ValueDef

private theorem decodeClrI2OpTag :
    decodeTag ⟨canonicalBytes, 631, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 645, 5⟩) := by
  apply decodeCanonicalTagV1 631 645 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI2OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 645, 5⟩ =
      .ok ((), ⟨canonicalBytes, 647, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI2LitType :
    decodeU32le ⟨canonicalBytes, 647, 5⟩ =
      .ok (0, ⟨canonicalBytes, 651, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI2LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 651, 5⟩ =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 663, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 651 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 663) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 651
      maxCanonicalProgramBytes = .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 663)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0, 0, 0, 0, 0, 0, 0, 0]
        651 maxCanonicalProgramBytes 8 655
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeClrI2Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 631, 4⟩ =
      .ok (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray),
        ⟨canonicalBytes, 663, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 631, 4⟩
    ⟨canonicalBytes, 645, 5⟩ ⟨canonicalBytes, 647, 5⟩
    ⟨canonicalBytes, 651, 5⟩ ⟨canonicalBytes, 663, 5⟩
    0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray) (by decide)
  · exact decodeClrI2OpTag
  · exact decodeClrI2OpFc
  · exact decodeClrI2LitType
  · exact decodeClrI2LitBytes

private theorem decodeClrI2Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 591, 3⟩ =
      .ok (valueInstruction 1 0 (.literal 0 zeroBytes), ⟨canonicalBytes, 663, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 591, 3⟩
    ⟨canonicalBytes, 608, 4⟩ ⟨canonicalBytes, 631, 4⟩ ⟨canonicalBytes, 663, 4⟩
    (some { valueId := 1, typeId := 0 }) (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray)) (by decide)
    expectClrI2Instr decodeClrI2Result decodeClrI2Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectClrI3Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 663, 4⟩ =
      .ok ((), ⟨canonicalBytes, 680, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 663 680 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI3ResMark :
    decodeU8 ⟨canonicalBytes, 680, 4⟩ =
      .ok (0, ⟨canonicalBytes, 681, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI3Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 680, 4⟩ =
      .ok (none, ⟨canonicalBytes, 681, 4⟩) := by
  apply decodeOption_noneV1
  exact decodeClrI3ResMark

private theorem decodeClrI3OpTag :
    decodeTag ⟨canonicalBytes, 681, 5⟩ =
      .ok ("Op.StateStore", ⟨canonicalBytes, 698, 5⟩) := by
  apply decodeCanonicalTagV1 681 698 5
    [79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101] "Op.StateStore"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI3OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 698, 5⟩ =
      .ok ((), ⟨canonicalBytes, 700, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI3StateId :
    decodeU32le ⟨canonicalBytes, 700, 5⟩ =
      .ok (1, ⟨canonicalBytes, 704, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI3Value :
    decodeU32le ⟨canonicalBytes, 704, 5⟩ =
      .ok (1, ⟨canonicalBytes, 708, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI3Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 681, 4⟩ =
      .ok (.stateStore 1 1, ⟨canonicalBytes, 708, 4⟩) := by
  apply decodeSemanticOpV1_stateStore ⟨canonicalBytes, 681, 4⟩
    ⟨canonicalBytes, 698, 5⟩ ⟨canonicalBytes, 700, 5⟩
    ⟨canonicalBytes, 704, 5⟩ ⟨canonicalBytes, 708, 5⟩
    1 1 (by decide)
  · exact decodeClrI3OpTag
  · exact decodeClrI3OpFc
  · exact decodeClrI3StateId
  · exact decodeClrI3Value

private theorem decodeClrI3Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 663, 3⟩ =
      .ok (voidInstruction (.stateStore 1 1), ⟨canonicalBytes, 708, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 663, 3⟩
    ⟨canonicalBytes, 680, 4⟩ ⟨canonicalBytes, 681, 4⟩ ⟨canonicalBytes, 708, 4⟩
    (none) (.stateStore 1 1) (by decide)
    expectClrI3Instr decodeClrI3Result decodeClrI3Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectClrI4Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 708, 4⟩ =
      .ok ((), ⟨canonicalBytes, 725, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 708 725 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectClrI4VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 726, 5⟩ =
      .ok ((), ⟨canonicalBytes, 740, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 726 740 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI4VID :
    decodeU32le ⟨canonicalBytes, 740, 5⟩ =
      .ok (2, ⟨canonicalBytes, 744, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI4TID :
    decodeU32le ⟨canonicalBytes, 744, 5⟩ =
      .ok (0, ⟨canonicalBytes, 748, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI4ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 726, 4⟩ =
      .ok ({ valueId := 2, typeId := 0 }, ⟨canonicalBytes, 748, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 726, 4⟩
    ⟨canonicalBytes, 740, 5⟩ ⟨canonicalBytes, 744, 5⟩
    ⟨canonicalBytes, 748, 5⟩ 2 0 (by decide)
  · exact expectClrI4VD
  · exact decodeClrI4VID
  · exact decodeClrI4TID

private theorem decodeClrI4ResMark :
    decodeU8 ⟨canonicalBytes, 725, 4⟩ =
      .ok (1, ⟨canonicalBytes, 726, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI4Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 725, 4⟩ =
      .ok (some { valueId := 2, typeId := 0 },
        ⟨canonicalBytes, 748, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 725, 4⟩
    ⟨canonicalBytes, 726, 4⟩
    ⟨canonicalBytes, 748, 4⟩
    { valueId := 2, typeId := 0 }
  · exact decodeClrI4ResMark
  · exact decodeClrI4ValueDef

private theorem decodeClrI4OpTag :
    decodeTag ⟨canonicalBytes, 748, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 762, 5⟩) := by
  apply decodeCanonicalTagV1 748 762 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI4OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 762, 5⟩ =
      .ok ((), ⟨canonicalBytes, 764, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI4LitType :
    decodeU32le ⟨canonicalBytes, 764, 5⟩ =
      .ok (0, ⟨canonicalBytes, 768, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI4LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 768, 5⟩ =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 780, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 768 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 780) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 768
      maxCanonicalProgramBytes = .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 780)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0, 0, 0, 0, 0, 0, 0, 0]
        768 maxCanonicalProgramBytes 8 772
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeClrI4Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 748, 4⟩ =
      .ok (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray),
        ⟨canonicalBytes, 780, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 748, 4⟩
    ⟨canonicalBytes, 762, 5⟩ ⟨canonicalBytes, 764, 5⟩
    ⟨canonicalBytes, 768, 5⟩ ⟨canonicalBytes, 780, 5⟩
    0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray) (by decide)
  · exact decodeClrI4OpTag
  · exact decodeClrI4OpFc
  · exact decodeClrI4LitType
  · exact decodeClrI4LitBytes

private theorem decodeClrI4Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 708, 3⟩ =
      .ok (valueInstruction 2 0 (.literal 0 zeroBytes), ⟨canonicalBytes, 780, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 708, 3⟩
    ⟨canonicalBytes, 725, 4⟩ ⟨canonicalBytes, 748, 4⟩ ⟨canonicalBytes, 780, 4⟩
    (some { valueId := 2, typeId := 0 }) (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray)) (by decide)
    expectClrI4Instr decodeClrI4Result decodeClrI4Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectClrI5Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 780, 4⟩ =
      .ok ((), ⟨canonicalBytes, 797, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 780 797 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI5ResMark :
    decodeU8 ⟨canonicalBytes, 797, 4⟩ =
      .ok (0, ⟨canonicalBytes, 798, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI5Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 797, 4⟩ =
      .ok (none, ⟨canonicalBytes, 798, 4⟩) := by
  apply decodeOption_noneV1
  exact decodeClrI5ResMark

private theorem decodeClrI5OpTag :
    decodeTag ⟨canonicalBytes, 798, 5⟩ =
      .ok ("Op.StateStore", ⟨canonicalBytes, 815, 5⟩) := by
  apply decodeCanonicalTagV1 798 815 5
    [79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101] "Op.StateStore"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI5OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 815, 5⟩ =
      .ok ((), ⟨canonicalBytes, 817, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI5StateId :
    decodeU32le ⟨canonicalBytes, 817, 5⟩ =
      .ok (2, ⟨canonicalBytes, 821, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI5Value :
    decodeU32le ⟨canonicalBytes, 821, 5⟩ =
      .ok (2, ⟨canonicalBytes, 825, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI5Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 798, 4⟩ =
      .ok (.stateStore 2 2, ⟨canonicalBytes, 825, 4⟩) := by
  apply decodeSemanticOpV1_stateStore ⟨canonicalBytes, 798, 4⟩
    ⟨canonicalBytes, 815, 5⟩ ⟨canonicalBytes, 817, 5⟩
    ⟨canonicalBytes, 821, 5⟩ ⟨canonicalBytes, 825, 5⟩
    2 2 (by decide)
  · exact decodeClrI5OpTag
  · exact decodeClrI5OpFc
  · exact decodeClrI5StateId
  · exact decodeClrI5Value

private theorem decodeClrI5Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 780, 3⟩ =
      .ok (voidInstruction (.stateStore 2 2), ⟨canonicalBytes, 825, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 780, 3⟩
    ⟨canonicalBytes, 797, 4⟩ ⟨canonicalBytes, 798, 4⟩ ⟨canonicalBytes, 825, 4⟩
    (none) (.stateStore 2 2) (by decide)
    expectClrI5Instr decodeClrI5Result decodeClrI5Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectClrI6Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 825, 4⟩ =
      .ok ((), ⟨canonicalBytes, 842, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 825 842 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectClrI6VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 843, 5⟩ =
      .ok ((), ⟨canonicalBytes, 857, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 843 857 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeClrI6VID :
    decodeU32le ⟨canonicalBytes, 857, 5⟩ =
      .ok (3, ⟨canonicalBytes, 861, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI6TID :
    decodeU32le ⟨canonicalBytes, 861, 5⟩ =
      .ok (0, ⟨canonicalBytes, 865, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI6ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 843, 4⟩ =
      .ok ({ valueId := 3, typeId := 0 }, ⟨canonicalBytes, 865, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 843, 4⟩
    ⟨canonicalBytes, 857, 5⟩ ⟨canonicalBytes, 861, 5⟩
    ⟨canonicalBytes, 865, 5⟩ 3 0 (by decide)
  · exact expectClrI6VD
  · exact decodeClrI6VID
  · exact decodeClrI6TID

private theorem decodeClrI6ResMark :
    decodeU8 ⟨canonicalBytes, 842, 4⟩ =
      .ok (1, ⟨canonicalBytes, 843, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrI6Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 842, 4⟩ =
      .ok (some { valueId := 3, typeId := 0 },
        ⟨canonicalBytes, 865, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 842, 4⟩
    ⟨canonicalBytes, 843, 4⟩
    ⟨canonicalBytes, 865, 4⟩
    { valueId := 3, typeId := 0 }
  · exact decodeClrI6ResMark
  · exact decodeClrI6ValueDef

private theorem decodeClrI6OpTag :
    decodeTag ⟨canonicalBytes, 865, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 881, 5⟩) := by
  apply decodeCanonicalTagV1 865 881 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrI6OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 881, 5⟩ =
      .ok ((), ⟨canonicalBytes, 883, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrI6StateId :
    decodeU32le ⟨canonicalBytes, 883, 5⟩ =
      .ok (2, ⟨canonicalBytes, 887, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrI6Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 865, 4⟩ =
      .ok (.stateLoad 2, ⟨canonicalBytes, 887, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 865, 4⟩
    ⟨canonicalBytes, 881, 5⟩ ⟨canonicalBytes, 883, 5⟩
    ⟨canonicalBytes, 887, 5⟩ 2 (by decide)
  · exact decodeClrI6OpTag
  · exact decodeClrI6OpFc
  · exact decodeClrI6StateId

private theorem decodeClrI6Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 825, 3⟩ =
      .ok (valueInstruction 3 0 (.stateLoad 2), ⟨canonicalBytes, 887, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 825, 3⟩
    ⟨canonicalBytes, 842, 4⟩ ⟨canonicalBytes, 865, 4⟩ ⟨canonicalBytes, 887, 4⟩
    (some { valueId := 3, typeId := 0 }) (.stateLoad 2) (by decide)
    expectClrI6Instr decodeClrI6Result decodeClrI6Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem decodeClrTermTag :
    decodeTag ⟨canonicalBytes, 887, 4⟩ =
      .ok ("Term.Return", ⟨canonicalBytes, 902, 4⟩) := by
  apply decodeCanonicalTagV1 887 902 4
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrTermFc :
    decodeFieldCount 1 ⟨canonicalBytes, 902, 4⟩ =
      .ok ((), ⟨canonicalBytes, 904, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrTermMark :
    decodeU8 ⟨canonicalBytes, 904, 4⟩ =
      .ok (1, ⟨canonicalBytes, 905, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrTermVal :
    decodeU32le ⟨canonicalBytes, 905, 4⟩ =
      .ok (3, ⟨canonicalBytes, 909, 4⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrReturn :
    decodeTerminatorV1 ⟨canonicalBytes, 887, 3⟩ =
      .ok (.return_ (some 3), ⟨canonicalBytes, 909, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 887, 3⟩
    ⟨canonicalBytes, 902, 4⟩ ⟨canonicalBytes, 904, 4⟩
    ⟨canonicalBytes, 909, 4⟩
    (some 3) (by decide)
  · exact decodeClrTermTag
  · exact decodeClrTermFc
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 904, 4⟩
      ⟨canonicalBytes, 905, 4⟩ ⟨canonicalBytes, 909, 4⟩ 3
    · exact decodeClrTermMark
    · exact decodeClrTermVal

private theorem decodeClrInstructions :
    decodeArray maxArrayElements decodeInstructionV1 ⟨canonicalBytes, 470, 3⟩ =
      .ok (clearBlock.instructions, ⟨canonicalBytes, 887, 3⟩) := by
  have h := decodeArray_sevenV1 maxArrayElements decodeInstructionV1
    ⟨canonicalBytes, 470, 3⟩ 474
    (valueInstruction 0 0 (.literal 0 zeroBytes))
    (voidInstruction (.stateStore 0 0))
    (valueInstruction 1 0 (.literal 0 zeroBytes))
    (voidInstruction (.stateStore 1 1))
    (valueInstruction 2 0 (.literal 0 zeroBytes))
    (voidInstruction (.stateStore 2 2))
    (valueInstruction 3 0 (.stateLoad 2))
    ⟨canonicalBytes, 546, 3⟩ ⟨canonicalBytes, 591, 3⟩ ⟨canonicalBytes, 663, 3⟩
    ⟨canonicalBytes, 708, 3⟩ ⟨canonicalBytes, 780, 3⟩ ⟨canonicalBytes, 825, 3⟩
    ⟨canonicalBytes, 887, 3⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 470
        maxArrayElements = .ok (7, 474)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeClrI0Instruction decodeClrI1Instruction decodeClrI2Instruction
    decodeClrI3Instruction decodeClrI4Instruction decodeClrI5Instruction
    decodeClrI6Instruction
  simpa [clearBlock, valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectClrBlock :
    expectTag "Block" 4 ⟨canonicalBytes, 451, 3⟩ =
      .ok ((), ⟨canonicalBytes, 462, 3⟩) := by
  apply expectTag_of_spine "Block" 4 451 462 3
    [66, 108, 111, 99, 107] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeClrBlockId :
    decodeU32le ⟨canonicalBytes, 462, 3⟩ = .ok (0, ⟨canonicalBytes, 466, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrBlock :
    decodeBlockV1 ⟨canonicalBytes, 451, 2⟩ =
      .ok (clearBlock, ⟨canonicalBytes, 909, 2⟩) := by
  apply decodeBlockV1_eq_of_fieldsV1 ⟨canonicalBytes, 451, 2⟩
    ⟨canonicalBytes, 462, 3⟩ ⟨canonicalBytes, 466, 3⟩
    ⟨canonicalBytes, 470, 3⟩ ⟨canonicalBytes, 887, 3⟩ ⟨canonicalBytes, 909, 3⟩
    0 #[] clearBlock.instructions (.return_ (some 3)) (by decide)
  · exact expectClrBlock
  · exact decodeClrBlockId
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 466
      maxArrayElements = .ok (0, 470)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeClrInstructions
  · exact decodeClrReturn

private theorem expectClrCallable :
    expectTag "Callable" 9 ⟨canonicalBytes, 344, 2⟩ =
      .ok ((), ⟨canonicalBytes, 358, 2⟩) := by
  apply expectTag_of_spine "Callable" 9 344 358 2
    [67, 97, 108, 108, 97, 98, 108, 101] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeClrId :
    decodeU32le ⟨canonicalBytes, 358, 2⟩ =
      .ok (0, ⟨canonicalBytes, 362, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrKindTag :
    decodeTag ⟨canonicalBytes, 362, 3⟩ =
      .ok ("Callable.Entry", ⟨canonicalBytes, 380, 3⟩) := by
  apply decodeCanonicalTagV1 362 380 3
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121] "Callable.Entry"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrKindFc :
    decodeFieldCount 0 ⟨canonicalBytes, 380, 3⟩ =
      .ok ((), ⟨canonicalBytes, 382, 3⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrKind :
    decodeCallableKindV1 ⟨canonicalBytes, 362, 2⟩ =
      .ok (.entry, ⟨canonicalBytes, 382, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 362, 2⟩ .entry
    ⟨canonicalBytes, 382, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_entry
  · exact decodeClrKindTag
  · exact decodeClrKindFc

private theorem decodeClrNameMark :
    decodeU8 ⟨canonicalBytes, 382, 2⟩ =
      .ok (1, ⟨canonicalBytes, 383, 2⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeClrNameStr :
    decodeString ⟨canonicalBytes, 383, 2⟩ =
      .ok ("clear", ⟨canonicalBytes, 392, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 383 maxStringBytes =
      .ok (ByteArray.mk [99, 108, 101, 97, 114].toArray, 392)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [99, 108, 101, 97, 114]
        383 maxStringBytes 5 387
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "clear" (by decide)

private theorem decodeClrName :
    decodeOption decodeString ⟨canonicalBytes, 382, 2⟩ =
      .ok (some "clear", ⟨canonicalBytes, 392, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 382, 2⟩
    ⟨canonicalBytes, 383, 2⟩ ⟨canonicalBytes, 392, 2⟩ "clear"
  · exact decodeClrNameMark
  · exact decodeClrNameStr

private theorem expectClrResult :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 396, 3⟩ =
      .ok ((), ⟨canonicalBytes, 416, 3⟩) := by
  apply expectTag_of_spine "CallableResult" 2 396 416 3
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeClrResultType :
    decodeU32le ⟨canonicalBytes, 416, 3⟩ =
      .ok (0, ⟨canonicalBytes, 420, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrVisTag :
    decodeTag ⟨canonicalBytes, 420, 4⟩ =
      .ok ("Visibility.Public", ⟨canonicalBytes, 441, 4⟩) := by
  apply decodeCanonicalTagV1 420 441 4
    [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
    "Visibility.Public"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeClrVisFc :
    decodeFieldCount 0 ⟨canonicalBytes, 441, 4⟩ =
      .ok ((), ⟨canonicalBytes, 443, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeClrVisibility :
    decodeVisibilityV1 ⟨canonicalBytes, 420, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 443, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 420, 3⟩ .public_
    ⟨canonicalBytes, 443, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · exact decodeClrVisTag
  · exact decodeClrVisFc

private theorem decodeClrResult :
    decodeCallableResultV1 ⟨canonicalBytes, 396, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨canonicalBytes, 443, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 396, 2⟩
    { typeId := 0, visibility := .public_ } ⟨canonicalBytes, 443, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectClrResult
  · exact decodeClrResultType
  · exact decodeClrVisibility

private theorem decodeClrEntryBlock :
    decodeU32le ⟨canonicalBytes, 443, 2⟩ =
      .ok (0, ⟨canonicalBytes, 447, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeClrCallable :
    decodeCallableV1 ⟨canonicalBytes, 344, 1⟩ =
      .ok (clearCallable, ⟨canonicalBytes, 914, 1⟩) := by
  apply decodeCallableV1_singleBlockV1 ⟨canonicalBytes, 344, 1⟩
    ⟨canonicalBytes, 358, 2⟩ ⟨canonicalBytes, 362, 2⟩
    ⟨canonicalBytes, 382, 2⟩ ⟨canonicalBytes, 392, 2⟩
    ⟨canonicalBytes, 443, 2⟩ ⟨canonicalBytes, 447, 2⟩
    ⟨canonicalBytes, 909, 2⟩ ⟨canonicalBytes, 914, 2⟩
    396 451 913
    0 0 .entry (some "clear")
    { typeId := 0, visibility := .public_ } clearBlock
    none (by decide)
  · exact expectClrCallable
  · exact decodeClrId
  · exact decodeClrKind
  · exact decodeClrName
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 392
      maxArrayElements = .ok (0, 396)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeClrResult
  · exact decodeClrEntryBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 447
      maxArrayElements = .ok (1, 451)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeClrBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 909
      maxArrayElements = .ok (0, 913)
    rw [readArrayCountAtV1_refinesSpine]; rfl

  · apply decodeOption_noneV1
    apply decodeCanonicalU8V1; rfl


/-! ### getTotalSupply callable -/

private theorem expectGetI0Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1052, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1069, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1052 1069 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectGetI0VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1070, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1084, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1070 1084 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeGetI0VID :
    decodeU32le ⟨canonicalBytes, 1084, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1088, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetI0TID :
    decodeU32le ⟨canonicalBytes, 1088, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1092, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetI0ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1070, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 1092, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1070, 4⟩
    ⟨canonicalBytes, 1084, 5⟩ ⟨canonicalBytes, 1088, 5⟩
    ⟨canonicalBytes, 1092, 5⟩ 0 0 (by decide)
  · exact expectGetI0VD
  · exact decodeGetI0VID
  · exact decodeGetI0TID

private theorem decodeGetI0ResMark :
    decodeU8 ⟨canonicalBytes, 1069, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1070, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeGetI0Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1069, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨canonicalBytes, 1092, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1069, 4⟩
    ⟨canonicalBytes, 1070, 4⟩
    ⟨canonicalBytes, 1092, 4⟩
    { valueId := 0, typeId := 0 }
  · exact decodeGetI0ResMark
  · exact decodeGetI0ValueDef

private theorem decodeGetI0OpTag :
    decodeTag ⟨canonicalBytes, 1092, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 1108, 5⟩) := by
  apply decodeCanonicalTagV1 1092 1108 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetI0OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 1108, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1110, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetI0StateId :
    decodeU32le ⟨canonicalBytes, 1110, 5⟩ =
      .ok (2, ⟨canonicalBytes, 1114, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetI0Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1092, 4⟩ =
      .ok (.stateLoad 2, ⟨canonicalBytes, 1114, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 1092, 4⟩
    ⟨canonicalBytes, 1108, 5⟩ ⟨canonicalBytes, 1110, 5⟩
    ⟨canonicalBytes, 1114, 5⟩ 2 (by decide)
  · exact decodeGetI0OpTag
  · exact decodeGetI0OpFc
  · exact decodeGetI0StateId

private theorem decodeGetI0Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1052, 3⟩ =
      .ok (valueInstruction 0 0 (.stateLoad 2), ⟨canonicalBytes, 1114, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1052, 3⟩
    ⟨canonicalBytes, 1069, 4⟩ ⟨canonicalBytes, 1092, 4⟩ ⟨canonicalBytes, 1114, 4⟩
    (some { valueId := 0, typeId := 0 }) (.stateLoad 2) (by decide)
    expectGetI0Instr decodeGetI0Result decodeGetI0Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem decodeGetTermTag :
    decodeTag ⟨canonicalBytes, 1114, 4⟩ =
      .ok ("Term.Return", ⟨canonicalBytes, 1129, 4⟩) := by
  apply decodeCanonicalTagV1 1114 1129 4
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetTermFc :
    decodeFieldCount 1 ⟨canonicalBytes, 1129, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1131, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetTermMark :
    decodeU8 ⟨canonicalBytes, 1131, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1132, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeGetTermVal :
    decodeU32le ⟨canonicalBytes, 1132, 4⟩ =
      .ok (0, ⟨canonicalBytes, 1136, 4⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetReturn :
    decodeTerminatorV1 ⟨canonicalBytes, 1114, 3⟩ =
      .ok (.return_ (some 0), ⟨canonicalBytes, 1136, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 1114, 3⟩
    ⟨canonicalBytes, 1129, 4⟩ ⟨canonicalBytes, 1131, 4⟩
    ⟨canonicalBytes, 1136, 4⟩
    (some 0) (by decide)
  · exact decodeGetTermTag
  · exact decodeGetTermFc
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 1131, 4⟩
      ⟨canonicalBytes, 1132, 4⟩ ⟨canonicalBytes, 1136, 4⟩ 0
    · exact decodeGetTermMark
    · exact decodeGetTermVal

private theorem decodeGetInstructions :
    decodeArray maxArrayElements decodeInstructionV1 ⟨canonicalBytes, 1048, 3⟩ =
      .ok (getBlock.instructions, ⟨canonicalBytes, 1114, 3⟩) := by
  have h := decodeArray_oneV1 maxArrayElements decodeInstructionV1
    ⟨canonicalBytes, 1048, 3⟩ 1052
    (valueInstruction 0 0 (.stateLoad 2))
    ⟨canonicalBytes, 1114, 3⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1048
        maxArrayElements = .ok (1, 1052)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeGetI0Instruction
  simpa [getBlock, valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectGetBlock :
    expectTag "Block" 4 ⟨canonicalBytes, 1029, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1040, 3⟩) := by
  apply expectTag_of_spine "Block" 4 1029 1040 3
    [66, 108, 111, 99, 107] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeGetBlockId :
    decodeU32le ⟨canonicalBytes, 1040, 3⟩ = .ok (0, ⟨canonicalBytes, 1044, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetBlock :
    decodeBlockV1 ⟨canonicalBytes, 1029, 2⟩ =
      .ok (getBlock, ⟨canonicalBytes, 1136, 2⟩) := by
  apply decodeBlockV1_eq_of_fieldsV1 ⟨canonicalBytes, 1029, 2⟩
    ⟨canonicalBytes, 1040, 3⟩ ⟨canonicalBytes, 1044, 3⟩
    ⟨canonicalBytes, 1048, 3⟩ ⟨canonicalBytes, 1114, 3⟩ ⟨canonicalBytes, 1136, 3⟩
    0 #[] getBlock.instructions (.return_ (some 0)) (by decide)
  · exact expectGetBlock
  · exact decodeGetBlockId
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1044
      maxArrayElements = .ok (0, 1048)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeGetInstructions
  · exact decodeGetReturn

private theorem expectGetCallable :
    expectTag "Callable" 9 ⟨canonicalBytes, 914, 2⟩ =
      .ok ((), ⟨canonicalBytes, 928, 2⟩) := by
  apply expectTag_of_spine "Callable" 9 914 928 2
    [67, 97, 108, 108, 97, 98, 108, 101] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeGetId :
    decodeU32le ⟨canonicalBytes, 928, 2⟩ =
      .ok (1, ⟨canonicalBytes, 932, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetKindTag :
    decodeTag ⟨canonicalBytes, 932, 3⟩ =
      .ok ("Callable.View", ⟨canonicalBytes, 949, 3⟩) := by
  apply decodeCanonicalTagV1 932 949 3
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119] "Callable.View"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetKindFc :
    decodeFieldCount 0 ⟨canonicalBytes, 949, 3⟩ =
      .ok ((), ⟨canonicalBytes, 951, 3⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetKind :
    decodeCallableKindV1 ⟨canonicalBytes, 932, 2⟩ =
      .ok (.view, ⟨canonicalBytes, 951, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 932, 2⟩ .view
    ⟨canonicalBytes, 951, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_view
  · exact decodeGetKindTag
  · exact decodeGetKindFc

private theorem decodeGetNameMark :
    decodeU8 ⟨canonicalBytes, 951, 2⟩ =
      .ok (1, ⟨canonicalBytes, 952, 2⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeGetNameStr :
    decodeString ⟨canonicalBytes, 952, 2⟩ =
      .ok ("getTotalSupply", ⟨canonicalBytes, 970, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 952 maxStringBytes =
      .ok (ByteArray.mk [103, 101, 116, 84, 111, 116, 97, 108, 83, 117, 112, 112, 108, 121].toArray, 970)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [103, 101, 116, 84, 111, 116, 97, 108, 83, 117, 112, 112, 108, 121]
        952 maxStringBytes 14 956
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "getTotalSupply" (by decide)

private theorem decodeGetName :
    decodeOption decodeString ⟨canonicalBytes, 951, 2⟩ =
      .ok (some "getTotalSupply", ⟨canonicalBytes, 970, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 951, 2⟩
    ⟨canonicalBytes, 952, 2⟩ ⟨canonicalBytes, 970, 2⟩ "getTotalSupply"
  · exact decodeGetNameMark
  · exact decodeGetNameStr

private theorem expectGetResult :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 974, 3⟩ =
      .ok ((), ⟨canonicalBytes, 994, 3⟩) := by
  apply expectTag_of_spine "CallableResult" 2 974 994 3
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeGetResultType :
    decodeU32le ⟨canonicalBytes, 994, 3⟩ =
      .ok (0, ⟨canonicalBytes, 998, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetVisTag :
    decodeTag ⟨canonicalBytes, 998, 4⟩ =
      .ok ("Visibility.Public", ⟨canonicalBytes, 1019, 4⟩) := by
  apply decodeCanonicalTagV1 998 1019 4
    [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
    "Visibility.Public"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeGetVisFc :
    decodeFieldCount 0 ⟨canonicalBytes, 1019, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1021, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeGetVisibility :
    decodeVisibilityV1 ⟨canonicalBytes, 998, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 1021, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 998, 3⟩ .public_
    ⟨canonicalBytes, 1021, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · exact decodeGetVisTag
  · exact decodeGetVisFc

private theorem decodeGetResult :
    decodeCallableResultV1 ⟨canonicalBytes, 974, 2⟩ =
      .ok ({ typeId := 0, visibility := .public_ }, ⟨canonicalBytes, 1021, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 974, 2⟩
    { typeId := 0, visibility := .public_ } ⟨canonicalBytes, 1021, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectGetResult
  · exact decodeGetResultType
  · exact decodeGetVisibility

private theorem decodeGetEntryBlock :
    decodeU32le ⟨canonicalBytes, 1021, 2⟩ =
      .ok (0, ⟨canonicalBytes, 1025, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeGetCallable :
    decodeCallableV1 ⟨canonicalBytes, 914, 1⟩ =
      .ok (getCallable, ⟨canonicalBytes, 1141, 1⟩) := by
  apply decodeCallableV1_singleBlockV1 ⟨canonicalBytes, 914, 1⟩
    ⟨canonicalBytes, 928, 2⟩ ⟨canonicalBytes, 932, 2⟩
    ⟨canonicalBytes, 951, 2⟩ ⟨canonicalBytes, 970, 2⟩
    ⟨canonicalBytes, 1021, 2⟩ ⟨canonicalBytes, 1025, 2⟩
    ⟨canonicalBytes, 1136, 2⟩ ⟨canonicalBytes, 1141, 2⟩
    974 1029 1140
    1 0 .view (some "getTotalSupply")
    { typeId := 0, visibility := .public_ } getBlock
    none (by decide)
  · exact expectGetCallable
  · exact decodeGetId
  · exact decodeGetKind
  · exact decodeGetName
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 970
      maxArrayElements = .ok (0, 974)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeGetResult
  · exact decodeGetEntryBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1025
      maxArrayElements = .ok (1, 1029)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeGetBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1136
      maxArrayElements = .ok (0, 1140)
    rw [readArrayCountAtV1_refinesSpine]; rfl

  · apply decodeOption_noneV1
    apply decodeCanonicalU8V1; rfl


/-! ### emptyPool callable -/

private theorem expectEpI0Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1279, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1296, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1279 1296 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI0VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1297, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1311, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1297 1311 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI0VID :
    decodeU32le ⟨canonicalBytes, 1311, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1315, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI0TID :
    decodeU32le ⟨canonicalBytes, 1315, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1319, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI0ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1297, 4⟩ =
      .ok ({ valueId := 0, typeId := 0 }, ⟨canonicalBytes, 1319, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1297, 4⟩
    ⟨canonicalBytes, 1311, 5⟩ ⟨canonicalBytes, 1315, 5⟩
    ⟨canonicalBytes, 1319, 5⟩ 0 0 (by decide)
  · exact expectEpI0VD
  · exact decodeEpI0VID
  · exact decodeEpI0TID

private theorem decodeEpI0ResMark :
    decodeU8 ⟨canonicalBytes, 1296, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1297, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI0Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1296, 4⟩ =
      .ok (some { valueId := 0, typeId := 0 },
        ⟨canonicalBytes, 1319, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1296, 4⟩
    ⟨canonicalBytes, 1297, 4⟩
    ⟨canonicalBytes, 1319, 4⟩
    { valueId := 0, typeId := 0 }
  · exact decodeEpI0ResMark
  · exact decodeEpI0ValueDef

private theorem decodeEpI0OpTag :
    decodeTag ⟨canonicalBytes, 1319, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 1335, 5⟩) := by
  apply decodeCanonicalTagV1 1319 1335 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI0OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 1335, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1337, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI0StateId :
    decodeU32le ⟨canonicalBytes, 1337, 5⟩ =
      .ok (2, ⟨canonicalBytes, 1341, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI0Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1319, 4⟩ =
      .ok (.stateLoad 2, ⟨canonicalBytes, 1341, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 1319, 4⟩
    ⟨canonicalBytes, 1335, 5⟩ ⟨canonicalBytes, 1337, 5⟩
    ⟨canonicalBytes, 1341, 5⟩ 2 (by decide)
  · exact decodeEpI0OpTag
  · exact decodeEpI0OpFc
  · exact decodeEpI0StateId

private theorem decodeEpI0Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1279, 3⟩ =
      .ok (valueInstruction 0 0 (.stateLoad 2), ⟨canonicalBytes, 1341, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1279, 3⟩
    ⟨canonicalBytes, 1296, 4⟩ ⟨canonicalBytes, 1319, 4⟩ ⟨canonicalBytes, 1341, 4⟩
    (some { valueId := 0, typeId := 0 }) (.stateLoad 2) (by decide)
    expectEpI0Instr decodeEpI0Result decodeEpI0Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI1Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1341, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1358, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1341 1358 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI1VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1359, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1373, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1359 1373 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI1VID :
    decodeU32le ⟨canonicalBytes, 1373, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1377, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI1TID :
    decodeU32le ⟨canonicalBytes, 1377, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1381, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI1ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1359, 4⟩ =
      .ok ({ valueId := 1, typeId := 0 }, ⟨canonicalBytes, 1381, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1359, 4⟩
    ⟨canonicalBytes, 1373, 5⟩ ⟨canonicalBytes, 1377, 5⟩
    ⟨canonicalBytes, 1381, 5⟩ 1 0 (by decide)
  · exact expectEpI1VD
  · exact decodeEpI1VID
  · exact decodeEpI1TID

private theorem decodeEpI1ResMark :
    decodeU8 ⟨canonicalBytes, 1358, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1359, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI1Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1358, 4⟩ =
      .ok (some { valueId := 1, typeId := 0 },
        ⟨canonicalBytes, 1381, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1358, 4⟩
    ⟨canonicalBytes, 1359, 4⟩
    ⟨canonicalBytes, 1381, 4⟩
    { valueId := 1, typeId := 0 }
  · exact decodeEpI1ResMark
  · exact decodeEpI1ValueDef

private theorem decodeEpI1OpTag :
    decodeTag ⟨canonicalBytes, 1381, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 1395, 5⟩) := by
  apply decodeCanonicalTagV1 1381 1395 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI1OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 1395, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1397, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI1LitType :
    decodeU32le ⟨canonicalBytes, 1397, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1401, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI1LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 1401, 5⟩ =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 1413, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 1401 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1413) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1401
      maxCanonicalProgramBytes = .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1413)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0, 0, 0, 0, 0, 0, 0, 0]
        1401 maxCanonicalProgramBytes 8 1405
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeEpI1Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1381, 4⟩ =
      .ok (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray),
        ⟨canonicalBytes, 1413, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 1381, 4⟩
    ⟨canonicalBytes, 1395, 5⟩ ⟨canonicalBytes, 1397, 5⟩
    ⟨canonicalBytes, 1401, 5⟩ ⟨canonicalBytes, 1413, 5⟩
    0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray) (by decide)
  · exact decodeEpI1OpTag
  · exact decodeEpI1OpFc
  · exact decodeEpI1LitType
  · exact decodeEpI1LitBytes

private theorem decodeEpI1Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1341, 3⟩ =
      .ok (valueInstruction 1 0 (.literal 0 zeroBytes), ⟨canonicalBytes, 1413, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1341, 3⟩
    ⟨canonicalBytes, 1358, 4⟩ ⟨canonicalBytes, 1381, 4⟩ ⟨canonicalBytes, 1413, 4⟩
    (some { valueId := 1, typeId := 0 }) (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray)) (by decide)
    expectEpI1Instr decodeEpI1Result decodeEpI1Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI2Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1413, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1430, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1413 1430 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI2VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1431, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1445, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1431 1445 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI2VID :
    decodeU32le ⟨canonicalBytes, 1445, 5⟩ =
      .ok (2, ⟨canonicalBytes, 1449, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI2TID :
    decodeU32le ⟨canonicalBytes, 1449, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1453, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI2ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1431, 4⟩ =
      .ok ({ valueId := 2, typeId := 1 }, ⟨canonicalBytes, 1453, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1431, 4⟩
    ⟨canonicalBytes, 1445, 5⟩ ⟨canonicalBytes, 1449, 5⟩
    ⟨canonicalBytes, 1453, 5⟩ 2 1 (by decide)
  · exact expectEpI2VD
  · exact decodeEpI2VID
  · exact decodeEpI2TID

private theorem decodeEpI2ResMark :
    decodeU8 ⟨canonicalBytes, 1430, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1431, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI2Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1430, 4⟩ =
      .ok (some { valueId := 2, typeId := 1 },
        ⟨canonicalBytes, 1453, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1430, 4⟩
    ⟨canonicalBytes, 1431, 4⟩
    ⟨canonicalBytes, 1453, 4⟩
    { valueId := 2, typeId := 1 }
  · exact decodeEpI2ResMark
  · exact decodeEpI2ValueDef

private theorem decodeEpI2OpTag :
    decodeTag ⟨canonicalBytes, 1453, 5⟩ =
      .ok ("Op.Binary", ⟨canonicalBytes, 1466, 5⟩) := by
  apply decodeCanonicalTagV1 1453 1466 5
    [79, 112, 46, 66, 105, 110, 97, 114, 121] "Op.Binary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI2OpFc :
    decodeFieldCount 3 ⟨canonicalBytes, 1466, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1468, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI2BinOp :
    decodeBinaryOpV1 ⟨canonicalBytes, 1468, 5⟩ =
      .ok (.eq, ⟨canonicalBytes, 1483, 5⟩) := by
  apply decodeBinaryOpV1_eqOp ⟨canonicalBytes, 1468, 5⟩
    ⟨canonicalBytes, 1481, 6⟩ ⟨canonicalBytes, 1483, 6⟩
    (by decide)
  · apply decodeCanonicalTagV1 1468 1481 6
      [66, 105, 110, 97, 114, 121, 46, 69, 113] "Binary.Eq"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 1481 1483 6 (by rfl) (by decide)

private theorem decodeEpI2Lhs :
    decodeU32le ⟨canonicalBytes, 1483, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1487, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI2Rhs :
    decodeU32le ⟨canonicalBytes, 1487, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1491, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI2Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1453, 4⟩ =
      .ok (.binary .eq 0 1,
        ⟨canonicalBytes, 1491, 4⟩) := by
  apply decodeSemanticOpV1_binary ⟨canonicalBytes, 1453, 4⟩
    ⟨canonicalBytes, 1466, 5⟩ ⟨canonicalBytes, 1468, 5⟩
    ⟨canonicalBytes, 1483, 5⟩ ⟨canonicalBytes, 1487, 5⟩
    ⟨canonicalBytes, 1491, 5⟩
    .eq 0 1 (by decide)
  · exact decodeEpI2OpTag
  · exact decodeEpI2OpFc
  · exact decodeEpI2BinOp
  · exact decodeEpI2Lhs
  · exact decodeEpI2Rhs

private theorem decodeEpI2Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1413, 3⟩ =
      .ok (valueInstruction 2 1 (.binary .eq 0 1), ⟨canonicalBytes, 1491, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1413, 3⟩
    ⟨canonicalBytes, 1430, 4⟩ ⟨canonicalBytes, 1453, 4⟩ ⟨canonicalBytes, 1491, 4⟩
    (some { valueId := 2, typeId := 1 }) (.binary .eq 0 1) (by decide)
    expectEpI2Instr decodeEpI2Result decodeEpI2Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI3Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1491, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1508, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1491 1508 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI3VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1509, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1523, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1509 1523 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI3VID :
    decodeU32le ⟨canonicalBytes, 1523, 5⟩ =
      .ok (3, ⟨canonicalBytes, 1527, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI3TID :
    decodeU32le ⟨canonicalBytes, 1527, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1531, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI3ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1509, 4⟩ =
      .ok ({ valueId := 3, typeId := 1 }, ⟨canonicalBytes, 1531, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1509, 4⟩
    ⟨canonicalBytes, 1523, 5⟩ ⟨canonicalBytes, 1527, 5⟩
    ⟨canonicalBytes, 1531, 5⟩ 3 1 (by decide)
  · exact expectEpI3VD
  · exact decodeEpI3VID
  · exact decodeEpI3TID

private theorem decodeEpI3ResMark :
    decodeU8 ⟨canonicalBytes, 1508, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1509, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI3Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1508, 4⟩ =
      .ok (some { valueId := 3, typeId := 1 },
        ⟨canonicalBytes, 1531, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1508, 4⟩
    ⟨canonicalBytes, 1509, 4⟩
    ⟨canonicalBytes, 1531, 4⟩
    { valueId := 3, typeId := 1 }
  · exact decodeEpI3ResMark
  · exact decodeEpI3ValueDef

private theorem decodeEpI3OpTag :
    decodeTag ⟨canonicalBytes, 1531, 5⟩ =
      .ok ("Op.Unary", ⟨canonicalBytes, 1543, 5⟩) := by
  apply decodeCanonicalTagV1 1531 1543 5
    [79, 112, 46, 85, 110, 97, 114, 121] "Op.Unary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI3OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 1543, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1545, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI3UnOp :
    decodeUnaryOpV1 ⟨canonicalBytes, 1545, 5⟩ =
      .ok (.not, ⟨canonicalBytes, 1560, 5⟩) := by
  apply decodeUnaryOpV1_notOp ⟨canonicalBytes, 1545, 5⟩
    ⟨canonicalBytes, 1558, 6⟩ ⟨canonicalBytes, 1560, 6⟩
    (by decide)
  · apply decodeCanonicalTagV1 1545 1558 6
      [85, 110, 97, 114, 121, 46, 78, 111, 116] "Unary.Not"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 1558 1560 6 (by rfl) (by decide)

private theorem decodeEpI3Operand :
    decodeU32le ⟨canonicalBytes, 1560, 5⟩ =
      .ok (2, ⟨canonicalBytes, 1564, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI3Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1531, 4⟩ =
      .ok (.unary .not 2, ⟨canonicalBytes, 1564, 4⟩) := by
  apply decodeSemanticOpV1_unary ⟨canonicalBytes, 1531, 4⟩
    ⟨canonicalBytes, 1543, 5⟩ ⟨canonicalBytes, 1545, 5⟩
    ⟨canonicalBytes, 1560, 5⟩ ⟨canonicalBytes, 1564, 5⟩
    .not 2 (by decide)
  · exact decodeEpI3OpTag
  · exact decodeEpI3OpFc
  · exact decodeEpI3UnOp
  · exact decodeEpI3Operand

private theorem decodeEpI3Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1491, 3⟩ =
      .ok (valueInstruction 3 1 (.unary .not 2), ⟨canonicalBytes, 1564, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1491, 3⟩
    ⟨canonicalBytes, 1508, 4⟩ ⟨canonicalBytes, 1531, 4⟩ ⟨canonicalBytes, 1564, 4⟩
    (some { valueId := 3, typeId := 1 }) (.unary .not 2) (by decide)
    expectEpI3Instr decodeEpI3Result decodeEpI3Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI4Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1564, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1581, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1564 1581 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI4VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1582, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1596, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1582 1596 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI4VID :
    decodeU32le ⟨canonicalBytes, 1596, 5⟩ =
      .ok (4, ⟨canonicalBytes, 1600, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI4TID :
    decodeU32le ⟨canonicalBytes, 1600, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1604, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI4ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1582, 4⟩ =
      .ok ({ valueId := 4, typeId := 0 }, ⟨canonicalBytes, 1604, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1582, 4⟩
    ⟨canonicalBytes, 1596, 5⟩ ⟨canonicalBytes, 1600, 5⟩
    ⟨canonicalBytes, 1604, 5⟩ 4 0 (by decide)
  · exact expectEpI4VD
  · exact decodeEpI4VID
  · exact decodeEpI4TID

private theorem decodeEpI4ResMark :
    decodeU8 ⟨canonicalBytes, 1581, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1582, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI4Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1581, 4⟩ =
      .ok (some { valueId := 4, typeId := 0 },
        ⟨canonicalBytes, 1604, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1581, 4⟩
    ⟨canonicalBytes, 1582, 4⟩
    ⟨canonicalBytes, 1604, 4⟩
    { valueId := 4, typeId := 0 }
  · exact decodeEpI4ResMark
  · exact decodeEpI4ValueDef

private theorem decodeEpI4OpTag :
    decodeTag ⟨canonicalBytes, 1604, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 1620, 5⟩) := by
  apply decodeCanonicalTagV1 1604 1620 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI4OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 1620, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1622, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI4StateId :
    decodeU32le ⟨canonicalBytes, 1622, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1626, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI4Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1604, 4⟩ =
      .ok (.stateLoad 0, ⟨canonicalBytes, 1626, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 1604, 4⟩
    ⟨canonicalBytes, 1620, 5⟩ ⟨canonicalBytes, 1622, 5⟩
    ⟨canonicalBytes, 1626, 5⟩ 0 (by decide)
  · exact decodeEpI4OpTag
  · exact decodeEpI4OpFc
  · exact decodeEpI4StateId

private theorem decodeEpI4Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1564, 3⟩ =
      .ok (valueInstruction 4 0 (.stateLoad 0), ⟨canonicalBytes, 1626, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1564, 3⟩
    ⟨canonicalBytes, 1581, 4⟩ ⟨canonicalBytes, 1604, 4⟩ ⟨canonicalBytes, 1626, 4⟩
    (some { valueId := 4, typeId := 0 }) (.stateLoad 0) (by decide)
    expectEpI4Instr decodeEpI4Result decodeEpI4Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI5Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1626, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1643, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1626 1643 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI5VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1644, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1658, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1644 1658 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI5VID :
    decodeU32le ⟨canonicalBytes, 1658, 5⟩ =
      .ok (5, ⟨canonicalBytes, 1662, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI5TID :
    decodeU32le ⟨canonicalBytes, 1662, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1666, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI5ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1644, 4⟩ =
      .ok ({ valueId := 5, typeId := 0 }, ⟨canonicalBytes, 1666, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1644, 4⟩
    ⟨canonicalBytes, 1658, 5⟩ ⟨canonicalBytes, 1662, 5⟩
    ⟨canonicalBytes, 1666, 5⟩ 5 0 (by decide)
  · exact expectEpI5VD
  · exact decodeEpI5VID
  · exact decodeEpI5TID

private theorem decodeEpI5ResMark :
    decodeU8 ⟨canonicalBytes, 1643, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1644, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI5Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1643, 4⟩ =
      .ok (some { valueId := 5, typeId := 0 },
        ⟨canonicalBytes, 1666, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1643, 4⟩
    ⟨canonicalBytes, 1644, 4⟩
    ⟨canonicalBytes, 1666, 4⟩
    { valueId := 5, typeId := 0 }
  · exact decodeEpI5ResMark
  · exact decodeEpI5ValueDef

private theorem decodeEpI5OpTag :
    decodeTag ⟨canonicalBytes, 1666, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 1680, 5⟩) := by
  apply decodeCanonicalTagV1 1666 1680 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI5OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 1680, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1682, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI5LitType :
    decodeU32le ⟨canonicalBytes, 1682, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1686, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI5LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 1686, 5⟩ =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 1698, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 1686 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1698) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1686
      maxCanonicalProgramBytes = .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1698)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0, 0, 0, 0, 0, 0, 0, 0]
        1686 maxCanonicalProgramBytes 8 1690
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeEpI5Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1666, 4⟩ =
      .ok (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray),
        ⟨canonicalBytes, 1698, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 1666, 4⟩
    ⟨canonicalBytes, 1680, 5⟩ ⟨canonicalBytes, 1682, 5⟩
    ⟨canonicalBytes, 1686, 5⟩ ⟨canonicalBytes, 1698, 5⟩
    0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray) (by decide)
  · exact decodeEpI5OpTag
  · exact decodeEpI5OpFc
  · exact decodeEpI5LitType
  · exact decodeEpI5LitBytes

private theorem decodeEpI5Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1626, 3⟩ =
      .ok (valueInstruction 5 0 (.literal 0 zeroBytes), ⟨canonicalBytes, 1698, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1626, 3⟩
    ⟨canonicalBytes, 1643, 4⟩ ⟨canonicalBytes, 1666, 4⟩ ⟨canonicalBytes, 1698, 4⟩
    (some { valueId := 5, typeId := 0 }) (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray)) (by decide)
    expectEpI5Instr decodeEpI5Result decodeEpI5Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI6Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1698, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1715, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1698 1715 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI6VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1716, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1730, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1716 1730 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI6VID :
    decodeU32le ⟨canonicalBytes, 1730, 5⟩ =
      .ok (6, ⟨canonicalBytes, 1734, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI6TID :
    decodeU32le ⟨canonicalBytes, 1734, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1738, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI6ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1716, 4⟩ =
      .ok ({ valueId := 6, typeId := 1 }, ⟨canonicalBytes, 1738, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1716, 4⟩
    ⟨canonicalBytes, 1730, 5⟩ ⟨canonicalBytes, 1734, 5⟩
    ⟨canonicalBytes, 1738, 5⟩ 6 1 (by decide)
  · exact expectEpI6VD
  · exact decodeEpI6VID
  · exact decodeEpI6TID

private theorem decodeEpI6ResMark :
    decodeU8 ⟨canonicalBytes, 1715, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1716, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI6Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1715, 4⟩ =
      .ok (some { valueId := 6, typeId := 1 },
        ⟨canonicalBytes, 1738, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1715, 4⟩
    ⟨canonicalBytes, 1716, 4⟩
    ⟨canonicalBytes, 1738, 4⟩
    { valueId := 6, typeId := 1 }
  · exact decodeEpI6ResMark
  · exact decodeEpI6ValueDef

private theorem decodeEpI6OpTag :
    decodeTag ⟨canonicalBytes, 1738, 5⟩ =
      .ok ("Op.Binary", ⟨canonicalBytes, 1751, 5⟩) := by
  apply decodeCanonicalTagV1 1738 1751 5
    [79, 112, 46, 66, 105, 110, 97, 114, 121] "Op.Binary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI6OpFc :
    decodeFieldCount 3 ⟨canonicalBytes, 1751, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1753, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI6BinOp :
    decodeBinaryOpV1 ⟨canonicalBytes, 1753, 5⟩ =
      .ok (.eq, ⟨canonicalBytes, 1768, 5⟩) := by
  apply decodeBinaryOpV1_eqOp ⟨canonicalBytes, 1753, 5⟩
    ⟨canonicalBytes, 1766, 6⟩ ⟨canonicalBytes, 1768, 6⟩
    (by decide)
  · apply decodeCanonicalTagV1 1753 1766 6
      [66, 105, 110, 97, 114, 121, 46, 69, 113] "Binary.Eq"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 1766 1768 6 (by rfl) (by decide)

private theorem decodeEpI6Lhs :
    decodeU32le ⟨canonicalBytes, 1768, 5⟩ =
      .ok (4, ⟨canonicalBytes, 1772, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI6Rhs :
    decodeU32le ⟨canonicalBytes, 1772, 5⟩ =
      .ok (5, ⟨canonicalBytes, 1776, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI6Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1738, 4⟩ =
      .ok (.binary .eq 4 5,
        ⟨canonicalBytes, 1776, 4⟩) := by
  apply decodeSemanticOpV1_binary ⟨canonicalBytes, 1738, 4⟩
    ⟨canonicalBytes, 1751, 5⟩ ⟨canonicalBytes, 1753, 5⟩
    ⟨canonicalBytes, 1768, 5⟩ ⟨canonicalBytes, 1772, 5⟩
    ⟨canonicalBytes, 1776, 5⟩
    .eq 4 5 (by decide)
  · exact decodeEpI6OpTag
  · exact decodeEpI6OpFc
  · exact decodeEpI6BinOp
  · exact decodeEpI6Lhs
  · exact decodeEpI6Rhs

private theorem decodeEpI6Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1698, 3⟩ =
      .ok (valueInstruction 6 1 (.binary .eq 4 5), ⟨canonicalBytes, 1776, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1698, 3⟩
    ⟨canonicalBytes, 1715, 4⟩ ⟨canonicalBytes, 1738, 4⟩ ⟨canonicalBytes, 1776, 4⟩
    (some { valueId := 6, typeId := 1 }) (.binary .eq 4 5) (by decide)
    expectEpI6Instr decodeEpI6Result decodeEpI6Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI7Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1776, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1793, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1776 1793 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI7VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1794, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1808, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1794 1808 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI7VID :
    decodeU32le ⟨canonicalBytes, 1808, 5⟩ =
      .ok (7, ⟨canonicalBytes, 1812, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI7TID :
    decodeU32le ⟨canonicalBytes, 1812, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1816, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI7ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1794, 4⟩ =
      .ok ({ valueId := 7, typeId := 0 }, ⟨canonicalBytes, 1816, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1794, 4⟩
    ⟨canonicalBytes, 1808, 5⟩ ⟨canonicalBytes, 1812, 5⟩
    ⟨canonicalBytes, 1816, 5⟩ 7 0 (by decide)
  · exact expectEpI7VD
  · exact decodeEpI7VID
  · exact decodeEpI7TID

private theorem decodeEpI7ResMark :
    decodeU8 ⟨canonicalBytes, 1793, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1794, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI7Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1793, 4⟩ =
      .ok (some { valueId := 7, typeId := 0 },
        ⟨canonicalBytes, 1816, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1793, 4⟩
    ⟨canonicalBytes, 1794, 4⟩
    ⟨canonicalBytes, 1816, 4⟩
    { valueId := 7, typeId := 0 }
  · exact decodeEpI7ResMark
  · exact decodeEpI7ValueDef

private theorem decodeEpI7OpTag :
    decodeTag ⟨canonicalBytes, 1816, 5⟩ =
      .ok ("Op.StateLoad", ⟨canonicalBytes, 1832, 5⟩) := by
  apply decodeCanonicalTagV1 1816 1832 5
    [79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] "Op.StateLoad"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI7OpFc :
    decodeFieldCount 1 ⟨canonicalBytes, 1832, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1834, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI7StateId :
    decodeU32le ⟨canonicalBytes, 1834, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1838, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI7Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1816, 4⟩ =
      .ok (.stateLoad 1, ⟨canonicalBytes, 1838, 4⟩) := by
  apply decodeSemanticOpV1_stateLoad ⟨canonicalBytes, 1816, 4⟩
    ⟨canonicalBytes, 1832, 5⟩ ⟨canonicalBytes, 1834, 5⟩
    ⟨canonicalBytes, 1838, 5⟩ 1 (by decide)
  · exact decodeEpI7OpTag
  · exact decodeEpI7OpFc
  · exact decodeEpI7StateId

private theorem decodeEpI7Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1776, 3⟩ =
      .ok (valueInstruction 7 0 (.stateLoad 1), ⟨canonicalBytes, 1838, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1776, 3⟩
    ⟨canonicalBytes, 1793, 4⟩ ⟨canonicalBytes, 1816, 4⟩ ⟨canonicalBytes, 1838, 4⟩
    (some { valueId := 7, typeId := 0 }) (.stateLoad 1) (by decide)
    expectEpI7Instr decodeEpI7Result decodeEpI7Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI8Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1838, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1855, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1838 1855 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI8VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1856, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1870, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1856 1870 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI8VID :
    decodeU32le ⟨canonicalBytes, 1870, 5⟩ =
      .ok (8, ⟨canonicalBytes, 1874, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI8TID :
    decodeU32le ⟨canonicalBytes, 1874, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1878, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI8ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1856, 4⟩ =
      .ok ({ valueId := 8, typeId := 0 }, ⟨canonicalBytes, 1878, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1856, 4⟩
    ⟨canonicalBytes, 1870, 5⟩ ⟨canonicalBytes, 1874, 5⟩
    ⟨canonicalBytes, 1878, 5⟩ 8 0 (by decide)
  · exact expectEpI8VD
  · exact decodeEpI8VID
  · exact decodeEpI8TID

private theorem decodeEpI8ResMark :
    decodeU8 ⟨canonicalBytes, 1855, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1856, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI8Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1855, 4⟩ =
      .ok (some { valueId := 8, typeId := 0 },
        ⟨canonicalBytes, 1878, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1855, 4⟩
    ⟨canonicalBytes, 1856, 4⟩
    ⟨canonicalBytes, 1878, 4⟩
    { valueId := 8, typeId := 0 }
  · exact decodeEpI8ResMark
  · exact decodeEpI8ValueDef

private theorem decodeEpI8OpTag :
    decodeTag ⟨canonicalBytes, 1878, 5⟩ =
      .ok ("Op.Literal", ⟨canonicalBytes, 1892, 5⟩) := by
  apply decodeCanonicalTagV1 1878 1892 5
    [79, 112, 46, 76, 105, 116, 101, 114, 97, 108] "Op.Literal"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI8OpFc :
    decodeFieldCount 2 ⟨canonicalBytes, 1892, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1894, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI8LitType :
    decodeU32le ⟨canonicalBytes, 1894, 5⟩ =
      .ok (0, ⟨canonicalBytes, 1898, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI8LitBytes :
    decodeByteArray maxCanonicalProgramBytes ⟨canonicalBytes, 1898, 5⟩ =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, ⟨canonicalBytes, 1910, 5⟩) := by
  have hread : readSizedBytesAtV1 canonicalBytes 1898 maxCanonicalProgramBytes =
      .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1910) := by
    change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1898
      maxCanonicalProgramBytes = .ok (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray, 1910)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [0, 0, 0, 0, 0, 0, 0, 0]
        1898 maxCanonicalProgramBytes 8 1902
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  simp only [decodeByteArray, hread, Bind.bind, Pure.pure, Except.bind, Except.pure]

private theorem decodeEpI8Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1878, 4⟩ =
      .ok (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray),
        ⟨canonicalBytes, 1910, 4⟩) := by
  apply decodeSemanticOpV1_literal ⟨canonicalBytes, 1878, 4⟩
    ⟨canonicalBytes, 1892, 5⟩ ⟨canonicalBytes, 1894, 5⟩
    ⟨canonicalBytes, 1898, 5⟩ ⟨canonicalBytes, 1910, 5⟩
    0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray) (by decide)
  · exact decodeEpI8OpTag
  · exact decodeEpI8OpFc
  · exact decodeEpI8LitType
  · exact decodeEpI8LitBytes

private theorem decodeEpI8Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1838, 3⟩ =
      .ok (valueInstruction 8 0 (.literal 0 zeroBytes), ⟨canonicalBytes, 1910, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1838, 3⟩
    ⟨canonicalBytes, 1855, 4⟩ ⟨canonicalBytes, 1878, 4⟩ ⟨canonicalBytes, 1910, 4⟩
    (some { valueId := 8, typeId := 0 }) (.literal 0 (ByteArray.mk [0, 0, 0, 0, 0, 0, 0, 0].toArray)) (by decide)
    expectEpI8Instr decodeEpI8Result decodeEpI8Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI9Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1910, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1927, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1910 1927 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI9VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 1928, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1942, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 1928 1942 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI9VID :
    decodeU32le ⟨canonicalBytes, 1942, 5⟩ =
      .ok (9, ⟨canonicalBytes, 1946, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI9TID :
    decodeU32le ⟨canonicalBytes, 1946, 5⟩ =
      .ok (1, ⟨canonicalBytes, 1950, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI9ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 1928, 4⟩ =
      .ok ({ valueId := 9, typeId := 1 }, ⟨canonicalBytes, 1950, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 1928, 4⟩
    ⟨canonicalBytes, 1942, 5⟩ ⟨canonicalBytes, 1946, 5⟩
    ⟨canonicalBytes, 1950, 5⟩ 9 1 (by decide)
  · exact expectEpI9VD
  · exact decodeEpI9VID
  · exact decodeEpI9TID

private theorem decodeEpI9ResMark :
    decodeU8 ⟨canonicalBytes, 1927, 4⟩ =
      .ok (1, ⟨canonicalBytes, 1928, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI9Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 1927, 4⟩ =
      .ok (some { valueId := 9, typeId := 1 },
        ⟨canonicalBytes, 1950, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 1927, 4⟩
    ⟨canonicalBytes, 1928, 4⟩
    ⟨canonicalBytes, 1950, 4⟩
    { valueId := 9, typeId := 1 }
  · exact decodeEpI9ResMark
  · exact decodeEpI9ValueDef

private theorem decodeEpI9OpTag :
    decodeTag ⟨canonicalBytes, 1950, 5⟩ =
      .ok ("Op.Binary", ⟨canonicalBytes, 1963, 5⟩) := by
  apply decodeCanonicalTagV1 1950 1963 5
    [79, 112, 46, 66, 105, 110, 97, 114, 121] "Op.Binary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI9OpFc :
    decodeFieldCount 3 ⟨canonicalBytes, 1963, 5⟩ =
      .ok ((), ⟨canonicalBytes, 1965, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI9BinOp :
    decodeBinaryOpV1 ⟨canonicalBytes, 1965, 5⟩ =
      .ok (.eq, ⟨canonicalBytes, 1980, 5⟩) := by
  apply decodeBinaryOpV1_eqOp ⟨canonicalBytes, 1965, 5⟩
    ⟨canonicalBytes, 1978, 6⟩ ⟨canonicalBytes, 1980, 6⟩
    (by decide)
  · apply decodeCanonicalTagV1 1965 1978 6
      [66, 105, 110, 97, 114, 121, 46, 69, 113] "Binary.Eq"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 1978 1980 6 (by rfl) (by decide)

private theorem decodeEpI9Lhs :
    decodeU32le ⟨canonicalBytes, 1980, 5⟩ =
      .ok (7, ⟨canonicalBytes, 1984, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI9Rhs :
    decodeU32le ⟨canonicalBytes, 1984, 5⟩ =
      .ok (8, ⟨canonicalBytes, 1988, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI9Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 1950, 4⟩ =
      .ok (.binary .eq 7 8,
        ⟨canonicalBytes, 1988, 4⟩) := by
  apply decodeSemanticOpV1_binary ⟨canonicalBytes, 1950, 4⟩
    ⟨canonicalBytes, 1963, 5⟩ ⟨canonicalBytes, 1965, 5⟩
    ⟨canonicalBytes, 1980, 5⟩ ⟨canonicalBytes, 1984, 5⟩
    ⟨canonicalBytes, 1988, 5⟩
    .eq 7 8 (by decide)
  · exact decodeEpI9OpTag
  · exact decodeEpI9OpFc
  · exact decodeEpI9BinOp
  · exact decodeEpI9Lhs
  · exact decodeEpI9Rhs

private theorem decodeEpI9Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1910, 3⟩ =
      .ok (valueInstruction 9 1 (.binary .eq 7 8), ⟨canonicalBytes, 1988, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1910, 3⟩
    ⟨canonicalBytes, 1927, 4⟩ ⟨canonicalBytes, 1950, 4⟩ ⟨canonicalBytes, 1988, 4⟩
    (some { valueId := 9, typeId := 1 }) (.binary .eq 7 8) (by decide)
    expectEpI9Instr decodeEpI9Result decodeEpI9Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI10Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 1988, 4⟩ =
      .ok ((), ⟨canonicalBytes, 2005, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 1988 2005 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI10VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 2006, 5⟩ =
      .ok ((), ⟨canonicalBytes, 2020, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 2006 2020 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI10VID :
    decodeU32le ⟨canonicalBytes, 2020, 5⟩ =
      .ok (10, ⟨canonicalBytes, 2024, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI10TID :
    decodeU32le ⟨canonicalBytes, 2024, 5⟩ =
      .ok (1, ⟨canonicalBytes, 2028, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI10ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 2006, 4⟩ =
      .ok ({ valueId := 10, typeId := 1 }, ⟨canonicalBytes, 2028, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 2006, 4⟩
    ⟨canonicalBytes, 2020, 5⟩ ⟨canonicalBytes, 2024, 5⟩
    ⟨canonicalBytes, 2028, 5⟩ 10 1 (by decide)
  · exact expectEpI10VD
  · exact decodeEpI10VID
  · exact decodeEpI10TID

private theorem decodeEpI10ResMark :
    decodeU8 ⟨canonicalBytes, 2005, 4⟩ =
      .ok (1, ⟨canonicalBytes, 2006, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI10Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 2005, 4⟩ =
      .ok (some { valueId := 10, typeId := 1 },
        ⟨canonicalBytes, 2028, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 2005, 4⟩
    ⟨canonicalBytes, 2006, 4⟩
    ⟨canonicalBytes, 2028, 4⟩
    { valueId := 10, typeId := 1 }
  · exact decodeEpI10ResMark
  · exact decodeEpI10ValueDef

private theorem decodeEpI10OpTag :
    decodeTag ⟨canonicalBytes, 2028, 5⟩ =
      .ok ("Op.Binary", ⟨canonicalBytes, 2041, 5⟩) := by
  apply decodeCanonicalTagV1 2028 2041 5
    [79, 112, 46, 66, 105, 110, 97, 114, 121] "Op.Binary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI10OpFc :
    decodeFieldCount 3 ⟨canonicalBytes, 2041, 5⟩ =
      .ok ((), ⟨canonicalBytes, 2043, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI10BinOp :
    decodeBinaryOpV1 ⟨canonicalBytes, 2043, 5⟩ =
      .ok (.and, ⟨canonicalBytes, 2059, 5⟩) := by
  apply decodeBinaryOpV1_andOp ⟨canonicalBytes, 2043, 5⟩
    ⟨canonicalBytes, 2057, 6⟩ ⟨canonicalBytes, 2059, 6⟩
    (by decide)
  · apply decodeCanonicalTagV1 2043 2057 6
      [66, 105, 110, 97, 114, 121, 46, 65, 110, 100] "Binary.And"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 2057 2059 6 (by rfl) (by decide)

private theorem decodeEpI10Lhs :
    decodeU32le ⟨canonicalBytes, 2059, 5⟩ =
      .ok (6, ⟨canonicalBytes, 2063, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI10Rhs :
    decodeU32le ⟨canonicalBytes, 2063, 5⟩ =
      .ok (9, ⟨canonicalBytes, 2067, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI10Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 2028, 4⟩ =
      .ok (.binary .and 6 9,
        ⟨canonicalBytes, 2067, 4⟩) := by
  apply decodeSemanticOpV1_binary ⟨canonicalBytes, 2028, 4⟩
    ⟨canonicalBytes, 2041, 5⟩ ⟨canonicalBytes, 2043, 5⟩
    ⟨canonicalBytes, 2059, 5⟩ ⟨canonicalBytes, 2063, 5⟩
    ⟨canonicalBytes, 2067, 5⟩
    .and 6 9 (by decide)
  · exact decodeEpI10OpTag
  · exact decodeEpI10OpFc
  · exact decodeEpI10BinOp
  · exact decodeEpI10Lhs
  · exact decodeEpI10Rhs

private theorem decodeEpI10Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 1988, 3⟩ =
      .ok (valueInstruction 10 1 (.binary .and 6 9), ⟨canonicalBytes, 2067, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 1988, 3⟩
    ⟨canonicalBytes, 2005, 4⟩ ⟨canonicalBytes, 2028, 4⟩ ⟨canonicalBytes, 2067, 4⟩
    (some { valueId := 10, typeId := 1 }) (.binary .and 6 9) (by decide)
    expectEpI10Instr decodeEpI10Result decodeEpI10Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpI11Instr :
    expectTag "Instruction" 2 ⟨canonicalBytes, 2067, 4⟩ =
      .ok ((), ⟨canonicalBytes, 2084, 4⟩) := by
  apply expectTag_of_spine "Instruction" 2 2067 2084 4
    [73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem expectEpI11VD :
    expectTag "ValueDef" 2 ⟨canonicalBytes, 2085, 5⟩ =
      .ok ((), ⟨canonicalBytes, 2099, 5⟩) := by
  apply expectTag_of_spine "ValueDef" 2 2085 2099 5
    [86, 97, 108, 117, 101, 68, 101, 102] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]
  rfl

private theorem decodeEpI11VID :
    decodeU32le ⟨canonicalBytes, 2099, 5⟩ =
      .ok (11, ⟨canonicalBytes, 2103, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI11TID :
    decodeU32le ⟨canonicalBytes, 2103, 5⟩ =
      .ok (1, ⟨canonicalBytes, 2107, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI11ValueDef :
    decodeValueDefV1 ⟨canonicalBytes, 2085, 4⟩ =
      .ok ({ valueId := 11, typeId := 1 }, ⟨canonicalBytes, 2107, 4⟩) := by
  apply decodeValueDefV1_eq_of_fieldsV1 ⟨canonicalBytes, 2085, 4⟩
    ⟨canonicalBytes, 2099, 5⟩ ⟨canonicalBytes, 2103, 5⟩
    ⟨canonicalBytes, 2107, 5⟩ 11 1 (by decide)
  · exact expectEpI11VD
  · exact decodeEpI11VID
  · exact decodeEpI11TID

private theorem decodeEpI11ResMark :
    decodeU8 ⟨canonicalBytes, 2084, 4⟩ =
      .ok (1, ⟨canonicalBytes, 2085, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpI11Result :
    decodeOption decodeValueDefV1 ⟨canonicalBytes, 2084, 4⟩ =
      .ok (some { valueId := 11, typeId := 1 },
        ⟨canonicalBytes, 2107, 4⟩) := by
  apply decodeOption_someV1 decodeValueDefV1 ⟨canonicalBytes, 2084, 4⟩
    ⟨canonicalBytes, 2085, 4⟩
    ⟨canonicalBytes, 2107, 4⟩
    { valueId := 11, typeId := 1 }
  · exact decodeEpI11ResMark
  · exact decodeEpI11ValueDef

private theorem decodeEpI11OpTag :
    decodeTag ⟨canonicalBytes, 2107, 5⟩ =
      .ok ("Op.Binary", ⟨canonicalBytes, 2120, 5⟩) := by
  apply decodeCanonicalTagV1 2107 2120 5
    [79, 112, 46, 66, 105, 110, 97, 114, 121] "Op.Binary"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpI11OpFc :
    decodeFieldCount 3 ⟨canonicalBytes, 2120, 5⟩ =
      .ok ((), ⟨canonicalBytes, 2122, 5⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpI11BinOp :
    decodeBinaryOpV1 ⟨canonicalBytes, 2122, 5⟩ =
      .ok (.or, ⟨canonicalBytes, 2137, 5⟩) := by
  apply decodeBinaryOpV1_orOp ⟨canonicalBytes, 2122, 5⟩
    ⟨canonicalBytes, 2135, 6⟩ ⟨canonicalBytes, 2137, 6⟩
    (by decide)
  · apply decodeCanonicalTagV1 2122 2135 6
      [66, 105, 110, 97, 114, 121, 46, 79, 114] "Binary.Or"
    · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
    · rfl
    · rfl
  · apply decodeCanonicalFieldCountV1 0 2135 2137 6 (by rfl) (by decide)

private theorem decodeEpI11Lhs :
    decodeU32le ⟨canonicalBytes, 2137, 5⟩ =
      .ok (3, ⟨canonicalBytes, 2141, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI11Rhs :
    decodeU32le ⟨canonicalBytes, 2141, 5⟩ =
      .ok (10, ⟨canonicalBytes, 2145, 5⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpI11Op :
    decodeSemanticOpV1 ⟨canonicalBytes, 2107, 4⟩ =
      .ok (.binary .or 3 10,
        ⟨canonicalBytes, 2145, 4⟩) := by
  apply decodeSemanticOpV1_binary ⟨canonicalBytes, 2107, 4⟩
    ⟨canonicalBytes, 2120, 5⟩ ⟨canonicalBytes, 2122, 5⟩
    ⟨canonicalBytes, 2137, 5⟩ ⟨canonicalBytes, 2141, 5⟩
    ⟨canonicalBytes, 2145, 5⟩
    .or 3 10 (by decide)
  · exact decodeEpI11OpTag
  · exact decodeEpI11OpFc
  · exact decodeEpI11BinOp
  · exact decodeEpI11Lhs
  · exact decodeEpI11Rhs

private theorem decodeEpI11Instruction :
    decodeInstructionV1 ⟨canonicalBytes, 2067, 3⟩ =
      .ok (valueInstruction 11 1 (.binary .or 3 10), ⟨canonicalBytes, 2145, 3⟩) := by
  have h := decodeInstructionV1_eq_of_fieldsV1 ⟨canonicalBytes, 2067, 3⟩
    ⟨canonicalBytes, 2084, 4⟩ ⟨canonicalBytes, 2107, 4⟩ ⟨canonicalBytes, 2145, 4⟩
    (some { valueId := 11, typeId := 1 }) (.binary .or 3 10) (by decide)
    expectEpI11Instr decodeEpI11Result decodeEpI11Op
  simpa [valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem decodeEpTermTag :
    decodeTag ⟨canonicalBytes, 2145, 4⟩ =
      .ok ("Term.Return", ⟨canonicalBytes, 2160, 4⟩) := by
  apply decodeCanonicalTagV1 2145 2160 4
    [84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110] "Term.Return"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpTermFc :
    decodeFieldCount 1 ⟨canonicalBytes, 2160, 4⟩ =
      .ok ((), ⟨canonicalBytes, 2162, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpTermMark :
    decodeU8 ⟨canonicalBytes, 2162, 4⟩ =
      .ok (1, ⟨canonicalBytes, 2163, 4⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpTermVal :
    decodeU32le ⟨canonicalBytes, 2163, 4⟩ =
      .ok (11, ⟨canonicalBytes, 2167, 4⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpReturn :
    decodeTerminatorV1 ⟨canonicalBytes, 2145, 3⟩ =
      .ok (.return_ (some 11), ⟨canonicalBytes, 2167, 3⟩) := by
  apply decodeTerminatorV1_return ⟨canonicalBytes, 2145, 3⟩
    ⟨canonicalBytes, 2160, 4⟩ ⟨canonicalBytes, 2162, 4⟩
    ⟨canonicalBytes, 2167, 4⟩
    (some 11) (by decide)
  · exact decodeEpTermTag
  · exact decodeEpTermFc
  · apply decodeOption_someV1 decodeU32le ⟨canonicalBytes, 2162, 4⟩
      ⟨canonicalBytes, 2163, 4⟩ ⟨canonicalBytes, 2167, 4⟩ 11
    · exact decodeEpTermMark
    · exact decodeEpTermVal

private theorem decodeEpInstructions :
    decodeArray maxArrayElements decodeInstructionV1 ⟨canonicalBytes, 1275, 3⟩ =
      .ok (emptyPoolBlock.instructions, ⟨canonicalBytes, 2145, 3⟩) := by
  have h := decodeArray_twelveV1 maxArrayElements decodeInstructionV1
    ⟨canonicalBytes, 1275, 3⟩ 1279
    (valueInstruction 0 0 (.stateLoad 2))
    (valueInstruction 1 0 (.literal 0 zeroBytes))
    (valueInstruction 2 1 (.binary .eq 0 1))
    (valueInstruction 3 1 (.unary .not 2))
    (valueInstruction 4 0 (.stateLoad 0))
    (valueInstruction 5 0 (.literal 0 zeroBytes))
    (valueInstruction 6 1 (.binary .eq 4 5))
    (valueInstruction 7 0 (.stateLoad 1))
    (valueInstruction 8 0 (.literal 0 zeroBytes))
    (valueInstruction 9 1 (.binary .eq 7 8))
    (valueInstruction 10 1 (.binary .and 6 9))
    (valueInstruction 11 1 (.binary .or 3 10))
    ⟨canonicalBytes, 1341, 3⟩ ⟨canonicalBytes, 1413, 3⟩ ⟨canonicalBytes, 1491, 3⟩
    ⟨canonicalBytes, 1564, 3⟩ ⟨canonicalBytes, 1626, 3⟩ ⟨canonicalBytes, 1698, 3⟩
    ⟨canonicalBytes, 1776, 3⟩ ⟨canonicalBytes, 1838, 3⟩ ⟨canonicalBytes, 1910, 3⟩
    ⟨canonicalBytes, 1988, 3⟩ ⟨canonicalBytes, 2067, 3⟩ ⟨canonicalBytes, 2145, 3⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1275
        maxArrayElements = .ok (12, 1279)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeEpI0Instruction decodeEpI1Instruction decodeEpI2Instruction
    decodeEpI3Instruction decodeEpI4Instruction decodeEpI5Instruction
    decodeEpI6Instruction decodeEpI7Instruction decodeEpI8Instruction
    decodeEpI9Instruction decodeEpI10Instruction decodeEpI11Instruction
  simpa [emptyPoolBlock, valueInstruction, valueDef, voidInstruction, zeroBytes] using h

private theorem expectEpBlock :
    expectTag "Block" 4 ⟨canonicalBytes, 1256, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1267, 3⟩) := by
  apply expectTag_of_spine "Block" 4 1256 1267 3
    [66, 108, 111, 99, 107] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeEpBlockId :
    decodeU32le ⟨canonicalBytes, 1267, 3⟩ = .ok (0, ⟨canonicalBytes, 1271, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpBlock :
    decodeBlockV1 ⟨canonicalBytes, 1256, 2⟩ =
      .ok (emptyPoolBlock, ⟨canonicalBytes, 2167, 2⟩) := by
  apply decodeBlockV1_eq_of_fieldsV1 ⟨canonicalBytes, 1256, 2⟩
    ⟨canonicalBytes, 1267, 3⟩ ⟨canonicalBytes, 1271, 3⟩
    ⟨canonicalBytes, 1275, 3⟩ ⟨canonicalBytes, 2145, 3⟩ ⟨canonicalBytes, 2167, 3⟩
    0 #[] emptyPoolBlock.instructions (.return_ (some 11)) (by decide)
  · exact expectEpBlock
  · exact decodeEpBlockId
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1271
      maxArrayElements = .ok (0, 1275)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeEpInstructions
  · exact decodeEpReturn

private theorem expectEpCallable :
    expectTag "Callable" 9 ⟨canonicalBytes, 1141, 2⟩ =
      .ok ((), ⟨canonicalBytes, 1155, 2⟩) := by
  apply expectTag_of_spine "Callable" 9 1141 1155 2
    [67, 97, 108, 108, 97, 98, 108, 101] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeEpId :
    decodeU32le ⟨canonicalBytes, 1155, 2⟩ =
      .ok (2, ⟨canonicalBytes, 1159, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpKindTag :
    decodeTag ⟨canonicalBytes, 1159, 3⟩ =
      .ok ("Callable.Invariant", ⟨canonicalBytes, 1181, 3⟩) := by
  apply decodeCanonicalTagV1 1159 1181 3
    [67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116] "Callable.Invariant"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpKindFc :
    decodeFieldCount 0 ⟨canonicalBytes, 1181, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1183, 3⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpKind :
    decodeCallableKindV1 ⟨canonicalBytes, 1159, 2⟩ =
      .ok (.invariant, ⟨canonicalBytes, 1183, 2⟩) := by
  refine decodeCallableKindV1_eq_of_bodyV1 ⟨canonicalBytes, 1159, 2⟩ .invariant
    ⟨canonicalBytes, 1183, 3⟩ (by decide) ?_
  apply decodeCallableKindBodyV1_invariant
  · exact decodeEpKindTag
  · exact decodeEpKindFc

private theorem decodeEpNameMark :
    decodeU8 ⟨canonicalBytes, 1183, 2⟩ =
      .ok (1, ⟨canonicalBytes, 1184, 2⟩) := by
  apply decodeCanonicalU8V1; rfl

private theorem decodeEpNameStr :
    decodeString ⟨canonicalBytes, 1184, 2⟩ =
      .ok ("emptyPool", ⟨canonicalBytes, 1197, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 1184 maxStringBytes =
      .ok (ByteArray.mk [101, 109, 112, 116, 121, 80, 111, 111, 108].toArray, 1197)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [101, 109, 112, 116, 121, 80, 111, 111, 108]
        1184 maxStringBytes 9 1188
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "emptyPool" (by decide)

private theorem decodeEpName :
    decodeOption decodeString ⟨canonicalBytes, 1183, 2⟩ =
      .ok (some "emptyPool", ⟨canonicalBytes, 1197, 2⟩) := by
  apply decodeOption_someV1 decodeString ⟨canonicalBytes, 1183, 2⟩
    ⟨canonicalBytes, 1184, 2⟩ ⟨canonicalBytes, 1197, 2⟩ "emptyPool"
  · exact decodeEpNameMark
  · exact decodeEpNameStr

private theorem expectEpResult :
    expectTag "CallableResult" 2 ⟨canonicalBytes, 1201, 3⟩ =
      .ok ((), ⟨canonicalBytes, 1221, 3⟩) := by
  apply expectTag_of_spine "CallableResult" 2 1201 1221 3
    [67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeEpResultType :
    decodeU32le ⟨canonicalBytes, 1221, 3⟩ =
      .ok (1, ⟨canonicalBytes, 1225, 3⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpVisTag :
    decodeTag ⟨canonicalBytes, 1225, 4⟩ =
      .ok ("Visibility.Public", ⟨canonicalBytes, 1246, 4⟩) := by
  apply decodeCanonicalTagV1 1225 1246 4
    [86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99]
    "Visibility.Public"
  · unfold readTagSpineBytesV1 takeSpineBytesV1 spineRemainingV1
    rw [canonicalSpine_length]; rfl
  · rfl
  · rfl

private theorem decodeEpVisFc :
    decodeFieldCount 0 ⟨canonicalBytes, 1246, 4⟩ =
      .ok ((), ⟨canonicalBytes, 1248, 4⟩) := by
  apply decodeCanonicalFieldCountV1
  · rfl
  · decide

private theorem decodeEpVisibility :
    decodeVisibilityV1 ⟨canonicalBytes, 1225, 3⟩ =
      .ok (.public_, ⟨canonicalBytes, 1248, 3⟩) := by
  refine decodeVisibilityV1_eq_of_bodyV1 ⟨canonicalBytes, 1225, 3⟩ .public_
    ⟨canonicalBytes, 1248, 4⟩ (by decide) ?_
  apply decodeVisibilityBodyV1_public
  · exact decodeEpVisTag
  · exact decodeEpVisFc

private theorem decodeEpResult :
    decodeCallableResultV1 ⟨canonicalBytes, 1201, 2⟩ =
      .ok ({ typeId := 1, visibility := .public_ }, ⟨canonicalBytes, 1248, 2⟩) := by
  refine decodeCallableResultV1_eq_of_bodyV1 ⟨canonicalBytes, 1201, 2⟩
    { typeId := 1, visibility := .public_ } ⟨canonicalBytes, 1248, 3⟩ (by decide) ?_
  apply decodeCallableResultBodyV1_eq_of_fields
  · exact expectEpResult
  · exact decodeEpResultType
  · exact decodeEpVisibility

private theorem decodeEpEntryBlock :
    decodeU32le ⟨canonicalBytes, 1248, 2⟩ =
      .ok (0, ⟨canonicalBytes, 1252, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeEpCallable :
    decodeCallableV1 ⟨canonicalBytes, 1141, 1⟩ =
      .ok (emptyPoolCallable, ⟨canonicalBytes, 2180, 1⟩) := by
  apply decodeCallableV1_singleBlockV1 ⟨canonicalBytes, 1141, 1⟩
    ⟨canonicalBytes, 1155, 2⟩ ⟨canonicalBytes, 1159, 2⟩
    ⟨canonicalBytes, 1183, 2⟩ ⟨canonicalBytes, 1197, 2⟩
    ⟨canonicalBytes, 1248, 2⟩ ⟨canonicalBytes, 1252, 2⟩
    ⟨canonicalBytes, 2167, 2⟩ ⟨canonicalBytes, 2180, 2⟩
    1201 1256 2171
    2 0 .invariant (some "emptyPool")
    { typeId := 1, visibility := .public_ } emptyPoolBlock
    (some 14) (by decide)
  · exact expectEpCallable
  · exact decodeEpId
  · exact decodeEpKind
  · exact decodeEpName
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1197
      maxArrayElements = .ok (0, 1201)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeEpResult
  · exact decodeEpEntryBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 1252
      maxArrayElements = .ok (1, 1256)
    rw [readArrayCountAtV1_refinesSpine]; rfl
  · exact decodeEpBlock
  · change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 2167
      maxArrayElements = .ok (0, 2171)
    rw [readArrayCountAtV1_refinesSpine]; rfl

  · apply decodeOption_someV1 decodeU64le ⟨canonicalBytes, 2171, 2⟩
      ⟨canonicalBytes, 2172, 2⟩ ⟨canonicalBytes, 2180, 2⟩ 14
    · apply decodeCanonicalU8V1; rfl
    · apply decodeCanonicalU64V1 2172 2180 2 14
      rfl


private theorem decodeCallables_canonicalBytes :
    decodeArray maxTableElements decodeCallableV1 ⟨canonicalBytes, 340, 1⟩ =
      .ok (#[clearCallable, getCallable, emptyPoolCallable], ⟨canonicalBytes, 2180, 1⟩) := by
  exact decodeArray_threeV1 maxTableElements decodeCallableV1
    ⟨canonicalBytes, 340, 1⟩ 344 clearCallable getCallable emptyPoolCallable
    ⟨canonicalBytes, 914, 1⟩ ⟨canonicalBytes, 1141, 1⟩ ⟨canonicalBytes, 2180, 1⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 340
        maxTableElements = .ok (3, 344)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeClrCallable decodeGetCallable decodeEpCallable

/-! ### Invariant + requirements -/

private theorem expectInv0 :
    expectTag "InvariantDecl" 3 ⟨canonicalBytes, 2184, 2⟩ =
      .ok ((), ⟨canonicalBytes, 2203, 2⟩) := by
  apply expectTag_of_spine "InvariantDecl" 3 2184 2203 2
    [73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodeInv0Id :
    decodeU32le ⟨canonicalBytes, 2203, 2⟩ =
      .ok (0, ⟨canonicalBytes, 2207, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeInv0Name :
    decodeString ⟨canonicalBytes, 2207, 2⟩ =
      .ok ("emptyPool", ⟨canonicalBytes, 2220, 2⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 2207 maxStringBytes =
      .ok (ByteArray.mk [101, 109, 112, 116, 121, 80, 111, 111, 108].toArray, 2220)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
        [101, 109, 112, 116, 121, 80, 111, 111, 108]
        2207 maxStringBytes 9 2211
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "emptyPool" (by decide)

private theorem decodeInv0CallableId :
    decodeU32le ⟨canonicalBytes, 2220, 2⟩ =
      .ok (2, ⟨canonicalBytes, 2224, 2⟩) := by
  apply decodeCanonicalU32V1; rfl

private theorem decodeInv0 :
    decodeInvariantDeclV1 ⟨canonicalBytes, 2184, 1⟩ =
      .ok (emptyPoolInvariant, ⟨canonicalBytes, 2224, 1⟩) := by
  refine decodeInvariantDeclV1_eq_of_bodyV1 ⟨canonicalBytes, 2184, 1⟩ emptyPoolInvariant
    ⟨canonicalBytes, 2224, 2⟩ (by decide) ?_
  apply decodeInvariantDeclBodyV1_eq_of_fields
  · exact expectInv0
  · exact decodeInv0Id
  · exact decodeInv0Name
  · exact decodeInv0CallableId

private theorem decodeInvariants_canonicalBytes :
    decodeArray maxTableElements decodeInvariantDeclV1 ⟨canonicalBytes, 2180, 1⟩ =
      .ok (#[emptyPoolInvariant], ⟨canonicalBytes, 2224, 1⟩) := by
  exact decodeArray_oneV1 maxTableElements decodeInvariantDeclV1
    ⟨canonicalBytes, 2180, 1⟩ 2184 emptyPoolInvariant ⟨canonicalBytes, 2224, 1⟩
    (by
      change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 2180
        maxTableElements = .ok (1, 2184)
      rw [readArrayCountAtV1_refinesSpine]; rfl)
    decodeInv0

private theorem expectProgramRequirements :
    expectTag "ProgramRequirements" 1 ⟨canonicalBytes, 2224, 2⟩ =
      .ok ((), ⟨canonicalBytes, 2249, 2⟩) := by
  apply expectTag_of_spine "ProgramRequirements" 1 2224 2249 2
    [80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 115] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem expectPersistentReq :
    expectTag "RequirementRequest" 4 ⟨canonicalBytes, 2253, 3⟩ =
      .ok ((), ⟨canonicalBytes, 2277, 3⟩) := by
  apply expectTag_of_spine "RequirementRequest" 4 2253 2277 3
    [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116] (by rfl)
  unfold expectTaggedHeaderSpineV1 readTagSpineBytesV1 takeSpineBytesV1
    spineRemainingV1 readSpineU16leV1
  rw [canonicalSpine_length]; rfl

private theorem decodePersistentReqId :
    decodeString ⟨canonicalBytes, 2277, 3⟩ =
      .ok ("state.persistent", ⟨canonicalBytes, 2297, 3⟩) := by
  apply decodeString_eq_of_valueV1
  · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 2277 maxStringBytes =
      .ok (ByteArray.mk [115, 116, 97, 116, 101, 46, 112, 101, 114, 115, 105, 115, 116, 101, 110, 116].toArray, 2297)
    apply readSizedBytesAtV1_eq_of_spine
    apply readSizedSpineBytesV1_eq_of_parts canonicalSpine
        [115, 116, 97, 116, 101, 46, 112, 101, 114, 115, 105, 115, 116, 101, 110, 116]
        2277 maxStringBytes 16 2281
    · rfl
    · decide
    · decide
    · unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]; rfl
  · rfl
  · exact requireNfc_eq_ok_of_isAscii "state.persistent" (by decide)

private theorem decodePersistentReqSemVer :
    decodeSemVer ⟨canonicalBytes, 2297, 3⟩ =
      .ok (s2RequirementVersionV1, ⟨canonicalBytes, 2306, 3⟩) := by
  apply decodeSemVer_eq_of_stringV1
  · apply decodeString_eq_of_valueV1
    · change readSizedBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 2297 maxStringBytes =
        .ok (ByteArray.mk [49, 46, 48, 46, 48].toArray, 2306)
      apply readSizedBytesAtV1_eq_of_spine
      apply readSizedSpineBytesV1_eq_of_parts canonicalSpine [49, 46, 48, 46, 48]
          2297 maxStringBytes 5 2301
      · rfl
      · decide
      · decide
      · unfold takeSpineBytesV1 spineRemainingV1
        rw [canonicalSpine_length]; rfl
    · rfl
    · exact requireNfc_eq_ok_of_isAscii "1.0.0" (by decide)
  · rfl

private theorem decodePersistentReqDigest :
    decodeDigest ⟨canonicalBytes, 2306, 3⟩ =
      .ok ({ algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 },
        ⟨canonicalBytes, 2338, 3⟩) := by
  apply decodeDigest_eq_of_takeV1
  · have h : takeBytesAtV1 (ByteArray.mk canonicalSpine.toArray) 2306 32 =
        .ok (ByteArray.mk ([2, 63, 255, 245, 41, 95, 167, 238, 77, 158, 78, 73, 144,
          154, 62, 183, 241, 252, 12, 86, 31, 142, 126, 160, 111, 18, 66, 52, 12, 20,
          110, 229]).toArray) := by
      apply takeBytesAtV1_eq_of_spine canonicalSpine
        ([2, 63, 255, 245, 41, 95, 167, 238, 77, 158, 78, 73, 144, 154, 62, 183, 241,
          252, 12, 86, 31, 142, 126, 160, 111, 18, 66, 52, 12, 20, 110, 229]) 2306
      unfold takeSpineBytesV1 spineRemainingV1
      rw [canonicalSpine_length]
      rfl
    simpa [canonicalBytes, s2StatePersistentDigestBytesV1] using h
  · simp [s2StatePersistentDigestBytesV1, validateDigest]
    rfl

private theorem decodePersistentReq :
    decodeRequirementRequestV1 ⟨canonicalBytes, 2253, 2⟩ =
      .ok (requirement "state.persistent" s2StatePersistentDigestBytesV1,
        ⟨canonicalBytes, 2342, 2⟩) := by
  apply decodeRequirementRequestV1_eq_of_fields ⟨canonicalBytes, 2253, 2⟩
    ⟨canonicalBytes, 2277, 3⟩ ⟨canonicalBytes, 2297, 3⟩
    ⟨canonicalBytes, 2306, 3⟩ ⟨canonicalBytes, 2338, 3⟩
    ⟨canonicalBytes, 2342, 3⟩
    "state.persistent" s2RequirementVersionV1
    { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 } #[] (by decide)
  · exact expectPersistentReq
  · exact decodePersistentReqId
  · exact decodePersistentReqSemVer
  · exact decodePersistentReqDigest
  · apply decodeArray_zeroV1
    change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 2338
      maxArrayElements = .ok (0, 2342)
    rw [readArrayCountAtV1_refinesSpine]; rfl

private theorem decodeRequirements_canonicalBytes :
    decodeProgramRequirementsV1 ⟨canonicalBytes, 2224, 1⟩ =
      .ok ({ items := #[persistentStateRequirement] }, ⟨canonicalBytes, 2342, 1⟩) := by
  refine decodeProgramRequirementsV1_eq_of_bodyV1 ⟨canonicalBytes, 2224, 1⟩
    { items := #[persistentStateRequirement] }
    ⟨canonicalBytes, 2342, 2⟩ (by decide) ?_
  apply decodeProgramRequirementsBodyV1_eq_of_fields
  · exact expectProgramRequirements
  · exact decodeArray_oneV1 maxArrayElements decodeRequirementRequestV1
      ⟨canonicalBytes, 2249, 2⟩ 2253
      persistentStateRequirement
      ⟨canonicalBytes, 2342, 2⟩
      (by
        change readArrayCountAtV1 (ByteArray.mk canonicalSpine.toArray) 2249
          maxArrayElements = .ok (1, 2253)
        rw [readArrayCountAtV1_refinesSpine]; rfl)
      (by simpa [persistentStateRequirement, requirement] using decodePersistentReq)

/-! ### Root tagged composition + public decode_ok -/

private theorem decodeTaggedData_canonicalBytes :
    decodeSemanticProgramDataTaggedV1 ⟨canonicalBytes, 15, 0⟩ =
      .ok (data, ⟨canonicalBytes, 2342, 0⟩) := by
  have h := decodeSemanticProgramDataTaggedV1_eq_of_fields
    ⟨canonicalBytes, 15, 0⟩ ⟨canonicalBytes, 41, 1⟩
    ⟨canonicalBytes, 73, 1⟩ ⟨canonicalBytes, 147, 1⟩
    ⟨canonicalBytes, 151, 1⟩ ⟨canonicalBytes, 332, 1⟩
    ⟨canonicalBytes, 336, 1⟩ ⟨canonicalBytes, 340, 1⟩
    ⟨canonicalBytes, 2180, 1⟩ ⟨canonicalBytes, 2224, 1⟩
    ⟨canonicalBytes, 2342, 1⟩ qualifiedName types #[]
    #[reserve0State, reserve1State, totalSupplyState] #[] #[]
    #[clearCallable, getCallable, emptyPoolCallable] #[emptyPoolInvariant]
    { items := #[persistentStateRequirement] } (by decide)
    expectRootTag_canonicalBytes decodeQualifiedName_canonicalBytes
    decodeTypes_canonicalBytes decodeConstants_canonicalBytes
    decodeLogicalState_canonicalBytes decodeEvents_canonicalBytes
    decodeErrors_canonicalBytes decodeCallables_canonicalBytes
    decodeInvariants_canonicalBytes decodeRequirements_canonicalBytes
  simpa [data] using h

/-- Production transport decoder certificate for closed MiniAmmEmptyPool. -/
theorem decode_ok :
    decodeSemanticProgramDataV1 MiniAmmEmptyPoolV1.canonicalBytes =
      .ok MiniAmmEmptyPoolV1.data := by
  apply decodeSemanticProgramDataV1_eq_of_framing canonicalBytes
    ⟨canonicalBytes, 15, 0⟩ ⟨canonicalBytes, 2342, 0⟩ data
  · change canonicalSpine.length ≤ maxCanonicalProgramBytes
    rw [canonicalSpine_length]
    decide
  · exact consumeMagic_canonicalBytes
  · exact decodeTaggedData_canonicalBytes
  · apply finish_eq_ok_of_offset_sizeV1
    change 2342 = canonicalSpine.length
    exact canonicalSpine_length.symm

end ProofForgeV2.ProofInstances.MiniAmmEmptyPoolDecodeV1
