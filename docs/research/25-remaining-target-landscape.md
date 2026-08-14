---
id: RESEARCH-025
title: 剩余 Target 版图、比特币脚本族与落地波次
status: draft
owner: engineering
updated: 2026-08-13
normative: false
---

# 剩余 Target 版图、比特币脚本族与落地波次

> **目的**：回答「四大类之外还能支持什么」；把**已注册未实现**、**研究期候选**、
> **明确不适合近期实现**的平台分桶；并给出**可执行但不扩 accepted PRD** 的工程波次。  
> **不是** formal `TASK-*`、不是 PRD Phase-1 扩面、不是第二套 live gap 清单。  
> 执行勾选只进 [`../engineering-backlog.md`](../engineering-backlog.md)；op 格子仍以
> [`12-target-coverage-matrix.md`](12-target-coverage-matrix.md) 为准。  
> 范围边界：[`ADR-0036`](../adr/0036-engineering-scope-and-evm-formal-lighthouse.md)。  
> 分类轴：[`04-target-taxonomy.md`](04-target-taxonomy.md)。

状态：`draft` / non-normative。日期：2026-08-13。

---

## 0. 一句话结论

用户口头的「四大类」（EVM / Near-Wasm / Solana / ZK）是**导航标签**，不是编译语义。
ProofForge 的真实权威是多轴 `TargetDescriptor` + 每 target 独占 Plan/IR。

在此框架下：

| 桶 | 内容 | 近期动作 |
|---|---|---|
| **已工程实现** | 9 个 materializer | 加深能力；不冒充 accepted/formal |
| **registry design-only** | `soroban` / `icp` / `openvm` | **下一刀实现波次（优先）** |
| **研究期已 ADR、dossier 缺口** | `aptos` / `sui` / `cairo` / `risc0` / `sp1`（ADR-0017；TON 已实现升格） | 先补 dossier + 独立实现 ADR，再进 registry |
| **比特币脚本族等 UTXO/predicate** | Script / Tapscript / Miniscript / Liquid / BitVM 等 | **研究钉 + 默认 wontfix-until**；与现有 Semantic 状态机不匹配 |
| **其它热门但未立项** | Fuel/Sway、Cardano/Plutus、Stylus-as-Wasm、Polkadot ink! 等 | 记录边界；不进本波实现队列 |

**硬约束**：实现任一新 target ≠ 改写 accepted Phase-1 四目标；formal lighthouse 仍 EVM-first。

---

## 1. 四大类 vs 项目真实 taxonomy

### 1.1 用户四类（产品讨论视图）

| 用户标签 | 典型代表 | 容易误并 |
|---|---|---|
| EVM 系列 | `evm`（及结算在 EVM 语境的 L2） | 把 Stylus Wasm 或 zkEVM verifier 当成「又一 Wasm host」 |
| Near Wasm 系列 | `near`（以及同字节码形态的其它 host） | 把 CosmWasm / Soroban / ICP 当成「NEAR 换 imports」 |
| Solana | `solana` | 把其它 SVM/账户模型链静默 alias |
| ZK | `noir` / `openvm` / `aleo` / `psy` / Cairo / RISC Zero / SP1 | 共用一个 `ZkPlan` |

### 1.2 项目已采用的阅读 family（非 dispatch）

见 [`../targets/README.md`](../targets/README.md)：

1. EVM contract VM  
2. SVM explicit-account  
3. Wasm host（NEAR / CosmWasm / Soroban / ICP — **共享 encoder，不共享 Plan**）  
4. ZK circuit（Noir）  
5. zkVM（OpenVM / Cairo / RISC Zero / SP1）  
6. ZK application chain（Aleo / Psy）  
7. TVM Stack-Account（TON）  
8. Executable model（Quint；无独立 family 文档）

编译器禁止用 family 选择 lowering；禁止 `GenericWasmHostPlan` / 单一 `ZkPlan`。

### 1.3 当前控制面计数（工程事实）

| 轨道 | 集合 |
|---|---|
| Accepted PRD Phase 1 | `evm` `solana` `near` `noir` |
| Engineering implemented | 上四 + `aleo` `psy` `quint` `cosmwasm` `ton`（共 9） |
| Registry design-only | `soroban` `icp` `openvm`（共 3） |
| Registry 合计 | **12** |
| ADR-0017 研究期、尚未进 registry | `aptos` `sui` `cairo` `risc0` `sp1`（`ton` 已离开此桶） |

