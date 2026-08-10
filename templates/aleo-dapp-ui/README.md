# ProofForge · Aleo dApp UI (minimal)

Minimal **React + Vite** template that pairs ProofForge backend artifacts with the
official **Provable Aleo Wallet Adapter**.

```text
pf build / pf deploy  →  program id
        ↓
this UI: connect wallet → initialize / increment → read public mappings
```

- **No private keys in the browser**
- Default program: `pfdemo336641.aleo` (live Testnet demo from the monorepo)
- Guide: [`docs/product/07-aleo-dapp-frontend-wallet.md`](../../docs/product/07-aleo-dapp-frontend-wallet.md)

## Prerequisites

1. Node 20+ (or 18+)
2. A browser wallet extension: [Leo](https://www.leo.app/) / Puzzle / Shield
3. Testnet credits in that wallet (https://faucet.aleo.org/)
4. A deployed StateCell-shaped program (or use the default demo id)

## Quick start

```bash
cd templates/aleo-dapp-ui
cp .env.example .env          # edit VITE_ALEO_PROGRAM_ID if needed
npm install
npm run dev
# → http://127.0.0.1:5173
```

## Env

| Variable | Default | Meaning |
|---|---|---|
| `VITE_ALEO_PROGRAM_ID` | `pfdemo336641.aleo` | On-chain program id |
| `VITE_ALEO_NETWORK` | `testnet` | `testnet` \| `mainnet` \| `canary` |
| `VITE_ALEO_API` | `https://api.explorer.provable.com/v1` | REST base |
| `VITE_ALEO_FEE_MICROCREDITS` | `100000` | Public fee hint for execute |

## Wire your own `pf` program

```bash
# monorepo / project with pf
pf new hello --target aleo && cd hello
pf build
pf deploy --network testnet --broadcast \
  --private-key-env PF_ALEO_TESTNET_KEY \
  --program-id myapp01

# template
echo 'VITE_ALEO_PROGRAM_ID=myapp01.aleo' > ../templates/aleo-dapp-ui/.env
```

Program shape expected (StateCell twin):

- `initialize(public u64)`
- `increment(public u64)`
- mappings `pf_state_0`, `initialized`

## Scripts

| Command | |
|---|---|
| `npm run dev` | Vite dev server |
| `npm run build` | production build |
| `npm run preview` | preview build |

## Boundaries

| This template | ProofForge CLI / MCP |
|---|---|
| Wallet UX + user-signed txs | Compile / package / optional CLI broadcast |
| Ecosystem `@provablehq/*` packages | Not vendored or version-pinned by PF product lock |
| Not formal / hermetic / mainnet product | Same honesty |

## Troubleshooting

| Symptom | Fix |
|---|---|
| Connect does nothing | Install Leo/Puzzle/Shield extension; allow site |
| `execute` rejected | Program id wrong; wallet on wrong network; need initialize first |
| mapping always `—` | Program not deployed on this network; wait for finality; check explorer |
| Fee errors | Raise `VITE_ALEO_FEE_MICROCREDITS`; fund wallet |
| Build fails on adapter types | `npm ls @provablehq/aleo-wallet-adaptor-react`; use lockfile |

## References

- https://docs.aleo.org/build/wallets/wallet-adapter/getting-started
- https://github.com/ProvableHQ/aleo-dev-toolkit
- Live demo program: https://testnet.explorer.provable.com/program/pfdemo336641.aleo
