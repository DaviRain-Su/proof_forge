# ProofForge 执行任务清单 + WASM 家族与调用层规划（2026-07）

- **定位**：原生中文规划文档，**非工程权威源**。与
  [code-review-2026-07-fv5-capability-gate](code-review-2026-07-fv5-capability-gate.md)、
  [architecture-review-2026-07](architecture-review-2026-07.md) 同类。可落地的条目
  应按惯例先 graduate 成英文 RFC / 进入
  [implementation-backlog](../implementation-backlog.md)。
- **与现有规划的关系**：本文**不另起炉灶**。项目已有 Workstream 24–33
  （架构收敛 / FV / testkit / allocator / 目标组合 / CLI / 版本 / 预算 / 部署生命周期 /
  错误模型 + 客户端）。本文做两件现有语料没做的事：(1) 把上一份 review 的
  **正确性 / FV 发现**编进 Workstream 结构、给出依赖排序；(2) 把 **WASM 新链**与
  **调用层（"调用文档"）**这两块从"已排期但未展开"补成可执行的适配器模板。
- 依据：[target-roadmap](../target-roadmap.md)（WS28）、
  [platform-gaps-2026-07](../platform-gaps-2026-07.md)（WS29–33）、
  [formal-verification](../formal-verification.md)（WS25）。

---

## 一、执行任务清单（按优先级分轨）

优先级读法：**Track 0 是 bug（违背核心承诺）**，Track 1 是 FV 地基（解锁"可验证"
卖点），Track 2 是结构债，Track 3 是已排期的平台缺口。Track 0/1 是本文相对现有
backlog 的新增/重排。

### Track 0 — 正确性修复（源自 review，小而确定）

| # | 任务 | 涉及文件 | 依赖 |
|---|---|---|---|
| 0.1 | 溢出语义节点化：`.add/.sub/.mul` 携带 `checked\|wrapping` 标签；或至少让 `+!`/`contract_source` elaboration 置 `overflowChecked`，并让 EVM 兑现该标志（否则默认 `false` 的"到处 wrapping"在 EVM 上不成立） | `IR/Contract.lean`、`Contract/Source.lean`、`Target/Adapter.lean:143`、`Backend/Evm/ToYul/Helpers.lean:19` | — |
| 0.2 | 能力派生改 `intent ∪ module` 去重；随后删掉 FV-5 专用 gate（checkedArithmetic 自然流过 `requireCapabilities`） | `Target/Adapter.lean:37` | 0.1 |
| 0.3 | 链专属 IR 节点给唯一能力：`crosscallInvokeNamedValue → .nearPromise`（现误映射为通用 `.crosscallInvoke`，能力层挡不住，只靠 EVM 硬编码 Validate 臂兜底） | `IR/Contract.lean:421` | — |
| 0.4 | 收紧 Solana `hasEntrypointDispatch`，删裸子串匹配，只认真实 label 形态 | `Backend/Solana/Refinement.lean:119-123` | — |

### Track 1 — FV 地基 keystone（重排 WS25，按依赖）

| # | 任务 | 产出 | 依赖 |
|---|---|---|---|
| 1.1 **keystone** | IR 解释器在"已验证片段"上 total 化（良基 `def`/fuel），换掉 `evalExpr`/`runEntrypoint` 的 `partial def` | 归纳原理 → 可陈述 `∀ input` 全称 refinement | — |
| 1.2 | 统一 refinement 契约：把三份复制的 `ObservableReturn`/`TraceObligation`（EVM/NEAR/Solana）合并成一个共享类型 + `BackendSemantics` typeclass | `Backend/Refinement/Core.lean`（新） | — | ✅ DONE |
| 1.3 | Solana 最小 sBPF 解释器：对 `Asm.AstNode` 子集（寄存器堆 + 线性内存 + Counter 用到的 ~15 opcode）做 `step`/`run`，建 IR↔sBPF 差分 obligation | `Backend/Solana/SbpfSemantics.lean`（新） | 1.2 | ✅ DONE |
| 1.4 | 每目标"支持片段"谓词 + 两条定理：`能力接受 ⟹ 属于片段` 与 `属于片段 ⟹ 降级成功`；用定理替代 `check-ir-coverage-manifest.py` | 覆盖完备性从测试升级成证明 | 1.1 |
| 1.5 | Ownership checker（FV-3）total 化，证"永不用已释放局部、永不双重释放" | `IR/Ownership.lean` | 1.1 |
| 1.6 | `native_decide`（130 处）→ kernel `decide` 可降级项审计；TCB 文档写明"信任 Lean 编译器" | 收敛可信基 | — |
| 1.7 | FV-8 产品化：`contract_source` 旁声明不变量、codegen 前证明（把 `ValueVaultInvariant` 从样例变成 authoring 模式） | 差异化卖点 | 1.1 |

### Track 2 — 结构性债务（WS24 / WS29）

| # | 任务 | 说明 |
|---|---|---|
| 2.1 | 完成 RFC 0014 ModulePlan 收敛：共享 plan 接口 + 各后端 `LoweringError` 实例真正接上（现 typeclass 在、实例为零） | `Backend/Diagnostic.lean` |
| 2.2 | `Lean.Evm` namespace → `ProofForge.*`（遮蔽编译器 `Lean` 命名空间） | 已在 WS24 记录 |
| 2.3 | CLI flag-zoo → target-first `build\|emit\|check --target`（M3/M4），迁移 testkit/scripts 后再删 `EmitMode` | WS29；testkit 绑到 flag zoo 前必须做 |

### Track 3 — 已排期平台缺口（WS30–33，注明依赖）

