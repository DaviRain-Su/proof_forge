# `.grok/` — Grok Goal / workflow 入口

**Live index.** 不是 backlog、不是 formal 权威、不是第四份 gap 清单。

冲突时：accepted ADR → PRD → architecture → SPEC → 代码事实 →
[`docs/engineering-backlog.md`](../docs/engineering-backlog.md)。

工程完成面按 **13 implemented + 0 design-only**（ADR-0036，仍 `proposed`）。
accepted PRD Phase-1 文案仍是四目标。cairo / risc0 / sp1 **不在** registry。

---

## 现在用什么

| 要做什么 | 入口 |
|---|---|
| 日常下一刀（13 叶诚实天花板 + B-CALL-SEM 残差） | [`docs/plan/completeness-phased-roadmap.md`](../docs/plan/completeness-phased-roadmap.md) · backlog [§12](../docs/engineering-backlog.md) |
| 等人拍的决策波 | [`docs/plan/remaining-owner-waves.md`](../docs/plan/remaining-owner-waves.md) |
| 新的有界工程切片 | `/workflow proof-forge-engineering-slice` |
| 实现后只读审查 | `/workflow proof-forge-one-slice` |
| 任意有界改动 + 三角审查 + 本地 commit | `/workflow develop-review-commit` |

**不要**再开下面任何 Goal / drain workflow。它们会从 LH-4 或 BUILD-1 重做已完成工作，或走到禁止的 C-3。

---

## 已退役（launch = refuse）

这些 `.rhai` 现在一启动就 `retired` 退出，不再选切片、不改树。

| Workflow / Goal | 为什么退役 |
|---|---|
| `next-wave-runner` · `prompt-next-wave.md` · [`next-wave-queue.md`](next-wave-queue.md) | LH-1…28 + Track F + SYS-S4 **零 pending** |
| `prompt-master-queue.md` · [`goals/QUEUE.md`](goals/QUEUE.md) · `goals/slices/*` | 2026-08-02 工程 drain 历史种子；事实以 backlog 为准 |
| `business-formalization-runner` · `prompt-business-formalization.md` · [`business-formalization-queue.md`](business-formalization-queue.md) | ADR-0034 wave-3′ 已 drain |
| `prompt-skeptic-recovery.md` · `prompt-build-1-2.md` · `prompt-c-2-finish.md` · `prompt-n-2-finish.md` · `prompt-n-a2.md` | 对应切片已 done |
| `noir-acir-ir` / `ir4` / `ir7` / `g3` | Noir ACIR IR-0…IR-7 **idle** |
| `product-surface-ladder` | I0–I3 + MCP-V0 + SDK-V0 已接线 |
| `external-program-v1` · `hello-dapp-catalog` | 外部 ProgramV1 / hello catalog 已接线 |
| `cli-engineering-dist` · `cli-cwd-free` · `author-sdk-and-ci-release` · `pypi-host-sdk` · `release-multiarch-host-sdk` · `release-engineering-0-1-1` | engineering-dist 一次性切片；VERSION 已是 `0.1.1` |
| `reference-target-refinement-audit` | 只读审计已产出；不要当 12-target 现状再跑 |

`goals/slices/*.md` **保留**为已完成切片合同，不是待办。

---

## 仍可 launch（通用，无队列）

| Workflow | 用途 |
|---|---|
| `proof-forge-engineering-slice` | 一个有界工程切片：preflight → 实现 → 审查 → 验证 → 一个本地 commit |
| `proof-forge-one-slice` | 只读三角审查（Goal 已改完、未 commit） |
| `develop-review-commit` | 任意有界改动的同一套审查/验证/本地 commit |

这三条**不会**从退役队列里自动拣 LH/BUILD。调用方必须自己给出切片合同。

禁止：push、formal TASK/TST 标 done、把 `just ci` 写成 hermetic/release、静默扩 accepted PRD、恢复 frontend 监督层。
