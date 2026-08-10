---
id: RPT-XLAYER-W1
title: X Layer 黑客松调研工作文档 Round 1
status: draft
owner: research
updated: 2026-08-10
normative: false
---

# 工作文档（Round 1 合并）

日期：2026-08-10。来源：5 路并行 explorer 报告，按维度重组。

## 维度 1：比赛机制细节（explorer 1）

- 赛事全 AI 主题：硬性要求第一条 = 产品须含 AI 元素并部署于 X Layer；条款称 "AI Season"。
- 官方页面未公布完整赛道列表；唯一被命名赛道 = AI-RWA（Liquidity Grant 适用）。
- 奖项：Hackathon Grant 第一 30k / 第二 15k / 第三 5k USDT（评审产出，全体竞争）；
  Liquidity Grant 50k（仅 AI-RWA 最佳）；Launch Grant 最高 200k（OKX DEX 界面交易量档）。
  三 grant 是否可叠加 [UNVERIFIED]。
- 硬性要求：08-07~08-21 23:59 UTC 内部署 X Layer 测试网（赛期内不要求主网）；
  独立 X 账号持续运营 + 发帖 @XLayerOfficial；Google 表单提交
  （字段：项目名/描述/URL/GitHub/Email/TG/X handle/X 帖子 URL；无赛道选择字段）。
- 评审标准：AI 应用与创新性、产品完成度、用户价值、X Layer 集成度、增长潜力、生态贡献；
  主办方另参考链上数据、代码质量、市场判断；评委名单未公布 [UNVERIFIED]。
- 往届画像（OKX ETHCC 2025）：获奖项目高度一致 = 深度集成 OKX DEX API/钱包 + X Layer 的
  成品化应用，AI agent 叙事反复获奖（AgenPay、Trendpup、Rivalz）。
- Build X 序列前一站 OKX.AI Genesis（7 月）要求 AI 服务上架 OKX.AI 市场。

## 维度 2：X Layer 生态现状（explorer 2）

- 已换栈：Polygon CDK → OP Stack（2025-12），经 Polygon AggLayer 悲观证明结算；1 秒出块、
  gas ≈0.02 gwei、Flashblocks 200ms 预确认；主网 chainId 196 / 测试网 1952（旧 195 废弃）；
  gas token OKB（供应锁 2100 万）。
- TVL ≈ $113M（DefiLlama 实测），Aave V3 占 ~74%；Uniswap V3 $17.5M；原生 DEX 仅 PotatoSwap 等小型。
- 稳定币：USDT0、原生 USDC+CCTP、USDG；预言机 Chainlink/API3/Band/RedStone/Supra；
  索引 The Graph/Dune/Allium；RPC QuickNode/Alchemy/Ankr/Tenderly；安全仅 Blockaid（生态页列出）。
- 生态缺口：行情终端（GeckoTerminal 不支持 xlayer）；合约安全工具近空白；
  AI 开发者工具链（MCP/agent 监控）刚起步；原生 DeFi 基元稀缺。
- OKX DEX 集成三路径：API/SDK（支持 chainId 196）、DEX Widget（可嵌入）、纯链上建池。
  Builder Codes（ERC-8021 归因）是低成本加分项。
- 官方叙事：AI agents（OKX.AI 市场、Agentic Wallet、x402、MCP）× 金融（Exchange OS、稳定币、RWA）
  × "The NewMoney Chain"。

## 维度 3：Web3 Cloudflare 概念验证（explorer 3）

- 四形态拆解：(a) RPC/CDN 被巨头占死、重资产，11 天不可行；(b) 交易防火墙 WAF 壁垒=威胁情报
  数据网络+分发，Blockaid 已于 2025-12 集成 X Layer——"X Layer 没有安全网关"叙事不成立；
  (c) 纯模拟无独立市场；(d) 监控/断路器拥挤（OZ Defender/Forta）。
- 付费方全是 B 端（钱包/链/协议），散户不为安全付费；B2B 需要信誉与数据积累。
- 真实新缝隙：AI agent 自主交易的授权边界/策略执行层。x402 已成标准（KPMG 口径 1.61 亿笔）、
  《Five Attacks on x402》预印本、Halborn 原则 "agent 只应提议不应执行"；
  Mastercard Verifiable Intent、Google AP2、ERC-7715 等巨头在填但窗口仍在。
- 黑客松先例：ENShell（ETHGlobal Cannes 2026 入围，一人 36 小时，agent 防火墙）、
  Aegis Protocol V5（Chainlink Convergence 获奖）、GenGuard、Safenode、FireMask。
  纯 "Web3 Cloudflare" 泛叙事无获奖先例，获奖的都是收窄到具体执行点的版本。
