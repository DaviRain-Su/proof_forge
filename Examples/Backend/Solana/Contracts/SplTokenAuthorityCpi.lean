import ProofForge.Contract.Source.Solana

namespace Examples.Backend.Solana.Contracts.SplTokenAuthorityCpi

open ProofForge.Contract.Source

contract_source SolanaSplTokenAuthorityCpi do
  state last_authority_marker : .u64

  account mint writable
  account authority readonly signer
  account new_authority readonly

  cpi token_set_authority spl_token_set_authority(
    mint,
    authority,
    new_authority
  ) authority_type("mint_tokens") signer_seeds []

  entry set_authority do
    invoke token_set_authority spl_token_set_authority(
      mint,
      authority,
      new_authority
    ) authority_type("mint_tokens") signer_seeds [];
    last_authority_marker := u64 1;

end Examples.Backend.Solana.Contracts.SplTokenAuthorityCpi
