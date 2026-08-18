import ProofForgeV2.Semantic.Wire.CodecInvertTypeTableV1

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertOpV1 — generic encode→decode
  invertibility for every `SemanticOpV1` constructor.

  Built from the sole production codecs through `FieldReadV1`. No second
  encoder, no fixture, no `native_decide` / `ofReduceBool` / sorry / axiom.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

private theorem toUTF8_size_eq_utf8ByteSize (s : String) :
    s.toUTF8.size = s.toUTF8.size := rfl

theorem asciiTagBytes_OpLiteralV1 : isAsciiTagBytesV1 "Op.Literal".toUTF8 = true := by
  rw [show "Op.Literal".toUTF8 = ByteArray.mk #[79, 112, 46, 76, 105, 116, 101, 114, 97, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpConstantV1 : isAsciiTagBytesV1 "Op.Constant".toUTF8 = true := by
  rw [show "Op.Constant".toUTF8 = ByteArray.mk #[79, 112, 46, 67, 111, 110, 115, 116, 97, 110, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpStateLoadV1 : isAsciiTagBytesV1 "Op.StateLoad".toUTF8 = true := by
  rw [show "Op.StateLoad".toUTF8 = ByteArray.mk #[79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpStateStoreV1 : isAsciiTagBytesV1 "Op.StateStore".toUTF8 = true := by
  rw [show "Op.StateStore".toUTF8 = ByteArray.mk #[79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpConstructV1 : isAsciiTagBytesV1 "Op.Construct".toUTF8 = true := by
  rw [show "Op.Construct".toUTF8 = ByteArray.mk #[79, 112, 46, 67, 111, 110, 115, 116, 114, 117, 99, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpFieldGetV1 : isAsciiTagBytesV1 "Op.FieldGet".toUTF8 = true := by
  rw [show "Op.FieldGet".toUTF8 = ByteArray.mk #[79, 112, 46, 70, 105, 101, 108, 100, 71, 101, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpFieldSetV1 : isAsciiTagBytesV1 "Op.FieldSet".toUTF8 = true := by
  rw [show "Op.FieldSet".toUTF8 = ByteArray.mk #[79, 112, 46, 70, 105, 101, 108, 100, 83, 101, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpVariantTagV1 : isAsciiTagBytesV1 "Op.VariantTag".toUTF8 = true := by
  rw [show "Op.VariantTag".toUTF8 = ByteArray.mk #[79, 112, 46, 86, 97, 114, 105, 97, 110, 116, 84, 97, 103] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpVariantPayloadV1 : isAsciiTagBytesV1 "Op.VariantPayload".toUTF8 = true := by
  rw [show "Op.VariantPayload".toUTF8 = ByteArray.mk #[79, 112, 46, 86, 97, 114, 105, 97, 110, 116, 80, 97, 121, 108, 111, 97, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpIndexGetV1 : isAsciiTagBytesV1 "Op.IndexGet".toUTF8 = true := by
  rw [show "Op.IndexGet".toUTF8 = ByteArray.mk #[79, 112, 46, 73, 110, 100, 101, 120, 71, 101, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpIndexSetV1 : isAsciiTagBytesV1 "Op.IndexSet".toUTF8 = true := by
  rw [show "Op.IndexSet".toUTF8 = ByteArray.mk #[79, 112, 46, 73, 110, 100, 101, 120, 83, 101, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpCheckedCastV1 : isAsciiTagBytesV1 "Op.CheckedCast".toUTF8 = true := by
  rw [show "Op.CheckedCast".toUTF8 = ByteArray.mk #[79, 112, 46, 67, 104, 101, 99, 107, 101, 100, 67, 97, 115, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpUnaryV1 : isAsciiTagBytesV1 "Op.Unary".toUTF8 = true := by
  rw [show "Op.Unary".toUTF8 = ByteArray.mk #[79, 112, 46, 85, 110, 97, 114, 121] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpBinaryV1 : isAsciiTagBytesV1 "Op.Binary".toUTF8 = true := by
  rw [show "Op.Binary".toUTF8 = ByteArray.mk #[79, 112, 46, 66, 105, 110, 97, 114, 121] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpPureCallV1 : isAsciiTagBytesV1 "Op.PureCall".toUTF8 = true := by
  rw [show "Op.PureCall".toUTF8 = ByteArray.mk #[79, 112, 46, 80, 117, 114, 101, 67, 97, 108, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpContextReadV1 : isAsciiTagBytesV1 "Op.ContextRead".toUTF8 = true := by
  rw [show "Op.ContextRead".toUTF8 = ByteArray.mk #[79, 112, 46, 67, 111, 110, 116, 101, 120, 116, 82, 101, 97, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpEnvReadV1 : isAsciiTagBytesV1 "Op.EnvRead".toUTF8 = true := by
  rw [show "Op.EnvRead".toUTF8 = ByteArray.mk #[79, 112, 46, 69, 110, 118, 82, 101, 97, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpCommitV1 : isAsciiTagBytesV1 "Op.Commit".toUTF8 = true := by
  rw [show "Op.Commit".toUTF8 = ByteArray.mk #[79, 112, 46, 67, 111, 109, 109, 105, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpAssertV1 : isAsciiTagBytesV1 "Op.Assert".toUTF8 = true := by
  rw [show "Op.Assert".toUTF8 = ByteArray.mk #[79, 112, 46, 65, 115, 115, 101, 114, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpEmitV1 : isAsciiTagBytesV1 "Op.Emit".toUTF8 = true := by
  rw [show "Op.Emit".toUTF8 = ByteArray.mk #[79, 112, 46, 69, 109, 105, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpExternalCallV1 : isAsciiTagBytesV1 "Op.ExternalCall".toUTF8 = true := by
  rw [show "Op.ExternalCall".toUTF8 = ByteArray.mk #[79, 112, 46, 69, 120, 116, 101, 114, 110, 97, 108, 67, 97, 108, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_OpScheduleV1 : isAsciiTagBytesV1 "Op.Schedule".toUTF8 = true := by
  rw [show "Op.Schedule".toUTF8 = ByteArray.mk #[79, 112, 46, 83, 99, 104, 101, 100, 117, 108, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_UnaryNegV1 : isAsciiTagBytesV1 "Unary.Neg".toUTF8 = true := by
  rw [show "Unary.Neg".toUTF8 = ByteArray.mk #[85, 110, 97, 114, 121, 46, 78, 101, 103] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_UnaryNotV1 : isAsciiTagBytesV1 "Unary.Not".toUTF8 = true := by
  rw [show "Unary.Not".toUTF8 = ByteArray.mk #[85, 110, 97, 114, 121, 46, 78, 111, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_UnaryBitNotV1 : isAsciiTagBytesV1 "Unary.BitNot".toUTF8 = true := by
  rw [show "Unary.BitNot".toUTF8 = ByteArray.mk #[85, 110, 97, 114, 121, 46, 66, 105, 116, 78, 111, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_EnvReadNativeVaultBalanceV1 : isAsciiTagBytesV1 "EnvRead.NativeVaultBalance".toUTF8 = true := by
  rw [show "EnvRead.NativeVaultBalance".toUTF8 = ByteArray.mk #[69, 110, 118, 82, 101, 97, 100, 46, 78, 97, 116, 105, 118, 101, 86, 97, 117, 108, 116, 66, 97, 108, 97, 110, 99, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_EnvReadTokenVaultBalanceV1 : isAsciiTagBytesV1 "EnvRead.TokenVaultBalance".toUTF8 = true := by
  rw [show "EnvRead.TokenVaultBalance".toUTF8 = ByteArray.mk #[69, 110, 118, 82, 101, 97, 100, 46, 84, 111, 107, 101, 110, 86, 97, 117, 108, 116, 66, 97, 108, 97, 110, 99, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_EnvReadNativeVaultBalanceU128V1 : isAsciiTagBytesV1 "EnvRead.NativeVaultBalanceU128".toUTF8 = true := by
  rw [show "EnvRead.NativeVaultBalanceU128".toUTF8 = ByteArray.mk #[69, 110, 118, 82, 101, 97, 100, 46, 78, 97, 116, 105, 118, 101, 86, 97, 117, 108, 116, 66, 97, 108, 97, 110, 99, 101, 85, 49, 50, 56] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryAddV1 : isAsciiTagBytesV1 "Binary.Add".toUTF8 = true := by
  rw [show "Binary.Add".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 65, 100, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinarySubV1 : isAsciiTagBytesV1 "Binary.Sub".toUTF8 = true := by
  rw [show "Binary.Sub".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 83, 117, 98] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryMulV1 : isAsciiTagBytesV1 "Binary.Mul".toUTF8 = true := by
  rw [show "Binary.Mul".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 77, 117, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryDivV1 : isAsciiTagBytesV1 "Binary.Div".toUTF8 = true := by
  rw [show "Binary.Div".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 68, 105, 118] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryModV1 : isAsciiTagBytesV1 "Binary.Mod".toUTF8 = true := by
  rw [show "Binary.Mod".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 77, 111, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryEqV1 : isAsciiTagBytesV1 "Binary.Eq".toUTF8 = true := by
  rw [show "Binary.Eq".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 69, 113] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryNeV1 : isAsciiTagBytesV1 "Binary.Ne".toUTF8 = true := by
  rw [show "Binary.Ne".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 78, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryLtV1 : isAsciiTagBytesV1 "Binary.Lt".toUTF8 = true := by
  rw [show "Binary.Lt".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 76, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryLeV1 : isAsciiTagBytesV1 "Binary.Le".toUTF8 = true := by
  rw [show "Binary.Le".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 76, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryGtV1 : isAsciiTagBytesV1 "Binary.Gt".toUTF8 = true := by
  rw [show "Binary.Gt".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 71, 116] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryGeV1 : isAsciiTagBytesV1 "Binary.Ge".toUTF8 = true := by
  rw [show "Binary.Ge".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 71, 101] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryAndV1 : isAsciiTagBytesV1 "Binary.And".toUTF8 = true := by
  rw [show "Binary.And".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 65, 110, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryOrV1 : isAsciiTagBytesV1 "Binary.Or".toUTF8 = true := by
  rw [show "Binary.Or".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 79, 114] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryBitAndV1 : isAsciiTagBytesV1 "Binary.BitAnd".toUTF8 = true := by
  rw [show "Binary.BitAnd".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 66, 105, 116, 65, 110, 100] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryBitOrV1 : isAsciiTagBytesV1 "Binary.BitOr".toUTF8 = true := by
  rw [show "Binary.BitOr".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 66, 105, 116, 79, 114] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryBitXorV1 : isAsciiTagBytesV1 "Binary.BitXor".toUTF8 = true := by
  rw [show "Binary.BitXor".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 66, 105, 116, 88, 111, 114] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryShlV1 : isAsciiTagBytesV1 "Binary.Shl".toUTF8 = true := by
  rw [show "Binary.Shl".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 83, 104, 108] from rfl]
  simp [isAsciiTagBytesV1]

theorem asciiTagBytes_BinaryShrV1 : isAsciiTagBytesV1 "Binary.Shr".toUTF8 = true := by
  rw [show "Binary.Shr".toUTF8 = ByteArray.mk #[66, 105, 110, 97, 114, 121, 46, 83, 104, 114] from rfl]
  simp [isAsciiTagBytesV1]

/-! ### UnaryOp / BinaryOp / EnvReadKey -/

def unaryOpTagV1 : UnaryOpV1 → String
  | .neg => "Unary.Neg"
  | .not => "Unary.Not"
  | .bitNot => "Unary.BitNot"

theorem encodeUnaryOp_eq_nullaryV1 (op : UnaryOpV1) :
    encodeUnaryOpV1 op = encodeNullary (unaryOpTagV1 op) := by
  cases op <;> rfl

theorem fieldRead_unaryOpV1 (op : UnaryOpV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeUnaryOpV1 op = .ok b) :
    FieldReadV1 decodeUnaryOpV1 b op nesting := by
  have hnull : encodeNullary (unaryOpTagV1 op) = .ok b := by
    simpa [encodeUnaryOp_eq_nullaryV1] using henc
  have hb := encodeNullary_ok_eq_headerV1 (unaryOpTagV1 op) b
    (by cases op <;> decide) (by cases op <;> decide) (by cases op <;> decide) hnull
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  cases op with
  | neg =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Unary.Neg" 0 ++ post) pre.size pre post
        "Unary.Neg" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_UnaryNegV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Unary.Neg" 0 ++ post)
        (pre.size + 4 + "Unary.Neg".utf8ByteSize) pre post "Unary.Neg" 0 (nesting + 1)
        rfl rfl (by decide)
      simp [unaryOpTagV1, h0, h1, Bind.bind, Except.bind,
        Pure.pure, Except.pure]
  | not =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Unary.Not" 0 ++ post) pre.size pre post
        "Unary.Not" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_UnaryNotV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Unary.Not" 0 ++ post)
        (pre.size + 4 + "Unary.Not".utf8ByteSize) pre post "Unary.Not" 0 (nesting + 1)
        rfl rfl (by decide)
      simp [unaryOpTagV1, h0, h1, Bind.bind, Except.bind,
        Pure.pure, Except.pure]
  | bitNot =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Unary.BitNot" 0 ++ post) pre.size pre post
        "Unary.BitNot" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_UnaryBitNotV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Unary.BitNot" 0 ++ post)
        (pre.size + 4 + "Unary.BitNot".utf8ByteSize) pre post "Unary.BitNot" 0
        (nesting + 1) rfl rfl (by decide)
      simp [unaryOpTagV1, h0, h1, Bind.bind, Except.bind,
        Pure.pure, Except.pure]


def binaryOpTagV1 : BinaryOpV1 → String
  | .add => "Binary.Add"
  | .sub => "Binary.Sub"
  | .mul => "Binary.Mul"
  | .div => "Binary.Div"
  | .mod => "Binary.Mod"
  | .eq => "Binary.Eq"
  | .ne => "Binary.Ne"
  | .lt => "Binary.Lt"
  | .le => "Binary.Le"
  | .gt => "Binary.Gt"
  | .ge => "Binary.Ge"
  | .and => "Binary.And"
  | .or => "Binary.Or"
  | .bitAnd => "Binary.BitAnd"
  | .bitOr => "Binary.BitOr"
  | .bitXor => "Binary.BitXor"
  | .shl => "Binary.Shl"
  | .shr => "Binary.Shr"

theorem encodeBinaryOp_eq_nullaryV1 (op : BinaryOpV1) :
    encodeBinaryOpV1 op = encodeNullary (binaryOpTagV1 op) := by
  cases op <;> rfl


theorem fieldRead_binaryOpBodyV1 (op : BinaryOpV1) (nesting : Nat) :
    FieldReadV1 decodeBinaryOpBodyV1 (taggedHeaderBytesV1 (binaryOpTagV1 op) 0) op
      nesting := by
  intro pre post
  cases op with
  | add =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Add" 0 ++ post) pre.size pre post
        "Binary.Add" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryAddV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Add" 0 ++ post)
        (pre.size + 4 + "Binary.Add".utf8ByteSize) pre post "Binary.Add" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | sub =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Sub" 0 ++ post) pre.size pre post
        "Binary.Sub" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinarySubV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Sub" 0 ++ post)
        (pre.size + 4 + "Binary.Sub".utf8ByteSize) pre post "Binary.Sub" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | mul =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Mul" 0 ++ post) pre.size pre post
        "Binary.Mul" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryMulV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Mul" 0 ++ post)
        (pre.size + 4 + "Binary.Mul".utf8ByteSize) pre post "Binary.Mul" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | div =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Div" 0 ++ post) pre.size pre post
        "Binary.Div" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryDivV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Div" 0 ++ post)
        (pre.size + 4 + "Binary.Div".utf8ByteSize) pre post "Binary.Div" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | mod =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Mod" 0 ++ post) pre.size pre post
        "Binary.Mod" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryModV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Mod" 0 ++ post)
        (pre.size + 4 + "Binary.Mod".utf8ByteSize) pre post "Binary.Mod" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | eq =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Eq" 0 ++ post) pre.size pre post
        "Binary.Eq" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryEqV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Eq" 0 ++ post)
        (pre.size + 4 + "Binary.Eq".utf8ByteSize) pre post "Binary.Eq" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | ne =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Ne" 0 ++ post) pre.size pre post
        "Binary.Ne" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryNeV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Ne" 0 ++ post)
        (pre.size + 4 + "Binary.Ne".utf8ByteSize) pre post "Binary.Ne" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | lt =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Lt" 0 ++ post) pre.size pre post
        "Binary.Lt" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryLtV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Lt" 0 ++ post)
        (pre.size + 4 + "Binary.Lt".utf8ByteSize) pre post "Binary.Lt" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | le =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Le" 0 ++ post) pre.size pre post
        "Binary.Le" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryLeV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Le" 0 ++ post)
        (pre.size + 4 + "Binary.Le".utf8ByteSize) pre post "Binary.Le" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | gt =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Gt" 0 ++ post) pre.size pre post
        "Binary.Gt" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryGtV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Gt" 0 ++ post)
        (pre.size + 4 + "Binary.Gt".utf8ByteSize) pre post "Binary.Gt" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | ge =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Ge" 0 ++ post) pre.size pre post
        "Binary.Ge" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryGeV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Ge" 0 ++ post)
        (pre.size + 4 + "Binary.Ge".utf8ByteSize) pre post "Binary.Ge" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | and =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.And" 0 ++ post) pre.size pre post
        "Binary.And" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryAndV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.And" 0 ++ post)
        (pre.size + 4 + "Binary.And".utf8ByteSize) pre post "Binary.And" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | or =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Or" 0 ++ post) pre.size pre post
        "Binary.Or" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryOrV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Or" 0 ++ post)
        (pre.size + 4 + "Binary.Or".utf8ByteSize) pre post "Binary.Or" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | bitAnd =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.BitAnd" 0 ++ post) pre.size pre post
        "Binary.BitAnd" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryBitAndV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.BitAnd" 0 ++ post)
        (pre.size + 4 + "Binary.BitAnd".utf8ByteSize) pre post "Binary.BitAnd" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | bitOr =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.BitOr" 0 ++ post) pre.size pre post
        "Binary.BitOr" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryBitOrV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.BitOr" 0 ++ post)
        (pre.size + 4 + "Binary.BitOr".utf8ByteSize) pre post "Binary.BitOr" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | bitXor =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.BitXor" 0 ++ post) pre.size pre post
        "Binary.BitXor" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryBitXorV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.BitXor" 0 ++ post)
        (pre.size + 4 + "Binary.BitXor".utf8ByteSize) pre post "Binary.BitXor" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | shl =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Shl" 0 ++ post) pre.size pre post
        "Binary.Shl" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryShlV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Shl" 0 ++ post)
        (pre.size + 4 + "Binary.Shl".utf8ByteSize) pre post "Binary.Shl" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]
  | shr =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Shr" 0 ++ post) pre.size pre post
        "Binary.Shr" 0 nesting rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_BinaryShrV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "Binary.Shr" 0 ++ post)
        (pre.size + 4 + "Binary.Shr".utf8ByteSize) pre post "Binary.Shr" 0 nesting
        rfl rfl (by decide)
      simp [binaryOpTagV1, decodeBinaryOpBodyV1, h0, h1,
        Bind.bind, Except.bind, Pure.pure, Except.pure]

theorem fieldRead_binaryOpV1 (op : BinaryOpV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeBinaryOpV1 op = .ok b) :
    FieldReadV1 decodeBinaryOpV1 b op nesting := by
  have hnull : encodeNullary (binaryOpTagV1 op) = .ok b := by
    simpa [encodeBinaryOp_eq_nullaryV1] using henc
  have hb := encodeNullary_ok_eq_headerV1 (binaryOpTagV1 op) b
    (by cases op <;> decide) (by cases op <;> decide) (by cases op <;> decide) hnull
  subst hb
  exact fieldRead_withTaggedNestingV1 _ _ _ _ hdepth (fieldRead_binaryOpBodyV1 op (nesting + 1))


def envReadKeyTagV1 : EnvReadKeyV1 → String
  | .nativeVaultBalance => "EnvRead.NativeVaultBalance"
  | .tokenVaultBalance => "EnvRead.TokenVaultBalance"
  | .nativeVaultBalanceU128 => "EnvRead.NativeVaultBalanceU128"

theorem encodeEnvReadKey_eq_nullaryV1 (key : EnvReadKeyV1) :
    encodeEnvReadKeyV1 key = encodeNullary (envReadKeyTagV1 key) := by
  cases key <;> rfl


theorem fieldRead_envReadKeyV1 (key : EnvReadKeyV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting) (henc : encodeEnvReadKeyV1 key = .ok b) :
    FieldReadV1 decodeEnvReadKeyV1 b key nesting := by
  have hnull : encodeNullary (envReadKeyTagV1 key) = .ok b := by
    simpa [encodeEnvReadKey_eq_nullaryV1] using henc
  have hb := encodeNullary_ok_eq_headerV1 (envReadKeyTagV1 key) b
    (by cases key <;> decide) (by cases key <;> decide) (by cases key <;> decide) hnull
  subst hb
  apply fieldRead_withTaggedNestingV1 _ _ _ _ hdepth
  intro pre post
  cases key with
  | nativeVaultBalance =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "EnvRead.NativeVaultBalance" 0 ++ post) pre.size pre post
        "EnvRead.NativeVaultBalance" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_EnvReadNativeVaultBalanceV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "EnvRead.NativeVaultBalance" 0 ++ post)
        (pre.size + 4 + "EnvRead.NativeVaultBalance".utf8ByteSize) pre post "EnvRead.NativeVaultBalance" 0 (nesting + 1)
        rfl rfl (by decide)
      simp [envReadKeyTagV1, h0, h1, Bind.bind, Except.bind,
        Pure.pure, Except.pure]
  | tokenVaultBalance =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "EnvRead.TokenVaultBalance" 0 ++ post) pre.size pre post
        "EnvRead.TokenVaultBalance" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_EnvReadTokenVaultBalanceV1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "EnvRead.TokenVaultBalance" 0 ++ post)
        (pre.size + 4 + "EnvRead.TokenVaultBalance".utf8ByteSize) pre post "EnvRead.TokenVaultBalance" 0 (nesting + 1)
        rfl rfl (by decide)
      simp [envReadKeyTagV1, h0, h1, Bind.bind, Except.bind,
        Pure.pure, Except.pure]
  | nativeVaultBalanceU128 =>
      have h0 := decodeTag_header_readV1
        (pre ++ taggedHeaderBytesV1 "EnvRead.NativeVaultBalanceU128" 0 ++ post) pre.size pre post
        "EnvRead.NativeVaultBalanceU128" 0 (nesting + 1) rfl rfl (by decide) (by decide) (by decide)
        asciiTagBytes_EnvReadNativeVaultBalanceU128V1 (by decide)
      have h1 := decodeFieldCount_header_readV1
        (pre ++ taggedHeaderBytesV1 "EnvRead.NativeVaultBalanceU128" 0 ++ post)
        (pre.size + 4 + "EnvRead.NativeVaultBalanceU128".utf8ByteSize) pre post "EnvRead.NativeVaultBalanceU128" 0 (nesting + 1)
        rfl rfl (by decide)
      simp [envReadKeyTagV1, h0, h1, Bind.bind, Except.bind,
        Pure.pure, Except.pure]


theorem fieldRead_semanticOpBody_constantV1 (id : ConstantIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.constant id) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.constant id) nesting := by
  have hb : b = taggedHeaderBytesV1 "Op.Constant" 1 ++ encodeU32le id :=
    encodeTagged_ok_eq_one_fieldV1 "Op.Constant" (encodeU32le id) b henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.Constant" 1 ++ encodeU32le id) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le id ++ post)
    "Op.Constant" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_OpConstantV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B
    (pre.size + 4 + "Op.Constant".utf8ByteSize) pre (encodeU32le id ++ post)
    "Op.Constant" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 id nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Constant" 1).size)
    (pre ++ taggedHeaderBytesV1 "Op.Constant" 1) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_stateLoadV1 (id : StateIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.stateLoad id) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.stateLoad id) nesting := by
  have hb : b = taggedHeaderBytesV1 "Op.StateLoad" 1 ++ encodeU32le id :=
    encodeTagged_ok_eq_one_fieldV1 "Op.StateLoad" (encodeU32le id) b henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.StateLoad" 1 ++ encodeU32le id) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le id ++ post)
    "Op.StateLoad" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_OpStateLoadV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B
    (pre.size + 4 + "Op.StateLoad".utf8ByteSize) pre (encodeU32le id ++ post)
    "Op.StateLoad" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 id nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.StateLoad" 1).size)
    (pre ++ taggedHeaderBytesV1 "Op.StateLoad" 1) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_variantTagV1 (base : ValueIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.variantTag base) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.variantTag base) nesting := by
  have hb : b = taggedHeaderBytesV1 "Op.VariantTag" 1 ++ encodeU32le base :=
    encodeTagged_ok_eq_one_fieldV1 "Op.VariantTag" (encodeU32le base) b henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.VariantTag" 1 ++ encodeU32le base) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le base ++ post)
    "Op.VariantTag" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_OpVariantTagV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B
    (pre.size + 4 + "Op.VariantTag".utf8ByteSize) pre (encodeU32le base ++ post)
    "Op.VariantTag" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 base nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.VariantTag" 1).size)
    (pre ++ taggedHeaderBytesV1 "Op.VariantTag" 1) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_commitV1 (value : ValueIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.commit value) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.commit value) nesting := by
  have hb : b = taggedHeaderBytesV1 "Op.Commit" 1 ++ encodeU32le value :=
    encodeTagged_ok_eq_one_fieldV1 "Op.Commit" (encodeU32le value) b henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.Commit" 1 ++ encodeU32le value) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le value ++ post)
    "Op.Commit" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_OpCommitV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B
    (pre.size + 4 + "Op.Commit".utf8ByteSize) pre (encodeU32le value ++ post)
    "Op.Commit" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 value nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Commit" 1).size)
    (pre ++ taggedHeaderBytesV1 "Op.Commit" 1) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_stateStoreV1 (stateId : StateIdV1) (value : ValueIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.stateStore stateId value) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.stateStore stateId value) nesting := by
  have hb : b = taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value :=
    encodeTagged_ok_eq_two_fieldsV1 "Op.StateStore" (encodeU32le stateId) (encodeU32le value) b henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId ++ encodeU32le value) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le stateId ++ encodeU32le value ++ post) "Op.StateStore" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpStateStoreV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.StateStore".utf8ByteSize)
    pre (encodeU32le stateId ++ encodeU32le value ++ post) "Op.StateStore" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 stateId nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size)
    (pre ++ taggedHeaderBytesV1 "Op.StateStore" 2) (encodeU32le value ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 value nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.StateStore" 2).size + (encodeU32le stateId).size)
    (pre ++ taggedHeaderBytesV1 "Op.StateStore" 2 ++ encodeU32le stateId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_fieldGetV1 (base : ValueIdV1) (fieldIndex : UInt32) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.fieldGet base fieldIndex) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.fieldGet base fieldIndex) nesting := by
  have hb : b = taggedHeaderBytesV1 "Op.FieldGet" 2 ++ encodeU32le base ++ encodeU32le fieldIndex :=
    encodeTagged_ok_eq_two_fieldsV1 "Op.FieldGet" (encodeU32le base) (encodeU32le fieldIndex) b henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.FieldGet" 2 ++ encodeU32le base ++ encodeU32le fieldIndex) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le base ++ encodeU32le fieldIndex ++ post) "Op.FieldGet" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpFieldGetV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.FieldGet".utf8ByteSize)
    pre (encodeU32le base ++ encodeU32le fieldIndex ++ post) "Op.FieldGet" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 base nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.FieldGet" 2).size)
    (pre ++ taggedHeaderBytesV1 "Op.FieldGet" 2) (encodeU32le fieldIndex ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 fieldIndex nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.FieldGet" 2).size + (encodeU32le base).size)
    (pre ++ taggedHeaderBytesV1 "Op.FieldGet" 2 ++ encodeU32le base) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_indexGetV1 (base : ValueIdV1) (index : ValueIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.indexGet base index) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.indexGet base index) nesting := by
  have hb : b = taggedHeaderBytesV1 "Op.IndexGet" 2 ++ encodeU32le base ++ encodeU32le index :=
    encodeTagged_ok_eq_two_fieldsV1 "Op.IndexGet" (encodeU32le base) (encodeU32le index) b henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.IndexGet" 2 ++ encodeU32le base ++ encodeU32le index) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le base ++ encodeU32le index ++ post) "Op.IndexGet" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpIndexGetV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.IndexGet".utf8ByteSize)
    pre (encodeU32le base ++ encodeU32le index ++ post) "Op.IndexGet" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 base nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.IndexGet" 2).size)
    (pre ++ taggedHeaderBytesV1 "Op.IndexGet" 2) (encodeU32le index ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 index nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.IndexGet" 2).size + (encodeU32le base).size)
    (pre ++ taggedHeaderBytesV1 "Op.IndexGet" 2 ++ encodeU32le base) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_checkedCastV1 (value : ValueIdV1) (toType : TypeIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.checkedCast value toType) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.checkedCast value toType) nesting := by
  have hb : b = taggedHeaderBytesV1 "Op.CheckedCast" 2 ++ encodeU32le value ++ encodeU32le toType :=
    encodeTagged_ok_eq_two_fieldsV1 "Op.CheckedCast" (encodeU32le value) (encodeU32le toType) b henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.CheckedCast" 2 ++ encodeU32le value ++ encodeU32le toType) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le value ++ encodeU32le toType ++ post) "Op.CheckedCast" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpCheckedCastV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.CheckedCast".utf8ByteSize)
    pre (encodeU32le value ++ encodeU32le toType ++ post) "Op.CheckedCast" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 value nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.CheckedCast" 2).size)
    (pre ++ taggedHeaderBytesV1 "Op.CheckedCast" 2) (encodeU32le toType ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 toType nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.CheckedCast" 2).size + (encodeU32le value).size)
    (pre ++ taggedHeaderBytesV1 "Op.CheckedCast" 2 ++ encodeU32le value) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_fieldSetV1 (base : ValueIdV1) (fieldIndex : UInt32) (value : ValueIdV1) (buf : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.fieldSet base fieldIndex value) = .ok buf) :
    FieldReadV1 decodeSemanticOpBodyV1 buf (.fieldSet base fieldIndex value) nesting := by
  have hb : buf = taggedHeaderBytesV1 "Op.FieldSet" 3 ++ encodeU32le base ++ encodeU32le fieldIndex ++
      encodeU32le value :=
    encodeTagged_ok_eq_three_fieldsV1 "Op.FieldSet" (encodeU32le base) (encodeU32le fieldIndex)
      (encodeU32le value) buf henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.FieldSet" 3 ++ encodeU32le base ++ encodeU32le fieldIndex ++
        encodeU32le value) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le base ++ encodeU32le fieldIndex ++ encodeU32le value ++ post) "Op.FieldSet" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpFieldSetV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.FieldSet".utf8ByteSize)
    pre (encodeU32le base ++ encodeU32le fieldIndex ++ encodeU32le value ++ post) "Op.FieldSet" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 base nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.FieldSet" 3).size)
    (pre ++ taggedHeaderBytesV1 "Op.FieldSet" 3) (encodeU32le fieldIndex ++ encodeU32le value ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 fieldIndex nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.FieldSet" 3).size + (encodeU32le base).size)
    (pre ++ taggedHeaderBytesV1 "Op.FieldSet" 3 ++ encodeU32le base) (encodeU32le value ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (fieldRead_u32V1 value nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.FieldSet" 3).size + (encodeU32le base).size +
      (encodeU32le fieldIndex).size)
    (pre ++ taggedHeaderBytesV1 "Op.FieldSet" 3 ++ encodeU32le base ++ encodeU32le fieldIndex) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_variantPayloadV1 (base : ValueIdV1) (variantIndex : UInt32) (payloadIndex : UInt32) (buf : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.variantPayload base variantIndex payloadIndex) = .ok buf) :
    FieldReadV1 decodeSemanticOpBodyV1 buf (.variantPayload base variantIndex payloadIndex) nesting := by
  have hb : buf = taggedHeaderBytesV1 "Op.VariantPayload" 3 ++ encodeU32le base ++ encodeU32le variantIndex ++
      encodeU32le payloadIndex :=
    encodeTagged_ok_eq_three_fieldsV1 "Op.VariantPayload" (encodeU32le base) (encodeU32le variantIndex)
      (encodeU32le payloadIndex) buf henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.VariantPayload" 3 ++ encodeU32le base ++ encodeU32le variantIndex ++
        encodeU32le payloadIndex) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le base ++ encodeU32le variantIndex ++ encodeU32le payloadIndex ++ post) "Op.VariantPayload" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpVariantPayloadV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.VariantPayload".utf8ByteSize)
    pre (encodeU32le base ++ encodeU32le variantIndex ++ encodeU32le payloadIndex ++ post) "Op.VariantPayload" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 base nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.VariantPayload" 3).size)
    (pre ++ taggedHeaderBytesV1 "Op.VariantPayload" 3) (encodeU32le variantIndex ++ encodeU32le payloadIndex ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 variantIndex nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.VariantPayload" 3).size + (encodeU32le base).size)
    (pre ++ taggedHeaderBytesV1 "Op.VariantPayload" 3 ++ encodeU32le base) (encodeU32le payloadIndex ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (fieldRead_u32V1 payloadIndex nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.VariantPayload" 3).size + (encodeU32le base).size +
      (encodeU32le variantIndex).size)
    (pre ++ taggedHeaderBytesV1 "Op.VariantPayload" 3 ++ encodeU32le base ++ encodeU32le variantIndex) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_indexSetV1 (base : ValueIdV1) (index : ValueIdV1) (value : ValueIdV1) (buf : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.indexSet base index value) = .ok buf) :
    FieldReadV1 decodeSemanticOpBodyV1 buf (.indexSet base index value) nesting := by
  have hb : buf = taggedHeaderBytesV1 "Op.IndexSet" 3 ++ encodeU32le base ++ encodeU32le index ++
      encodeU32le value :=
    encodeTagged_ok_eq_three_fieldsV1 "Op.IndexSet" (encodeU32le base) (encodeU32le index)
      (encodeU32le value) buf henc
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.IndexSet" 3 ++ encodeU32le base ++ encodeU32le index ++
        encodeU32le value) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le base ++ encodeU32le index ++ encodeU32le value ++ post) "Op.IndexSet" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpIndexSetV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.IndexSet".utf8ByteSize)
    pre (encodeU32le base ++ encodeU32le index ++ encodeU32le value ++ post) "Op.IndexSet" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 base nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.IndexSet" 3).size)
    (pre ++ taggedHeaderBytesV1 "Op.IndexSet" 3) (encodeU32le index ++ encodeU32le value ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 index nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.IndexSet" 3).size + (encodeU32le base).size)
    (pre ++ taggedHeaderBytesV1 "Op.IndexSet" 3 ++ encodeU32le base) (encodeU32le value ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (fieldRead_u32V1 value nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.IndexSet" 3).size + (encodeU32le base).size +
      (encodeU32le index).size)
    (pre ++ taggedHeaderBytesV1 "Op.IndexSet" 3 ++ encodeU32le base ++ encodeU32le index) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

/-! ### Remaining SemanticOp bodies -/

theorem fieldRead_semanticOpBody_literalV1 (typeId : TypeIdV1) (valueBytes : ByteArray)
    (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.literal typeId valueBytes) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.literal typeId valueBytes) nesting := by
  obtain ⟨vb, hvb, htag⟩ := except_bind_ok_inversionV1 (encodeByteArray valueBytes)
    (fun vb => encodeTagged "Op.Literal" #[encodeU32le typeId, vb]) b henc
  have hb := encodeTagged_ok_eq_two_fieldsV1 "Op.Literal" (encodeU32le typeId) vb b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId ++ vb) ++ post :=
    ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (encodeU32le typeId ++ vb ++ post)
    "Op.Literal" 2 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_OpLiteralV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.Literal".utf8ByteSize)
    pre (encodeU32le typeId ++ vb ++ post) "Op.Literal" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 typeId nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Literal" 2).size)
    (pre ++ taggedHeaderBytesV1 "Op.Literal" 2) (vb ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_byteArrayV1 valueBytes vb nesting hvb).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Literal" 2).size + (encodeU32le typeId).size)
    (pre ++ taggedHeaderBytesV1 "Op.Literal" 2 ++ encodeU32le typeId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_constructV1 (typeId : TypeIdV1) (constructorIndex : UInt32)
    (args : Array ValueIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.construct typeId constructorIndex args) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.construct typeId constructorIndex args)
      nesting := by
  obtain ⟨argsB, hargs, htag⟩ := except_bind_ok_inversionV1 (encodeValueIdArray args)
    (fun argsB => encodeTagged "Op.Construct"
      #[encodeU32le typeId, encodeU32le constructorIndex, argsB]) b henc
  have hb := encodeTagged_ok_eq_three_fieldsV1 "Op.Construct" (encodeU32le typeId)
    (encodeU32le constructorIndex) argsB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.Construct" 3 ++ encodeU32le typeId ++
        encodeU32le constructorIndex ++ argsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le typeId ++ encodeU32le constructorIndex ++ argsB ++ post)
    "Op.Construct" 3 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_OpConstructV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.Construct".utf8ByteSize)
    pre (encodeU32le typeId ++ encodeU32le constructorIndex ++ argsB ++ post)
    "Op.Construct" 3 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 typeId nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Construct" 3).size)
    (pre ++ taggedHeaderBytesV1 "Op.Construct" 3)
    (encodeU32le constructorIndex ++ argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 constructorIndex nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Construct" 3).size + (encodeU32le typeId).size)
    (pre ++ taggedHeaderBytesV1 "Op.Construct" 3 ++ encodeU32le typeId) (argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (fieldRead_u32ArrayV1 args argsB nesting hargs).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Construct" 3).size + (encodeU32le typeId).size +
      (encodeU32le constructorIndex).size)
    (pre ++ taggedHeaderBytesV1 "Op.Construct" 3 ++ encodeU32le typeId ++
      encodeU32le constructorIndex) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_unaryV1 (op : UnaryOpV1) (operand : ValueIdV1)
    (b : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.unary op operand) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.unary op operand) nesting := by
  obtain ⟨opB, hop, htag⟩ := except_bind_ok_inversionV1 (encodeUnaryOpV1 op)
    (fun opB => encodeTagged "Op.Unary" #[opB, encodeU32le operand]) b henc
  have hb := encodeTagged_ok_eq_two_fieldsV1 "Op.Unary" opB (encodeU32le operand) b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.Unary" 2 ++ opB ++ encodeU32le operand) ++ post :=
    ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (opB ++ encodeU32le operand ++ post)
    "Op.Unary" 2 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_OpUnaryV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.Unary".utf8ByteSize)
    pre (opB ++ encodeU32le operand ++ post) "Op.Unary" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_unaryOpV1 op opB nesting hdepth hop).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Unary" 2).size)
    (pre ++ taggedHeaderBytesV1 "Op.Unary" 2) (encodeU32le operand ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 operand nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Unary" 2).size + opB.size)
    (pre ++ taggedHeaderBytesV1 "Op.Unary" 2 ++ opB) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_binaryV1 (op : BinaryOpV1) (lhs rhs : ValueIdV1)
    (b : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.binary op lhs rhs) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.binary op lhs rhs) nesting := by
  obtain ⟨opB, hop, htag⟩ := except_bind_ok_inversionV1 (encodeBinaryOpV1 op)
    (fun opB => encodeTagged "Op.Binary" #[opB, encodeU32le lhs, encodeU32le rhs]) b henc
  have hb := encodeTagged_ok_eq_three_fieldsV1 "Op.Binary" opB (encodeU32le lhs)
    (encodeU32le rhs) b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs ++
        encodeU32le rhs) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (opB ++ encodeU32le lhs ++ encodeU32le rhs ++ post) "Op.Binary" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpBinaryV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.Binary".utf8ByteSize)
    pre (opB ++ encodeU32le lhs ++ encodeU32le rhs ++ post) "Op.Binary" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_binaryOpV1 op opB nesting hdepth hop).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Binary" 3).size)
    (pre ++ taggedHeaderBytesV1 "Op.Binary" 3) (encodeU32le lhs ++ encodeU32le rhs ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 lhs nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size)
    (pre ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB) (encodeU32le rhs ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (fieldRead_u32V1 rhs nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Binary" 3).size + opB.size +
      (encodeU32le lhs).size)
    (pre ++ taggedHeaderBytesV1 "Op.Binary" 3 ++ opB ++ encodeU32le lhs) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_pureCallV1 (callableId : CallableIdV1)
    (args : Array ValueIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.pureCall callableId args) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.pureCall callableId args) nesting := by
  obtain ⟨argsB, hargs, htag⟩ := except_bind_ok_inversionV1 (encodeValueIdArray args)
    (fun argsB => encodeTagged "Op.PureCall" #[encodeU32le callableId, argsB]) b henc
  have hb := encodeTagged_ok_eq_two_fieldsV1 "Op.PureCall" (encodeU32le callableId)
    argsB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.PureCall" 2 ++ encodeU32le callableId ++ argsB) ++
        post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le callableId ++ argsB ++ post) "Op.PureCall" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpPureCallV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.PureCall".utf8ByteSize)
    pre (encodeU32le callableId ++ argsB ++ post) "Op.PureCall" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 callableId nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.PureCall" 2).size)
    (pre ++ taggedHeaderBytesV1 "Op.PureCall" 2) (argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32ArrayV1 args argsB nesting hargs).read B
    (pre.size + (taggedHeaderBytesV1 "Op.PureCall" 2).size + (encodeU32le callableId).size)
    (pre ++ taggedHeaderBytesV1 "Op.PureCall" 2 ++ encodeU32le callableId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_contextReadV1 (key : SchemaId) (b : ByteArray)
    (nesting : Nat) (henc : encodeSemanticOpV1 (.contextRead key) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.contextRead key) nesting := by
  obtain ⟨keyB, hkey, htag⟩ := except_bind_ok_inversionV1 (encodeSchemaId key)
    (fun keyB => encodeTagged "Op.ContextRead" #[keyB]) b henc
  have hb := encodeTagged_ok_eq_one_fieldV1 "Op.ContextRead" keyB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.ContextRead" 1 ++ keyB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (keyB ++ post)
    "Op.ContextRead" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_OpContextReadV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B
    (pre.size + 4 + "Op.ContextRead".utf8ByteSize) pre (keyB ++ post)
    "Op.ContextRead" 1 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_schemaIdV1 key keyB nesting hkey).read B
    (pre.size + (taggedHeaderBytesV1 "Op.ContextRead" 1).size)
    (pre ++ taggedHeaderBytesV1 "Op.ContextRead" 1) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_envReadV1 (key : EnvReadKeyV1) (args : Array ValueIdV1)
    (b : ByteArray) (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.envRead key args) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.envRead key args) nesting := by
  obtain ⟨keyB, hkey, hrest⟩ := except_bind_ok_inversionV1 (encodeEnvReadKeyV1 key)
    (fun keyB => encodeValueIdArray args >>= fun argsB =>
      encodeTagged "Op.EnvRead" #[keyB, argsB]) b henc
  obtain ⟨argsB, hargs, htag⟩ := except_bind_ok_inversionV1 (encodeValueIdArray args)
    (fun argsB => encodeTagged "Op.EnvRead" #[keyB, argsB]) b hrest
  have hb := encodeTagged_ok_eq_two_fieldsV1 "Op.EnvRead" keyB argsB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.EnvRead" 2 ++ keyB ++ argsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre (keyB ++ argsB ++ post)
    "Op.EnvRead" 2 nesting (by rw [hB]; simp [ByteArray.append_assoc]) rfl
    (by decide) (by decide) (by decide) asciiTagBytes_OpEnvReadV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.EnvRead".utf8ByteSize)
    pre (keyB ++ argsB ++ post) "Op.EnvRead" 2 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_envReadKeyV1 key keyB nesting hdepth hkey).read B
    (pre.size + (taggedHeaderBytesV1 "Op.EnvRead" 2).size)
    (pre ++ taggedHeaderBytesV1 "Op.EnvRead" 2) (argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32ArrayV1 args argsB nesting hargs).read B
    (pre.size + (taggedHeaderBytesV1 "Op.EnvRead" 2).size + keyB.size)
    (pre ++ taggedHeaderBytesV1 "Op.EnvRead" 2 ++ keyB) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, Bind.bind, Except.bind, Pure.pure,
    Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_assertV1 (condition : ValueIdV1)
    (errorId : Option ErrorIdV1) (args : Array ValueIdV1) (b : ByteArray)
    (nesting : Nat) (henc : encodeSemanticOpV1 (.assert_ condition errorId args) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.assert_ condition errorId args) nesting := by
  obtain ⟨errB, herr, hrest⟩ :=
    except_bind_ok_inversionV1 (encodeOption (fun id => pure (encodeU32le id)) errorId)
      (fun errB => encodeValueIdArray args >>= fun argsB =>
        encodeTagged "Op.Assert" #[encodeU32le condition, errB, argsB]) b henc
  obtain ⟨argsB, hargs, htag⟩ := except_bind_ok_inversionV1 (encodeValueIdArray args)
    (fun argsB => encodeTagged "Op.Assert" #[encodeU32le condition, errB, argsB]) b hrest
  have hb := encodeTagged_ok_eq_three_fieldsV1 "Op.Assert" (encodeU32le condition) errB
    argsB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.Assert" 3 ++ encodeU32le condition ++ errB ++
        argsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le condition ++ errB ++ argsB ++ post) "Op.Assert" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpAssertV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.Assert".utf8ByteSize)
    pre (encodeU32le condition ++ errB ++ argsB ++ post) "Op.Assert" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 condition nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Assert" 3).size)
    (pre ++ taggedHeaderBytesV1 "Op.Assert" 3) (errB ++ argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_option_pureV1 encodeU32le decodeU32le errorId errB nesting
      herr (fun x => fieldRead_u32V1 x nesting)).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Assert" 3).size + (encodeU32le condition).size)
    (pre ++ taggedHeaderBytesV1 "Op.Assert" 3 ++ encodeU32le condition) (argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (fieldRead_u32ArrayV1 args argsB nesting hargs).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Assert" 3).size + (encodeU32le condition).size +
      errB.size)
    (pre ++ taggedHeaderBytesV1 "Op.Assert" 3 ++ encodeU32le condition ++ errB) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_emitV1 (effectId : EffectIdV1) (eventId : EventIdV1)
    (args : Array ValueIdV1) (b : ByteArray) (nesting : Nat)
    (henc : encodeSemanticOpV1 (.emit effectId eventId args) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.emit effectId eventId args) nesting := by
  obtain ⟨argsB, hargs, htag⟩ := except_bind_ok_inversionV1 (encodeValueIdArray args)
    (fun argsB => encodeTagged "Op.Emit"
      #[encodeU32le effectId, encodeU32le eventId, argsB]) b henc
  have hb := encodeTagged_ok_eq_three_fieldsV1 "Op.Emit" (encodeU32le effectId)
    (encodeU32le eventId) argsB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.Emit" 3 ++ encodeU32le effectId ++
        encodeU32le eventId ++ argsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le effectId ++ encodeU32le eventId ++ argsB ++ post) "Op.Emit" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpEmitV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B (pre.size + 4 + "Op.Emit".utf8ByteSize)
    pre (encodeU32le effectId ++ encodeU32le eventId ++ argsB ++ post) "Op.Emit" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 effectId nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Emit" 3).size)
    (pre ++ taggedHeaderBytesV1 "Op.Emit" 3) (encodeU32le eventId ++ argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (fieldRead_u32V1 eventId nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Emit" 3).size + (encodeU32le effectId).size)
    (pre ++ taggedHeaderBytesV1 "Op.Emit" 3 ++ encodeU32le effectId) (argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h4 := (fieldRead_u32ArrayV1 args argsB nesting hargs).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Emit" 3).size + (encodeU32le effectId).size +
      (encodeU32le eventId).size)
    (pre ++ taggedHeaderBytesV1 "Op.Emit" 3 ++ encodeU32le effectId ++
      encodeU32le eventId) post
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_externalCallV1 (effectId : EffectIdV1)
    (callee : QualifiedName) (args : Array ValueIdV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.externalCall effectId callee args) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.externalCall effectId callee args)
      nesting := by
  obtain ⟨calleeB, hcallee, hrest⟩ := except_bind_ok_inversionV1 (encodeQualifiedName callee)
    (fun calleeB => encodeValueIdArray args >>= fun argsB =>
      encodeTagged "Op.ExternalCall" #[encodeU32le effectId, calleeB, argsB]) b henc
  obtain ⟨argsB, hargs, htag⟩ := except_bind_ok_inversionV1 (encodeValueIdArray args)
    (fun argsB => encodeTagged "Op.ExternalCall" #[encodeU32le effectId, calleeB, argsB])
    b hrest
  have hb := encodeTagged_ok_eq_three_fieldsV1 "Op.ExternalCall" (encodeU32le effectId)
    calleeB argsB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.ExternalCall" 3 ++ encodeU32le effectId ++
        calleeB ++ argsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le effectId ++ calleeB ++ argsB ++ post) "Op.ExternalCall" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpExternalCallV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B
    (pre.size + 4 + "Op.ExternalCall".utf8ByteSize) pre
    (encodeU32le effectId ++ calleeB ++ argsB ++ post) "Op.ExternalCall" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 effectId nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.ExternalCall" 3).size)
    (pre ++ taggedHeaderBytesV1 "Op.ExternalCall" 3) (calleeB ++ argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (FieldReadV1.ofExactAt
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_qualifiedName callee) hdepth) hcallee).read B
    (pre.size + (taggedHeaderBytesV1 "Op.ExternalCall" 3).size +
      (encodeU32le effectId).size)
    (pre ++ taggedHeaderBytesV1 "Op.ExternalCall" 3 ++ encodeU32le effectId)
    (argsB ++ post) (by rw [hB]; simp [ByteArray.append_assoc])
    (by simp [ByteArray.size_append])
  have h4 := (fieldRead_u32ArrayV1 args argsB nesting hargs).read B
    (pre.size + (taggedHeaderBytesV1 "Op.ExternalCall" 3).size +
      (encodeU32le effectId).size + calleeB.size)
    (pre ++ taggedHeaderBytesV1 "Op.ExternalCall" 3 ++ encodeU32le effectId ++ calleeB)
    post (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

theorem fieldRead_semanticOpBody_scheduleV1 (effectId : EffectIdV1)
    (callee : QualifiedName) (args : Array ValueIdV1) (b : ByteArray)
    (nesting : Nat) (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 (.schedule effectId callee args) = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b (.schedule effectId callee args) nesting := by
  obtain ⟨calleeB, hcallee, hrest⟩ := except_bind_ok_inversionV1 (encodeQualifiedName callee)
    (fun calleeB => encodeValueIdArray args >>= fun argsB =>
      encodeTagged "Op.Schedule" #[encodeU32le effectId, calleeB, argsB]) b henc
  obtain ⟨argsB, hargs, htag⟩ := except_bind_ok_inversionV1 (encodeValueIdArray args)
    (fun argsB => encodeTagged "Op.Schedule" #[encodeU32le effectId, calleeB, argsB])
    b hrest
  have hb := encodeTagged_ok_eq_three_fieldsV1 "Op.Schedule" (encodeU32le effectId)
    calleeB argsB b htag
  subst hb
  intro pre post
  obtain ⟨B, hB⟩ : ∃ B, B =
      pre ++ (taggedHeaderBytesV1 "Op.Schedule" 3 ++ encodeU32le effectId ++
        calleeB ++ argsB) ++ post := ⟨_, rfl⟩
  rw [← hB]
  have h0 := decodeTag_header_readV1 B pre.size pre
    (encodeU32le effectId ++ calleeB ++ argsB ++ post) "Op.Schedule" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide) (by decide) (by decide)
    asciiTagBytes_OpScheduleV1 (by decide)
  have h1 := decodeFieldCount_header_readV1 B
    (pre.size + 4 + "Op.Schedule".utf8ByteSize) pre
    (encodeU32le effectId ++ calleeB ++ argsB ++ post) "Op.Schedule" 3 nesting
    (by rw [hB]; simp [ByteArray.append_assoc]) rfl (by decide)
  have h2 := (fieldRead_u32V1 effectId nesting).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Schedule" 3).size)
    (pre ++ taggedHeaderBytesV1 "Op.Schedule" 3) (calleeB ++ argsB ++ post)
    (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  have h3 := (FieldReadV1.ofExactAt
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_qualifiedName callee) hdepth) hcallee).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Schedule" 3).size +
      (encodeU32le effectId).size)
    (pre ++ taggedHeaderBytesV1 "Op.Schedule" 3 ++ encodeU32le effectId)
    (argsB ++ post) (by rw [hB]; simp [ByteArray.append_assoc])
    (by simp [ByteArray.size_append])
  have h4 := (fieldRead_u32ArrayV1 args argsB nesting hargs).read B
    (pre.size + (taggedHeaderBytesV1 "Op.Schedule" 3).size +
      (encodeU32le effectId).size + calleeB.size)
    (pre ++ taggedHeaderBytesV1 "Op.Schedule" 3 ++ encodeU32le effectId ++ calleeB)
    post (by rw [hB]; simp [ByteArray.append_assoc]) (by simp [ByteArray.size_append])
  simp [toUTF8_size_eq_utf8ByteSize] at h0
  simp only [toUTF8_size_eq_utf8ByteSize, decodeSemanticOpBodyV1, h0, h1, h2, h3, h4, Bind.bind, Except.bind,
    Pure.pure, Except.pure]
  try simp [ByteArray.size_append, Nat.add_assoc]

/-! ### Dispatcher -/

theorem fieldRead_semanticOpBodyV1 (op : SemanticOpV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting < maxNesting)
    (henc : encodeSemanticOpV1 op = .ok b) :
    FieldReadV1 decodeSemanticOpBodyV1 b op nesting := by
  cases op with
  | literal typeId valueBytes =>
      exact fieldRead_semanticOpBody_literalV1 typeId valueBytes b nesting henc
  | constant constantId =>
      exact fieldRead_semanticOpBody_constantV1 constantId b nesting henc
  | stateLoad stateId =>
      exact fieldRead_semanticOpBody_stateLoadV1 stateId b nesting henc
  | stateStore stateId value =>
      exact fieldRead_semanticOpBody_stateStoreV1 stateId value b nesting henc
  | construct typeId constructorIndex args =>
      exact fieldRead_semanticOpBody_constructV1 typeId constructorIndex args b nesting henc
  | fieldGet base fieldIndex =>
      exact fieldRead_semanticOpBody_fieldGetV1 base fieldIndex b nesting henc
  | fieldSet base fieldIndex value =>
      exact fieldRead_semanticOpBody_fieldSetV1 base fieldIndex value b nesting henc
  | variantTag base =>
      exact fieldRead_semanticOpBody_variantTagV1 base b nesting henc
  | variantPayload base variantIndex payloadIndex =>
      exact fieldRead_semanticOpBody_variantPayloadV1 base variantIndex payloadIndex b
        nesting henc
  | indexGet base index =>
      exact fieldRead_semanticOpBody_indexGetV1 base index b nesting henc
  | indexSet base index value =>
      exact fieldRead_semanticOpBody_indexSetV1 base index value b nesting henc
  | checkedCast value toType =>
      exact fieldRead_semanticOpBody_checkedCastV1 value toType b nesting henc
  | unary uop operand =>
      exact fieldRead_semanticOpBody_unaryV1 uop operand b nesting hdepth henc
  | binary bop lhs rhs =>
      exact fieldRead_semanticOpBody_binaryV1 bop lhs rhs b nesting hdepth henc
  | pureCall callableId args =>
      exact fieldRead_semanticOpBody_pureCallV1 callableId args b nesting henc
  | contextRead key =>
      exact fieldRead_semanticOpBody_contextReadV1 key b nesting henc
  | envRead key args =>
      exact fieldRead_semanticOpBody_envReadV1 key args b nesting hdepth henc
  | commit value =>
      exact fieldRead_semanticOpBody_commitV1 value b nesting henc
  | assert_ condition errorId args =>
      exact fieldRead_semanticOpBody_assertV1 condition errorId args b nesting henc
  | emit effectId eventId args =>
      exact fieldRead_semanticOpBody_emitV1 effectId eventId args b nesting henc
  | externalCall effectId callee args =>
      exact fieldRead_semanticOpBody_externalCallV1 effectId callee args b nesting
        hdepth henc
  | schedule effectId callee args =>
      exact fieldRead_semanticOpBody_scheduleV1 effectId callee args b nesting
        hdepth henc

/-- Generic encode→decode invertibility of the production `SemanticOp` codec. -/
theorem fieldRead_semanticOpV1 (op : SemanticOpV1) (b : ByteArray) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting)
    (henc : encodeSemanticOpV1 op = .ok b) :
    FieldReadV1 decodeSemanticOpV1 b op nesting := by
  apply fieldRead_withTaggedNestingV1 _ _ _ _ (Nat.lt_of_succ_lt hdepth)
  exact fieldRead_semanticOpBodyV1 op b (nesting + 1) (by omega) henc

theorem exactMidOffsetInvertAt_semanticOpV1 (op : SemanticOpV1) (nesting : Nat)
    (hdepth : nesting + 1 < maxNesting) :
    ExactMidOffsetInvertAtV1 encodeSemanticOpV1 decodeSemanticOpV1 op nesting :=
  exactMidOffsetInvertAt_of_fieldReadV1
    (fun b henc => fieldRead_semanticOpV1 op b nesting hdepth henc)

end ProofForgeV2.Semantic.WireV1
