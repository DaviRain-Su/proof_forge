import ProofForgeV2.Source.AstDeclCodecV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemCodecV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineDeclCodecV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace Tests.Language.SourceAstProgramItemV1
open ProofForgeV2.Source.AstDeclCodecV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemCodecV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineDeclCodecV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
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

/-- Fixed hex + no-wrapper identity vs direct record encoder. -/
private def expectItem (label want : String)
    (itemR directR : Except String ByteArray) : IO Unit :=
  match itemR, directR with
  | .ok ib, .ok db => do
    expect (bytesHex ib == want) s!"{label}: got {bytesHex ib}"
    expect (bytesHex ib == bytesHex db) s!"{label}: item≠direct"
  | .error e, _ => throw <| IO.userError s!"{label}: {e}"
  | _, .error e => throw <| IO.userError s!"{label}: direct {e}"

private def name (s : String) : IO SourceNameComponentV1 :=
  lift s (parseSourceNameComponentV1 s)

private def qn (ps : Array String) : IO SourceQualifiedNameV1 :=
  lift "qn" (parseSourceQualifiedNameV1 ps)

private def wErr := "integer width must be one of 8,16,32,64,128,256"
private def structEmpty := "struct fields must be nonempty"
private def blockEmpty := "block statements must be nonempty"
private def qidErr := "source qualified id must contain 2..256 components"
private def dig00 := "sha256:0000000000000000000000000000000000000000000000000000000000000000"

