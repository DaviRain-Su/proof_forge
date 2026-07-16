# Benchmarks

ProofForge vs native comparison corpus and runners.

**Spec:** [docs/benchmarks.md](../docs/benchmarks.md)
**Plan wave:** B1 in
[docs/superpowers/plans/2026-07-10-post-review-execution.md](../docs/superpowers/plans/2026-07-10-post-review-execution.md)

## Status

- **B1.0** layout + spec doc: done.
- **B1.1** result schema + checker: done (`schema/`, `just benchmark-schema`).
- **B1.2** native Counter corpus: done (`native/`, `just benchmark-native-counter`).
- **B1.3** PF Counter runner: done (`just benchmark-counter-pf`).
- **B1.4** native Counter runner: done (`just benchmark-counter-native`).
- **B1.5** behavior gate: done (`just benchmark-behavior-gate`).
- **B1.6** cost table: done (`just benchmark-cost-table` → `docs/generated/benchmark-counter.md`).
- **B1.7** expand scenarios: done (ValueVault + Ownable; `just benchmark-matrix`).
- **B1.8** ZK optional rows: done (`just benchmark-zk-counter`).

```sh
just benchmark-counter          # Counter PF + native
just benchmark-value-vault      # ValueVault PF + native
just benchmark-ownable          # Ownable PF + native
just benchmark-matrix           # triad scenarios + behavior gate + cost table
just benchmark-zk-counter       # experimental Psy/Aleo Counter rows
just benchmark-matrix-all       # matrix + ZK
```

## Schema

```sh
just benchmark-schema
# validates benchmarks/schema/fixtures/* via
# scripts/benchmarks/validate-result-schema.py
```

## Temporary seeds

Until the dedicated matrix exists, use:

```sh
just testkit
just product
```
