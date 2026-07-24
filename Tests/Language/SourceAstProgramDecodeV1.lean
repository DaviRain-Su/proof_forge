import ProofForgeV2.Source.AstProgramCodecV1
import ProofForgeV2.Source.AstProgramDecodeV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceAstProgramDecodeV1

open ProofForgeV2.Source.AstProgramCodecV1
open ProofForgeV2.Source.AstProgramDecodeV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
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

private def decodeProgram (depth nodes : Nat) (bytes : ByteArray) :=
  decodeProgramV1 depth (budget nodes) (start bytes)

private def setFieldCount (bytes : ByteArray) (fieldCount : Nat) : ByteArray :=
  let offset := 4 + (bytes.get! 0).toNat
  (bytes.set! offset (UInt8.ofNat fieldCount)).set! (offset + 1) (UInt8.ofNat (fieldCount / 256))

private def name (value : String) : IO SourceNameComponentV1 :=
  lift "name" (parseSourceNameComponentV1 value)

private def roundTrip (label expectedHex : String) (depth nodes : Nat)
    (expected : ProgramV1) : IO ByteArray := do
  let bytes := hexBytes expectedHex
  let ((actual, residual), cursor) ← lift label (decodeProgram depth nodes bytes)
  expect (decide (actual = expected)) s!"{label}: wrong value"
  expect (residual.remainingNodes == 0) s!"{label}: wrong node residual"
  lift s!"{label}: finish" (finish cursor)
  let encoded ← lift s!"{label}: encode" (encodeProgramV1 actual)
  expect (bytesHex encoded == expectedHex) s!"{label}: re-encode mismatch"
  pure bytes

/-- Frozen D1-PA-117: 3 positives, 2 field-count negatives, 17 boundaries. -/
def run : IO Unit := do
  let demo ← name "Demo"; let enabled ← name "enabled"; let maxName ← name "max"
  let state : StateDeclV1 := { visibility := .public_, name := enabled, type_ := .bool }
  let const_ : ConstDeclV1 := {
    name := maxName, type_ := .uint 256, value := .literal (.integer 4096) }
  let stateItem : ProgramItemV1 := .state state
  let constItem : ProgramItemV1 := .const const_
  let stateOnly : ProgramV1 := { name := demo, items := #[stateItem] }
  let twoOrder : ProgramV1 := { name := demo, items := #[stateItem, constItem] }
  let twoReversed : ProgramV1 := { name := demo, items := #[constItem, stateItem] }

  let stateProgramHex := "0700000050726f6772616d02000400000044656d6f010000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
  let twoOrderHex := "0700000050726f6772616d02000400000044656d6f020000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c000009000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
  let twoReversedHex := "0700000050726f6772616d02000400000044656d6f0200000009000000436f6e73744465636c0300030000006d617809000000547970652e55496e74010000010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
  let stateItemBytes := hexBytes "0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"

  let _ ← roundTrip "prog_state_only" stateProgramHex 3 3 stateOnly
  let orderBytes ← roundTrip "prog_two_order" twoOrderHex 3 6 twoOrder
  let reversedBytes ← roundTrip "prog_two_reversed" twoReversedHex 3 6 twoReversed
  expect (decide (twoOrder ≠ twoReversed)) "program order values aliased"
  expect (decide (orderBytes ≠ reversedBytes)) "program order bytes aliased"

  for invalid in [1, 3] do
    expectError s!"field-count-{invalid}" "tag 'Program' must declare 2 fields"
      (decodeProgram 0 0 (setFieldCount (hexBytes stateProgramHex) invalid))

  expectError "boundary-1" "tag length must be 1..21 bytes" (decodeProgram 0 0 (u32 0))
  expectError "boundary-2" "invalid UTF-8 tag"
    (decodeProgram 0 0 (u32 1 ++ ByteArray.mk #[0xff]))
  expectError "boundary-3" "unknown program tag 'StateDecl'"
    (decodeProgram 0 0 (badTag "StateDecl"))
  expectError "boundary-4" "depth budget exhausted" (decodeProgram 0 0 (head "Program" 2))
  expectError "boundary-5" "node budget exhausted" (decodeProgram 1 0 (head "Program" 2))
  expectError "boundary-6" "source name component must contain 1..240 UTF-8 bytes"
    (decodeProgram 2 8 (tagged "Program" #[u32 0, u32 0xffffffff]))
  expectError "boundary-7" "program items must be nonempty"
    (decodeProgram 2 8 (tagged "Program" #[stringBytes "Demo", u32 0]))
  expectError "boundary-8" "array count exceeds caller limit"
    (decodeProgram 2 2 (tagged "Program" #[stringBytes "Demo", u32 2]))
  expectError "boundary-9" "array count exceeds caller limit"
    (decodeProgram 2 100 (tagged "Program" #[stringBytes "Demo", u32 0xffffffff]))
  expectError "boundary-10" "unknown program-item tag 'BogusItem'"
    (decodeProgram 2 8 (tagged "Program" #[stringBytes "Demo", u32 1 ++ badTag "BogusItem"]))
  expectError "boundary-11" "unknown program-item tag 'Type.Bool'"
    (decodeProgram 2 8 (tagged "Program" #[stringBytes "Demo", u32 1 ++ badTag "Type.Bool"]))
  expectError "boundary-12" "depth budget exhausted"
    (decodeProgram 2 3 (hexBytes stateProgramHex))
  expectError "boundary-13" "node budget exhausted"
    (decodeProgram 3 2 (hexBytes stateProgramHex))
  expectError "boundary-14" "unknown program-item tag 'BogusItem'"
    (decodeProgram 3 6 (tagged "Program" #[stringBytes "Demo",
      u32 2 ++ stateItemBytes ++ badTag "BogusItem"]))
  let emptyStruct := tagged "StructDecl" #[stringBytes "Store", u32 0]
  expectError "boundary-15" "struct fields must be nonempty"
    (decodeProgram 4 6 (tagged "Program" #[stringBytes "Demo",
      u32 2 ++ stateItemBytes ++ emptyStruct]))
  let badConst := tagged "ConstDecl" #[stringBytes "max", badTag "BogusType", badTag "BogusValue"]
  expectError "boundary-16" "unknown type tag 'BogusType'"
    (decodeProgram 4 8 (tagged "Program" #[stringBytes "Demo",
      u32 2 ++ badConst ++ stateItemBytes]))
  expectError "boundary-17" "trailing bytes" (do
    let ((_program, _residual), cursor) ← decodeProgram 3 3 (hexBytes (stateProgramHex ++ "00"))
    finish cursor)

end Tests.Language.SourceAstProgramDecodeV1
