# Goal — 全工程 backlog 主队列（串行消项）

> **这就是「用 Goal 跑完全部工程任务」的入口。**  
> 不要期望一个 Goal 在一轮里做完 60 项；正确模式是：  
> **一个 `/goal` 会话 = 按 QUEUE 顺序连续消项，每项独立 commit，直到预算耗尽 / 阻塞 / 队列空。**
>
> ```text
> /goal @.grok/goals/prompt-master-queue.md --budget 8000000
> ```
>
> 或从指定 ID 开始：
>
> ```text
> /goal @.grok/goals/prompt-master-queue.md starting at BUILD-1 --budget 8000000
> ```

---

## OBJECTIVE

你是 **ProofForge V2 工程 backlog 执行器**。仓库根目录工作。  
权威队列：

1. [`.grok/goals/QUEUE.md`](QUEUE.md) — 切片顺序与 ID 列表  
2. 每项契约：[`.grok/goals/slices/<ID>.md`](slices/)  
3. 状态回写：[`docs/engineering-backlog.md`](../../docs/engineering-backlog.md)  
4. 控制面：`AGENTS.md`、`RECOVERY.md`、`MIGRATION_MATRIX.md`  
5. 宽度专项：`docs/roadmap-t8.md`  
6. Op 矩阵：`docs/research/12-target-coverage-matrix.md`

**目标**：按 QUEUE 顺序，把状态为 pending 的工程切片逐个做成 **local commit（不 push）**，并更新 backlog。  
**非目标**：formal TASK/TST/EV、release-check、Stage-0、整仓「formal 0/27 → done」。

---

## 启动协议（每一会话第一件事）

1. `git status --short` — 若有无关脏文件，**停**并报告，勿吞掉他人改动。  
2. `git rev-parse HEAD` 与 `git log -3 --oneline`。  
3. 读 `QUEUE.md` + `docs/engineering-backlog.md` 推荐序与已 done 项。  
4. 选定 **下一个** 可做 ID：  
   - 按 QUEUE 顺序；  
   - skip 已 done；  
   - 若依赖未完成 → skip 到下一个可做，或阻塞并说明；  
   - **Normalize/Typed/Semantic 共享核**（ID 以 N-、R-、T-1/2/3、N-A、N-BYTES 为主）**严禁**与另一共享核切片并行。  
5. 打开 `slices/<ID>.md` 作为该切片契约。

可选参数：`starting at <ID>` / `max_slices=N`（默认本会话最多 **3** 个完整切片，防预算爆）。  
若用户说 **「所有的」** 且预算足够：`max_slices` 可提到 10，但仍一项一项 commit。

---

## 单切片执行环（对每一个 ID 重复）

### A. Preflight

- 依赖是否满足（代码/backlog 事实，不是愿望）。  
- 工作区在切片开始时应对该切片干净（上一切片已 commit）。  
- 记下 `BASE=$(git rev-parse HEAD)`。

### B. Implement（二选一）

**B1 — 自实现（小切片 / BUILD / DOC 推荐）**

1. 先写失败测试或最小可观察 RED（文档切片可改为「矩阵错误句」清单）。  
2. 最小实现，路径不超出 `slices/<ID>.md` allowlist。  
3. 跑 focused checks + 适用 verification。  
4. 改 `ProofForgeV2/**` ⇒ `just sbom-package-files-refresh`。  
5. 更新 `docs/engineering-backlog.md` 该 ID → done（+ 日期）。

**B2 — 整包 workflow（中大切片推荐）**

用 **workflow 工具**（不是假装用户 slash）：

```text
name: proof-forge-engineering-slice
args: <复制 slices/<ID>.md 内 JSON，按需删 verification 里过重项时须在报告说明>
```

等待完成；若 `blocked` → 读 report → 修或标记 backlog blocked → **不要** 假装 done。

### C. Review

若 B1 自实现且已有 uncommitted diff：

```text
name: proof-forge-one-slice
args: {
  "slice": "<ID>",
  "base_commit": "<BASE>",
  "task_prompt": "<objective 一句话>",
  "changed_files": [ ...exact paths... ]
}
```

有 P0/P1 → 修 → 重验。

### D. Commit

- 一个切片 **一个** local commit（消息用 slice 文件建议或 conventional）。  
- 禁止 `git add -A`；逐文件 `git add -- path`。  
- **禁止 push**。  
- `git status` 应干净后再进入下一 ID。

### E. 记录

在会话笔记中追加：

```text
DONE <ID> commit=<sha> base=<sha> checks=...
```

---

## 会话停止条件（满足任一则停止并报告）

1. `max_slices` 已完成。  
2. QUEUE 中无剩余可做项（或仅剩依赖未来决策的 blocked）。  
3. 共享核冲突 / 产品决策缺失 / 工具链不可 pin → 写入 backlog `blocked` 原因。  
4. Token 预算不足完成下一切片 preflight。  
5. `just ci` 或关键门禁持续失败且非「环境缺工具可跳过」。

**Goal 完成声明**（给 host 核验）只能是：

- 「本会话完成了 ID 列表 …，commit SHAs …，QUEUE/backlog 已更新，未 push」；  
- **不能**是「整个 ProofForge formal 完成」或「60 项全 done」除非 QUEUE 真的清空且证据可复现。

---

## 并行规则（leaf only）

仅当当前选中项文件 allowlist **完全不重叠** 时，才可考虑 worktree 并行 leaf（B-1d/B-1e 等）。  
**Master Goal 默认串行**，更简单、更安全。  
禁止并行：任何 `NormalizeV1` / `ReferenceV1` / `EnvelopeV1` / `CheckV1` 共享核。

---

## 明确排除（永不作为本 Goal 成功标准）

| 排除 | 原因 |
|---|---|
| formal TASK-D* / TST-* / EV-* | release 轴 |
| C-3 formal Anvil differential | formal |
| NS-3 全量 IBC | wontfix-until-NS-1 + crypto |
| `just release-check` 绿 | 主机资格 |

---

## 推荐本会话默认起点（2026-08-02）

```text
1. BUILD-1 → BUILD-2 → BUILD-6   （反馈循环）
2. N-A2                           （Normalize 主轴）
3. DOC-2 或 B-1d/B-1e             （矩阵/边界，与 Normalize 不冲突时可交错）
```

已 done 勿重做：DOC-1/4/5、T9a–d、B-1a/b/c、T9c* 等（以 backlog 为准）。

---

## 完成后报告模板

```text
# Master queue session report
HEAD_START: ...
HEAD_END: ...
COMPLETED:
  - BUILD-1 @ abc123
  - BUILD-2 @ def456
BLOCKED: (none | ID: reason)
NEXT: N-A2
PUSHED: no
BACKLOG_UPDATED: yes
```
