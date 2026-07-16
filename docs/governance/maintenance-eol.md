---
id: GOV-EOL-001
title: 维护、目标成熟度与 EOL
status: proposed
owner: maintainers
updated: 2026-07-15
normative: true
---

# 维护、目标成熟度与 EOL

每月复核 toolchain/advisory/target 官方规范，每季度复核 target dossier、support claims、性能
预算和 evidence freshness。owner 缺失 30 天、官方 tool EOL、required gate 连续失败 7 天、
语义差异或安全漏洞可将 target/profile 降级或禁用。

成熟度提升只按 evidence：specified→artifact_validated→local_runtime→
network_or_proof_validated；下降立即生效并记录原因。Wasm/ZK family 标签不能替代逐 target
证据。设计档案没有 backend，始终不可 build。

EOL 正常流程：公告≥90天/两个 minor→提供 successor/migration→停止新增功能→最后安全
窗口→registry 默认隐藏→下一 major 删除实现但保留 ID tombstone/dossier。紧急安全禁用不等
待窗口。历史 artifacts、schema 和验证工具在法律/安全允许时保留至少两年。
