import Lean
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.SourceProgramWireFieldCountGoldenV1

open Lean
open ProofForgeV2
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.ValidatedSourceV1

private structure MutationRow where
  caseId : String
  expectedCount : Nat
  expectedError : String
  fieldCountOffset : Nat
  mutatedCount : Nat
  tag : String
  deriving FromJson, Repr

private structure MutationManifest where
  baseCanonicalBytesSha256 : String
  baseCanonicalFile : String
  baseCaseId : String
  mutationCount : Nat
  mutations : Array MutationRow
  nullaryTagCount : Nat
  positiveFieldTagCount : Nat
  schema : String
  scope : String
  tagCount : Nat
  deriving FromJson, Repr

private def basePath : System.FilePath :=
  "testdata/golden/source-program-v1/full-tag-v1/canonical.bin"

private def manifestPath : System.FilePath :=
  "testdata/golden/source-program-v1/field-count-v1/manifest.json"

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
  | .error detail => throw <| IO.userError s!"invalid PA126 mutation manifest: {detail}"

private def wireTags : Array String := #[
  "BinaryOp.Add", "BinaryOp.And", "BinaryOp.BitAnd", "BinaryOp.BitOr",
  "BinaryOp.BitXor", "BinaryOp.Div", "BinaryOp.Eq", "BinaryOp.Ge",
  "BinaryOp.Gt", "BinaryOp.Le", "BinaryOp.Lt", "BinaryOp.Mod",
  "BinaryOp.Mul", "BinaryOp.Ne", "BinaryOp.Or", "BinaryOp.Shl",
  "BinaryOp.Shr", "BinaryOp.Sub", "Block", "ConstDecl",
  "EntryDecl", "EnumDecl", "EnumVariant", "ErrorDecl",
  "EventDecl", "Expr.Binary", "Expr.Constructor", "Expr.Literal",
  "Expr.LocalCall", "Expr.Match", "Expr.Place", "Expr.Unary",
  "ExprMatchArm", "ExtensionReq", "ExternalCallExpr", "FieldDecl",
  "FnDecl", "InitDecl", "InvariantDecl", "Literal.Bool",
  "Literal.Integer", "Literal.String", "Param", "Pattern.Bind",
  "Pattern.Constructor", "Pattern.Literal", "Pattern.Wildcard", "Place.Field",
  "Place.Index", "Place.Name", "Program", "ProofDecl",
  "ProofKind.Holds", "StateDecl", "Stmt.Assert", "Stmt.Assign",
  "Stmt.Call", "Stmt.Emit", "Stmt.For", "Stmt.If",
  "Stmt.Let", "Stmt.Match", "Stmt.Return", "Stmt.Revert",
  "Stmt.Schedule", "StmtMatchArm", "StructDecl", "Type.Array",
  "Type.Bool", "Type.Bytes", "Type.Field", "Type.Int",
  "Type.Map", "Type.Named", "Type.Option", "Type.Principal",
  "Type.UInt", "Type.Unit", "UnaryOp.BitNot", "UnaryOp.Neg",
  "UnaryOp.Not", "ViewDecl", "Visibility.Commitment", "Visibility.Private",
  "Visibility.Public"

]

private def fieldCountAt (bytes : ByteArray) (offset : Nat) : Nat :=
  (bytes.get! offset).toNat + 256 * (bytes.get! (offset + 1)).toNat

private def mutateFieldCount (bytes : ByteArray) (offset count : Nat) : ByteArray :=
  (bytes.set! offset (UInt8.ofNat (count % 256))).set!
    (offset + 1) (UInt8.ofNat (count / 256))

private def expectDecodeError (row : MutationRow) (bytes : ByteArray) : IO Unit :=
  match decodeCanonicalSourceAstBytesV1 bytes with
  | .error detail =>
      expect (detail == row.expectedError)
        s!"{row.caseId}: expected '{row.expectedError}', got '{detail}'"
  | .ok _ => throw <| IO.userError s!"{row.caseId}: unexpectedly decoded"

