---
id: GROK-GOALS
title: Goal + workflow 全队列操作手册（ProofForge）
status: draft
owner: engineering
updated: 2026-08-12
normative: false
---

# Goal + workflow：整仓工程队列

## 当前优先：下一波可执行工程（EVM lighthouse + S4）

旧 master 队列（2026-08-02）里的 N-*/BUILD-*/D3-E* 工程项已 drain。
业务形式化 wave-3′ 已 drain。
**现在不要再开 `prompt-master-queue` 从头扫。**

```text
/goal @.grok/goals/prompt-next-wave.md --budget 8000000
```

队列：`.grok/next-wave-queue.md`
单切片 workflow：`next-wave-runner`
**默认 drain**：Goal 内连续消项，不要回聊天说「继续」。

单切片（不 drain）：

```text
/workflow next-wave-runner
```

只看下一项、不改树：

```text
/workflow next-wave-runner {"mode":"status"}
```

## 不能用 Goal 自动做完的东西

| 轴 | 为什么 Goal 不能“持续跑到完成” |
|---|---|
| Formal D1–D4 0/27 | 要独立 TST/EV/资格仪式；`TASK-D1-01` 仍 blocked |
| C-3 / Anvil lossless Outcome | spec 明确 fail closed；不是缺人写 adapter |
| B-CALL-SEM / B-COMMIT-ZK / QUINT-2 / D3-E8 | 产品决策，不是实现债 |
| `just release-check` | 当前无 recipe（DOC-JUST-CONTROL） |

Goal **成功** = Track A+B 工程 pending 清空。Formal 仍保持 pending。

## 历史入口（勿当当前主轴）

| 文件 | 状态 |
|---|---|
| `prompt-master-queue.md` + `QUEUE.md` | 历史工程 drain；seed 过期；backlog 才是事实 |
| `prompt-business-formalization.md` | wave-3′ **drained**；无新 pending 不得发明切片 |
| `prompt-skeptic-recovery.md` | 已 closed |
| `proof-forge-engineering-slice` | 仍可用：任意单切片全流程 |
| `proof-forge-one-slice` | 仍可用：实现后只读 review |

## 与 workflow

| Workflow | 作用 |
|---|---|
| **`next-wave-runner`** | **当前** 下一波单切片 + local commit |
| `proof-forge-engineering-slice` | 通用单切片（需手传 args） |
| `proof-forge-one-slice` | 实现后只读 review |
| `business-formalization-runner` | 历史；队列已空则 `program_complete` |

**不** push；**不** formal release。

## 预算

| 意图 | `--budget` |
|---|---|
| 续跑一长段 drain | 8M+ |
| 小 pilot | 1–2M + 显式 `max_slices=N` |

## 禁止

不 push、不 formal 仪式、不并行改 Normalize 共享核。
不在聊天里 drain backlog 并假 done。
不重做已存在的 NEAR/CW `blockHeight` runtime harness。
