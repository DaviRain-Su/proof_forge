# Backend tests (compiler / adapter probes)

These tests validate **lowering, goldens, and host models**. They are **not**
the product author API.

```text
Product path:  Tests/Product/  +  just product
This path:     Tests/Backend/  +  just backend (or solana-light / emitwat-ci-smoke / …)
```

| Subtree | Contents |
|---------|----------|
| `Solana/` | sBPF, CPI packing, PDA, SDK manifest, diagnostics |
| `Wasm/` | EmitWat probes, Wasm host models, coverage TSV |
| `Evm/` | plan / semantic plan / diagnostics / coverage TSV |

Product multi-target materialize lives in `Tests/Product/Matrix.lean`.
Account auto-fill product asserts: `Tests/Product/Accounts.lean`.
