/-
  Tests.Semantic.SimpleClosureDecodeCallableV1 — focused suite for the
  callable-leaf B-SC-DEC module.

  Kernel:
    * ValueDef {0,0} encode→decode mid-offset (no free decode premises)
    * Op.Literal / Instruction / Term.Return / Block mid-offset
    * view / inv Callable mid-offset under Legal (no free hdecode)
    * two-callable array mid-offset under Legal
    * demo Legal encode of view/inv callables + two-callable array
    * public of_legal theorems for view/inv/array

  Runtime:
    * Unicode-shaped params materialize (2 callables)
    * demo encode + mid-offset decode success for view/inv/array

  Not registered in lakefile (lane allowlist: new files only).
  No axiom / sorry / native_decide / Tests FQN hardcode in production module.
-/
import ProofForgeV2.Semantic.SimpleClosureDecodeCallableV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Common

namespace Tests.Semantic.SimpleClosureDecodeCallableV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.SimpleClosureDecodeCallableV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-! ### Kernel: ValueDef leaf -/

theorem valueDef_encode_ok :
    encodeValueDefV1 { valueId := 0, typeId := 0 } = .ok valueDef00BytesV1 :=
  encode_valueDef00

theorem valueDef_decode_mid (left right : ByteArray) :
    decodeValueDefV1 ⟨left ++ valueDef00BytesV1 ++ right, left.size, 1⟩ =
      .ok ({ valueId := 0, typeId := 0 },
        ⟨left ++ valueDef00BytesV1 ++ right,
          left.size + valueDef00BytesV1.size, 1⟩) :=
  decode_valueDef00_mid left right 1 (by decide)

theorem valueDef_of_encode (left right : ByteArray) (b : ByteArray)
    (h : encodeValueDefV1 { valueId := 0, typeId := 0 } = .ok b) :
    decodeValueDefV1 ⟨left ++ b ++ right, left.size, 1⟩ =
      .ok ({ valueId := 0, typeId := 0 },
        ⟨left ++ b ++ right, left.size + b.size, 1⟩) :=
  decodeValueDefV1_simpleClosure00_of_encode left right b 1 h (by decide)

/-! ### Kernel: Op / Instruction / Term / Block mid-offset -/

theorem opLiteral_decode_mid (left right : ByteArray) :
    decodeSemanticOpV1 ⟨left ++ opLiteralTrueBytesV1 ++ right, left.size, 1⟩ =
      .ok (.literal 0 (encodeU8 1),
        ⟨left ++ opLiteralTrueBytesV1 ++ right,
          left.size + opLiteralTrueBytesV1.size, 1⟩) :=
  decode_opLiteralTrue_mid left right 1 (by decide)

theorem instruction_decode_mid (left right : ByteArray) :
    decodeInstructionV1 ⟨left ++ litTrueInstructionBytesV1 ++ right, left.size, 1⟩ =
      .ok (simpleClosureLitTrueV1,
        ⟨left ++ litTrueInstructionBytesV1 ++ right,
          left.size + litTrueInstructionBytesV1.size, 1⟩) :=
  decode_litTrueInstruction_mid left right 1 (by decide)

theorem termReturn_decode_mid (left right : ByteArray) :
    decodeTerminatorV1 ⟨left ++ termReturn0BytesV1 ++ right, left.size, 1⟩ =
      .ok (.return_ (some 0),
        ⟨left ++ termReturn0BytesV1 ++ right,
          left.size + termReturn0BytesV1.size, 1⟩) :=
  decode_termReturn0_mid left right 1 (by decide)

theorem block_decode_mid (left right : ByteArray) :
    decodeBlockV1 ⟨left ++ simpleClosureBlockBytesV1 ++ right, left.size, 1⟩ =
      .ok (simpleClosureBlockV1,
        ⟨left ++ simpleClosureBlockBytesV1 ++ right,
          left.size + simpleClosureBlockBytesV1.size, 1⟩) :=
  decode_simpleClosureBlock_mid left right 1 (by decide)

/-! ### Kernel: demo Legal + encode callables -/

theorem demo_legal : SimpleClosureParamsLegalV1 demoParamsV1 :=
  demoParams_legal

theorem demo_encode_view :
    encodeCallableV1 (simpleClosureViewCallableV1 demoParamsV1.viewName) =
      .ok (viewCallableBytesV1 demoParamsV1.viewName) :=
  encode_viewCallable_of_legal demoParamsV1 demoParams_legal

theorem demo_encode_inv :
    encodeCallableV1 (simpleClosureInvCallableV1 demoParamsV1.invName) =
      .ok (invCallableBytesV1 demoParamsV1.invName) :=
  encode_invCallable_of_legal demoParamsV1 demoParams_legal

