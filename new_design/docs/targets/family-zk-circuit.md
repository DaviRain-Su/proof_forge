---
id: FAMILY-ZK-CIRCUIT
title: ZK Circuit Compiler family view
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# Family View：ZK Circuit Compiler

状态：`draft`

Circuit target 把 `program` 物化为关系、public inputs、private witness 和约束系统。它不天然提供持久状态、调用宿主或链结算。Phase 1 只包含 `noir`。

有状态程序被解释为 `preState → postState` 关系；状态连续性、proof 发布和 settlement 必须标为 external，除非以后增加显式且独立验证的 adapter。`private/public/commitment` 是业务披露语义，不是顶层类别。

不受约束执行、oracle 和 foreign call 会扩大信任基，必须由版本化 extension 和 soundness evidence 开启；Phase 1 默认拒绝。
