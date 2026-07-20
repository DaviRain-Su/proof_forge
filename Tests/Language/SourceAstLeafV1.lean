import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.NameComponentV1

namespace Tests.Language.SourceAstLeafV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.NameComponentV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def lift (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def expectErr (label : String) (r : Except String α) : IO Unit :=
  match r with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly ok"

private def expectErrExact (label want : String) (r : Except String α) : IO Unit :=
  match r with
  | .error e => expect (e == want) s!"{label}: got {e}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly ok"

private def lowerHexDigit (v : Nat) : Char :=
  if v < 10 then Char.ofNat ('0'.toNat + v)
  else Char.ofNat ('a'.toNat + v - 10)

private def bytesHex (b : ByteArray) : String :=
  b.foldl (fun o x =>
    let v := x.toNat
    (o.push (lowerHexDigit (v / 16))).push (lowerHexDigit (v % 16))) ""

private def expectHex (label want : String) (r : Except String ByteArray) : IO Unit :=
  match r with
  | .ok b => expect (bytesHex b == want) s!"{label}: got {bytesHex b}"
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def name (s : String) : IO SourceNameComponentV1 :=
  lift s (parseSourceNameComponentV1 s)

private def wErr := "integer width must be one of 8,16,32,64,128,256"
private def aErr := "array length must be 0..4096"
private def bErr := "bytes length must be 0..4096"
private def fErr := "field id must be bn254_fr"

/-- D1-PA-95 RED: AstV1/AstCodecV1 missing → focused build fails; goldens fixed. -/
def run : IO Unit := do
  expectHex "vis_public" "110000005669736962696c6974792e5075626c69630000"
    (encodeVisibilityV1 .public_)
  expectHex "vis_private" "120000005669736962696c6974792e507269766174650000"
    (encodeVisibilityV1 .private_)
  expectHex "vis_commitment" "150000005669736962696c6974792e436f6d6d69746d656e740000"
    (encodeVisibilityV1 .commitment)
  expectHex "type_bool" "09000000547970652e426f6f6c0000" (encodeTypeV1 .bool)
  expectHex "type_principal" "0e000000547970652e5072696e636970616c0000" (encodeTypeV1 .principal)
  expectHex "type_unit" "09000000547970652e556e69740000" (encodeTypeV1 .unit)
  for (w, uh, ih) in ([
    ((8 : UInt16), "09000000547970652e55496e7401000800", "08000000547970652e496e7401000800"),
    (16, "09000000547970652e55496e7401001000", "08000000547970652e496e7401001000"),
    (32, "09000000547970652e55496e7401002000", "08000000547970652e496e7401002000"),
    (64, "09000000547970652e55496e7401004000", "08000000547970652e496e7401004000"),
    (128, "09000000547970652e55496e7401008000", "08000000547970652e496e7401008000"),
    (256, "09000000547970652e55496e7401000001", "08000000547970652e496e7401000001")
  ] : List (UInt16 × String × String)) do
    expectHex s!"type_uint_{w}" uh (encodeTypeV1 (.uint w))
    expectHex s!"type_int_{w}" ih (encodeTypeV1 (.int w))
  expectErrExact "uint_24" wErr (encodeTypeV1 (.uint 24))
  expectErrExact "int_0" wErr (encodeTypeV1 (.int 0))
  let foobar ← name "foo-bar"
  expectHex "type_named_foobar" "0a000000547970652e4e616d6564010007000000666f6f2d626172"
    (encodeTypeV1 (.named foobar))
  expectHex "type_map_bool_unit"
    "08000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000"
    (encodeTypeV1 (.map .bool .unit))
  expectHex "type_bytes_0" "0a000000547970652e4279746573010000000000"
    (encodeTypeV1 (.bytes 0))
  expectHex "type_bytes_4096" "0a000000547970652e4279746573010000100000"
    (encodeTypeV1 (.bytes 4096))
  expectErrExact "bytes_4097" bErr (encodeTypeV1 (.bytes 4097))
  expectHex "type_array_bool_0"
    "0a000000547970652e4172726179020009000000547970652e426f6f6c000000000000"
    (encodeTypeV1 (.array .bool 0))
  expectHex "type_array_bool_4096"
    "0a000000547970652e4172726179020009000000547970652e426f6f6c000000100000"
    (encodeTypeV1 (.array .bool 4096))
  expectErrExact "array_4097" aErr (encodeTypeV1 (.array .bool 4097))
  expectHex "type_array_opt_bytes"
    "0a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000"
    (encodeTypeV1 (.array (.option (.bytes 0)) 0))
  expectHex "type_option_bytes0"
    "0b000000547970652e4f7074696f6e01000a000000547970652e4279746573010000000000"
    (encodeTypeV1 (.option (.bytes 0)))
  let fr ← name "bn254_fr"
  expectHex "type_field_bn254" "0a000000547970652e4669656c64010008000000626e3235345f6672"
    (encodeTypeV1 (.field fr))
  let badF ← name "bls12_381_fr"
  expectErrExact "field_other" fErr (encodeTypeV1 (.field badF))
  expectHex "lit_bool_f" "0c0000004c69746572616c2e426f6f6c010000" (encodeLiteralV1 (.bool false))
  expectHex "lit_bool_t" "0c0000004c69746572616c2e426f6f6c010001" (encodeLiteralV1 (.bool true))
  expectHex "lit_int_0"
    "0f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000"
    (encodeLiteralV1 (.integer 0))
  expectHex "lit_int_gt_u64"
    "0f0000004c69746572616c2e496e746567657201000000000000000000010000000000000000000000000000000000000000000000"
    (encodeLiteralV1 (.integer (2 ^ 64)))
  expectHex "lit_int_max"
    "0f0000004c69746572616c2e496e74656765720100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    (encodeLiteralV1 (.integer (2 ^ 256 - 1)))
  expectErr "lit_int_overflow" (encodeLiteralV1 (.integer (2 ^ 256)))
  expectHex "lit_str_hi" "0e0000004c69746572616c2e537472696e670100020000006869"
    (encodeLiteralV1 (.string "hi"))
  expectHex "lit_str_cafe" "0e0000004c69746572616c2e537472696e67010005000000636166c3a9"
    (encodeLiteralV1 (.string "café"))
  expectErr "lit_str_nfd" (encodeLiteralV1 (.string "e\u0301"))
  expectHex "unary_neg" "0b000000556e6172794f702e4e65670000" (encodeUnaryOpV1 .neg)
  expectHex "unary_not" "0b000000556e6172794f702e4e6f740000" (encodeUnaryOpV1 .not)
  expectHex "unary_bitnot" "0e000000556e6172794f702e4269744e6f740000" (encodeUnaryOpV1 .bitNot)
  expectHex "bin_add" "0c00000042696e6172794f702e4164640000" (encodeBinaryOpV1 .add)
  expectHex "bin_sub" "0c00000042696e6172794f702e5375620000" (encodeBinaryOpV1 .sub)
  expectHex "bin_mul" "0c00000042696e6172794f702e4d756c0000" (encodeBinaryOpV1 .mul)
  expectHex "bin_div" "0c00000042696e6172794f702e4469760000" (encodeBinaryOpV1 .div)
  expectHex "bin_mod" "0c00000042696e6172794f702e4d6f640000" (encodeBinaryOpV1 .mod)
  expectHex "bin_eq" "0b00000042696e6172794f702e45710000" (encodeBinaryOpV1 .eq)
  expectHex "bin_ne" "0b00000042696e6172794f702e4e650000" (encodeBinaryOpV1 .ne)
  expectHex "bin_lt" "0b00000042696e6172794f702e4c740000" (encodeBinaryOpV1 .lt)
  expectHex "bin_le" "0b00000042696e6172794f702e4c650000" (encodeBinaryOpV1 .le)
  expectHex "bin_gt" "0b00000042696e6172794f702e47740000" (encodeBinaryOpV1 .gt)
  expectHex "bin_ge" "0b00000042696e6172794f702e47650000" (encodeBinaryOpV1 .ge)
  expectHex "bin_and" "0c00000042696e6172794f702e416e640000" (encodeBinaryOpV1 .logicalAnd)
  expectHex "bin_or" "0b00000042696e6172794f702e4f720000" (encodeBinaryOpV1 .logicalOr)
  expectHex "bin_bitand" "0f00000042696e6172794f702e426974416e640000" (encodeBinaryOpV1 .bitAnd)
  expectHex "bin_bitor" "0e00000042696e6172794f702e4269744f720000" (encodeBinaryOpV1 .bitOr)
  expectHex "bin_bitxor" "0f00000042696e6172794f702e426974586f720000" (encodeBinaryOpV1 .bitXor)
  expectHex "bin_shl" "0c00000042696e6172794f702e53686c0000" (encodeBinaryOpV1 .shl)
  expectHex "bin_shr" "0c00000042696e6172794f702e5368720000" (encodeBinaryOpV1 .shr)
  let orB ← lift "or" (encodeBinaryOpV1 .logicalOr)
  let bitOrB ← lift "bitor" (encodeBinaryOpV1 .bitOr)
  expect (bytesHex orB != bytesHex bitOrB) "logicalOr≠bitOr"

end Tests.Language.SourceAstLeafV1
