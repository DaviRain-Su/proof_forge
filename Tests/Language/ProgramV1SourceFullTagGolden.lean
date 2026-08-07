import Lean
import Tests.Language.ParserSession
import Tests.Language.ProgramV1SourceFullTagGolden.Source
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Language.ProgramExport
import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.SpanJoinV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1

namespace Tests.Language.ProgramV1SourceFullTagGolden

open Lean
open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

private structure GoldenEdge where
  parentTag : String
  fieldTag : String
  deriving DecidableEq, FromJson, Repr

private structure GoldenPathSegment where
  parentTag : String
  fieldTag : String
  index : Nat
  deriving DecidableEq, FromJson, Repr

private structure GoldenNode where
  constructorTag : String
  path : Array GoldenPathSegment
  nodeId : String
  deriving DecidableEq, FromJson, Repr

private structure GoldenSpan where
  constructorTag : String
  path : Array GoldenPathSegment
  startByte : Nat
  endByte : Nat
  deriving DecidableEq, FromJson, Repr

private structure GoldenManifest where
  canonicalBytesSha256 : String
  canonicalFile : String
  caseId : String
  edgePairs : Array GoldenEdge
  expectedNodePathsAndIds : Array GoldenNode
  expectedSourceHash : String
  moduleName : Array String
  nodeTags : Array String
  programIdentity : Array String
  representativeSpans : Array GoldenSpan
  schema : String
  scope : String
  sourceByteDigest : String
  sourceByteSize : Nat
  sourceFile : String
  spanCount : Nat
  wireTags : Array String
  deriving FromJson, Repr

private def packageDirectory : System.FilePath :=
  "testdata/golden/source-program-v1/source-full-tag-v1"

private def sourcePath : System.FilePath := packageDirectory / "source.lean"
private def manifestPath : System.FilePath := packageDirectory / "manifest.json"
private def canonicalPath : System.FilePath := packageDirectory / "canonical.bin"
private def leanFixturePath : System.FilePath :=
  "Tests/Language/ProgramV1SourceFullTagGolden/Source.lean"

private def moduleNameText : String :=
  "Tests.Language.ProgramV1SourceFullTagGolden.Source"

