# Gate 完成记录

状态：**Live（2026-07-12 刷新）**

本页是分层目标组合的逐 Gate 完成台账（[target-roadmap](../target-roadmap.md)，
D-034）。每个 Gate 都有一条记录，列出验收标准、逐项状态、证据和签署日期。
只有当所有标准都 **met** 时，Gate 才能 **closed**；任何一个未满足的标准都会
阻塞下一层级。Gate P0 记录主三链完成规约（D-045），它比 G0 的行为/预算切片
更严格。

不同于记录工程里程碑流水的 [development-log](../development-log.md)，本页记录
的是*阶段边界*决策：当前阶段的 Definition of Done 是否已经满足，并且证据可审计。

## Gate A1 —— Portable Intent 与 NFT 纵向切片

**状态：Closed**

**Closed: 2026-07-12**

| # | 标准 | 状态 | 所需证据 |
|---|---|---|---|
| A1-1 | 从 portable `Source` 隔离 Solana 语法 | ✅ met | `52402821` 移动语法；`c1433b2e` 固定 portable 拒绝与 Source.Solana account/PDA/CPI/realloc IR intent；`just solana-light` 和 `just product` 通过 |
| A1-2 | 目标中立的 Intent materializer registry | ✅ met | 私有 registry 构造；`resolveIntentMaterializer`；校验返回 target；`just intent-registry` 纳入 product/check |
| A1-3 | 最小 NFT intent 与实现契约 | ✅ 已满足 | `just nft-intent` 和 `just nft-implementation-contract`；已验证便携 intent 与三个可执行审查候选实现 |
| A1-4 | 主三链严格 NFT 物化 | ✅ met | `just nft-materialization`：EVM、Solana、NEAR 严格 canonical 校验及 `buildFromCore`，无 advisory fallback |
| A1-5 | 产品制品与生命周期运行时证据 | ✅ met | `just portable-nft-multi-target` 证明三套制品；`just portable-nft-runtime` 在 EVM Foundry、Solana Surfpool/SVM 和 NEAR Wasm 上执行 mint、owner/balance、授权 transfer、未授权拒绝和重复 mint 拒绝 |
| A1-6 | 聚合验收 | ✅ met | `6a6022ea`；`just product`、`just portable-nft-runtime`、`just solana-light`、`just check` 和 `git diff --check` 通过 |

## Gate A-CUT1e —— Direct Solana authoring 切换

**状态：Closed**

**Closed: 2026-07-14**

| # | 标准 | 状态 | 证据 |
|---|---|---|---|
| A-CUT1e-1 | Public/internal Solana authoring 不依赖 Legacy builder | ✅ met | `Source.Solana` 只生成一个 `AuthoredContract`；边界搜索确认 public/internal 模块不依赖 `Source.Solana.Legacy`、`ContractSpec` 或 `IR.Module`；`just source-dsl-isolation` 通过 |
| A-CUT1e-2 | Typed target operation 严格进入 plan-only lowering | ✅ met | account/PDA/CPI/allocator/realloc payload fail closed 解码；`SolanaHostOpCatalog`、`SourceDslSolanaAcceptance` 和 `SolanaCpiPacking` 通过 |
| A-CUT1e-3 | Plan-only 制品保留 SDK 与运行时约束 | ✅ met | `SolanaSdkManifest` 和 `SolanaAccountRealloc` 通过；canonical lowering 强制检查 instruction length 与 signer/writable/owner；System、Memo、close-account、authority Pinocchio 结构对比通过 |
| A-CUT1e-4 | 未引入 fallback | ✅ met | 公开 fixture 只暴露 `.contract`；公开 CLI fixture route 使用 `compileSolanaAuthoredSbpf`/`compileSolanaAuthoredElf`；normalization、planning、lowering、package 与 sBPF build 失败均保持终止 |

## Gate CMP-0 —— 原生差分契约与资产清单

**状态：Closed**

**Closed: 2026-07-14**

