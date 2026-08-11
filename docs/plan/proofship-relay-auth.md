---
id: PLAN-PROOFSHIP-RELAY-AUTH
title: ProofShip Cloud — relay (local engine ⇄ Web App) + auth design
status: draft
owner: product+engineering
updated: 2026-08-11
normative: false
---

# ProofShip Cloud · 中继与登录设计（P2 输入）

> **关系**：[`proofship-cloud.md`](proofship-cloud.md) 的子设计；实现前另开 ADR。
> **形制来源**：comet（MIT）已验证的「本地 engine ⇄ CF Durable Objects 中继 ⇄ 任意端 UI」
> 拓扑（见其 ARCHITECTURE.md）。我们裁剪为 gate-first 产品面：**本地 bridge 是唯一写者 +
> 唯一门禁执行者**；Web App 主要是观察者 + 指令入口。
> **纪律不变**：中继/云端永不持有链上私钥与 LLM 明文凭据；门禁权威只在 engine 本机进程。

## 1. 为什么需要中继（用户场景钉死）

| 场景 | 没有中继 | 有中继 |
|---|---|---|
| 用户本机跑 agent+gate，想在手机/另一台机器看进度 | 做不到 | ✅ Web App 实时同步 |
| 给客户/评审发一个「可点的」会话链接 | 只能录屏 | ✅ 只读分享链接 |
| 本地 gate 跑完后从网页一键部署 | 要回到本机终端 | ✅ Web 触发，本机执行（或钱包页签） |
| 关电脑后会话断了 | 状态丢 | ✅ DO 持久化，回来接着看 |

**一句话**：本地 bridge（engine）长连到云端 Room；Web App 连同一个 Room；
Durable Object 是中继 + 持久化，不做计算。

## 2. 拓扑

```text
 本机（用户设备）                    Cloudflare                      任意浏览器
┌──────────────────┐   WSS（出站，无公网入口）  ┌───────────────────────┐   WSS   ┌────────────┐
│ studio-bridge     │ ────────────────────────► │ SessionRoom DO        │ ◄────── │ Web App    │
│  · agent lanes    │   事件流（draft/gate/…）   │  （每次 launch 一个）   │  读/指令 │ (Pages)    │
│  · proof-forge    │ ◄──────────────────────── │  · 事件日志（持久）     │ ──────► │            │
│    gate（权威）    │   指令（新 prompt/重试）   │  · 指令队列             │        └────────────┘
└──────────────────┘                            └──────────┬────────────┘
        │                                                  │
        │ device 注册/心跳                          ┌──────▼────────────┐
        └──────────────────────────────────────────►│ DeviceRoom DO      │
                                                    │ （每台 bridge 一个）│
                                                    └──────┬────────────┘
                                            D1（accounts/projects/launches）
                                            R2（制品/gate 报告/快照）
```

要点：bridge **出站**连接（用户无公网 IP / NAT 也能用）；DO hibernation 省电；
Web App 与 bridge 不直连，全部经 Room。

## 3. 协议（最小事件模型）

不做 CRDT（我们单写者），用**追加事件日志 + 服务端物化**：

| 方向 | 消息 | 说明 |
|---|---|---|
| engine→Room | `session.open {launchId, fields, agentLane}` | 开始一次 launch |
| engine→Room | `draft.ready {program, source, lane}` | 草案（含模板/agent 来源标注） |
| engine→Room | `gate.start` / `gate.done {ok, stage, digests, diag?}` | 门禁过程与 verdict |
| engine→Room | `artifact.sealed {outputSetDigest, files[]}` | 制品封存 |
| Room→engine | `cmd.prompt {nl, lane?}` | Web 端发新需求 |
| Room→engine | `cmd.cancel` | 取消当前运行 |
| 任意 | `presence {who}` | 在线状态 |

- 每条事件带单调 `seq`；Room 落盘（DO storage），断线重连用 `since=seq` 补漏。
- Web 端初始同步 = 物化后的最新状态 + 尾部事件。
- 大 payload（源码/报告正文）放 R2，事件里只带 digest + URL。

## 4. 存储分工

| 存储 | 放什么 | 理由 |
|---|---|---|
| **SessionRoom DO** | 会话事件日志、指令队列、在线状态 | 低延迟中继 + 会话级持久 |
| **DeviceRoom DO** | 设备在线、bridge 能力（lanes/版本） | 路由与 presence |
| **D1** | accounts / identities / projects / launches / deployments 索引 | 关系查询（我的项目列表等） |
| **R2** | 制品包、gate-report、源码快照、分享页快照 | 大对象 + digest 寻址 |