| # | Workstream | 状态 / 动作 |
|---|---|---|
| 3.1 | WS30 版本/兼容策略 | 未写；IR 99 构造子仅结构性 gate。写 RFC 定 IR/artifact/capability-id/SDK 的 semver 规则。外部消费者（explorer、cloud、客户端）落地前做 |
| 3.2 | WS31 预算即门 | 基本完成（G0 已闭）；保持为 P0 回归门；NEAR gas 从 wasmtime-fuel 代理换成原生 host-gas 模型 |
| 3.3 | WS32 部署生命周期 / 升级 / 签名 | 未建模；升级默认各后端分歧（语义静默 bug）。RFC 定升级策略 intent（`immutable\|authority\|governance`）+ 签名边界（ProofForge 出未签名 tx，密钥托管在外） |
| 3.4 | WS33a 可移植错误模型 | 运行时错误 stringly、逐链。RFC 定 IR 级错误码 + 每目标编码表 + testkit `expect.error`；与 0.1 溢出 trap 语义天然配对 |
| 3.5 | WS33b 统一客户端生成 | 见 **第三节**（用户点名的"调用文档"） |

---

## 二、WASM 新链扩展计划（WS28 Wasm 家族）

### 2.1 现状：抽象有骨架，但没打通

- `Target/HostBridge.lean` 已把各链 WASM 宿主抽象成 metadata：`requiredExports` /
  `requiredImports` / `hostFunctions`（带 WAT 类型签名），目前两个变体 `near` /
  `cosmWasm`。这是**新增 WASM 链的正确接缝**。
- 但**只有 NEAR 真正走这个接缝**：`WasmNear/Imports.lean:36 bridgeBaseImports(bridge)`
  由 HostBridge 驱动。**CosmWasm 却 fork 了一份手写 EmitWat**，import 是硬编码字符串
  （`CosmWasm/EmitWat.lean:56`：`"(import \"env\" \"db_read\" ...)"`），没走 HostBridge。
- 可复用的链无关基座很小：`Compiler/Wasm/AST.lean`(138) + `Printer.lean`(167)；
  NEAR 专属的 `WasmNear/EmitWat.lean` 有 1016 行。

**含义**：若不先把 EmitWat 真正参数化，每加一条 WASM 链就会像 CosmWasm 一样再 fork
一份 EmitWat，"一个 EmitWat 核 + 换 import/ABI 适配器"的家族卖点永远不成立。

### 2.2 使能重构（做一次，解锁所有后续 WASM 链）

**任务 W0：HostBridge 驱动的统一 EmitWat。** 把 NEAR + CosmWasm 收敛到同一个
host-参数化 EmitWat：

- 扩展 `HostBridge` 覆盖 imports / exports / **入口消息编码**（NEAR JSON+Borsh vs
  CosmWasm JSON msg）/ **allocator 绑定**（RFC 0008：near wee / cosmwasm region）。
- CosmWasm 的硬编码 import 改为走 `bridgeBaseImports` / HostBridge。
- **退出判据**：NEAR 与 CosmWasm 都从同一 EmitWat 核产出，差异只在各自的 HostBridge
  变体 + ABI 适配器。这就是 target-roadmap Tier 1a "EmitWat generality proof"，本文把它
  从"证明"表述成"重构任务"。

### 2.3 每条 WASM 链的适配器模板（W0 之后，复用清单）

每加一条 WASM 链 = 履行下面这张清单（**不再写新 EmitWat**）：

1. `HostBridge` 新变体（imports / exports / host 函数签名）。
2. `TargetProfile`（capabilities 子集、allocator 绑定、`hostBridge?`）。
3. ABI / 编码适配器（入口参数/返回的链原生编码）。
4. allocator 绑定（RFC 0008）。
5. IR 覆盖清单（长期改成 Track 1.4 的谓词 + 定理）。
6. testkit harness（wasmtime + host shim，复用 NEAR 模式）。
7. CLI emit 路由 + 一个 chain-CLI 验证门。
8. （客户端）第三节的 client schema 里加该链适配器。

### 2.4 候选 WASM 链逐个（按 roadmap 门序 + 本文补充）

| 链 | 家族契合度 | 关键 delta | 排期 |
|---|---|---|---|
| **CosmWasm** | 高（第二个 WASM 宿主） | db_read/db_write、region allocator、JSON msg | Tier 1a；**W0 的验证对象**，先做 |
| **Stellar Soroban** | 高 | Soroban host env、XDR / contract-spec ABI、storage TTL 作 metadata | CosmWasm M4 后；第二便宜 |
| **ICP canister** | 中（最难） | Candid ABI、update/query 分裂、cycles metadata、**异步 inter-canister** 不适配当前同步 IR effect 集 | 需先补"IR 异步 effect"设计（见下）；不要靠适配器惯性硬上 |
| **Casper** | 中 | Wasm + Odra 框架、可升级合约；**目前无 target note** | 先补 docs-first target note（D-012 式）再进 tier |
| **Arbitrum Stylus**（本文新增建议） | 中（WASM，但 EVM 账户模型 + Solidity ABI） | Rust/WASM-on-EVM；复用 Wasm AST 但用 EVM ABI + EVM 存储模型 | 值得补 target note；与 evm chain-profile 模式有交叉，需判定是"WASM 后端"还是"evm 变体" |
| **MultiversX / Concordium / Radix**（本文新增建议） | 待研究（均 WASM VM） | 各自宿主 ABI；需 docs-first note | 与 Casper 同批，按生态需求择一 |
| **Polkadot ink!** | research-only（D-009） | 现已转 PolkaVM/RISC-V，未必还是纯 WASM | 保持 parked，按需 revisit |

