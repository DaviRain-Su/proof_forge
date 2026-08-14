---
id: RESEARCH-09
title: assembler-semantics as Solana ISA foundation
status: draft
owner: architecture
updated: 2026-07-16
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
[`ADR-0048`](../adr/0048-optional-solana-sbpf-semantics-provider.md)；该ADR仍为`proposed`，因此当前
仓库**没有**新增Lake dependency，也没有provider-backed refinement claim。

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

## Proposed future wiring (not implemented here)

```text
ProofForgeV2.Solana materializer
    │ emits Array Instr  (resolved)
    ▼
import SbpfSemantics.Api   -- optional formal/trace profile
    pfRun / Observation / pfEncode
    ▼
differential vs Mollusk / sbpf VM (external evidence)
```

Promotion path (when ADR-0048 is accepted):

1. Add the exact ADR-0048 revision to Lake and the supply-chain closure.
2. Refactor the production emitter to one structured instruction source; render `.s` and project
   `SbpfSemantics.Instr` from that same source.
3. TST-SOL-*: `Observation.controlEq` against Semantic.Program reference traces
   for Counter portable fragment.
4. Keep product ELF path independent (sbpf toolchain); formal lane fail-closed
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

## Related V1 research (parent, also research-only)

- Parent `docs/solana-sbpf-solanalib-bridge.md` (LabeledSbpf / solanalib host).
- Complementary: assembler-semantics is a cleaner ISA ground truth;
  parent bridge remains a product-adjacent formal experiment.
