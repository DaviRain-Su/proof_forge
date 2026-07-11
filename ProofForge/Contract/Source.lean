/-
# `contract_source` authoring surface

Portable-default product path for Shared examples: import this module only.

Solana account / PDA / CPI / allocator syntax is **not** lowered in this module
(PF-P1-05). Portable product code imports only this file. Solana extensions require:

```lean
import ProofForge.Contract.Source.Solana
```

NEAR Promise chaining (`nearPromiseThen` / result decode) is opt-in via:

```lean
import ProofForge.Contract.Source.Near
```

Portable Shared files must not import `Source.Solana` or `Source.Near`
(`just portable-default`). Prefer `declareRemote` + `remoteCallRef` for
portable cross-contract intent (logical peers; no host string-pool APIs;
no bare pool indices).
-/
import Lean
import ProofForge.Contract.Surface
import ProofForge.Contract.Protocol

set_option hygiene false

namespace ProofForge.Contract.Source

open Lean
open ProofForge.IR

/-- Machine-readable `contract_source` surface version (PF-P1-05). Bump when
entry arity, item syntax, or diagnostic codes change incompatibly. -/
def sourceDslVersion : String := "contract_source-v1"

abbrev ScalarRef := ProofForge.Contract.Surface.ScalarRef
abbrev MapRef := ProofForge.Contract.Surface.MapRef
abbrev BindingRef := ProofForge.Contract.Surface.BindingRef
abbrev MethodRef := ProofForge.Contract.Surface.MethodRef
abbrev EventRef := ProofForge.Contract.Surface.EventRef
abbrev EventField := ProofForge.Contract.Surface.EventField
abbrev ModuleM := ProofForge.Contract.Surface.ModuleM
abbrev EntryM := ProofForge.Contract.Surface.EntryM
abbrev ContractSpec := ProofForge.Contract.ContractSpec
abbrev ExternalToken := ProofForge.Contract.Protocol.ExternalToken
abbrev ExternalVault := ProofForge.Contract.Protocol.ExternalVault
abbrev RemoteRef := ProofForge.Contract.Surface.RemoteRef

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

/-- Portable external FT peer (product protocol intent; no `Protocols.*` import). -/
def declareExternalToken (peerId : String) : ModuleM ExternalToken :=
  ProofForge.Contract.Protocol.declareExternalToken peerId

def externalTokenTransfer [ToExpr α] [ToExpr β] (token : ExternalToken) (to : α) (amount : β) :
    ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalTokenTransfer token (expr to) (expr amount)

def externalTokenApprove [ToExpr α] [ToExpr β] (token : ExternalToken) (spender : α) (amount : β) :
    ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalTokenApprove token (expr spender) (expr amount)

def externalTokenTransferFrom [ToExpr α] [ToExpr β] [ToExpr γ]
    (token : ExternalToken) (fromAddr : α) (to : β) (amount : γ) : ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalTokenTransferFrom token (expr fromAddr) (expr to) (expr amount)

def externalTokenBalanceOf [ToExpr α] (token : ExternalToken) (account : α) : ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalTokenBalanceOf token (expr account)

def externalTokenTotalSupply (token : ExternalToken) : ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalTokenTotalSupply token

def registerAccountId (accountId : String) : ModuleM ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.registerAccountId accountId

def declareExternalVault (peerId : String) : ModuleM ExternalVault :=
  ProofForge.Contract.Protocol.declareExternalVault peerId

def externalVaultDeposit [ToExpr α] [ToExpr β] (vault : ExternalVault) (assets : α) (receiver : β) :
    ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalVaultDeposit vault (expr assets) (expr receiver)

def externalVaultWithdraw [ToExpr α] [ToExpr β] [ToExpr γ]
    (vault : ExternalVault) (assets : α) (receiver : β) (owner : γ) : ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalVaultWithdraw vault (expr assets) (expr receiver) (expr owner)

def externalVaultConvertToShares [ToExpr α] (vault : ExternalVault) (assets : α) : ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalVaultConvertToShares vault (expr assets)

def externalVaultConvertToAssets [ToExpr α] (vault : ExternalVault) (shares : α) : ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalVaultConvertToAssets vault (expr shares)

def externalVaultTotalAssets (vault : ExternalVault) : ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalVaultTotalAssets vault

def externalVaultAsset (vault : ExternalVault) : ProofForge.IR.Expr :=
  ProofForge.Contract.Protocol.externalVaultAsset vault

