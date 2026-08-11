---
id: PLAN-PROOFSHIP-CLOUD
title: ProofShip Cloud — managed agent gate & hosting (P2/P3 design)
status: draft
owner: product+engineering
updated: 2026-08-11
normative: false
---

# ProofShip Cloud（P2/P3 设计稿）

> **关系**：本文是 [`product/proofship-positioning.md`](../product/proofship-positioning.md) §4 阶段表
> 中 **P2（Managed build lane）/ P3（Multi-tenant SaaS）** 的设计展开。
> 按演进纪律，进入 P2/P3 实现前须另开 **ADR**；本文是 ADR 的输入，不是实现许可。
> **赛期（至 2026-08-21）不做**：黑客松交付继续走 P0/P1.5（local-first + Pages 壳）。
>
> 事实基线（2026-08-11 核实）：**Cloudflare Containers 与 Sandbox SDK 已 GA（2026-04-13）**，
> Workers Paid 可用；scale-to-zero、active-CPU 计费、快照、preview URL、
> **outbound-proxy 凭据注入**（agent 看不到明文密钥）均为官方能力。

## 0. 愿景复述（用户拍板版）

| # | 设想 | 设计映射 |
|---|---|---|
| 1 | 云端 Agent 运行环境；默认内置一个 **Pi Agent**；对接我们默认 MCP | Sandbox/Container 会话 + 默认 agent 镜像 + MCP 挂接 |
| 2 | 一句话需求 → 生成合约 → **验证** → 生成前端 → 一键部署 | 云端 gate（真实 proof-forge-next）+ 模板化前端 + Pages 部署 API |
| 3 | 我们持有一级域名，用户项目挂二级域名托管 | Pages 项目 + wildcard 子域（`*.proofship.app` 之类，域名待定） |
| 4 | 多租户注册登录；更多 Code Agent；**绑定用户自己的订阅账号** | 账号体系 + agent picker + 凭据注入（见 §3 校正） |

模型默认：最便宜的 **DeepSeek** 级模型（平台 API key，成本计入配额/计费）。

## 1. 总体架构

```text
                用户浏览器
                    │
   ┌────────────────┼─────────────────────────────┐
   │                │                             │
   ▼                ▼                             ▼
Pages 壳      Workers API（控制面）           用户钱包（签名唯一持有方）
（静态 UI）   ├─ 会话/项目/配额（DO + D1）          │
              ├─ Sandbox 会话编排                 │ sign deploy tx
              │   ├─ agent 进程（Pi / BYO）       │
              │   ├─ proof-forge-next gate ◄──────┼── 唯一门禁权威
              │   └─ 前端模板渲染                 │
              ├─ R2：制品/gate 报告/项目快照       │
              └─ Pages API：项目站点部署           ▼
                                        X Layer / 目标链
```

| 层 | 选型 | 说明 |
|---|---|---|
| 壳 | Pages（现有 proofship.pages.dev 演进） | 已上线 |
| 控制面 | Workers + Durable Objects + D1 | 会话/项目/配额状态机 |
| 执行面 | **Sandbox SDK**（Containers） | 每用户会话一个隔离沙箱：agent + gate |
| 制品 | R2 | build 产物、gate-report、快照 |
| 站点托管 | Pages per-project + wildcard 子域 | 用户项目自动部署 |
| 链上写 | **用户钱包签名**（浏览器） | 平台默认**永不**代持链上私钥（见 §4） |

## 2. 默认 Agent（Pi）与 MCP

- **Pi Agent** = 平台默认 agent 进程（命名待定），容器内启动即挂：
  - 我们的远程 MCP（docs/catalog/networks — 现有 Workers MCP）
  - 本地 gate（同沙箱内 `proof-forge-next`，不经网络）
  - 可选 OnchainOS MCP（用户自己的 `OK-ACCESS-KEY`，凭据注入）
- Agent 协议面 = **MCP 优先**，与 positioning §3.5 的 agent-agnostic 原则一致：
  Pi 是默认船员，不是唯一船员。

## 3. 关键校正（写进 ADR 前必须接受）

### 3.1 「绑定用户自己的订阅账号」的正确形态

消费者订阅（ChatGPT/Grok 订阅）**不是 API 额度**，不能直接当 API key 用。
真实可行的三档（按实现成本排序）：

