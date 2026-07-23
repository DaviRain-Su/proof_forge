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
必须从accepted v2 profile/service pin建立新candidate。首个v2 pin/acceptance前的Linux feasibility纠错保持
protocol/service/frame closed wire与`2.0.0` major不变，只把未发布isolation-policy的不可达
`custodyCapabilities=[CAP_SYS_PTRACE]`替换为exact
`[CAP_SETPCAP,CAP_SYS_PTRACE]` ambient exec transition；旧policy bytes/profile refs一律删除并cross-reject，
关联nonce spent，不存在same-ID/digest alias、dual transition或runtime negotiation。rollback只能撤销尚未签发的
v2 pins/objects、spend全部handoff nonce并让TASK-D0-10回到blocked；一旦v2 acceptance签发，修复必须使用新
protocol major，不能回退v1、旧capability checkpoint或caller-provided seeds。仓库没有已发布v2对象需要data
migration。

2026-07-24 raw artifact owner R2不改变profile/pin/frame/acceptance字段或v2 protocol major；它注册
`proof-forge.task-qualification-artifact-payload.v1`，并把既有production artifact/protected identity roles
closed映射到该raw owner或已accepted typed owner。首个production profile/pin/acceptance尚未签发，因此没有
legacy bytes可迁移；任何使用unknown owner、fixture schema、错误role/schema或把plain `payloadSha256`冒充
ContentRef digest的草稿profile必须删除，关联nonce spent。禁止same-ID alias、dual registry、generic raw hash或
best-effort fallback；首个production acceptance后的owner语义变化必须升级对应schema/protocol并走新评审。