theorem demo_encode_callables :
    encodeArray encodeCallableV1
        #[simpleClosureViewCallableV1 demoParamsV1.viewName,
          simpleClosureInvCallableV1 demoParamsV1.invName] =
      .ok (callablesArrayBytesV1 demoParamsV1) :=
  encode_callablesArray_of_legal demoParamsV1 demoParams_legal

theorem demo_encode_block :
    encodeBlockV1 simpleClosureBlockV1 =
      .ok
        (taggedBytesV1 "Block"
          #[encodeU32le 0, encodeU32le 0,
            encodeU32le 1 ++
              taggedBytesV1 "Instruction"
                #[encodeU8 1 ++ valueDef00BytesV1,
                  taggedBytesV1 "Op.Literal"
                    #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]],
            taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]]) :=
  encode_simpleClosureBlock

theorem demo_encode_instruction :
    encodeInstructionV1 simpleClosureLitTrueV1 =
      .ok
        (taggedBytesV1 "Instruction"
          #[encodeU8 1 ++ valueDef00BytesV1,
            taggedBytesV1 "Op.Literal"
              #[encodeU32le 0, encodeU32le 1 ++ encodeU8 1]]) :=
  encode_litTrueInstruction

theorem demo_encode_return :
    encodeTerminatorV1 (.return_ (some 0)) =
      .ok (taggedBytesV1 "Term.Return" #[encodeU8 1 ++ encodeU32le 0]) :=
  encode_termReturn0

/-! ### Kernel: public of_legal mid-offset decode (no free hdecode) -/

theorem demo_decode_view_of_legal (left right : ByteArray) :
    decodeCallableV1
        ⟨left ++ viewCallableBytesV1 demoParamsV1.viewName ++ right,
          left.size, 1⟩ =
      .ok (simpleClosureViewCallableV1 demoParamsV1.viewName,
        ⟨left ++ viewCallableBytesV1 demoParamsV1.viewName ++ right,
          left.size + (viewCallableBytesV1 demoParamsV1.viewName).size, 1⟩) :=
  decodeCallableV1_simpleClosureView_of_legal left right demoParamsV1
    demoParams_legal 1 (by decide)

theorem demo_decode_inv_of_legal (left right : ByteArray) :
    decodeCallableV1
        ⟨left ++ invCallableBytesV1 demoParamsV1.invName ++ right,
          left.size, 1⟩ =
      .ok (simpleClosureInvCallableV1 demoParamsV1.invName,
        ⟨left ++ invCallableBytesV1 demoParamsV1.invName ++ right,
          left.size + (invCallableBytesV1 demoParamsV1.invName).size, 1⟩) :=
  decodeCallableV1_simpleClosureInv_of_legal left right demoParamsV1
    demoParams_legal 1 (by decide)

theorem demo_decode_callables_of_legal (left right : ByteArray) :
    decodeArray maxTableElements decodeCallableV1
        ⟨left ++ callablesArrayBytesV1 demoParamsV1 ++ right, left.size, 1⟩ =
      .ok (#[simpleClosureViewCallableV1 demoParamsV1.viewName,
            simpleClosureInvCallableV1 demoParamsV1.invName],
        ⟨left ++ callablesArrayBytesV1 demoParamsV1 ++ right,
          left.size + (callablesArrayBytesV1 demoParamsV1).size, 1⟩) :=
  decodeCallableArrayV1_simpleClosure_of_legal left right demoParamsV1
    demoParams_legal 1 (by decide)

/-! ### Runtime: demo + unicode materialize + mid-offset decode -/

def run : IO Unit := do
  -- ValueDef encode/decode round-trip at mid-offset (runtime)
  let left := ByteArray.mk #[1, 2, 3]
  let right := ByteArray.mk #[9]
  match encodeValueDefV1 { valueId := 0, typeId := 0 } with
  | .error _ => throw <| IO.userError "valueDef encode failed"
  | .ok b =>
      match decodeValueDefV1 ⟨left ++ b ++ right, left.size, 1⟩ with
      | .ok (v, c) =>
          expect (v.valueId == 0) "valueId"
          expect (v.typeId == 0) "typeId"
          expect (c.offset == left.size + b.size) "valueDef cursor"
      | .error _ => throw <| IO.userError "valueDef decode failed"

  -- Demo encode view/inv/array
  match encodeCallableV1 (simpleClosureViewCallableV1 demoParamsV1.viewName) with
  | .ok b =>
      expect (b == viewCallableBytesV1 demoParamsV1.viewName) "view encode bytes"
  | .error _ => throw <| IO.userError "view encode failed"
  match encodeCallableV1 (simpleClosureInvCallableV1 demoParamsV1.invName) with
  | .ok b =>
      expect (b == invCallableBytesV1 demoParamsV1.invName) "inv encode bytes"
  | .error _ => throw <| IO.userError "inv encode failed"
  match encodeArray encodeCallableV1
      #[simpleClosureViewCallableV1 demoParamsV1.viewName,
        simpleClosureInvCallableV1 demoParamsV1.invName] with
  | .ok b =>
      expect (b == callablesArrayBytesV1 demoParamsV1) "callables encode bytes"
      expect (b.size > 8) "callables non-empty"
  | .error _ => throw <| IO.userError "callables encode failed"

  -- Demo mid-offset decode view/inv/array (production path)
  match decodeCallableV1
      ⟨left ++ viewCallableBytesV1 demoParamsV1.viewName ++ right, left.size, 1⟩ with
  | .ok (c, cur) =>
      expect (c.kind == .view) "demo view kind"
      expect (c.name == some demoParamsV1.viewName) "demo view name"
      expect (cur.offset == left.size + (viewCallableBytesV1 demoParamsV1.viewName).size)
        "demo view cursor"
  | .error e => throw <| IO.userError s!"demo view decode failed: {repr e}"
  match decodeCallableV1
      ⟨left ++ invCallableBytesV1 demoParamsV1.invName ++ right, left.size, 1⟩ with
  | .ok (c, cur) =>
      expect (c.kind == .invariant) "demo inv kind"
      expect (c.name == some demoParamsV1.invName) "demo inv name"
      expect (c.invariantSteps == some 3) "demo inv steps"
      expect (cur.offset == left.size + (invCallableBytesV1 demoParamsV1.invName).size)
        "demo inv cursor"
  | .error e => throw <| IO.userError s!"demo inv decode failed: {repr e}"
  match decodeArray maxTableElements decodeCallableV1
      ⟨left ++ callablesArrayBytesV1 demoParamsV1 ++ right, left.size, 1⟩ with
  | .ok (arr, cur) =>
      expect (arr.size == 2) "demo array size"
      expect (cur.offset == left.size + (callablesArrayBytesV1 demoParamsV1).size)
        "demo array cursor"
      match arr[0]?, arr[1]? with
      | some c0, some c1 =>
          expect (c0.kind == .view) "demo arr view"
          expect (c1.kind == .invariant) "demo arr inv"
          expect (c0.name == some "alive") "demo arr view name"
          expect (c1.name == some "safe") "demo arr inv name"
      | _, _ => throw <| IO.userError "demo array missing"
  | .error e => throw <| IO.userError s!"demo array decode failed: {repr e}"

  -- Unicode materialize shape (runtime identifier surface)
  let data := materializeSimpleClosureDataV1 unicodeLegalParamsV1
  expect (data.callables.size == 2) "unicode callables size"
  match data.callables[0]?, data.callables[1]? with
  | some c0, some c1 =>
      expect (c0.kind == .view) "unicode view kind"
      expect (c1.kind == .invariant) "unicode inv kind"
      expect (c1.invariantSteps == some 3) "unicode inv steps"
      expect (c0.name == some unicodeLegalParamsV1.viewName) "unicode view name"
      expect (c1.name == some unicodeLegalParamsV1.invName) "unicode inv name"
  | _, _ => throw <| IO.userError "unicode callables missing"

  -- Unicode Legal names: identifier gate + encode + mid-offset decode
  expect (validateIdentifierComponent unicodeLegalParamsV1.viewName matches .ok _)
    "unicode view identifier"
  expect (validateIdentifierComponent unicodeLegalParamsV1.invName matches .ok _)
    "unicode inv identifier"
  match encodeCallableV1 (simpleClosureViewCallableV1 unicodeLegalParamsV1.viewName) with
  | .error e => throw <| IO.userError s!"unicode view encode failed: {repr e}"
  | .ok vb =>
      match decodeCallableV1 ⟨left ++ vb ++ right, left.size, 1⟩ with
      | .ok (c, _) =>
          expect (c.kind == .view) "unicode view decode kind"
          expect (c.name == some unicodeLegalParamsV1.viewName) "unicode view decode name"
      | .error e => throw <| IO.userError s!"unicode view decode failed: {repr e}"
  match encodeCallableV1 (simpleClosureInvCallableV1 unicodeLegalParamsV1.invName) with
  | .error e => throw <| IO.userError s!"unicode inv encode failed: {repr e}"
  | .ok ib =>
      match decodeCallableV1 ⟨left ++ ib ++ right, left.size, 1⟩ with
      | .ok (c, _) =>
          expect (c.kind == .invariant) "unicode inv decode kind"
          expect (c.name == some unicodeLegalParamsV1.invName) "unicode inv decode name"
          expect (c.invariantSteps == some 3) "unicode inv decode steps"
      | .error e => throw <| IO.userError s!"unicode inv decode failed: {repr e}"

  IO.println "SimpleClosureDecodeCallableV1: ok"

end Tests.Semantic.SimpleClosureDecodeCallableV1

def main : IO Unit :=
  Tests.Semantic.SimpleClosureDecodeCallableV1.run
