---
id: TARGET-XRPL
title: XRPL native WASM smart-features target dossier
status: draft
owner: architecture
updated: 2026-08-17
normative: false
---

# Target Dossier：XRPL（Bedrock / XLS-0101）

状态：`proposed` / engineering source-only Q0 + opt-in WASM Q1（ADR-0049/0050）
Target ID：`xrpl`
成熟度 ceiling：`research`
阶段：engineering implemented。默认 `pf build --target xrpl` 发射 `{name}.rs`
（zero-tool）；`--profile xrpl-bedrock-wasm-u64-v1` 可经 ambient rustc 附加
`.wasm` extra。`deployable=false`。**无** bedrock / AlphaNet / 主网。

规划：[`../plan/xrpl-bedrock-wasm-gap.md`](../plan/xrpl-bedrock-wasm-gap.md) ·
任务：[`../plan/xrpl-bedrock-wasm-tasks.md`](../plan/xrpl-bedrock-wasm-tasks.md)。

## 1. 身份与来源

XRPL L1 正在实验 **原生 WASM 智能合约**（[XLS-0101](https://xls.xrpl.org/xls/XLS-0101-smart-contracts.html)）：
Rust → `wasm32-unknown-unknown` → `ContractCreate` / `ContractCall`，合约落在
**pseudo-account** 上。Commons 的开发面是
[XRPL-Commons/bedrock](https://github.com/XRPL-Commons/bedrock)
（Go CLI + 嵌入 JS 发交易）和
[scaffold-xrp](https://github.com/XRPL-Commons/scaffold-xrp)（上传 `.wasm`）。

这 **不是**：

| 易混对象 | 为何不是 |
|---|---|
| XRPL EVM Sidechain | 另一条 Cosmos+EVM 链；Solidity；Commons 只做培训 |
| Hooks（XRPL Labs） | `SetHook` 账户钩子；非独立合约账户；bedrock 无此路径 |
| OpenVM / 任意 zkVM | 无证明、无 RV32 guest；host 是 XRPL ledger API |
| NEAR / CosmWasm / ICP Wasm host | 不得复用 `NearPlan` / `CosmWasmPlan` / `IcpPlan` |
| Smart Escrow / Vault（XLS-0100） | 谓词 WASM；Q0 **不做** |

归类：新 family 候选 **XRPL smart-features**。禁止 `GenericWasmHostPlan` /
`ZkPlan` / EVM Yul。

可部署面（2026-08）：**仅** Bedrock local Docker 与 AlphaNet
（`wss://alphanet.nerdnest.xyz`，network 21465）。XRPL 主网 **没有**
`ContractCreate`。

## 2. 执行、状态、调用、失败

- 执行：WASM runtime 嵌在 rippled（实验构建）；host 是 XRPL 账本读/发交易，不是
  WASI、不是 OpenVM。
- 状态：合约自有 `ContractData`；与 PF `logicalState` 的映射未冻结。
- 调用：`ContractCall` 调导出函数；合约可 **emit** 原生 XRPL 交易
  （Payment / OfferCreate / …）。portable `call`/`schedule` **不得**在 Q0
  假装已对齐（`B-CALL-SEM` 级）。
- 失败：合约返回码 + 交易 tec/tes；与 PF checked-arithmetic / revert 的
  join 未冻结。
- 资源：gas / bytecode size / 100 XRP 量级部署费（测试网观察，非正式 NFR）。

## 3. Q0 portable fragment（建议）

与 Soroban S0 / OpenVM O0 同级诚实 4-key：

`failure.atomic-rollback` · `state.persistent` · `value.bool` ·
`value.checked-arithmetic`。

开：public UInt64/Bool/Unit Counter/StateCell 的 **受控 Rust 源**
（`xrpl_wasm` / Bedrock 注解风格）；UInt64/Bool const inline；T3 Bytes N /
Array UInt64 N state flatten（N∈1..8 叶，字面量下标）；T4 Principal 9 叶
identity（`len+w0..w7`，不是 AccountID）；T5 named Struct/Enum 叶 flatten；
T6/T7 named view/entry 叶返回 Rust `(u64,…)` 元组；T8b Bytes N **view**
叶返回；T9a/T9b if-diamond + `switchOn`；T9c counted `forLoop` trap。

ContextRead / `pf.crypto.sha256` 见 [ADR-0052](../adr/0052-xrpl-host-capability-keys.md)：
TIME/CALLER 符号已冻、SHA keep-FC；**叶仍 FC**。

Q0 **一律 fail closed**：`call`/`schedule`、ContextRead、`pf.crypto.*`、
`pf.assets`、invariants、Principal result/self/caller、Bytes **entry**
return、不可约 CFG / 臂内 call·emit·revert、Escrow/Vault、Hooks、EVM
sidechain、主网 deployable、bedrock CLI 作为 product Finalize。

## 4. 制品与工具（研究钉，非 Tool Lock）

| 层 | 事实 | Q0 产品面 |
|---|---|---|
| 源 | Rust + Bedrock `@xrpl-function` 注解 | **可**发射受控模板 |
| WASM | `cargo` `wasm32-unknown-unknown` | Q0 **不**调 rustc；Q1 opt-in 才调 ambient cargo |
| 部署 | `ContractCreate` via bedrock `deploy.js` / xrpl.js | Q0 `deployable=false` |
| 网络 | local / AlphaNet | 不得写 mainnet |
| ABI | 链上 Functions + 源注解 | 研究；不进 resolver |

## 5. 非声称

已进 `TargetRegistryV1` 为第 13 个 implemented materializer（ADR-0049）。不扩
accepted PRD。不关 formal。不把 AlphaNet 实验写成主网智能合约。不把 EVM
侧链或 Hooks 算作本 target 完成度。C（AlphaNet deploy）需后续独立批准。Q1 WASM extra 见 ADR-0050。host 三键见 ADR-0052（不开叶）。
