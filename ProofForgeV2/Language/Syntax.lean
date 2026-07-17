import Lean
import ProofForgeV2.Core.Source
import Std.Data.HashSet

open Lean Parser Command
open ProofForgeV2

namespace ProofForgeV2.Language

declare_syntax_cat pfType
/-- Parse the one-identifier primitive form or a same-line two-identifier field
form without allowing the next program item to become part of the type. -/
@[pfType_parser] def portableType := leading_parser
  withPosition (ident >> optional (checkLineEq >> ident))

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

declare_syntax_cat pfAggregateMember
@[pfAggregateMember_parser] def aggregateField := leading_parser
  withPosition (ident >> " : " >> ident >>
    (checkLinebreakBefore <|> checkLineEq >> ident >> checkLinebreakBefore))
syntax "| " ident linebreak : pfAggregateMember
syntax "| " ident "(" sepBy(pfType, ", ") ")" linebreak : pfAggregateMember

declare_syntax_cat pfItem
@[pfItem_parser default+1] def bareErrorDecl := leading_parser
  withPosition (nonReservedSymbol "error " (includeIdent := true) >> checkLineEq >> ident >>
    checkLinebreakBefore)
syntax "state " ident " : " pfType : pfItem
syntax "state " "public " ident " : " pfType : pfItem
syntax "state " "private " ident " : " pfType : pfItem
syntax "state " "commitment " ident " : " pfType : pfItem
syntax ident ident "(" sepBy(pfParam, ", ") ")" : pfItem
syntax ident ident " where" ppLine manyIndent(pfAggregateMember) : pfItem
@[pfItem_parser default+1] def constDecl := leading_parser
  withPosition (nonReservedSymbol "const " (includeIdent := true) >> checkLineEq >> ident >>
    " : " >> categoryParser `pfType 0 >> " := " >> categoryParser `pfExpr 0)
@[pfItem_parser default+1] def invariantDecl := leading_parser
  withPosition (nonReservedSymbol "invariant " (includeIdent := true) >> checkLineEq >> ident >>
    " : " >> categoryParser `pfExpr 0)
/-- Preserve invalid escaped/unknown contextual shapes long enough for the
shared decoder to emit the stable unsupported-item diagnostic. -/
@[pfItem_parser low] def unsupportedConstLikeDecl := leading_parser
  withPosition (ident >> checkLineEq >> ident >> " : " >> categoryParser `pfType 0 >>
    " := " >> categoryParser `pfExpr 0)
@[pfItem_parser low] def unsupportedInvariantLikeDecl := leading_parser
  withPosition (ident >> checkLineEq >> ident >> " : " >> categoryParser `pfExpr 0 >>
    checkLinebreakBefore)
@[pfItem_parser low] def unsupportedBareItemDecl := leading_parser
  withPosition (ident >> checkLineEq >> ident >> checkLinebreakBefore)
syntax ident ident "(" sepBy(pfParam, ", ") ")" " : " pfType " do" ppLine manyIndent(pfStmt) : pfItem
syntax "init" "(" sepBy(pfParam, ", ") ")" " do" ppLine manyIndent(pfStmt) : pfItem
syntax "entry " ident "(" sepBy(pfParam, ", ") ")" " : " pfType " do" ppLine manyIndent(pfStmt) : pfItem
syntax "view " ident "(" sepBy(pfParam, ", ") ")" " : " pfType " do" ppLine manyIndent(pfStmt) : pfItem

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

private def decodeIdentifier (stx : Syntax) : Except String String :=
  let name := stx.getId.toString
  if name == "struct" || name == "enum" || name == "const" || name == "event" ||
      name == "error" || name == "fn" || name == "invariant" then
    .error s!"reserved portable identifier '{name}'"
  else
    .ok name

private def decodeTypeIdentifiers (first : Syntax) (second : Option Syntax) :
    Except String ProofForgeV2.Source.ValueType :=
  match rawIdentifierText? first, second.bind rawIdentifierText? with
  | some "UInt64", none => .ok .u64
  | some "Bool", none => .ok .bool
  | some "Field", some "bn254_fr" => .ok .field
  | _, _ => .error "unsupported portable type"

private partial def collectTypeIdentifierSyntax (stx : Syntax) : Array Syntax :=
  if stx.isIdent then #[stx]
  else stx.getArgs.flatMap collectTypeIdentifierSyntax

private def decodeTypeUnchecked (stx : Syntax) : Except String ProofForgeV2.Source.ValueType :=
  if !stx.isOfKind ``portableType then
    .error "unsupported portable type"
  else
    match collectTypeIdentifierSyntax stx with
    | #[name] => decodeTypeIdentifiers name none
    | #[constructor, fieldId] => decodeTypeIdentifiers constructor (some fieldId)
    | _ => .error "unsupported portable type"

