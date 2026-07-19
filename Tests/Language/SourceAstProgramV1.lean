import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramCodecV1
import ProofForgeV2.Source.AstProgramItemCodecV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireCodecV1

namespace Tests.Language.SourceAstProgramV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramCodecV1
open ProofForgeV2.Source.AstProgramItemCodecV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireCodecV1

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
private def structEmpty := "struct fields must be nonempty"
private def itemsEmpty := "program items must be nonempty"
/-- ASCII `Program` tagged header: u32le(7) || "Program" (fieldCount not included). -/
private def programTagPrefix := "0700000050726f6772616d"

private def expectProgramTagPrefix (label : String) (b : ByteArray) : IO Unit :=
  let h := bytesHex b
  expect (h.take programTagPrefix.length == programTagPrefix)
    s!"{label}: missing Program tag prefix, got {h.take 32}"

/-- Hand composition of Program/2 (no moduleName/programIdentity root bytes). -/
private def composeProgram (n : SourceNameComponentV1) (items : Array ProgramItemV1) :
    Except String ByteArray := do
  let nameB ← encodeSourceNameComponentV1 n
  let itemsB ← encodeArray encodeProgramItemV1 items
  encodeTagged "Program" #[nameB, itemsB]

/-- D1-PA-103: Program tagged-value mechanical codec vectors (not LANG-valid programs). -/
def run : IO Unit := do
  let demo ← name "Demo"
  let enabled ← name "enabled"
  let maxN ← name "max"
  let store ← name "Store"
  let st : StateDeclV1 := { visibility := .public_, name := enabled, type_ := .bool }
  let co : ConstDeclV1 := { name := maxN, type_ := .uint 256, value := .literal (.integer 4096) }
  let iSt := ProgramItemV1.state st
  let iCo := ProgramItemV1.const co
  let p1 : ProgramV1 := { name := demo, items := #[iSt] }
  let p2 : ProgramV1 := { name := demo, items := #[iSt, iCo] }
  let p3 : ProgramV1 := { name := demo, items := #[iCo, iSt] }
  -- Mechanical codec boundary only: state-only has zero Entry/View; not invariant-valid.
  expectHex "prog_state_only"
    "0700000050726f6772616d02000400000044656d6f010000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
    (encodeProgramV1 p1)
  expectHex "prog_two_order"
    "0700000050726f6772616d02000400000044656d6f020000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c000009000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
    (encodeProgramV1 p2)
  expectHex "prog_two_reversed"
    "0700000050726f6772616d02000400000044656d6f0200000009000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
    (encodeProgramV1 p3)
  let b1 ← lift "prog_state_only_bytes" (encodeProgramV1 p1)
  let b2 ← lift "prog_two_order_bytes" (encodeProgramV1 p2)
  let b3 ← lift "prog_two_reversed_bytes" (encodeProgramV1 p3)
  expectProgramTagPrefix "prog_state_only" b1
  expectProgramTagPrefix "prog_two_order" b2
  expectProgramTagPrefix "prog_two_reversed" b3
  let c1 ← lift "compose_state" (composeProgram demo #[iSt])
  let c2 ← lift "compose_order" (composeProgram demo #[iSt, iCo])
  let c3 ← lift "compose_rev" (composeProgram demo #[iCo, iSt])
  expect (bytesHex b1 == bytesHex c1) "compose_state_only"
  expect (bytesHex b2 == bytesHex c2) "compose_two_order"
  expect (bytesHex b3 == bytesHex c3) "compose_two_reversed"
  expect (decide (bytesHex b2 ≠ bytesHex b3)) "order_byte_nonalias"
  expect (decide (p1 = p1)) "eq_self"
  expect (decide (p2 ≠ p3)) "eq_order_swapped"
  expectErrExact "prog_empty_items" itemsEmpty
    (encodeProgramV1 { name := demo, items := #[] })
  expectErrExact "prog_struct_empty" structEmpty
    (encodeProgramV1 {
      name := demo
      items := #[ProgramItemV1.struct { name := store, fields := #[] }] })
  let Lbad : ExprV1 := .literal (.integer (2 ^ 256))
  expectErrExact "prog_const_w24" wErr
    (encodeProgramV1 {
      name := demo
      items := #[ProgramItemV1.const { name := maxN, type_ := .uint 24, value := Lbad }] })
  -- Second-item child error after valid state (source-order propagation).
  expectErrExact "prog_second_struct_empty" structEmpty
    (encodeProgramV1 {
      name := demo
      items := #[iSt, ProgramItemV1.struct { name := store, fields := #[] }] })

end Tests.Language.SourceAstProgramV1
