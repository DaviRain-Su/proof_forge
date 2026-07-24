import Lean
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.SourceProgramWireUnknownTagGoldenV1

open Lean
open ProofForgeV2
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.ValidatedSourceV1

private structure MutationRow where
  caseId : String
  diagnosticFamily : String
  expectedError : String
  mutatedFirstByte : Nat
  mutatedTag : String
  originalFirstByte : Nat
  originalTag : String
  tagByteOffset : Nat
  deriving FromJson, Repr

private structure MutationManifest where
  baseCanonicalBytesSha256 : String
  baseCanonicalFile : String
  baseCaseId : String
  diagnosticFamilies : Array String
  diagnosticFamilyCount : Nat
  mutationCount : Nat
  mutations : Array MutationRow
  schema : String
  scope : String
  tagCount : Nat
  deriving FromJson, Repr

private def basePath : System.FilePath :=
  "testdata/golden/source-program-v1/full-tag-v1/canonical.bin"

private def manifestPath : System.FilePath :=
  "testdata/golden/source-program-v1/unknown-tag-v1/manifest.json"

private def wireTags : Array String := #[
  "BinaryOp.Add", "BinaryOp.And", "BinaryOp.BitAnd", "BinaryOp.BitOr",
  "BinaryOp.BitXor", "BinaryOp.Div", "BinaryOp.Eq", "BinaryOp.Ge", "BinaryOp.Gt",
  "BinaryOp.Le", "BinaryOp.Lt", "BinaryOp.Mod", "BinaryOp.Mul", "BinaryOp.Ne",
  "BinaryOp.Or", "BinaryOp.Shl", "BinaryOp.Shr", "BinaryOp.Sub", "Block",
  "ConstDecl", "EntryDecl", "EnumDecl", "EnumVariant", "ErrorDecl", "EventDecl",
  "Expr.Binary", "Expr.Constructor", "Expr.Literal", "Expr.LocalCall", "Expr.Match",
  "Expr.Place", "Expr.Unary", "ExprMatchArm", "ExtensionReq", "ExternalCallExpr",
  "FieldDecl", "FnDecl", "InitDecl", "InvariantDecl", "Literal.Bool",
  "Literal.Integer", "Literal.String", "Param", "Pattern.Bind",
  "Pattern.Constructor", "Pattern.Literal", "Pattern.Wildcard", "Place.Field",
  "Place.Index", "Place.Name", "Program", "ProofDecl", "StateDecl", "Stmt.Assert",
  "Stmt.Assign", "Stmt.Call", "Stmt.Emit", "Stmt.For", "Stmt.If", "Stmt.Let",
  "Stmt.Match", "Stmt.Return", "Stmt.Revert", "Stmt.Schedule", "StmtMatchArm",
  "StructDecl", "Type.Array", "Type.Bool", "Type.Bytes", "Type.Field", "Type.Int",
  "Type.Map", "Type.Named", "Type.Option", "Type.Principal", "Type.UInt", "Type.Unit",
  "UnaryOp.BitNot", "UnaryOp.Neg", "UnaryOp.Not", "ViewDecl",
  "Visibility.Commitment", "Visibility.Private", "Visibility.Public"
]

private def diagnosticFamilies : Array String := #[
  "binary-op", "block", "enum-variant", "expr", "expr-match-arm", "external-call",
  "field-decl", "literal", "param", "pattern", "place", "program", "program-item",
  "stmt", "stmt-match-arm", "type", "unary-op", "visibility"
]

