---
id: FAMILY-WASM-HOST
title: Wasm Artifact 与 Host family view
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# Family View：Wasm Artifact 与 Host

状态：`draft`

NEAR、CosmWasm、Soroban、ICP 都以 Wasm module 为制品容器，但宿主语义不同。

## 允许共享

- 确定性 Wasm AST 与 encoder；
- 基础 type/control/integer/memory 指令；
- module section writer、hash 和 provenance；
- 与具体 host 无关的结构验证。

## 必须分离

| Target | Plan | 状态 | 调用/提交 | ABI/权限 |
|---|---|---|---|---|
| NEAR | `NearPlan` | KV | Promise/receipt | JSON/Borsh + account context |
| CosmWasm | `CosmWasmPlan` | instance KV | CosmosMsg/SubMsg/reply | JSON messages + Cosmos sender/funds |
| Soroban | `SorobanPlan` | instance/persistent/temporary + TTL | sync invocation | XDR + auth tree |
| ICP | `IcpPlan` | heap + stable memory | actor message/await | Candid + Principal/controllers |

禁止 `GenericWasmHostPlan` tagged union。每个 Plan 生成专属 `ModuleRecipe`，由共享 encoder 序列化；host validator、imports/exports、custom sections、storage、resource、upgrade 和 deploy 都留在目标层。
