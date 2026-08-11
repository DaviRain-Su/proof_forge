---
id: PLAN-AI-RWA-VERIFIED-SHIP-XLAYER
title: A×C 合一 — Verified Ship 平台 + AI-RWA 竖切（X Layer AI Season）
status: draft
owner: product+engineering
updated: 2026-08-11
normative: false
---

# A×C 合一：Verified Ship + AI-RWA

> **目标**：把两条叙事压成**一条可演示产品**，而不是两个并行项目。  
> - **A（平台脊骨）**：Web3 Vercel — 自然语言 / 模板 → `program ... where` → check/proof gate → materialize → **X Layer 部署**。  
> - **C（黑客松竖切）**：AI-RWA — 用同一条脊骨交付「真实世界资产登记 / 份额 / 受限转让」场景，争取 **评审奖 + AI-RWA Liquidity Grant 叙事资格**。  
>
> **性质**：工程/产品规划，不改写 accepted PRD/Architecture/Technical Spec；不关闭 formal TASK；不声称 hermetic / formal Stage-0 / 链上字节码已证明。

## 0. 先给结论

| 问题 | 结论 |
|---|---|
| A 和 C 是两个产品吗？ | **否。** A 是管线；C 是管线上的默认业务模板 + 演示 DApp。 |
| 对外一句话怎么说？ | **AI 起草 RWA 份额合约，经 ProofForge 机器核验门禁后，一键部署到 X Layer。** |
| 隐喻怎么站？ | 主隐喻 **Vercel（Verified Ship）**；RWA 是首个 **template vertical**；**不是** Cloudflare / 通用 CDN。 |
| 和既有调研关系？ | 继承 [`docs/research/2026-08-10-xlayer-hackathon-proofforge/final.md`](../research/2026-08-10-xlayer-hackathon-proofforge/final.md) 的可行性结论（LLM→DSL→EVM 已实测）；把原「金库护栏」**升维为 RWA 份额金库**，护栏（白名单/限额）变成 RWA 合规控制面的一部分。 |
| 两周内必须 ship 什么？ | **一条竖切闭环**：AI 生成 → check → build → X Layer testnet 部署 → 前端/agent 演示 claim/transfer/拒绝路径；可选 proof 族内 certified 演示。 |
| 明确不做？ | 不接真实法域托管；不做完整证券合规；不刷 Launch Grant 量；不改 formal D2–D4；不新增第二套语义机。 |
| **外部 Yul→EVM 形式化要不要先接入？** | **不要。** 赛期产品路径 **不依赖** powdr yul-c / EVMYulLean / Solidus 等；仅 **D4 候选登记**。权威说明见 [§7.4](#74-外部-yulevm-形式化-backend赛期不接入-d4-登记) 与 [`research/2026-08-11-yul-evm-formal-backends.md`](../research/2026-08-11-yul-evm-formal-backends.md)。 |

```text
                    ┌─────────────────────────────────────┐
                    │  C · AI-RWA vertical (用户看见的)     │
                    │  资产登记 / 份额 / 白名单 / 限额转让   │
                    └─────────────────┬───────────────────┘
                                      │ 同一份 program 源
                    ┌─────────────────▼───────────────────┐
                    │  A · Verified Ship spine (差异化)     │
                    │  NL/模板 → ProgramV1 → check/proof     │
                    │  → EVM materialize → X Layer deploy   │
                    └─────────────────┬───────────────────┘
                                      │
                              X Layer (1952/196)
                              + OKX Wallet / 可选 DEX
```

**一句话产品定义（提交表单用）：**

> **ForgeRWA**（暂定名）：面向 AI agent 与开发者的 **verified onchain ship 工作台**。  
> 你用自然语言描述 RWA 份额规则，AI 写出 ProofForge 程序；只有通过语义检查与（可选）同文件证明门禁后，才会编译并部署到 X Layer。  
> 首发竖切：可证明约束下的 **链上份额登记与受限转让**（AI-RWA）。

---

## 1. 为什么必须 A+C 合体（而不是二选一）

### 1.1 单独做 A（纯 Verified Ship）的问题

| 优点 | 风险 |
|---|---|
| 与 ProofForge 长期定位一致（Vercel） | OKX 系评审对「纯开发工具」偏冷（ETHCC Security 赛道曾空奖） |
| 可复用 MCP / CLI / EVM 链路 | 缺垂直用户故事，难讲「谁天天用」 |
| 可扩展多模板 | 难对齐 **AI-RWA Liquidity Grant** 叙事 |

### 1.2 单独做 C（纯 AI-RWA DApp）的问题

| 优点 | 风险 |
|---|---|
| 赛道名明确（Liquidity Grant 面向 AI-RWA） | 变成又一个登记/份额合约，**ProofForge 可替换** |
| 可做前端、可上主网 | AI 若只是文案生成器，评审不买账 |
| 有增长话术空间 | 与仓库核心差异（证明门禁 / 统一源）脱节 |

### 1.3 合体原则

| 层 | 归属 | 对外怎么讲 |
|---|---|---|
| **Spine（A）** | 永远可见：生成 → 门禁 → 部署 | 「不是 vibe code 直接上主网」 |
| **Vertical（C）** | 默认模板 + 演示业务 | 「首个落地场景是 AI-RWA 份额」 |
| **Guard（原调研 A 护栏）** | C 的合规控制子集 | 白名单 / 单笔限额 / 窗口累计 = RWA 转让约束 |
| **非目标** | Launch Grant 交易量冲刺 | 赛期默认不追；主网义务另表 |

**评审主语必须是 AI 应用**，安全/编译是 AI 产物的属性：

- ✅ 「AI 帮你起草 RWA 规则并部署」
- ❌ 「我们是一个形式化验证编译器」
- ❌ 「我们是 Web3 Cloudflare」

---

## 2. 产品切片：用户看到什么

### 2.1 角色

| 角色 | 诉求 | 在 demo 中的动作 |
|---|---|---|
| **Issuer（发行方）** | 登记一项 RWA、设定份额与转让规则 | 对话描述资产 → 确认 program → 部署 |
| **Holder（持有人）** | claim / 受限转让 | 钱包连 X Layer 测试网 → 调 entry |
| **Agent（AI 协作者）** | 从 NL 生成/修复 program | MCP 或 Web 对话；展示失败重试 |
| **Auditor（叙事用）** | 看门禁有没有拦住坏规则 | proof gate 拒绝错误定理 / check 拒绝坏形状 |

### 2.2 端到端用户旅程（90s demo 骨架）

```text
1. Issuer: 「登记一笔代币化发票份额，总量 1_000_000，仅白名单地址可受让，
            单笔 ≤ 50_000，每 1000 block 窗口累计 ≤ 200_000。」
2. AI: 生成 program RwaShareV1 where ...（高亮 state / entry / 可选 invariant+proof）
3. check: 诊断通过；若含 theorem → certified（族内模板，现场跑）
4. build --target evm: 产出 abi/bin/yul + proof-forge.output.v1
5. deploy: cast/脚本 → X Layer testnet（chainId 1952），explorer 链接
6. 正路径: 白名单 claim/transfer 成功，状态可读
7. 负路径: 超限额 / 非白名单 → revert（链上可见）
8. 高潮（可选）: 故意坏 theorem 或坏规则 → proof/check 拒绝，**零部署制品**
```

### 2.3 最小 UI 表面（黑客松）

不必做完整 SaaS，三页够：

| 面 | 内容 | 技术建议 |
|---|---|---|
| **Studio** | 对话 + 生成源码 + check/build 日志 | 本地 CLI/MCP 包装一层 Web，或 Streamlit/简单 Next |
| **Deploy** | network 选择（仅 xlayer testnet 默认）+ 部署按钮 + 地址 | 密钥仅本机 env；对齐 [`product/13-xlayer-onchainos.md`](../product/13-xlayer-onchainos.md) |
| **DApp** | attach 已部署地址：claim / transfer / view | 复用 [`product/08-evm-dapp-frontend.md`](../product/08-evm-dapp-frontend.md) + `templates/evm-dapp-ui` |

---

## 3. 业务模型：什么叫「我们的 AI-RWA」（刻意收窄）

### 3.1 合法叙事 vs 不碰的雷

| 可以说 | 不可以说 / 不做 |
|---|---|
| 链上 **份额登记与转让规则** 的可验证部署 | 真实法域证券发行、KYC 服务商一体化 |
| **规则由 AI 起草、门禁后上链** | 链下资产已托管完成 / 有法律强制力 |
| 演示资产元数据哈希上链 | 实时预言机喂价完整 RWA 定价 |
| 白名单 = 简易准入控制（工程） | 完整 AML/KYC 合规产品 |

对外英文可用：**Onchain share registry with transfer policy** under AI-RWA track；  
中文可用：**AI 驱动的受限份额登记（RWA-oriented）**。

### 3.2 合约状态机（EVM 子集可交付）

对齐当前 EVM/Normalize **工程子集**（public 整数、Map、控制流、checked 算术、revert、白名单风格 Map 等；以仓库现货为准，开发前再钉死 fixture）。

**建议唯一竖切 program 形状（伪结构）：**

```text
program RwaShareRegistry where
  -- 元数据（链上只存承诺，不存 PDF）
  state assetIdHash : public UInt256   -- 或 Bytes/哈希拆叶，按现货能力
  state totalSupply : public UInt64
  state issued : public UInt64

  -- 份额账本
  state balance : public Map Principal UInt64   -- 若 Principal 未就绪则用固定地址编码/UInt 键

  -- 转让策略（= 护栏，原调研 A）
  state allowlist : public Map Principal Bool
  state maxPerTx : public UInt64
  state windowCap : public UInt64
  state windowSpent : public UInt64
  state windowStart : public UInt64     -- block/time 若 context 可用；否则简化为全局 spent

  init ...
  entry issue(to, amount)      -- 仅 issuer；issued+balance 守恒
  entry transfer(to, amount)   -- allowlist + maxPerTx + windowCap
  entry setAllow(addr, ok)     -- 仅 issuer
  view balanceOf(addr)
  view policy()
```

**不变量（工程 / 可选证明族）：**

| 不变量 | 运行时手段 | 证明演示 |
|---|---|---|
| `issued ≤ totalSupply` | check + 代码结构 | 族内 parity/有界形状 stretch |
| `sum(balance) == issued` | 子集若难维护全图，则 demo 用单 holder 或双 holder 手工不变量 | 诚实声明工程门禁 |
| `transfer amount ≤ maxPerTx` | require/revert | 链上负路径 |
| `windowSpent ≤ windowCap` | require | stretch shape 引理（同 final.md a'） |

### 3.3 与「金库护栏」的映射（复用调研资产）

| 原 ProofGuard 概念 | 升维到 ForgeRWA |
|---|---|
| Agent 支付白名单 | 份额受让白名单 |
| 单笔限额 | 单笔转让上限 |
| 窗口累计限额 | 窗口转让上限（反倾倒） |
| 金库余额 | `balance` 账本 + `issued` |
| 坏策略被 proof 拒 | 坏 RWA 规则 / 坏定理被拒 |

**结论**：原 vault-v1 实验不是废弃，而是 **C 竖切的策略层内核**；外皮从「支付金库」换成「RWA 份额登记」。

### 3.4 可选「AI-RWA」增强（优先级）

| 增强 | 优先级 | 说明 |
|---|---|---|
| 链下 PDF/发票 → AI 抽字段 → 填 program 参数 | **P0** | 强化 AI 与 RWA 叙事；哈希上链 |
| 发行事件 emit | P1 | 便于 explorer/索引 |
| 与 OKX DEX 的份额 token 可交易性 | **P2 / 赛后** | Launch Grant 相关；子集+合规复杂，赛期不做 |
| 多资产工厂 | P2 | 超出两周竖切 |
| 跨链 RWA | 不做 | |

---

## 4. 平台脊骨 A：Verified Ship 模块

### 4.1 流水线（与产品 CLI 对齐）

```text
Source (NL | 模板 | 手写 .lean)
    → AI codegen (MCP / 本地 agent)
    → Loader.selectProgramV1ProductWithTheoremInventory
    → normalize / compileProgramProductV1
    → certifyInlineProofV1   (有 theorem 时；fail → 早退)
    → resolve EVM profile
    → materialize + finalize → proof-forge.output.v1
    → (本机) deploy script → X Layer testnet
    → dApp attach
```

权威边界见：

- [`product/13-xlayer-onchainos.md`](../product/13-xlayer-onchainos.md) — 网络 / 密钥 / OnchainOS 分工  
- [`adr/0027-inline-same-file-theorem-certification.md`](../adr/0027-inline-same-file-theorem-certification.md) — 同文件 proof  
- 调研 final — LLM 生成与 proof 族悬崖  

### 4.2 AI 层职责（必须「在关键路径」）

| AI 做什么 | AI 不做什么 |
|---|---|
| 从 NL + 字段表生成 **合法 ProgramV1 子集** | 绕过 check 直接部署 |
| 根据诊断（PF-*）自动改源 2–4 轮 | 声称任意业务定理自动证明 |
| 解释策略：白名单/限额含义 | 密钥管理 / 广播交易（交给本机） |
| 从文档抽 RWA 元数据 → 参数 | 编造法域合规结论 |

**MCP 最小能力（P0）：**

1. `pf_check` / `pf_build`（若缺 check wrapper，按调研补）  
2. `pf_networks` 或读 catalog：只允许 `evm.xlayer.testnet` 默认  
3. 提示词内嵌 **RwaShare 模板 + 禁止语法列表**（来自实测坑）  

### 4.3 模板库（A 可扩展、C 只 ship 一个）

| 模板 id | 场景 | 赛期 |
|---|---|---|
| `rwa-share-v1` | 受限份额登记 | **必须** |
| `agent-vault-guard-v1` | 纯支付护栏（调研原 A） | 降级备份 |
| `counter-v1` | smoke | 内部 |

用户感知上：**Studio 默认打开 RWA 模板**；「更多模板」灰掉或标注 coming。

### 4.4 诚实证明叙事（提交材料必写）

| 可以说 | 不可以说 |
|---|---|
| machine-checked gate before deploy | full formal verification of bytecode |
| same-file Lean theorem certification（engineering） | Stage-0 / hermetic evidence |
| 坏规则/坏证明导致 **fail closed、零制品** | 任意自然语言规格自动证明 |
| certified 文件与 deploy 文件若孪生，工程纪律绑定 | 密码学绑定孪生源（除非做出一致性工具） |

若仍存在 **invariant 阻碍 EVM build** 的孪生双文件策略：在 README 首屏画清 check 文件 vs deploy 文件，并尽量提供 canonical 一致性检查脚本（调研 R2）。

---

## 5. 架构总图

```text
┌──────────────┐   NL / PDF 字段    ┌────────────────────┐
│  Web Studio  │ ─────────────────► │  AI Agent (MCP)     │
│  + dApp UI   │ ◄── 源码/日志/地址 ─ │  codegen + repair   │
└──────┬───────┘                    └─────────┬──────────┘
       │                                      │
       │ attach / view                        │ pf_check / pf_build
       │                                      ▼
       │                            ┌────────────────────┐
       │                            │  ProofForge CLI     │
       │                            │  compile + proof    │
       │                            │  EVM materialize    │
       │                            └─────────┬──────────┘
       │                                      │ artifacts
       │                                      ▼
       │                            ┌────────────────────┐
       └───────────────────────────►│  Deploy (local key) │
                                    │  X Layer 1952/196   │
                                    └────────────────────┘

可选：OnchainOS MCP —— 行情/DEX（赛期非关键路径；赛后探索份额可交易性）
```

**密钥纪律（不可破）：**

- 远程 MCP **永不**持有部署私钥  
- 部署仅 `cast` / 本机脚本 + env  
- 用户 dApp 交互走钱包  

---

## 6. 奖项与定位映射

| 奖项 | 合体方案怎么吃 | 策略 |
|---|---|---|
| **Hackathon 1/2/3** | AI 关键路径 + 完成度 + X Layer 真部署 + 差异化门禁 | **主目标** |
| **Liquidity 50k（AI-RWA）** | 产品明确 RWA 份额场景 + AI 文档抽取 + 叙事/完成度 | **主叙事对齐；不保证获奖** |
| **Launch ≤200k** | 需 OKX DEX 界面真实成交量 | **赛期不追**；避免 wash trading 风险 |

提交表单文案建议关键词：`AI-RWA` · `share registry` · `X Layer` · `verified deploy` · `agent`。

---

## 7. 与仓库能力的映射（交付边界）

### 7.1 依赖现货（已有或调研已证）

| 能力 | 状态 | 用途 |
|---|---|---|
| ProgramV1 + product compile | 现货 | 源权威 |
| EVM materialize（Yul/solc） | 现货 | X Layer 部署物 |
| X Layer 为 EVM 等效 | 现货结论 | 无需新 materializer |
| Inline proof gate（族内） | 现货 + 实测 ~11s | demo certified |
| LLM 写 vault 子集 | 调研 R3 实测 | 迁移为 RWA 模板 |
| networks catalog | `product/networks.v1.json` | chainId/RPC |
| evm-dapp-ui 模板 | 现货 | 前端 |

### 7.2 赛期必须新增（最小）

| 工作项 | 说明 | 验收 |
|---|---|---|
| `examples/` 或 `testdata/` 下 `RwaShareRegistry` 源 | 手写 golden，非仅 AI 输出 | check + build 绿 |
| AI system prompt + 模板 few-shot | 固定字段 schema | 2–4 轮收敛生成 |
| `scripts/deploy-xlayer-testnet.*` | 读 output 目录部署 | 返回 explorer URL |
| Studio 极简 UI 或脚本 orchestrator | 串起生成→check→build→deploy | 一键或一命令 |
| dApp 三动作 | issue/transfer/view + 负路径 | 测试网 tx |
| 项目 X 账号 + 90s 视频 | 资格条款 | 提交前可播 |
| README 诚实边界 | 中英各一段 | 无 overclaim |

### 7.3 明确延后

| 项 | 原因 |
|---|---|
| EVM invariant 完整 lowering | 高风险，调研已放弃赛期 |
| 任意 shape 自动证明 | 证明悬崖 |
| Launch Grant 刷量 / 做市 | 反作弊 + 非评审主路径 |
| 多 target（Solana…）同 demo | 稀释 X Layer 集成分 |
| 真实托管/预言机/法币入金 | 范围爆炸 |
| **外部 Yul→EVM 已证编译器 / EVM 形式语义 Lake 依赖** | 见 [§7.4](#74-外部-yulevm-形式化-backend赛期不接入-d4-登记)；季度级研究，不挡产品 |

### 7.4 外部 Yul/EVM 形式化 backend（赛期不接入 · D4 登记）

**决策（2026-08-11，已拍板写入本 plan）：**

> **Hackathon / ForgeRWA：不接入、不依赖** 外部 Yul→EVM 已证编译器或 EVM 形式语义包。  
> **并行：研究登记** 为 formal D4 / EVM lighthouse 的 backend 候选；禁止用其进度代签 formal TASK 或赛期「字节码已证明」叙事。

触发背景：[@leonardoalt 对 EVM formal methods 列表的更新](https://x.com/leonardoalt/status/2086829714144944549)（powdr yul-c / evm·yul-semantics、EVMYulLean 生态、equiVM 等）。完整候选表、禁止项与阶段 0–3 见：

**[`docs/research/2026-08-11-yul-evm-formal-backends.md`](../research/2026-08-11-yul-evm-formal-backends.md)**

#### 为什么赛期不接（摘要）

| 理由 | 说明 |
|---|---|
| 层位不同 | 对方主场是 **Yul/EVM 语义与编译正确性**；我们赛期差异化是 **Program→门禁→X Layer 应用** |
| 工期 | Lake 依赖、子集交集、refinement 桥 = **季度级**，不是周末级 |
| 评审 | 换 solc 几乎不加 AI-RWA 用户价值，反易被读成「纯工具」 |
| 权威 | 不得替换 `SemanticProgramV1` / 现货 EVM materializer sole path；不得第二套业务 `step` |
| 选型过早 | powdr yul-c、EVMYulLean、Solidus 等 **并行**；赛期钉死一家成本高 |
| 诚实表述 | 子集 WIP + 我们缺 Program→Yul 形式链 → 极易 overclaim |

#### 赛期边界（硬）

| 允许 | 禁止 |
|---|---|
| README「相关工作」点名生态（无依赖） | 产品 `lakefile` / CLI 依赖上述仓库 |
| ≤1 人日桌面调研：我们 emit 的 Yul 是否落入可证片段（结论写回 research 文） | 用 verified yul-c **替换** default `solc` emit |
| 研究 worktree 只读 clone（不进 ordinary 产品 CI） | 声称「已集成形式化 Yul→EVM / 字节码已证明 / formal D4 完成」 |

#### 赛后接入形态（仅登记，需另开任务/ADR）

```text
阶段 0  登记（本文 + research 文）     ← 当前
阶段 1  差分：制品 vs 对方语义/解释器   （研究门）
阶段 2  可选 profile：solc default + verified-yulc 子集 fail-closed
阶段 3  formal refinement：Reference ⟷ Yul ⟷ EVM
```

**Default 工程路径不变：**

```text
SemanticProgramV1 → EVM Plan/IR → 工程 Yul → solc --strict-assembly → bytecode
```

证明门禁赛期仍停在 **源 / Reference / inline theorem（engineering）**；不把外部 backend 写成已闭合的 target refinement。

#### 候选优先级（一览；细节以 research 文为准）

| 优先级 | 候选 | 未来用途 |
|---|---|---|
| 高 | Nethermind **EVMYulLean**；powdr **EvmSemantics** / **yul-semantics** | 语义差分、Yul 层对照 |
| 高 | powdr **yul-compiler**；**Solidus** Yul→EVM backend | 可选 verified emit profile（子集命中时） |
| 中 | **Clear**；hevm/Kontrol/KEVM | 旁路性质 / 工程差分 |
| 低 | equiVM、evm-smith、evm-sail 等 | 观察；语言栈不同 |

对齐：[`ADR-0036`](../adr/0036-engineering-scope-and-evm-formal-lighthouse.md)（EVM-first formal lighthouse；外部 positives 不代签 formal）。

---

## 8. 分阶段落地（建议日历）

假设提交截止 **2026-08-21 23:59 UTC**（以官方页为准）。一人或小团队：

| 阶段 | 日 | 交付物 | 失败降级 |
|---|---|---|---|
| **P0 Spike** | D1 | 手写 RWA 最小 program 在 **Anvil** check+build；同一 bin **cast 到 X Layer testnet** | 若 Map/Principal 撞线 → 改 UInt 编码地址键 |
| **P0 Template** | D2 | `rwa-share-v1` golden + 负路径测试（超限/非白名单） | 砍 windowCap，只留 maxPerTx+allowlist |
| **P1 AI loop** | D3–D4 | NL→生成→check 修复闭环；文档字段抽取 | AI 只填参数，源用固定模板 |
| **P1 Proof demo** | D4–D5 | 族内 certified 变体 + 坏定理拒绝预录 | 仅 check 门禁 money shot |
| **P1 Deploy UX** | D5–D6 | 一键脚本 + 前端 attach | 纯 CLI + 固定 HTML |
| **P2 Polish** | D7–D9 | 视频、X 运营、README、表单预填 | 砍 Studio UI |
| **P2 Buffer** | D10–D11 | 压测 testnet、提交 | — |
| **Post** | 赛后 | 主网部署义务；可选 OnchainOS/DEX 探索 | — |

### 8.1 每日「合体」检查清单

每天结束时必须能回答三个「是」：

1. **A 还在吗？** 是否仍有生成→门禁→制品路径（不是只剩手写合约）？  
2. **C 还在吗？** 用户是否仍理解这是 RWA/份额而不是通用 vault？  
3. **X Layer 还在吗？** 是否有新的或仍有效的 testnet 地址？

任一变「否」→ 次日优先修，不扩 scope。

---

## 9. 风险与缓解（合体特有）

| ID | 风险 | 缓解 |
|---|---|---|
| H1 | RWA 叙事被评委当成空气币/证券承诺 | README + 视频开头 5s 声明：demo registry，非法币证券产品 |
| H2 | 做成纯工具，AI-RWA 名不副实 | 默认模板强制 RWA 字段；PDF/发票抽取必须出现在 demo |
| H3 | 做成纯 DApp，ProofForge 可替换 | 每次 demo 必跑 check/proof 失败路径 |
| H4 | 子集不够表达份额守恒 | 收窄状态；用 issued/balance 双变量 + 少量 holder |
| H5 | 证明悬崖拖垮日程 | 证明只演示族内；stretch 单独标记 |
| H6 | 资格条款（X 账号/表单） | D1 建号；提交前 24–48h 发主帖 |
| H7 | 孪生源文件被质疑 | 文档诚实 + 可选一致性脚本 |
| H8 | Launch 诱惑导致洗量 | 书面禁止；不把交易量写进成功标准 |
| H9 | 中途想「先接 powdr/EVMYulLean 再做产品」 | **拒绝 scope**；见 §7.4；最多 1 人日桌面调研写回 research 文 |

---

## 10. 成功标准

### 10.1 开发完成（可提交）

- [ ] X Layer **testnet** 上有可交互 RWA 份额合约地址  
- [ ] AI 路径至少一次 **从 NL 或文档字段** 产出可 check 的源（允许模板锚定）  
- [ ] 正路径 issue/transfer + 至少两条链上负路径  
- [ ] 门禁 money shot：check 或 proof **拒绝**坏输入且不产生部署  
- [ ] 90s 视频 + X 帖 @XLayerOfficial + Google 表单  
- [ ] 成熟度措辞审计通过（无 formal/hermetic/bytecode-proven 误称）

### 10.2 评审向加分项

- [ ] 族内 certified 现场可复现  
- [ ] 与 OKX 生态浅集成（Wallet 连 X Layer；可选 security skill 对照一句）  
- [ ] 开源 README 可让第三人 30 分钟复现 testnet 部署  

### 10.3 非目标（不要写进 Done）

- formal TASK 关闭  
- Launch Grant 档位  
- 主网 TVL / 真实 RWA 资产入驻  
- **外部 Yul→EVM 形式化 backend 接入 / dual emit /「字节码已证明」**（§7.4）  

---

## 11. 命名与对外物料

| 用途 | 建议 |
|---|---|
| 产品名 | **ForgeRWA** 或 **ProofForge Ship · RWA**（二选一，提交后勿改） |
| 副标题 | Verified onchain ship for AI-drafted RWA share policies |
| 中文副标题 | AI 起草、机器核验、一键上 X Layer 的 RWA 份额部署台 |
| 标签 | `#AI` `#RWA` `#XLayer` `#Agent` `#VerifiedDeploy` |
| 仓库布局建议 | `examples/rwa-share-v1/` · `scripts/xlayer/` · `docs/demos/xlayer-rwa-walkthrough.md`（实现期再建） |

**一页纸电梯稿：**

1. Agent 与发行人正在把真实资产规则写上链，但 vibe code 太危险。  
2. ForgeRWA 让 AI 写 ProofForge 程序，**不过门禁就不能部署**。  
3. 首发场景：X Layer 上的受限份额登记（AI-RWA）。  
4. 演示：生成 → certified/check → 测试网 → 超限 revert → 坏证明被拒。  

---

## 12. 决策记录（请产品方确认）

实现开工前建议显式勾选：

| # | 决策 | 默认建议 |
|---|---|---|
| D1 | 产品暂定名 | ForgeRWA |
| D2 | 赛期是否包含 inline proof 演示 | **是**（族内）；失败则仅 check |
| D3 | 是否做 PDF/发票抽取 | **是**（弱 AI 也要有） |
| D4 | 是否追 Liquidity 文案 | **是**；不保证奖 |
| D5 | 是否追 Launch 量 | **否** |
| D6 | 部署文件是否允许无 invariant 孪生 | 按 EVM 现货能力；若必须孪生则文档化 |
| D7 | UI 形态 | 优先脚本+最小 Web；有余力再 Studio |
| D8 | 赛期是否接入外部 Yul→EVM / EVM 形式语义 backend | **否**（已拍板，§7.4）；赛后 D4 再评估 |
| D9 | 赛期是否允许 1 人日桌面调研写回 research | **是**（可选，不阻塞 P0） |

---

## 13. 相关文档

| 文档 | 关系 |
|---|---|
| [`research/2026-08-10-xlayer-hackathon-proofforge/final.md`](../research/2026-08-10-xlayer-hackathon-proofforge/final.md) | 可行性、证明悬崖、11 天旧计划（护栏向） |
| [`research/2026-08-11-yul-evm-formal-backends.md`](../research/2026-08-11-yul-evm-formal-backends.md) | **外部 Yul/EVM formal backend 候选登记；赛期不接入边界** |
| [`product/13-xlayer-onchainos.md`](../product/13-xlayer-onchainos.md) | 网络、OnchainOS、密钥边界 |
| [`product/08-evm-dapp-frontend.md`](../product/08-evm-dapp-frontend.md) | 前端模板 |
| [`adr/0027-...`](../adr/0027-inline-same-file-theorem-certification.md) | proof gate |
| [`plan/verified-contract-authoring.md`](verified-contract-authoring.md) | 长期作者/证明体验（赛后） |
| [`adr/0036-...`](../adr/0036-engineering-scope-and-evm-formal-lighthouse.md) | 工程范围与 EVM lighthouse；勿用黑客松代签 formal |

---

## 14. 下一步（文档之后）

1. **确认第 12 节决策表**（尤其 D1/D2/D5；**D8 已否**）。  
2. 开分支：手写 `RwaShareRegistry` golden + Anvil/X Layer spike（P0）。  
3. 把调研 `/tmp` vault 实验 **移植为** `rwa-share-v1` 模板（策略层复用）。  
4. 补 `docs/demos/xlayer-rwa-walkthrough.md`（与实现同步，不提前空写）。  
5. 不改 accepted PRD；本 plan 保持 `draft` / `normative: false`。  
6. **不**开 Yul-c / EVMYulLean 产品集成分支；若做桌面调研，只更新 [`2026-08-11-yul-evm-formal-backends.md`](../research/2026-08-11-yul-evm-formal-backends.md) 附录。

---

*本文是 A（Verified Ship）与 C（AI-RWA）的合体规划权威草稿；与调研 final 冲突时，**产品竖切以本文为准**，**编译器能力边界以仓库代码与 final 实测为准**；**外部 Yul/EVM formal backend 边界以本文 §7.4 与 research 登记文为准**。*
