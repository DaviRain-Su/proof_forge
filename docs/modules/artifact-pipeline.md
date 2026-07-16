---
id: MOD-ART-001
title: ArtifactPipeline 模块规格
status: proposed
owner: artifacts
updated: 2026-07-15
normative: true
---

# ArtifactPipeline

输入 emitter 提供的 named byte streams、verified tool results、hash identities 和 support
decisions；输出原子 `OutputSetV1`。模块拥有 staging、path containment、limits、manifest JCS、
hash 和 atomic publish；不读取 source AST、不决定 target semantics、不部署或证明。

状态：`created → writing → validating → manifesting → publishing → published`；任一错误进入
`aborted`，旧 destination 不变并清理 staging。API：`OutputBuilder.create/add/validate/publish/
abort`；builder 是线性资源，publish/abort 后不可复用。

覆盖 duplicate/traversal/symlink/case paths、limits、disk full/permissions/signals、validator
failure、concurrency、force rollback、JCS/hash mismatch、dirty release、non-deployable role、
private data scan。关联 `SPEC-OUT-001`、`TASK-D3-05`、`TST-OUT/SEC-*`。
