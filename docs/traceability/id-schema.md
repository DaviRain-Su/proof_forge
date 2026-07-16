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
一个文件只有一个 primary ID，但可定义多条 FR/INV/TST。ID 区分大小写并只用 ASCII。

机器校验表格中的 definition/reference cell 必须使用一个精确 ID，或使用逗号分隔的精确 ID
列表；禁止 `001..005`、`001/002`、`*`、省略 prefix 或 Milestone shorthand。显示性 prose、
code fence 与示例不作为机器引用来源，避免把解释文字误判成 trace edge。

docs-check 只从以下权威位置收集定义：Markdown primary frontmatter；PRD 的 GOAL/FR/NFR/OOS；
Architecture 的 INV；Task Breakdown 的 TASK；Test Spec catalog 的 TST；Evidence Ledger 的 EV；
source/claim registry JSON 的 SRC/CLM。ADR、SPEC 与 MOD 由各自 primary frontmatter 定义。
requirements matrix 和 task test/evidence columns 只允许引用已定义 ID。

研究 SRC/CLM registry 由 JSON 定义；每个 CLM 必须至少引用一个已存在 SRC。staged claim/source
允许暂未被正文消费，不视为 orphan。docs-check 拒绝定义重复、结构化引用未知、循环
supersession 和 done→missing TST/passed EV。
