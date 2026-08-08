---
id: TARGET-ALEO
title: Aleo and Leo 4 target dossier
status: proposed
owner: architecture
updated: 2026-08-08
normative: true
---

# Target Dossier：Aleo / Leo 4

状态：`proposed`
Target ID：`aleo`
Phase 1：实现（工程切片已接线；成熟度 source-only / compile-only）

## 权威物化方向（2026-08-08 产品决策）

**主线：Aleo Instructions IR**（官方中间 IR，对标 Psy DPN），**不是**长期 sole Leo 源语法。
规划 sole 输入：[`09-aleo-instructions-lowering.md`](09-aleo-instructions-lowering.md)。
**IR-0..IR-7 / G0–G6 + G5-MATRIX + G5-HARD + RES-CLEAN engineering closeout（2026-08-08）**：`Targets/Aleo/Instructions/{SchemaV1,TextCodecV1,LowerPlanV1}` +
Counter 金样 `testdata/golden/aleo-instructions-v1/counter.compiled.aleo`（locked Leo 4.0.2）；
`programFromCapabilityV1` Counter Plan→Instructions ≡ 金样；if/match/bounded-for →
`branch.eq`/`position`/静态 for-unroll；multi-leaf Map/Option/Array + narrow UInt；
IR-5 效果诚实矩阵（emit/payload-revert Plan FC；call/schedule/assets/context 产品 FC，无 PARTIAL 假 Y）；
**G5-HARD** Int64/Field BLS12-377/pureFn inline true lower + 空 allowlist `ALEO-IR-G5-HARD`；
**产品 primary** = Instructions 文本 `{id}.aleo`（Counter ≡ golden）；query-contract 不变；
Leo 4 源 debug-only（`PROOF_FORGE_ALEO_EMIT_LEO=1` / `emitLeoDebug` → `{id}.leo`；
compile profile 双写供 locked-leo compare extras）；**IR-7/G6 runtime honesty PARTIAL+MISSING**
（无 locked snarkVM package-only；`just aleo-runtime` → `PF-TOOLCHAIN-MISSING`；不发明 CLI）。
**RES-CLEAN** residual honesty closeout：sole Counter full-byte golden；deferred multi-program
leo 金样 / record custody / prove/deploy / full opcode。不得把 Leo 源写成长期 sole 权威。
Lane **idle**。**诚实 residual**：full opcode / record / prove deferred（见规划 §10）。

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 直接读取 `CompiledSemanticV1.semanticV1Of`，private lowering 构造 target-owned `AleoPlan`。

**工程已接线（摘）**：标量 UInt64/UInt32/UInt8/Int64/Unit/Bool envelope（state/arith/compare/bitwise/shift/logical/pureCall/if/match/for/bare assert/bare revert）；named Struct/Enum + Array UInt64 flatten-to-mapping leaves；**dense Map UInt64 cap-2**（occ/key/val leaves + IndexGet→Option + IndexSet upsert；`storeAggregate` 先完成全叶 `get_or_use`/值绑定再统一 `set`，固定 pre-store snapshot）；**fixed Bytes N**（N×u8 mappings + checked u8 lane）；**Option UInt64 state（B-OPT-STATE / BL-35）** tag+payload 双 mapping 叶（entry-surface match；computed view-over-state 与 Option params 仍 FC）；Commit 身份透传；Leo 4.0.2 emission。**ALEO-I1** 已以 `pf.aleo-plan.engineering.v1` 将 canonical Plan content digest 接入 Registry/BuildIdentity。**ALEO-I2** 让产品有序发出 `.aleo` 与 `.aleo-query-contract.json` 两个 base artifacts；sidecar 绑定 source/semantic identity、public mappings、bare views 与 `resultDropped`，但不执行查询。**ALEO-I3** 将两平台 Tool Lock 与 locked-only acceptance 收紧。**ALEO-I4** 新增显式 `aleo-leo-4.0.2-u64-compile-v1`：与 source profile 共享同一 Plan/planDigest，但 support claim/BuildIdentity 不同；产品 Finalize 只消费 `.aleo` base，在临时 package + 隔离 HOME 中执行 locked offline build，并发布三个 compiler extras。`AleoAcceptance` 继续覆盖更宽 source corpus（未物化时 clean skip；含 OptionState fixture）。

