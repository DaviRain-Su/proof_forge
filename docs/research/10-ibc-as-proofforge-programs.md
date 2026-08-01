---
id: RPT-010
title: IBC 作为 ProofForge 程序的可行性研究
status: draft
owner: research
updated: 2026-08-02
normative: false
---

# IBC 作为 ProofForge 程序的可行性研究

状态：`draft`
研究日期：2026-08-02

## 问题

能否用 ProofForge 的统一 `program` 语言把 IBC（Inter-Blockchain Communication）协议
本身实现成合约，再编译部署到每条目标链，从而让没有原生 IBC 支持的链也能跑 IBC？
如果可行，哪些 IBC 模块真正跨链可移植、哪些只能 target-specific，语言与编译器还缺什么？

本文为非规范性研究。结论不能越过已接受的 ADR、PRD、架构和技术规格；其作用是说明
"为什么这条路值得 / 不值得、以及若要走需要补什么"，而不是暗中改变产品语义或目标范围。

## 动机与定位

当前 Phase-1 target（`evm`/`solana`/`near`/`noir`）没有一个原生支持 IBC：
EVM 链无原生 IBC，Solana / NEAR 无原生 IBC（NEAR 走 Rainbow Bridge，另一套），
Noir 是电路无持久状态。Cosmos 链才有原生 IBC，但 `cosmwasm` 为 design-only、未接。
因此"靠链原生 IBC"在当前 target 集上不成立。

用户提出的方向是相反的：**不依赖宿主链原生 IBC，而是把 IBC 协议状态机本身写成
ProofForge 程序，编译成各链合约部署**。这是"在非原生 IBC 链上用合约实现 IBC"路线，
业界有真实对应物（Polymer 的 ibc-eureka、Composable 的 EVM-IBC 等），不是玩具想法。

## 与 ProofForge 模型的契合度

IBC 核心模块本质是状态机：一组状态对象（connection end / channel end /
nextSequenceRecv/Send/Ack），由消息触发状态迁移，带证明验证，失败原子回滚。这恰好是
ProofForge 擅长的语义形态——有状态、带授权、原子迁移、外部调用与回滚（架构
`SPEC-SEM-001` reference semantics + `effect.*`/`context.*`/`authority.*` requirement 域）。
因此概念上比"靠链原生 IBC"契合得多。

但 IBC 不是单个合约，而是一个协议栈（ICS-02 client / ICS-03 connection / ICS-04
channel / ICS-05 packet / ICS-23 proof / ICS-26 routing / transfer app）。把它当作
ProofForge 的第一个大用例，相当于刚验证完 `UInt64 add/sub` 就去盖摩天楼。本文不主张
立即推进，而是把可行性、可移植性边界和前置缺口固定下来，供后续决策。

## IBC 模块可移植性映射

INV-002 要求"target 只能选等价物化，不等价必须拒绝"。IBC 内部并非整块可移植，
需按模块拆分：

| IBC 模块 | 跨链可移植 | 说明 |
|---|---|---|
| Connection handshake (ICS-03) | 是 | 纯状态迁移，语义与宿主链无关 |
| Channel handshake (ICS-04) | 是 | 同上 |
| Packet 序号 / ack / timeout 排序 (ICS-04/05) | 是 | 纯计数器 + 排序逻辑 |
| Routing (ICS-26) | 基本是 | 派发表，少量 target ABI 差异 |
| Transfer app (token 转账) | 是 | burn/mint + 余额表，本质是 fungible token |
| Light client 验证 (ICS-23 Merkle proof + header 校验) | 算法可移植，依赖 counterparty 共识 | 验证的是对方链 header；算法跨链相同，但需要 crypto 原语 |
| Client state / consensus state 存储 | 是 | 宿主链持久状态 |
| Relayer 交互（收 packet、发 ack、timeout） | 部分 | 异步回调 + 对方链高度/时间，依赖 `context.*` |

结论：IBC 中**一大块（状态机 + transfer app）是"写一次、各链物化"的好素材**；
light client 验证是共享硬依赖，crypto 是命脉。

## 与 ProofForge requirement 域的对应

| IBC 需求 | 对应 requirement 域 | 当前状态 |
|---|---|---|
| 持久结构化状态（connection/channel/client state） | `state.*` | state 仍 UInt64-only；aggregates/Map 未进产品 Normalize |
| 收/发包、ack、timeout | `effect.*`（external.call.sync / workflow.schedule） | Wave I call/schedule 已接四个 target |
| 对方链高度/时间（timeout 判定） | `context.*` | deferred |
| Port/Channel owner 权限 | `authority.*` | deferred |
| Packet 转发可见性 | `disclosure.*` | disclosure 已接 CheckV1 |
| 失败原子回滚 | `failure.*` | revert 已接 |
| Crypto（hash/Merkle/签名） | 拟议 `extension.crypto` | 无任何 crypto 原语 |
| 轻客户端验证 | 拟议 `extension.ibc-client` | 不存在 |

## 语言与编译器前置缺口

当前产品路径完全无法表达 IBC。诚实清单：

