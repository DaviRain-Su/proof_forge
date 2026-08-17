---
id: TARGET-ICP
title: Internet Computer target dossier
status: proposed
owner: architecture
updated: 2026-08-17
normative: true
---

# Target Dossier：Internet Computer Canister

状态：`proposed`
Target ID：`icp`
Phase：engineering leave（ADR-0047）；**非** accepted PRD Phase 1

## 1. 身份与来源

ICP canister 是带 System API、Candid 接口、heap/stable memory、cycles 和 actor message 语义的 Wasm actor。依据 [IC Interface Specification](https://docs.internetcomputer.org/references/ic-interface-spec/)、[Message Execution Properties](https://docs.internetcomputer.org/references/message-execution-properties/)、[Candid](https://docs.internetcomputer.org/guides/canister-calls/candid/) 与 [Canisters](https://docs.internetcomputer.org/concepts/canisters/)（`SRC-ICP-001..004`，verified）。

Registry 六轴（已冻结）：`icpCanister` / `awaitSegmented` / `canisterHeapStable` /
`asynchronousActor` / `noProof` / `icpSubnet`。Sole profile：`icp-wasm-candid-u64-v1`。
ArtifactEncoding：`icpWasmCandid`。

## 2. 执行、状态、调用、失败与资源

- 执行：update/query/composite query 和 lifecycle methods 的约束不同。
- 状态：Wasm heap 可通过升级 hooks 管理；stable memory 提供持久载体。
- 调用：actor 异步 inter-canister calls；`await`/callback 将逻辑工作流分成多个 message/commit 边界。
- 失败：trap 回滚当前 message 的可回滚更新，但已发送消息/此前提交边界需按规范区分。
- 资源：instructions、cycles、memory、message size、callback quota 与 subnet/profile 绑定。

## 3. Portable fragment 与扩展

Portable 候选：Cell/Map、entry/view、checked arithmetic、Principal、message-local failure。

扩展：Candid service types、update/query/lifecycle mode、stable memory layout、cycles、management canister、timers、certified data、async actor calls、upgrade hooks。

## 4. `IcpPlan` schema（ICP-2）

```text
IcpPlan {
  profile, candidService, exports,
  heapLayout, stableLayout, upgradeHooks,
  updateMethods, queryMethods,
  actorWorkflows, cyclesPlan, errors
}
```

async workflow 必须标出每个 message 的 pre/post state 和 callback continuation；不能复用 NEAR Promise 或同步 call Plan。

## 5. Target IR 与制品

`IcpPlan → IcpModuleRecipe → shared Wasm encoder`。输出 Wasm、`.did`、stable schema/version、upgrade compatibility report、cycles/resource metadata 和 manifest。

## 6. 工具链

冻结 interface spec 工程引用面（[IC Interface Specification](https://docs.internetcomputer.org/references/ic-interface-spec/)）+ Candid homogeneous nat64/int64 inline codec；
Finalize 钉 locked `wat2wasm`（与 NEAR/CosmWasm 同 Tool Lock 供给）。
ICP-3 工程门：PocketIC **server 15.0.0** + Rust `pocket-ic = "=15.0.0"`（`runtime-tests/icp`）；
`just icp-runtime` / `proof-forge-next local --target icp` → `scripts/pf_icp_test.sh`（缺
`POCKET_IC_BIN` 时 skip-clean，不算 pass）。dfx 不是编译语义来源。

## 7. 部署流程

local replica create/install → update/query → inter-canister call → upgrade with stable-state preservation → inspect reject/trap/cycles。真实 subnet deployment 是更高证据等级。

## 8. 安全

重点是 caller/Principal、controller authority、reentrancy across await、upgrade serialization、stable memory corruption、cycles exhaustion、query mutation assumptions 和 certified response integrity。

## 9. 验证阶梯

Candid/stable schema golden → Wasm/System API validation → local replica single-message behavior → two-canister async/upgrade → subnet evidence。

## 10. 当前切片状态（ADR-0047）

| Slice | 状态 | 内容 |
|---|---|---|
| **ICP-1** | **done / control plane** | registry implemented、descriptor、resolver（sync+event FC；async advertise）、list/inspect |
| **ICP-2** | **done / leaf** | target-owned Plan/IR → `.wat` + `.did`；Counter/StateCell 齐次 UInt64 **或** Int64（Candid `nat64`/`int64`，混用 FC）；**Array UInt64 N 或 Array Int64 N∈1..8** flatten 为 N 个 `i64` Wasm global（元素跟随 signedNumeric；**无** Candid `vec`）；**Option UInt64** 2 叶（`o_tag`/`o_p0`，无 Candid `opt`）；**Map UInt64 UInt64 cap-8** 24 叶（occ/key/val i64 globals + ite mux + assert，无 Candid `map`/`vec`；Int64 Map / Map return 仍 FC）；checked `+`/`-`/`*`/`/`/`%`（unsigned wrap / signed two's-complement overflow；div0 与 `MIN/-1` trap）；store-then-read overlay rewrite；**CAP-1a** `unixTimeSeconds`→`ic0.time` ns÷10⁹ |
| **ICP-3** | **done / host-optional** | `wat2wasm` Finalize → `.wasm`（`deployable=true`）；PocketIC 15.0.0 StateCell gate；maturity 仍 `source-only`；非 formal/mainnet |

Capability（honest）：`state.persistent`、`value.checked-arithmetic`、`value.bool`、
`failure.atomic-rollback`（message-local）、`effect.asynchronous-workflow`。
**拒**：`effect.synchronous-call`、`effect.event`（MVP）。

不得复用 Near/CosmWasm Plan。复杂 async workflow、timers、HTTP outcalls、certified
variables、upgrade 按 extension 后续分片。formal / hermetic / release / accepted PRD
扩面不因本 dossier 改变。
