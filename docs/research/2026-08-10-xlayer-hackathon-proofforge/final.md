---
id: RPT-XLAYER-FINAL
title: ProofForge 参赛 X Layer 黑客松方向最终报告
status: draft
owner: research
updated: 2026-08-10
normative: false
---

# ProofForge × OKX X Layer "AI Season" 黑客松参赛方向：最终调研报告

日期：2026-08-10 ｜ 协议：deep-investigate 3 轮（5+4+3 路 explorer，3 轮独立 verifier，终轮 PASS）
核心问题：用 ProofForge 做什么参赛最合理（目标：评审奖）？"Web3 Cloudflare" 想法是否可行？

---

## 一、TL;DR

1. **"Web3 Cloudflare" 原样不可行**：RPC/CDN 被巨头占死；交易防火墙的壁垒是威胁情报数据网络，
   且 **Blockaid 已于 2025-12 官方集成 X Layer**——"链上没有安全网关" 的缝隙叙事不成立。
   但收窄为 **"X Layer 上 AI agent 的交易授权边界/护栏"** 可行，且正是 2026 年热点。
2. **主推方向（A）："带证明的 AI agent 金库"**——LLM 经 MCP 生成 ProofForge DSL 护栏合约
   （白名单+单笔限额+窗口累计限额），不变量证明与源码同文件、proof gate 先于部署 fail-closed，
   真实部署 X Layer 测试网。它同时命中评审第一条 "AI 应用" 与 ProofForge 的独有价值。
3. **关键实测结论（Round 3 真实实验）**：LLM 仅凭 ~300 行文档+示例即可 2-3 轮迭代写出合法
   DSL 合约并一次 build 出 EVM 字节码；证明生成是二值难度（既有定理族内改名即 certified ~11s，
   族外则 kernel 归约挂起 8 分钟+）——demo 必须按 "族内模板现场跑 + 自由发挥预录" 设计。
4. **最大结构性约束**：带 invariant 的合约目前不能 build 到 EVM（proof/deploy 孪生双文件），
   叙事必须守住 "机器核验的部署前门禁"，不能声称链上字节码被证明。
5. **资格性硬条款**：X 独立账号持续运营 + 发帖 @XLayerOfficial + 08-21 23:59 UTC 前 Google 表单
   + 赛期内测试网部署（主网可赛后），缺一取消资格。

---

## 二、比赛机制（全部经官方 SSR 原文核实）

- 时间：2026-08-07 ~ 08-21 23:59 UTC（提交截止）；剩 11 天。
- 硬性要求（任一不满足即失去参赛/收奖资格）：产品含 AI 元素 + 部署 X Layer；赛期内上测试网、
  后续上主网（无 deadline，但是收奖资格条款）；独立 X 账号存续期保持活跃；提交时 X 发帖
  @XLayerOfficial；Google 表单提交（字段：项目名/描述/URL/GitHub/Email/TG/X handle/X 帖 URL，
  无赛道选择字段）。
- 奖项：Hackathon Grant 1st $30k / 2nd $15k / 3rd $5k（评审产出）；Liquidity Grant $50k
  （仅 AI-RWA 赛道最佳）；Launch Grant ≤$200k（OKX DEX 界面交易量每满 $10M 解锁 $50k，
  反作弊核验）。三者无互斥明文，机制正交，但本次目标评审奖，Launch Grant 不追。
- 评审：AI 应用与创新性、产品完成度、用户价值、X Layer 集成度、增长潜力、生态贡献；
  主办方另参考链上数据/代码质量/市场判断；评委名单未公布。
- 竞争强度：Build X Season 1 有 100+ 提交；本届 $300k 池估计 100-300 有效提交，前三仅 3 席。
- **负面数据点**：OKX ETHCC 2025 设 Security & Privacy Tooling 赛道但无获奖者——
  纯安全工具定位在 OKX 系评审下无成功记录，必须以 "AI 应用" 而非 "安全工具" 定位。