| # | 标准 | 状态 | 证据 |
|---|---|---|---|
| CMP-0-1 | 受跟踪比较资产清单完整且诚实 | ✅ met | `18f15e59`；生成的 `testkit/differential/inventory.v1.json` 列出 85 项 NEAR、Solana、Stylus、EVM、portable scenario 和 CI 资产，并报告零项 semantic verified 资产 |
| CMP-0-2 | 版本化契约 fail closed | ✅ met | 四个 v1 schema 以及 11 个单元测试拒绝缺失 provenance、重复 step ID、未知 observation dimension、skipped/error runner 以及将 coverage 不完整声称为 semantic success |
| CMP-0-3 | 当前 v0 manifest 具有显式且不会升级状态的 migration | ✅ met | 全部 28 个 NEAR 与 7 个 Solana manifest 通过各自 schema 的函数迁移；推断/缺失 provenance 保持显式，迁移后的 observation 保持 `semanticMatch=false` |
| CMP-0-4 | 比较契约保持在生产架构之外 | ✅ met | 边界测试扫描 `ProofForge/**/*.lean` 中的 comparison schema/import 泄漏；`just differential-contracts` 与 `git diff --check` 通过；migration function 只存在于 `scripts/differential`，并在 v1 转换后删除 |

## Gate CMP-1 —— 归一化 runner result 与 comparator

**状态：Closed**

**Closed: 2026-07-14**

| # | 标准 | 状态 | 证据 |
|---|---|---|---|
| CMP-1-1 | Runner result 分离保存 logical 与 target-native identity | ✅ met | `7fee238c`；typed value 以及 logical account/actor/clock context 比较 portable identity，同时在 evidence 中保留 native account ID、height 和 timestamp |
| CMP-1-2 | 每个 required observation dimension 都 fail closed | ✅ met | 12 个 comparator 测试分别覆盖 call status/error、return、state、balance、ordered event、external action、interface 和 resource mismatch；缺失 coverage、skip/error 与 incomplete provenance 均保持 `semanticMatch=false` |
| CMP-1-3 | Target-owned observation 不会被压平为虚假 equivalence | ✅ met | 跨 target external action 比较 logical payload 并保留 native payload；resource value 只在同一 target family 内比较，aggregate score 字段会被拒绝 |
| CMP-1-4 | 共享 comparator 保持 test-only | ✅ met | runner schema 与实现位于 `testkit/differential` 和 `scripts/differential`；compiler boundary 测试包含 runner schema ID；`just differential-contracts` 通过 23 个 contract/comparator 测试以及 inventory/matrix snapshot |

## Gate A-CUT2g —— Direct public authoring 路线

**状态：Closed**

**Closed: 2026-07-14**

| # | 标准 | 状态 | 证据 |
|---|---|---|---|
| A-CUT2g-1 | Public Source 与 Loader 只交换 `AuthoredContract` | ✅ met | `just public-authored-route` 证明 Counter 与 ValueVault 只导出 `contract`，不导出 `spec`/`module`；internal Surface fixture 使用独立 loader identity，且不存在 Legacy fallback |
| A-CUT2g-2 | 主三链物化绕开 `ContractSpec` 与 `IR.Module` | ✅ met | `just portable-counter-multi-target` 从不变的 Product Counter 构建 EVM、Solana assembly 和 NEAR/Wasm，metadata 为 `contract-source-authored` / `canonical-core-v1`，并拒绝任何 ContractSpec sidecar |
| A-CUT2g-3 | 最终 Solana ELF 同样使用 direct target plan | ✅ met | target-specific Counter testkit 通过 `compileSolanaAuthoredElf` 构建 ELF；initialize/get/increment/get 生命周期在 Mollusk 中通过严格 account 与 instruction-data 校验 |
| A-CUT2g-4 | Target 行为保持可执行 | ✅ met | Counter 的 `evm`、`solana-sbpf-asm`、`wasm-near` 独立 testkit runner 均通过；NEAR offline-host 报告 `0 -> 1`；EVM selector metadata 与 target golden 通过 |
| A-CUT2g-5 | Legacy 是待删除清单，不是兼容层 | ✅ met | direct boundary gate 拒绝 Source/Counter 导入 Legacy；剩余调用方显式导入 public Loader 无法发现的 `Source.Legacy`；不存在 direct-to-Legacy adapter 或 fallback |

