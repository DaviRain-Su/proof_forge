# 跨目标原生差分验证实施计划

状态：**已接受；CMP-0/CMP-1/CMP-2 已完成，CMP-3 进行中（2026-07-14）**

设计文档：[跨目标原生差分验证设计](../specs/2026-07-14-cross-target-native-differential-design.zh.md)

## 执行规则

这是验证轨道，不替代当前架构队列。A-CUT1e-c2、CMP-0、CMP-1 以及
A-CUT2/CMP-2 已完成。CMP-3 现在验证 ValueVault cutover，并属于 A-CUT3 验收。
Target-extension 测试附着在对应 target 的迁移任务上，不能借此提前开启无关
backend 工作。

状态只能使用 `pending`、`in_progress`、`blocked` 和 `done (verified at <sha>)`。每个完成任务必须记录精确门禁并更新 implementation log。

## 当前资产

| 资产 | 当前状态 | 处理方式 |
|---|---|---|
| `testkit/scenarios` | 13 个 portable v0 scenario | 在 CMP-1/CMP-2 迁移 logical step |
| `testkit/compare/near` | 28 个 Rust v0 reference 以及 offline/Sandbox runner；历史矩阵仅限 measurement | 增量替换 v0 manifest 与 observation |
| `references/solana/pinocchio` | 7 个 Rust v0 reference 以及 14 个 static/live script | 保留为 Solana extension 目录，并在 CMP-SOL 替换 v0 manifest |
| Stylus differential scripts | 5 个 focused Rust/direct-Wasm compare 以及 VM/host runner；没有 v1 native-reference manifest | 主三链 schema 稳定后适配 |
| EVM runtime gates | Counter 已有固定的 Solidity v1 reference 与归一化 Anvil result；另两份手写源码仍为 partial | 随 A-CUT3 family 在 CMP-3/CMP-EVM 中迁移剩余 reference |

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

状态：`done (verified at e2834c59)`

Direct route 前置证据：`42183403` 证明 public Source/Loader、EVM、Solana
assembly/ELF 与 NEAR/Wasm 直接消费 Authored/Core/target plan，不产生
ContractSpec sidecar，也没有 Legacy fallback。`just portable-counter-multi-target`
和各 target 的 Counter testkit runner 已通过；CMP-2 需要把独立 native reference
接到 v1 observation/comparator contract。
A-CUT2h 提交 `b2d673b4` 还证明旧 Counter Product alias 与 backend ContractSpec
wrapper 均已删除；EVM constructor 证据仅在选择 EVM 后从 target-owned attachment
加载。

- ProofForge 侧只使用未改写的 `Examples/Product/Counter.lean`。
- 独立 reference：EVM 使用 Solidity，Solana 使用 Pinocchio/native Rust，NEAR 使用 `near-sdk` Rust。
- 在确定性 runner 中以等价 actor 和输入执行 initialize/increment/get。
- 比较状态、返回值、错误、必要 log、artifact metadata 和 target 本地资源。
- 证明 ProofForge 侧直接经过 Authored/Canonical，不经过 `ContractSpec`、`IR.Module` 或 Legacy adapter。

验收：主三链必需 observation coverage 完整且 semantic match；每份 manifest 固定来源、license 和工具链；focused pilot 不需要执行完整 `just check`。

完成证据：

- `just differential-counter` 通过 direct Authored/checked Core target plan
  构建未改写的 Product Counter，并拒绝任何 ContractSpec sidecar。EVM 与 Solana
  分别在 Anvil 和 Mollusk 执行；ProofForge 与 near-sdk Wasm 都在未修改的
  upstream NEAR VM 上执行。
- 三份 v1 reference manifest 固定 SHA-256 source revision、Apache-2.0 和精确
  compiler/framework toolchain。Pinocchio reference 的 `get` 已通过真实 Solana
  return-data syscall 返回结果。
- EVM、Solana、NEAR 均覆盖全部八个 observation dimension，
  `semanticMatch=true` 且没有未允许 mismatch。target-local gas/CU 差异只保留在
  四个精确 resource path 下，不会聚合为跨链分数。
- 生成 inventory 现有 96 项资产；三份 reference、v1 scenario、deterministic
  runner 和 focused gate 是六项 verified CMP-2 资产。比较代码仍位于
  `ProofForge/` 之外。

### CMP-3 - Stateful 可移植产品扩展

状态：`in_progress; attached to A-CUT3`

- ValueVault 公开源码现已只走 direct Authored/checked Core，并可在三个主目标
  编译。将其作为首个 stateful native scenario；Legacy artifact 不具备比较资格。
- 补齐缺失的独立 Solana Rust ValueVault reference；不允许用 skip 或
  ProofForge 生成的 sBPF 充当原生证据。
- 再分别选择 authorization、map/collection、event/error 和 portable crosscall intent 的代表场景。
- 复用 `Examples/Product`，禁止 target-specific Product copy。
- 不支持的 capability 必须产生具名编译失败，不能静默 skip。

