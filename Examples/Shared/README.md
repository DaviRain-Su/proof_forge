# Shared Portable Examples

`Examples/Shared` is the canonical place for reusable `contract_source`
examples. A shared example keeps business logic in one Lean file and lets
`proof-forge build --target ...` choose the chain artifact.

Target directories such as `Examples/Evm`, `Examples/Solana`, and
`Examples/WasmNear` should only keep chain-specific fixtures, golden files, and
compatibility entrypoints. New portable product examples should start here.

## Primary Multi-Target Examples

These examples are checked as one source across EVM, Solana sBPF, and
NEAR/Wasm:

| Example | Source | Checked demo |
|---|---|---|
| Counter | [Counter.lean](Counter.lean) | `just portable-counter-multi-target` |
| ValueVault | [ValueVault.lean](ValueVault.lean) | `just portable-value-vault` |
| RoleGatedToken | [RoleGatedToken.lean](RoleGatedToken.lean) | `scripts/portable/role-gated-token-multi-target.sh` |
| StakingVault | [StakingVault.lean](StakingVault.lean) | `scripts/portable/staking-vault-multi-target.sh` |

Each file carries the concrete `evm`, `solana-sbpf-asm`, and `wasm-near`
commands in its header. The compiler test fixtures with equivalent Counter and
ValueVault semantics live in `ProofForge/Contract/Examples/`.

## High-Level Intent Examples

These examples are not protocol-specific contract code. They describe a
product-level intent once and let target routing choose the chain form:

| Example | Source | Current target status |
|---|---|---|
| FungibleToken | [FungibleToken.lean](FungibleToken.lean) | `TokenSpec` lowers to an EVM ERC-20-compatible artifact or a Solana SPL Token / Token-2022 plan; NEAR token lowering is still gated |

The source does not mention ERC-20, SPL Token, Token-2022, or NEP-141. Those
names are target outputs chosen below the shared intent layer.

Legacy `.learn` examples remain parser/equivalence fixtures. New product
examples should use ordinary `.lean` files with `contract_source` or a
higher-level intent SDK such as `TokenSpec`.
