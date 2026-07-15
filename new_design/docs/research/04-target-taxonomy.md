---
id: RPT-004
title: 目标分类研究
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# 目标分类研究

状态：`draft`
研究日期：2026-07-15

## 问题

怎样把多平台组织在同一产品中，又不因使用同一种字节码或 ZK 技术而错误合并其语义？

## 多轴描述符

编译使用以下正交字段，而不是单一 `family`：

```text
targetId
artifactEncoding
executionHost
commitModel
stateBinding
callModel
proofModel
settlementModel
abiModel
resourceModel
toolchainProfile
supportClaims
```

`family` 只是文档视图，可把相关目标放在相邻页面；它不能决定 lowering。

## 目标视图

| Target ID | 文档视图 | Phase 1 | 关键区分 |
|---|---|---|---|
| `evm` | contract VM | implement | account storage、sync call、revert |
| `solana` | explicit-account SVM | implement | accounts、signer/writable、CPI |
| `near` | Wasm host | implement | KV、Promise DAG、receipt commit |
| `cosmwasm` | Wasm host | design | Cosmos messages、SubMsg/reply、IBC |
| `soroban` | Wasm host | design | XDR、auth tree、TTL storage |
| `icp` | Wasm actor host | design | Candid、stable memory、await boundary |
| `noir` | circuit compiler | implement | ACIR/Brillig、witness、external state continuity |
| `openvm` | zkVM | design | RV32IM guest、VmExe、external verifier |
| `aleo` | ZK application chain | design | records、mappings、proof/final contexts |
| `psy` | ZK application chain | research | partitioned state、CFC/UPS/network aggregation |

## Wasm 分类结论

NEAR、CosmWasm、Soroban、ICP 都接收 Wasm，但 Wasm 只回答“机器指令与模块如何编码”，没有回答存储、ABI、调用、权限、gas/cycles、升级和提交边界。因此它们最多共享：确定性 Wasm AST/encoder、基础结构验证、通用整数/控制/内存指令、section writer、hash/provenance。

它们分别从 `NearPlan`、`CosmWasmPlan`、`SorobanPlan`、`IcpPlan` 生成 target-specific `ModuleRecipe`，再调用共享 encoder。禁止创建把四种宿主语义塞进 tagged union 的 `GenericWasmHostPlan`。

## ZK 分类结论

- Noir 是 circuit compiler：描述关系、witness/public input，proof backend 独立，无原生链状态。
- OpenVM 是 zkVM：证明 guest 指令执行，宿主结算外置。
- Aleo 和 Psy 是 ZK application chain：证明机制与链状态、托管、finalization/settlement 共同构成平台。

所以 “ZK series” 只能作为产品导航标签，不能共享一个 `ZkPlan`。

## Support resolution

1. 前端产生 target-neutral `SemanticProgram` 和带 span 的 requirements。
2. 通过 exact `TargetId + CodegenProfile` 查静态 registry。
3. 每个 requirement 必须由 exact version/digest `SupportClaim` 匹配。
4. 验证 claim 的前置条件和证据等级。
5. 构造 `ResolvedProgram target`。
6. target materializer 构造其专属 Plan；Plan 拥有 ABI、layout、imports、proof wiring。

任何缺失、版本漂移或语义不等价都失败。禁止 target alias 猜测、最近版本匹配、Legacy fallback 和把错误降级为 warning。

## 反例

“输出 Wasm 所以属于 Wasm 语义”是错误分类。Arbitrum Stylus 即使使用 Wasm 形式，仍在 EVM-compatible 执行与结算语境中；同理 ICP 的 Wasm actor 模型也不能由 NEAR host imports 推断。

## 开放项

- 网络 fork/profile 如何影响已有 artifact 的可部署性。
- extension 的 semantics digest 如何发布和撤销。
- 跨 target 的等价性证据分级：静态、解释器、runtime、network/proof。
