# ProofForge CosmWasm dApp UI (skeleton)

Engineering frontend starter for CosmWasm contracts built with ProofForge.

## Honesty

- Ecosystem packages (`@cosmjs/*`) — **not** vendored/pinned by PF
- `pf deploy -t cosmwasm` is **save-only**; `--broadcast` refused
- Local differential: `pf test -t cosmwasm` / cosmwasm-vm mock (not wasmd mainnet, not formal)

## Flow

```bash
pf build -t cosmwasm
pf test -t cosmwasm
pf deploy -t cosmwasm
pf scaffold-ui --template cosmwasm-dapp
cd ui/cosmwasm-dapp && npm i && npm run dev
```
