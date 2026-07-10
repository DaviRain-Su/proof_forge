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
    role-gated-token/ # nested-map role gate
    fee-token/        # fee-on-transfer FT body
    remote-call/      # promise_create + callee
    status-message/   # per-account status (u64 codes)
    guestbook/        # append/index message board (u64 codes)
    storage-deposit/  # NEP-145-lite storage_deposit
    pausable/         # emergency-stop mixin
    reentrancy-guard/ # lock-bit mixin
    ownable-pausable/ # owner-gated pause
    sandbox/          # NEAR Sandbox dual-deploy (near-workspaces)
      src/
        main.rs       # CLI + dispatch
        kind.rs       # ContractKind
        report.rs     # SideReport / write_dual_report
        host.rs       # deploy/call/view + SideCtx
        scenarios/    # one module per contract + run_side registry
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

# RoleGatedToken
just near-compare-role-gated-token
just near-compare-role-gated-token-live

# FeeToken (fee-on-transfer body)
just near-compare-fee-token
just near-compare-fee-token-live

# RemoteCall (promise_create cross-contract)
just near-compare-remote-call
just near-compare-remote-call-live

# StatusMessage (u64 status codes; string KV still open)
just near-compare-status-message
just near-compare-status-message-live

# GuestBook (u64 message codes; string KV still open)
just near-compare-guestbook
just near-compare-guestbook-live

# NEP-145-lite storage_deposit
just near-compare-storage-deposit
just near-compare-storage-deposit-live

# Pausable / ReentrancyGuard / OwnablePausable mixins
just near-compare-pausable
just near-compare-pausable-live
just near-compare-reentrancy-guard
just near-compare-reentrancy-guard-live
just near-compare-ownable-pausable
just near-compare-ownable-pausable-live

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
| RoleGatedToken | wasm | **2373 B** | 208887 B | **~88.0×** |
| RoleGatedToken | deploy gas | 7.55e11 | 1.55e13 | **~20.5×** |
| RoleGatedToken | call gas | 6.30e12 | 7.54e12 | **~1.20×** |
| RoleGatedToken | storage | 2898 B | 209520 B | **~72.3×** |
| FeeToken | wasm | **2006 B** | 187292 B | **~93.4×** |
| FeeToken | deploy gas | 7.29e11 | 1.40e13 | **~19.1×** |
| FeeToken | call gas | 4.72e12 | 5.32e12 | **~1.13×** |
| FeeToken | storage | 2379 B | 187732 B | **~78.9×** |
| RemoteCall | wasm | **~900 B** | ~167 KB | **~186×** |
| RemoteCall | deploy gas | 6.50e11 | 1.25e13 | **~19.3×** |
| RemoteCall | call gas | 4.14e12 | 4.67e12 | **~1.13×** |
| RemoteCall | storage | 1135 B | 167688 B | **~148×** |
| StatusMessage | wasm | **1428 B** | 179296 B | **~125.6×** |
| StatusMessage | deploy gas | 6.88e11 | 1.34e13 | **~19.5×** |
| StatusMessage | call gas | 4.09e12 | 5.10e12 | **~1.25×** |
| StatusMessage | storage | 1729 B | 179624 B | **~103.9×** |
| GuestBook | wasm | **1647 B** | 196089 B | **~119.1×** |
| GuestBook | deploy gas | 7.03e11 | 1.46e13 | **~20.7×** |
| GuestBook | call gas | 4.69e12 | 5.45e12 | **~1.16×** |
| GuestBook | storage | 2147 B | 196640 B | **~91.6×** |
| StorageDeposit | wasm | **895 B** | 175626 B | **~196.2×** |
| StorageDeposit | deploy gas | 6.50e11 | 1.31e13 | **~20.2×** |
| StorageDeposit | call gas | 2.75e12 | 3.25e12 | **~1.18×** |
| StorageDeposit | storage | 1236 B | 175962 B | **~142.4×** |
| Pausable | wasm | **415 B** | 54216 B | **~130.6×** |
| Pausable | deploy gas | 6.15e11 | 4.46e12 | **~7.2×** |
| Pausable | call gas | 2.68e12 | 2.81e12 | **~1.05×** |
| Pausable | storage | 651 B | 54451 B | **~83.6×** |
| ReentrancyGuard | wasm | **401 B** | 54145 B | **~135.0×** |
| ReentrancyGuard | deploy gas | 6.14e11 | 4.45e12 | **~7.2×** |
| ReentrancyGuard | call gas | 2.61e12 | 2.81e12 | **~1.08×** |
| ReentrancyGuard | storage | 635 B | 54380 B | **~85.6×** |
| OwnablePausable | wasm | **773 B** | 76105 B | **~98.5×** |
| OwnablePausable | deploy gas | 6.41e11 | 6.02e12 | **~9.4×** |
| OwnablePausable | call gas | 4.11e12 | 4.36e12 | **~1.06×** |
| OwnablePausable | storage | 1016 B | 76387 B | **~75.2×** |

Fairness notes:

- Same scenario steps on both sides; PF uses Borsh/raw, near-sdk uses JSON.
- Events kept on both sides (names aligned; account encoding may differ: hash hex vs AccountId).
- FT body is `Stdlib.NearFungibleToken` via `Examples/Backend/WasmNear/FungibleToken.lean`
  (Product `FungibleToken.lean` is TokenSpec intent).
- Live host fix: `attached_deposit` matches near-sys `(balance_ptr)` u128 write (needed for StakingVault).
- StatusMessage / GuestBook store **U64 codes** (not free-form UTF-8 strings) until EmitWat
  string KV lands; control flow + map storage match the classic tutorials.
- StorageDeposit is **NEP-145-lite** (U64 cumulative deposits + min bounds), not full
  JSON `StorageBalance` / withdraw / refund.
- Pausable / ReentrancyGuard use sdk `Default` state (no init) to match PF mixin surface.
- ReentrancyGuard is a **lock bit**, not EVM call-stack reentrancy theory.

## Contracts

| Example | Command | ProofForge source |
|---------|---------|-------------------|
| `counter` | `just near-compare-live` | `Examples/Product/Counter.lean` |
| `value-vault` | `just near-compare-value-vault-live` | `Examples/Product/ValueVault.lean` |
| `fungible-token` | `just near-compare-fungible-token-live` | `Examples/Backend/WasmNear/FungibleToken.lean` |
| `ownable` | `just near-compare-ownable-live` | `Examples/Product/Ownable.lean` |
| `staking-vault` | `just near-compare-staking-vault-live` | `Examples/Product/StakingVault.lean` |
| `role-gated-token` | `just near-compare-role-gated-token-live` | `Examples/Product/RoleGatedToken.lean` |
| `fee-token` | `just near-compare-fee-token-live` | `Examples/Backend/WasmNear/FeeToken.lean` |
| `remote-call` | `just near-compare-remote-call-live` | `Examples/Product/RemoteCall.lean` |
| `status-message` | `just near-compare-status-message-live` | `Examples/Product/StatusMessage.lean` |
| `guestbook` | `just near-compare-guestbook-live` | `Examples/Product/GuestBook.lean` |
| `storage-deposit` | `just near-compare-storage-deposit-live` | `Examples/Product/StorageDeposit.lean` |
| `pausable` | `just near-compare-pausable-live` | `Examples/Product/Pausable.lean` |
| `reentrancy-guard` | `just near-compare-reentrancy-guard-live` | `Examples/Product/ReentrancyGuard.lean` |
| `ownable-pausable` | `just near-compare-ownable-pausable-live` | `Examples/Product/OwnablePausable.lean` |

Expansion charter: `testkit/compare/GOAL.md`.
