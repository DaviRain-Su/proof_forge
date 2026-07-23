---
id: GOV-VER-001
title: 版本与兼容治理
status: proposed
owner: release
updated: 2026-07-23
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

## TASK-D0-10 taskqualification authority-store v1 → v2

`ADR-0021`是C3 breaking protocol amendment。`pf.taskqual.authority-store.rpc.v1`及其descriptor/frame/domain
保持字节不变且只供historical lookup evidence重放；它不能签发protected acceptance。所有新
`TaskQualificationProtectedHandoffV1` production invocation必须exact pin
`pf.taskqual.authority-store.rpc.v2`与`TaskQualificationAuthorityStoreServiceV2`，使用Linux
`AF_UNIX/SOCK_SEQPACKET`、exact v2 frame decoder和一次terminal acceptance-signing。不存在in-place alias、
version negotiation、v1→v2 coercion、dual reader、best effort或fallback。

迁移只适用于首次production acceptance前尚未发布的D0-10 candidate：旧candidate `1e0214f9`永久不可closeout，
必须从accepted v2 profile/service pin建立新candidate。rollback只能撤销尚未签发的v2 pins/objects、spend
全部handoff nonce并让TASK-D0-10回到blocked；一旦v2 acceptance签发，修复必须使用新protocol major，不能
回退v1或caller-provided seeds。仓库没有已发布v2对象需要data migration。
