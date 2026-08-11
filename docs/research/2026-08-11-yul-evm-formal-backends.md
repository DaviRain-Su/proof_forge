---
id: RESEARCH-YUL-EVM-FORMAL-BACKENDS
title: Yul/EVM 形式化 backend 候选登记（非赛期依赖）
status: draft
owner: research
updated: 2026-08-11
normative: false
---

# Yul / EVM 形式化 backend 候选登记

> **产品决策（2026-08-11）**  
> - **Hackathon / ForgeRWA / 赛期产品路径：不接入、不依赖** 外部 Yul→EVM 已证编译器或 EVM 形式语义包（无 Lake import、无 dual materializer 切换、无「已形式化编译」对外声称）。  
> - **正式 D4 / EVM formal lighthouse：登记为候选**，按阶段评估；接入形态最多是 **可选 backend / 差分 / refinement 桥**，不得替换 `SemanticProgramV1` 权威或新增第二套业务语义机。  
> - 产品竖切规划见 [`docs/plan/ai-rwa-verified-ship-xlayer.md`](../plan/ai-rwa-verified-ship-xlayer.md) §7.4。  
> - 范围对齐 [`ADR-0036`](../adr/0036-engineering-scope-and-evm-formal-lighthouse.md)：EVM-first formal 不得用外部工程 positives 或黑客松交付代签。

**性质**：研究登记与边界说明；`normative: false`；不关闭任何 formal TASK。

---

## 1. 触发来源

