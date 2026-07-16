/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — EVM IERC20 external client (fixture)

Calls an **already-deployed** ERC-20 via CALL + standard selectors.
Not Layer C (`Stdlib.ERC20` / SimpleToken — those *are* the token).

Product index: `docs/protocols-layer.md` · `ProofForge.Protocols.Evm.IERC20`.

```text
  pushTokens(to, amount)  → IERC20.transfer(to, amount)   selector 0xa9059cbb
  readBalance(account)    → IERC20.balanceOf(account)     selector 0x70a08231
```

Peer id `token.peer` is logical; bind at deploy with `--peer token.peer=0x…`
where the host uses a string pool. EVM packs the method id as the 4-byte
selector (`shl(224, selector)` in Yul).
-/
import ProofForge.Contract.Builder
import ProofForge.Protocols.Evm.IERC20

namespace Examples.Backend.Evm.Contracts.Ierc20Client

open ProofForge.Contract.Builder
open ProofForge.Protocols.Evm.IERC20

def spec : ProofForge.Contract.ContractSpec :=
  build "Ierc20Client" do
    scalarState "last_amount" .u64
    let token ← declareToken "token.peer"

    -- Host entry selectors must match ABI (PF selector honesty); peer IERC20
    -- selectors remain on the remoteCall side (0xa9059cbb / 0x70a08231).
    entrySelectorWithParams "pushTokens" "51720e25"
        #[("to", .u64), ("amount", .u64)] .unit do
      letBind "_ok" .u64 (transfer token (localVar "to") (localVar "amount"))
      effect (storageScalarWrite "last_amount" (localVar "amount"))

    entrySelectorWithParams "readBalance" "9f700267"
        #[("account", .u64)] .u64 do
      ret (balanceOf token (localVar "account"))

    entrySelectorReturns "readSupply" "6df137f6" .u64 do
      ret (totalSupply token)

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Evm.Contracts.Ierc20Client
