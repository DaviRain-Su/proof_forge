---
id: GOV-DEP-001
title: 依赖与供应链策略
status: proposed
owner: security
updated: 2026-07-15
normative: true
---

# 依赖与供应链策略

V2 初始 Lean library 只依赖 Lean/Std。新增依赖必须说明不可内建的能力、API 面、维护状态、
license、transitive tree、漏洞和替代方案；使用 exact commit/tag 和 checksum，禁止 floating
branch、unpinned Git/path dependency、post-install script 与运行时动态下载。

默认允许 MIT、Apache-2.0、BSD-2/3-Clause、ISC；MPL-2.0 需 Security/Release 审核并保持
文件边界；GPL/AGPL/SSPL/proprietary 未获书面批准禁止进入发布物。外部 CLI 的 license 与
分发权单独记录；无法再分发时只记录官方安装和 checksum，CI 使用预置 cache。

每个 release 生成 SPDX SBOM、dependency graph、licenses、tool asset hashes 和 provenance。
Dependabot/自动升级只创建 proposal，不能自动合并 toolchain/semantic dependency。月度扫描
CVE/advisory；critical 24h triage。失维护、checksum 消失、license 变化或不可重现依赖触发
替换/冻结/target demotion。

clean-room 扫描拒绝父项目 local path、symlink、transitive path dependency和未知 binary。
