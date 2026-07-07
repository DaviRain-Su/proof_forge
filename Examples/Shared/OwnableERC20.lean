/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical shared OwnableERC20 source for stdlib composition.

Compile the same module to target artifacts by changing `--target`:

  lake env proof-forge build --target evm --root . \
    -o build/shared-ownable-erc20/OwnableERC20.bin \
    --yul-output build/shared-ownable-erc20/OwnableERC20.yul \
    --artifact-output build/shared-ownable-erc20/OwnableERC20.proof-forge-artifact.json \
    Examples/Shared/OwnableERC20.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/shared-ownable-erc20/OwnableERC20.s \
    --artifact-output build/shared-ownable-erc20/OwnableERC20.solana-artifact.json \
    Examples/Shared/OwnableERC20.lean

NEAR/Wasm currently keeps address-keyed map composition behind backend
capability validation; this file remains the single source for that future
target rather than growing a separate NEAR copy.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Compose
import ProofForge.Contract.Stdlib.Compose.Specs
import ProofForge.Contract.Stdlib.Ownable
import ProofForge.Contract.Stdlib.ERC20

namespace Examples.Shared.OwnableERC20

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

end Examples.Shared.OwnableERC20

namespace OwnableERC20

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Shared.OwnableERC20.spec

def module : ProofForge.IR.Module :=
  spec.module

end OwnableERC20