**横切前置：IR 异步 effect 设计。** ICP 的 inter-canister、NEAR 的 Promise 链
（`crosscallContinue` 等）本质是同一类"异步跨合约"需求。当前 IR 把 NEAR 异步硬塞进
共享 `Expr`（见 review 5.1 的 D-027 违背）。**建议把异步跨合约抽成一个统一的 IR
扩展（effect + capability），NEAR 和 ICP 共用**——既修了 review 里的链专属节点污染，
又给 ICP 铺路。这是"规划新链时顺带修架构"的高杠杆点。

---

## 三、调用层（"调用文档"）计划（WS33b）

### 3.1 现状

- Solana：`Idl.lean`（schema `proof-forge.solana.idl.v0`，**Solana 命名空间**）+
  `Client.lean`（TS 客户端）。
- EVM：ABI JSON（`Cli/EvmArtifacts.lean`）。
- NEAR / Psy / Aleo：**无面向客户端的产物**。
- 即：IDL 是链专属、无共享 schema；"一份合约多链调用"在**应用开发者**这一侧还没兑现。

### 3.2 计划（按依赖）

1. **链中立 client schema**：从 `ContractSpec` 派生一个 `proof-forge.client.v0`——
   entrypoints / 参数与返回类型 / 事件 / 错误码（错误码接 WS33a）。把 Solana IDL
   泛化成它。
2. **每链调用编码适配器**：EVM selector/ABI、Solana instruction/Borsh + account metas、
   NEAR JSON/Borsh 参数……**与 testkit 的编码适配器是同一套逻辑，写一次共享**
   （platform-gaps Gap 6 的核心点）。
3. **每链 TS 客户端生成**：把 Solana `Client.lean` 改成 schema 驱动，补 EVM / NEAR。
4. **调用文档自动生成**（用户点名的"调用文档"）：从 client schema 生成每链"如何调用
   本合约"的人读文档（方法签名、示例调用、参数编码说明）。**从 `ContractSpec` 自动
   生成 → 永不漂移**。这正是"之前那个项目里的调用文档"在本项目的对应物。
5. **依赖**：排在 testkit M3 之后（共享编码逻辑）+ WS33a 错误模型之后（错误面）。

### 3.3 退出判据

一份 `contract_source` → 指定 target → 同时得到：可部署产物（第二节）+ 该链 TS 客户端
+ 该链调用文档，三者都从同一 `ContractSpec` 派生，跨链行为由 testkit 差分门锁定。

---

## 四、其他可规划项（本文建议纳入）

- **统一部署清单 schema**（接 WS32）：现 EVM 用 `proof-forge-deploy.json`，其余链 ad-hoc。
  做一个跨链 `proof-forge-deploy.v1`，每加一条链不再多一种清单格式。
- **`proof-forge deploy` 多链广播适配器**（接 WS32）：现只 EVM 一键；给 Solana/NEAR/Sui
  补广播，或明确把承诺定为"生成部署就绪产物 + 各链原生工具部署"。
- **升级策略 intent**（WS32）：`immutable | authority(key) | governance(ref)`，各链诚实
  lower 或编译期拒绝——消除"升级默认各后端分歧"的语义静默 bug。
- **FV 作为面向用户的产品面**（Track 1.7 / FV-8）：合约作者写不变量、codegen 前证明。
  这是相对 Reach/Solang 的差异化，且纯 Lean、无后端依赖。

---

## 五、依赖排序（gate，非日期）

```text
Track 0（正确性）  ── 可即刻并行，小改动
       │
1.1 IR 解释器 total ──┬─→ 1.4 支持片段定理 ─→（替代覆盖清单脚本）
（keystone）          ├─→ 1.5 ownership 可靠性
                     └─→ 1.7 FV-8 用户不变量
1.2 统一 refinement 契约 ─→ 1.3 Solana sBPF 解释器
                     └─（新后端复用同一 obligation）

W0 统一 EmitMat（HostBridge 驱动）
   ├─→ CosmWasm（验证对象）─→ Soroban ─→ ICP（+IR 异步 effect）
   └─→ Casper / Stylus / …（先补 target note）

IR 异步 effect ──共享──→ NEAR Promise 收敛 + ICP inter-canister

WS33a 错误模型 ─┐
testkit M3 编码 ─┴─→ WS33b client schema ─→ 每链 TS 客户端 + 调用文档自动生成

WS30 版本策略 ──（客户端/explorer 等外部消费者落地前必须先定）
```

**一句话**：先清 Track 0 的 4 个正确性 bug（小、确定），同时起 1.1（IR 解释器 total 化，
是解锁一切 FV 的总开关）与 W0（HostBridge 驱动的统一 EmitWat，是解锁一切 WASM 新链的
总开关）；这两个 keystone 分别打通"可验证"和"可扩链"两条主线，其余按上图依赖展开。

---

## 六、被漏掉的规划轴：目标是否已有 Lean 4 形式语义（修订第二、5.5 节）

> 本节回应"WASM 没考虑全 + 你有一份调研了很多 Lean 4 的文档"这一反馈。核对
> `docs/tier-c-proof-feasibility.md` 与外部事实后，补上一条现路线图漏掉的关键轴。

### 6.1 核心洞见

FV-first 平台的差异化是 Tier C-proof（证明 IR ↔ 目标）。这一步的前提是**目标存在
一份 Lean 4 形式语义**（refinement 的等式右边）。现路线图只按"产物/VM 形状"分类目标
（EVM / WASM / Move / sourcegen），**没有"该目标是否已有 Lean 4 语义"这条轴**——而
这才是决定"能不能真做 FV"的那条。目标语义可以：(a) 自己在 Lean 里建（EVM pseudo-Yul、
NEAR offline-host、Solana 待建，见 Track 1.3），或 **(b) 直接引入已有的 Lean 4
项目**——后者又便宜又强，让该目标从 C-diff 直接跳到"可 C-proof"。

