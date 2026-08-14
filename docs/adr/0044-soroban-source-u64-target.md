---
id: ADR-0044
title: Soroban source-only UInt64 capability-gated target (S0)
status: proposed
owner: architecture
updated: 2026-08-13
normative: true
---

# ADR-0044：Soroban source-only UInt64 capability-gated target（S0）

## 状态

proposed

## 背景

Stellar Soroban 是 Wasm host：合约以受限 Wasm 在 Stellar transaction/host 中同步
执行，状态带 TTL/archival，调用经 auth tree，接口经 XDR/ScVal。仓库早已登记
`TargetId.soroban` 与六轴（`soroban-wasm` / TTL storage / synchronous auth tree /
Stellar settlement），但一直保持 **design-only**（无 Plan/IR/materializer）。

dossier [`docs/targets/05-soroban.md`](../targets/05-soroban.md) 的完整退出条件
（XDR、auth tree、TTL plan、locked stellar-cli）超出单一切片。本 ADR 冻结 **S0
engineering leaf**：Quint/Aleo 式 **zero-tool source-only**，把 retained
`SemanticProgramV1` 的窄 public-UInt64 子集物化为 **Soroban contract Rust 方言**
`.rs` 源码 recipe，使产品 `build --target soroban` 可闭合并诚实标注不可部署。

产品边界必须诚实：

- 不得把 `.rs` 写成可部署 Wasm 或 formal D3/D4 完成；
- 不得在 product finalization 中调用 stellar-cli / soroban SDK host / RPC；
- 不得静默发明 storage durability/TTL、auth tree always-pass、或复用
  NEAR/CosmWasm Plan；
- 不得把本切片写成 accepted PRD Phase 1 扩面（仍为 EVM/Solana/NEAR/Noir）。

## 决策

1. **身份与归类**：`TargetId.soroban`。执行语义归类为 **Soroban Wasm host
   family**（ADR-0007 / `family-wasm-host`）：可与其它 Wasm host **共享 encoder
   纪律**，但 **必须拥有独立** `SorobanPlan` / `SorobanIR`，禁止
   `NearPlan`/`CosmWasmPlan`/`GenericWasmHostPlan` 复用。
2. **Registry**：`TargetRegistryV1` 工程计数改为 **12 targets = 10 implemented +
   2 design-only**（剩 `icp` / `openvm`）。六轴保持既有 seed：
   - `executionHost` = `soroban-wasm`
   - `commit` = `transaction-atomic`
   - `state` = `ttl-scoped-storage`
   - `call` = `synchronous-auth-tree`
   - `proof` = `no-proof`
   - `settlement` = `stellar-chain`
   `CodegenProfileId` wire = `soroban-source-u64-v1`；
   `ArtifactEncoding` = `sorobanSource`（**不是** `wasmText`）；
   `AcceptanceProfileRef` = `phase1.soroban-u64.v1`；
   maturity = **`source-only`**。
3. **Capability（honest 4-key）**：resolver **仅** 承认
   `failure.atomic-rollback`、`state.persistent`、`value.bool`、
   `value.checked-arithmetic`。显式拒绝（非穷举）：`effect.event`、
   `effect.synchronous-call`、`effect.asynchronous-workflow`、
   `extension.pf-assets`。Call 轴虽为 `synchronous-auth-tree`，本 profile **不
   广告、不降低** sync call；auth/TTL 未进入 Plan 字段前一律 fail closed
   （B-CALL-SEM 同级）。
4. **制品与 finalization**：materializer 产出单个 `{artifactName}.rs`
   （`soroban-sdk` 风格 `#[contract]` / `#[contractimpl]` / instance storage
   get/set 骨架）。`deployable=false`。**Product finalization 为零工具**：不调用
   stellar-cli、不编译 wasm32、不写 Tool Lock 依赖。locked Wasm Finalize、
   contract-spec/XDR、local invoke 属后续独立 profile（SOR-1+），不得在 S0 声称。
5. **S0 语言/CFG 子集（唯一本 profile 合法面）**：
   - 类型：仅 anonymous `UInt64` / `Bool` / `Unit`；
   - 状态与参数：仅 **public** `UInt64`；
   - 结果：public `Unit` / `UInt64` / `Bool`；
   - callables：`init` / `entry` / `view` / `pureFn`；**single-block**；无
     loops / branch / switch / block params；
   - ops：literal、state load/store、checked `UInt64` 算术、比较、Bool
     `and`/`or`/`not`、`pureCall`、bare assert、zero-payload declared revert；
   - **nonempty invariants / constants / events / call / schedule /
     ContextRead / Commit / multi-width / aggregates / Field / Principal /
     String**：Plan 边界 fail closed；
   - 存储：S0 **仅**映射到单一 **instance** storage 约定；不得静默选择
     persistent/temporary TTL；
   - 失败：checked overflow / assert / revert 映射为 Rust `panic!`（host 回滚），
     对应 `failure.atomic-rollback`。
6. **不做（本 ADR 明确排除）**：
   - 改写 accepted PRD Phase 1 四目标；
   - formal TASK/TST、formal SupportClaim / OutputSetV1、Reference↔Soroban 差分；
   - product 路径上的 stellar-cli / Wasm / RPC / testnet；
   - auth tree always-pass、默认 TTL、与其它 target 共享 Plan/IR。

## 理由

- Soroban 是真实 Wasm host，值得 engineering leaf，但完整 XDR/auth/TTL/tool 闭包
  超出单切片；source-only `.rs` 先闭合 registry→产品 build，并保持 fail-closed。
- `ArtifactEncoding.sorobanSource` 避免把未编译源码标成 `wasmText`。
- 4-key + 拒 sync call 防止在 auth tree 未接线时冒充 call 完成（B-CALL-SEM）。
- 与 ADR-0036 对齐：engineering 扩面不静默改写 accepted scope；formal lighthouse
  仍为 EVM-first。

## 影响

- engineering：implemented **9 → 10**；design-only **3 → 2**（`icp`/`openvm`）；
  materializer **9 → 10**；resolver 增加一行 `soroban-source-u64-v1`。
- 文档：dossier `05-soroban.md`、TARGET-INDEX、ADR-0036 §Decision.2、backlog
  `SOR-0`/`SOR-1`、AGENTS/catalog 同步。
- leaf：`ProofForgeV2/Targets/Soroban*` + Registry 三臂 + CLI list/inspect pins。

## 备选

- 保持 design-only（拒绝：S0 子集已可决策冻结且 worktree 意图即为 promotion）。
- S0 即 locked Wasm Finalize（拒绝：Tool Lock/host pin 成本超出本切片；SOR-1）。
- 广告 sync call 并 always-pass auth（拒绝：与 auth-tree 轴及 B-CALL-SEM 冲突）。