def remoteCallRef (remote : RemoteRef) (args : Array ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.remoteCallRef remote args

declare_syntax_cat contractItem
declare_syntax_cat entryStmt
declare_syntax_cat solanaSeed
declare_syntax_cat solanaSignerSeed

scoped syntax "state " ident " : " term : contractItem
scoped syntax "mapping " ident " from " term " to " term : contractItem
scoped syntax "binding " ident " : " term : contractItem
scoped syntax "event " ident : contractItem
scoped syntax "event " ident " abi " term : contractItem
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
scoped syntax "cpi " ident " associated_token_create" "(" ident ", " ident ", " ident ", " ident ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" : contractItem
scoped syntax "cpi " ident " associated_token_create_idempotent" "(" ident ", " ident ", " ident ", " ident ")"
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
scoped syntax "quint_invariant " ident " := " str : contractItem
scoped syntax "quint_liveness " ident " := " str : contractItem
scoped syntax "lean_invariant " ident " := " str : contractItem
scoped syntax "remote " ident str str ";" : contractItem
/-- Product protocol intent: external fungible token peer (no Protocols import). -/
scoped syntax "external_token " ident str ";" : contractItem
/-- Product protocol intent: external ERC-4626 vault peer. -/
scoped syntax "external_vault " ident str ";" : contractItem
scoped syntax "do " term ";" : contractItem
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
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine entryStmt* : contractItem

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
scoped syntax "invoke " ident " associated_token_create" "(" ident ", " ident ", " ident ", " ident ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" ";" : entryStmt
scoped syntax "invoke " ident " associated_token_create_idempotent" "(" ident ", " ident ", " ident ", " ident ")"
  " signer_seeds " "[" solanaSignerSeed,* "]" ";" : entryStmt
scoped syntax "realloc " ident " to " term ";" : entryStmt
scoped syntax "init_transfer_hook_extra_meta" "(" ident ", " ident ")" ";" : entryStmt
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

def identNameLit (name : TSyntax `ident) : TSyntax `term :=
  ⟨Syntax.mkStrLit name.getId.toString⟩

def mixinTerm (mod : TSyntax `ident) : MacroM (TSyntax `term) := do
  let mixId : TSyntax `ident := ⟨mkIdent (mod.getId ++ `mixin)⟩
  `(term| $mixId)

def chainTerms (terms : Array (TSyntax `term)) : MacroM (TSyntax `term) := do
  let mut acc ← `(pure ())
  for term in terms.reverse do
    acc ← `($term *> $acc)
  return acc

def composeSpecTerm (mod : TSyntax `ident) : MacroM (TSyntax `term) := do
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

def mkComposeBaseSpec (nameLit : TSyntax `term) (mods : Array (TSyntax `ident)) :
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

def partitionContractItems (items : Array (TSyntax `contractItem)) :
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

def mkParamLet (name : TSyntax `ident) (type : TSyntax `term)
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

def mkBindingLet (name : TSyntax `ident) (type : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) :=
  mkParamLet name type body

def mkMapLet (name : TSyntax `ident) (keyType valueType : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Surface.MapRef :=
      { id := $nameLit, keyType := $keyType, valueType := $valueType }
    $body)

def mkStateLet (name : TSyntax `ident) (type : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Surface.ScalarRef :=
      ProofForge.Contract.Surface.slot $nameLit $type
    $body)

def mkEventLet (name : TSyntax `ident)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Surface.EventRef :=
      ProofForge.Contract.Surface.event $nameLit
    $body)

