import ProofForgeV2.Source.AstCanonicalRootV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramCodecV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireCodecV1

namespace Tests.Language.SourceAstCanonicalRootV1
open ProofForgeV2.Source.AstCanonicalRootV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramCodecV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
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

private def qn (ps : Array String) : IO SourceQualifiedNameV1 :=
  lift "qn" (parseSourceQualifiedNameV1 ps)

private def wErr := "integer width must be one of 8,16,32,64,128,256"
private def structEmpty := "struct fields must be nonempty"
private def itemsEmpty := "program items must be nonempty"
private def qidErr := "source qualified id must contain 2..256 components"
private def strictErr := "program identity must strictly extend the module name"
private def prefixErr := "program identity must begin with the exact module name components"
private def nameMismatch := "program name must equal the last program identity component"
private def programTagPrefix := "0700000050726f6772616d"

/-- Direct root composition without outer tag (no production root helper). -/
private def composeRoot (mod id : SourceQualifiedNameV1) (p : ProgramV1) :
    Except String ByteArray := do
  let mB ← encodeSourceQualifiedNameV1 mod
  let iB ← encodeSourceQualifiedNameV1 id
  let pB ← encodeProgramV1 p
  pure (mB.append (iB.append pB))

/-- D1-PA-104: mechanical canonical root vectors (not LANG-valid programs). -/
def run : IO Unit := do
  let enabled ← name "enabled"; let maxN ← name "max"
  let demoN ← name "Demo"; let mainN ← name "Main"; let store ← name "Store"
  let st : StateDeclV1 := { visibility := .public_, name := enabled, type_ := .bool }
  let co : ConstDeclV1 := { name := maxN, type_ := .uint 256, value := .literal (.integer 4096) }
  let iSt := ProgramItemV1.state st
  let iCo := ProgramItemV1.const co
  let modRoot ← qn #["Root"]
  let idRootDemo ← qn #["Root", "Demo"]
  let modAB ← qn #["A", "B"]
  let idABMain ← qn #["A", "B", "Main"]
  let demoOnly ← qn #["Demo"]
  let pair ← qn #["Demo", "Counter"]
  let elsewhere ← qn #["Elsewhere", "Counter"]
  -- Mechanical only: state-only has zero Entry/View; not LANG set-valid / not pipeline-ready.
  let pState : ProgramV1 := { name := demoN, items := #[iSt] }
  let pTwo : ProgramV1 := { name := demoN, items := #[iSt, iCo] }
  let pMain : ProgramV1 := { name := mainN, items := #[iSt] }
  expectHex "root_state_ok"
    "0100000004000000526f6f740200000004000000526f6f740400000044656d6f0700000050726f6772616d02000400000044656d6f010000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
    (canonicalSourceAstBytesV1 modRoot idRootDemo pState)
  expectHex "root_two_order"
    "0100000004000000526f6f740200000004000000526f6f740400000044656d6f0700000050726f6772616d02000400000044656d6f020000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c000009000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
    (canonicalSourceAstBytesV1 modRoot idRootDemo pTwo)
  expectHex "root_deep_mod"
    "02000000010000004101000000420300000001000000410100000042040000004d61696e0700000050726f6772616d0200040000004d61696e010000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
    (canonicalSourceAstBytesV1 modAB idABMain pMain)
  let b1 ← lift "root_state_ok_b" (canonicalSourceAstBytesV1 modRoot idRootDemo pState)
  let b2 ← lift "root_two_order_b" (canonicalSourceAstBytesV1 modRoot idRootDemo pTwo)
  let b3 ← lift "root_deep_mod_b" (canonicalSourceAstBytesV1 modAB idABMain pMain)
  let c1 ← lift "compose_state" (composeRoot modRoot idRootDemo pState)
  let c2 ← lift "compose_two" (composeRoot modRoot idRootDemo pTwo)
  let c3 ← lift "compose_deep" (composeRoot modAB idABMain pMain)
  expect (bytesHex b1 == bytesHex c1) "compose_state_ok"
  expect (bytesHex b2 == bytesHex c2) "compose_two_order"
  expect (bytesHex b3 == bytesHex c3) "compose_deep_mod"
  let h1 := bytesHex b1
  expect (h1.take 8 == "01000000") "module_array_prefix"
  expect (decide !(h1.take programTagPrefix.length == programTagPrefix)) "no_program_outer_prefix"
  expectErrExact "root_qid1" qidErr
    (canonicalSourceAstBytesV1 demoOnly demoOnly pState)
  expectErrExact "root_equal_two" strictErr
    (canonicalSourceAstBytesV1 pair pair pState)
  expectErrExact "root_nonprefix" prefixErr
    (canonicalSourceAstBytesV1 demoOnly elsewhere pState)
  let emptyWrong : ProgramV1 := { name := mainN, items := #[] }
  expectErrExact "root_badjoin_before_name_empty" prefixErr
    (canonicalSourceAstBytesV1 demoOnly elsewhere emptyWrong)
  expectErrExact "root_name_before_empty" nameMismatch
    (canonicalSourceAstBytesV1 modRoot idRootDemo emptyWrong)
  expectErrExact "root_empty_items" itemsEmpty
    (canonicalSourceAstBytesV1 modRoot idRootDemo { name := demoN, items := #[] })
  expectErrExact "root_struct_empty" structEmpty
    (canonicalSourceAstBytesV1 modRoot idRootDemo {
      name := demoN
      items := #[ProgramItemV1.struct { name := store, fields := #[] }] })
  let Lbad : ExprV1 := .literal (.integer (2 ^ 256))
  expectErrExact "root_const_w24" wErr
    (canonicalSourceAstBytesV1 modRoot idRootDemo {
      name := demoN
      items := #[ProgramItemV1.const { name := maxN, type_ := .uint 24, value := Lbad }] })

end Tests.Language.SourceAstCanonicalRootV1
