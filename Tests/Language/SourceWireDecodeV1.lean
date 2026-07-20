import ProofForgeV2.Source.WireCodecV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceWireDecodeV1
open ProofForgeV2.Source.WireCodecV1
open ProofForgeV2.Source.WireDecodeV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def expectErr (label : String) (r : Except String α) : IO Unit :=
  match r with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def expectErrExact (label want : String) (r : Except String α) : IO Unit :=
  match r with
  | .error e => expect (e == want) s!"{label}: got {e}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def runFin (label : String) (d : DecoderV1 α) (bytes : ByteArray) : IO α := do
  match d (start bytes) with
  | .error e => throw <| IO.userError s!"{label}: {e}"
  | .ok (v, c) =>
    match finish c with
    | .error e => throw <| IO.userError s!"{label} finish: {e}"
    | .ok () => pure v

private def hexByte (c : Char) : Nat :=
  if '0' ≤ c && c ≤ '9' then c.toNat - '0'.toNat
  else if 'a' ≤ c && c ≤ 'f' then 10 + c.toNat - 'a'.toNat
  else 0

private def fromHex (s : String) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  let cs := s.toList
  let mut i := 0
  while i + 1 < cs.length do
    let hi := hexByte cs[i]!
    let lo := hexByte cs[i+1]!
    out := out.push (UInt8.ofNat (hi * 16 + lo))
    i := i + 2
  pure out

private def encU8 (u : UInt8) : Except String ByteArray := .ok (encodeU8 u)

private def childFail : DecoderV1 UInt8 := fun _ => .error "child-must-not-run"
private def childErr : DecoderV1 UInt8 := fun _ => .error "child-failed"

/-- D1-PA-92 RED: production WireDecodeV1 missing → focused build fails. -/
def run : IO Unit := do
  expect ((← runFin "u8_0" decodeU8 (fromHex "00")) == 0) "u8_0"
  expect ((← runFin "u8_max" decodeU8 (fromHex "ff")) == 255) "u8_max"
  expect ((← runFin "u16" decodeU16le (fromHex "0201")) == 0x0102) "u16"
  expect ((← runFin "u32" decodeU32le (fromHex "04030201")) == 0x01020304) "u32"
  expect ((← runFin "u256_asym" decodeU256le
      (fromHex "0102030400000000000000000000000000000000000000000000000005060708")) ==
      0x04030201 + 0x08070605 * 2 ^ 224) "u256_asym"
  expect ((← runFin "u256_max" decodeU256le (fromHex <| String.join (List.replicate 32 "ff"))) ==
      2 ^ 256 - 1) "u256_max"
  expect ((← runFin "bool_f" decodeBool (fromHex "00")) == false) "bool_f"
  expect ((← runFin "bool_t" decodeBool (fromHex "01")) == true) "bool_t"
  expect ((← runFin "opt_none" (decodeOption decodeU8) (fromHex "00")).isNone) "opt_none"
  expect ((← runFin "opt_some" (decodeOption decodeU8) (fromHex "0107")) == some 7) "opt_some"
  expect ((← runFin "arr_empty" (decodeArray 8 decodeU8) (fromHex "00000000")) == #[]) "arr_empty"
  expect ((← runFin "arr_12" (decodeArray 8 decodeU8) (fromHex "020000000102")) == #[1, 2])
    "arr_12"
  expect ((← runFin "str_hi" decodeString (fromHex "020000006869")) == "hi") "str_hi"
  expect ((← runFin "str_cafe" decodeString (fromHex "05000000636166c3a9")) == "café") "str_cafe"
  -- PA91 allowlist encode → decode round-trips only
  let r8 ← runFin "rt_u8" decodeU8 (encodeU8 7)
  expect (r8 == 7) "rt_u8"
  let r16 ← runFin "rt_u16" decodeU16le (encodeU16le 0x0102)
  expect (r16 == 0x0102) "rt_u16"
  let r32 ← runFin "rt_u32" decodeU32le (encodeU32le 0x01020304)
  expect (r32 == 0x01020304) "rt_u32"
  let b256 ← match encodeU256le (2 ^ 256 - 1) with
    | .ok b => pure b | .error e => throw <| IO.userError e
  expect ((← runFin "rt_u256" decodeU256le b256) == 2 ^ 256 - 1) "rt_u256"
  expect ((← runFin "rt_bool" decodeBool (encodeBool true)) == true) "rt_bool"
  let bOpt ← match encodeOption encU8 (some (7 : UInt8)) with
    | .ok b => pure b | .error e => throw <| IO.userError e
  expect ((← runFin "rt_opt" (decodeOption decodeU8) bOpt) == some 7) "rt_opt"
  let bArr ← match encodeArray encU8 (#[1, 2] : Array UInt8) with
    | .ok b => pure b | .error e => throw <| IO.userError e
  expect ((← runFin "rt_arr" (decodeArray 8 decodeU8) bArr) == #[1, 2]) "rt_arr"
  let bStr ← match encodeString "hi" with
    | .ok b => pure b | .error e => throw <| IO.userError e
  expect ((← runFin "rt_str" decodeString bStr) == "hi") "rt_str"
  expectErr "t_u8" (decodeU8 (start (fromHex "")))
  expectErr "t_u16" (decodeU16le (start (fromHex "01")))
  expectErr "t_u32" (decodeU32le (start (fromHex "010203")))
  expectErr "t_u256" (decodeU256le (start (fromHex <| String.join (List.replicate 31 "00"))))
  expectErr "bool2" (decodeBool (start (fromHex "02")))
  expectErr "opt2" (decodeOption decodeU8 (start (fromHex "02")))
  expectErrExact "cap" "array count exceeds caller limit"
    (decodeArray 0 childFail (start (fromHex "01000000")))
  expectErrExact "child" "child-failed"
    (decodeArray 8 childErr (start (fromHex "0100000001")))
  expectErr "t_child" (decodeArray 8 decodeU8 (start (fromHex "01000000")))
  expectErr "str_over" (decodeString (start (fromHex "050000006869")))
  expectErr "utf8" (decodeString (start (fromHex "01000000ff")))
  expectErr "nfd" (decodeString (start (fromHex "0300000065cc81")))
  match decodeU8 (start (fromHex "0000")) with
  | .error e => throw <| IO.userError e
  | .ok (_, c) => expectErr "trail" (finish c)

end Tests.Language.SourceWireDecodeV1
