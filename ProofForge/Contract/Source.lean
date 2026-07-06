import Lean
import ProofForge.Contract.Surface
import ProofForge.Solana.Surface

set_option hygiene false

namespace ProofForge.Contract.Source

open Lean
open ProofForge.IR

abbrev ScalarRef := ProofForge.Contract.Surface.ScalarRef
abbrev MapRef := ProofForge.Contract.Surface.MapRef
abbrev BindingRef := ProofForge.Contract.Surface.BindingRef
abbrev MethodRef := ProofForge.Contract.Surface.MethodRef
abbrev EventRef := ProofForge.Contract.Surface.EventRef
abbrev EventField := ProofForge.Contract.Surface.EventField
abbrev ModuleM := ProofForge.Contract.Surface.ModuleM
abbrev EntryM := ProofForge.Contract.Surface.EntryM
abbrev ContractSpec := ProofForge.Contract.ContractSpec

def checkpointId : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.checkpointId

def timestamp : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.timestamp

def epochHeight : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.epochHeight

def randomSeed : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.randomSeed

def u64 (value : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.u64 value

def boolLit (value : Bool) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.bool value

def emitIndexedEvent (eventRef : ProofForge.Contract.Surface.EventRef)
    (indexedFields dataFields : Array ProofForge.Contract.Surface.EventField) : EntryM Unit :=
  ProofForge.Contract.Surface.emitIndexed eventRef indexedFields dataFields

class ToExpr (α : Type) where
  toExpr : α → ProofForge.IR.Expr

instance : ToExpr ProofForge.IR.Expr where
  toExpr value := value

instance : ToExpr ProofForge.Contract.Surface.BindingRef where
  toExpr binding := ProofForge.Contract.Surface.ref binding

instance : ToExpr ProofForge.Contract.Surface.ScalarRef where
  toExpr slot := ProofForge.Contract.Surface.read slot

instance : ToExpr Nat where
  toExpr value := u64 value

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

def u64Array3 [ToExpr α] [ToExpr β] [ToExpr γ] (a : α) (b : β) (c : γ) : ProofForge.IR.Expr :=
  .arrayLit .u64 #[expr a, expr b, expr c]

def arrayGet [ToExpr α] [ToExpr β] (arr : α) (index : β) : ProofForge.IR.Expr :=
  .arrayGet (expr arr) (expr index)

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

def fieldAsName (name : String) [ToExpr α] (value : α) : ProofForge.Contract.Surface.EventField :=
  ProofForge.Contract.Surface.field name (expr value)

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
scoped syntax "cpi " ident " memo" "(" ident ")" : contractItem
scoped syntax "cpi " ident " system_create_account" "(" ident ", " ident ", " ident ", " ident ")" " owner " term : contractItem
scoped syntax "cpi " ident " spl_token_transfer_checked" "(" ident ", " ident ", " ident ", " ident ", " ident ")" " decimals" "(" term ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" : contractItem
scoped syntax "cpi " ident " spl_token_close_account" "(" ident ", " ident ", " ident ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" : contractItem
scoped syntax "cpi " ident " spl_token_set_authority" "(" ident ", " ident ", " ident ")" " authority_type" "(" term ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" : contractItem
scoped syntax "use " term : contractItem
scoped syntax "compose " ident ";" : contractItem
scoped syntax "upgrade_policy_immutable;" : contractItem
scoped syntax "upgrade_policy_authority " ident ";" : contractItem
scoped syntax "proxy_pattern_uups;" : contractItem
scoped syntax "proxy_pattern_transparent;" : contractItem
scoped syntax "import " ident ";" : contractItem
scoped syntax "open " ident ";" : contractItem
scoped syntax "do " term ";" : contractItem
scoped syntax "constructor_param " ident " : " term ";" : contractItem
scoped syntax "constructor_param " ident " : " "cstring" ";" : contractItem
scoped syntax "constructor_param " ident " : " "cbytes" ";" : contractItem
scoped syntax "constructor_param " ident " : " "u256array" ";" : contractItem
scoped syntax "entry " ident " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem

scoped syntax "let " ident " : " term " := " term ";" : entryStmt
scoped syntax ident " := " term ";" : entryStmt
scoped syntax "emit " ident term ";" : entryStmt
scoped syntax "emit " ident " indexed " term " data " term ";" : entryStmt
scoped syntax "return " term ";" : entryStmt
scoped syntax "derive " "pda " ident " seeds " "[" solanaSeed,* "]" " bump " ident " account " ident " signer;" : entryStmt
scoped syntax "invoke " ident " system_transfer" "(" ident ", " ident ", " ident ")" ";" : entryStmt
scoped syntax "invoke " ident " memo" "(" ident ")" ";" : entryStmt
scoped syntax "invoke " ident " system_create_account" "(" ident ", " ident ", " ident ", " ident ")" " owner " term ";" : entryStmt
scoped syntax "invoke " ident " spl_token_transfer_checked" "(" ident ", " ident ", " ident ", " ident ", " ident ")" " decimals" "(" term ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" ";" : entryStmt
scoped syntax "invoke " ident " spl_token_close_account" "(" ident ", " ident ", " ident ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" ";" : entryStmt
scoped syntax "invoke " ident " spl_token_set_authority" "(" ident ", " ident ", " ident ")" " authority_type" "(" term ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" ";" : entryStmt
scoped syntax "realloc " ident " to " term ";" : entryStmt
scoped syntax "do " term ";" : entryStmt
scoped syntax "accepts_callvalue;" : entryStmt
scoped syntax "sendto " ident ident ";" : entryStmt
scoped syntax "guard_owner " ident ";" : entryStmt
scoped syntax "guard_role " ident ";" : entryStmt
scoped syntax "guard_not_paused " ident ";" : entryStmt
scoped syntax "guard_paused " ident ";" : entryStmt
scoped syntax "guard_unlocked " ident ";" : entryStmt
scoped syntax "acquire_lock " ident ";" : entryStmt
scoped syntax "release_lock " ident ";" : entryStmt
scoped syntax "fixedu64x3 " ident "(" term ", " term ", " term ")" ";" : entryStmt

scoped syntax "literal_seed " str : solanaSeed
scoped syntax "account_seed " ident : solanaSeed

scoped syntax "pda_seed " ident : solanaSignerSeed
scoped syntax "bump_seed " ident : solanaSignerSeed

scoped syntax "contract_source " ident " do" ppLine contractItem* : command
scoped syntax "contract_mixin " ident " do" ppLine contractItem* : command

private def identNameLit (name : TSyntax `ident) : TSyntax `term :=
  ⟨Syntax.mkStrLit name.getId.toString⟩

private def mixinTerm (mod : TSyntax `ident) : MacroM (TSyntax `term) := do
  let mixId : TSyntax `ident := ⟨mkIdent (mod.getId ++ `mixin)⟩
  `(term| $mixId)

private def chainTerms (terms : Array (TSyntax `term)) : MacroM (TSyntax `term) := do
  let mut acc ← `(pure ())
  for term in terms.reverse do
    acc ← `($term *> $acc)
  return acc

private def composeSpecTerm (mod : TSyntax `ident) : MacroM (TSyntax `term) := do
  match mod.getId with
  | `ProofForge.Contract.Stdlib.Ownable =>
    `(ProofForge.Contract.Stdlib.Compose.Specs.ownableSpec)
  | `ProofForge.Contract.Stdlib.ERC20 =>
    `(ProofForge.Contract.Stdlib.Compose.Specs.erc20Spec)
  | `ProofForge.Contract.Stdlib.OwnableERC20 =>
    `(ProofForge.Contract.Stdlib.Compose.Specs.ownableErc20Spec)
  | _ =>
    let specId : TSyntax `ident := ⟨mkIdent (mod.getId ++ `spec)⟩
    `(term| $specId)

private def mkComposeBaseSpec (nameLit : TSyntax `term) (mods : Array (TSyntax `ident)) :
    MacroM (TSyntax `term) := do
  if mods.isEmpty then
    Macro.throwError "compose requires at least one module"
  else if mods.size == 1 then
    composeSpecTerm mods[0]!
  else
    let mut specs : Array (TSyntax `term) := #[]
    for mod in mods do
      specs := specs.push (← composeSpecTerm mod)
    `(ProofForge.Contract.Compose.mergeMany $nameLit #[ $(specs),* ])

private def partitionContractItems (items : Array (TSyntax `contractItem)) :
    MacroM (Array (TSyntax `ident) × Array (TSyntax `contractItem)) := do
  let mut composeMods : Array (TSyntax `ident) := #[]
  let mut extItems : Array (TSyntax `contractItem) := #[]
  for item in items do
    match item with
    | `(contractItem| compose $mod:ident;) =>
        composeMods := composeMods.push mod
    | _ =>
        extItems := extItems.push item
  return (composeMods, extItems)

private def mkParamLet (name : TSyntax `ident) (type : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  match type with
  | `(.address) =>
    `(let $name : ProofForge.Contract.Surface.BindingRef :=
        ProofForge.Contract.Surface.bindingWithAbi $nameLit (.u64) "address"
      $body)
  | `(.bytes4) =>
    `(let $name : ProofForge.Contract.Surface.BindingRef :=
        ProofForge.Contract.Surface.bindingWithAbi $nameLit (.u64) "bytes4"
      $body)
  | `(.hash) =>
    `(let $name : ProofForge.Contract.Surface.BindingRef :=
        ProofForge.Contract.Surface.bindingWithAbi $nameLit (.hash) "bytes32"
      $body)
  | `(.bytes32) =>
    `(let $name : ProofForge.Contract.Surface.BindingRef :=
        ProofForge.Contract.Surface.bindingWithAbi $nameLit (.hash) "bytes32"
      $body)
  | _ =>
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
          match type with
          | `(.address) =>
            `(let $name : ProofForge.Contract.Surface.BindingRef :=
                ProofForge.Contract.Surface.bindingWithAbi $nameLit (.u64) "address"
              ProofForge.Contract.Source.bindValue $name $value *> $acc)
          | `(.bytes4) =>
            `(let $name : ProofForge.Contract.Surface.BindingRef :=
                ProofForge.Contract.Surface.bindingWithAbi $nameLit (.u64) "bytes4"
              ProofForge.Contract.Source.bindValue $name $value *> $acc)
          | `(.hash) =>
            `(let $name : ProofForge.Contract.Surface.BindingRef :=
                ProofForge.Contract.Surface.bindingWithAbi $nameLit (.hash) "bytes32"
              ProofForge.Contract.Source.bindValue $name $value *> $acc)
          | `(.bytes32) =>
            `(let $name : ProofForge.Contract.Surface.BindingRef :=
                ProofForge.Contract.Surface.bindingWithAbi $nameLit (.hash) "bytes32"
              ProofForge.Contract.Source.bindValue $name $value *> $acc)
          | _ =>
            `(let $name : ProofForge.Contract.Surface.BindingRef :=
                ProofForge.Contract.Surface.binding $nameLit $type
              ProofForge.Contract.Source.bindValue $name $value *> $acc)
    | `(entryStmt| $slot:ident := $value:term;) =>
        acc ← `(ProofForge.Contract.Source.writeValue $slot $value *> $acc)
    | `(entryStmt| emit $eventRef:ident $fields:term;) =>
        acc ← `(ProofForge.Contract.Source.emitEvent $eventRef $fields *> $acc)
    | `(entryStmt| emit $eventRef:ident indexed $indexedFields:term data $dataFields:term;) =>
        acc ← `(ProofForge.Contract.Source.emitIndexedEvent $eventRef $indexedFields $dataFields *> $acc)
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
    | `(entryStmt| invoke $call:ident memo($memoSource:ident);) =>
        let callLit := identNameLit call
        let memoLit := identNameLit memoSource
        acc ←
          `(ProofForge.Solana.invokeMemo $callLit $memoLit *> $acc)
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
    | `(entryStmt| accepts_callvalue;) =>
        acc ← `(ProofForge.Contract.Surface.markPayable *> $acc)
    | `(entryStmt| sendto $recipient:ident $amount:ident;) =>
        acc ← `(ProofForge.Contract.Surface.nativeTransfer (ProofForge.Contract.Source.expr $recipient) (ProofForge.Contract.Source.expr $amount) *> $acc)
    | `(entryStmt| guard_owner $slot:ident;) =>
        acc ← `(ProofForge.Contract.Surface.requireOwner $slot *> $acc)
    | `(entryStmt| guard_role $role:ident;) =>
        acc ←
          `(ProofForge.Contract.Surface.requireRole roleMembers (ProofForge.Contract.Source.expr $role)
              ProofForge.Contract.Surface.caller *> $acc)
    | `(entryStmt| guard_not_paused $slot:ident;) =>
        acc ← `(ProofForge.Contract.Surface.requireNotPaused $slot *> $acc)
    | `(entryStmt| guard_paused $slot:ident;) =>
        acc ← `(ProofForge.Contract.Surface.requirePaused $slot *> $acc)
    | `(entryStmt| guard_unlocked $slot:ident;) =>
        acc ← `(ProofForge.Contract.Surface.requireUnlocked $slot *> $acc)
    | `(entryStmt| acquire_lock $slot:ident;) =>
        acc ← `(ProofForge.Contract.Surface.acquireLock $slot *> $acc)
    | `(entryStmt| release_lock $slot:ident;) =>
        acc ← `(ProofForge.Contract.Surface.releaseLock $slot *> $acc)
    | `(entryStmt| fixedu64x3 $name:ident ($a:term, $b:term, $c:term);) =>
        let nameLit := identNameLit name
        acc ←
          `(let $name : ProofForge.Contract.Surface.BindingRef :=
              ProofForge.Contract.Surface.binding $nameLit (.fixedArray .u64 3)
            ProofForge.Contract.Source.bindValue $name (ProofForge.Contract.Source.u64Array3 $a $b $c) *> $acc)
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

private def mkEntry4 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 : TSyntax `term)
    (p4 : TSyntax `ident) (t4 retTy : TSyntax `term)
    (stmts : Array (TSyntax `entryStmt)) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← mkParamLet p3 t3
        (← mkParamLet p4 t4
          (← `(ProofForge.Contract.Surface.entry
              (ProofForge.Contract.Surface.method $nameLit #[$p1, $p2, $p3, $p4] $retTy)
              $body)))))

