import ProofForge.Contract.Source.Solana

namespace Examples.Backend.Solana.Contracts.MemoCpi

open ProofForge.Contract.Source

-- Memo Program CPI fixture:
-- * log_memo: classic 8-byte (u64) payload (regression)
-- * log_memo_bytes: L1.3 multi-byte fixedArray .u8 16 raw payload
contract_source SolanaMemoCpi do
  state last_memo_word : .u64

  cpi memo_call memo(memoArg)
  cpi memo_bytes_call memo(memoBytes)

  entry log_memo(memoArg : .u64) do
    invoke memo_call memo(memoArg);
    last_memo_word := memoArg;

  entry log_memo_bytes(memoBytes : .fixedArray .u8 16) do
    invoke memo_bytes_call memo(memoBytes);

end Examples.Backend.Solana.Contracts.MemoCpi