## Gate A-CUT2h —— 删除 Counter 反向依赖

状态：**在 `b2d673b4` 关闭**。

| 条件 | 要求 | 状态 | 证据 |
|---|---|---|---|
| A-CUT2h-1 | 不再保留 Product Counter `.spec`/`.module` 旧别名 | ✅ met | `just counter-authoring-cutover` 扫描 production、test、example、script 和 `justfile`；formal/Quint 消费者改用 Authored/checked Core 或显式 v1 fixture |
| A-CUT2h-2 | 删除过时 backend wrapper | ✅ met | EVM `Contracts/Counter.lean`、其重复 golden 以及 Solana `Counter.lean` 均已删除；topology 与 EVM example gate 通过 |
| A-CUT2h-3 | EVM constructor ABI 归 target 所有 | ✅ met | 仅在选择 EVM 后加载 `evmConstructor : ConstructorConfigPlan`；`buildFromCore` 拒绝共享 Canonical constructor payload，并校验参数/存储绑定引用 |
| A-CUT2h-4 | Direct runtime 行为保持 | ✅ met | `just evm-anvil-deploy` 记录 `creationMode: deploy-object`，先读取 `123`，再观测 `0`、`1`、`2`；`just portable-counter-multi-target` 无 ContractSpec sidecar 通过 |
| A-CUT2h-5 | 未新增兼容路线 | ✅ met | public `build`、Yul 和 `check` 均消费 Authored -> checked Core -> EVM plan；direct EVM check 通过，非法共享/target constructor config fail closed |

## Gate A-CUT3a —— ValueVault direct authoring cutover

状态：**已用主三链 native differential 证据关闭；catalog 迁移继续进行**。

| 条件 | 要求 | 状态 | 证据 |
|---|---|---|---|
| A-CUT3a-1 | Product ValueVault 只有一个当前 authoring identity | ✅ met | `just value-vault-authoring-cutover` 证明模块只导出 `contract`；不存在 `.spec`、`.module` 或 `Source.Legacy` Product 路线 |
| A-CUT3a-2 | Portable state、event 与 context 直接进入 checked Core | ✅ met | 显式 typed event schema、named argument 与 `blockNumber` 归一化为 6 个 state、7 个 function、5 个 event，并与内部 Core 基线一致 |
| A-CUT3a-3 | 主目标消费 target-owned plan | ✅ met | focused EVM、Solana、NEAR CLI build 都报告 `contract-source-authored` / `canonical-core-v1`；Solana package 保留 event 与 Clock 物化 |
| A-CUT3a-4 | 删除旧 reverse alias，而不是适配 | ✅ met | production/test 中没有 `ProofForge.Contract.Examples.ValueVault.spec/module` 或 `Examples.Product.ValueVault.module`；历史 v1 proof 显式命名 `ProofForge.IR.Examples.ValueVault` |

## Gate CMP-2 —— 主三链原生 Counter 差分

**状态：Closed**

**Closed: 2026-07-14**

| # | 标准 | 状态 | 证据 |
|---|---|---|---|
| CMP-2-1 | 一份 direct ProofForge 业务源码到达三个 target | ✅ met | `e2834c59`；`Examples/Product/Counter.lean` 为 EVM、Solana、NEAR 生成 `contract-source-authored` / `canonical-core-v1` metadata；focused runner 拒绝 ContractSpec sidecar |
| CMP-2-2 | 独立原生 reference 具有完整 provenance | ✅ met | Solidity、Pinocchio Rust、near-sdk Rust v1 manifest 固定精确 source SHA-256、Apache-2.0 和工具链版本；source digest 过期会使 `just differential-contracts` 与 runtime gate 失败 |
| CMP-2-3 | 原生和 ProofForge artifact 在 target VM 执行 | ✅ met | Anvil 执行两份 EVM artifact，Mollusk 执行两份 sBPF ELF，`near-vm-runner` 通过 upstream NEAR VM logic 执行两份 Wasm artifact |
| CMP-2-4 | 必需语义 fail closed | ✅ met | 每个 target 的八个 dimension 均完整覆盖，`semanticMatch=true`，且没有未允许 mismatch；精确的 target-local gas/CU 差异继续作为 resource 证据保留 |
| CMP-2-5 | 比较不是编译器兼容路线 | ✅ met | schema、manifest、runner 与 report 仅位于 `testkit/`、`scripts/`、`benchmarks/` 和忽略的 `build/`；compiler import boundary test 保持通过 |

