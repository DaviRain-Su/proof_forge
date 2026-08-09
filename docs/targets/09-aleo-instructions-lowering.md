---
id: TARGET-ALEO-INSTRUCTIONS
title: Aleo Instructions lowering contract
status: draft
owner: engineering
updated: 2026-08-10
normative: false
---

# Aleo Instructions lowering contract

The Aleo target lowers directly from target-owned `AleoPlan` to canonical Aleo Instructions. This is
the sole product IR and artifact path；there is no source-language intermediate、compiler compare lane
or fallback.

## 1. Product contract

```text
ResolvedEngineeringBuildV1
  → Aleo.planFromCapability
  → Aleo.irFromCapability
  → Aleo.buildFromCapability
  → {programId}.aleo + {programId}.aleo-query-contract.json
```

Exact identities：

- target：`aleo`
- codegen profile：`aleo-instructions-v1`
- artifact encoding：`aleoInstructions`
- primary MIME：`text/plain`
- finalizer：zero-tool、`deployable=false`

Removed profile ids are unknown. No alias or source-language translation occurs.

## 2. Authority

Implementation authority is target-owned：

- `Instructions.SchemaV1` defines the admitted Aleo Instructions AST；
- `Instructions.LowerPlanV1` is the sole Plan→Instructions lowerer；
- `Instructions.TextCodecV1` is the sole canonical text codec；
- `Aleo.EmitIRV1` binds the exact Plan、profile and program and revalidates round trip；
- `Aleo.FinalizeV1` performs zero-tool finalization。

Official Aleo Instructions documentation and grammar define syntax/opcode meaning. Repository
fixtures under `testdata/golden/aleo-instructions-v1/` freeze canonical output for admitted programs；
they are native Instructions fixtures, not compiler-output dependencies.

## 3. Program model

The admitted AST includes：

- program identifier；
- mappings；
- constructor；
- functions and finalize blocks；
- typed input/output declarations；
- registers and literals；
- the exact arithmetic、comparison、cast、assert、mapping and branch instructions required by the
  Plan subset。

`TextCodecV1` rejects unknown syntax、opcode or annotation. Register and label allocation is
deterministic and source-order stable.

## 4. Lowering invariants

- Program names are normalized to the target spelling before codec emission；
- Plan profile must equal `aleo-instructions-v1`；
- every Plan state leaf maps to one deterministic mapping declaration；
- aggregate stores evaluate all leaf values from the pre-store snapshot before any write；
- mapping reads/writes appear only in the public finalization path；
- checked arithmetic/failure behavior remains explicit；
- if/match lower to explicit branch/position sequences；
- bounded loops statically unroll under the Plan budget；
- pure calls inline only effect-free、acyclic bodies under resource limits；
- non-Unit state-touching results remain explicitly marked dropped and described in the query sidecar；
- `validateIR` recomputes lowering and requires exact equality；
- encoded text must decode to the identical program。

## 5. Coverage matrix

| Program/Plan surface | Status |
|---|---|
| UInt8/16/32/64、Int64、Bool、Unit | lowered |
| exact BLS12-377 Field | lowered |
| named Struct/Enum、Array、Bytes | bounded flatten |
| `Option UInt64` state/entry surface | bounded flatten |
| dense Map UInt64 cap-2 | bounded flatten |
| literals/constants、checked arithmetic、compare、bitwise/logical/shift | lowered |
| let/assign/assert/if/match/bounded-for/bare revert | lowered |
| effect-free pureFn/localCall | bounded inline |
| computed or multi-leaf state view | fail closed |
| event、external call、schedule、ContextRead | fail closed |
| payload error、nonempty invariant | fail closed |
| Principal、String、Int128/256、nested Option/Map | fail closed |
| records、proof、deploy、network query | absent |

A Plan-admitted shape that cannot be encoded fails with `ALEO-IR-G5-HARD`. The residual fallback
allowlist is empty.

## 6. Query descriptor

`renderQueryContract` emits canonical `proof-forge-aleo-query-contract/v1` JSON binding：

- program and profile；
- `.aleo` program file identity；
- public mapping names/types；
- bare views；
- dropped-result observations。

The descriptor is not executable query output and is not a compiler or VM input.

## 7. Validation and tests

Focused tests cover：

- Schema/TextCodec round trip and malformed syntax rejection；
- Counter exact bytes；
- control flow、narrow integers、Field、aggregate、Map、Option and pure-call lowering；
- constants and fail-closed effects；
- product artifact list、profile、encoding、MIME and query descriptor；
- unknown removed profile ids；
- zero-tool finalization with no extra artifacts。

## 8. Maturity

The completed engineering claim is canonical Aleo Instructions emission and exact artifact closure.
No VM execution、proof、deploy、network query、hermetic qualification or formal target refinement is
claimed. Future runtime work must consume the native Instructions artifact directly and introduce a
new versioned capability；it must not restore a source-language compiler path.
