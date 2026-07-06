# ProofForge RFCs

RFCs define durable architecture decisions for ProofForge. They describe
intended capabilities before implementation, and separate current behavior from
research or future backend targets.

Process: proposals start as Draft, move to **Accepted** when recorded in
[decisions.md](../decisions.md) and cross-linked docs are aligned.

## Index

| RFC | Status | Summary |
|---|---|---|
| [0001](0001-multichain-platform.md) | Accepted | Lean-first multi-chain contract platform architecture |
| [0002](0002-target-implementation-design.md) | Accepted | Target profiles, build pipelines, and backend implementation design |
| [0003](0003-portable-ir-and-runtime.md) | Draft | Portable IR, capability lowering, runtime profiles |
| [0004](0004-evm-semantic-plan.md) | Accepted | EVM semantic plan and Yul AST boundary |
| [0005](0005-solana-sbpf-assembly-backend.md) | Accepted | Solana sBPF assembly backend — direct codegen route bypassing the Zig runtime |
| [0006](0006-multichain-token-sdk.md) | Draft | Multi-chain Token SDK: ERC-20 on EVM, SPL Token / Token-2022 plans on Solana |
| [0007](0007-unified-rust-test-framework.md) | Draft | Unified Rust test framework: declarative scenarios over revm/Mollusk/wasmtime harnesses |
| [0008](0008-allocator-abstraction.md) | Draft | Chain-decoupled allocator abstraction across EVM, Solana, and NEAR |
| [0009](0009-cli-product-surface.md) | Accepted | CLI product surface: `build|emit|check --target <id> --fixture <id>`; M1/M3 landed, M4 transition open |
| [0010](0010-resource-budgets-as-gates.md) | Draft | Resource budgets as testkit gates (gas / CU / near-gas) |
| [0011](0011-runtime-error-model-and-client-generation.md) | Draft | Portable runtime error model + unified client generation |
| [0012](0012-versioning-and-compatibility-policy.md) | Draft | Versioning and compatibility policy (IR, artifact schema, capability ids, SDK) |
| [0013](0013-deployment-lifecycle-upgrades-and-signing.md) | Draft | Deployment lifecycle, upgrades, and signing boundary |
| [0014](0014-unified-semantic-lowering-contract.md) | Draft | Unified semantic lowering contract across backends (validate → *ModulePlan → AST + `*-semantic-plan` gates) |

## Related

- [Documentation index](../INDEX.md)
- [Design decisions](../decisions.md)
- [Implementation backlog](../implementation-backlog.md)
- [Target notes](../targets/README.md)
- [中文文档](../zh/README.md)