### 6.2 按"Lean 4 语义可得性"分类目标

| 目标 | VM/语言 | 有 Lean 4 语义? | 来源 | FV 价值 | 现状 |
|---|---|---|---|---|---|
| EVM | EVM/Yul | ✓ | `powdr-labs/evm-semantics`（Lean v4.31，与本仓一致，**当前主目标**；关系 `Step`+可执行 `stepF`）；`EVMYulLean`（v4.22，历史 fallback/参考） | 高 | Phase 6b **已接入/已解锁**：opt-in `EvmRefinement` 已 pin powdr；下一步是 Phase 6c Counter per-entrypoint `Step` 证明 |
| **Cairo / Starknet** | Cairo/Sierra/CASM | ✓ | `starkware-libs/formal-proofs`（Lean 4 主目录：Cairo VM/CPU 语义 + proof-producing compiler） | 高 | **仓库只当 sourcegen，漏了 Lean 语义** |
| **Noir / Aztec** | Noir/ACIR | ✓ | Reilabs `Lampe`（Noir→Lean 4）；NAVe（ACIR） | 高 | **仓库完全没有** |
| JAR PVM | RV64E/PVM2（RISC-V） | ✓ | JAR 自带 Lean 4 spec（`Jar.PVM2.*`） | 中高 | 已有 docs-first 计划 |
| NEAR / CosmWasm / Soroban / ICP | WASM | ✗ | 无 Lean 4 WASM 等价物（WasmCert 是 Isabelle/Coq） | 低（停 C-diff） | 扩链广度好、FV 弱 |
| Solana | sBPF | ✗ | 需自建（Track 1.3） | 低 | — |
| Move（Aptos/Sui） | Move bytecode | ✗ | Move Prover 用 Boogie，非 Lean | 低 | — |

**含义**：WASM 家族适合**扩链广度**，但 FV 弱（要自建语义）；ZK/证明系（Cairo、Noir）
与 RISC-V（JAR）相反——codegen 窄，但 **Lean 4 语义已存在**，是能真正完成 IR↔目标
refinement 的目标。**FV-first 平台应在 FV 车道给后者更高权重**；现路线图把 Cairo 归成
sourcegen、Noir 根本没上，是最大的战略遗漏。

### 6.3 完整 WASM 家族清单（回应"WASM 没考虑全"）

| 链 | 生态 | 状态 | 备注 |
|---|---|---|---|
| NEAR | NEAR | 生产（参考实现） | HostBridge `.near` |
| CosmWasm | Cosmos | spike | HostBridge `.cosmWasm`（但 EmitWat 是 fork，见 W0） |
| Stellar Soroban | Stellar | 研究 | 你找到的"还有这一个"；XDR ABI、TTL metadata |
| Internet Computer | ICP | 研究 | Candid、update/query、异步 inter-canister |
| Casper | Casper | 无 target note | Odra 框架、可升级；需先补 note |
| MultiversX | MultiversX | 未调研 | WASM VM |
| Arbitrum Stylus | Arbitrum | 未调研 | Rust/WASM-on-EVM，EVM 账户模型 + Solidity ABI |
| Fluent | Fluent | 未调研 | blended EVM+WASM rollup |
| Concordium | Concordium | 未调研 | WASM |
| Radix | Radix | 未调研 | Scrypto→WASM |
| Vara / Gear | Gear | 未调研 | WASM actor 模型 |
| Polkadot ink! | Polkadot | research-only(D-009) | 已转 PolkaVM/RISC-V，正离开 WASM |
| Cloudflare Workers | —（链下） | spike | WASM/JS 链下宿主 |

前 5 个是家族核心排期；后面 6 个（MultiversX/Stylus/Fluent/Concordium/Radix/Vara）都需
docs-first target note 才能进 tier。它们证明"WASM 家族"确实很大——**W0 的统一 EmitWat
是把它们从"研究项目"变成"适配器项目"的前提。**

### 6.4 把有 Lean 4 语义的目标规划进来（新增 FV-priority 车道）

相对本文前几节的**修订**：除 WASM 广度车道外，增开一条 **FV-priority 车道**，优先做
"Lean 语义已存在"的目标：

- **Cairo/Starknet（升级为双路）**：除现有 sourcegen（Road 1），加一条 **FV 路**——把
  `starkware-libs/formal-proofs` 的 Cairo VM 语义作为 refinement target（类比
  `powdr-labs/evm-semantics` 之于 EVM）。让 Starknet 从"sourcegen 目标"升级成
  "可 C-proof 目标"。前置：Track 1.2 统一 refinement 契约。
- **Noir/Aztec（新目标类别）**：ProofForge IR → Noir/ACIR，用 Lampe 的 Noir Lean 语义
  做 refinement。与 `psy-dpn`（ZK circuit sourcegen）是姊妹，但 Noir 有现成 Lean 语义，
  FV 价值更高。先补 docs-first target note + zk 相关 capability。
- **JAR PVM（已有计划，重新 framing）**：标注它是"Lean-semantics-available RISC-V 目标"，
  FV 车道优先于纯 codegen 目标；同时打开 RISC-V 语义复用（与 PolkaVM 未来交叉）。

**第三个 keystone**：除"IR 解释器 total 化"（FV 总开关）与"HostBridge 驱动的统一
EmitWat"（扩链总开关），再加 **Track 1.2 统一 refinement 契约必须先落**——只有它落了，
才能把 `powdr-labs/evm-semantics` / Cairo formal-proofs / Lampe 这些**外部 Lean
语义作为可插拔的 refinement target** 接进来。三者分别打通：可验证、扩链广度、
**外部语义复用**。

