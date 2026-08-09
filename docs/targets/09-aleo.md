---
id: TARGET-ALEO
title: Aleo target dossier
status: proposed
owner: architecture
updated: 2026-08-10
normative: true
---

# Target Dossier：Aleo

状态：`proposed`
Target ID：`aleo`
工程状态：implemented leaf；不自动扩展 accepted Phase 1 范围。

## 产品物化权威

Aleo 只有一条产品路径：

```text
SemanticProgramV1
  → capability-gated AleoPlan
  → target-owned Aleo Instructions IR
  → canonical {programId}.aleo
  → zero-tool FinalizeV1
```

唯一 codegen profile 是 `aleo-instructions-v1`。旧 source-compiler profile、source AST、
debug dual-write、compiler finalization 和 compiler Tool Lock 成员已删除；旧 profile id
必须返回 `PF-PROFILE-UNKNOWN`，不得 fallback。

权威实现：

- `ProofForgeV2/Targets/Aleo/LowerSemanticV1.lean`
- `ProofForgeV2/Targets/Aleo/Instructions/SchemaV1.lean`
- `ProofForgeV2/Targets/Aleo/Instructions/LowerPlanV1.lean`
- `ProofForgeV2/Targets/Aleo/Instructions/TextCodecV1.lean`
- `ProofForgeV2/Targets/Aleo/EmitIRV1.lean`
- `ProofForgeV2/Targets/Aleo/FinalizeV1.lean`

迁移决定见 [ADR-0035](../adr/0035-direct-native-artifact-materializers.md)，lowering
规格见 [`09-aleo-instructions-lowering.md`](09-aleo-instructions-lowering.md)。

## 1. 身份与执行模型

Aleo 是带私有 proof execution 与公共 on-chain finalization 的 ZK application chain。
Aleo Instructions 是本 target 的产品 IR 与文本制品格式；frontend 与 SemanticProgramV1
不因 target 改写业务语义。

状态、记录、mapping、proof execution、finalization、网络和费用是不同语义面。
当前产品只物化已声明支持的 public mapping 子集，不由平台能力反推开放 record custody、
program call、proof、deploy 或 network query。

## 2. 支持表面

当前 target-owned Plan/Instructions lowering 覆盖：

- public UInt8/16/32/64、Int64、Bool、Unit 与 exact BLS12-377 Fr Field；
- named Struct/Enum、Array、Bytes、`Option UInt64` 与 dense Map cap-2 的受限 flatten；
- checked arithmetic、比较、bitwise/logical/shift；
- immutable let、assign、assert、if/match、bounded-for、bare revert；
- pure function inline 与 literal-backed constants；
- public mapping state，含 store-then-read 的 pre-store snapshot 原子聚合写。

具体 capability 必须同时通过 requirement resolver、Plan validation 和 Instructions
lowering；任一未声明形状 fail closed。

## 3. Fail-closed 边界

以下仍拒绝：

- event emission、external call、schedule、ContextRead；
- 带 payload 的 error；
- nonempty invariant Plan；
- Principal、String、Int128/256；
- nested/non-UInt64 Option、aggregate pure-function return；
- record custody、proof execution、deployment 与 network query。

Plan admitted 但 Instructions lowering 失败时返回 `ALEO-IR-G5-HARD`；不存在 source
语言旁路。

## 4. Target IR 与制品

`Aleo.TargetIR` 保留关联 `AleoPlan` 与 canonical `Instructions.ProgramV1`。产品
materialize 有序输出两个 `materialized-base`：

1. `{programId}.aleo`：canonical Aleo Instructions 文本；
2. `{programId}.aleo-query-contract.json`：
   `proof-forge-aleo-query-contract/v1` network-state descriptor。

query descriptor 只描述 public mapping、bare view 与 dropped-result observation；它不执行
查询，也不是编译器输入。`ArtifactEncoding.aleoInstructions` 是唯一 Aleo artifact encoding。

## 5. Finalization 与工具边界

`FinalizeV1` 是 zero-tool、`deployable=false`。产品不启动 source compiler、VM、prover、
network client 或 deploy 工具。Tool Lock 不包含 Aleo source compiler；doctor/install 对 Aleo
返回空 core-tool closure。

Aleo Instructions 的 schema/opcode 权威来自版本化官方文档与仓库内 canonical fixtures。
更换 schema 或开放新 opcode 必须更新 target-owned codec、golden 与 capability，而不是引入
source-language fallback。

## 6. 安全与资源

重点风险：private/public 泄漏、record owner/custody、double spend、mapping key visibility、
proof/finalization mismatch、program/network identity 与 upgrade authorization。

Plan gate 继续限制表达式深度、函数数、参数数与语句数。输出仍经 content-bound inventory、
evidence、manifest-last 与 `inspect` exact disk closure。

## 7. 成熟度

当前成熟度是 **canonical Aleo Instructions emission**。没有 VM execution、proof、deploy、
on-chain finalization、offline query、hermetic 或 formal refinement 证据；删除旧编译器路径不提高
这些成熟度。accepted PRD Phase 1 仍为 EVM/Solana/NEAR/Noir；Aleo 属 engineering
扩面，accepted/engineering scope 边界由 ADR-0036 固定。
