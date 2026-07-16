import ProofForge.Contract.Source.Solana

namespace Examples.Backend.Solana.Contracts.AccountRealloc

open ProofForge.Contract.Source

contract_source SolanaAccountRealloc do
  state marker : .u64
  account buffer writable owner "program"

  entry grow do
    realloc buffer to 64;
    marker := u64 1;

end Examples.Backend.Solana.Contracts.AccountRealloc
