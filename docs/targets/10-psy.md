---
id: TARGET-PSY
title: Psy target dossier
status: draft
owner: architecture
updated: 2026-08-02
normative: true
---

# Target Dossier：Psy

状态：`draft`
Target ID：`psy`
Phase 1：实现（工程切片已接线；成熟度 source-only）

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 直接读取 `CompiledSemanticV1.semanticV1Of`，private lowering 构造 target-owned `PsyPlan`。

**工程已接线（摘）**：标量 UInt64/UInt32/Unit/Bool/Int64 envelope；named Struct/Enum + Array UInt64 flatten-to-Felt leaves；Commit 身份透传；sync call 与 event（`__emit`）；**Field Goldilocks（T14，p=2^64−2^32+1）→ Felt state/param/body**（不再 fail-closed，PsyEmissionFix 修字面量范围）；Dargo/Psy source（`psy-dargo-u64-v1`）。

**明确未闭合**：bn254 Fr 仍 fail-closed（Psy Felt=Goldilocks ≠ bn254）；Map/Bytes/Option/Principal/String/bitNot 显式 fail-closed；resolver 拒 async-workflow(schedule)；无 VM/prover 门；成熟度 **source-only**，不得写成 runtime/formal 完成。

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

候选路径：`PsyPlan → PsyIR/DPN operations → compiler artifact/circuit package`。现阶段不承诺 `.psy`、opcode 或部署包的稳定格式，不创建 emitter、registry production entry 或假 artifact。

## 6. 工具链

待验证：compiler exact release/commit、语言/bytecode schema、Dargo/CLI、prover、local node/testnet、deploy/finalization。仓库 commit 存在不等于工作流可复现。

## 7. 部署/证明流程

预期研究闭环：编译最小 program → 部署/登记 → 本地 CFC proof → UPS aggregation → state delta 提交 → network finalization → 读取新状态。每步命令、版本、hash、日志和 failure case 都必须保存。

## 8. 安全

关注用户分区隔离、历史读取新鲜度、proof/state-delta binding、SDKey authority、encrypted delta disclosure、aggregation soundness、data availability 与 pre-testnet spec drift。

## 9. 验证阶梯

官方 claim/source review → pinned compiler MWE → bytecode/circuit inspection → local proof → UPS → local/test network finalization。当前只完成第一阶。

## 10. 不支持、风险与成熟度退出

Psy 不在 Phase 1 implementation scope。离开 research 的条件：稳定一手规格、可获取且许可明确的工具链、完整 live MWE、状态/证明/finalization 语义无未决冲突。此前不得宣称 supported，也不得将它归入 Noir circuit family。

### 工程成熟度（C-2 / 2026-08-02）

树内为 target-owned Plan/IR/source 面；Psy Felt=Goldilocks 对 catalog bn254 **FAIL-CLOSED**。
**C-2 研究结论（`docs/research/15-aleo-psy-compiler-vm.md`）**：**不**升格 psy-vm / prover 验收门；无受支持工具链 pin。成熟度保持 **source-only / research**，不得写成 VM 或证明完成。
