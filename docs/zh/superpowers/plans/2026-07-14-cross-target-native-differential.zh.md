# 跨目标原生差分验证实施计划

状态：**已接受；CMP-0/CMP-1 已完成，CMP-2 等待 A-CUT2g（2026-07-14）**

设计文档：[跨目标原生差分验证设计](../specs/2026-07-14-cross-target-native-differential-design.zh.md)

## 执行规则

这是验证轨道，不替代当前架构队列。A-CUT1e-c2、CMP-0 与 CMP-1 已完成。现在由 A-CUT2g 删除剩余 public authored Legacy exchange，之后再执行 CMP-2；CMP-3 仍属于 A-CUT3 验收。Target-extension 测试附着在对应 target 的迁移任务上，不能借此提前开启无关 backend 工作。

状态只能使用 `pending`、`in_progress`、`blocked` 和 `done (verified at <sha>)`。每个完成任务必须记录精确门禁并更新 implementation log。

## 当前资产

| 资产 | 当前状态 | 处理方式 |
|---|---|---|
| `testkit/scenarios` | 13 个 portable v0 scenario | 在 CMP-1/CMP-2 迁移 logical step |
| `testkit/compare/near` | 28 个 Rust v0 reference 以及 offline/Sandbox runner；历史矩阵仅限 measurement | 增量替换 v0 manifest 与 observation |
| `references/solana/pinocchio` | 7 个 Rust v0 reference 以及 14 个 static/live script | 保留为 Solana extension 目录，并在 CMP-SOL 替换 v0 manifest |
| Stylus differential scripts | 5 个 focused Rust/direct-Wasm compare 以及 VM/host runner；没有 v1 native-reference manifest | 主三链 schema 稳定后适配 |
| EVM runtime gates | 3 份手写 Solidity 源码以及 `revm`、Foundry、Anvil 执行；没有归一化 v1 result | 在 CMP-2/CMP-EVM 固定 provenance 并配对 reference |

## 任务顺序

### CMP-0 - 冻结资产清单与共享契约

状态：`done (verified at 18f15e59)`

- 盘点所有 native reference、runner、manifest schema、scenario 和 CI gate，并诚实标记历史 measurement-only 报告。
- 定义版本化 reference provenance、logical scenario、normalized observation、required coverage 和 allowed divergence schema。
- validator 必须拒绝缺少来源、重复 step ID、未知 observation dimension，以及 coverage 不完整却声称 semantic success 的数据。
- 为现有 NEAR v0 和 Solana v0 manifest 提供显式迁移 adapter；validator 完成前不做全量机械重写。

验收：生成的 inventory 完整列出 NEAR、Solana、Stylus 和 EVM 比较资产；合法旧 manifest 可显式迁移，畸形 fixture 失败；编译器和 target plan 不导入比较 schema。

完成证据：

- `testkit/differential/inventory.v1.json` 确定性列出 NEAR、Solana、Stylus、
  EVM 及 portable scenario/CI 层的 85 项受跟踪资产；
  `semanticVerifiedCount` 为零，不会提升现有 partial evidence。
- 四个检入的 v1 JSON schema 与 `scripts/differential/contracts.py` 强制验证
  provenance、唯一 step ID、封闭 observation dimension、精确 coverage、runner
  状态和 fail-closed semantic promotion。
- 显式 NEAR v0 与 Solana v0 migration function 验证当前全部 28 和 7 份
  manifest。缺失历史字段被记录为 inference 和 incomplete provenance；迁移后的
  observation 保持 skipped，绝不会成为 semantic success。每个 target 迁移到 v1
  后必须删除这些测试数据 migration；它们不是编译器兼容路线。
- `just differential-contracts` 通过 11 个 schema/malformed/migration/boundary
  测试、生成 inventory 检查和 NEAR matrix snapshot 测试。

### CMP-1 - 归一化 observation runner 契约

状态：`done (verified at 7fee238c)`

- 统一 call status/error、typed return、state、event、target-owned external action、interface assertion 和 resource result。
- 定义 actor、account、value 和 clock 归一化，但不抹掉 target 原生差异。
- 每个 scenario 和 runner 必须声明 coverage。
- Target adapter 只翻译原生观测，不重新解释编译器语义。

验收：合成测试证明完全匹配通过，任一维度不匹配失败，缺失必需观测不能得到 `semanticMatch=true`；资源不能被合成为虚假的跨链总分。

完成证据：

- `proof-forge.differential.runner-result.v1` 定义 typed logical value、account、
  actor、clock、runner status、declared coverage 和逐 step observation，且不进入
  compiler module。
- Comparator 独立检查全部八个 observation dimension，要求 declared/actual
  coverage 精确，拒绝未分类错误，并把 allowed divergence 限制到精确 dimension
  与 JSON path。
- 跨 target external action 比较 logical payload，同时保留 target-owned native
  payload。Resource observation 只在同一个 target family 内比较，并禁止暴露
  aggregate cross-chain score。
- `just differential-contracts` 通过 11 个基础 contract 测试、12 个 runner/
  comparator 测试、90 项 inventory 检查和 NEAR matrix snapshot。

### CMP-2 - Counter 主三链原生试点

状态：`pending after A-CUT2g; required by A-CUT2 completion`

