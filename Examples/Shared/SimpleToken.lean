/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical shared SimpleToken source for stdlib composition.

Compile the same module to target artifacts by changing `--target`:

  lake env proof-forge build --target evm --root . \
    -o build/shared-simple-token/SimpleToken.bin \
    --yul-output build/shared-simple-token/SimpleToken.yul \
    --artifact-output build/shared-simple-token/SimpleToken.proof-forge-artifact.json \
    Examples/Shared/SimpleToken.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/shared-simple-token/SimpleToken.s \
    --artifact-output build/shared-simple-token/SimpleToken.solana-artifact.json \
    Examples/Shared/SimpleToken.lean

NEAR/Wasm currently keeps address-keyed map composition behind backend
capability validation; this file remains the single source for that future
target rather than growing a separate NEAR copy.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Compose
import ProofForge.Contract.Stdlib.Compose.Specs
import ProofForge.Contract.Stdlib.Ownable
import ProofForge.Contract.Stdlib.ERC20

namespace Examples.Shared.SimpleToken

open ProofForge.Contract.Source
open ProofForge.Contract.Stdlib.Ownable
open ProofForge.Contract.Stdlib.ERC20

contract_source SimpleToken do
  compose ProofForge.Contract.Stdlib.Ownable;
  compose ProofForge.Contract.Stdlib.ERC20;

  entry init (supply : .u64) do
    do ProofForge.Contract.Surface.requireZero «owner» "already initialized";
    «owner» := caller;
    tokenDecimals := u64 18;
    totalSupply := supply;
    let who : .address := caller;
    do mapWrite balances who supply;

end Examples.Shared.SimpleToken

namespace SimpleToken

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Shared.SimpleToken.spec

def module : ProofForge.IR.Module :=
  spec.module

end SimpleToken
