import Lean
import ProofForgeV2.Core.Source
import Std.Data.HashSet

open Lean Parser Command
open ProofForgeV2

namespace ProofForgeV2.Language

declare_syntax_cat pfType
syntax ident : pfType

declare_syntax_cat pfParam
syntax ident " : " pfType : pfParam
syntax "public " ident " : " pfType : pfParam
syntax "private " ident " : " pfType : pfParam
syntax "commitment " ident " : " pfType : pfParam

declare_syntax_cat pfExpr
syntax num : pfExpr
syntax ident : pfExpr
syntax:65 pfExpr:65 " + " pfExpr:66 : pfExpr

declare_syntax_cat pfStmt
syntax ident " := " pfExpr : pfStmt
syntax "return " pfExpr : pfStmt
syntax "call " str : pfStmt

declare_syntax_cat pfItem
syntax "state " ident " : " pfType : pfItem
syntax "init" "(" sepBy(pfParam, ", ") ")" " do" ppLine ppIndent(pfStmt*) : pfItem
syntax "entry " ident "(" sepBy(pfParam, ", ") ")" " : " pfType " do" ppLine ppIndent(pfStmt*) : pfItem
syntax "view " ident "(" sepBy(pfParam, ", ") ")" " : " pfType " do" ppLine ppIndent(pfStmt*) : pfItem

syntax (name := programDecl) "program " ident " where" ppLine ppIndent(pfItem*) : command

/-- Maximum nodes in one portable decoder subtree, including its root. -/
def maxSyntaxNodes : Nat := 100000

/-- Maximum root-inclusive depth in one portable decoder subtree. -/
def maxSyntaxNesting : Nat := 256

/-- Count name components iteratively, returning `none` before exceeding `limit`. -/
def boundedNamePartCount (limit : Nat) (name : Name) : Option Nat := Id.run do
  let mut current := name
  let mut count := 0
  while current != .anonymous do
    if count >= limit then
      return none
    count := count + 1
    current := current.getPrefix
  return some count

/-- Iterative post-parser preflight over one portable Syntax subtree. This runs
before the recursive DSL decoder or macro expander; it does not protect Lean's
parser itself or impose an aggregate limit across multiple programs. -/
def preflightSyntax (root : Syntax) : CompileResult Unit := do
  let mut pending : Array (Syntax × Nat) := #[(root, 1)]
  let mut discovered := 1
  while !pending.isEmpty do
    let (current, nesting) := pending.back!
    pending := pending.pop
    if nesting > maxSyntaxNesting then
      throw <| .resourceBound s!"portable syntax exceeds nesting limit {maxSyntaxNesting}"
    match current with
    | .ident _ _ name _ =>
        if (boundedNamePartCount maxSyntaxNesting name).isNone then
          throw <| .resourceBound
            s!"portable identifier nesting exceeds limit {maxSyntaxNesting}"
    | _ => pure ()
    for child in current.getArgs do
      let childNesting := nesting + 1
      if childNesting > maxSyntaxNesting then
        throw <| .resourceBound s!"portable syntax exceeds nesting limit {maxSyntaxNesting}"
      if discovered >= maxSyntaxNodes then
        throw <| .resourceBound s!"portable syntax exceeds node limit {maxSyntaxNodes}"
      discovered := discovered + 1
      pending := pending.push (child, childNesting)

private def preflightForDecoder (stx : Syntax) : Except String Unit :=
  (preflightSyntax stx).mapError CompileError.render

/-- Decode the registered Lean syntax tree into the target-neutral source AST.
This function is also used by the non-elaborating CLI loader. -/
private def rawIdentifierText? : Syntax → Option String
  | .ident _ rawValue _ _ => some rawValue.toString
  | _ => none

