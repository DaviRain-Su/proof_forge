---
id: RESEARCH-INDEX
title: 调研证据索引
status: draft
owner: research
updated: 2026-08-01
normative: false
---

# 调研证据索引

状态：`draft`
更新日期：2026-08-01

本目录保存 ProofForge V2 的非规范性研究材料。研究结论不能越过已接受的 ADR、PRD、架构和技术规格；它们的作用是说明“为什么这样设计”，而不是暗中改变产品语义。

**工程执行队列**不在本目录：见 [`../engineering-backlog.md`](../engineering-backlog.md)。
日常只把 **11 + 12** 的缺口回写 backlog；**01–09** 为早期设计研究（已被 ADR/SPEC 吸收），**10** 为长期北极星（IBC），勿再平行开第四份 gap 清单。

## 阅读顺序

1. [`source-register.json`](source-register.json)：来源、版本、定位与访问状态。
2. [`claim-register.json`](claim-register.json)：可独立复核的原子结论。
3. [`01-current-system-audit.md`](01-current-system-audit.md)：空白 V2 与父项目参考边界。
4. [`02-execution-models.md`](02-execution-models.md)：各平台执行、状态和提交模型。
5. [`03-language-semantics.md`](03-language-semantics.md)：统一 `program` 语言的研究结论。
6. [`04-target-taxonomy.md`](04-target-taxonomy.md)：多轴目标分类。
7. [`05-backends-artifacts-toolchains.md`](05-backends-artifacts-toolchains.md)：后端、制品和工具链。
8. [`06-security-and-migration.md`](06-security-and-migration.md)：安全与 clean-room 迁移。
9. [`07-synthesis.md`](07-synthesis.md)：研究综合与实施准入。
10. [`08-v1-v2-frontend-ir-comparison.md`](08-v1-v2-frontend-ir-comparison.md)：V1 与 V2 的 Lean 语法入口、领域 IR 和编译边界对照。
11. [`09-assembler-semantics-bridge.md`](09-assembler-semantics-bridge.md)：汇编语义桥研究。
12. [`10-ibc-as-proofforge-programs.md`](10-ibc-as-proofforge-programs.md)：IBC-as-programs 可行性与语言前置（**北极星，非近期任务**）。
13. [`11-feature-coverage-audit.md`](11-feature-coverage-audit.md)：特性覆盖审查——分层缺口与按杠杆排序清单。
14. [`12-target-coverage-matrix.md`](12-target-coverage-matrix.md)：wire Op × target LOWERED/FAIL-CLOSED/GAP 矩阵（工程覆盖权威格子）。

## 证据等级

- `verified`：2026-07-15 已通过官方规范、官方文档或可复现本地事实核验。
- `provisional`：方向有一手材料支持，但版本、工具链或真实网络流程尚未冻结。
- `accepted`：项目设计决定；事实依据可复核，但决定本身由 ADR 管理。
- `rejected`：已核验后明确不采用。

网页没有被仓库快照化时，`contentHash` 为 `null`，并在 `hashStatus` 中明确说明。不能用 URL 字符串的哈希冒充来源内容哈希。进入实现前，所有工具链 profile 必须把文档、二进制和依赖固定到可重现版本。

## 维护规则

- 每个重要事实至少对应一个 `CLM-*`，每个 claim 引用一个或多个 `SRC-*`。
- 平台营销性能数字只作为待验证主张，不作为容量、费用或安全承诺。
- 父项目路径只能记录观察结果和 commit；不得被 V2 作为依赖、测试 oracle 或 fallback。
- 任何事实发生变化时，新增来源记录并更新 claim，不覆写历史语义。
