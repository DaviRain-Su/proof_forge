---
id: GOV-VER-001
title: 版本与兼容治理
status: proposed
owner: release
updated: 2026-07-15
normative: true
---

# 版本与兼容治理

技术规则以 [`../specs/versioning.md`](../specs/versioning.md) 为准。本流程要求每个 release
生成 compatibility matrix：compiler × DSL × Semantic schema × Output schema × target
CodegenProfile。matrix fixture 必须来自前一受支持 minor 和当前 candidate。

稳定版本至少支持当前和前一 minor，时间不少于 90 天；alpha/beta 可只支持同 minor，
但必须显式标记。任何破坏变化提供 migration guide、machine-readable diagnostic 和 source/
artifact backup；migration 不自动部署或覆盖原文件。

release notes 分为 added/changed/deprecated/removed/security/toolchains/target maturity。没有
schema/profile version justification 的 golden/ABI/layout change 阻断合并。revoked profile
进入 denylist 后所有仍安装的 compiler 也必须在显式 registry update 时 fail closed。
