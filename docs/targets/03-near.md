---
id: TARGET-NEAR
title: NEAR target dossier
status: proposed
owner: architecture
updated: 2026-08-04
normative: true
---

# Target Dossier：NEAR

状态：`proposed`
Target ID：`near`
Phase 1：实现

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 读取 retained `SemanticProgramV1`，structure-gate 后 private lowering；
无 alpha residual Plan route。保留 KV / raw ABI / receipt-local policy。

**工程已接线（摘）**：

- Normalize 当前子集：算术/比较/assert、控制流、fn、let/for、shift/bitwise、revert/emit 等；
- state/param **UInt8/16/32/64 与窄 Int** ABI/body 子集；**UInt128/256 软件多字（T9e）**；
  schedule → 原生 promise；sync call 在 capability 矩阵上 fail-closed；
- **Array + dense Map UInt64 cap-8 + fixed Bytes N + named Struct/Enum + Option UInt64 state**
  flatten-to-KV；聚合 `StateStore` 使用 `storeAtomic` 两阶段 IR（先求值全部叶、再写 KV），HostModel
  已固定 empty Map upsert、连续 Map StateStore、PointBox/EnumBox，以及 Option tag/payload 的
  none/some/reset（reset 清零 stale payload）；Option params、非 UInt64 payload与 nested Option 仍 FC；
- **≤8 叶聚合返回**：named Struct/Enum 与 anonymous Array/Option UInt64 经单次 `value_return`
  发 N×8-byte LE；Map/Bytes/nested/非 UInt64元素返回仍 fail-closed；
- **Principal 9×KV leaf 存储（T12）**（wire identity 原样；**非** account-id）；
- WAT 发射 + locked `wat2wasm` 结构编译；`NearWasmAcceptance` 另需 host-optional
  `wasm-interp`/`wasmtime`/`wasmer` 之一做 runtime load；locked near-sandbox 2.13.0 的
  `runtime-tests/near` 已覆盖 Counter init/mutate/view、overflow state-hold+recovery、PairRet、
  ArrayRet、OptionRet 与 OptionState 的工程路径。
- **`pf.assets` 半绑定（ADR-0029 Phase C2，2026-08-05）**：resolver advertise exact
  `extension.pf-assets` + `effect.synchronous-call`（后者仅覆盖 pf.assets catalog；
  generic 非 catalog sync call 在 Plan 层继续 fail closed）。`pf.assets.native.deposit`
  → `attached_deposit == amount` 精确校验（u128 lo/hi；无 deposit 的 entry 保持
  zero-deposit 门）；`pf.assets.native.transferAsync` → `promise_batch_create` +
  `promise_batch_action_transfer` fire-and-forget（不观测结果、不传播异步失败）；
  dst Principal 运行时须 exact wire shape `u32le(len)||utf8-account-id-bytes`
  （grammar 校验 2..64 与小写字符集）。sync `transfer` 与 token QN **永久 fail closed**
  （Promise 为 async，不得包装成 sync）。near-sandbox 门新增 `TipJarAsync` 套件
  （`Examples/TipJarAsync.lean`）：init/精确 deposit 成功/错误与零 deposit 拒绝 +
  **receiver 子账户真实余额差值观测**（fire-and-forget 转账的端到端证据）。
- **`pf.assets.token.transferAsync` binding（ADR-0030 E1-NEAR，2026-08-05）**：payload
  不变的 per-target 绑定。→ fire-and-forget NEP-141 `ft_transfer` Promise
  （`promise_batch_create(mint)` + `promise_batch_action_function_call`：exact JSON
  args `{"receiver_id":dst,"amount":"<decimal>"}`、30 Tgas 冻结 gas、**恰好
  1 yoctoNEAR** attached deposit——NEP-141 核心要求）；mint/dst account-id 语法门同
  C2 dst（受控动态 callee，仅 catalog token 家族）；sync `token.transfer` 永久 FC
  （诚实边界）。schedule pilot 潜在 ABI bug 顺带修复：
  `promise_batch_action_function_call` import 由误写的 8 参（amount_low/high）改为
  真实 host ABI 7 参（amount_ptr→u128 LE），schedule call site 同步修正。near-sandbox
  门新增 `TokenJarAsync` 套件（`runtime-tests/near/fixtures/TokenJarAsync.lean`）：
  最小 mock NEP-141（pinned `mock_token.wat` + locked wat2wasm，其 `ft_transfer`
  **断言恰好 1 yoctoNEAR**）部署到带 key 子账户，验证 jar SuccessValue、
  fire-and-forget 状态推进、mint 账户 SUCCESS receipt + `ft_transfer ok` 日志；
  诚实上限：mock 无账本记账，token 余额差值未声明；**非** formal/testnet/mainnet。
