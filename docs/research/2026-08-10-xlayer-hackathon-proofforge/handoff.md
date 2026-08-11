---
id: RPT-XLAYER-HANDOFF
title: X Layer 黑客松调研交接
status: draft
owner: research
updated: 2026-08-11
normative: false
---

# handoff：10 分钟接手本调研

## 这是什么

为 OKX X Layer "AI Season" 黑客松（2026-08-21 23:59 UTC 提交截止）选参赛方向的调研，
已完成 3 轮 deep-investigate（终轮 verifier PASS）。目标：拿评审奖（Hackathon Grant 前三）。

## 读这个顺序

0. **产品合体规划（2026-08-11）**：[`docs/plan/ai-rwa-verified-ship-xlayer.md`](../../plan/ai-rwa-verified-ship-xlayer.md)
   —— 将「A Verified Ship（Web3 Vercel）」与「C AI-RWA 竖切」压成单一产品 **ForgeRWA**；
   原 final 护栏金库升维为 RWA 份额策略层。**竖切以该 plan 为准**；编译器能力边界仍以
   `final.md` 实测为准。plan **§7.4**：赛期 **不接入** 外部 Yul→EVM 形式化 backend。
0b. **Yul/EVM formal backend 登记（2026-08-11）**：
   [`docs/research/2026-08-11-yul-evm-formal-backends.md`](../2026-08-11-yul-evm-formal-backends.md)
   —— powdr / EVMYulLean / Solidus 等仅作 **D4 候选**；禁止产品 Lake 依赖与字节码已证声称。
1. `final.md` —— 结论：原主推护栏金库、verdict、证明悬崖、风险清单（能力基线）。
2. `working-r3.md` —— 关键实测：LLM 生成 DSL 实验（证明悬崖）、护栏合约 DSL 可表达性。
3. `working-r2.md` —— 评审感知路径、视频脚本、X 帖策略、X Layer 实测参数。
4. `working.md` —— 比赛机制、生态、竞品、Web3 Cloudflare 拆解。
5. `plan.md` —— 调研框架（可跳过）。

## 立刻可复用的资产

- `/tmp/pf-llm-experiment/vault-v1.lean` —— 已 check + EVM build 通过的金库合约（实验产物，
  模块名 `Examples.SpendVault` 风格，跑前读文件头确认 `--module` 参数）。
- `/tmp/pf-llm-experiment/even-step-v1.lean` —— certified 族内变体（~11s）。
- 编译器二进制：`.lake/build/bin/proof-forge-next`；foundry 在 `~/.foundry/bin`。
- X Layer 测试网 RPC：`https://testrpc.xlayer.tech/terigon`（chainId 1952，实测在线）。

## 执行第一天的三件事

1. 建项目 X 账号（资格硬条款）；2. 领 faucet（web3.okx.com/xlayer/faucet）；
3. 用 vault-v1.lean 的 bin 做首次真实测试网部署（`cast send --create`）。

## 三条铁律

- 证明环节现场只跑族内模板（族外归约挂起 8 分钟+），自由发挥预录。
- 对外只说 "machine-checked invariant gate"，不说 full formal verification；部署的是无 invariant 孪生文件。
- 定位是 "AI 应用"（AI 在关键路径），不是 "安全工具"（OKX 系评审无安全工具获奖记录）。
- **不**把 powdr yul-c / EVMYulLean / Solidus 等接进赛期产品路径；default 仍是工程 solc emit（见 plan §7.4）。

## 已知的编译器坑（demo 要避开）

- 无括号 `error X` 声明 → PF-INTERNAL（真实 bug，应写 `error X()`）。
- event/error 字段仅匿名 UInt/Int/String；Principal 字段不允许。
- invariant/constants 非空 → EVM build fail closed（PF-PLAN-INVARIANT，裸异常文本）。
