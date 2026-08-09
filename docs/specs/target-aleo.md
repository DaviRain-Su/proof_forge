---
id: SPEC-TARGET-ALEO-001
title: Aleo Instructions capability-gated target specification
status: proposed
owner: targets
updated: 2026-08-10
normative: true
---

# Aleo Instructions target specification

## 1. Scope

`proof-forge-next build --target aleo` consumes retained `SemanticProgramV1` through
`ResolvedEngineeringBuildV1`, constructs target-owned `AleoPlan`, lowers directly to canonical Aleo
Instructions, and emits a network-state descriptor. There is no source-compiler lane or target-language
fallback.

Exact product identities：

- target：`aleo`
- codegen profile：`aleo-instructions-v1`
- artifact encoding：`aleoInstructions`
- finalizer：zero-tool、`deployable=false`

## 2. Supported surface

| Category | Supported subset |
|---|---|
| State | public UInt8/16/32/64、Int64、exact BLS12-377 Field；bounded named/Array/Bytes/`Option UInt64`/dense Map cap-2 flatten |
| Init | one-shot initialized guard + public mapping writes |
| Entry | checked state transition；non-Unit mapping-touching result is explicitly `resultDropped` |
| View | bare single-leaf public mapping descriptor；computed/multi-leaf state view fail closed |
| Expressions | literals、places、checked arithmetic、compare、bitwise/logical/shift、pureCall、supported aggregate/index/Option ops |
| Statements | immutable let、assign、assert、if/match、bounded-for、bare revert；aggregate store uses pre-store snapshot |
| Pure functions | bounded scalar inline；aggregate return fail closed |
| Constants | literal-backed `Op.Constant` inline |

Every surface must pass requirement resolution、Plan validation、Instructions lowering and codec
round trip. Platform capability alone never opens a feature.

## 3. Fail closed

The target rejects event emission、external call、schedule、ContextRead、payload errors、nonempty
invariants、Principal、String、Int128/256、nested/non-UInt64 Option、record custody、proof execution,
deployment and network query. Plan-admitted but non-lowerable shapes fail with
`ALEO-IR-G5-HARD`.

## 4. Aleo Instructions contract

The target owns `Instructions.ProgramV1` and its exact text codec. The schema covers only the opcode,
type, mapping, function/finalize and control-flow forms admitted by the Plan lowerer. Unknown opcode,
annotation, label, register or declaration shape fails closed.

Key lowering invariants：

- each Plan state leaf maps deterministically to `pf_state_N`；
- mapping key is canonical `0u8` in the current single-slot pilot；
- all aggregate leaves are evaluated before ordered mapping writes；
- checked arithmetic/failure behavior remains explicit；
- bounded loops are statically expanded under the Plan budget；
- target IR retains and revalidates the exact source Plan；
- `encodeProgram` then `decodeProgram?` must reproduce the exact IR。

## 5. Artifacts

Materialization emits exactly two ordered `materialized-base` files：

1. `{programId}.aleo` — canonical Aleo Instructions text, `text/plain`；
2. `{programId}.aleo-query-contract.json` —
   `proof-forge-aleo-query-contract/v1`, `application/json`。

The descriptor binds the profile、program、state mappings、bare views and dropped-result observations.
It is not executable query output and is not compiler input. Both files enter content-bound inventory,
evidence and manifest-last exact disk closure.

## 6. Finalization and maturity

`FinalizeV1` performs no compilation、VM execution、proof、deployment or network query and emits no
extra file. Tool Lock contains no Aleo source compiler; doctor/install report no core tool requirement
for this target.

Current maturity is canonical Aleo Instructions emission only. No VM/proof/network/formal/hermetic
claim follows. The direct-only migration and compatibility break are recorded in
[ADR-0035](../adr/0035-direct-native-artifact-materializers.md).
