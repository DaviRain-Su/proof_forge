/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical portable StakingVault shared across primary targets.

Users deposit native value (ETH on EVM, lamports on Solana, NEAR on NEAR)
and receive shares proportional to their deposit. Withdraw burns shares
and returns the corresponding native value. The share ratio is 1:1 for
simplicity (no yield/rebase).

This scenario validates that `nativeValue` (attached_deposit / callvalue /
lamports) can be read and transferred in a chain-neutral way.

Compile the same module to EVM, Solana sBPF, and NEAR/Wasm by changing only
`--target`:

  lake env proof-forge build --target evm --root . \
    -o build/staking-vault/StakingVault.bin \
    --yul-output build/staking-vault/StakingVault.yul \
    --artifact-output build/staking-vault/StakingVault.proof-forge-artifact.json \
    Examples/Shared/StakingVault.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/staking-vault/StakingVault.s \
    --artifact-output build/staking-vault/StakingVault.solana-artifact.json \
    Examples/Shared/StakingVault.lean

  lake env proof-forge build --target wasm-near --root . \
    -o build/staking-vault/near \
    --artifact-output build/staking-vault/StakingVault.near-artifact.json \
    Examples/Shared/StakingVault.lean

See `scripts/portable/staking-vault-multi-target.sh` for a checked
end-to-end demo.
-/
import ProofForge.Contract.Source

namespace Examples.Shared.StakingVault

open ProofForge.Contract.Source

contract_source StakingVault do
  state totalDeposits : .u64
  state totalShares : .u64

  mapping shares from .u64 to .u64

  event Deposit
  event Withdraw

  entry init do
    totalDeposits := u64 0;
    totalShares := u64 0;

  entry deposit do
    let amount : .u64 := nativeValue;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref amount) "zero deposit";
    let depositor : .u64 := caller;
    let currentShares : .u64 := mapRead shares depositor;
    do mapWrite shares depositor (currentShares +! amount);
    let td : .u64 := totalDeposits;
    totalDeposits := td +! amount;
    let ts : .u64 := totalShares;
    totalShares := ts +! amount;
    emit Deposit indexed #[fieldAsName "depositor" depositor] data #[fieldAsName "amount" amount];

  entry withdraw (shareAmount : .u64) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref shareAmount) "zero shares";
    let depositor : .u64 := caller;
    let currentShares : .u64 := mapRead shares depositor;
    do ProofForge.Contract.Surface.requireGe (ProofForge.Contract.Surface.ref currentShares)
      (ProofForge.Contract.Surface.ref shareAmount) "insufficient shares";
    do mapWrite shares depositor (currentShares -! shareAmount);
    let td : .u64 := totalDeposits;
    totalDeposits := td -! shareAmount;
    let ts : .u64 := totalShares;
    totalShares := ts -! shareAmount;
    emit Withdraw indexed #[fieldAsName "depositor" depositor] data #[fieldAsName "amount" shareAmount];

  query totalDeposits returns(.u64) do
    return totalDeposits;

  query totalShares returns(.u64) do
    return totalShares;

  query sharesOf (who : .u64) returns(.u64) do
    return mapRead shares who;

end Examples.Shared.StakingVault
