/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

E1.4 negative fixture: authority policy paired with a UUPS proxy pattern.
The proxy transport exists, but EVM does not yet bind the declared keyRef to
runtime authorization, so the product build must fail closed.
-/
import ProofForge.Contract.Source

namespace BadUpgradeAuth

open ProofForge.Contract.Source

contract_source BadUpgradeAuth do
  upgrade_policy_authority admin;
  proxy_pattern_uups;

  state x : .u64

  entry set (v : .u64) do
    x := v;

end BadUpgradeAuth
