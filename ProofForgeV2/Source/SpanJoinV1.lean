import Lean
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Language.Syntax

namespace ProofForgeV2.Source.SpanJoinV1

open Lean
open ProofForgeV2
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Language

private def fail (detail : String) : Except String α :=
  .error detail

private def spanOfSyntax
    (source : String) (stx : Syntax) : Except String SourceByteSpanV1 :=
  match originalSyntaxByteSpanV1 source stx with
  | .ok span => .ok span
  | .error err => fail err.render

/-- Span covering the original tokens of all provided syntaxes in order. -/
private def spanOfSyntaxes
    (source : String) (stxs : Array Syntax) : Except String SourceByteSpanV1 :=
  if stxs.isEmpty then
    fail "spanOfSyntaxes requires at least one syntax"
  else
    spanOfSyntax source (Syntax.node SourceInfo.none nullKind stxs)

/-- Find the first atom with the given value anywhere in the syntax tree. -/
private partial def findAtom (stx : Syntax) (value : String) : Option Syntax :=
  if stx.isAtom && stx.getAtomVal == value then
    some stx
  else
    stx.getArgs.findSome? (findAtom · value)

private structure SpanVisitV1 where
  path : NormalizedSyntacticPathV1
  tag : String
  span : SourceByteSpanV1
  deriving BEq