### 6.5 落地动作（docs-first，接现有 target 入库流程）

1. 改 `docs/targets/starknet-cairo.md`：新增"Lean 4 语义可得性"段，记
   `starkware-libs/formal-proofs`，并把它从"纯 sourcegen"重列为"sourcegen + FV 双路候选"。
2. 新建 `docs/targets/noir-aztec.md`（docs-first，D-012 式）：分类、Lampe/ACIR 语义、
   capability 草案、Counter/ZK spike 判据。
3. 在 `docs/target-roadmap.md` 增开 **FV-priority 车道**（与 sourcegen 车道并列），把
   Cairo-FV、Noir、JAR-PVM 按"Lean 语义已就绪"优先排序。
4. `docs/tier-c-proof-feasibility.md` 的 Phase 6e（"非 EVM 需自建语义"）更新：Cairo/Noir/
   JAR **不需自建**——它们有现成 Lean 语义，应先于 Solana/NEAR 自建语义的工作。

### 6.6 全部已调研目标的完整清点（不遗漏）

> 前几节挑了 WASM 和 Cairo/Noir 讲，漏了仓库里已调研/已实现的其他链（尤其 **Aleo
> 已经是带代码的 spike**、**Kaspa 是 UTXO-covenant+ZK**）。这里对
> `docs/targets/` + `target-roadmap.md` 里**每一条**链做统一清点，按家族分组，标注
> Lean 4 语义可得性与 FV 路径。

| 目标 | 家族 | Lean 4 语义 | 仓库状态 | FV 路径 |
|---|---|---|---|---|
| EVM | 直接编译/bytecode | ✓ `powdr-labs/evm-semantics`（当前主目标，v4.31 兼容）；EVMYulLean 仅作历史 fallback/参考 | 生产 | **已引入 opt-in 外部语义；继续做 Counter powdr `Step` 证明** |
| Solana sBPF | 直接编译/bytecode | ✗ | 生产 | 自建（Track 1.3） |
| JAR PVM | 直接编译/RISC-V | ✓ JAR 自带 spec | docs 计划 | **引入外部语义** |
| NEAR | WASM-host | ✗ | 生产 | 自建 / C-diff |
| CosmWasm | WASM-host | ✗ | spike | C-diff |
| Stellar Soroban | WASM-host | ✗ | 研究 | C-diff |
| Internet Computer | WASM-host | ✗ | 研究 | C-diff |
| Casper | WASM-host | ✗ | 无 note | 先补 note |
| CF Workers | WASM（链下） | ✗ | spike | 差分 HTTP |
| Move Aptos | Move sourcegen | ✗（Move Prover=Boogie） | spike | C-diff |
| Move Sui | Move sourcegen | ✗ | Counter MVP | C-diff |
| **Starknet Cairo** | 非 Move sourcegen | **✓ starkware/formal-proofs** | 研究（仓库只当 sourcegen） | **引入外部语义（升级双路）** |
| TON TVM | sourcegen | ✗ | 研究 | C-diff |
| Algorand AVM | sourcegen | ✗ | 研究 | C-diff |
| Cardano Plutus/Aiken | eUTXO validator sourcegen | ✗（有 Agda `plutus-metatheory`，非 Lean） | 研究 | C-diff / 语义需移植 |
| Tezos Michelson/LIGO | sourcegen | ✗（有 Coq `Mi-Cho-Coq`，非 Lean） | 研究 | C-diff / 语义需移植 |
| Psy/DPN | ZK circuit sourcegen | ✗ | 实验子集 | 差分 dargo |
| **Aleo / Leo** | ZK-app-sourcegen | ✗（无成熟 Lean） | **spike（已有代码！）** | 自建 / 差分 leo |
| **Noir / Aztec** | ZK-app（ACIR） | **✓ Lampe** | **仓库完全无** | **引入外部语义（新目标）** |
| Bitcoin Script/Miniscript | policy / UTXO | ✗ | 研究（独立 policy 族） | 决定性谓词检查 |
| BCH CashScript | policy / UTXO | ✗ | 研究 | 同上 |
| Zcash Shielded | privacy UTXO / ZK | ✗ | 研究 | 同上 + 证明边界 |
| **Kaspa Toccata** | **UTXO covenant + 内联 ZK** | ✗ | 研究 | policy 族 + `zk.verify` |
| Polkadot ink! | WASM→PolkaVM/RISC-V | ✗ | research-only(D-009) | 转 RISC-V 后或复用 JAR |
| MultiversX / Stylus / Fluent / Concordium / Radix / Vara | WASM-host | ✗ | 未调研 | 先补 note |

**三条被我先前遗漏的要点**：

- **Aleo 不是"待规划"，是已实现的 spike**：`ProofForge.Backend.Aleo.IR` + `Compiler.Leo`
  + `Examples/Backend/Aleo/*.golden.leo` + `scripts/aleo/*-smoke.sh` 都在。家族是
  `zk-app-sourcegen`（proof context 私有 records + finalization context 公有 mappings）。
  它是 **ZK 家族但无现成 Lean 语义**——属"自建/差分"桶，**不**进 Cairo/Noir 那条
  Lean-语义-就绪车道。规划动作：把 Road 2（私有 record 流）+ target profile 入库排上。