- **`pf.assets.native.balanceOfSelf` env-read binding（ADR-0030 E2-NEAR，2026-08-06）**：
  payload v1.1.0 新 QN 的 per-target 绑定（read-only、view/entry-callable、
  effect-free、结果 UInt64）。native → host `account_balance`（ABI 同
  `attached_deposit`：`balance_ptr` 单参、写 u128 LE）+ UInt64 range guard
  （高 64 位非零 → trap），host import 由结构扫描条件加入；**token 永久 FC**
  （NEP-141 `ft_balance_of` 为跨合约 view call，NEAR 异步 promise 模型无法在
  表达式内同步完成——诚实边界非债务）。near-sandbox 门新增第 8 套件
  `EnvReadJar`（jar 部署于带 key 子账户以隔离 master gas 混淆）：真实余额
  ~10^24 yocto ≫ 2^64 → range-guard trap 分支真实触发；`acceptNative(1000)`
  deposit 精确落账且 jar RPC 余额非递减 ≥ base+amount（storage-stake 记账可
  使 Δ 超过 deposit，不断言精确等值）；wrong-deposit 失败且状态保持。
  **实用性 caveat**：2^64 yocto ≈ 0.0000184 NEAR，真实账户余额几乎总使该
  绑定 trap——UInt64 结果纪律与 u128 yocto 面额的已知产品级张力；不阻塞 E2
  （E4 北极星不依赖 NEAR），后续若要成功路径需另行设计面额/宽度故事。
  **非** formal/testnet/mainnet。

**明确未闭合**：near-sandbox 门不是 Reference↔Wasm/sandbox formal 差分，仍不覆盖 corrupt
storage、bad input 或 gas/profile；Option params、非 UInt64/nested Option、Map/Bytes/nested aggregate
return 与 ContextRead 仍 fail-closed；formal identity/OutputSet / D6 milestone 未完成。不得写成
formal runtime-validated。

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

`TASK-A0-15` 的当前通用 UInt64 切片只覆盖 verifier-visible `UInt64` state/parameter、
literal/param/state/checked-add/sub/store/return、init、entry 和 view。`NearPlan` 必须拥有 raw ABI、
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

两平台 Tool Lock v4 固定 `wat2wasm` 与 near-sandbox `2.13.0` 的资产、executable
digest/version probe（Darwin near-sandbox 另闭合 xz/liblzma runtime）；`wasm-interp`、
`wasmtime`、`wasmer` 不在 Tool Lock，NearWasmAcceptance 只把它们作为 host-optional runtime
load engine。missing、PATH shadow、version/hash mismatch、unknown host import/export 或结构失败
必须 fail closed。WABT 编译不能替代 NEAR host semantics；near-sandbox acceptance 也只是外置
Counter receipt happy path，不能替代完整 protocol profile、Reference differential 或 formal
Stage-0 evidence。

## 7. 部署/证明流程

G123 已完成产品 Counter 的 near-sandbox deploy/init/mutate/view happy path，并观测 receipt
成功与 view 值；这只覆盖固定 raw-u64 正向路径。Phase 1 完整目标仍需独立 protocol/ABI
profile、Reference 对照、bad input/corrupt storage/overflow unchanged-state negatives、gas/resource
约束与 identity-bound evidence。`TASK-A0-15` 的历史静态切片及当前 G123 happy path 都不足以
关闭该完整部署验收。真实 testnet receipt 证据属于后续 network gate。

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

第 1-2 级构成静态 artifact evidence。G123 现在为 Counter happy path 提供第 4 级的一个
工程子集（deploy/init/increment/view receipt），但没有第 3 级 Reference↔Wasm differential，
也没有第 4 级的 bad-input/corrupt-storage/overflow rollback negatives，更没有第 5 级证据。

`TASK-A0-15` / `EV-20260716-0020` 的历史切片让 Counter 与 Accumulator 通过第 1-2 级；
deterministic HostModel 只解释 typed recipe，并把 trap 后恢复调用前 snapshot 作为模型假设。
G123 receipt 门新增真实 sandbox happy-path 观测，但两者都不构成 formal Reference differential
或完整 rollback 证明。

## 10. 不支持、风险与成熟度退出

通用 UInt64 首切片不支持 JSON ABI、Promise/callback、跨 receipt workflow、protocol calls、
attached-deposit 业务语义、upgrade migration 或任意 NEAR SDK surface。它只在 typed Plan/recipe
中表达 receipt-local rollback 要求；trap/write 顺序和 `wat2wasm` 成功不是 rollback 观测。
当前只能声称 **Counter sandbox receipt happy path 的工程观测**。在 Reference-bound sandbox
differential 取得 Accumulator mutate/view、corrupt storage、bad input 和 overflow
unchanged-state negatives 之前，不得声称完整 runtime validated、rollback validated 或 JSON
compatible。退出条件仍是合法 Wasm、完整 sandbox 状态/rollback、artifact repeatability、unknown
host/unsupported sync-call 负例全部通过。