- 往届获奖画像：深度集成 OKX 自家产品（DEX API/钱包/Agent 工具链）的成品化应用；
  AI agent 叙事反复获奖（AgenPay/Trendpup/Rivalz/Eolia）。官方可集成资产：
  okx/agent-trade-kit（交易 MCP）、okx/onchainos-skills（13 个官方 skills，含 okx-security）。

## 三、"Web3 Cloudflare" verdict（用户原想法）

| 形态 | 判断 | 依据 |
|---|---|---|
| RPC/CDN 基础设施 | 不可行 | Alchemy/QuickNode/Ankr 重资产运营生意，11 天无可信 demo |
| 通用交易防火墙/WAF | 基本不可行 | 壁垒=威胁情报数据网络+分发；Blockaid 已集成 X Layer（2025-12） |
| 交易模拟/预览 | 不可行（独立产品） | 只是安全产品的 feature |
| 协议监控/断路器 | 边缘可行但平庸 | OZ Defender/Forta 拥挤，且与 AI 评审权重无关 |
| **AI agent 交易授权边界** | **可行，推荐** | x402/AP2/ERC-7715 巨头进场但窗口仍在；ENShell（一人 36h 入围 ETHGlobal Cannes 2026）、Aegis（Chainlink Convergence 获奖）有先例；OKX 官方叙事正是 agentic commerce |

**结论：你的直觉方向没错，但需要两个收窄**——(1) 从 "平台/基础设施" 收窄到 "AI agent 花钱的
授权边界" 这个具体执行点；(2) 从 "检测一切威胁"（需要威胁情报，11 天做不出可信度）收窄到
"执行明确授权边界"（白名单/限额/速率，100% 工程可交付）。ProofForge 的证明门禁正好给这个
收窄方向提供了别人没有的差异化：**护栏的业务不变量带机器核验证明**。

## 四、候选方向（收敛结果）

### 方向 A（主推）：ProofGuard —— 带证明的 AI agent 金库护栏

**一句话**：AI agent 替你写金库护栏合约，安全不变量是同文件的 Lean 机器证明；
没有证明，编译失败，什么都不会部署到 X Layer。

- **产品形态**：MCP 接入的 LLM → 生成 `program ... where` 护栏合约（白名单 + 单笔限额 +
  时间/块高窗口累计限额 + native/ERC-20 转账）→ `check`（含 proof gate）→ `build --target evm`
  → cast 部署 X Layer 测试网 → agent 端演示：正常转账放行 / 超限额与白名单外地址被拒。
- **ProofForge 使用点**：就是产品本体。DSL + 证明门禁 + EVM 编译链全部是现有能力。
- **可行性实测（Round 3）**：金库合约已由实验 agent 从零写出，check 2 轮迭代通过、
  EVM build 一次通过（产物 yul/bin/abi.json 完整）；certified 族内变体 ~11s。
  合并版护栏合约（白名单+限额+窗口）在当前 EVM 子集内**无撞线**。
- **评审契合**：AI 应用（LLM 在关键路径，MCP 闭环）✓；创新性（证明=构建产物，无重合产品）✓；
  X Layer 集成（真实测试网部署；可选接 okx-security skill 做对照叙事）✓；
  生态贡献（X Layer 缺开发者/安全工具，agentic commerce 叙事缺安全层）✓；
  用户价值（agent 金库是 2026 真实热点：AP2/x402/session caps）✓。
- **差异化卡位（经反例排查加固）**："在 AI agent 支付护栏品类里，没有任何公开产品把业务安全
  不变量的机器核验证明作为部署前强制门禁。Safe 验证的是 guard 挂载机制而非策略本身；
  Zodiac 策略层仅有传统审计；AP2 mandate/session caps/LLM 防火墙全部是工程强制——
  约束执行路径，但不证明不变量。" 素材：2026-06 Gnosis Pay 因 Zodiac 依赖一行缺失的
  ERC-1271 success 检查被盗 ~$1.5M（官方 post-mortem 已核实，措辞勿带 "审计过"）。
- **vs Certora AI Composer**（最强相邻竞品，评委可能问）：它验证的是人事后写的外部 CVL 规格、
  是开发期研究原型、LLM 可请求放宽需求；ProofForge 的证明与源码同文件、编译期 fail-closed、
  无放宽通道——"证明不是审计产物，是构建产物"。借 Certora 背书品类，不贬低。
