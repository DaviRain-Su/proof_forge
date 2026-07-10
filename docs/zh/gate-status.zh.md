# Gate 完成记录

状态：**Live (2026-07-04)**

本页是分层目标组合的逐 Gate 完成台账（[target-roadmap](../target-roadmap.md)，
D-034）。每个 Gate 都有一条记录，列出验收标准、逐项状态、证据和签署日期。
只有当所有标准都 **met** 时，Gate 才能 **closed**；任何一个未满足的标准都会
阻塞下一层级。Gate P0 记录主三链完成规约（D-045），它比 G0 的行为/预算切片
更严格。

不同于记录工程里程碑流水的 [development-log](../development-log.md)，本页记录
的是*阶段边界*决策：当前阶段的 Definition of Done 是否已经满足，并且证据可审计。

## 使用方式

- 当某个 Gate 的第一条标准开始推进时，新增一个 `## Gate GN` 小节。
- 随工作落地更新状态为 ✅ / ❌ / 🟡（met / unmet / in-progress）。
- 证据使用可复现的命令和 commit 范围，而不是只写描述性文字。
- Gate 关闭时添加 `**Closed: YYYY-MM-DD**`；在此之前都保持 **Open**。

## Gate G0 — Tier-0 退出（当前阶段目标）

**Definition of Done：** 共享场景（Counter，然后是 ValueVault）在
[testkit](../../testkit/)（RFC 0007）中通过 `evm`、`solana-sbpf-asm` 和
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
生产级硬化继续保持 active：

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
| P0-1 | Solana 直接 sBPF 后端达到生产级 | ✅ met | Gate G0 行为/预算一致性已关闭；Pinocchio reference-equivalence 已纳入 `just solana-light`；Agave/Solana CLI ELF 兼容阻塞已通过把 target-first `--solana-sbpf-arch v0` 透传到 legacy ELF builder 修复，现在 `emit --target solana-sbpf-asm --format elf` 会生成 loader-compatible v0 ELF（`e_flags = 0`，带有效 section table）；本地 `just solana-pinocchio-live-equivalence` 通过全部五个 Surfpool dual-deploy 场景（System transfer/create_account、SPL Token transfer/ops/authority），结果为 `5 passed, 0 skipped, 0 failed`；GitHub CI run `28675037861` 在 commit `3b2719a` 全部成功，其中强制 `solana-pinocchio-live` job 安装 Agave/Solana CLI、SBF platform-tools、`sbpf`、Surfpool、Node/npm，构建 ProofForge，并在不允许 skip 的情况下运行 aggregate live suite。 |
| P0-2 | Ethereum/EVM 后端达到生产级 | ✅ met | EVM semantic-plan 迁移已落地（RFC 0004）：`Plan.lean` 现定义 `ExprPlan`、`StmtPlan`、`EntrypointPlan`、`EventPlan`、`CrosscallPlan`、`MetadataPlan`；`Validate.lean` 承载纯校验/类型推断；`Lower.lean` 构建已填充的 `ModulePlan`（entrypoints、events、crosscalls、creates、checked-arithmetic 标记）；`Metadata.lean` 从计划生成 artifact/deploy 元数据；`IR.lean` 是兼容门面，在 Yul 生成前构建完整 semantic plan。门禁：`just evm-plan`、`just evm-semantic-plan`、`just evm-all`（诊断 58 case、99 IR 覆盖条目、19 IR smoke + Foundry + Anvil deploy）、`just check` 全绿。FV-4 还包含可由 `decide` 检查的 EVM/Yul 可执行追踪义务，覆盖 Counter、ValueVault、EvmExpressionProbe、EvmMapProbe、EvmTypedStorageProbe、EvmStorageStructProbe 和 EvmAbiAggregateProbe，即标量 trace、map slots、typed storage arrays、storage structs 以及 aggregate ABI params/returns。FV-2 现在已有 IR aggregate/storage 和 map lifecycle executable trace slices，覆盖 arrays、structs、storage paths、aggregate ABI values，以及 state-threaded map insert/set expressions；P0 后形式化硬化已经通过 `*_ir_observable_trace_ok` 锚点把覆盖到的 EVM map/storage/aggregate IR traces 接入这些 obligations。 |
| P0-3 | NEAR/Wasm 后端达到生产级 | ✅ met | EmitWat/NEAR 诊断、IR 覆盖、形式化锚点、offline host smoke 和预算基线均已通过。Commit `466b320` 为 `wasm-near` 添加 target-first `check`、`emit` 和 `build` 覆盖，写出 `proof-forge-artifact.json` 与 `proof-forge-deploy.json`，通过 `scripts/near/validate-emitwat-metadata.py` 验证 WAT/可选 Wasm hash、ABI entrypoints、capabilities、fixture/module ids 和本地 offline-host 部署模式，并通过 `runtime/offline-host` 执行生成的 Counter WAT。证据：本地 `just near-target-first` 与 `just check`；GitHub CI run `28677055773` 在 commit `466b320` 全部成功，包括 `Run Wasm-NEAR target-first smoke`、`Run EmitWat offline host smoke`、`Run unified testkit`、Foundry/Anvil 和强制 `solana-pinocchio-live` job。 |
| P0-4 | 额外链推进保持冻结 | ✅ met | D-044/D-045 冻结 Aptos/CosmWasm 超过 M1/M2 的推进，并在 P0 关闭前保持其他目标 docs-first。关闭后 Tier-1 可以排期，但 backlog 仍要求先完成 CLI M3/M4 清理。 |

### Sign-off

Gate P0 已在 2026-07-04 于 commit `466b320` 关闭；GitHub CI run
`28677055773` 已全部成功。该 closing run 补齐了 NEAR/Wasm target-first
本地执行/部署元数据证据，并重新验证了现有 Solana、EVM、冻结 spike 和共享
testkit gates。

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