private def declarationName : Name :=
  `Tests.Language.ProgramV1SourceFullTagGolden.Source.FullTag

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def sameSet [BEq α] (left right : Array α) : Bool :=
  left.size == right.size && left.all right.contains && right.all left.contains

private def productionPathText (path : NormalizedSyntacticPathV1) : String :=
  String.intercalate "/" <| path.toList.map fun segment =>
    s!"{segment.parentTag}.{segment.fieldTag}[{segment.index.toNat}]"

private def goldenPathText (path : Array GoldenPathSegment) : String :=
  String.intercalate "/" <| path.toList.map fun segment =>
    s!"{segment.parentTag}.{segment.fieldTag}[{segment.index}]"

private def pathEqual (production : NormalizedSyntacticPathV1)
    (golden : Array GoldenPathSegment) : Bool :=
  production.size == golden.size &&
    (List.range production.size).all fun i =>
      match production[i]?, golden[i]? with
      | some p, some g =>
          p.parentTag == g.parentTag && p.fieldTag == g.fieldTag &&
            p.index.toNat == g.index
      | _, _ => false

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
  "Type.String", "Type.UInt", "Type.Unit", "UnaryOp.BitNot",
  "UnaryOp.Neg", "UnaryOp.Not", "ViewDecl", "Visibility.Commitment",
  "Visibility.Private", "Visibility.Public"

]

private def nodeTags : Array String := #[
  "Program", "StateDecl", "StructDecl", "EnumDecl", "ConstDecl", "EventDecl",
  "ErrorDecl", "InitDecl", "EntryDecl", "ViewDecl", "FnDecl", "InvariantDecl",
  "ExtensionReq", "ProofDecl", "Param", "FieldDecl", "EnumVariant", "Block",
  "StmtMatchArm", "ExprMatchArm", "ExternalCallExpr", "Type.Bool", "Type.UInt",
  "Type.Int", "Type.Principal", "Type.Unit", "Type.String", "Type.Named", "Type.Array",
  "Type.Map", "Type.Option", "Type.Bytes", "Type.Field", "Stmt.Let", "Stmt.Assign",
  "Stmt.If",
  "Stmt.Match", "Stmt.For", "Stmt.Assert", "Stmt.Revert", "Stmt.Emit", "Stmt.Return",
  "Stmt.Call", "Stmt.Schedule", "Expr.Literal", "Expr.Place", "Expr.Constructor",
  "Expr.Unary", "Expr.Binary", "Expr.LocalCall", "Expr.Match", "Place.Name",
  "Place.Field", "Place.Index", "Pattern.Wildcard", "Pattern.Bind", "Pattern.Literal",
  "Pattern.Constructor"
]

private def edgePairs : Array GoldenEdge := #[
  ⟨"Program", "items"⟩, ⟨"StateDecl", "type"⟩, ⟨"StructDecl", "fields"⟩,
  ⟨"EnumDecl", "variants"⟩, ⟨"ConstDecl", "type"⟩, ⟨"ConstDecl", "value"⟩,
  ⟨"EventDecl", "params"⟩, ⟨"ErrorDecl", "params"⟩, ⟨"InitDecl", "params"⟩,
  ⟨"InitDecl", "body"⟩, ⟨"EntryDecl", "params"⟩, ⟨"EntryDecl", "result"⟩,
  ⟨"EntryDecl", "body"⟩, ⟨"ViewDecl", "params"⟩, ⟨"ViewDecl", "result"⟩,
  ⟨"ViewDecl", "body"⟩, ⟨"FnDecl", "params"⟩, ⟨"FnDecl", "result"⟩,
  ⟨"FnDecl", "body"⟩, ⟨"InvariantDecl", "predicate"⟩, ⟨"Param", "type"⟩,
  ⟨"FieldDecl", "type"⟩, ⟨"EnumVariant", "payloadTypes"⟩, ⟨"Block", "statements"⟩,
  ⟨"StmtMatchArm", "pattern"⟩, ⟨"StmtMatchArm", "body"⟩,
  ⟨"ExprMatchArm", "pattern"⟩, ⟨"ExprMatchArm", "value"⟩,
  ⟨"ExternalCallExpr", "args"⟩, ⟨"Type.Array", "element"⟩,
  ⟨"Type.Map", "key"⟩, ⟨"Type.Map", "value"⟩, ⟨"Type.Option", "element"⟩,
  ⟨"Stmt.Let", "typeAnn"⟩, ⟨"Stmt.Let", "value"⟩, ⟨"Stmt.Assign", "target"⟩,
  ⟨"Stmt.Assign", "value"⟩, ⟨"Stmt.If", "condition"⟩, ⟨"Stmt.If", "thenBlock"⟩,
  ⟨"Stmt.If", "elseBlock"⟩, ⟨"Stmt.Match", "scrutinee"⟩, ⟨"Stmt.Match", "arms"⟩,
  ⟨"Stmt.For", "start"⟩, ⟨"Stmt.For", "endExclusive"⟩, ⟨"Stmt.For", "body"⟩,
  ⟨"Stmt.Assert", "condition"⟩, ⟨"Stmt.Revert", "args"⟩, ⟨"Stmt.Emit", "args"⟩,
  ⟨"Stmt.Return", "value"⟩, ⟨"Stmt.Call", "call"⟩, ⟨"Stmt.Schedule", "call"⟩,
  ⟨"Expr.Place", "place"⟩, ⟨"Expr.Constructor", "args"⟩,
  ⟨"Expr.Unary", "operand"⟩, ⟨"Expr.Binary", "lhs"⟩, ⟨"Expr.Binary", "rhs"⟩,
  ⟨"Expr.LocalCall", "args"⟩, ⟨"Expr.Match", "scrutinee"⟩, ⟨"Expr.Match", "arms"⟩,
  ⟨"Place.Field", "base"⟩, ⟨"Place.Index", "base"⟩, ⟨"Place.Index", "index"⟩,
  ⟨"Pattern.Constructor", "args"⟩
]

private def readManifest : IO GoldenManifest := do
  let payload ← IO.FS.readFile manifestPath
  match Json.parse payload >>= fromJson? with
  | .ok manifest => pure manifest
  | .error detail => throw <| IO.userError s!"invalid source-full-tag golden manifest: {detail}"

private unsafe def loadViaLoader (sourceText : String) :
    IO (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1WithSpans sourceText sourcePath.toString
      moduleNameText none with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"Loader path: {error.render}"

private unsafe def loadViaCommand : IO ValidatedSourceV1 := do
  Lean.initSearchPath (← Lean.findSysroot "lean")
  let env ← Lean.importModules
    (imports := #[{ module := `Tests.Language.ProgramV1SourceFullTagGolden.Source }])
    (opts := {})
    (trustLevel := 0)
  match programPayloadV2 env declarationName with
  | .ok source => pure source
  | .error detail => throw <| IO.userError s!"command/export path: {detail}"

