---
id: TARGET-RISC0
title: RISC Zero zkVM target dossier
status: draft
owner: architecture
updated: 2026-08-13
normative: true
---

# Target Dossier：RISC Zero

状态：`draft`
Target ID：`risc0`
成熟度 ceiling（静态 dossier）：`research`
阶段：研究期（ADR-0017）；**无** registry materializer；Plan 设计见
[`../research/26-zkvm-trio-cairo-risc0-sp1-design.md`](../research/26-zkvm-trio-cairo-risc0-sp1-design.md)

## 1. 身份与来源

RISC Zero 证明 **RISC-V guest** 执行并产出 receipt；属于 zkVM family，与 OpenVM/SP1 同轴但
**Plan/IR/tool lock 必须独立**（禁止 `type Risc0Plan := OpenVmPlan`）。

官方入口（研究期 plain link）：[RISC Zero docs](https://dev.risczero.com/)（实现前钉 commit/tag）。

## 2. 执行、状态、调用、失败与资源

- 执行：guest ELF（或 profile 固定的 guest 方言）在 zkVM 中执行。
- 状态：guest memory + 显式 public/private I/O；无原生链 persistent storage。
- 调用：仅 guest 内；外部链 call/schedule **Q0 FC**。
- 失败：guest trap/panic 与 receipt 验证失败分开；overflow 对齐 PF checked 语义。
- 资源：cycle 预算、segment、prover 内存/时间进 Plan。

## 3. Portable fragment（Q0）与扩展

与 RPT-026 §3 **同一 Q0 Admit/FC 表**（标量 state、init/entry/view、checked 算术、有界控制流、
external pre/post；拒 call/schedule/context/聚合等）。

扩展：syscalls/host 函数、持续证明、Bonsai 等——均 versioned extension，默认 FC。

## 4. `Risc0Plan` schema（设计冻结）

```text
Risc0Plan {
  profileId                 -- e.g. risc0-guest-u64-v1
  semanticsDigest
  sourceHash, semanticHash
  continuity                -- external-public-pre-post
  proofMode                 -- none | execute-only | prove
  guest {
    entrypoints[] { name, role: init|entry|view|pure,
                    publicInputLayout, privateInputLayout, publicOutputLayout }
    memoryLayout
    cycleBudget             -- optional at Z1
  }
  methods[]
  stateSlots[]
  failurePolicy
  resourceEnvelope
}
```

## 5. Target IR 与制品

`Risc0Plan → Risc0GuestIR → 受控 Rust guest 或最小 RV IR → ELF →（可选）receipt`。

Guest 生成策略（Lean→Rust vs 直接 IR）在实现 ADR 一次性钉死。首切片 **Z0–Z1**；
`ArtifactDeployability` 最高到 `verifiable-workload`（仅 Z3+）。

## 6. 工具链

冻结单一 risc0 toolchain / cargo 模板 / prover 版本；纳入 Tool Lock 后方可 Z2/Z3。

## 7. 证明 / 结算

`proofModel=zkvm-execution`，`settlementModel=external-verifier`。无链部署故事。

## 8. 安全

input 布局歧义、public output 遗漏、ELF 替换、非确定 host、receipt 与 method 绑定失败。

## 9. 验证阶梯

Counter Q0 → Plan/IR 金样 → guest build → execute public I/O → receipt verify（可选）。

## 10. 不支持与退出

当前不实现。作为 **OpenVM 之后的第二 zkVM 叶候选 A**（与 `sp1` 二选一，见
`TGT-ZKVM-SECOND`）。不得与 SP1 共享 lowering 函数「改名导出」。
