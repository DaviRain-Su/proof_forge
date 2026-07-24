import ProofForgeV2.Source.AstProgramItemCodecV1
import ProofForgeV2.Source.AstProgramItemDecodeV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceAstProgramItemDecodeV1

open ProofForgeV2.Source.AstProgramItemCodecV1
open ProofForgeV2.Source.AstProgramItemDecodeV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireDecodeV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def lift (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: {detail}"

private def expectError (label expected : String) (result : Except String α) : IO Unit :=
  match result with
  | .error detail => expect (detail == expected) s!"{label}: expected {expected}, got {detail}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def hexValue (c : Char) : Nat :=
  if c ≤ '9' then c.toNat - '0'.toNat else c.toNat - 'a'.toNat + 10

private def hexBytes (value : String) : ByteArray := Id.run do
  let chars := value.toList.toArray
  let mut bytes := ByteArray.empty
  let mut index := 0
  while index + 1 < chars.size do
    bytes := bytes.push <| UInt8.ofNat (hexValue chars[index]! * 16 + hexValue chars[index + 1]!)
    index := index + 2
  pure bytes

private def lowerHexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat ('0'.toNat + value)
  else Char.ofNat ('a'.toNat + value - 10)

private def bytesHex (bytes : ByteArray) : String :=
  bytes.foldl (fun output byte =>
    let value := byte.toNat
    (output.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

private def u16 (value : Nat) : ByteArray :=
  ByteArray.mk #[UInt8.ofNat value, UInt8.ofNat (value / 256)]

private def u32 (value : Nat) : ByteArray :=
  ByteArray.mk #[UInt8.ofNat value, UInt8.ofNat (value / 256),
    UInt8.ofNat (value / 65536), UInt8.ofNat (value / 16777216)]

private def stringBytes (value : String) : ByteArray :=
  u32 value.utf8ByteSize ++ value.toUTF8

private def tagged (tag : String) (fields : Array ByteArray) : ByteArray :=
  stringBytes tag ++ u16 fields.size ++ fields.foldl (· ++ ·) ByteArray.empty

private def badTag (tag : String) : ByteArray := stringBytes tag
private def head (tag : String) (fieldCount : Nat) : ByteArray := stringBytes tag ++ u16 fieldCount
private def budget (nodes : Nat) : DecodeBudgetV1 := { remainingNodes := nodes }

private def decodeItem (depth nodes : Nat) (bytes : ByteArray) :=
  decodeProgramItemV1 depth (budget nodes) (start bytes)

private def setFieldCount (bytes : ByteArray) (fieldCount : Nat) : ByteArray :=
  let offset := 4 + (bytes.get! 0).toNat
  (bytes.set! offset (UInt8.ofNat fieldCount)).set! (offset + 1) (UInt8.ofNat (fieldCount / 256))

private def name (value : String) : IO SourceNameComponentV1 :=
  lift "name" (parseSourceNameComponentV1 value)

private def qualified (parts : Array String) : IO SourceQualifiedNameV1 :=
  lift "qualified" (parseSourceQualifiedNameV1 parts)

private def roundTrip (label expectedHex : String) (depth nodes : Nat)
    (expected : ProgramItemV1) : IO Unit := do
  let ((actual, residual), cursor) ← lift label (decodeItem depth nodes (hexBytes expectedHex))
  expect (decide (actual = expected)) s!"{label}: wrong value"
  expect (residual.remainingNodes == 0) s!"{label}: wrong node residual"
  lift s!"{label}: finish" (finish cursor)
  let encoded ← lift s!"{label}: encode" (encodeProgramItemV1 actual)
  expect (bytesHex encoded == expectedHex) s!"{label}: re-encode mismatch"

private def fieldCountPair (tag : String) (expected : Nat) (bytes : ByteArray) : IO Unit := do
  for invalid in [expected - 1, expected + 1] do
    expectError s!"field-count-{tag}-{invalid}" s!"tag '{tag}' must declare {expected} fields"
      (decodeItem 0 0 (setFieldCount bytes invalid))

private def aliasRoundTrip (label : String) (depth nodes : Nat)
    (expected : ProgramItemV1) : IO ByteArray := do
  let encoded ← lift s!"{label}: encode" (encodeProgramItemV1 expected)
  let ((actual, residual), cursor) ← lift s!"{label}: decode" (decodeItem depth nodes encoded)
  expect (decide (actual = expected)) s!"{label}: wrong constructor"
  expect (residual.remainingNodes == 0) s!"{label}: wrong residual"
  lift s!"{label}: finish" (finish cursor)
  pure encoded

private def expectDistinct (label : String) (left right : ProgramItemV1)
    (leftBytes rightBytes : ByteArray) : IO Unit := do
  expect (decide (left ≠ right)) s!"{label}: values aliased"
  expect (decide (leftBytes ≠ rightBytes)) s!"{label}: bytes aliased"

/-- Frozen D1-PA-116: 13 positives, 26 field-count negatives, 19 boundaries. -/
def run : IO Unit := do
  let enabled ← name "enabled"; let count ← name "count"; let store ← name "Store"
  let choice ← name "Choice"; let noneName ← name "None"; let someName ← name "Some"
  let ping ← name "Ping"; let emptyError ← name "Empty"; let safe ← name "safe"
  let maxName ← name "max"; let bounded ← name "bounded"; let startName ← name "start"
  let secret ← name "secret"; let runName ← name "run"; let to ← name "to"
  let amount ← name "amount"; let note ← name "note"; let get ← name "get"
  let helper ← name "helper2"; let x ← name "x"; let fieldId ← name "bn254_fr"
  let demoFeature ← qualified #["Demo", "Feature"]
  let proofsSafe ← qualified #["Proofs", "safe"]
  let fieldCount : FieldDeclV1 := { name := count, type_ := .uint 256 }
  let variantNone : EnumVariantV1 := { name := noneName, payloadTypes := #[] }
  let variantSome : EnumVariantV1 := { name := someName, payloadTypes := #[.bool, .principal] }
  let literal0 : ExprV1 := .literal (.integer 0)
  let literal1 : ExprV1 := .literal (.integer 1)
  let literal4096 : ExprV1 := .literal (.integer 4096)
  let literalTrue : ExprV1 := .literal (.bool true)
  let countPlace : PlaceV1 := .name count
  let countExpr : ExprV1 := .place countPlace
  let lessThan : ExprV1 := .binary .lt countExpr literal4096
  let assignBlock : BlockV1 := { statements := #[.assign countPlace literal1] }
  let returnCount : BlockV1 := { statements := #[.return_ (some countExpr)] }
  let return0 : BlockV1 := { statements := #[.return_ (some literal0)] }
  let returnNone : BlockV1 := { statements := #[.return_ none] }
  let ifBlock : BlockV1 := { statements := #[.if_ literalTrue returnNone none] }
  let startParam : ParamV1 := { visibility := .public_, name := startName, type_ := .uint 64 }
  let secretParam : ParamV1 := { visibility := .private_, name := secret, type_ := .field fieldId }
  let toParam : ParamV1 := { visibility := .public_, name := to, type_ := .principal }
  let amountParam : ParamV1 := { visibility := .private_, name := amount, type_ := .uint 64 }
  let noteParam : ParamV1 := { visibility := .commitment, name := note, type_ := .bytes 0 }
  let xParam : ParamV1 := { visibility := .public_, name := x, type_ := .uint 64 }
  let state : StateDeclV1 := { visibility := .public_, name := enabled, type_ := .bool }
  let struct_ : StructDeclV1 := { name := store, fields := #[fieldCount] }
  let enum_ : EnumDeclV1 := { name := choice, variants := #[variantNone, variantSome] }
  let const_ : ConstDeclV1 := { name := maxName, type_ := .uint 256, value := literal4096 }
  let event : EventDeclV1 := { name := ping, params := #[] }
  let error_ : ErrorDeclV1 := { name := emptyError, params := #[] }
  let init : InitDeclV1 := { params := #[startParam, secretParam], body := assignBlock }
  let entry : EntryDeclV1 :=
    { name := runName, params := #[toParam, amountParam, noteParam], result := .uint 64,
      body := returnCount }
  let view : ViewDeclV1 := { name := get, params := #[], result := .uint 64, body := return0 }
  let fn_ : FnDeclV1 := { name := helper, params := #[xParam], result := .unit, body := ifBlock }
  let invariant : InvariantDeclV1 := { name := bounded, predicate := lessThan }
  let extension : ExtensionReqV1 := {
    id := demoFeature, version := "1.0.0",
    digest := "sha256:0000000000000000000000000000000000000000000000000000000000000000" }
  let proof : ProofDeclV1 := { invariant := safe, theorem_ := proofsSafe }

  let stateHex := "0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
  let structHex := "0a0000005374727563744465636c02000500000053746f726501000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"
  let enumHex := "08000000456e756d4465636c02000600000043686f696365020000000b000000456e756d56617269616e740200040000004e6f6e65000000000b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000"
  let constHex := "09000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
  let eventHex := "090000004576656e744465636c02000400000050696e6700000000"
  let errorHex := "090000004572726f724465636c020005000000456d70747900000000"
  let initHex := "08000000496e69744465636c02000200000005000000506172616d0300110000005669736962696c6974792e5075626c6963000005000000737461727409000000547970652e55496e740100400005000000506172616d0300120000005669736962696c6974792e507269766174650000060000007365637265740a000000547970652e4669656c64010008000000626e3235345f667205000000426c6f636b0100010000000b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"
  let entryHex := "09000000456e7472794465636c04000300000072756e0300000005000000506172616d0300110000005669736962696c6974792e5075626c6963000002000000746f0e000000547970652e5072696e636970616c000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e427974657301000000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e74"
  let viewHex := "08000000566965774465636c0400030000006765740000000009000000547970652e55496e740100400005000000426c6f636b0100010000000b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000"
  let fnHex := "06000000466e4465636c04000700000068656c706572320100000005000000506172616d0300110000005669736962696c6974792e5075626c69630000010000007809000000547970652e55496e740100400009000000547970652e556e6974000005000000426c6f636b0100010000000700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000"
  let invariantHex := "0d000000496e76617269616e744465636c020007000000626f756e6465640b000000457870722e42696e61727903000b00000042696e6172794f702e4c7400000a000000457870722e506c61636501000a000000506c6163652e4e616d65010005000000636f756e740c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
  let extensionHex := "0c000000457874656e73696f6e5265710300020000000400000044656d6f070000004665617475726505000000312e302e30470000007368613235363a30303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030"
  let proofHex := "0900000050726f6f664465636c02000400000073616665020000000600000050726f6f66730400000073616665"

  roundTrip "item_state" stateHex 2 2 (.state state)
  roundTrip "item_struct" structHex 3 3 (.struct struct_)
  roundTrip "item_enum" enumHex 3 5 (.enum enum_)
  roundTrip "item_const" constHex 2 3 (.const const_)
  roundTrip "item_event" eventHex 1 1 (.event event)
  roundTrip "item_error" errorHex 1 1 (.error error_)
  roundTrip "item_init" initHex 4 9 (.init init)
  roundTrip "item_entry" entryHex 5 12 (.entry entry)
  roundTrip "item_view" viewHex 4 5 (.view view)
  roundTrip "item_fn" fnHex 5 9 (.fn fn_)
  roundTrip "item_invariant" invariantHex 4 5 (.invariant invariant)
  roundTrip "item_extension_req" extensionHex 1 1 (.extensionReq extension)
  roundTrip "item_proof" proofHex 1 1 (.proof proof)

  fieldCountPair "StateDecl" 3 (hexBytes stateHex)
  fieldCountPair "StructDecl" 2 (hexBytes structHex)
  fieldCountPair "EnumDecl" 2 (hexBytes enumHex)
  fieldCountPair "ConstDecl" 3 (hexBytes constHex)
  fieldCountPair "EventDecl" 2 (hexBytes eventHex)
  fieldCountPair "ErrorDecl" 2 (hexBytes errorHex)
  fieldCountPair "InitDecl" 2 (hexBytes initHex)
  fieldCountPair "EntryDecl" 4 (hexBytes entryHex)
  fieldCountPair "ViewDecl" 4 (hexBytes viewHex)
  fieldCountPair "FnDecl" 4 (hexBytes fnHex)
  fieldCountPair "InvariantDecl" 2 (hexBytes invariantHex)
  fieldCountPair "ExtensionReq" 3 (hexBytes extensionHex)
  fieldCountPair "ProofDecl" 2 (hexBytes proofHex)

  let sameEvent : ProgramItemV1 := .event { name := ping, params := #[] }
  let sameError : ProgramItemV1 := .error { name := ping, params := #[] }
  let sameBody := return0
  let sameEntry : ProgramItemV1 :=
    .entry { name := get, params := #[], result := .uint 64, body := sameBody }
  let sameView : ProgramItemV1 :=
    .view { name := get, params := #[], result := .uint 64, body := sameBody }
  let sameFn : ProgramItemV1 :=
    .fn { name := get, params := #[], result := .uint 64, body := sameBody }
  let sameEventBytes ← aliasRoundTrip "same-event" 1 1 sameEvent
  let sameErrorBytes ← aliasRoundTrip "same-error" 1 1 sameError
  let sameEntryBytes ← aliasRoundTrip "same-entry" 4 5 sameEntry
  let sameViewBytes ← aliasRoundTrip "same-view" 4 5 sameView
  let sameFnBytes ← aliasRoundTrip "same-fn" 4 5 sameFn
  expectDistinct "event/error" sameEvent sameError sameEventBytes sameErrorBytes
  expectDistinct "entry/view" sameEntry sameView sameEntryBytes sameViewBytes
  expectDistinct "entry/fn" sameEntry sameFn sameEntryBytes sameFnBytes
  expectDistinct "view/fn" sameView sameFn sameViewBytes sameFnBytes

  expectError "boundary-1" "tag length must be 1..21 bytes" (decodeItem 0 0 (u32 0))
  expectError "boundary-2" "tag length must be 1..21 bytes" (decodeItem 0 0 (u32 22))
  expectError "boundary-3" "truncated" (decodeItem 0 0 (u32 4 ++ "Bo".toUTF8))
  expectError "boundary-4" "invalid UTF-8 tag"
    (decodeItem 0 0 (u32 1 ++ ByteArray.mk #[0xff]))
  expectError "boundary-5" "tag must be ASCII" (decodeItem 0 0 (u32 2 ++ "é".toUTF8))
  expectError "boundary-6" "unknown program-item tag 'BogusItem'"
    (decodeItem 0 0 (badTag "BogusItem"))
  expectError "boundary-7" "unknown program-item tag 'Type.Bool'"
    (decodeItem 0 0 (badTag "Type.Bool"))
  expectError "boundary-8" "depth budget exhausted" (decodeItem 0 0 (head "StateDecl" 3))
  expectError "boundary-9" "node budget exhausted" (decodeItem 1 0 (head "StateDecl" 3))
  expectError "boundary-10" "unknown visibility tag 'Type.Bool'"
    (decodeItem 3 8 (tagged "StateDecl" #[tagged "Type.Bool" #[], u32 0, badTag "BogusType"]))
  expectError "boundary-11" "struct fields must be nonempty"
    (decodeItem 3 8 (tagged "StructDecl" #[stringBytes "Store", u32 0]))
  expectError "boundary-12" "enum variants must be nonempty"
    (decodeItem 3 8 (tagged "EnumDecl" #[stringBytes "Choice", u32 0]))
  expectError "boundary-13" "array count exceeds caller limit"
    (decodeItem 2 1 (tagged "EventDecl" #[stringBytes "Ping", u32 2]))
  expectError "boundary-14" "unknown param tag 'BogusParam'"
    (decodeItem 2 8 (tagged "ErrorDecl" #[stringBytes "Empty", u32 1 ++ badTag "BogusParam"]))
  expectError "boundary-15" "unknown type tag 'BogusType'"
    (decodeItem 3 8 (tagged "ConstDecl" #[stringBytes "max", badTag "BogusType", badTag "BogusValue"]))
  let emptyBlock := tagged "Block" #[u32 0]
  expectError "boundary-16" "block statements must be nonempty"
    (decodeItem 3 8 (tagged "InitDecl" #[u32 0, emptyBlock]))
  let oneComponent := u32 1 ++ stringBytes "Only"
  expectError "boundary-17" "source qualified id must contain 2..256 components"
    (decodeItem 1 1 (tagged "ExtensionReq" #[oneComponent, stringBytes "bad", stringBytes "bad"]))
  expectError "boundary-18" "source qualified id must contain 2..256 components"
    (decodeItem 1 1 (tagged "ProofDecl" #[stringBytes "safe", oneComponent]))
  expectError "boundary-19" "trailing bytes" (do
    let ((_item, _residual), cursor) ← decodeItem 2 2 (hexBytes (stateHex ++ "00"))
    finish cursor)

end Tests.Language.SourceAstProgramItemDecodeV1
