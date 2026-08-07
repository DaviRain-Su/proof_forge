---
id: TARGET-PSY
title: Psy target dossier
status: draft
owner: architecture
updated: 2026-08-07
normative: true
---

# Target Dossier：Psy

状态：`draft`
Target ID：`psy`
Phase 1：实现（工程切片已接线；成熟度 source-only）

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 直接读取 `CompiledSemanticV1.semanticV1Of`，private lowering 构造 target-owned `PsyPlan`。

**工程已接线（摘）**：标量 UInt8/16/32/64、Int64、Bool、Unit 与 exact Goldilocks Field envelope；named Struct/Enum、Array UInt64 与 Option UInt64 按 Felt leaves 展平；标量 `Op.Constant` 复用同一 canonical literal decoder/Plan 表达式（当前产品源码开放 UInt8/16/32、Bool、`UInt64 < p` 与非负 Int64 const，窄 UInt width metadata 保留；Goldilocks ConstantV1 target-internal 路径同构）；sync call（`__invoke_sync`）与 event（`__emit`）；Dargo/Psy source（`psy-dargo-u64-v1`）。注意：Emit 层把 UInt 字面量按 Goldilocks 模约（`feltNat`），这是 **UInt→Felt 字面量归约**，**不是** Field 类型支持；Constant 没有新增 ABI、target const 声明或独立 emitter primitive。

**明确边界**：T14 已把 exact Goldilocks FieldSpec 接到 Psy Felt；bn254 与 BLS12-377 在 Psy 上仍 fail-closed。**Commit 仍 fail-closed**：虽然 shared Semantic 值级契约是 label-only identity，但 Psy 尚未冻结 proof/public-input/commitment binding，不能把普通 Felt passthrough 冒充密码学承诺。Map/Bytes/Principal/String、aggregate constants、负 Int64 constant、`UInt64 ≥ Goldilocks p` constant 与 `CheckedCast` 显式 fail-closed；canonical two's-complement 负值不能直接交给 `feltNat`；Option 只开放 `Option UInt64` state 与受限 entry/view result，Option params/非 UInt64/nested 仍 fail-closed；UInt64 `~` 已降为 `checkedBitNot`（assert `x ≥ 2^32−1` 后 Felt sub `(2^32−2)−x`，可表示半区精确 UInt64 bitNot；`x ≤ 2^32−2` 运行时 trap；**非** mod-p bitNot；Int64 `~` 仍 fail-closed）；resolver 拒 async-workflow(schedule)；有 optional host `psyup`/`dargo` source compile 验收，但无 Tool Lock pin、VM/prover 门；成熟度 **source-only + optional host compile**，不得写成 runtime/formal 完成。**ADR-0029 Phase D（2026-08-05）**：`pf.assets` 五 QN **零绑定**——Psy 无原生资产/金库本征（Felt 是算术域不是资产单位；`__invoke_sync#<Felt>` 只是源码面发射、无真实资金移动，绑它就是假建模），无 deposit 对应物；catalog QN 在 Plan 层显式 unbound 诊断（不降级为 `__invoke_sync`）、resolver 不 advertise、resolve 处 `PF-REQ-UNSUPPORTED`（`Tests/Materialization/PsyPfAssetsV1` 钉死）。

## 1. 身份与来源

Psy 公开材料描述 PARTH 用户分区状态、本地 Contract Function Circuit（CFC）证明、User Proving Session（UPS）递归聚合和网络最终证明，因此应归为 ZK application chain，而非纯 circuit。依据 [Psy Documentation](https://psy.xyz/docs) 与 [Privacy](https://psy.xyz/privacy)；材料处于 pre-testnet 阶段，全部为 provisional。编译器仓库只记录 research snapshot `24f5ec9`，尚未形成受支持工具链。

## 2. 执行、状态、调用、失败与资源

- 执行：候选模型是用户本地执行/证明 CFC，再在 UPS 和网络层递归聚合。
- 状态：用户 UCON/CSTATE 分区；写本用户分区，跨用户读取使用历史/已 final 状态的具体规则待版本化规范确认。
- 调用：contract call 如何映射到多个 CFC、UPS 顺序与跨用户交互仍需 live tooling 验证。
- 失败：local execution/proof、UPS aggregation、network rejection/finalization 需分别建模。
- 资源：proof time/memory、state delta、aggregation 和 data availability cost 尚无冻结 profile。

## 3. Portable fragment 与扩展

候选 portable fragment：有限/固定整数、pure computation、private witness、user-owned logical state transition、explicit disclosure。

候选扩展：CFC、UCON/CSTATE paths、UPS ordering、historical global read、SDKey authorization、encrypted state delta、network aggregation。任何名称和 opcode 在源码生成前都需与版本化规范对齐。

## 4. `PsyPlan` schema（候选）

```text
PsyPlan {
  profile, userStatePartitions,
  cfcUnits, localInputs,
  publicCommitments, stateDeltas,
  upsOrder, authorizationCircuit,
  aggregationBindings, settlementPolicy
}
```

该 schema 是设计假设，不是已验证 API；字段必须在 sandbox MWE 后转入 normative spec。

## 5. Target IR 与制品

当前工程路径为 `PsyPlan → PsyIR → Dargo `.psy` source package`，并已进入 registry/capability materialization；该 source schema仍是 engineering profile，不承诺 VM bytecode、circuit/proof 或部署包的稳定格式。Finalize 为零工具、`deployable=false`，不得把 source package 写成可执行 artifact。

## 6. 工具链

待验证：compiler exact release/commit、语言/bytecode schema、Dargo/CLI、prover、local node/testnet、deploy/finalization。仓库 commit 存在不等于工作流可复现。

## 7. 部署/证明流程

预期研究闭环：编译最小 program → 部署/登记 → 本地 CFC proof → UPS aggregation → state delta 提交 → network finalization → 读取新状态。每步命令、版本、hash、日志和 failure case 都必须保存。

## 8. 安全

关注用户分区隔离、历史读取新鲜度、proof/state-delta binding、SDKey authority、encrypted delta disclosure、aggregation soundness、data availability 与 pre-testnet spec drift。

## 9. 验证阶梯

官方 claim/source review → pinned compiler MWE → bytecode/circuit inspection → local proof → UPS → local/test network finalization。当前只完成第一阶。

## 10. 不支持、风险与成熟度退出

accepted PRD 仍把 Psy 列为 Phase 1 design-only；当前 Recovery 工程则已接入 source-only target leaf，两者的范围差异尚无 accepted ADR 闭合。离开 source-only/research 成熟度的条件仍是稳定一手规格、可获取且许可明确的锁定工具链、完整 live MWE，以及状态/证明/finalization 语义无未决冲突。不得将它归入 Noir circuit family。

### 工程成熟度（C-2 / 2026-08-02）

树内为 target-owned Plan/IR/source 面；Goldilocks Field 已 LOWERED，bn254/BLS12-377 仍 FAIL-CLOSED。`PsyAcceptance` 在主机提供 psyup/dargo/std 时编译 source fixtures（缺席可 skip）；没有受支持 Tool Lock pin，也不运行 psy-vm/prover。成熟度保持 **source-only + optional host compile / research**，不得写成 VM 或证明完成。
