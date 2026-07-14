/-
# Deletion-only Legacy source implementation

This module preserves unmigrated callers while they are rewritten to the
direct Authored frontend. It is not a public authoring surface, is never
discovered by the public loader, and must not receive new features. A-CUT3
migrates its remaining callers; A-CUT5 deletes the module.
-/
import Lean
import ProofForge.Contract.Source.Internal
import ProofForge.Contract.Protocol

set_option hygiene false

namespace ProofForge.Contract.Source.Legacy

open Lean
open ProofForge.IR

/-- Stable machine-readable identity for the public `contract_source` format.
Schema evolution is tracked by schema metadata, not parallel source routes. -/
def sourceDslVersion : String := "legacy-contract-source"

abbrev ScalarRef := ProofForge.Contract.Source.Internal.ScalarRef
abbrev MapRef := ProofForge.Contract.Source.Internal.MapRef
abbrev BindingRef := ProofForge.Contract.Source.Internal.BindingRef
abbrev MethodRef := ProofForge.Contract.Source.Internal.MethodRef
abbrev EventRef := ProofForge.Contract.Source.Internal.EventRef
abbrev EventField := ProofForge.Contract.Source.Internal.EventField
abbrev ModuleM := ProofForge.Contract.Source.Internal.ModuleM
abbrev EntryM := ProofForge.Contract.Source.Internal.EntryM
abbrev ContractSpec := ProofForge.Contract.ContractSpec
abbrev ExternalToken := ProofForge.Contract.Protocol.ExternalToken
abbrev ExternalVault := ProofForge.Contract.Protocol.ExternalVault
abbrev RemoteRef := ProofForge.Contract.Source.Internal.RemoteRef

/-! Public authoring helpers live under the single `Contract.Source` API.
`Source.Internal` owns their implementation and is not a second authoring
surface. -/
export ProofForge.Contract.Source.Internal (
  acquireLock add allowancePath assertCondition bind binding bindingWithAbi
  bindingWithAbiWord boolOr cast declareConstructorInitBinding
  declareConstructorParam declareEventAbi declareLeanInvariant
  declareQuintInvariant declareQuintLiveness declareRemote declareRemoteUnit
  div eip1967Implementation eip1967ImplementationId emit emitIndexed emitNamed
  entry entryWithMutability eq event fieldOf ge le mapGet mapKey mapSet mapState
  markPayable method methodWithReturnAbi methodWithSelector mul nativeTransfer
  ne pathRead pathWrite peerHandle read ref releaseLock remoteCall requireEq
  requireGe requireNe requireNonZero requireNotPaused requireOwner
  requireOwnerHash requirePaused requireRole requireUnlocked requireZero ret
  scalar setProxyPattern setUpgradePolicy signer slot sub u32 view whenPositive
  whenZero write
)

def checkpointId : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.checkpointId

def timestamp : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.timestamp

def epochHeight : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.epochHeight

def randomSeed : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.randomSeed