因此：**「四大类之外」在仓库里早已存在**——至少有 TON、Quint、CosmWasm、Aleo/Psy，以及三个 design-only。

---

## 2. 四大类之外：还能支持什么

按「与现有 SemanticProgram 可映射程度 × 工程成本 × 产品诚实度」分五档。

### 档 A — 已接线，继续加深（不新开 target）

| Target | 为何不算用户四类里的「已完成」 | 诚实上限 |
|---|---|---|
| `cosmwasm` | Wasm host，但 Cosmos SubMsg/IBC ≠ NEAR Promise | MVP + mock/wasmd rung；非主网/formal |
| `ton` | TVM actor，非 EVM/SVM/Wasm | Tolk/BoC + sandbox；pf.assets 冻结 |
| `aleo` / `psy` | ZK **应用链**，非电路 DSL、非通用 zkVM | zero-tool 制品；无 VM/proof/deploy |
| `quint` | 可执行规格 / 模型面 | source-only；不可部署 |

### 档 B — registry 已有、缺 materializer（**本文件主实现队列**）

| Target | Family | 与已实现 leaf 的关键差 | 建议 MVP 形态 |
|---|---|---|---|
| `soroban` | Wasm host | XDR / auth tree / TTL storage；不得复用 NearPlan | WAT/Wasm recipe + contract-spec/XDR 子集 + local invoke 门（若工具可钉） |
| `icp` | Wasm actor | Candid + await 分段提交 + stable memory；不得复用 Near Promise | Wasm + `.did` + pocket-ic/local replica 子集；sync 跨 canister FC 或显式 async |
| `openvm` | zkVM | RV32IM guest / VmExe / 外置 verifier；无链上持久 state | guest IR → ELF/VmExe；`verifiable-workload`；无假「链上合约」 |

准入门槛（三个共同）：

1. 独立实现 ADR（descriptor / profile / Plan/IR schema / fail-closed 表）。  
2. 只消费 retained `SemanticProgramV1`；capability-only Plan。  
3. Counter 级 portable 子集 + 显式 unsupported 矩阵 + ordinary CI leaf；**不**改 accepted PRD。

### 档 C — ADR-0017 已立项研究、dossier/registry 未闭合

| TargetId | Family | 相对档 B 的额外难点 | 建议顺序 |
|---|---|---|---|
| `aptos`、`sui` | Move Resource VM | — | **wontfix**（2026-08-13 产品决定：不做 Move 轴；不补 dossier、不进 registry） |
| `cairo` | zkVM | Cairo VM + STARK；≠ OpenVM Plan | OpenVM MVP 后再开；**Plan 设计见 RPT-026**；dossier `13-cairo` |
| `risc0` | zkVM | RISC-V guest + receipt | 同 OpenVM 轴；择一深度优先；**Plan 设计见 RPT-026** |
| `sp1` | zkVM | 同上 | 与 risc0 二选一作为第二 zkVM leaf，或更晚；**Plan 设计见 RPT-026** |

> 现状缺口：`docs/targets/` **没有** `12-aptos`…`16-sp1` dossier（ADR-0017 曾规划编号；`12-quint.md` 已占用 12）。
> 补档时应续排新编号，**不要**覆盖 Quint。

### 档 D — 比特币脚本族与 UTXO / predicate 平台（用户点名）

| 候选 | 执行模型一句话 | 与 PF Semantic 的匹配 | 建议 |
|---|---|---|---|
| **Bitcoin Script / Tapscript** | UTXO 花费谓词；栈机；无持久合约存储 | **弱**：无 `state`/`init`/`entry`/`view` 账户机；「程序」是锁脚本路径，不是可变状态机 | **research-only**；默认 `wontfix-until` 独立 predicate profile ADR |
| **Miniscript / Policy** | Script 的结构化策略编译 | 同上；更适合作为 **policy IR → Script**，不是 Semantic→账户 Plan | 可作 **旁路工具研究**，不进 TargetRegistry |
| **Liquid Script** | 联合侧链 + 类似 Script | 同 UTXO 谓词问题 | 随 Bitcoin 桶延后 |
| **BitVM / BitVM2** | 链下挑战 + 链上欺诈证明骨架 | 有状态计算感，但结算与失败模型远非 PF portable fragment | **观察研究**；不可当下一 materializer |
| **Stacks (Clarity)** | 比特币锚定的账户/合约层 | 比 Script **更接近** account VM；仍需独立 TargetId 与 Clarity Plan | 可进「档 E 候补」；非 Bitcoin Script |
| **RGB / client-side validation** | 链下状态 + 比特币承诺 | 状态不在链上 VM 执行 | 不适合当前 materializer 形态 |
| **Ordinals / inscriptions** | 数据铭刻，非通用合约 VM | 无 | 排除 |