/-- D1-PA-126: all 85 constructor field-count negatives over the PA125 base. -/
def run : IO Unit := do
  let canonical ← IO.FS.readBinFile basePath
  let manifest ← readManifest
  let baseSha := Crypto.sha256Hex canonical
  expect (manifest.schema ==
      "proof-forge.source-program-field-count-golden-prerequisite.v1")
    "field-count descriptor schema"
  expect (manifest.scope == "pa125-base-first-occurrence-exact-field-count")
    "field-count descriptor scope"
  expect (manifest.baseCaseId == "full-tag-valid-v1" &&
      manifest.baseCanonicalFile ==
        "testdata/golden/source-program-v1/full-tag-v1/canonical.bin")
    "field-count base identity"
  expect (manifest.baseCanonicalBytesSha256 == "sha256:" ++ baseSha &&
      baseSha == "a7075ca364c099e18510c1f5a8961449e3859d6a45fec46820d327a7d095a0d8")
    "field-count base digest"
  expect (manifest.tagCount == 85 && manifest.nullaryTagCount == 29 &&
      manifest.positiveFieldTagCount == 56 && manifest.mutationCount == 141 &&
      manifest.mutations.size == 141 && wireTags.size == 85)
    "field-count descriptor cardinalities"

  let mut seenKeys : Array String := #[]
  let mut previous? : Option (String × Nat) := none
  for row in manifest.mutations do
    expect (wireTags.contains row.tag) s!"unknown mutation tag {row.tag}"
    expect (row.fieldCountOffset + 2 ≤ canonical.size)
      s!"{row.caseId}: offset outside canonical.bin"
    expect (row.expectedCount < 65536 && row.mutatedCount < 65536)
      s!"{row.caseId}: count outside u16"
    expect (fieldCountAt canonical row.fieldCountOffset == row.expectedCount)
      s!"{row.caseId}: base field count mismatch"
    expect (row.expectedError ==
      s!"tag '{row.tag}' must declare {row.expectedCount} fields")
      s!"{row.caseId}: expected error mismatch"
    let key := row.tag ++ "\u0000" ++ toString row.mutatedCount
    expect (!seenKeys.contains key) s!"duplicate mutation key {row.caseId}"
    seenKeys := seenKeys.push key
    match previous? with
    | none => pure ()
    | some previous =>
        expect (previous.1 < row.tag ||
          (previous.1 == row.tag && previous.2 < row.mutatedCount))
          s!"{row.caseId}: mutation rows are not sorted"
    previous? := some (row.tag, row.mutatedCount)
    let mutated := mutateFieldCount canonical row.fieldCountOffset row.mutatedCount
    expect (mutated != canonical) s!"{row.caseId}: mutation did not change bytes"
    expectDecodeError row mutated
    expect (Crypto.sha256Hex canonical == baseSha)
      s!"{row.caseId}: base canonical bytes changed"

  let mut nullaryTags : Nat := 0
  let mut positiveTags : Nat := 0
  for tag in wireTags do
    let rows := manifest.mutations.filter (fun row => row.tag == tag)
    match rows[0]? with
    | none => throw <| IO.userError s!"missing field-count rows for {tag}"
    | some first =>
        expect (rows.all fun row => row.expectedCount == first.expectedCount)
          s!"inconsistent expected count for {tag}"
        if first.expectedCount == 0 then
          nullaryTags := nullaryTags + 1
          expect (rows.size == 1 && rows.any fun row => row.mutatedCount == 1)
            s!"nullary mutation matrix for {tag}"
        else
          positiveTags := positiveTags + 1
          expect (rows.size == 2 &&
              rows.any (fun row => row.mutatedCount + 1 == first.expectedCount) &&
              rows.any (fun row => row.mutatedCount == first.expectedCount + 1))
            s!"positive field-count mutation matrix for {tag}"
  expect (nullaryTags == 29 && positiveTags == 56)
    "observed field-count partition"

  let decoded ← liftResult "decode unchanged PA125 base"
    (decodeCanonicalSourceAstBytesV1 canonical)
  let reencoded ← liftResult "re-encode unchanged PA125 base"
    (canonicalValidatedSourceAstBytesV1 decoded)
  expect (reencoded == canonical && Crypto.sha256Hex canonical == baseSha)
    "PA125 base must remain an exact decode/re-encode fixed point"

end Tests.Language.SourceProgramWireFieldCountGoldenV1
