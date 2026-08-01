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

## 当前主轴（2026-08-02）

Live status authority = [`docs/engineering-backlog.md`](../../docs/engineering-backlog.md)
（QUEUE seed **不是** 真值）。

| 状态 | 说明 |
|---|---|
| **已 commit 过的主轴** | N-1…N-8、N-A*、N-BYTES、R-1…R-3、B-1d/e、B-3、B-ctx、C-1、T-3、SKEPTIC-1、DOC-* 等见 backlog `done` |
| **NEXT** | **`C-2`** Aleo/Psy compiler/VM research（**勿**升格验收门） |
| **Goal-owned WIP 可能存在** | `docs/research/15-aleo-psy-compiler-vm.md` untracked — **只许 Goal 收口 commit** |

**在 Goal 内收口 C-2 再 drain：**

```text
/goal @.grok/goals/prompt-c-2-finish.md --budget 4000000
```

或：

```text
/goal @.grok/goals/prompt-master-queue.md starting at C-2 --budget 8000000
```

**禁止**在普通聊天回合里把 C-2/后续切片实现到「半绿 + backlog 假 done」；实现、检查、commit、backlog 回写都必须发生在 **Goal** 内。聊天侧最多留下 Goal-owned WIP，不得宣称切片完成。

**默认模式是 `drain`**：Goal **在内部连续消项**，直到：

- 工程 pending **清空**，或
- **预算硬尽** / **硬阻塞**（无关脏 tree、决策缺失等）

**不会**因为「做完 3 项 / 进度 10%」就正常结束。
若预算用尽，报告 `NEXT=` 后 **再开同一 Goal 从 NEXT 续跑**。
Skeptic / 切片修复也必须在 **Goal 内 commit**，不要在聊天侧手工交差后假装队列前进。

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
  prompt-c-2-finish.md         ← 收口 C-2 WIP → commit → 续 drain
  prompt-skeptic-recovery.md   ← skeptic 三缺口优先入口（已 closed 可跳过）
  prompt-n-2-finish.md         ← 历史 N-2 收口（N-2 已 done，勿重做）
  QUEUE.md / slices/           ← 顺序与每项契约
  prompt-build-1-2.md / prompt-n-a2.md  ← 细案
```

## 单开一项

```text
/goal @.grok/goals/slices/C-2.md --budget 1500000
/goal @.grok/goals/prompt-c-2-finish.md --budget 4000000
/goal @.grok/goals/slices/C-4.md --budget 2000000
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
不在聊天里 drain backlog 并假 done。