**比特币脚本族结论（钉死）**：

1. **不能**把「比特币那几个脚本」当成 EVM/Solana 式第四类之外的「下一个 Wasm」。  
2. 它们缺的是 **持久逻辑状态 + 同步/异步调用边界** 与 PF 产品语义的同构，不是缺一个 emitter。  
3. 若未来要支持，应新增 **独立 family**（例如 `utxo-predicate` 或 `bitcoin-policy`），用**极窄** surface（纯谓词 / 无 state store / 无 call），并接受大量 ProgramV1 形态在 resolver **fail closed**。  
4. **本波实现队列不包含** `bitcoin` / `liquid` / `bitvm` TargetId。

### 档 D′ — UTXO「语义同构」到底能不能做？（2026-08-13 加深）

> 用户追问：UTXO 能否接入；「语义同构」是否可行。  
> 权威产品语义：[`../02-architecture.md`](../02-architecture.md) 的 Reference `step` 与
> 「logical state 可有不同 realization」；执行模型轴见 [`02-execution-models.md`](02-execution-models.md)。

#### 先钉词：ProofForge 说的「同构」不是「同一台 VM」

产品里「target 不改业务语义」指的是：对 **已承认（admitted）的 portable 片段**，

```text
Reference.step(Semantic, LogicalState, Invocation, Ext) ≈ Target.realize(...)
```

在成功后状态、失败回滚、effect 序、权限/披露意图上一致；物化可以是 EVM storage、
Solana accounts、NEAR KV，或 Noir 的 **external pre/post continuity**。

因此有三档「接进来」，不要混谈：

| 档 | 含义 | 经典 Bitcoin Script | eUTxO（Cardano 等） | 链下状态+链上承诺（RGB/BitVM） |
|---|---|---|---|---|
| **A. 全表面同构** | 任意合法 `program`（state/init/entry/view/call/schedule）都有等价 realization | **否** | **否**（大量 FC） | **否** |
| **B. 受限片段同构** | 只承认窄 fragment；其余 resolver FC；Reference↔target 对承认面可测 | **极难 / 实质否**（无耐久逻辑 state） | **可以做研究/工程 MVP** | **仅当把「链下机」当 realization，结算外置** |
| **C. 换表面接入** | 不假装是账户 `program`；另开 predicate/policy 语言或 profile | **可以**（Miniscript→Script） | 可，但不如 B 有价值 | 可，但是另一产品 |

**结论一句话**：  
- **全表面同构：做不到，也不该做。**  
- **受限同构：eUTxO 方向可行；纯 Bitcoin Script 基本不可行。**  
- **换表面：Bitcoin Script 可行，但那是「策略编译器」，不是现有 Semantic 状态机的又一个 target。**

#### 为什么纯 UTXO Script 难做 B

PF 工程 Semantic 默认假设：

1. **有名逻辑 state** 在多次 `entry` 之间延续（Counter 的 `count`）。  
2. 一次 `entry` 是对 **同一逻辑对象** 的状态迁移；失败则该次迁移原子回滚。  
3. `view` 只读同一逻辑状态。  
4. `call`/`schedule` 表达跨对象交互边界。

经典 Bitcoin / Liquid Script：

1. 链上对象是 **UTXO**，花费即销毁；「下次状态」是 **新 UTXO 集**，不是合约 storage 槽。  
2. Script 是 **花费谓词**（这次能不能花），不是「读改写命名 state」的 VM。  
3. 没有一等 `view`；「查询余额」是索引/钱包问题，不是合约方法。  
4. 没有 PF 意义下的 sync `call`；多输入/多输出是交易结构，不是嵌套 message。

