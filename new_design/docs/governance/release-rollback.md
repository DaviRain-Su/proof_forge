---
id: GOV-REL-001
title: 发布与回滚
status: proposed
owner: release
updated: 2026-07-15
normative: true
---

# 发布与回滚

## Release

1. 从 clean commit 创建 signed candidate tag。
2. 空 cache 执行全部 required CI，形成 immutable evidence set。
3. 生成 compiler archives、checksums、SBOM、provenance、compatibility matrix、release notes。
4. 三方 review 签署 `07-review-report`，确认 supported targets/profiles 和明确非目标。
5. 以独立 signing key 签名 manifest/checksums；先发布 candidate channel。
6. 安装/Counter build/prove/verify smoke 后提升 stable；发布不自动部署用户程序。

## Rollback

每个 release 记录 predecessor、下载位置、checksums 和 data/schema downgrade 限制。触发条件：
P0/P1 安全或语义错误、制品不可重现、toolchain 撤销、target artifact/runtime mismatch。
操作：冻结渠道→撤销 profile/target（fail closed）→发布 advisory→恢复 predecessor installer→
验证其 lock/evidence→提供受影响 artifact detection。已部署链程序不能由 compiler release
自动回滚，必须由 target-specific upgrade/migration runbook 明示。

每个 minor 至少演练一次 install previous→upgrade→build compatibility→rollback，记录
`TST-REL-001`/EV。禁止删除已发布 artifacts；标记 revoked 并保留验证元数据。