/-- Join one TypeV1 subtree by zipping sole-decoder syntax anchors with
canonical TypeV1 visits. SpanJoin does not classify type tokens, walk type
syntax, or re-interpret type structure: the decoder produces anchors and
`canonicalTypeVisitsV1` produces tags/paths; count/tag/path and decoded-type
identity are validated here. -/
private def walkTypeV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (type_ : TypeV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let (decoded, anchors) ← match decodeTypeV1WithAnchors stx with
    | .ok value => pure value
    | .error detail => fail detail
  unless decoded == type_ do
    fail "type span join type identity mismatch"
  let typeVisits ← match canonicalTypeVisitsV1 type_ path with
    | .ok visits => pure visits
    | .error detail => fail detail
  unless anchors.size == typeVisits.size do
    fail s!"type span join count mismatch: {anchors.size} anchors vs {typeVisits.size} type visits"
  let mut visits : Array SpanVisitV1 := #[]
  for (anchor, typeVisit) in anchors.zip typeVisits do
    let span ← spanOfSyntax source anchor
    visits := visits.push {
      path := typeVisit.path
      tag := typeVisit.constructorTag
      span
    }
  pure visits

private def tagOfItem (item : ProgramItemV1) : String :=
  match item with
  | .state _ => "StateDecl"
  | .struct _ => "StructDecl"
  | .enum _ => "EnumDecl"
  | .const _ => "ConstDecl"
  | .event _ => "EventDecl"
  | .error _ => "ErrorDecl"
  | .init _ => "InitDecl"
  | .entry _ => "EntryDecl"
  | .view _ => "ViewDecl"
  | .fn _ => "FnDecl"
  | .invariant _ => "InvariantDecl"
  | .extensionReq _ => "ExtensionReq"
  | .proof _ => "ProofDecl"

/-- Children of a sepBy null node, dropping separator atoms. -/
private def sepByChildren (stx : Syntax) : Array Syntax :=
  match stx with
  | .node _ `null args => args.filter (!·.isAtom)
  | _ => stx.getArgs.filter (!·.isAtom)

private def atomValue (stx : Syntax) (value : String) : Bool :=
  stx.isAtom && stx.getAtomVal == value

private def projectKind? (stx : Syntax) : Option (String × String) :=
  let k := stx.getKind
  if k.getPrefix == `ProofForgeV2.Language then
    some (k.getString!, k.toString)
  else
    none

private partial def unwrapTransparentExpr (stx : Syntax) : Syntax :=
  match projectKind? stx with
  | some ("pfExpr(_)", _) =>
      if stx.getArgs.size == 3 then
        unwrapTransparentExpr stx.getArgs[1]!
      else
        stx
  | _ => stx

/-- Return true if `stx` is a `pfType` node. The category has many concrete
node kinds, all ending in `Type` under the project namespace. -/
private def isPfType (stx : Syntax) : Bool :=
  match projectKind? stx with
  | some (last, _) => last.endsWith "Type"
  | none => false

/-- Return true if `stx` is a `pfExpr` node. The category has many concrete
node kinds, prefixed with `pfExpr` or ending in `Expr`. -/
private def isPfExpr (stx : Syntax) : Bool :=
  match projectKind? stx with
  | some (last, _) => last.startsWith "pfExpr" || last.endsWith "Expr"
  | none => false

/-- Return true if `stx` is a `pfPlace` node. -/
private def isPfPlace (stx : Syntax) : Bool :=
  match projectKind? stx with
  | some (last, _) => last.startsWith "pfPlace"
  | none => false

/-- Return true if `stx` is a `pfParam` node. -/
private def isPfParam (stx : Syntax) : Bool :=
  match projectKind? stx with
  | some (last, _) => last.startsWith "pfParam"
  | none => false

/-- Extract the children of the `null` node that immediately follows the given
atom in `stx`'s direct arguments. Used to obtain program items after `where`,
struct fields after `where`, and enum variants after `where`. -/
private def childrenAfterAtom (stx : Syntax) (value : String) : Array Syntax :=
  match stx.getArgs.findIdx? (atomValue · value) with
  | some idx =>
      match stx.getArgs[idx+1]? with
      | some node =>
          if node.isOfKind `null then
            node.getArgs.filter fun s => !s.isAtom && !s.isIdent
          else
            #[]
      | none => #[]
  | none => #[]

private def findAfterAtom (args : Array Syntax) (value : String) : Option Syntax :=
  match args.findIdx? (atomValue · value) with
  | some idx => args[idx+1]?
  | none => none

private def callableParamsAndBody (stx : Syntax) : Except String (Array Syntax × Array Syntax) := do
  let args := stx.getArgs
  let paramsNode ← match findAfterAtom args "(" with
    | some node => pure node
    | none => fail "callable declaration missing '('"
  let params := sepByChildren paramsNode
  let body := match findAfterAtom args "do" with
    | some node => sepByChildren node
    | none => #[]
  pure (params, body)

private def callableResultSyntax? (stx : Syntax) : Option Syntax :=
  match findAfterAtom stx.getArgs ")" with
  | none => none
  | some s =>
      if s.isAtom then
        none
      else
        -- Result is wrapped as `":" type`; the Type node span is the
        -- `portableType` child.
        match s.getArgs.find? isPfType with
        | some typeStx => some typeStx
        | none => some s

private def doAtomSpan (source : String) (stx : Syntax) : Except String SourceByteSpanV1 :=
  match findAtom stx "do" with
  | some atom => spanOfSyntax source atom
  | none => fail "missing do atom for inferred unit result"

mutual

private partial def walkBlockV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (block : BlockV1) (stxs : Array Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntaxes source stxs
  unless stxs.size == block.statements.size do
    fail "block statement count mismatch"
  let mut visits : Array SpanVisitV1 := #[{ path, tag := "Block", span }]
  let mut stmtVisits : Array SpanVisitV1 := #[]
  for ((stmt, stmtStx), idx) in block.statements.zip stxs |>.zipIdx do
    let childPath := path.push {
      parentTag := "Block", fieldTag := "statements",
      index := UInt32.ofNat idx
    }
    let subVisits ← walkStmtV1 source childPath stmt stmtStx
    stmtVisits := stmtVisits ++ subVisits
  pure (visits ++ stmtVisits)

private partial def walkStmtV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (stmt : StmtV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  match stmt with
  | .let_ _ typeAnn value => do
      let args := stx.getArgs
      let typeAnnStx? := args.find? (isPfType)
      let valueStx ← match args.find? (isPfExpr) with
        | some s => pure s
        | none => fail "let statement missing value"
      let typeAnnVisits ← match typeAnn, typeAnnStx? with
        | some type_, some typeStx =>
            let typePath := path.push {
              parentTag := "Stmt.Let", fieldTag := "typeAnn", index := 0
            }
            walkTypeV1 source typePath type_ typeStx
        | none, none => pure #[]
        | _, _ => fail "let statement type annotation mismatch"
      let valuePath := path.push {
        parentTag := "Stmt.Let", fieldTag := "value", index := 0
      }
      let valueVisits ← walkExprV1 source valuePath value valueStx
      pure (#[{ path, tag := "Stmt.Let", span }] ++ typeAnnVisits ++ valueVisits)
  | .assign target value => do
      let args := stx.getArgs
      let targetStx ← match args.find? (isPfPlace) with
        | some s => pure s
        | none => fail "assign statement missing target"
      let valueStx ← match args.find? (isPfExpr) with
        | some s => pure s
        | none => fail "assign statement missing value"
      let targetPath := path.push {
        parentTag := "Stmt.Assign", fieldTag := "target", index := 0
      }
      let valuePath := path.push {
        parentTag := "Stmt.Assign", fieldTag := "value", index := 0
      }
      let targetVisits ← walkPlaceV1 source targetPath target targetStx
      let valueVisits ← walkExprV1 source valuePath value valueStx
      pure (#[{ path, tag := "Stmt.Assign", span }] ++ targetVisits ++ valueVisits)
  | .if_ condition thenBlock elseBlock => do
      let args := stx.getArgs
      unless args.size == 5 && args[0]!.getAtomVal == "if" &&
          args[2]!.getAtomVal == "then" do
        fail "if statement span mismatch"
      let condStx := args[1]!
      let thenStxs := sepByChildren args[3]!
      let elseStxs? ← match args[4]! with
        | .node _ `null #[] => pure none
        | .node _ `null #[atom, bodyNode] =>
            if atom.getAtomVal == "else" then
              pure (some (sepByChildren bodyNode))
            else fail "if statement else mismatch"
        | _ => fail "if statement else mismatch"
      let condPath := path.push {
        parentTag := "Stmt.If", fieldTag := "condition", index := 0
      }
      let thenPath := path.push {
        parentTag := "Stmt.If", fieldTag := "thenBlock", index := 0
      }
      let condVisits ← walkExprV1 source condPath condition condStx
      let thenVisits ← walkBlockV1 source thenPath thenBlock thenStxs
      let elseVisits ← match elseBlock, elseStxs? with
        | some block, some stxs =>
            let elsePath := path.push {
              parentTag := "Stmt.If", fieldTag := "elseBlock", index := 0
            }
            walkBlockV1 source elsePath block stxs
        | none, none => pure #[]
        | _, _ => fail "if statement else block mismatch"
      pure (#[{ path, tag := "Stmt.If", span }] ++ condVisits ++ thenVisits ++ elseVisits)
  | .match_ scrutinee arms => do
      let args := stx.getArgs
      unless args.size == 4 && args[0]!.getAtomVal == "match" &&
          args[2]!.getAtomVal == "with" do
        fail "statement match span mismatch"
      let scrutStx := args[1]!
      let armStxs := sepByChildren args[3]!
      unless armStxs.size == arms.size do
        fail "statement match arm count mismatch"
      let scrutPath := path.push {
        parentTag := "Stmt.Match", fieldTag := "scrutinee", index := 0
      }
      let scrutVisits ← walkExprV1 source scrutPath scrutinee scrutStx
      let mut visits : Array SpanVisitV1 := #[{ path, tag := "Stmt.Match", span }]
      let mut armVisits : Array SpanVisitV1 := #[]
      for ((arm, armStx), idx) in arms.zip armStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "Stmt.Match", fieldTag := "arms",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkStmtMatchArmV1 source childPath arm armStx
        armVisits := armVisits ++ subVisits
      pure (visits ++ scrutVisits ++ armVisits)
  | .for_ _ start endExclusive _ body => do
      let args := stx.getArgs
      unless args.size == 10 && args[0]!.getAtomVal == "for" &&
          args[2]!.getAtomVal == "in" && args[4]!.getAtomVal == "..<" &&
          args[6]!.getAtomVal == "bounded" && args[8]!.getAtomVal == "do" do
        fail "for statement span mismatch"
      let startStx := args[3]!
      let endStx := args[5]!
      let bodyStxs := sepByChildren args[9]!
      let startPath := path.push {
        parentTag := "Stmt.For", fieldTag := "start", index := 0
      }
      let endPath := path.push {
        parentTag := "Stmt.For", fieldTag := "endExclusive", index := 0
      }
      let bodyPath := path.push {
        parentTag := "Stmt.For", fieldTag := "body", index := 0
      }
      let startVisits ← walkExprV1 source startPath start startStx
      let endVisits ← walkExprV1 source endPath endExclusive endStx
      let bodyVisits ← walkBlockV1 source bodyPath body bodyStxs
      pure (#[{ path, tag := "Stmt.For", span }] ++ startVisits ++ endVisits ++ bodyVisits)
  | .assert_ condition _ => do
      let args := stx.getArgs
      let condStx ← match args.find? (isPfExpr) with
        | some s => pure s
        | none => fail "assert statement missing condition"
      let condPath := path.push {
        parentTag := "Stmt.Assert", fieldTag := "condition", index := 0
      }
      let condVisits ← walkExprV1 source condPath condition condStx
      pure (#[{ path, tag := "Stmt.Assert", span }] ++ condVisits)
  | .revert _ args => do
      let argStxs := match stx.getArgs.find? (isPfExpr) with
        | some expr => #[expr]
        | none =>
            match stx.getArgs.find? fun arg =>
                match arg with
                | .node _ `null _ => true
                | _ => false with
            | some node => sepByChildren node
            | none => #[]
      unless argStxs.size == args.size do
        fail "revert argument count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag := "Stmt.Revert", span }]
      let mut argVisits : Array SpanVisitV1 := #[]
      for ((arg, argStx), idx) in args.zip argStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "Stmt.Revert", fieldTag := "args",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkExprV1 source childPath arg argStx
        argVisits := argVisits ++ subVisits
      pure (visits ++ argVisits)
  | .emit _ args => do
      let argStxs := match stx.getArgs.find? fun arg =>
          match arg with
          | .node _ `null _ => true
          | _ => false with
        | some node => sepByChildren node
        | none => #[]
      unless argStxs.size == args.size do
        fail "emit argument count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag := "Stmt.Emit", span }]
      let mut argVisits : Array SpanVisitV1 := #[]
      for ((arg, argStx), idx) in args.zip argStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "Stmt.Emit", fieldTag := "args",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkExprV1 source childPath arg argStx
        argVisits := argVisits ++ subVisits
      pure (visits ++ argVisits)
  | .return_ value => do
      match value with
      | some expr => do
          let args := stx.getArgs
          let valueStx ← match args.find? (isPfExpr) with
            | some s => pure s
            | none => fail "return statement missing value"
          let valuePath := path.push {
            parentTag := "Stmt.Return", fieldTag := "value", index := 0
          }
          let valueVisits ← walkExprV1 source valuePath expr valueStx
          pure (#[{ path, tag := "Stmt.Return", span }] ++ valueVisits)
      | none =>
          pure #[{ path, tag := "Stmt.Return", span }]
  | .call c => do
      let callPath := path.push {
        parentTag := "Stmt.Call", fieldTag := "call", index := 0
      }
      let callVisits ← walkExternalCallV1 source callPath c stx
      pure (#[{ path, tag := "Stmt.Call", span }] ++ callVisits)
  | .schedule s => do
      let callPath := path.push {
        parentTag := "Stmt.Schedule", fieldTag := "call", index := 0
      }
      let callVisits ← walkExternalCallV1 source callPath s stx
      pure (#[{ path, tag := "Stmt.Schedule", span }] ++ callVisits)

private partial def walkStmtMatchArmV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (arm : StmtMatchArmV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  let args := stx.getArgs
  unless args.size == 5 && args[0]!.getAtomVal == "|" &&
      args[2]!.getAtomVal == "=>" && args[3]!.getAtomVal == "do" do
    fail "statement match arm span mismatch"
  let patternStx := args[1]!
  let bodyStxs := sepByChildren args[4]!
  let patternPath := path.push {
    parentTag := "StmtMatchArm", fieldTag := "pattern", index := 0
  }
  let bodyPath := path.push {
    parentTag := "StmtMatchArm", fieldTag := "body", index := 0
  }
  let patternVisits ← walkPatternV1 source patternPath arm.pattern patternStx
  let bodyVisits ← walkBlockV1 source bodyPath arm.body bodyStxs
  pure (#[{ path, tag := "StmtMatchArm", span }] ++ patternVisits ++ bodyVisits)

private partial def walkExternalCallV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (c : ExternalCallExprV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  let argStxs := match stx.getArgs.find? fun arg =>
      match arg with
      | .node _ `null _ => true
      | _ => false with
    | some node => sepByChildren node
    | none => #[]
  unless argStxs.size == c.args.size do
    fail "external call argument count mismatch"
  let mut visits : Array SpanVisitV1 := #[{ path, tag := "ExternalCallExpr", span }]
  let mut argVisits : Array SpanVisitV1 := #[]
  for ((arg, argStx), idx) in c.args.zip argStxs |>.zipIdx do
    let childPath := path.push {
      parentTag := "ExternalCallExpr", fieldTag := "args",
      index := UInt32.ofNat idx
    }
    let subVisits ← walkExprV1 source childPath arg argStx
    argVisits := argVisits ++ subVisits
  pure (visits ++ argVisits)

private partial def walkExprV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (expr : ExprV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let stx := unwrapTransparentExpr stx
  let span ← spanOfSyntax source stx
  match expr with
  | .literal _ =>
      pure #[{ path, tag := "Expr.Literal", span }]
  | .place place => do
      let placeStx ←
        if isPfPlace stx then pure stx
        else match stx.getArgs.find? isPfPlace with
          | some s => pure s
          | none =>
              fail s!"expression place missing place syntax at {repr path}: kind={stx.getKind} args={stx.getArgs.size}"
      let placePath := path.push {
        parentTag := "Expr.Place", fieldTag := "place", index := 0
      }
      let placeVisits ← walkPlaceV1 source placePath place placeStx
      pure (#[{ path, tag := "Expr.Place", span }] ++ placeVisits)
  | .constructor _ args => do
      let argStxs := match stx.getArgs.find? fun arg =>
          match arg with
          | .node _ `null _ => true
          | _ => false with
        | some node => sepByChildren node
        | none => #[]
      unless argStxs.size == args.size do
        fail "expression constructor argument count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag := "Expr.Constructor", span }]
      let mut argVisits : Array SpanVisitV1 := #[]
      for ((arg, argStx), idx) in args.zip argStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "Expr.Constructor", fieldTag := "args",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkExprV1 source childPath arg argStx
        argVisits := argVisits ++ subVisits
      pure (visits ++ argVisits)
  | .unary _ operand => do
      let operandStx ← match stx.getArgs with
        | #[_, operand] => pure operand
        | _ => fail "unary expression span mismatch"
      let operandPath := path.push {
        parentTag := "Expr.Unary", fieldTag := "operand", index := 0
      }
      let operandVisits ← walkExprV1 source operandPath operand operandStx
      pure (#[{ path, tag := "Expr.Unary", span }] ++ operandVisits)
  | .binary _ lhs rhs => do
      let (lhsStx, rhsStx) ← match stx.getArgs with
        | #[lhs, _, rhs] => pure (lhs, rhs)
        | _ => fail "binary expression span mismatch"
      let lhsPath := path.push {
        parentTag := "Expr.Binary", fieldTag := "lhs", index := 0
      }
      let rhsPath := path.push {
        parentTag := "Expr.Binary", fieldTag := "rhs", index := 0
      }
      let lhsVisits ← walkExprV1 source lhsPath lhs lhsStx
      let rhsVisits ← walkExprV1 source rhsPath rhs rhsStx
      pure (#[{ path, tag := "Expr.Binary", span }] ++ lhsVisits ++ rhsVisits)
  | .localCall _ args => do
      let argStxs := match stx.getArgs.find? fun arg =>
          match arg with
          | .node _ `null _ => true
          | _ => false with
        | some node => sepByChildren node
        | none => #[]
      unless argStxs.size == args.size do
        fail "local call argument count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag := "Expr.LocalCall", span }]
      let mut argVisits : Array SpanVisitV1 := #[]
      for ((arg, argStx), idx) in args.zip argStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "Expr.LocalCall", fieldTag := "args",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkExprV1 source childPath arg argStx
        argVisits := argVisits ++ subVisits
      pure (visits ++ argVisits)
  | .match_ scrutinee arms => do
      let args := stx.getArgs
      unless args.size == 4 && args[0]!.getAtomVal == "match" &&
          args[2]!.getAtomVal == "with" do
        fail "expression match span mismatch"
      let scrutStx := args[1]!
      let armStxs := sepByChildren args[3]!
      unless armStxs.size == arms.size do
        fail "expression match arm count mismatch"
      let scrutPath := path.push {
        parentTag := "Expr.Match", fieldTag := "scrutinee", index := 0
      }
      let scrutVisits ← walkExprV1 source scrutPath scrutinee scrutStx
      let mut visits : Array SpanVisitV1 := #[{ path, tag := "Expr.Match", span }]
      let mut armVisits : Array SpanVisitV1 := #[]
      for ((arm, armStx), idx) in arms.zip armStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "Expr.Match", fieldTag := "arms",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkExprMatchArmV1 source childPath arm armStx
        armVisits := armVisits ++ subVisits
      pure (visits ++ scrutVisits ++ armVisits)
  | .externalCall ec => do
      let childPath := path.push {
        parentTag := "Expr.ExternalCall", fieldTag := "call", index := 0
      }
      let callVisits ← walkExternalCallV1 source childPath ec stx
      pure (#[{ path, tag := "Expr.ExternalCall", span }] ++ callVisits)

private partial def walkExprMatchArmV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (arm : ExprMatchArmV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  let args := stx.getArgs
  unless args.size == 4 && args[0]!.getAtomVal == "|" &&
      args[2]!.getAtomVal == "=>" do
    fail "expression match arm span mismatch"
  let patternStx := args[1]!
  let valueStx := args[3]!
  let patternPath := path.push {
    parentTag := "ExprMatchArm", fieldTag := "pattern", index := 0
  }
  let valuePath := path.push {
    parentTag := "ExprMatchArm", fieldTag := "value", index := 0
  }
  let patternVisits ← walkPatternV1 source patternPath arm.pattern patternStx
  let valueVisits ← walkExprV1 source valuePath arm.value valueStx
  pure (#[{ path, tag := "ExprMatchArm", span }] ++ patternVisits ++ valueVisits)

private partial def walkPatternV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (pattern : PatternV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  match pattern with
  | .wildcard =>
      pure #[{ path, tag := "Pattern.Wildcard", span }]
  | .bind _ =>
      pure #[{ path, tag := "Pattern.Bind", span }]
  | .literal _ =>
      pure #[{ path, tag := "Pattern.Literal", span }]
  | .constructor _ args => do
      let argStxs := match stx.getArgs.find? fun arg =>
          match arg with
          | .node _ `null _ => true
          | _ => false with
        | some node => sepByChildren node
        | none => #[]
      unless argStxs.size == args.size do
        fail "pattern constructor argument count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag := "Pattern.Constructor", span }]
      let mut argVisits : Array SpanVisitV1 := #[]
      for ((arg, argStx), idx) in args.zip argStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "Pattern.Constructor", fieldTag := "args",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkPatternV1 source childPath arg argStx
        argVisits := argVisits ++ subVisits
      pure (visits ++ argVisits)

private partial def walkPlaceV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (place : PlaceV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  match place with
  | .name _ => do
      let span ← spanOfSyntax source stx
      pure #[{ path, tag := "Place.Name", span }]
  | .field base _ => do
      let span ← spanOfSyntax source stx
      let basePath := path.push {
        parentTag := "Place.Field", fieldTag := "base", index := 0
      }
      let baseVisits ← walkPlaceV1 source basePath base
        (if stx.isIdent then stx else stx.getArgs[0]!)
      pure (#[{ path, tag := "Place.Field", span }] ++ baseVisits)
  | .index base index => do
      let span ← spanOfSyntax source stx
      let basePath := path.push {
        parentTag := "Place.Index", fieldTag := "base", index := 0
      }
      let baseVisits ← walkPlaceV1 source basePath base stx.getArgs[0]!
      let indexPath := path.push {
        parentTag := "Place.Index", fieldTag := "index", index := 0
      }
      let indexVisits ← walkExprV1 source indexPath index stx.getArgs[2]!
      pure (#[{ path, tag := "Place.Index", span }] ++ baseVisits ++ indexVisits)

end

private partial def walkParamV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (param : ParamV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  let typeStx ← match stx.getArgs.find? (isPfType) with
    | some s => pure s
    | none => fail "param missing type"
  let typePath := path.push {
    parentTag := "Param", fieldTag := "type", index := 0
  }
  let typeVisits ← walkTypeV1 source typePath param.type_ typeStx
  pure (#[{ path, tag := "Param", span }] ++ typeVisits)

private partial def walkFieldDeclV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (field : FieldDeclV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  let args := stx.getArgs
  -- Field syntax: name ":" type-atoms...
  let typeAtoms := args.extract 2 args.size
  let typeStx := Syntax.node SourceInfo.none `null typeAtoms
  let typePath := path.push {
    parentTag := "FieldDecl", fieldTag := "type", index := 0
  }
  let typeVisits ← walkTypeV1 source typePath field.type_ typeStx
  pure (#[{ path, tag := "FieldDecl", span }] ++ typeVisits)

private partial def walkEnumVariantV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (variant : EnumVariantV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  let payloadStxs := match stx.getArgs.find? fun arg =>
      match arg with
      | .node _ `null _ => true
      | _ => false with
    | some node => sepByChildren node
    | none => #[]
  unless payloadStxs.size == variant.payloadTypes.size do
    fail "enum variant payload count mismatch"
  let mut visits : Array SpanVisitV1 := #[{ path, tag := "EnumVariant", span }]
  let mut payloadVisits : Array SpanVisitV1 := #[]
  for ((payload, payloadStx), idx) in variant.payloadTypes.zip payloadStxs |>.zipIdx do
    let childPath := path.push {
      parentTag := "EnumVariant", fieldTag := "payloadTypes",
      index := UInt32.ofNat idx
    }
    let subVisits ← walkTypeV1 source childPath payload payloadStx
    payloadVisits := payloadVisits ++ subVisits
  pure (visits ++ payloadVisits)

private partial def walkProgramItemV1
    (source : String) (path : NormalizedSyntacticPathV1)
    (item : ProgramItemV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  let tag := tagOfItem item
  match item with
  | .state declaration => do
      let typeStx ← match stx.getArgs.find? (isPfType) with
        | some typeStx => pure typeStx
        | none => fail "state declaration missing type syntax"
      let typePath := path.push {
        parentTag := "StateDecl", fieldTag := "type", index := 0
      }
      let typeVisits ← walkTypeV1 source typePath declaration.type_ typeStx
      pure (#[{ path, tag, span }] ++ typeVisits)
  | .struct declaration => do
      let memberStxs := childrenAfterAtom stx "where"
      unless memberStxs.size == declaration.fields.size do
        fail "struct field count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag, span }]
      let mut fieldVisits : Array SpanVisitV1 := #[]
      for ((field, fieldStx), idx) in declaration.fields.zip memberStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "StructDecl", fieldTag := "fields",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkFieldDeclV1 source childPath field fieldStx
        fieldVisits := fieldVisits ++ subVisits
      pure (visits ++ fieldVisits)
  | .enum declaration => do
      let memberStxs := childrenAfterAtom stx "where"
      unless memberStxs.size == declaration.variants.size do
        fail "enum variant count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag, span }]
      let mut variantVisits : Array SpanVisitV1 := #[]
      for ((variant, variantStx), idx) in declaration.variants.zip memberStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "EnumDecl", fieldTag := "variants",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkEnumVariantV1 source childPath variant variantStx
        variantVisits := variantVisits ++ subVisits
      pure (visits ++ variantVisits)
  | .const declaration => do
      let args := stx.getArgs
      let typeStx? := args.find? (isPfType)
      let valueStx? := args.find? (isPfExpr)
      let typeStx ← match typeStx? with | some s => pure s | none => fail "const declaration missing type"
      let valueStx ← match valueStx? with | some s => pure s | none => fail "const declaration missing value"
      let typePath := path.push {
        parentTag := "ConstDecl", fieldTag := "type", index := 0
      }
      let valuePath := path.push {
        parentTag := "ConstDecl", fieldTag := "value", index := 0
      }
      let typeVisits ← walkTypeV1 source typePath declaration.type_ typeStx
      let valueVisits ← walkExprV1 source valuePath declaration.value valueStx
      pure (#[{ path, tag, span }] ++ typeVisits ++ valueVisits)
  | .event declaration => do
      let (paramStxs, _) ← callableParamsAndBody stx
      unless paramStxs.size == declaration.params.size do
        fail "event param count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag, span }]
      let mut paramVisits : Array SpanVisitV1 := #[]
      for ((param, paramStx), idx) in declaration.params.zip paramStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "EventDecl", fieldTag := "params",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkParamV1 source childPath param paramStx
        paramVisits := paramVisits ++ subVisits
      pure (visits ++ paramVisits)
  | .error declaration => do
      let (paramStxs, _) ← callableParamsAndBody stx
      unless paramStxs.size == declaration.params.size do
        fail "error param count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag, span }]
      let mut paramVisits : Array SpanVisitV1 := #[]
      for ((param, paramStx), idx) in declaration.params.zip paramStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "ErrorDecl", fieldTag := "params",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkParamV1 source childPath param paramStx
        paramVisits := paramVisits ++ subVisits
      pure (visits ++ paramVisits)
  | .init declaration => do
      let (paramStxs, bodyStxs) ← callableParamsAndBody stx
      unless paramStxs.size == declaration.params.size do
        fail "init param count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag, span }]
      let mut paramVisits : Array SpanVisitV1 := #[]
      for ((param, paramStx), idx) in declaration.params.zip paramStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "InitDecl", fieldTag := "params",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkParamV1 source childPath param paramStx
        paramVisits := paramVisits ++ subVisits
      let bodyPath := path.push {
        parentTag := "InitDecl", fieldTag := "body", index := 0
      }
      let bodyVisits ← walkBlockV1 source bodyPath declaration.body bodyStxs
      pure (visits ++ paramVisits ++ bodyVisits)
  | .entry declaration => do
      let (paramStxs, bodyStxs) ← callableParamsAndBody stx
      let resultStx? := callableResultSyntax? stx
      let resultPath := path.push {
        parentTag := "EntryDecl", fieldTag := "result", index := 0
      }
      let resultVisits ← match declaration.result, resultStx? with
        | .unit, none => do
            let resultSpan ← doAtomSpan source stx
            pure #[{ path := resultPath, tag := "Type.Unit", span := resultSpan }]
        | type_, some typeStx =>
            walkTypeV1 source resultPath type_ typeStx
        | _, _ => fail "entry declaration result mismatch"
      unless paramStxs.size == declaration.params.size do
        fail "entry param count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag, span }]
      let mut paramVisits : Array SpanVisitV1 := #[]
      for ((param, paramStx), idx) in declaration.params.zip paramStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "EntryDecl", fieldTag := "params",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkParamV1 source childPath param paramStx
        paramVisits := paramVisits ++ subVisits
      let bodyPath := path.push {
        parentTag := "EntryDecl", fieldTag := "body", index := 0
      }
      let bodyVisits ← walkBlockV1 source bodyPath declaration.body bodyStxs
      pure (visits ++ paramVisits ++ resultVisits ++ bodyVisits)
  | .view declaration => do
      let (paramStxs, bodyStxs) ← callableParamsAndBody stx
      let resultStx? := callableResultSyntax? stx
      let resultPath := path.push {
        parentTag := "ViewDecl", fieldTag := "result", index := 0
      }
      let resultVisits ← match declaration.result, resultStx? with
        | .unit, none => do
            let resultSpan ← doAtomSpan source stx
            pure #[{ path := resultPath, tag := "Type.Unit", span := resultSpan }]
        | type_, some typeStx =>
            walkTypeV1 source resultPath type_ typeStx
        | _, _ => fail "view declaration result mismatch"
      unless paramStxs.size == declaration.params.size do
        fail "view param count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag, span }]
      let mut paramVisits : Array SpanVisitV1 := #[]
      for ((param, paramStx), idx) in declaration.params.zip paramStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "ViewDecl", fieldTag := "params",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkParamV1 source childPath param paramStx
        paramVisits := paramVisits ++ subVisits
      let bodyPath := path.push {
        parentTag := "ViewDecl", fieldTag := "body", index := 0
      }
      let bodyVisits ← walkBlockV1 source bodyPath declaration.body bodyStxs
      pure (visits ++ paramVisits ++ resultVisits ++ bodyVisits)
  | .fn declaration => do
      let (paramStxs, bodyStxs) ← callableParamsAndBody stx
      let resultStx? := callableResultSyntax? stx
      let resultPath := path.push {
        parentTag := "FnDecl", fieldTag := "result", index := 0
      }
      let resultVisits ← match declaration.result, resultStx? with
        | .unit, none => do
            let resultSpan ← doAtomSpan source stx
            pure #[{ path := resultPath, tag := "Type.Unit", span := resultSpan }]
        | type_, some typeStx =>
            walkTypeV1 source resultPath type_ typeStx
        | _, _ => fail "fn declaration result mismatch"
      unless paramStxs.size == declaration.params.size do
        fail "fn param count mismatch"
      let mut visits : Array SpanVisitV1 := #[{ path, tag, span }]
      let mut paramVisits : Array SpanVisitV1 := #[]
      for ((param, paramStx), idx) in declaration.params.zip paramStxs |>.zipIdx do
        let childPath := path.push {
          parentTag := "FnDecl", fieldTag := "params",
          index := UInt32.ofNat idx
        }
        let subVisits ← walkParamV1 source childPath param paramStx
        paramVisits := paramVisits ++ subVisits
      let bodyPath := path.push {
        parentTag := "FnDecl", fieldTag := "body", index := 0
      }
      let bodyVisits ← walkBlockV1 source bodyPath declaration.body bodyStxs
      pure (visits ++ paramVisits ++ resultVisits ++ bodyVisits)
  | .invariant declaration => do
      let predStx ← match stx.getArgs.find? (isPfExpr) with
        | some s => pure s
        | none => fail "invariant declaration missing predicate"
      let predPath := path.push {
        parentTag := "InvariantDecl", fieldTag := "predicate", index := 0
      }
      let predVisits ← walkExprV1 source predPath declaration.predicate predStx
      pure (#[{ path, tag, span }] ++ predVisits)
  | .extensionReq _ =>
      pure #[{ path, tag, span }]
  | .proof _ =>
      pure #[{ path, tag, span }]

private partial def walkProgramV1
    (source : String) (prog : ProgramV1) (stx : Syntax) :
    Except String (Array SpanVisitV1) := do
  let span ← spanOfSyntax source stx
  let itemStxs := childrenAfterAtom stx "where"
  unless itemStxs.size == prog.items.size do
    fail s!"program item count mismatch: {itemStxs.size} syntax items vs {prog.items.size} program items"
  let mut visits : Array SpanVisitV1 := #[{ path := #[], tag := "Program", span }]
  let mut itemVisits : Array SpanVisitV1 := #[]
  for ((item, itemStx), idx) in prog.items.zip itemStxs |>.zipIdx do
    let childPath := #[{
      parentTag := "Program", fieldTag := "items",
      index := UInt32.ofNat idx
    }]
    let subVisits ← walkProgramItemV1 source childPath item itemStx
    itemVisits := itemVisits ++ subVisits
  pure (visits ++ itemVisits)

/--
Join every node-bearing ProgramV1 constructor in canonical preorder to the
byte span of the original parser syntax that produced it.
-/
def spanJoinV1
    (source : String) (programStx : Syntax) (prog : ProgramV1) :
    Except String (Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  let expected ← canonicalNodeVisitsV1 prog
  let visits ← walkProgramV1 source prog programStx
  for ((visit, expectedVisit), i) in visits.zip expected |>.zipIdx do
    unless visit.tag == expectedVisit.constructorTag && visit.path == expectedVisit.path do
      fail s!"span join tag/path mismatch at index {i}: actual {visit.tag} {repr visit.path} vs expected {expectedVisit.constructorTag} {repr expectedVisit.path}"
  unless visits.size == expected.size do
    fail s!"span join count mismatch: {visits.size} spans vs {expected.size} canonical visits"
  pure (visits.map fun visit => (visit.path, visit.span))

end ProofForgeV2.Source.SpanJoinV1