/-- B3: source-driven full-tag ProgramV1 golden — command/export vs Loader. -/
unsafe def run : IO Unit := do
  -- Authority: golden source.lean must exist and match the Lean command fixture.
  expect (← sourcePath.pathExists) "missing source-full-tag-v1/source.lean"
  expect (← leanFixturePath.pathExists)
    "missing Tests/Language/ProgramV1SourceFullTagGolden/Source.lean"
  let sourceText ← IO.FS.readFile sourcePath
  let fixtureText ← IO.FS.readFile leanFixturePath
  expect (sourceText == fixtureText)
    "golden source.lean must be byte-identical to the Lean command fixture"

  -- RED until package is frozen.
  expect (← canonicalPath.pathExists) "missing source-full-tag-v1/canonical.bin"
  expect (← manifestPath.pathExists) "missing source-full-tag-v1/manifest.json"

  let manifest ← readManifest
  let canonical ← IO.FS.readBinFile canonicalPath
  expect (manifest.schema == "proof-forge.source-program-v1-source-full-tag-golden.v1")
    "golden schema"
  expect (manifest.scope == "source-driven-programv1-command-and-loader")
    "golden scope"
  expect (manifest.caseId == "source-full-tag-v1" &&
      manifest.canonicalFile == "canonical.bin" &&
      manifest.sourceFile == "source.lean")
    "golden case/file identity"
  expect (manifest.moduleName ==
      #["Tests", "Language", "ProgramV1SourceFullTagGolden", "Source"])
    "moduleName"
  expect (manifest.programIdentity ==
      #["Tests", "Language", "ProgramV1SourceFullTagGolden", "Source", "FullTag"])
    "programIdentity"
  expect (wireTags.size == 86 && sameSet manifest.wireTags wireTags)
    "closed 86-tag wire inventory"
  expect (nodeTags.size == 58 && sameSet manifest.nodeTags nodeTags)
    "closed 58-tag node inventory"
  expect (edgePairs.size == 63 && sameSet manifest.edgePairs edgePairs)
    "closed 63-edge inventory"

  let sourceUtf8 := sourceText.toUTF8
  expect (manifest.sourceByteSize == sourceUtf8.size) "source byte size"
  expect (manifest.sourceByteDigest == "sha256:" ++ Crypto.sha256Hex sourceUtf8)
    "source byte digest"

  -- Independent command/export path vs Loader path (not the same Loader twice).
  let commandSource ← loadViaCommand
  let (loaderSource, loaderSpans) ← loadViaLoader sourceText

  let commandIdentity :=
    (NonEmptyArray.toArray commandSource.programIdentity.components).map (·.raw)
  let loaderIdentity :=
    (NonEmptyArray.toArray loaderSource.programIdentity.components).map (·.raw)
  let commandModule :=
    (NonEmptyArray.toArray commandSource.moduleName.components).map (·.raw)
  let loaderModule :=
    (NonEmptyArray.toArray loaderSource.moduleName.components).map (·.raw)
  expect (commandModule == manifest.moduleName && loaderModule == manifest.moduleName)
    "command/Loader moduleName join"
  expect (commandIdentity == manifest.programIdentity &&
      loaderIdentity == manifest.programIdentity)
    "command/Loader programIdentity join"
  expect (commandSource.program == loaderSource.program)
    "command and Loader must reconstruct the same ProgramV1"
  expect (commandSource.program.name.raw == "FullTag")
    "short program name"

  let commandBytes ← liftResult "command encode"
    (canonicalValidatedSourceAstBytesV1 commandSource)
  let loaderBytes ← liftResult "Loader encode"
    (canonicalValidatedSourceAstBytesV1 loaderSource)
  expect (commandBytes == loaderBytes)
    "command and Loader must produce byte-identical canonical root bytes"
  expect (commandBytes == canonical)
    "production bytes must equal checked-in canonical.bin"
  expect (manifest.canonicalBytesSha256 == "sha256:" ++ Crypto.sha256Hex canonical)
    "canonical.bin SHA-256"

  let commandHash ← liftResult "command sourceHash" (sourceHashV1 commandSource)
  let loaderHash ← liftResult "Loader sourceHash" (sourceHashV1 loaderSource)
  let commandHashText ← liftResult "render command hash" (renderDigest commandHash)
  let loaderHashText ← liftResult "render Loader hash" (renderDigest loaderHash)
  expect (commandHashText == loaderHashText &&
      commandHashText == manifest.expectedSourceHash)
    "command/Loader sourceHash golden"

  let decoded ← liftResult "decode canonical.bin" (decodeCanonicalSourceAstBytesV1 canonical)
  expect (decoded.moduleName == loaderSource.moduleName) "decoded module"
  expect (decoded.programIdentity == loaderSource.programIdentity) "decoded identity"
  expect (decoded.program == loaderSource.program) "decoded ProgramV1"
  let reencoded ← liftResult "re-encode" (canonicalValidatedSourceAstBytesV1 decoded)
  expect (reencoded == canonical) "decode/re-encode fixed point"

  let table ← liftResult "assign NodeIds"
    (assignNodeIdsV1 loaderSource.moduleName loaderSource.programIdentity
      loaderSource.program)
  let assignments := nodeAssignmentsPreorderV1 table
  let expectedRows := manifest.expectedNodePathsAndIds
  expect (assignments.size == expectedRows.size) "golden node row count"
  let mut seenPaths : Array String := #[]
  let mut seenIds : Array String := #[]
  for pair in assignments.zip expectedRows do
    let assignment := pair.1
    let expected := pair.2
    let path := productionPathText assignment.path
    let expectedPath := goldenPathText expected.path
    let nodeId ← liftResult "render NodeId" (renderNodeId assignment.nodeId)
    expect (assignment.constructorTag == expected.constructorTag)
      s!"node tag at {expectedPath}"
    expect (path == expectedPath) s!"node path {expectedPath}"
    expect (nodeId == expected.nodeId) s!"NodeId at {expectedPath}"
    expect (!seenPaths.contains path) s!"duplicate path {path}"
    expect (!seenIds.contains nodeId) s!"duplicate NodeId {nodeId}"
    seenPaths := seenPaths.push path
    seenIds := seenIds.push nodeId

  let visits ← liftResult "canonical visits" (canonicalNodeVisitsV1 loaderSource.program)
  expect (loaderSpans.size == visits.size &&
      loaderSpans.size == assignments.size &&
      loaderSpans.size == manifest.spanCount)
    s!"span count {loaderSpans.size} vs visits {visits.size} vs assignments {assignments.size} vs manifest {manifest.spanCount}"
  -- Path/tag join with NodeId preorder (no tautological re-find on the same zip).
  -- Every Loader span must satisfy startByte ≤ endByte ≤ source UTF-8 size.
  for triple in (loaderSpans.zip visits).zip assignments do
    let (path, span) := triple.1.1
    let visit := triple.1.2
    let assignment := triple.2
    expect (path == visit.path)
      s!"span path must match visit at {visit.constructorTag}"
    expect (path == assignment.path)
      s!"span path must match NodeId assignment at {assignment.constructorTag}"
    expect (visit.constructorTag == assignment.constructorTag)
      s!"visit tag must match NodeId assignment ({visit.constructorTag} vs {assignment.constructorTag})"
    expect (span.startByte.toNat ≤ span.endByte.toNat &&
        span.endByte.toNat ≤ sourceUtf8.size)
      s!"span bounds start≤end≤sourceSize at {visit.constructorTag}"

  -- Representative exact spans from the frozen manifest.
  for expected in manifest.representativeSpans do
    let mut found := false
    for ((path, span), visit) in loaderSpans.zip visits do
      if !found && visit.constructorTag == expected.constructorTag &&
          pathEqual path expected.path then
        expect (span.startByte.toNat == expected.startByte &&
            span.endByte.toNat == expected.endByte)
          s!"representative span bytes for {expected.constructorTag}"
        found := true
    expect found s!"representative span missing for {expected.constructorTag}"

  IO.println "Tests.Language.ProgramV1SourceFullTagGolden: ok"

end Tests.Language.ProgramV1SourceFullTagGolden
