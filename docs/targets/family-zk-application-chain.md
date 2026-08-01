---
id: FAMILY-ZK-APP-CHAIN
title: ZK Application Chain family view
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# Family View：ZK Application Chain

状态：`draft`

Aleo 和 Psy 把零知识证明与自身链状态、托管、交易/finalization 和结算结合，因此既不是普通 circuit target，也不是通用 zkVM。

- Aleo：record/mapping、私有 proof context、公共 finalization context。
- Psy：用户分区状态、本地 CFC/UPS 证明、网络递归聚合；工程 leaf 已落地（`.psy` 源码发射 + capability gate；dargo 为未配置的 locked toolchain，`effect.asynchronous-workflow` 因无 deferred crosscall 形式而拒诊；formal/DPN 直发仍为研究项）。

两者必须分别拥有 `AleoPlan` 与 `PsyPlan`。共享最多限于 disclosure vocabulary、proof artifact provenance 和通用 cryptographic type descriptions；状态与 settlement 不共享。