private def decodeTypeUnchecked : Syntax → Except String ProofForgeV2.Source.ValueType
  | `(pfType| $name:ident) =>
      match rawIdentifierText? name with
      | some "UInt64" => .ok .u64
      | some "Bool" => .ok .bool
      | _ => .error "unsupported portable type"
  | _ => .error "unsupported portable type"

def decodeType (stx : Syntax) : Except String ProofForgeV2.Source.ValueType := do
  preflightForDecoder stx
  decodeTypeUnchecked stx

private def decodeParamUnchecked : Syntax → Except String ProofForgeV2.Source.Param
  | `(pfParam| $name:ident : $type:pfType) => do
      return { name := name.getId.toString, type := ← decodeTypeUnchecked type }
  | `(pfParam| public $name:ident : $type:pfType) => do
      return {
        name := name.getId.toString
        type := ← decodeTypeUnchecked type
        visibility := .verifierVisible
      }
  | `(pfParam| private $name:ident : $type:pfType) => do
      return {
        name := name.getId.toString
        type := ← decodeTypeUnchecked type
        visibility := .proverWitness
      }
  | `(pfParam| commitment $name:ident : $type:pfType) => do
      return {
        name := name.getId.toString
        type := ← decodeTypeUnchecked type
        visibility := .commitmentOnly
      }
  | _ => .error "unsupported portable parameter"

def decodeParam (stx : Syntax) : Except String ProofForgeV2.Source.Param := do
  preflightForDecoder stx
  decodeParamUnchecked stx

private partial def decodeExprUnchecked : Syntax → Except String ProofForgeV2.Source.Expr
  | `(pfExpr| $value:num) =>
      let number := value.getNat
      if number > 18446744073709551615 then
        .error s!"UInt64 literal is out of range: {number}"
      else
        .ok <| .literal (UInt64.ofNat number)
  | `(pfExpr| $name:ident) => .ok <| .variable name.getId.toString
  | `(pfExpr| $lhs:pfExpr + $rhs:pfExpr) => do
      return .checkedAdd (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | _ => .error "unsupported portable expression"

def decodeExpr (stx : Syntax) : Except String ProofForgeV2.Source.Expr := do
  preflightForDecoder stx
  decodeExprUnchecked stx

private def decodeStatementUnchecked : Syntax → Except String ProofForgeV2.Source.Statement
  | `(pfStmt| $name:ident := $value:pfExpr) => do
      return .assign name.getId.toString (← decodeExprUnchecked value)
  | `(pfStmt| return $value:pfExpr) => do
      return .returnValue (← decodeExprUnchecked value)
  | `(pfStmt| call $callee:str) => .ok <| .synchronousCall callee.getString
  | _ => .error "unsupported portable statement"

def decodeStatement (stx : Syntax) : Except String ProofForgeV2.Source.Statement := do
  preflightForDecoder stx
  decodeStatementUnchecked stx

private def decodeParams (params : Array Syntax) :
    Except String (Array ProofForgeV2.Source.Param) :=
  params.mapM decodeParamUnchecked

private def decodeStatementsUnchecked (statements : Array Syntax) :
    Except String (Array ProofForgeV2.Source.Statement) :=
  statements.mapM decodeStatementUnchecked

private def decodeItemUnchecked : Syntax → Except String ProofForgeV2.Source.Item
  | `(pfItem| state $name:ident : $type:pfType) => do
      return .stateDecl { name := name.getId.toString, type := ← decodeTypeUnchecked type }
  | `(pfItem| init ($params:pfParam,*) do $statements:pfStmt*) => do
      return .initializer {
        params := ← decodeParams params
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| entry $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := name.getId.toString
        params := ← decodeParams params
        result := ← decodeTypeUnchecked type
        mode := .mutate
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| view $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := name.getId.toString
        params := ← decodeParams params
        result := ← decodeTypeUnchecked type
        mode := .view
        body := ← decodeStatementsUnchecked statements
      }
  | _ => .error "unsupported portable program item"

def decodeItem (stx : Syntax) : Except String ProofForgeV2.Source.Item := do
  preflightForDecoder stx
  decodeItemUnchecked stx

private def hasDuplicate (values : Array String) : Bool := Id.run do
  let mut seen := Std.HashSet.emptyWithCapacity values.size
  for value in values do
    let (alreadyPresent, updated) := seen.containsThenInsert value
    if alreadyPresent then
      return true
    seen := updated
  return false

/-- Validate declaration-scope invariants shared by the CLI Loader and Lean
command elaborator. Error order is part of the alpha frontend contract. -/
def validateDecodedProgram (sourceProgram : ProofForgeV2.Source.Program) : CompileResult Unit := do
  if sourceProgram.entries.isEmpty then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' must declare at least one entry or view"
  if hasDuplicate (sourceProgram.state.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate state declarations"
  if hasDuplicate (sourceProgram.entries.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate entry declarations"
  match sourceProgram.initializer with
  | some initializer =>
      if hasDuplicate (initializer.params.map (·.name)) then
        throw <| .invalidProgram "initializer contains duplicate parameters"
  | none => pure ()
  for sourceEntry in sourceProgram.entries do
    if hasDuplicate (sourceEntry.params.map (·.name)) then
      throw <| .invalidProgram s!"entry '{sourceEntry.name}' contains duplicate parameters"

private def decodeProgramCommandUnchecked (currentNamespace : Name) : Syntax →
    Except String ProofForgeV2.Source.Program
  | `(program $name:ident where $items:pfItem*) => do
      let shortName := name.getId.toString
      let qualifiedName := (currentNamespace ++ name.getId).toString
      let decodedItems ← items.mapM decodeItemUnchecked
      let initializerCount : Nat := decodedItems.foldl (fun count item =>
        match item with | .initializer .. => count + 1 | _ => count) 0
      if initializerCount > 1 then
        throw "program may declare at most one initializer"
      return ProofForgeV2.Source.Program.buildQualified
        qualifiedName shortName decodedItems
  | _ => .error "expected a program declaration"

/-- Bound the fully qualified identity before recursive `Name.toString`. -/
def preflightProgramIdentity (currentNamespace programName : Name) :
    CompileResult Unit := do
  let namespaceParts ←
    match boundedNamePartCount maxSyntaxNesting currentNamespace with
    | some count => .ok count
    | none => .error (.resourceBound
        s!"portable program identity exceeds nesting limit {maxSyntaxNesting}")
  match boundedNamePartCount (maxSyntaxNesting - namespaceParts) programName with
  | some _ => .ok ()
  | none => .error (.resourceBound
      s!"portable program identity exceeds nesting limit {maxSyntaxNesting}")

inductive ProgramNamespace where
  | bounded (name : Name)
  | overLimit
  deriving Inhabited

def decodeProgramCommandChecked (currentNamespace : ProgramNamespace) (stx : Syntax) :
    CompileResult ProofForgeV2.Source.Program := do
  preflightSyntax stx
  match stx with
  | `(program $name:ident where $_items:pfItem*) =>
      let namespaceName ← match currentNamespace with
        | .bounded namespaceName => .ok namespaceName
        | .overLimit => .error (.resourceBound
            s!"portable program identity exceeds nesting limit {maxSyntaxNesting}")
      preflightProgramIdentity namespaceName name.getId
      match decodeProgramCommandUnchecked namespaceName stx with
      | .ok contractProgram => do
          validateDecodedProgram contractProgram
          return contractProgram
      | .error message => .error <| .invalidProgram message
  | _ => .error <| .invalidProgram "expected a program declaration"

def decodeProgramCommand (currentNamespace : Name) (stx : Syntax) :
    Except String ProofForgeV2.Source.Program :=
  (decodeProgramCommandChecked (.bounded currentNamespace) stx).mapError CompileError.render

private def quoteValueType : ProofForgeV2.Source.ValueType → MacroM (TSyntax `term)
  | .u64 => `(ProofForgeV2.Source.ValueType.u64)
  | .bool => `(ProofForgeV2.Source.ValueType.bool)
  | .field => `(ProofForgeV2.Source.ValueType.field)

private def quoteVisibility : ProofForgeV2.Source.Visibility → MacroM (TSyntax `term)
  | .verifierVisible => `(ProofForgeV2.Source.Visibility.verifierVisible)
  | .proverWitness => `(ProofForgeV2.Source.Visibility.proverWitness)
  | .commitmentOnly => `(ProofForgeV2.Source.Visibility.commitmentOnly)

private def quoteParam (param : ProofForgeV2.Source.Param) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit param.name
  let typeExpr ← quoteValueType param.type
  let visibility ← quoteVisibility param.visibility
  `(ProofForgeV2.Source.Param.mk $name $typeExpr $visibility)

