import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstTypeDecodeV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceAstTypeDecodeV1
open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstTypeDecodeV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireDecodeV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m
private def lift (lab : String) (r : Except String α) : IO α :=
  match r with | .ok v => pure v | .error e => throw <| IO.userError s!"{lab}: {e}"
private def expectErrExact (lab want : String) (r : Except String α) : IO Unit :=
  match r with
  | .error e => expect (e == want) s!"{lab}: got {e}"
  | .ok _ => throw <| IO.userError s!"{lab}: unexpectedly ok"
private def hexVal (c : Char) : Nat :=
  if '0' ≤ c && c ≤ '9' then c.toNat - '0'.toNat
  else if 'a' ≤ c && c ≤ 'f' then c.toNat - 'a'.toNat + 10
  else if 'A' ≤ c && c ≤ 'F' then c.toNat - 'A'.toNat + 10 else 0
private def fromHex (s : String) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  let cs := s.toList.toArray
  let mut i := 0
  while i + 1 < cs.size do
    out := out.push (UInt8.ofNat (hexVal cs[i]! * 16 + hexVal cs[i + 1]!))
    i := i + 2
  pure out
private def bytesHex (b : ByteArray) : String :=
  b.foldl (fun o x =>
    let v := x.toNat
    let d (n : Nat) := if n < 10 then Char.ofNat ('0'.toNat + n)
      else Char.ofNat ('a'.toNat + n - 10)
    (o.push (d (v / 16))).push (d (v % 16))) ""
private def setU16le (b : ByteArray) (off fc : Nat) : ByteArray := Id.run do
  let mut o := b
  o := o.set! off (UInt8.ofNat (fc % 256))
  o := o.set! (off + 1) (UInt8.ofNat (fc / 256))
  pure o
private def typeFc (hex : String) (fc : Nat) : ByteArray :=
  let b := fromHex hex; setU16le b (4 + (b.get! 0).toNat) fc
private def stripFc (hex : String) : ByteArray :=
  let b := fromHex hex; b.extract 0 (b.size - 2)
private def bud (n : Nat) : DecodeBudgetV1 := { remainingNodes := n }
private def boolHex : String := "09000000547970652e426f6f6c0000"
private def unitHex : String := "09000000547970652e556e69740000"
private def mapHex : String :=
  "08000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000"
private def arr0Hex : String :=
  "0a000000547970652e4172726179020009000000547970652e426f6f6c000000000000"
private def optPrefix : ByteArray := fromHex "0b000000547970652e4f7074696f6e0100"
/-- Test-owned Option wrappers (not production encoder). -/
private def optWrap (inner : ByteArray) : ByteArray := optPrefix ++ inner
private def optN : Nat → ByteArray → ByteArray
  | 0, leaf => leaf
  | n + 1, leaf => optWrap (optN n leaf)
private def nameOk (s : String) : IO SourceNameComponentV1 :=
  lift "name" (parseSourceNameComponentV1 s)
/-- Decode + exact value + residual nodes + re-encode identity + finish. -/
private def rt (hex : String) (want : TypeV1) (nodes : Nat) (startN : Nat := 100) : IO Unit := do
  let ((got, b), c) ← lift "d" (decodeTypeV1 256 (bud startN) (start (fromHex hex)))
  expect (decide (got = want)) "val"
  expect (b.remainingNodes == startN - nodes) s!"nodes residual {b.remainingNodes}"
  lift "f" (finish c)
  expect (bytesHex (← lift "e" (encodeTypeV1 got)) == hex) "reenc"
private def decErr (lab want : String) (depth nodes : Nat) (raw : ByteArray) : IO Unit :=
  expectErrExact lab want (decodeTypeV1 depth (bud nodes) (start raw))

