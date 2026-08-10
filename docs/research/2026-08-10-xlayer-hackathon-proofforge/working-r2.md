---
id: RPT-XLAYER-W2
title: X Layer 黑客松调研工作文档 Round 2
status: draft
owner: research
updated: 2026-08-10
normative: false
---

# 工作文档（Round 2 增量合并）

日期：2026-08-10。接 working.md（Round 1）。按 verifier GAP 编号组织。

## G2 invariant × EVM 张力（explorer 6，代码级实证）

- FC 位置实证：`LowerSemanticV1.lean:4893-4895`（Plan 入口闸）、`:4956-4958`（.invariant kind 闸）、
  `:4599-4602`（invariantSteps 守卫）。实测：Counter `check` → certified；`build --target evm` →
  `PF-PLAN-INVARIANT` FC；MiniAmm（无 invariant）build EVM 成功。
- **方案 a（打通 EVM invariant lowering）**：关键发现——EVM Plan/IR 已有全部运行时机制
  （`.assert` 语句 + `if iszero(cond) revert` 发射），缺的是把 invariant callable 降成 Expr 的通路。
  最小实现：对 Q0 read-only Bool invariant 复用 view-mode lowering，把 Bool Expr 在每个 entry
  return 前/constructor stores 后 append `.assert`。改动集中在 LowerSemanticV1.lean（~100-200 行）+
  测试（`Tests/Materialization/Targets.lean:232-288` 是 FC 边界对照表）+ Anvil fixture。
  熟手 2-4 天，一人 11 天赛期内属高风险高回报；hashed-Map 默认 profile 刚切换，
  读 Map 的 invariant 应先 FC。
- **方案 b（两步走：check 证证明 + build 部署无 invariant 变体）**：仓库自带先例
  （MiniAmmL1 注释明确 deployable 变体是 MiniAmm.lean），成本 <1 天；弱点是"两层皮"质疑。
- **方案 c（proof gate 拒绝 money shot）**：机制现成、成本 ≈0；
  **风险实测发现：破坏 preservation 后 `by decide` 归约可能 >290s 超时**——演示须选快失败路径
  （删 proof 声明/改 theorem 名/改 inventory）或预录。
- 重要细节：声明 invariant 本身不触发证明义务（MiniAmmL1 实测 proofStatus=not-required），
  要 certified 必须显式写 `proof ... preserving using ...` 绑定。
- 排序：c 保底 → b 补叙事 → a 作 stretch goal。

## G4 MCP 闭环成熟度（explorer 6）

- MCP server（tools/mcp/proof_forge_mcp_server.py，stdlib only，protocol 2024-11-05）暴露 7 工具：
  list_targets/doctor/install/build/artifacts/local/chain_catalog。
- **关键缺口：MCP 无 `pf_check`**（SDK 有 check()，MCP 没有——像遗漏非设计）；
  proof gate 恰是叙事核心。补 `pf_check` + `pf_test`(EVM Anvil) ≈ 1 天纯 Python wrapper。
- 无写文件工具（LLM 用自己的 fs 工具）、无 deploy 工具（刻意设计）。
- deploy gate：safety.rs:66 仅允许 `--network local` broadcast；放宽到 X Layer testnet 需改
  safety.rs/deploy.rs 四处 + 单测；constructor(uint64) 硬编码在 deploy.rs:71/121。

## G3 X Layer 实测部署路径（explorer 7，全部实测）

- 测试网 RPC 在线：chainId 1952、gas 0.02 gwei、出块正常；reth 定制客户端 xlayer/v0.0.7，
  区块头到 Prague；PUSH0/MCOPY/TSTORE 实测可用（Cancun+）；EIP-3860（49152B）实测生效；
  部署 ~56k gas ≈ 0.0000011 OKB。
- 限制：eth_getLogs 区块范围上限 100；部分 RPC 方法白名单化。
- Faucet：每地址每天 0.2 OKB + 滑块验证，无 OKX 账号/主网余额门槛——摩擦低。
- Explorer：仅 OKX 自家；验证只支持 Solidity 源码路线，无 raw bytecode 入口；
  未验证合约正常展示（token 页能读 name/symbol）。
- 本机 foundry（cast/forge/anvil）已装于 ~/.foundry/bin；solc 0.8.34 在。
- G10：主网义务原文 "subsequently launched on the X Layer Mainnet"，无 deadline，
  但 Requirements 头部 "fail to meet any requirement → ineligible to receive prizes"
  使其成为收奖资格条款 [UNVERIFIED 核验方式]。
- Grant 叠加：页面/条款无互斥措辞，三者触发机制正交，文本上不禁止叠加 [无明文 UNVERIFIED]。

