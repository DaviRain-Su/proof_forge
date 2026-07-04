/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Counter implementation intended for deployment behind `UUPSProxy`.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Stdlib.UUPSUpgradeable

namespace CounterUUPSImpl

open ProofForge.Contract.Source
open ProofForge.Contract.Stdlib.UUPSUpgradeable

contract_source CounterUUPSImpl do
  upgrade_policy_authority admin;
  import ProofForge.Contract.Stdlib.UUPSUpgradeable;

  state count : .u64

  entry init do
    «owner» := caller;
    count := u64 0;

  entry increment do
    let n : .u64 := count;
    count := n +! u64 1;

  query get returns(.u64) do
    return count;

end CounterUUPSImpl
