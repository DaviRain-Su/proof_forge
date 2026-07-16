/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — NEAR NEP-141 *peer* client (fixture)

Calls an **already-deployed** FT via promise/remote + NEP-141 JSON args.

```text
  pay(amount)              → ft_transfer JSON {receiver_id, amount, memo:null}
  pay_with_callback(…)     → ft_transfer_call JSON {receiver_id, amount, msg}
  query_balance            → ft_balance_of JSON {account_id}
  query_supply             → ft_total_supply JSON {}
```

Bind FT peer: `--peer my_ft=token.near`. Receiver/account strings are registered
in the host pool (`alice.near`).
-/
import ProofForge.Contract.Builder
import ProofForge.Protocols.Near.FungibleToken

namespace Examples.Backend.WasmNear.FtPeerClient

open ProofForge.Contract.Builder
open ProofForge.Protocols.Near.FungibleToken

def spec : ProofForge.Contract.ContractSpec :=
  build "NearFtPeerClient" do
    scalarState "last_amount" .u64
    let payMethod ← declareFtTransfer "my_ft"
    let payCallMethod ← declareFtTransferCall "my_ft"
    let balMethod ← declareFtBalanceOf "my_ft"
    let supplyMethod ← declareFtTotalSupply "my_ft"
    let alice ← registerAccountId "alice.near"

    entryWithParams "pay" #[("amount", .u64)] .unit do
      letBind "_p" .u64 (ftTransfer payMethod alice (localVar "amount"))
      effect (storageScalarWrite "last_amount" (localVar "amount"))

    entryWithParams "pay_with_callback" #[("amount", .u64), ("msg_tag", .u64)] .unit do
      letBind "_p" .u64
        (ftTransferCallWithMsg payCallMethod alice (localVar "amount") (localVar "msg_tag"))
      effect (storageScalarWrite "last_amount" (localVar "amount"))

    entryReturns "query_balance" .u64 do
      ret (ftBalanceOf balMethod alice)

    entryReturns "query_supply" .u64 do
      ret (ftTotalSupply supplyMethod)

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.WasmNear.FtPeerClient
