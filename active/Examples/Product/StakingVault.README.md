# StakingVault Shared Scenario

Deposit native value, earn shares, withdraw. Users call `deposit` with
native value attached (ETH on EVM, NEAR on NEAR) and receive 1:1 shares.
`withdraw` burns shares and returns the corresponding value.

## Three-chain status

| Target | Status | Notes |
|---|---|---|
| `evm` | ✅ Compiles | `nativeValue` reads `callvalue()`; Foundry/Anvil can validate deposit/withdraw |
| `wasm-near` | ✅ Compiles | `nativeValue` reads `attached_deposit` (S5 lowering); WAT emitted with event indexed/data flattening |
| `solana-sbpf-asm` | ✅ Compiles | `nativeValue` stub (returns 0); map storage via linear table (P1b); indexed events flattened (P1a) |

## What this proves

StakingVault validates that `nativeValue` (the chain-native value attached
to a call) can be read in a chain-neutral way across EVM and NEAR. This is
the foundation for any DeFi primitive that accepts deposits (vaults,
staking, AMMs). The `eventEmitIndexed` lowering to NEAR log_utf8 was added
as part of this scenario — indexed events flatten to a single JSON log on
NEAR (the indexed/data distinction is EVM-specific).

Compile:
```sh
lake env proof-forge build --target evm --root . \
  -o build/staking-vault/StakingVault.bin Examples/Product/StakingVault.lean
lake env proof-forge build --target wasm-near --root . \
  -o build/staking-vault/StakingVault Examples/Product/StakingVault.lean
```