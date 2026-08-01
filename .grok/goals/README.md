---
id: GROK-GOALS
title: Goal + workflow 全队列操作手册（ProofForge）
status: draft
owner: engineering
updated: 2026-08-02
normative: false
---

# Goal + workflow：整仓工程队列

## 你要的「全部任务」怎么跑

```text
/goal @.grok/goals/prompt-master-queue.md --budget 8000000
```

**默认模式是 `drain`**：Goal **在内部连续消项**，直到：

- 工程 pending **清空**，或  
- **预算硬尽** / **硬阻塞**（脏 tree、决策缺失等）

**不会**因为「做完 3 项 / 进度 10%」就正常结束。  
若预算用尽，报告 `NEXT=` 后 **再开同一 Goal 从 NEXT 续跑**。

## 与 workflow

| Workflow | 作用 |
|---|---|
| `proof-forge-engineering-slice` | 单切片全流程 + local commit |
| `proof-forge-one-slice` | 实现后只读 review |

**不** push；**不** formal release。

## 目录

```text
.grok/goals/
  prompt-master-queue.md    ← ★ 主 Goal（drain 全队列）
  QUEUE.md / slices/        ← 顺序与每项契约
  prompt-build-1-2.md / prompt-n-a2.md  ← 细案
```

## 单开一项

```text
/goal @.grok/goals/slices/BUILD-3.md --budget 1500000
```

## pilot（可选限流）

仅当显式需要短试跑时：

```text
/goal @.grok/goals/prompt-master-queue.md pilot max_slices=3 --budget 2000000
```

未写 `pilot` / `max_slices` → **一律 drain**。

## 预算

| 意图 | `--budget` |
|---|---|
| 续跑一长段 | 8M+ |
| 小 pilot | 1–2M + 显式 max_slices |

## 禁止

不 push、不 formal 仪式、不并行改 Normalize 共享核。
