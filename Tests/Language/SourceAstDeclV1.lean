import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstDeclCodecV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace Tests.Language.SourceAstDeclV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstDeclCodecV1
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
private def enumEmpty := "enum variants must be nonempty"
private def qidErr := "source qualified id must contain 2..256 components"
private def verErr := "extension version must use canonical exact SemVer"
private def digErr := "extension digest must use canonical sha256 spelling"
private def dig00 := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
private def digab := "sha256:abababababababababababababababababababababababababababababababab"

/-- D1-PA-98 phase-neutral: declaration-record wire vectors and fail-closed checks. -/
def run : IO Unit := do
  let enabled ← name "enabled"
  let count ← name "count"
  let secret ← name "secret"
  let store ← name "Store"
  let items ← name "items"
  let choice ← name "Choice"
  let noneN ← name "None"
  let someN ← name "Some"
  let ping ← name "Ping"
  let transfer ← name "Transfer"
  let from_ ← name "from"
  let amount ← name "amount"
  let note ← name "note"
  let emptyE ← name "Empty"
  let denied ← name "Denied"
  let reason ← name "reason"
  let safe ← name "safe"
  let only ← qn #["Only"]
  let demoFeature ← qn #["Demo", "Feature"]
  let demoAdvanced ← qn #["Demo", "Advanced"]
  let proofsSafe ← qn #["Proofs", "safe"]
  let fdCount : FieldDeclV1 := { name := count, type_ := .uint 256 }
  let fdItems : FieldDeclV1 := { name := items, type_ := .map .bool .unit }
  let varNone : EnumVariantV1 := { name := noneN, payloadTypes := #[] }
  let varSome : EnumVariantV1 := { name := someN, payloadTypes := #[.bool, .principal] }
  let pFrom : ParamV1 := { visibility := .public_, name := from_, type_ := .principal }
  let pAmount : ParamV1 := { visibility := .private_, name := amount, type_ := .uint 64 }
  let pNote : ParamV1 := { visibility := .commitment, name := note, type_ := .bytes 0 }
  let pReason : ParamV1 := { visibility := .public_, name := reason, type_ := .bool }
  expectHex "state_enabled_public_bool"
    "0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
    (encodeStateDeclV1 { visibility := .public_, name := enabled, type_ := .bool })
  expectHex "state_count_private_u64"
    "0900000053746174654465636c0300120000005669736962696c6974792e50726976617465000005000000636f756e7409000000547970652e55496e7401004000"
    (encodeStateDeclV1 { visibility := .private_, name := count, type_ := .uint 64 })
  expectHex "state_secret_commitment_aob"
    "0900000053746174654465636c0300150000005669736962696c6974792e436f6d6d69746d656e740000060000007365637265740a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000"
    (encodeStateDeclV1 {
      visibility := .commitment, name := secret,
      type_ := .array (.option (.bytes 0)) 0 })
  expectHex "struct_store"
    "0a0000005374727563744465636c02000500000053746f726502000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000"
    (encodeStructDeclV1 { name := store, fields := #[fdCount, fdItems] })
  expectHex "struct_store_single"
    "0a0000005374727563744465636c02000500000053746f726501000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"
    (encodeStructDeclV1 { name := store, fields := #[fdCount] })
  expectHex "struct_store_reversed"
    "0a0000005374727563744465636c02000500000053746f726502000000090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"
    (encodeStructDeclV1 { name := store, fields := #[fdItems, fdCount] })
  expectHex "enum_choice"
    "08000000456e756d4465636c02000600000043686f696365020000000b000000456e756d56617269616e740200040000004e6f6e65000000000b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000"
    (encodeEnumDeclV1 { name := choice, variants := #[varNone, varSome] })
  expectHex "event_ping_empty"
    "090000004576656e744465636c02000400000050696e6700000000"
    (encodeEventDeclV1 { name := ping, params := #[] })
  expectHex "event_transfer"
    "090000004576656e744465636c0200080000005472616e736665720300000005000000506172616d0300110000005669736962696c6974792e5075626c696300000400000066726f6d0e000000547970652e5072696e636970616c000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e4279746573010000000000"
    (encodeEventDeclV1 { name := transfer, params := #[pFrom, pAmount, pNote] })
  expectHex "error_empty"
    "090000004572726f724465636c020005000000456d70747900000000"
    (encodeErrorDeclV1 { name := emptyE, params := #[] })
  expectHex "error_denied"
    "090000004572726f724465636c02000600000044656e6965640100000005000000506172616d0300110000005669736962696c6974792e5075626c6963000006000000726561736f6e09000000547970652e426f6f6c0000"
    (encodeErrorDeclV1 { name := denied, params := #[pReason] })
  expectHex "ext_feature"
    "0c000000457874656e73696f6e5265710300020000000400000044656d6f070000004665617475726505000000312e302e30470000007368613235363a30303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030"
    (encodeExtensionReqV1 { id := demoFeature, version := "1.0.0", digest := dig00 })
  expectHex "ext_advanced"
    "0c000000457874656e73696f6e5265710300020000000400000044656d6f08000000416476616e63656415000000312e322e332d616c7068612e312b6275696c642e35470000007368613235363a61626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162"
    (encodeExtensionReqV1 {
      id := demoAdvanced, version := "1.2.3-alpha.1+build.5", digest := digab })
  expectHex "proof_safe"
    "0900000050726f6f664465636c030004000000736166650f00000050726f6f664b696e642e486f6c64730000020000000600000050726f6f66730400000073616665"
    (encodeProofDeclV1 { invariant := safe, kind := .holds, theorem_ := proofsSafe })
  expectHex "proof_safe_preserving"
    "0900000050726f6f664465636c030004000000736166651400000050726f6f664b696e642e50726573657276696e670000020000000600000050726f6f66730400000073616665"
    (encodeProofDeclV1 { invariant := safe, kind := .preserving, theorem_ := proofsSafe })
  expectErrExact "struct_empty" structEmpty
    (encodeStructDeclV1 { name := store, fields := #[] })
  expectErrExact "enum_empty" enumEmpty
    (encodeEnumDeclV1 { name := choice, variants := #[] })
  expectErrExact "state_w24" wErr
    (encodeStateDeclV1 { visibility := .public_, name := count, type_ := .uint 24 })
  expectErrExact "struct_w24" wErr
    (encodeStructDeclV1 {
      name := store, fields := #[{ name := count, type_ := .uint 24 }] })
  expectErrExact "ext_qid1" qidErr
    (encodeExtensionReqV1 { id := only, version := "1.0.0", digest := dig00 })
  expectErrExact "ext_qid_before_hostile" qidErr
    (encodeExtensionReqV1 { id := only, version := "not-a-semver", digest := "bad" })
  expectErrExact "ext_ver_before_digest" verErr
    (encodeExtensionReqV1 { id := demoFeature, version := "01.0.0", digest := "bad" })
  expectErrExact "ext_bad_digest" digErr
    (encodeExtensionReqV1 { id := demoFeature, version := "1.0.0", digest := "sha256:ZZ" })
  expectErrExact "proof_qid1" qidErr
    (encodeProofDeclV1 { invariant := safe, kind := .holds, theorem_ := only })

end Tests.Language.SourceAstDeclV1
