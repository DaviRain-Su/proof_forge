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