因此：把现有 `program Counter` 直出 Script，**不是缺 lowering，而是 Reference `step` 的状态载体不存在**。硬编会变成「假同构」（例如把 state 藏在链下、链上只验证哈希）——那必须标 `stateContinuity=external`，并承认与 EVM Counter **不是同一产品保证**。

#### eUTxO 为什么可以谈 B（仍非本波）

Cardano 式 eUTxO（datum + redeemer + script）：

- datum 可承载 **显式状态值**；花费旧 UTXO、产出新 UTXO ≈ 一次状态迁移。  
- 这与 PF「logical state → 一次 invocation → 新 logical state」**可以**做成 **realization 映射**：  
  - `state` 字段 ↔ datum 布局  
  - `entry` ↔ redeemer + spending script  
  - 失败 ↔ 交易不入块 / script fail（无「半写」storage）  
- **必须 FC 的**：任意动态 `call` 图、隐式全局单例合约、跨多个独立 UTXO 的「假装同步」、无 datum 的纯 Script。

这是 **新 TargetId + 新 Plan**（例如未来 `cardano`），不是把 Bitcoin Script 塞进 Wasm/EVM family。  
适合度：**中**——高于 Bitcoin Script，低于 Soroban/ICP；实现成本高在：线性资源、多 UTXO 并发、币值守恒与 PF `pf.assets` 的对齐。

#### 三条诚实接入路径（若产品要 UTXO）

| 路径 | 做什么 | 与现有 `program` | 建议 |
|---|---|---|---|
| **P1 Predicate profile** | Miniscript/policy → Script/Tapscript；无 state/entry 状态机 | 大量语法 FC；或独立源表面 | Bitcoin 最稳；**不叫** Semantic 全同构 |
| **P2 eUTxO state-cell MVP** | 单 state cell（单 UTXO）Counter 级；datum↔state；无 call | 窄 fragment 可 Reference 对齐 | Cardano/同类；需独立 ADR |
| **P3 External continuity** | 链下跑 PF Reference/guest，链上只放承诺/挑战（RGB/BitVM 风格） | 类似 Noir `stateContinuity=external` | 可研究；成熟度与证明/挑战协议绑定；**禁止**写成「链上 Counter」 |

**禁止**：

- 用「输出了 Script 字节」声称与 EVM/Solana Counter 语义等价。  
- 把 UTXO 接进现有九个 materializer 的 Plan 类型。  
- 未先 ADR 就扩 `ExecutionHost` / registry。

#### 对「能做吗」的直接回答

| 问题 | 答案 |
|---|---|
| UTXO **能不能接进仓库**？ | **能**，但只能走 P1/P2/P3 之一，且是 **新 family + 大量 FC**。 |
| 与现有 Semantic **全表面同构**？ | **不能**（也不应追求）。 |
| 与现有 Semantic **窄片段同构**？ | **eUTxO：可以设计**；**Bitcoin Script：基本不能**（无耐久 state 载体）。 |
| 是否应插入当前 Soroban→ICP→OpenVM 波次？ | **否**；维持 §4 Wave T6 / backlog `TGT-BTC-SCRIPT-PIN`，除非产品单独立项 P2。 |

### 档 E — 热门但未立项（只记边界，不排期）

| 候选 | 归类建议 | 不立刻做的原因 |
|---|---|---|
| Arbitrum Stylus | **EVM settlement + Wasm 编码** | 属 EVM 语境扩展/profile，不是新 Wasm host（taxonomy 反例） |
| Fuel / Sway | 独立 VM | 无 dossier；资源模型与 UTXO-ish 并行需研究 |
| Cardano / Plutus | eUTxO | 与档 D 同类难度 |
| Polkadot ink! / pallet | Wasm + FRAME | 易误并 CosmWasm；需独立 Plan |
| Cosmos SDK module（非 CosmWasm） | 原生模块 | 不是合约 materializer 轨道 |
| zkEVM / validity rollup | 证明 + EVM 语义 | 多半是 EVM profile / 证明后端，不是新 TargetId |

---

## 3. 能力匹配速查（为何有的能做、有的不能）

Portable Semantic 核心假设（工程子集）：

- 有名逻辑 state、init / entry / view / pureFn  
- checked 算术与有界控制流  
- 显式 effect（emit / revert / call / schedule）按 target fail-closed  
- target **不得**改写业务语义，只改物化

