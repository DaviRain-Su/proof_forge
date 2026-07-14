# Canonical Compiler Architecture

For a **whole-repo map** (CLI → frontend → Core → backends → gates) with Mermaid
diagrams, see [system-architecture.md](system-architecture.md). Chinese deep
dive with per-component internals:
[zh/system-architecture.zh.md](zh/system-architecture.zh.md).

ProofForge separates contract meaning from target materialization. The public
compiler route is:

```text
Legacy v1 adapter or Surface v2
  -> CanonicalContract + CanonicalEvidence
  -> checked CanonicalContract + CapabilityPlan
  -> target semantic plan
  -> existing target renderer and artifact pipeline
```

## Input boundaries

- **Legacy v1** is the frozen `ProofForge.IR.Contract` compatibility input. Its
  adapter exists for migration and parity tests; it is not extended with new
  syntax.
- **Surface v2** is the independent authoring input for new portable features.
  It normalizes directly into the canonical contract.
- Both routes must produce the same checked canonical meaning for their shared
  fragment. Canonical parity gates enforce that contract.

`CanonicalContract` contains only semantic program data: types, logical state,
entrypoints, control flow, effects, host operations, and source-independent
identities. `CanonicalEvidence` contains diagnostics, origin spans, migration
provenance, and comparison traces. Evidence must not affect capability
selection, target plans, rendered artifacts, or artifact hashes.

## State ownership

The canonical layer owns **logical state**: named scalar, map, array, queue, and
set declarations and their operations. It never assigns EVM slots, Solana
account offsets, or Wasm linear-memory addresses. Each target semantic plan
owns that physical allocation and validates its target constraints before the
renderer runs. Renderers consume plans; they do not rediscover storage layout
from source syntax or canonical evidence.

## Public target routes

The canonical implementation reuses the existing target plans and renderers.
It does not expose parallel `*-core` target ids or skeleton artifacts.

| Public target id | Canonical materialization | Existing output pipeline |
|---|---|---|
| `evm` | `ProofForge.Backend.Evm.Plan.Core.buildFromCore` | EVM `ModulePlan` -> Yul -> `solc` |
| `solana-sbpf-asm` | `ProofForge.Backend.Solana.Plan.Core.buildFromCore` | `SolanaModulePlan` -> sBPF assembly -> ELF |
| `wasm-near` | `ProofForge.Backend.Wasm.NearModulePlan.Core.buildFromCore` | `NearModulePlan` -> Wasm AST/WAT -> Wasm |

Unsupported canonical operations fail before rendering. The public target id
always selects this route; there is no production fallback to Legacy lowering.

## Rollback window

For one release after canonical promotion, the frozen Legacy adapter and its
dual-run comparison helpers remain available to tests only. They may diagnose
a regression by comparing canonical meaning, plans, and artifacts, but the CLI,
registry, and product compiler cannot select Legacy as a fallback. At the end
of that release window the comparison-only code is removed or its retention is
approved explicitly with a new decision and deadline.

See [Backend interface](backend-interface.md) for target author obligations and
[Validation gates](validation-gates.md) for executable enforcement.
