# NEAR compare matrix — full snapshot

**Date:** 2026-07-10  
**Live dual-deploy contracts:** **23**  
**Ratio:** near-sdk ÷ ProofForge

## Product scan

| Product | Matrix | Notes |
|---------|:------:|-------|
| Counter | ✅ | |
| ValueVault | ✅ | |
| FungibleToken | ✅ | |
| Ownable | ✅ | |
| StakingVault | ✅ | |
| RoleGatedToken | ✅ | |
| FeeToken | ✅ | |
| RemoteCall | ✅ | |
| StatusMessage | ✅ | |
| GuestBook | ✅ | |
| StorageDeposit | ✅ | |
| Pausable | ✅ | |
| ReentrancyGuard | ✅ | |
| OwnablePausable | ✅ | |
| ArrayExample | ✅ | |
| OwnableHash | ✅ | |
| HostEnvProbe | ✅ | |
| AuthRemoteCall | ✅ | |
| AccessControl | ✅ | |
| ExternalTokenTransfer | ✅ | |
| ExternalVault | ✅ | |
| ProRataVault | ✅ Wave 8 | |
| SoulboundTokenBody | ✅ Wave 8 | |
| SoulboundToken TokenSpec | ❌ plan-only | |
| ERC4626Vault stdlib | ❌ NEAR asset crosscall | |

## Leaderboard (wasm×)

| Rank | Contract | PF wasm | sdk wasm | **wasm×** | call× | storage× | Kind |
|-----:|----------|--------:|---------:|----------:|------:|---------:|------|
| 1 | ownable | 627 | 160515 | **~256.0×** | 1.13× | 186.5× | access |
| 2 | storage-deposit | 895 | 175626 | **~196.2×** | 1.18× | 142.4× | NEP-145-lite |
| 3 | remote-call | 899 | 167406 | **~186.2×** | 1.13× | 147.7× | promise |
| 4 | access-control | 1055 | 186321 | **~176.6×** | 1.26× | 134.4× | roles |
| 5 | auth-remote-call | 1093 | 173940 | **~159.1×** | 1.11× | 131.0× | promise+debit |
| 6 | external-vault | 1272 | 176107 | **~138.4×** | 1.13× | 116.6× | vault client |
| 7 | counter | 403 | 54695 | **~135.7×** | 1.07× | 86.1× | baseline |
| 8 | reentrancy-guard | 401 | 54145 | **~135.0×** | 1.08× | 85.6× | mixin |
| 9 | array-example | 374 | 49041 | **~131.1×** | —× | 88.5× | pure |
| 10 | pausable | 415 | 54216 | **~130.6×** | 1.05× | 83.6× | mixin |
| 11 | status-message | 1428 | 179296 | **~125.6×** | 1.25× | 103.9× | map U64 |
| 12 | guestbook | 1647 | 196089 | **~119.1×** | 1.16× | 91.6× | maps U64 |
| 13 | ownable-hash | 656 | 75445 | **~115.0×** | 1.06× | 82.7× | hash owner |
| 14 | external-token-transfer | 1629 | 180222 | **~110.6×** | 1.13× | 96.5× | NEP-141 client |
| 15 | soulbound-token | 1734 | 191050 | **~110.2×** | 1.12× | 93.8× | non-transferable |
| 16 | ownable-pausable | 773 | 76105 | **~98.5×** | 1.06× | 75.2× | compose |
| 17 | staking-vault | 1924 | 181709 | **~94.4×** | 1.13× | 81.6× | deposit map |
| 18 | fee-token | 2006 | 187292 | **~93.4×** | 1.12× | 78.9× | FT+fee |
| 19 | role-gated-token | 2373 | 208887 | **~88.0×** | 1.20× | 72.3× | nested roles |
| 20 | host-env-probe | 893 | 74718 | **~83.7×** | 1.11× | 65.1× | host env |
| 21 | pro-rata-vault | 2412 | 198473 | **~82.3×** | 1.13× | 72.7× | share vault |
| 22 | value-vault | 2053 | 156142 | **~76.1×** | 1.16× | 67.2× | state |
| 23 | fungible-token | 3860 | 185022 | **~47.9×** | 1.10× | 42.2× | NEP-141 body |

### Stats

| Stat | wasm× | call× |
|------|------:|------:|
| min | 47.9× | 1.05× |
| **median** | **119.1×** | **1.13×** |
| mean | 125.6× | 1.13× |
| max | 256.0× | 1.26× |

### Takeaways

1. PF wasm advantage **~48–256×** vs near-sdk across 23 contracts.
2. Call gas band **~1.05–1.26×** (storage host ops dominate).
3. **ProRataVault** (~82×): ERC-4626-like pro-rata shares **without** IERC20 pulls.
4. **SoulboundTokenBody** (~110×): mint/burn, **no transfer**.
5. Full stdlib ERC4626 still blocked on NEAR (`nearCrosscallStrings` for asset peer).

```sh
just near-compare-all-live
```
