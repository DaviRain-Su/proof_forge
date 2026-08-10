# Demo: Aleo with `pf` — local run → Testnet deploy → execute

**Audience:** video / livestream  
**Time:** ~8–12 minutes (save-only) · +5–15 minutes if real Testnet broadcast  
**Claims:** engineering demo only — **not** formal / hermetic / mainnet  

## What this proves

| Step | What viewers see |
|---|---|
| 1 Setup | `pf setup` checklist (compiler + Leo) |
| 2 New project | cargo-like `pf new` |
| 3 Build | `pf build` → `.aleo` OutputSet |
| 4 Local VM | `pf run` initialize / increment (offline Leo) |
| 5 Deploy package | `pf deploy` → saved deployment JSON (default **no broadcast**) |
| 6 Execute package | `pf execute` → saved execution JSON |
| 7 (Optional) Testnet | `--broadcast` with **your funded** key on testnet |

## Safety (say this on camera)

1. Default `pf deploy` / `pf execute` are **save-only** — no chain write.  
2. Mainnet is **refused**.  
3. Broadcast needs `--private-key-env NAME` and a **funded** testnet key — never the Leo well-known dev key.  
4. Do **not** paste private keys into chat, slides, or git.

---

## Prerequisites (before recording)

```bash
# Product tools (this machine already works if these pass)
export PROOF_FORGE_CLI=/path/to/proof-forge-next   # monorepo: $PWD/.lake/build/bin/proof-forge-next
export PATH="$HOME/.cargo/bin:$PATH"               # leo + cargo-installed pf

# Optional: install from crates.io
# cargo install proof-forge-pf --locked

pf setup --target aleo
# Expect: proof-forge-next ok, leo ok
```

### For real Testnet broadcast only

| Need | Notes |
|---|---|
| Aleo testnet account | Create via Leo / Provable explorer tooling |
| Funded credits | Testnet faucet / community faucet (policy changes — check current docs) |
| Env var with private key | e.g. `export PF_ALEO_TESTNET_KEY='APrivateKey1…'` — **never commit** |
| Network | `testnet` only (`devnet` ok for local snarkOS; mainnet refused) |

---

## Shot list (record in one terminal, large font)

### Shot 0 — Title card (5s)

> ProofForge `pf` · Aleo · local → Testnet  
> Default: save-only · Optional: broadcast

### Shot 1 — Setup (30s)

```bash
pf setup --target aleo
pf version
```

**Say:** “`pf` is the developer CLI. Compiler is `proof-forge-next`. Leo is the official VM/tool.”

### Shot 2 — New project (45s)

```bash
rm -rf /tmp/pf-aleo-video && mkdir -p /tmp/pf-aleo-video && cd /tmp/pf-aleo-video
pf new hello --target aleo
cd hello
cat pf.toml
sed -n '1,40p' src/Hello.lean
```

**Say:** “Same shape as our StateCell template — init, increment, get. No Lake package.”

### Shot 3 — Build (45s)

```bash
pf build
ls -la build/aleo/
head -30 build/aleo/hello.aleo   # program id may be hello.aleo
cat build/aleo/manifest.json | head -40
```

**Say:** “Compiler emits Aleo Instructions OutputSet. We never rewrite deployable.”

### Shot 4 — Local run (90s)

```bash
pf run -- initialize 5u64
pf run -- increment 3u64
pf run -v -- increment 1u64    # optional: show full Leo log once
```

**Say:** “Offline Leo VM via imports pin — no network.”

### Shot 5 — Deploy save-only (60s)

```bash
pf deploy --network testnet
ls -la build/aleo/tx/
# show a slice of the deployment JSON (no secrets)
python3 -I -c 'import json,glob; p=glob.glob("build/aleo/tx/*.deployment.json")[0]; d=json.load(open(p)); print(p); print("keys", list(d)[:12] if isinstance(d,dict) else type(d))'
```

**Say:** “This materializes a deploy transaction and **saves** it. broadcast=false by default.”

### Shot 6 — Execute save-only (60s)

```bash
pf execute --network testnet -- initialize 5u64
ls -la build/aleo/tx/
```

**Say:** “Same for execute — package the call, don’t send unless we opt in.”

### Shot 7 — Safety demo (30s)

```bash
# Must fail:
pf deploy --network mainnet || true
```

**Say:** “Mainnet hard-refused in pf v0.”

### Shot 8 — Optional real Testnet broadcast (only if funded key ready)

```bash
# DO NOT type the key on camera — load from a pre-exported env in a private shell
# export PF_ALEO_TESTNET_KEY='…'   # already set off-camera

pf deploy --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY
# Wait for explorer confirmation; paste program id on screen

pf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY -- initialize 5u64
pf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY -- increment 3u64
```

