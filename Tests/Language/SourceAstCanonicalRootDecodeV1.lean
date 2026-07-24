import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.SourceAstCanonicalRootDecodeV1

open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

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

private def u16 (value : Nat) : ByteArray :=
  ByteArray.mk #[UInt8.ofNat value, UInt8.ofNat (value / 256)]

private def u32 (value : Nat) : ByteArray :=
  ByteArray.mk #[UInt8.ofNat value, UInt8.ofNat (value / 256),
    UInt8.ofNat (value / 65536), UInt8.ofNat (value / 16777216)]

private def stringBytes (value : String) : ByteArray :=
  u32 value.utf8ByteSize ++ value.toUTF8

private def tagged (tag : String) (fields : Array ByteArray) : ByteArray :=
  stringBytes tag ++ u16 fields.size ++ fields.foldl (· ++ ·) ByteArray.empty

private def arrayBytes (values : Array ByteArray) : ByteArray :=
  u32 values.size ++ values.foldl (· ++ ·) ByteArray.empty

private def nameArray (values : Array String) : ByteArray :=
  arrayBytes (values.map stringBytes)

private def badTag (tag : String) : ByteArray := stringBytes tag

private def rootBytes (moduleParts identityParts : Array String)
    (program : ByteArray) : ByteArray :=
  nameArray moduleParts ++ nameArray identityParts ++ program

private def programBytes (name : String) (items : Array ByteArray) : ByteArray :=
  tagged "Program" #[stringBytes name, arrayBytes items]

private def typeBool := tagged "Type.Bool" #[]
private def typeUnit := tagged "Type.Unit" #[]
private def publicVisibility := tagged "Visibility.Public" #[]

private def stateBytes (type_ : ByteArray) : ByteArray :=
  tagged "StateDecl" #[publicVisibility, stringBytes "enabled", type_]

private def returnNone := tagged "Stmt.Return" #[ByteArray.mk #[0]]

private def returnSomeBool :=
  let literal := tagged "Literal.Bool" #[ByteArray.mk #[1]]
  let expression := tagged "Expr.Literal" #[literal]
  tagged "Stmt.Return" #[ByteArray.mk #[1] ++ expression]

private def blockBytes (statements : Array ByteArray) : ByteArray :=
  tagged "Block" #[arrayBytes statements]

private def entryBytes (body : ByteArray) : ByteArray :=
  tagged "EntryDecl" #[stringBytes "run", u32 0, typeUnit, body]