**明确边界**：T14 已把 exact BLS12-377 Fr FieldSpec 接到 Leo `field`；bn254 与 Goldilocks 在 Aleo 上仍 fail-closed。**Option 仅 UInt64 state 与 anonymous entry/view return LOWERED**；Option params/nested/非 UInt64、Principal/String/Int128/256/emit/call/schedule/ContextRead 均显式 fail-closed。query-contract 是 `network-state-descriptor`：`leo query` 仍需网络，Final 也不能返回 `resultDropped` 的原值；computed/multi-leaf state view 继续 FC。没有 prove/deploy/VM 门，compile-only 也不是 hermetic/formal 证据；成熟度为 **source emission + engineering locked compile finalization**，不得写成 runtime/proof 完成。**ADR-0029 Phase D（2026-08-05）**：`pf.assets` 五 QN **零绑定**——Aleo 资产主模型是 record（owner-bound consume/mint）而非 account-balance vault，`credits.aleo/transfer_public` 走 private-proof + public finalize 不满足 sync 原子 failure 传播；catalog QN 在 Plan 层显式 unbound 诊断、resolver 不 advertise、resolve 处 `PF-REQ-UNSUPPORTED`（`Tests/Materialization/AleoPfAssetsV1` 钉死）。record custody 五轴差异分析存于 `Targets/Aleo/PfAssetsDispositionV1.lean`，为未来 custody v2 设计种子。**Uniswap/MiniAMM 路径：park**（token transfer / balanceOfSelf / caller 全 FC）。

## 1. 身份与来源

