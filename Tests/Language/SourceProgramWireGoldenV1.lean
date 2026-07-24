import Lean
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1

namespace Tests.Language.SourceProgramWireGoldenV1

open Lean
open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.QualifiedNameV1
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
  schema : String
  scope : String
  wireTags : Array String
  deriving FromJson, Repr

private structure Fixture where
  moduleName : SourceQualifiedNameV1
  programIdentity : SourceQualifiedNameV1
  program : ProgramV1

private def packageDirectory : System.FilePath :=
  "testdata/golden/source-program-v1/full-tag-v1"

private def manifestPath : System.FilePath := packageDirectory / "manifest.json"
private def canonicalPath : System.FilePath := packageDirectory / "canonical.bin"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def name (value : String) : Except String SourceNameComponentV1 :=
  parseSourceNameComponentV1 value

private def qualified (parts : Array String) : Except String SourceQualifiedNameV1 :=
  parseSourceQualifiedNameV1 parts

private def fullTagFixture : Except String Fixture := do
  let fullTag ← name "FullTag"
  let stateN ← name "state"
  let recordN ← name "Record"
  let firstN ← name "first"
  let unicodeN ← name "café"
  let choiceN ← name "Choice"
  let filledN ← name "Filled"
  let emptyN ← name "Empty"
  let limitN ← name "limit"
  let changedN ← name "Changed"
  let whoN ← name "who"
  let eventValueN ← name "eventValue"
  let failureN ← name "Failure"
  let codeN ← name "code"
  let seedN ← name "seed"
  let ownerN ← name "owner"
  let runN ← name "run"
  let inputN ← name "input"
  let readN ← name "read"
  let keyN ← name "key"
  let helperN ← name "helper"
  let argN ← name "arg"
  let safeN ← name "safe"
  let bn254 ← name "bn254_fr"
  let slotN ← name "slot"
  let valueN ← name "value"
  let boundN ← name "bound"
  let otherN ← name "other"
  let typedLocalN ← name "typedLocal"
  let plainLocalN ← name "plainLocal"
  let i0N ← name "i0"
  let i4096N ← name "i4096"
  let choiceFilled ← qualified #["Choice", "Filled"]
  let choiceEmpty ← qualified #["Choice", "Empty"]
  let peerCall ← qualified #["Peer", "call"]
  let peerLater ← qualified #["Peer", "later"]
  let extensionId ← qualified #["ext", "demo"]
  let theoremName ← qualified #["Golden", "theorem"]
  let moduleName ← qualified #["Golden"]
  let programIdentity ← qualified #["Golden", "FullTag"]

  let zero : ExprV1 := .literal (.integer 0)
  let maximum : ExprV1 := .literal (.integer (2 ^ 256 - 1))
  let falseValue : ExprV1 := .literal (.bool false)
  let trueValue : ExprV1 := .literal (.bool true)
  let unicodeValue : ExprV1 := .literal (.string "café")
  let place : PlaceV1 := .index (.field (.name slotN) valueN) zero
  let placeExpr : ExprV1 := .place place
  let ctorEmpty : ExprV1 := .constructor choiceEmpty #[]
  let ctorMany : ExprV1 := .constructor choiceFilled #[trueValue, unicodeValue]
  let unary : Array ExprV1 := #[
    .unary .neg zero, .unary .not zero, .unary .bitNot zero
  ]
  let binary : Array ExprV1 := #[
    .binary .add zero maximum, .binary .sub zero maximum,
    .binary .mul zero maximum, .binary .div zero maximum,
    .binary .mod zero maximum, .binary .eq zero maximum,
    .binary .ne zero maximum, .binary .lt zero maximum,
    .binary .le zero maximum, .binary .gt zero maximum,
    .binary .ge zero maximum, .binary .logicalAnd zero maximum,
    .binary .logicalOr zero maximum, .binary .bitAnd zero maximum,
    .binary .bitOr zero maximum, .binary .bitXor zero maximum,
    .binary .shl zero maximum, .binary .shr zero maximum
  ]
  let localEmpty : ExprV1 := .localCall helperN #[]
  let localMany : ExprV1 := .localCall helperN #[zero, maximum]
  let richPattern : PatternV1 := .constructor choiceFilled #[
    .wildcard, .bind boundN, .literal (.bool true), .constructor choiceEmpty #[]
  ]
  let matchExpr : ExprV1 := .match_ falseValue #[
    { pattern := richPattern, value := ctorMany },
    { pattern := .literal (.string "café"), value := localEmpty }
  ]
  let allExpressions : Array ExprV1 :=
    #[zero, maximum, falseValue, trueValue, unicodeValue, placeExpr,
      ctorEmpty, ctorMany] ++ unary ++ binary ++ #[localEmpty, localMany, matchExpr]

  let returnSome : BlockV1 := { statements := #[.return_ (some unicodeValue)] }
  let returnNone : BlockV1 := { statements := #[.return_ none] }
  let matchStmt : StmtV1 := .match_ trueValue #[
    {
      pattern := richPattern
      body := { statements := #[.assert_ trueValue none] }
    },
    { pattern := .bind otherN, body := returnSome }
  ]
  let loopBody : BlockV1 := {
    statements := #[.emit changedN #[zero, unicodeValue]]
  }
  let initBody : BlockV1 := {
    statements := #[
      .let_ typedLocalN (some (.option .bool)) ctorMany,
      .let_ plainLocalN none localEmpty,
      .assign place (.binary .add zero maximum),
      .if_ trueValue returnSome (some returnNone),
      .if_ falseValue returnNone none,
      matchStmt,
      .for_ i0N zero maximum 0 loopBody,
      .for_ i4096N zero maximum 4096 loopBody,
      .assert_ placeExpr none,
      .assert_ trueValue (some failureN),
      .revert failureN #[],
      .revert failureN #[zero, maximum],
      .emit changedN allExpressions,
      .return_ (some matchExpr),
      .return_ none,
      .call { callee := peerCall, args := allExpressions },
      .schedule { callee := peerLater, args := #[] }
    ]
  }

  let allTypes : Array TypeV1 := #[
    .bool,
    .uint 8, .uint 16, .uint 32, .uint 64, .uint 128, .uint 256,
    .int 8, .int 16, .int 32, .int 64, .int 128, .int 256,
    .principal, .unit, .named recordN,
    .array .bool 0, .array (.uint 8) 4096,
    .map (.uint 16) (.int 16), .option .principal,
    .bytes 0, .bytes 4096, .field bn254
  ]
  let field (fieldName : SourceNameComponentV1) (type_ : TypeV1) : FieldDeclV1 :=
    { name := fieldName, type_ }
  let param (visibility : VisibilityV1) (paramName : SourceNameComponentV1)
      (type_ : TypeV1) : ParamV1 := { visibility, name := paramName, type_ }
  let program : ProgramV1 := {
    name := fullTag
    items := #[
      .state { visibility := .public_, name := stateN, type_ := .array .bool 1 },
      .struct { name := recordN, fields := #[
        field firstN .bool, field unicodeN (.map (.uint 8) (.int 8))
      ] },
      .enum { name := choiceN, variants := #[
        { name := filledN, payloadTypes := allTypes },
        { name := emptyN, payloadTypes := #[] }
      ] },
      .const { name := limitN, type_ := .uint 256, value := maximum },
      .event { name := changedN, params := #[
        param .public_ whoN .principal,
        param .private_ eventValueN (.uint 64)
      ] },
      .error { name := failureN, params := #[
        param .commitment codeN (.uint 32)
      ] },
      .init {
        params := #[
          param .public_ seedN (.uint 64), param .private_ ownerN .principal
        ]
        body := initBody
      },
      .entry {
        name := runN
        params := #[param .public_ inputN (.uint 64)]
        result := .map (.uint 64) (.int 64)
        body := returnSome
      },
      .view {
        name := readN
        params := #[param .public_ keyN (.uint 64)]
        result := .option .bool
        body := returnNone
      },
      .fn {
        name := helperN
        params := #[param .public_ argN (.field bn254)]
        result := .bytes 4096
        body := { statements := #[.return_ (some localMany)] }
      },
      .invariant { name := safeN, predicate := matchExpr },
      .extensionReq {
        id := extensionId
        version := "1.0.0"
        digest := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
      },
      .proof { invariant := safeN, theorem_ := theoremName }
    ]
  }
  pure { moduleName, programIdentity, program }

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

