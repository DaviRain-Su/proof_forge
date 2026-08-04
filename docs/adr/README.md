---
id: ADR-INDEX
title: Architecture Decision Records
status: proposed
owner: architecture
updated: 2026-08-04
normative: true
---

# Architecture Decision Records

状态：`proposed`
更新日期：2026-08-04

ADR 是 V2 架构决定的最高规范性记录。frontmatter 生命周期统一使用
`draft | proposed | in_review | accepted | superseded | archived`；未采纳的提案使用 `archived`
并在正文记录 decision=`rejected`，不得发明独立 document status。修改 accepted 决定必须新增
ADR，并在旧 ADR frontmatter 中记录 `successor`，不得静默改写历史。

| ID | 决定 | 状态 |
|---|---|---|
| [ADR-0001](0001-isolated-v2.md) | 独立 V2 工程 | proposed |
| [ADR-0002](0002-unified-program-dsl.md) | 统一 `program ... where` DSL | proposed |
| [ADR-0003](0003-target-selects-materialization.md) | target 选择物化，源码无类别 | proposed |
| [ADR-0004](0004-semantic-core-and-target-plan.md) | 语义 Core 与 target Plan 分离 | proposed |
| [ADR-0005](0005-exact-capabilities-and-extensions.md) | 精确能力/扩展，默认拒绝 | proposed |
| [ADR-0006](0006-associated-plan-and-ir.md) | 关联 Plan/TargetIR 不擦除 | proposed |
| [ADR-0007](0007-wasm-encoding-not-host-semantics.md) | Wasm 只共享编码层 | proposed |
| [ADR-0008](0008-separate-zk-execution-models.md) | circuit、zkVM、ZK 链分离 | proposed |
| [ADR-0009](0009-separate-target-codegen-network-profiles.md) | Target/Codegen/Network profile 分离 | proposed |
| [ADR-0010](0010-artifact-contract-and-provenance.md) | 制品契约与来源 | proposed |
| [ADR-0011](0011-static-target-registry.md) | 静态目标注册表 | proposed |
| [ADR-0012](0012-parent-research-only.md) | 父项目仅作研究参考 | proposed |
| [ADR-0013](0013-content-addressed-tools-and-host-profile.md) | 内容工具闭包与受信 host profile 分离 | proposed |
| [ADR-0014](0014-pinned-unicode-normalization.md) | 固定 Unicode 17.0.0 与纯 Lean NFC | proposed |
| [ADR-0015](0015-canonical-tool-lock-and-candidate-bound-sbom.md) | Tool Lock 唯一摘要与 candidate-bound SBOM | proposed |
| [ADR-0016](0016-cross-platform-host-profile-and-linux-eligibility.md) | 跨平台 Host Profile、per-platform Tool Lock 与 Linux eligibility | proposed |
| [ADR-0017](0017-research-phase-targets-ton-move-cairo-zkvm.md) | 研究期新增目标 TON/TVM、Move、Cairo、RISC Zero/SP1 | proposed |
| [ADR-0018](0018-d0-07-formal-execution-semantics.md) | D0-07 formal 执行语义：fixture 验收域、linux bwrap stage 引擎、freshness 判定与 finalizer 身份 | accepted |
| [ADR-0019](0019-single-programv1-source-authority.md) | ProgramV1 单一 source authority 与 alpha cutover | accepted |
| [ADR-0020](0020-task-scoped-formal-qualification.md) | 任务作用域 formal qualification 与 release aggregate 分离 | accepted |
| [ADR-0021](0021-task-qualification-terminal-signing.md) | Task qualification protected acceptance 的一次性终结签名 | accepted |
| [ADR-0022](0022-d1-diagnostics-contained-frontend-contract.md) | D1 diagnostic / contained-frontend 工程契约（parser 1.0.0 default、containment class、receipts、DiagnosticOriginV1） | proposed |
| [ADR-0023](0023-aleo-target-integration.md) | Aleo（Leo 4.0.2）capability-gated target 集成（第 5 个 implemented target；source-only） | proposed |
| [ADR-0024](0024-ton-target-integration.md) | TON（Tolk 1.4.2 / TVM）capability-gated target 集成（第 8 个 implemented target；source-only；sync call fail closed） | proposed |
| [ADR-0025](0025-evm-caller-principal-realization.md) | EVM `context.caller` Principal realization encoding contract（`u32le(20)\|\|CALLER`；shared wire 不变；Plan 仍 FC 至原子 cutover） | accepted |
| [ADR-0026](0026-quint-target-integration.md) | Quint（executable specification / model surface）capability-gated target 集成（第 9 个 implemented target；source-only；zero-tool finalize；Q0 UInt64 子集） | proposed |
| [ADR-0027](0027-inline-same-file-theorem-certification.md) | Inline same-file theorem certification（单 snapshot；hash 不含 body；in-process 非 sandbox；固定 axiom；proof gate 早于 materialize；仅 `InvariantTheoremV1`/`StateConformsV1`） | proposed |
| [ADR-0028](0028-solana-explicit-accounts-pda-cpi.md) | Solana 显式账户、PDA/bump 与真实同步 CPI v1 合同（opt-in `solana-sbpf-cpi-elf-v1` product activation；#111–#125） | accepted |
| [ADR-0029](0029-portable-cross-program-interop.md) | Portable 跨程序互通层（L1 shared semantic extensions；词表判据；custody/vault 消隐 PDA；包装层 catalog：target binding catalog + NetworkProfile asset registry；`pf.assets` 草案与 A→D 分期） | proposed |
