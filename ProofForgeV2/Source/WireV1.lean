import ProofForgeV2.Core.Common
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace ProofForgeV2.Source.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

/-- One exact edge in the canonical Source.ProgramV1 node path. -/
structure NodePathSegmentV1 where
  parentTag : String
  fieldTag : String
  index : UInt32
  deriving BEq, DecidableEq, Repr

abbrev NormalizedSyntacticPathV1 := Array NodePathSegmentV1

private inductive ChildCardinality where
  | direct
  | array

/--
The closed set of node-bearing child fields in Source.ProgramV1. Scalar and
tagged-scalar fields are deliberately absent because they never receive a
NodeId path segment.
-/
private def childCardinality? : String → String → Option ChildCardinality
  | "Program", "items" => some .array
  | "StateDecl", "type" => some .direct
  | "StructDecl", "fields" => some .array
  | "EnumDecl", "variants" => some .array
  | "ConstDecl", "type" => some .direct
  | "ConstDecl", "value" => some .direct
  | "EventDecl", "params" => some .array
  | "ErrorDecl", "params" => some .array
  | "InitDecl", "params" => some .array
  | "InitDecl", "body" => some .direct
  | "EntryDecl", "params" => some .array
  | "EntryDecl", "result" => some .direct
  | "EntryDecl", "body" => some .direct
  | "ViewDecl", "params" => some .array
  | "ViewDecl", "result" => some .direct
  | "ViewDecl", "body" => some .direct
  | "FnDecl", "params" => some .array
  | "FnDecl", "result" => some .direct
  | "FnDecl", "body" => some .direct
  | "InvariantDecl", "predicate" => some .direct
  | "Param", "type" => some .direct
  | "FieldDecl", "type" => some .direct
  | "EnumVariant", "payloadTypes" => some .array
  | "Block", "statements" => some .array
  | "StmtMatchArm", "pattern" => some .direct
  | "StmtMatchArm", "body" => some .direct
  | "ExprMatchArm", "pattern" => some .direct
  | "ExprMatchArm", "value" => some .direct
  | "ExternalCallExpr", "args" => some .array
  | "Type.Array", "element" => some .direct
  | "Type.Map", "key" => some .direct
  | "Type.Map", "value" => some .direct
  | "Type.Option", "element" => some .direct
  | "Stmt.Let", "typeAnn" => some .direct
  | "Stmt.Let", "value" => some .direct
  | "Stmt.Assign", "target" => some .direct
  | "Stmt.Assign", "value" => some .direct
  | "Stmt.If", "condition" => some .direct
  | "Stmt.If", "thenBlock" => some .direct
  | "Stmt.If", "elseBlock" => some .direct
  | "Stmt.Match", "scrutinee" => some .direct
  | "Stmt.Match", "arms" => some .array
  | "Stmt.For", "start" => some .direct
  | "Stmt.For", "endExclusive" => some .direct
  | "Stmt.For", "body" => some .direct
  | "Stmt.Assert", "condition" => some .direct
  | "Stmt.Revert", "args" => some .array
  | "Stmt.Emit", "args" => some .array
  | "Stmt.Return", "value" => some .direct
  | "Stmt.Call", "call" => some .direct
  | "Stmt.Schedule", "call" => some .direct
  | "Expr.Place", "place" => some .direct
  | "Expr.Constructor", "args" => some .array
  | "Expr.Unary", "operand" => some .direct
  | "Expr.Binary", "lhs" => some .direct
  | "Expr.Binary", "rhs" => some .direct
  | "Expr.LocalCall", "args" => some .array
  | "Expr.Match", "scrutinee" => some .direct
  | "Expr.Match", "arms" => some .array
  | "Place.Field", "base" => some .direct
  | "Place.Index", "base" => some .direct
  | "Place.Index", "index" => some .direct
  | "Pattern.Constructor", "args" => some .array
  | _, _ => none

private def isProgramItemTag (tag : String) : Bool :=
  #["StateDecl", "StructDecl", "EnumDecl", "ConstDecl", "EventDecl",
    "ErrorDecl", "InitDecl", "EntryDecl", "ViewDecl", "FnDecl",
    "InvariantDecl", "ExtensionReq", "ProofDecl"].contains tag

private def isTypeTag (tag : String) : Bool :=
  #["Type.Bool", "Type.UInt", "Type.Int", "Type.Principal", "Type.Unit",
    "Type.Named", "Type.Array", "Type.Map", "Type.Option", "Type.Bytes",
    "Type.Field"].contains tag

private def isStatementTag (tag : String) : Bool :=
  #["Stmt.Let", "Stmt.Assign", "Stmt.If", "Stmt.Match", "Stmt.For",
    "Stmt.Assert", "Stmt.Revert", "Stmt.Emit", "Stmt.Return", "Stmt.Call",
    "Stmt.Schedule"].contains tag

private def isExpressionTag (tag : String) : Bool :=
  #["Expr.Literal", "Expr.Place", "Expr.Constructor", "Expr.Unary",
    "Expr.Binary", "Expr.LocalCall", "Expr.Match"].contains tag

private def isPlaceTag (tag : String) : Bool :=
  #["Place.Name", "Place.Field", "Place.Index"].contains tag

private def isPatternTag (tag : String) : Bool :=
  #["Pattern.Wildcard", "Pattern.Bind", "Pattern.Literal",
    "Pattern.Constructor"].contains tag

