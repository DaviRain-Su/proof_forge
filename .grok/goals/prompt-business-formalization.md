# Goal — 业务逻辑形式化主路径（track 1）drain

> **入口（在 Grok Goal 里开，不要只聊天做半截）：**
>
> ```text
> /goal @.grok/goals/prompt-business-formalization.md --budget 8000000
> ```
>
> 续跑（会话断后）：
>
> ```text
> /goal @.grok/goals/prompt-business-formalization.md --budget 8000000
> ```
>
> 或启动 workflow（同一队列）：
>
> ```text
> /workflow business-formalization-runner
> ```
>
> （runner 一次做 **下一项**；要 drain 请用本 Goal 或带 `args.drain=true` 的 multi-fire。）

---

## OBJECTIVE（读三次）

你是 **ProofForge track-1 业务逻辑形式化执行器**。

**成功 = 把** [`.grok/business-formalization-queue.md`](../business-formalization-queue.md)
**里所有 pending/in_progress 切片做成 local commit（不 push）**，并更新队列状态，
**然后立即做下一项**，直到队列清空、预算硬尽、或硬阻塞。

**不是** formal TASK/TST、**不是** 工具内部 metatheory、**不是** MiniAmm 优先、
**不是** 第二非 AMM 实例（deferred）。

权威：

1. `.grok/business-formalization-queue.md`（sole slice order）
2. `docs/adr/0034-preservation-abi.md` D9/D10
3. `AGENTS.md` Active/Next · INV-2 · RECOVERY L1
4. 代码：`PreservationPackagingV1` · `EvenCounterPreservationV1` · `ClosedSubjectPinV1` ·
   `InlineProofCertifierV1` · `ReferenceMachineV1`

**Sole L1 step：** `admitReferenceProgramSliceV1` + `stepReferenceSliceV1`  
**禁止：** 第二 State/Effect/step · MiniAmm 特例 · supersede ADR-0027 · push ·
`git reset --hard` · `git add -A` · formal overclaim

---

## 默认模式：`drain`

| 模式 | 行为 |
|---|---|
| **drain（默认）** | 禁止因「做完 1 项」结束。一直做到队列无 pending / BUDGET_STOP / BLOCKED |
| pilot | 仅当用户写 `max_slices=N` |

**硬停止仅此：**

1. 队列全部 `done`
2. 预算不够 preflight 下一项 → `BUDGET_STOP` + `NEXT=`
3. 无关脏 worktree / 产品决策缺失 → `BLOCKED`
4. 用户显式 `max_slices=N` 且已完成 N

---

## 队列（顺序固定）

先读 `.grok/business-formalization-queue.md` **全部 wave**。Wave1+wave2 应已 done
（EvenCounter packaging/unpin/docs + ZeroCounter data/preserve/product/docs）。
若队列清空：`status=program_complete`；下一业务轨是 MiniAmm P1（**不在** 本 queue 除非
人类新增 wave-3 行）。**不** supersede ADR-0027。

## 队列（历史 wave1 顺序）

| id | 意图 |
|---|---|
| bf-pack-1 | 抽出 program-agnostic packaging → `PreservationPackagingV1`（可能已 done） |
| bf-pack-2 | EvenCounter **消费** packaging，删安全重复 thin alias |
| bf-unpin-1 | 非 pin author 路径：文档 + 必要测试；pin 仅 golden |
| bf-docs-1 | INV-2 / Agents / ADR-0034 / research-023 同步；`just docs-check` |

启动时读队列真值，**跳过已 done**，从第一个 pending/in_progress 开始。

若 worktree 已有本队列的未提交 GREEN 改动：先 verify + **commit 该项**，再 mark done，再继续。

---

## 每项循环（零停顿）

1. `git status` / `HEAD`；无关脏 → BLOCKED  
2. 声明 `SLICE=<id>`；队列标 `in_progress`  
3. 实现最小完整契约（Lean 优先 focused `lake build`）  
4. 触 proof 面：`lake build Tests.Compiler.InlineProofCertifierV1`（或等价）必须 GREEN  
5. 触 `ProofForgeV2/**`：`just sbom-package-files-refresh`  
6. 触 docs：`just docs-check`  
7. `git diff --check`  
8. **local commit only**（`git add -- <paths>`）；更新队列 `done`  
9. **立即**下一项（禁止「请用户继续」）

---

## 切片细则

### bf-pack-1 / bf-pack-2

- 共享模块：`ProofForgeV2/Semantic/PreservationPackagingV1.lean`
- 通用 lemmas：failure arms、returned⇒gate ready、post=pre、uint64 size-from-validate
- EvenCounter 只保留 instance 专用证明；直接 `open`/call packaging
- 不改 Reference 语义机器

### bf-unpin-1

- Pin = closed golden 加速；**不是** 唯一可证通道
- 文档/模块注释 +（若缺）focused 测试：unpinned 程序可对 `subjectProgramV1` /
  `preservation_theorem_of_eq_bytes` 形状挂载，无需 pin 表膨胀
- 不强制新 pin 行

### bf-docs-1

- 诚实更新 backlog INV-2、Agents Next、ADR-0034 实现切片、research-023
- **不** supersede 0027；**不** formal 关闭

---

## 完成声明模板

```text
BUSINESS_FORMALIZATION: drain complete | BUDGET_STOP | BLOCKED
DONE: bf-pack-1=… bf-pack-2=… bf-unpin-1=… bf-docs-1=…
SHAs: …
NEXT: none | <id>
EvenCounter product GREEN: yes/no
ADR-0027 superseded: no
```

---

## 与 workflow / scheduler

| 机制 | 作用 |
|---|---|
| 本 Goal | **首选 drain** 整队 |
| `business-formalization-runner` workflow | 单切片实现→review→commit；可连续 `/workflow` |
| durable scheduler | 断会话后补刀；**不得**替代 Goal 内 drain 义务 |

用户要求「不要来回说继续」时：**默认 drain**，禁止中途把控制权交回聊天。