private structure LoweredItem where
  action? : Option (TSyntax `term) := none
  binder : TSyntax `term → MacroM (TSyntax `term) := fun body => pure body

private def lowerItem (item : TSyntax `contractItem) : MacroM LoweredItem := do
  match item with
  | `(contractItem| upgrade_policy_immutable;) =>
      let action ← `(ProofForge.Contract.Surface.setUpgradePolicy ProofForge.Contract.UpgradePolicy.immutable)
      return { action? := some action }
  | `(contractItem| upgrade_policy_authority $keyRef:ident;) =>
      let keyLit := identNameLit keyRef
      let action ← `(ProofForge.Contract.Surface.setUpgradePolicy (ProofForge.Contract.UpgradePolicy.authority $keyLit))
      return { action? := some action }
  | `(contractItem| proxy_pattern_uups;) =>
      let action ← `(ProofForge.Contract.Surface.setProxyPattern ProofForge.Contract.ProxyPattern.uups)
      return { action? := some action }
  | `(contractItem| proxy_pattern_transparent;) =>
      let action ← `(ProofForge.Contract.Surface.setProxyPattern ProofForge.Contract.ProxyPattern.transparent)
      return { action? := some action }
  | `(contractItem| constructor_param $name:ident : "cstring";) =>
      let nameLit := identNameLit name
      let action ← `(ProofForge.Contract.Surface.declareConstructorParam $nameLit "string")
      return { action? := some action }
  | `(contractItem| constructor_param $name:ident : "cbytes";) =>
      let nameLit := identNameLit name
      let action ← `(ProofForge.Contract.Surface.declareConstructorParam $nameLit "bytes")
      return { action? := some action }
  | `(contractItem| constructor_param $name:ident : "u256array";) =>
      let nameLit := identNameLit name
      let action ← `(ProofForge.Contract.Surface.declareConstructorParam $nameLit "uint256[]")
      return { action? := some action }
  | `(contractItem| do $action:term;) =>
      return { action? := some action }
  | `(contractItem| constructor_param $name:ident : $type:term;) =>
      let nameLit := identNameLit name
      match type with
      | `(.u64) =>
          let action ← `(ProofForge.Contract.Surface.declareConstructorParam $nameLit "uint256")
          return { action? := some action }
      | `(.u32) =>
          let action ← `(ProofForge.Contract.Surface.declareConstructorParam $nameLit "uint32")
          return { action? := some action }
      | `(.bool) =>
          let action ← `(ProofForge.Contract.Surface.declareConstructorParam $nameLit "bool")
          return { action? := some action }
      | _ =>
          Macro.throwError s!"unsupported constructor_param type: {type.raw}"
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
  | `(contractItem| cpi $call:ident memo($memoSource:ident)) =>
      let callLit := identNameLit call
      let memoLit := identNameLit memoSource
      let action ←
        `(ProofForge.Solana.memo $callLit $memoLit)
      return { action? := some action, binder := mkCpiLet call }
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
  | `(contractItem| import $mod:ident;) =>
      return { action? := some (← mixinTerm mod) }
  | `(contractItem| open $mod:ident;) =>
      return { action? := some (← mixinTerm mod) }
  | `(contractItem| entry $name:ident do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry0 name (← `(.unit)) stmts) }
  | `(contractItem| entry $name:ident returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry0 name retTy stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 (← `(.unit)) stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 retTy stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 (← `(.unit)) stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 retTy stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 (← `(.unit)) stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 retTy stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry4 name p1 t1 p2 t2 p3 t3 p4 t4 (← `(.unit)) stmts) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry4 name p1 t1 p2 t2 p3 t3 p4 t4 retTy stmts) }
  | `(contractItem| query $name:ident returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry0 name retTy stmts) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 retTy stmts) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 retTy stmts) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 retTy stmts) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry4 name p1 t1 p2 t2 p3 t3 p4 t4 retTy stmts) }
  | _ =>
      Macro.throwError s!"unsupported contract source item: {item.raw}"

