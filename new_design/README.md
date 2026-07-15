# ProofForge V2 (`proof-forge-next`)

ProofForge V2 是一个独立的 Lean 4 多目标程序编译器设计。作者只写一份
`program ... where` 业务源码，编译器从源码推导语义需求，再由 `--target`
选择 EVM、Solana、NEAR、Noir 或后续平台的物化方式。

当前前端直接使用 Lean 4 parser 产生的 `Syntax`，但不会把 Lean AST 当成领域语义：
`Syntax → Source.Program → Typed.Program → Semantic.Program → target Plan/IR`。CLI
只解析允许的 portable command，不 elaboration/执行用户文件中的任意 Lean command。

```lean
import ProofForgeV2
open ProofForgeV2.Language

program Counter where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count

  view get() : UInt64 do
    return count
```

源码不声明“合约、电路或 zkVM workload”类别。`--target` 只能改变物化和制品，
不能改变整数、状态迁移、回滚、调用顺序、授权或信息披露语义；无法保持语义时，
编译器必须返回稳定诊断而不是降级或回退。

## 当前状态

V2 当前完成了文档/规格基线和一个不可发布的 alpha 骨架。alpha 只验证独立 Lake、
统一入口、Core 与四目标 materializer 的最小连通性，不等于 Phase 1 完成：EVM 已验证
`solc` bytecode，并在 Anvil 验证初始化、increment 与 overflow rollback；NEAR 已验证
`wat2wasm`，但尚无 sandbox receipt 证据；Solana 当前只有 `.s` 与 IDL、没有 ELF/runtime
证据；Noir 当前只有 source 与 Prover input、没有 ACIR/proof/VK/verify 证据。生命周期状态以
[`docs/document-status.md`](docs/document-status.md) 为准，研发入口是
[`AGENTS.md`](AGENTS.md)，文档导航位于 [`docs/index.md`](docs/index.md)。

第一阶段实现范围固定为：

- `evm`
- `solana`
- `near`
- `noir`

CosmWasm、Soroban、Internet Computer、OpenVM、Aleo 和 Psy 本阶段只形成
可实施的目标档案及路线图，不宣称已有后端。

## 独立性

本目录是独立工程，不依赖父项目的源码、构建产物、fixture、脚本或二进制。
父项目只能作为带 commit、路径和观察记录的研究资料，不能成为 V2 的运行时
oracle、兼容入口或失败回退。最终 clean-room 门禁必须能将本目录复制到空目录，
清理父项目相关环境后独立构建和测试。

## 文档权威顺序

1. 已接受 ADR 与 PRD。
2. 已接受架构、技术规格和模块规格。
3. 测试规格与可复现证据。
4. 当前代码、制品和实际运行门禁。

调研材料是证据输入，不会自动成为规范。所有开发工作必须遵循
[`docs/governance/change-control.md`](docs/governance/change-control.md)。
