---
id: ADR-0004
title: 分离 Semantic Core 与 Target Plan
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0004：分离 Target-neutral Semantic Core 与 Target-owned Plan

- 状态：`proposed`
- 日期：2026-07-15

## 背景

把 storage slot、Solana account、Promise、TTL 或 proof wiring 放进共享 IR，会让共享层成为所有平台语义的混合体。

## 决定

共享 `SemanticProgram` 只描述类型、逻辑状态、entries、deterministic step/effects 和 requirements。每个 materializer 在 resolution 后创建 target-owned Plan，Plan 完整拥有 ABI、物理状态、调用、提交、资源、proof 和 upgrade 决策。

## 后果

共享层稳定且可解释；每个目标需要独立 Plan/validator，但不会因共同后缀而互相泄漏。

## 否决方案

- 一个包含全部 target constructors 的 Universal IR。
- backend 在打印时重新遍历源码猜布局/ABI。

## 验证

import boundary gate、Plan completeness tests、renderer 只接收其 Plan/TargetIR。