private def lowerContractItems (items : Array (TSyntax `contractItem)) :
    MacroM (TSyntax `term × Array LoweredItem) := do
  let mut loweredItems : Array LoweredItem := #[]
  let mut actions : Array (TSyntax `term) := #[]
  for item in items do
    let lowered ← lowerItem item
    loweredItems := loweredItems.push lowered
    if let some action := lowered.action? then
      actions := actions.push action
  let chained ← chainTerms actions
  let mut body ← pure chained
  for lowered in loweredItems.reverse do
    body ← lowered.binder body
  return (body, loweredItems)

macro_rules
  | `(contract_source $name:ident do $items:contractItem*) => do
      let (composeMods, extItems) ← partitionContractItems items
      let nameLit := identNameLit name
      let specId : TSyntax `ident := ⟨mkIdent `spec⟩
      let moduleId : TSyntax `ident := ⟨mkIdent `module⟩
      if composeMods.isEmpty then
        let (body, _) ← lowerContractItems items
        `(
          def $specId : ProofForge.Contract.ContractSpec :=
            ProofForge.Contract.Surface.contract $nameLit $body

          def $moduleId : ProofForge.IR.Module :=
            ($specId).module
        )
      else if extItems.isEmpty then
        let baseSpec ← mkComposeBaseSpec nameLit composeMods
        `(
          def $specId : ProofForge.Contract.ContractSpec := $baseSpec

          def $moduleId : ProofForge.IR.Module :=
            ($specId).module
        )
      else
        let baseSpec ← mkComposeBaseSpec nameLit composeMods
        let (extBody, _) ← lowerContractItems extItems
        `(
          def $specId : ProofForge.Contract.ContractSpec :=
            ProofForge.Contract.Compose.mergeExtension $nameLit $baseSpec
              (ProofForge.Contract.Surface.contract $nameLit $extBody)

          def $moduleId : ProofForge.IR.Module :=
            ($specId).module
        )

  | `(contract_mixin $_name:ident do $items:contractItem*) => do
      let (body, _) ← lowerContractItems items
      let mixinId : TSyntax `ident := ⟨mkIdent `mixin⟩
      `(
        def $mixinId : ModuleM Unit := $body
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

def pathReadRole [ToExpr α] [ToExpr β]
    (mapRef : ProofForge.Contract.Surface.MapRef) (roleKey : α) (accountKey : β) :
    ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.pathRead mapRef.id
    (ProofForge.Contract.Surface.allowancePath (expr roleKey) (expr accountKey))

def pathWriteRole [ToExpr α] [ToExpr β] [ToExpr γ]
    (mapRef : ProofForge.Contract.Surface.MapRef) (roleKey : α) (accountKey : β)
    (mapValue : γ) : EntryM Unit :=
  ProofForge.Contract.Surface.pathWrite mapRef.id
    (ProofForge.Contract.Surface.allowancePath (expr roleKey) (expr accountKey)) (expr mapValue)

def pathRead2 [ToExpr α] [ToExpr β]
    (mapRef : ProofForge.Contract.Surface.MapRef) (outerKey : α) (innerKey : β) :
    ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.pathRead mapRef.id
    (ProofForge.Contract.Surface.allowancePath (expr outerKey) (expr innerKey))

def pathWrite2 [ToExpr α] [ToExpr β] [ToExpr γ]
    (mapRef : ProofForge.Contract.Surface.MapRef) (outerKey : α) (innerKey : β)
    (mapValue : γ) : EntryM Unit :=
  ProofForge.Contract.Surface.pathWrite mapRef.id
    (ProofForge.Contract.Surface.allowancePath (expr outerKey) (expr innerKey)) (expr mapValue)

def caller : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.caller

def callerHash : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.callerHash

def nativeValue : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.nativeValue

def hash4 (a b c d : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.hash4 a b c d

def create2Deploy (callValue salt : ProofForge.IR.Expr) (initCodeHex : String) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.create2Deploy callValue salt initCodeHex

macro "array_get " arr:ident idx:term : term => `(ProofForge.Contract.Source.arrayGet $arr $idx)

end ProofForge.Contract.Source
