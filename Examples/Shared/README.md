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

## Shared Stdlib Composition Examples

These examples are also authored once in `Examples/Shared`, but target support
is gated by backend capability coverage:

| Example | Source | Current target status |
|---|---|---|
| SimpleToken | [SimpleToken.lean](SimpleToken.lean) | EVM golden/runtime gates; Solana assembly/package generation; NEAR address-keyed map lowering still gated |
| OwnableERC20 | [OwnableERC20.lean](OwnableERC20.lean) | EVM golden/runtime gates; Solana assembly/package generation; NEAR address-keyed map lowering still gated |
| AccessControlProbe | [AccessControlProbe.lean](AccessControlProbe.lean) | EVM golden/runtime gates; Solana assembly/package generation; NEAR address-keyed map lowering still gated |

The matching paths under `Examples/Evm/Contracts/` are symlink compatibility
entrypoints so existing EVM golden and Foundry scripts keep working while the
canonical source lives here.

Legacy `.learn` examples remain parser/equivalence fixtures. New product
examples should use ordinary `.lean` files with `contract_source`.
