import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.WireV1

namespace ProofForgeV2.Source.NodeTraversalV1

open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.WireV1

/-- One node-bearing ProgramV1 value in canonical preorder. -/
structure NodeVisitV1 where
  constructorTag : String
  path : NormalizedSyntacticPathV1
  deriving BEq, DecidableEq, Repr

private inductive NodeValueV1 where
  | program (value : ProgramV1)
  | item (value : ProgramItemV1)
  | param (value : ParamV1)
  | fieldDecl (value : FieldDeclV1)
  | enumVariant (value : EnumVariantV1)
  | block (value : BlockV1)
  | stmtMatchArm (value : StmtMatchArmV1)
  | exprMatchArm (value : ExprMatchArmV1)
  | externalCall (value : ExternalCallExprV1)
  | type (value : TypeV1)
  | stmt (value : StmtV1)
  | expr (value : ExprV1)
  | place (value : PlaceV1)
  | pattern (value : PatternV1)

private structure WorkItemV1 where
  node : NodeValueV1
  path : NormalizedSyntacticPathV1

private def maxNodeVisitsV1 : Nat := 100000
private def maxPathEdgesV1 : Nat := 255

private def fail (detail : String) : Except String α :=
  .error detail

private def depthError : Except String α :=
  fail "source node traversal exceeds the nesting bound"

private def nodeError : Except String α :=
  fail "source node traversal exceeds the node limit"

/-- Sole bounded canonical child-path encoder for ProgramV1 node paths.

    Preserves the same nesting (`path.size ≥ 255`) and index (`≥ UInt32.size`)
    bounds as the preorder traversal. Typed producers (B7b) must consume this
    helper (or the direct/index wrappers) and must not invent a second path
    encoder. -/