def run : IO Unit := do
  -- ── 24 PA95 fixed-wire positives (exact residual node counts) ──
  rt boolHex .bool 1
  rt "0e000000547970652e5072696e636970616c0000" .principal 1
  rt unitHex .unit 1
  rt "09000000547970652e55496e7401000800" (.uint 8) 1
  rt "09000000547970652e55496e7401001000" (.uint 16) 1
  rt "09000000547970652e55496e7401002000" (.uint 32) 1
  rt "09000000547970652e55496e7401004000" (.uint 64) 1
  rt "09000000547970652e55496e7401008000" (.uint 128) 1
  rt "09000000547970652e55496e7401000001" (.uint 256) 1
  rt "08000000547970652e496e7401000800" (.int 8) 1
  rt "08000000547970652e496e7401001000" (.int 16) 1
  rt "08000000547970652e496e7401002000" (.int 32) 1
  rt "08000000547970652e496e7401004000" (.int 64) 1
  rt "08000000547970652e496e7401008000" (.int 128) 1
  rt "08000000547970652e496e7401000001" (.int 256) 1
  let foobar ← nameOk "foo-bar"
  rt "0a000000547970652e4e616d6564010007000000666f6f2d626172" (.named foobar) 1
  rt mapHex (.map .bool .unit) 3
  rt "0a000000547970652e4279746573010000000000" (.bytes 0) 1
  rt "0a000000547970652e4279746573010000100000" (.bytes 4096) 1
  rt arr0Hex (.array .bool 0) 2
  rt "0a000000547970652e4172726179020009000000547970652e426f6f6c000000100000" (.array .bool 4096) 2
  rt "0a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000"
    (.array (.option (.bytes 0)) 0) 3
  rt "0b000000547970652e4f7074696f6e01000a000000547970652e4279746573010000000000" (.option (.bytes 0)) 2
  let fr ← nameOk "bn254_fr"
  rt "0a000000547970652e4669656c64010008000000626e3235345f6672" (.field fr) 1
  -- ── 19 exhaustive field-count negatives ──
  for (hex, tag) in ([
    (boolHex, "Type.Bool"),
    ("0e000000547970652e5072696e636970616c0000", "Type.Principal"),
    (unitHex, "Type.Unit")
  ] : List (String × String)) do
    decErr s!"fc1_{tag}" s!"tag '{tag}' must declare 0 fields" 8 8 (typeFc hex 1)
  for (hex, tag) in ([
    ("09000000547970652e55496e7401000800", "Type.UInt"),
    ("08000000547970652e496e7401000800", "Type.Int"),
    ("0a000000547970652e4e616d6564010007000000666f6f2d626172", "Type.Named"),
    ("0b000000547970652e4f7074696f6e01000a000000547970652e4279746573010000000000", "Type.Option"),
    ("0a000000547970652e4279746573010000000000", "Type.Bytes"),
    ("0a000000547970652e4669656c64010008000000626e3235345f6672", "Type.Field")
  ] : List (String × String)) do
    decErr s!"fc0_{tag}" s!"tag '{tag}' must declare 1 fields" 8 8 (typeFc hex 0)
    decErr s!"fc2_{tag}" s!"tag '{tag}' must declare 1 fields" 8 8 (typeFc hex 2)
  for (hex, tag) in ([(arr0Hex, "Type.Array"), (mapHex, "Type.Map")] : List (String × String)) do
    decErr s!"fc1_{tag}" s!"tag '{tag}' must declare 2 fields" 8 8 (typeFc hex 1)
    decErr s!"fc3_{tag}" s!"tag '{tag}' must declare 2 fields" 8 8 (typeFc hex 3)
  -- ── 24 boundaries ──
  -- 1 wrong-family no FC under zero budgets → unknown first
  decErr "b_unk_zero" "unknown type tag 'Visibility.Public'" 0 0
    (stripFc "110000005669736962696c6974792e5075626c69630000")
  -- 2 known wrong FC before budgets (depth/node 0)
  decErr "b_fc_before_bud" "tag 'Type.Bool' must declare 0 fields" 0 0 (typeFc boolHex 1)
  -- 3 depth before node when both zero after correct FC
  decErr "b_depth_both0" "depth budget exhausted" 0 0 (fromHex boolHex)
  -- 4 node before payload (known UInt/1 header, missing width)
  decErr "b_node0" "node budget exhausted" 1 0
    (fromHex "09000000547970652e55496e740100")
  -- 5–9 domain
  decErr "b_u24" "integer width must be one of 8,16,32,64,128,256" 8 8
    (fromHex "09000000547970652e55496e7401001800")
  decErr "b_i0" "integer width must be one of 8,16,32,64,128,256" 8 8
    (fromHex "08000000547970652e496e7401000000")
  decErr "b_a4097" "array length must be 0..4096" 8 8
    (fromHex "0a000000547970652e4172726179020009000000547970652e426f6f6c000001100000")
  decErr "b_b4097" "bytes length must be 0..4096" 8 8
    (fromHex "0a000000547970652e4279746573010001100000")
  -- Field wrong id (valid Ident wire for bls12_381_fr)
  decErr "b_field" "field id must be bn254_fr" 8 8
    (fromHex "0a000000547970652e4669656c6401000c000000626c7331325f3338315f6672")
  -- 10 missing fieldCount (tag only)
  decErr "b_miss_fc" "truncated" 8 8 (stripFc boolHex)
  -- 11 truncated width (UInt tag+fc, no u16)
  decErr "b_trunc_w" "truncated" 8 8 (fromHex "09000000547970652e55496e740100")
  -- 12 truncated Array child (Array tag+fc, no element)
  decErr "b_trunc_arr" "truncated" 8 8 (fromHex "0a000000547970652e41727261790200")
  -- 13 trailing
  expectErrExact "b_trail" "trailing bytes" (do
    let ((_t, _), c) ← decodeTypeV1 8 (bud 8) (start (fromHex (boolHex ++ "00")))
    finish c)
  -- 14 Bool exact depth=1 nodes=1
  let ((b14, r14), c14) ← lift "b14" (decodeTypeV1 1 (bud 1) (start (fromHex boolHex)))
  expect (decide (b14 = .bool) && r14.remainingNodes == 0) "b14"; lift "b14f" (finish c14)
  -- 15 Option(Bool) pass depth=2 nodes=2
  let optBool := optWrap (fromHex boolHex)
  let ((o15, r15), c15) ← lift "o15" (decodeTypeV1 2 (bud 2) (start optBool))
  expect (decide (o15 = .option .bool) && r15.remainingNodes == 0) "o15"; lift "o15f" (finish c15)
  -- 16 Option(Bool) depth-short
  decErr "b_opt_d1" "depth budget exhausted" 1 2 optBool
  -- 17–18 Map nodes2 fail / nodes3 pass
  decErr "b_map_n2" "node budget exhausted" 8 2 (fromHex mapHex)
  let ((m18, r18), c18) ← lift "m18" (decodeTypeV1 8 (bud 3) (start (fromHex mapHex)))
  expect (decide (m18 = .map .bool .unit) && r18.remainingNodes == 0) "m18"
  lift "m18f" (finish c18)
  -- 19 Array bad-element before hostile length: element is unknown tag; length would be 0xFFFFFFFF
  -- wire: Array/2 || Visibility.Public(no fc) || u32 hostile — unknown during element
  let arrBadEl :=
    fromHex "0a000000547970652e41727261790200" ++
    stripFc "110000005669736962696c6974792e5075626c69630000" ++
    fromHex "ffffffff"
  decErr "b_arr_el" "unknown type tag 'Visibility.Public'" 8 8 arrBadEl
  -- 20 Map bad-key before hostile value: key unknown; value not reached
  let mapBadKey :=
    fromHex "08000000547970652e4d61700200" ++
    stripFc "110000005669736962696c6974792e5075626c69630000" ++
    fromHex boolHex
  decErr "b_map_key" "unknown type tag 'Visibility.Public'" 8 8 mapBadKey
  -- 21 Option^255(Bool): 256 Type nodes; depth=256 nodes=256 pass
  let deep255 := optN 255 (fromHex boolHex)
  let ((d21, r21), c21) ← lift "d21" (decodeTypeV1 256 (bud 256) (start deep255))
  expect (r21.remainingNodes == 0) "d21nodes"; lift "d21f" (finish c21)
  -- shape: 255 options around bool
  let rec countOpt : TypeV1 → Nat
    | .option t => 1 + countOpt t
    | .bool => 0
    | _ => 9999
  expect (countOpt d21 == 255) "d21depth"
  -- 22 Option^256(Bool): needs depth 257; at depth=256 nodes=257 → depth error
  let deep256 := optN 256 (fromHex boolHex)
  decErr "b_opt256" "depth budget exhausted" 256 257 deep256
  -- 23 Named Ident declared length 241, no payload — pre-copy 1..240
  -- Type.Named/1 || u32le(241) with no following bytes
  decErr "b_ident241" "source name component must contain 1..240 UTF-8 bytes" 8 8
    (fromHex "0a000000547970652e4e616d65640100f1000000")
  -- 24 depth before payload (known UInt/1 header, missing width)
  decErr "b_depth0_nodes" "depth budget exhausted" 0 5
    (fromHex "09000000547970652e55496e740100")

end Tests.Language.SourceAstTypeDecodeV1
