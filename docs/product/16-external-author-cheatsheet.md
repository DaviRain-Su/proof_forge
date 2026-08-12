---
id: PRODUCT-EXTERNAL-AUTHOR-CHEATSHEET
title: External author cheatsheet (install → build → test → run → deploy → UI)
status: draft
owner: product+engineering
updated: 2026-08-12
normative: false
---

# External author cheatsheet

**Do not `lake build`.** Channel: `engineering-dist`. Not formal Stage-0.  
Authority: [ADR-0040](../adr/0040-external-author-host-mode-and-bundle.md) · [14-external-author-mvp.md](14-external-author-mvp.md)

Single page for agents: **install → setup → new → build → test → run → deploy → UI**.

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

## Universal skeleton (any target)

```bash
pf -y setup --target <id>          # install tool-root pins when available
pf doctor --target <id>            # checklist
pf new hello --target <id> && cd hello
pf build                           # → build/<target>/ artifacts
pf test                            # host-optional; may skip-clean if tools missing
pf run -- <method> [u64…]          # EVM / Solana / NEAR / CosmWasm / Aleo / Psy
pf deploy                          # save-only package (broadcast restricted)
pf scaffold-ui --template <id>-dapp   # when template exists
```

`pf run` is **engineering local runtime only** (Anvil / Mollusk / near-sandbox /
cosmwasm-vm / leo / psy simulate). Not mainnet. Not formal.

---

## EVM

```bash
pf -y setup --target evm
pf network list --family evm
pf new hello --target evm && cd hello
pf build
pf test                              # Anvil smoke (tool-root anvil/cast)
pf run -- get                        # one-shot Anvil view (ctor default 0)
pf run -- increment 5                # mutate; prints return
pf run -- init 7                     # deploy-only; prints address
# PF_EVM_INIT_ARGS=7 pf run -- get   # custom constructor then call
pf deploy                            # save-only
pf scaffold-ui --template evm-dapp
cd ui/evm-dapp && npm i && npm run dev
```

Optional local broadcast (Anvil only):

```bash
pf deploy --broadcast --network local
# writes ui-deployment.json with contractAddress
```

Detail: [08-evm-dapp-frontend.md](08-evm-dapp-frontend.md) · dossier `docs/targets/01-evm.md`

---

## Solana (body-only run)

```bash
pf -y setup --target solana
pf new h --target solana && cd h
pf build
pf verify                            # offline; needs proof-forge-solana-client
pf test                              # Mollusk if monorepo harness; else skip-clean
pf run -- get                        # one-shot Mollusk (StateCell-shaped; monorepo)
pf run -- increment 5
pf run -- init 7
pf scaffold-ui --template solana-dapp
```

**Run scope:** body-only single-state programs (what `pf new` scaffolds).  
CPI / multi-role / TipJar → use `pf test`, not `pf run`.

Detail: [09-solana-agent-playbook.md](09-solana-agent-playbook.md) · dossier `docs/targets/02-solana.md`

---

## NEAR

```bash
pf -y setup --target near --with-runtime
pf new cell --target near && cd cell
pf build
pf test                              # near-sandbox; artifact fast-path or corpus
pf run -- init 7
pf run -- increment 5
pf run -- get
# views also: nativeBalanceU128 (needs pf.assets@1.2.0 program)
pf deploy                            # save-only; --broadcast always refused
pf write-ui-json -t near
pf scaffold-ui --template near-dapp
```

Permanent FC (not bugs): sync transfer/call, view `context.caller`, public broadcast.  
Sync vs async: [near-sync-async-api.md](near-sync-async-api.md)  
Cheatsheet: [near-agent-cheatsheet.md](near-agent-cheatsheet.md)

---

## CosmWasm

```bash
pf -y setup --target cosmwasm --with-runtime
pf new cell --target cosmwasm && cd cell
pf build
pf test                              # cosmwasm-vm mock; artifact fast-path or corpus
pf run -- get                        # one-shot mock (auto-instantiate)
pf run -- increment 5
pf deploy                            # save-only; --broadcast refused
pf write-ui-json -t cosmwasm
pf scaffold-ui --template cosmwasm-dapp
```

Cheatsheet: [cosmwasm-agent-cheatsheet.md](cosmwasm-agent-cheatsheet.md)

---

## Aleo / Psy (zero-tool compile + interactive run)

```bash
pf -y setup --target aleo            # or psy
pf new h --target aleo && cd h
pf build
pf run -- initialize 5u64            # Aleo leo offline / Psy simulate
pf deploy                            # Psy wraps psy_user_cli; Aleo save-oriented
```

Playbooks: [03-hello-dapp-agent-playbook.md](03-hello-dapp-agent-playbook.md) · [11-psy-agent-playbook.md](11-psy-agent-playbook.md)

---

## TON

```bash
pf -y setup --target ton
pf new cell --target ton && cd cell
pf build
pf test                              # @ton/sandbox corpus; skip-clean if tools missing
pf run -- get                        # one-shot sandbox (auto-init 0)
pf run -- increment 5
pf deploy                            # save-only; --broadcast refused
```

Needs monorepo `runtime-tests/ton` + node ≥18 + `npm install` (first run).

## Noir / Quint (no interactive `pf run` yet)

```bash
pf build -t noir|quint
pf test -t noir|quint                # artifact / source smoke
pf deploy -t noir|quint              # save-only; --broadcast refused
# pf run → NotImplemented; use pf test
```

---

## Agent rules

| Do | Don't |
|---|---|
| Bundle + `pf` subcommands | `lake build proof_forge_next` as default path |
| `PROOF_FORGE_HOST_MODE=dev` (default) | Hand-edit `host-profiles.lock.json` |
| stdio MCP on machine with bundle | Claim remote edge MCP can compile / hold keys |
| `pf network use <id>` for RPC metadata | Public `--broadcast` in pf v0 (EVM/Solana local only) |
| `pf run` for local engineering smoke | Treat `pf run` as mainnet or formal evidence |

## Fix-ups

| Symptom | Fix |
|---|---|
| `host:stat` / host profile mismatch | `export PROOF_FORGE_HOST_MODE=dev` |
| missing compiler | `pf bootstrap --from bundle.tar.gz` |
| missing solc/anvil | `pf -y setup --target evm` |
| Solana test/run skipped | expected without monorepo harness; use `pf verify` |
| NEAR run skipped | install near-sandbox under Tool Root; `pf setup --target near --with-runtime` |
| CosmWasm run skipped | need cargo + `runtime-tests/cosmwasm` (monorepo) or bundle with scripts |
| GLIBC / near-sandbox won't start on old Linux | `scripts/near_sandbox_glibc_materialize.sh` → Tool Root `near-sandbox-glibc/` (auto-launch); or set `PF_NEAR_SANDBOX_LOADER`+`LIBRARY_PATH`. Engineering pack — not hermetic lock pin yet |

## Related

- MVP backlog: [14-external-author-mvp.md](14-external-author-mvp.md)
- Networks: [networks.v1.json](networks.v1.json)
- Install surface: [01-toolchain-install-surface.md](01-toolchain-install-surface.md)
- Hello playbook: [03-hello-dapp-agent-playbook.md](03-hello-dapp-agent-playbook.md)
