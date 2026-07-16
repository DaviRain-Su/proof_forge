---
id: TRACE-ID-001
title: 稳定 ID 规则
status: proposed
owner: quality
updated: 2026-07-15
normative: true
---

# 稳定 ID 规则

| Prefix | 对象 | 格式示例 |
|---|---|---|
| `GOAL` | 产品目标 | `GOAL-001` |
| `BV` | 商业假设/实验 | `BV-001` |
| `FR` / `NFR` / `OOS` | 需求/质量/非目标 | `FR-001` |
| `INV` | 架构不变量 | `INV-001` |
| `ADR` | 决策 | `ADR-0001` |
| `SRC` / `CLM` | 来源/原子结论 | `SRC-0001` |
| `SPEC` | normative spec | `SPEC-LANG-001` |
| `CAP` | capability semantic contract | `CAP-STATE-MAP-001` |
| `MOD` | 模块规格 | `MOD-SOURCE-001` |
| `TASK` | ≤4h 实施任务 | `TASK-D2-01` |
| `TST` | 测试/验收 | `TST-SEM-001` |
| `EV` | 一次不可变证据 | `EV-20260715-0001` |
| `REL` | release decision | `REL-0.1.0-alpha.1` |
| `PF-*` | 稳定诊断 | `PF-REQ-UNSUPPORTED` |

ID 分配后永不复用；删除对象标记 retired，保留 tombstone/successor。文档重命名不改 ID。
一个文件只有一个 primary ID，但可定义多条 FR/INV/TST。除 `REL-<SemVer>` 使用 SemVer 的
数字、点和合法 prerelease 字符外，ID 区分大小写并只用大写 ASCII prefix/segment。
Evidence ID 固定为 `EV-YYYYMMDD-NNNN`，不得使用任意 `EV-*` label 代替不可变 evidence identity。

机器校验表格中的 definition/reference cell 必须使用一个精确 ID，或使用逗号分隔的精确 ID
列表；禁止 `001..005`、`001/002`、`*`、省略 prefix 或 Milestone shorthand。显示性 prose、
inline/fenced code、HTML comment 与示例不作为机器引用来源，避免把解释文字误判成 trace edge。

docs-check 只从以下权威位置收集定义：Markdown primary frontmatter；Business Validation 的 BV；
PRD 的 GOAL/FR/NFR/OOS；Architecture 的 INV；Task Breakdown 的 TASK；Test Spec catalog 的 TST；
Evidence Ledger 的 EV；source/claim registry JSON 的 SRC/CLM。ADR、SPEC 与 MOD 由各自 primary
frontmatter 定义。requirements matrix 和 task dependencies/test/evidence columns 只允许引用
已定义的精确 ID；依赖图不得自环或成环，`in_progress|done` task 的全部 task dependencies 必须
已经 `done`。task 的非任务文档前置条件使用精确 `DOCUMENT-ID@accepted` 逗号列表；允许
`in_progress` 收集 pre-acceptance evidence，但 task 变为 `done` 前必须逐项满足。

Evidence Ledger 的 canonical columns 是
`ID | Task | Tests | Grade | Gate / command | Result | Scope and limitation`，不得省略、改名或增加
替代列。`Grade` 只允许 `development|bootstrap|formal`。绑定 EV 的 `Task` 必须是一个精确 `TASK-*`，
`Tests` 必须是该 task 拥有的一个或多个精确 `TST-*`；不绑定任务的历史 observation 必须同时写
`Task=—` 与 `Tests=—`。done task 引用的每个 EV 都必须绑定该 task，所有引用 EV 的 Tests 并集
必须覆盖 task 的全部 Tests；`TASK-A0-*` 只能由 development EV 关闭；bootstrap grade 只允许
`TASK-D0-01/02`，作为 binder 建立前受 accepted prerequisite、依赖和评审约束的显式信任根；
其他 task 只能由 formal EV 关闭。formal grade 仍须通过正式 evidence-set binder 对不可变 EV JSON 的候选、gate、artifact
与新鲜度绑定，不能由 ledger 文本自行声明；binder 接入前 docs-check 拒绝所有 `formal` 行，
不得用自声明解除该 bootstrap 边界。requirements matrix 的 Evidence 在正式闭合模型
落地前只能是精确 `specified`；其他值一律 fail closed。

研究 SRC/CLM registry 由 JSON 定义；每个 CLM 必须至少引用一个已存在 SRC。staged claim/source
允许暂未被正文消费，不视为 orphan。docs-check 拒绝定义重复、结构化引用未知、循环
supersession 和 done→missing TST/passed EV。
