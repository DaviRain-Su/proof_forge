/-
# Direct `contract_source` authoring surface

The public source DSL constructs one target-neutral `AuthoredContract` and
normalizes directly to checked Canonical Core. It does not construct or adapt
`ContractSpec`, `IR.Module`, or the retired builder expression tree.

Unmigrated sources must import `ProofForge.Contract.Source.Legacy` explicitly.
That namespace is deletion-only and is never discovered by the public loader.
-/
import Lean
import ProofForge.Frontend.Authored

set_option hygiene false

namespace ProofForge.Contract.Source

open Lean
open ProofForge.Frontend.Authored

def sourceDslVersion : String := "contract-source"

abbrev ModuleM := ProofForge.Frontend.Authored.Builder.ModuleM
abbrev EntryM := ProofForge.Frontend.Authored.Builder.EntryM

structure ScalarRef where
  id : String
  type : AuthoredType
  deriving Repr

structure BindingRef where
  id : String
  type : AuthoredType
  abiWord? : Option String := none
  deriving Repr

def slot (id : String) (type : AuthoredType) : ScalarRef :=
  { id, type }

def binding (id : String) (type : AuthoredType) : BindingRef :=
  { id, type }

def bindingWithAbiWord (id : String) (type : AuthoredType) (abiWord : String) : BindingRef :=
  { id, type, abiWord? := some abiWord }

def scalar (ref : ScalarRef) : ModuleM Unit :=
  ProofForge.Frontend.Authored.Builder.scalarState ref.id ref.type

def ref (bindingRef : BindingRef) : AuthoredExpr :=
  .local bindingRef.id

def read (stateRef : ScalarRef) : AuthoredExpr :=
  .stateRead stateRef.id

def u64 (value : Nat) : AuthoredExpr :=
  .literal (.u64Lit value)

def u128 (value : Nat) : AuthoredExpr :=
  .literal (.u128Lit value)

def boolLit (value : Bool) : AuthoredExpr :=
  .literal (.boolLit value)

def blockNumber : AuthoredExpr :=
  .contextRead .blockNumber

/-- Immediate portable caller identity. Target plans decide how the logical
address is read from their execution environment. -/
def caller : AuthoredExpr :=
  .contextRead .sender

/-- Target-neutral absent-address value. Each target plan materializes the
numeric zero handle in its native address representation. -/
def addressZero : AuthoredExpr :=
  .literal (.addressLit "0")

def add (lhs rhs : AuthoredExpr) (checked : Bool := true) : AuthoredExpr :=
  .arith .add checked lhs rhs

def sub (lhs rhs : AuthoredExpr) (checked : Bool := true) : AuthoredExpr :=
  .arith .sub checked lhs rhs

def mul (lhs rhs : AuthoredExpr) (checked : Bool := true) : AuthoredExpr :=
  .arith .mul checked lhs rhs

def div (lhs rhs : AuthoredExpr) : AuthoredExpr :=
  .arith .div false lhs rhs

/-- Target-neutral local array literal. Its source length is fixed by `values`;
target plans choose the concrete memory representation. -/
def arrayLiteral (elementType : AuthoredType) (values : Array AuthoredExpr) : AuthoredExpr :=
  .memoryArray elementType values

/-- Target-neutral local array access. Bounds behavior is preserved by
Canonical Core and materialized by each target plan. -/
def arrayGet (array index : AuthoredExpr) : AuthoredExpr :=
  .index array index

class ToExpr (alpha : Type) where
  toExpr : alpha -> AuthoredExpr

instance : ToExpr AuthoredExpr where
  toExpr value := value

instance : ToExpr BindingRef where
  toExpr value := ref value

instance : ToExpr ScalarRef where
  toExpr value := read value

instance : ToExpr Nat where
  toExpr value := u64 value

def expr [ToExpr alpha] (value : alpha) : AuthoredExpr :=
  ToExpr.toExpr value

def addValue [ToExpr alpha] [ToExpr beta] (lhs : alpha) (rhs : beta) : AuthoredExpr :=
  add (expr lhs) (expr rhs)

def subValue [ToExpr alpha] [ToExpr beta] (lhs : alpha) (rhs : beta) : AuthoredExpr :=
  sub (expr lhs) (expr rhs)

def mulValue [ToExpr alpha] [ToExpr beta] (lhs : alpha) (rhs : beta) : AuthoredExpr :=
  mul (expr lhs) (expr rhs)

def divValue [ToExpr alpha] [ToExpr beta] (lhs : alpha) (rhs : beta) : AuthoredExpr :=
  div (expr lhs) (expr rhs)

