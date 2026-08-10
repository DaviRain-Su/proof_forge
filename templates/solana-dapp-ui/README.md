# ProofForge · Solana dApp UI (minimal)

Minimal **React + Vite + `@solana/web3.js` + wallet-adapter** template for
**StateCell-shaped** programs produced by **ProofForge** (`pf build --target solana`).

```text
Write ProgramV1 (Lean)  →  pf build -t solana  →  *.idl.json + *.so
                                    ↓
                    pf deploy --network local (CLI)
                                    ↓
              browser wallet → PF ix-data (handlerId u64 LE + params)
```

This is **not** an Anchor/Rust project template. Contracts are authored with the
ProofForge language + `pf` / `proof-forge-next` CLI (and optional host SDK). The
UI only consumes PF IDL + a local validator.

## Quick start

```bash
# monorepo — build Solana artifacts
export PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next
pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o /tmp/sc-sol
cp /tmp/sc-sol/StateCell.idl.json templates/solana-dapp-ui/public/artifacts/

# deploy on local validator (CLI — not this UI)
# solana-test-validator &
# pf deploy --network local --broadcast --endpoint http://127.0.0.1:8899 -o /tmp/sc-sol
# write public/deployment.json (see deployment.example.json)

cd templates/solana-dapp-ui
npm install
npm run dev
# → http://127.0.0.1:5175
```

## Instruction encoding (PF, not Anchor)

```text
ix data = u64le(handlerId) || u64le(param0) || u64le(param1) || …
```

`handlerId` comes from `*.idl.json` (`instructions[].handlerId`).  
Do **not** use Anchor 8-byte sighash discriminators with PF ELF.

## Env

| Variable | Default |
|---|---|
| `VITE_RPC_URL` | `http://127.0.0.1:8899` |
| `VITE_PROGRAM_ID` | empty (use deployment.json) |
| `VITE_STATE_ACCOUNT` | empty |

## Boundaries

| This template | ProofForge CLI |
|---|---|
| Wallet UX + local RPC calls | Compile ProgramV1 → sBPF ELF + IDL |
| Does not compile Rust/Anchor | `pf build/verify/test/deploy` |
| Local validator default | Public Solana RPC broadcast refused in pf v0 |

## References

- `docs/product/09-solana-agent-playbook.md`
- `docs/product/10-solana-dapp-frontend.md`
- `docs/demos/solana-local-walkthrough.md`
