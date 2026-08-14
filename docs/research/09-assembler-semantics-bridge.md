---
id: RESEARCH-09
title: assembler-semantics as Solana ISA foundation
status: draft
owner: architecture
updated: 2026-08-14
normative: false
---

# Research: assembler-semantics ↔ ProofForge V2 Solana

> **Research only.** This note does not create a Lake dependency, runtime
> oracle, or product fallback. Per ADR-0012, external code is evidence input
> until an accepted ADR promotes an exact pin into the V2 toolchain policy.

## Source

| Field | Value |
|-------|--------|
| Repository | [`DaviRain-Su/assembler-semantics`](https://github.com/DaviRain-Su/assembler-semantics) |
| Audited revision | `ef6e20c20827e4158e1cb025518465aa8beb46da` |
| Method | Lean 4 sBPF ISA semantics (yul-semantics style) |
| Normative contract | `docs/proof-forge-interface.md` in that repo |
| Stable import | `SbpfSemantics.Api` |

2026-08-14 source audit确认该revision使用Lean 4.31.0、无transitive Lake dependency，并公开
resolved instruction runner、memory/host dialect、observation与encode/decode。它仍不提供`.s` parser、
label resolver、ELF reader或production Solana account serializer。候选promotion边界已写入
[`ADR-0048`](../adr/0048-optional-solana-sbpf-semantics-provider.md)；该ADR已`accepted`并固定development
Lake pin。ProofForge现已直接解析/resolve production StateCell `.s`为provider `Program`，并用真实
single-account Loader V3 ABIv1 image执行bounded provider observations。`SbpfHandlerJoinV1`已固定
Handler invocation↔Loader invocation、success/overflow observation及Reference→Handler→provider
组合关系，并要求真实两侧evaluator等式；但production 168条program的provider执行等式尚未由
identity-bound assumptions闭合。当前完整55-step `get`轨迹与provider `runFuel` status-zero等式已
证明；strict artifact identity→lookup、encoded input→read以及实际`execInstr`→proof-bearing stack
effects均已接入单一sound checker/`runFuel` theorem；validated execution-window与encoder projection
也已给出真实`runBound`/`executeLoaderV3SingleAccountV1`等式。剩余的是在Handler join中discharge
production invocation gate并证明observation relation，所以仍**没有**完整concrete provider-backed
refinement claim。

## Why it matters for V2

V2 Solana target (`docs/targets/02-solana.md`) needs:

1. Plan → sBPF artifacts (TASK-D5-03).
2. Semantic interpreter vs sBPF emulator (verification ladder step 3).
3. Local runtime Counter evidence (TST-SOL-005).

`assembler-semantics` supplies **L2 resolved instructions + L4 small-step +
observation surface**, not the full SVM/account model. That matches OOS-002
(do not rewrite complete SVM in Lean) while still enabling:

- Lean-local **reference traces** for lowered fragments.
- Encode/decode and redecode preservation goldens.
- A plug-in `ExecDialect` / `hostExec` for host effects.

## Current wiring and remaining execution seam

```text
ProofForgeV2.Solana materializer
    │ exact production .s + expected SHA-256
    ▼
SbpfArtifactV1 strict parse/resolve
    │ identity-bound Array Instr + artifact layout
    ▼
SbpfExecutionV1 Loader V3 ABIv1 adapter
    │ bounded input image
    ▼
SbpfSemantics.Api   -- optional formal/trace profile
    runFuel / Observation / final account-data window
    ▼
differential vs Mollusk / sbpf VM (external evidence)
```

Promotion path (ADR-0048 accepted; 1–3 complete, 4 in progress):

1. Add the exact ADR-0048 revision to Lake and the supply-chain closure.
2. Strictly parse and resolve the exact production `.s` artifact into `SbpfSemantics.Instr`; do not add
   a proof-only `HandlerIR → Program` code generator.
3. Build the real Loader V3 single-account input and execute the resolved program.
4. `SbpfHandlerJoinV1`先固定两侧invocation/outcome/account join，再以bounded sparse provider trace
   discharge identity-bound execution equations and compose with existing Reference→Handler theorems。
   `get`完整55/55步与`runFuel` status-zero sparse theorem已完成；exact SHA-256 + 全部certificate
   program lookup以及concrete encoded input reads的可执行checker与kernel soundness也已闭合。
   proof-bearing provider stack-store derivation和真实/tampered回归也已闭合，并聚合为单一sound
   trace gate；raw/encoded Loader execution equation的sound projection也已闭合。下一步在
   `SbpfHandlerJoinV1`中discharge production gate并证明Handler/provider observation relation。
5. Keep product ELF path independent (sbpf toolchain); formal lane fail-closed
   if pin missing.

## Concrete integration surface (sibling Phase 1)

```lean
import SbpfSemantics.Api
import SbpfSemantics.CounterScenario

-- Portable Counter L2 (input cell = stand-in for account data)
open SbpfSemantics.CounterScenario
#eval (runInc 0#64 1#64).r0   -- expected 1
```

Stable modules: `Api`, `Observation`, `AccountLayout`, `CounterScenario`.
Contract: sibling `docs/proof-forge-interface.md`.

## Explicit non-claims

- Does not replace SolanaPlan, account schema, CPI, or IDL.
- Does not claim Agave binary compatibility.
- Does not satisfy clean-room until pinned under V2 dependency policy.
- Current join carrier/relations are not a proof that the 168-instruction StateCell artifact executes them;
  all 55/55 `get` steps, exact identity→lookup binding, concrete input reads, and proof-bearing stack-store
  derivation are behind sound trace/Loader execution gates, but those gates are not yet discharged in the
  HandlerIR/provider join carrier.

## Related V1 research (parent, also research-only)

- Parent `docs/solana-sbpf-solanalib-bridge.md` (LabeledSbpf / solanalib host).
- Complementary: assembler-semantics is a cleaner ISA ground truth;
  parent bridge remains a product-adjacent formal experiment.
