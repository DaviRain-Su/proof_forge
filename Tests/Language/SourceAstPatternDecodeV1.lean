import ProofForgeV2.Source.AstPatternCodecV1
import ProofForgeV2.Source.AstPatternDecodeV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceAstPatternDecodeV1
open ProofForgeV2.Source.AstPatternCodecV1
open ProofForgeV2.Source.AstPatternDecodeV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireDecodeV1

private def expect (c : Bool) (m : String) : IO Unit := unless c do throw <| IO.userError m
private def lift (lab : String) (r : Except String α) : IO α :=
  match r with | .ok v => pure v | .error e => throw <| IO.userError s!"{lab}: {e}"
private def expectErr (lab want : String) (r : Except String α) : IO Unit :=
  match r with
  | .error e => expect (e == want) s!"{lab}: want {want}, got {e}"
  | .ok _ => throw <| IO.userError s!"{lab}: unexpectedly ok"
private def hv (c : Char) : Nat :=
  if c ≤ '9' then c.toNat - '0'.toNat else c.toNat - 'a'.toNat + 10
private def hex (s : String) : ByteArray := Id.run do
  let cs := s.toList.toArray; let mut out := ByteArray.empty; let mut i := 0
  while i + 1 < cs.size do
    out := out.push (UInt8.ofNat (hv cs[i]! * 16 + hv cs[i + 1]!)); i := i + 2
  pure out
private def toHex (b : ByteArray) : String :=
  b.foldl (fun s x =>
    let d (n : Nat) := if n < 10 then Char.ofNat ('0'.toNat+n) else Char.ofNat ('a'.toNat+n-10)
    (s.push (d (x.toNat/16))).push (d (x.toNat%16))) ""
private def u32 (n : Nat) : ByteArray :=
  ByteArray.mk #[UInt8.ofNat n, UInt8.ofNat (n/256), UInt8.ofNat (n/65536), UInt8.ofNat (n/16777216)]
private def setFc (b : ByteArray) (n : Nat) : ByteArray :=
  (b.set! (4 + (b.get! 0).toNat) (UInt8.ofNat n)).set! (5 + (b.get! 0).toNat) (UInt8.ofNat (n/256))
private def stripFc (b : ByteArray) : ByteArray := b.extract 0 (b.size - 2)
private def bud (n : Nat) : DecodeBudgetV1 := { remainingNodes := n }
private def nm (s : String) : IO SourceNameComponentV1 := lift "name" (parseSourceNameComponentV1 s)
private def qid (xs : Array String) : IO SourceQualifiedNameV1 := lift "qid" (parseSourceQualifiedNameV1 xs)
private def decErr (lab want : String) (d n : Nat) (b : ByteArray) : IO Unit :=
  expectErr lab want (decodePatternV1 d (bud n) (start b))

private def wild := "100000005061747465726e2e57696c64636172640000"
private def bindX := "0c0000005061747465726e2e42696e6401000100000078"
private def litF := "0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010000"
private def ctorEmpty := "130000005061747465726e2e436f6e7374727563746f72020002000000060000004f7074696f6e040000006e6f6e6500000000"
private def ctorWild := "130000005061747465726e2e436f6e7374727563746f72020002000000060000004f7074696f6e04000000736f6d6501000000100000005061747465726e2e57696c64636172640000"
private def ctorPrefix : ByteArray :=
  hex "130000005061747465726e2e436f6e7374727563746f7202000200000001000000410100000042"
private def wrap (p : ByteArray) : ByteArray := ctorPrefix ++ u32 1 ++ p
private def wrapN : Nat → ByteArray → ByteArray
  | 0, p => p | n + 1, p => wrap (wrapN n p)

private def rt (lab hs : String) (want : PatternV1) (spent : Nat) : IO Unit := do
  let ((got, r), c) ← lift lab (decodePatternV1 256 (bud 300) (start (hex hs)))
  expect (got == want && r.remainingNodes == 300 - spent) s!"{lab}: value/residual"
  lift (lab ++ " finish") (finish c)
  expect (toHex (← lift (lab ++ " encode") (encodePatternV1 got)) == hs) s!"{lab}: reencode"

