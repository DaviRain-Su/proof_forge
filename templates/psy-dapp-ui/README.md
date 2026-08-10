# ProofForge · Psy dApp UI

Minimal React UI for **ProofForge Psy** programs:

1. `pf build -t psy` → `*.dpn.json`
2. `scripts/psy_dpn_to_abi.py` → `*.abi.json`
3. `pf deploy -t psy --broadcast` → `tx/deployment.json` (`contractId`)
4. Copy artifacts into `public/`, open this UI, connect **official Psy wallet** (`window.psy`)

## Setup

```bash
# from monorepo after build+deploy
cp build/v2/sc-psy/*.abi.json templates/psy-dapp-ui/public/artifacts/StateCell.abi.json
cp build/v2/sc-psy/tx/deployment.json templates/psy-dapp-ui/public/deployment.json

cd templates/psy-dapp-ui
npm install
npm run dev
```

## Boundaries

- PF does **not** ship `@psy-protocol/*` or hold keys.
- Calls go through the **official wallet extension**.
- L2 balance required for calls (GUTA/DA fees). Deploy may work at zero balance.
- Engineering demo only — not formal/mainnet product.

## Related

- `docs/product/12-psy-dapp-frontend.md`
- `docs/product/11-psy-agent-playbook.md`
- https://app.psy-protocol.xyz/#/wallet