- 推文：[Leo Alt (@leonardoalt) — EVM formal methods 列表更新](https://x.com/leonardoalt/status/2086829714144944549)（2026-08-10）  
- 地图仓库：[leonardoalt/ethereum_formal_verification_overview](https://github.com/leonardoalt/ethereum_formal_verification_overview)  
- 点名相关：equiVM、evm-asm、evm-sail、**powdr `{evm,yul}-semantics` + verified yul-c** 等  

本文只登记与 ProofForge **EVM materializer / D4 refinement** 可能相交的 Lean（及相邻）工作；不写成竞品踩踏文。

---

## 2. 层位：为什么不是「接上就更好」

```text
ProofForge 信任链（工程现状）

  program ... where
       ↓
  SemanticProgramV1 + Reference step     ← 业务语义 / 不变量主场（产品证明门禁）
       ↓
  EVM Plan / IR
       ↓
  工程 Yul
       ↓
  solc --strict-assembly                 ← 未证编译器（工程门）
       ↓
  bytecode → Anvil / X Layer

外部形式化主场（候选）

  Yul（或 Sol⁻ 等）
       ↓
  形式化 Yul / EVM 语义
       ↓
  已证或可证 Yul→EVM / 字节码性质
```

| 层 | ProofForge 现状 | 外部候选价值 |
|---|---|---|
| 统一 DSL → 多 target | 产品主线 | 通常无 |
| 业务不变量 + 同文件 proof gate | Reference 侧 engineering | 路径不同 |
| **Yul→EVM 编译正确性** | 依赖 solc | **高（长期）** |
| EVM 可执行/关系语义 | 工程差分（Anvil 等） | **高（长期 differential）** |
| 两周 AI-RWA + X Layer ship | 现货管线 | **无直接帮助** |

**结论**：「更好」仅对 **IR/字节码形式可信** 成立；对 **ForgeRWA 赛期交付** 不成立。赛期接入会把产品工期换成 compiler research，并抬高 overclaim 风险。

---

## 3. 候选清单（登记，非选型终裁）

评估时统一看四列：**Lean 可组合性**、**与我们 emit Yul 的子集交集**、**许可证/维护**、**是否可做 optional profile 而不改 sole authority**。

### 3.1 高优先级（D4 预研首选阅读）

| 候选 | 组织/仓库 | 角色 | 对 ProofForge 的可能用途 |
|---|---|---|---|
| **EVMYulLean** | [NethermindEth/EVMYulLean](https://github.com/NethermindEth/EVMYulLean) | Lean 可执行 EVM + Yul 模型（Cancun 等） | Reference/Anvil 之外的 **语义差分**；Yul 解释对照 |
| **powdr EvmSemantics** | [powdr-labs/evm-semantics](https://github.com/powdr-labs/evm-semantics) | Lean 关系小步/大步 EVM + 可执行解释器 soundness | 同上，第二对照系 |
| **powdr yul-semantics** | [powdr-labs/yul-semantics](https://github.com/powdr-labs/yul-semantics) | Yul 语义（Lean） | Plan/IR→Yul 后的 **Yul 层性质** |
| **powdr yul-compiler** | [powdr-labs/yul-compiler](https://github.com/powdr-labs/yul-compiler) | **片段** Yul→EVM 已证编译；证不过则拒编译 | 可选 **verified-yulc** profile（仅子集命中时） |
| **Solidus Yul→EVM backend** | Paradigm 等公开材料 / EVMYulLean fork | 另一套已证 Yul→EVM backend | 与 powdr 并列评估，**勿赛期押一家** |

### 3.2 中优先级（旁路验证，非 materializer）

| 候选 | 角色 | 可能用途 |
|---|---|---|
| **Clear** ([NethermindEth/Clear](https://github.com/NethermindEth/Clear)) | Yul 程序交互式 FV / VC | 对 **已生成 Yul** 做性质证明；不替代 compile 路径 |
| **hevm / Kontrol / KEVM** | 符号执行 / K 语义 | 工程差分与 bug hunting；非 Lean 同内核 |
| **equiVM** (argotorg) | 高层 Sol⁻ 与字节码 refinement（偏 agent 产出） | 叙事相邻；语言栈不同 |
| **evm-smith** (Leo Alt) | AI 写字节码 + Lean 安全证明（基于 EVMYulLean） | 研究对照；不是 ProofForge DSL 路径 |

### 3.3 低优先级 / 观察

| 候选 | 备注 |
|---|---|
| evm-sail | Sail→多证明助手；集成成本高 |
| evm-asm / EthIsabelle | 历史或不同层；维护状态需再查 overview ⚠️ |
| Verity / Blanc / Jaune | Lean 合约/EVM 相关独立栈；避免重复造轮与权威分裂 |

**地图权威入口**：持续以 [ethereum_formal_verification_overview](https://github.com/leonardoalt/ethereum_formal_verification_overview) 为准更新本表，本文件只记 **ProofForge 决策与用法**。

---

## 4. 禁止与允许

### 4.1 赛期 / ForgeRWA **禁止**

- Lake 依赖上述仓库或 fork 进入 **产品** `lakefile` / 产品 CLI 路径  
- 用 verified yul-c **替换** 现货 `solc --strict-assembly` 作为 sole emit  
- 对外声称：「Yul→EVM 已形式化验证」「字节码被证明」「接入 powdr/Nethermind 即 formal D4 完成」  
- 用外部 backend 进度 **关闭** formal TASK 或代签 Stage-0 / hermetic  
- 为接入而改 ProgramV1 权威或新增平行 `step`/业务语义机  

### 4.2 赛期 **允许**（上限）

- README / 相关工作一节 **点名** 生态（1 段，无依赖）  
- **桌面调研 ≤1 人日**：抽样对照我们 emit 的 Yul 是否落入某 compiler 的可证片段（结论写回本文附录，仍不 import）  
- 研究 worktree **只读 clone** 跑对方测试（不进主产品 CI）  

### 4.3 赛后 / D4 **允许的接入形态**（需单独 ADR 或任务）

```text
阶段 0  本文登记（已完成决策）
阶段 1  差分：同一 Program 制品 vs 对方 interpreter/语义（研究门，非产品）
阶段 2  可选 profile：工程 solc 仍为 default；verified-yulc 仅子集 fail-closed
阶段 3  formal：Semantic/Reference ⟷ Yul 语义 ⟷ EVM 小步 refinement 陈述
```

Sole authority 不变：

- 源与语义：`ProgramV1` / `SemanticProgramV1` / Reference  
- 工程 emit：现货 EVM materializer + solc（default）  
- 外部包：最多 **backend plugin / 证明对象**，不得成为第二产品编译器  

---

## 5. 与 ADR-0036 / 任务边界

| 文档/任务 | 关系 |
|---|---|
| [ADR-0036](../adr/0036-engineering-scope-and-evm-formal-lighthouse.md) | formal lighthouse = EVM-first；本登记服务 D4 预研，不扩大 accepted PRD |
| formal TASK-D2-07 / TST-SEM-002/003 | 仍 pending；外部 EVM 模型 **不**自动满足 |
| formal D4 / target refinement | 未来可消费阶段 1–3；黑客松 **不**推进 |
| [plan A×C](../plan/ai-rwa-verified-ship-xlayer.md) | 赛期交付以 plan 为准；本文件只钉 backend 边界 |

---

## 6. 诚实表述模板（对外）

**可以说：**

- 产品路径使用工程 solc 物化；业务侧有 machine-checked（engineering）gate。  
- 我们跟踪 powdr / Nethermind 等 Yul·EVM Lean 工作，作为 **未来 refinement 候选**。  

**不可以说：**

- 已集成 verified Yul→EVM compiler。  
- 部署字节码已经过形式化验证。  
- 与 EVMYulLean 语义一致（除非阶段 1 差分已有可引用证据）。  

---

## 7. 开放问题（赛后填）

- [ ] 我们当前 EVM Yul emit 的 op/storage/call 子集 vs powdr yul-compiler 可证片段交集  
- [ ] 同一子集 vs Solidus backend 的证明义务与 gas/memory 模型假设  
- [ ] EVMYulLean 与 Anvil 差分：哪些 fixture 可自动化  
- [ ] Lake 版本 / 依赖膨胀 / SBOM 政策若 optional profile 引入  
- [ ] 是否需要独立 `CodegenProfileId`（例如 `evm-yulc-verified-v0`）而非替换 default  

---

## 8. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-08-11 | 初版：赛期不接入；D4 候选登记；对齐 Leo Alt overview 与 A×C plan |

---

*冲突时：赛期产品行为以 [`ai-rwa-verified-ship-xlayer.md`](../plan/ai-rwa-verified-ship-xlayer.md) 为准；形式化成熟度与 TASK 状态以 `docs/04-task-breakdown.md` / ADR-0036 为准；本文件只约束 **外部 Yul/EVM formal backend 的依赖边界**。*
