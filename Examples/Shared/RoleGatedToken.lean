/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical portable RoleGatedToken shared across primary targets.

This is the first "complex business logic" shared scenario: it combines
role membership with fungible-token balance and transfer semantics, so that
only accounts holding the `minter` role can call `mint`. The same source
compiles to EVM, Solana, and NEAR through target routing.

Compile the same module to EVM, Solana sBPF, and NEAR/Wasm by changing only
`--target`:

  lake env proof-forge build --target evm --root . \
    -o build/role-gated-token/RoleGatedToken.bin \
    --yul-output build/role-gated-token/RoleGatedToken.yul \
    --artifact-output build/role-gated-token/RoleGatedToken.proof-forge-artifact.json \
    Examples/Shared/RoleGatedToken.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/role-gated-token/RoleGatedToken.s \
    --artifact-output build/role-gated-token/RoleGatedToken.solana-artifact.json \
    Examples/Shared/RoleGatedToken.lean

  lake env proof-forge build --target wasm-near --root . \
    -o build/role-gated-token/near \
    --artifact-output build/role-gated-token/RoleGatedToken.near-artifact.json \
    Examples/Shared/RoleGatedToken.lean

See `scripts/portable/role-gated-token-multi-target.sh` for a checked
end-to-end demo.
-/
import ProofForge.Contract.Source

namespace Examples.Shared.RoleGatedToken

open ProofForge.Contract.Source

def adminRole : Nat := 0
def minterRole : Nat := 1

contract_source RoleGatedToken do
  state totalSupply : .u64
  state tokenDecimals : .u64

  mapping balances from .u64 to .u64
  mapping roleMembers from .u64 to .u64

  event Transfer
  event Approval
  event RoleGranted
  event RoleRevoked

  entry init do
    totalSupply := u64 0;
    tokenDecimals := u64 18;
    let admin : .u64 := caller;
    do pathWriteRole roleMembers (u64 adminRole) admin (u64 1);

  query totalSupply returns(.u64) do
    return totalSupply;

  query balanceOf (who : .u64) returns(.u64) do
    return mapRead balances who;

  query hasRole (role : .u64, who : .u64) returns(.bool) do
    let member : .u64 := pathReadRole roleMembers role who;
    return ProofForge.Contract.Surface.ne (ProofForge.Contract.Surface.ref member) (u64 0);

  entry transfer (recipient : .u64, amount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount) "zero amount";
    let sender : .u64 := caller;
    let srcBal : .u64 := mapRead balances sender;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref srcBal)
      (ProofForge.Contract.Surface.ref amount) "insufficient balance";
    do mapWrite balances sender (srcBal -! amount);
    let dstBal : .u64 := mapRead balances recipient;
    do mapWrite balances recipient (dstBal +! amount);
    emit Transfer indexed #[fieldAsName "from" sender, fieldAsName "to" recipient] data #[fieldAsName "amount" amount];

  entry grantRole (role : .u64, who : .u64) do
    guard_role adminRole;
    do pathWriteRole roleMembers role who (u64 1);
    emit RoleGranted indexed #[fieldAsName "role" role, fieldAsName "who" who] data #[];

  entry revokeRole (role : .u64, who : .u64) do
    guard_role adminRole;
    do pathWriteRole roleMembers role who (u64 0);
    emit RoleRevoked indexed #[fieldAsName "role" role, fieldAsName "who" who] data #[];

  entry mint (recipient : .u64, amount : .u64) do
    guard_role minterRole;
    let ts : .u64 := totalSupply;
    totalSupply := ts +! amount;
    let bal : .u64 := mapRead balances recipient;
    do mapWrite balances recipient (bal +! amount);
    emit Transfer indexed #[fieldAsName "from" (u64 0), fieldAsName "to" recipient] data #[fieldAsName "amount" amount];

end Examples.Shared.RoleGatedToken