检查点（2026-07-14）：13 步 v1 ValueVault 场景现已固定 stateful 生命周期、
八类 observation 和 arithmetic underflow 拒绝。独立 Pinocchio 实现及完整
Solana v1 provenance manifest 已提交并通过 host typecheck。Inventory 将这两项
登记为 `semanticEvidence=none`；下一切片必须补齐 Solidity/near-sdk reference，
并在三个 VM 上分别执行原生与 ProofForge artifact 后才能晋级。

Reference 检查点（2026-07-14）：手写 Solidity 与 near-sdk 实现现已覆盖全部
七个方法、五类事件、snapshot 和 checked arithmetic 拒绝。对应 v1 manifest
分别固定 `solc` 0.8.30 与 near-sdk 5.28.3/Rust 1.94；原生 Solidity 编译、
near-sdk host 生命周期测试和 release Wasm 编译均通过。在共享
Anvil/Mollusk/near-vm-runner comparison 执行前，三份 reference 保持
`semanticEvidence=none`。

ValueVault 执行检查点（2026-07-14）：`just differential-value-vault` 现在把
direct Authored Product 源码经 checked Core 和 target-owned plan 构建，再在
Anvil、Mollusk 与 upstream NEAR VM 上执行两侧实现。全部 13 个 logical step
（包括被拒绝的 `release(201)`）覆盖八个 observation dimension，并在 EVM、
Solana、NEAR 上报告 `semanticMatch=true`。原生 Solidity 的 `uint64` ABI 与
ProofForge EVM 的 `uint256` ABI 仍是 target-local 调用细节，runner 将二者
归一化为同一个 portable `u64` interface；没有新增 compiler adapter 或
fallback。生成 inventory 现有 102 项资产，其中六项 CMP-3 ValueVault 资产被
晋级，总计 12 项 verified 资产。CMP-3 继续推进 authorization、map/collection、
event/error 和 portable-crosscall 代表场景。

Authorization authoring 检查点（2026-07-14）：A-CUT3b1 只增加 target-neutral
direct Source 操作：portable caller identity、数值零地址以及相等/不等断言。
Focused `just authored-authorization` 门禁证明它们归一化为 Canonical Core 的
`contextRead.sender`、`compare` 和 `assert` 操作，并且无需 `Source.Internal`、
Legacy adapter 或 target-specific frontend 分支即可到达 EVM、Solana、NEAR
target plan。随后 A-CUT3b2 将 Product Ownable 本身切换到这条单一路线，
删除 ContractSpec/v1 alias 与过时 EVM wrapper，并发射携带
`contract-source-authored` / `canonical-core-v1` 的 EVM、Solana 与最终
NEAR Wasm 制品。focused gate 拒绝 legacy sidecar，并证明 NEAR address
carrier 由 Wasm-host plan 所有。独立原生 Ownable 与 Pausable 差分证据均已完成。
Pausable 已在 `50c1c07a` 获得唯一 direct Product source，并在 `98e9996f`
获得完整 VM 证据。ReentrancyGuard 已在 `69499e99` 获得唯一 direct Product
source；CMP-3f 只能比较这条路线，且不得适配任何已退役 Legacy source。

Ownable authorization 执行切片：

| ID | 状态 | 任务 |
|---|---|---|
| CMP-3d1 | done (verified at `6e1df78b`) | 已固定独立 Solidity、Pinocchio、near-sdk Ownable reference 与一个版本化十步逻辑场景。执行前 inventory evidence 保持 `none`。 |
| CMP-3d2 | done (verified at `ce539dce`) | 已在 Anvil、Mollusk 与 upstream `near-vm-runner` 上执行 direct Authored artifact 和原生 reference；比较全部八个必需 dimension，删除已被取代的 Ownable v0 测试 manifest，并且只晋级完整证据。 |

两个切片都不得增加兼容编译路线、把 ProofForge artifact 复用为原生 oracle，
也不得保留已退役的 Product Legacy 路径。

CMP-3d1 完成证据（2026-07-14）：三份 v1 manifest 固定 source SHA-256、
Apache-2.0 与精确原生工具链。逻辑场景覆盖初始化、owner 查询、未授权与零地址
transfer 失败、所有权 transfer、未授权与授权 renounce，以及 renounce 后拒绝重新
初始化。Solidity 通过 `solc` 0.8.30 编译；Pinocchio source 通过 host typecheck，
并由 cargo-build-sbf 3.1.12 / platform-tools v1.52 构建；near-sdk source 通过
host 测试，并由 Rust 1.94.0 构建 Wasm。确定性 inventory 含 106 项资产，但仍
只有 12 项 verified；四项新增 Ownable 资产均为 `semanticEvidence=none`。

