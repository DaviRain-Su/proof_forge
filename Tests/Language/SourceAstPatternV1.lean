import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstPatternCodecV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace Tests.Language.SourceAstPatternV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstPatternCodecV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

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

private def qn (ps : Array String) : IO SourceQualifiedNameV1 :=
  lift "qn" (parseSourceQualifiedNameV1 ps)

private def qidErr := "source qualified id must contain 2..256 components"
private def u256Err := "u256 magnitude exceeds 2^256-1"
private def nfcErr := "string must already be NFC under Unicode 17.0.0"

/-- D1-PA-97 exact Pattern wire vectors, equality, and child-error priority. -/
def run : IO Unit := do
  let x ← name "x"
  let y ← name "y"
  let foobar ← name "foo-bar"
  let optNone ← qn #["Option", "none"]
  let optSome ← qn #["Option", "some"]
  let demoPair ← qn #["Demo", "Pair"]
  let ab ← qn #["A", "B"]
  let cd ← qn #["C", "D"]
  let only ← qn #["Only"]
  expectHex "pat_wildcard" "100000005061747465726e2e57696c64636172640000"
    (encodePatternV1 .wildcard)
  expectHex "pat_bind_x" "0c0000005061747465726e2e42696e6401000100000078"
    (encodePatternV1 (.bind x))
  expectHex "pat_bind_foobar" "0c0000005061747465726e2e42696e64010007000000666f6f2d626172"
    (encodePatternV1 (.bind foobar))
  expectHex "pat_lit_bool_f"
    "0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010000"
    (encodePatternV1 (.literal (.bool false)))
  expectHex "pat_lit_bool_t"
    "0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001"
    (encodePatternV1 (.literal (.bool true)))
  expectHex "pat_lit_int_2_64"
    "0f0000005061747465726e2e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000010000000000000000000000000000000000000000000000"
    (encodePatternV1 (.literal (.integer (2 ^ 64))))
  expectHex "pat_lit_str_cafe"
    "0f0000005061747465726e2e4c69746572616c01000e0000004c69746572616c2e537472696e67010005000000636166c3a9"
    (encodePatternV1 (.literal (.string "café")))
  expectHex "pat_ctor_empty"
    "130000005061747465726e2e436f6e7374727563746f72020002000000060000004f7074696f6e040000006e6f6e6500000000"
    (encodePatternV1 (.constructor optNone #[]))
  expectHex "pat_ctor_wild"
    "130000005061747465726e2e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d6501000000100000005061747465726e2e57696c64636172640000"
    (encodePatternV1 (.constructor optSome #[.wildcard]))
  let ordered : PatternV1 :=
    .constructor demoPair #[.bind x, .literal (.bool true)]
  let reversed : PatternV1 :=
    .constructor demoPair #[.literal (.bool true), .bind x]
  expectHex "pat_ctor_ordered"
    "130000005061747465726e2e436f6e7374727563746f720200020000000400000044656d6f0400000050616972020000000c0000005061747465726e2e42696e64010001000000780f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001"
    (encodePatternV1 ordered)
  expectHex "pat_ctor_reversed"
    "130000005061747465726e2e436f6e7374727563746f720200020000000400000044656d6f0400000050616972020000000f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c0100010c0000005061747465726e2e42696e6401000100000078"
    (encodePatternV1 reversed)
  expect (ordered != reversed) "ordered≠reversed"
  let nested : PatternV1 :=
    .constructor ab #[.constructor cd #[.wildcard], .bind y]
  expectHex "pat_ctor_nested"
    "130000005061747465726e2e436f6e7374727563746f720200020000000100000041010000004202000000130000005061747465726e2e436f6e7374727563746f720200020000000100000043010000004401000000100000005061747465726e2e57696c646361726400000c0000005061747465726e2e42696e6401000100000079"
    (encodePatternV1 nested)
  -- nested DecidableEq: equal / order / shape
  expect (nested == .constructor ab #[.constructor cd #[.wildcard], .bind y]) "nested equal"
  expect (nested != .constructor ab #[.bind y, .constructor cd #[.wildcard]]) "nested order"
  expect (nested != .constructor ab #[.wildcard, .bind y]) "nested shape"
  expectErrExact "qid1" qidErr (encodePatternV1 (.constructor only #[]))
  expectErrExact "u256" u256Err
    (encodePatternV1 (.literal (.integer (2 ^ 256))))
  expectErrExact "nfd" nfcErr
    (encodePatternV1 (.literal (.string "e\u0301")))
  -- invalid QID wins over invalid nested literal
  expectErrExact "qid_before_lit" qidErr
    (encodePatternV1 (.constructor only #[.literal (.integer (2 ^ 256))]))

end Tests.Language.SourceAstPatternV1
