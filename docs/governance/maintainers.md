---
id: GOV-MAINTAINERS-001
title: 角色与人员映射
status: proposed
owner: maintainers
updated: 2026-07-17
normative: true
---

# 角色与人员映射

本文件是 [`authority.md`](authority.md) 的角色→人员绑定记录；在 CODEOWNERS 落地前
以本文件为准。状态转 `accepted` 需表列人员书面确认。

## 映射

| Role | 人员（safe-id） | 绑定身份 |
|---|---|---|
| Product Owner | `davirain` | git author `Davirain <davirain.yin@gmail.com>` |
| Architecture Owner | `davirain` | 同上 |
| Language/Semantics Owner | `davirain` | 同上 |
| Target Owner | `davirain` | 同上 |
| Quality Owner | `davirain` | 同上 |
| Security Owner | `davirain` | 同上 |
| Release Manager | `davirain` | 同上 |

## 单点声明（诚实义务）

当前全部角色由同一人持有，[`authority.md`](authority.md) 批准矩阵中的多角色会签
实质为同一人多次签字，独立性弱化。在此状态下：

1. security-critical 变更的"至少两位不同审阅者"由**记录在案的独立复审**满足：
   每次为 bounded independent read-only review（可为外部 reviewer 或独立 AI 复审），
   结论（P0/P1/P2）必须写入 implementation log 或 evidence ledger；
2. 任何批准记录必须给出来源文档（如 [`genesis-authority.md`](genesis-authority.md)），
   禁止以"本仓库记录"自证批准；
3. 新增 maintainer 时按 [`change-control.md`](change-control.md) C2 更新本文件。
