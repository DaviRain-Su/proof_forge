---
id: GOV-TASK-FREEZE-001
title: 全局任务冻结协议
status: proposed
owner: quality
updated: 2026-07-17
normative: true
---

# 全局任务冻结协议

本文件对**全部** `TASK-*` 生效，不限于 `TASK-D0-01`。  
目标：禁止“执行中不断扩大完成面”导致任务永不 `done`。

权威优先级：本协议约束任务调度与完成判定；技术语义仍以 accepted ADR/spec 为准。  
与 [`change-control.md`](change-control.md)、[`authority.md`](authority.md) 并用。  
任务表权威：[`../04-task-breakdown.md`](../04-task-breakdown.md)。  
`AGENTS.md` 只镜像当前指针，不得另立完成条件。

## 1. 问题与原则

| 禁止模式 | 允许模式 |
|---|---|
| 改当前 `in_progress` 任务的输出/Tests/前置来继续干 | 修实现以满足**已冻结**的完成包 |
| 发现缺口就回填进同一任务描述 | 溢出到新 `TASK-*`、backlog 或标 `blocked` |
| 由 checkpoint / agent 自动递增 task ID | 先在任务表说明理由并评审后再增行 |
| `done` 后靠改描述吞新范围 | 新范围 = 新任务 + 新 TST + 新 EV |
| 用 pre-acceptance EV 冒充 formal done | grade 与 task 关闭规则按 traceability 执行 |

**原则 TFP-001（完成面守恒）**：任务一旦进入执行态，其完成面字节与语义不得变胖。  
**原则 TFP-002（溢出外置）**：新能力、新对象、新依赖、新 TST 不得并入执行中任务。  
**原则 TFP-003（全局一致）**：A0 / D0 / D1…Dn 与任何未来 milestone 同一套规则。  
**原则 TFP-004（机器可拦）**：最终须由 docs-check（或等价门禁）拒绝违规；规则生效不依赖口头自觉。

## 2. 任务生命周期与可变性

状态仅允许：`pending` | `in_progress` | `blocked` | `done`。  
同一时刻全局最多一项 `in_progress`。

| 状态 | 可改任务行完成面？ | 说明 |
|---|---|---|
| `pending` | 可以（C1+ 评审） | 未开工可拆分、改措辞、改依赖 |
| **进入 `in_progress` 的瞬间** | **完成包必须已写入并冻结** | 见 §3；无冻结包不得开工 |
| `in_progress` | **禁止** | 只允许实现、测试、写 log/EV；描述/Tests/Prerequisites/Dependencies 完成语义锁定 |
| `blocked` | 禁止变胖；可改 blocker 说明 | 解除 blocker 后回到冻结包，不得借机扩 scope |
| `done` | 禁止 | 仅 C0 错字；行为变更走 ADR + 新 task |

### 2.1 完成面（Completion Surface）定义

下列任一变更均视为**完成面变更**（对 `in_progress`/`done` 非法）：

1. **输出（Output）** 语句语义扩大或增加交付物  
2. **Tests** 单元格增删 `TST-*`  
3. **Dependencies** 增加新的完成依赖（放宽依赖需 Quality 书面例外）  
4. **Prerequisites** 增加新的 `DOCUMENT-ID@accepted` 或其他非任务前置  
5. **Done 含义** 在正文、TST、gate-catalog、AGENTS checkpoint 中新增“还必须…”  
6. 将本属其他 task 的 work item 并入当前 task 的验收叙述

下列**不算**完成面变更（允许）：

- C0 错字、断链修复且不改语义  
- implementation log / evidence ledger **追加**事实  
- 在**不改变 Tests 集合**前提下修复测试实现或 flaky  
- 规格歧义导致无法验收：标 `blocked`，先改规格再重开或新 task（见 §5）

## 3. 冻结完成包（Freeze Package）