## Gate CMP-3a —— 主三链原生 ValueVault 差分

**状态：Closed**

**Closed: 2026-07-14**

| # | 标准 | 状态 | 证据 |
|---|---|---|---|
| CMP-3a-1 | direct ValueVault Product source 是唯一 ProofForge 业务输入 | ✅ met | `just differential-value-vault` 以 `contract-source-authored` / `canonical-core-v1` metadata 构建 `Examples/Product/ValueVault.lean`，并拒绝任何 ContractSpec sidecar |
| CMP-3a-2 | 独立 reference 具有完整固定 provenance | ✅ met | Solidity、Pinocchio Rust、near-sdk Rust v1 manifest 固定精确 source SHA-256、Apache-2.0 与 compiler/framework 工具链 |
| CMP-3a-3 | 两侧实现执行相同 stateful 与 negative lifecycle | ✅ met | Anvil、Mollusk 与 upstream `near-vm-runner` 执行全部 13 步，包括 checked underflow 拒绝与失败后状态保持 |
| CMP-3a-4 | 所有必需 observation fail closed | ✅ met | EVM、Solana、NEAR 各自完整覆盖 status、return、state、balance、event、external action、interface 与 target-local resource，并报告 `semanticMatch=true` |
| CMP-3a-5 | ABI 归一化不创建 compiler 兼容路线 | ✅ met | 仅测试 runner 分别调用原生 Solidity `uint64` 与 ProofForge EVM `uint256` signature，再把二者归一化为 portable `u64`；没有新增 compiler adapter、fallback 或 dual-write route |

## Gate A-CUT3b1 —— Direct authorization authoring 原语

**状态：Closed**

**Closed: 2026-07-14**

| # | 标准 | 状态 | 证据 |
|---|---|---|---|
| A-CUT3b1-1 | target 选择前 caller identity 保持 target-neutral | ✅ met | `just authored-authorization` 证明 public `caller` 归一化为 Canonical Core `contextRead.sender` |
| A-CUT3b1-2 | authorization check 是 direct Core operation | ✅ met | public `requireEq` / `requireNe` statement 归一化为 typed Core comparison 与 assertion；不支持的 direct action 以 no-Legacy-fallback 诊断失败 |
| A-CUT3b1-3 | 主 target plan 消费同一 checked contract | ✅ met | 同一个 Authored authorization probe 的 focused EVM、Solana、NEAR `buildFromCore` 均通过 |

## 使用方式

- 当某个 Gate 的第一条标准开始推进时，新增一个 `## Gate GN` 小节。
- 随工作落地更新状态为 ✅ / ❌ / 🟡（met / unmet / in-progress）。
- 证据使用可复现的命令和 commit 范围，而不是只写描述性文字。
- Gate 关闭时添加 `**Closed: YYYY-MM-DD**`；在此之前都保持 **Open**。

## Gate G0 — Tier-0 退出（当前阶段目标）

**Definition of Done：** 共享场景（Counter，然后是 ValueVault）在
[testkit](../../testkit)（RFC 0007）中通过 `evm`、`solana-sbpf-asm` 和
`wasm-near`，同时满足行为一致性和资源预算（D-040 / RFC 0010）。

**状态：Closed**

**Closed: 2026-07-03**

### 验收标准

