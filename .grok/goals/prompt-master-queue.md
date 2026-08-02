# Goal — 全工程 backlog 主队列（**drain 直到空 / 硬阻塞**）

> **这就是「用 Goal 跑完全部工程任务」的入口。**
> 续跑必须发生在 **Goal 回合内部**，不要做完几项就当 Goal 完成、把「剩下的」丢回聊天。
>
> ```text
> /goal @.grok/goals/prompt-master-queue.md --budget 8000000
> ```
>
> **若 skeptic 仍 open（DOC-T9-0 无矩阵 commit / DONE_IDS 漏项 / BUILD-5 脏日志）先跑：**
>
> ```text
> /goal @.grok/goals/prompt-skeptic-recovery.md --budget 4000000
> ```
>
> 从指定 ID 续跑（上一会话结束后）：
>
> ```text
> /goal @.grok/goals/prompt-master-queue.md starting at T-1 --budget 8000000
> ```
>
> **历史收口入口（勿重做已 done）：** `prompt-c-2-finish.md`、`prompt-n-2-finish.md`。

---

## OBJECTIVE（读三次）

你是 **ProofForge V2 工程 backlog 执行器**，在 **同一个 Goal** 内串行消费队列。

**成功 = 尽可能 drain 工程 pending 队列**，不是「本会话做满 N 项交差」。

权威：

1. [`.grok/goals/QUEUE.md`](QUEUE.md)
2. [`.grok/goals/slices/<ID>.md`](slices/)
3. [`docs/engineering-backlog.md`](../../docs/engineering-backlog.md)
4. `AGENTS.md` / `RECOVERY.md` / `MIGRATION_MATRIX.md`
5. `docs/roadmap-t8.md`
6. `docs/research/12-target-coverage-matrix.md`
7. Skeptic recovery: [`.grok/goals/slices/SKEPTIC-1.md`](slices/SKEPTIC-1.md) + [`prompt-skeptic-recovery.md`](prompt-skeptic-recovery.md)

**目标**：按 QUEUE 顺序，把 **pending** 工程切片逐个做成 **local commit（不 push）**，回写 backlog，**然后立即做下一项**，直到停止条件。
**非目标**：formal TASK/TST/EV、release-check、Stage-0、「formal 0/27 done」。

---

## ⚠ 启动硬门：Skeptic recovery（在 drain 前）

若下列任一为真，**禁止**直接宣称从 DOC-SPEC-AUDIT / N-* 开干；先闭合 SKEPTIC-1：

1. `DOC-T9-0` 在 backlog 非 done，或 done 但 `git log --oneline -- MIGRATION_MATRIX.md` 自上次 false-done 后**无**对应矩阵扫 commit
2. 上轮 report 的 `DONE_IDS` 漏了 backlog 已 done 的 `B-1d` / `B-1e` / `T9e`
3. BUILD-5 无 clean exit-0 serial log（带 `AssertionError` 的 log 无效）

执行契约：[`slices/SKEPTIC-1.md`](slices/SKEPTIC-1.md)、[`slices/DOC-T9-0.md`](slices/DOC-T9-0.md)。
**DOC-T9-0 完成 = 该 commit 的 file list 含 `MIGRATION_MATRIX.md`**；仅改 backlog/roadmap **不算**。

闭合后打印 `SKEPTIC_RECOVERY: closed`，再进入正常 drain。

---

## 默认模式：`drain`（禁止默认只做 3 项）

| 模式 | 何时 | 行为 |
|---|---|---|
| **`drain`（默认）** | 用户说「全部 / 继续 / 队列 / Goal」或未指定 max_slices | **禁止**因「已做满 3 项」停止。一直做直到下面「硬停止」 |
| **`pilot`** | 用户显式 `max_slices=N` 或 `pilot` / `first wave only` | 最多 N 项后可停，报告 NEXT |

**禁止行为（会判 Goal 失败）**：

- 队列里还有可做 pending，却因「默认 max_slices=3」「进度 5%～15%」「今天够了」结束 Goal
- 把「请用户再开一轮」当作正常完成（预算硬尽除外）
- 未更新 backlog 就宣称 slice done

**允许的硬停止**（仅此）：

1. QUEUE/backlog 中 **无剩余可做** pending（依赖全 blocked / 仅剩 excluded formal）
2. **Token 预算**不足以完成下一项 preflight（报告 `BUDGET_STOP`、`NEXT`、剩余数量与 %）
3. **硬阻塞**：脏 worktree 属他人 WIP、产品决策缺失、工具链无法 pin——写入 backlog `blocked`，`NEXT` 写明
4. 用户在本 Goal 文本里 **显式** `max_slices=N` 且已完成 N

停止后 Goal 完成声明必须是：

