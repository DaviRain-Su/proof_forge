import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstSupportCodecV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1

namespace Tests.Language.SourceAstSupportV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstSupportCodecV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def lift (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: {e}"

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
private def bErr := "bytes length must be 0..4096"

/-- D1-PA-96 RED: AstSupportV1/AstSupportCodecV1 missing → focused build fails. -/
def run : IO Unit := do
  let x ← name "x"
  let y ← name "y"
  let z ← name "z"
  let arr ← name "arr"
  let foobar ← name "foo-bar"
  let count ← name "count"
  let items ← name "items"
  let noneN ← name "None"
  let someN ← name "Some"
  let wrap ← name "Wrap"
  expectHex "param_public_bool"
    "05000000506172616d0300110000005669736962696c6974792e5075626c69630000010000007809000000547970652e426f6f6c0000"
    (encodeParamV1 { visibility := .public_, name := x, type_ := .bool })
  expectHex "param_private_unit"
    "05000000506172616d0300120000005669736962696c6974792e507269766174650000010000007909000000547970652e556e69740000"
    (encodeParamV1 { visibility := .private_, name := y, type_ := .unit })
  expectHex "param_commitment_u64"
    "05000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000010000007a09000000547970652e55496e7401004000"
    (encodeParamV1 { visibility := .commitment, name := z, type_ := .uint 64 })
  expectHex "param_nested_aob"
    "05000000506172616d0300110000005669736962696c6974792e5075626c69630000030000006172720a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000"
    (encodeParamV1 {
      visibility := .public_, name := arr,
      type_ := .array (.option (.bytes 0)) 0 })
  expectHex "param_raw_foobar"
    "05000000506172616d0300110000005669736962696c6974792e5075626c6963000007000000666f6f2d62617209000000547970652e426f6f6c0000"
    (encodeParamV1 { visibility := .public_, name := foobar, type_ := .bool })
  expectHex "field_uint256"
    "090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"
    (encodeFieldDeclV1 { name := count, type_ := .uint 256 })
  expectHex "field_map_bool_unit"
    "090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000"
    (encodeFieldDeclV1 { name := items, type_ := .map .bool .unit })
  expectHex "variant_empty"
    "0b000000456e756d56617269616e740200040000004e6f6e6500000000"
    (encodeEnumVariantV1 { name := noneN, payloadTypes := #[] })
  expectHex "variant_bool_principal"
    "0b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000"
    (encodeEnumVariantV1 { name := someN, payloadTypes := #[.bool, .principal] })
  expectHex "variant_nested_opt"
    "0b000000456e756d56617269616e7402000400000057726170010000000b000000547970652e4f7074696f6e010009000000547970652e556e69740000"
    (encodeEnumVariantV1 { name := wrap, payloadTypes := #[.option .unit] })
  let bad ← name "bad"
  expectErrExact "param_w24" wErr
    (encodeParamV1 { visibility := .public_, name := bad, type_ := .uint 24 })
  expectErrExact "field_w24" wErr
    (encodeFieldDeclV1 { name := bad, type_ := .uint 24 })
  expectErrExact "var_b4097" bErr
    (encodeEnumVariantV1 { name := bad, payloadTypes := #[.bytes 4097] })

end Tests.Language.SourceAstSupportV1
