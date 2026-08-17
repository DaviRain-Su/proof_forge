---
id: TARGET-SOROBAN
title: Stellar Soroban target dossier
status: proposed
owner: architecture
updated: 2026-08-16
normative: true
---

# Target Dossier：Stellar Soroban

状态：`proposed`（engineering S0 implemented；accepted Phase 1 仍不含）
Target ID：`soroban`
Engineering：ADR-0044 **source-only S0**（`soroban-source-u64-v1`）
Phase 1 accepted PRD：仍为四目标；本 target 不静默扩面（ADR-0036）

## 1. 身份与来源

Soroban 在 Stellar host 中执行受限 Wasm，并以 XDR、host objects、授权树和带 TTL 的存储为关键边界。依据官方 [Contract Rust Dialect](https://developers.stellar.org/docs/learn/fundamentals/contract-development/rust-dialect)、[Persisting Data](https://developers.stellar.org/docs/learn/fundamentals/contract-development/storage/persisting-data)、[Authorization](https://developers.stellar.org/docs/learn/fundamentals/contract-development/authorization) 与 [State Archival](https://developers.stellar.org/docs/learn/fundamentals/contract-development/storage/state-archival)（`SRC-SOR-001..004`，verified）。

## 2. 当前 engineering 状态（S0）

| 项 | 值 |
|---|---|
| Profile | `soroban-source-u64-v1` |
| Encoding | `sorobanSource`（`.rs` recipe；**不是** `wasmText`） |
| Maturity | `source-only` |
| Finalize | **zero-tool**；`deployable=false` |
| Capability | 仅 `failure.atomic-rollback` / `state.persistent` / `value.bool` / `value.checked-arithmetic` |
| 存储约定 | 单一 **instance** storage；无 TTL 策略选择 |
| 明确拒 | event / sync call / async / pf.assets / nonempty invariants / Int8/16/32 state·params / mixed UInt64↔Int64 / 错域 Array/Option/Map 元素 / nonempty Map construct / N∉1..8 / `symbol_short!` key >9 bytes（never truncate） |
| 整数域 | 齐次 UInt64 或 Int64（混用 fail closed；未使用的 interned UInt64 类型行不强制 mixed） |
| Array flatten | 匿名 `Array UInt64 N` 或 `Array Int64 N`（N=1..8）**state** 展平为 N 个 instance key `{name}_0`..`{name}_{N-1}`（无 Vec；叶类型跟随 signedNumeric：`u64`/`i64`）。叶名必须适配 `symbol_short!`（≤9 UTF-8 bytes）。不是 SOR-1 / 不是 formal。 |
| Option flatten | 匿名 `Option UInt64` 或 `Option Int64` **state** 展平为 2 个 instance key `{name}_tag` + `{name}_p0`（tag 0=none / 1=some；none 清零 payload；payload 跟随 signedNumeric）。Option **param** 同布局只读。construct none/some。叶名必须适配 `symbol_short!`（`o_tag`/`o_p0` 通过；过长前缀 fail closed，不截断）。**不是** Option-of-非标量 / 嵌套 / match、不是 SOR-1 / 不是 formal。 |
| Map flatten | 匿名 `Map UInt64 UInt64` 或 `Map Int64 Int64` **state** 展平为 24 个 instance key `{name}_0`..`{name}_23`（cap-8 × occ/key/val 交错；key/value 跟随 signedNumeric；`Map.empty` + IndexSet upsert；IndexGet → Option tag+payload）。叶名必须适配 `symbol_short!`（`m_0`..`m_23` 通过；过长前缀 fail closed，不截断）。**B-RET-MAP** entry/view 24 叶 Rust 元组已开。Map **param** 同布局 24 只读叶。**不是** Map UInt64 Int64、不是 nonempty construct、不是 native HashMap、不是 SOR-1 / 不是 formal。 |

制品：`{name}.rs`（`soroban-sdk` 风格 `#[contract]` / instance get/set / `checked_*` panic→rollback）。
**不**声称可直接 `stellar contract build`、Wasm、auth tree、XDR/spec 或 testnet。

## 3. 执行、状态、调用、失败与资源（平台真相；S0 未全开）

- 执行：合约函数在 Stellar transaction/host invocation 中同步执行。
- 状态：instance、persistent、temporary storage，均受不同 TTL/archival 规则影响。
- 调用：同步 contract invocation；authorization 由 `Address.require_auth` 和 invocation tree 表达。
- 失败：host/contract error 使 transaction 失败；错误编码进入 XDR/contract spec。
- 资源：CPU、memory、ledger read/write footprint、event 和 tx size 需模拟与计费。

## 4. Portable fragment 与扩展

Portable（S0 子集）：Cell、entry/view、checked arithmetic、transaction atomicity（via panic rollback）。

扩展（SOR-1+）：storage durability/TTL、opaque Address、auth tree、XDR/ScVal、footprint、token interface、Wasm hash upgrade。TTL 不是部署脚本细节，而是状态生命周期语义。

## 5. `SorobanPlan` schema（S0）

```text
SorobanPlan {
  programName, sourceHash, semanticHash, signedNumeric,
  states, initializer?, entries, views
}
```

完整 aspirational schema（TTL/auth/XDR）留 SOR-1+，不得在 S0 Plan 静默默认。

## 6. Target IR 与制品

`SorobanPlan → Soroban Rust IR → {name}.rs`（S0）。
后续：`SorobanPlan → ModuleRecipe → locked Wasm`（SOR-1）。不得实现成“NEAR Wasm + 不同 imports”。

## 7. 工具链

S0：无 Tool Lock。SOR-1：冻结 Stellar protocol、host/Wasm subset、stellar-cli、RPC simulation 和 SDK/XDR schema。

## 8. 部署流程

S0：不部署。SOR-1+：本地 network 安装 Wasm → create contract → simulate/submit invoke → inspect events/storage/auth → extend/expire TTL → upgrade Wasm。

## 9. 安全

关注 auth tree 重放/作用域、Address 类型误解、TTL 过期、archived state、footprint 不完整、resource fee、XDR canonical encoding 和 upgrade authorization。S0 通过 fail-closed 拒绝对上述面的假实现。

## 10. 验证阶梯

S0：Plan/IR/`.rs` golden + registry/inspect + content-bound output。
SOR-1+：contract spec/XDR golden → host Wasm validation → SDK host test → local Stellar network invoke/auth/TTL → testnet receipt。

## 11. 不支持、风险与成熟度退出

S0 已实现 source-only leaf。进入 locked Wasm / deployable 前必须固定 protocol/profile，证明 custom sections、XDR、auth tree 和 TTL plan 可独立生成，并完成 Counter 的宿主测试设计。不能把 `.rs` recipe 等同完整后端或 accepted Phase 1。
