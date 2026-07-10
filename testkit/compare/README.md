# Testkit compare benchmarks

**One place** for native-vs-ProofForge contract comparison.

```text
testkit/compare/
  GOAL.md             # durable multi-contract expansion goal
  src/main.rs
  near/
    counter/          # near-sdk Counter reference
    value-vault/      # near-sdk ValueVault reference
    fungible-token/   # NEP-141-minimal FT reference
    ownable/          # Ownable reference
    staking-vault/    # StakingVault reference
    sandbox/          # NEAR Sandbox dual-deploy (near-workspaces)
```

## Run

```sh
# Counter
just near-compare
just near-compare-live

# ValueVault
just near-compare-value-vault
just near-compare-value-vault-live

# FungibleToken (NEP-141 minimal)
just near-compare-fungible-token
just near-compare-fungible-token-live

# Ownable
just near-compare-ownable
just near-compare-ownable-live

# StakingVault
just near-compare-staking-vault
just near-compare-staking-vault-live

# All live dual-deploys
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

## Snapshot (local Sandbox, 2026-07-10)

| Contract | Metric | ProofForge | near-sdk | sdk/pf |
|----------|--------|------------|----------|--------|
| Counter | wasm | ~400 B | ~55 KB | **~135×** |
| Counter | call gas | ~2.6e12 | ~2.8e12 | **~1.07×** |
| ValueVault | wasm | ~2 KB | ~156 KB | **~75×** |
| ValueVault | call gas | ~2.7e12 | ~3.1e12 | **~1.15×** |
| FungibleToken | wasm | **3860 B** | 185022 B | **~47.9×** |
| FungibleToken | deploy gas | 8.61e11 | 1.38e13 | **~16.0×** |
| FungibleToken | call gas | 4.79e12 | 5.29e12 | **~1.10×** |
| FungibleToken | storage | 4398 B | 185454 B | **~42.2×** |
| Ownable | wasm | **627 B** | 160515 B | **~256×** |
| Ownable | deploy gas | 6.30e11 | 1.20e13 | **~19.1×** |
| Ownable | call gas | 2.74e12 | 3.09e12 | **~1.13×** |
| Ownable | storage | 862 B | 160789 B | **~187×** |
| StakingVault | wasm | **1924 B** | 181709 B | **~94.4×** |
| StakingVault | deploy gas | 7.23e11 | 1.36e13 | **~18.8×** |
| StakingVault | call gas | 4.53e12 | 5.10e12 | **~1.13×** |
| StakingVault | storage | 2230 B | 182053 B | **~81.6×** |

Fairness notes:

- Same scenario steps on both sides; PF uses Borsh/raw, near-sdk uses JSON.
- Events kept on both sides (names aligned; account encoding may differ: hash hex vs AccountId).
- FT body is `Stdlib.NearFungibleToken` via `Examples/Backend/WasmNear/FungibleToken.lean`
  (Product `FungibleToken.lean` is TokenSpec intent).
- Live host fix: `attached_deposit` matches near-sys `(balance_ptr)` u128 write (needed for StakingVault).

## Contracts

| Example | Command | ProofForge source |
|---------|---------|-------------------|
| `counter` | `just near-compare-live` | `Examples/Product/Counter.lean` |
| `value-vault` | `just near-compare-value-vault-live` | `Examples/Product/ValueVault.lean` |
| `fungible-token` | `just near-compare-fungible-token-live` | `Examples/Backend/WasmNear/FungibleToken.lean` |
| `ownable` | `just near-compare-ownable-live` | `Examples/Product/Ownable.lean` |
| `staking-vault` | `just near-compare-staking-vault-live` | `Examples/Product/StakingVault.lean` |

Expansion charter: `testkit/compare/GOAL.md`.
