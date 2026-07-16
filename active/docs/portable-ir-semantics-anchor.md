# Portable IR Semantics Anchor (multi-chain source of truth)

Status: **already on `main`** — this note pins the architectural rule so
Scheme 1/2 Solana work (and any future backend) never re-opens a
"skip Portable IR" path.

## Non-negotiable

```
Lean Contract (Intent API / contract_source)
              │
              ▼
     Portable IR (Probe-IR)
              │
              │  IR.Semantics          ← formal multi-chain source
              │  IR.StepSemantics      ← inductive trace layer
              │  IR.CounterSemantics   ← Counter fragment totalization
              │
     ┌────────┼────────┬──────────┬─────────┐
     ▼        ▼        ▼          ▼         ▼
   EVM     Solana    NEAR       Sui      Aleo/Psy/…
```

**Portable IR is never optional.** dennj/solana-lean-style "pure Lean → sBPF"
cross-compilation is **not** a ProofForge product path. Hybrid modes that
bypass IR for "simple contracts" are rejected: they would split the multi-chain
refinement story and reintroduce per-chain authoring.

## Where the formal IR semantics already lives

| Module | Role |
|--------|------|
| `ProofForge/IR/Semantics.lean` | Executable big-step semantics for the covered IR subset (scalar + aggregate/storage/control-flow/event slices). Three-valued `ExecResult` (ok / reverted / error). |
| `ProofForge/IR/StepSemantics.lean` | Generic inductive `runTraceListGen` + soundness by induction (Tier C-proof Phase 6a). Backend-agnostic over the call list. |
| `ProofForge/IR/CounterSemantics.lean` | Counter fragment totalization + all-state lemmas. |
| `ProofForge/IR/ValueVaultSemantics.lean` | ValueVault fragment helpers. |
| `ProofForge/Backend/Refinement/Core.lean` | Shared `traceSimulation_lift`, `TargetSemantics`, observable types. |
| `ProofForge/Backend/Refinement/CounterUniversal.lean` | Counter C-proof skeleton vs tiny `counter-model`. |

There is **no** separate `ProofForge/PortableIR/Semantics.lean` to invent —
`ProofForge.IR.Semantics` *is* that anchor. New work extends coverage and
connects backends; it does not fork a second IR semantics.

## How each backend attaches

Every backend refinement is of the form:

```
IR.Semantics.Run  ⇝  TargetSemantics.Run
```

| Backend | IR side | Target side today |
|---------|---------|-------------------|
| EVM | `runEntrypoint*` | Yul subset interpreter + opt-in powdr `stepF` (`ProofForgeFormalEvm`) |
| Solana | `runEntrypoint*` | `SbpfInterpreter` + encode/lift to solanalib (`ProofForgeFormalSolana`) |
| NEAR | `runEntrypoint*` | Wasm interpreter / offline host |
| Others | same IR | target-specific (no IR bypass) |

Solana Scheme 1/2 work **only** deepens the Solana column. It must not
introduce a Solana-only source language path.

## Solana verified-lowering stack (from IR only)

See [solana-sbpf-solanalib-bridge.md](solana-sbpf-solanalib-bridge.md).

```
IR.Module
  │ SbpfAsm.lowerModule          (EmitSBPF, product)
  ▼
Array AstNode  ──render──► .s ──sbpf──► ELF
  │ LabeledSbpf.fromNodes        (Scheme 2 Phase A)
  ▼
LabeledProgram / ResolvedInst
  │ BpfEncode.toBpfBin           (default binary seam)
  │ LabeledToSolanalib.lift*     (Scheme 2 Phase B, opt-in)
  ▼
solanalib BpfInstruction / verifyInstr / bpfInterp
```

## What "formally verify Portable IR" still means

The anchor exists; **coverage** is the open work (documented in
[formal-verification.md](formal-verification.md)):

1. Expand `IR.Semantics` toward the full checked IR surface (FV-2).
2. Keep crosscall as an honest stub until an oracle path exists (U2).
3. Prove per-backend simulation for declared supported fragments (C-proof),
   starting from Counter, not from a second IR.

## Gates

- IR semantics / Counter fragment: existing `just` smokes
  (`ir-counter-semantics-smoke`, `counter-universal-refinement-smoke`, …).
- Solana encode + labeled: `just solana-bpf-encode-smoke`.
- Solana solanalib lift: `just solana-solanalib-adapter`.
