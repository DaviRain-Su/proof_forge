import ProofForge.Contract.Source

namespace Tests.ContractSource.NearTimestamp

open ProofForge.Contract.Source

contract_source NearTimestamp do
  query now returns(.u64) do
    return timestamp;

end Tests.ContractSource.NearTimestamp
