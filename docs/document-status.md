---
id: DOC-STATUS
title: 文档生命周期与权威索引
status: proposed
owner: architecture
updated: 2026-07-19
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
| 产品 | [`01-prd.md`](01-prd.md) | `accepted` | 用户需求、范围、成功标准 |
| 架构 | [`02-architecture.md`](02-architecture.md) | `accepted` | 系统边界、不变量、数据流 |
| 技术规格 | [`03-technical-spec.md`](03-technical-spec.md) + `specs/` | `accepted` | `03-technical-spec.md`及其他accepted specs的API/schema/错误/版本；当前`SPEC-TASKQUAL-001` C3 amendment为`in_review`并明确排除在accepted aggregate外 |
| 实施计划 | [`04-task-breakdown.md`](04-task-breakdown.md) | `accepted` | 任务顺序与任务验收 |
| 测试 | [`05-test-spec.md`](05-test-spec.md) | `in_review` | 验收和证据要求；ADR-0021 C3 amendment审核中，旧accepted批准保留于Git历史且当前不得作为新v2 authority |
| 实现事实 | [`06-implementation-log.md`](06-implementation-log.md) | `draft` | alpha 实际命令、结果与限制 |
| 最终评审 | [`07-review-report.md`](07-review-report.md) | `not_started` | 发布判断 |

## 权威优先级

规范意图冲突时：accepted ADR → accepted PRD → accepted architecture →
accepted technical/module spec → accepted test spec。当前事实冲突时：代码和实际制品
→ 可复现 gate/evidence → implementation log。调研冲突时：官方 primary source →
verified claim → synthesis。`proposed` 文档不能覆盖已接受决策。

2026-07-20 authority amendment的**历史accepted revision**输入为`ADR-0020`、当时的
`SPEC-TASKQUAL-001`与`GOV-TASKQUAL-BOOTSTRAP-001`；批准来源是Amp thread
`T-019f7dea-e600-77ea-8884-9f35f81f747d`，其reviewCommit为批准时current HEAD。当前工作树中的
`SPEC-TASKQUAL-001`因ADR-0021 C3正文修订已转`in_review`，不再由该旧metadata授权；旧accepted bytes只保留
于Git历史。只有新的proposed-body review及metadata-only approval完成后，当前bytes才能重新成为accepted输入。

## 接受与废弃

- 所有 Markdown frontmatter 必须且只能包含 `id`、`title`、`status`、`owner`、`updated`、
  `normative` 以及下述条件字段；key 不得重复，`updated` 使用 `YYYY-MM-DD`，`normative` 只能是
  `true|false`。
- `accepted` 必须额外包含 `approvers`、`approvedAt`、40 位小写十六进制
  `reviewCommit`、`https://` `reviewLink` 与 `openFindings: none`。这些字段是批准记录的机器入口；
  `approvers` 是一个 scalar，wire grammar 固定为 exact `, ` 分隔的 ASCII `safe-id` 列表：每项
  1–256 字符，首尾为字母或数字，中间只允许字母、数字、`.`、`_`、`:`、`+`、`-`；列表非空、
  唯一并按 ASCII byte 升序，禁止 email、trim 后修复、隐式重排或其他分隔符。角色数量与权限仍按
  [`governance/authority.md`](governance/authority.md) 人工/评审校验。
- `superseded` 必须额外包含精确 primary document ID 的 `successor`；successor 必须存在且
  supersession graph 无环。若旧文档曾为 `accepted`，五个 approval 字段必须完整保留并继续
  通过格式校验；从未 accepted 的文档不得伪造部分 approval metadata。除 `superseded` 的该历史
  保留例外外，其他状态不得携带 accepted/superseded 条件字段。
- 修改 accepted 行为必须先增加 ADR；破坏性变化还需 migration 和版本提升。
- supersede 时旧文件只加状态横幅与 successor，不改写历史正文。
- `REL-<semver>` 是合法 primary ID；在 `TASK-D0-07` 的 formal evidence-set binder 落地前，
  docs-check 必须 fail closed，拒绝任何 `accepted` release document，不得以普通 `passed` alpha
  ledger 代替正式 candidate-bound evidence set。
- 文档检查必须拒绝重复 ID、死链接、accepted 文档中的 `TODO`/`TBD`/
  `待补充`/`待决定`/`待锁`、已登记 `CLM-*` 的空/未知 source、无 successor 的
  superseded 状态以及未闭合的 normative trace。
- “当前索引”必须且只能各包含一次 Phase 0–7 的八个 canonical 文档路径；索引状态必须与目标
  frontmatter 一致。缺行、重复行、额外文档或用索引文字伪造 `accepted` 均须 fail closed。