- **主要风险**：见第六节风险清单 R1-R5。

### 方向 B（备选/降级）：AI 合约工厂 —— 自然语言到 X Layer 的可验证流水线

如果护栏叙事执行中塌掉（例如证明环节掉链子），降级为泛化的 "vibe-coding 但带门禁"：
自然语言 → DSL 生成 → check/build → 一键部署 X Layer。对照组是 ChainGPT 生成器
（有生成无证明）。差异化仍在 proof gate，但叙事尖锐度低于 A，且更靠近 "开发工具"
（OKX 系评审对纯工具的负面记录）。**只作降级预案，不作主推。**

### 方向 C（不推荐作主方向）：MiniAmm/DeFi 原语

MiniAmm（双 ERC-20 AMM）有 Anvil 门禁、可 build。但：DeFi 方向竞争者多、AI 元素弱、
接入 OKX DEX 路由需官方集成（[UNVERIFIED] 接入条件）、与用户设定的评审奖目标错位。
可作 A 的增强素材（金库与真实 USDT0 互操作）。

### 方向 D（不推荐）：ProofForge 编译器本体作为产品

无 AI 角度、无获奖先例、纯工具定位在 OKX 系评审下无成功记录。

## 五、方案选型（G17：证明叙事怎么讲）

| 方案 | 内容 | 工期 | 选择 |
|---|---|---|---|
| c | proof gate 拒绝攻击合约的 money shot（现有能力） | ≈0 | **做**（保底） |
| b | 孪生双文件：check 证证明 + build 部署无 invariant 变体 | <1 天 | **做**（仓库自带先例） |
| a'（新增） | 为 `spent <= windowCap` 写一条 contract-agnostic shape 引理 | 1-2 天（编译器侧，参考 parity family） | **stretch**——做成则 "限额永不超额有机器证明" 叙事为真；做不成就用族内 parity 变体演示证明机制 |
| a | 打通 EVM invariant lowering（invariant 编译为运行时 assert） | 2-4 天 + 测试，风险高 | **放弃**（赛期内不碰 LowerSemanticV1） |

demo 演示设计（90 秒视频 + 现场脚本）：钩子（Gnosis Pay 事件）→ agent 对话生成合约
（定理与源码同文件高亮）→ check certified + build + X Layer 测试网真实部署 →
**高潮：坏合约被 proof gate 拒绝、零制品** → agent 自动修复重试成功 → 对比字幕
（工程强制 vs 机器证明）。**执行铁律（来自实测）：证明环节现场只跑族内模板变体（~11s），
自由发挥的定理必须预录——族外证明会分钟级挂起。** 先写 demo 脚本再写代码（ENShell 经验）；
所有链上画面用真实 testnet 交易并提前压测。

## 六、风险清单与缓解

- **R1 证明悬崖（最高危）**：现货证明族只有 parity/eq-zero/literal-true 三个形状；
  "spent<=windowCap" 需要新 shape 引理。缓解：demo 用族内变体 + 预录；a' 作 stretch。
- **R2 孪生接缝**：certified 文件与部署文件是两份源，等价性靠工程纪律非密码学绑定；
  评委会问 "证明绑的是哪份代码"。缓解：README/FAQ 主动写清楚；可选做孪生一致性检查小工具
  （normalize 后 diff canonical bytes）。
- **R3 编译器粗糙面**：无括号 `error X` 声明触发 PF-INTERNAL（真实 bug，实验中发现）；
  FC 报错为 uncaught exception 裸文本。缓解：demo 脚本避开已知坑；文档侧记录 workaround。
- **R4 定位风险**：纯安全工具在 OKX 系无获奖记录。缓解：一切材料以 "AI 应用" 为主语
  （"AI agent writes your vault"），安全是 AI 产物的属性而非产品定位。
- **R5 资格合规**：X 账号义务是硬条款。缓解：Day 1 建号，赛期 2-3 条 build-in-public 帖，
  提交帖 @XLayerOfficial + 原生内嵌视频。