| # | 标准 | 状态 | 证据 |
|---|---|---|---|
| G0-1 | Counter 在 3 个 target 上行为一致 | ✅ met | `just testkit` → `counter trace parity: ok (3 target(s))` |
| G0-2 | ValueVault 在 3 个 target 上行为一致 | ✅ met | 远端 CI `28655651561`（`12a007b`）的 `build-test` → `Run unified testkit` 在安装 Foundry/cast 后成功 |
| G0-3 | Counter 资源预算：`solana_cu`、`evm_gas`、`wasmtime_fuel_cumulative` | ✅ met | `testkit/scenarios/counter.toml` 已锁定三种预算；offline-host fuel 是 Wasmtime（不是 NEAR gas）；`CAST="$PWD/build/tools/cast-shim" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --trace` |
| G0-4 | ValueVault 在 3 个 target 上的资源预算 | ✅ met | `testkit/scenarios/value-vault.toml` 已为全部 11 次调用锁定 `solana_cu`、`evm_gas` 和 `wasmtime_fuel_cumulative`；`CAST="$PWD/build/tools/cast-shim" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --trace` |
| G0-5 | Unsupported-capability 诊断一致性 | ✅ met | `just testkit` → `unsupported-crosscall ... diagnostic crosscall.invoke unsupported: ok` |
| G0-6 | `just check` 绿灯（build + lint + gates） | ✅ met | `CAST="$PWD/build/tools/cast-shim" just check` 已在本地通过；远端 CI `28658576786`（`0c52fb8`）也已全部成功，包括 `Run unified testkit`、`Check Solana light gates`、Foundry smoke 和 Anvil deploy smoke |

### Gate G0 关闭后的 carry-over 工作

Gate G0 关闭的是共享行为/资源预算切片。它**不等于**关闭 Gate P0。剩余的主三链
P0 后端硬化继续保持 active：

1. ~~EVM semantic-plan migration（Workstream 3：ExprPlan/StmtPlan/
   EntrypointPlan/EventPlan/CrosscallPlan/MetadataPlan）。~~ ✅ 已落地 — 见 P0-2。
2. ~~Solana Pinocchio live dual-deploy equivalence 的 CI/toolchain 稳定化以及
   更广 reference 覆盖（Workstream 7）。~~ ✅ 已落地 — 见 P0-1。
3. ~~NEAR/Wasm target-first 本地执行/部署元数据签署。~~ ✅ 已落地 — 见 P0-3。

### Sign-off

Gate G0 已在 2026-07-03 于 commit `0c52fb8` 关闭；GitHub CI run
`28658576786` 已全部成功。该 closing run 验证了当前 `just check` CI 面，包括
unified testkit、Solana light gates、EVM Foundry/Anvil gates，以及冻结的非主链
spike smoke jobs。

---

## Gate P0 — 主三链完成规约（当前产品前置条件）

**Definition of Done：** ProofForge 必须按实现顺序完成三个优先链：
`solana-sbpf-asm`、`evm`（Ethereum）和 `wasm-near`（NEAR/Wasm）。在此之前，
任何额外链都不能推进到 docs-only research 或冻结 spike 维护之外（D-045）。

**状态：Closed**

**Closed: 2026-07-04**

### 验收标准

