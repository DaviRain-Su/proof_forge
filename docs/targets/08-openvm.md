---
id: TARGET-OPENVM
title: OpenVM target dossier
status: proposed
owner: architecture
updated: 2026-08-15
normative: true
---

# Target Dossier：OpenVM

状态：`proposed`（engineering O0 implemented ADR-0045；O1 implemented ADR-0046）
Target ID：`openvm`
Phase 1：engineering leaf（**非** accepted PRD Phase 1）

## 1. 身份与来源

OpenVM 是模块化 zkVM，guest 编译为 RV32IM ELF/VmExe，并可生成 application、STARK 或
EVM-oriented proof。依据官方 [Overview](https://docs.openvm.dev/book/writing-apps/overview/)、
[Compiling](https://docs.openvm.dev/book/writing-apps/compiling-a-program/) 与
[Generating Proofs](https://docs.openvm.dev/book/writing-apps/generating-proofs/)
（核心模型 verified；prove 工具链仍属后续 profile）。

## 2. 执行、状态、调用、失败与资源

- 执行：guest 指令与启用的 VM extensions 决定可证明语义（O0 不执行 guest）。
- 状态：guest memory/I/O；没有原生链 persistent state（`state=guest-memory-io`）。
- 调用：guest 内普通调用（`call=guest-internal`）；portable `call`/`schedule` 在 O0 fail closed。
- 失败：guest trap、VM config mismatch、proof failure 分开（O0 仅编码 checked 算术/assert/revert 于 guest 源）。
- 资源：cycles、segments、extensions、proof mode、memory/prover cost（后续 profile）。

## 3. Portable fragment 与扩展

O0/O1 共享 portable 子集：public 齐次 UInt64 **或** Int64（混用 FC）/Bool/Unit、
anonymous `Array UInt64 N`（N=1..8）**state** flatten 为 N 个 guest `u64` 标量字段
`{name}_0`..`{name}_{N-1}`（无 `[u64; N]` / Vec；literal index only）、single-block、
checked `+`/`-`（unsigned `u64` / signed `i64::checked_*`）、bare
assert、zero-payload revert（ADR-0045）。Option/Map/Bytes/nested Array、Array
param/return、N∉1..8、非 UInt64 元素、非字面量下标、Array+signedNumeric Int64
均 fail closed。扩展（commit/reveal 之外的 guest I/O、RV32
extensions、crypto accelerators、continuations/aggregation、EVM proof mode）均未开放；
每项未来须绑定 OpenVM config hash。O1 只新增 Finalize-time build/transpile，不扩大
portable 子集或新增 requirement id。不声称 ELF/prove/formal。

## 4. `OpenVmPlan` schema（O0 + O1 共享）

```text
OpenVmPlan {
  profile = openvm-guest-source-v1 | openvm-guest-elf-v1,
  vmConfig = openvm-2.0.x-rv32im-stub-v1,
  guestInputs, publicValues,
  memoryLayout, entry,
  enabledExtensions = [],
  executableCommitment = none,
  proofMode = none,
  verifierBinding = none
  + Counter-shaped states/initializer/entries/views
}
```

两个 codegen profile 共用同一 `OpenVmPlan`/`GuestIR`/guest emission；`profile` 字段决定
Finalize 分支，不改变 Plan/IR 本身或 admitted capability（两者接受完全相同的四个
requirement key）。

## 5. Target IR 与制品

当前路径：`OpenVmPlan → GuestIR → controlled Rust guest source`（两个 profile 共享的
base materialize）。base 制品：`guest/Cargo.toml`、`guest/openvm.toml`、
`guest/src/main.rs`、`{program}.openvm-guest.json`（`artifactKind=source-only`，
`proofStatus=not-produced`）。

- **O0（`openvm-guest-source-v1`，默认）**：zero-tool finalize；base 制品即最终产物，无
  extras。
- **O1（`openvm-guest-elf-v1`，opt-in，ADR-0046）**：Finalize 额外解析锁定的
  `cargo-openvm` 2.0.1，在临时目录内对 staged guest tree 运行
  `cargo openvm build --manifest-path guest/Cargo.toml`，把产出的 RV32IM ELF 与
  `.vmexe` 分别 stage 为 `openvm-build/{program}`、`openvm-build/{program}.vmexe`
  extras。缺少 `cargo-openvm` → 稳定 `PF-TOOLCHAIN-MISSING` fail closed。

两个 profile 均 `deployable=false`；O1 只 build/transpile，**不** keygen、**不**
execute、**不** prove/verify。

Guest 生成策略（已决）：**受控 Rust 模板**（Lean 渲染；`no_std`/`no_main` +
`openvm::entry!(main);`；`openvm = "=2.0.1"` 声明依赖；`guest/openvm.toml` 声明
`app_vm_config.{rv32i,rv32m,io}`）。Lean direct guest 不在 O0/O1。

## 6. 工具链

意图主线：OpenVM **2.0.x**。默认 `openvm-guest-source-v1` **不** Tool Lock、不调用
OpenVM CLI / rustc guest / transpile / prove。opt-in `openvm-guest-elf-v1`（ADR-0046）
锁定 `cargo-openvm` 2.0.1（`https://github.com/openvm-org/openvm`, tag `v2.0.1`, commit
`b820b25baab6c5d9b055f64e0286b6b1058e707c`，Tool Lock `cargo-git` sourceBuild；
`requiredByProfiles=["openvm-guest-elf-v1"]`）只用于 build/transpile guest 为 ELF +
`.vmexe`；仍不调用 keygen/execute/prove/verify 工具链。禁止跨版本拼接。真实
keygen/prove/verify pin 留给后续 profile。

## 7. 证明流程

O0/O1：无 prove（O1 只 build/transpile executable）。后续：commit executable →
keygen（若需要）→ execute → prove → verify。EVM proof 只说明 verifier 形式，不赋予
chain storage/settlement。

## 8. 安全

关注 guest input ambiguity、public output omission、VM extension mismatch、ELF/VmExe
substitution、config commitment、host nondeterminism、unsafe guest code、proof recursion
与 verifier contract binding。O0/O1 通过 fail-closed 子集缩小暴露面；O1 额外要求
`cargo-openvm` 精确 commit/version 匹配，缺失即 fail closed 而非 best-effort fallback。

## 9. 验证阶梯

- **O0（已完成）**：registry/resolver/Plan/IR/guest-source emit + zero-tool finalize + Counter/StateCell/Int64Cell 正例与 unsupported 负例；工程 `Array UInt64 N`（N=1..8）state flatten 为标量 `u64` 字段（非 Option/Map/Array return/elf/prove/formal）。
- **O1（当前，ADR-0046）**：同一 Plan/IR 上的 opt-in `openvm-guest-elf-v1`；锁定
  `cargo-openvm` 2.0.1 build/transpile guest → RV32IM ELF + `.vmexe` extras；缺失工具
  fail closed（`PF-TOOLCHAIN-MISSING`）；host-optional acceptance（ambient 工具存在时
  验证 extras 非空）。
- **后续**：ELF/VmExe validation → deterministic execute → app proof →
  STARK/EVM proof profile（若选择）→ external verifier negative cases。

## 10. 不支持、风险与成熟度退出

Registry maturity = `source-only`；acceptance = `research.openvm.v1`；`deployable=false`
（O0 与 O1 均不变）。不得宣称 deployable contract 或 `verifiable-workload`（后者留给
proof/VK profile）；O1 的 build/transpile 只是工程 packaging 步骤，不构成 execute/prove
证据。下一 profile 准入：keygen/execute/prove/VK MWE、Counter I/O + proof binding、
资源基线。Formal D3/D4 与 accepted PRD 扩面不因 O0/O1 完成。
