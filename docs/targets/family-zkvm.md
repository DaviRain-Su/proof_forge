---
id: FAMILY-ZKVM
title: zkVM Workload family view
status: draft
owner: research
updated: 2026-08-13
normative: false
---

# Family View：zkVM Workload

状态：`draft`
更新日期：2026-08-13

zkVM target 证明一段 guest 指令执行，而不是直接编译成算术电路 DSL。当前工程 leaf 为
OpenVM：默认 `openvm-guest-source-v1`（ADR-0045 O0）Lean 渲染受控 Rust guest 源码，
zero-tool；opt-in `openvm-guest-elf-v1`（ADR-0046 O1）在同一 Plan/IR 上锁定
`cargo-openvm` 2.0.1 build/transpile 出 RV32IM ELF + `.vmexe` extras。keygen/execute/
prove/verify 仍属后续 profile。

## 成员（阅读视图，非共享 Plan）

| TargetId | 阶段 | ISA / 证明对象 | Plan 类型（独占） |
|---|---|---|---|
| `openvm` | registry design-only | RV32IM + extensions / VmExe | `OpenVmPlan` |
| `risc0` | research（ADR-0017） | RISC-V guest / receipt | `Risc0Plan` |
| `sp1` | research（ADR-0017） | RISC-V guest / SP1 proof | `Sp1Plan` |
| `cairo` | research（ADR-0017） | Cairo/Sierra / STARK | `CairoPlan` |

**禁止** `ZkPlan`、禁止 RISC-V 三机共用 IR 类型、禁止把 Noir/Aleo/Psy 并入本 family 的 Plan。

Q0 可移植片段、fail-closed 面、成熟度梯子与分机 schema 见
[`../research/26-zkvm-trio-cairo-risc0-sp1-design.md`](../research/26-zkvm-trio-cairo-risc0-sp1-design.md)。

zkVM 可以实现更宽的控制流/内存模型，但 proof 成本、guest I/O、VM extension、config hash 和 verifier 都必须进入 Plan 与 manifest。它仍没有原生链状态或 settlement；这些能力不得由“可以生成 EVM proof”或“跑在 Starknet 上”推断出来。O0/O1 制品角色均为 source-only 或 build-only，不得冒充 `verifiable-workload` 或 deployable contract。
