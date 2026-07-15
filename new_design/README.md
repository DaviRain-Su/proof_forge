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

当前 `just v2-clean-room-alpha`（`just isolated-check` 为兼容别名）在随机归档目录、空
HOME/cache、受控 PATH 与 macOS 网络沙箱中执行 clean build/test、四目标制品验证、逐字节
复现和 localhost-only EVM runtime。Lean/Lake 与外部工具都从精确 archive/file 进入
content-addressed cache：官方 Lean ZIP 离线物化完整 toolchain；官方 solc 只使用系统库，
WABT 的 `libcrypto` 与 Foundry archive 也在 bundle 中逐文件校验，并验证实际 Mach-O load
closure。首次运行前显式执行 `just toolchains-provision-lean` 和
`just toolchains-provision-external`；`toolchains-materialize-lean` 与
`toolchains-materialize-external` 可用于独立检查物化结果，普通 build 和 clean-room gate
本身不联网。

commit `0b0aebda…643c8` 已完成这条完整 development clean-room gate（archive
`05b5bda6…2115c`）。它仍是 alpha：当前 macOS host profile 报告 `Sealed: Broken`，且
deny-default sandbox 与 schema evidence 尚未完成。因此不能作为正式 hermetic 或 release
evidence。

H0 现已能由外部净化入口先验证固定 bootstrap 与 Xcode bundle，避免启动任何未验证的
Git/Python；随后只启动已锁定的 direct Xcode Python 完成 live host profile observation，
并在 development 模式输出规范化结果。正式模式会 fail closed：当前机器同时因
system-volume seal broken 和 Xcode pathname 可由当前 admin 用户替换而不具备 hermetic 资格。
这不是 remote attestation；deny-default sandbox 与正式 evidence schema 仍未完成，所以
`v2-clean-room-alpha` 仍不是 release gate。

## 文档权威顺序

1. 已接受 ADR 与 PRD。
2. 已接受架构、技术规格和模块规格。
3. 测试规格与可复现证据。
4. 当前代码、制品和实际运行门禁。

调研材料是证据输入，不会自动成为规范。所有开发工作必须遵循
[`docs/governance/change-control.md`](docs/governance/change-control.md)。