1. **无 crypto 原语**。IBC 安全性全靠 light client 证明验证——SHA-256、ICS-23 Merkle
   proof、签名验证（Tendermint 用 ed25519，Ethereum 用 secp256k1）。语言里一个 hash
   都没有；`Field` 是 BN254 给 ZK 用的，不是通用哈希。缺这个，IBC security model 直接
   塌掉，只剩状态机空壳。
2. **无 Bytes/String 产品路径**。packet / header / proof 全是 protobuf 字节流。
   `WireV1` 中 `Bytes` shape 有定义（≤4096），但产品 Normalize 不降。存不了一个
   packet payload。
3. **无 aggregates/Map 产品路径**。IBC 状态是结构化的
   `ConnectionEnd{clientId, versions, state, counterparty}`、
   `ChannelEnd{state, ordering, counterparty, hops}`、`Map<PortId, Capability>`。
   Typed 层有检查，产品 compile 仍 fail closed。
4. **无 Principal/account 身份**。port/channel owner 与 transfer 余额表
   `Map<Principal, UInt64>` 需要身份类型。当前 state 仍 UInt64-only。
5. **async/timeout/context requirements 未接**。timeout 依赖对方链高度/时间，
   ack 是异步回调（onRecvPacket / onAcknowledgement / onTimeout）。映射到
   `context.*` / `effect.workflow.schedule`，均 deferred。
6. **Noir 状态连续性 mismatch**。IBC 需跨 packet 持久状态，而架构明确"Noir 无原生
   持续状态，stateContinuity = external"。Noir 上 IBC 持久层需外部 pre/post state
   relation 承载，是额外架构假设。
7. **target capability 差异**。EVM 走 precompile（sha256/ecrecover/ed25519）、
   Solana 走 syscall、NEAR 走 host function、Noir 走 circuit gadget——crypto 原语
   在四 target 上的物化路径完全不同，必须以 `extension.crypto` capability 矩阵
   表达，单 target 缺则 fail closed（同 Noir `status/slot`、NEAR `schedule` 模式）。

## 风险

- **规模风险**：IBC 是多模块协议栈，业界 EVM 实现为数千行。ProofForge 当前产品路径
  仅 `UInt64 add/sub` 四链。直接冲 IBC 易变成长期半成品。
- **生态风险**：IBC adoption 取决于 relayer、对端链支持，不是编译器单方面能推动。
- **论证风险**：若连 Fungible Token 都未在四链跑通，直接上 IBC 会模糊"跨链等价
  物化"核心论点的证明。Token 是验证模型的最小实验，比 IBC 便宜得多。
- **crypto 依赖风险**：light client 验证是 IBC 安全命脉；若 `extension.crypto`
  在某 target 无法物化，该 target 上的 IBC 必须 fail closed，而非降级。

## 建议推进顺序（北极星，非近期任务）

本研究不主张把 IBC 列为近期任务。若后续真要推进，建议顺序：

1. **补语言面**：aggregates + Map + Principal + Bytes/String 进 sole Normalize 产品
   路径（本就是 active task"ContextRead/Commit 与 aggregates"的下一步）。
2. **加 crypto 原语**：至少 SHA-256 + Merkle 验证，作为 `extension.crypto` requirement，
   capability matrix 按 target 物化。独立有价值，是 IBC 命脉。
3. **先证明模型，做 Fungible Token**：用补好的语言写一个 `program Token where`，
   跑通四 target 物化。这是"写一次跨链物化"是否真 work 的最小验证，比 IBC 便宜得多。
   Token 本身也对应 IBC transfer app 的内核。
4. **做一个 IBC-flavored 最小件**：不直接上全套 IBC，先做一个 "packet mailbox"——
   存消息、nonce、timeout、emit 事件给 relayer。一个能跑的 IBC 子集，验证 cross-chain
   message 表达力。
5. **再上真 IBC 模块**：按 connection → channel → packet → transfer app 顺序，
   每层相对独立的状态机，逐层沉淀成公共组件库。light client 验证作为最硬一块最后攻，
   依赖 `extension.crypto` 成熟。

## 结论

- IBC-as-ProofForge-programs 方向**概念上契合**（IBC 状态机正是 ProofForge 语义域），
  且"在非原生 IBC 链上用合约实现 IBC"有真实业界对应物。
- 但**当前语言面完全无法表达**（无 crypto / Bytes / aggregates / Map / Principal /
  async-context），且 IBC 是协议栈而非单合约。
- **可移植性边界**：状态机 + transfer app 可移植；light client 验证算法可移植但依赖
  crypto 与 counterparty 共识；relayer 异步交互依赖 `context.*`。
- **战略定位**：建议把 IBC 作为长期北极星，把 Fungible Token 作为近期试金石。两者
  共享同一批语言前置工作；先跑通 Token 证明"跨链等价物化"模型，再沿同一基础设施爬
  IBC 状态机，最后补 crypto 攻 light client。
- 本文档不改变任何已接受决策、目标范围或任务状态；仅为后续决策提供研究依据。

## 待补充

- 各 ICS 模块的精确状态机规格与 ProofForge callable/block 映射草图。
- `extension.crypto` / `extension.ibc-client` 的 requirement catalog 草案与四 target
  capability 物化路径。
- packet mailbox 最小件的语言表面草案与四 target 物化可行性核对。