| # | 标准 | 状态 | 证据 |
|---|---|---|---|
| P0-1 | Solana 直接 sBPF 的 P0 制品/执行门禁完成 | ✅ met | Gate G0 行为/预算一致性已关闭；Pinocchio reference-equivalence 已纳入 `just solana-light`；Agave/Solana CLI ELF 兼容阻塞已通过把 target-first `--solana-sbpf-arch v0` 透传到 legacy ELF builder 修复，现在 `emit --target solana-sbpf-asm --format elf` 会生成 loader-compatible v0 ELF（`e_flags = 0`，带有效 section table）；本地 `just solana-pinocchio-live-equivalence` 通过全部五个 Surfpool dual-deploy 场景（System transfer/create_account、SPL Token transfer/ops/authority），结果为 `5 passed, 0 skipped, 0 failed`；GitHub CI run `28675037861` 在 commit `3b2719a` 全部成功，其中强制 `solana-pinocchio-live` job 安装 Agave/Solana CLI、SBF platform-tools、`sbpf`、Surfpool、Node/npm，构建 ProofForge，并在不允许 skip 的情况下运行 aggregate live suite。 |
| P0-2 | Ethereum/EVM 的 P0 lowering/制品/运行时门禁完成 | ✅ met | EVM semantic-plan 迁移已落地（RFC 0004）：`Plan.lean` 现定义 `ExprPlan`、`StmtPlan`、`EntrypointPlan`、`EventPlan`、`CrosscallPlan`、`MetadataPlan`；`Validate.lean` 承载纯校验/类型推断；`Lower.lean` 构建已填充的 `ModulePlan`（entrypoints、events、crosscalls、creates、checked-arithmetic 标记）；`Metadata.lean` 从计划生成 artifact/deploy 元数据；`IR.lean` 是兼容门面，在 Yul 生成前构建完整 semantic plan。门禁：`just evm-plan`、`just evm-semantic-plan`、`just evm-all`（诊断 58 case、99 IR 覆盖条目、19 IR smoke + Foundry + Anvil deploy）、`just check` 全绿。FV-4 还包含可由 `decide` 检查的 EVM/Yul 可执行追踪义务，覆盖 Counter、ValueVault、EvmExpressionProbe、EvmMapProbe、EvmTypedStorageProbe、EvmStorageStructProbe 和 EvmAbiAggregateProbe，即标量 trace、map slots、typed storage arrays、storage structs 以及 aggregate ABI params/returns。FV-2 现在已有 IR aggregate/storage 和 map lifecycle executable trace slices，覆盖 arrays、structs、storage paths、aggregate ABI values，以及 state-threaded map insert/set expressions；P0 后形式化硬化已经通过 `*_ir_observable_trace_ok` 锚点把覆盖到的 EVM map/storage/aggregate IR traces 接入这些 obligations。 |
| P0-3 | NEAR/Wasm 的 P0 target-first/offline-host 门禁完成 | ✅ met | EmitWat/NEAR 诊断、IR 覆盖、形式化锚点、offline host smoke 和预算基线均已通过。Commit `466b320` 为 `wasm-near` 添加 target-first `check`、`emit` 和 `build` 覆盖，写出 `proof-forge-artifact.json` 与 `proof-forge-deploy.json`，通过 `scripts/near/validate-emitwat-metadata.py` 验证 WAT/可选 Wasm hash、ABI entrypoints、capabilities、fixture/module ids 和本地 offline-host 部署模式，并通过 `runtime/offline-host` 执行生成的 Counter WAT。证据：本地 `just near-target-first` 与 `just check`；GitHub CI run `28677055773` 在 commit `466b320` 全部成功，包括 `Run Wasm-NEAR target-first smoke`、`Run EmitWat offline host smoke`、`Run unified testkit`、Foundry/Anvil 和强制 `solana-pinocchio-live` job。 |
| P0-4 | 额外链推进保持冻结 | ✅ met | D-044/D-045 冻结 Aptos/CosmWasm 超过 M1/M2 的推进，并在 P0 关闭前保持其他目标 docs-first。关闭后 Tier-1 可以排期，但 backlog 仍要求先完成 CLI M3/M4 清理。 |

### Sign-off

Gate P0 已在 2026-07-04 于 commit `466b320` 关闭；GitHub CI run
`28677055773` 已全部成功。该 closing run 补齐了 NEAR/Wasm target-first
本地执行/部署元数据证据，并重新验证了现有 Solana、EVM、冻结 spike 和共享
testkit gates。

Gate P0 是针对已记录场景与 fragment 的范围化工程签署。它不证明通用编译器
正确性，不代表 registry 成熟度已晋升为 `Supported`，也不是生产部署/运维签署。

---

## Gate G1a — CosmWasm M4（未开始）

**状态：Not started。** Gate P0 已关闭，因此 D-045 freeze 不再阻塞排期。
下一步仍受 backlog 控制：在把该 spike 推进到 M3/M4 之前，先完成 CLI M3/M4
target-first migration。

## Gate G1b — Aptos M4（未开始）

**状态：Not started。** Gate P0 已关闭，因此 D-045 freeze 不再阻塞排期。
下一步仍受 backlog 控制：先完成 CLI M3/M4 target-first migration，再推进该
spike 到 M3/M4 或启动 `move-sui`。

## Gate G2 — 两个 Tier-1 退出（未开始）

**状态：Not started。** 只有在 G1a 和 G1b 都关闭后才开启；而它们本身都要求
Gate P0 先关闭（D-045）。
