---
id: PRODUCT-COSMWASM-DAPP-FRONTEND
title: CosmWasm dApp frontend surface
status: draft
owner: product
updated: 2026-08-12
normative: false
---

# CosmWasm dApp frontend

Minimal React skeleton for ProofForge CosmWasm Wasm products.

## Template

```bash
pf build -t cosmwasm
pf scaffold-ui --template cosmwasm-dapp
cd ui/cosmwasm-dapp && npm i && npm run dev
```

Source: `templates/cosmwasm-dapp-ui`.

## Honesty

- Ecosystem packages (`@cosmjs/*`) — **not** vendored or version-pinned by PF
- `pf deploy -t cosmwasm` is **save-only**; `--broadcast` refused in v0
- Local differential: `pf test -t cosmwasm` / cosmwasm-vm mock (not wasmd mainnet, not formal)
- Generic sync `call` permanent fail-closed; `schedule` → SubMsg `reply_on=never` (same-tx)
- Interactive `pf run` for CosmWasm is **not** in v0 — exercise JSON ABI via `pf test`

## Product path (parity with EVM/Solana)

| Step | Command |
|------|---------|
| Setup | `pf setup --target cosmwasm` |
| Build | `pf build -t cosmwasm` |
| Test | `pf test -t cosmwasm` (artifact fast-path when `*.wasm` present) |
| Package | `pf deploy -t cosmwasm` |
| UI | `pf scaffold-ui --template cosmwasm-dapp` |

## JSON ABI subset (product wire)

- Instantiate: flat `{ "param": <decimal u64>, … }`
- Execute/query: `{ "methodName": { …params } }`
- Valued execute: attribute `result` = decimal or JSON array of decimals
- Query ok: `{"ok":"<decimal>"}` or `{"ok":"[d0,d1,…]"}` (text, not Binary base64)

Sidecar: `<Program>.cosmwasm-abi.json` (`proof-forge-cosmwasm-abi/v1alpha1`).

## Related

- Agent cheatsheet: `docs/product/cosmwasm-agent-cheatsheet.md`
- Dossier: `docs/targets/04-cosmwasm.md`
- Catalog: `docs/product/chain-client-catalog.v1.json`

## UI deployment JSON

```bash
pf build -t cosmwasm
pf deploy -t cosmwasm   # optional save-only package under tx/
pf write-ui-json -t cosmwasm --address <contract-or-account>
# → build/<target>/ui-deployment.json  (copy to template public/deployment.json)
```

Schema: `proof-forge.pf.cosmwasm-ui-deployment.v1` (wasm sha, catalog network, optional contractId). Broadcast remains refused.

