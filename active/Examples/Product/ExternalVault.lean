/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Product protocol intent — external ERC-4626 vault peer

Authors call an already-deployed vault without `Protocols.*` import.

  --target evm → IERC4626 selectors (deposit / convertToShares / …)

The token-intent planner still does **not** generate ERC-4626 *bodies*
(Layer C); this is ecosystem integration only.

```bash
just product-protocol-vault
```
-/
import ProofForge.Contract.Source

namespace Examples.Product.ExternalVault

open ProofForge.Contract.Source

contract_source ExternalVault do
  external_vault vault "vault.peer";

  state last_shares : .u64

  entry «initialize» do
    last_shares := u64 0;

  entry deposit_assets (assets : .u64, receiver : .u64) returns(.u64) do
    let shares : .u64 := externalVaultDeposit vault assets receiver;
    last_shares := shares;
    return shares;

  entry preview_shares (assets : .u64) returns(.u64) do
    return externalVaultConvertToShares vault assets;

  entry read_total_assets returns(.u64) do
    return externalVaultTotalAssets vault;

end Examples.Product.ExternalVault
