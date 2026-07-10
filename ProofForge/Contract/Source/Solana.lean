/-
# Solana extension entrypoint for `contract_source` (**fixture / research only**)

**Product path:** `import ProofForge.Contract.Source` only. Portable Shared
examples must never import this file (`just portable-default`).

Import **this** module for backend fixtures, Pinocchio/live gates, or
hand-tuned Solana layouts:

```lean
import ProofForge.Contract.Source.Solana
```

PF-P1-05: `ProofForge.Solana.Surface` is loaded only through this opt-in module.
-/
import ProofForge.Contract.Source
import ProofForge.Solana.Surface
import ProofForge.Solana

set_option hygiene false

namespace ProofForge.Contract.Source

open Lean
open ProofForge.IR

def mkAccountLet (name : TSyntax `ident)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Solana.Surface.AccountRef :=
      { name := $nameLit }
    $body)

def mkPdaLet (name : TSyntax `ident)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Solana.Surface.PdaRef :=
      { name := $nameLit }
    $body)

def mkCpiLet (name : TSyntax `ident)
    (body : TSyntax `term) : MacroM (TSyntax `term) := do
  let nameLit := identNameLit name
  `(let $name : ProofForge.Solana.Surface.CpiRef :=
      { name := $nameLit }
    $body)

def lowerSolanaSeed (seed : TSyntax `solanaSeed) : MacroM (TSyntax `term) := do
  match seed with
  | `(solanaSeed| literal_seed $value:str) =>
      `(ProofForge.Solana.Surface.literalSeed $value)
  | `(solanaSeed| account_seed $accountRef:ident) =>
      `(ProofForge.Solana.Surface.accountSeed $accountRef)
  | _ =>
      Macro.throwErrorAt seed s!"unsupported Solana PDA seed (dsl {sourceDslVersion})"

def lowerSolanaSeeds (seedItems : TSyntaxArray `solanaSeed) : MacroM (TSyntax `term) := do
  let lowered ← seedItems.mapM lowerSolanaSeed
  `(#[$lowered,*])

def lowerSolanaSignerSeed (seed : TSyntax `solanaSignerSeed) : MacroM (TSyntax `term) := do
  match seed with
  | `(solanaSignerSeed| pda_seed $pdaRef:ident) =>
      `(ProofForge.Solana.Surface.pdaName $pdaRef)
  | `(solanaSignerSeed| bump_seed $bindingRef:ident) =>
      `(ProofForge.Solana.Surface.bindingName $bindingRef)
  | _ =>
      Macro.throwErrorAt seed s!"unsupported Solana signer seed (dsl {sourceDslVersion})"

def lowerSolanaSignerSeeds (seedItems : TSyntaxArray `solanaSignerSeed) : MacroM (TSyntax `term) := do
  let lowered ← seedItems.mapM lowerSolanaSignerSeed
  `(#[$lowered,*])



/-- Solana entry-stmt extension for `lowerEntryBody` (PF-P1-05). -/
def trySolanaEntryStmt : EntryStmtExt := fun stmt acc => do
  match stmt with
  | `(entryStmt| derive pda $pdaRef:ident seeds [$seedItems:solanaSeed,*] bump $bumpRef:ident account $accountRef:ident signer;) => do
    let seedArray ← lowerSolanaSeeds seedItems
    return some (←
      `(ProofForge.Solana.Surface.derivePda $pdaRef $seedArray
          (bump? := some $bumpRef)
          (account? := some $accountRef)
          (isSigner := true) *> $acc))
  | `(entryStmt| invoke $call:ident system_transfer($fromAccount:ident, $toAccount:ident, $lamportsSource:ident);) => do
    let callLit := identNameLit call
    let fromLit := identNameLit fromAccount
    let toLit := identNameLit toAccount
    let lamportsLit := identNameLit lamportsSource
    return some (←
      `(ProofForge.Solana.invokeSystemTransfer $callLit $fromLit $toLit $lamportsLit *> $acc))
  | `(entryStmt| invoke $call:ident memo($memoSource:ident);) => do
    let callLit := identNameLit call
    let memoLit := identNameLit memoSource
    return some (←
      `(ProofForge.Solana.invokeMemo $callLit $memoLit *> $acc))
  | `(entryStmt| invoke $call:ident system_create_account($payer:ident, $newAccount:ident, $lamportsSource:ident, $spaceSource:ident) owner $ownerSource:term;) => do
    let callLit := identNameLit call
    let payerLit := identNameLit payer
    let newAccountLit := identNameLit newAccount
    let lamportsLit := identNameLit lamportsSource
    let spaceLit := identNameLit spaceSource
    return some (←
      `(ProofForge.Solana.invokeSystemCreateAccount
          $callLit $payerLit $newAccountLit $lamportsLit $spaceLit $ownerSource *> $acc))
  | `(entryStmt| invoke $call:ident spl_token_transfer_checked($source:ident, $mint:ident, $destination:ident, $authority:ident, $amountRef:ident) decimals($decimalValue:term) signer_seeds [$signerSeedItems:solanaSignerSeed,*];) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    return some (←
      `(ProofForge.Solana.Surface.invokeSplTokenTransferChecked
          $call $source $mint $destination $authority $amountRef $decimalValue
          (signerSeeds := $signerSeedArray) *> $acc))
  | `(entryStmt| invoke $call:ident spl_token_close_account($tokenAccount:ident, $destination:ident, $authority:ident) signer_seeds [$signerSeedItems:solanaSignerSeed,*];) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    return some (←
      `(ProofForge.Solana.Surface.invokeSplTokenCloseAccount
          $call $tokenAccount $destination $authority
          (signerSeeds := $signerSeedArray) *> $acc))
  | `(entryStmt| invoke $call:ident spl_token_set_authority($tokenAccount:ident, $authority:ident, $newAuthority:ident) authority_type($authorityType:term) signer_seeds [$signerSeedItems:solanaSignerSeed,*];) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    return some (←
      `(ProofForge.Solana.Surface.invokeSplTokenSetAuthority
          $call $tokenAccount $authority $newAuthority
          (authorityType := $authorityType)
          (signerSeeds := $signerSeedArray) *> $acc))
  | `(entryStmt| invoke $call:ident associated_token_create($funding:ident, $ataAccount:ident, $wallet:ident, $mint:ident) signer_seeds [$signerSeedItems:solanaSignerSeed,*];) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    return some (←
      `(ProofForge.Solana.Surface.invokeAssociatedTokenCreate
          $call $funding $ataAccount $wallet $mint
          (idempotent := false)
          (signerSeeds := $signerSeedArray) *> $acc))
  | `(entryStmt| invoke $call:ident associated_token_create_idempotent($funding:ident, $ataAccount:ident, $wallet:ident, $mint:ident) signer_seeds [$signerSeedItems:solanaSignerSeed,*];) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    return some (←
      `(ProofForge.Solana.Surface.invokeAssociatedTokenCreate
          $call $funding $ataAccount $wallet $mint
          (idempotent := true)
          (signerSeeds := $signerSeedArray) *> $acc))
  | `(entryStmt| realloc $accountRef:ident to $newSize:term;) => do
    return some (←
      `(ProofForge.Solana.Surface.reallocAccount $accountRef $newSize *> $acc))
  | `(entryStmt| init_transfer_hook_extra_meta($accountRef:ident, $extraAccountRef:ident);) => do
    return some (←
      `(ProofForge.Solana.Surface.initializeTransferHookExtraAccountMetaList
          $accountRef $extraAccountRef *> $acc))
  | _ => pure none