CMP-3d2 完成证据（2026-07-14）：`just differential-ownable` 只把
`Examples/Product/Ownable.lean` 经 Authored/checked Core 与三个 target-owned
plan 构建，再通过 Anvil、Mollusk 与 upstream `near-vm-runner` 执行两侧实现。
十步授权生命周期在每个 target 上都报告 `semanticMatch=true`，并完整覆盖 status、
return、state、balance、event、external action、interface 与 target-local resource。
旧 NEAR Ownable v0 manifest 已删除；其 compare 调用方现在显式命名 v1 manifest，
不存在发现 fallback 或迁移 adapter。Inventory 现含 107 项资产，恰有 18 项 verified。

Pausable 状态机执行切片：

| ID | 状态 | 任务 |
|---|---|---|
| CMP-3e1 | done (verified at `c8e417db`) | 已固定独立 Solidity 与 Pinocchio program，把现有 near-sdk reference 提升到完整 v1 provenance，并定义含重复 pause/unpause 失败与状态保持的版本化九步场景。Evidence 保持 `none`。 |
| CMP-3e2 | done (verified at `98e9996f`) | 已在 Anvil、Mollusk 与 upstream `near-vm-runner` 上执行 direct Authored artifact 和原生 reference；全部八个 dimension 匹配，且被替代的 NEAR v0 manifest 已删除。 |

两个切片都不得增加 compiler compatibility path、消费 v1
`ContractSpec`/`IR.Module`，也不得在三个 VM 完成同一场景前晋级 inventory
evidence。

CMP-3e1 完成证据（2026-07-14）：Solidity 0.8.30 编译独立 `uint64`
reference；单账户、8 字节 Pinocchio 状态机通过 host typecheck，并由
cargo-build-sbf 3.1.12 / platform-tools v1.52 构建；near-sdk source 通过三个
host test，并使用 Rust 1.94.0 构建 Wasm。三份 v1 manifest 都匹配已检入 source
SHA-256。生成 inventory 现含 112 项资产，仍恰有 18 项 verified；三份 Pausable
reference 与 scenario 在 CMP-3e2 前保持 `semanticEvidence=none`。

CMP-3e2 完成证据（2026-07-14）：`just differential-pausable` 仅把
`Examples/Product/Pausable.lean` 经 Authored/checked Core 与三个 target-owned
plan 构建。独立 Solidity、Pinocchio 与 near-sdk 实现在 Anvil、Mollusk 和
upstream `near-vm-runner` 上执行与 ProofForge 相同的九步场景。每个 target
均报告 `semanticMatch=true` 和完整八维 coverage；两个非法 transition 都保持
之前的 paused 状态。旧 NEAR Pausable v0 manifest 已删除，剩余 compare 调用方
显式命名 v1 reference，不存在 discovery fallback。Inventory 现含 113 项资产，
恰有 24 项 verified。

ReentrancyGuard lock-state 执行切片：

| ID | 状态 | 任务 |
|---|---|---|
| CMP-3f1 | done (verified at `9772da92`) | 固定独立 Solidity、Pinocchio 与 near-sdk ReentrancyGuard reference，并定义版本化九步场景，覆盖 unlocked 时 release、重复 acquire 和失败后状态保持。全部新增资产保持 `semanticEvidence=none`。 |
| CMP-3f2 | done (verified at `b407b493`) | 已在 Anvil、Mollusk 与 upstream `near-vm-runner` 上执行 direct Authored artifact 和原生 reference；全部八个 dimension 匹配，且被替代的 NEAR v0 manifest 已删除。 |

两个切片都不得让原生 reference 导入 ProofForge compiler module、把
`ContractSpec`/`IR.Module` 适配回 Product 路线、复用生成的 target code 作为
oracle，也不得在 VM 证据落地后保留被取代的 v0 manifest。

CMP-3f1 完成证据（2026-07-14）：Solidity 0.8.30 编译独立 `uint64` lock
policy；单账户、8 字节 Pinocchio 状态机通过 host typecheck，并由
cargo-build-sbf 3.1.12 / platform-tools v1.52 构建；near-sdk source 通过正向
cycle 与两个负面 host test，并使用 Rust 1.94.0 构建 Wasm。三份 v1 manifest
都匹配已检入 source SHA-256。生成 inventory 现含 118 项资产，仍恰有 24 项
verified；三份 ReentrancyGuard reference 与 scenario 在 CMP-3f2 前保持
`semanticEvidence=none`。

CMP-3f2 完成证据（2026-07-14）：`just differential-reentrancy-guard`
只把 `Examples/Product/ReentrancyGuard.lean` 经 Authored/checked Core 与三个
target-owned plan 构建。独立 Solidity、Pinocchio 与 near-sdk 实现在 Anvil、
Mollusk 和 upstream `near-vm-runner` 上执行与 ProofForge 相同的九步场景。
每个 target 都报告 `semanticMatch=true` 和完整八维 coverage；unlocked 时
release 与重复 acquire 都保持之前的 lock 状态。旧 NEAR ReentrancyGuard v0
manifest 已删除，剩余 compare 调用方显式命名 v1 reference。Inventory 现含
119 项资产，恰有 30 项 verified。CMP-3 下一步为 direct ArrayExample 切换
补充 fixed-array 证据。

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