/-- D1-PA-102 phase-neutral: ProgramItem sum pure-dispatch wire vectors. -/
def run : IO Unit := do
  let enabled ← name "enabled"; let count ← name "count"; let store ← name "Store"
  let choice ← name "Choice"; let noneN ← name "None"; let someN ← name "Some"
  let ping ← name "Ping"; let emptyE ← name "Empty"; let safe ← name "safe"
  let maxN ← name "max"; let bounded ← name "bounded"; let start ← name "start"
  let secret ← name "secret"; let runN ← name "run"; let to ← name "to"
  let amount ← name "amount"; let note ← name "note"; let get ← name "get"
  let helper2 ← name "helper2"; let x ← name "x"
  let only ← qn #["Only"]; let demoFeature ← qn #["Demo", "Feature"]
  let proofsSafe ← qn #["Proofs", "safe"]
  let fdCount : FieldDeclV1 := { name := count, type_ := .uint 256 }
  let varNone : EnumVariantV1 := { name := noneN, payloadTypes := #[] }
  let varSome : EnumVariantV1 := { name := someN, payloadTypes := #[.bool, .principal] }
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
  let st : StateDeclV1 := { visibility := .public_, name := enabled, type_ := .bool }
  let su : StructDeclV1 := { name := store, fields := #[fdCount] }
  let en : EnumDeclV1 := { name := choice, variants := #[varNone, varSome] }
  let co : ConstDeclV1 := { name := maxN, type_ := .uint 256, value := L4096 }
  let ev : EventDeclV1 := { name := ping, params := #[] }
  let er : ErrorDeclV1 := { name := emptyE, params := #[] }
  let ini : InitDeclV1 := { params := #[pStart, pSecret], body := blkAssign }
  let ent : EntryDeclV1 :=
    { name := runN, params := #[pTo, pAmount, pNote], result := .uint 64, body := blkRetCount }
  let vw : ViewDeclV1 := { name := get, params := #[], result := .uint 64, body := blkRet0 }
  let fnD : FnDeclV1 := { name := helper2, params := #[pX], result := .unit, body := blkIf }
  let inv : InvariantDeclV1 := { name := bounded, predicate := eLt }
  let ext : ExtensionReqV1 := { id := demoFeature, version := "1.0.0", digest := dig00 }
  let pr : ProofDeclV1 := { invariant := safe, kind := .holds, theorem_ := proofsSafe }
  let iSt := ProgramItemV1.state st; let iSu := ProgramItemV1.struct su
  let iEn := ProgramItemV1.enum en; let iCo := ProgramItemV1.const co
  let iEv := ProgramItemV1.event ev; let iEr := ProgramItemV1.error er
  let iIn := ProgramItemV1.init ini; let iEnt := ProgramItemV1.entry ent
  let iVw := ProgramItemV1.view vw; let iFn := ProgramItemV1.fn fnD
  let iInv := ProgramItemV1.invariant inv; let iExt := ProgramItemV1.extensionReq ext
  let iPr := ProgramItemV1.proof pr
  expectItem "item_state"
    "0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
    (encodeProgramItemV1 iSt) (encodeStateDeclV1 st)
  expectItem "item_struct"
    "0a0000005374727563744465636c02000500000053746f726501000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"
    (encodeProgramItemV1 iSu) (encodeStructDeclV1 su)
  expectItem "item_enum"
    "08000000456e756d4465636c02000600000043686f696365020000000b000000456e756d56617269616e740200040000004e6f6e65000000000b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000"
    (encodeProgramItemV1 iEn) (encodeEnumDeclV1 en)
  expectItem "item_const"
    "09000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
    (encodeProgramItemV1 iCo) (encodeConstDeclV1 co)
  expectItem "item_event"
    "090000004576656e744465636c02000400000050696e6700000000"
    (encodeProgramItemV1 iEv) (encodeEventDeclV1 ev)
  expectItem "item_error"
    "090000004572726f724465636c020005000000456d70747900000000"
    (encodeProgramItemV1 iEr) (encodeErrorDeclV1 er)
  expectItem "item_init"
    "08000000496e69744465636c02000200000005000000506172616d0300110000005669736962696c6974792e5075626c6963000005000000737461727409000000547970652e55496e740100400005000000506172616d0300120000005669736962696c6974792e507269766174650000060000007365637265740a000000547970652e4669656c64010008000000626e3235345f667205000000426c6f636b0100010000000b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"
    (encodeProgramItemV1 iIn) (encodeInitDeclV1 ini)
  expectItem "item_entry"
    "09000000456e7472794465636c04000300000072756e0300000005000000506172616d0300110000005669736962696c6974792e5075626c6963000002000000746f0e000000547970652e5072696e636970616c000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e427974657301000000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e74"
    (encodeProgramItemV1 iEnt) (encodeEntryDeclV1 ent)
  expectItem "item_view"
    "08000000566965774465636c0400030000006765740000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000"
    (encodeProgramItemV1 iVw) (encodeViewDeclV1 vw)
  expectItem "item_fn"
    "06000000466e4465636c04000700000068656c706572320100000005000000506172616d0300110000005669736962696c6974792e5075626c69630000010000007809000000547970652e55496e740100400009000000547970652e556e6974000005000000426c6f636b0100010000000700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000"
    (encodeProgramItemV1 iFn) (encodeFnDeclV1 fnD)
  expectItem "item_invariant"
    "0d000000496e76617269616e744465636c020007000000626f756e6465640b000000457870722e42696e61727903000b00000042696e6172794f702e4c7400000a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
    (encodeProgramItemV1 iInv) (encodeInvariantDeclV1 inv)
  expectItem "item_extension_req"
    "0c000000457874656e73696f6e5265710300020000000400000044656d6f070000004665617475726505000000312e302e30470000007368613235363a30303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030"
    (encodeProgramItemV1 iExt) (encodeExtensionReqV1 ext)
  expectItem "item_proof"
    "0900000050726f6f664465636c030004000000736166650f00000050726f6f664b696e642e486f6c64730000020000000600000050726f6f66730400000073616665"
    (encodeProgramItemV1 iPr) (encodeProofDeclV1 pr)
  expect (decide (iSt = iSt)) "eq_state"; expect (decide (iSu = iSu)) "eq_struct"
  expect (decide (iEn = iEn)) "eq_enum"; expect (decide (iCo = iCo)) "eq_const"
  expect (decide (iEv = iEv)) "eq_event"; expect (decide (iEr = iEr)) "eq_error"
  expect (decide (iIn = iIn)) "eq_init"; expect (decide (iEnt = iEnt)) "eq_entry"
  expect (decide (iVw = iVw)) "eq_view"; expect (decide (iFn = iFn)) "eq_fn"
  expect (decide (iInv = iInv)) "eq_inv"; expect (decide (iExt = iExt)) "eq_ext"
  expect (decide (iPr = iPr)) "eq_proof"
  -- Event/Error same name+params shape
  let sameEv : EventDeclV1 := { name := ping, params := #[] }
  let sameEr : ErrorDeclV1 := { name := ping, params := #[] }
  let iSameEv := ProgramItemV1.event sameEv
  let iSameEr := ProgramItemV1.error sameEr
  expect (decide (iSameEv ≠ iSameEr)) "event_error_eq_nonalias"
  let bSameEv ← lift "ev" (encodeProgramItemV1 iSameEv)
  let bSameEr ← lift "er" (encodeProgramItemV1 iSameEr)
  expect (decide (bytesHex bSameEv ≠ bytesHex bSameEr)) "event_error_byte_nonalias"
  -- Entry/View/Fn same name/params/result/body
  let sameEnt : EntryDeclV1 :=
    { name := get, params := #[], result := .uint 64, body := blkRet0 }
  let sameVw : ViewDeclV1 :=
    { name := get, params := #[], result := .uint 64, body := blkRet0 }
  let sameFn : FnDeclV1 :=
    { name := get, params := #[], result := .uint 64, body := blkRet0 }
  let iSE := ProgramItemV1.entry sameEnt
  let iSV := ProgramItemV1.view sameVw
  let iSF := ProgramItemV1.fn sameFn
  expect (decide (iSE ≠ iSV)) "entry_view_eq"; expect (decide (iSE ≠ iSF)) "entry_fn_eq"
  expect (decide (iSV ≠ iSF)) "view_fn_eq"
  let bSE ← lift "se" (encodeProgramItemV1 iSE)
  let bSV ← lift "sv" (encodeProgramItemV1 iSV)
  let bSF ← lift "sf" (encodeProgramItemV1 iSF)
  expect (decide (bytesHex bSE ≠ bytesHex bSV)) "entry_view_byte"
  expect (decide (bytesHex bSE ≠ bytesHex bSF)) "entry_fn_byte"
  expect (decide (bytesHex bSV ≠ bytesHex bSF)) "view_fn_byte"
  expectErrExact "item_struct_empty" structEmpty
    (encodeProgramItemV1 (ProgramItemV1.struct { name := store, fields := #[] }))
  expectErrExact "item_const_w24" wErr
    (encodeProgramItemV1
      (ProgramItemV1.const { name := maxN, type_ := .uint 24, value := Lbad }))
  expectErrExact "item_init_empty_block" blockEmpty
    (encodeProgramItemV1 (ProgramItemV1.init { params := #[pStart], body := blkEmpty }))
  expectErrExact "item_ext_qid_before_hostile" qidErr
    (encodeProgramItemV1 (ProgramItemV1.extensionReq {
      id := only, version := "not-a-semver", digest := "bad" }))

end Tests.Language.SourceAstProgramItemV1