def decodeType (stx : Syntax) : Except String ProofForgeV2.Source.ValueType := do
  preflightForDecoder stx
  decodeTypeUnchecked stx

private def decodeParamUnchecked : Syntax → Except String ProofForgeV2.Source.Param
  | `(pfParam| $name:ident : $type:pfType) => do
      return { name := ← decodeIdentifier name, type := ← decodeTypeUnchecked type }
  | `(pfParam| public $name:ident : $type:pfType) => do
      return {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .verifierVisible
      }
  | `(pfParam| private $name:ident : $type:pfType) => do
      return {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .proverWitness
      }
  | `(pfParam| commitment $name:ident : $type:pfType) => do
      return {
        name := ← decodeIdentifier name
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
  | `(pfExpr| $name:ident) => do
      return .variable (← decodeIdentifier name)
  | `(pfExpr| $lhs:pfExpr + $rhs:pfExpr) => do
      return .checkedAdd (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | _ => .error "unsupported portable expression"

def decodeExpr (stx : Syntax) : Except String ProofForgeV2.Source.Expr := do
  preflightForDecoder stx
  decodeExprUnchecked stx

private def decodeStatementUnchecked : Syntax → Except String ProofForgeV2.Source.Statement
  | `(pfStmt| $name:ident := $value:pfExpr) => do
      return .assign (← decodeIdentifier name) (← decodeExprUnchecked value)
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

private partial def collectIdentifierSyntax (stx : Syntax) : Array Syntax :=
  if stx.isIdent then #[stx]
  else stx.getArgs.flatMap collectIdentifierSyntax

private def decodeStructFieldUnchecked (stx : Syntax) :
    Except String ProofForgeV2.Source.FieldDecl := do
  unless stx.isOfKind ``aggregateField do
    throw "unsupported portable struct field"
  match collectIdentifierSyntax stx with
  | #[name, typeName] =>
      return {
        name := ← decodeIdentifier name
        type := ← decodeTypeIdentifiers typeName none
      }
  | #[name, constructor, fieldId] =>
      return {
        name := ← decodeIdentifier name
        type := ← decodeTypeIdentifiers constructor (some fieldId)
      }
  | _ => throw "unsupported portable struct field"

private def decodeEnumVariantUnchecked : Syntax → Except String ProofForgeV2.Source.EnumVariant
  | `(pfAggregateMember| | $name:ident
      ) => do
      return { name := ← decodeIdentifier name, payloadTypes := #[] }
  | `(pfAggregateMember| | $name:ident ($payloadTypes:pfType,*)
      ) => do
      let name ← decodeIdentifier name
      let payloadTypes := payloadTypes.getElems
      if payloadTypes.isEmpty then
        throw s!"enum variant '{name}' payload must contain at least one type"
      return { name, payloadTypes := ← payloadTypes.mapM decodeTypeUnchecked }
  | _ => .error "unsupported portable enum variant"

private def decodeItemUnchecked : Syntax → Except String ProofForgeV2.Source.Item
  | `(pfItem| state $name:ident : $type:pfType) => do
      return .stateDecl { name := ← decodeIdentifier name, type := ← decodeTypeUnchecked type }
  | `(pfItem| state public $name:ident : $type:pfType) => do
      return .stateDecl {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .verifierVisible
      }
  | `(pfItem| state private $name:ident : $type:pfType) => do
      return .stateDecl {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .proverWitness
      }
  | `(pfItem| state commitment $name:ident : $type:pfType) => do
      return .stateDecl {
        name := ← decodeIdentifier name
        type := ← decodeTypeUnchecked type
        visibility := .commitmentOnly
      }
  | `(constDecl| const $name:ident : $type:pfType := $value:pfExpr) => do
      let name ← decodeIdentifier name
      let type ← decodeTypeUnchecked type
      let value ← decodeExprUnchecked value
      return .constDecl { name, type, value }
  | `(unsupportedConstLikeDecl| $_kind:ident $_name:ident : $_type:pfType :=
        $_value:pfExpr) =>
      .error "unsupported portable program item"
  | `(invariantDecl| invariant $name:ident : $predicate:pfExpr) => do
      let name ← decodeIdentifier name
      let predicate ← decodeExprUnchecked predicate
      return .invariantDecl { name, predicate }
  | `(unsupportedInvariantLikeDecl| $_kind:ident $_name:ident : $_predicate:pfExpr
      ) =>
      .error "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*) : $result:pfType do
        $body:pfStmt*) =>
      match rawIdentifierText? kind with
      | some "fn" => do
          let name ← decodeIdentifier name
          let params ← decodeParams params.getElems
          let result ← decodeTypeUnchecked result
          let body ← decodeStatementsUnchecked body
          return .fnDecl { name, params, result, body }
      | _ => .error "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident where $members:pfAggregateMember*) =>
      match rawIdentifierText? kind with
      | some "struct" => do
          return .structDecl {
            name := ← decodeIdentifier name
            fields := ← members.mapM decodeStructFieldUnchecked
          }
      | some "enum" => do
          return .enumDecl {
            name := ← decodeIdentifier name
            variants := ← members.mapM decodeEnumVariantUnchecked
          }
      | _ => .error "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*)) =>
      match rawIdentifierText? kind with
      | some "event" => do
          return .eventDecl {
            name := ← decodeIdentifier name
            params := ← decodeParams params
          }
      | some "error" => do
          return .errorDecl {
            name := ← decodeIdentifier name
            params := ← decodeParams params
          }
      | _ => .error "unsupported portable program item"
  | `(bareErrorDecl| error $name:ident
      ) =>
      return .errorDecl { name := ← decodeIdentifier name, params := #[] }
  | `(unsupportedBareItemDecl| $_kind:ident $_name:ident
      ) =>
      .error "unsupported portable program item"
  | `(pfItem| init ($params:pfParam,*) do $statements:pfStmt*) => do
      return .initializer {
        params := ← decodeParams params
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| entry $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := ← decodeIdentifier name
        params := ← decodeParams params
        result := ← decodeTypeUnchecked type
        mode := .mutate
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| view $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := ← decodeIdentifier name
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
  if hasDuplicate (sourceProgram.events.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate event declarations"
  if hasDuplicate (sourceProgram.errors.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate error declarations"
  if hasDuplicate (sourceProgram.structs.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate struct declarations"
  if hasDuplicate (sourceProgram.enums.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate enum declarations"
  if hasDuplicate (sourceProgram.consts.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate const declarations"
  if hasDuplicate (sourceProgram.functions.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate fn declarations"
  if hasDuplicate (sourceProgram.invariants.map (·.name)) then
    throw <| .invalidProgram
      s!"program '{sourceProgram.qualifiedName}' contains duplicate invariant declarations"
  match sourceProgram.initializer with
  | some initializer =>
      if hasDuplicate (initializer.params.map (·.name)) then
        throw <| .invalidProgram "initializer contains duplicate parameters"
  | none => pure ()
  for sourceStruct in sourceProgram.structs do
    if sourceStruct.fields.isEmpty then
      throw <| .invalidProgram s!"struct '{sourceStruct.name}' must declare at least one field"
    if hasDuplicate (sourceStruct.fields.map (·.name)) then
      throw <| .invalidProgram s!"struct '{sourceStruct.name}' contains duplicate fields"
  for sourceEnum in sourceProgram.enums do
    if sourceEnum.variants.isEmpty then
      throw <| .invalidProgram s!"enum '{sourceEnum.name}' must declare at least one variant"
    if hasDuplicate (sourceEnum.variants.map (·.name)) then
      throw <| .invalidProgram s!"enum '{sourceEnum.name}' contains duplicate variants"
  for sourceEvent in sourceProgram.events do
    if hasDuplicate (sourceEvent.params.map (·.name)) then
      throw <| .invalidProgram s!"event '{sourceEvent.name}' contains duplicate parameters"
  for sourceError in sourceProgram.errors do
    if hasDuplicate (sourceError.params.map (·.name)) then
      throw <| .invalidProgram s!"error '{sourceError.name}' contains duplicate parameters"
  for sourceEntry in sourceProgram.entries do
    if hasDuplicate (sourceEntry.params.map (·.name)) then
      throw <| .invalidProgram s!"entry '{sourceEntry.name}' contains duplicate parameters"
  for sourceFn in sourceProgram.functions do
    if hasDuplicate (sourceFn.params.map (·.name)) then
      throw <| .invalidProgram s!"fn '{sourceFn.name}' contains duplicate parameters"
    if sourceFn.body.isEmpty then
      throw <| .invalidProgram s!"fn '{sourceFn.name}' must declare at least one statement"

private def decodeProgramCommandUnchecked (currentNamespace : Name) : Syntax →
    Except String ProofForgeV2.Source.Program
  | `(program $name:ident where $items:pfItem*) => do
      let shortName ← decodeIdentifier name
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
  let visibility ← quoteVisibility sourceState.visibility
  `(ProofForgeV2.Source.StateDecl.mk $name $typeExpr $visibility)

private def quoteState (states : Array ProofForgeV2.Source.StateDecl) : MacroM (TSyntax `term) := do
  let values ← states.mapM quoteStateDecl
  `(#[$[$values],*])

private def quoteFieldDecl (field : ProofForgeV2.Source.FieldDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit field.name
  let typeExpr ← quoteValueType field.type
  `(ProofForgeV2.Source.FieldDecl.mk $name $typeExpr)

private def quoteStructDecl (sourceStruct : ProofForgeV2.Source.StructDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceStruct.name
  let fields ← sourceStruct.fields.mapM quoteFieldDecl
  `(ProofForgeV2.Source.StructDecl.mk $name #[$[$fields],*])

private def quoteStructs (structs : Array ProofForgeV2.Source.StructDecl) : MacroM (TSyntax `term) := do
  let values ← structs.mapM quoteStructDecl
  `(#[$[$values],*])

private def quoteEnumVariant (variant : ProofForgeV2.Source.EnumVariant) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit variant.name
  let payloadTypes ← variant.payloadTypes.mapM quoteValueType
  `(ProofForgeV2.Source.EnumVariant.mk $name #[$[$payloadTypes],*])

private def quoteEnumDecl (sourceEnum : ProofForgeV2.Source.EnumDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceEnum.name
  let variants ← sourceEnum.variants.mapM quoteEnumVariant
  `(ProofForgeV2.Source.EnumDecl.mk $name #[$[$variants],*])

private def quoteEnums (enums : Array ProofForgeV2.Source.EnumDecl) : MacroM (TSyntax `term) := do
  let values ← enums.mapM quoteEnumDecl
  `(#[$[$values],*])

private def quoteEventDecl (sourceEvent : ProofForgeV2.Source.EventDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceEvent.name
  let params ← quoteParams sourceEvent.params
  `(ProofForgeV2.Source.EventDecl.mk $name $params)

private def quoteEvents (events : Array ProofForgeV2.Source.EventDecl) : MacroM (TSyntax `term) := do
  let values ← events.mapM quoteEventDecl
  `(#[$[$values],*])

private def quoteErrorDecl (sourceError : ProofForgeV2.Source.ErrorDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceError.name
  let params ← quoteParams sourceError.params
  `(ProofForgeV2.Source.ErrorDecl.mk $name $params)

private def quoteErrors (errors : Array ProofForgeV2.Source.ErrorDecl) : MacroM (TSyntax `term) := do
  let values ← errors.mapM quoteErrorDecl
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

private def quoteConstDecl (sourceConst : ProofForgeV2.Source.ConstDecl) :
    MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceConst.name
  let typeExpr ← quoteValueType sourceConst.type
  let value ← quoteExpr sourceConst.value
  `(ProofForgeV2.Source.ConstDecl.mk $name $typeExpr $value)

private def quoteConsts (consts : Array ProofForgeV2.Source.ConstDecl) : MacroM (TSyntax `term) := do
  let values ← consts.mapM quoteConstDecl
  `(#[$[$values],*])

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

private def quoteFnDecl (sourceFn : ProofForgeV2.Source.FnDecl) : MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceFn.name
  let params ← quoteParams sourceFn.params
  let result ← quoteValueType sourceFn.result
  let body ← quoteStatements sourceFn.body
  `(ProofForgeV2.Source.FnDecl.mk $name $params $result $body)

private def quoteFunctions (functions : Array ProofForgeV2.Source.FnDecl) :
    MacroM (TSyntax `term) := do
  let values ← functions.mapM quoteFnDecl
  `(#[$[$values],*])

private def quoteInvariantDecl (sourceInvariant : ProofForgeV2.Source.InvariantDecl) :
    MacroM (TSyntax `term) := do
  let name := Syntax.mkStrLit sourceInvariant.name
  let predicate ← quoteExpr sourceInvariant.predicate
  `(ProofForgeV2.Source.InvariantDecl.mk $name $predicate)

private def quoteInvariants (invariants : Array ProofForgeV2.Source.InvariantDecl) :
    MacroM (TSyntax `term) := do
  let values ← invariants.mapM quoteInvariantDecl
  `(#[$[$values],*])

/-- Quote an already decoded source value without reinterpreting raw grammar. -/
private def quoteProgram (sourceProgram : ProofForgeV2.Source.Program) : MacroM (TSyntax `term) := do
  let qualifiedName := Syntax.mkStrLit sourceProgram.qualifiedName
  let name := Syntax.mkStrLit sourceProgram.name
  let stateExpr ← quoteState sourceProgram.state
  let structs ← quoteStructs sourceProgram.structs
  let enums ← quoteEnums sourceProgram.enums
  let consts ← quoteConsts sourceProgram.consts
  let events ← quoteEvents sourceProgram.events
  let errors ← quoteErrors sourceProgram.errors
  let initializer ← quoteInitializer? sourceProgram.initializer
  let entries ← quoteEntries sourceProgram.entries
  let functions ← quoteFunctions sourceProgram.functions
  let invariants ← quoteInvariants sourceProgram.invariants
  `(ProofForgeV2.Source.Program.mk $qualifiedName $name $stateExpr $structs $enums $consts $events
      $errors $initializer $entries $functions $invariants)

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
