---
id: FAMILY-ZK-APP-CHAIN
title: ZK Application Chain family view
status: draft
owner: research
updated: 2026-08-10
normative: false
---

# Family View：ZK Application Chain

状态：`draft`

Aleo 和 Psy 把零知识证明与自身链状态、托管、交易/finalization 和结算结合，因此既不是普通 circuit target，也不是通用 zkVM。

- Aleo：工程 leaf 只发射 canonical Aleo Instructions + query descriptor；无 Leo/compiler/runtime/network lane。
- Psy：工程 leaf 只发射 versioned canonical DPN package；无 `.psy` source、Dargo/local VM/proof lane。

两者必须分别拥有 `AleoPlan` 与 `PsyPlan`。共享最多限于 disclosure vocabulary、proof artifact provenance 和通用 cryptographic type descriptions；状态与 settlement 不共享。
