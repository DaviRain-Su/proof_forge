---
id: PRODUCT-NEAR-DAPP-FRONTEND
title: NEAR dApp frontend surface
status: draft
owner: product
updated: 2026-08-12
normative: false
---

# NEAR dApp frontend

Minimal React skeleton for ProofForge NEAR Wasm products.

## Template

```bash
pf build -t near
pf scaffold-ui --template near-dapp
cd ui/near-dapp && npm i && npm run dev
```

Source: `templates/near-dapp-ui`.

## Honesty

- Ecosystem packages (`near-api-js`, wallet-selector) — **not** vendored or version-pinned by PF
- `pf deploy -t near` is **save-only**; `--broadcast` refused in v0
- Local differential: `pf test -t near` / `near-sandbox` (not testnet parity, not formal)
- Sync `call` / sync transfer permanent fail-closed; Promise is async (see
  `docs/product/near-sync-async-api.md`)

## Product path (parity with EVM/Solana)

| Step | Command |
|------|---------|
| Setup | `pf setup --target near` |
| Build | `pf build -t near` |
| Test | `pf test -t near` (artifact fast-path when `*.wasm` present) |
| One-shot | `pf run -t near -- init 7` / `pf run -t near -- get` |
| Package | `pf deploy -t near` |
| UI | `pf scaffold-ui --template near-dapp` |

## Wire contract

1. Deploy package JSON under `<artifact>/tx/*.deployment.package.json` (account id is
   packaging metadata — rewrite for real deploy tooling outside pf v0).
2. Point near-api-js / wallet-selector at catalog RPC
   (`near.local.sandbox` narrative or `near.testnet` catalog-only).
3. Call/view method names match product exports (`init`, `increment`, `get`, …).

## Related

- Agent cheatsheet: `docs/product/near-agent-cheatsheet.md`
- Sync/async: `docs/product/near-sync-async-api.md`
- Catalog: `docs/product/chain-client-catalog.v1.json`

## UI deployment JSON

```bash
pf build -t near
pf deploy -t near   # optional save-only package under tx/
pf write-ui-json -t near --address <contract-or-account>
# → build/<target>/ui-deployment.json  (copy to template public/deployment.json)
```

Schema: `proof-forge.pf.near-ui-deployment.v1` (wasm sha, catalog network, optional contractId). Broadcast remains refused.

