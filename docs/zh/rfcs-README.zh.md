# ProofForge RFCs

RFC 定义了 ProofForge 持久的架构决策。它们在实现前描述预期的能力，并将当前行为与 Research 或未来的后端目标区分开。

流程：提案以 Draft 开始，当记录在 [decisions.md](../decisions.md) 且交叉链接的文档达成一致时转为 **Accepted**。

## 索引

| RFC | 状态 | 摘要 |
|---|---|---|
| [0001](0001-multichain-platform.md) | Accepted | Lean 优先的多链合约平台架构 |
| [0002](0002-target-implementation-design.md) | Accepted | 目标 profile、构建流水线和后端实现设计 |
| [0003](0003-portable-ir-and-runtime.md) | Draft | 可移植 IR、能力降级、运行时 profile |
| [0004](0004-evm-semantic-plan.md) | Accepted | EVM semantic plan 与 Yul AST 边界 |
| [0005](0005-solana-sbpf-assembly-backend.md) | Accepted | Solana sBPF assembly 后端，即绕过 Zig runtime 的 direct codegen 路线 |
| [0006](0006-multichain-token-sdk.md) | Draft | 多链 Token SDK：EVM 上生成 ERC-20，Solana 上生成 SPL Token / Token-2022 计划 |
| [0007](0007-unified-rust-test-framework.md) | Draft | 统一 Rust 测试框架：覆盖 revm/Mollusk/wasmtime harness 的声明式场景 |
| [0008](0008-allocator-abstraction.md) | Draft | 跨 EVM、Solana、NEAR 的链解耦分配器抽象 |
| [0009](0009-cli-product-surface.md) | Accepted | CLI 产品形态：`build|emit|check --target <id> --fixture <id>`；M1/M3 已落地，M4 迁移仍开放 |
| [0010](0010-resource-budgets-as-gates.md) | Draft | 将资源预算（gas / CU / near-gas）作为 testkit 门控 |
| [0011](0011-runtime-error-model-and-client-generation.md) | Draft | 可移植运行时错误模型 + 统一客户端生成 |
| [0012](0012-versioning-and-compatibility-policy.md) | Draft | 版本控制与兼容性策略（IR、制品 schema、能力 id、SDK） |
| [0013](0013-deployment-lifecycle-upgrades-and-signing.md) | Draft | 部署生命周期、升级与签名边界 |
| [0014](0014-unified-semantic-lowering-contract.zh.md) | Draft | 跨后端的统一语义 lowering 契约（validate → *ModulePlan → AST + `*-semantic-plan` 校验门） |

## 相关

- [文档索引](../INDEX.md)
- [设计决策](../decisions.md)
- [实现待办事项](../implementation-backlog.md)
- [目标说明](../targets/README.md)
- [中文文档](../zh/README.md)
