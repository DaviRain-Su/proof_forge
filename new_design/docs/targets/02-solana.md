---
id: TARGET-SOLANA
title: Solana target dossier
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# Target Dossier：Solana

状态：`proposed`
Target ID：`solana`
Phase 1：实现

## 1. 身份与来源

Solana program 在 sBPF runtime 中执行，状态位于显式传入的 accounts。依据官方 [Programs](https://solana.com/docs/core/programs) 与 [Accounts](https://solana.com/docs/core/accounts) 文档（`SRC-SOL-001/002`，verified）。

## 2. 执行、状态、调用、失败与资源

- 执行：instruction 携带 program id、account metas 和 data；transaction 提供原子执行边界。
- 状态：account 的 data、owner、lamports、executable 等是显式约束；程序只能按 runtime 权限修改。
- 调用：CPI 同步发生，需显式传递 callee 所需账户；PDA signer 语义由 seeds/program id 决定。
- 失败：program error、runtime violation、CPI error 分开；失败 transaction 不提交变更。
- 资源：compute units、stack/heap、account size/rent 与 loader/profile 绑定。

## 3. Portable fragment 与扩展

Portable：Cell/Map 的逻辑访问、entry/view、checked arithmetic、event-like log、authority predicate、同步 call。

扩展：account schema、PDA derivation、CPI account metas、system/token program operations、remaining accounts、return data、sysvars。使用扩展后只承诺支持相同语义的 target。

## 4. `SolanaPlan` schema

```text
SolanaPlan {
  profile, programIdPolicy, instructions,
  accountSchemas, layouts, pdaRules,
  dispatch, cpiSites, logs, errors,
  computeAssumptions
}
```

每个 instruction 完整列出 account index、role、owner、signer、writable、optional、PDA 约束。禁止 materializer 在 assembly 阶段猜账户顺序。

## 5. Target IR 与制品

`SolanaPlan → SbpfIR → sBPF assembly/ELF`。输出 ELF、可审计 assembly、IDL、account schema、program metadata、hash manifest。ELF loader/verifier 合法不代表账户语义正确，必须另做 runtime 测试。

## 6. 工具链

固定 Solana loader/runtime profile、sBPF toolchain、ELF linker 与本地 validator 版本。基线环境可能没有完整 SBF tools；缺失时返回 `PF-TOOLCHAIN-MISMATCH`，不得生成伪 ELF。

## 7. 部署/证明流程

Phase 1 在本地 runtime/validator 创建 program 与 state accounts，发送 init/increment/get instructions，核验 data 和错误。网络 deployment、upgrade authority 与 program id 分配由独立 network/deployment profile 管理。

## 8. 安全

检查 account substitution、owner confusion、missing signer/writable、PDA seed collision、duplicate mutable alias、CPI privilege escalation、unchecked account data 和 arithmetic/size bounds。

## 9. 验证阶梯

1. account schema/PDA/IDL golden。
2. Plan account-flow invariant 与 ELF validation。
3. Semantic interpreter 对照 sBPF emulator。
4. local runtime 完成 Counter 正常与 overflow rollback。
5. 可用时增加官方 validator deployment evidence。

## 10. 不支持、风险与成熟度退出

Phase 1 不承诺 Token-2022、复杂 CPI、zero-copy、upgradeable loader 管理或任意 remaining accounts。退出条件：同源 Counter、typed account plan、真实 ELF、local runtime、错误负例和确定性制品全部通过。
