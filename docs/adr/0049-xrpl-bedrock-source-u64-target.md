---
id: ADR-0049
title: XRPL Bedrock source-only UInt64 capability-gated target (Q0)
status: proposed
owner: architecture
updated: 2026-08-17
normative: true
---

# ADR-0049：XRPL Bedrock source-only UInt64 capability-gated target（Q0）

## 状态

proposed

## 背景

XRPL L1 正在实验原生 WASM 智能合约（[XLS-0101](https://xls.xrpl.org/xls/XLS-0101-smart-contracts.html)）：
Rust → `wasm32-unknown-unknown` → `ContractCreate` / `ContractCall`，合约落在
**pseudo-account** 上。Commons 开发面是
[XRPL-Commons/bedrock](https://github.com/XRPL-Commons/bedrock) 与
[scaffold-xrp](https://github.com/XRPL-Commons/scaffold-xrp) 的 Counter 模板。

这 **不是** XRPL EVM Sidechain、**不是** Hooks（`SetHook`）、**不是** OpenVM
guest、**不是** NEAR/CosmWasm/ICP Wasm host。`ContractCreate` 当前只能在
**AlphaNet / 本地节点**使用，不能上 XRPL 主网。Bedrock 是社区工具，不是
Ripple 官方编译器。

本 ADR 冻结 **Q0 engineering leaf**：与 Soroban S0 / OpenVM O0 同级的
**zero-tool source-only**。产品 `build --target xrpl` 发射受控 Bedrock 形
`.rs` recipe，诚实标注不可部署。B（locked rustc → WASM）与 C（AlphaNet
`ContractCreate`）需要后续独立批准。

Accepted PRD Phase 1 仍为 EVM/Solana/NEAR/Noir（ADR-0036）。本 ADR 只把 XRPL
提升为第 13 个 engineering materializer，不静默扩 accepted 范围，不改变
EVM-first formal lighthouse，不关闭 formal 0/27。

## 决策

1. **身份与归类**：新增 `TargetId.xrpl`。执行语义归类为 **XRPL smart-features**
   新 family。**不得**复用 `OpenVmPlan` / `NearPlan` / `IcpPlan` /
   `SorobanPlan` / `EvmPlan` / 未来 `HooksPlan`，不得建立
   `GenericWasmHostPlan`。
2. **Registry**：`TargetRegistryV1` 工程计数改为 **13 targets = 13 implemented +
   0 design-only**。六轴：
   - `executionHost` = `xrpl-wasm`
   - `commit` = `transaction-atomic`
   - `state` = `contract-key-value`
   - `call` = `synchronous-message`
   - `proof` = `no-proof`
   - `settlement` = `xrpl-chain`
   `CodegenProfileId` wire = `xrpl-bedrock-source-u64-v1`（sole / default）；
   `ArtifactEncoding` = `xrplBedrockSource`；
   `AcceptanceProfileRef` = `research.xrpl.v1`；
   maturity = **`source-only`**。
3. **Capability（honest 4-key）**：resolver **仅** 承认
   `failure.atomic-rollback`、`state.persistent`、`value.bool`、
   `value.checked-arithmetic`。显式拒绝（非穷举）：`effect.event`、
   `effect.synchronous-call`、`effect.asynchronous-workflow`、
   `extension.pf-assets`。Call 轴虽为 `synchronous-message`，本 profile **不
   广告、不降低** portable `call`/`schedule`；不得把 `ContractCall` 或 emit
   Payment 假装成已对齐（`B-CALL-SEM` 级）。
4. **制品与 finalization**：materializer 产出单个 `{artifactName}.rs`
   （scaffold-xrp Counter 形：`xrpl_wasm_std`、`get_data`/`set_data`、
   `#[unsafe(no_mangle)] pub extern "C"`）。`deployable=false`。
   **Product finalization 为零工具**：不调用 rustc、wasm-opt、bedrock CLI、
   rippled、`ContractCreate`、`ContractCall`、AlphaNet 或主网。locked WASM
   Finalize 与 AlphaNet 部署属后续独立 profile（XRPL-9 / XRPL-10）。
5. **Q0 语言/CFG 子集（唯一本 profile 合法面）**：
   - 类型：仅 anonymous `UInt64` / `Bool` / `Unit`；
   - 状态与参数：仅 **public** `UInt64`；
   - 结果：public `Unit` / `UInt64` / `Bool`；
   - callables：`init` / `entry` / `view` / `pureFn`；**single-block**；无
     loops / branch / switch / block params；
   - ops：literal、state load/store、checked `UInt64` `+`/`-`/`*`/`/`/`%`、
     比较、Bool `and`/`or`/`not`、`pureCall` inline（depth ≤ 64）、bare
     assert、zero-payload declared revert；
   - **nonempty invariants / events / call / schedule / ContextRead /
     Commit / multi-width / aggregates / Field / Principal / String /
     Int64 / Smart Escrow / Vault / Hooks / EVM sidechain**：Plan 边界
     fail closed；
   - 存储：Q0 仅映射到 `get_data`/`set_data` 字符串 key（state 名）；
   - 失败：checked overflow / assert / revert 映射为 `trace` + 负 `i32`
     返回码（host 回滚由后续 WASM/runtime profile 解释，Q0 不声称 tec/tes）。
6. **源码形状钉（真实 API，非发明宏）**：
   - crate path `xrpl_wasm_std`；
   - `core::data::codec::{get_data, set_data}`；
   - `get_current_contract_call()` + `get_contract_account()`；
   - 导出是 `#[unsafe(no_mangle)] pub extern "C" fn … -> i32`；
   - `/// @xrpl-function name` 只是文档注释，**不是** Rust 宏；
   - 不得发射 `#[xrpl_function]`、`host_storage`、或 OpenVM/`soroban_sdk`
     模板。
7. **诚实边界**：AlphaNet ≠ 主网。Q0 不生成 ABI JSON、不生成
   `ContractCreate` 交易、不写 Tool Lock。resolver 从 15 行增为 **16** 行。
   formal D1–D4 仍为 0/27。

## 后果

- `pf build --target xrpl` 可闭合，产出 `{name}.rs` + 工程 sidecar。
- `list-targets` 出现 `xrpl\tsource-only`。
- B/C 不得在本 profile 声称。Hooks / EVM sidechain 不得记入本 TargetId。

## 非声称

不是 formal SupportClaim / OutputSetV1 / ToolchainIdentity。不是主网智能
合约。不是 Bedrock CLI 产品化。不是 CAP-1a。
