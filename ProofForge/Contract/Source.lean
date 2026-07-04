import Lean
import ProofForge.Contract.Surface
import ProofForge.Solana.Surface

namespace ProofForge.Contract.Source

open Lean
open ProofForge.IR

abbrev ScalarRef := ProofForge.Contract.Surface.ScalarRef
abbrev BindingRef := ProofForge.Contract.Surface.BindingRef
abbrev MethodRef := ProofForge.Contract.Surface.MethodRef
abbrev EventRef := ProofForge.Contract.Surface.EventRef
abbrev EventField := ProofForge.Contract.Surface.EventField
abbrev ModuleM := ProofForge.Contract.Surface.ModuleM
abbrev EntryM := ProofForge.Contract.Surface.EntryM
abbrev ContractSpec := ProofForge.Contract.ContractSpec

def checkpointId : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.checkpointId

def u64 (value : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.u64 value

class ToExpr (α : Type) where
  toExpr : α → ProofForge.IR.Expr

instance : ToExpr ProofForge.IR.Expr where
  toExpr value := value

instance : ToExpr ProofForge.Contract.Surface.BindingRef where
  toExpr binding := ProofForge.Contract.Surface.ref binding

instance : ToExpr ProofForge.Contract.Surface.ScalarRef where
  toExpr slot := ProofForge.Contract.Surface.read slot

def expr [ToExpr α] (value : α) : ProofForge.IR.Expr :=
  ToExpr.toExpr value

def bindValue [ToExpr α] (binding : ProofForge.Contract.Surface.BindingRef)
    (value : α) : EntryM Unit :=
  ProofForge.Contract.Surface.bind binding (expr value)

def writeValue [ToExpr α] (slot : ProofForge.Contract.Surface.ScalarRef)
    (value : α) : EntryM Unit :=
  ProofForge.Contract.Surface.write slot (expr value)

def retValue [ToExpr α] (value : α) : EntryM Unit :=
  ProofForge.Contract.Surface.ret (expr value)

def addValue [ToExpr α] [ToExpr β] (lhs : α) (rhs : β) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.add (expr lhs) (expr rhs)

def subValue [ToExpr α] [ToExpr β] (lhs : α) (rhs : β) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.sub (expr lhs) (expr rhs)

def mulValue [ToExpr α] [ToExpr β] (lhs : α) (rhs : β) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.mul (expr lhs) (expr rhs)

def divValue [ToExpr α] [ToExpr β] (lhs : α) (rhs : β) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.div (expr lhs) (expr rhs)

scoped infixl:65 " +! " => addValue
scoped infixl:65 " -! " => subValue
scoped infixl:70 " *! " => mulValue
scoped infixl:70 " /! " => divValue

class ToField (α : Type) where
  toField : α → ProofForge.Contract.Surface.EventField

instance : ToField ProofForge.Contract.Surface.BindingRef where
  toField binding := ProofForge.Contract.Surface.fieldOf binding

instance : ToField ProofForge.Contract.Surface.ScalarRef where
  toField slot := ProofForge.Contract.Surface.fieldAs slot (expr slot)

def field [ToField α] (value : α) : ProofForge.Contract.Surface.EventField :=
  ToField.toField value

def fieldValue [ToExpr α] (name : String) (value : α) :
    ProofForge.Contract.Surface.EventField :=
  ProofForge.Contract.Surface.field name (expr value)

def fieldAs [ToExpr α] (slot : ProofForge.Contract.Surface.ScalarRef)
    (value : α) : ProofForge.Contract.Surface.EventField :=
  ProofForge.Contract.Surface.fieldAs slot (expr value)

def emitEvent (eventRef : ProofForge.Contract.Surface.EventRef)
    (fields : Array ProofForge.Contract.Surface.EventField) : EntryM Unit :=
  ProofForge.Contract.Surface.emit eventRef fields

declare_syntax_cat contractItem
declare_syntax_cat entryStmt
declare_syntax_cat solanaSeed
declare_syntax_cat solanaSignerSeed

scoped syntax "state " ident " : " term : contractItem
scoped syntax "mapping " ident " from " term " to " term : contractItem
scoped syntax "binding " ident " : " term : contractItem
scoped syntax "event " ident : contractItem
scoped syntax "allocator " "bump" : contractItem
scoped syntax "account " ident " readonly" : contractItem
scoped syntax "account " ident " readonly " "signer" : contractItem
scoped syntax "account " ident " readonly " "owner " term : contractItem
scoped syntax "account " ident " readonly " "signer " "owner " term : contractItem
scoped syntax "account " ident " writable" : contractItem
scoped syntax "account " ident " writable " "signer" : contractItem
scoped syntax "account " ident " writable " "owner " term : contractItem
scoped syntax "account " ident " writable " "signer " "owner " term : contractItem
scoped syntax "pda " ident " seeds " "[" solanaSeed,* "]" " bump " ident " account " ident " signer" : contractItem
scoped syntax "cpi " ident " system_transfer" "(" ident ", " ident ", " ident ")" : contractItem
scoped syntax "cpi " ident " system_create_account" "(" ident ", " ident ", " ident ", " ident ")" " owner " term : contractItem
scoped syntax "cpi " ident " spl_token_transfer_checked" "(" ident ", " ident ", " ident ", " ident ", " ident ")" " decimals" "(" term ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" : contractItem
scoped syntax "cpi " ident " spl_token_close_account" "(" ident ", " ident ", " ident ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" : contractItem
scoped syntax "cpi " ident " spl_token_set_authority" "(" ident ", " ident ", " ident ")" " authority_type" "(" term ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" : contractItem
scoped syntax "use " term : contractItem
scoped syntax "entry " ident " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem

scoped syntax "let " ident " : " term " := " term ";" : entryStmt
scoped syntax ident " := " term ";" : entryStmt
scoped syntax "emit " ident term ";" : entryStmt
scoped syntax "return " term ";" : entryStmt
scoped syntax "derive " "pda " ident " seeds " "[" solanaSeed,* "]" " bump " ident " account " ident " signer;" : entryStmt
scoped syntax "invoke " ident " system_transfer" "(" ident ", " ident ", " ident ")" ";" : entryStmt
scoped syntax "invoke " ident " system_create_account" "(" ident ", " ident ", " ident ", " ident ")" " owner " term ";" : entryStmt
scoped syntax "invoke " ident " spl_token_transfer_checked" "(" ident ", " ident ", " ident ", " ident ", " ident ")" " decimals" "(" term ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" ";" : entryStmt
scoped syntax "invoke " ident " spl_token_close_account" "(" ident ", " ident ", " ident ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" ";" : entryStmt
scoped syntax "invoke " ident " spl_token_set_authority" "(" ident ", " ident ", " ident ")" " authority_type" "(" term ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" ";" : entryStmt
scoped syntax "realloc " ident " to " term ";" : entryStmt
scoped syntax "do " term ";" : entryStmt

scoped syntax "literal_seed " str : solanaSeed
scoped syntax "account_seed " ident : solanaSeed

scoped syntax "pda_seed " ident : solanaSignerSeed
scoped syntax "bump_seed " ident : solanaSignerSeed

scoped syntax "contract_source " ident " do" ppLine contractItem* : command

private def identNameLit (name : TSyntax `ident) : TSyntax `term :=
  ⟨Syntax.mkStrLit name.getId.toString⟩

private def chainTerms (terms : Array (TSyntax `term)) : MacroM (TSyntax `term) := do
  let mut acc ← `(pure ())
  for term in terms.reverse do
    acc ← `($term *> $acc)
  return acc

private def mkParamLet (name : TSyntax `ident) (type : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Surface.BindingRef :=
      ProofForge.Contract.Surface.binding $nameLit $type
    $body)

private def mkBindingLet (name : TSyntax `ident) (type : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) :=
  mkParamLet name type body

private def mkMapLet (name : TSyntax `ident) (keyType valueType : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Surface.MapRef :=
      { id := $nameLit, keyType := $keyType, valueType := $valueType }
    $body)

private def mkStateLet (name : TSyntax `ident) (type : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Surface.ScalarRef :=
      ProofForge.Contract.Surface.slot $nameLit $type
    $body)

private def mkEventLet (name : TSyntax `ident)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Surface.EventRef :=
      ProofForge.Contract.Surface.event $nameLit
    $body)

private def mkAccountLet (name : TSyntax `ident)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Solana.Surface.AccountRef :=
      { name := $nameLit }
    $body)

private def mkPdaLet (name : TSyntax `ident)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Solana.Surface.PdaRef :=
      { name := $nameLit }
    $body)

private def mkCpiLet (name : TSyntax `ident)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Solana.Surface.CpiRef :=
      { name := $nameLit }
    $body)

private def lowerSolanaSeed (seed : TSyntax `solanaSeed) : MacroM (TSyntax `term) := do
  match seed with
  | `(solanaSeed| literal_seed $value:str) =>
      `(ProofForge.Solana.Surface.literalSeed $value)
  | `(solanaSeed| account_seed $accountRef:ident) =>
      `(ProofForge.Solana.Surface.accountSeed $accountRef)
  | _ =>
      Macro.throwError s!"unsupported Solana PDA seed: {seed.raw}"

private def lowerSolanaSeeds (seedItems : TSyntaxArray `solanaSeed) : MacroM (TSyntax `term) := do
  let lowered ← seedItems.mapM lowerSolanaSeed
  `(#[$lowered,*])

private def lowerSolanaSignerSeed (seed : TSyntax `solanaSignerSeed) : MacroM (TSyntax `term) := do
  match seed with
  | `(solanaSignerSeed| pda_seed $pdaRef:ident) =>
      `(ProofForge.Solana.Surface.pdaName $pdaRef)
  | `(solanaSignerSeed| bump_seed $bindingRef:ident) =>
      `(ProofForge.Solana.Surface.bindingName $bindingRef)
  | _ =>
      Macro.throwError s!"unsupported Solana signer seed: {seed.raw}"

private def lowerSolanaSignerSeeds (seedItems : TSyntaxArray `solanaSignerSeed) : MacroM (TSyntax `term) := do
  let lowered ← seedItems.mapM lowerSolanaSignerSeed
  `(#[$lowered,*])

partial def lowerEntryBody (stmts : Array (TSyntax `entryStmt)) :
    MacroM (TSyntax `term) := do
  let mut acc ← `(pure ())
  for stmt in stmts.reverse do
    match stmt with
    | `(entryStmt| let $name:ident : $type:term := $value:term;) =>
        let nameLit := identNameLit name
        acc ←
          `(let $name : ProofForge.Contract.Surface.BindingRef :=
              ProofForge.Contract.Surface.binding $nameLit $type
            ProofForge.Contract.Source.bindValue $name $value *> $acc)
    | `(entryStmt| $slot:ident := $value:term;) =>
        acc ← `(ProofForge.Contract.Source.writeValue $slot $value *> $acc)
    | `(entryStmt| emit $eventRef:ident $fields:term;) =>
        acc ← `(ProofForge.Contract.Source.emitEvent $eventRef $fields *> $acc)
    | `(entryStmt| return $value:term;) =>
        acc ← `(ProofForge.Contract.Source.retValue $value *> $acc)
    | `(entryStmt| derive pda $pdaRef:ident seeds [$seedItems:solanaSeed,*] bump $bumpRef:ident account $accountRef:ident signer;) =>
        let seedArray ← lowerSolanaSeeds seedItems
        acc ←
          `(ProofForge.Solana.Surface.derivePda $pdaRef $seedArray
              (bump? := some $bumpRef)
              (account? := some $accountRef)
              (isSigner := true) *> $acc)
    | `(entryStmt| invoke $call:ident system_transfer($fromAccount:ident, $toAccount:ident, $lamportsSource:ident);) =>
        let callLit := identNameLit call
        let fromLit := identNameLit fromAccount
        let toLit := identNameLit toAccount
        let lamportsLit := identNameLit lamportsSource
        acc ←
          `(ProofForge.Solana.invokeSystemTransfer $callLit $fromLit $toLit $lamportsLit *> $acc)
    | `(entryStmt| invoke $call:ident system_create_account($payer:ident, $newAccount:ident, $lamportsSource:ident, $spaceSource:ident) owner $ownerSource:term;) =>
        let callLit := identNameLit call
        let payerLit := identNameLit payer
        let newAccountLit := identNameLit newAccount
        let lamportsLit := identNameLit lamportsSource
        let spaceLit := identNameLit spaceSource
        acc ←
          `(ProofForge.Solana.invokeSystemCreateAccount
              $callLit $payerLit $newAccountLit $lamportsLit $spaceLit $ownerSource *> $acc)
    | `(entryStmt| invoke $call:ident spl_token_transfer_checked($source:ident, $mint:ident, $destination:ident, $authority:ident, $amountRef:ident) decimals($decimalValue:term) signer_seeds [$signerSeedItems:solanaSignerSeed,*];) =>
        let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
        acc ←
          `(ProofForge.Solana.Surface.invokeSplTokenTransferChecked
              $call $source $mint $destination $authority $amountRef $decimalValue
              (signerSeeds := $signerSeedArray) *> $acc)
    | `(entryStmt| invoke $call:ident spl_token_close_account($tokenAccount:ident, $destination:ident, $authority:ident) signer_seeds [$signerSeedItems:solanaSignerSeed,*];) =>
        let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
        acc ←
          `(ProofForge.Solana.Surface.invokeSplTokenCloseAccount
              $call $tokenAccount $destination $authority
              (signerSeeds := $signerSeedArray) *> $acc)
    | `(entryStmt| invoke $call:ident spl_token_set_authority($tokenAccount:ident, $authority:ident, $newAuthority:ident) authority_type($authorityType:term) signer_seeds [$signerSeedItems:solanaSignerSeed,*];) =>
        let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
        acc ←
          `(ProofForge.Solana.Surface.invokeSplTokenSetAuthority
              $call $tokenAccount $authority $newAuthority
              (authorityType := $authorityType)
              (signerSeeds := $signerSeedArray) *> $acc)
    | `(entryStmt| realloc $accountRef:ident to $newSize:term;) =>
        acc ←
          `(ProofForge.Solana.Surface.reallocAccount $accountRef $newSize *> $acc)
    | `(entryStmt| do $action:term;) =>
        acc ← `($action *> $acc)
    | _ =>
        Macro.throwError s!"unsupported contract source statement: {stmt.raw}"
  return acc

private def mkEntry0 (name : TSyntax `ident) (retTy : TSyntax `term)
    (stmts : Array (TSyntax `entryStmt)) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts
  `(ProofForge.Contract.Surface.entry
      (ProofForge.Contract.Surface.method $nameLit #[] $retTy)
      $body)

private def mkEntry1 (name p1 : TSyntax `ident) (t1 retTy : TSyntax `term)
    (stmts : Array (TSyntax `entryStmt)) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts
  mkParamLet p1 t1
    (← `(ProofForge.Contract.Surface.entry
        (ProofForge.Contract.Surface.method $nameLit #[$p1] $retTy)
        $body))

private def mkEntry2 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 retTy : TSyntax `term)
    (stmts : Array (TSyntax `entryStmt)) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← `(ProofForge.Contract.Surface.entry
          (ProofForge.Contract.Surface.method $nameLit #[$p1, $p2] $retTy)
          $body)))

private def mkEntry3 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 retTy : TSyntax `term)
    (stmts : Array (TSyntax `entryStmt)) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← mkParamLet p3 t3
        (← `(ProofForge.Contract.Surface.entry
            (ProofForge.Contract.Surface.method $nameLit #[$p1, $p2, $p3] $retTy)
            $body))))

private structure LoweredItem where
  action? : Option (TSyntax `term) := none
  binder : TSyntax `term → MacroM (TSyntax `term) := fun body => pure body

