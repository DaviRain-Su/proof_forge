---
id: ADR-0009
title: 分离 Target Codegen 与 Network Profile
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# ADR-0009：分离 TargetId、CodegenProfile 与 NetworkProfile

- 状态：`proposed`
- 日期：2026-07-15

## 背景

平台身份、编译工具版本和部署网络规则变化速度不同。把它们编码进一个 target string 会造成别名和静默漂移。

## 决定

- `TargetId` 表示语义宿主，如 `near`。
- `CodegenProfile` 固定 compiler/ABI/VM/proof backend 与 binary digest。
- `NetworkProfile` 固定 chain/fork/protocol、资源与部署策略。

解析必须 exact；没有 network profile 仍可生成标记为未部署的 artifact，但不能宣称 network-compatible。

## 后果

支持历史 profile 与可重现构建；用户需要显式选择或接受项目记录的默认 profile。

## 验证

profile mismatch/unknown/withdrawn tests，manifest 包含三层身份与 lock digest。
