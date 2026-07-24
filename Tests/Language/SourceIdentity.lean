import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireV1

namespace Tests.Language.SourceIdentity

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def expectInvalid (label : String) (result : Except String α) : IO Unit :=
  match result with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def expectError (label expected : String) (result : Except String α) : IO Unit :=
  match result with
  | .error detail => expect (detail == expected) s!"{label}: expected {expected}, got {detail}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def nodeIdText
    (label : String) (moduleName programIdentity : SourceQualifiedNameV1)
    (path : NormalizedSyntacticPathV1) : IO String := do
  let nodeId ← liftResult label (nodeIdV1 moduleName programIdentity path)
  let _ ← liftResult s!"{label} validation" (validateNodeId nodeId)
  expect (nodeId.bytes.size == 16) s!"{label}: candidate must contain 16 bytes"
  liftResult s!"{label} render" (renderNodeId nodeId)

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

private def rawEscapedPreimageHex : String :=
  "70662e736f757263652d6e6f64652e7631007b226d6f64756c65223a5b22412e42225d2c2270617468223a5b7b226669656c64546167223a226974656d73222c22696e646578223a312c22706172656e74546167223a2250726f6772616d227d5d2c2270726f6772616d223a5b22412e42222c22505c22515c5c52225d7d"

private def segment
    (parentTag fieldTag : String) (index : UInt32 := 0) : NodePathSegmentV1 := {
  parentTag
  fieldTag
  index
}

private def directPairs : Array (String × String) := #[
  ("StateDecl", "type"),
  ("ConstDecl", "type"), ("ConstDecl", "value"),
  ("InitDecl", "body"),
  ("EntryDecl", "result"), ("EntryDecl", "body"),
  ("ViewDecl", "result"), ("ViewDecl", "body"),
  ("FnDecl", "result"), ("FnDecl", "body"),
  ("InvariantDecl", "predicate"),
  ("Param", "type"), ("FieldDecl", "type"),
  ("StmtMatchArm", "pattern"), ("StmtMatchArm", "body"),
  ("ExprMatchArm", "pattern"), ("ExprMatchArm", "value"),
  ("Type.Array", "element"),
  ("Type.Map", "key"), ("Type.Map", "value"),
  ("Type.Option", "element"),
  ("Stmt.Let", "typeAnn"), ("Stmt.Let", "value"),
  ("Stmt.Assign", "target"), ("Stmt.Assign", "value"),
  ("Stmt.If", "condition"), ("Stmt.If", "thenBlock"),
  ("Stmt.If", "elseBlock"),
  ("Stmt.Match", "scrutinee"),
  ("Stmt.For", "start"), ("Stmt.For", "endExclusive"),
  ("Stmt.For", "body"),
  ("Stmt.Assert", "condition"),
  ("Stmt.Return", "value"),
  ("Stmt.Call", "call"), ("Stmt.Schedule", "call"),
  ("Expr.Place", "place"),
  ("Expr.Unary", "operand"),
  ("Expr.Binary", "lhs"), ("Expr.Binary", "rhs"),
  ("Expr.Match", "scrutinee"),
  ("Place.Field", "base"),
  ("Place.Index", "base"), ("Place.Index", "index")
]

private def arrayPairs : Array (String × String) := #[
  ("Program", "items"),
  ("StructDecl", "fields"), ("EnumDecl", "variants"),
  ("EventDecl", "params"), ("ErrorDecl", "params"),
  ("InitDecl", "params"), ("EntryDecl", "params"),
  ("ViewDecl", "params"), ("FnDecl", "params"),
  ("EnumVariant", "payloadTypes"),
  ("Block", "statements"),
  ("ExternalCallExpr", "args"),
  ("Stmt.Match", "arms"),
  ("Stmt.Revert", "args"), ("Stmt.Emit", "args"),
  ("Expr.Constructor", "args"), ("Expr.LocalCall", "args"),
  ("Expr.Match", "arms"),
  ("Pattern.Constructor", "args")
]

private def itemParentTags : Array String := #[
  "StateDecl", "StructDecl", "EnumDecl", "ConstDecl", "EventDecl",
  "ErrorDecl", "InitDecl", "EntryDecl", "ViewDecl", "FnDecl",
  "InvariantDecl"
]

private def statementParentTags : Array String := #[
  "Stmt.Let", "Stmt.Assign", "Stmt.If", "Stmt.Match", "Stmt.For",
  "Stmt.Assert", "Stmt.Revert", "Stmt.Emit", "Stmt.Return", "Stmt.Call",
  "Stmt.Schedule"
]

