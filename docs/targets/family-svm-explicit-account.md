---
id: FAMILY-SVM
title: SVM Explicit-Account Program family view
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# Family View：SVM Explicit-Account Program

状态：`draft`

该视图强调 Solana 的显式账户输入：程序不能把逻辑状态简单映射为“自己的全局 storage”，必须声明账户身份、owner、signer、writable、PDA seeds、data layout 和 CPI account metas。

共享层可以描述逻辑 Cell/Map、权限谓词和有序 effect；`SolanaPlan` 决定它们如何分布到 accounts。账户缺失、owner 不匹配、签名或 writable 不足都是调用前置条件失败，不得降为业务 `false`。

该视图当前只含 `solana`，不是所有名为 SVM 的网络都自动兼容。
