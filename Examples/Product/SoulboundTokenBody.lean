/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Soulbound token **body** (non-transferable balances)

Portable `contract_source` surface for dual-deploy compare. Complements
TokenSpec intent in `SoulboundToken.lean` (Solana Token-2022 plan path).

- Mint / burn / balanceOf / totalSupply
- **No transfer** entry (soulbound honesty)

  lake env proof-forge build --target wasm-near --root . \
    -o build/soulbound-token Examples/Product/SoulboundTokenBody.lean

NEAR compare: `just near-compare-soulbound-token` / `-live`
-/
import ProofForge.Contract.Source

namespace Examples.Product.SoulboundTokenBody

open ProofForge.Contract.Source

contract_source SoulboundTokenBody do
  state totalSupply : .u64
  mapping balances from .u64 to .u64

  event Mint
  event Burn

  entry init do
    totalSupply := u64 0;

  entry mint (recipient : .u64, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount)
      "zero amount";
    let bal : .u64 := mapRead balances recipient;
    do mapWrite balances recipient (bal +! amount);
    let ts : .u64 := totalSupply;
    totalSupply := ts +! amount;
    emit Mint indexed #[fieldAsName "to" recipient] data #[fieldAsName "amount" amount];

  entry burn (amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount)
      "zero amount";
    let who : .u64 := caller;
    let bal : .u64 := mapRead balances who;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref bal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances who (bal -! amount);
    let ts : .u64 := totalSupply;
    totalSupply := ts -! amount;
    emit Burn indexed #[fieldAsName "from" who] data #[fieldAsName "amount" amount];

  query balance_of (who : .u64) returns(.u64) do
    return mapRead balances who;

  query total_supply returns(.u64) do
    return totalSupply;

end Examples.Product.SoulboundTokenBody
