import ProofForge.Contract.Source.Solana

namespace Examples.Backend.Solana.Contracts.Vault

open ProofForge.Contract.Source

contract_source SolanaVault do
  state nonce : .u64
  binding amount : .u64
  binding vault_bump : .u64

  allocator bump
  account vault_account writable owner "program"
  account source writable
  account mint readonly
  account destination writable
  account authority readonly
  account spl_token readonly owner "executable"

  pda vault seeds [literal_seed "vault", account_seed authority]
    bump vault_bump account vault_account signer

  cpi token_transfer spl_token_transfer_checked(
    source,
    mint,
    destination,
    authority,
    amount
  ) decimals(9) signer_seeds [pda_seed vault, bump_seed vault_bump]

  entry «initialize» do
    nonce := u64 0;

  -- Params on the entry so Solana valueBindings resolve (amount / vault_bump).
  entry touch (amount : .u64, vault_bump : .u64) do
    derive pda vault seeds [literal_seed "vault", account_seed authority]
      bump vault_bump account vault_account signer;
    invoke token_transfer spl_token_transfer_checked(
      source,
      mint,
      destination,
      authority,
      amount
    ) decimals(9) signer_seeds [pda_seed vault, bump_seed vault_bump];
    let n : .u64 := nonce;
    nonce := n +! u64 1;

end Examples.Backend.Solana.Contracts.Vault
