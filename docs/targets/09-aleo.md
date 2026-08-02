---
id: TARGET-ALEO
title: Aleo and Leo 4 target dossier
status: proposed
owner: architecture
updated: 2026-08-02
normative: true
---

# Target Dossier：Aleo / Leo 4

状态：`proposed`
Target ID：`aleo`
Phase 1：实现（工程切片已接线；成熟度 source-only）

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 直接读取 `CompiledSemanticV1.semanticV1Of`，private lowering 构造 target-owned `AleoPlan`。

**工程已接线（摘）**：标量 UInt64/UInt32/Unit/Bool envelope（state/arith/compare/bitwise/shift/logical/pureCall/if/match/for/bare assert/bare revert）；named Struct/Enum + Array UInt64 flatten-to-mapping leaves；Commit 身份透传；**Field BLS12-377 Fr（T14）→ Leo native `field` state/param/body**（不再 fail-closed）；Leo 4.0.2 emission（`EmitIRV1`，`leo build --offline` 验收，工具缺席 skip）。

**明确未闭合**：bn254 Fr 仍 fail-closed（Aleo native = BLS12-377 ≠ catalog bn254）；Map/Bytes/Option/Principal/String/Int/call/schedule/event 均显式 fail-closed；无 prove/deploy/VM 门；成熟度 **source-only**，不得写成 runtime/formal 完成。

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

预期 `AleoPlan → Leo4AST → .leo → Aleo Instructions`。输出 Leo、compiled instructions、interface/record/mapping schema、transaction/proof metadata 和 manifest。printer 不得发出 Leo 3.x 兼容语法。

## 6. 工具链

实现时把 Leo 4.x exact patch（研究基准候选 4.0.2，但必须现场验证）与 Aleo SDK/VM 作为
CodegenProfile/toolchain closure 固定；network profile 只固定 chain/genesis/endpoint/deploy policy
并列出兼容 BuildIdentity。任一版本变化创建新 target semantics 或 CodegenProfile，不静默适配。

## 7. 部署/证明流程

compile → deploy program → execute proof-context fn → build transaction → public finalization → inspect records/mappings。local VM 完整通过后再 testnet。

## 8. 安全

关注 private/public 泄漏、record owner/custody、double spend、mapping key visibility、proof/final mismatch、Final payload substitution、program ID/network binding 和 upgrade authorization。

## 9. 验证阶梯

Leo4 AST/printer golden → compiler parse/typecheck → local proof execution → finalization state check → negative record/mapping cases → testnet transaction evidence。

## 10. 不支持、风险与成熟度退出

当前不实现。准入条件：冻结 Leo 4 patch/profile、完成 record 与 mapping 两条最小闭环、证明 disclosure/custody/finalization requirements 可精确推导。Aleo 不能复用 NoirPlan 或 PsyPlan。

### 工程成熟度（C-2 / 2026-08-02）

产品路径已有 target-owned Plan/IR/source package 与 B-1c coverage 钉（Field FAIL-CLOSED）。
**C-2 研究结论（`docs/research/15-aleo-psy-compiler-vm.md`）**：**不**在本波次升格真实 `leo` 编译验收门；无 Tool Lock pin 与 skip/fail-closed CI 门。成熟度声明保持 **source-only**，不得写成 compiler/VM 验收完成。
