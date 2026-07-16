import ProofForge.Contract.Source.Solana

namespace Examples.Backend.Solana.Contracts.SplTokenCloseAccountCpi

open ProofForge.Contract.Source

contract_source SolanaSplTokenCloseAccountCpi do
  state last_close_marker : .u64

  account token_account writable
  account destination writable
  account authority readonly signer

  cpi token_close spl_token_close_account(
    token_account,
    destination,
    authority
  ) signer_seeds []

  entry close_account do
    invoke token_close spl_token_close_account(
      token_account,
      destination,
      authority
    ) signer_seeds [];
    last_close_marker := u64 1;

end Examples.Backend.Solana.Contracts.SplTokenCloseAccountCpi