- **Kaspa Toccata 是 policy/UTXO 家族，不是合约链**：状态是 covenant lineage、验证
  successor output，不是账户存储。它的 ZK 是"内联验证一个证明"（Noir/Groth16）而非
  "生成电路"。归到 **policy 族**（与 Bitcoin/BCH/Zcash 同批），spike 触发条件是上游
  Silverscript/ZK SDK 发布。
- **别把"有形式语义"等同于"有 Lean 语义"**：Tezos Michelson 有 Coq（`Mi-Cho-Coq`）、
  Cardano Plutus 有 Agda（`plutus-metatheory`）——**都不是 Lean**，移植到 Lean 4 是研究
  级工作，远贵于 `powdr-labs/evm-semantics` 那种"加 opt-in lake 依赖"。所以真正
  "Lean-语义-就绪"的集合仍是精确的四个：**EVM、Cairo、Noir、JAR PVM**。

**修订后的目标车道（三条并行）**：
1. **Lean-语义-就绪 FV 车道**（最高 FV 价值）：EVM → Cairo（升级双路）→ Noir（新）→ JAR。
2. **codegen 广度车道**：WASM 家族（W0 后 12+ 条）+ Move + 非 Move sourcegen + Aleo/Psy（ZK sourcegen，自建语义）。
3. **policy/UTXO 家族**（不同产品）：Bitcoin Script/Miniscript → BCH → Zcash → Kaspa Toccata。

---

## 七、两处目标语义的具体任务分解（Solana sBPF + WASM 自建语义）

> 这两块是"自建目标语义"桶里的核心（Solana 无 Lean 语义、WASM 无 Lean WASM 语义）。
> 本质是**同一个模式**：给目标 VM 建一个 Lean 解释器（`step`/`run`）+ 建它到 IR 语义
> 的映射（模拟关系 `R`）+ 差分/精化义务。Solana 已有设计 note
> （`docs/solana-sbpf-executable-trace.md`），WASM 需新写。**先建共享接口，再各自实例化。**

### 7.0 共享前置（做一次，两边复用）

| # | 任务 | 落点 | 说明 |
|---|---|---|---|
| P1 | 统一 `TargetSemantics` 接口（= Track 1.2） | `Backend/Refinement/Core.lean`（新） | 抽出 `MachineState / step / run(fuel) / observe / R / executableTraceOk` + **共享** `ObservableReturn`/`TraceObligation`；两个解释器都 instantiate 它，三份复制的 obligation 类型就此合并 |
| P2 | trace 归纳（= Track 1.1，**已落为任意 MachineState**） | `IR/StepSemantics.lean` | Phase 6a 已有 `IRTraceMatches` + `runTraceListGen_sound`（归纳证明，非 native_decide），并已在 EVM/Yul、Solana sBPF、Wasm/NEAR target runner state 上实例化 smoke。**只是 C-proof 的前置，C-diff 不需要它** |

**关键排期洞见**：C-diff 差分义务（`executableTraceOk` 用 `native_decide` 逐点跑）**只需
P1，不需 P2**——因为 native_decide 直接求值，`partial def` 的 IR 解释器照跑。所以
**下面 S1–S5 / W1–W5 现在就能做**，P2 + C-proof（S6/W6）是更难的后一层。

### 7.1 Solana sBPF 语义（执行已有设计 note，Slice A→D）

| # | 任务 | 产出 / 落点 | 依赖 |
|---|---|---|---|
| S1 | `SbpfInterpreter.lean`：`SbpfState`(regs/stack/entryR0/pc) + `step` 覆盖 Counter 指令子集（`mov64/add64/sub64/mul64/lsh64/lddw/ldxdw/stxdw/ja/jeq/exit` + storage syscall stub）+ label 表 + dispatch + fuel-bounded `run` | `Backend/Solana/SbpfInterpreter.lean`（新） | P1 |
| S2 | `observe` + 差分义务 `sbpfExecutableTraceOk` + `counter_sbpf_executable_trace_ok`(native_decide)；**顺带废掉 Track 0.4 的裸子串 `hasEntrypointDispatch`**（真执行检查取代它） | `Backend/Solana/Refinement.lean` | S1 |
| S3 | 模拟关系 `R : IR.State ↔ SbpfState`，用 `StateLayout.lean` 的账户数据偏移（Slice A：单个 U64 scalar slot） | `SbpfInterpreter.lean` | S1 |
| S4 | Slice B：ValueVault 多 scalar 字段（多 slot），在 sBPF 层观测 accounting 不变量 | — | S3 |
| S5 | Slice C：map/array —— 把 IR 存储-slot 模型移植到 sBPF scratch 内存 | — | S4 |
| S6 | **C-proof**：per-entrypoint 模拟引理 `R s s' → R (stepIR …) (runSbpf …)` + trace 归纳 | — | P1+P2, S3 |
| — | **非目标（留外部差分门）**：Slice D 的 CPI / PDA 派生 / 账户校验 prologue → Mollusk/Surfpool，不进 Lean | — | — |

### 7.2 WASM 语义（先写设计 note，再把执行搬进 Lean）

现状：执行在**外部 Rust `runtime/offline-host/main.rs`（882 行 wasmtime）**；Lean 内只有
`WasmTraceOp` 语法级 trace 抽取 + offline-host 边界义务。任务是把可执行语义搬进 Lean。

