---
id: RPT-XLAYER-PLAN
title: X Layer 黑客松调研计划
status: draft
owner: research
updated: 2026-08-10
normative: false
---

# 调研计划：ProofForge × OKX X Layer "Build X Series / AI Season" 黑客松参赛方向

日期：2026-08-10
协议：deep-investigate（FRAME → EXPLORE×N → ANALYZE → DELIVER）

## 核心问题

在 OKX X Layer 黑客松（2026-08-07 ~ 08-21 提交，EVM L2，评审导向）中，
用 ProofForge（Lean 4 多目标合约编译器，EVM lane 有 solc bytecode + inline 不变量证明门禁）
构建什么产品最合理以赢得评审奖？并明确评估用户原有想法 "Web3 Cloudflare 平台" 的可行性。

## 已确认的关键事实（Phase 1 初步搜索）

- 赛事名称：Crypto Hackathon 2026 | OKX Web3 Developer Challenge；法律条款中称为 "AI Season"。
- 时间：黑客松期 2026-08-07 ~ 08-21 23:59 UTC（今天 08-10，剩约 11 天）。
- 硬性要求：必须部署到 X Layer 测试网，后续须上主网。
- Launch Grant：截至 08-31 23:59 (UTC+8) 经 OKX DEX 界面（API 不计）累计交易额
  每满 10,000,000 USDT 解锁 50,000 USDT，单项目上限 200,000 USDT；09-01 快照，反作弊核验。
- Liquidity Grant：仅面向 AI-RWA 赛道。
- 评审标准：AI 应用、创新性、产品完成度、用户价值、X Layer 集成度、增长潜力、生态贡献。
- 反作弊：wash trading / 刷量取消资格。
- 参赛目标（用户确认）：拿评审奖，不追交易量档位。

## ProofForge 能力基线（来自仓库 AGENTS.md，待验证）

- Lean 4 DSL 编译器 `proof-forge-next`，统一 `program ... where` 源码。
- 9 个已实现 materializer：EVM / Solana / NEAR / Noir / Aleo / Psy / Quint / CosmWasm / TON。
- EVM lane：真实 solc bytecode（Yul 经 `solc --strict-assembly`）、Anvil 差分测试、
  inline same-file theorem 认证（invariant 证明门禁，ADR-0027）。
- 当前产品子集：多宽 UInt/Int、Bool/aggregates、控制流、checked 算术、revert/emit、
  call/schedule、ContextRead/Commit、invariant 子集。
- 重要限制：formal D1–D4 未闭合；EVM 目前是工程先导（public-UInt64 add/sub 等子集）；
  语言子集对复杂 DeFi 合约的支持程度待确认。

## 调研维度

1. **比赛机制细节**：完整赛道列表、奖项结构、评审细则、往届 OKX/X Layer 黑客松获奖项目画像。
2. **X Layer 生态现状**：链参数、现有 dApp/基础设施、生态缺口、OKX DEX 集成方式、开发者工具成熟度。
3. **"Web3 Cloudflare" 概念验证**：定义拆解、现有竞品（RPC 网关、交易模拟、安全中间件）、
   真实需求与付费方、11 天 MVP 可行性。
4. **AI × 合约安全/形式化验证叙事**：评审的 "AI 应用" 权重如何满足；
   LLM 生成合约 + 机器校验不变量的叙事在 2026 黑客松中的接受度。
5. **ProofForge 可交付盘点**：EVM lane 11 天内真实可交付的合约类型与 demo 路径、限制清单。

## min_rounds

3（产品决策类调研，复杂度中等，且提交截止 08-21 时间敏感；默认 10 不适用）。

## 完成标准

- 产出 2–4 个候选参赛方向，每个含：ProofForge 使用点、11 天可行性评估、
  与评审标准（AI 应用 / X Layer 集成 / 用户价值 / 生态贡献）的契合度、主要风险。
- 对 "Web3 Cloudflare" 给出明确 verdict（可行 / 不可行 / 如何改造才可行）。
- 每个关键结论附来源；未能验证的声明标 `[UNVERIFIED]`。

## 保存位置

`docs/research/2026-08-10-xlayer-hackathon-proofforge/`（plan.md → working.md → final.md + handoff.md）