def u64 (value : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.u64 value

def u128 (value : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.u128 value

def boolLit (value : Bool) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.bool value

def emitIndexedEvent (eventRef : ProofForge.Contract.Source.Internal.EventRef)
    (indexedFields dataFields : Array ProofForge.Contract.Source.Internal.EventField) : EntryM Unit :=
  ProofForge.Contract.Source.Internal.emitIndexed eventRef indexedFields dataFields

class ToExpr (α : Type) where
  toExpr : α → ProofForge.IR.Expr

instance : ToExpr ProofForge.IR.Expr where
  toExpr value := value

instance : ToExpr ProofForge.Contract.Source.Internal.BindingRef where
  toExpr binding := ProofForge.Contract.Source.Internal.ref binding

instance : ToExpr ProofForge.Contract.Source.Internal.ScalarRef where
  toExpr slot := ProofForge.Contract.Source.Internal.read slot

instance : ToExpr Nat where
  toExpr value := u64 value

def expr [ToExpr α] (value : α) : ProofForge.IR.Expr :=
  ToExpr.toExpr value

def bindValue [ToExpr α] (binding : ProofForge.Contract.Source.Internal.BindingRef)
    (value : α) : EntryM Unit :=
  ProofForge.Contract.Source.Internal.bind binding (expr value)

def writeValue [ToExpr α] (slot : ProofForge.Contract.Source.Internal.ScalarRef)
    (value : α) : EntryM Unit :=
  ProofForge.Contract.Source.Internal.write slot (expr value)

def retValue [ToExpr α] (value : α) : EntryM Unit :=
  ProofForge.Contract.Source.Internal.ret (expr value)

def addValue [ToExpr α] [ToExpr β] (lhs : α) (rhs : β) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.add (expr lhs) (expr rhs)

def subValue [ToExpr α] [ToExpr β] (lhs : α) (rhs : β) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.sub (expr lhs) (expr rhs)

def mulValue [ToExpr α] [ToExpr β] (lhs : α) (rhs : β) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.mul (expr lhs) (expr rhs)

def divValue [ToExpr α] [ToExpr β] (lhs : α) (rhs : β) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.div (expr lhs) (expr rhs)

def u64Array3 [ToExpr α] [ToExpr β] [ToExpr γ] (a : α) (b : β) (c : γ) : ProofForge.IR.Expr :=
  .arrayLit .u64 #[expr a, expr b, expr c]

def arrayGet [ToExpr α] [ToExpr β] (arr : α) (index : β) : ProofForge.IR.Expr :=
  .arrayGet (expr arr) (expr index)

scoped infixl:65 " +! " => addValue
scoped infixl:65 " -! " => subValue
scoped infixl:70 " *! " => mulValue
scoped infixl:70 " /! " => divValue

class ToField (α : Type) where
  toField : α → ProofForge.Contract.Source.Internal.EventField

instance : ToField ProofForge.Contract.Source.Internal.BindingRef where
  toField binding := ProofForge.Contract.Source.Internal.fieldOf binding

instance : ToField ProofForge.Contract.Source.Internal.ScalarRef where
  toField slot := ProofForge.Contract.Source.Internal.fieldAs slot (expr slot)

def field [ToField α] (value : α) : ProofForge.Contract.Source.Internal.EventField :=
  ToField.toField value

def fieldAsName (name : String) [ToExpr α] (value : α) : ProofForge.Contract.Source.Internal.EventField :=
  ProofForge.Contract.Source.Internal.field name (expr value)

def fieldValue [ToExpr α] (name : String) (value : α) :
    ProofForge.Contract.Source.Internal.EventField :=
  ProofForge.Contract.Source.Internal.field name (expr value)

def fieldAs [ToExpr α] (slot : ProofForge.Contract.Source.Internal.ScalarRef)
    (value : α) : ProofForge.Contract.Source.Internal.EventField :=
  ProofForge.Contract.Source.Internal.fieldAs slot (expr value)

def emitEvent (eventRef : ProofForge.Contract.Source.Internal.EventRef)
    (fields : Array ProofForge.Contract.Source.Internal.EventField) : EntryM Unit :=
  ProofForge.Contract.Source.Internal.emit eventRef fields

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
  ProofForge.Contract.Source.Internal.remoteCallRef remote args

declare_syntax_cat legacyContractItem
declare_syntax_cat legacyEntryStmt

scoped syntax "state " ident " : " term : legacyContractItem
scoped syntax "mapping " ident " from " term " to " term : legacyContractItem
scoped syntax "binding " ident " : " term : legacyContractItem
scoped syntax "event " ident : legacyContractItem
scoped syntax "event " ident " abi " term : legacyContractItem
scoped syntax "use " term : legacyContractItem
scoped syntax "compose " ident ";" : legacyContractItem
scoped syntax "upgrade_policy_immutable;" : legacyContractItem
scoped syntax "upgrade_policy_authority " ident ";" : legacyContractItem
scoped syntax "proxy_pattern_uups;" : legacyContractItem
scoped syntax "proxy_pattern_transparent;" : legacyContractItem
scoped syntax "import " ident ";" : legacyContractItem
scoped syntax "open " ident ";" : legacyContractItem
scoped syntax "do " term ";" : legacyContractItem
scoped syntax "constructor_param " ident " : " term ";" : legacyContractItem
scoped syntax "constructor_param " ident " : " "cstring" ";" : legacyContractItem
scoped syntax "constructor_param " ident " : " "cbytes" ";" : legacyContractItem
scoped syntax "constructor_param " ident " : " "u256array" ";" : legacyContractItem
scoped syntax "quint_invariant " ident " := " str : legacyContractItem
scoped syntax "quint_liveness " ident " := " str : legacyContractItem
scoped syntax "lean_invariant " ident " := " str : legacyContractItem
scoped syntax "remote " ident str str ";" : legacyContractItem
/-- Product protocol intent: external fungible token peer (no Protocols import). -/
scoped syntax "external_token " ident str ";" : legacyContractItem
/-- Product protocol intent: external ERC-4626 vault peer. -/
scoped syntax "external_vault " ident str ";" : legacyContractItem
scoped syntax "do " term ";" : legacyContractItem
scoped syntax "entry " ident " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "entry " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "query " ident " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "query " ident "(" ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem
scoped syntax "query " ident "(" ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ", " ident " : " term ")" " returns" "(" term ")" " do" ppLine legacyEntryStmt* : legacyContractItem

scoped syntax "let " ident " : " term " := " term ";" : legacyEntryStmt
scoped syntax ident " := " term ";" : legacyEntryStmt
scoped syntax "emit " ident term ";" : legacyEntryStmt
scoped syntax "emit " ident " indexed " term " data " term ";" : legacyEntryStmt
scoped syntax "return " term ";" : legacyEntryStmt

scoped syntax "do " term ";" : legacyEntryStmt
scoped syntax "accepts_callvalue;" : legacyEntryStmt
scoped syntax "sendto " ident ident ";" : legacyEntryStmt
scoped syntax "guard_owner " ident ";" : legacyEntryStmt
scoped syntax "guard_role " ident ";" : legacyEntryStmt
scoped syntax "guard_not_paused " ident ";" : legacyEntryStmt
scoped syntax "guard_paused " ident ";" : legacyEntryStmt
scoped syntax "guard_unlocked " ident ";" : legacyEntryStmt
scoped syntax "acquire_lock " ident ";" : legacyEntryStmt
scoped syntax "release_lock " ident ";" : legacyEntryStmt
scoped syntax "fixedu64x3 " ident "(" term ", " term ", " term ")" ";" : legacyEntryStmt

scoped syntax "contract_source " ident " do" ppLine legacyContractItem* : command
scoped syntax "contract_mixin " ident " do" ppLine legacyContractItem* : command

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

def partitionContractItems (items : Array (TSyntax `legacyContractItem)) :
    MacroM (Array (TSyntax `ident) × Array (TSyntax `legacyContractItem)) := do
  let mut composeMods : Array (TSyntax `ident) := #[]
  let mut extItems : Array (TSyntax `legacyContractItem) := #[]
  for item in items do
    match item with
    | `(legacyContractItem| compose $mod:ident;) =>
        composeMods := composeMods.push mod
    | _ =>
        extItems := extItems.push item
  return (composeMods, extItems)

def mkParamLet (name : TSyntax `ident) (type : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  match type with
  | `(.address) =>
    `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
        ProofForge.Contract.Source.Internal.bindingWithAbi $nameLit (.u64) "address"
      $body)
  | `(.bytes4) =>
    `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
        ProofForge.Contract.Source.Internal.bindingWithAbi $nameLit (.u64) "bytes4"
      $body)
  | `(.hash) =>
    `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
        ProofForge.Contract.Source.Internal.bindingWithAbi $nameLit (.hash) "bytes32"
      $body)
  | `(.bytes32) =>
    `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
        ProofForge.Contract.Source.Internal.bindingWithAbi $nameLit (.hash) "bytes32"
      $body)
  | _ =>
    `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
        ProofForge.Contract.Source.Internal.binding $nameLit $type
      $body)

def mkBindingLet (name : TSyntax `ident) (type : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) :=
  mkParamLet name type body

def mkMapLet (name : TSyntax `ident) (keyType valueType : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Source.Internal.MapRef :=
      { id := $nameLit, keyType := $keyType, valueType := $valueType }
    $body)

def mkStateLet (name : TSyntax `ident) (type : TSyntax `term)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Source.Internal.ScalarRef :=
      ProofForge.Contract.Source.Internal.slot $nameLit $type
    $body)

def mkEventLet (name : TSyntax `ident)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Contract.Source.Internal.EventRef :=
      ProofForge.Contract.Source.Internal.event $nameLit
    $body)

/-- Optional Solana (or other extension) entry-stmt handler.
Returns `some newAcc` when the statement was consumed. -/
abbrev EntryStmtExt :=
  TSyntax `legacyEntryStmt → TSyntax `term → MacroM (Option (TSyntax `term))

def noEntryStmtExt : EntryStmtExt := fun _ _ => pure none

partial def lowerEntryBody (stmts : Array (TSyntax `legacyEntryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) :
    MacroM (TSyntax `term) := do
  let mut acc ← `(pure ())
  for stmt in stmts.reverse do
    match ← ext stmt acc with
    | some acc' =>
        acc := acc'
    | none =>
      match stmt with
      | `(legacyEntryStmt| let $name:ident : $type:term := $value:term;) =>
          let nameLit := identNameLit name
          acc ←
            match type with
            | `(.address) =>
              `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
                  ProofForge.Contract.Source.Internal.bindingWithAbi $nameLit (.u64) "address"
                ProofForge.Contract.Source.Legacy.bindValue $name $value *> $acc)
            | `(.bytes4) =>
              `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
                  ProofForge.Contract.Source.Internal.bindingWithAbi $nameLit (.u64) "bytes4"
                ProofForge.Contract.Source.Legacy.bindValue $name $value *> $acc)
            | `(.hash) =>
              `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
                  ProofForge.Contract.Source.Internal.bindingWithAbi $nameLit (.hash) "bytes32"
                ProofForge.Contract.Source.Legacy.bindValue $name $value *> $acc)
            | `(.bytes32) =>
              `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
                  ProofForge.Contract.Source.Internal.bindingWithAbi $nameLit (.hash) "bytes32"
                ProofForge.Contract.Source.Legacy.bindValue $name $value *> $acc)
            | _ =>
              `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
                  ProofForge.Contract.Source.Internal.binding $nameLit $type
                ProofForge.Contract.Source.Legacy.bindValue $name $value *> $acc)
      | `(legacyEntryStmt| $slot:ident := $value:term;) =>
          acc ← `(ProofForge.Contract.Source.Legacy.writeValue $slot $value *> $acc)
      | `(legacyEntryStmt| emit $eventRef:ident $fields:term;) =>
          acc ← `(ProofForge.Contract.Source.Legacy.emitEvent $eventRef $fields *> $acc)
      | `(legacyEntryStmt| emit $eventRef:ident indexed $indexedFields:term data $dataFields:term;) =>
          acc ← `(ProofForge.Contract.Source.Legacy.emitIndexedEvent $eventRef $indexedFields $dataFields *> $acc)
      | `(legacyEntryStmt| return $value:term;) =>
          acc ← `(ProofForge.Contract.Source.Legacy.retValue $value *> $acc)
      | `(legacyEntryStmt| do $action:term;) =>
          acc ← `($action *> $acc)
      | `(legacyEntryStmt| accepts_callvalue;) =>
          acc ← `(ProofForge.Contract.Source.Internal.markPayable *> $acc)
      | `(legacyEntryStmt| sendto $recipient:ident $amount:ident;) =>
          acc ← `(ProofForge.Contract.Source.Internal.nativeTransfer (ProofForge.Contract.Source.Legacy.expr $recipient) (ProofForge.Contract.Source.Legacy.expr $amount) *> $acc)
      | `(legacyEntryStmt| guard_owner $slot:ident;) =>
          acc ← `(ProofForge.Contract.Source.Internal.requireOwner $slot *> $acc)
      | `(legacyEntryStmt| guard_role $role:ident;) =>
          acc ←
            `(ProofForge.Contract.Source.Internal.requireRole roleMembers (ProofForge.Contract.Source.Legacy.expr $role)
                ProofForge.Contract.Source.Internal.caller *> $acc)
      | `(legacyEntryStmt| guard_not_paused $slot:ident;) =>
          acc ← `(ProofForge.Contract.Source.Internal.requireNotPaused $slot *> $acc)
      | `(legacyEntryStmt| guard_paused $slot:ident;) =>
          acc ← `(ProofForge.Contract.Source.Internal.requirePaused $slot *> $acc)
      | `(legacyEntryStmt| guard_unlocked $slot:ident;) =>
          acc ← `(ProofForge.Contract.Source.Internal.requireUnlocked $slot *> $acc)
      | `(legacyEntryStmt| acquire_lock $slot:ident;) =>
          acc ← `(ProofForge.Contract.Source.Internal.acquireLock $slot *> $acc)
      | `(legacyEntryStmt| release_lock $slot:ident;) =>
          acc ← `(ProofForge.Contract.Source.Internal.releaseLock $slot *> $acc)
      | `(legacyEntryStmt| fixedu64x3 $name:ident ($a:term, $b:term, $c:term);) =>
          let nameLit := identNameLit name
          acc ←
            `(let $name : ProofForge.Contract.Source.Internal.BindingRef :=
                ProofForge.Contract.Source.Internal.binding $nameLit (.fixedArray .u64 3)
              ProofForge.Contract.Source.Legacy.bindValue $name (ProofForge.Contract.Source.Legacy.u64Array3 $a $b $c) *> $acc)
      | _ =>
          Macro.throwError
            s!"unsupported contract source statement (dsl {sourceDslVersion}); \
this statement is not portable. If it is a Solana-specific operation \
(PDA, CPI, realloc), import ProofForge.Contract.Source.Solana in a \
non-portable module. For portable cross-contract calls, use `remote` + `remoteCallRef`."
  return acc

def surfaceEntryFn (isView : Bool) : MacroM (TSyntax `term) :=
  if isView then
    `(ProofForge.Contract.Source.Internal.view)
  else
    `(ProofForge.Contract.Source.Internal.entry)

