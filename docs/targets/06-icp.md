---
id: TARGET-ICP
title: Internet Computer target dossier
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# Target Dossier：Internet Computer Canister

状态：`proposed`
Target ID：`icp`
Phase 1：设计，不实现

## 1. 身份与来源

ICP canister 是带 System API、Candid 接口、heap/stable memory、cycles 和 actor message 语义的 Wasm actor。依据 [IC Interface Specification](https://docs.internetcomputer.org/references/ic-interface-spec/)、[Message Execution Properties](https://docs.internetcomputer.org/references/message-execution-properties/)、[Candid](https://docs.internetcomputer.org/guides/canister-calls/candid/) 与 [Canisters](https://docs.internetcomputer.org/concepts/canisters/)（`SRC-ICP-001..004`，verified）。

## 2. 执行、状态、调用、失败与资源

- 执行：update/query/composite query 和 lifecycle methods 的约束不同。
- 状态：Wasm heap 可通过升级 hooks 管理；stable memory 提供持久载体。
- 调用：actor 异步 inter-canister calls；`await`/callback 将逻辑工作流分成多个 message/commit 边界。
- 失败：trap 回滚当前 message 的可回滚更新，但已发送消息/此前提交边界需按规范区分。
- 资源：instructions、cycles、memory、message size、callback quota 与 subnet/profile 绑定。

## 3. Portable fragment 与扩展

Portable 候选：Cell/Map、entry/view、checked arithmetic、Principal、message-local failure。

扩展：Candid service types、update/query/lifecycle mode、stable memory layout、cycles、management canister、timers、certified data、async actor calls、upgrade hooks。

## 4. `IcpPlan` schema

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

冻结 interface spec revision、Candid compiler/parser、local replica/dfx 或 pocket-ic profile、Wasm feature set。dfx 不是编译语义来源。

## 7. 部署流程

local replica create/install → update/query → inter-canister call → upgrade with stable-state preservation → inspect reject/trap/cycles。真实 subnet deployment 是更高证据等级。

## 8. 安全

重点是 caller/Principal、controller authority、reentrancy across await、upgrade serialization、stable memory corruption、cycles exhaustion、query mutation assumptions 和 certified response integrity。

## 9. 验证阶梯

Candid/stable schema golden → Wasm/System API validation → local replica single-message behavior → two-canister async/upgrade → subnet evidence。

## 10. 不支持、风险与成熟度退出

当前不实现。准入要求：冻结 message commit 语义、stable memory versioning、Candid canonical mapping 和 local replica test matrix。复杂 async workflow、timers、HTTP outcalls 和 certified variables 后续按 extension 分片。
