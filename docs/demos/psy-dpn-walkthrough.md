---
id: DEMO-PSY-DPN-WALKTHROUGH
title: Demo — Psy DPN with pf (+ official ecosystem pointers)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Demo: Psy with ProofForge `pf`（DPN emission）

**Claims:** engineering only — PF stops at canonical DPN; deploy/prove/wallet are official Psy tools  
**Time:** ~5 minutes (PF) · optional +N minutes on official WebIDE/wallet

## What this proves

| Step | Viewers see |
|---|---|
| 1 Setup | `pf setup --target psy` (zero-tool) |
| 2 Build | `pf build -t psy` → `StateCell.dpn.json` |
| 3 Inspect | method_id / state_commands / manifest `deployable=false` |
| 4 Ecosystem | open config / explorer / IDE / wallet (no PF private key) |

## Safety

1. Default `pf deploy` is **save-only**; `--broadcast` wraps official `deploy-contract --is-deploy` (testnet/local).  
2. Do **not** paste private keys into chat, slides, or git.  
3. Success ≠ mainnet / formal readiness.  
4. Public endpoints from `config.psy-protocol.xyz` **drift** — refresh live JSON.

---

## Shot list

### 1) Tooling

```bash
export PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next
export PATH="$HOME/.cargo/bin:$PATH"
pf setup --target psy
pf doctor --target psy
# expect: psy status=ok, tools=[]
```

### 2) Build DPN

```bash
pf build Examples/StateCell.lean \
  --module Examples.StateCell \
  --target psy \
  -o build/v2/sc-psy

ls -la build/v2/sc-psy/
# StateCell.dpn.json  manifest.json  evidence.json
```

**Say:** “Sole profile `psy-dpn-v1`. No Dargo source, no local VM in PF.”

### 3) Peek package

```bash
jq '.[].name, .[].method_id' build/v2/sc-psy/StateCell.dpn.json
jq '{target,codegenProfile,deployable,files}' build/v2/sc-psy/manifest.json
```

Expected shape: array of function circuit defs (`get` / `increment` / `initialize`).




> **Session continuity:** `psy_user_cli simulate` is **one call per process** (fresh memory).
> For `init(7) → increment(5) → get = 12`, use `scripts/psy_dpn_session.py` / `pf test -t psy`
> (shared-state harness). Do not expect three separate simulates to accumulate.

### 3b) Local VM via official `psy_user_cli simulate` (now wired)

```bash
# one-shot monorepo smoke
just psy-dpn-local-smoke
# or:
export PATH="$HOME/.psy/bin:$PATH"
pf build Examples/StateCell.lean --module Examples.StateCell --target psy -o build/v2/sc-psy
pf test -t psy --artifact build/v2/sc-psy
pf run -t psy --artifact build/v2/sc-psy -- initialize 7
pf run -t psy --artifact build/v2/sc-psy -- increment 5
```

**Honesty:** each `simulate` uses a **fresh** in-memory state (no multi-tx session).  
This is the official DPN VM, not a PF-written interpreter. Not UPS/proof/network.

### 4) Official surfaces (browser)

| Open | Why |
|---|---|
| https://config.psy-protocol.xyz | live RPC + L1 Sepolia addresses |
| https://explorer.psy-protocol.xyz | chain observability |
| https://ide.psy-protocol.xyz | write/compile Psy-lang in browser |
| https://app.psy-protocol.xyz/#/wallet | wallet UX |
| https://docs.psy-protocol.xyz | language · SDK · VM · RPC |

Optional developer machine:

```bash
curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh \
  | PSYUP_DEFAULT_NETWORK=sepolia sh
psyup install
# psyup new demo && cd demo && psyup build
# deploy remains official: psyup deploy (funded key / keystore)
```

### 5) Closing line

> ProofForge ships **verifiable DPN packages** from a shared ProgramV1.  
> Psy official stack ships **language, prove, deploy, wallet**.  
> We integrate at the package boundary — we don’t fake a second Psy compiler inside PF.

## Related

- `docs/product/11-psy-agent-playbook.md`  
- `docs/product/12-psy-dapp-frontend.md`  
- `docs/targets/10-psy.md`  
