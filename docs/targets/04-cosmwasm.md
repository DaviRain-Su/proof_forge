---
id: TARGET-COSMWASM
title: CosmWasm target dossier
status: draft
owner: architecture
updated: 2026-07-15
normative: true
---

# Target Dossier：CosmWasm

状态：`draft`
Target ID：`cosmwasm`
Phase 1：设计，不实现

## 1. 身份与来源

CosmWasm 是 Cosmos SDK `x/wasm` 合约环境，强调 Cosmos modules 与 IBC 集成；官方总览见 [CosmWasm Documentation](https://cosmwasm.github.io/)（`SRC-CW-001`，verified）。精确 transaction/SubMsg/reply 语义来源尚未冻结到版本化快照（`SRC-CW-002`，provisional）。

## 2. 执行、状态、调用、失败与资源

- 执行：固定 instantiate/execute/query/migrate/reply 等 entrypoint 与 JSON messages。
- 状态：合约实例前缀隔离的 KV store。
- 调用：返回 CosmosMsg/SubMsg，可能触发 reply；IBC 是协议化异步交互。
- 失败：transaction rollback、submessage error/reply/savepoint 的精确边界必须随 runtime profile 固定。
- 资源：Cosmos gas、Wasm gas、storage 和链定制模块共同决定。

## 3. Portable fragment 与扩展

Portable 候选：Cell/Map、JSON entry/query、checked arithmetic、event attributes、sender、funds、transaction-local failure。

扩展：CosmosMsg、SubMsg/reply policy、bank/staking/custom module messages、IBC packet/ack/timeout、migrate/admin、chain query。每种 custom message schema 属于 network/profile extension。

## 4. `CosmWasmPlan` schema

```text
CosmWasmPlan {
  profile, entrypoints, jsonSchemas,
  storageSchema, hostImports,
  responseMessages, submessages, replies,
  ibcHandlers, events, errors, gasAssumptions
}
```

Plan 必须表达 SubMsg id、reply policy、result decoding 与保存点；不能复用 `NearPlan` 的 Promise DAG。

## 5. Target IR 与制品

`CosmWasmPlan → CosmWasmModuleRecipe → shared Wasm encoder`。预期输出 Wasm、JSON schema、manifest、capability declaration 和 migration metadata。当前不创建 emitter。

## 6. 工具链

实现前冻结 Rust-independent Wasm ABI、`cosmwasm-vm`/`wasmd` 版本、allowed capabilities、Cosmos SDK profile 与 schema conventions。

## 7. 部署流程

预期 gate：本地链 store code → instantiate → execute/query → SubMsg success/error/reply → migrate。每一步保存 tx/event/state evidence；IBC 另需双链 harness。

## 8. 安全

重点是 reply/savepoint 误建模、custom message schema confusion、fund denom/amount、address validation、IBC timeout/replay、migration admin、iterator determinism 和 gas amplification。

## 9. 验证阶梯

official ABI fixture → Wasm VM static validation → `cosmwasm-vm` unit → local `wasmd` transaction/reply → optional IBC two-chain evidence。

## 10. 不支持、风险与成熟度退出

当前所有代码生成均不支持。设计退出条件：冻结 versioned profile、复核 transaction/reply semantics、完成 ABI/import/schema fixture 和 local-chain test plan。只有这些完成后才能进入 implementation。
