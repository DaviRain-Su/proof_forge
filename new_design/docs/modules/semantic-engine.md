---
id: MOD-SEM-001
title: SemanticEngine 模块规格
status: proposed
owner: semantics
updated: 2026-07-15
normative: true
---

# SemanticEngine

当前 alpha API：`Typed.check : Source.Program → CompileResult Typed.Program`、
`Semantic.fromTyped : SourceHash → Typed.Program → Semantic.Program`、
`Compiler.compile : Source.Program → CompileResult Semantic.Program`。完整阶段还要求
`step : Semantic.Program → State → Invocation → ExternalResponses → Outcome`。
模块拥有 name/type/effect/bound/disclosure rules、canonical Core、serializer 和 interpreter；
不读取 target/profile/network，不生成 ABI/layout/artifact。

状态：`source → names → types → effects/bounds/disclosure → typed → normalized → validated`。
任何阶段失败返回 sorted DiagnosticBundle；normalize 的内部失败为 compiler bug。

不变量：checked arithmetic、left-to-right、atomic logical rollback、ordered effects、完整
requirement origin、canonical hash。覆盖整数/Field、Map/Array、CFG、revert/trap、external
responses、private flows、循环边界、serializer roundtrip/order、malformed Core、resource
limits。关联 `SPEC-TYPE-001`、`SPEC-SEM-001`、`TASK-D2-*`、`TST-TYPE/EFFECT/SEM-*`。
