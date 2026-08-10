# PF Solana artifacts

Copy from a `pf build -t solana` output directory:

```bash
pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o /tmp/sc-sol
cp /tmp/sc-sol/StateCell.idl.json templates/solana-dapp-ui/public/artifacts/
# optional: keep .so off the web root — deploy via pf CLI, not the browser
```

This template only needs `*.idl.json` (+ `public/deployment.json` after deploy).
