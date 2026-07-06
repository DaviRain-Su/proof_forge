import ProofForge.Contract.Source

namespace ProofForge.Contract.Examples.Counter

open ProofForge.Contract.Source

contract_source Counter do
  state count : .u64

  quint_invariant countBounded := "count <= MAX_UINT"
  quint_liveness eventuallyPositive := "eventually(count > 0)"

  entry «initialize» do
    count := u64 0;

  entry increment do
    let n : .u64 := count;
    count := n +! u64 1;

  query get returns(.u64) do
    return count;

end ProofForge.Contract.Examples.Counter
