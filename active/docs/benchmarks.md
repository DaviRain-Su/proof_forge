# ProofForge vs Native Benchmark Matrix

Status: **Active (B1 wave core complete through B1.8)**
Plan: [post-review execution plan](superpowers/plans/2026-07-10-post-review-execution.md) wave **B1**

## Why

ProofForge claims one portable business path can lower to multiple chains.
Correctness gates (`just product`, testkit) are necessary but not sufficient:
we also need **behavior parity and native cost comparison** against hand-written
contracts on each chain.

This document is the SOT for that matrix. Results (when generated) live under
`build/benchmarks/` and may be snapshotted into `docs/generated/`.

## Non-goals

- A single cross-chain “score” that averages gas + CU + fuel + circuit ops.
- Using Anchor-heavy Solana programs as the “native efficient” baseline without
  labeling them (prefer Pinocchio-class / minimal sBPF for efficiency claims).
- Treating Psy/Aleo metrics as comparable to EVM gas.

## Implementations

| Tag | Meaning |
|-----|---------|
| `proofforge` | Artifact from `proof-forge` + target toolchain |
| `native` | Hand-written reference checked into `benchmarks/native/` (B1.2+) or pinned external source |

## Cost dimensions (native only)

| Target | Behavior oracle | Cost fields | Artifact size |
|--------|-----------------|-------------|---------------|
| `evm` | Foundry / revm / Anvil | `evm_gas` | runtime bytecode bytes |
| `solana-sbpf-asm` | Mollusk / Surfpool | `solana_cu` | ELF bytes |
| `wasm-near` | offline-host / sandbox | `wasmtime_fuel_*` and/or `near_gas` when real | Wasm bytes |
| `psy-dpn` (optional) | `dargo execute` | `dpn_definition_count`, `dpn_op_count`, execute wall time | DPN JSON bytes |
| `aleo-leo` (optional) | `leo` / snarkVM | constraint/proof metrics when available | `.aleo` / package bytes |

## Scenario set

| Id | PF source | Native references | Priority |
|----|-----------|-------------------|----------|
| `bm-counter` | `Examples/Product/Counter.lean` | Solidity / Pinocchio-or-Rust / near-sdk Counter | P0 first |
| `bm-value-vault` | `Examples/Product/ValueVault.lean` | hand-written triad vaults | P1 |
| `bm-ownable` | `Examples/Product/Ownable.lean` | OZ-style / Anchor-like / NEAR owner | P1 |
| `bm-ft-transfer` | Token / FT product path | ERC-20 / SPL / NEP-141 | P2 after N1 |
| `bm-remote-call` | `Examples/Product/RemoteCall.lean` | CALL / CPI / Promise peers | P2 |
| `bm-psy-counter` | IR Counter → psy-dpn | hand `.psy` Counter | Experimental |
| `bm-aleo-counter` | IR Counter → aleo | hand Leo Counter | Experimental |

## Result schema (B1.1)

Machine-readable SOT:

- JSON Schema draft: [`benchmarks/schema/result.schema.json`](../benchmarks/schema/result.schema.json)
- Pure-Python checker (no `jsonschema` dep):
  [`scripts/benchmarks/validate-result-schema.py`](../scripts/benchmarks/validate-result-schema.py)
- Fixtures + accept/reject smoke: `just benchmark-schema`

Each run emits one JSON object per (scenario, target, implementation):

```json
{
  "schema": "proof-forge.benchmark-result.v1",
  "schemaVersion": 1,
  "scenario": "bm-counter",
  "target": "evm",
  "implementation": "proofforge",
  "commit": "<git sha>",
  "toolVersions": {
    "proof-forge": "...",
    "solc": "...",
    "sbpf": "...",
    "dargo": "..."
  },
  "behavior": {
    "ok": true,
    "steps": [
      { "name": "initialize", "return": null },
      { "name": "increment", "return": null },
      { "name": "get", "return": "1" }
    ]
  },
  "costs": {
    "evm_gas": { "initialize": 0, "increment": 0, "get": 0 }
  },
  "artifactBytes": 0,
  "notes": ""
}
```