/-- Solana contract-item extension for `lowerItem` (PF-P1-05). -/
def trySolanaContractItem : ContractItemExt := fun item => do
  match item with
  | `(contractItem| allocator bump) => do
    let action ← `(ProofForge.Solana.Surface.bumpAllocator)
    return some { action? := some action }
  | `(contractItem| account $name:ident readonly) => do
    let action ← `(ProofForge.Solana.Surface.readonlyAccount $name)
    return some { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident readonly signer) => do
    let action ← `(ProofForge.Solana.Surface.signerAccount $name)
    return some { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident readonly owner $ownerValue:term) => do
    let action ← `(ProofForge.Solana.Surface.readonlyAccount $name $ownerValue)
    return some { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident readonly signer owner $ownerValue:term) => do
    let action ← `(ProofForge.Solana.Surface.signerAccount $name .readOnly $ownerValue)
    return some { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident writable) => do
    let action ← `(ProofForge.Solana.Surface.writableAccount $name)
    return some { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident writable signer) => do
    let action ← `(ProofForge.Solana.Surface.writableSignerAccount $name)
    return some { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident writable owner $ownerValue:term) => do
    let action ← `(ProofForge.Solana.Surface.writableAccount $name $ownerValue)
    return some { action? := some action, binder := mkAccountLet name }
  | `(contractItem| account $name:ident writable signer owner $ownerValue:term) => do
    let action ← `(ProofForge.Solana.Surface.writableSignerAccount $name $ownerValue)
    return some { action? := some action, binder := mkAccountLet name }
  | `(contractItem| pda $name:ident seeds [$seedItems:solanaSeed,*] bump $bumpRef:ident account $accountRef:ident signer) => do
    let seedArray ← lowerSolanaSeeds seedItems
    let action ←
      `(ProofForge.Solana.Surface.pdaAccount $name $seedArray
          (bump? := some $bumpRef)
          (account? := some $accountRef)
          (isSigner := true))
    return some { action? := some action, binder := mkPdaLet name }
  | `(contractItem| cpi $call:ident system_transfer($fromAccount:ident, $toAccount:ident, $lamportsSource:ident)) => do
    let callLit := identNameLit call
    let fromLit := identNameLit fromAccount
    let toLit := identNameLit toAccount
    let lamportsLit := identNameLit lamportsSource
    let action ←
      `(ProofForge.Solana.systemTransfer $callLit $fromLit $toLit $lamportsLit)
    return some { action? := some action }
  | `(contractItem| cpi $call:ident memo($memoSource:ident)) => do
    let callLit := identNameLit call
    let memoLit := identNameLit memoSource
    let action ←
      `(ProofForge.Solana.memo $callLit $memoLit)
    return some { action? := some action }
  | `(contractItem| cpi $call:ident system_create_account($payer:ident, $newAccount:ident, $lamportsSource:ident, $spaceSource:ident) owner $ownerSource:term) => do
    let callLit := identNameLit call
    let payerLit := identNameLit payer
    let newAccountLit := identNameLit newAccount
    let lamportsLit := identNameLit lamportsSource
    let spaceLit := identNameLit spaceSource
    let action ←
      `(ProofForge.Solana.systemCreateAccount
          $callLit $payerLit $newAccountLit $lamportsLit $spaceLit $ownerSource)
    return some { action? := some action }
  | `(contractItem| cpi $call:ident spl_token_transfer_checked($source:ident, $mint:ident, $destination:ident, $authority:ident, $amountRef:ident) decimals($decimalValue:term) signer_seeds [$signerSeedItems:solanaSignerSeed,*]) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    let action ←
      `(ProofForge.Solana.Surface.splTokenTransferChecked
          $call $source $mint $destination $authority $amountRef $decimalValue
          (signerSeeds := $signerSeedArray))
    return some { action? := some action, binder := mkCpiLet call }
  | `(contractItem| cpi $call:ident spl_token_close_account($tokenAccount:ident, $destination:ident, $authority:ident) signer_seeds [$signerSeedItems:solanaSignerSeed,*]) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    let action ←
      `(ProofForge.Solana.Surface.splTokenCloseAccount
          $call $tokenAccount $destination $authority
          (signerSeeds := $signerSeedArray))
    return some { action? := some action, binder := mkCpiLet call }
  | `(contractItem| cpi $call:ident spl_token_set_authority($tokenAccount:ident, $authority:ident, $newAuthority:ident) authority_type($authorityType:term) signer_seeds [$signerSeedItems:solanaSignerSeed,*]) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    let action ←
      `(ProofForge.Solana.Surface.splTokenSetAuthority
          $call $tokenAccount $authority $newAuthority
          (authorityType := $authorityType)
          (signerSeeds := $signerSeedArray))
    return some { action? := some action, binder := mkCpiLet call }
  | `(contractItem| cpi $call:ident associated_token_create($funding:ident, $ataAccount:ident, $wallet:ident, $mint:ident) signer_seeds [$signerSeedItems:solanaSignerSeed,*]) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    let action ←
      `(ProofForge.Solana.Surface.associatedTokenCreate
          $call $funding $ataAccount $wallet $mint
          (idempotent := false)
          (signerSeeds := $signerSeedArray))
    return some { action? := some action, binder := mkCpiLet call }
  | `(contractItem| cpi $call:ident associated_token_create_idempotent($funding:ident, $ataAccount:ident, $wallet:ident, $mint:ident) signer_seeds [$signerSeedItems:solanaSignerSeed,*]) => do
    let signerSeedArray ← lowerSolanaSignerSeeds signerSeedItems
    let action ←
      `(ProofForge.Solana.Surface.associatedTokenCreate
          $call $funding $ataAccount $wallet $mint
          (idempotent := true)
          (signerSeeds := $signerSeedArray))
    return some { action? := some action, binder := mkCpiLet call }
  | _ => pure none

