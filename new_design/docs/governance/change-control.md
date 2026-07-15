---
id: GOV-CHANGE-001
title: 变更控制流程
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
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

## 流程

1. 提交 change proposal，列用户影响、类别、替代方案、风险和 rollback。
2. C2+ 先 accepted ADR；更新 PRD/architecture/module/technical/test/trace。
3. 创建 ≤4h task 并先写 failing acceptance test。
4. 实现、聚焦验证、diff review；禁止把 golden 更新当唯一证明。
5. 生成 EV，运行 required aggregate/repro/clean-room。
6. 更新 implementation log、document status 和 review findings。
7. 按 authority matrix 批准；release 由独立步骤执行。

若实现暴露规格歧义，停止实现，把 task 标 blocked，先修订并重审规格。禁止用代码先行
反向覆盖 accepted 语义。父项目变化不会自动触发 V2 迁移，只能形成新的研究 claim/proposal。
