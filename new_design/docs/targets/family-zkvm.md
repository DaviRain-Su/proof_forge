---
id: FAMILY-ZKVM
title: zkVM Workload family view
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# Family View：zkVM Workload

状态：`draft`

zkVM target 证明一段 guest 指令执行，而不是直接编译成算术电路 DSL。当前候选为 OpenVM：程序经 RV32IM ELF/VmExe 执行并生成 proof。

zkVM 可以实现更宽的控制流/内存模型，但 proof 成本、guest I/O、VM extension、config hash 和 verifier 都必须进入 Plan 与 manifest。它仍没有原生链状态或 settlement；这些能力不得由“可以生成 EVM proof”推断出来。