/-- Whether a child edge may lead to a node whose constructor owns the next edge. -/
private def permitsChildTag
    (parentTag fieldTag childTag : String) : Bool :=
  match parentTag, fieldTag with
  | "Program", "items" => isProgramItemTag childTag
  | "StateDecl", "type"
  | "ConstDecl", "type"
  | "EntryDecl", "result"
  | "ViewDecl", "result"
  | "FnDecl", "result"
  | "Param", "type"
  | "FieldDecl", "type"
  | "EnumVariant", "payloadTypes"
  | "Type.Array", "element"
  | "Type.Map", "key"
  | "Type.Map", "value"
  | "Type.Option", "element"
  | "Stmt.Let", "typeAnn" => isTypeTag childTag
  | "StructDecl", "fields" => childTag == "FieldDecl"
  | "EnumDecl", "variants" => childTag == "EnumVariant"
  | "EventDecl", "params"
  | "ErrorDecl", "params"
  | "InitDecl", "params"
  | "EntryDecl", "params"
  | "ViewDecl", "params"
  | "FnDecl", "params" => childTag == "Param"
  | "InitDecl", "body"
  | "EntryDecl", "body"
  | "ViewDecl", "body"
  | "FnDecl", "body"
  | "StmtMatchArm", "body"
  | "Stmt.If", "thenBlock"
  | "Stmt.If", "elseBlock"
  | "Stmt.For", "body" => childTag == "Block"
  | "InvariantDecl", "predicate"
  | "ConstDecl", "value"
  | "ExprMatchArm", "value"
  | "ExternalCallExpr", "args"
  | "Stmt.Let", "value"
  | "Stmt.Assign", "value"
  | "Stmt.If", "condition"
  | "Stmt.Match", "scrutinee"
  | "Stmt.For", "start"
  | "Stmt.For", "endExclusive"
  | "Stmt.Assert", "condition"
  | "Stmt.Revert", "args"
  | "Stmt.Emit", "args"
  | "Stmt.Return", "value"
  | "Expr.Constructor", "args"
  | "Expr.Unary", "operand"
  | "Expr.Binary", "lhs"
  | "Expr.Binary", "rhs"
  | "Expr.LocalCall", "args"
  | "Expr.Match", "scrutinee"
  | "Place.Index", "index" => isExpressionTag childTag
  | "Block", "statements" => isStatementTag childTag
  | "StmtMatchArm", "pattern"
  | "ExprMatchArm", "pattern"
  | "Pattern.Constructor", "args" => isPatternTag childTag
  | "Stmt.Match", "arms" => childTag == "StmtMatchArm"
  | "Expr.Match", "arms" => childTag == "ExprMatchArm"
  | "Stmt.Call", "call"
  | "Stmt.Schedule", "call" => childTag == "ExternalCallExpr"
  | "Stmt.Assign", "target"
  | "Expr.Place", "place"
  | "Place.Field", "base"
  | "Place.Index", "base" => isPlaceTag childTag
  | _, _ => false

private def fail (detail : String) : Except String α :=
  .error detail

private def sourceQualifiedNameJson (name : SourceQualifiedNameV1) : PfJson :=
  .array ((NonEmptyArray.toArray name.components).map fun component =>
    .string component.raw)

private def pathJson
    (path : NormalizedSyntacticPathV1) : Except String PfJson := do
  -- The program root is depth one, so at most 255 child edges fit the
  -- root-inclusive Source.ProgramV1 nesting bound of 256.
  if path.size > 255 then
    return ← fail "source node path exceeds the nesting bound"
  let mut values := #[]
  let mut previous? : Option NodePathSegmentV1 := none
  for segment in path do
    match previous? with
    | none =>
      unless segment.parentTag == "Program" do
        return ← fail
          "non-root source node paths must begin at Program"
    | some previous =>
      unless permitsChildTag previous.parentTag previous.fieldTag segment.parentTag do
        return ← fail
          "source node path contains an impossible constructor transition"
    match childCardinality? segment.parentTag segment.fieldTag with
    | none =>
        return ← fail
          "source node path contains an unknown constructor/field pair"
    | some .direct =>
        unless segment.index == 0 do
          return ← fail
            "direct source node path fields require index zero"
    | some .array => pure ()
    values := values.push (.object #[
      ("parentTag", .string segment.parentTag),
      ("fieldTag", .string segment.fieldTag),
      ("index", .int (Int.ofNat segment.index.toNat))
    ])
    previous? := some segment
  pure (.array values)

/--
Canonical NodeId preimage from SPEC-SOURCE-WIRE-001. Source paths, spans,
comments, line/column data, targets and profiles are deliberately absent.
-/
def nodeIdPreimageV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (path : NormalizedSyntacticPathV1) : Except String ByteArray := do
  validateSourceProgramIdentityV1 moduleName programIdentity
  let moduleJson := sourceQualifiedNameJson moduleName
  let programJson := sourceQualifiedNameJson programIdentity
  let pathValue ← pathJson path
  let canonical ← renderPfJcs (.object #[
    ("module", moduleJson),
    ("program", programJson),
    ("path", pathValue)
  ])
  pure (("pf.source-node.v1".toUTF8.push 0).append canonical.toUTF8)

/-- Fixed production NodeId: first 16 raw bytes of SHA-256(canonical preimage). -/
def nodeIdV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (path : NormalizedSyntacticPathV1) : Except String NodeId := do
  let preimage ← nodeIdPreimageV1 moduleName programIdentity path
  let digest := ProofForgeV2.Crypto.sha256 preimage
  let nodeId : NodeId := { bytes := digest.extract 0 16 }
  validateNodeId nodeId
  pure nodeId

end ProofForgeV2.Source.WireV1
