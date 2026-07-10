# Testkit compare benchmarks

**One place** for native-vs-ProofForge contract comparison.

```text
testkit/compare/
  src/main.rs
  near/
    counter/          # near-sdk Counter reference
    value-vault/      # near-sdk ValueVault reference
    sandbox/          # NEAR Sandbox dual-deploy (near-workspaces)
```

## Run

```sh
# Counter — offline
just near-compare

# Counter — offline + Sandbox dual-deploy (real deploy/call gas + storage)
just near-compare-live

# ValueVault — offline / live
just near-compare-value-vault
just near-compare-value-vault-live

# Both live
just near-compare-all-live
```

Reports under `build/testkit/compare/near/<contract>/`:

| File | Contents |
|------|----------|
| `report.json` | Offline size/fuel + optional sandbox summary |
| `sandbox-report.json` | Dual-deploy: wasm / deploy gas / call gas / storage_usage |

## What the numbers mean

| Metric | What it shows |
|--------|----------------|
| **wasmBytes** | Code size (framework-free vs near-sdk runtime) |
| **deployGasBurnt** | Real sandbox gas for `DeployContract` — **tracks size** |
| **storageUsageBytes** | Account storage after deploy+scenario (code + state) — **tracks size** |
| **callGasBurnt** | Function-call receipts only — often **storage-dominated**, may not track size |

### Snapshot (local Sandbox, 2026-07-10)

| Contract | Metric | ProofForge | near-sdk | sdk/pf |
|----------|--------|------------|----------|--------|
| Counter | wasm | 439 B | 54,695 B | **~125×** |
| Counter | deploy gas | ~6.2e11 | ~4.5e12 | **~7.3×** |
| Counter | storage | 674 B | 54,930 B | **~81×** |
| Counter | call gas | ~2.6e12 | ~2.8e12 | ~1.07× |
| ValueVault | wasm | **2,197 B** | 156,142 B | **~71×** |
| ValueVault | deploy gas | ~7.4e11 | ~1.2e13 | **~15.8×** |
| ValueVault | storage | 2,721 B | 156,417 B | **~57×** |
| ValueVault | call gas | ~3.34e12 | ~3.13e12 | ~0.94×* |

\*ValueVault call gas is within ~6% after fair event logs on both sides. Remaining
gap is mostly **per-field storage keys** (PF writes 6 scalar slots) vs near-sdk
single Borsh state blob — not event-assembly putc cost. Event JSON assembly was
optimized to static `putstr` punctuation (same log bytes, smaller guest code).

## Contracts

| Example | Command | ProofForge source |
|---------|---------|-------------------|
| `counter` | `just near-compare-live` | `Examples/Product/Counter.lean` |
| `value-vault` | `just near-compare-value-vault-live` | `Examples/Product/ValueVault.lean` |

Next candidates: NEP-141 FT, StatusMessage.
