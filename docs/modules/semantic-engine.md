---
id: MOD-SEM-001
title: SemanticEngine 模块规格
status: proposed
owner: semantics
updated: 2026-07-16
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

当前 alpha 的 names/types 子切片在进入完整 DiagnosticBundle 前仍返回
`CompileError.invalidProgram`。它为 accepted-width `Source.Program` 建立 target-neutral 的
临时名称环境：state index 每个 program 只构建一次并由 initializer/entries 共享，parameter
index 每个 callable 构建一次；索引不进入 `Typed.Program`，也不参与 canonical serialization。
所有 typed 数组与 ID 继续来自源码声明顺序，frontend/SemanticEngine 不读取 target、
codegen profile 或 network profile。名称 lookup 的预期/摊销复杂度按声明、引用和名称字节
总量线性，但不承诺恶意哈希碰撞下的严格最坏情况界。

不变量：checked arithmetic、left-to-right、atomic logical rollback、ordered effects、完整
requirement origin、canonical hash。覆盖整数/Field、Map/Array、CFG、revert/trap、external
responses、private flows、循环边界、serializer roundtrip/order、malformed Core、resource
limits。关联 `SPEC-TYPE-001`、`SPEC-SEM-001`、`TASK-D2-*`、`TST-TYPE/EFFECT/SEM-*`。