Validation rules (enforced by the checker):

1. `schema` is `proof-forge.benchmark-result.v1`; `schemaVersion` is `1`.
2. `implementation` is only `proofforge` or `native`.
3. `scenario` matches `^bm-[a-z0-9-]+$`; `target` is one of the triad + optional ZK ids.
4. `costs` keys must be from the target’s allowed cost dimensions
   (`evm_gas` / `solana_cu` / `wasmtime_fuel_*`+`near_gas` / Psy / Aleo fields).
5. Behavior steps for the same scenario must match across implementations on
   the **same** target before cost ratios are reported (B1.5 gate).
6. Missing tools → skip row with `behavior.ok = false` and non-empty honest
   `notes`; never fake zeros as success.

## Tolerances (initial)

- Behavior: exact match on returns / storage / events for the scenario script.
- Cost regression band (optional CI later): start at **±15%** vs the pinned
  native baseline for the same target; tighten after the corpus stabilizes.
- Solana native baseline policy: document whether native is Pinocchio-class or
  Anchor-class in the row `notes`.

## Layout

```text
benchmarks/
  README.md                 # points here
  schema/
    result.schema.json      # B1.1
    fixtures/               # accept/reject samples for just benchmark-schema
  native/                   # B1.2+ hand-written corpus
    evm/Counter.sol
    solana/counter/
    near/counter/
```

## Commands

```sh
just benchmark-schema           # B1.1 — schema fixtures accept/reject
just benchmark-native-counter   # B1.2 — native corpus compile/typecheck
just benchmark-counter-pf       # B1.3 — PF Counter rows
just benchmark-counter-native   # B1.4 — native Counter rows (EVM gas when Anvil present)
just benchmark-counter          # B1.3 + B1.4
just benchmark-behavior-gate    # B1.5 — PF vs native step parity
just benchmark-cost-table       # B1.6 — docs/generated/benchmark-counter.md
just benchmark-value-vault      # B1.7
just benchmark-ownable          # B1.7
just benchmark-matrix           # Counter + ValueVault + Ownable + gates
just benchmark-zk-counter       # B1.8 experimental Psy/Aleo Counter rows
just benchmark-matrix-all       # matrix + ZK + gates
# → build/benchmarks/bm-{counter,value-vault,ownable,psy-counter,aleo-counter}_*
```

Seeds still useful for budgets outside the matrix:

```sh
just testkit             # Counter/ValueVault budgets (not full native matrix)
just product             # multi-target compile matrix
```

## Wave checklist

| Task | Status |
|------|--------|
| B1.0 Spec + layout (this doc) | **done** |
| B1.1 Schema checker | **done** (`just benchmark-schema`) |
| B1.2 Native Counter corpus | **done** (`benchmarks/native/`, `just benchmark-native-counter`) |
| B1.3 PF Counter runner | **done** (`just benchmark-counter` / `benchmark-counter-pf`) |
| B1.4 Native Counter runner | **done** (`just benchmark-counter-native`; EVM gas via Anvil/cast) |
| B1.5 Behavior gate | **done** (`just benchmark-behavior-gate`; step name/return parity) |
| B1.6 Cost table snapshot | **done** (`just benchmark-cost-table` → `docs/generated/benchmark-counter.md`) |
| B1.7 Expand scenarios | **done** (ValueVault + Ownable; `just benchmark-matrix`) |
| B1.8 ZK optional rows | **done** (`just benchmark-zk-counter`; dargo/leo tool-gated) |

## Related

- [shared-scenario.md](shared-scenario.md) — Counter/ValueVault budgets
- [validation-gates.md](validation-gates.md) — runnable gates
- [targets/psy-dpn.md](targets/psy-dpn.md) — DPN bytecode lower boundary
- [targets/aleo-leo.md](targets/aleo-leo.md) — Aleo Instructions path
