import ProofForge.Contract.Source

namespace ProofForge.Solana.Examples.AssociatedTokenCpi

open ProofForge.Contract.Source

contract_source SolanaAssociatedTokenCpi do
  state last_created_marker : .u64

  account payer writable signer
  account associated_account writable
  account wallet readonly
  account mint readonly
  account system_program readonly owner "executable"
  account spl_token readonly owner "executable"

  cpi create_associated_token associated_token_create_idempotent(
    payer,
    associated_account,
    wallet,
    mint
  ) signer_seeds []

  entry create_associated do
    invoke create_associated_token associated_token_create_idempotent(
      payer,
      associated_account,
      wallet,
      mint
    ) signer_seeds [];
    last_created_marker := u64 1;

end ProofForge.Solana.Examples.AssociatedTokenCpi
