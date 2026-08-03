---
id: TARGET-COSMWASM
title: CosmWasm target dossier
status: draft
owner: architecture
updated: 2026-08-03
normative: true
---

# Target Dossier：CosmWasm

状态：`draft`
Target ID：`cosmwasm`
Phase 1（规范/dossier）：设计，不实现

## 当前工程偏离（A0 registry slice，非 formal / 非 dossier 升格）

commit `dd607de72` 已把 CosmWasm 标为 engineering registry `implemented`，加入 profile
`cosmwasm-wasm-u64-v1`、descriptor、五键 requirement support row 与 CLI list/inspect；两类
call requirement 继续拒绝。**但当前没有** `ProofForgeV2/Targets/CosmWasm*` target-owned
Plan/IR/emitter/finalizer，`Registry.materializeResult` 也没有 `.cosmwasm` dispatch，因此产品
`build --target cosmwasm` 仍以 `PF-TARGET-NOT-IMPLEMENTED` fail closed。CLI 的
`wasm-validated-alpha` 是 A0 registry label，不是已有 Wasm artifact/runtime evidence。

CW-A1 必须在不复用 `NearPlan` 的前提下补 target-owned Plan/IR/materializer 与产品正/负测试，
但目前先由 `CW-ABI-FREEZE` 阻塞：下述 §6/§10 要求 implementation 前冻结 versioned runtime、
Rust-independent ABI、capability/SDK/schema 及 transaction/SubMsg/reply savepoint 语义，且
`SRC-CW-002` 仍 provisional。除非产品正式修订本 dossier 以批准 structural-only 先导并限定
`wasm-validated-alpha` 声明，否则不得先按行业常识落码。在此之前不得把 A0 写成 Phase-1 backend
完成。未合入候选 `ed2401e72` 的 static `cosmwasm-check` fixture 不满足该 design-exit；未合入
`48e8bffad` 的 A1 emitter 既绕过 freeze/scope 决策，独立代码审计又认定静态内存布局、JSON
溢出、Int64 乘法和无界缓冲等 P0 候选，必须保持隔离而非直接合并。该工程 promotion 还扩大了
`DOC-ADR-SCOPE`（accepted 四目标 vs engineering 七个 registry-implemented target）文档决策债。

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

扩展：CosmosMsg、SubMsg/reply policy、bank/staking/custom module messages、IBC packet/ack/timeout、migrate/admin、chain query。每种 custom message schema 属于 target semantics/CodegenProfile exact 引用的版本化 extension；NetworkProfile 只能声明兼容 BuildIdentity，不能定义 schema。

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
