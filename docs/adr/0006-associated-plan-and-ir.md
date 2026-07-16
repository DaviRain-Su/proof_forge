---
id: ADR-0006
title: Materializer 保留关联 Plan 与 TargetIR 类型
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0006：Materializer 保留关联 Plan 与 TargetIR 类型

- 状态：`proposed`
- 日期：2026-07-15

## 背景

把所有 target plan 擦除成 JSON、string、`Unit` 或通用 record 会失去编译期完整性和不变量边界。

## 决定

`Materializer target` 暴露关联类型 `Plan` 与 `TargetIR`，流水线固定为 resolve → plan → validate → lower → emit。只有最终 manifest 使用稳定序列化 schema；内部 typed Plan 不因 CLI 统一而擦除。

## 后果

各 target 编译器能够用 Lean 类型表达完整性；统一 orchestration 需要 existential/package boundary，但不降低具体 Plan 类型。

## 否决方案

- 一个大 union Plan。
- backend 直接从 SemanticProgram 输出 bytes。

## 验证

每个 Plan 有 constructor/validator tests；emit 不能访问 Source AST 或未解析 requirements。
