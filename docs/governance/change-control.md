---
id: GOV-CHANGE-001
title: 变更控制流程
status: accepted
owner: architecture
updated: 2026-07-17
normative: true
approvers: architecture-owner, davirain, quality-owner
approvedAt: 2026-07-17
reviewCommit: 306b7b6a19855f1b7c9416543bd4aa4f3860a91f
reviewLink: https://github.com/DaviRain-Su/proof_forge/commit/306b7b6a19855f1b7c9416543bd4aa4f3860a91f
openFindings: none
---

# 变更控制流程

## 分类

| Class | 示例 | 必需动作 |
|---|---|---|
| C0 editorial | 拼写、无语义链接 | docs check + one reviewer |
| C1 compatible | 新 optional diagnostic metadata | spec/test/trace update + owner review |
| C2 semantic | requirement/Plan/ABI/layout 行为 | ADR + specs + tests first + owners |
| C3 breaking | DSL/Core/schema/profile incompatible | ADR、major/version、migration、release note |
| C4 maturity | target evidence/promotion/demotion | dossier、EV、roadmap/status、Security/Quality |
| C5 emergency | 漏洞/工具链撤销 | 立即 fail closed、advisory，24h 内追补记录 |

## 与任务冻结的关系

全部 `TASK-*` 的完成面守恒见
[`task-freeze.md`](task-freeze.md)（`GOV-TASK-FREEZE-001`）。

- 不得在 `in_progress`/`done` 任务上通过“改任务描述/增 TST”吸收 C1+ 范围。  
- 规格变更迫使任务完成面变化时：先 `blocked` 或走 Freeze Exception，再开新 task / 重置完成包。  
- 新增 milestone 任务行属于调度变更，须满足 task-freeze §4 / §7，不能只靠本文件的 C1 路径静默加行。

## 流程

1. 提交 change proposal，列用户影响、类别、替代方案、风险和 rollback。
2. C2+ 先 accepted ADR；更新 PRD/architecture/module/technical/test/trace。
3. 创建 ≤4h task，写入冻结完成包，再标 `in_progress`；先写 failing acceptance test。
4. 实现、聚焦验证、diff review；禁止把 golden 更新当唯一证明；禁止扩大完成面。
5. 生成 EV，运行 required aggregate/repro/clean-room。
6. 更新 implementation log、document status 和 review findings。
7. 按 authority matrix 批准；release 由独立步骤执行。

若实现暴露规格歧义，停止实现，把 task 标 blocked，先修订并重审规格。禁止用代码先行
反向覆盖 accepted 语义。父项目变化不会自动触发 V2 迁移，只能形成新的研究 claim/proposal。