private def expressionParentTags : Array String := #[
  "Expr.Place", "Expr.Constructor", "Expr.Unary", "Expr.Binary",
  "Expr.LocalCall", "Expr.Match"
]

private def prefixForParent (parentTag : String) : Option NormalizedSyntacticPathV1 :=
  if parentTag == "Program" then
    some #[]
  else if itemParentTags.contains parentTag then
    some #[segment "Program" "items"]
  else if parentTag == "Param" then
    some #[segment "Program" "items", segment "EventDecl" "params"]
  else if parentTag == "FieldDecl" then
    some #[segment "Program" "items", segment "StructDecl" "fields"]
  else if parentTag == "EnumVariant" then
    some #[segment "Program" "items", segment "EnumDecl" "variants"]
  else if parentTag == "Block" then
    some #[segment "Program" "items", segment "InitDecl" "body"]
  else if parentTag == "StmtMatchArm" then
    some #[segment "Program" "items", segment "InitDecl" "body",
      segment "Block" "statements", segment "Stmt.Match" "arms"]
  else if parentTag == "ExprMatchArm" then
    some #[segment "Program" "items", segment "InvariantDecl" "predicate",
      segment "Expr.Match" "arms"]
  else if parentTag == "ExternalCallExpr" then
    some #[segment "Program" "items", segment "InitDecl" "body",
      segment "Block" "statements", segment "Stmt.Call" "call"]
  else if parentTag.startsWith "Type." then
    some #[segment "Program" "items", segment "StateDecl" "type"]
  else if statementParentTags.contains parentTag then
    some #[segment "Program" "items", segment "InitDecl" "body",
      segment "Block" "statements"]
  else if expressionParentTags.contains parentTag then
    some #[segment "Program" "items", segment "InvariantDecl" "predicate"]
  else if #["Place.Field", "Place.Index"].contains parentTag then
    some #[segment "Program" "items", segment "InvariantDecl" "predicate",
      segment "Expr.Place" "place"]
  else if parentTag == "Pattern.Constructor" then
    some #[segment "Program" "items", segment "InitDecl" "body",
      segment "Block" "statements", segment "Stmt.Match" "arms",
      segment "StmtMatchArm" "pattern"]
  else
    none

private def pathForPair
    (parentTag fieldTag : String) (index : UInt32 := 0) :
    Option NormalizedSyntacticPathV1 :=
  (prefixForParent parentTag).map fun pathPrefix =>
    pathPrefix.push (segment parentTag fieldTag index)