def mkEntry0 (name : TSyntax `ident) (retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `legacyEntryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  `($entryFn
      (ProofForge.Contract.Source.Internal.method $nameLit #[] $retTy)
      $body)

def mkEntry1 (name p1 : TSyntax `ident) (t1 retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `legacyEntryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← `($entryFn
        (ProofForge.Contract.Source.Internal.method $nameLit #[$p1] $retTy)
        $body))

def mkEntry2 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `legacyEntryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← `($entryFn
          (ProofForge.Contract.Source.Internal.method $nameLit #[$p1, $p2] $retTy)
          $body)))

def mkEntry3 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 retTy : TSyntax `term)
    (isView : Bool)
    (stmts : Array (TSyntax `legacyEntryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← mkParamLet p3 t3
        (← `($entryFn
            (ProofForge.Contract.Source.Internal.method $nameLit #[$p1, $p2, $p3] $retTy)
            $body))))

def mkEntry4 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 : TSyntax `term)
    (p4 : TSyntax `ident) (t4 retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `legacyEntryStmt))
    (ext : EntryStmtExt := noEntryStmtExt) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  let body ← lowerEntryBody stmts ext
  let entryFn ← surfaceEntryFn isView
  mkParamLet p1 t1
    (← mkParamLet p2 t2
      (← mkParamLet p3 t3
        (← mkParamLet p4 t4
          (← `($entryFn
              (ProofForge.Contract.Source.Internal.method $nameLit #[$p1, $p2, $p3, $p4] $retTy)
              $body)))))

def mkEntry5 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 : TSyntax `term)
    (p4 : TSyntax `ident) (t4 : TSyntax `term) (p5 : TSyntax `ident) (t5 retTy : TSyntax `term)
    (isView : Bool)
    (stmts : Array (TSyntax `legacyEntryStmt))
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
                (ProofForge.Contract.Source.Internal.method $nameLit #[$p1, $p2, $p3, $p4, $p5] $retTy)
                $body))))))

def mkEntry6 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 : TSyntax `term)
    (p4 : TSyntax `ident) (t4 : TSyntax `term) (p5 : TSyntax `ident) (t5 : TSyntax `term)
    (p6 : TSyntax `ident) (t6 retTy : TSyntax `term) (isView : Bool)
    (stmts : Array (TSyntax `legacyEntryStmt))
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
                  (ProofForge.Contract.Source.Internal.method $nameLit #[$p1, $p2, $p3, $p4, $p5, $p6] $retTy)
                  $body)))))))

def mkEntry7 (name p1 : TSyntax `ident) (t1 : TSyntax `term)
    (p2 : TSyntax `ident) (t2 : TSyntax `term) (p3 : TSyntax `ident) (t3 : TSyntax `term)
    (p4 : TSyntax `ident) (t4 : TSyntax `term) (p5 : TSyntax `ident) (t5 : TSyntax `term)
    (p6 : TSyntax `ident) (t6 : TSyntax `term) (p7 : TSyntax `ident) (t7 retTy : TSyntax `term)
    (isView : Bool)
    (stmts : Array (TSyntax `legacyEntryStmt))
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
                    (ProofForge.Contract.Source.Internal.method $nameLit
                      #[$p1, $p2, $p3, $p4, $p5, $p6, $p7] $retTy)
                    $body))))))))

