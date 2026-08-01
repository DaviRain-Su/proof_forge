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

**若 skeptic 缺口仍 open（矩阵未真扫 / DONE_IDS 漏项 / BUILD-5 脏日志）先：**

```text
/goal @.grok/goals/prompt-skeptic-recovery.md --budget 4000000
```

**当前主轴（N-1 已 commit，N-2 有 Goal-owned WIP 未提交）——在 Goal 内收口 N-2 再 drain：**

```text
/goal @.grok/goals/prompt-n-2-finish.md --budget 4000000
```

或：

```text
/goal @.grok/goals/prompt-master-queue.md starting at N-2 --budget 8000000
```

**禁止**在普通聊天回合里把 N-2/后续切片实现到「半绿 + backlog 假 done」；实现、检查、commit、backlog 回写都必须发生在 **Goal** 内。

**默认模式是 `drain`**：Goal **在内部连续消项**，直到：

- 工程 pending **清空**，或
- **预算硬尽** / **硬阻塞**（无关脏 tree、决策缺失等）

**不会**因为「做完 3 项 / 进度 10%」就正常结束。
若预算用尽，报告 `NEXT=` 后 **再开同一 Goal 从 NEXT 续跑**。
Skeptic / N-2 修复也必须在 **Goal 内 commit**，不要在聊天侧手工交差后假装队列前进。

## 与 workflow

| Workflow | 作用 |
|---|---|
| `proof-forge-engineering-slice` | 单切片全流程 + local commit |
| `proof-forge-one-slice` | 实现后只读 review |

**不** push；**不** formal release。

## 目录

```text
.grok/goals/
  prompt-master-queue.md       ← ★ 主 Goal（drain 全队列）
  prompt-skeptic-recovery.md   ← skeptic 三缺口优先入口
  prompt-n-2-finish.md         ← 收口 N-2 WIP → commit → 续 drain
  QUEUE.md / slices/           ← 顺序与每项契约（含 SKEPTIC-1、N-2、DOC-T9-0）
  prompt-build-1-2.md / prompt-n-a2.md  ← 细案
```

## 单开一项

```text
/goal @.grok/goals/slices/N-2.md --budget 2000000
/goal @.grok/goals/prompt-n-2-finish.md --budget 4000000
/goal @.grok/goals/slices/DOC-T9-0.md --budget 1500000
/goal @.grok/goals/slices/SKEPTIC-1.md --budget 2000000
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
