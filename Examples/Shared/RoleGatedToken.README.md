# RoleGatedToken Shared Scenario

A token with role-gated minting: only accounts holding the `minter` role
can call `mint`. Combines AccessControl role membership with ERC-20 token
semantics.

## Three-chain status

| Target | Status | Notes |
|---|---|---|
| `evm` | ✅ Compiles | Full role + token semantics via nested map storage path |
| `wasm-near` | ⚠️ Storage path gap | `pathWriteRole` uses nested `mapKey(role) + mapKey(account)` paths; EmitWat only supports single `mapKey` storage paths. Needs S9 follow-up: multi-segment storage paths in EmitWat. |
| `solana-sbpf-asm` | ⚠️ Caller model gap | `caller` (userId context read) is not supported on Solana (account-based, not EOA). Role checks need Solana account owner constraints, not portable `caller` reads. Needs Solana Target Extension SDK for role-gated entrypoints. |

## What this proves

RoleGatedToken is the first "complex business logic" shared scenario: it
combines two stdlib concepts (roles + tokens) in one contract and validates
that the `contract_source` DSL can express the composition. EVM full
coverage proves the IR → Yul → solc → Foundry pipeline handles the
combination. The NEAR and Solana gaps are honest evidence of where
cross-chain portability meets chain-specific execution models — not
silent failures, but explicit capability limits.

Compile to EVM:
```sh
lake env proof-forge build --target evm --root . \
  -o build/role-gated-token/RoleGatedToken.bin \
  Examples/Shared/RoleGatedToken.lean
```