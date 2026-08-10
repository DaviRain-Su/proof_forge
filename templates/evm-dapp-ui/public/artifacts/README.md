# Artifacts

Copy from a `pf build -t evm` OutputSet:

```bash
# monorepo example
pf build Examples/StateCell.lean --module Examples.StateCell -t evm -o /tmp/sc
cp /tmp/sc/StateCell.abi.json templates/evm-dapp-ui/public/artifacts/
cp /tmp/sc/StateCell.bin templates/evm-dapp-ui/public/artifacts/
```

Or run monorepo helper:

```bash
bash scripts/pf_evm_local_demo.sh
```

which builds, starts Anvil, deploys, and writes `public/deployment.json`.