Aleo 是带私有 proof execution 和公共 on-chain finalization 的 ZK application chain。采用 Leo 4.0 的 `fn`、`final`、`Final` 术语，禁止以旧 async/Future 模型设计。依据官方 [Leo 3.5→4.0 Migration](https://docs.aleo.org/build/leo/documentation/guides/migration-3-5-to-4-0/index.html)、[Types](https://docs.aleo.org/build/aleo-instructions/reference/types/index.html)、[Finalize Operations](https://docs.aleo.org/build/aleo-instructions/reference/finalize-operations/index.html) 与 [Transactions](https://docs.aleo.org/learn/core-concepts/transactions/index.html)（`SRC-ALEO-001..004`，verified）。

## 2. 执行、状态、调用、失败与资源

- 执行：`fn` 在私有 proof context；`final {}`/`final fn` 在公共 finalization context。
- 状态：owner-bound records 与 public mappings/storage 的托管、披露和消费语义不同。
- 调用：program calls 需区分 proof execution 与 finalization effects。
- 失败：proof unsatisfied、record ownership/nonce、finalization rejection 分开。
- 资源：constraints、records、finalize limits、transaction fees 和 network rules。

## 3. Portable fragment 与扩展

Portable：固定整数/field、struct、pure computation、disclosure、authority、state transition、checked assertions。

扩展：Aleo address/scalar/group/field、record mint/consume、mapping get/set、program call、Final payload、constructor/upgrade policy。record custody 不能由通用 `private` 推导。

## 4. `AleoPlan` schema

```text
AleoPlan {
  profile, programId,
  records, mappings, storage,
  proofFunctions, finalBlocks,
  calls, disclosureMap,
  custodyRules, feeAssumptions
}
```

## 5. Target IR 与制品

**现状（IR-6 + G5-HARD closeout）**：`Aleo Plan → Instructions` 为产品 primary `{id}.aleo`（官方中间 IR）；
transitional Leo 4 源为 `{id}.leo`（debug/compare）。G5-HARD：residual allowlist 空，Plan admitted
且 Instructions lower fail → `ALEO-IR-G5-HARD`（禁 silent Leo-only primary）。Plan identity 由
`pf.aleo-plan.engineering.v1` content digest 绑定。
产品 materialize 的有序 base artifacts 为：

1. `{programId}.aleo`（**Aleo Instructions** 文本；`LowerPlanV1` 成功路径 ≡ Counter golden）
2. `{programId}.aleo-query-contract.json`（schema
   `proof-forge-aleo-query-contract/v1`）

可选/对照：`{programId}.leo`（Leo 4 源；`PROOF_FORGE_ALEO_EMIT_LEO=1` / `emitLeoDebug`；
compile profile 始终双写供 locked-leo compare）。query-contract 是 public mapping / bare view /
dropped-result 的固定键序 network-state descriptor，受 exact artifact content hash/manifest
closure 约束；它不是 Leo `build/abi.json`、不是 executable query，也不作为 compiler input。
默认 source profile 的 Finalize 仍 zero-tool。显式 `aleo-leo-4.0.2-u64-compile-v1` Finalize
在临时 package/隔离 HOME 中运行 locked offline build，并只复制三个 `finalized-extra`：
`{programId}.compiled.aleo`（Instructions 面，IR 金样/对照）、`{programId}.abi.json`、
`{programId}.leo-program.json`。两 profile 均 `deployable=false`。不得发出 Leo 3.x 兼容语法。

**规划收口**：IR-7/G6 runtime honesty **done PARTIAL/MISSING（2026-08-08）**
（`just aleo-runtime` → `PF-TOOLCHAIN-MISSING`；无 locked package-only execute）；
**RES-CLEAN done**；Lane **idle**。见
[`09-aleo-instructions-lowering.md`](09-aleo-instructions-lowering.md) §10。

## 6. 工具链

工程 Tool Lock v4 已在 darwin-arm64 与 linux-x86_64 固定 Leo `4.0.2` 的下载资产、
executable digest 与 version probe，`requiredByProfiles` exact join source + compile 两个
profile。`AleoAcceptance` 与 compile-profile product Finalize 均只接受显式 tool root 或
package cache 中的 locked binary，无 PATH/cargo/brew fallback；在隔离 HOME/secret/network
env 下仅运行 `leo build --offline --disable-update-check`。产品 compile profile 对工具缺失或
任一预期输出缺失 fail closed 且零发布。Aleo SDK/VM、CRS、snarkOS/snarkVM 与 proof/deploy
runtime 仍未固定。任一版本变化创建新 target semantics 或 CodegenProfile，不静默适配。

## 7. 部署/证明流程

compile → deploy program → execute proof-context fn → build transaction → public finalization → inspect records/mappings。local VM 完整通过后再 testnet。

## 8. 安全

关注 private/public 泄漏、record owner/custody、double spend、mapping key visibility、proof/final mismatch、Final payload substitution、program ID/network binding 和 upgrade authorization。

## 9. 验证阶梯

Leo4 AST/printer golden → compiler parse/typecheck → local proof execution → finalization state check → negative record/mapping cases → testnet transaction evidence。

## 10. 不支持、风险与成熟度退出

当前工程仅实现 target-owned Plan/IR/source package 与 public mapping pilot，不实现 record custody、prove/deploy 或 VM runtime。进入更高成熟度前仍须冻结 Leo 4 工具链 profile、完成 record 与 mapping 两条最小闭环，并证明 disclosure/custody/finalization requirements 可精确推导。Aleo 不能复用 NoirPlan 或 PsyPlan。

### 工程成熟度（C-2 / ALEO-I1–I4，2026-08-07）

产品路径已有 target-owned Plan/IR/source package、canonical Plan content digest 与 content-bound
query-contract sidecar。默认 profile 保持 zero-tool；显式 compile profile 以两平台 Tool Lock 中的
Leo 4.0.2 执行 offline compile-only Finalize，发布三个 content-bound compiler extras，并由
产品双次构建、缺失/坏工具零发布负例和 `inspect` exact disk closure 覆盖。
`AleoAcceptance` 仍提供更宽 source corpus 的 host-optional compile gate。RPT-024 确认
`leo run` 仅为解释器、execute/deploy/query 依赖网络、synthesize 需要未锁定 CRS，且仓库无
pinned snarkOS/snarkVM。**ALEO-IR-7（2026-08-08）** 将 runtime honesty 钉为
**PARTIAL + MISSING**：`scripts/aleo_runtime_test.sh` / `just aleo-runtime`（非 ordinary
ci）在 tool root 无 snarkVM/snarkOS 时以 `PF-TOOLCHAIN-MISSING` fail closed，不发明
package-only CLI，也不把 `leo run` 升格为 Instructions 运行时。该产品 finalization 仍
`deployable=false`，不验证 VM、proof、deploy 或 public finalization，也不是
formal/hermetic Stage-0 证据。成熟度声明为
**source emission + engineering locked compile finalization**（runtime execute MISSING）。
