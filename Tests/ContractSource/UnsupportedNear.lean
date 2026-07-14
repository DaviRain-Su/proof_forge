import ProofForge.Contract.Source.Legacy

namespace Tests.ContractSource.UnsupportedNear

open ProofForge.Contract.Source.Legacy

contract_source UnsupportedNear do
  use ProofForge.Contract.Builder.capability
    ProofForge.Target.Capability.crosscallCpi
    "contract_source.solana_cpi"
    (source? := some "Tests/ContractSource/UnsupportedNear.lean:contract_source.use")

  state count : .u64

  query get returns(.u64) do
    return count;

end Tests.ContractSource.UnsupportedNear
