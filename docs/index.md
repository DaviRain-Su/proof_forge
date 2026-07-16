---
id: DOC-INDEX
title: ProofForge V2 文档导航
status: proposed
owner: architecture
updated: 2026-07-17
normative: true
---

# 文档导航

## 生命周期

| Phase | 文档 | 状态 | 进入下一阶段的条件 |
|---|---|---|---|
| 0 | [商业验证](00-business-validation.md) | `draft` | 证据达到 Go 条件或形成有时限的 founder exception |
| 1 | [PRD](01-prd.md) | `accepted` | FR/NFR/非目标/DoD 获批 |
| 2 | [Architecture](02-architecture.md) | `accepted` | 边界、不变量、威胁模型获批 |
| 3 | [Technical Spec](03-technical-spec.md) | `accepted` | 所有公共接口、状态、错误、版本和边界获批 |
| 4 | [Task Breakdown](04-task-breakdown.md) | `proposed` | 任务均可在 4 小时内独立验收 |
| 5 | [Test Spec](05-test-spec.md) | `proposed` | 测试骨架和 acceptance matrix 获批 |
| 6 | [Implementation Log](06-implementation-log.md) | `draft` | 只记录真实执行与证据；当前为 pre-acceptance alpha |
| 7 | [Review Report](07-review-report.md) | `not_started` | 规格、安全、依赖、性能、发布与回滚签署 |

## 架构图（Excalidraw）

可编辑白板图：[`diagrams/README.md`](diagrams/README.md)。在
[excalidraw.com](https://excalidraw.com) 打开 `.excalidraw` 后导出 PNG/SVG 用于 README。

## 规范入口

- 语言与语义：[`specs/language.md`](specs/language.md)、
  [`specs/source-program-wire.md`](specs/source-program-wire.md)、
  [`specs/type-effect-system.md`](specs/type-effect-system.md)、
  [`specs/semantic-core.md`](specs/semantic-core.md)、
  [`specs/semantic-program-wire.md`](specs/semantic-program-wire.md)。
- 目标求解：[`specs/capabilities-extensions.md`](specs/capabilities-extensions.md)、
  [`specs/target-registry.md`](specs/target-registry.md)、
  [`specs/materializer-protocol.md`](specs/materializer-protocol.md)。
- 公共产品面：[`specs/cli.md`](specs/cli.md)、
  [`specs/output-contract.md`](specs/output-contract.md)、
  [`specs/diagnostics.md`](specs/diagnostics.md)。
- 公共 primitive 与资源 profile：[`specs/common-types.md`](specs/common-types.md)。
- 工程可信度：[`specs/security.md`](specs/security.md)、
  [`specs/toolchains.md`](specs/toolchains.md)、
  [`specs/versioning.md`](specs/versioning.md)、
  [`specs/reproducibility.md`](specs/reproducibility.md)、
  [`specs/gate-catalog-finalization.md`](specs/gate-catalog-finalization.md)。

## 模块、目标与证据

- 模块边界：[`modules/README.md`](modules/README.md)。
- 目标档案：[`targets/README.md`](targets/README.md)。
- ADR：[`adr/README.md`](adr/README.md)。
- 调研：[`research/README.md`](research/README.md)。
- V1/V2 前端与 IR 对照：[`research/08-v1-v2-frontend-ir-comparison.md`](research/08-v1-v2-frontend-ir-comparison.md)。
- Solana ISA 地基（研究）：[`research/09-assembler-semantics-bridge.md`](research/09-assembler-semantics-bridge.md)。
- 追踪矩阵：[`traceability/README.md`](traceability/README.md)。
- 治理：[`governance/README.md`](governance/README.md)。
- 术语：[`glossary.md`](glossary.md)。

目标与 ADR/调研目录由对应工作流维护。缺失页面表示该工作流尚未完成，不能推断
目标已实现。