## 5. 登录设计

### 5.1 三方 OAuth（Google / X / GitHub）

| 项 | 选择 |
|---|---|
| 库 | **arctic**（oslo 系 OAuth 客户端，Workers 原生、零服务器依赖） |
| 流程 | `GET /auth/{google,x,github}/start`（PKCE+state 存 DO/D1）→ provider → `/auth/{p}/callback` → 建/找 account → session |
| 会话 | HttpOnly Secure Cookie（opaque session id，D1 表，30d 滑动）；API 也可 Bearer |
| 账号模型 | `accounts(id, created_at)` + `identities(account_id, provider, provider_sub, handle, …)` —— **一人多身份可绑定** |

### 5.2 钱包登录（SIWE / EIP-4361）

| 步 | 端点 | 说明 |
|---|---|---|
| 1 | `GET /auth/wallet/nonce?address=0x…` | 签发一次性 nonce（DO/D1，5min TTL） |
| 2 | 前端 | 钱包 `personal_sign` SIWE 消息（domain=proofship，chainId=1952） |
| 3 | `POST /auth/wallet/verify` | Workers 侧 viem `verifySiweMessage` → session |

- OKX Wallet / MetaMask 均支持 personal_sign；**钱包登录 = 身份，不等于托管**：
  服务端只验证签名，永不触私钥；部署交易仍浏览器内钱包签。
- 钱包地址作为一种 identity 可挂到既有 account（与 OAuth 并存）。
- 后续多链钱包（Solana SIWS 等）同模型扩展；赛期只做 EVM/X Layer。

### 5.3 bridge 的设备凭据

- 用户在 Web 登录后生成 **device token**（一次性展示，`pfs_dev_…`，D1 存 hash）；
  bridge 启动 `npm run bridge -- --link pfs_dev_…` 或 env `PROOFSHIP_DEVICE_TOKEN`。
- token 可吊销；scope 限定「写自己的 SessionRoom」。

## 6. 安全边界（写进 ADR 的硬条款）

1. Room 只中继：不执行代码、不碰门禁；gate 输出以 **digest 自证**（Web 端可对照 display）。
2. 链上私钥、LLM API key 永不进 Room/Workers；agent 凭据只在本机（未来云端走 outbound-proxy）。
3. 分享链接默认**只读**、可过期、可吊销；写操作必须登录且拥有该 launch。
4. bridge 出站 WSS 用 device token 鉴权；Room 按 token 的 account 做隔离。
5. 全部事件不存 LLM 明文 key、不存用户钱包私钥的任何材料。

## 7. 分阶段

| Phase | 内容 | 验收 |
|---|---|---|
| **R0 spike** | bridge `--link` + 单个 SessionRoom DO + Web 只读同步 | 本机 gate 进度实时出现在 Pages |
| **R1** | 指令面（cmd.prompt/cancel）+ device token 签发 | 网页发需求，本机执行回显 |
| **R2** | OAuth 三方登录 + 账号/项目列表（D1） | 登录态闭环 |
| **R3** | SIWE 钱包登录 + 身份绑定 + 分享链接 | 完整账号面 |

与 cloud.md 的 C 阶段关系：**R0–R1 ≈ C1 的通信层**；R2–R3 ≈ C2 的账号面。
赛期不做（08-21 前）；Spike 可在赛后第一周。

## 8. 与 comet 的关系（诚实记录）

- 借鉴：DeviceRoom/SessionRoom 拓扑、DO 中继、命令账本思路（见其公开架构文档）。
- 不照搬：他们用 Loro CRDT（多写者通用编辑）；我们单写者，事件日志更简单。
- 不集成：comet 是通用 coding 会话控制面；我们是 gate-first 产品面，协议面自建更薄。
- 若未来要「多设备多写者协作编辑同一份草案」，再评估 Loro 或直接用 comet 引擎。

## 9. 相关

- [`proofship-cloud.md`](proofship-cloud.md)（C 阶段与 Lean 上云风险）
- [`../product/proofship-positioning.md`](../product/proofship-positioning.md)（阶段纪律）
- [`../research/2026-08-11-code-agent-landscape.md`](../research/2026-08-11-code-agent-landscape.md)（agent lane 协议面）