**Say:**

- “Broadcast is explicit.”  
- “Key comes from env name only — never a default file scan.”  
- “Well-known Leo demo key is refused for broadcast.”  
- Open Provable/Aleo explorer for the program + txs if available.

### Shot 9 — Close (20s)

```bash
pf --help | head -40
```

**Say:** “Same `pf` surface for EVM/Solana later — build / test / deploy save-only. Aleo is first full local+network packaging path.”

---

## One-shot rehearsal script (no broadcast)

```bash
#!/usr/bin/env bash
set -euo pipefail
export PROOF_FORGE_CLI="${PROOF_FORGE_CLI:?set PROOF_FORGE_CLI}"
PF="${PF:-pf}"
command -v "$PF" >/dev/null || PF="$(pwd)/clients/pf-cli/target/release/pf"

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pf-aleo-video.XXXXXX")"
echo "demo root: $ROOT"
cd "$ROOT"

"$PF" setup --target aleo
"$PF" new hello --target aleo
cd hello
"$PF" build
"$PF" run -- initialize 5u64
"$PF" run -- increment 3u64
"$PF" deploy --network testnet
"$PF" execute --network testnet -- initialize 5u64
echo "SAVE-ONLY OK — artifacts under $ROOT/hello/build/aleo/"
ls -la build/aleo/tx/
```

Save as `scripts/demo_aleo_testnet_save_only.sh` in the monorepo (optional) and run before filming.

---

## Broadcast checklist (day of shoot)

- [ ] Fresh shell; `echo $PF_ALEO_TESTNET_KEY` is set **off camera**  
- [ ] Key is **not** the Leo well-known dev key  
- [ ] Balance > fee on testnet  
- [ ] Screen recording hides any env dump / shell history  
- [ ] Plan B if faucet is down: film save-only only, show JSON + explorer docs  

---

## If something fails

| Symptom | Fix |
|---|---|
| `proof-forge-next` missing | `export PROOF_FORGE_CLI=…` or monorepo lake build |
| `leo not found` | install Leo 4.x; `pf setup --target aleo` |
| deploy twin mismatch | template must stay StateCell-shaped (`pf new` default) |
| broadcast refused well-known key | use a real testnet key in env |
| broadcast fee / network error | check endpoint, balance, Leo version |
| want quieter Leo | default `pf run` is quiet; `-v` for full log |

---

## Non-goals for this video

- Mainnet  
- Non–StateCell-shaped Aleo programs (twin registry only `statecell-v1` today)  
- Claiming formal verification or “production ready”  
- Showing private keys or seed phrases  

## CLI recording tools (what we use)

| Tool | Role | Install |
|---|---|---|
| **asciinema** | Terminal session cast (best for CLI demos) | `brew install asciinema` |
| **ffmpeg** | Optional screen MP4 from desktop | `brew install ffmpeg` |
| **script(1)** | Plain typescript log | preinstalled on macOS |

### One-command record (save-only)

```bash
export PROOF_FORGE_CLI="$PWD/.lake/build/bin/proof-forge-next"
just pf-cli-aleo-record
# → build/demos/aleo/pf-aleo-demo-*.cast
asciinema play build/demos/aleo/pf-aleo-demo-*.cast
# optional public share:
# asciinema upload build/demos/aleo/pf-aleo-demo-*.cast
```

### Real Testnet broadcast record

1. Create account (off camera): `leo account new`  
2. Fund via **https://faucet.aleo.org/** (captcha — human only; ~3+ credits for deploy)  
3. Load key into env (never echo):

```bash
export PF_ALEO_TESTNET_KEY='APrivateKey1…'   # funded testnet key
export PF_ALEO_BROADCAST=1
just pf-cli-aleo-record
```

Deploy fee observed in rehearsal: **~3.04 credits** (namespace + storage + synthesis).

Without faucet funds, broadcast correctly fails with insufficient balance after building the deployment plan — still useful footage.

### Optional desktop MP4 (macOS)

```bash
# Capture main display while you run the demo in Terminal (large font)
ffmpeg -f avfoundation -i "2:none" -r 30 -t 600 build/demos/aleo/screen.mp4
```

(`2` = “Capture screen 0” from `ffmpeg -f avfoundation -list_devices true -i ""`)

## Related

- `clients/pf-cli/README.md`  
- `docs/specs/cli-developer.md` § Aleo  
- `scripts/demo_aleo_record.sh` / `scripts/demo_aleo_testnet_save_only.sh`  
- `scripts/aleo_instructions_network_tx_acceptance.sh` (CI gate; save-only default)  
