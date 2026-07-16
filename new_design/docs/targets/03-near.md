---
id: TARGET-NEAR
title: NEAR target dossier
status: proposed
owner: architecture
updated: 2026-07-16
normative: true
---

# Target Dossier：NEAR

状态：`proposed`
Target ID：`near`
Phase 1：实现

## 1. 身份与来源

NEAR 合约是调用 runtime host bindings 的 Wasm module。依据 [Bindings Specification](https://nomicon.io/RuntimeSpec/Components/BindingsSpec/)、[Cross-contract Calls](https://docs.near.org/smart-contracts/anatomy/crosscontract)、[Receipts](https://nomicon.io/RuntimeSpec/Receipts)、[Serialization Protocols](https://docs.near.org/smart-contracts/anatomy/serialization-interface) 与 [Contract Preparation](https://nomicon.io/RuntimeSpec/Preparation)（`SRC-NEAR-001..005`，verified）。

## 2. 执行、状态、调用、失败与资源

- 执行：exported method 在 receipt 上执行；输入/输出经 host registers 和 ABI 约定交换。
- 状态：合约账户拥有 byte-key/value storage。
- 调用：跨合约调用构造 Promise/receipt，可组合 callback；不是同步栈调用。
- 失败：当前 receipt panic/host error 与后续 promise failure 分开；已完成 receipt 的状态不会因后续 callback 失败自动回滚。
- 资源：prepaid gas、promise gas、storage staking/deposit 与 protocol profile 绑定；当前 raw-u64 profile 还在 Plan/recipe 两层将每个 exported method 的生成 locals 限制为 50,000。

## 3. Portable fragment 与扩展

Portable：Cell/Map、entry/view、JSON-compatible scalar/struct、checked arithmetic、event、account identity、receipt-local rollback。

扩展：Promise DAG、callbacks、attached deposit、storage accounting、batch actions、protocol calls、Borsh ABI、code upgrade。`schedule` 明确表示异步工作流；同步 `call` requirement 在 NEAR 上默认不满足。

## 4. `NearPlan` schema

```text
NearPlan {
  profile, rawAbi,
  storageBindings, layoutMarker, initializationPolicy,
  hostImports, methods, failurePolicy,
  commitPolicy, resourceLimits
}

NearModuleRecipe {
  memory, dataSegments, imports, exports,
  typedInstructions, provenance
}
```

`TASK-A0-15` 的首个通用 UInt64 切片只覆盖 verifier-visible `UInt64` state/parameter、
literal/param/state/checked-add/store/return、init、entry 和 view。`NearPlan` 必须拥有 raw ABI、
每个 `StateId` 的 KV binding、初始化 marker、host imports、method mode/body、trap/deposit policy 和
receipt-local commit assumption；不得保留整个 `SemanticProgram`，renderer 也不得重新推导
业务逻辑。

后续 Promise slice 仍须在 Plan 中明确每个 dependency、callback result index、gas/deposit 和
receipt commit boundary。不能把 Promise 串编码成通用 effect 字符串，也不能把它塞进本切片
的通用 UInt64 recipe。

## 5. Target IR 与制品

`NearPlan → NearModuleRecipe → WAT → Wasm`。编译器内部生成 typed recipe；对外输出 WAT（审计）、Wasm、
ABI/metadata、storage schema 和 manifest。recipe/encoder 只实现已经由 `NearPlan` 决定的
imports、exports、memory/data layout 和 typed instructions；不得查询 source、猜 KV key 或注入
业务默认值。Plan 和 recipe 分别验证，recipe 必须等于 Plan 的 canonical lowering；
随后由锁定 `wat2wasm` 验证生成的 WAT。任何 invariant/tool failure 不得返回 partial artifact。

首个通用切片固定 profile `near-wasm-raw-u64-v1`；验收时必须以 Counter、Accumulator 和非
Counter literal-return body 证明 lowering 由 semantics 驱动。每个 method 的 input 必须恰好为
`8 * parameter-count` bytes little-endian；零参数 method 只接受空 input，禁止 trailing bytes。
每个 `UInt64` return 恰好为 8-byte little-endian。这不是 JSON ABI；JSON scalar/object、字段名、
大整数表示和 error envelope 必须由未来独立 profile 冻结，不能在 raw profile 内隐式兼容。

KV layout 使用 target-owned initialized marker 区分 absent/present state，并把 marker 绑定到
canonical layout。initializer 先要求 marker absent，再将全部声明字段物化为 canonical zero，
然后按顺序执行 semantic init body，最后写入 marker；因此 init body 读取尚未赋值字段时观察到
零。entry/view 先要求 marker present 且匹配。每次 field read 都必须验证 `storage_read` found、
register length 恰好为 8，再按 little-endian 解码；missing、短值、长值或旧 layout 一律失败。
checked-add 必须在对应 store 前检测 unsigned overflow，store 后的 state read 必须观察新值，
view recipe 不得包含 KV write。

initializer/mutate 使用 `attached_deposit(balance_ptr)` 在任何 KV 操作前要求完整
`u128 == 0`。NEAR ViewFunction context 禁止调用该 host function，因此 view method 在 Plan/ABI
中固定为 `query-only`并且 recipe 不调用 `attached_deposit`；把 view export 作为付款
transaction 调用不属于此 profile 的承诺。

## 6. 工具链

本切片只允许工具链 lock 中固定 absolute pathname、version 与 executable digest 的
`wat2wasm`。missing、PATH shadow、version/hash mismatch、unknown host import/export 或
structural validation failure 必须 fail closed。`wat2wasm` 只把已验证 WAT 编码并做 Wasm 结构
检查；它不执行 NEAR host semantics，也不能替代 sandbox/workspaces 或 protocol profile。

## 7. 部署/证明流程

Phase 1 完整目标仍是在独立 JSON profile 冻结后部署到 NEAR sandbox，调用 init/mutate/view，
校验 ABI、storage、receipt status 和 overflow 时当前 receipt 状态不变。`TASK-A0-15` 的
raw-u64 Accumulator 首切片即使通过，也只建立 Plan/recipe/WAT/Wasm 的静态编译路径，
不满足本节部署验收。
真实 testnet receipt 证据属于后续 network gate。

## 8. 安全

当前切片必须 fail closed 检查 descriptor/profile/schema/requirements、export 与 KV identity、
exact input/storage lengths、init marker、view-no-write、checked overflow、artifact name/JSON escaping、
初始化/可变 method 的 zero-deposit policy 和 view query-only 边界。未建模的 predecessor/signer、
payable 业务语义、storage accounting、Promise/callback、
gas allocation、跨 receipt workflow 和 upgrade/migration 不得通过隐式默认值获得支持。

## 9. 验证阶梯

1. Plan/recipe mutation、host imports/exports、raw ABI、KV layout/storage golden。
2. 锁定 `wat2wasm` 的 Wasm structural validation + host import allowlist。
3. 参考语义与 Wasm host interpreter 差分。
4. sandbox deploy/call/receipt/storage/rollback evidence。
5. 真实网络 receipt 与 gas band 后才 network-validated。

第 1-2 级通过只构成静态 artifact evidence。当前没有第 3-5 级证据，尤其没有 sandbox
receipt、NEAR runtime 执行或 overflow rollback 观测。

`TASK-A0-15` / `EV-20260716-0020` 已让 Counter 与 Accumulator 通过第 1-2 级：Plan/recipe
mutation、raw ABI/WAT golden、锁定 `wat2wasm`、Wasm header/size/digest 和双轮复现均通过。
补充的 deterministic host model 只解释 typed recipe，并把 trap 后恢复调用前 snapshot 作为
模型假设；它不构成本阶梯第 3 级的 Wasm host interpreter，更不构成第 4 级 receipt 观测。

## 10. 不支持、风险与成熟度退出

通用 UInt64 首切片不支持 JSON ABI、Promise/callback、跨 receipt workflow、protocol calls、
attached-deposit 业务语义、upgrade migration 或任意 NEAR SDK surface。它只在 typed Plan/recipe
中表达 receipt-local rollback 要求；trap/write 顺序和 `wat2wasm` 成功不是 rollback 观测。
在 sandbox differential 取得 init、Accumulator mutate/view、corrupt storage、bad input 和
overflow unchanged-state receipt 之前，不得声称 runtime validated、receipt validated 或 JSON
compatible。退出条件仍是合法 Wasm、sandbox receipt、状态与 rollback、artifact
repeatability、unknown host/unsupported sync-call 负例全部通过。
