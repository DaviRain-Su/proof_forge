# Test Timing Baseline

Commit: `2b52b346`

| Metric | Result |
|---|---:|
| Serial warm-cache wall time | 1297.26s |
| Parallel mean wall time | 760.89s |
| Improvement | 41.35% |
| Stable parallel runs | 3 |
| Default-cutover qualification | PASS |

## Parallel Runs

| Run | Jobs | Wall time |
|---:|---:|---:|
| 1 | 4 | 703.38s |
| 2 | 4 | 862.21s |
| 3 | 4 | 717.09s |

## Lane Work

| Lane | Latest cumulative work |
|---|---:|
| `core-product` | 526.63s |
| `evm` | 465.45s |
| `solana` | 325.25s |
| `wasm-other-exclusive` | 402.26s |

## Slowest Recipes

| Recipe | Time |
|---|---:|
| `rebuild-hash` | 384.24s |
| `quint-mbt-gate` | 183.64s |
| `testkit` | 160.94s |
| `solana-light` | 141.75s |
| `registry-command` | 88.21s |
| `product` | 69.71s |
| `source-identity` | 62.60s |
| `near-target-first` | 42.50s |
| `canonical-parity` | 36.03s |
| `check-l2-parity` | 35.19s |
