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

这会让 Goal **按序消费** [QUEUE.md](QUEUE.md) 里 **60 个工程切片**（每项契约在 [slices/](slices/)），  
配合已有 workflow：

| Workflow | 作用 |
|---|---|
| `proof-forge-engineering-slice` | 单切片：preflight→实现→三方审→修→验→**本地 commit** |
| `proof-forge-one-slice` | 实现后只读 review（Goal 自实现时用） |

**不会**自动 formal release；**不会** push。

## 目录结构

```text
.grok/goals/
  README.md                 ← 本文件
  QUEUE.md                  ← 全序 ID 表
  slice-ids.txt             ← 纯 ID 列表
  prompt-master-queue.md    ← ★ 主 Goal（跑全部队列）
  prompt-build-1-2.md       ← BUILD 细案（可选，比 slice 更详）
  prompt-n-a2.md            ← N-A2 细案
  slices/
    BUILD-1.md … EXT-CRYPTO.md   ← 每 ID 一份可执行契约 + engineering-slice JSON
```

## 单开某一项（不用主队列）

```text
/goal @.grok/goals/slices/N-1.md --budget 2000000
```

或：

```text
/workflow proof-forge-engineering-slice
```

args 复制对应 `slices/<ID>.md` 里的 JSON。

## 与「Go / Goal」的关系

- **Goal** = 跨轮自动驾驶 + 完成前 adversarial 核验（slash `/goal`）。  
- **Workflow** = 确定性多智能体流水线（`/workflow` 或模型侧 `workflow` 工具）。  
- **Backlog** = 人类可读状态权威 `docs/engineering-backlog.md`（Goal 必须回写）。

推荐：**主 Goal 驱动顺序**，切片内 **调 engineering-slice / one-slice**。

## 会话预算建议

| 意图 | `--budget` 量级 | max_slices |
|---|---|---|
| 只做 BUILD 反馈循环 | 0.8M–1.5M | 3 |
| BUILD + 一个 Normalize | 2M–4M | 2–3 |
| 长跑多切片 | 8M+ | 5–10（见 master 内默认 3，可改） |

一项共享核 Normalize 失败重试会吃很多 token——**宁少勿滥**。

## 禁止

见任意 `slices/*.md` 的 Global forbidden；主队列再强调：不 push、不 formal 仪式、不并行改 Normalize。

## 生成说明

`slices/*` 与 `QUEUE.md` 由工程 backlog 导出生成（2026-08-02）。  
新增 backlog ID 时：补 `slices/<ID>.md` + `QUEUE.md` 一行，并同步 `docs/engineering-backlog.md`。