private def minimalEntry := entryBytes (blockBytes #[returnNone])

private def nestedOptionType (count : Nat) : ByteArray := Id.run do
  let mut value := typeBool
  for _ in [:count] do
    value := tagged "Type.Option" #[value]
  pure value

private def deepRoot (optionCount : Nat) : ByteArray :=
  rootBytes #["Root"] #["Root", "Demo"]
    (programBytes "Demo" #[stateBytes (nestedOptionType optionCount), minimalEntry])

private def repeatBytes (chunk : ByteArray) (count : Nat) : ByteArray := Id.run do
  let mut output := ByteArray.emptyWithCapacity (chunk.size * count)
  for _ in [:count] do
    output := output ++ chunk
  pure output

private def wideRoot (noneCount : Nat) : ByteArray :=
  let statementPayload := repeatBytes returnNone noneCount ++ returnSomeBool
  let body := tagged "Block" #[u32 (noneCount + 1) ++ statementPayload]
  rootBytes #["Root"] #["Root", "Demo"]
    (programBytes "Demo" #[entryBytes body])

private def zeroBytes (count : Nat) : ByteArray :=
  ByteArray.mk (Array.replicate count (0 : UInt8))

private def name (value : String) : IO SourceNameComponentV1 :=
  lift value (parseSourceNameComponentV1 value)

private def qn (values : Array String) : IO SourceQualifiedNameV1 :=
  lift "qualified name" (parseSourceQualifiedNameV1 values)

private def checkIdentity (label : String) (source : ValidatedSourceV1)
    (moduleName programIdentity : SourceQualifiedNameV1) : IO Unit := do
  expect (source.moduleName == moduleName) s!"{label}: wrong module name"
  expect (source.programIdentity == programIdentity) s!"{label}: wrong program identity"

private def checkReencode (label : String) (source : ValidatedSourceV1)
    (expected : ByteArray) : IO Unit := do
  let encoded ← lift s!"{label}: re-encode" (canonicalValidatedSourceAstBytesV1 source)
  expect (encoded == expected) s!"{label}: canonical bytes changed"

/-- Frozen D1-PA-118: 3 positives and 15 root/resource/priority boundaries. -/
def run : IO Unit := do
  let fixedHex := "0100000004000000526f6f740200000004000000526f6f740400000044656d6f0700000050726f6772616d02000400000044656d6f020000000900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c000009000000456e7472794465636c04000300000072756e0000000009000000547970652e556e6974000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"
  let fixed := hexBytes fixedHex
  let moduleName ← qn #["Root"]
  let programIdentity ← qn #["Root", "Demo"]
  let demo ← name "Demo"; let enabled ← name "enabled"; let runName ← name "run"
  let state : StateDeclV1 := { visibility := .public_, name := enabled, type_ := .bool }
  let body : BlockV1 := { statements := #[.return_ none] }
  let entry : EntryDeclV1 := { name := runName, params := #[], result := .unit, body }
  let expectedProgram : ProgramV1 := { name := demo, items := #[.state state, .entry entry] }

  let decoded ← lift "positive-fixed" (decodeCanonicalSourceAstBytesV1 fixed)
  checkIdentity "positive-fixed" decoded moduleName programIdentity
  expect (decoded.program == expectedProgram) "positive-fixed: wrong ProgramV1"
  checkReencode "positive-fixed" decoded fixed

  let deep := deepRoot 253
  let deepDecoded ← lift "positive-depth-256" (decodeCanonicalSourceAstBytesV1 deep)
  checkIdentity "positive-depth-256" deepDecoded moduleName programIdentity
  expect (deepDecoded.program.items.size == 2) "positive-depth-256: wrong item count"
  checkReencode "positive-depth-256" deepDecoded deep

  let wide := wideRoot 99994
  let wideDecoded ← lift "positive-nodes-100000" (decodeCanonicalSourceAstBytesV1 wide)
  checkIdentity "positive-nodes-100000" wideDecoded moduleName programIdentity
  expect (wideDecoded.program.items.size == 1) "positive-nodes-100000: wrong item count"
  checkReencode "positive-nodes-100000" wideDecoded wide

  let maxBytes := 16 * 1024 * 1024
  expectError "boundary-1" "source exceeds the 16 MiB limit"
    (decodeCanonicalSourceAstBytesV1 (zeroBytes (maxBytes + 1)))
  let exactCap := fixed ++ zeroBytes (maxBytes - fixed.size)
  expectError "boundary-2" "trailing bytes" (decodeCanonicalSourceAstBytesV1 exactCap)
  expectError "boundary-3" "source qualified name must contain 1..256 components"
    (decodeCanonicalSourceAstBytesV1 (u32 0 ++ u32 0xffffffff ++ badTag "BogusProgram"))
  expectError "boundary-4" "source name component must contain 1..240 UTF-8 bytes"
    (decodeCanonicalSourceAstBytesV1 (u32 1 ++ u32 0 ++ u32 0xffffffff))
  expectError "boundary-5" "source qualified id must contain 2..256 components"
    (decodeCanonicalSourceAstBytesV1
      (nameArray #["Root"] ++ u32 1 ++ stringBytes "Only" ++ badTag "BogusProgram"))
  expectError "boundary-6" "unknown program tag 'StateDecl'"
    (decodeCanonicalSourceAstBytesV1
      (nameArray #["Root"] ++ nameArray #["Root", "Demo"] ++ badTag "StateDecl"))

  let emptyBodyEntry := entryBytes (tagged "Block" #[u32 0])
  let localBad := rootBytes #["Root"] #["Elsewhere", "Demo"]
    (programBytes "Demo" #[emptyBodyEntry]) ++ zeroBytes 1
  expectError "boundary-7" "block statements must be nonempty"
    (decodeCanonicalSourceAstBytesV1 localBad)
  let stateOnlyNonPrefix := rootBytes #["Root"] #["Elsewhere", "Demo"]
    (programBytes "Demo" #[stateBytes typeBool])
  expectError "boundary-8" "trailing bytes"
    (decodeCanonicalSourceAstBytesV1 (stateOnlyNonPrefix ++ zeroBytes 1))
  expectError "boundary-9" "program identity must begin with the exact module name components"
    (decodeCanonicalSourceAstBytesV1 (rootBytes #["Root"] #["Elsewhere", "Demo"]
      (programBytes "Wrong" #[stateBytes typeBool])))
  expectError "boundary-10" "program name must equal the last program identity component"
    (decodeCanonicalSourceAstBytesV1 (rootBytes #["Root"] #["Root", "Demo"]
      (programBytes "Wrong" #[stateBytes typeBool])))
  expectError "boundary-11" "program must declare at least one entry or view"
    (decodeCanonicalSourceAstBytesV1 (rootBytes #["Root"] #["Root", "Demo"]
      (programBytes "Demo" #[stateBytes typeBool])))
  expectError "boundary-12" "depth budget exhausted"
    (decodeCanonicalSourceAstBytesV1 (deepRoot 254))
  expectError "boundary-13" "node budget exhausted"
    (decodeCanonicalSourceAstBytesV1 (wideRoot 99995))
  expectError "boundary-14" "source qualified name must contain 1..256 components"
    (decodeCanonicalSourceAstBytesV1 (u32 257))
  expectError "boundary-15" "source qualified id must contain 2..256 components"
    (decodeCanonicalSourceAstBytesV1 (nameArray #["Root"] ++ u32 257))

end Tests.Language.SourceAstCanonicalRootDecodeV1
