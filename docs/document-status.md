---
id: DOC-STATUS
title: 文档生命周期与权威索引
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# 文档生命周期与权威索引

## 状态含义

| 状态 | 含义 |
|---|---|
| `not_started` | 仅有模板或计划，没有执行事实 |
| `draft` | 信息不完整，不能作为后续实现输入 |
| `proposed` | decision-complete 候选，等待正式评审 |
| `in_review` | 评审窗口已打开，允许记录意见但不可默认为接受 |
| `accepted` | 有 owner、日期和批准记录，可作为规范 |
| `superseded` | 被明确 successor 替代，保留历史路径 |
| `archived` | 只保留证据价值，不参与当前决策 |

## 当前索引

| 文档族 | 当前文档 | 状态 | 权威范围 |
|---|---|---|---|
| 商业验证 | [`00-business-validation.md`](00-business-validation.md) | `draft` | 市场假设与 Go/No-Go |
| 产品 | [`01-prd.md`](01-prd.md) | `proposed` | 用户需求、范围、成功标准 |
| 架构 | [`02-architecture.md`](02-architecture.md) | `proposed` | 系统边界、不变量、数据流 |
| 技术规格 | [`03-technical-spec.md`](03-technical-spec.md) + `specs/` | `proposed` | API、schema、错误和版本 |
| 实施计划 | [`04-task-breakdown.md`](04-task-breakdown.md) | `proposed` | 任务顺序与任务验收 |
| 测试 | [`05-test-spec.md`](05-test-spec.md) | `proposed` | 验收和证据要求 |
| 实现事实 | [`06-implementation-log.md`](06-implementation-log.md) | `draft` | alpha 实际命令、结果与限制 |
| 最终评审 | [`07-review-report.md`](07-review-report.md) | `not_started` | 发布判断 |

## 权威优先级

规范意图冲突时：accepted ADR → accepted PRD → accepted architecture →
accepted technical/module spec → accepted test spec。当前事实冲突时：代码和实际制品
→ 可复现 gate/evidence → implementation log。调研冲突时：官方 primary source →
verified claim → synthesis。`proposed` 文档不能覆盖已接受决策。

## 接受与废弃

- 接受记录必须包含 approver、日期、评审 commit 和已关闭意见。
- 修改 accepted 行为必须先增加 ADR；破坏性变化还需 migration 和版本提升。
- supersede 时旧文件只加状态横幅与 successor，不改写历史正文。
- 文档检查必须拒绝重复 ID、死链接、accepted TODO、无来源事实、无 successor 的
  superseded 状态以及未闭合的 normative trace。
