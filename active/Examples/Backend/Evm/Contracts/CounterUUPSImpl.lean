/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Backend-only Counter implementation intended for deployment behind `UUPSProxy`.
It exercises the owner-guarded runtime mechanism without declaring the portable
authority policy that the EVM target cannot yet enforce from `keyRef`. Its
zero-state initialization is completed by the proxy constructor, so the
implementation runtime deliberately exposes no public initializer.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Stdlib.UUPSUpgradeable

namespace CounterUUPSImpl

open ProofForge.Contract.Source
open ProofForge.Contract.Stdlib.UUPSUpgradeable

contract_source CounterUUPSImpl do
  import ProofForge.Contract.Stdlib.UUPSUpgradeable;

  state count : .u64

  entry increment do
    let n : .u64 := count;
    count := n +! u64 1;

  query get returns(.u64) do
    return count;

end CounterUUPSImpl