任何任务从 `pending` → `in_progress` 前，必须在任务表或附录中具备**冻结完成包**。  
推荐写在 `docs/04-task-breakdown.md` 的任务专节，或 `docs/governance/task-freeze-packages/<TASK-ID>.md`；  
至少可被 docs-check 定位到精确 `TASK-*`。

### 3.1 强制字段

| 字段 | 要求 |
|---|---|
| `taskId` | 精确一个 `TASK-*` |
| `frozenAt` | `YYYY-MM-DD` |
| `freezeCommit` | 40 位小写 hex；冻结生效的基线 commit（或“本 PR merge commit”） |
| `output` | 一句话输出；与任务表 Output 列**逐字一致** |
| `tests` | 精确 `TST-*` 列表；与任务表 Tests 列**集合相等** |
| `dependencies` | 精确 `TASK-*` 或 `—`；与表一致 |
| `prerequisites` | 精确 `DOC@accepted` 列表或 `—`；与表一致 |
| `inScope` | 3–12 条可验收子弹 |
| `outOfScope` | 3–12 条明确不做；防止回填 |
| `doneWhen` | 可判定布尔条件（命令/证据/grade） |
| `overflowPolicy` | 溢出默认去向：新 task ID 建议或 backlog 标签 |
| `maxCalendarDays` | 建议上限（默认 3）；超时强制 §6 triage |
| `maxCommits` | 建议上限（默认 20 个 task-owned commits）；超时强制 §6 |

### 3.2 冻结瞬间规则

1. 将状态改为 `in_progress` 的同一变更集中，完成包必须齐全。  
2. 冻结后，任务表该行的 Output / Dependencies / Prerequisites / Tests 四列与完成包锁定字段必须持续一致。  
3. AGENTS `Active task` 只能引用该 `TASK-*` 与已冻结 output 摘要，**不得**追加新完成条件。  
4. 不得用“补一个 boundary / freeze 又一个 object”改写 `doneWhen`。

## 4. 新发现的唯一合法去向

执行中或评审中发现缺口时，**只允许**下列处置：

| 代号 | 条件 | 动作 |
|---|---|---|
| R1 实现缺口 | 冻结包已覆盖 | 修代码/文档实现；不改完成面 |
| R2 规格歧义 | 无法判断对错 | task → `blocked`；先改 spec/ADR 并重审；再按冻结包继续或废止重建 |
| R3 范围不足 | 需要更大能力 | **新** `TASK-*`（pending）+ 新/扩展 `TST-*`；当前任务仍按原包关闭或 blocked |
| R4 拆分错误 | 单任务无法 ≤ 约定工时 | 停工；经 Quality+Architecture 批准后拆分为多个 pending；**原 in_progress 不得直接改胖**，应 `blocked` 或 done-with-narrow-success 后开新任务 |
| R5 外部前置 | host/工具/人审不可控 | 保持 `blocked` 或维持 Prerequisites；**禁止**把外部系统实现塞进当前 task 完成面 |

**非法 R0**：修改当前 `in_progress`/`done` 任务描述或 Tests 以吸收新范围。

新增 milestone 行（新 `TASK-D*-*` / 新 A0）必须：

1. 在 `04-task-breakdown.md` 说明**为何现有任务不能承载**；  
2. 不得由 `Next task` 或 agent checkpoint **自动**递增；  
3. A0 已冻结到 `TASK-A0-20`：禁止再增 `TASK-A0-*`；  
4. 每个 Milestone 的 **task ID 集合**在 milestone freeze 后禁止静默增加（§7）。

## 5. 与变更控制 / 规格的关系

- 实现暴露规格错误：遵守 change-control：**停实现 → blocked → 修订规格 → 再实现**。  
- 规格修订若迫使完成面变化：  
  - 若任务仍 `in_progress`：要么 (a) 废止本任务为 `blocked` 并开替代 task，要么 (b) Quality Owner 记录 **Freeze Exception**（§8）后替换完成包并重置 `frozenAt`/`freezeCommit`（视为重新开工）。  
  - 禁止无 exception 的静默改行。  
