---
id: ADR-0007
title: Wasm 只共享编码而不共享宿主语义
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0007：Wasm 只共享编码，不共享宿主语义

- 状态：`proposed`
- 日期：2026-07-15

## 背景

NEAR、CosmWasm、Soroban、ICP 都输出 Wasm，但它们的 ABI、状态、权限、调用、提交、资源和升级语义不同。

## 决定

共享层只提供 deterministic Wasm AST/encoder、基础 structural validator、通用 instructions、section writer 和 provenance。四个目标分别使用 `NearPlan`、`CosmWasmPlan`、`SorobanPlan`、`IcpPlan`，生成 target-specific `ModuleRecipe` 后调用 encoder。

## 后果

避免 `GenericWasmHostPlan` 逐渐变成带大量 target switches 的混合 IR；代价是 host adapters 不能通过继承一个大 plan 快速拼装。

## 否决方案

- 把所有 imports/exports/storage/call 放入 tagged union host plan。
- 只按 `.wasm` 后缀判定兼容。

## 验证

shared Wasm modules 禁止 import target namespaces；每个 host validator 拒绝其他 host imports/custom sections。
