---
id: RPT-002
title: 多平台执行模型研究
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# 多平台执行模型研究

状态：`draft`
研究日期：2026-07-15

## 问题与范围

本报告比较十个目标的执行、状态、调用、失败、证明和结算模型，判断哪些语义可以共享，哪些必须由 target-owned Plan 保留。

## 方法

阅读 `source-register.json` 中的一手规范；将平台术语映射到统一分析轴，但不把分析轴误当成统一运行时。

## 比较结果

| Target | 执行/提交单元 | 状态绑定 | 调用模型 | 证明/结算 |
|---|---|---|---|---|
| EVM | 交易内嵌套执行；异常回滚 | 合约账户 storage | 同步 message call | 链直接结算 |
| Solana | transaction/instruction 原子执行 | 显式传入 accounts | 同步 CPI | 链直接结算 |
| NEAR | receipt 局部执行与提交 | 合约 KV | Promise/receipt/callback | NEAR receipt 结算 |
| CosmWasm | Cosmos 交易；submessage/reply 保存点需版本冻结 | 合约实例 KV | CosmosMsg/SubMsg/IBC | Cosmos 链结算 |
| Soroban | Stellar transaction | instance/persistent/temporary + TTL | 同步合约调用和 auth tree | Stellar 链结算 |
| ICP | 单 canister message；`await` 划分提交边界 | heap + stable memory | actor 异步消息 | ICP 子网结算 |
| Noir | 关系/约束求值 | 无原生持续状态 | 无链原生调用 | proof + 外部 verifier |
| OpenVM | guest 指令执行 | guest memory/I/O | guest 内调用 | proof + 外部 verifier |
| Aleo | 私有 proof context + 公共 finalization | records + mappings | program call/finalization | Aleo 链结算 |
| Psy | 本地 CFC/UPS + 网络递归聚合 | 用户分区状态 | 证明化调用流水线 | Psy 网络 finalization，provisional |

## 原子结论

| Claim | 状态 | 含义 |
|---|---|---|
| `CLM-EVM-001` | verified | EVM Plan 必须拥有 storage/ABI/call/revert 细节 |
| `CLM-SOL-001` | verified | Solana 账户元数据不是通用 storage 的一个布尔开关 |
| `CLM-NEAR-001` | verified | Promise DAG 不能降成同步 call |
| `CLM-WASM-001` | verified | 四个 Wasm host 仅共享编码层 |
| `CLM-NOIR-001` | verified | 电路输出不等于部署合约 |
| `CLM-OVM-001` | verified | zkVM guest 不等于电路 DSL |
| `CLM-ALEO-001` | verified | proof/final 两个上下文必须保留 |
| `CLM-PSY-001` | provisional | Psy 是带状态与结算的 ZK 应用链候选模型 |

## 统一语义边界

业务层可以统一描述纯计算、逻辑状态迁移、有序 effect、权限和披露意图。目标不得改变：整数宽度和溢出规则、成功后的逻辑后状态、失败时的状态承诺、effect 顺序、权限谓词及公开/私有/承诺信息。

目标可以决定如何实现这些语义：EVM storage、Solana accounts、NEAR KV、Noir pre/post state commitment 都是不同 realization。如果不存在等价 realization，`resolve` 必须失败，而不是模拟成功或静默丢弃 effect。

## 冲突

- “一次调用失败时状态不变”在异步系统中不能跨多个已提交 receipt/message 自动成立。DSL 必须把 `schedule` 产生的异步工作流与同步 `call` 分开，或者目标拒绝。
- 电路和 zkVM 没有平台原生持久状态。编译有状态程序时只能生成可验证状态转移，并把连续性与结算标为 external。
- Aleo/Psy 同样使用 ZK，但拥有链状态与结算规则，不能归入通用 circuit family。

## 结论

不存在能安全驱动所有后端的单一 VM family。编译决策必须依赖多轴 `TargetDescriptor` 和精确 `SupportClaim`；“family”只用于文档导航。

## 限制与开放问题

- CosmWasm reply/savepoint 需要冻结具体 runtime/wasmd profile 后重验。
- OpenVM 需要冻结单一版本线。
- Psy live compiler/deploy/prover/network 流程尚未复现。
- 各链 gas/compute/resource 计量会随 protocol/fork 升级改变可观察执行结果，因此必须进入
  versioned target semantics digest；`NetworkProfile` 只声明某 network 兼容的 exact BuildIdentity。