private def nodeTags : Array String := #[
  "Program", "StateDecl", "StructDecl", "EnumDecl", "ConstDecl", "EventDecl",
  "ErrorDecl", "InitDecl", "EntryDecl", "ViewDecl", "FnDecl", "InvariantDecl",
  "ExtensionReq", "ProofDecl", "Param", "FieldDecl", "EnumVariant", "Block",
  "StmtMatchArm", "ExprMatchArm", "ExternalCallExpr", "Type.Bool", "Type.UInt",
  "Type.Int", "Type.Principal", "Type.Unit", "Type.Named", "Type.Array", "Type.Map",
  "Type.Option", "Type.Bytes", "Type.Field", "Stmt.Let", "Stmt.Assign", "Stmt.If",
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

private def sameSet [BEq α] (left right : Array α) : Bool :=
  left.size == right.size && left.all right.contains && right.all left.contains

private def productionPathText (path : NormalizedSyntacticPathV1) : String :=
  String.intercalate "/" <| path.toList.map fun segment =>
    s!"{segment.parentTag}.{segment.fieldTag}[{segment.index.toNat}]"

private def goldenPathText (path : Array GoldenPathSegment) : String :=
  String.intercalate "/" <| path.toList.map fun segment =>
    s!"{segment.parentTag}.{segment.fieldTag}[{segment.index}]"

private def readManifest : IO GoldenManifest := do
  let payload ← IO.FS.readFile manifestPath
  match Json.parse payload >>= fromJson? with
  | .ok manifest => pure manifest
  | .error detail => throw <| IO.userError s!"invalid PA125 golden manifest: {detail}"

