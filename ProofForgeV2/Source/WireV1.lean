import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic

namespace ProofForgeV2.Source.WireV1

open ProofForgeV2.Core.Common

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

private def invalidSourceIdentity (detail : String) : CompileResult α :=
  .error (.invalidProgram detail)

private def qualifiedNameJson
    (name : QualifiedName) : CompileResult PfJson := do
  let components ← match renderQualifiedNameComponents name with
    | .ok value => pure value
    | .error detail => invalidSourceIdentity detail
  pure (.array (components.map PfJson.string))

private def validateIdentityJoin
    (moduleName programIdentity : QualifiedName) : CompileResult Unit := do
  let moduleComponents ← match renderQualifiedNameComponents moduleName with
    | .ok value => pure value
    | .error detail => invalidSourceIdentity detail
  let programComponents ← match renderQualifiedNameComponents programIdentity with
    | .ok value => pure value
    | .error detail => invalidSourceIdentity detail
  unless moduleComponents.size < programComponents.size do
    return ← invalidSourceIdentity
      "program identity must extend the module identity with a declaration name"
  unless programComponents.toList.take moduleComponents.size == moduleComponents.toList do
    return ← invalidSourceIdentity
      "program identity must begin with the exact module identity"

private def pathJson
    (path : NormalizedSyntacticPathV1) : CompileResult PfJson := do
  -- The program root is depth one, so at most 255 child edges fit the
  -- root-inclusive Source.ProgramV1 nesting bound of 256.
  if path.size > 255 then
    return ← invalidSourceIdentity "source node path exceeds the nesting bound"
  let mut values := #[]
  for segment in path do
    match childCardinality? segment.parentTag segment.fieldTag with
    | none =>
        return ← invalidSourceIdentity
          "source node path contains an unknown constructor/field pair"
    | some .direct =>
        unless segment.index == 0 do
          return ← invalidSourceIdentity
            "direct source node path fields require index zero"
    | some .array => pure ()
    values := values.push (.object #[
      ("parentTag", .string segment.parentTag),
      ("fieldTag", .string segment.fieldTag),
      ("index", .int (Int.ofNat segment.index.toNat))
    ])
  pure (.array values)

/--
Canonical NodeId preimage from SPEC-SOURCE-WIRE-001. Source paths, spans,
comments, line/column data, targets and profiles are deliberately absent.
-/
def nodeIdPreimageV1
    (moduleName programIdentity : QualifiedName)
    (path : NormalizedSyntacticPathV1) : CompileResult ByteArray := do
  validateIdentityJoin moduleName programIdentity
  let moduleJson ← qualifiedNameJson moduleName
  let programJson ← qualifiedNameJson programIdentity
  let pathValue ← pathJson path
  let canonical ← match renderPfJcs (.object #[
      ("module", moduleJson),
      ("program", programJson),
      ("path", pathValue)
    ]) with
    | .ok value => pure value
    | .error detail => invalidSourceIdentity detail
  pure (("pf.source-node.v1".toUTF8.push 0).append canonical.toUTF8)

end ProofForgeV2.Source.WireV1