- **R6 非阻塞遗留**：OKLink 对 Yul standard-JSON 验证未实测（explorer 上合约显示未验证，
  功能展示不受影响）；Genesis 获奖名单未公开可检索；多 Map state 共存未验证（demo 用单 Map）。
- **诚实边界（必须守住）**：只说 "machine-checked invariant gate / 部署前门禁"；
  不声称 full formal verification、不声称链上字节码被证明、不声称证明覆盖任意业务不变量。
  评委席可能有 FV 背景观众（Certora 生态），过度声称会被当场击穿。

## 七、11 天执行计划（G9，一人团队）

| 日 | 工作 |
|---|---|
| D1（08-10/11） | 决策确认；建项目 X 账号；领 faucet（0.2 OKB/天足够）；用 R3 实验产物 vault-v1.lean 的 bin 做首次真实 X Layer 测试网部署 spike（cast 已装，RPC 已实测）；打开 Google 表单确认字段 |
| D2-D3 | MCP 补 `pf_check` wrapper（~30 行，照 pf_build 抄；SDK 已有 check()）；LLM 生成→报错→修复循环脚本端到端跑通（实测纯合约 2-4 轮收敛） |
| D4-D5 | 护栏合约定稿（白名单+单笔限额+窗口累计，固定资产集规避嵌套 Map）；族内 certified 变体；攻击拒绝路径选定快失败方式（删 proof 声明/改定理名，避开归约挂起）并预录 |
| D6-D7 | stretch：a' shape 引理（spent<=windowCap）；否则加固 demo 压测（所有链上交易预跑数小时，ENShell 经验） |
| D8-D9 | GitHub README（首屏：一句话问题+架构图+30 秒最小命令，AI 组件独立色块）；90 秒视频录制（7 镜头脚本见 working-r2.md）；X 帖子文案 |
| D10 | 表单提交前演练；X 主帖发布（提交前 24-48h，原生内嵌视频） |
| D11（08-21） | 提交 Google 表单；缓冲 |
| 赛后 | 主网上线义务（OKB 成本 ~$0.0001/次部署，OKX 提币即可） |

## 八、关键事实备查（精选来源）

- 官方页面/条款/Requirements 原文：[web3.okx.com/xlayer/build-x-series](https://web3.okx.com/xlayer/build-x-series)
- X Layer 测试网实测：chainId 1952、0.02 gwei、PUSH0/MCOPY/TSTORE 可用、EIP-3860 生效、
  eth_getLogs 限 100 块窗口；faucet 0.2 OKB/天+滑块验证
- Blockaid 集成 X Layer：[blockaid.io/blog](https://www.blockaid.io/blog)（2025-12-17）
- Agent 护栏热点：Google AP2、Coinbase x402/Agentic Wallets、Lit Vincent、Fireblocks Agentic Suite
- 黑客松先例：ENShell（ETHGlobal Cannes 2026 入围）、Aegis V5（Chainlink Convergence）、
  KSwap-VM（ETHGlobal Lisbon 2026，1inch 赛道 $1000，FV 类唯一获奖先例）
- Certora AI Composer：[github.com/Certora/AIComposer](https://github.com/Certora/AIComposer)
- Gnosis Pay post-mortem：[gnosis.io/blog](https://www.gnosis.io/blog/post-mortem-gnosis-pay-vulnerability-exploit)
- OKX 官方 agent 工具链：github.com/okx/agent-trade-kit、github.com/okx/onchainos-skills
- R3 实测产物：/tmp/pf-llm-experiment/（vault-v1.lean check+EVM build 通过，已经 verifier 独立复现）

## 九、遗留 [UNVERIFIED]（非阻塞）

OKX.AI Genesis 获奖名单（X 反爬）；OKLink Yul standard-JSON 验证接受度（可实测一次）；
OKX DEX 对新 AMM 的路由接入条件（需 DevRel）；init 内 context.caller（实际已被 R3 实验
vault 的 EVM build 成功间接回答）；多 Map state 共存；三个 Grant 叠加无明文。
