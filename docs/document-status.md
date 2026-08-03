---
id: DOC-STATUS
title: 文档生命周期与权威索引
status: proposed
owner: architecture
updated: 2026-08-03
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

## 当前恢复执行指针

当前产品开发由根级 [`RECOVERY.md`](../RECOVERY.md) / [`AGENTS.md`](../AGENTS.md) 驱动：
ProgramV1 → CheckV1/Normalize → `CompiledSemanticV1` → **八个 materializer**
（EVM/Solana/NEAR/Noir/Aleo/Psy/CosmWasm/TON）capability Plan/IR 的**工程纵切面**。
工程 registry **11 = 8 implemented + 3 design-only**（Soroban/ICP/OpenVM）。CosmWasm
工程面为 WAT + locked `wat2wasm` + `cosmwasm-check` + cosmwasm-vm mock（sync call FC、
async SubMsg 同 tx）；TON 工程面为 Tolk + real BoC + `@ton/sandbox`（resolver 开 async、
Plan schedule 仍 FC）。以上均为工程观察，**非** formal/hermetic。
**Accepted PRD Phase 1 范围仍为四目标**（EVM/Solana/NEAR/Noir）；后四个 engineering
leaves 的产品范围 reconciliation 仍待 **`DOC-ADR-SCOPE`**，不得静默扩 accepted scope。
日常缺口队列见 [`engineering-backlog.md`](engineering-backlog.md)。下表中的 task/evidence
文档继续保存历史 release-qualification 权威，但不再作为 development completion 的前置条件。

## 当前索引

| 文档族 | 当前文档 | 状态 | 权威范围 |
|---|---|---|---|
| 商业验证 | [`00-business-validation.md`](00-business-validation.md) | `draft` | 市场假设与 Go/No-Go |
| 产品 | [`01-prd.md`](01-prd.md) | `accepted` | 用户需求、范围、成功标准 |
| 架构 | [`02-architecture.md`](02-architecture.md) | `accepted` | 系统边界、不变量、数据流 |
| 技术规格 | [`03-technical-spec.md`](03-technical-spec.md) + `specs/` | `accepted` | API、schema、错误和版本；`SPEC-TASKQUAL-001` raw artifact owner R2已按single-maintainer owner waiver批准 |
| 实施计划 | [`04-task-breakdown.md`](04-task-breakdown.md) | `accepted` | 任务顺序与任务验收 |
| 测试 | [`05-test-spec.md`](05-test-spec.md) | `accepted` | owner matrix、真实production acceptance、签名与closeout要求已批准 |
| 实现事实 | [`06-implementation-log.md`](06-implementation-log.md) | `draft` | 工程实现事实、实际命令、结果与限制 |
| 最终评审 | [`07-review-report.md`](07-review-report.md) | `not_started` | 发布判断 |

## 权威优先级

规范意图冲突时：accepted ADR → accepted PRD → accepted architecture →
accepted technical/module spec → accepted test spec。当前事实冲突时：代码和实际制品
→ 可复现 gate/evidence → implementation log。调研冲突时：官方 primary source →
verified claim → synthesis。`proposed` 文档不能覆盖已接受决策。

2026-07-20 authority amendment的历史accepted revision输入为`ADR-0020`、当时的
`SPEC-TASKQUAL-001`与`GOV-TASKQUAL-BOOTSTRAP-001`；批准来源是Amp thread
`T-019f7dea-e600-77ea-8884-9f35f81f747d`。2026-07-23 首次C3 terminal-signing amendment的历史
accepted unit为`ADR-0021`、当时的`SPEC-TASKQUAL-001`与PHASE-5，reviewCommit为
`3d68d8658cc26ce95201b277b10e4a94103836af`；该批准只保留于Git历史。真实Linux probe随后证明其中
capability checkpoint不可达。纠错后的immutable proposed-body commit固定为
`d7390d472785fae533460eb96f31bdbec13ae21e`，两次fresh commit-bound复审
`019f8f3c-ab93-7a50-a267-696a04253d76`与`019f8f3c-ab93-7a50-a267-697b0f23c2d5`均为P0=0、P1=0；三份bytes曾由
metadata-only `687d59bb229e3b0bdc3fd7bb56dd4b8a2c749753`恢复`accepted`且normative body相对reviewCommit零变化。

2026-07-24 corrected RED后的GREEN审计发现raw artifact/identity payload没有owning ContentRef schema/domain，
而accepted contract又要求adapter/service重算original ref；旧approval不覆盖本次新增owner registry。当前
`ADR-0021`、`SPEC-TASKQUAL-001`与PHASE-5共同转`in_review`，TASK-D0-10按R2 blocked。唯一维护者随后于
2026-07-24明确采用ADR-0021 §11.2的`single-maintainer-owner-waiver`：不再声称或要求其他agent提供independent
review，但全部可执行、kernel、production签名、C→D与gate验收保持不变。包含该waiver的immutable body
`102342f5c89600780220e6c075f7ddac937dcf2e`已由唯一维护者批准；ADR-0021、SPEC-TASKQUAL-001与PHASE-5仅以
`approvers: davirain`及status/index metadata恢复`accepted`。该批准明确是owner directive而不是independent review。

## 接受与废弃

- 所有 Markdown frontmatter 必须且只能包含 `id`、`title`、`status`、`owner`、`updated`、
  `normative` 以及下述条件字段；key 不得重复，`updated` 使用 `YYYY-MM-DD`，`normative` 只能是
  `true|false`。
- `accepted` 必须额外包含 `approvers`、`approvedAt`、40 位小写十六进制
  `reviewCommit`、`https://` `reviewLink` 与 `openFindings: none`。这些字段是批准记录的机器入口；
  `approvers` 是一个 scalar，wire grammar 固定为 exact `, ` 分隔的 ASCII `safe-id` 列表：每项
  1–256 字符，首尾为字母或数字，中间只允许字母、数字、`.`、`_`、`:`、`+`、`-`；列表非空、
  唯一并按 ASCII byte 升序，禁止 email、trim 后修复、隐式重排或其他分隔符。
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
