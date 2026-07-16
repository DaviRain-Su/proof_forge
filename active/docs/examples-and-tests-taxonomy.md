# Examples & Tests taxonomy (Product vs Backend)

Status: **Normative (2026-07-09)**  
Related: [product-authoring-architecture](product-authoring-architecture.md),
[authoring-model](authoring-model.md).

## Product thesis

```text
Author writes:  business logic only
Author chooses: --target <id>
Platform does:  chain materialization (ABI, accounts, CPI, host, token standard)
```

## Directory roles

| Path | Role | Who cares |
|------|------|-----------|
| **`Examples/Product/`** | Portable business contracts + TokenSpec intents | Application authors, product CI |
| **`Examples/Backend/`** | Chain probes, goldens, Source.Solana/NEAR fixtures, research spikes | Compiler / backend engineers |
| **`Tests/Product/`** | Multi-target materialize matrix on Product sources | Primary product gate (`just product`) |
| **`Tests/Backend/`** | Solana / EmitWat / Wasm host / Evm plan probes | Backend depth (`just backend`, `solana-light`, …) |
| **`Tests/*` (IR/Cli/Sdk)** | Compiler internals, formal, CLI | Engineering CI |
| **`ProofForge/IR/Examples/`** | IR fixtures for semantics (not author tutorials) | Formal / IR tests |

## Hard rules

1. **Product** sources import only `ProofForge.Contract.Source` or
   `ProofForge.Contract.Token` (plus stdlib mixins composed as business policy).
2. **Product** never requires `Source.Solana`, selectors, CREATE2, or Promise APIs
   (`just portable-default` / product-default enforces this).
3. **Backend** may use chain Surfaces and golden diffs; they are **not** the
   product API and must not lead tutorials.
4. One business source per contract name. Chain directories hold **artifacts**
   (goldens/manifests), not forked business logic.

## Primary command

```bash
just product
```

Runs:

1. `portable-default` (Product sources stay business-only)
2. `product-matrix` — `Tests/Product/Matrix.lean` (every Product module × EVM · Solana · NEAR · Soroban; TokenSpec honesty)
3. Multi-target CLI smokes (Counter, RemoteCall)

Backend probes: `just backend` (solana-lean subset) or `solana-light` / `emitwat-ci-smoke`.

Full engineering suite remains `just check` (product + backend + formal).

## CI (Phase 5)

| Host | Product-first | Full suite |
|------|---------------|------------|
| GitHub Actions | job **`product`** (required) | job **`build-test`** with `needs: [product]` |
| Codeberg Woodpecker | step **`proof-forge-product`** (`just product`) | step **`proof-forge-check`** (`just check`) |

Authoring / portable regressions fail in `product` before backend probe suites run.

## Single Counter author source (Phase 2)

| Module | Role |
|--------|------|
| `Examples/Product/Counter.lean` | **Author source** (name-only entrypoints) |
| `ProofForge.Contract.Examples.Counter` | Spec alias → Product |
| `ProofForge.IR.Examples.Counter` | IR fixture: same **shape**; may pin selectors / wrapping add for formal+CLI |
| `Examples/Backend/*/Counter` | Thin wrappers / goldens only |

Shape parity is enforced in `Tests/Product/Matrix.lean`.

## Migration note

Formerly `Examples/Shared` is `Examples/Product`. Chain trees under
`Examples/{Evm,Solana,…}` live under `Examples/Backend/`.