- ProofForge 侧只使用未改写的 `Examples/Product/Counter.lean`。
- 独立 reference：EVM 使用 Solidity，Solana 使用 Pinocchio/native Rust，NEAR 使用 `near-sdk` Rust。
- 在确定性 runner 中以等价 actor 和输入执行 initialize/increment/get。
- 比较状态、返回值、错误、必要 log、artifact metadata 和 target 本地资源。
- 证明 ProofForge 侧直接经过 Authored/Canonical，不经过 `ContractSpec`、`IR.Module` 或 Legacy adapter。

验收：主三链必需 observation coverage 完整且 semantic match；每份 manifest 固定来源、license 和工具链；focused pilot 不需要执行完整 `just check`。

### CMP-3 - Stateful 可移植产品扩展

状态：`pending after CMP-2; attached to A-CUT3`

- 先加入 ValueVault。
- 再分别选择 authorization、map/collection、event/error 和 portable crosscall intent 的代表场景。
- 复用 `Examples/Product`，禁止 target-specific Product copy。
- 不支持的 capability 必须产生具名编译失败，不能静默 skip。

验收：ValueVault 在主三链通过状态快照和负面用例；每个代表族有明确 observation contract 和诚实 support matrix；A-CUT3 不能仅靠 golden artifact 宣称迁移完成。

### CMP-SOL - Solana extension conformance

状态：`pending with IR-B5`

- 将现有 Pinocchio reference 迁移到共享 provenance/observation contract。
- 增加从公共 authoring 入口产生 Account、PDA、CPI、signer/writable/order 和 instruction payload 的场景。
- 先比较 plan/manifest，再在工具可用时比较 Mollusk 或 Surfpool 行为。

验收：ProofForge artifact 来自在 target 选择后解析的 typed Solana extension；独立 Rust reference 与 ProofForge 运行同一输入并比较 account/state/CPI；共享 IR 不增加 Solana constructor。

### CMP-NEAR - NEAR 原生参考重放

状态：`pending with NEAR-R4`

- 复用现有 `near-sdk` reference 目录和 Sandbox harness。
- 补齐参数、caller、return、log、storage、promise/action 和负面错误观测。
- ProofForge 侧必须从 canonical-only 公共路线重建后才能接受历史行为结论。

验收：Counter、ValueVault 和 N-T1 至 N-T4 代表合约从新路线通过 fail-closed compare；历史 measurement-only 报告继续排除在语义排名外；receipt scheduling 必须使用 Sandbox/node 证据，不能只依赖 `near-vm-runner`。

### CMP-EVM - Solidity reference 目录

状态：`pending after CMP-2; may proceed with A-CUT3 EVM slices`

- 为 Counter、ValueVault 及代表性 ABI/event/revert/call/storage 场景增加独立 Solidity reference。
- 固定 `solc` 与 reference 来源，在同一 `revm` 或 Anvil 场景执行两份 artifact。
- Yul shape 和 bytecode 门禁继续作为结构检查，不作为语义 oracle。

验收：原生 EVM reference 使用 Solidity，Rust 模型必须标记为 secondary；按场景比较 returndata、storage、log、revert 和 gas band。

### CMP-STYLUS - Stylus reference 统一

状态：`pending after primary-triad CMP-2/CMP-3`

- 将已有 `stylus-sdk` Rust differential gate 适配到共享 manifest 和 observation contract。
- 保留独立 `StylusPlan`，不能因为同为 Wasm 就路由到 NEAR plan。

### CMP-CI - 分层执行与晋级策略

状态：`pending after CMP-2`

- 增加只运行 schema/static/VM differential 的 affected-path 快速命令。
- node/sandbox/live dual-deploy 保留在 target-specific lane，并明确工具前置条件和 evidence artifact。
- 不把 heavyweight live suite 加入每个开发切片。
- capability 对外宣称 implemented 前，至少要有一个独立 native-reference 或 VM behavior gate。

验收：本地 inner loop focused 且确定性；CI 区分 skipped tool 与 passed compare；IR-B8/A-CUT5 使用在缺失 coverage 时 fail closed 的生成矩阵签署。

## 与当前队列的合并顺序

| 顺序 | 工作 | 比较要求 |
|---:|---|---|
| 1 | A-CUT1e-c2 | 使用现有 Solana canonical 与 Pinocchio 证据，不等待 CMP 框架统一 |
| 2 | CMP-0 | 在新增 reference 前冻结 schema 和 inventory |
| 3 | A-CUT2 + CMP-1/CMP-2 | direct authoring cutover 与 Counter native pilot 一起完成 |
| 4 | A-CUT3 + CMP-3/CMP-EVM | 产品迁移逐步加入 stateful native evidence |
| 5 | IR-B5 + CMP-SOL | Solana target extension 获得独立 Rust conformance |
| 6 | NEAR-R4 + CMP-NEAR | canonical-only NEAR artifact 重放现有 reference 目录 |
| 7 | IR-B8/A-CUT5 + CMP-CI | Legacy 删除和边界关闭要求 fail-closed matrix |
| 8 | CMP-STYLUS 和后续 target | 采用稳定契约，不扰动主迁移顺序 |

## 提交纪律

每个任务按 schema/validator、单个 target adapter、单个 scenario/reference、CI wiring 分成可审查提交。开发期间只运行受影响 focused gate；完整 `just product` 或 `just check` 只用于集成检查点。
