---
id: PRODUCT-PROOFSHIP-POSITIONING
title: ProofShip product positioning and brand hierarchy
status: draft
owner: product
updated: 2026-08-11
normative: false
---

# ProofShip — 定位与品牌层级

> **性质**：黑客松/赛期产品定位卡（`normative: false`）。  
> **不**改写 accepted PRD / Architecture / Technical Spec；**不**关闭 formal TASK；  
> **不**声称 hermetic / Stage-0 / 链上字节码已形式证明。  
> 竖切规划：[`docs/plan/ai-rwa-verified-ship-xlayer.md`](../plan/ai-rwa-verified-ship-xlayer.md)。

## 1. 定稿命名

| 层级 | 名称 | 角色 |
|---|---|---|
| **产品主品牌** | **ProofShip** | 提交表单 Project Name；X / 产品面 / 对外主语 |
| **首发 vertical（副叙事）** | **AI-RWA** | 赛道文案、Liquidity Grant 对齐、默认业务故事 |
| **默认业务模板** | `rwa-share-v1` | 工程模块 id（份额登记 + 转让策略） |
| **平台脊骨** | Verified Ship spine | NL/模板 → check/proof → EVM → X Layer deploy |
| **编译与门禁引擎** | **ProofForge** | *Powered by ProofForge*；CLI `proof-forge-next`；**不当** Project Name |
| **弃用名** | ForgeRWA · ProofForge RWA · ProofGuard（对外） | 历史调研/暂定名，不再作主名 |

**Tagline**

> AI drafts the rules. The gate checks. Then it ships to X Layer.

**一句话（EN）**

> ProofShip is a verified ship workspace for AI-drafted onchain programs. First vertical: AI-RWA share registry with transfer policy on X Layer.

**一句话（中文）**

> ProofShip：AI 起草链上规则程序的可验证上线工作台；首发场景 AI-RWA 受限份额登记与转让，经 ProofForge 机器门禁后部署到 X Layer。

## 2. 品牌层级（组件关系）

```text
ProofShip                          ← 唯一产品主名
├── Spine: Verified Ship           ← 生成 → 门禁 → 部署（差异化）
├── Verticals
│   └── AI-RWA                     ← 副叙事 / 首发场景（不是第二产品）
│       └── template rwa-share-v1  ← 工程组件
│       └── (future templates…)
├── Surfaces
│   ├── Studio (Web)               ← 可选壳：对话 UI / 日志 / 部署入口
│   ├── Code Agents (pluggable)    ← Grok Build / Claude / Cursor / Codex / … via MCP
│   ├── Deploy lane                ← 本机 key → X Layer（P0）；日后受控 runner
│   └── dApp UI                    ← claim / transfer / view
└── Engine: ProofForge             ← 编译 + check + optional proof gate（门禁 sole authority）
```

| 说法 | 对 / 错 |
|---|---|
| AI-RWA 是 ProofShip **旗下** 的 vertical / 组件叙事 | ✅ |
| `rwa-share-v1`、Studio、Deploy、dApp 是旗下 **组件** | ✅ |
| ProofForge 是引擎，Powered-by | ✅ |
| Code Agent **可插拔**；Grok Build 是首个适配，不是唯一 | ✅ |
| ProofShip 与 AI-RWA 是两个并列产品 | ❌ |
| 产品主名 = ProofForge RWA / ForgeRWA | ❌ |
| 我们是 Pump.fun 式 meme launchpad | ❌ |
| ProofShip = 绑定某一家 Code Agent 的插件 | ❌ |

## 3. 产品定位

| 要素 | 内容 |
|---|---|
| **Category** | AI application · verified contract ship workspace |
| **Who** | Issuer / AI agent；次要 Holder（dApp） |
| **Job** | 把业务规则变成可部署程序，且坏规则上不了链 |
| **How** | 对话/模板 → ProgramV1 → check/proof gate → EVM build → X Layer |
| **Why us** | 门禁是构建产物（fail closed），不是事后审计 PDF；AI 不能绕过 gate |
| **Metaphor** | Vercel for onchain programs（Verified Ship） |
| **Not** | Meme launchpad · 纯编译器产品 · 证券发行/全合规平台 · Web3 Cloudflare |

**价值主张**

```text
AI 可写合约
  + 机器门禁（不过则零部署制品）
  + 一键到 X Layer（赛期 testnet）
  = 敢让 AI 参与上链，是因为写了也未必能 ship
```

## 3.5 Agent-agnostic · Universal Ship（已拍板方向）

**判断（同意并定稿）：** 现有 **MCP + 任一代码 Agent + Web 面** 已足够支撑完整的 P0 产品面；  
长期若要做成面向 Web3 的 **Universal Ship**，必须把 **Code Agent 当可插拔运行时**，  
**不**把产品锁死在 Grok Build（或任何单一厂商）上。

### 分工（稳定中心 vs 可换边缘）

