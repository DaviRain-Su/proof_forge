# RoleGatedToken Shared Scenario

A token with role-gated minting: only accounts holding the `minter` role
can call `mint`. Combines role membership with fungible-token balance and
transfer semantics.

## Three-chain status

| Target | Status | Notes |
|---|---|---|
| `evm` | ✅ Compiles | Full role + token semantics via nested map storage path |
| `wasm-near` | ✅ Compiles | Uses single mapKey storage path (NEAR supports nested paths since S9) |
| `solana-sbpf-asm` | ✅ Compiles | Map storage via fixed-capacity linear table (P1b); userId maps to account[0] |

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
  Examples/Product/RoleGatedToken.lean
```
