# Product tests

Multi-target gates on **`Examples/Product`** sources (business logic only).

| File | Role |
|------|------|
| `Matrix.lean` | All Product modules × EVM · Solana · NEAR · Soroban (+ Token honesty) |
| `Accounts.lean` | Solana account auto-fill for auth / remote / nativeValue |
| `SolanaMaterialize.lean` | Portable IR → Solana accounts without Source.Solana |

```bash
just product
just product-matrix
```

Backend compiler probes: `../Backend/`.
