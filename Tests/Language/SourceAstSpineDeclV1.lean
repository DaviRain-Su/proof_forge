import ProofForgeV2.Source.AstSpineDeclCodecV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1

namespace Tests.Language.SourceAstSpineDeclV1
open ProofForgeV2.Source.AstSpineDeclCodecV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
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
private def u256Err := "u256 magnitude exceeds 2^256-1"
private def blockEmpty := "block statements must be nonempty"
private def fieldErr := "field id must be bn254_fr, bls12_377_fr, or goldilocks"

/-- D1-PA-101 phase-neutral: spine-dependent declaration-record wire vectors. -/
def run : IO Unit := do
  let maxN ← name "max"; let bounded ← name "bounded"; let count ← name "count"
  let start ← name "start"; let secret ← name "secret"; let runN ← name "run"
  let to ← name "to"; let amount ← name "amount"; let note ← name "note"
  let get ← name "get"; let helper2 ← name "helper2"; let x ← name "x"
  let badFr ← name "bad_fr"
  let L0 : ExprV1 := .literal (.integer 0)
  let L1 : ExprV1 := .literal (.integer 1)
  let L4096 : ExprV1 := .literal (.integer 4096)
  let Lbad : ExprV1 := .literal (.integer (2 ^ 256))
  let LT : ExprV1 := .literal (.bool true)
  let pCount : PlaceV1 := .name count
  let eCount : ExprV1 := .place pCount
  let eLt : ExprV1 := .binary .lt eCount L4096
  let blkAssign : BlockV1 := { statements := #[.assign pCount L1] }
  let blkRetCount : BlockV1 := { statements := #[.return_ (some eCount)] }
  let blkRet0 : BlockV1 := { statements := #[.return_ (some L0)] }
  let blkRetNone : BlockV1 := { statements := #[.return_ none] }
  let blkIf : BlockV1 := { statements := #[.if_ LT blkRetNone none] }
  let blkEmpty : BlockV1 := { statements := #[] }
  let pStart : ParamV1 := { visibility := .public_, name := start, type_ := .uint 64 }
  let pSecret : ParamV1 :=
    { visibility := .private_, name := secret, type_ := .field (← name "bn254_fr") }
  let pTo : ParamV1 := { visibility := .public_, name := to, type_ := .principal }
  let pAmount : ParamV1 := { visibility := .private_, name := amount, type_ := .uint 64 }
  let pNote : ParamV1 := { visibility := .commitment, name := note, type_ := .bytes 0 }
  let pX : ParamV1 := { visibility := .public_, name := x, type_ := .uint 64 }
  let pBad : ParamV1 := { visibility := .public_, name := x, type_ := .field badFr }
  let cMax : ConstDeclV1 := { name := maxN, type_ := .uint 256, value := L4096 }
  let cMax2 : ConstDeclV1 := { name := maxN, type_ := .uint 64, value := L4096 }
  let inv : InvariantDeclV1 := { name := bounded, predicate := eLt }
  let inv2 : InvariantDeclV1 := { name := bounded, predicate := L0 }
  let initD : InitDeclV1 := { params := #[pStart, pSecret], body := blkAssign }
  let init2 : InitDeclV1 := { params := #[pStart], body := blkAssign }
  let entry : EntryDeclV1 :=
    { name := runN, params := #[pTo, pAmount, pNote], result := .uint 64, body := blkRetCount }
  let entrySw : EntryDeclV1 :=
    { name := runN, params := #[pAmount, pTo, pNote], result := .uint 64, body := blkRetCount }
  let viewD : ViewDeclV1 :=
    { name := get, params := #[], result := .uint 64, body := blkRet0 }
  let view2 : ViewDeclV1 :=
    { name := get, params := #[], result := .uint 32, body := blkRet0 }
  let fnD : FnDeclV1 :=
    { name := helper2, params := #[pX], result := .unit, body := blkIf }
  let fn2 : FnDeclV1 :=
    { name := helper2, params := #[pX], result := .bool, body := blkIf }
  let entryAsView : EntryDeclV1 :=
    { name := get, params := #[], result := .uint 64, body := blkRet0 }
  let viewAsEntry : ViewDeclV1 :=
    { name := get, params := #[], result := .uint 64, body := blkRet0 }
  expectHex "const_max"
    "09000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
    (encodeConstDeclV1 cMax)
  expectHex "invariant_bounded"
    "0d000000496e76617269616e744465636c020007000000626f756e6465640b000000457870722e42696e61727903000b00000042696e6172794f702e4c7400000a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
    (encodeInvariantDeclV1 inv)
  expectHex "init_two_params"
    "08000000496e69744465636c02000200000005000000506172616d0300110000005669736962696c6974792e5075626c6963000005000000737461727409000000547970652e55496e740100400005000000506172616d0300120000005669736962696c6974792e507269766174650000060000007365637265740a000000547970652e4669656c64010008000000626e3235345f667205000000426c6f636b0100010000000b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"
    (encodeInitDeclV1 initD)
  expectHex "entry_run"
    "09000000456e7472794465636c04000300000072756e0300000005000000506172616d0300110000005669736962696c6974792e5075626c6963000002000000746f0e000000547970652e5072696e636970616c000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e427974657301000000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e74"
    (encodeEntryDeclV1 entry)
  expectHex "entry_swapped"
    "09000000456e7472794465636c04000300000072756e0300000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300110000005669736962696c6974792e5075626c6963000002000000746f0e000000547970652e5072696e636970616c000005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e427974657301000000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e74"
    (encodeEntryDeclV1 entrySw)
  expectHex "view_get_empty"
    "08000000566965774465636c0400030000006765740000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000"
    (encodeViewDeclV1 viewD)
  expectHex "fn_helper2"
    "06000000466e4465636c04000700000068656c706572320100000005000000506172616d0300110000005669736962696c6974792e5075626c69630000010000007809000000547970652e55496e740100400009000000547970652e556e6974000005000000426c6f636b0100010000000700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000"
    (encodeFnDeclV1 fnD)
  expect (decide (cMax = cMax)) "const_eq_true"; expect (decide (cMax ≠ cMax2)) "const_eq_false"
  expect (decide (inv = inv)) "inv_eq_true"; expect (decide (inv ≠ inv2)) "inv_eq_false"
  expect (decide (initD = initD)) "init_eq_true"; expect (decide (initD ≠ init2)) "init_eq_false"
  expect (decide (entry = entry)) "entry_eq_true"; expect (decide (entry ≠ entrySw)) "entry_eq_false"
  expect (decide (viewD = viewD)) "view_eq_true"; expect (decide (viewD ≠ view2)) "view_eq_false"
  expect (decide (fnD = fnD)) "fn_eq_true"; expect (decide (fnD ≠ fn2)) "fn_eq_false"
  let bEntry ← lift "entry_run_bytes" (encodeEntryDeclV1 entry)
  let bSw ← lift "entry_swapped_bytes" (encodeEntryDeclV1 entrySw)
  expect (decide (bytesHex bEntry ≠ bytesHex bSw)) "entry_param_order_byte_nonalias"
  let bEV ← lift "entry_as_view" (encodeEntryDeclV1 entryAsView)
  let bVE ← lift "view_as_entry" (encodeViewDeclV1 viewAsEntry)
  expect (decide (bytesHex bEV ≠ bytesHex bVE)) "entry_view_tag_nonalias"
  expectErrExact "const_w24_before_hostile" wErr
    (encodeConstDeclV1 { name := maxN, type_ := .uint 24, value := Lbad })
  expectErrExact "const_u256_hostile" u256Err
    (encodeConstDeclV1 { name := maxN, type_ := .uint 256, value := Lbad })
  expectErrExact "inv_hostile" u256Err
    (encodeInvariantDeclV1 { name := bounded, predicate := Lbad })
  expectErrExact "init_empty_block" blockEmpty
    (encodeInitDeclV1 { params := #[pStart], body := blkEmpty })
  expectErrExact "entry_field_before_w24_body" fieldErr
    (encodeEntryDeclV1 {
      name := runN, params := #[pBad], result := .uint 24, body := blkEmpty })
  expectErrExact "view_w24_before_empty_body" wErr
    (encodeViewDeclV1 { name := get, params := #[], result := .uint 24, body := blkEmpty })
  expectErrExact "fn_empty_body" blockEmpty
    (encodeFnDeclV1 { name := helper2, params := #[pX], result := .unit, body := blkEmpty })

end Tests.Language.SourceAstSpineDeclV1
