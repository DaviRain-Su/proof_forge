---
id: TARGET-ALEO
title: Aleo and Leo 4 target dossier
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# Target Dossier：Aleo / Leo 4

状态：`proposed`
Target ID：`aleo`
Phase 1：设计，不实现

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