| # | 任务 | 产出 / 落点 | 依赖 |
|---|---|---|---|
| W1 | **新写设计 note**（镜像 Solana 那份）：Wasm 栈机子集 + 抽象 host 模型 + 分期 | `docs/wasm-executable-trace.md`（新） | — |
| W2 | `WasmInterpreter.lean`：`WasmState`(值栈/locals/线性内存/抽象 host 态) + `step`/`eval` 覆盖 EmitWat 发出的指令子集（`i64.const/add/sub/mul`、`local.get/set`、`i64.load/store`、`block/loop/br/br_if/if/call/return`）+ fuel-bounded。**复用现有 `WasmTraceOp` 作指令枚举** | `Backend/WasmHost/WasmInterpreter.lean`（新） | P1, W1 |
| W3 | host 模型：`HostBridge` 的 `storage_read/write/value_return/…` 作抽象 host 态上的纯转移；**按 `HostBridge` 参数化**（接 W0 → CosmWasm/Soroban 可复用） | `WasmInterpreter.lean` | W2 |
| W4 | `observe` + 差分义务 `wasmExecutableTraceOk` + native_decide 定理。**把执行搬进 Lean**（今天靠外部 Rust host） | `Backend/WasmHost/Refinement.lean` | W2,W3 |
| W5 | 模拟关系 `R : IR.State ↔ WasmState host storage`，用 `Layout.lean` 的 Borsh key 派生 | `WasmInterpreter.lean` | W2 |
| W6 | **C-proof**：模拟引理 + 归纳 | — | P1+P2, W5 |
| — | **非目标（留 offline-host/wasmtime 差分门）**：NEAR Promise / async / CPI 等价 | — | — |

### 7.3 为什么必须先做 P1（两者的公共结构）

| 部件 | Solana | WASM |
|---|---|---|
| 机器状态 | `SbpfState`（寄存器机） | `WasmState`（栈机 + host 态） |
| `step` | 每指令 | 每指令 |
| `run` | fuel-bounded → total | fuel-bounded → total |
| `R` 关系 | `StateLayout` 账户偏移 | `Layout` Borsh key |
| `observe` | r0@exit → `ObservableReturn` | `value_return` payload → `ObservableReturn` |
| C-diff 义务 | `sbpfExecutableTraceOk` | `wasmExecutableTraceOk` |
| C-proof | 模拟引理 + 归纳 | 模拟引理 + 归纳 |

七行完全同构 → **不要建两套 bespoke 解释器 + 两套 obligation 类型**；先落 P1 的
`TargetSemantics` 接口，两者各 instantiate。EVM 的 in-tree `YulSemantics` 也应回收进同一
接口（第三个 instance）。

### 7.4 放到哪里（你问的"看看放到哪里"）

- **Solana 详细解释器设计**：已在 `docs/solana-sbpf-executable-trace.md`——**执行它**、完成后
  更新其 Status 与 `formal-verification.md` 的 Tier C-diff 行。
- **WASM 详细解释器设计**：**新写 `docs/wasm-executable-trace.md`**（W1，镜像 Solana 那份）。
- **任务排期**：本节（7.x）即清单；可落地版应 graduate 到英文
  [implementation-backlog](../implementation-backlog.md) 的 **Workstream 25（FV）**。
- **新增代码文件**：`Backend/Refinement/Core.lean`（P1）、
  `Backend/Solana/SbpfInterpreter.lean`（S1）、`Backend/WasmHost/WasmInterpreter.lean`（W2）。

### 7.5 依赖顺序

```text
P1 共享接口 ─┬─→ S1→S2→S3 (Solana C-diff, 现在就能做) ─┬→ S4→S5 (深化)
             └─→ W1→W2→W3→W4→W5 (WASM C-diff) ────────┘
P2 IR 归纳(部分已落) ─┬─→ S6 (Solana C-proof)
                      └─→ W6 (WASM  C-proof)
```

**一句话**：先落 P1 共享 `TargetSemantics` 接口，然后**两条 C-diff 解释器并行**
（Solana 照 `solana-sbpf-executable-trace.md` 执行；WASM 先补 `wasm-executable-trace.md`
再把执行从外部 Rust host 搬进 Lean）——这一步只需 P1、现在就能动，且立刻把 Solana 从
"子串检查"、WASM 从"外部执行"升级成"in-Lean 真执行检查"。C-proof（S6/W6）是叠加在
P2 归纳之上的后一层。

### 7.6 优先级修正：从逐点 fixture 到全称覆盖（"IR 覆盖所有链"的正确路径）

> 观测确认：现有目标可执行-trace 定理覆盖 **2 个合约（Counter/ValueVault）+
> 2 个存储 probe（fixed array / u64 map）**，仍然是逐点 `native_decide`、
> 标量 + 少量 map/array 子集。本小节据此**修正 7.1/7.2 的优先级**：先立支持片段 +
> 首个全称证明，再扩广度。

**为什么加 fixture 到不了"覆盖所有语义"**：`native_decide` 本质逐点求值一个闭合项，
证的是"这一个合约/fixture、这一组输入"。加 ERC20/DEX 就是加 N 条 fixture + 每次扩解释器，
**线性跑步机，永远到不了"所有合约/所有输入"**（连 ValueVault 都只验默认输入一个点）。
**逐点绿定理 ≠ 语义被覆盖。**

**修正后的优先级（先全称、再广度，取代 S4/S5 早于 S6 的排法）**：

1. **[先落] IR Counter 片段 total 化（Track 1.1）**：把全称证明要用的
   Counter IR 解释路径从 `partial def` 旁路出来，改成 fuel-indexed total `def`，并给
   `initialize/get/increment` 建 per-entrypoint 全状态 lemma。
2. **[上移] 首个全称 C-proof（哪怕只 Counter）**：把 `counter_*_executable_trace_ok`
   从 `native_decide`（单输入）升级成 `∀ input, observe(target)=observe(IR)`（对所有
   调用序列/输入全称），用 `IRTraceMatches` 归纳 + per-entrypoint 模拟引理。**这是
   验证"全称路走得通"的关键点。**