| 平台类 | state 机 | call/schedule | 证明/结算 | 适合度 |
|---|---|---|---|---|
| Account + sync tx（EVM） | 强 | sync 自然 | 可选 | 高 |
| Explicit accounts + CPI（Solana） | 强（账户布局） | sync CPI | 可选 | 高 |
| Wasm + host KV / Promise（NEAR） | 强 | async 为主 | 可选 | 高（诚实 async） |
| Wasm + Cosmos messages（CW） | 强 | SubMsg 同 tx | 可选 | 高 |
| Wasm + auth/TTL（Soroban） | 强 | sync invoke + auth tree | 可选 | 高（档 B） |
| Wasm actor + await（ICP） | 强 | 分段 commit | 可选 | 中高（async 诚实成本高） |
| TVM actor（TON） | 强（cell） | 仅 async | 可选 | 已做；扩面冻结 |
| Move resource（Aptos/Sui） | 强但线性/对象 | 同步调用为主 | 可选 | 中（类型映射重） |
| Circuit（Noir） | 关系/witness | 无原生链调用 | 外置 | 已做；prove 另议 |
| zkVM guest（OpenVM/…） | guest 内存 | 无原生链 CPI | 核心 | 档 B/C |
| ZK app chain（Aleo/Psy） | 记录/分区 | 平台专用 | 内生 | 已做（制品级） |
| Model（Quint） | 模型变量 | 无部署调用 | 无 | 已做 |
| UTXO Script | **谓词** | 无 | 链结算 | **低（档 D；全同构否，见档 D′）** |
| eUTxO（datum 状态元） | **状态细胞**（花费即迁移） | 交易结构 ≠ sync call | 链结算 | **中（仅窄 fragment B；非本波）** |

跨合约原子性现实见 [`22-portable-surface-vs-chain-reality.md`](22-portable-surface-vs-chain-reality.md)。

---

## 4. 落地波次（工程，不扩 accepted PRD）

> 下列波次写入 backlog ID（§5）。每一刀仍遵守：先失败测试 → 最小 Plan/IR →
> capability resolve → 文档成熟度诚实 → `just docs-check` / 聚焦测 / 必要时 `just ci`。  
> **禁止**并行发明共享 adapter；leaf 文件不重叠时可并行，registry/docs/SBOM 由主代理串行。

### Wave T0 — 文档与决策闸（本文件闭合即完成）

- 固定四类导航 vs 多轴 taxonomy 的读法。  
- 固定比特币脚本族 **不进本波实现**。  
- 固定下一实现优先序：**Soroban → ICP → OpenVM**（Wasm 同轴两 leaf 先复用 encoder 经验，再开 zkVM）。  
- ADR-0017 候选改编号续排；补 dossier 前不得改 `TargetId` 枚举。

### Wave T1 — `soroban` MVP（design-only → engineering leaf）

**切片建议**：

1. 实现 ADR：`soroban-*-v1` sole profile、六轴 descriptor、deployable 策略。  
2. `SorobanPlan` / IR：storage durability 子集（先 persistent-only 或 instance-only，TTL 显式 FC 或极窄）。  
3. auth tree：Counter 无需复杂 auth 时可 FC 高级 auth，保留 `require_auth` 扩展位。  
4. shared Wasm encoder + Soroban imports/recipe；**零** NearPlan 复用。  
5. 测试：ValidatePlan + 制品 digest +（若可钉）local invoke smoke。  

**非目标**：完整 TTL/archival、token interface 全家、主网。

### Wave T2 — `icp` MVP

1. 实现 ADR：update/query 二分；Candid 子集。  
2. `IcpPlan`：单 message 可提交子集优先；inter-canister **默认 FC 或仅 schedule 形**。  
3. stable memory：Counter 可先 heap-only + upgrade FC。  
4. pocket-ic / local replica 工程门（缺席 skip-clean）。  

**非目标**：timers、HTTP outcalls、certified vars、复杂 await 工作流。

### Wave T3 — `openvm` MVP

1. 实现 ADR：guest generation 策略（Lean→Rust guest 或直接 IR）一次性钉死。  
2. `OpenVmPlan` → ELF/VmExe；proof profile 可先 **execute-only / artifact-only**，prove FC。  
3. 成熟度标签诚实为 source/guest-workload；无链上 deployable 声称。  

