---
id: GOV-SEC-001
title: 安全漏洞响应
status: proposed
owner: security
updated: 2026-07-15
normative: true
---

# 安全漏洞响应

报告通过 canonical repository 的 private Security Advisory 提交；公共 issue 发现疑似漏洞时
只回复转移渠道，不讨论利用细节。确认接收目标 24 小时。

| Severity | 示例 | Triage | Mitigation target |
|---|---|---|---|
| P0 critical | secret 泄漏、生成可盗资产的错误制品、供应链接管 | 4h | 24h 禁用/72h 修复候选 |
| P1 high | 跨目标语义错误、证明接受错误陈述、路径逃逸 | 24h | 7 天 |
| P2 medium | DoS、受限信息泄漏 | 3 天 | 30 天 |
| P3 low | hardening/documentation | 7 天 | 下一 minor |

流程：隔离报告→复现/影响版本与 artifacts→临时 profile/target revoke→私有修复与回归测试→
协调签名 release→advisory/CVE（适用时）→artifact detection 和用户迁移→复盘。修复不能以
降低检查或 silent fallback 规避。

证据和 witness 按 least privilege 存储；复现日志先做 secret scan。披露时间由修复可用性、
链上不可逆风险和报告者协商，默认修复发布后同步公开。复盘 14 天内更新 threat model、
SPEC/TST、依赖策略和响应指标。