- Verdict：原样 "Web3 Cloudflare 平台" 不可行；收窄为 "X Layer 上 AI agent 交易防火墙/
  授权网关" 可行且有先例。定位应从 "检测一切威胁" 改为 "执行明确授权边界"（白名单/限额/
  速率/目标集合）——100% 可工程交付，不依赖威胁情报。

## 维度 4：AI × 合约安全叙事（explorer 4）

- 直接对标：Certora AI Composer（2025-11，开源，"AI 生成循环内嵌 FV 把关"），
  ETHDenver 2026 演讲 "Proving Correctness of LLM-Generated Smart Contracts"；
  PropertyGPT（NDSS 2025 杰出论文，LLM 生成验证属性）。
- ProofForge 差异点：不变量与证明随源码同文件携带、proof gate 先于部署 fail-closed——
  "AI 的产出必须带机器可核验证明才能编译通过"，现有产品无完全重合者。
- Lean 4 + AI 资本级叙事：Harmonic Aristotle（$120M C 轮，Lean 4 定理证明 AI，IMO 金牌）、
  Pi Squared（$12.5M，Proof of Proof）。
- 痛点素材：arXiv 2602.04039（LLM 生成合约常含严重漏洞）；ChainGPT 生成器 = "有生成无证明" 对照组。
- AI agent 护栏热点三重证据：Google AP2（60+ 伙伴，Mandate 原语）、Visa/Mastercard agent 支付、
  ERC-8004 Trustless Agents、Coinbase Agentic Wallets（session caps）、Fireblocks Agentic Suite、
  Lit Vincent（支出限额护栏）。**所有现有护栏都是工程强制，无一是机器证明的不变量**——
  ProofForge 卡位缝隙："护栏合约本身带证明"。
- 无 "编译器/验证器工具在 AI 黑客松获奖" 直接先例 [UNVERIFIED] → 必须把 AI 放进关键路径：
  MCP 接 LLM 生成 DSL + 定理 → 编译/proof gate → 部署；demo money shot = 失败路径
  （LLM 写出违反不变量的合约 → proof gate 当场拒绝零制品 → 自动修复重试至通过）。
- 诚实边界：只能说 "machine-checked invariant gate"，不能说 full formal verification；
  带 invariant 合约目前不能 build 到 EVM（8 target FC，仅 Quint 例外）。

## 维度 5：ProofForge 可交付盘点（explorer 5，本地仓库核实）

- EVM 产物链完整：Yul → locked solc 0.8.34 → 标准 EVM creation bytecode + 真实 ABI JSON +
  evidence/manifest（content-bound digest）。Anvil 差分覆盖 Counter/Token/MiniAmm/TokenJar 等。
- 语言能写：多宽 UInt/Int、Bool、Principal、String、Bytes、Array、Option、Struct/Enum、
  Map（UInt64→UInt64、Principal→UInt64）、if/match/bounded-for、event/revert/assert、
  context.caller/blockHeight、真实 ERC-20 调用（`pf.assets.token.transfer`，动态 callee）、
  native transfer（payable）。
- 不能写：nonempty invariant 合约无法 build 到 EVM（证明与部署分离，关键约束！）；
  无 address ABI 类型（Principal=9×uint64）、无嵌套 Map（写不出标准 ERC-20 approve/allowance）、
  无递归、String event 字段 FC。
- ERC-20 判断：写不出 ABI 兼容的标准 ERC-20，但可以调用 X Layer 上现存真实 ERC-20
  （USDT 式非标已处理）——集成点应围绕 "调用真实 ERC-20"。
- MiniAmm 两变体：vault-internal 数学版 + 双 ERC-20 真实转账版（Anvil 七场景门禁）。
  MiniAmmL1 带证明但不可部署。
- CLI：`proof-forge-next check/build`；`pf` 编排器已上 crates.io；`pf deploy` 拒绝非 local
  broadcast（testnet 也拒，需手动 cast 或放宽 gate）；deploy package 硬编码 constructor(uint64)。
- MCP server（tools/mcp/）+ Python SDK 已存在——"AI 应用"维度的直接资产，成熟度未深入 [UNVERIFIED]。
- X Layer 部署：字节码无阻碍（标准 initcode+ABI），cast/foundry 可直接部署；浏览器合约验证
  基本无望（Yul 产物无 Solidity 源码）。

## Round 1 后待验证/缺口（交 verifier 审查）

- AI-RWA 之外是否有其他命名赛道（影响定位文案）。
- MCP server 真实可用性（AI 闭环 demo 的关键依赖）。
- "护栏合约带证明"方向与 "invariant 合约不能 build EVM" 约束的张力如何解：
  demo 叙事是 "check 证证明 + build 部署无 invariant 变体" 两步，还是接受解释成本？
- 11 天执行计划的可行性（X 账号运营义务、表单字段、部署 gate 放宽）。
