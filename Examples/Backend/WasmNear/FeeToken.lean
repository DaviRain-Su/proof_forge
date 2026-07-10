/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

NEAR-comparable fee-on-transfer token body for testkit/compare.

Product `Examples/Product/FeeToken.lean` is TokenSpec intent (Solana fee plan).
This module is the EmitWat-capable surface used for near-sdk dual-deploy:

  - init(fee_bps)
  - mint(to, amount)
  - transfer(to, amount) — burns fee_bps/10000 of amount from supply
  - balanceOf / totalSupply views

Compile:
  lake env proof-forge build --target wasm-near --root . \
    -o build/wasm-near/FeeToken Examples/Backend/WasmNear/FeeToken.lean
-/
import ProofForge.Contract.Source

namespace Examples.Backend.WasmNear.FeeToken

open ProofForge.Contract.Source

contract_source FeeToken do
  state totalSupply : .u64
  state feeBps : .u64

  mapping balances from .u64 to .u64

  event Transfer
  event Mint

  entry init (fee_bps : .u64) do
    totalSupply := u64 0;
    feeBps := fee_bps;

  entry mint (recipient : .u64, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount) "zero amount";
    let bal : .u64 := mapRead balances recipient;
    do mapWrite balances recipient (bal +! amount);
    let ts : .u64 := totalSupply;
    totalSupply := ts +! amount;
    emit Mint indexed #[fieldAsName "to" recipient] data #[fieldAsName "amount" amount];

  entry transfer (recipient : .u64, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount) "zero amount";
    let sender : .u64 := caller;
    let srcBal : .u64 := mapRead balances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    let bps : .u64 := feeBps;
    let fee : .u64 := (amount *! bps) /! u64 10000;
    let net : .u64 := amount -! fee;
    do mapWrite balances sender (srcBal -! amount);
    let dstBal : .u64 := mapRead balances recipient;
    do mapWrite balances recipient (dstBal +! net);
    let ts : .u64 := totalSupply;
    totalSupply := ts -! fee;
    emit Transfer indexed #[fieldAsName "from" sender, fieldAsName "to" recipient]
      data #[fieldAsName "amount" net, fieldAsName "fee" fee];

  query balanceOf (who : .u64) returns(.u64) do
    return mapRead balances who;

  query totalSupply returns(.u64) do
    return totalSupply;

  query getFeeBps returns(.u64) do
    return feeBps;

end Examples.Backend.WasmNear.FeeToken
