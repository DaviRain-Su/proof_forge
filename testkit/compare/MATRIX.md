# NEAR compare matrix — full snapshot

**Date:** 2026-07-10  
**Contracts with live Sandbox reports:** **21**  
**Ratio:** near-sdk ÷ ProofForge (higher ⇒ PF smaller / cheaper)

## Coverage status

| Bucket | Count | Status |
|--------|------:|--------|
| Live dual-deploy | **21** | Product NEAR-comparable set complete |
| Product remaining | **2 blocked** | SoulboundToken, ERC4626Vault |
| Backend bodies | 2 | FungibleToken, FeeToken |

### Product scan (final)

| Product | Matrix | Notes |
|---------|:------:|-------|
| Counter | ✅ | live dual-deploy |
| ValueVault | ✅ | live dual-deploy |
| FungibleToken | ✅ | live dual-deploy |
| Ownable | ✅ | live dual-deploy |
| StakingVault | ✅ | live dual-deploy |
| RoleGatedToken | ✅ | live dual-deploy |
| FeeToken | ✅ | live dual-deploy |
| RemoteCall | ✅ | live dual-deploy |
| StatusMessage | ✅ | live dual-deploy |
| GuestBook | ✅ | live dual-deploy |
| StorageDeposit | ✅ | live dual-deploy |
| Pausable | ✅ | live dual-deploy |
| ReentrancyGuard | ✅ | live dual-deploy |
| OwnablePausable | ✅ | live dual-deploy |
| ArrayExample | ✅ | live dual-deploy |
| OwnableHash | ✅ | live dual-deploy |
| HostEnvProbe | ✅ | live dual-deploy |
| AuthRemoteCall | ✅ | live dual-deploy |
| AccessControl | ✅ | live dual-deploy |
| ExternalTokenTransfer | ✅ | live dual-deploy |
| ExternalVault | ✅ | live dual-deploy |
| SoulboundToken | ❌ | TokenSpec only — no EmitWat ContractSpec |
| ERC4626Vault | ❌ | EmitWat: `nearCrosscallStrings` empty |

## Full leaderboard (wasm× descending)

| Rank | Contract | PF wasm | sdk wasm | **wasm×** | call× | storage× | Kind |
|-----:|----------|--------:|---------:|----------:|------:|---------:|------|
| 1 | ownable | 627 | 160,515 | **~256.0×** | 1.1× | 186.5× | access |
| 2 | storage-deposit | 895 | 175,626 | **~196.2×** | 1.2× | 142.4× | NEP-145-lite |
| 3 | remote-call | 899 | 167,406 | **~186.2×** | 1.1× | 147.7× | promise |
| 4 | access-control | 1055 | 186,321 | **~176.6×** | 1.3× | 134.4× | roles |
| 5 | auth-remote-call | 1093 | 173,940 | **~159.1×** | 1.1× | 131.0× | promise+debit |
| 6 | external-vault | 1272 | 176,107 | **~138.4×** | 1.1× | 116.6× | vault client |
| 7 | counter | 403 | 54,695 | **~135.7×** | 1.1× | 86.1× | baseline |
| 8 | reentrancy-guard | 401 | 54,145 | **~135.0×** | 1.1× | 85.6× | mixin |
| 9 | array-example | 374 | 49,041 | **~131.1×** | —× | 88.5× | pure |
| 10 | pausable | 415 | 54,216 | **~130.6×** | 1.1× | 83.6× | mixin |
| 11 | status-message | 1428 | 179,296 | **~125.6×** | 1.2× | 103.9× | map U64 |
| 12 | guestbook | 1647 | 196,089 | **~119.1×** | 1.2× | 91.6× | maps U64 |
| 13 | ownable-hash | 656 | 75,445 | **~115.0×** | 1.1× | 82.7× | hash owner |
| 14 | external-token-transfer | 1629 | 180,222 | **~110.6×** | 1.1× | 96.5× | NEP-141 client |
| 15 | ownable-pausable | 773 | 76,105 | **~98.5×** | 1.1× | 75.2× | compose |
| 16 | staking-vault | 1924 | 181,709 | **~94.4×** | 1.1× | 81.6× | deposit map |
| 17 | fee-token | 2006 | 187,292 | **~93.4×** | 1.1× | 78.9× | FT+fee |
| 18 | role-gated-token | 2373 | 208,887 | **~88.0×** | 1.2× | 72.3× | nested roles |
| 19 | host-env-probe | 893 | 74,718 | **~83.7×** | 1.1× | 65.1× | host env |
| 20 | value-vault | 2053 | 156,142 | **~76.1×** | 1.2× | 67.2× | state |
| 21 | fungible-token | 3860 | 185,022 | **~47.9×** | 1.1× | 42.2× | NEP-141 body |

### Distribution

| Stat | wasm× | call× |
|------|------:|------:|
| min | 47.9× | 1.05× |
| **median** | **125.6×** | **1.13×** |
| mean | 128.4× | 1.13× |
| max | 256.0× | 1.26× |

### Comparison takeaways

1. **Wasm:** PF is **~48–256×** smaller than near-sdk-rs (no framework runtime).
2. **Call gas:** narrow band **~1.05–1.26×** (storage host ops dominate).
3. **Storage:** large PF wins (**~42–187×**), tracks code size more than call gas.
4. **Smallest PF:** ArrayExample 374 B · Reentrancy 401 B · Counter 403 B · Pausable 415 B.
5. **Largest PF body:** FungibleToken 3860 B is still **~48×** under sdk ~185 KB.
6. **Promise / peer clients** (Remote, Auth, ExtFT, ExtVault): **~111–186×** wasm, call ~1.1×.
7. **Access family:** Ownable **~256×** (best), AccessControl **~177×**, OwnableHash **~115×**.

### By kind (median wasm×)

- **access**: median **256×** (n=1)
- **NEP-145-lite**: median **196×** (n=1)
- **promise**: median **186×** (n=1)
- **roles**: median **177×** (n=1)
- **promise+debit**: median **159×** (n=1)
- **vault client**: median **138×** (n=1)
- **baseline**: median **136×** (n=1)
- **mixin**: median **133×** (n=2)
- **pure**: median **131×** (n=1)
- **map U64**: median **126×** (n=1)
- **maps U64**: median **119×** (n=1)
- **hash owner**: median **115×** (n=1)
- **NEP-141 client**: median **111×** (n=1)
- **compose**: median **98×** (n=1)
- **deposit map**: median **94×** (n=1)
- **FT+fee**: median **93×** (n=1)
- **nested roles**: median **88×** (n=1)
- **host env**: median **84×** (n=1)
- **state**: median **76×** (n=1)
- **NEP-141 body**: median **48×** (n=1)

## Blocked next

| Item | Blocker | Unblock |
|------|---------|--------|
| SoulboundToken | TokenSpec only | portable non-transferable body + EmitWat |
| ERC4626Vault | `nearCrosscallStrings` empty | asset/peer binding for vault body on NEAR |
| UTF-8 Status/GuestBook | no string KV | EmitWat string storage |

## Commands

```sh
just near-compare-all-live
# reports: build/testkit/compare/near/<id>/sandbox-report.json
```