private def expectedFamily : String → String
  | "BinaryOp.Add" | "BinaryOp.And" | "BinaryOp.BitAnd" | "BinaryOp.BitOr" |
      "BinaryOp.BitXor" | "BinaryOp.Div" | "BinaryOp.Eq" | "BinaryOp.Ge" |
      "BinaryOp.Gt" | "BinaryOp.Le" | "BinaryOp.Lt" | "BinaryOp.Mod" |
      "BinaryOp.Mul" | "BinaryOp.Ne" | "BinaryOp.Or" | "BinaryOp.Shl" |
      "BinaryOp.Shr" | "BinaryOp.Sub" => "binary-op"
  | "Visibility.Commitment" | "Visibility.Private" | "Visibility.Public" => "visibility"
  | "UnaryOp.BitNot" | "UnaryOp.Neg" | "UnaryOp.Not" => "unary-op"
  | "Literal.Bool" | "Literal.Integer" | "Literal.String" => "literal"
  | "Type.Array" | "Type.Bool" | "Type.Bytes" | "Type.Field" | "Type.Int" |
      "Type.Map" | "Type.Named" | "Type.Option" | "Type.Principal" |
      "Type.UInt" | "Type.Unit" => "type"
  | "Pattern.Bind" | "Pattern.Constructor" | "Pattern.Literal" |
      "Pattern.Wildcard" => "pattern"
  | "Place.Field" | "Place.Index" | "Place.Name" => "place"
  | "Expr.Binary" | "Expr.Constructor" | "Expr.Literal" | "Expr.LocalCall" |
      "Expr.Match" | "Expr.Place" | "Expr.Unary" => "expr"
  | "Stmt.Assert" | "Stmt.Assign" | "Stmt.Call" | "Stmt.Emit" | "Stmt.For" |
      "Stmt.If" | "Stmt.Let" | "Stmt.Match" | "Stmt.Return" | "Stmt.Revert" |
      "Stmt.Schedule" => "stmt"
  | "Program" => "program"
  | "ConstDecl" | "EntryDecl" | "EnumDecl" | "ErrorDecl" | "EventDecl" |
      "ExtensionReq" | "FnDecl" | "InitDecl" | "InvariantDecl" | "ProofDecl" |
      "StateDecl" | "StructDecl" | "ViewDecl" => "program-item"
  | "Param" => "param"
  | "FieldDecl" => "field-decl"
  | "EnumVariant" => "enum-variant"
  | "Block" => "block"
  | "StmtMatchArm" => "stmt-match-arm"
  | "ExprMatchArm" => "expr-match-arm"
  | "ExternalCallExpr" => "external-call"
  | _ => ""

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def readManifest : IO MutationManifest := do
  let payload ← IO.FS.readFile manifestPath
  match Json.parse payload >>= fromJson? with
  | .ok manifest => pure manifest
  | .error detail => throw <| IO.userError s!"invalid PA128 mutation manifest: {detail}"

private def expectDecodeError (row : MutationRow) (bytes : ByteArray) : IO Unit :=
  match decodeCanonicalSourceAstBytesV1 bytes with
  | .error detail =>
      expect (detail == row.expectedError)
        s!"{row.caseId}: expected '{row.expectedError}', got '{detail}'"
  | .ok _ => throw <| IO.userError s!"{row.caseId}: unexpectedly decoded"