structure LoweredItem where
  action? : Option (TSyntax `term) := none
  binder : TSyntax `term → MacroM (TSyntax `term) := fun body => pure body

def strLitValue (stx : TSyntax `str) : MacroM String := do
  match stx.raw.isStrLit? with
  | some s => pure s
  | none => Macro.throwError "expected string literal for quint_invariant expression"

abbrev ContractItemExt := TSyntax `legacyContractItem → MacroM (Option LoweredItem)

def noContractItemExt : ContractItemExt := fun _ => pure none

def lowerItem (item : TSyntax `legacyContractItem)
    (entryExt : EntryStmtExt := noEntryStmtExt)
    (itemExt : ContractItemExt := noContractItemExt) : MacroM LoweredItem := do
  match ← itemExt item with
  | some lowered => return lowered
  | none => pure ()
  match item with
  | `(legacyContractItem| upgrade_policy_immutable;) =>
      let action ← `(ProofForge.Contract.Source.Internal.setUpgradePolicy ProofForge.Contract.UpgradePolicy.immutable)
      return { action? := some action }
  | `(legacyContractItem| upgrade_policy_authority $keyRef:ident;) =>
      let keyLit := identNameLit keyRef
      let action ← `(ProofForge.Contract.Source.Internal.setUpgradePolicy (ProofForge.Contract.UpgradePolicy.authority $keyLit))
      return { action? := some action }
  | `(legacyContractItem| proxy_pattern_uups;) =>
      let action ← `(ProofForge.Contract.Source.Internal.setProxyPattern ProofForge.Contract.ProxyPattern.uups)
      return { action? := some action }
  | `(legacyContractItem| proxy_pattern_transparent;) =>
      let action ← `(ProofForge.Contract.Source.Internal.setProxyPattern ProofForge.Contract.ProxyPattern.transparent)
      return { action? := some action }
  | `(legacyContractItem| constructor_param $name:ident : "cstring";) =>
      let nameLit := identNameLit name
      let action ← `(ProofForge.Contract.Source.Internal.declareConstructorParam $nameLit "string")
      return { action? := some action }
  | `(legacyContractItem| constructor_param $name:ident : "cbytes";) =>
      let nameLit := identNameLit name
      let action ← `(ProofForge.Contract.Source.Internal.declareConstructorParam $nameLit "bytes")
      return { action? := some action }
  | `(legacyContractItem| constructor_param $name:ident : "u256array";) =>
      let nameLit := identNameLit name
      let action ← `(ProofForge.Contract.Source.Internal.declareConstructorParam $nameLit "uint256[]")
      return { action? := some action }
  | `(legacyContractItem| quint_invariant $name:ident := $expr:str) =>
      let nameLit := identNameLit name
      let exprStr ← strLitValue expr
      let exprLit := Syntax.mkStrLit exprStr
      let action ← `(ProofForge.Contract.Source.Internal.declareQuintInvariant $nameLit $exprLit)
      return { action? := some action }
  | `(legacyContractItem| quint_liveness $name:ident := $expr:str) =>
      let nameLit := identNameLit name
      let exprStr ← strLitValue expr
      let exprLit := Syntax.mkStrLit exprStr
      let action ← `(ProofForge.Contract.Source.Internal.declareQuintLiveness $nameLit $exprLit)
      return { action? := some action }
  | `(legacyContractItem| lean_invariant $name:ident := $predFnName:str) =>
      let nameLit := identNameLit name
      let predStr ← strLitValue predFnName
      let predLit := Syntax.mkStrLit predStr
      let action ← `(ProofForge.Contract.Source.Internal.declareLeanInvariant $nameLit $predLit)
      return { action? := some action }
  | `(legacyContractItem| remote $name:ident $peer:str $method:str;) => do
      let peerS ← strLitValue peer
      let methodS ← strLitValue method
      let peerLit : TSyntax `term := quote peerS
      let methodLit : TSyntax `term := quote methodS
      return {
        binder := fun body =>
          `(bind (ProofForge.Contract.Source.Internal.declareRemote $peerLit $methodLit)
              (fun ($name : ProofForge.Contract.Source.Internal.RemoteRef) => $body))
      }
  | `(legacyContractItem| external_token $name:ident $peer:str;) => do
      let peerS ← strLitValue peer
      let peerLit : TSyntax `term := quote peerS
      return {
        binder := fun body =>
          `(bind (ProofForge.Contract.Protocol.declareExternalToken $peerLit)
              (fun ($name : ProofForge.Contract.Protocol.ExternalToken) => $body))
      }
  | `(legacyContractItem| external_vault $name:ident $peer:str;) => do
      let peerS ← strLitValue peer
      let peerLit : TSyntax `term := quote peerS
      return {
        binder := fun body =>
          `(bind (ProofForge.Contract.Protocol.declareExternalVault $peerLit)
              (fun ($name : ProofForge.Contract.Protocol.ExternalVault) => $body))
      }
  | `(legacyContractItem| do $action:term;) =>
      return { action? := some action }
  | `(legacyContractItem| constructor_param $name:ident : $type:term;) =>
      let nameLit := identNameLit name
      match type with
      | `(.u64) =>
          let action ← `(ProofForge.Contract.Source.Internal.declareConstructorParam $nameLit "uint256")
          return { action? := some action }
      | `(.u32) =>
          let action ← `(ProofForge.Contract.Source.Internal.declareConstructorParam $nameLit "uint32")
          return { action? := some action }
      | `(.bool) =>
          let action ← `(ProofForge.Contract.Source.Internal.declareConstructorParam $nameLit "bool")
          return { action? := some action }
      | _ =>
          Macro.throwError s!"unsupported constructor_param type: {type.raw}"
  | `(legacyContractItem| state $name:ident : $type:term) =>
      let action ← `(ProofForge.Contract.Source.Internal.scalar $name)
      return { action? := some action, binder := mkStateLet name type }
  | `(legacyContractItem| mapping $name:ident from $keyType:term to $valueType:term) =>
      let action ← `(ProofForge.Contract.Source.Internal.mapState $name)
      return { action? := some action, binder := mkMapLet name keyType valueType }
  | `(legacyContractItem| binding $name:ident : $type:term) =>
      return { binder := mkBindingLet name type }
  | `(legacyContractItem| event $name:ident abi $fields:term) =>
      let nameLit := identNameLit name
      let action ← `(ProofForge.Contract.Source.Internal.declareEventAbi $nameLit $fields)
      return { action? := some action, binder := mkEventLet name }
  | `(legacyContractItem| event $name:ident) =>
      return { binder := mkEventLet name }
  | `(legacyContractItem| use $action:term) =>
      return { action? := some action }
  | `(legacyContractItem| import $mod:ident;) =>
      return { action? := some (← mixinTerm mod) }
  | `(legacyContractItem| open $mod:ident;) =>
      return { action? := some (← mixinTerm mod) }
  | `(legacyContractItem| entry $name:ident do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry0 name (← `(.unit)) false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry0 name retTy false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 (← `(.unit)) false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 retTy false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 (← `(.unit)) false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 retTy false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 (← `(.unit)) false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 retTy false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry4 name p1 t1 p2 t2 p3 t3 p4 t4 (← `(.unit)) false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry4 name p1 t1 p2 t2 p3 t3 p4 t4 retTy false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry5 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 (← `(.unit)) false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry5 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 retTy false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry6 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 (← `(.unit)) false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry6 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 retTy false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term, $p7:ident : $t7:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry7 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 p7 t7 (← `(.unit)) false stmts entryExt) }
  | `(legacyContractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term, $p7:ident : $t7:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry7 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 p7 t7 retTy false stmts entryExt) }
  | `(legacyContractItem| query $name:ident returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry0 name retTy true stmts entryExt) }
  | `(legacyContractItem| query $name:ident ($p1:ident : $t1:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry1 name p1 t1 retTy true stmts entryExt) }
  | `(legacyContractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry2 name p1 t1 p2 t2 retTy true stmts entryExt) }
  | `(legacyContractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry3 name p1 t1 p2 t2 p3 t3 retTy true stmts entryExt) }
  | `(legacyContractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry4 name p1 t1 p2 t2 p3 t3 p4 t4 retTy true stmts entryExt) }
  | `(legacyContractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry5 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 retTy true stmts entryExt) }
  | `(legacyContractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry6 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 retTy true stmts entryExt) }
  | `(legacyContractItem| query $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term, $p3:ident : $t3:term, $p4:ident : $t4:term, $p5:ident : $t5:term, $p6:ident : $t6:term, $p7:ident : $t7:term) returns($retTy:term) do $stmts:legacyEntryStmt*) =>
      return { action? := some (← mkEntry7 name p1 t1 p2 t2 p3 t3 p4 t4 p5 t5 p6 t6 p7 t7 retTy true stmts entryExt) }
  | _ =>
      Macro.throwErrorAt item
        s!"unsupported contract source item (dsl {sourceDslVersion}); \
check entry arity (0–7 params) and item syntax. Solana-specific items \
(account, pda, cpi, allocator) require `import ProofForge.Contract.Source.Solana` \
in a non-portable module."

def lowerContractItems (items : Array (TSyntax `legacyContractItem))
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
  | `(contract_source $name:ident do $items:legacyContractItem*) => do
      let (composeMods, extItems) ← partitionContractItems items
      let nameLit := identNameLit name
      let specId : TSyntax `ident := ⟨mkIdent `spec⟩
      let moduleId : TSyntax `ident := ⟨mkIdent `module⟩
      if composeMods.isEmpty then
        let (body, _) ← lowerContractItems items
        `(
          def $specId : ProofForge.Contract.ContractSpec :=
            ProofForge.Contract.Source.Internal.contract $nameLit $body

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
              (ProofForge.Contract.Source.Internal.contract $nameLit $extBody)

          def $moduleId : ProofForge.IR.Module :=
            ($specId).module
        )

  | `(contract_mixin $_name:ident do $items:legacyContractItem*) => do
      let (body, _) ← lowerContractItems items
      let mixinId : TSyntax `ident := ⟨mkIdent `mixin⟩
      `(
        def $mixinId : ModuleM Unit := $body
      )

