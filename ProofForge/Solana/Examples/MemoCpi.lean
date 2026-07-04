import ProofForge.Contract.Source

namespace ProofForge.Solana.Examples.MemoCpi

open ProofForge.Contract.Source

contract_source SolanaMemoCpi do
  state last_memo_len : .u64

  cpi memo_call memo(memoArg)

  entry log_memo(memoArg : .u64) do
    invoke memo_call memo(memoArg);
    last_memo_len := memoArg;

end ProofForge.Solana.Examples.MemoCpi