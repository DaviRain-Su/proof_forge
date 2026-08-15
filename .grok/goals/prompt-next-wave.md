# Goal — 下一波可执行工程 drain（EVM lighthouse + S4）

> **2026-08-15：本 Goal 已退役。** Track A/B 无 `pending`。
> **不要**再执行 `/goal @.grok/goals/prompt-next-wave.md`，**不要** `starting at LH-4`，
> **不要**报告 `NEXT=FORMAL_C3`。下一刀见 [`docs/research/28-project-wide-honesty-audit.md`](../../docs/research/28-project-wide-honesty-audit.md)
> 与 [`AGENTS.md`](../../AGENTS.md) Next task。
>
> 历史入口（已空，仅留档）：
>
> ```text
> /goal @.grok/goals/prompt-next-wave.md --budget 8000000
> ```

---

## OBJECTIVE（读三次）

你是 **ProofForge 下一波工程执行器**。

**成功 = drain** [`.grok/next-wave-queue.md`](../next-wave-queue.md) 里 Track A 然后 Track B 的全部 `pending`。

**不是** formal TASK/TST/EV 完成，**不是** C-3，**不是** 把 Anvil 观察发明成 lossless OutcomeWire，**不是** 替用户拍 B-CALL-SEM / Psy Commit 等产品决策。

权威（冲突时从上到下）：

1. `.grok/next-wave-queue.md`（顺序）
2. `docs/engineering-backlog.md`（事实）
3. `AGENTS.md` / `RECOVERY.md` / ADR-0036
4. `docs/specs/reference-outcome-v1.md` + `docs/specs/evm-outcome-adapter-v1.md`
5. `docs/adr/0031-system-capability-unification.md`（仅 Track B）

**Sole L1 step：** `admitReferenceProgramSliceV1` + `stepReferenceSliceV1`

**禁止：** 第二套 step · 关闭 `TASK-D2-07` / `TST-SEM-002/003` / `C-3` · Anvil↛OutcomeWire 变 lossless · 新增 `TASK-*` · push · `git add -A` · `reset --hard` · `commit --amend` · 恢复 `ProofInstances/` / pin

---

## 默认模式：`drain`

| 模式 | 行为 |
|---|---|
| **drain（默认）** | 禁止因「做完 1 项」结束。做到 Track A+B 无 pending，或硬停 |
| pilot | 仅当用户写 `max_slices=N` |

**硬停止仅此：**

1. Track A+B 全部 `done` / `blocked`（Track C 不算失败）
2. 预算不够下一项 preflight → `BUDGET_STOP` + `NEXT=`
3. 无关脏 worktree / 产品决策缺失 → `BLOCKED`
4. 用户显式 `max_slices=N` 且已完成 N

停止后必须报告模板（见文末）。**禁止**把「请用户再开一轮」当正常完成（预算硬尽除外）。

---

## 与 workflow 的配合

对 **LH-4…LH-7** 与 **SYS-S4-***：优先用工作流工具启动已保存的 `next-wave-runner`（一次一项：select→implement→review→verify→local commit）。

该 workflow 自己读 `.grok/next-wave-queue.md`。Goal 在它 `complete` 之后：

1. 读 queue + `git log -1`
2. 确认该 id 已 `done` 且 tree 干净
3. **零停顿**进入下一项（再 launch 同一 workflow，或自实现更小的文档行）

不要在聊天里复述「要不要继续」。

小切片（只改 backlog/queue 一行且无产品代码）可在 Goal 内做，但仍要 focused check + 单独 commit。

---

## 启动协议

1. `git status --short`。无关脏文件 → **停**（BLOCKED）。
2. `git rev-parse HEAD`、`git log -3 --oneline`。
3. 读 queue + backlog。打印  
   `PROGRESS: A+B done=D pending=P blocked=B`
4. `starting at <ID>` 若给出则从该 ID；否则第一个 Track A/B `pending`。
5. 立刻进入循环。

---

## 单切片环

### A. Preflight

- 依赖已 done（LH-5 依赖 LH-4；SYS-S4-* 依赖 SYS-S4-SHARED；Track B 不得与未完成 Track A 并行改同一共享核）
- tree 对该切片干净，或脏路径全在 allowlist
- `BASE=$(git rev-parse HEAD)`

### B. Implement

优先 `/workflow next-wave-runner`。  
若自实现：RED → 最小实现 → focused checks → 触 `ProofForgeV2/**` 则 `just sbom-package-files-refresh`。

LH-4/5 必须保持：`try_mint_outcome_wire_from_observation` 仍 fail closed。  
LH-6/7 只加 **engineering** pin / suite；**不得**改 `docs/04-task-breakdown.md` 把 TASK/TST 标 done。

### C. Review

workflow 已含三角 review。自实现时跑 `proof-forge-one-slice` 或等价只读审查；修 P0/P1。

### D. Commit

- 每 ID **一个** local commit
- 禁止 `git add -A` / push / amend / force
- 回写 queue + backlog 一行事实
- 干净 tree → 下一项

### E. 记录

```text
DONE <ID> commit=<sha> base=<sha>
PROGRESS: A+B done=D pending=P
NEXT: <id or EMPTY>
```

---

## 明确排除

| 排除 | 原因 |
|---|---|
| formal TASK-D* / TST-* / EV-* 标 done | release / formal 轴 |
| C-3 / Anvil lossless Outcome | spec 与 ADR-0036 |
| B-CALL-SEM、B-COMMIT-ZK、D3-E8、QUINT-2、DOC-JUST-CONTROL | 产品决策 |
| 重做 SYS-S2 NEAR/CW blockHeight runtime | 代码已有 harness |
| NS-2 / EXT-CRYPTO | 北极星 / catalog |

---

## 完成后报告模板

```text
# Next-wave session report
MODE: drain | pilot(max_slices=N)
HEAD_START: ...
HEAD_END: ...
PROGRESS: done=D pending=P blocked=B
DONE_IDS: ...
COMPLETED:
  - ID @ sha
BLOCKED: (none | ID: reason)
BUDGET_STOP: yes|no
NEXT: <id|EMPTY|FORMAL_C3>
PUSHED: no
QUEUE_UPDATED: yes
FORMAL_UNCHANGED: yes
```

`NEXT=FORMAL_C3` 仅当 Track A drain-complete 且下一步只能走 formal 仪式。