3. **[接上] 支持片段谓词（Track 1.4）**：每个目标定义可判定的
   `SupportedFragment(target, module) : Bool`，精确圈定"该目标能忠实下降的 IR
   节点/形状"。**单一真相源**，替代散在三层的拒绝逻辑（capability / validate / Phase-1）。
4. **[然后才] 按节点扩广度（原 S4/S5 及 WASM 深化）**：每扩一类节点
   （map/struct/events/hashing/位宽），三件事同步——(a) 扩 `SupportedFragment` 谓词、
   (b) 扩解释器、(c) 扩模拟引理。**全称定理自动覆盖用到该节点的所有合约**，不再一合约
   一 fixture。
5. **片段外**：`SupportedFragment = false` 的模块**编译期拒绝**（接 Track 0 的能力/校验门，
   顺带修 0.1/0.2/0.3 的漏）。

**当前落地状态（2026-07-07）**：`ProofForge/IR/CounterSemantics.lean` 已把 Counter
IR 片段 total 化；`ProofForge/Backend/Refinement/CounterUniversal.lean` 已证明
Counter per-entrypoint simulation 与任意 Counter call list 的 trace 归纳（目标是很小的
`counter-model`，不是 EVM/Solana/Wasm VM）；`ProofForge/Backend/Refinement/Core.lean`
新增 `TargetSemantics.supportedFragment`，目前只声明/接受 canonical Counter 片段并拒绝
checked/renamed Counter。对应 smoke：`just ir-counter-semantics-smoke`、
`just counter-universal-refinement-smoke`、`just supported-fragment-smoke`。

**"IR 覆盖所有链"的准确机制**：不是"给每条链手写 N 个合约 fixture"，而是对每个目标证

> `∀ module ∈ SupportedFragment(target), ∀ input,`
> `  observe(target(module,input)) = observe(IR(module,input))`，片段外编译期拒绝。

**一条谓词 + 一条全称定理，覆盖片段内无穷多合约**；换链 = 换一份目标 Lean 语义（自建，
或引入 `powdr-labs/evm-semantics` / Cairo formal-proofs / Lampe，见第六节）+ 重新实例化同一
`TargetSemantics` 接口（P1）。这才是 IR 通吃所有链的机制，而不是 fixture 堆叠。

**修订依赖顺序（取代 7.5 的图）**：

```text
P1 共享接口
  └→ Track 1.1 IR total 化 ─→ [支持片段谓词] ─→ [首个全称 C-proof: Counter] ─→ 广度×全称同步推进
                             （原逐点 C-diff 解释器 S1..W5 作为回归 smoke 保留）
```

**诚实边界**：全称也只覆盖**支持片段**，非任意图灵完备逻辑；全套链运行时
（CPI/syscall/Promise/账户模型）永远留外部差分（Mollusk/wasmtime），是 non-goal。
"覆盖所有链" = "覆盖每条链的支持片段、全称，片段外拒绝"，不是"任意合约都能证"。

### 7.7 引入 vs 自建：自建目标别啃完整 VM（两跳信任 + 外部差分门必留）

参照 EVM 用 `powdr-labs/evm-semantics` 的做法后，一个必须记清的区分——否则实现时容易
误以为要在 Lean 里啃完整 sBPF/WASM VM：

- **EVM = 引入**：`powdr-labs/evm-semantics` 现成（Lean v4.31，与本仓一致；关系 `Step` +
  可执行 `stepF`），挂 **opt-in lake 依赖**、对它的关系 `Step` 证精化——**不自己写 EVM 语义**。
- **Solana / WASM = 自建，但只建片段**：无现成 Lean 语义，写解释器（S1/W2）；但**自建 ≠
  重写完整 VM**，只 model 被下降到的指令 + host 子集（ALU / 存储 / 控制流）。完整 VM
  （Solana CPI/PDA/syscall/账户模型；NEAR Promise/async）留外部门（见 7.1/7.2 非目标）。
  是**小而可审计的片段解释器，不是链 runtime**。

**两跳信任（自建的代价，外部差分门必须永久保留）**：

- **引入（EVM）**：powdr 的 `Step` 拿 `ethereum/tests` 测过 → "Lean 模型 ≈ 真 EVM"是它的
  活；你只证**一跳** `IR ⟷ powdr Step`。
- **自建（Solana/WASM）**：你证 `IR ⟷ 你的解释器`（纯 Lean、无 mathlib、可控）；但"你的
  解释器 ≈ 真机"这**第二跳不在 Lean 里证**，靠**外部差分门**（Mollusk/Surfpool；
  wasmtime/offline-host）兜。**自建目标永远不能删/弱化这个门**——它是唯一能抓到手写解释器
  和真机悄悄发散的东西。

**WASM 专属备注**：WASM 是标准化 ISA，将来若出现成熟的 Lean 4 WASM 语义，核心部分可切成
"引入"（像 EVM 那样）；但 **host 部分（NEAR `env.storage_read`/`value_return` 等）是链专属，
无论如何都得自建**。所以 WASM = "核心也许将来能引入 + host 永远自建"，Solana 目前 = "全自建"。

不管引入还是自建，都插进同一个 `TargetSemantics` 接口（P1）：关系 `Step`（供 C-proof 归纳）
+ 可执行 `step`/`stepF`（供 C-diff `native_decide`）。**自建的也照抄 powdr 的"关系 + 可执行"
双结构。**

**战略含义**：有现成 Lean 语义的链（EVM/Cairo/Noir/JAR）验证便宜（引入 + 一跳信任）；没有的
（Solana/WASM/Move）要自建（写片段解释器 + 两跳信任 + 永留外部门）。规划 FV 优先级时，优先
推有现成语义的那批。
