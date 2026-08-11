# ProofForge NEAR dApp UI (skeleton)

Engineering frontend starter for NEAR contracts built with ProofForge.

## Honesty

- Ecosystem packages (`near-api-js`, wallet-selector) — **not** vendored/pinned by PF
- `pf deploy -t near` is **save-only**; `--broadcast` refused in v0
- Local differential: `pf test -t near` / `near-sandbox` (not testnet parity, not formal)

## Flow

```bash
pf build -t near
pf test -t near          # artifact fast-path when *.wasm present
pf deploy -t near        # package only
pf scaffold-ui --template near-dapp
cd ui/near-dapp && npm i && npm run dev
```

Paste the contract account from your sandbox/deploy package. Wire wallet yourself.
