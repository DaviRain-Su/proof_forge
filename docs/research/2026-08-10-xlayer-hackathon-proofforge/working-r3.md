---
id: RPT-XLAYER-W3
title: X Layer 黑客松调研工作文档 Round 3
status: draft
owner: research
updated: 2026-08-10
normative: false
---

# 工作文档（Round 3 增量合并）

日期：2026-08-10。接 working.md / working-r2.md。

## G13/G14 LLM 生成 DSL 实测（coder agent-14，真实实验，全部实测）

**这是本轮最重要的实证。** 方法：agent 仅凭语言 EBNF（docs/specs/language.md 45-125 行）
+ 3-4 个示例，从零写合约并跑真实编译器。

- **上下文成本**：约 250-300 行有效参考材料即可写出合法合约（EBNF 80 行 + 示例 ~150 行）。
- **阶段 1（金库合约）**：语义建模（owner/白名单/限额/transfer/match）一次全对；
  2 轮实质迭代到 check 通过；`build --target evm` 零额外迭代一次通过，产出 yul/bin/abi.json
  （solc 真实编译，ABI 正确）。期间 8 次迭代是在给一个编译器 bug 做二分
  （无括号 `error X` 声明触发 `PF-INTERNAL` 而非语法错误——真实 bug）。
- **阶段 2（带证明合约）**：悬崖式分布——**既有定理族形状内（parity/literal-true）改名级变体
  一次 certified（~11 秒）**；偏离族形状（+2 改 +4）则 kernel 归约失控挂起 8 分 45 秒
  （错误证明不是快速报错而是分钟级挂起）。当前全库实际只有 2 个可用证明族。
  "count 只增" 这类单调性跨状态性质在语言层面不可表达。
- **阶段 3 结论**：(a) 纯合约 2-3 轮迭代收敛，文档补齐两个表面坑后一次通过率估计 60%+；
  (b) 证明是二值难度（族内免费/族外不可行）；(c) 自动修复循环纯合约 2-4 轮收敛，
  证明环节需 60s 超时兜底+回退族内模板；(d) **90 秒 demo 全现场可行**：现场生成金库
  （check+build ~20s）+ 现场跑族内改名变体 certified（~11s），证明的自由发挥部分必须预录或拿掉。
- 附带发现：certified 文件 EVM build 仍 FC（PF-PLAN-INVARIANT，与已知约束一致）；
  FC 报错以 uncaught exception 裸文本抛出（产品打磨扣分点）。

## G15 护栏合约 DSL 可表达性（explorer 12，设计级核对）

- **全局约束重申**：证明与部署必须是孪生双文件（带 invariant 的只能 check certified，
  部署版删 invariant/const）；孪生间等价性是工程纪律而非密码学绑定（Q4：可加一致性检查工具）。
- **三个 shape 均可表达**：a 白名单金库（Principal owner + Map Principal→UInt64 + 单笔限额 +
  native/token transfer）；b 速率限制（**context.unixTimeSeconds 和 blockHeight 在 EVM 都开着**，
  固定窗口直接可写，分桶滑动窗口可表达但复杂）；c 窗口累计限额（同 b 子集）。
  合并版（白名单+单笔+窗口累计）在当前 EVM 子集内**无撞线**。
- 撞线点：event 不能带 Principal/String 字段（只能 UInt）；Principal 不能作返回值；
  无 approve 模式；多资产各自限额需嵌套 Map（不支持）→ 固定资产集平行 state 规避。
- **不变量配对（关键）**：invariant 表达式禁 ContextRead；现货可证 family 只有
  parity/eq-zero/literal-true。"白名单外地址收不到款" 不可表达（无量化/Map 迭代）；
  **`spent <= windowCap` 可表达但不在现货证明族**——需要写一条新的 contract-agnostic
  shape 引理（对标 UInt64ParityPreservationV1 一个 family 的编译器侧工程量）。
  这是把 "限额永不超额——有机器证明" 叙事做真的唯一路径；否则只能 literal-true 弱证明。
- Q2/Q3 [UNVERIFIED]：init 内 context.caller 是否开放；多条 Map state 共存。

## 遗留验证债清理（explorer 13）

- Gnosis Pay 事件一手确认：2026-06-01，~$1.5M 损失（官方口径），根因 = Zodiac 模块
  ERC-1271 验签 staticcall 丢弃 success 标志；上游已静默修复、生产停留旧依赖。
  **"审计过" 未证实——pitch 措辞绕开审计断言**（安全表述已给）。
- KSwap-VM 获奖确认：ETHGlobal Lisbon 2026 1inch 赞助商赛道 $1000——FV 项目有获奖先例但仅小额。
- OKX.AI Genesis 获奖名单仍 [UNVERIFIED]（X 反爬）。
- OKLink 验证：仅 solidity-single-file / standard-json-input / vyper；Yul-language standard JSON
  理论上可能但无文档 [UNVERIFIED，可实测]。
- 主网 OKB：OKX 提币到 X Layer 即可，部署成本 ~$0.0001/次，摩擦可忽略。
- OKX DEX 在 X Layer 路由 PotatoSwap 等已识别 DEX 的池子；新 AMM 被路由需 OKX 侧集成
  [UNVERIFIED 接入条件]。

## Round 3 后状态

- G1（候选方向收敛）、G9（产能分解）、G17（方案 a/b/c 选型）——主代理 Phase 3 完成，
  素材已齐。
- 残余 [UNVERIFIED] 均为非阻塞项（Genesis 名单、OKLink Yul 验证、DEX 路由接入条件、
  init 内 context.caller、多 Map 共存）。