```text
        ┌──────────────────────────────────────────┐
        │  Code Agents（可换）                        │
        │  Grok Build · Claude · Cursor · Codex · … │
        │  用户自选；赛期可用其中任一已接通者     │
        └──────────────────┬───────────────────────┘
                           │ MCP（工具协议 · 文档/目录/引导）
                           │ + 本机/受控 runner 上的 check/build
        ┌──────────────────▼───────────────────────┐
        │  ProofShip 不变脊骨                        │
        │  模板 vertical · 门禁语义 · 部署纪律        │
        │  Engine = ProofForge（sole gate）          │
        └──────────────────┬───────────────────────┘
                           ▼
                      X Layer / 多链 targets
```

| 层 | 角色 | 可换？ |
|---|---|---|
| **Code Agent** | NL 理解、写/修 program、多轮修诊断 | **可换**（产品应支持多选） |
| **MCP 工具面** | 稳定契约：docs、networks、catalog、agent instructions… | **协议稳定**；实现可演进 |
| **ProofForge gate** | check / proof / materialize — 谁写的源码都一视同仁 | **不可换**（差异化） |
| **Deploy / 钱包** | 上链与持有 | 通道可多，**钥不进远程 MCP** |
| **Web Studio** | 展示与编排壳；可帮用户「选 Agent / 看日志」 | 壳可换；不是门禁 |

### 为何这是对的

1. **你已经验证路径**：MCP 挂到 Grok Build + Web 能跑通 → 证明瓶颈不在「再写一个专用 IDE」，而在 **协议 + 门禁 + 竖切模板**。  
2. **Agent 市场会碎**：用户粘在 Claude / Cursor / Codex / Grok 等不同壳上；绑死一家 = 自我限流。  
3. **Universal Ship 的「Universal」**：应对 **多 Agent × 多模板 vertical × 多链 target**；不是「我们自研第 N 个 chat UI」。  
4. **差异化不在 Agent**，在 **过 gate 才能 ship**——任意 Agent 写坏规则，一样 fail closed。

### 实现纪律

| 做 | 不做 |
|---|---|
| MCP 工具与 prompt 对 **任意 MCP 客户端** 可读 | 工具参数/文案写死「仅 Grok」 |
| 产品面写清「示例 Agent：Grok Build」 | 对外声称 ProofShip 只能用 Grok |
| 赛期优先 **stdio + 远程 docs MCP** 双挂（与 OnchainOS 同模式） | 为单一 Agent 分叉第二套产品语义 |
| P3 规划「用户选择 / 自带 Agent endpoint」 | 把 LLM 厂商密钥当成 ProofShip 核心 IP |
| 垂直模板（AI-RWA）与 Agent 解耦 | 模板逻辑写进某一家 Agent 私有插件格式 |

### 与阶段对应

| Phase | Agent 策略 |
|---|---|
| **P0** | **任意已接 MCP 的 Agent 均可**；Grok Build 为官方参考路径之一 |
| **P1.5（已落地）** | Studio bridge 三条 lane：**内置模板渲染**（离线兜底）/ **本地 agent**（默认 `codex exec` headless；ACP 适配器如 `claude-code-acp` 经 `PROOFSHIP_AGENT_CMD` 切换）/ 后续云端 agent（C1+）。Studio 发送即起草 → 同机 gate 立即裁决 |
| **P1** | Studio 文档化多 Agent 接入步骤；不强制内嵌单一模型 |
| **P2** | 编排层调用「用户指定的 agent 会话」+ 固定 runner 上的 gate |
| **P3** | **Agent picker / BYO agent**：云端部署流里用户自选 Code Agent；平台不垄断推理 |

> 2026-08-11 实测：bridge agent lane 注册表（`GET /api/agent/lanes`）+ `POST /api/agent/draft`：
> **codex（exec）与 omp-acp（原生 ACP）全链路验证**（NL → 合约源 → 同机 gate 绿）；
> grok / claude-acp 待用户重登 CLI 凭据；gemini-acp 协议可握手但 Google 个人版已停服。
> ACP 族（omp 原生、claude 适配器）与 exec 族（codex/grok/pi/omp -p）同一 driver 接口，
> 云端 lane（C1+）复用同一契约。

**一句话：**

> ProofShip is the ship desk and the gate; Code Agents are interchangeable crews. MCP is the gangway.

## 4. 交付形态演进（已拍板 · 分阶段）

**原则：** 同一条产品脊骨（AI 起草 → 机器门禁 → 部署），**先本地 hybrid，再渐进云化**；  
**Code Agent 全程可插拔**（§3.5）。  
不在赛期一步做成多租户全托管；后期 SaaS **不得**削弱 fail-closed 门禁或把部署私钥默认为平台代持。

