---
id: MOD-RESOLVE-001
title: SupportResolver 模块规格
status: proposed
owner: targets
updated: 2026-07-15
normative: true
---

# SupportResolver

输入 `SemanticProgramV1`、static `TargetRegistry`、TargetId、CodegenProfileId、最低证据；
输出 `ResolvedProgram target` 与 immutable support decisions，或聚合 requirement diagnostics。
API：`inferRequirements`、`resolveTarget/profile`、`resolveSupport`。

模块拥有 requirement merge、exact key lookup、predicate implication、evidence order 和 registry
canonical hash；不解析 source、不调用 materializer/emitter、不加载动态配置。

前置：SemanticProgram validated、registry constructed；后置：成功值对每个 requirement 恰有
一个 claim decision，且 profile 属于 target。覆盖 zero/duplicate/conflicting requirements、
missing/version/digest/predicate/evidence、unknown/design-only target、wrong profile、registry
reordering、origin merge、diagnostic order、100-error cap、malicious config。关联
`SPEC-CAP-001`、`SPEC-REG-001`、`TASK-D3-01..03`、`TST-REQ/REG-*`。
