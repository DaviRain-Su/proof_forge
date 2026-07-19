import ProofForgeV2.Source.WireCodecV1

namespace Tests.Language.SourceWireCodecV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.WireCodecV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def lowerHexDigit (v : Nat) : Char :=
  if v < 10 then Char.ofNat ('0'.toNat + v)
  else Char.ofNat ('a'.toNat + v - 10)

private def bytesHex (bytes : ByteArray) : String :=
  bytes.foldl (fun o b =>
    let v := b.toNat
    (o.push (lowerHexDigit (v / 16))).push (lowerHexDigit (v % 16))) ""

private def expectBytes (label want : String) (bytes : ByteArray) : IO Unit :=
  expect (bytesHex bytes == want) s!"{label}: got {bytesHex bytes}"

private def expectOk (label want : String) (r : Except String ByteArray) : IO Unit :=
  match r with
  | .ok b => expectBytes label want b
  | .error e => throw <| IO.userError s!"{label}: unexpected error {e}"

private def expectErr (label : String) (r : Except String α) : IO Unit :=
  match r with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def liftOk (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok value => pure value
  | .error e => throw <| IO.userError s!"{label}: unexpected error {e}"

private def encodeU8Ok (value : UInt8) : Except String ByteArray :=
  .ok (encodeU8 value)

private def encodeU8Fail (_ : UInt8) : Except String ByteArray :=
  .error "child-failed"

/-- D1-PA-91 RED: production WireCodecV1 missing → focused build fails; goldens fixed. -/
def run : IO Unit := do
  expectBytes "u8_0" "00" (encodeU8 0)
  expectBytes "u8_max" "ff" (encodeU8 255)
  expectBytes "u16_0x0102" "0201" (encodeU16le 0x0102)
  expectBytes "u32_0x01020304" "04030201" (encodeU32le 0x01020304)
  expectOk "u256_0"
    "0000000000000000000000000000000000000000000000000000000000000000"
    (encodeU256le 0)
  expectOk "u256_max"
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    (encodeU256le (2 ^ 256 - 1))
  expectErr "u256_overflow" (encodeU256le (2 ^ 256))
  expectBytes "bool_f" "00" (encodeBool false)
  expectBytes "bool_t" "01" (encodeBool true)
  expectOk "opt_none" "00" (encodeOption encodeU8Ok none)
  expectOk "opt_some_u8_7" "0107" (encodeOption encodeU8Ok (some 7))
  expectErr "opt_child_error" (encodeOption encodeU8Fail (some 7))
  expectOk "arr_empty" "00000000" (encodeArray encodeU8Ok #[])
  expectOk "arr_u8_1_2" "020000000102" (encodeArray encodeU8Ok #[1, 2])
  expectErr "arr_child_error" (encodeArray encodeU8Fail #[1, 2])
  expectOk "ident_Foo" "03000000466f6f" (encodeIdent "Foo")
  expectOk "ident_alpha" "02000000ceb1" (encodeIdent "α")
  expectOk "str_hi" "020000006869" (encodeString "hi")
  expectOk "str_cafe" "05000000636166c3a9" (encodeString "café")
  let qn ← liftOk "qn" (parseQualifiedName #["Counter"])
  let qi ← liftOk "qi" (parseQualifiedName #["Demo", "Counter"])
  expectOk "qn_Counter" "0100000007000000436f756e746572" (encodeQualifiedName qn)
  expectOk "qi_Demo_Counter" "020000000400000044656d6f07000000436f756e746572"
    (encodeQualifiedId qi)
  expectOk "tag_Visibility.Public" "110000005669736962696c6974792e5075626c69630000"
    (encodeTagged "Visibility.Public" #[])
  let nameB ← liftOk "program name" (encodeIdent "Counter")
  let itemsB ← liftOk "program items" (encodeArray encodeU8Ok #[])
  expectOk "tag_Program" "0700000050726f6772616d020007000000436f756e74657200000000"
    (encodeTagged "Program" #[nameB, itemsB])
  expectErr "non_nfc" (encodeString "e\u0301")
  expectOk "ident_1bad" "0400000031626164" (encodeIdent "1bad")
  expectErr "qn_empty" (parseQualifiedName #[])
  let qiOne ← liftOk "qi one carrier" (parseQualifiedName #["Only"])
  let qi257 : QualifiedName := {
    components := { head := "C", tail := Array.replicate 256 "C" }
  }
  expectErr "qi_one" (encodeQualifiedId qiOne)
  expectErr "qi_257" (encodeQualifiedId qi257)
  expectErr "tag_empty" (encodeTagged "" #[])
  expectErr "tag_non_ascii" (encodeTagged "Pα" #[])
  expectErr "field_count" (encodeTagged "T" (Array.replicate 65536 ByteArray.empty))

end Tests.Language.SourceWireCodecV1
