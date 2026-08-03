---
id: TARGET-SOLANA
title: Solana target dossier
status: proposed
owner: architecture
updated: 2026-08-04
normative: true
---

# Target Dossier：Solana

状态：`proposed`
Target ID：`solana`
Phase 1：实现

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 读取 retained `SemanticProgramV1`，structure-gate 后 private lowering；
module 内无 alpha residual Plan route。carrier/identity 为 `CompiledSemanticV1` + canonical Digests。

**工程已接线（摘）**：

- Normalize 当前可 lower 的控制流/算术/fn/for/shift/bitwise/revert/emit 等子集（非完整 Semantic 面）；
- state/param/result **UInt8/16/32/64 与窄 Int** ABI/body 子集（UInt128/256 软件多字已开 T9e）；
- **`EmitSbpfAsmV1`** 完整 Operation 表面 → 锁定 `sbpf` 汇编为 deployable Solana ELF `.so`
  （`solana-sbpf-elf-v1` profile；默认仍可走 plan-only profile）；
- **Mollusk 运行时差分**（`runtime-tests/solana`：Counter + 18 fixtures = 19 programs；
  含 body 多宽、聚合/匿名返回、Option state；legacy call 已从 runtime 面移除）；
- **legacy call/schedule 已恢复 fail closed**（#111）：`solana-sbpf-plan-v1` 与
  `solana-sbpf-elf-v1` 均不声明 sync/async requirement，Plan/IR/SBPF 纵深拒绝旧节点；static
  QualifiedName 不再经 SHA-256 冒充 program id；真实多账户/PDA/bump/CPI 由 opt-in versioned
  profile epic [#110](https://github.com/DaviRain-Su/proof_forge/issues/110) 分批实现；
- **dense Map UInt64 cap-8 pilot** 已进入 opt-in ELF + Mollusk；`storeAggregate` → structural CSE →
  `storeStateMulti` 令同一 StateStore 的 24 叶先基于旧 account snapshot 求值、再统一写入，且保持
  177 temp / 1424B < 4096B frame。`put_into_empty` 已解除 ignore 并转绿；WideMul 另以
  独立 base-2^64 oracle 钉住 UInt128/256 成功与 `0x1001` 溢出回滚；PrincipalStore 固定
  `len + 8×UInt64` identity state/param、逐叶 equality 与短值覆盖高位清零（非 pubkey）；
- **#113 V1 单 state-account 安全矩阵**：IR/SBPF `num_accounts==1` + non-dup `0xff` 先于固定偏移；
  Mollusk 负例 Custom(1)+完整 exact snapshot；manifest-bound ELF/Plan 字节；
- **Option UInt64 state（BL-29）**：`slot_tag`/`slot_p0` 双 u64-LE leaf，`none` 清零 stale payload，
  assign 走多叶原子 store；Option params、非 UInt64 payload与 nested Option 仍 fail-closed；
- **≤8 叶聚合返回**：named Struct/Enum 与 anonymous Array/Option UInt64 经单次
  `sol_set_return_data` 发 N×8-byte LE；Map/Bytes/nested/非 UInt64元素返回仍 fail-closed。

**明确未闭合**：formal Solana milestone / Stage-0 hermetic runtime；formal identity/OutputSet；
完整 Normalize 表面；CPI 外层多账户布局与成功调用尚未闭合，static-QN program id 仍是 hash stub，
不是动态 pubkey/address。registry 历史标签可能仍显示 `plan-only` 字符串——**工程事实以本段与
coverage matrix 为准**。

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

首个通用 planning 基线使用一个显式 state account：8-byte target-owned header
后按声明顺序保存 little-endian `UInt64`。该历史基线已经扩到多宽 ABI/body、真实 SBPF assembly、
opt-in ELF 与 Mollusk；**默认 profile 仍是 non-deployable plan**，但不能再把整个 Solana 工程面
写成“没有 ELF/runtime”。header 绑定 layout version 与 initialized 状态；initializer 只接受未初始化
账户，entry/view 只接受已初始化账户。instruction data 使用 8-byte discriminator + target-owned
little-endian参数布局；discriminator 固定为
`SHA-256("proof-forge-solana-v1:" || canonical-signature)[0..8]`，避免按声明序编号造成 ABI 漂移。

当前单账户 provisioning policy 要求 `initialize` 时 state account 自身为 signer、program-owned、
writable 且 header 为 zero；成功后写入版本化 initialized marker。**V1 初始化消费的是已存在的
program-owned account（caller 预先 create/allocate/assign）**，不是 System Program
create/allocate/assign 或 PDA 派生。mutate 不再要求 signer，view 声明 readonly。这个 signer 是
Solana 账户创建/初始化绑定，不是从业务 DSL 推导出的 authority；未来引入 PDA/authority 扩展时
必须用新的显式 Plan policy/version，不能静默替换。

**V1 序列化输入形态（#113 工程 hardening，非 multi-account/CPI）**：IR `checks` 以
`num_accounts == 1` 与 `account[0].dup_marker == 0xff` 打头，再做 instruction_data 精确长度、
owner==current_program、exact data_len、可选 signer/writable、headerEquals。SBPF entrypoint
在任何固定 `INSTRUCTION_*`/`ACC0_*` 绝对偏移加载前复检该 account-list shape；失败与未知
discriminator 同为 `program_error` / `Custom(1)`。固定 layout 仍由 `computeInputLayoutV1`
从单一 full account 推导。Mollusk 负例矩阵覆盖 missing signer、not writable、double init、
uninitialized/malformed marker、wrong owner、short/long data、0/2 accounts、duplicate meta、
instruction 长度 0/7/短参/trailing，且每例用完整 exact account snapshot（#112 helper）证明无提交。

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
