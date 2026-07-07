/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EVM stdlib composition fixture: Ownable access control plus ERC-20 token
surface. The chain-neutral token intent example lives in
`Examples/Shared/FungibleToken.lean`.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Compose
import ProofForge.Contract.Stdlib.Compose.Specs
import ProofForge.Contract.Stdlib.Ownable
import ProofForge.Contract.Stdlib.ERC20

namespace OwnableERC20

open ProofForge.Contract.Source
open ProofForge.Contract.Stdlib.Ownable
open ProofForge.Contract.Stdlib.ERC20

contract_source OwnableERC20 do
  compose ProofForge.Contract.Stdlib.Ownable;
  compose ProofForge.Contract.Stdlib.ERC20;

  event Transfer

  entry init (supply : .u64) do
    do ProofForge.Contract.Surface.requireZero «owner» "already initialized";
    «owner» := caller;
    tokenDecimals := u64 18;
    totalSupply := supply;
    let who : .address := caller;
    do mapWrite balances who supply;

  entry ownerMint (recipient : .address, amount : .u64) returns(.bool) do
    guard_owner «owner»;
    let ts : .u64 := totalSupply;
    totalSupply := ts +! amount;
    let bal : .u64 := mapRead balances recipient;
    do mapWrite balances recipient (bal +! amount);
    emit Transfer indexed #[
      fieldAsName "from" (u64 0),
      fieldAsName "to" recipient
    ] data #[
      fieldAsName "value" amount
    ];
    return boolLit true;

end OwnableERC20