## G7 竞争格局 / G8 OKX 工具链 / G6 X 账号 / G11（explorer 8）

- 本届无公开提交平台（仅 Google Form），参赛规模不可观测；Build X Season 1 有 100+ 提交
  （冠军 agent 信用基建，一等奖仅 2k+ 推广资源）。本届 300k 池，估计 100-300 有效提交。
- **关键负面数据点：OKX ETHCC 2025 设了 Security & Privacy Tooling 赛道但该赛道无获奖者**——
  纯安全工具在 OKX 系评审下无成功记录。
- 已观察同生态参赛者方向：agent 市场/x402 支付（agentsmarketplace、xlayer-agent-commons、Amber）；
  **未发现 "AI+合约验证/安全护栏" 同向选手——差异化位是空的**。
- G8：官方 Requirements/FAQ/条款全文未提 OKX.AI/x402/MCP（非明示要求）；但隐含鼓励证据强。
  官方可集成资产：okx/agent-trade-kit（交易 MCP）、okx/onchainos-skills（13 个官方 agent skills，
  含 **okx-security**——token 风险/钓鱼/交易预执行扫描）。接入是高概率隐性加分项；
  okx-security 与 ProofForge 证明门禁是天然互补叙事（"他们检测风险，我们证明不变量"）。
- G6：X 账号义务是**硬性取消资格条件**（Requirements 头部措辞），不是软参考；
  现实执行 = 建独立 handle + 赛期 2-3 条 build-in-public 帖 + 提交帖 @XLayerOfficial。
- FV 先例：KSwap-VM（1inch swap-vm 形式语义，ETHGlobal Lisbon 2026 参展，获奖状态 UNVERIFIED）；
  无 "编译器/FV 工具在 AI 黑客松拿前三" 确证先例。

## G12 卡位叙事加固 / G5 AI 感知路径（explorer 9）

- 反例排查：Safe Guards.spec 只验证 guard 挂载机制（钩子必被调），不验证策略业务不变量；
  Zodiac 生态仅传统审计，且 2026-06 Gnosis Pay 倒在审计过的 Zodiac Delay Module（单一来源，
  需一手确认 [UNVERIFIED]）；Certora/RV 无公开 "agent 支付策略" FV 案例；Aegis 自称
  "mathematically constrains" 但实为工程约束（注意区分 constrain vs prove）；学界（ACM Queue/
  AgentVerify/Symbolic Guardrails）全在验证 agent 决策过程，无人验证链上护栏合约。
- **精确措辞（可直接用）**："在 AI agent 支付护栏品类里，没有任何公开产品把业务安全不变量
  的机器核验证明作为部署前强制门禁"（保持限定，不用全称判断）。
- Certora AI Composer 差异表：规格来源（外部 CVL vs 同文件定理）、循环角色（可人肉放宽需求
  vs fail-closed 无放宽通道）、部署语义（开发期工具/研究原型 vs 部署前置条件）、
  证据归属（会话产物 vs 与源码 hash 绑定）。策略：借 Certora 背书品类，不贬低。
- 评审感知规律：评委约 4 分钟看视频 + 5-8 分钟读 README；README 首屏 = 问题一句话+架构图+
  30 秒最小命令；AI 元素感知手法 = 摘要第一句出现 AI/agent 关键词、demo 有肉眼可见的
  "AI 在决策" 画面、架构图 AI 组件独立色块。
- 60-90 秒视频脚本（7 镜头版）：钩子（Gnosis Pay 事件）→ agent 对话 + 代码逐字流出
  （定理与源码同文件高亮）→ build certified + X Layer testnet 真实部署 → **高潮：坏合约被
  proof gate 拒绝、零制品** → agent 自动修复重试成功 → 对比字幕（工程强制 vs 机器证明）→
  Logo+repo+@XLayerOfficial。
- X 帖子策略：主帖 "AI agents are about to control real money... No valid proof → nothing deploys"
  + 原生视频内嵌 + thread 讲生态贡献；提交前 24-48h 发。
- ENShell 经验：先写 demo 脚本再写代码；砍讲不完的功能；所有交易真实上链预跑数小时。

## 剩余缺口（交 Round 2 verifier）

- G1 候选方向收敛（主代理在 Phase 3 完成，但需要 verifier 先确认素材足够）。
- G9 11 天产能分解（主代理 Phase 3 完成）。
- MiniAmmL1 文档漂移（docs 声称 certified，实测 not-required）——若选用 MiniAmm 作 demo 需注意。
- 负面 proof demo 延迟风险需赛前实测选定快失败路径。
- Gnosis Pay Zodiac 事件需一手来源确认。
- 真实 broadcast 部署未做（无测试币未领 faucet）——执行期第一件事。
