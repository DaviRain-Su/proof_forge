/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Product — deployable ERC-4626 vault body (Layer C)

You *are* the vault (stdlib mixin). Honest bounds: **pro-rata** exchange rate,
optional **entry+exit feeBps**, **fee-on-transfer** on pull/push (vault deltas)
and **recipient** up-delta on user withdraw/redeem, `mint` net shares, IERC20
pull/push, `vaultSelf` init. For *calling* a peer vault use `external_vault`.

```bash
just product-erc4626-vault
```
-/
import ProofForge.Contract.Stdlib.ERC4626
import ProofForge.Contract.Spec
import ProofForge.IR.Contract

namespace Examples.Product.ERC4626Vault

/-- Thin product re-export of the stdlib vault body (Layer C). -/
def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.ERC4626.spec

def module : ProofForge.IR.Module :=
  ProofForge.Contract.Stdlib.ERC4626.module

end Examples.Product.ERC4626Vault