- pre-acceptance / alpha 证据可以在正式依赖未满足时收集，但**不得**把 formal task 标 `done`，也不得因此扩写 formal 完成面。

## 6. 超时与强制 triage

当 `in_progress` 任务满足任一条件，必须在 24h 内做 triage 记录（implementation log 或 review note）：

- 日历超过 `maxCalendarDays`  
- task-owned commits 超过 `maxCommits`  
- 完成包字段与任务表行不一致  
- 连续新增与 `outOfScope` 冲突的“边界冻结”提交

Triage 结论仅四选一：

1. **Close**：满足 `doneWhen` → `done`  
2. **Split**：`blocked` + 新 pending 任务  
3. **Block**：外部/规格前置  
4. **Exception**：§8 书面 freeze exception（有时限）

禁止第五项：无视超时继续加 scope。

## 7. Milestone 集合封顶

| Milestone | 当前封顶策略 |
|---|---|
| A0 | **已冻结**：`TASK-A0-01`…`TASK-A0-20`；禁止新增 |
| D0 | **当前集合** `TASK-D0-01`…`TASK-D0-07` 为执行基线；新增 D0 行视为 milestone 变更，需 Architecture + Quality 批准并记 ADR 或 governance 修订 |
| D1–D8 | 以 `04-task-breakdown.md` 现表为基线；新增行同 D0 变更级别 |
| 未来 Dx | 开 milestone 时一次性写入任务集合并声明 freeze；之后同规则 |

Milestone 封顶**不**阻止把过胖任务**拆出**到新 milestone；拆出必须新 ID，不得改写已 `done` 历史行的完成语义。

## 8. Freeze Exception（唯一合法扩面）

仅 Quality Owner（语义相关加 Architecture Owner）可批准。  
必须记录：

- `taskId`、原 `freezeCommit`、新 `freezeCommit`  
- 扩面原因、用户/安全影响  
- 新增/删除的 Tests  
- 时限（默认 ≤ 48h）与回滚：到期未 done 则强制 Split/Block  
- review link 或 commit

无 exception 记录的完成面 diff，docs-check / review 必须 fail closed。

## 9. 机器强制（分阶段）

| 阶段 | 检查 | 状态 |
|---|---|---|
| M0 | 本文件 + 任务表引用 + 人工 review 按清单 | **生效** |
| M1 | docs-check：至多一个 `in_progress`；A0 集合冻结；A0/D0–D8 ID 集合相对 [`task-set.lock.json`](task-set.lock.json) exact | **生效**（`PF-DOC-TASK-SET-LOCK` / 既有 active/A0 规则） |
| M2 | docs-check：每个 `in_progress` 必须有 `task-freeze-packages/TASK-*.json`，且 Output/Tests/Dependencies/Prerequisites 与任务表行一致 | **生效**（`PF-DOC-TASK-FREEZE`） |
| M3 | CI 对完成面 diff 无 exception 则失败 | 待实现（可由 M1+M2 在 docs-check/CI 中近似覆盖） |

M3 未单独落地前，**§2–§6 与 M0–M2 仍为规范**；不得以“更高阶段未实现”为由违反。

Lock 文件：`docs/governance/task-set.lock.json`（`schemaVersion: 1`，`milestones` → exact `TASK-*` 列表）。  
完成包目录：`docs/governance/task-freeze-packages/TASK-*.json`。  
Milestone 增行必须同变更更新 lock，并经 Architecture + Quality 批准。

## 10. Agent / 人类执行清单

开工前：

1. 确认依赖 `done`、Prerequisites 策略（可 pre-acceptance 但不可假 done）  
2. 写齐冻结完成包  
3. 唯一 `in_progress`  
4. 先有失败验收（TST）再实现  

执行中：

5. 不改任务行完成面  
6. 新缺口走 R1–R5  
7. 触碰超时 → triage  

关闭时：

