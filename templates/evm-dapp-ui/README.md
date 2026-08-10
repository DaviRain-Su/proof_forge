# ProofForge · EVM dApp UI (minimal)

Minimal **React + Vite + viem** template for StateCell-shaped contracts produced by
`pf build -t evm`.

```text
pf build -t evm  →  *.abi.json + *.bin
        ↓
local Anvil deploy (script or in-UI)
        ↓
browser wallet → get() / increment(uint64)
```

- **Default path is local Anvil** (chain id 31337)
- **No public-chain broadcast** in pf v0 product surface
- Guide: [`docs/product/08-evm-dapp-frontend.md`](../../docs/product/08-evm-dapp-frontend.md)

## Quick start (recommended)

From monorepo root (needs `pf`/`proof-forge-next`, locked `anvil`+`cast`):

```bash
bash scripts/pf_evm_local_demo.sh
# leaves Anvil running; writes templates/evm-dapp-ui/public/deployment.json
```

In another terminal:

```bash
cd templates/evm-dapp-ui
npm install
npm run dev
# → http://127.0.0.1:5174
```

MetaMask:

1. Add network: RPC `http://127.0.0.1:<port from script>`, chain id from script (default **31337**)
2. Optional: import Anvil account #0 private key (**local only**):
   `ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
3. Connect → **Refresh get()** → **Send increment**

## Manual artifact path

```bash
pf build Examples/StateCell.lean --module Examples.StateCell -t evm -o /tmp/sc
cp /tmp/sc/StateCell.abi.json templates/evm-dapp-ui/public/artifacts/
cp /tmp/sc/StateCell.bin templates/evm-dapp-ui/public/artifacts/   # for in-UI deploy
```

Then start your own Anvil, deploy with `cast`/`pf deploy --broadcast --network local`, set
`VITE_CONTRACT_ADDRESS` or write `public/deployment.json`.

## Env

| Variable | Default | |
|---|---|---|
| `VITE_RPC_URL` | `http://127.0.0.1:8545` | overridden by deployment.json |
| `VITE_CHAIN_ID` | `31337` | |
| `VITE_CONTRACT_ADDRESS` | empty | |
| `VITE_CONSTRUCTOR_INITIAL` | `7` | StateCell ctor |

## Expected ABI shape

```json
constructor(uint64 initial)
function increment(uint64 delta) returns (uint64)
function get() view returns (uint64)
```

## Boundaries

| This template | ProofForge |
|---|---|
| Wallet UX + local calls | Compile / Anvil test / local deploy package |
| viem + injected provider | Does not vendor wagmi; catalog lists ethers/viem/wagmi as ecosystem |
| Not Sepolia/mainnet product | pf refuses public broadcast in v0 |

## References

- `docs/product/08-evm-dapp-frontend.md`
- `docs/demos/evm-local-walkthrough.md`
- `scripts/pf_evm_local_demo.sh`
- `scripts/pf_evm_test.sh`
