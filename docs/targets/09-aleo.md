---
id: TARGET-ALEO
title: Aleo and Leo 4 target dossier
status: proposed
owner: architecture
updated: 2026-08-03
normative: true
---

# Target Dossier：Aleo / Leo 4

状态：`proposed`
Target ID：`aleo`
Phase 1：实现（工程切片已接线；成熟度 source-only）

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 直接读取 `CompiledSemanticV1.semanticV1Of`，private lowering 构造 target-owned `AleoPlan`。

**工程已接线（摘）**：标量 UInt64/UInt32/UInt8/Int64/Unit/Bool envelope（state/arith/compare/bitwise/shift/logical/pureCall/if/match/for/bare assert/bare revert）；named Struct/Enum + Array UInt64 flatten-to-mapping leaves；**dense Map UInt64 cap-2**（occ/key/val leaves + IndexGet→Option + IndexSet upsert；`storeAggregate` 先完成全叶 `get_or_use`/值绑定再统一 `set`，固定 pre-store snapshot）；**fixed Bytes N**（N×u8 mappings + checked u8 lane）；Commit 身份透传；Leo 4.0.2 emission。Leo 4.0.2 已进入两平台 Tool Lock v4，`AleoAcceptance` 优先使用物化的 locked tool 执行 `leo build --offline` compile-only 验收（未物化时 clean skip）。

**明确边界**：T14 已把 exact BLS12-377 Fr FieldSpec 接到 Leo `field`；bn254 与 Goldilocks 在 Aleo 上仍 fail-closed。Option/Principal/String/Int128/256/emit/call/schedule/ContextRead 均显式 fail-closed；没有 prove/deploy/VM 门，compile-only 也不是 hermetic/formal 证据；成熟度仍为 **source-only + engineering compile acceptance**，不得写成 runtime/proof 完成。

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

工程 Tool Lock v4 已在 darwin-arm64 与 linux-x86_64 固定 Leo `4.0.2` 的下载资产、
executable digest 与 version probe，供 compile-only acceptance 使用；Aleo SDK/VM、proof/deploy
runtime 与相应 CodegenProfile closure 仍未固定。network profile 只固定
chain/genesis/endpoint/deploy policy 并列出兼容 BuildIdentity。任一版本变化创建新 target
semantics 或 CodegenProfile，不静默适配。

## 7. 部署/证明流程

compile → deploy program → execute proof-context fn → build transaction → public finalization → inspect records/mappings。local VM 完整通过后再 testnet。

## 8. 安全

关注 private/public 泄漏、record owner/custody、double spend、mapping key visibility、proof/final mismatch、Final payload substitution、program ID/network binding 和 upgrade authorization。

## 9. 验证阶梯

Leo4 AST/printer golden → compiler parse/typecheck → local proof execution → finalization state check → negative record/mapping cases → testnet transaction evidence。

## 10. 不支持、风险与成熟度退出

当前工程仅实现 target-owned Plan/IR/source package 与 public mapping pilot，不实现 record custody、prove/deploy 或 VM runtime。进入更高成熟度前仍须冻结 Leo 4 工具链 profile、完成 record 与 mapping 两条最小闭环，并证明 disclosure/custody/finalization requirements 可精确推导。Aleo 不能复用 NoirPlan 或 PsyPlan。

### 工程成熟度（C-2 / 2026-08-02）

产品路径已有 target-owned Plan/IR/source package 与 B-1c/T14 coverage 钉。G123 已将 Leo 4.0.2 纳入两平台 Tool Lock；`AleoAcceptance` 优先解析物化的 locked tool 并执行 `leo build --offline`（工具未物化时可 clean skip）。该门仍不验证 VM、proof 或 deploy，也不是 formal/hermetic Stage-0 证据。成熟度声明保持 **source-only + engineering compile acceptance**。
