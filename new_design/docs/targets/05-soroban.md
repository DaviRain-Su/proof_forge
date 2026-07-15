---
id: TARGET-SOROBAN
title: Stellar Soroban target dossier
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# Target Dossier：Stellar Soroban

状态：`proposed`
Target ID：`soroban`
Phase 1：设计，不实现

## 1. 身份与来源

Soroban 在 Stellar host 中执行受限 Wasm，并以 XDR、host objects、授权树和带 TTL 的存储为关键边界。依据官方 [Contract Rust Dialect](https://developers.stellar.org/docs/learn/fundamentals/contract-development/rust-dialect)、[Persisting Data](https://developers.stellar.org/docs/learn/fundamentals/contract-development/storage/persisting-data)、[Authorization](https://developers.stellar.org/docs/learn/fundamentals/contract-development/authorization) 与 [State Archival](https://developers.stellar.org/docs/learn/fundamentals/contract-development/storage/state-archival)（`SRC-SOR-001..004`，verified）。

## 2. 执行、状态、调用、失败与资源

- 执行：合约函数在 Stellar transaction/host invocation 中同步执行。
- 状态：instance、persistent、temporary storage，均受不同 TTL/archival 规则影响。
- 调用：同步 contract invocation；authorization 由 `Address.require_auth` 和 invocation tree 表达。
- 失败：host/contract error 使 transaction 失败；错误编码进入 XDR/contract spec。
- 资源：CPU、memory、ledger read/write footprint、event 和 tx size 需模拟与计费。

## 3. Portable fragment 与扩展

Portable：Cell/Map、entry/view、checked arithmetic、event、transaction atomicity、authority predicate。

扩展：storage durability/TTL、opaque Address、auth tree、XDR/ScVal、footprint、token interface、Wasm hash upgrade。TTL 不是部署脚本细节，而是状态生命周期语义。

## 4. `SorobanPlan` schema

```text
SorobanPlan {
  profile, functions, contractSpec,
  xdrTypes, storageEntries, ttlPolicies,
  authorizationTrees, calls, events,
  resourceEnvelope, upgradePolicy
}
```

## 5. Target IR 与制品

`SorobanPlan → SorobanModuleRecipe → shared Wasm encoder`。输出 Wasm、contract-spec/custom sections、XDR schema、TTL/resource policy 和 manifest。不得把它实现成“NEAR Wasm + 不同 imports”。

## 6. 工具链

冻结 Stellar protocol、host/Wasm subset、stellar-cli、RPC simulation 和 SDK/XDR schema。所有 protocol feature 进入 profile。

## 7. 部署流程

本地 network 安装 Wasm → create contract → simulate/submit invoke → inspect events/storage/auth → extend/expire TTL → upgrade Wasm。部署 ID 与 source hash 进入 evidence。

## 8. 安全

关注 auth tree 重放/作用域、Address 类型误解、TTL 过期、archived state、footprint 不完整、resource fee、XDR canonical encoding 和 upgrade authorization。

## 9. 验证阶梯

contract spec/XDR golden → host Wasm validation → SDK host test → local Stellar network invoke/auth/TTL → testnet receipt。

## 10. 不支持、风险与成熟度退出

当前不实现。进入 implementation 前必须固定 protocol/profile，证明 custom sections、XDR、auth tree 和 TTL plan 可独立生成，并完成 Counter 的六级测试设计。不能把已有 Counter spike 等同完整后端。
