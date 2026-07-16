# Internet Computer 目标

状态：**Research（文档优先候选）**

候选 target id：**`wasm-icp-canister`**

英文权威文档：[../../targets/internet-computer.md](../../targets/internet-computer.md)

## 结论

Internet Computer canister 应归入 Wasm-host 家族，但必须是独立目标，不能和 NEAR、CosmWasm 或 Stellar/Soroban 合并。

```text
Internet Computer canister 目标
  -> 当前主流是 Motoko 或 Rust CDK
  -> Wasm canister module
  -> Candid service/interface metadata
  -> IC System API 和 management canister
  -> local replica / PocketIC / ICP CLI validation
```

ICP 不是“通用 Wasm 链”。Canister 是带 persistent state、Candid interface、query/update/composite-query 调用模式、principal identity、cycles accounting、async inter-canister calls 和 management canister lifecycle 的 Wasm smart contract。

## 对 ProofForge 的含义

`wasm-icp-canister` 应先作为文档优先的 Research candidate。第一步不直接加入 `ProofForge.Target.Registry`。

目标特有问题包括：

- Motoko 有 actor、async/await、Candid 和 orthogonal persistence 的一等支持；
- Rust canister 使用 `ic-cdk` 等 CDK glue 暴露方法、做 Candid serialization、stable memory 和 System API 调用；
- update、query、composite query 不是同一种 entrypoint；
- principal 是用户和 canister identity 的基础；
- persistent state 可能来自 canister memory、stable memory 或 CDK-managed stable structures；
- inter-canister call 是异步消息流；
- cycles 是 compute、memory、message 和 lifecycle operation 的资源计量单位；
- deployment 和 upgrade 通过 canister lifecycle 与 management canister API 完成；
- Candid `.did` 是公开合约接口的一部分。

## 候选能力

现有 Wasm-host 能力可以覆盖一部分基础语义，例如 `storage.scalar`、`storage.map`、`caller.sender`、`crosscall.invoke` 和 `crypto.hash`。

但以下能力应先作为候选项保留在文档中：

| 候选能力 | 含义 |
|---|---|
| `abi.candid` | 构建输出并验证 Candid service interface。 |
| `canister.method_mode` | entrypoint 区分 update、query 和 composite query。 |
| `storage.stable_memory` | 状态使用 stable memory 或 stable structures 跨 upgrade 保留。 |
| `storage.orthogonal_persistence` | 状态遵循 Motoko-style orthogonal persistence 语义。 |
| `principal.id` | caller/canister/user identity 是 Principal。 |
| `cycles.manage` | 目标可以 inspect、accept、send 或 account for cycles。 |
| `crosscall.async` | cross-canister call 是异步消息流。 |
| `canister.lifecycle` | 目标支持 install、upgrade、stop/start 和 lifecycle hooks。 |
| `certified.data` | 目标暴露 certified variables 或 certified data responses。 |
| `management.canister` | 目标可以调用 virtual management canister。 |

## 两条接入路线

1. **Native canister package sourcegen**：先生成或包装 Motoko / Rust CDK canister package，通过本地 replica、PocketIC 或 ICP CLI 验证。这个路线最保守。
2. **Direct Wasm host bridge**：Lean 直接降级到 Wasm canister module + ICP host bridge。这个路线应等待 Wasm runtime split 足够清楚后再做。

## 第一阶段非目标

- 不把 `wasm-icp-canister` 加入代码 registry。
- 不把 ICP 和 `wasm-near`、`wasm-cosmwasm` 或 `wasm-stellar-soroban` 合并。
- 不把 query 和 update method 当成同一种 entrypoint。
- 不把 cycles 当成普通 native token value。
- 不忽略 upgrade 和 stable-memory 行为。
- 不把 inter-canister calls 当成同步 cross-contract calls。
