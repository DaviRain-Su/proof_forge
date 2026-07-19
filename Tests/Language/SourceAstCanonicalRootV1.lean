import ProofForgeV2.Core.Common
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
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireCodecV1

namespace Tests.Language.SourceAstCanonicalRootV1
open ProofForgeV2.Core.Common
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
open ProofForgeV2.Source.ValidatedSourceV1
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

  -- D1-PA-108: the product publish/hash API accepts only a validated source unit.
  let runN ← name "run"
  let validBlock : BlockV1 := { statements := #[.return_ none] }
  let emptyBlock : BlockV1 := { statements := #[] }
  let entryWith (n : SourceNameComponentV1) (body : BlockV1) : EntryDeclV1 :=
    { name := n, params := #[], result := .unit, body }
  let validProgram : ProgramV1 := {
    name := demoN
    items := #[iSt, .entry (entryWith runN validBlock)] }
  let valid ← lift "validated_source"
    (validateSourceV1 modRoot idRootDemo validProgram)
  expect (valid.moduleName == modRoot) "validated module projection"
  expect (valid.programIdentity == idRootDemo) "validated identity projection"
  expect (valid.program == validProgram) "validated program projection"
  let validHex :=
    "0100000004000000526f6f740200000004000000526f6f740400000044656d6f0700000050726f6772616d02000400000044656d6f020000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c000009000000456e7472794465636c04000300000072756e0000000009000000547970652e556e6974000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"
  let validBytes ← lift "validated_bytes" (canonicalValidatedSourceAstBytesV1 valid)
  expect (bytesHex validBytes == validHex) s!"validated bytes: got {bytesHex validBytes}"
  let validHash ← lift "validated_hash" (sourceHashV1 valid)
  expect (validHash.bytes.size == 32) "source hash width"
  let rendered ← lift "render source hash" (renderDigest validHash)
  expect (rendered ==
    "sha256:bdad32dda5c3aa2862acc50855a7908a96745b493e58e6b06ecce1d31cdc6ec9")
    s!"source hash: got {rendered}"

  let modA ← qn #["A"]
  let idADemo ← qn #["A", "Demo"]
  let otherN ← name "Other"
  let idRootOther ← qn #["Root", "Other"]
  let moduleTwin ← lift "module_twin" (validateSourceV1 modA idADemo validProgram)
  let identityTwin ← lift "identity_twin" (validateSourceV1 modRoot idRootOther {
    name := otherN, items := validProgram.items })
  let orderTwin ← lift "order_twin" (validateSourceV1 modRoot idRootDemo {
    name := demoN, items := #[.entry (entryWith runN validBlock), iSt] })
  for (label, twin) in #[
      ("module", moduleTwin), ("identity", identityTwin), ("order", orderTwin)] do
    let twinBytes ← lift s!"{label}_bytes" (canonicalValidatedSourceAstBytesV1 twin)
    let twinHash ← lift s!"{label}_hash" (sourceHashV1 twin)
    expect (twinBytes != validBytes) s!"{label} bytes must differ"
    expect (twinHash.bytes != validHash.bytes) s!"{label} hash must differ"

  expectErrExact "validated_wrong_prefix" prefixErr
    (validateSourceV1 demoOnly elsewhere validProgram)
  expectErrExact "validated_wrong_name" nameMismatch
    (validateSourceV1 modRoot idRootDemo { name := mainN, items := validProgram.items })
  let emptyBodyProgram : ProgramV1 := {
    name := demoN, items := #[iSt, .entry (entryWith runN emptyBlock)] }
  expectErrExact "validated_empty_block" "block statements must be nonempty"
    (validateSourceV1 modRoot idRootDemo emptyBodyProgram)
  expectErrExact "validated_zero_entry_view" "program must declare at least one entry or view"
    (validateSourceV1 modRoot idRootDemo pState)
  let dupStateProgram : ProgramV1 := {
    name := demoN, items := #[iSt, iSt, .entry (entryWith runN validBlock)] }
  expectErrExact "validated_duplicate_state" "program contains duplicate state declarations"
    (validateSourceV1 modRoot idRootDemo dupStateProgram)
  let shapeAndSetBad : ProgramV1 := {
    name := demoN, items := #[iSt, iSt, .entry (entryWith runN emptyBlock)] }
  expectErrExact "validated_shape_before_set" "block statements must be nonempty"
    (validateSourceV1 modRoot idRootDemo shapeAndSetBad)

end Tests.Language.SourceAstCanonicalRootV1