| 档 | 形态 | 先例 | 注意 |
|---|---|---|---|
| **BYOK** | 用户填自己的 API key（DeepSeek/OpenAI/xAI…） | 普遍 | 经 outbound-proxy 注入，agent 进程不见明文 |
| **订阅 OAuth 的 agent CLI** | 容器内跑用户登录态的 Claude Code / Codex 等 CLI | Claude Pro/Max、ChatGPT 账号登录 CLI | 受各厂商 ToS 约束；token 存储与隔离是安全设计点 |
| **平台默认模型** | 我们付 DeepSeek API，按配额/计费摊销 | — | 需要用量上限与防滥用 |

### 3.2 一键部署 ≠ 平台代签

- 合约部署：**浏览器钱包签名**（一次点击仍是"一键"）；平台只构造未签名交易。
- 若未来做"平台代付 gas / 代部署"，那是 **custody 产品决策**，单独 ADR，默认不开。
- 前端站点部署走 Pages API（这是纯静态托管，无密钥问题）。

### 3.3 Lean 门禁上云的最大技术风险

`proof-forge-next` + locked toolchain 是重资产：

| 风险 | 量级 | 缓解 |
|---|---|---|
| 镜像体积 | 预估 GB 级（CLI + olean + solc） | C0 spike 实测最小镜像（去 Tests/去 runtime-tests） |
| 冷启动 | 秒~十秒级 | 沙箱保活 + 会话复用；gate 结果异步推送 |
| 单次 gate 时长 | 暖机 ~10–30s（实测 golden 20s） | 异步任务 + 进度事件；不做同步 HTTP 等待 |
| 并发成本 | active-CPU 计费 | scale-to-zero + 配额 + 队列 |

### 3.4 滥用面

多租户 + 免费算力 = 挖矿/滥用目标。C2 起必须有：配额、速率限制、
沙箱 egress 白名单（默认只放 MCP/RPC 域名）、会话时长上限。

## 4. 不可破的纪律（跨阶段沿用）

1. **门禁权威**：`proof-forge-next` 产品链是唯一 gate；云端/本地同一二进制与 digest 口径。
2. **密钥**：链上私钥不出用户侧；LLM/agent 凭据走 outbound-proxy 注入。
3. **诚实**：云端过 gate ≠ formal/字节码已证；话术沿用 positioning §5。
4. **fail closed**：gate 不过 → 不生成部署物、不建站点。

## 5. 分阶段（与 positioning §4 对齐）

| Phase | 内容 | 验收 | 对应 |
|---|---|---|---|
| **C0 spike** | 最小容器镜像跑通 `check+build+inspect`；记录镜像大小/冷启动/单次时长 | 技术可行性报告（写回本文） | P2 预研 |
| **C1** | 单租户托管 gate：Workers API + Sandbox + 现有 Studio 接上（无账号） | 线上一句话→gate→制品下载 | P2 |
| **C2** | 账号/项目/配额 + 项目站点（wildcard 子域）+ 前端自动生成部署 | 多用户隔离实测 | P3 |
| **C3** | agent picker / BYOK / 订阅-OAuth CLI / 计费 | ADR 评审 | P3+ |

**赛期边界**：08-21 前最多做 C0 spike（且不阻塞交付）；C1+ 一律赛后。
黑客松叙事可以讲「cloud roadmap 已完成技术验证（C0）」，**不**讲「已是 SaaS」。

## 6. 待决问题（ADR 输入）

1. 一级域名选什么（proofship.app / ship.proofforge.* ？）与 wildcard 证书策略。
2. 默认模型供应商与配额/定价模型。
3. Pi Agent 的实现栈（自研 loop vs 包装开源 agent CLI）。
4. 账号体系选型（Clerk / WorkOS / Auth.js / CF 原生 D1+WebAuthn）。
5. 容器镜像的供应链纪律（SBOM、Tool Lock 与云端 runner 的关系）。

## 7. 相关

| 文档 | 关系 |
|---|---|
| [`proofship-relay-auth.md`](proofship-relay-auth.md) | **中继（本地 engine ⇄ Web App）+ 登录（OAuth×3 + SIWE 钱包）设计** |
| [`product/proofship-positioning.md`](../product/proofship-positioning.md) | 阶段纪律（P0–P3）与 agent-agnostic 原则 |
| [`plan/ai-rwa-verified-ship-xlayer.md`](ai-rwa-verified-ship-xlayer.md) | 赛期竖切（唯一在做的产品面） |
| [`plan/proofship-execution.md`](proofship-execution.md) | 赛期执行清单 |
