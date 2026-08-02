---
id: FAMILY-TVM-STACK-ACCOUNT
title: TVM Stack-Account family view
status: draft
owner: research
updated: 2026-08-03
normative: false
---

# Family View：TVM Stack-Account

状态：`draft`

该视图描述 **TON Threaded Virtual Machine** 一类栈式、account-based 执行：持久状态是
account 上的 **cell DAG**（c4 data cell + dict），合约间交互是 **异步消息 + bounce**，
不是 EVM 同步 `CALL`、不是 Solana 显式账户 CPI、也不是 Wasm host import/Promise 同构。

当前成员：`ton`（研究期 dossier [`11-ton.md`](11-ton.md)）。不是所有“消息传递链”或
“account 模型链”都自动归入本 family。

## 允许共享

- **无**与 EVM / SVM / Wasm host / ZK circuit / zkVM / ZK application chain 的 Plan 或
  TargetIR 共享。
- 可共享的仅限于 ProofForge **target-neutral** 层：`SemanticProgramV1` 语义、wire/hash、
  通用 diagnostics、制品侧车格式约定——且 **不得** 因此引入 `GenericStackVmPlan` 或
  “消息链通用 Plan”。
- 同一 family 内若未来出现第二个 TVM 兼容网络，仍须 **独立 `TargetId` + 独立 Plan 类型**；
  NetworkProfile 只区分链，不合并 materializer。

## 必须分离

| 轴 | TON / TVM（本 family） | EVM | Solana (SVM) | NEAR (Wasm host) |
|---|---|---|---|---|
| 执行模型 | 栈式 TVM；int257；codepage `cp0` + GlobalVersion 解锁指令 | 栈式 256-bit 字 EVM 字节码 | SBPF/eBPF 寄存器机 + 显式账户 | Wasm module + host imports |
| 状态 | account **c4 cell** + dict/hashmap（≤1023 bits/4 refs/cell） | contract storage trie / slots | 调用方声明的 account data | 合约账户 KV storage |
| 调用 | **仅异步消息**；callback + `query_id`；send modes；无同步返回 | 同步 `CALL`/`DELEGATECALL` 等 | CPI + account metas | Promise/receipt 异步；sync call 在 capability 上常 fail closed |
| 失败 | 五阶段 storage→credit→compute→action→bounce；compute≠业务成功 | 交易级 revert / 气体耗尽 | 指令错误码 / 账户前置失败 | receipt panic 与后续 promise 失败分离 |
| 资源 | gas + **cell/storage** 双账本；255 actions/tx | gas | CU + 账户租金 | prepaid gas + storage staking |
| 日志/事件 | external out message | LOG* | `sol_log` / events | `log_utf8` 等 host |
| 地址/身份 | workchain + hash；raw vs friendly | 20-byte address | 32-byte pubkey / PDA | account id 字符串 |
| Plan 类型 | 未来 `TonPlan` only | `EvmPlan` | `SolanaPlan` | `NearPlan` |

禁止：

- `GenericMessageChainPlan` / `GenericAccountVmPlan` tagged union。
- 把 TON 消息降成 EVM `CALL` 或 NEAR Promise 的“同一 lowering 换后端”。
- 把 dict/cell 布局编码进 shared Wasm encoder 或 shared Yul 路径。
- 在用户源码引入 `kind = ton` 或 family 标记（统一 `program ... where`，target 只在
  物化时选择）。

## 阅读指引

- Target dossier：[`11-ton.md`](11-ton.md)
- 登记决策：[ADR-0017](../adr/0017-research-phase-targets-ton-move-cairo-zkvm.md)
- 与 Wasm 共享边界对照：[family-wasm-host.md](family-wasm-host.md)（仅说明 **不** 共享）