scoped infixl:65 " +! " => addValue
scoped infixl:65 " -! " => subValue
scoped infixl:70 " *! " => mulValue
scoped infixl:70 " /! " => divValue

declare_syntax_cat contractItem
declare_syntax_cat entryStmt

scoped syntax "state " ident " : " term : contractItem
scoped syntax "binding " ident " : " term : contractItem
scoped syntax "event " ident term : contractItem
scoped syntax "quint_invariant " ident " := " str : contractItem
scoped syntax "quint_liveness " ident " := " str : contractItem
scoped syntax "lean_invariant " ident " := " str : contractItem
scoped syntax "entry " ident " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem

scoped syntax "let " ident " : " term " := " term ";" : entryStmt
scoped syntax ident " := " term ";" : entryStmt
scoped syntax "emit " ident term ";" : entryStmt
scoped syntax "return " term ";" : entryStmt
scoped syntax "do " term ";" : entryStmt

scoped syntax "contract_source " ident " do" ppLine contractItem* : command
scoped syntax "contract_mixin " ident " do" ppLine contractItem* : command

namespace Direct

def nameLit (name : TSyntax `ident) : TSyntax `term :=
  quote name.getId.toString

def chain (actions : Array (TSyntax `term)) : MacroM (TSyntax `term) := do
  let mut body <- `(pure ())
  for action in actions.reverse do
    body <- `($action *> $body)
  return body

partial def lowerExpr (states locals : Array String) (source : TSyntax `term) :
    MacroM (TSyntax `term) := do
  match source with
  | `(($value:term)) =>
      lowerExpr states locals value
  | `(u64 $value:num) =>
      `(.literal (.u64Lit $value))
  | `(u128 $value:num) =>
      `(.literal (.u128Lit $value))
  | `(boolLit $value:term) =>
      `(.literal (.boolLit $value))
  | `(blockNumber) =>
      `(.contextRead .blockNumber)
  | `(caller) =>
      `(.contextRead .sender)
  | `(addressZero) =>
      `(.literal (.addressLit "0"))
  | `($lhs:term +! $rhs:term) =>
      let left <- lowerExpr states locals lhs
      let right <- lowerExpr states locals rhs
      `(.arith .add true $left $right)
  | `($lhs:term -! $rhs:term) =>
      let left <- lowerExpr states locals lhs
      let right <- lowerExpr states locals rhs
      `(.arith .sub true $left $right)
  | `($lhs:term *! $rhs:term) =>
      let left <- lowerExpr states locals lhs
      let right <- lowerExpr states locals rhs
      `(.arith .mul true $left $right)
  | `($lhs:term /! $rhs:term) =>
      let left <- lowerExpr states locals lhs
      let right <- lowerExpr states locals rhs
      `(.arith .div false $left $right)
  | `(arrayLiteral $elementType:term #[$values,*]) =>
      let loweredValues <- values.getElems.mapM (lowerExpr states locals)
      `(.memoryArray $elementType #[$loweredValues,*])
  | `(arrayGet $array:term $index:term) =>
      let loweredArray <- lowerExpr states locals array
      let loweredIndex <- lowerExpr states locals index
      `(.index $loweredArray $loweredIndex)
  | `(term| $name:ident) =>
      let value := name.getId.toString
      let valueTerm : TSyntax `term := quote value
      if states.contains value && !locals.contains value then
        `(.stateRead $valueTerm)
      else
        `(.local $valueTerm)
  | _ => Macro.throwErrorAt source s!"unsupported direct authored expression `{source.raw}`; no Legacy fallback exists"

def lowerEventArgument (states locals : Array String) (source : TSyntax `term) :
    MacroM (TSyntax `term) := do
  match source with
  | `(field $value:ident) =>
      let valueTerm <- lowerExpr states locals value
      let fieldName := nameLit value
      `(ProofForge.Frontend.Authored.AuthoredEventArgument.mk
        $fieldName false none $valueTerm)
  | `(fieldAs $name:ident $value:term) =>
      let valueTerm <- lowerExpr states locals value
      let fieldName := nameLit name
      `(ProofForge.Frontend.Authored.AuthoredEventArgument.mk
        $fieldName false none $valueTerm)
  | `(indexedField $value:ident) =>
      let valueTerm <- lowerExpr states locals value
      let fieldName := nameLit value
      `(ProofForge.Frontend.Authored.AuthoredEventArgument.mk
        $fieldName true none $valueTerm)
  | `(indexedFieldAs $name:ident $value:term) =>
      let valueTerm <- lowerExpr states locals value
      let fieldName := nameLit name
      `(ProofForge.Frontend.Authored.AuthoredEventArgument.mk
        $fieldName true none $valueTerm)
  | _ => Macro.throwErrorAt source "unsupported direct authored event argument"

def lowerEntryBody (states : Array String) (params : Array String)
    (statements : Array (TSyntax `entryStmt)) : MacroM (TSyntax `term) := do
  let mut locals := params
  let mut actions : Array (TSyntax `term) := #[]
  for statement in statements do
    match statement with
    | `(entryStmt| let $name:ident : $type:term := $value:term;) =>
        let valueTerm <- lowerExpr states locals value
        let nameTerm := nameLit name
        actions := actions.push (←
          `(ProofForge.Frontend.Authored.Builder.bind $nameTerm $type $valueTerm))
        locals := locals.push name.getId.toString
    | `(entryStmt| $target:ident := $value:term;) =>
        let valueTerm <- lowerExpr states locals value
        let targetTerm := nameLit target
        if states.contains target.getId.toString && !locals.contains target.getId.toString then
          actions := actions.push (←
            `(ProofForge.Frontend.Authored.Builder.stateWrite $targetTerm $valueTerm))
        else
          actions := actions.push (←
            `(ProofForge.Frontend.Authored.Builder.assign (.local $targetTerm) $valueTerm))
    | `(entryStmt| emit $eventName:ident $fieldsTerm:term;) =>
        let fields <- match fieldsTerm with
          | `(#[$fields,*]) => pure fields.getElems
          | _ => Macro.throwErrorAt fieldsTerm "event arguments must be an array literal"
        let loweredFields <- fields.mapM (lowerEventArgument states locals)
        let eventNameTerm := nameLit eventName
        actions := actions.push (←
          `(ProofForge.Frontend.Authored.Builder.emitFields $eventNameTerm #[$loweredFields,*]))
    | `(entryStmt| return $value:term;) =>
        let valueTerm <- lowerExpr states locals value
        actions := actions.push (← `(ProofForge.Frontend.Authored.Builder.ret $valueTerm))
    | `(entryStmt| do $action:term;) =>
        match action with
        | `(requireEq $lhs:term $rhs:term $message:str) =>
            let left <- lowerExpr states locals lhs
            let right <- lowerExpr states locals rhs
            actions := actions.push (←
              `(ProofForge.Frontend.Authored.Builder.assert (.compare .eq $left $right) $message))
        | `(requireNe $lhs:term $rhs:term $message:str) =>
            let left <- lowerExpr states locals lhs
            let right <- lowerExpr states locals rhs
            actions := actions.push (←
              `(ProofForge.Frontend.Authored.Builder.assert (.compare .ne $left $right) $message))
        | _ => Macro.throwErrorAt action "unsupported direct authored action; no Legacy fallback exists"
    | _ => Macro.throwErrorAt statement "unsupported direct authored statement; no Legacy fallback exists"
  chain actions

def entryAction (states : Array String) (name : TSyntax `ident)
    (params : Array (TSyntax `ident × TSyntax `term)) (retType : TSyntax `term)
    (isView : Bool) (statements : Array (TSyntax `entryStmt)) : MacroM (TSyntax `term) := do
  let body <- lowerEntryBody states (params.map fun param => param.1.getId.toString) statements
  let authoredParams <- params.mapM fun param => do
    let paramName := nameLit param.1
    let paramType := param.2
    `(show ProofForge.Frontend.Authored.AuthoredParam from {
      name := $paramName, type := $paramType })
  let mutability <- if isView then `(.view) else `(.call)
  let entryName := nameLit name
  `(ProofForge.Frontend.Authored.Builder.entryFull $entryName #[$authoredParams,*]
      $retType $body $mutability)

def stateNames (items : Array (TSyntax `contractItem)) : Array String :=
  items.foldl (init := #[]) fun names item => match item with
    | `(contractItem| state $name:ident : $_type:term) => names.push name.getId.toString
    | _ => names

def strLitValue (stx : TSyntax `str) : MacroM String := do
  match stx.raw.isStrLit? with
  | some value => pure value
  | none => Macro.throwErrorAt stx "expected a string literal"

