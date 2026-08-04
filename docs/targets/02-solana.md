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
- **Mollusk 运行时差分**（`runtime-tests/solana`：Counter + 18 既有 fixtures +
  `Examples/TransferSol.lean` 产品 CPI ELF = 20 programs；含 body 多宽、聚合/匿名返回、
  Option state 与原生 System transfer；legacy call 已从旧 profile runtime 面移除）；
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
- **`pf.assets` native binding（ADR-0029 Phase B1，2026-08-05）**：`solana-sbpf-cpi-elf-v1`
  advertise exact `extension.pf-assets`（resolver multi-permit；产品 capability = sync +
  至少一个 closed extension 且各 requested extension 须落 SupportClaim）。vault 为
  program-owned PDA（frozen seed `proof-forge:vault:v1`、canonical bump 255..1、
  rent-exempt 890880 lamports、zero data）。`pf.assets.native.deposit` → 幂等 ensure
  （fresh System vault 经 `createPdaAccount`，owner 三态 closed alternatives：
  current-program skip / System-fresh create / 其余 FC）+ caller→vault System CPI
  （synthetic `pf_caller`：该 handler 恰好一个 outer signer，多/零 FC）；
  `pf.assets.native.transfer` → vault→dst **program 直接 lamports debit/credit**
  （System 依法不能 debit program-owned 账户 `ExternalAccountLamportSpend`；
  PDA key join + 下溢 FC）。QN 门：catalog QN 须 exact `extension.pf-assets` row；
  token/async 与 generic 非 catalog 保持 FC。Mollusk 工程门 `runtime-tests/solana`
  **15** binaries / **324** active（`tipjar_assets` **12/12**：init/view/tip 成功/
  幂等 ensure/underfunded 完整 snapshot rollback/错误 PDA/多·零 signer 拒绝）；
  产品纵切 `Tests/Product/TipJarSolanaV1`（`TipJar.so` + exact closure）。

**明确未闭合**：formal Solana milestone / Stage-0 hermetic runtime；formal identity/OutputSet；
完整 Normalize 表面；active CPI profile 之外的任意动态 program address/remaining accounts 与更广
callee catalog。legacy profiles 对 call/schedule 继续 fail closed；只有 opt-in
`solana-sbpf-cpi-elf-v1` 可按 exact catalog/program identity 物化多账户 CPI，不能把它泛化为任意
static-QN 或动态地址支持。registry 历史标签可能仍显示 `plan-only` 字符串——**工程事实以本段与
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

**CPI profile 预激活输入形态（#118，非产品 artifact/非 CPI）**：handler local roles按 Plan position
精确密集排列，数量上限 16；walker先检查每个 full marker/ODL/bool/rent，再按 direct-mapped growth span
和 8-byte alignment做 checked virtual cursor walk，随后核对 program-id 后 zero padding与 pointer table。
probe instruction data固定为 exact 8-byte LE handlerId。每个 handler在任何业务执行前检查 role key
pairwise distinct、state/current-program join、fixed callee key/loader owner/executable、site account
owner/data与 joined signer/writable。测试 emitter不执行业务 body或 CPI，只在全部检查成功后返回 0；
locked `sbpf disassemble` 还直接要求最终 ELF 零 `call` 指令。raw-image 模型独立覆盖非规范 marker/bool/
original-data-len/rent/padding/pointer-table/truncation/overflow，Mollusk `AccountMeta` 路径只承诺 canonical
Loader 输入并执行所有相邻 swap与 leading/middle/trailing missing/extra负例。

**#119 unsigned companion CPI（仍 test-preactivation；#125 后 companion 三 API 仍 product-denied）**：
独立 `CpiUnsignedIRV1`/`EmitCpiUnsignedSbpfV1` 在 #118 authority 之上发射真实 `sol_invoke_signed_c`
（零 signer groups）到 pinned companion-v1；#118 no-invoke 链保持独立。site checks 在每个 invoke 前
site-time 执行；fail 路径原样传播 syscall status 并完整 snapshot rollback。该 lane **不**成为 #125
product materialize authority；product path 另走 active catalog 五 API + product-ir。

**#125 product acceptance（工程，非 formal）**：ordinary `proof-forge-next build --target solana
--profile solana-sbpf-cpi-elf-v1` 产出 proof-forge.output.v1：5 base + `.so`；inspect 重走 exact
closure；manifest/evidence 绑定 active profile/catalog digests。Principal 仍 opaque。

**通用 Solana client + TransferSol 本地调用闭环（工程，非 formal）**：
`clients/solana-client` 的 `proof-forge-solana-client` 先独立重验通用 OutputSet，再对当前三个
Solana profile 做 closed dispatch；默认验证不钉程序名、source hash 或某一业务 ABI，未知 profile
fail closed。程序约束通过显式 `--program-adapter` 扩展。首个 `transfer-sol-v1` adapter 对
`Examples/TransferSol.lean` 的 `solana.system.transfer` 产品固定 handler 0、16-byte outer ABI、
payer/recipient/System 角色、Plan/IR/IDL/bindings joins 与 source pin；
`just solana-transfer-sol-local` 随后在本地 SVM 加载同一 manifest-bound ELF，并运行 8 个聚焦测试
（其中 6 个加载执行 ELF）。该表面不含 RPC、Devnet、airdrop、wallet/keypair、Program ID 或部署；
若需部署，由 operator 在自己的本地 validator 工具链完成。OutputSet/profile 校验是工程自洽，
本地 Mollusk 观测也不属于 signed provenance、hermetic 或 formal 证据。

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


> **Solana CPI epic #111–#125 engineering closed** (#110 engineering epic complete): legacy profiles fail closed on call/schedule; exact `solana-sbpf-cpi-elf-v1` advertises sync+extension (async still FC); CpiEscrowIRV1 composite escrow remains test-preactivation history; product activation is ordinary-resolver product capability (not formal TASK-D5).