/-- Solana-aware `contract_source` / `contract_mixin` (tried before portable-only rules). -/
macro_rules
  | `(contract_source $name:ident do $items:contractItem*) => do
      let (composeMods, extItems) ← partitionContractItems items
      let nameLit := identNameLit name
      let specId : TSyntax `ident := ⟨mkIdent `spec⟩
      let moduleId : TSyntax `ident := ⟨mkIdent `module⟩
      if composeMods.isEmpty then
        let (body, _) ← lowerContractItems items trySolanaEntryStmt trySolanaContractItem
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
        let (extBody, _) ← lowerContractItems extItems trySolanaEntryStmt trySolanaContractItem
        `(
          def $specId : ProofForge.Contract.ContractSpec :=
            ProofForge.Contract.Compose.mergeExtension $nameLit $baseSpec
              (ProofForge.Contract.Surface.contract $nameLit $extBody)

          def $moduleId : ProofForge.IR.Module :=
            ($specId).module
        )

  | `(contract_mixin $_name:ident do $items:contractItem*) => do
      let (body, _) ← lowerContractItems items trySolanaEntryStmt trySolanaContractItem
      let mixinId : TSyntax `ident := ⟨mkIdent `mixin⟩
      `(
        def $mixinId : ModuleM Unit := $body
      )

end ProofForge.Contract.Source
