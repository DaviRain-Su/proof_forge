# Goal — Skeptic recovery first, then master drain

> **入口（本轮优先用这个，再回到 master）**
>
> ```text
> /goal @.grok/goals/prompt-skeptic-recovery.md --budget 4000000
> ```
>
> 恢复完成后若预算仍够，**同一 Goal 回合内**无缝切入
> [`.grok/goals/prompt-master-queue.md`](prompt-master-queue.md) 的 drain 环，
> 从真实 NEXT 继续；不够则报告 `NEXT=` 后用户再开 master。

---

## OBJECTIVE

你是 ProofForge 工程队列执行器。上一轮 skeptic **拒绝**了虚假进度。本 Goal **必须先**在仓库内闭合三缺口，**禁止**在聊天侧空谈修复而不 commit。

权威：

1. [`.grok/goals/slices/SKEPTIC-1.md`](slices/SKEPTIC-1.md) ← 总契约  
2. [`.grok/goals/slices/DOC-T9-0.md`](slices/DOC-T9-0.md) ← 矩阵扫  
3. [`docs/engineering-backlog.md`](../../docs/engineering-backlog.md)  
4. `MIGRATION_MATRIX.md`  
5. 可选续跑：[`.grok/goals/prompt-master-queue.md`](prompt-master-queue.md)

---

## PHASE 0 — SKEPTIC-1（强制，不可跳过）

按顺序：

### A. DOC-T9-0
1. `git status --short` 干净；`BASE=$(git rev-parse HEAD)`  
2. `rg` 扫 `MIGRATION_MATRIX.md` 过时 present-tense 句（见 DOC-T9-0 表）  
3. **外科手术**改矩阵 + backlog `DOC-T9-0` → done + SHA  
4. `just docs-check` + `git diff --check`  
5. **一个 local commit**，`git show --stat` **必须含** `MIGRATION_MATRIX.md`  
6. 若只有 backlog 改动无矩阵 → **Goal 失败**，不得宣称 done  

### B. PROGRESS recount
1. 从 backlog 数全部 `**done**` 工程 ID  
2. `DONE_IDS` **必须包含** `B-1d`, `B-1e`, `T9e`（若 backlog 已 done）  
3. 写入 session report / SCRATCH `master-queue-report.md`  

### C. BUILD-5 clean log
1. `just run-deletion-gates`（或 justfile 当前 serial 入口）  
2. 退出码 0；日志无 `AssertionError` / traceback  
3. 保存 `slice-BUILD-5-checks.log`  
4. 若失败 → 在 BUILD-5 allowlist 修并另 commit  

### D. SKEPTIC-1 关闭
报告：

```text
SKEPTIC_RECOVERY: closed
DOC-T9-0: <sha>
BUILD-5_LOG: exit=0 path=...
DONE_IDS: <full truthful list>
PROGRESS: done=D pending=P (~pct%)
```

---

## PHASE 1 — 继续 drain（预算允许时）

同一 Goal 内切换 master 规则：

- 读 backlog 第一个 **pending** 可做项（依赖满足）  
- 典型：`DOC-SPEC-AUDIT` 或 `N-A4` / `N-1`…（以 backlog 为准）  
- 每项一 commit；禁止默认 max_slices=3 停  

硬停：预算 / 脏 tree / 无 pending / 用户 pilot。

---

## 禁止

- 在聊天实现矩阵扫却不走 Goal commit  
- 无矩阵文件变更却标 DOC-T9-0/T9-0 完成  
- DONE_IDS 漏 B-1d/B-1e/T9e  
- BUILD-5 带 traceback 当绿  
- push / formal / release-check  

---

## 完成报告模板

```text
# Skeptic recovery + drain report
MODE: skeptic-first then drain
HEAD_START: ...
HEAD_END: ...
SKEPTIC_RECOVERY: closed|partial
DOC-T9-0_COMMIT: <sha|missing>
MATRIX_IN_COMMIT: yes|no
BUILD-5_EXIT: 0|nonzero
DONE_IDS: ...
PROGRESS: done=D pending=P total=T (~pct%)
COMPLETED: ...
NEXT: ...
BUDGET_STOP: yes|no
PUSHED: no
```