8. Tests 全覆盖且 EV grade 符合 trace 规则  
9. Prerequisites 在 `done` 前满足  
10. log 记录 commit、命令、限制、Next（仅下一 **pending** 合法任务）

## 11. 首个应用实例：`TASK-D0-01`

### 11.1 Freeze Exception `FX-2026-07-17-D0-01`

| 字段 | 值 |
|---|---|
| 原因 | 原完成面把 candidate-external protected production positive 与 pure consumer 绑死；在 producer/Stage-0/protected service 未实现时，规范要求任何 bootstrap/`done` 永久 zero-closure，导致 D0-02+ 无法开工 |
| 批准 | Quality + Architecture（本仓库执行记录；reviewLink 指向同日 closeout commit） |
| 时限 | 一次性；关闭 D0-01 后不得再用同类例外吞 D0-02+ 范围 |
| 变更 | 重置 D0-01 完成面：done = docs-check + pure consumer + Phase1–3 accepted + pure-consumer bootstrap attestation；protected production positive **移交 `TASK-D0-04`**，缺失时继续 fail closed，但不阻塞 D0-01 `done` |
| 回滚 | 若 attestation 伪造或 pure consumer 回退，docs-check 拒绝 bootstrap EV 并需 reopen D0-01 |

### 11.2 现行完成包（exception 后）

| 字段 | 值 |
|---|---|
| `taskId` | `TASK-D0-01` |
| `frozenAt` | `2026-07-17` |
| `freezeCommit` | 见 `task-freeze-packages/TASK-D0-01.json`（exception 重置） |
| `output` | 与任务表 Output 列一致（pure consumer 关闭；protected production deferred） |
| `tests` | `TST-DOC-001` |
| `dependencies` | `—` |
| `prerequisites` | `PHASE-1@accepted`, `PHASE-2@accepted`, `PHASE-3@accepted` |
| `doneWhen` | (a) docs-check + pure-consumer self-test 绿；(b) Phase 1–3 accepted；(c) `docs/governance/bootstrap-closure/TASK-D0-01.attest.json` 有效且 bootstrap EV `EV-20260717-0028` passed；(d) 完成面与 freeze package 一致 |
| `outOfScope` | Stage-0 handoff / protected RPC production positive / D0-04 six-item activation / formal evidence-set binder |

**状态：** exception 路径下 `TASK-D0-01` → `done`。

### 11.3 Freeze Exception `FX-2026-07-17-D0-02`

| 字段 | 值 |
|---|---|
| 原因 | D0-02 的 Lake/package isolation 已 development 绿，但全局规则要求 bootstrap TaskApproval/authenticated receipt 才能 `done`；该基建属 D0-04，未实现则永久 blocked，阻断 D0-03+ |
| 批准 | Quality + Architecture（本仓库 closeout 记录） |
| 时限 | 一次性；不得自动推广到 D0-03..06 |
| 变更 | done = `v2-isolation`/`ci` + package-boundary attest + bootstrap EV；signed approval/receipt **移交 D0-04** |
| 回滚 | 撤销 attest 后 docs-check 拒绝 D0-02 bootstrap EV，需 reopen |

**状态：** `TASK-D0-02` → `done`；Active = `TASK-D0-03`。

## 12. 违规处理

| 违规 | 处理 |
|---|---|
| `in_progress` 完成面被改胖 | review 拒绝；回滚描述；必要时 exception 或 split |
| 自动新增 A0/Dx 行 | docs-check/review fail；删除或补 milestone 批准 |
| 用 done 任务吞新范围 | 开新 task；旧 EV 不覆盖新 TST |
| 超时无 triage | Quality 可将任务强制 `blocked` 直到 triage |

## 13. 修订本协议

本文件变更类比为 change-control **C2**（影响全部任务完成判定）：  
Architecture + Quality 批准；更新 `updated`；若收紧机器强制，同步 test-spec 中 docs-check 相关 TST 或独立 chore task。  
不得在无批准时用“临时例外”架空 §2–§4。
