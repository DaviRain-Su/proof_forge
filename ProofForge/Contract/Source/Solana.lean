import ProofForge.Contract.Source
import ProofForge.Contract.Source.Solana.Internal

/-!
# Direct Solana extension for `contract_source`

This opt-in authoring module owns Solana account, PDA, CPI, allocator, and
account-layout grammar. Its macro emits one `AuthoredContract`; target-specific
syntax becomes versioned Solana HostOps and never constructs `ContractSpec`,
`IR.Module`, or a Legacy intent.
-/

set_option hygiene false

namespace ProofForge.Contract.Source

open Lean

declare_syntax_cat solanaSeed
declare_syntax_cat solanaSignerSeed

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

scoped syntax "literal_seed " str : solanaSeed
scoped syntax "account_seed " ident : solanaSeed
scoped syntax "pda_seed " ident : solanaSignerSeed
scoped syntax "bump_seed " ident : solanaSignerSeed

namespace Solana.Direct

def nameLit (name : TSyntax `ident) : TSyntax `term :=
  quote name.getId.toString

def chain (actions : Array (TSyntax `term)) : MacroM (TSyntax `term) := do
  let mut body <- `(pure ())
  for action in actions.reverse do
    body <- `($action *> $body)
  return body

def lowerSeed (seed : TSyntax `solanaSeed) : MacroM (TSyntax `term) := do
  match seed with
  | `(solanaSeed| literal_seed $value:str) =>
      let valueTerm : TSyntax `term := ⟨value.raw⟩
      `(ProofForge.Target.HostOps.Solana.Payload.pdaSeed .literal $valueTerm)
  | `(solanaSeed| account_seed $accountRef:ident) =>
      let valueTerm := nameLit accountRef
      `(ProofForge.Target.HostOps.Solana.Payload.pdaSeed .account $valueTerm)
  | _ => Macro.throwErrorAt seed "unsupported direct Solana PDA seed"

def lowerSeeds (seedItems : TSyntaxArray `solanaSeed) : MacroM (TSyntax `term) := do
  let values <- seedItems.mapM lowerSeed
  `(#[$values,*])

def lowerSignerSeed (seed : TSyntax `solanaSignerSeed) : MacroM (TSyntax `term) := do
  match seed with
  | `(solanaSignerSeed| pda_seed $pdaRef:ident) =>
      let valueTerm := nameLit pdaRef
      `(ProofForge.Target.HostOps.Solana.Payload.pdaSeed .literal $valueTerm)
  | `(solanaSignerSeed| bump_seed $bumpRef:ident) =>
      let valueTerm := nameLit bumpRef
      `(ProofForge.Target.HostOps.Solana.Payload.pdaSeed .bump $valueTerm)
  | _ => Macro.throwErrorAt seed "unsupported direct Solana signer seed"

def lowerSignerSeeds (seedItems : TSyntaxArray `solanaSignerSeed) : MacroM (TSyntax `term) := do
  let values <- seedItems.mapM lowerSignerSeed
  `(#[$values,*])

def cpiAccount (accountName : TSyntax `ident) (accessValue signerValue : String) :
    MacroM (TSyntax `term) := do
  let nameTerm := nameLit accountName
  let accessTerm <- if accessValue == "writable" then `(.writable) else `(.readOnly)
  let signerTerm <- match signerValue with
    | "signer" => `(.signer)
    | "pda-signer" => `(.pdaSigner)
    | _ => `(.none)
  `(ProofForge.Target.HostOps.Solana.Payload.cpiAccountSpec
    $nameTerm $accessTerm $signerTerm)

def cpiArgument (kind : String) (value : TSyntax `term) : MacroM (TSyntax `term) := do
  let kindTerm <- match kind with
    | "lamports" => `(.lamportsSource)
    | "space" => `(.spaceSource)
    | "owner" => `(.owner)
    | "amount" => `(.amountSource)
    | "decimals" => `(.decimals)
    | "authority_type" => `(.authorityType)
    | "new_authority" => `(.newAuthority)
    | "memo" => `(.memoSource)
    | "token_program" => `(.tokenProgram)
    | _ => Macro.throwError s!"unsupported direct Solana CPI argument `{kind}`"
  `(ProofForge.Target.HostOps.Solana.Payload.cpiArgument $kindTerm $value)

def cpiSpec (name program instruction protocol layout : TSyntax `term)
    (accountItems signerSeedTerm argumentItems : TSyntax `term) (isSigned : Bool) :
    MacroM (TSyntax `term) := do
  let signedTerm <- if isSigned then `(true) else `(false)
  `(ProofForge.Target.HostOps.Solana.Payload.cpiSpec
    $name $program $instruction $accountItems $signerSeedTerm
    (some $protocol) (some $layout) $argumentItems $signedTerm)

def systemTransferSpec (call fromAccount toAccount lamports : TSyntax `ident) :
    MacroM (TSyntax `term) := do
  let callName := nameLit call
  let fromMeta <- cpiAccount fromAccount "writable" "signer"
  let toMeta <- cpiAccount toAccount "writable" "none"
  let lamportsArg <- cpiArgument "lamports" (nameLit lamports)
  cpiSpec callName (quote "system_program") (quote "transfer") (quote "system")
    (quote "system.transfer") (← `(#[$fromMeta, $toMeta])) (← `(#[]))
    (← `(#[$lamportsArg])) false

def memoSpec (call memoSource : TSyntax `ident) : MacroM (TSyntax `term) := do
  let memoArg <- cpiArgument "memo" (nameLit memoSource)
  cpiSpec (nameLit call) (quote "memo") (quote "memo") (quote "memo")
    (quote "memo.memo") (← `(#[])) (← `(#[])) (← `(#[$memoArg])) false

def systemCreateAccountSpec (call payer newAccount lamports space : TSyntax `ident)
    (ownerValue : TSyntax `term) : MacroM (TSyntax `term) := do
  let payerMeta <- cpiAccount payer "writable" "signer"
  let accountMeta <- cpiAccount newAccount "writable" "signer"
  let lamportsArg <- cpiArgument "lamports" (nameLit lamports)
  let spaceArg <- cpiArgument "space" (nameLit space)
  let ownerArg <- cpiArgument "owner" ownerValue
  cpiSpec (nameLit call) (quote "system_program") (quote "create_account")
    (quote "system") (quote "system.create_account")
    (← `(#[$payerMeta, $accountMeta])) (← `(#[]))
    (← `(#[$lamportsArg, $spaceArg, $ownerArg])) false

def splTransferCheckedSpec (call source mint destination authority amount : TSyntax `ident)
    (decimalsValue : TSyntax `term) (signerSeedItems : TSyntaxArray `solanaSignerSeed) :
    MacroM (TSyntax `term) := do
  let signerPolicy := if signerSeedItems.isEmpty then "signer" else "pda-signer"
  let sourceMeta <- cpiAccount source "writable" "none"
  let mintMeta <- cpiAccount mint "readonly" "none"
  let destinationMeta <- cpiAccount destination "writable" "none"
  let authorityMeta <- cpiAccount authority "readonly" signerPolicy
  let amountArg <- cpiArgument "amount" (nameLit amount)
  let decimalsArg <- cpiArgument "decimals" (← `(toString $decimalsValue))
  let signerSeedTerm <- lowerSignerSeeds signerSeedItems
  cpiSpec (nameLit call) (quote "spl_token") (quote "transfer_checked")
    (quote "spl-token") (quote "spl-token.transfer_checked")
    (← `(#[$sourceMeta, $mintMeta, $destinationMeta, $authorityMeta])) signerSeedTerm
    (← `(#[$amountArg, $decimalsArg])) (!signerSeedItems.isEmpty)

def splCloseAccountSpec (call accountRef destination authority : TSyntax `ident)
    (signerSeedItems : TSyntaxArray `solanaSignerSeed) : MacroM (TSyntax `term) := do
  let signerPolicy := if signerSeedItems.isEmpty then "signer" else "pda-signer"
  let accountMeta <- cpiAccount accountRef "writable" "none"
  let destinationMeta <- cpiAccount destination "writable" "none"
  let authorityMeta <- cpiAccount authority "readonly" signerPolicy
  let signerSeedTerm <- lowerSignerSeeds signerSeedItems
  cpiSpec (nameLit call) (quote "spl_token") (quote "close_account")
    (quote "spl-token") (quote "spl-token.close_account")
    (← `(#[$accountMeta, $destinationMeta, $authorityMeta])) signerSeedTerm (← `(#[]))
    (!signerSeedItems.isEmpty)

def splSetAuthoritySpec (call accountRef authority newAuthority : TSyntax `ident)
    (authorityType : TSyntax `term) (signerSeedItems : TSyntaxArray `solanaSignerSeed) :
    MacroM (TSyntax `term) := do
  let signerPolicy := if signerSeedItems.isEmpty then "signer" else "pda-signer"
  let accountMeta <- cpiAccount accountRef "writable" "none"
  let authorityMeta <- cpiAccount authority "readonly" signerPolicy
  let authorityTypeArg <- cpiArgument "authority_type" authorityType
  let newAuthorityArg <- cpiArgument "new_authority" (nameLit newAuthority)
  let signerSeedTerm <- lowerSignerSeeds signerSeedItems
  cpiSpec (nameLit call) (quote "spl_token") (quote "set_authority")
    (quote "spl-token") (quote "spl-token.set_authority")
    (← `(#[$accountMeta, $authorityMeta])) signerSeedTerm
    (← `(#[$authorityTypeArg, $newAuthorityArg])) (!signerSeedItems.isEmpty)

def associatedTokenSpec (call funding accountRef wallet mint : TSyntax `ident)
    (idempotent : Bool) (signerSeedItems : TSyntaxArray `solanaSignerSeed) :
    MacroM (TSyntax `term) := do
  let signerPolicy := if signerSeedItems.isEmpty then "signer" else "pda-signer"
  let fundingMeta <- cpiAccount funding "writable" signerPolicy
  let accountMeta <- cpiAccount accountRef "writable" "none"
  let walletMeta <- cpiAccount wallet "readonly" "none"
  let mintMeta <- cpiAccount mint "readonly" "none"
  let systemMeta : TSyntax `term <-
    `(ProofForge.Target.HostOps.Solana.Payload.cpiAccountSpec
      "system_program" .readOnly .none)
  let tokenMeta : TSyntax `term <-
    `(ProofForge.Target.HostOps.Solana.Payload.cpiAccountSpec
      "spl_token" .readOnly .none)
  let tokenArg <- cpiArgument "token_program" (quote "spl_token")
  let signerSeedTerm <- lowerSignerSeeds signerSeedItems
  let instruction := if idempotent then quote "create_idempotent" else quote "create"
  let layout := if idempotent then quote "associated-token.create_idempotent" else quote "associated-token.create"
  cpiSpec (nameLit call) (quote "associated_token") instruction (quote "associated-token")
    layout (← `(#[$fundingMeta, $accountMeta, $walletMeta, $mintMeta, $systemMeta, $tokenMeta]))
    signerSeedTerm (← `(#[$tokenArg])) (!signerSeedItems.isEmpty)

partial def lowerExpr (states locals : Array String) (expr : TSyntax `term) :
    MacroM (TSyntax `term) := do
  match expr with
  | `(u64 $value:num) =>
      `(.literal (.u64Lit $value))
  | `($lhs:term +! $rhs:term) =>
      let lhs <- lowerExpr states locals lhs
      let rhs <- lowerExpr states locals rhs
      `(.arith .add true $lhs $rhs)
  | `(term| $name:ident) =>
      let value := name.getId.toString
      let valueTerm : TSyntax `term := quote value
      if states.contains value && !locals.contains value then
        `(.stateRead $valueTerm)
      else
        `(.local $valueTerm)
  | _ => Macro.throwErrorAt expr s!"unsupported direct Solana source expression `{expr.raw}`"

def lowerEntryBody (states : Array String) (stmts : Array (TSyntax `entryStmt)) :
    MacroM (TSyntax `term) := do
  let mut locals : Array String := #[]
  let mut actions : Array (TSyntax `term) := #[]
  for stmt in stmts do
    match stmt with
    | `(entryStmt| let $name:ident : $type:term := $value:term;) =>
        let valueTerm <- lowerExpr states locals value
        let nameTerm := nameLit name
        actions := actions.push (←
          `(ProofForge.Frontend.Authored.Builder.bind $nameTerm $type $valueTerm))
        locals := locals.push name.getId.toString
    | `(entryStmt| $slot:ident := $value:term;) =>
        let valueTerm <- lowerExpr states locals value
        let slotName := nameLit slot
        actions := actions.push (←
          `(ProofForge.Frontend.Authored.Builder.stateWrite $slotName $valueTerm))
    | `(entryStmt| return $value:term;) =>
        let valueTerm <- lowerExpr states locals value
        actions := actions.push (← `(ProofForge.Frontend.Authored.Builder.ret $valueTerm))
    | `(entryStmt| derive pda $pdaRef:ident seeds [$seedItems:solanaSeed,*] bump $bumpRef:ident account $accountRef:ident signer;) =>
        let seedTerm <- lowerSeeds seedItems
        let pdaName := nameLit pdaRef
        let bumpName := nameLit bumpRef
        let accountName := nameLit accountRef
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.derivePda
            (ProofForge.Target.HostOps.Solana.Payload.pdaSpec
              $pdaName $seedTerm (some $bumpName) (some $accountName) true)))
    | `(entryStmt| invoke $call:ident system_transfer($fromAccount:ident, $toAccount:ident, $lamports:ident);) =>
        let spec <- systemTransferSpec call fromAccount toAccount lamports
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.invokeCpi $spec))
    | `(entryStmt| invoke $call:ident memo($memoSource:ident);) =>
        let spec <- memoSpec call memoSource
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.invokeCpi $spec))
    | `(entryStmt| invoke $call:ident system_create_account($payer:ident, $newAccount:ident, $lamports:ident, $space:ident) owner $ownerValue:term;) =>
        let spec <- systemCreateAccountSpec call payer newAccount lamports space ownerValue
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.invokeCpi $spec))
    | `(entryStmt| invoke $call:ident spl_token_transfer_checked($source:ident, $mint:ident, $destination:ident, $authority:ident, $amount:ident) decimals($decimalsValue:term) signer_seeds [$seedItems:solanaSignerSeed,*];) =>
        let spec <- splTransferCheckedSpec call source mint destination authority amount decimalsValue seedItems
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.invokeCpi $spec))
    | `(entryStmt| invoke $call:ident spl_token_close_account($accountRef:ident, $destination:ident, $authority:ident) signer_seeds [$seedItems:solanaSignerSeed,*];) =>
        let spec <- splCloseAccountSpec call accountRef destination authority seedItems
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.invokeCpi $spec))
    | `(entryStmt| invoke $call:ident spl_token_set_authority($accountRef:ident, $authority:ident, $newAuthority:ident) authority_type($authorityType:term) signer_seeds [$seedItems:solanaSignerSeed,*];) =>
        let spec <- splSetAuthoritySpec call accountRef authority newAuthority authorityType seedItems
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.invokeCpi $spec))
    | `(entryStmt| invoke $call:ident associated_token_create($funding:ident, $accountRef:ident, $wallet:ident, $mint:ident) signer_seeds [$seedItems:solanaSignerSeed,*];) =>
        let spec <- associatedTokenSpec call funding accountRef wallet mint false seedItems
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.invokeCpi $spec))
    | `(entryStmt| invoke $call:ident associated_token_create_idempotent($funding:ident, $accountRef:ident, $wallet:ident, $mint:ident) signer_seeds [$seedItems:solanaSignerSeed,*];) =>
        let spec <- associatedTokenSpec call funding accountRef wallet mint true seedItems
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.invokeCpi $spec))
    | `(entryStmt| realloc $accountRef:ident to $newSize:term;) =>
        let actionName : TSyntax `term := quote ("realloc_" ++ accountRef.getId.toString)
        let accountName := nameLit accountRef
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.reallocAccount
            (ProofForge.Target.HostOps.Solana.Payload.accountReallocSpec
              $actionName $accountName $newSize)))
    | `(entryStmt| init_transfer_hook_extra_meta($accountRef:ident, $extraAccount:ident);) =>
        let accountName := nameLit accountRef
        let extraAccountName := nameLit extraAccount
        actions := actions.push (←
          `(ProofForge.Contract.Source.Solana.Internal.Authored.initializeTransferHookExtraAccountMeta
            (ProofForge.Target.HostOps.Solana.Payload.transferHookExtraAccountMetaSpec
              "init_transfer_hook_extra_meta" $accountName #[$extraAccountName])))
    | _ => Macro.throwErrorAt stmt "unsupported statement in direct Solana contract source"
  chain actions

def entryAction (states : Array String) (name : TSyntax `ident)
    (params : Array (TSyntax `ident × TSyntax `term)) (retType : TSyntax `term)
    (isView : Bool) (stmts : Array (TSyntax `entryStmt)) : MacroM (TSyntax `term) := do
  let body <- lowerEntryBody states stmts
  let params <- params.mapM fun param => do
    let paramName := nameLit param.1
    let paramType := param.2
    `(show ProofForge.Frontend.Authored.AuthoredParam from
      { name := $paramName, type := $paramType })
  let mutability <- if isView then `(.view) else `(.call)
  let entryName := nameLit name
  `(ProofForge.Frontend.Authored.Builder.entryFull $entryName #[$params,*]
      $retType $body $mutability)

def collectStateNames (items : Array (TSyntax `contractItem)) : Array String :=
  items.foldl (init := #[]) fun names item => match item with
    | `(contractItem| state $name:ident : $_type:term) => names.push name.getId.toString
    | _ => names

def lowerItem (states : Array String) (item : TSyntax `contractItem) :
    MacroM (Option (TSyntax `term)) := do
  match item with
  | `(contractItem| state $name:ident : $type:term) =>
      let stateName := nameLit name
      return some (← `(ProofForge.Frontend.Authored.Builder.scalarState $stateName $type))
  | `(contractItem| binding $_name:ident : $_type:term) => return none
  | `(contractItem| allocator bump) =>
      return some (←
        `(ProofForge.Contract.Source.Solana.Internal.Authored.configureAllocator
          (ProofForge.Target.HostOps.Solana.Payload.allocatorSpec
            "runtime" .bump "0x300000000" 32768)))
  | `(contractItem| account $name:ident readonly) =>
      let accountName := nameLit name
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareAccount
        (ProofForge.Target.HostOps.Solana.Payload.accountSpec
          $accountName .readOnly .none "any")))
  | `(contractItem| account $name:ident readonly signer) =>
      let accountName := nameLit name
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareAccount
        (ProofForge.Target.HostOps.Solana.Payload.accountSpec
          $accountName .readOnly .signer "any")))
  | `(contractItem| account $name:ident readonly owner $ownerValue:term) =>
      let accountName := nameLit name
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareAccount
        (ProofForge.Target.HostOps.Solana.Payload.accountSpec
          $accountName .readOnly .none $ownerValue)))
  | `(contractItem| account $name:ident readonly signer owner $ownerValue:term) =>
      let accountName := nameLit name
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareAccount
        (ProofForge.Target.HostOps.Solana.Payload.accountSpec
          $accountName .readOnly .signer $ownerValue)))
  | `(contractItem| account $name:ident writable) =>
      let accountName := nameLit name
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareAccount
        (ProofForge.Target.HostOps.Solana.Payload.accountSpec
          $accountName .writable .none "any")))
  | `(contractItem| account $name:ident writable signer) =>
      let accountName := nameLit name
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareAccount
        (ProofForge.Target.HostOps.Solana.Payload.accountSpec
          $accountName .writable .signer "any")))
  | `(contractItem| account $name:ident writable owner $ownerValue:term) =>
      let accountName := nameLit name
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareAccount
        (ProofForge.Target.HostOps.Solana.Payload.accountSpec
          $accountName .writable .none $ownerValue)))
  | `(contractItem| account $name:ident writable signer owner $ownerValue:term) =>
      let accountName := nameLit name
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareAccount
        (ProofForge.Target.HostOps.Solana.Payload.accountSpec
          $accountName .writable .signer $ownerValue)))
  | `(contractItem| pda $name:ident seeds [$seedItems:solanaSeed,*] bump $bumpRef:ident account $accountRef:ident signer) =>
      let seedTerm <- lowerSeeds seedItems
      let pdaName := nameLit name
      let bumpName := nameLit bumpRef
      let accountName := nameLit accountRef
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declarePda
        (ProofForge.Target.HostOps.Solana.Payload.pdaSpec
          $pdaName $seedTerm (some $bumpName) (some $accountName) true)))
  | `(contractItem| cpi $call:ident system_transfer($fromAccount:ident, $toAccount:ident, $lamports:ident)) =>
      let spec <- systemTransferSpec call fromAccount toAccount lamports
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareCpi $spec))
  | `(contractItem| cpi $call:ident memo($memoSource:ident)) =>
      let spec <- memoSpec call memoSource
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareCpi $spec))
  | `(contractItem| cpi $call:ident system_create_account($payer:ident, $newAccount:ident, $lamports:ident, $space:ident) owner $ownerValue:term) =>
      let spec <- systemCreateAccountSpec call payer newAccount lamports space ownerValue
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareCpi $spec))
  | `(contractItem| cpi $call:ident spl_token_transfer_checked($source:ident, $mint:ident, $destination:ident, $authority:ident, $amount:ident) decimals($decimalsValue:term) signer_seeds [$seedItems:solanaSignerSeed,*]) =>
      let spec <- splTransferCheckedSpec call source mint destination authority amount decimalsValue seedItems
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareCpi $spec))
  | `(contractItem| cpi $call:ident spl_token_close_account($accountRef:ident, $destination:ident, $authority:ident) signer_seeds [$seedItems:solanaSignerSeed,*]) =>
      let spec <- splCloseAccountSpec call accountRef destination authority seedItems
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareCpi $spec))
  | `(contractItem| cpi $call:ident spl_token_set_authority($accountRef:ident, $authority:ident, $newAuthority:ident) authority_type($authorityType:term) signer_seeds [$seedItems:solanaSignerSeed,*]) =>
      let spec <- splSetAuthoritySpec call accountRef authority newAuthority authorityType seedItems
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareCpi $spec))
  | `(contractItem| cpi $call:ident associated_token_create($funding:ident, $accountRef:ident, $wallet:ident, $mint:ident) signer_seeds [$seedItems:solanaSignerSeed,*]) =>
      let spec <- associatedTokenSpec call funding accountRef wallet mint false seedItems
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareCpi $spec))
  | `(contractItem| cpi $call:ident associated_token_create_idempotent($funding:ident, $accountRef:ident, $wallet:ident, $mint:ident) signer_seeds [$seedItems:solanaSignerSeed,*]) =>
      let spec <- associatedTokenSpec call funding accountRef wallet mint true seedItems
      return some (← `(ProofForge.Contract.Source.Solana.Internal.Authored.declareCpi $spec))
  | `(contractItem| entry $name:ident do $stmts:entryStmt*) =>
      return some (← entryAction states name #[] (← `(.unit)) false stmts)
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term) do $stmts:entryStmt*) =>
      return some (← entryAction states name #[(p1, t1)] (← `(.unit)) false stmts)
  | `(contractItem| entry $name:ident ($p1:ident : $t1:term, $p2:ident : $t2:term) do $stmts:entryStmt*) =>
      return some (← entryAction states name #[(p1, t1), (p2, t2)] (← `(.unit)) false stmts)
  | `(contractItem| entry $name:ident returns($ret:term) do $stmts:entryStmt*) =>
      return some (← entryAction states name #[] ret false stmts)
  | `(contractItem| query $name:ident returns($ret:term) do $stmts:entryStmt*) =>
      return some (← entryAction states name #[] ret true stmts)
  | _ => Macro.throwError
          "unsupported item in direct Solana contract source; use only portable state/entry items and typed Solana operations"

def lowerItems (items : Array (TSyntax `contractItem)) : MacroM (TSyntax `term) := do
  let states := collectStateNames items
  let mut actions := #[]
  for item in items do
    if let some action <- lowerItem states item then
      actions := actions.push action
  chain actions

end Solana.Direct

macro_rules
  | `(contract_source $name:ident do $items:contractItem*) => do
      let body <- Solana.Direct.lowerItems items
      let nameLit := Solana.Direct.nameLit name
      `(
        def contract : ProofForge.Frontend.Authored.AuthoredContract :=
          ProofForge.Frontend.Authored.Builder.build $nameLit $body
      )
  | `(contract_mixin $_name:ident do $items:contractItem*) => do
      let body <- Solana.Direct.lowerItems items
      `(
        def mixin : ProofForge.Frontend.Authored.Builder.ModuleM Unit := $body
      )

end ProofForge.Contract.Source