private def quoteParams (params : Array ProofForgeV2.Source.Param) : MacroM (TSyntax `term) := do
  let values ← params.mapM quoteParam
  `(#[$[$values],*])

private def quoteStateDecl (sourceState : ProofForgeV2.Source.StateDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceState.name
  let typeExpr ← quoteValueType sourceState.type
  `(ProofForgeV2.Source.StateDecl.mk $name $typeExpr)

private def quoteState (states : Array ProofForgeV2.Source.StateDecl) : MacroM (TSyntax `term) := do
  let values ← states.mapM quoteStateDecl
  `(#[$[$values],*])

private partial def quoteExpr : ProofForgeV2.Source.Expr → MacroM (TSyntax `term)
  | .literal value =>
      let value := Syntax.mkNumLit (toString value.toNat)
      `(ProofForgeV2.Source.Expr.literal (UInt64.ofNat $value))
  | .variable value =>
      let value := Syntax.mkStrLit value
      `(ProofForgeV2.Source.Expr.variable $value)
  | .state value =>
      let value := Syntax.mkStrLit value
      `(ProofForgeV2.Source.Expr.state $value)
  | .checkedAdd lhs rhs => do
      let lhs ← quoteExpr lhs
      let rhs ← quoteExpr rhs
      `(ProofForgeV2.Source.Expr.checkedAdd $lhs $rhs)

private def quoteStatement : ProofForgeV2.Source.Statement → MacroM (TSyntax `term)
  | .assign stateName value => do
      let stateName := Syntax.mkStrLit stateName
      let value ← quoteExpr value
      `(ProofForgeV2.Source.Statement.assign $stateName $value)
  | .returnValue value => do
      let value ← quoteExpr value
      `(ProofForgeV2.Source.Statement.returnValue $value)
  | .synchronousCall callee =>
      let callee := Syntax.mkStrLit callee
      `(ProofForgeV2.Source.Statement.synchronousCall $callee)

private def quoteStatements (statements : Array ProofForgeV2.Source.Statement) :
    MacroM (TSyntax `term) := do
  let values ← statements.mapM quoteStatement
  `(#[$[$values],*])

private def quoteInitializer (initializer : ProofForgeV2.Source.Initializer) :
    MacroM (TSyntax `term) := do
  let params ← quoteParams initializer.params
  let body ← quoteStatements initializer.body
  `(ProofForgeV2.Source.Initializer.mk $params $body)

private def quoteInitializer? : Option ProofForgeV2.Source.Initializer → MacroM (TSyntax `term)
  | none => `(Option.none)
  | some initializer => do
      let initializer ← quoteInitializer initializer
      `(Option.some $initializer)

private def quoteEntryMode : ProofForgeV2.Source.EntryMode → MacroM (TSyntax `term)
  | .mutate => `(ProofForgeV2.Source.EntryMode.mutate)
  | .view => `(ProofForgeV2.Source.EntryMode.view)

private def quoteEntry (sourceEntry : ProofForgeV2.Source.Entry) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceEntry.name
  let params ← quoteParams sourceEntry.params
  let result ← quoteValueType sourceEntry.result
  let mode ← quoteEntryMode sourceEntry.mode
  let body ← quoteStatements sourceEntry.body
  `(ProofForgeV2.Source.Entry.mk $name $params $result $mode $body)

private def quoteEntries (entries : Array ProofForgeV2.Source.Entry) : MacroM (TSyntax `term) := do
  let values ← entries.mapM quoteEntry
  `(#[$[$values],*])

/-- Quote an already decoded source value without reinterpreting raw grammar. -/
private def quoteProgram (sourceProgram : ProofForgeV2.Source.Program) : MacroM (TSyntax `term) := do
  let qualifiedName := Syntax.mkStrLit sourceProgram.qualifiedName
  let name := Syntax.mkStrLit sourceProgram.name
  let stateExpr ← quoteState sourceProgram.state
  let initializer ← quoteInitializer? sourceProgram.initializer
  let entries ← quoteEntries sourceProgram.entries
  `(ProofForgeV2.Source.Program.mk $qualifiedName $name $stateExpr $initializer $entries)

elab_rules : command
  | `(program $name:ident where $items:pfItem*) => do
      let currentNamespace ← getCurrNamespace
      let commandStx ← `(program $name:ident where $items:pfItem*)
      let decoded ← match decodeProgramCommand currentNamespace commandStx with
      | .error message => throwError message
      | .ok decoded => pure decoded
      let programExpr ← Lean.Elab.liftMacroM <| quoteProgram decoded
      let expanded ← `(@[proof_forge_program] def $name : ProofForgeV2.Source.Program :=
          $programExpr)
      Lean.Elab.Command.elabCommand expanded

initialize Lean.registerBuiltinAttribute {
  name := `proof_forge_program
  descr := "marks a declaration generated by the ProofForge V2 program DSL"
  add := fun _ _ _ => pure ()
}

end ProofForgeV2.Language
