---
id: TARGET-CAIRO
title: Cairo / Starknet-oriented zkVM target dossier
status: draft
owner: architecture
updated: 2026-08-13
normative: true
---

# Target Dossier：Cairo

状态：`draft`
Target ID：`cairo`
成熟度 ceiling（静态 dossier）：`research`
阶段：研究期（ADR-0017）；**无** registry materializer；Plan 设计见
[`../research/26-zkvm-trio-cairo-risc0-sp1-design.md`](../research/26-zkvm-trio-cairo-risc0-sp1-design.md)

## 1. 身份与来源

Cairo 程序在 **Cairo VM** 上执行，并由 STARK 类系统证明该执行（与 Noir 电路 DSL、
RISC-V zkVM、Aleo/Psy 应用链均不同）。Starknet 是常见结算语境，但 **本 target 默认是
zkVM workload**，不得因「可部署到 Starknet」就写成 CosmWasm 式合约叶。

归类：family [`family-zkvm.md`](family-zkvm.md)。独立 `CairoPlan`；禁止复用
`OpenVmPlan` / `Risc0Plan` / `Sp1Plan` / `NoirPlan`。

官方文档入口（研究期 plain link；SRC/CLM 补齐前不得升 specified）：
[Cairo book](https://book.cairo-lang.org/)、Starknet docs（版本实现前钉死）。

## 2. 执行、状态、调用、失败与资源

- 执行：Cairo/Sierra→CASM 路径由 **锁定** toolchain profile 决定；禁止混版本。
- 状态：guest/felt 内存与显式 I/O；**无** PF 意义下的原生持久合约 storage（除非未来
  Starknet storage extension，且不得进 Q0）。
- 调用：guest 内调用；**Starknet 系统调用整表 Q0 fail closed**。
- 失败：assert/panic 与 proof failure 分开；checked UInt 必须经 felt 范围守卫，禁止静默 wrap。
- 资源：steps/builtins/proof cost 进 Plan `resourceEnvelope`。

## 3. Portable fragment（Q0）与扩展

**Q0 Admit**（与三机共享表，RPT-026 §3）：public 标量 `UInt32`/`UInt64`/`Bool`/`Unit`、
≤4 state、init/entry/view/pureFn、checked 加/减/乘（div/mod 可 FC）、if/有界 for、
assert/zero-payload revert、continuity=`external-public-pre-post`。

**Q0 Fail-closed**：`call`/`schedule`、`context.*`、emit（或仅 extension）、聚合/Map/Bytes、
Field 曲线特化、invariants、Starknet syscalls、无界循环。

**扩展（非 Q0）**：Starknet storage/caller、L1 handler、builtins 加速、prove profile。
每项 exact version + SupportClaim。

## 4. `CairoPlan` schema（设计冻结）

```text
CairoPlan {
  profileId                 -- e.g. cairo-sierra-u64-v1
  semanticsDigest
  sourceHash, semanticHash
  continuity                -- external-public-pre-post
  proofMode                 -- none | execute-only | prove
  sierraOrCairo {
    entrypoints[] { name, role, feltLayout ... }
  }
  methods[]
  stateSlots[]
  failurePolicy
  starknetHints             -- Q0 must be empty
  resourceEnvelope
}
```

## 5. Target IR 与制品

`CairoPlan → CairoGuestIR → Sierra/Cairo 源或 IR →（可选）execute/prove 元数据`。

首切片目标 **Z0–Z1**（Plan + guest 源）；`deployable=false`；prove 前不得声称
`verifiable-workload` 以上。

## 6. 工具链

实现 ADR 必须冻结单一 Cairo/Sierra/scarb（或等价）+ prover 版本线。禁止 PATH 漂移拼接。

## 7. 证明 / 结算

默认 `settlementModel=external-verifier`。Starknet 网络部署仅经独立 `NetworkProfileId`，
不进入默认 codegen，也不改 semantic hash。

## 8. 安全

felt 宽度误映射、syscall 偷渡、VK/proof 替换、非确定 hint、把 STARK 收据写成「合约已上链」。

## 9. 验证阶梯

Q0 Counter 金样 → Plan validate → guest 金样 →（可选）execute 钉 public I/O → prove/verify。

## 10. 不支持与退出

当前 **不实现**、不扩 accepted PRD。升 materializer 前：实现 ADR、扩 `ExecutionHost`、
Registry 行、Q0 负例矩阵、与 OpenVM/risc0/sp1 **零 Plan 共享** 证明。实现序默认在
OpenVM 与 RISC-V 第二叶之后（`TGT-CAIRO-MVP`）。