def mapRead [ToExpr α] (mapRef : ProofForge.Contract.Source.Internal.MapRef) (mapKey : α) :
    ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.mapGet mapRef (expr mapKey)

def mapWrite [ToExpr α] [ToExpr β]
    (mapRef : ProofForge.Contract.Source.Internal.MapRef) (mapKey : α) (mapValue : β) : EntryM Unit :=
  ProofForge.Contract.Source.Internal.mapSet mapRef (expr mapKey) (expr mapValue)

def pathReadAllowance (mapRef : ProofForge.Contract.Source.Internal.MapRef)
    (ownerKey spenderKey : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.pathRead mapRef.id
    (ProofForge.Contract.Source.Internal.allowancePath ownerKey spenderKey)

def pathWriteAllowance [ToExpr α]
    (mapRef : ProofForge.Contract.Source.Internal.MapRef) (ownerKey spenderKey : ProofForge.IR.Expr)
    (mapValue : α) : EntryM Unit :=
  ProofForge.Contract.Source.Internal.pathWrite mapRef.id
    (ProofForge.Contract.Source.Internal.allowancePath ownerKey spenderKey) (expr mapValue)

def pathReadRole [ToExpr α] [ToExpr β]
    (mapRef : ProofForge.Contract.Source.Internal.MapRef) (roleKey : α) (accountKey : β) :
    ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.pathRead mapRef.id
    (ProofForge.Contract.Source.Internal.allowancePath (expr roleKey) (expr accountKey))

def pathWriteRole [ToExpr α] [ToExpr β] [ToExpr γ]
    (mapRef : ProofForge.Contract.Source.Internal.MapRef) (roleKey : α) (accountKey : β)
    (mapValue : γ) : EntryM Unit :=
  ProofForge.Contract.Source.Internal.pathWrite mapRef.id
    (ProofForge.Contract.Source.Internal.allowancePath (expr roleKey) (expr accountKey)) (expr mapValue)

def pathRead2 [ToExpr α] [ToExpr β]
    (mapRef : ProofForge.Contract.Source.Internal.MapRef) (outerKey : α) (innerKey : β) :
    ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.pathRead mapRef.id
    (ProofForge.Contract.Source.Internal.allowancePath (expr outerKey) (expr innerKey))

def pathWrite2 [ToExpr α] [ToExpr β] [ToExpr γ]
    (mapRef : ProofForge.Contract.Source.Internal.MapRef) (outerKey : α) (innerKey : β)
    (mapValue : γ) : EntryM Unit :=
  ProofForge.Contract.Source.Internal.pathWrite mapRef.id
    (ProofForge.Contract.Source.Internal.allowancePath (expr outerKey) (expr innerKey)) (expr mapValue)

def caller : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.caller

def callerHash : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.callerHash

/-- NEAR predecessor account id as a raw string (Phase 3 NEP-141 interop).
Identity is not hash-truncated: balances keyed by this are keyed by the raw
account id string. NEAR-only. -/
def callerAccountId : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.callerAccountId

/-- This contract / program id (`address(this)` · program_id · current_account).
Portable triad after HostEnv U1.2 (Solana: sha256(program_id) limb0). -/
def contractId : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.contractId

def nativeValue : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.nativeValue

def callValueU128 : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.callValueU128

def hash4 (a b c d : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Source.Internal.hash4 a b c d

macro "array_get " arr:ident idx:term : term => `(ProofForge.Contract.Source.Legacy.arrayGet $arr $idx)

end ProofForge.Contract.Source.Legacy