def lowerEventFieldDecl (source : TSyntax `term) :
    MacroM (TSyntax `term) := do
  match source with
  | `(field $name:ident $type:term) =>
      let fieldName := nameLit name
      `(ProofForge.Frontend.Authored.AuthoredEventField.mk
        $fieldName $type false none)
  | `(indexedField $name:ident $type:term) =>
      let fieldName := nameLit name
      `(ProofForge.Frontend.Authored.AuthoredEventField.mk
        $fieldName $type true none)
  | _ => Macro.throwErrorAt source "unsupported direct authored event field"

def lowerItem (states : Array String) (item : TSyntax `contractItem) :
    MacroM (Option (TSyntax `term)) := do
  match item with
  | `(contractItem| state $name:ident : $type:term) =>
      let stateName := nameLit name
      return some (← `(ProofForge.Frontend.Authored.Builder.scalarState $stateName $type))
  | `(contractItem| binding $_name:ident : $_type:term) =>
      return none
  | `(contractItem| event $name:ident $fieldsTerm:term) =>
      let eventName := nameLit name
      let fields <- match fieldsTerm with
        | `(#[$fields,*]) => pure fields.getElems
        | _ => Macro.throwErrorAt fieldsTerm "event fields must be an array literal"
      let loweredFields <- fields.mapM lowerEventFieldDecl
      return some (← `(ProofForge.Frontend.Authored.Builder.event
        (ProofForge.Frontend.Authored.AuthoredEventDecl.mk
          $eventName #[$loweredFields,*])))
  | `(contractItem| quint_invariant $name:ident := $body:str) =>
      let annotationName := nameLit name
      let annotationBody : TSyntax `term := quote (← strLitValue body)
      return some (← `(ProofForge.Frontend.Authored.Builder.quintInvariant
        $annotationName $annotationBody))
  | `(contractItem| quint_liveness $name:ident := $body:str) =>
      let annotationName := nameLit name
      let annotationBody : TSyntax `term := quote (← strLitValue body)
      return some (← `(ProofForge.Frontend.Authored.Builder.quintLiveness
        $annotationName $annotationBody))
  | `(contractItem| lean_invariant $name:ident := $body:str) =>
      let annotationName := nameLit name
      let annotationBody : TSyntax `term := quote (← strLitValue body)
      return some (← `(ProofForge.Frontend.Authored.Builder.leanInvariant
        $annotationName $annotationBody))
  | `(contractItem| entry $name:ident do $statements:entryStmt*) =>
      return some (← entryAction states name #[] (← `(.unit)) false statements)
  | `(contractItem| entry $name:ident returns($retType:term) do $statements:entryStmt*) =>
      return some (← entryAction states name #[] retType false statements)
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term) do $statements:entryStmt*) =>
      return some (← entryAction states name #[(p1, t1)] (← `(.unit)) false statements)
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term) returns($retType:term) do $statements:entryStmt*) =>
      return some (← entryAction states name #[(p1, t1)] retType false statements)
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) do $statements:entryStmt*) =>
      return some (← entryAction states name #[(p1, t1), (p2, t2)] (← `(.unit)) false statements)
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) returns($retType:term) do $statements:entryStmt*) =>
      return some (← entryAction states name #[(p1, t1), (p2, t2)] retType false statements)
  | `(contractItem| query $name:ident returns($retType:term) do $statements:entryStmt*) =>
      return some (← entryAction states name #[] retType true statements)
  | `(contractItem| query $name:ident ($p1:ident : $t1:term) returns($retType:term) do $statements:entryStmt*) =>
      return some (← entryAction states name #[(p1, t1)] retType true statements)
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) returns($retType:term) do $statements:entryStmt*) =>
      return some (← entryAction states name #[(p1, t1), (p2, t2)] retType true statements)
  | _ => Macro.throwErrorAt item "unsupported direct authored contract item; no Legacy fallback exists"

def lowerItems (items : Array (TSyntax `contractItem)) : MacroM (TSyntax `term) := do
  let states := stateNames items
  let mut actions : Array (TSyntax `term) := #[]
  for item in items do
    if let some action <- lowerItem states item then
      actions := actions.push action
  chain actions

end Direct

macro_rules
  | `(contract_source $name:ident do $items:contractItem*) => do
      let body <- Direct.lowerItems items
      `(
        def contract : ProofForge.Frontend.Authored.AuthoredContract :=
          ProofForge.Frontend.Authored.Builder.build $(Direct.nameLit name) $body
      )
  | `(contract_mixin $_name:ident do $items:contractItem*) => do
      let body <- Direct.lowerItems items
      `(
        def mixin : ProofForge.Frontend.Authored.Builder.ModuleM Unit := $body
      )

end ProofForge.Contract.Source
