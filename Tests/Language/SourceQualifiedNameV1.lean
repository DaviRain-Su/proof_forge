import Lean
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireCodecV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceQualifiedNameV1
open Lean
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
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

private def hexVal (c : Char) : Nat :=
  if '0' ≤ c && c ≤ '9' then c.toNat - '0'.toNat
  else 10 + c.toNat - 'a'.toNat

private def fromHex (s : String) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  let cs := s.toList.toArray
  let mut i := 0
  while i + 1 < cs.size do
    out := out.push (UInt8.ofNat (hexVal cs[i]! * 16 + hexVal cs[i + 1]!))
    i := i + 2
  pure out

private def qnExact := "source qualified name must contain 1..256 components"
private def qidExact := "source qualified id must contain 2..256 components"

private def roundTripQN (label : String) (n : SourceQualifiedNameV1) : IO Unit := do
  let bytes ← lift s!"{label} enc" (encodeSourceQualifiedNameV1 n)
  match decodeSourceQualifiedNameV1 (start bytes) with
  | .error e => throw <| IO.userError s!"{label} dec: {e}"
  | .ok (n', c) => do
      expect (n' == n) s!"{label} BEq"
      match finish c with
      | .error e => throw <| IO.userError s!"{label} finish: {e}"
      | .ok () => pure ()

private def roundTripQID (label : String) (n : SourceQualifiedNameV1) : IO Unit := do
  let bytes ← lift s!"{label} enc" (encodeSourceQualifiedIdV1 n)
  match decodeSourceQualifiedIdV1 (start bytes) with
  | .error e => throw <| IO.userError s!"{label} dec: {e}"
  | .ok (n', c) => do
      expect (n' == n) s!"{label} BEq"
      match finish c with
      | .error e => throw <| IO.userError s!"{label} finish: {e}"
      | .ok () => pure ()

/-- D1-PA-94 RED: QualifiedNameV1 production APIs missing → focused build fails. -/
def run : IO Unit := do
  let demo ← lift "Demo" (parseSourceQualifiedNameV1 #["Demo"])
  expectHex "Demo wire" "010000000400000044656d6f" (encodeSourceQualifiedNameV1 demo)
  let pair ← lift "pair" (parseSourceQualifiedNameV1 #["Demo", "Counter"])
  expectHex "pair wire" "020000000400000044656d6f07000000436f756e746572"
    (encodeSourceQualifiedNameV1 pair)
  let hy ← lift "hyphen" (parseSourceQualifiedNameV1 #["foo-bar"])
  expectHex "hyphen wire" "0100000007000000666f6f2d626172" (encodeSourceQualifiedNameV1 hy)
  let openG ← lift "open" (parseSourceQualifiedNameV1 #["«"])
  expectHex "open wire" "0100000002000000c2ab" (encodeSourceQualifiedNameV1 openG)
  let leanPair ← lift "lean" (sourceQualifiedNameV1FromLeanName (`Demo.Counter))
  expect (leanPair == pair) "lean Demo.Counter"
  lift "qid2" (validateSourceQualifiedIdV1 pair)
  let many256 ← lift "256" (parseSourceQualifiedNameV1 (Array.replicate 256 "C"))
  roundTripQID "qid256" many256
  let fixedDemo := fromHex "010000000400000044656d6f"
  match decodeSourceQualifiedNameV1 (start fixedDemo) with
  | .error e => throw <| IO.userError e
  | .ok (d, c) => do
      expect (d == demo) "direct decode"
      match finish c with | .error e => throw <| IO.userError e | .ok () => pure ()
  roundTripQN "rt_demo" demo
  roundTripQN "rt_pair" pair
  roundTripQID "rt_qid" pair
  lift "join ok" (validateSourceProgramIdentityV1 demo pair)
  expectErr "empty" (parseSourceQualifiedNameV1 #[])
  expectErr "257" (parseSourceQualifiedNameV1 (Array.replicate 257 "C"))
  expectErr "qid1" (validateSourceQualifiedIdV1 demo)
  expectErr "comp empty" (parseSourceQualifiedNameV1 #[""])
  expectErr "comp nfd" (parseSourceQualifiedNameV1 #["e\u0301"])
  expectErr "comp cc" (parseSourceQualifiedNameV1 #["a\u0000"])
  expectErr "comp close" (parseSourceQualifiedNameV1 #["»"])
  expectErr "anon" (sourceQualifiedNameV1FromLeanName Name.anonymous)
  expectErr "final num" (sourceQualifiedNameV1FromLeanName (Name.mkNum `Demo 1))
  expectErr "prefix num" (sourceQualifiedNameV1FromLeanName (Name.mkStr (Name.mkNum .anonymous 1) "x"))
  expectErr "join equal" (validateSourceProgramIdentityV1 pair pair)
  let other ← lift "other" (parseSourceQualifiedNameV1 #["Elsewhere", "Counter"])
  expectErr "join non-prefix" (validateSourceProgramIdentityV1 demo other)
  -- count-before-child: invalid count must not require valid child payload
  expectErrExact "qn count0" qnExact
    (decodeSourceQualifiedNameV1 (start (fromHex "00000000")))
  expectErrExact "qn count257" qnExact
    (decodeSourceQualifiedNameV1 (start (fromHex "01010000ff")))
  expectErrExact "qid count0" qidExact
    (decodeSourceQualifiedIdV1 (start (fromHex "00000000")))
  expectErrExact "qid count1" qidExact
    (decodeSourceQualifiedIdV1 (start (fromHex "01000000ff")))
  expectErrExact "qid count257" qidExact
    (decodeSourceQualifiedIdV1 (start (fromHex "01010000")))
  -- ofComponents path
  let cDemo ← lift "cDemo" (parseSourceNameComponentV1 "Demo")
  let viaOf ← lift "of" (sourceQualifiedNameV1OfComponents #[cDemo])
  expect (viaOf == demo) "ofComponents"

end Tests.Language.SourceQualifiedNameV1
