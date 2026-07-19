import ProofForgeV2.Language.Syntax
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireCodecV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceNameComponentV1.Fixture
open ProofForgeV2.Language

/-- Explicit underscore program name: Lean `.str` raw `_` (not anonymous). -/
program «_» where
  entry ping() : UInt64 do
    return 0

end Tests.Language.SourceNameComponentV1.Fixture

namespace Tests.Language.SourceNameComponentV1
open Lean
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireCodecV1
open ProofForgeV2.Source.WireDecodeV1

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

private def roundTrip (label : String) (c : SourceNameComponentV1) : IO Unit := do
  let bytes ← lift s!"{label} enc" (encodeSourceNameComponentV1 c)
  match decodeSourceNameComponentV1 (start bytes) with
  | .error e => throw <| IO.userError s!"{label} dec: {e}"
  | .ok (c', cur) => do
      expect (c' == c) s!"{label} BEq"
      match finish cur with
      | .error e => throw <| IO.userError s!"{label} finish: {e}"
      | .ok () => pure ()

private def raw240 : String := String.mk (List.replicate 240 'A')

/-- D1-PA-93 RED: NameComponentV1 production missing → focused build fails. -/
def run : IO Unit := do
  let simple ← lift "simple" (parseSourceNameComponentV1 "Counter")
  expect (simple.raw == "Counter") "simple raw"
  expect (renderSourceNameComponentV1 simple == "Counter") "simple render"
  expectHex "simple wire" "07000000436f756e746572" (encodeSourceNameComponentV1 simple)
  let alpha ← lift "alpha" (parseSourceNameComponentV1 "α")
  expect (alpha.raw == "α" && renderSourceNameComponentV1 alpha == "α") "alpha"
  let us ← lift "us" (parseSourceNameComponentV1 "_")
  expect (us.raw == "_" && renderSourceNameComponentV1 us == "_") "underscore"
  let leanUs ← lift "leanUs" (sourceNameComponentV1FromLeanName (Name.mkStr .anonymous "_"))
  expect (leanUs.raw == "_") "fromLean _"
  let digit ← lift "1bad" (parseSourceNameComponentV1 "1bad")
  expect (digit.raw == "1bad") "1bad raw"
  expectHex "1bad wire" "0400000031626164" (encodeSourceNameComponentV1 digit)
  let hy ← lift "hyphen" (parseSourceNameComponentV1 "foo-bar")
  expect (hy.raw == "foo-bar") "hyphen raw"
  expect (renderSourceNameComponentV1 hy == "«foo-bar»") "hyphen render"
  expect (hy.raw != renderSourceNameComponentV1 hy) "hyphen raw≠render"
  let dot ← lift "dot" (parseSourceNameComponentV1 "foo.bar")
  expect (dot.raw == "foo.bar" && renderSourceNameComponentV1 dot == "«foo.bar»") "dot"
  let sp ← lift "space" (parseSourceNameComponentV1 "foo bar")
  expect (sp.raw == "foo bar" && renderSourceNameComponentV1 sp == "«foo bar»") "space"
  let openG ← lift "open" (parseSourceNameComponentV1 "«")
  expect (openG.raw == "«" && renderSourceNameComponentV1 openG == "««»") "open guillemet"
  let openBody ← lift "open body" (parseSourceNameComponentV1 "a«b")
  expect (renderSourceNameComponentV1 openBody == "«a«b»") "open body render"
  let kw ← lift "struct" (parseSourceNameComponentV1 "struct")
  expect (kw.raw == "struct") "keyword body"
  let long ← lift "240" (parseSourceNameComponentV1 raw240)
  expect (long.raw.utf8ByteSize == 240) "240"
  expectErr "empty" (parseSourceNameComponentV1 "")
  expectErr "241" (parseSourceNameComponentV1 (raw240.push 'B'))
  expectErr "nfd" (parseSourceNameComponentV1 "e\u0301")
  expectErr "cc" (parseSourceNameComponentV1 "a\u0000b")
  expectErr "closing" (parseSourceNameComponentV1 "»")
  expectErr "closing-in" (parseSourceNameComponentV1 "foo»bar")
  expectErr "anonymous" (sourceNameComponentV1FromLeanName Name.anonymous)
  expectErr "num" (sourceNameComponentV1FromLeanName (Name.mkNum .anonymous 1))
  -- injectivity: embedded-dot accept vs closing guillemet reject
  let _ ← lift "foo.bar" (parseSourceNameComponentV1 "foo.bar")
  expectErr "close-raw" (parseSourceNameComponentV1 "foo»bar")
  expectHex "fixed" "0400000031626164"
    (encodeSourceNameComponentV1 (← lift "d" (parseSourceNameComponentV1 "1bad")))
  let fixed := ByteArray.mk #[4, 0, 0, 0, 49, 98, 97, 100]
  match decodeSourceNameComponentV1 (start fixed) with
  | .error e => throw <| IO.userError s!"fixed decode: {e}"
  | .ok (c, cur) => do
      expect (c.raw == "1bad") "fixed decode raw"
      match finish cur with
      | .ok () => pure ()
      | .error e => throw <| IO.userError s!"fixed finish: {e}"
  roundTrip "rt_simple" simple
  roundTrip "rt_hyphen" hy
  roundTrip "rt_1bad" digit
  -- encodeIdent migration surface (must accept 1bad after GREEN)
  expectHex "encodeIdent 1bad" "0400000031626164" (encodeIdent "1bad")

end Tests.Language.SourceNameComponentV1
