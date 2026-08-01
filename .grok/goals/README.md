---
id: GROK-GOALS
title: Goal + workflow 操作手册（ProofForge）
status: draft
owner: engineering
updated: 2026-08-02
normative: false
---

# Goal + workflow 怎么配合

本仓库的推荐模式是：

```text
你（或会话）启动 /goal  <── 长循环、跨多轮、完成前有独立证据复审
         │
         ├─ 每一切片实现后 ──► /workflow proof-forge-one-slice
         │                      （只读三方 review，不改代码）
         │
         └─ 或者整切片包办 ──► /workflow proof-forge-engineering-slice
                                （preflight→implement→review→repair→verify→local commit）
```

| 机制 | 职责 | 预算 |
|---|---|---|
| **`/goal`** | 跨轮推进 backlog 一项（或一小串）；自己选下一步、改代码、跑门禁；完成后由 host 做 adversarial 完成核验 | **token** 预算（`--budget`） |
| **`proof-forge-engineering-slice`** | 单切片端到端（含 local commit、禁止 push） | **agent 调用数**（默认 128） |
| **`proof-forge-one-slice`** | Goal 已实现且测试绿后的只读复审 | agent 数 |
| **`docs/engineering-backlog.md`** | 权威队列与 ID | — |

## 会话前置

1. 工作区干净：`git status` 无未提交产品改动（或 Goal 明确只吃某一 baseline）。
2. Goal 模式开启；`GROK_WORKFLOWS=1`（默认）以便 Goal 走 host workflow 驱动 + 完成核验。
3. 日常队列：[`docs/engineering-backlog.md`](../../docs/engineering-backlog.md)。

## 推荐执行序列（当前 backlog）

| 序 | ID | 怎么跑 | Prompt 文件 |
|---|---|---|---|
| 1 | **BUILD-1 + BUILD-2** | `/goal` 粘贴 `prompt-build-1-2.md`；内部可调 `proof-forge-engineering-slice` 或直接改 justfile | [prompt-build-1-2.md](prompt-build-1-2.md) |
| 2 | **N-A2** 多臂同构造器 match | 新 `/goal` 粘贴 `prompt-n-a2.md`；共享核串行，**禁止**并行改 Normalize | [prompt-n-a2.md](prompt-n-a2.md) |
| 3 | 后续 Normalize | 复制 `prompt-n-a2.md` 模板，换 ID/契约 | 见 backlog §2 |

**不要**一个 Goal 吞整个 backlog（T9e、IBC、formal 全塞）——完成核验会失败或拖垮预算。

## Goal 内如何调用 workflow

在 Goal 回合里（模型侧）用 **workflow 工具**，不要假装用户 slash 已执行：

```text
# 实现完、HEAD 未变、仅有未提交 diff 时：
workflow name=proof-forge-one-slice
  args = {
    slice: "BUILD-1-2",
    base_commit: "<pre-impl HEAD>",
    task_prompt: "<本切片契约一句话>",
    changed_files: ["justfile", ...]
  }

# 或者整切片交给 engineering-slice（更重，含 commit）：
workflow name=proof-forge-engineering-slice
  args = { ... 见各 prompt 内 JSON ... }
```

Goal 完成声明必须可复现：commit SHA、命令输出、`docs/engineering-backlog.md` 状态行更新。

## 禁止项（所有 Goal / workflow）

- 不 push、不 force、不 amend 已发布 commit  
- 不新建 formal `TASK-*` / `TST-*` / `EV-*` / freeze  
- 不跑 `just governance-check` / `just release-check` / Stage-0  
- 不引入 fallback / dual reader / 第二套 ProgramV1 decoder  
- 不声称 formal D1–D4 done  
- 改 `ProofForgeV2/**` 必须 `just sbom-package-files-refresh`  