def childPathV1
    (path : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    Except String NormalizedSyntacticPathV1 := do
  if path.size >= maxPathEdgesV1 then
    return ← depthError
  if index >= UInt32.size then
    return ← nodeError
  pure (path.push {
    parentTag
    fieldTag
    index := UInt32.ofNat index
  })

/-- Direct (index-0) child path — sole wrapper over `childPathV1`. -/
def directChildPathV1
    (path : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) :
    Except String NormalizedSyntacticPathV1 :=
  childPathV1 path parentTag fieldTag 0

/-- Indexed child path — sole wrapper over `childPathV1` (same body; named for
    call-site clarity at array fields). -/
def indexChildPathV1
    (path : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat) :
    Except String NormalizedSyntacticPathV1 :=
  childPathV1 path parentTag fieldTag index

private def pushNodeV1
    (pending : Array WorkItemV1)
    (path : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (index : Nat)
    (node : NodeValueV1) : Except String (Array WorkItemV1) := do
  let childPath ← childPathV1 path parentTag fieldTag index
  pure (pending.push { node, path := childPath })

private def pushDirectV1
    (pending : Array WorkItemV1)
    (path : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (node : NodeValueV1) :
    Except String (Array WorkItemV1) :=
  pushNodeV1 pending path parentTag fieldTag 0 node

private def pushOptionV1
    (pending : Array WorkItemV1)
    (path : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (value : Option α)
    (wrap : α → NodeValueV1) : Except String (Array WorkItemV1) :=
  match value with
  | none => pure pending
  | some child => pushDirectV1 pending path parentTag fieldTag (wrap child)

private def pushArrayV1
    (pending : Array WorkItemV1)
    (path : NormalizedSyntacticPathV1)
    (parentTag fieldTag : String) (values : Array α)
    (wrap : α → NodeValueV1) : Except String (Array WorkItemV1) := do
  if values.size > maxNodeVisitsV1 then
    return ← nodeError
  let mut result := pending
  for (value, index) in values.zipIdx.toList.reverse do
    let next ← pushNodeV1 result path parentTag fieldTag index (wrap value)
    result := next
  pure result

private def visit (tag : String) (item : WorkItemV1) : NodeVisitV1 := {
  constructorTag := tag
  path := item.path
}

/-- Constructor tag for one TypeV1 node, matching program preorder inventory. -/
def typeConstructorTagV1 : TypeV1 → String
  | .bool => "Type.Bool"
  | .uint _ => "Type.UInt"
  | .int _ => "Type.Int"
  | .principal => "Type.Principal"
  | .unit => "Type.Unit"
  | .string => "Type.String"
  | .named _ => "Type.Named"
  | .array .. => "Type.Array"
  | .map .. => "Type.Map"
  | .option _ => "Type.Option"
  | .bytes _ => "Type.Bytes"
  | .field _ => "Type.Field"

/-- Enumerate TypeV1 nodes rooted at `path` in canonical preorder. Map always
visits key before value (wire-field preorder). Consistent with the Type cases of
`canonicalNodeVisitsV1`. -/
def canonicalTypeVisitsV1
    (type_ : TypeV1) (path : NormalizedSyntacticPathV1) :
    Except String (Array NodeVisitV1) := do
  let mut pending : Array WorkItemV1 := #[{ node := .type type_, path }]
  let mut visits : Array NodeVisitV1 := #[]
  while let some current := pending.back? do
    pending := pending.pop
    if visits.size >= maxNodeVisitsV1 then
      return ← nodeError
    match current.node with
    | .type value =>
      match value with
      | .bool => visits := visits.push (visit "Type.Bool" current)
      | .uint _ => visits := visits.push (visit "Type.UInt" current)
      | .int _ => visits := visits.push (visit "Type.Int" current)
      | .principal => visits := visits.push (visit "Type.Principal" current)
      | .unit => visits := visits.push (visit "Type.Unit" current)
      | .string => visits := visits.push (visit "Type.String" current)
      | .named _ => visits := visits.push (visit "Type.Named" current)
      | .array element _ =>
          visits := visits.push (visit "Type.Array" current)
          pending ← pushDirectV1 pending current.path "Type.Array" "element" (.type element)
      | .map key value =>
          visits := visits.push (visit "Type.Map" current)
          -- Stack: push value then key so key is visited first (Map key before value).
          pending ← pushDirectV1 pending current.path "Type.Map" "value" (.type value)
          pending ← pushDirectV1 pending current.path "Type.Map" "key" (.type key)
      | .option element =>
          visits := visits.push (visit "Type.Option" current)
          pending ← pushDirectV1 pending current.path "Type.Option" "element" (.type element)
      | .bytes _ => visits := visits.push (visit "Type.Bytes" current)
      | .field _ => visits := visits.push (visit "Type.Field" current)
    | _ =>
        return ← fail "canonicalTypeVisitsV1 encountered a non-type node"
  pure visits

/-- Enumerate all node-bearing ProgramV1 values by canonical ordered-field preorder. -/
def canonicalNodeVisitsV1
    (program : ProgramV1) : Except String (Array NodeVisitV1) := do
  let mut pending : Array WorkItemV1 := #[{ node := .program program, path := #[] }]
  let mut visits : Array NodeVisitV1 := #[]
  while let some current := pending.back? do
    pending := pending.pop
    if visits.size >= maxNodeVisitsV1 then
      return ← nodeError
    match current.node with
    | .program value =>
        visits := visits.push (visit "Program" current)
        pending ← pushArrayV1 pending current.path "Program" "items" value.items .item
    | .item value =>
      match value with
      | .state declaration =>
          visits := visits.push (visit "StateDecl" current)
          pending ← pushDirectV1 pending current.path "StateDecl" "type" (.type declaration.type_)
      | .struct declaration =>
          visits := visits.push (visit "StructDecl" current)
          pending ← pushArrayV1 pending current.path "StructDecl" "fields"
            declaration.fields .fieldDecl
      | .enum declaration =>
          visits := visits.push (visit "EnumDecl" current)
          pending ← pushArrayV1 pending current.path "EnumDecl" "variants"
            declaration.variants .enumVariant
      | .const declaration =>
          visits := visits.push (visit "ConstDecl" current)
          pending ← pushDirectV1 pending current.path "ConstDecl" "value" (.expr declaration.value)
          pending ← pushDirectV1 pending current.path "ConstDecl" "type" (.type declaration.type_)
      | .event declaration =>
          visits := visits.push (visit "EventDecl" current)
          pending ← pushArrayV1 pending current.path "EventDecl" "params" declaration.params .param
      | .error declaration =>
          visits := visits.push (visit "ErrorDecl" current)
          pending ← pushArrayV1 pending current.path "ErrorDecl" "params" declaration.params .param
      | .init declaration =>
          visits := visits.push (visit "InitDecl" current)
          pending ← pushDirectV1 pending current.path "InitDecl" "body" (.block declaration.body)
          pending ← pushArrayV1 pending current.path "InitDecl" "params" declaration.params .param
      | .entry declaration =>
          visits := visits.push (visit "EntryDecl" current)
          pending ← pushDirectV1 pending current.path "EntryDecl" "body" (.block declaration.body)
          pending ← pushDirectV1 pending current.path "EntryDecl" "result" (.type declaration.result)
          pending ← pushArrayV1 pending current.path "EntryDecl" "params" declaration.params .param
      | .view declaration =>
          visits := visits.push (visit "ViewDecl" current)
          pending ← pushDirectV1 pending current.path "ViewDecl" "body" (.block declaration.body)
          pending ← pushDirectV1 pending current.path "ViewDecl" "result" (.type declaration.result)
          pending ← pushArrayV1 pending current.path "ViewDecl" "params" declaration.params .param
      | .fn declaration =>
          visits := visits.push (visit "FnDecl" current)
          pending ← pushDirectV1 pending current.path "FnDecl" "body" (.block declaration.body)
          pending ← pushDirectV1 pending current.path "FnDecl" "result" (.type declaration.result)
          pending ← pushArrayV1 pending current.path "FnDecl" "params" declaration.params .param
      | .invariant declaration =>
          visits := visits.push (visit "InvariantDecl" current)
          pending ← pushDirectV1 pending current.path "InvariantDecl" "predicate"
            (.expr declaration.predicate)
      | .extensionReq _ => visits := visits.push (visit "ExtensionReq" current)
      | .proof _ => visits := visits.push (visit "ProofDecl" current)
    | .param value =>
        visits := visits.push (visit "Param" current)
        pending ← pushDirectV1 pending current.path "Param" "type" (.type value.type_)
    | .fieldDecl value =>
        visits := visits.push (visit "FieldDecl" current)
        pending ← pushDirectV1 pending current.path "FieldDecl" "type" (.type value.type_)
    | .enumVariant value =>
        visits := visits.push (visit "EnumVariant" current)
        pending ← pushArrayV1 pending current.path "EnumVariant" "payloadTypes"
          value.payloadTypes .type
    | .block value =>
        visits := visits.push (visit "Block" current)
        pending ← pushArrayV1 pending current.path "Block" "statements" value.statements .stmt
    | .stmtMatchArm value =>
        visits := visits.push (visit "StmtMatchArm" current)
        pending ← pushDirectV1 pending current.path "StmtMatchArm" "body" (.block value.body)
        pending ← pushDirectV1 pending current.path "StmtMatchArm" "pattern" (.pattern value.pattern)
    | .exprMatchArm value =>
        visits := visits.push (visit "ExprMatchArm" current)
        pending ← pushDirectV1 pending current.path "ExprMatchArm" "value" (.expr value.value)
        pending ← pushDirectV1 pending current.path "ExprMatchArm" "pattern" (.pattern value.pattern)
    | .externalCall value =>
        visits := visits.push (visit "ExternalCallExpr" current)
        pending ← pushArrayV1 pending current.path "ExternalCallExpr" "args" value.args .expr
    | .type value =>
      match value with
      | .bool => visits := visits.push (visit "Type.Bool" current)
      | .uint _ => visits := visits.push (visit "Type.UInt" current)
      | .int _ => visits := visits.push (visit "Type.Int" current)
      | .principal => visits := visits.push (visit "Type.Principal" current)
      | .unit => visits := visits.push (visit "Type.Unit" current)
      | .string => visits := visits.push (visit "Type.String" current)
      | .named _ => visits := visits.push (visit "Type.Named" current)
      | .array element _ =>
          visits := visits.push (visit "Type.Array" current)
          pending ← pushDirectV1 pending current.path "Type.Array" "element" (.type element)
      | .map key value =>
          visits := visits.push (visit "Type.Map" current)
          pending ← pushDirectV1 pending current.path "Type.Map" "value" (.type value)
          pending ← pushDirectV1 pending current.path "Type.Map" "key" (.type key)
      | .option element =>
          visits := visits.push (visit "Type.Option" current)
          pending ← pushDirectV1 pending current.path "Type.Option" "element" (.type element)
      | .bytes _ => visits := visits.push (visit "Type.Bytes" current)
      | .field _ => visits := visits.push (visit "Type.Field" current)
    | .stmt value =>
      match value with
      | .let_ _ typeAnn value =>
          visits := visits.push (visit "Stmt.Let" current)
          pending ← pushDirectV1 pending current.path "Stmt.Let" "value" (.expr value)
          pending ← pushOptionV1 pending current.path "Stmt.Let" "typeAnn" typeAnn .type
      | .assign target value =>
          visits := visits.push (visit "Stmt.Assign" current)
          pending ← pushDirectV1 pending current.path "Stmt.Assign" "value" (.expr value)
          pending ← pushDirectV1 pending current.path "Stmt.Assign" "target" (.place target)
      | .if_ condition thenBlock elseBlock =>
          visits := visits.push (visit "Stmt.If" current)
          pending ← pushOptionV1 pending current.path "Stmt.If" "elseBlock" elseBlock .block
          pending ← pushDirectV1 pending current.path "Stmt.If" "thenBlock" (.block thenBlock)
          pending ← pushDirectV1 pending current.path "Stmt.If" "condition" (.expr condition)
      | .match_ scrutinee arms =>
          visits := visits.push (visit "Stmt.Match" current)
          pending ← pushArrayV1 pending current.path "Stmt.Match" "arms" arms .stmtMatchArm
          pending ← pushDirectV1 pending current.path "Stmt.Match" "scrutinee" (.expr scrutinee)
      | .for_ _ start endExclusive _ body =>
          visits := visits.push (visit "Stmt.For" current)
          pending ← pushDirectV1 pending current.path "Stmt.For" "body" (.block body)
          pending ← pushDirectV1 pending current.path "Stmt.For" "endExclusive" (.expr endExclusive)
          pending ← pushDirectV1 pending current.path "Stmt.For" "start" (.expr start)
      | .assert_ condition _ =>
          visits := visits.push (visit "Stmt.Assert" current)
          pending ← pushDirectV1 pending current.path "Stmt.Assert" "condition" (.expr condition)
      | .revert _ args =>
          visits := visits.push (visit "Stmt.Revert" current)
          pending ← pushArrayV1 pending current.path "Stmt.Revert" "args" args .expr
      | .emit _ args =>
          visits := visits.push (visit "Stmt.Emit" current)
          pending ← pushArrayV1 pending current.path "Stmt.Emit" "args" args .expr
      | .return_ value =>
          visits := visits.push (visit "Stmt.Return" current)
          pending ← pushOptionV1 pending current.path "Stmt.Return" "value" value .expr
      | .call call =>
          visits := visits.push (visit "Stmt.Call" current)
          pending ← pushDirectV1 pending current.path "Stmt.Call" "call" (.externalCall call)
      | .schedule call =>
          visits := visits.push (visit "Stmt.Schedule" current)
          pending ← pushDirectV1 pending current.path "Stmt.Schedule" "call" (.externalCall call)
    | .expr value =>
      match value with
      | .literal _ => visits := visits.push (visit "Expr.Literal" current)
      | .place place =>
          visits := visits.push (visit "Expr.Place" current)
          pending ← pushDirectV1 pending current.path "Expr.Place" "place" (.place place)
      | .constructor _ args =>
          visits := visits.push (visit "Expr.Constructor" current)
          pending ← pushArrayV1 pending current.path "Expr.Constructor" "args" args .expr
      | .unary _ operand =>
          visits := visits.push (visit "Expr.Unary" current)
          pending ← pushDirectV1 pending current.path "Expr.Unary" "operand" (.expr operand)
      | .binary _ lhs rhs =>
          visits := visits.push (visit "Expr.Binary" current)
          pending ← pushDirectV1 pending current.path "Expr.Binary" "rhs" (.expr rhs)
          pending ← pushDirectV1 pending current.path "Expr.Binary" "lhs" (.expr lhs)
      | .localCall _ args =>
          visits := visits.push (visit "Expr.LocalCall" current)
          pending ← pushArrayV1 pending current.path "Expr.LocalCall" "args" args .expr
      | .match_ scrutinee arms =>
          visits := visits.push (visit "Expr.Match" current)
          pending ← pushArrayV1 pending current.path "Expr.Match" "arms" arms .exprMatchArm
          pending ← pushDirectV1 pending current.path "Expr.Match" "scrutinee" (.expr scrutinee)
      | .externalCall call =>
          visits := visits.push (visit "Expr.ExternalCall" current)
          pending ← pushDirectV1 pending current.path "Expr.ExternalCall" "call" (.externalCall call)
    | .place value =>
      match value with
      | .name _ => visits := visits.push (visit "Place.Name" current)
      | .field base _ =>
          visits := visits.push (visit "Place.Field" current)
          pending ← pushDirectV1 pending current.path "Place.Field" "base" (.place base)
      | .index base index =>
          visits := visits.push (visit "Place.Index" current)
          pending ← pushDirectV1 pending current.path "Place.Index" "index" (.expr index)
          pending ← pushDirectV1 pending current.path "Place.Index" "base" (.place base)
    | .pattern value =>
      match value with
      | .wildcard => visits := visits.push (visit "Pattern.Wildcard" current)
      | .bind _ => visits := visits.push (visit "Pattern.Bind" current)
      | .literal _ => visits := visits.push (visit "Pattern.Literal" current)
      | .constructor _ args =>
          visits := visits.push (visit "Pattern.Constructor" current)
          pending ← pushArrayV1 pending current.path "Pattern.Constructor" "args" args .pattern
  pure visits

end ProofForgeV2.Source.NodeTraversalV1
