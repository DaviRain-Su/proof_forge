# NEAR compare matrix — snapshot

**Date:** 2026-07-10  
**Gate:** dual-deploy `semanticMatch: true` on NEAR Sandbox  
**Formula:** ratio = near-sdk / ProofForge (higher ⇒ PF smaller / cheaper)

## Coverage

| Surface | Count | Notes |
|---------|------:|-------|
| Live dual-deploy (this matrix) | **21** | Product (+ 2 Backend FT/FeeToken bodies) |
| Product `contract_source` / stdlib facades on NEAR | most | See blocked below |
| Not comparable yet | 2 | SoulboundToken (TokenSpec), ERC4626Vault (stdlib olean gap) |

## Full leaderboard (wasm size ratio, live)

| Rank | Contract | PF wasm | sdk wasm | **wasm×** | call× | storage× | Kind |
|-----:|----------|--------:|---------:|----------:|------:|---------:|------|
| 1 | Ownable | 627 B | 161 KB | **~256×** | ~1.13× | ~187× | access |
| 2 | StorageDeposit | 895 B | 176 KB | **~196×** | ~1.18× | ~142× | NEP-145-lite |
| 3 | AccessControl | 1055 B | 186 KB | **~177×** | ~1.26× | ~134× | roles |
| 4 | AuthRemoteCall | ~1.1 KB | 174 KB | **~159×** | ~1.11× | ~131× | promise+debit |
| 5 | RemoteCall | ~900 B | ~167 KB | **~186×**† | ~1.13× | ~148× | promise |
| 6 | ExternalVault | 1272 B | 176 KB | **~138×** | ~1.13× | ~117× | peer client |
| 7 | ReentrancyGuard | 401 B | 54 KB | **~135×** | ~1.08× | ~86× | mixin |
| 8 | ArrayExample | 374 B | 49 KB | **~131×** | views | ~89× | pure compute |
| 9 | Pausable | 415 B | 54 KB | **~131×** | ~1.05× | ~84× | mixin |
| 10 | StatusMessage | 1428 B | 179 KB | **~126×** | ~1.25× | ~104× | map |
| 11 | GuestBook | 1647 B | 196 KB | **~119×** | ~1.16× | ~92× | maps |
| 12 | OwnableHash | 656 B | 75 KB | **~115×** | ~1.06× | ~83× | hash owner |
| 13 | ExternalTokenTransfer | 1629 B | 180 KB | **~111×** | ~1.13× | ~97× | NEP-141 client |
| 14 | OwnablePausable | 773 B | 76 KB | **~98×** | ~1.06× | ~75× | compose |
| 15 | FeeToken | 2006 B | 187 KB | **~93×** | ~1.13× | ~79× | FT+fee |
| 16 | StakingVault | 1924 B | 182 KB | **~94×**† | ~1.13× | ~82× | deposit map |
| 17 | RoleGatedToken | 2373 B | 209 KB | **~88×** | ~1.20× | ~72× | nested maps |
| 18 | HostEnvProbe | 893 B | 75 KB | **~84×** | ~1.11× | ~65× | host env |
| 19 | ValueVault | 2053 B | 156 KB | **~76×** | ~1.16× | ~67× | multi-scalar |
| 20 | Counter | ~400 B | ~55 KB | **~135×**† | ~1.07× | — | baseline |
| 21 | FungibleToken | 3860 B | 185 KB | **~48×** | ~1.10× | ~42× | NEP-141 body |

† Some baseline rows from earlier README snapshots if local `sandbox-report.json` was cleaned.

### Takeaways

1. **Code size:** PF is consistently **~50–250×** smaller wasm than near-sdk-rs references (framework runtime).
2. **Call gas:** ratios cluster **~1.05–1.26×** — storage host ops dominate; size wins do not fully translate to call gas.
3. **Deploy gas / storage:** track wasm size more closely (**~7–21×** deploy, **~40–190×** storage).
4. **Smallest PF binaries:** ArrayExample (374 B), ReentrancyGuard (401 B), Pausable (415 B), Counter (~400 B).
5. **Largest PF binaries:** FungibleToken (~3.9 KB), RoleGatedToken (~2.4 KB), ValueVault (~2.1 KB) — still far under sdk.
6. **Peer clients** (ExternalTokenTransfer / ExternalVault / AuthRemoteCall / RemoteCall) still show **~110–160×** wasm wins while exercising promise paths.

## Product scan (what is / is not in the matrix)

| Product | Matrix? | Reason |
|---------|:-------:|--------|
| Counter, ValueVault, Ownable, … (21) | ✅ | dual-deploy live |
| FungibleToken / FeeToken | ✅ | via Backend/WasmNear bodies |
| ExternalTokenTransfer | ✅ | NEP-141 peer client + mock FT |
| ExternalVault | ✅ | vault peer client + mock vault |
| AuthRemoteCall | ✅ | debit + promise receive |
| AccessControl | ✅ | `.address` → U64 on NEAR |
| **SoulboundToken** | ❌ | TokenSpec only; no `ContractSpec` for EmitWat |
| **ERC4626Vault** | ❌ | stdlib ERC4626 olean/build gap on this branch |

## Honesty reminders

- PF = raw/Borsh LE args; near-sdk = JSON (except raw LE promise bodies where noted).
- Status/GuestBook use **U64 codes**, not UTF-8 strings.
- StorageDeposit is NEP-145-**lite** (U64 balances).
- ReentrancyGuard is a **lock bit**, not EVM call-stack theory.
- External peers use mocks; not mainnet NEP-141/4626 compliance.

## Commands

```sh
just near-compare-all-live
# reports: build/testkit/compare/near/<contract>/sandbox-report.json
```
