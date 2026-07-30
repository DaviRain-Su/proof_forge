---
id: TARGET-SOLANA
title: Solana target dossier
status: proposed
owner: architecture
updated: 2026-07-30
normative: true
---

# Target Dossier：Solana

状态：`proposed`
Target ID：`solana`
Phase 1：实现

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 已直接读取 retained `SemanticProgramV1` 并在 target 内重新执行 structure gate；
Solana module 内 `alphaResidualOf`、`makePlanFromAlpha`、alpha requirement re-derive均已归零。当前只
lower NormalizeV1 当前 public-UInt64 envelope 的 anonymous UInt64/Unit、public state/params/results、
single-block initializer/entry/view 与 literal/stateLoad/checked add-sub/stateStore/return；dense `ValueId`、
expanded-tree cost及 store/return effect segment均 fail closed。checked-sub 在 typed audit IR 中保留同一
arithmetic error code并发射为 `checked_sub_u64`；产物仍是不可执行 plan text。

这只完成 shared migration leaf：现有产物仍是 `.sbpf-plan`+IDL 的不可执行审计制品，没有
sBPF assembly/ELF、validator runtime或 formal Solana milestone证据；产品 compiler/resolver/artifact identity
已切到 `CompiledSemanticV1` + canonical Digests，但 transitional v2alpha1 output contract尚未删除。

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

Phase-1 的首个通用 planning 切片使用一个显式 state account：8-byte target-owned header
后按声明顺序保存 little-endian `UInt64`。header 绑定 layout version 与 initialized 状态；
initializer 只接受未初始化账户，entry/view 只接受已初始化账户。instruction data 使用
`8-byte discriminator + little-endian UInt64 parameters`，Plan 明确记录每个参数 offset、state offset、
checked-add、store/return 与 writable 要求。discriminator 固定为
`SHA-256("proof-forge-solana-v1:" || canonical-signature)[0..8]`，避免按声明序编号造成 ABI
漂移。这个边界仍是 non-deployable typed audit plan，不是 sBPF assembly/ELF，也没有 local
runtime 证据。

当前单账户 provisioning policy 要求 `initialize` 时 state account 自身为 signer、program-owned、
writable 且 header 为 zero；成功后写入版本化 initialized marker。mutate 不再要求 signer，view
声明 readonly。这个 signer 是 Solana 账户创建/初始化绑定，不是从业务 DSL 推导出的 authority；
未来引入 PDA/authority 扩展时必须用新的显式 Plan policy/version，不能静默替换。

initialized marker 是
`SHA-256("proof-forge-solana-layout-v1:" || canonical-account-layout)[0..8]` 对应的 target
word，而不是所有合约共用常量；同长度但不同字段 schema 不可复用旧 header。为保持参考语义中
“init 从全零 state 开始”，initializer IR 在执行业务 init body 前显式清零全部 state fields，
包括业务 body 没有赋值的字段。

`solana-sbpf-plan-v1` 在 hash/lowering 前限制 ASCII identifier、最多 1024 个 UInt64 fields、
255 个 entries、每 handler 64 个参数、4096 statements、表达式深度 256 和 aggregate nodes
100000；`.sbpf-plan` 的 10-byte 后缀使 artifact stem 上限为 230 bytes。

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
   - 研究中的 ISA 地基：sibling `assembler-semantics`（`SbpfSemantics.Api` /
     `Observation`），见 [`../research/09-assembler-semantics-bridge.md`](../research/09-assembler-semantics-bridge.md)。
     未 pin 前不得作为 clean-room 或 release 证据。
4. local runtime 完成 Counter 正常与 overflow rollback。
5. 可用时增加官方 validator deployment evidence。

## 10. 不支持、风险与成熟度退出

Phase 1 不承诺 Token-2022、复杂 CPI、zero-copy、upgradeable loader 管理或任意 remaining accounts。退出条件：同源 Counter、typed account plan、真实 ELF、local runtime、错误负例和确定性制品全部通过。
