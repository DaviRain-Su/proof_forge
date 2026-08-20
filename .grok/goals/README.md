---
id: GROK-GOALS
title: Goal + workflow 入口（退役手册）
status: draft
owner: engineering
updated: 2026-08-20
normative: false
---

# Goal + workflow：不要再 drain

**活索引：** [`.grok/README.md`](../README.md)

工程完成面是 **13 implemented + 0 design-only**。Goal-auto / master / business
drain **全部空**。本目录只留历史合同。

## 现在用什么

| 意图 | 入口 |
|---|---|
| 日常下一刀 | [`docs/plan/completeness-phased-roadmap.md`](../../docs/plan/completeness-phased-roadmap.md) · backlog §12 |
| 人拍项 | [`docs/plan/remaining-owner-waves.md`](../../docs/plan/remaining-owner-waves.md) |
| 新的有界切片 | `/workflow proof-forge-engineering-slice` |
| 只读审查 | `/workflow proof-forge-one-slice` |
| 任意有界改动 + 本地 commit | `/workflow develop-review-commit` |

## 禁止 launch

| 文件 / workflow | 状态 |
|---|---|
| `prompt-next-wave.md` · `next-wave-runner` | **retired**（一启动就退出） |
| `prompt-master-queue.md` · `QUEUE.md` · `slices/*` | 历史种子；不要从 BUILD-1 续跑 |
| `prompt-business-formalization.md` · `business-formalization-runner` | **retired** |
| `prompt-skeptic-recovery.md` · `prompt-build-1-2.md` · `prompt-c-2-finish.md` · `prompt-n-2-finish.md` · `prompt-n-a2.md` | 对应切片已 done |

Goal **不能**自动做完：formal D1–D4、C-3、B-CALL-SEM 绑定、ADR 升格、`just release-check`。

`slices/*.md` 是已完成切片合同，不是待办。