def run : IO Unit := do
  let moduleName ← liftResult "module name" (parseSourceQualifiedNameV1 #["Demo"])
  let programIdentity ← liftResult "program identity"
    (parseSourceQualifiedNameV1 #["Demo", "Counter"])

  let rootPreimage ← liftResult "root preimage"
    (nodeIdPreimageV1 moduleName programIdentity #[])
  expect (bytesHex rootPreimage == rootPreimageHex)
    "root NodeId preimage must match the exact cross-implementation byte vector"
  expect (Crypto.sha256Hex rootPreimage ==
      "58c75af894b6f832163564705c9f23ef3a02df045126baf9492f89844f7ef08f")
    "root NodeId preimage must match the SHA-256 golden"
  let rootNodeId ← nodeIdText "root NodeId" moduleName programIdentity #[]
  expect (rootNodeId == "nodeid:58c75af894b6f832163564705c9f23ef")
    s!"root NodeId truncation mismatch: {rootNodeId}"
  let rootRoundTrip ← liftResult "root NodeId round-trip" (parseNodeId rootNodeId)
  let rootRoundTripText ← liftResult "root NodeId re-render" (renderNodeId rootRoundTrip)
  expect (rootRoundTripText == rootNodeId) "root Common NodeId round-trip"

  let firstItemPath := #[segment "Program" "items"]
  let firstItemPreimage ← liftResult "first item preimage"
    (nodeIdPreimageV1 moduleName programIdentity firstItemPath)
  expect (bytesHex firstItemPreimage == firstItemPreimageHex)
    "array-child NodeId preimage must match the exact PF-JCS byte vector"
  expect (Crypto.sha256Hex firstItemPreimage ==
      "17ac87bb9262ace7d062c77c38a17d0ddcd69fbff4e7927ed8fe9d02af454822")
    "array-child NodeId preimage must match the SHA-256 golden"
  let firstItemNodeId ← nodeIdText "first item NodeId"
    moduleName programIdentity firstItemPath
  expect (firstItemNodeId == "nodeid:17ac87bb9262ace7d062c77c38a17d0d")
    s!"first item NodeId truncation mismatch: {firstItemNodeId}"

  let otherIdentity ← liftResult "other program identity"
    (parseSourceQualifiedNameV1 #["Demo", "Other"])
  let otherIdentityPreimage ← liftResult "other identity preimage"
    (nodeIdPreimageV1 moduleName otherIdentity #[])
  expect (otherIdentityPreimage != rootPreimage)
    "program identity must participate in the NodeId preimage"
  let otherIdentityNodeId ← nodeIdText "other identity NodeId" moduleName otherIdentity #[]
  expect (otherIdentityNodeId != rootNodeId)
    "program identity must participate in the production NodeId"
  let secondItemPath := #[segment "Program" "items" 1]
  let secondItemPreimage ← liftResult "second item preimage"
    (nodeIdPreimageV1 moduleName programIdentity secondItemPath)
  expect (secondItemPreimage != firstItemPreimage)
    "array source order must participate in the NodeId preimage"
  let secondItemNodeId ← nodeIdText "second item NodeId"
    moduleName programIdentity secondItemPath
  expect (secondItemNodeId != firstItemNodeId)
    "array source order must participate in the production NodeId"

  let rawModule ← liftResult "raw module" (parseSourceQualifiedNameV1 #["A.B"])
  let rawIdentity ← liftResult "raw identity"
    (parseSourceQualifiedNameV1 #["A.B", "P\"Q\\R"])
  let rawPath := #[segment "Program" "items" 1]
  let rawPreimage ← liftResult "raw escaped preimage"
    (nodeIdPreimageV1 rawModule rawIdentity rawPath)
  expect (bytesHex rawPreimage == rawEscapedPreimageHex)
    "raw dot/quote/backslash components must match the exact PF-JCS vector"
  expect (Crypto.sha256Hex rawPreimage ==
      "1d20bd4f37f942a52977fa9aade547fb0cbe5317f04f777ca50973de99e1e495")
    "raw escaped NodeId preimage must match the SHA-256 golden"
  let rawNodeId ← nodeIdText "raw escaped NodeId" rawModule rawIdentity rawPath
  expect (rawNodeId == "nodeid:1d20bd4f37f942a52977fa9aade547fb")
    s!"raw escaped NodeId truncation mismatch: {rawNodeId}"
  let splitModule ← liftResult "split module" (parseSourceQualifiedNameV1 #["A", "B"])
  let splitIdentity ← liftResult "split identity"
    (parseSourceQualifiedNameV1 #["A", "B", "P\"Q\\R"])
  let splitPreimage ← liftResult "split preimage"
    (nodeIdPreimageV1 splitModule splitIdentity rawPath)
  expect (splitPreimage != rawPreimage) "raw dotted and split components must not alias"
  let splitNodeId ← nodeIdText "split NodeId" splitModule splitIdentity rawPath
  expect (splitNodeId != rawNodeId) "raw dotted and split component NodeIds must not alias"

  let stateType ← liftResult "state type path" (nodeIdPreimageV1 moduleName programIdentity
    #[segment "Program" "items", segment "StateDecl" "type"])
  let constType ← liftResult "const type path" (nodeIdPreimageV1 moduleName programIdentity
    #[segment "Program" "items", segment "ConstDecl" "type"])
  expect (stateType != constType) "parentTag must participate in the NodeId preimage"
  let stateTypeNodeId ← nodeIdText "state type NodeId" moduleName programIdentity
    #[segment "Program" "items", segment "StateDecl" "type"]
  let constTypeNodeId ← nodeIdText "const type NodeId" moduleName programIdentity
    #[segment "Program" "items", segment "ConstDecl" "type"]
  expect (stateTypeNodeId != constTypeNodeId)
    "parentTag must participate in the production NodeId"
  let mapKey ← liftResult "map key path" (nodeIdPreimageV1 moduleName programIdentity
    #[segment "Program" "items", segment "StateDecl" "type", segment "Type.Map" "key"])
  let mapValue ← liftResult "map value path" (nodeIdPreimageV1 moduleName programIdentity
    #[segment "Program" "items", segment "StateDecl" "type", segment "Type.Map" "value"])
  expect (mapKey != mapValue) "fieldTag must participate in the NodeId preimage"
  let mapKeyNodeId ← nodeIdText "map key NodeId" moduleName programIdentity
    #[segment "Program" "items", segment "StateDecl" "type", segment "Type.Map" "key"]
  let mapValueNodeId ← nodeIdText "map value NodeId" moduleName programIdentity
    #[segment "Program" "items", segment "StateDecl" "type", segment "Type.Map" "value"]
  expect (mapKeyNodeId != mapValueNodeId)
    "fieldTag must participate in the production NodeId"

  let wrongPrefix ← liftResult "wrong-prefix identity"
    (parseSourceQualifiedNameV1 #["Elsewhere", "Counter"])
  expectError "identity prefix"
    "program identity must begin with the exact module name components"
    (nodeIdPreimageV1 moduleName wrongPrefix #[])
  expectError "NodeId identity prefix"
    "program identity must begin with the exact module name components"
    (nodeIdV1 moduleName wrongPrefix #[])
  expectError "identity qid count" "source qualified id must contain 2..256 components"
    (nodeIdPreimageV1 moduleName moduleName #[])
  let twoPartModule ← liftResult "two-part module"
    (parseSourceQualifiedNameV1 #["Demo", "Inner"])
  expectError "identity must extend module"
    "program identity must strictly extend the module name"
    (nodeIdPreimageV1 twoPartModule twoPartModule #[])
  expectError "scalar field cannot create a path segment"
    "source node path contains an unknown constructor/field pair"
    (nodeIdPreimageV1 moduleName programIdentity #[segment "Program" "name"])
  expectError "NodeId scalar field cannot create a path segment"
    "source node path contains an unknown constructor/field pair"
    (nodeIdV1 moduleName programIdentity #[segment "Program" "name"])
  expectError "constructor/field pairing is closed"
    "source node path contains an unknown constructor/field pair"
    (nodeIdPreimageV1 moduleName programIdentity #[segment "Program" "fields"])
  expectError "non-root path is impossible"
    "non-root source node paths must begin at Program"
    (nodeIdPreimageV1 moduleName programIdentity #[segment "Type.Option" "element"])
  expectError "constructor transition is typed"
    "source node path contains an impossible constructor transition"
    (nodeIdPreimageV1 moduleName programIdentity
      #[segment "Program" "items", segment "Type.Option" "element"])
  expectError "direct child requires index zero"
    "direct source node path fields require index zero"
    (nodeIdPreimageV1 moduleName programIdentity
      #[segment "Program" "items", segment "StateDecl" "type" 1])

  expect (directPairs.size == 44 && arrayPairs.size == 19)
    "the closed node-bearing field inventory must contain exactly 63 pairs"
  for pair in directPairs do
    let some indexZeroPath := pathForPair pair.1 pair.2
      | throw <| IO.userError s!"missing test prefix for {pair.1}.{pair.2}"
    let _ ← liftResult s!"direct pair {pair.1}.{pair.2}"
      (nodeIdPreimageV1 moduleName programIdentity indexZeroPath)
    let some indexOnePath := pathForPair pair.1 pair.2 1
      | throw <| IO.userError s!"missing test prefix for {pair.1}.{pair.2}"
    expectInvalid s!"direct pair index {pair.1}.{pair.2}"
      (nodeIdPreimageV1 moduleName programIdentity indexOnePath)
  for pair in arrayPairs do
    let some indexZeroPath := pathForPair pair.1 pair.2
      | throw <| IO.userError s!"missing test prefix for {pair.1}.{pair.2}"
    let _ ← liftResult s!"array pair zero {pair.1}.{pair.2}"
      (nodeIdPreimageV1 moduleName programIdentity indexZeroPath)
    let some indexOnePath := pathForPair pair.1 pair.2 1
      | throw <| IO.userError s!"missing test prefix for {pair.1}.{pair.2}"
    let _ ← liftResult s!"array pair one {pair.1}.{pair.2}"
      (nodeIdPreimageV1 moduleName programIdentity indexOnePath)
  let allPairs := directPairs ++ arrayPairs
  for parentSource in allPairs do
    for fieldSource in allPairs do
      let candidate := (parentSource.1, fieldSource.2)
      unless allPairs.contains candidate do
        let some candidatePath := pathForPair candidate.1 candidate.2
          | throw <| IO.userError s!"missing test prefix for {candidate.1}.{candidate.2}"
        expectInvalid s!"non-member pair {candidate.1}.{candidate.2}"
          (nodeIdPreimageV1 moduleName programIdentity candidatePath)

  let typePrefix := #[segment "Program" "items", segment "ConstDecl" "type"]
  let atDepthLimit := typePrefix ++
    Array.replicate 253 (segment "Type.Option" "element")
  let _ ← liftResult "path at depth limit"
    (nodeIdPreimageV1 moduleName programIdentity atDepthLimit)
  let overDepthLimit := typePrefix ++
    Array.replicate 254 (segment "Type.Option" "element")
  expectError "path over depth limit" "source node path exceeds the nesting bound"
    (nodeIdPreimageV1 moduleName programIdentity overDepthLimit)

end Tests.Language.SourceIdentity