- drain 完成：**「工程 QUEUE pending 已清空（或仅剩 blocked/excluded）」** + SHAs；或
- 硬停：**「BUDGET_STOP / BLOCKED，已完成 K 项，剩余 M 项（约 p%），NEXT=…」**

**禁止**声明：「本会话做完 3 项即 Goal 成功」当队列仍有可做项且未 BUDGET_STOP。

---

## 启动协议

1. `git status --short` — 无关脏文件 → **停**（BLOCKED），勿吞他人改动。
2. `git rev-parse HEAD`、`git log -3 --oneline`。
3. 读 QUEUE + backlog：数 **pending 总数**、**已 done 数**、打印
   `PROGRESS: done=D pending=P total=T (~D/T %)`
4. `starting at <ID>` 若给出则从该 ID 起；否则从第一个 pending。
5. **立刻进入循环**；完成一项后 **零停顿** 进入下一项（同一 Goal 回合）。

---

## 单切片执行环（对每个 pending 重复，直到硬停）

### A. Preflight

- 依赖满足（否则 skip 或 blocked）
- 上一切片已 commit，tree 对该切片干净
- `BASE=$(git rev-parse HEAD)`

### B. Implement

**小切片（BUILD/DOC）**：自实现 B1。
**中大切片**：workflow `proof-forge-engineering-slice`（B2）。

B1：

1. RED / 可观察失败
2. 最小实现，守 allowlist
3. focused checks
4. `ProofForgeV2/**` → `just sbom-package-files-refresh`
5. backlog 该 ID → **done**

### C. Review（B1 且有 uncommitted）

workflow `proof-forge-one-slice`；修 P0/P1。

### D. Commit

- 每 ID **一个** local commit
- 禁止 `git add -A` / push
- 干净 tree → **立刻** 选下一 pending（更新 PROGRESS 行）

### E. 记录

```text
DONE <ID> commit=<sha> base=<sha>
PROGRESS: done=D pending=P (~pct%)
NEXT: <id or EMPTY>
```

---

## 并行规则

- Master **默认串行**
- 共享核（Normalize/Reference/Envelope/Check）禁止并行
- leaf 仅 allowlist 零重叠时可选 worktree（非默认）

---

## 明确排除（永不算 drain 成功条件）

| 排除 | 原因 |
|---|---|
| formal TASK-D* / TST-* / EV-* | release |
| C-3 formal Anvil | formal |
| NS-3 全量 IBC | 北极星 |
| `just release-check` 绿 | 主机资格 |

这些 **不计入**「还要做完的工程 pending」进度分母时可单独列出 `EXCLUDED_FORMAL`。

---

## 续跑（预算停后）

用户再开 **同一 Goal 文件**：

```text
/goal @.grok/goals/prompt-master-queue.md starting at <NEXT> --budget …
```

新会话 **不得** 从 BUILD-1 重做已 done；从 NEXT 接着 **drain**。

---

## 当前队列事实（执行时以 backlog 为准）

典型已 done（须全部进 DONE_IDS，**勿漏**）：BUILD-1..9、DOC-1..5、DOC-DEDUP、DOC-SPEC-AUDIT、N-A1、N-A2、N-A3、N-A4、N-1、B-1a..e、T9a–e、T9-0（控制面）、**DOC-T9-0 仅在矩阵 commit 后**、**SKEPTIC-1 仅在三缺口真闭后**。
从 **第一个仍 pending / 可做** 起（当前常见 **T-1**；**C-5** 为 ongoing 不阻塞后续）**继续 drain**。
N-2 脏树若路径均在 N-2 allowlist → **Goal 拥有该 WIP**，禁止当「他人 WIP」停机。

### PROGRESS 计数规则

- `done` / `DONE_IDS`：从 `docs/engineering-backlog.md` 实际 `**done**` 行收集，含 B-1d、B-1e、T9e
- `pending`：backlog 中仍 pending 且未 excluded formal 的工程 ID
- QUEUE.md 的 Status seed **仅导航**；冲突时 **backlog 赢**

---

## 完成后报告模板

```text
# Master queue session report
MODE: drain | pilot(max_slices=N)
HEAD_START: ...
HEAD_END: ...
SKEPTIC_RECOVERY: closed|open|n/a
PROGRESS: done=D pending=P total_engineering=T (~pct%)
DONE_IDS: <comma list — must include B-1d,B-1e,T9e if backlog-done>
COMPLETED:
  - ID @ sha
  - ...
BLOCKED: (none | ID: reason)
BUDGET_STOP: yes|no
NEXT: <id|EMPTY>
PUSHED: no
BACKLOG_UPDATED: yes
```

若 `PENDING>0` 且 `BUDGET_STOP=no` 且 `BLOCKED` 未覆盖全部剩余 → **Goal 未完成，继续做**。