/-- Optional Solana (or other extension) entry-stmt handler.
Returns `some newAcc` when the statement was consumed. -/
abbrev EntryStmtExt :=
  TSyntax `entryStmt → TSyntax `term → MacroM (Option (TSyntax `term))

def noEntryStmtExt : EntryStmtExt := fun _ _ => pure none

partial def lowerEntryBody (stmts : Array (TSyntax `entryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) :
    MacroM (TSyntax `term) := do
  let mut acc ← `(pure ())
  for stmt in stmts.reverse do
    match ← ext stmt acc with
    | some acc' =>
        acc := acc'
    | none =>
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
          Macro.throwErrorAt stmt
            s!"unsupported contract source statement (dsl {sourceDslVersion}); \
check entry body syntax or import ProofForge.Contract.Source.Solana for Solana extensions"
  return acc

def surfaceEntryFn (isView : Bool) : MacroM (TSyntax `term) :=
  if isView then
    `(ProofForge.Contract.Surface.view)
  else
    `(ProofForge.Contract.Surface.entry)

def mkEntry0 (name : TSyntax `ident) (retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `entryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  `($entryFn
      (ProofForge.Contract.Surface.method $nameLit #[] $retTy)
      $body)

def mkEntry1 (name p1 : TSyntax `ident) (t1 retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `entryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← `($entryFn
        (ProofForge.Contract.Surface.method $nameLit #[$p1] $retTy)
        $body))

def mkEntry2 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `entryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← `($entryFn
          (ProofForge.Contract.Surface.method $nameLit #[$p1, $p2] $retTy)
          $body)))

def mkEntry3 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 retTy : TSyntax `term)
    (isView : Bool)
    (stmts : Array (TSyntax `entryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← mkParamLet p3 t3
        (← `($entryFn
            (ProofForge.Contract.Surface.method $nameLit #[$p1, $p2, $p3] $retTy)
            $body))))

def mkEntry4 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 : TSyntax `term)
    (p4 : TSyntax `ident) (t4 retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `entryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← mkParamLet p3 t3
        (← mkParamLet p4 t4
          (← `($entryFn
              (ProofForge.Contract.Surface.method $nameLit #[$p1, $p2, $p3, $p4] $retTy)
              $body)))))

def mkEntry5 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 : TSyntax `term)
    (p4 : TSyntax `ident) (t4 : TSyntax `term) (p5 : TSyntax `ident) (t5 retTy : TSyntax `term)
    (isView : Bool)
    (stmts : Array (TSyntax `entryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← mkParamLet p3 t3
        (← mkParamLet p4 t4
          (← mkParamLet p5 t5
            (← `($entryFn
                (ProofForge.Contract.Surface.method $nameLit #[$p1, $p2, $p3, $p4, $p5] $retTy)
                $body))))))

def mkEntry6 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 : TSyntax `term)
    (p4 : TSyntax `ident) (t4 : TSyntax `term) (p5 : TSyntax `ident) (t5 : TSyntax `term)
    (p6 : TSyntax `ident) (t6 retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `entryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← mkParamLet p3 t3
        (← mkParamLet p4 t4
          (← mkParamLet p5 t5
            (← mkParamLet p6 t6
              (← `($entryFn
                  (ProofForge.Contract.Surface.method $nameLit #[$p1, $p2, $p3, $p4, $p5, $p6] $retTy)
                  $body)))))))

def mkEntry7 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 : TSyntax `term)
    (p4 : TSyntax `ident) (t4 : TSyntax `term) (p5 : TSyntax `ident) (t5 : TSyntax `term)
    (p6 : TSyntax `ident) (t6 : TSyntax `term) (p7 : TSyntax `ident) (t7 retTy : TSyntax `term)
    (isView : Bool)
    (stmts : Array (TSyntax `entryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← mkParamLet p3 t3
        (← mkParamLet p4 t4
          (← mkParamLet p5 t5
            (← mkParamLet p6 t6
              (← mkParamLet p7 t7
                (← `($entryFn
                    (ProofForge.Contract.Surface.method $nameLit
                      #[$p1, $p2, $p3, $p4, $p5, $p6, $p7] $retTy)
                    $body))))))))

structure LoweredItem where
  action? : Option (TSyntax `term) := none
  binder : TSyntax `term → MacroM (TSyntax `term) := fun body => pure body

def strLitValue (stx : TSyntax `str) : MacroM String := do
  match stx.raw.isStrLit? with
  | some s => pure s
  | none => Macro.throwError "expected string literal for quint_invariant expression"

abbrev ContractItemExt := TSyntax `contractItem → MacroM (Option LoweredItem)

def noContractItemExt : ContractItemExt := fun _ => pure none

def lowerItem (item : TSyntax `contractItem)
    (entryExt : EntryStmtExt := noEntryStmtExt)
    (itemExt : ContractItemExt := noContractItemExt) : MacroM LoweredItem := do
  match ← itemExt item with
  | some lowered => return lowered
  | none => pure ()
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
  | `(contractItem| quint_invariant $name:ident := $expr:str) =>
      let nameLit := identNameLit name
      let exprStr ← strLitValue expr
      let exprLit := Syntax.mkStrLit exprStr
      let action ← `(ProofForge.Contract.Surface.declareQuintInvariant $nameLit $exprLit)
      return { action? := some action }
  | `(contractItem| quint_liveness $name:ident := $expr:str) =>
      let nameLit := identNameLit name
      let exprStr ← strLitValue expr
      let exprLit := Syntax.mkStrLit exprStr
      let action ← `(ProofForge.Contract.Surface.declareQuintLiveness $nameLit $exprLit)
      return { action? := some action }
  | `(contractItem| lean_invariant $name:ident := $predFnName:str) =>
      let nameLit := identNameLit name
      let predStr ← strLitValue predFnName
      let predLit := Syntax.mkStrLit predStr
      let action ← `(ProofForge.Contract.Surface.declareLeanInvariant $nameLit $predLit)
      return { action? := some action }
  | `(contractItem| remote $name:ident $peer:str $method:str;) => do
      let peerS ← strLitValue peer
      let methodS ← strLitValue method
      let peerLit : TSyntax `term := quote peerS
      let methodLit : TSyntax `term := quote methodS
      return {
        binder := fun body =>
          `(bind (ProofForge.Contract.Surface.declareRemote $peerLit $methodLit)
              (fun ($name : ProofForge.Contract.Surface.RemoteRef) => $body))
      }
  | `(contractItem| external_token $name:ident $peer:str;) => do
      let peerS ← strLitValue peer
      let peerLit : TSyntax `term := quote peerS
      return {
        binder := fun body =>
          `(bind (ProofForge.Contract.Protocol.declareExternalToken $peerLit)
              (fun ($name : ProofForge.Contract.Protocol.ExternalToken) => $body))
      }
  | `(contractItem| external_vault $name:ident $peer:str;) => do
      let peerS ← strLitValue peer
      let peerLit : TSyntax `term := quote peerS
      return {
        binder := fun body =>
          `(bind (ProofForge.Contract.Protocol.declareExternalVault $peerLit)
              (fun ($name : ProofForge.Contract.Protocol.ExternalVault) => $body))
      }
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
  | `(contractItem| event $name:ident abi $fields:term) =>
      let nameLit := identNameLit name
      let action ← `(ProofForge.Contract.Surface.declareEventAbi $nameLit $fields)
      return { action? := some action, binder := mkEventLet name }
  | `(contractItem| event $name:ident) =>
      return { binder := mkEventLet name }
  | `(contractItem| use $action:term) =>
      return { action? := some action }
  | `(contractItem| import $mod:ident;) =>
      return { action? := some (← mixinTerm mod) }
  | `(contractItem| open $mod:ident;) =>
      return { action? := some (← mixinTerm mod) }
  | `(contractItem| entry $name:ident do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry0 name (← `(.unit)) false stmts entryExt) }
  | `(contractItem| entry $name:ident returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry0 name retTy false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 (← `(.unit)) false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 retTy false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 (← `(.unit)) false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 retTy false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 (← `(.unit)) false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 retTy false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry4 name p1 t1 p2 t2 p3 t3 p4 t4 (← `(.unit)) false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry4 name p1 t1 p2 t2 p3 t3 p4 t4 retTy false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry5 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 (← `(.unit)) false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry5 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 retTy false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry6 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 (← `(.unit)) false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry6 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 retTy false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term, $p7:ident : $t7:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry7 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 p7 t7 (← `(.unit)) false stmts entryExt) }
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term, $p7:ident : $t7:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry7 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 p7 t7 retTy false stmts entryExt) }
  | `(contractItem| query $name:ident returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry0 name retTy true stmts entryExt) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 retTy true stmts entryExt) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 retTy true stmts entryExt) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 retTy true stmts entryExt) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry4 name p1 t1 p2 t2 p3 t3 p4 t4 retTy true stmts entryExt) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry5 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 retTy true stmts entryExt) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry6 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 retTy true stmts entryExt) }
  | `(contractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term, $p7:ident : $t7:term) returns($retTy:term) do $stmts:entryStmt*) =>
      return { action? := some (← mkEntry7 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 p7 t7 retTy true stmts entryExt) }
  | _ =>
      Macro.throwErrorAt item
        s!"unsupported contract source item (dsl {sourceDslVersion}); \
check entry arity (0–7 params), item syntax, or import ProofForge.Contract.Source.Solana"

def lowerContractItems (items : Array (TSyntax `contractItem))
    (entryExt : EntryStmtExt := noEntryStmtExt)
    (itemExt : ContractItemExt := noContractItemExt) :
    MacroM (TSyntax `term × Array LoweredItem) := do
  let mut loweredItems : Array LoweredItem := #[]
  let mut actions : Array (TSyntax `term) := #[]
  for item in items do
    let lowered ← lowerItem item entryExt itemExt
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

/-- This contract / program id (`address(this)` · program_id · current_account).
Portable triad after HostEnv U1.2 (Solana: sha256(program_id) limb0). -/
def contractId : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.contractId

def nativeValue : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.nativeValue

def hash4 (a b c d : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.hash4 a b c d

def create2Deploy (callValue salt : ProofForge.IR.Expr) (initCodeHex : String) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.create2Deploy callValue salt initCodeHex

macro "array_get " arr:ident idx:term : term => `(ProofForge.Contract.Source.arrayGet $arr $idx)

end ProofForge.Contract.Source