/-- D1-PA-125: checked-in full-tag positive ProgramV1 wire golden package. -/
def run : IO Unit := do
  let fixture ← liftResult "full-tag fixture" fullTagFixture
  let manifest ← readManifest
  let canonical ← IO.FS.readBinFile canonicalPath
  expect (manifest.schema == "proof-forge.source-program-wire-golden-prerequisite.v1")
    "golden schema"
  expect (manifest.scope == "constructed-validated-programv1-no-frontend")
    "golden scope"
  expect (manifest.caseId == "full-tag-valid-v1" && manifest.canonicalFile == "canonical.bin")
    "golden case/file identity"
  expect (manifest.moduleName == #["Golden"] &&
      manifest.programIdentity == #["Golden", "FullTag"])
    "golden qualified identities"
  expect (wireTags.size == 84 && sameSet manifest.wireTags wireTags)
    "closed 84-tag wire inventory"
  expect (nodeTags.size == 57 && sameSet manifest.nodeTags nodeTags)
    "closed 57-tag node inventory"
  expect (edgePairs.size == 63 && sameSet manifest.edgePairs edgePairs)
    "closed 63-edge inventory"

  let validated ← liftResult "validate fixture"
    (validateSourceV1 fixture.moduleName fixture.programIdentity fixture.program)
  let productionBytes ← liftResult "production encode"
    (canonicalValidatedSourceAstBytesV1 validated)
  expect (productionBytes == canonical) "production bytes must equal canonical.bin"
  expect (manifest.canonicalBytesSha256 == "sha256:" ++ Crypto.sha256Hex canonical)
    "canonical.bin SHA-256"
  let sourceHash ← liftResult "source hash" (sourceHashV1 validated)
  let renderedHash ← liftResult "render source hash" (renderDigest sourceHash)
  expect (renderedHash == manifest.expectedSourceHash) "sourceHash golden"

  let decoded ← liftResult "decode canonical.bin" (decodeCanonicalSourceAstBytesV1 canonical)
  expect (decoded.moduleName == fixture.moduleName) "decoded module"
  expect (decoded.programIdentity == fixture.programIdentity) "decoded identity"
  expect (decoded.program == fixture.program) "decoded ProgramV1"
  let reencoded ← liftResult "re-encode decoded golden"
    (canonicalValidatedSourceAstBytesV1 decoded)
  expect (reencoded == canonical) "decode/re-encode fixed point"

  let table ← liftResult "production node assignment"
    (assignNodeIdsV1 fixture.moduleName fixture.programIdentity fixture.program)
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
    let nodeId ← liftResult "render assigned NodeId" (renderNodeId assignment.nodeId)
    expect (assignment.constructorTag == expected.constructorTag)
      s!"node tag at {expectedPath}"
    expect (path == expectedPath) s!"node path {expectedPath}"
    expect (nodeId == expected.nodeId) s!"NodeId at {expectedPath}"
    expect (!seenPaths.contains path) s!"duplicate golden path {path}"
    expect (!seenIds.contains nodeId) s!"duplicate golden NodeId {nodeId}"
    seenPaths := seenPaths.push path
    seenIds := seenIds.push nodeId

  let rebuiltModuleParts : Array String := manifest.moduleName.foldl
    (fun parts part => parts.push part) (Array.emptyWithCapacity 257)
  let rebuiltIdentityParts : Array String := manifest.programIdentity.foldl
    (fun parts part => parts.push part) (Array.emptyWithCapacity 257)
  let rebuiltItems : Array ProgramItemV1 := fixture.program.items.foldl
    (fun items item => items.push item)
    (Array.emptyWithCapacity (fixture.program.items.size + 64))
  let twinModule ← liftResult "allocation-history module" (qualified rebuiltModuleParts)
  let twinIdentity ← liftResult "allocation-history identity" (qualified rebuiltIdentityParts)
  let twinProgram : ProgramV1 := { fixture.program with items := rebuiltItems }
  expect (twinModule == fixture.moduleName && twinIdentity == fixture.programIdentity &&
      twinProgram == fixture.program)
    "allocation-history twins must retain the same logical source value"
  let twinValidated ← liftResult "allocation-history validate"
    (validateSourceV1 twinModule twinIdentity twinProgram)
  let twinBytes ← liftResult "allocation-history encode"
    (canonicalValidatedSourceAstBytesV1 twinValidated)
  let twinHash ← liftResult "allocation-history hash" (sourceHashV1 twinValidated)
  let twinHashText ← liftResult "allocation-history hash render" (renderDigest twinHash)
  let twinTable ← liftResult "allocation-history node assignment"
    (assignNodeIdsV1 twinModule twinIdentity twinProgram)
  expect (twinBytes == canonical && twinHashText == manifest.expectedSourceHash &&
      nodeAssignmentsPreorderV1 twinTable == assignments)
    "array capacity/insertion history must not alter bytes, sourceHash, or NodeIds"

end Tests.Language.SourceProgramWireGoldenV1
