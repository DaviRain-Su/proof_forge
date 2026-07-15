---
id: TARGET-OPENVM
title: OpenVM target dossier
status: draft
owner: architecture
updated: 2026-07-15
normative: true
---

# Target Dossier：OpenVM

状态：`draft`
Target ID：`openvm`
Phase 1：设计，不实现

## 1. 身份与来源

OpenVM 是模块化 zkVM，guest 编译为 RV32IM ELF/VmExe，并可生成 application、STARK 或 EVM-oriented proof。依据官方 [Overview](https://docs.openvm.dev/book/writing-apps/overview/)、[Compiling](https://docs.openvm.dev/book/writing-apps/compiling-a-program/) 与 [Generating Proofs](https://docs.openvm.dev/book/writing-apps/generating-proofs/)（核心模型 verified；版本组合 provisional）。

## 2. 执行、状态、调用、失败与资源

- 执行：guest 指令与启用的 VM extensions 决定可证明语义。
- 状态：guest memory/I/O；没有原生链 persistent state。
- 调用：guest 内普通调用；外部数据通过受约束 I/O/commit/reveal interface。
- 失败：guest trap、VM config mismatch、proof failure 分开。
- 资源：cycles、segments、extensions、proof mode、memory/prover cost。

## 3. Portable fragment 与扩展

Portable 候选：固定整数、较丰富的有界控制流、memory data structures、pure/state-transition workloads。

扩展：guest I/O、commit/reveal、RV32 extensions、crypto accelerators、continuations/aggregation、EVM proof mode。每项绑定 OpenVM config hash。

## 4. `OpenVmPlan` schema

```text
OpenVmPlan {
  profile, vmConfig,
  guestInputs, publicValues,
  memoryLayout, entry,
  enabledExtensions, executableCommitment,
  proofMode, verifierBinding
}
```

## 5. Target IR 与制品

预期路径：`OpenVmPlan → GuestIR → RV32IM ELF → VmExe`。输出 guest source/IR、ELF、VmExe、VM config、proof/VK/verifier metadata 和 manifest。Lean direct guest 或受控 Rust guest 是后续 ADR，当前不预设为已解决。

## 6. 工具链

官方页面存在混合版本线；实现前必须选择一个完整 OpenVM release，固定 CLI/crates/toolchain/config schema 和 proof backend。禁止跨版本拼接命令。

## 7. 证明流程

build guest → transpile/commit executable → keygen（若 profile 需要）→ execute → prove → verify。EVM proof 只说明 verifier 形式，不赋予 chain storage/settlement。

## 8. 安全

关注 guest input ambiguity、public output omission、VM extension mismatch、ELF/VmExe substitution、config commitment、host nondeterminism、unsafe guest code、proof recursion 与 verifier contract binding。

## 9. 验证阶梯

frozen-version MWE → ELF/VmExe validation → deterministic execute → app proof → STARK/EVM proof profile（若选择）→ external verifier negative cases。

## 10. 不支持、风险与成熟度退出

当前不实现、不注册为 production target。准入条件：冻结单一版本、决定 guest generation strategy、完成 Counter state-transition I/O 与 proof binding MWE、记录资源基线。输出始终为 `provable-guest`，没有 adapter 时 `nonDeployable`。