/-- D1-PA-128: all 84 constructor tags fail closed after a one-byte unknown mutation. -/
def run : IO Unit := do
  let canonical ← IO.FS.readBinFile basePath
  let manifest ← readManifest
  let baseSha := Crypto.sha256Hex canonical
  expect (manifest.schema ==
      "proof-forge.source-program-unknown-tag-golden-prerequisite.v1")
    "unknown-tag descriptor schema"
  expect (manifest.scope == "pa125-base-first-occurrence-one-byte-unknown-tag")
    "unknown-tag descriptor scope"
  expect (manifest.baseCaseId == "full-tag-valid-v1" &&
      manifest.baseCanonicalFile ==
        "testdata/golden/source-program-v1/full-tag-v1/canonical.bin")
    "unknown-tag base identity"
  expect (manifest.baseCanonicalBytesSha256 == "sha256:" ++ baseSha &&
      baseSha == "5d38eaca671e503ae50a517cc8ffaddba20b370d11da22f6bcdb807089aa64ce")
    "unknown-tag base digest"
  expect (manifest.diagnosticFamilies == diagnosticFamilies &&
      manifest.diagnosticFamilyCount == 18 && manifest.tagCount == 84 &&
      manifest.mutationCount == 84 && manifest.mutations.size == 84 &&
      wireTags.size == 84)
    "unknown-tag descriptor cardinalities"

  let mut observedTags : Array String := #[]
  let mut observedCases : Array String := #[]
  let mut observedOffsets : Array Nat := #[]
  let mut observedFamilies : Array String := #[]
  let mut previous? : Option String := none
  for row in manifest.mutations do
    expect (wireTags.contains row.originalTag)
      s!"{row.caseId}: unknown canonical tag {row.originalTag}"
    expect (!observedTags.contains row.originalTag)
      s!"{row.caseId}: duplicate canonical tag"
    expect (row.caseId != "" && !observedCases.contains row.caseId)
      s!"{row.caseId}: empty or duplicate case id"
    expect (!observedOffsets.contains row.tagByteOffset)
      s!"{row.caseId}: duplicate tag offset"
    match previous? with
    | none => pure ()
    | some previous =>
        expect (previous < row.originalTag) s!"{row.caseId}: rows are not sorted"
    previous? := some row.originalTag
    observedTags := observedTags.push row.originalTag
    observedCases := observedCases.push row.caseId
    observedOffsets := observedOffsets.push row.tagByteOffset

    let family := expectedFamily row.originalTag
    expect (family != "" && row.diagnosticFamily == family &&
        diagnosticFamilies.contains family)
      s!"{row.caseId}: diagnostic family mismatch"
    unless observedFamilies.contains family do
      observedFamilies := observedFamilies.push family
    expect (row.expectedError ==
        s!"unknown {family} tag '{row.mutatedTag}'")
      s!"{row.caseId}: expected error mismatch"

    let originalBytes := row.originalTag.toUTF8
    let mutatedBytes := row.mutatedTag.toUTF8
    expect (originalBytes.size > 0 && originalBytes.size == mutatedBytes.size &&
        row.tagByteOffset + originalBytes.size ≤ canonical.size)
      s!"{row.caseId}: tag byte range"
    expect (canonical.extract row.tagByteOffset
        (row.tagByteOffset + originalBytes.size) == originalBytes)
      s!"{row.caseId}: base tag bytes mismatch"
    expect (row.originalFirstByte == (originalBytes.get! 0).toNat &&
        row.mutatedFirstByte == 88 && (mutatedBytes.get! 0).toNat == 88 &&
        !wireTags.contains row.mutatedTag)
      s!"{row.caseId}: first-byte mutation metadata"

    let mutated := canonical.set! row.tagByteOffset (UInt8.ofNat row.mutatedFirstByte)
    expect (mutated.size == canonical.size && mutated != canonical &&
        mutated.extract row.tagByteOffset
          (row.tagByteOffset + mutatedBytes.size) == mutatedBytes)
      s!"{row.caseId}: one-byte mutation failed"
    expectDecodeError row mutated
    expect (Crypto.sha256Hex canonical == baseSha)
      s!"{row.caseId}: base canonical bytes changed"

  expect (observedTags == wireTags) "closed 84-tag mutation matrix"
  for family in diagnosticFamilies do
    expect (observedFamilies.contains family) s!"missing diagnostic family {family}"
  expect (observedFamilies.size == 18) "closed 18-family matrix"

  let decoded ← liftResult "decode unchanged PA125 base"
    (decodeCanonicalSourceAstBytesV1 canonical)
  let reencoded ← liftResult "re-encode unchanged PA125 base"
    (canonicalValidatedSourceAstBytesV1 decoded)
  expect (reencoded == canonical && Crypto.sha256Hex canonical == baseSha)
    "PA125 base must remain an exact decode/re-encode fixed point"

end Tests.Language.SourceProgramWireUnknownTagGoldenV1
