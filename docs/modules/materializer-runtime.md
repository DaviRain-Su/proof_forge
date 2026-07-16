---
id: MOD-MAT-001
title: MaterializerRuntime 模块规格
status: proposed
owner: backends
updated: 2026-07-15
normative: true
---

# MaterializerRuntime

本模块只定义关联类型协议、registration 和阶段 orchestrator；实际 `EvmPlan`、
`SolanaPlan`、`NearPlan`、`NoirPlan` 由对应 target 模块拥有。输入必须是
`ResolvedProgram target + Verified CodegenProfile`；输出 staged OutputSet 或稳定诊断。

调用顺序固定 `plan → validatePlan → hash → lower → validateTargetIR → hash → emit`，不能
跳步、重试另一个 target 或从失败继续。orchestrator 不可擦除 Plan/IR 为字符串/JSON，
不可查看 source AST 或 network profile。

覆盖 registration duplicate、wrong target witness、Plan/IR validation failure、panic boundary、
tool timeout、partial output、resource cancellation、deterministic hashes、target cross-import、
unsupported settlement、private disclosure 和 commit mismatch。关联 `SPEC-MAT-001`、
`TASK-D3-04`、`TASK-D4..D7`、`TST-MAT-001` 及 target tests。
