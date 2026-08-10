---
id: TARGET-PSY-DPN
title: Psy DPN lowering contract
status: draft
owner: engineering
updated: 2026-08-10
normative: false
---

# Psy DPN lowering contract

本文记录 `ProgramV1 → SemanticProgramV1 → PsyPlan → DPN` 的工程合同。产品只输出
DPN package；不存在 Psy source artifact、source compiler profile、debug dual-write或
source-language fallback。

## 1. Authority pin

| 项 | 值 |
|---|---|
| Repository | `https://github.com/PsyProtocol/psy-node` |
| Revision | `79e0b82422ebdd1173a7b4b3751eb3186aad83e5` |
| Crate | `psy_vm` |
| Schema | `DPNFunctionCircuitDefinition` |
| Paths | `client_prover/psy_vm/src/dpn/vm/def.rs`, `client_prover/psy_vm/src/dpn/ops/` |
| Lean pin | `ProofForgeV2.Targets.Psy.Dpn.SchemaV1.psyNodeDpnAuthorityRevV1` |
| Supply-chain annotation | `supply-chain/psy-node-dpn-authority.v1.json` |

该 revision 只提供 schema、discriminant 与 method-id algorithm authority。它不是产品可执行
工具，不进入 Tool Lock。revision 改变时必须重新验证 schema constants、codec 与 goldens。

## 2. Product contract

```text
ResolvedEngineeringBuildV1
  → Psy.planFromCapability
  → Psy.irFromCapability
  → Psy.buildFromCapability
  → {programName}.dpn.json
```

Exact identities：

- target：`psy`
- codegen profile：`psy-dpn-v1`
- artifact encoding：`psyDpn`
- MIME：`application/json`
- finalizer：zero-tool、`deployable=false`

旧 profile id 不在 registry。选择旧 id 返回 `PF-PROFILE-UNKNOWN`；产品不得 fallback。

## 3. DPN model

每个 materialized callable 对应一个 `DPNFunctionCircuitDefinition`：

```text
DPNFunctionCircuitDefinition {
  name,
  method_id,
  circuit_inputs,
  circuit_outputs,
  state_commands,
  state_command_resolution_indices,
  assertions,
  definitions,
  events
}
```

`DPNIndexedVarDef` 使用 exact data-type/op-type discriminants。indexed id 为
`(dataType << 32) | index`。枚举有保留洞，禁止按声明 ordinal 自行推导 wire value。

Method id 使用 pinned upstream `gen_dapen_contract_function_method_id` algorithm；Counter
`get`、`increment`、`initialize` fixtures固定算法结果。产品不使用仅靠名称的自由 pin 表。

## 4. State and value layout

- scalar values使用 DPN Target/Bool/U32 carriers；
- UInt128/256使用 4/8 个 little-endian UInt32 limbs；
- named aggregates、Array、Bytes、Principal identity、Option 与 dense Map 采用 Plan 冻结的
  deterministic leaf order；
- aggregate store 必须先在 pre-store snapshot 求值全部 leaves，再提交 ordered state commands；
- state-command resolution index 与 command array exact 对齐；
- return leaves按 target ABI order进入 `circuit_outputs`。

Unknown type、leaf count、layout或 state command fail closed。

## 5. Operation coverage

当前 DPN lower支持已开放 Plan 中的：

- literal、state load/store、construct/field/index；
- checked UInt/Int arithmetic、compare、logical、bitwise、shift；
- Goldilocks Field add/sub/mul/div/neg/eq/ne；
- if/match Select lowering；
- bounded UInt64 loop static unroll；
- assert、bare revert；
- constants与 pure-function inline；
- event与 void synchronous call 的既有 PARTIAL DPN encoding。

Wide integer multiplication采用 bounded schoolbook construction；division/remainder使用
restoring division；shift使用 bounded bit walk。所有中间 carrier、range guard、overflow与
zero-divisor behavior由 target-owned lowering固定。

## 6. Fail-closed matrix

| Surface | Status | Boundary |
|---|---|---|
| UInt8/16/32/64/128/256 | lowered | Plan + DPN tests |
| Int8/16/32/64 | lowered | Plan + DPN tests |
| Goldilocks Field | lowered | exact FieldSpec |
| bn254/BLS12-377 Field | fail closed | Plan type closure |
| named/Array/Bytes/Principal/Option | bounded lower | leaf cap/layout gate |
| dense Map UInt64 cap-8 | lowered | fixed 24-leaf layout |
| nested Map / Map return | fail closed | Plan gate |
| if / match | lowered | Select/branch construction |
| bounded for | bounded lower | static-unroll budget |
| pureFn/localCall | bounded inline | recursion/effect gate |
| payload error | fail closed | no structured DPN payload ABI |
| event | PARTIAL | ordered DPN event encoding only |
| void sync call | PARTIAL | exact DPN invoke shape only |
| result call / schedule | fail closed | capability/Plan gate |
| ContextRead / Commit | fail closed | no frozen public-input binding |
| nonempty invariant | fail closed | no target refinement contract |
| UPS / network / deploy | absent | outside materializer/finalizer |

If Plan admission succeeds but DPN lowering cannot encode the shape, materialization fails with
`PSY-DPN-G5-HARD`. The residual fallback allowlist is empty.

## 7. Canonical codec and tests

`Dpn.JsonCodecV1` is the sole package encoder/decoder. It validates exact JSON shape, integer-only
wire values, required fields and round-trip identity. The test corpus pins：

- operation/data-type discriminants and indexed ids；
- method-id algorithm；
- Counter full-byte package golden；
- control flow, wide integers, aggregate layouts, Map and effects；
- sole-profile product materialization；
- unknown/unsupported shapes fail closed；
- exactly one `.dpn.json` output and no alternate artifact encoding。

The Counter golden is a DPN schema fixture. It does not imply execution by an external compiler or
runtime.

## 8. Finalization and maturity

`Psy.FinalizeV1` performs no compilation or execution and adds no files. The product has no compiler
or runtime tool dependency for Psy. Removal of the old source lane also removes its acceptance/runtime
recipes and distribution payloads.

Current claim ceiling：canonical DPN emission with content-bound artifact closure. No local execution,
proof generation, UPS, network settlement, deployment, hermetic qualification or formal
Reference↔Psy refinement is claimed.
