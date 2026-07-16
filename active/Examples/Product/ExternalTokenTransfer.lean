/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Product protocol intent — external fungible token peer

Authors call an already-deployed ecosystem token without importing
`ProofForge.Protocols.*`. Method packing is plan/materialize only:

  --target evm              → IERC20 CALL selectors
  --target wasm-near        → NEP-141 promise + JsonEncode
  --target solana-sbpf-asm  → portable CPI smoke (not live Tokenkeg layout)

```bash
just product-protocol-ft
```

Bind peer at deploy: `--peer usdc.peer=…`.
-/
import ProofForge.Contract.Source

namespace Examples.Product.ExternalTokenTransfer

open ProofForge.Contract.Source

contract_source ExternalTokenTransfer do
  external_token usdc "usdc.peer";

  state last_amount : .u64

  entry «initialize» do
    last_amount := u64 0;

  entry pay (recipient : .u64, amount : .u64) returns(.u64) do
    let _ok : .u64 := externalTokenTransfer usdc recipient amount;
    last_amount := amount;
    return amount;

  entry set_allowance (spender : .u64, amount : .u64) returns(.u64) do
    let _ok : .u64 := externalTokenApprove usdc spender amount;
    last_amount := amount;
    return amount;

  entry read_balance (holder : .u64) returns(.u64) do
    return externalTokenBalanceOf usdc holder;

  entry read_supply returns(.u64) do
    return externalTokenTotalSupply usdc;

end Examples.Product.ExternalTokenTransfer
