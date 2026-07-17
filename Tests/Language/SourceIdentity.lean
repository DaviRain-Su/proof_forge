import ProofForgeV2.Source.WireV1

namespace Tests.Language.SourceIdentity

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftStringResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def liftCompileResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: unexpected error: {error.render}"

private def expectInvalid (label : String) (result : CompileResult α) : IO Unit :=
  match result with
  | .error (.invalidProgram _) => pure ()
  | .error error =>
      throw <| IO.userError s!"{label}: expected invalid-program, got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def lowerHexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat ('0'.toNat + value)
  else Char.ofNat ('a'.toNat + value - 10)

private def bytesHex (bytes : ByteArray) : String :=
  bytes.foldl (fun output byte =>
    let value := byte.toNat
    (output.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

private def rootPreimageHex : String :=
  "70662e736f757263652d6e6f64652e7631007b226d6f64756c65223a5b2244656d6f225d2c2270617468223a5b5d2c2270726f6772616d223a5b2244656d6f222c22436f756e746572225d7d"

private def firstItemPreimageHex : String :=
  "70662e736f757263652d6e6f64652e7631007b226d6f64756c65223a5b2244656d6f225d2c2270617468223a5b7b226669656c64546167223a226974656d73222c22696e646578223a302c22706172656e74546167223a2250726f6772616d227d5d2c2270726f6772616d223a5b2244656d6f222c22436f756e746572225d7d"

private def segment
    (parentTag fieldTag : String) (index : UInt32 := 0) : NodePathSegmentV1 := {
  parentTag
  fieldTag
  index
}

def run : IO Unit := do
  let moduleName ← liftStringResult "module name" (parseQualifiedName #["Demo"])
  let programIdentity ← liftStringResult "program identity"
    (parseQualifiedName #["Demo", "Counter"])

  let rootPreimage ← liftCompileResult "root preimage"
    (nodeIdPreimageV1 moduleName programIdentity #[])
  expect (bytesHex rootPreimage == rootPreimageHex)
    "root NodeId preimage must match the exact cross-implementation byte vector"
  expect (Crypto.sha256Hex rootPreimage ==
      "58c75af894b6f832163564705c9f23ef3a02df045126baf9492f89844f7ef08f")
    "root NodeId preimage must match the SHA-256 golden"

  let firstItemPath := #[segment "Program" "items"]
  let firstItemPreimage ← liftCompileResult "first item preimage"
    (nodeIdPreimageV1 moduleName programIdentity firstItemPath)
  expect (bytesHex firstItemPreimage == firstItemPreimageHex)
    "array-child NodeId preimage must match the exact PF-JCS byte vector"
  expect (Crypto.sha256Hex firstItemPreimage ==
      "17ac87bb9262ace7d062c77c38a17d0ddcd69fbff4e7927ed8fe9d02af454822")
    "array-child NodeId preimage must match the SHA-256 golden"

  let otherIdentity ← liftStringResult "other program identity"
    (parseQualifiedName #["Demo", "Other"])
  let otherIdentityPreimage ← liftCompileResult "other identity preimage"
    (nodeIdPreimageV1 moduleName otherIdentity #[])
  expect (otherIdentityPreimage != rootPreimage)
    "program identity must participate in the NodeId preimage"
  let secondItemPreimage ← liftCompileResult "second item preimage"
    (nodeIdPreimageV1 moduleName programIdentity #[segment "Program" "items" 1])
  expect (secondItemPreimage != firstItemPreimage)
    "array source order must participate in the NodeId preimage"

  let wrongPrefix ← liftStringResult "wrong-prefix identity"
    (parseQualifiedName #["Elsewhere", "Counter"])
  expectInvalid "identity prefix"
    (nodeIdPreimageV1 moduleName wrongPrefix #[])
  expectInvalid "identity must extend module"
    (nodeIdPreimageV1 moduleName moduleName #[])
  expectInvalid "scalar field cannot create a path segment"
    (nodeIdPreimageV1 moduleName programIdentity #[segment "Program" "name"])
  expectInvalid "constructor/field pairing is closed"
    (nodeIdPreimageV1 moduleName programIdentity #[segment "Program" "fields"])
  expectInvalid "direct child requires index zero"
    (nodeIdPreimageV1 moduleName programIdentity #[segment "StateDecl" "type" 1])

  let atDepthLimit := Array.replicate 255 (segment "Type.Option" "element")
  let _ ← liftCompileResult "path at depth limit"
    (nodeIdPreimageV1 moduleName programIdentity atDepthLimit)
  let overDepthLimit := Array.replicate 256 (segment "Type.Option" "element")
  expectInvalid "path over depth limit"
    (nodeIdPreimageV1 moduleName programIdentity overDepthLimit)

end Tests.Language.SourceIdentity
