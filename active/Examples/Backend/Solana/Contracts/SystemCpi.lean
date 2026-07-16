import ProofForge.Contract.Source.Solana

namespace Examples.Backend.Solana.Contracts.SystemCpi

open ProofForge.Contract.Source

contract_source SolanaSystemCpi do
  state last_transfer_lamports : .u64

  account payer writable signer
  account recipient writable

  cpi lamport_transfer system_transfer(payer, recipient, lamports)

  entry transfer(lamports : .u64) do
    invoke lamport_transfer system_transfer(payer, recipient, lamports);
    last_transfer_lamports := lamports;

end Examples.Backend.Solana.Contracts.SystemCpi