**非目标**：与 Noir 共享 Plan；EVM verifier 部署；多 zkVM 同时开工。

### Wave T4 — Move 轴（**取消**）

产品决定（2026-08-13）：**不做** `aptos` / `sui`。不补 dossier、不进 registry、不排 materializer。
ADR-0017 研究登记保留为历史；执行队列 `TGT-MOVE-DOSSIER=wontfix`。

### Wave T5 — 第二 zkVM / Cairo（择一）

在 OpenVM MVP 稳定后，于 `cairo` / `risc0` / `sp1` 中选 **一个** 深度 leaf；其余保持 research。
三机 **Plan/Q0 设计**已固定于 [`26-zkvm-trio-cairo-risc0-sp1-design.md`](26-zkvm-trio-cairo-risc0-sp1-design.md)；实现仍串行。

### Wave T6 — 比特币 / UTXO（可选；默认不开；见档 D′）

仅当产品明确选型后择一：

1. **P1 Predicate**：Miniscript/policy → Script；独立表面或极窄 FC。  
2. **P2 eUTxO state-cell**：单 UTXO datum↔state 的 Counter 级片段同构（独立 TargetId/ADR）。  
3. **P3 External continuity**：链下 step + 链上承诺/挑战；标 external，禁止假「链上账户机」。

默认 backlog 保持 **`wontfix-until-T6-decision`**。**禁止**在未 ADR 前把 UTXO 塞进现有 materializer。

---

## 5. Backlog 挂钩（sole live 队列）

下列 ID 只在 [`../engineering-backlog.md`](../engineering-backlog.md) 勾选；本文件不维护第二套状态机。

| ID | 项 | 波次 | 初态 |
|---|---|---|---|
| **TGT-DOC-025** | 本版图研究落地 + README/索引 | T0 | 随本文 → done |
| **TGT-SOROBAN-MVP** | Soroban design-only → materializer MVP | T1 | pending |
| **TGT-ICP-MVP** | ICP design-only → materializer MVP | T2 | pending |
| **TGT-OPENVM-MVP** | OpenVM design-only → materializer MVP | T3 | pending |
| **TGT-MOVE-DOSSIER** | Aptos/Sui dossier + family 补齐（无代码） | T4 | pending |
| **TGT-BTC-SCRIPT-PIN** | 比特币脚本族研究钉（默认不实现） | T6 gate | pending（文档钉）→ 本文完成后可标 done |

扩 registry 计数时必须同步：`targets/README.md`、ADR-0036 后继 ADR、`12-target-coverage-matrix`、SPEC-REG 轴枚举（若增 ExecutionHost 等）。

---

## 6. 明确非声称

- 不把 engineering leaf 写成 accepted Phase-1 或 formal 完成。  
- 不把「输出 Wasm / 输出 proof」写成跨平台语义等价。  
- 不把 Bitcoin Script 支持写成「再加一个 target 就行」。  
- 不在恢复期新增 `TASK-*` / `TST-*` / qualification ceremony。  
- 不恢复 `active/` 或跨 target Plan 复用。

---

## 7. 建议阅读顺序（执行前）

1. 本文 §0–§4  
2. [`ADR-0036`](../adr/0036-engineering-scope-and-evm-formal-lighthouse.md)  
3. [`ADR-0017`](../adr/0017-research-phase-targets-ton-move-cairo-zkvm.md)（Move/zkVM 研究边界）  
4. 对应 dossier：[`05-soroban.md`](../targets/05-soroban.md) / [`06-icp.md`](../targets/06-icp.md) / [`08-openvm.md`](../targets/08-openvm.md)  
5. [`family-wasm-host.md`](../targets/family-wasm-host.md) / [`family-zkvm.md`](../targets/family-zkvm.md)  
6. [`22-portable-surface-vs-chain-reality.md`](22-portable-surface-vs-chain-reality.md)

---

## 8. 更新协议

- 某 Wave 的实现 ADR accepted 或 MVP 合入后：更新本文对应档位一行 + backlog 状态 + targets 索引。  
- 若产品决定把比特币谓词升格：先新 ADR，再改本文 §2 档 D 与 §4 Wave T6；禁止先写 emitter。  
- 与 op 覆盖冲突时：以代码 + matrix 12 为准，回写本文「诚实上限」列。
