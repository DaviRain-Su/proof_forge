---
id: DEMO-EVM-LOCAL-WALKTHROUGH
title: Demo — EVM with pf (build → Anvil deploy → browser UI)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Demo: EVM with `pf` — build → local Anvil → browser

**Audience:** video / hackathon  
**Time:** ~8–12 minutes  
**Claims:** engineering demo only — **not** formal / hermetic / mainnet / public broadcast  

## Shot list

### 1) Build

```bash
export PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next
pf build Examples/StateCell.lean --module Examples.StateCell -t evm -o build/v2/sc-ui
ls build/v2/sc-ui/
# StateCell.abi.json  StateCell.bin  StateCell.yul  manifest.json
```

### 2) One-shot local demo (recommended)

```bash
bash scripts/pf_evm_local_demo.sh
# starts Anvil, deploys ctor(7), writes templates/evm-dapp-ui/public/deployment.json
# leave running
```

### 3) UI

```bash
cd templates/evm-dapp-ui
npm install
npm run dev
# http://127.0.0.1:5174
```

MetaMask → add network (RPC/port/chainId printed by script) → Connect → Refresh get() → increment(5) → get()==12.

### 4) Safety on camera

- Local Anvil only  
- Anvil #0 key is a **well-known demo key** — never mainnet  
- `pf deploy --network testnet --broadcast` for EVM is **refused** in v0  

## Manual cast path (optional)

```bash
anvil --port 8545 &
BYTECODE=$(tr -d '\n' < build/v2/sc-ui/StateCell.bin)
ENC=$(cast abi-encode 'constructor(uint64)' 7)
cast send --rpc-url http://127.0.0.1:8545 \
  --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --create "0x${BYTECODE}${ENC#0x}"
```

## Related

- `docs/product/08-evm-dapp-frontend.md`  
- `templates/evm-dapp-ui/`  
- `scripts/pf_evm_test.sh`  
