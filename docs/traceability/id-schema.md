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

引用语法在 Markdown 使用反引号，JSON 使用字符串；docs-check 扫描定义与引用，拒绝
重复定义、未知引用、循环 supersession 和 done→missing EV。研究 SRC/CLM registry
由 JSON 定义，正文只能引用。
