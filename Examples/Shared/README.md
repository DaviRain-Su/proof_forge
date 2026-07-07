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
| ArrayExample | [ArrayExample.lean](ArrayExample.lean) | `just portable-array-example-multi-target` |
| Ownable | [Ownable.lean](Ownable.lean) | `just portable-stdlib-core-multi-target`; shared facade over the canonical stdlib mixin |
| Pausable | [Pausable.lean](Pausable.lean) | `just portable-stdlib-core-multi-target`; shared facade over the canonical stdlib mixin |
| ReentrancyGuard | [ReentrancyGuard.lean](ReentrancyGuard.lean) | `just portable-stdlib-core-multi-target`; shared facade over the canonical stdlib mixin |
| ValueVault | [ValueVault.lean](ValueVault.lean) | `just portable-value-vault` |
| RoleGatedToken | [RoleGatedToken.lean](RoleGatedToken.lean) | `scripts/portable/role-gated-token-multi-target.sh` |
| StakingVault | [StakingVault.lean](StakingVault.lean) | `scripts/portable/staking-vault-multi-target.sh` |

Each file carries the concrete `evm`, `solana-sbpf-asm`, and `wasm-near`
commands in its header. The `ProofForge.Contract.Examples.Counter` and
`ProofForge.Contract.Examples.ValueVault` modules are compatibility aliases for
these shared sources so formal gates and older tests keep stable import paths.

## High-Level Intent Examples

These examples are not protocol-specific contract code. They describe a
product-level intent once and let target routing choose the chain form:

| Example | Source | Current target status |
|---|---|---|
| FungibleToken | [FungibleToken.lean](FungibleToken.lean) | `just token-intent-smoke`; `TokenSpec` lowers to EVM or Solana token artifacts below the shared intent layer; NEAR token lowering is still gated |
| FeeToken | [FeeToken.lean](FeeToken.lean) | `just token-intent-smoke`; `TokenSpec` lowers the transfer-fee intent to a Solana Token-2022 plan while keeping the authored source target-neutral |
| SoulboundToken | [SoulboundToken.lean](SoulboundToken.lean) | `just token-intent-smoke`; `TokenSpec` lowers the non-transferable intent to a Solana Token-2022 plan while keeping the authored source target-neutral |

The sources do not mention ERC-20, SPL Token, Token-2022, or NEP-141. Those
names are target outputs chosen below the shared intent layer.

Legacy `.learn` examples remain parser/equivalence fixtures. New product
examples should use ordinary `.lean` files with `contract_source` or a
higher-level intent SDK such as `TokenSpec`.
