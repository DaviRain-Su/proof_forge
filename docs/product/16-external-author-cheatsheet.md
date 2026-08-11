---
id: PRODUCT-EXTERNAL-AUTHOR-CHEATSHEET
title: External author cheatsheet (install → build → test → UI)
status: draft
owner: product+engineering
updated: 2026-08-11
normative: false
---

# External author cheatsheet

**Do not `lake build`.** Channel: `engineering-dist`. Not formal Stage-0.  
Authority: [ADR-0040](../adr/0040-external-author-host-mode-and-bundle.md) · [14-external-author-mvp.md](14-external-author-mvp.md)

## Install (once)

```bash
# From GitHub Release asset proof-forge-bundle-<ver>-<plat>.tar.gz
bash scripts/install.sh --from proof-forge-bundle-*.tar.gz
# or: pf bootstrap --from proof-forge-bundle-*.tar.gz

export PATH="$HOME/.local/proof-forge/current/bin:$PATH"
export PROOF_FORGE_CLI="$HOME/.local/proof-forge/current/bin/proof-forge-next"
export PROOF_FORGE_ROOT="$HOME/.local/proof-forge/current"
# default PROOF_FORGE_HOST_MODE=dev  (no hermetic host:stat pin)
```

## EVM day path

```bash
pf -y setup --target evm
pf network list --family evm
pf new hello --target evm && cd hello
pf build
pf test                    # Anvil smoke (needs tool-root anvil/cast)
pf deploy                  # save-only package
pf scaffold-ui --template evm-dapp
cd ui/evm-dapp && npm i && npm run dev
```

Optional local broadcast (Anvil only):

```bash
pf deploy --broadcast --network local
# writes ui-deployment.json with contractAddress
```

## Aleo / Psy (zero-tool compile)

```bash
pf -y setup --target aleo   # or psy
pf new h --target aleo && cd h && pf build
```

## Solana

```bash
pf -y setup --target solana
pf new h --target solana && cd h
pf build
pf verify                  # offline; needs proof-forge-solana-client
pf test                    # Mollusk if monorepo runtime-tests present; else skip-clean
pf scaffold-ui --template solana-dapp
```

## Agent rules

| Do | Don't |
|---|---|
| Use bundle + `pf` subcommands | `lake build proof_forge_next` as default |
| `PROOF_FORGE_HOST_MODE=dev` (default) | Hand-edit `host-profiles.lock.json` |
| stdio MCP on machine with bundle | Claim remote edge MCP can compile |
| `pf network use <id>` for RPC metadata | Public `--broadcast` in pf v0 (EVM/Solana local only) |

## Fix-ups

| Symptom | Fix |
|---|---|
| `host:stat` / host profile mismatch | `export PROOF_FORGE_HOST_MODE=dev` |
| missing compiler | `pf bootstrap --from bundle.tar.gz` |
| missing solc/anvil | `pf -y setup --target evm` |
| Solana test skipped | expected without monorepo harness; use `pf verify` |

## Related

- Playbook: [03-hello-dapp-agent-playbook.md](03-hello-dapp-agent-playbook.md)
- Networks: [networks.v1.json](networks.v1.json)
- EVM UI: [08-evm-dapp-frontend.md](08-evm-dapp-frontend.md)
