import ProofForge.Contract.Source.Legacy

namespace Tests.ContractSource.NearTimestamp

open ProofForge.Contract.Source.Legacy

contract_source NearTimestamp do
  query now returns(.u64) do
    return timestamp;

end Tests.ContractSource.NearTimestamp