| Phase | 名称 | 形态 | 编译/proof | 部署钥 | Code Agent | 目标 |
|---|---|---|---|---|---|---|
| **P0** | **Local-first hybrid**（**当前 / 赛期**） | 本机 CLI + MCP + 最小 Web/dApp | **本机** `proof-forge-next` | **本机** env / 用户钱包 | **任选**（本 build 以 Grok Build 为参考） | 可跑通闭环；密钥与门禁可信 |
| **P1** | Hosted surface | Cloudflare Pages 等托管 Studio；远程 docs MCP | 仍本机（或开发者自建 runner） | 仍本机 / 钱包 | 多 Agent 接入文档；可选 LLM API | 分享链接、评审打开 UI |
| **P2** | Managed build lane | 可选 **单租户/受控** 远程 build 队列 | 平台 runner（隔离、可审计日志） | 仍 **不**默认代持；签名在用户侧 | 编排层对接用户指定 Agent | 降低安装门槛 |
| **P3** | Multi-tenant SaaS | 账号 · 项目 · 配额 · 计费 | 多租户 runner + 制品存储 | 显式 custody 产品决策（默认仍用户签名） | **Agent picker / BYO** | Universal Ship 规模化 |

> P2/P3 设计稿（Cloudflare Containers/Sandbox GA 后的落地形态）：
> [`plan/proofship-cloud.md`](../plan/proofship-cloud.md)。实现前须另开 ADR。

```text
P0 Local-first  ──►  P1 Hosted UI  ──►  P2 Managed build  ──►  P3 Multi-tenant SaaS
   ▲ 赛期只承诺这里
   │
   └── 每阶段只加「托管面」，不重写门禁语义
```

### P0（赛期）固定架构

```text
[可选 Web Studio / dApp]     [AI Agent 或 LLM API]
           │                         │
           └──────────┬──────────────┘
                      ▼
            本机 ProofForge CLI（check / proof / build）
                      │
                      ▼
            本机 deploy（cast）→ X Layer
            用户钱包 → dApp 交互
```

| P0 做 | P0 不做 |
|---|---|
| 本机 check/build + fail-closed | 公有多租户远程 Lean 编译 |
| 本机/钱包签名部署 | 远程 MCP 持有部署私钥 |
| 最小 Web 或脚本面 | 完整账号/计费/SaaS 控制台 |
| AI 在关键路径（生成/修源） | 声称已是全托管云产品 |

### 演进纪律（跨阶段不变）

1. **门禁权威**永远是 ProofForge 产品链；UI/SaaS 只是壳。  
2. **Code Agent 可插拔**；Grok Build / Claude / 其他均为适配，**不是**产品本体（§3.5）。  
3. **远程文档 MCP**（现有 Cloudflare Workers）可以一直存在；**不等于**远程 compile。  
4. 进入 P2/P3 前须另开 ADR：runner 隔离、制品保管、密钥模型、多租户威胁模型、Agent BYO 信任边界。  
5. 对外表述：赛期说 *local-first verified ship desk · agent-agnostic via MCP*；可提 *roadmap to managed SaaS + agent picker*，**不**把路线图说成已交付。

## 5. 诚实边界（对外必守）

| 可以说 | 不可以说 |
|---|---|
| machine-checked gate before deploy | full formal verification of bytecode |
| same-file Lean theorem certification（engineering） | Stage-0 / hermetic / release evidence |
| 坏规则/坏证明 → fail closed、零制品 | 任意 NL 规格自动证明 |
| onchain share registry with transfer policy | 真实法域托管完成 / 法律强制力 |
| AI-RWA **oriented** first vertical | 完整证券合规产品 |
| local-first now; managed SaaS on roadmap | 已是多租户全托管编译云 |
| agent-agnostic (MCP); ships with Grok Build | ProofShip 绑定唯一 Code Agent 厂商 |

## 6. 提交表单用词

| 字段 | 建议 |
|---|---|
| Project Name | **ProofShip** |
| Description 首句 | ProofShip — AI drafts share rules; ProofForge gate; ship to X Layer. AI-RWA first vertical. |
| Keywords | `ProofShip` · `AI-RWA` · `share registry` · `X Layer` · `verified deploy` · `agent` |
| X 帖 | @XLayerOfficial · 产品名 **ProofShip** · 可带 AI-RWA |
| 形态诚实句 | Local-first ship desk (CLI + MCP agents + web); multi-agent SaaS is roadmap, not the hackathon claim. |
| Agent 诚实句 | Works with MCP-compatible code agents (e.g. Grok Build); the gate is ProofForge, not the chat UI. |

## 7. 相关

| 文档 | 关系 |
|---|---|
| [`plan/ai-rwa-verified-ship-xlayer.md`](../plan/ai-rwa-verified-ship-xlayer.md) | A×C 竖切实施规划 |
| [`research/2026-08-10-xlayer-hackathon-proofforge/handoff.md`](../research/2026-08-10-xlayer-hackathon-proofforge/handoff.md) | 调研交接 |
| [`product/13-xlayer-onchainos.md`](13-xlayer-onchainos.md) | 网络 / OnchainOS / 密钥 |
| [`adr/0027-inline-same-file-theorem-certification.md`](../adr/0027-inline-same-file-theorem-certification.md) | proof gate 工程基线 |
| [`clients/pf-mcp/README.md`](../../clients/pf-mcp/README.md) | 远程 MCP 边界（无 compile / 无 key custody） |
