---
id: TARGET-PSY
title: Psy DPN target dossier
status: draft
owner: architecture
updated: 2026-08-10
normative: true
---

# Target Dossier：Psy DPN

状态：`draft`
Target ID：`psy`
工程状态：implemented leaf；不自动扩展 accepted Phase 1 范围。

## 产品物化权威

Psy 只有一条产品路径：

```text
SemanticProgramV1
  → capability-gated PsyPlan
  → target-owned DPN IR/package
  → canonical {programName}.dpn.json
  → zero-tool FinalizeV1
```

唯一 codegen profile 是 `psy-dpn-v1`。旧 Psy source profile、source emitter、debug
artifact、source compiler/runtime recipes 和 compiler Tool Lock 成员已删除；旧 profile id
必须返回 `PF-PROFILE-UNKNOWN`，不得 fallback。

权威实现：

- `ProofForgeV2/Targets/Psy/LowerSemanticV1.lean`
- `ProofForgeV2/Targets/Psy/Dpn/SchemaV1.lean`
- `ProofForgeV2/Targets/Psy/Dpn/LowerPlanV1.lean`
- `ProofForgeV2/Targets/Psy/Dpn/JsonCodecV1.lean`
- `ProofForgeV2/Targets/Psy/EmitIRV1.lean`
- `ProofForgeV2/Targets/Psy/FinalizeV1.lean`

迁移决定见 [ADR-0035](../adr/0035-direct-native-artifact-materializers.md)，DPN 规格见
[`10-psy-dpn-lowering.md`](10-psy-dpn-lowering.md)。

## 1. 身份与执行模型

Psy 的公开材料描述用户分区状态、本地 Contract Function Circuit、User Proving Session
递归聚合和网络最终证明，因此属于 ZK application chain，而不是通用 circuit compiler。
当前产品仅编码 target-owned DPN 方法定义；不执行 proof、UPS、network settlement 或 deploy。

DPN schema/method-id authority 固定到
`PsyProtocol/psy-node@79e0b82422ebdd1173a7b4b3751eb3186aad83e5`，对应
`DPNFunctionCircuitDefinition`、operation/state-command discriminants 与
`gen_dapen_contract_function_method_id`。这是 source/schema authority pin，不是 executable
Tool Lock 成员。

## 2. 支持表面

当前 DPN lowering 覆盖：

- UInt8/16/32/64/128/256 与 Int8/16/32/64 的受限 envelope；
- exact Goldilocks Field、Bool、Unit；
- named Struct/Enum、Array、Bytes、Principal identity、`Option UInt64` 与 dense Map cap-8
  的受限 leaf lowering；
- checked arithmetic、比较、logical/bitwise/shift；
- immutable let、assign、assert、if/match、bounded-for static unroll、bare revert；
- literal-backed constants与 pure-function inline；
- DPN event 与 void synchronous-call 的既有 PARTIAL encoding。

UInt128/256 采用 little-endian UInt32 limbs；乘法、除余与 shift 使用 target-owned bounded
algorithms。支持结论以当前 Plan/DPN tests 为准，不由历史 source compiler 行为推导。

## 3. Fail-closed 边界

以下仍拒绝或保持既有 PARTIAL 标签：

- bn254/BLS12-377 Field；
- nested Map、Map return、超出 aggregate-return cap；
- result-bearing call、schedule、ContextRead、Commit、nonempty invariant；
- `pf.assets` bindings、UPS、network 与 deploy。

Plan admitted 但 DPN lowering 失败时返回 `PSY-DPN-G5-HARD`；不存在 source 语言旁路。

## 4. DPN Target IR 与制品

`Psy.TargetIR` 保留关联 `PsyPlan` 与 canonical
`Array DPNFunctionCircuitDefinition`。`ArtifactEncoding.psyDpn` 是唯一 Psy artifact
encoding。materialize 只输出 `{programName}.dpn.json`，MIME 为 `application/json`。

JSON codec 强制 target-owned schema、canonical field order/shape 与 decode/encode round trip。
Counter golden 和 wider structural fixtures用于固定 method id、indexed ids、state commands、
assertions、definitions 与 inputs/outputs。

## 5. Finalization 与工具边界

`FinalizeV1` 是 zero-tool、`deployable=false`。产品不启动 source compiler、local VM、prover、
UPS 或 network client。Tool Lock 不包含 Psy source compiler/runtime；doctor/install 对 Psy
返回空 core-tool closure。

改变 upstream DPN schema/revision 时必须同步 schema constants、supply-chain annotation、
codec 与 golden。不得发明不可供给的 `psy-node` executable row。

## 6. 安全与资源

重点风险：用户分区隔离、proof/state-delta binding、authorization、encrypted delta
披露、aggregation soundness、data availability 与 pre-testnet schema drift。

DPN lower 保留函数、参数、static-unroll、aggregate leaf、expression work 与 package size上限；
未知 opcode/shape fail closed。输出继续经过 content-bound inventory、evidence、manifest-last 与
`inspect` exact disk closure。

## 7. 成熟度

当前成熟度是 **canonical DPN package emission** + **host-optional official local simulate**（`psy_user_cli simulate` via `pf test`/`pf run` / `scripts/psy_dpn_local_smoke.sh`）。没有 PF-owned VM、proof、UPS、
network deploy、hermetic 或 formal refinement 证据；删除旧 source/compiler path 不提高这些
成熟度。accepted PRD Phase 1 仍为 EVM/Solana/NEAR/Noir；Psy 属 engineering
扩面，accepted/engineering scope 边界由 ADR-0036 固定。


## 8. Product surface (agents / dApp)

- Agent playbook: [`../product/11-psy-agent-playbook.md`](../product/11-psy-agent-playbook.md)
- Frontend / wallet companion: [`../product/12-psy-dapp-frontend.md`](../product/12-psy-dapp-frontend.md)
- Demo walkthrough: [`../demos/psy-dpn-walkthrough.md`](../demos/psy-dpn-walkthrough.md)
- Official: [app](https://app.psy-protocol.xyz) · [wallet](https://app.psy-protocol.xyz/#/wallet) · [explorer](https://explorer.psy-protocol.xyz) · [IDE](https://ide.psy-protocol.xyz) · [config](https://config.psy-protocol.xyz/config.json) · [docs](https://docs.psy-protocol.xyz)

> **Session continuity:** `psy_user_cli simulate` is **one call per process** (fresh memory).
> For `init(7) → increment(5) → get = 12`, use `scripts/psy_dpn_session.py` / `pf test -t psy`
> (shared-state harness). Do not expect three separate simulates to accumulate.