private def lowerItem (item : TSyntax `contractItem) : MacroM LoweredItem := do
  match item with
  | `(contractItem| state $name:ident : $type:term) =>
      let action ← `(ProofForge.Contract.Surface.scalar $name)
      return { action? := some action, binder := mkStateLet name type }
  | `(contractItem| mapping $name:ident from $keyType:term to $valueType:term) =>
      let action ← `(ProofForge.Contract.Surface.mapState $name)
      return { action? := some action, binder := mkMapLet name keyType valueType }
  | `(contractItem| binding $name:ident : $type:term) =>
      return { binder := mkBindingLet name type }
  | `(contractItem| event $name:ident) =>
      return { binder := mkEventLet name }
  | `(contractItem| allocator bump) =>
      let action ← `(ProofForge.Solana.Surface.bumpAllocator)
      return { action? := some action }
  | `(contractItem| account $name:ident readonly) =>
      let action ← `(ProofForge.Solana.Surface.readonlyAccount $name)
      return { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident readonly signer) =>
      let action ← `(ProofForge.Solana.Surface.signerAccount $name)
      return { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident readonly owner $ownerValue:term) =>
      let action ← `(ProofForge.Solana.Surface.readonlyAccount $name $ownerValue)
      return { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident readonly signer owner $ownerValue:term) =>
      let action ← `(ProofForge.Solana.Surface.signerAccount $name .readOnly $ownerValue)
      return { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident writable) =>
      let action ← `(ProofForge.Solana.Surface.writableAccount $name)
      return { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident writable signer) =>
      let action ← `(ProofForge.Solana.Surface.writableSignerAccount $name)
      return { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident writable owner $ownerValue:term) =>
      let action ← `(ProofForge.Solana.Surface.writableAccount $name $ownerValue)
      return { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident writable signer owner $ownerValue:term) =>
      let action ← `(ProofForge.Solana.Surface.writableSignerAccount $name $ownerValue)
      return { action? := some action, binder := mkAccountLet name }
  | `(contractItem| pda $name:ident seeds [$seedItems:solanaSeed,*] bump $bumpRef:ident account $accountRef:ident signer) =>
      let seedArray ← lowerSolanaSeeds seedItems
      let action ←
        `(ProofForge.Solana.Surface.pdaAccount $name $seedArray
            (bump? := some $bumpRef)
            (account? := some $accountRef)
            (isSigner := true))
      return { action? := some action, binder := mkPdaLet name }
  | `(contractItem| cpi $call:ident system_transfer($fromAccount:ident, $toAccount:ident, $lamportsSource:ident)) =>
      let callLit := identNameLit call
      let fromLit := identNameLit fromAccount
      let toLit := identNameLit toAccount
      let lamportsLit := identNameLit lamportsSource
      let action ←
        `(ProofForge.Solana.systemTransfer $callLit $fromLit $toLit $lamportsLit)
      return { action? := some action }
  | `(contractItem| cpi $call:ident system_create_account($payer:ident, $newAccount:ident, $lamportsSource:ident, $spaceSource:ident) owner $ownerSource:term) =>
      let callLit := identNameLit call
      let payerLit := identNameLit payer
      let newAccountLit := identNameLit newAccount
      let lamportsLit := identNameLit lamportsSource
      let spaceLit := identNameLit spaceSource
      let action ←
        `(ProofForge.Solana.systemCreateAccount
            $callLit $payerLit $newAccountLit $lamportsLit $spaceLit $ownerSource)
      return { action? := some action }
  | `(contractItem| cpi $call:ident spl_token_transfer_checked($source:ident, $mint:ident, $destination:ident, $authority:ident, $amountRef:ident) decimals($decimalValue:term) signer_seeds [$signerSeedItems:solanaSignerSeed,*]) =>
      let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
      let action ←
        `(ProofForge.Solana.Surface.splTokenTransferChecked
            $call $source $mint $destination $authority $amountRef $decimalValue
            (signerSeeds := $signerSeedArray))
      return { action? := some action, binder := mkCpiLet call }
  | `(contractItem| cpi $call:ident spl_token_close_account($tokenAccount:ident, $destination:ident, $authority:ident) signer_seeds [$signerSeedItems:solanaSignerSeed,*]) =>
      let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
      let action ←
        `(ProofForge.Solana.Surface.splTokenCloseAccount
            $call $tokenAccount $destination $authority
            (signerSeeds := $signerSeedArray))
      return { action? := some action, binder := mkCpiLet call }
  | `(contractItem| cpi $call:ident spl_token_set_authority($tokenAccount:ident, $authority:ident, $newAuthority:ident) authority_type($authorityType:term) signer_seeds [$signerSeedItems:solanaSignerSeed,*]) =>
      let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
      let action ←
        `(ProofForge.Solana.Surface.splTokenSetAuthority
            $call $tokenAccount $authority $newAuthority
            (authorityType := $authorityType)
            (signerSeeds := $signerSeedArray))
      return { action? := some action, binder := mkCpiLet call }
  | `(contractItem| use $action:term) =>
      return { action? := some action }
  | `(contractItem| entry $name:ident do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry0 name (← `(.unit)) stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 (← `(.unit)) stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 (← `(.unit)) stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 (← `(.unit)) stmts) }
  | `(contractItem| query $name:ident returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry0 name retTy stmts) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 retTy stmts) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 retTy stmts) }
  | _ =>
      Macro.throwError s!"unsupported contract source item: {item.raw}"

macro_rules
  | `(contract_source $name:ident do $items:contractItem*) => do
      let mut loweredItems : Array LoweredItem := #[]
      let mut actions : Array (TSyntax `term) := #[]
      for item in items do
        let lowered ← lowerItem item
        loweredItems := loweredItems.push lowered
        if let some action := lowered.action? then
          actions := actions.push action
      let nameLit := identNameLit name
      let chained ← chainTerms actions
      let mut body ←
        `(ProofForge.Contract.Surface.contract $nameLit $chained)
      for lowered in loweredItems.reverse do
        body ← lowered.binder body
      let specId : TSyntax `ident := ⟨mkIdent `spec⟩
      let moduleId : TSyntax `ident := ⟨mkIdent `module⟩
      `(
        def $specId : ProofForge.Contract.ContractSpec := $body

        def $moduleId : ProofForge.IR.Module :=
          ($specId).module
      )

def mapRead [ToExpr α] (mapRef : ProofForge.Contract.Surface.MapRef) (mapKey : α) :
    ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.mapGet mapRef (expr mapKey)

def mapWrite [ToExpr α] [ToExpr β]
    (mapRef : ProofForge.Contract.Surface.MapRef) (mapKey : α) (mapValue : β) : EntryM Unit :=
  ProofForge.Contract.Surface.mapSet mapRef (expr mapKey) (expr mapValue)

def pathReadAllowance (mapRef : ProofForge.Contract.Surface.MapRef)
    (ownerKey spenderKey : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.pathRead mapRef.id
    (ProofForge.Contract.Surface.allowancePath ownerKey spenderKey)

def pathWriteAllowance [ToExpr α]
    (mapRef : ProofForge.Contract.Surface.MapRef) (ownerKey spenderKey : ProofForge.IR.Expr)
    (mapValue : α) : EntryM Unit :=
  ProofForge.Contract.Surface.pathWrite mapRef.id
    (ProofForge.Contract.Surface.allowancePath ownerKey spenderKey) (expr mapValue)

def caller : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.caller

def nativeValue : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.nativeValue

end ProofForge.Contract.Source
