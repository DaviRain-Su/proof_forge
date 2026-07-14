/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B end-to-end: vault-owned SPL token account

Creates a token account via official program CPIs (not ATA):

1. `system.create_account` — fund + allocate 165-byte account, owner = SPL Token
2. `spl-token.initialize_account3` — bind mint; **owner pubkey = vault PDA**

This is the PDA-owned token-account path (vault holds the authority). ATA still
uses `associated-token.create`. Product index: `docs/protocols-layer.md` ·
`ProofForge.Protocols.Solana`.
-/
import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.VaultTokenAccountCpi

open ProofForge.Contract.Builder
open ProofForge.Contract.Source.Solana.Legacy

/-- SPL Token account data size (classic layout). -/
def tokenAccountSpace : Nat := 165

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaVaultTokenAccountCpi" do
    scalarState "nonce" .u64
    scalarState "lamports" .u64
    scalarState "space" .u64

    writableSignerAccountConstraint "payer"
    -- New token account keypair (client-supplied signer) or PDA-signed account.
    writableSignerAccountConstraint "token_account"
    readonlyAccountConstraint "mint"
    -- Vault PDA: owner recorded in InitializeAccount3 ix data.
    writableAccountConstraint "vault_account" "program"
    readonlyAccountConstraint "authority"
    readonlyAccountConstraint "spl_token" "executable"
    readonlyAccountConstraint "system_program" "executable"

    bumpAllocator "bump"

    pdaAccount "vault"
      #[literalSeed "vault", accountSeed "authority"]
      (bump? := some "vault_bump")
      (account? := some "vault_account")
      (isSigner := true)

    -- Owner of the *system* account = SPL Token program (not our program).
    systemCreateAccount
      "create_token_account"
      "payer"
      "token_account"
      "lamports"
      "space"
      "spl_token"
      (requireProgramAccount := false)

    -- Token-account owner = vault PDA pubkey (packed into ix data).
    splTokenInitializeAccount3
      "init_token_account"
      "token_account"
      "mint"
      "vault_account"

    entrySelectorWithParams "open_vault_token" "10"
        #[("lamports", .u64), ("space", .u64), ("vault_bump", .u64)] .unit do
      derivePda "vault"
        #[literalSeed "vault", accountSeed "authority"]
        (bump? := some "vault_bump")
        (account? := some "vault_account")
        (isSigner := true)
      invokeSystemCreateAccount
        "create_token_account"
        "payer"
        "token_account"
        "lamports"
        "space"
        "spl_token"
        (requireProgramAccount := false)
      invokeSplTokenInitializeAccount3
        "init_token_account"
        "token_account"
        "mint"
        "vault_account"
      effect (storageScalarWrite "nonce" (u64 1))

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.VaultTokenAccountCpi