/-- Frozen D1-PA-110: 12 positives, 7 field counts, and 24 boundaries. -/
def run : IO Unit := do
  let x ← nm "x"; let y ← nm "y"; let fb ← nm "foo-bar"
  let on ← qid #["Option", "none"]; let os ← qid #["Option", "some"]
  let dp ← qid #["Demo", "Pair"]; let ab ← qid #["A", "B"]; let cd ← qid #["C", "D"]
  rt "p1" wild .wildcard 1
  rt "p2" bindX (.bind x) 1
  rt "p3" "0c0000005061747465726e2e42696e64010007000000666f6f2d626172" (.bind fb) 1
  rt "p4" litF (.literal (.bool false)) 1
  rt "p5" "0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001" (.literal (.bool true)) 1
  rt "p6" "0f0000005061747465726e2e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000010000000000000000000000000000000000000000000000" (.literal (.integer (2^64))) 1
  rt "p7" "0f0000005061747465726e2e4c69746572616c01000e0000004c69746572616c2e537472696e67010005000000636166c3a9" (.literal (.string "café")) 1
  rt "p8" ctorEmpty (.constructor on #[]) 1
  rt "p9" ctorWild (.constructor os #[.wildcard]) 2
  rt "p10" "130000005061747465726e2e436f6e7374727563746f720200020000000400000044656d6f0400000050616972020000000c0000005061747465726e2e42696e64010001000000780f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001" (.constructor dp #[.bind x, .literal (.bool true)]) 3
  rt "p11" "130000005061747465726e2e436f6e7374727563746f720200020000000400000044656d6f0400000050616972020000000f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c0100010c0000005061747465726e2e42696e6401000100000078" (.constructor dp #[.literal (.bool true), .bind x]) 3
  rt "p12" "130000005061747465726e2e436f6e7374727563746f720200020000000100000041010000004202000000130000005061747465726e2e436f6e7374727563746f720200020000000100000043010000004401000000100000005061747465726e2e57696c646361726400000c0000005061747465726e2e42696e6401000100000079" (.constructor ab #[.constructor cd #[.wildcard], .bind y]) 4
  for (raw, tag, want, bads) in ([
    (hex wild, "Pattern.Wildcard", 0, [1]), (hex bindX, "Pattern.Bind", 1, [0,2]),
    (hex litF, "Pattern.Literal", 1, [0,2]), (hex ctorEmpty, "Pattern.Constructor", 2, [1,3])
  ] : List (ByteArray × String × Nat × List Nat)) do
    for bad in bads do decErr "fc" s!"tag '{tag}' must declare {want} fields" 0 0 (setFc raw bad)
  -- priority and primitive boundaries (1–10)
  decErr "unknown" "unknown pattern tag 'Literal.Bool'" 0 0 (stripFc (hex "0c0000004c69746572616c2e426f6f6c0100"))
  decErr "fc-budget" "tag 'Pattern.Wildcard' must declare 0 fields" 0 0 (setFc (hex wild) 1)
  decErr "depth" "depth budget exhausted" 0 0 (hex wild)
  let emptyBind := hex "0c0000005061747465726e2e42696e64010000000000"
  decErr "node" "node budget exhausted" 1 0 emptyBind
  decErr "bind-empty" "source name component must contain 1..240 UTF-8 bytes" 1 1 emptyBind
  decErr "lit-marker" "invalid bool marker" 1 1
    (hex "0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010002")
  decErr "qid-first" "source qualified id must contain 2..256 components" 1 1 (ctorPrefix.extract 0 (ctorPrefix.size-12) ++ u32 1)
  decErr "qid-before-count" "truncated" 1 1 ctorPrefix
  decErr "count-limit" "array count exceeds caller limit" 2 1 (ctorPrefix ++ u32 1)
  decErr "count-before-child" "array count exceeds caller limit" 2 2 (ctorPrefix ++ u32 2)
  -- exact budgets/order/trailing/truncation (11–20)
  let ((e, er), ec) ← lift "empty" (decodePatternV1 1 (bud 1) (start (hex ctorEmpty)))
  expect (e == .constructor on #[] && er.remainingNodes == 0) "empty"; lift "empty-f" (finish ec)
  decErr "child-depth" "depth budget exhausted" 1 2 (hex ctorWild)
  decErr "child-node" "array count exceeds caller limit" 2 1 (hex ctorWild)
  decErr "sibling-node" "node budget exhausted" 3 3
    (ctorPrefix ++ u32 2 ++ wrap (hex wild) ++ hex wild)
  let ((ord, rr), oc) ← lift "order" (decodePatternV1 2 (bud 3) (start (ctorPrefix ++ u32 2 ++ hex bindX ++ hex wild)))
  expect (ord == .constructor ab #[.bind x, .wildcard] && rr.remainingNodes == 0) "order/residual"; lift "order-f" (finish oc)
  expectErr "trailing" "trailing bytes" (do let ((_, _), c) ← decodePatternV1 1 (bud 1) (start (hex (wild++"00"))); finish c)
  decErr "trunc-tag" "truncated" 2 2 (hex "100000005061")
  decErr "trunc-fc" "truncated" 2 2 (stripFc (hex wild))
  decErr "qid-invalid-child" "source qualified id must contain 2..256 components" 3 3
    (hex "130000005061747465726e2e436f6e7374727563746f72020001000000010000004101000000" ++ hex wild)
  decErr "first-sibling" "invalid bool marker" 2 3
    (ctorPrefix ++ u32 2 ++ hex "0f0000005061747465726e2e4c69746572616c01000c0000004c69746572616c2e426f6f6c010002" ++ hex wild)
  -- depth maxima (21–24)
  let deep255 := wrapN 255 (hex wild)
  let ((_, r21), c21) ← lift "deep255" (decodePatternV1 256 (bud 256) (start deep255))
  expect (r21.remainingNodes == 0) "deep255 residual"; lift "deep255-f" (finish c21)
  decErr "deep256" "depth budget exhausted" 256 257 (wrap deep255)
  decErr "deep-node" "array count exceeds caller limit" 256 255 deep255
  let ((_, r24), _) ← lift "spare" (decodePatternV1 256 (bud 257) (start deep255))
  expect (r24.remainingNodes == 1) "spare residual"

end Tests.Language.SourceAstPatternDecodeV1
