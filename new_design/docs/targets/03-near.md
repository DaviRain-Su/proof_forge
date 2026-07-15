---
id: TARGET-NEAR
title: NEAR target dossier
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# Target Dossier：NEAR

状态：`proposed`
Target ID：`near`
Phase 1：实现

## 1. 身份与来源

NEAR 合约是调用 runtime host bindings 的 Wasm module。依据 [Bindings Specification](https://nomicon.io/RuntimeSpec/Components/BindingsSpec/)、[Cross-contract Calls](https://docs.near.org/smart-contracts/anatomy/crosscontract)、[Receipts](https://nomicon.io/RuntimeSpec/Receipts) 与 [Serialization Protocols](https://docs.near.org/smart-contracts/anatomy/serialization-interface)（`SRC-NEAR-001..004`，verified）。

## 2. 执行、状态、调用、失败与资源

- 执行：exported method 在 receipt 上执行；输入/输出经 host registers 和 ABI 约定交换。
- 状态：合约账户拥有 byte-key/value storage。
- 调用：跨合约调用构造 Promise/receipt，可组合 callback；不是同步栈调用。
- 失败：当前 receipt panic/host error 与后续 promise failure 分开；已完成 receipt 的状态不会因后续 callback 失败自动回滚。
- 资源：prepaid gas、promise gas、storage staking/deposit 与 protocol profile 绑定。

## 3. Portable fragment 与扩展

Portable：Cell/Map、entry/view、JSON-compatible scalar/struct、checked arithmetic、event、account identity、receipt-local rollback。

扩展：Promise DAG、callbacks、attached deposit、storage accounting、batch actions、protocol calls、Borsh ABI、code upgrade。`schedule` 明确表示异步工作流；同步 `call` requirement 在 NEAR 上默认不满足。

## 4. `NearPlan` schema

```text
NearPlan {
  profile, exports, jsonAbi,
  storageSchema, hostImports,
  methods, promiseGraphs, callbacks,
  events, errors, gasPlan, upgradePolicy
}
```

Plan 明确每个 Promise dependency、callback result index、gas/deposit 和 receipt commit boundary。不能把 Promise 串编码成通用 effect 字符串。

## 5. Target IR 与制品

`NearPlan → NearWasmIR/ModuleRecipe → shared Wasm encoder`。输出 WAT（审计）、Wasm、ABI/metadata、storage schema 和 manifest。共享 encoder 不包含 NEAR host 名称或业务默认值。

当前 alpha 只实现 profile `near-wasm-raw-u64-v1` 的 exact Counter：`init`/`increment`
输入和 `get`/`increment` 返回均为 8-byte little-endian `UInt64`，不是 JSON ABI。它输出
WAT、经 `wat2wasm` 生成的结构有效 Wasm 和明确标注 raw encoding 的 alpha ABI metadata；
尚无 sandbox receipt，因此不得推断 JSON 兼容、部署成功或 runtime validated。

## 6. 工具链

锁定 Lean/Wasm encoder、`wasm-tools` 或 `wat2wasm` validator、NEAR sandbox/workspaces 与 protocol profile。外部工具缺失时 fail closed。

## 7. 部署/证明流程

Phase 1 完整目标是切换到规范冻结的 JSON ABI 后部署到 NEAR sandbox，调用
init/increment/get，校验 JSON、storage、receipt status 和 overflow 时当前 receipt 状态
不变。当前 raw-u64 alpha 只是通往该目标的结构验证，不满足本节部署验收。真实 testnet
receipt 证据属于后续 network gate。

## 8. 安全

关注 predecessor/signer 混淆、promise callback spoof、unused promise result、gas allocation、attached deposit、storage deposit、跨 receipt 原子性误解、serialization ambiguity 和 code upgrade authority。

## 9. 验证阶梯

1. host imports/exports、ABI、storage golden。
2. Wasm validation + host import allowlist。
3. 参考语义与 Wasm host interpreter 差分。
4. sandbox deploy/call/receipt/storage evidence。
5. 真实网络 receipt 与 gas band 后才 network-validated。

## 10. 不支持、风险与成熟度退出

Phase 1 Counter 不需要 Promise；首版只实现 receipt-local state semantics。异步 workflow 在独立 slice 中实现。退出条件：合法 Wasm、sandbox receipt、状态与 rollback、artifact repeatability、unknown host/unsupported sync-call 负例全部通过。
