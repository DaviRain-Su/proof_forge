#!/usr/bin/env bash
# End-to-end local Solana demo for templates/solana-dapp-ui via Surfpool.
#
# 1) pf/proof-forge-next build StateCell → solana
# 2) pf verify (offline joins)
# 3) start Surfpool (scripts/solana_surfpool_up.sh)
# 4) pf deploy --broadcast --network local (or solana program deploy fallback)
# 5) create state account + send init/increment/get (PF ix encoding)
# 6) write templates/solana-dapp-ui/public/deployment.json (+ copy idl)
# 7) leave Surfpool running unless PF_SOLANA_DEMO_KEEP=0
#
# Env:
#   PROOF_FORGE_CLI / PROOF_FORGE_SOLANA_CLIENT
#   PF_SOLANA_DEMO_OUT (default build/v2/solana-dapp-demo)
#   PF_SOLANA_DEMO_KEEP=1 (default) leave surfpool up; 0 = tear down
#   PF_SOLANA_CTOR_INITIAL (default 7)
#   PF_SOLANA_INCREMENT (default 5)
#
# Engineering only — not formal / mainnet / public RPC.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Prefer official Surfpool 1.x + Solana CLI 4.x (same as miniamm surfpool smoke).
if [[ -x "${HOME}/.local/bin/surfpool" ]]; then
  PATH="${HOME}/.local/bin:${PATH}"
  export PATH
fi
if [[ -d "${HOME}/.local/share/solana/install/active_release/bin" ]]; then
  PATH="${HOME}/.local/share/solana/install/active_release/bin:${PATH}"
  export PATH
fi

ui_dir="$root/templates/solana-dapp-ui"
out_dir="${PF_SOLANA_DEMO_OUT:-$root/build/v2/solana-dapp-demo}"
source_rel="Examples/StateCell.lean"
module_name="Examples.StateCell"
ctor_initial="${PF_SOLANA_CTOR_INITIAL:-7}"
increment_delta="${PF_SOLANA_INCREMENT:-5}"
keep="${PF_SOLANA_DEMO_KEEP:-1}"
surf_dir="$root/runtime-tests/solana/surfpool"

die() { echo "pf-solana-local-demo: FAIL: $*" >&2; exit 1; }
info() { echo "pf-solana-local-demo: $*"; }

for tool in surfpool solana solana-keygen; do
  command -v "$tool" >/dev/null 2>&1 || die "missing $tool on PATH"
done
info "surfpool=$(command -v surfpool) $(surfpool --version 2>/dev/null | head -1)"
info "solana=$(command -v solana) $(solana --version 2>/dev/null | head -1)"

solana_ver="$(solana --version 2>/dev/null || true)"
if [[ "$solana_ver" != *"4."* && "$solana_ver" != *"5."* ]]; then
  die "need Solana CLI 4.x+ matching Surfpool (got: $solana_ver)"
fi

cli="${PROOF_FORGE_CLI:-}"
if [[ -z "$cli" || ! -x "$cli" ]]; then
  if [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
    cli="$root/.lake/build/bin/proof-forge-next"
  else
    die "proof-forge-next not found (lake build or set PROOF_FORGE_CLI)"
  fi
fi
export PROOF_FORGE_CLI="$cli"

pf_bin=""
if [[ -x "$root/clients/pf-cli/target/release/pf" ]]; then
  pf_bin="$root/clients/pf-cli/target/release/pf"
elif command -v pf >/dev/null 2>&1; then
  pf_bin="$(command -v pf)"
fi

sc_bin="${PROOF_FORGE_SOLANA_CLIENT:-}"
if [[ -z "$sc_bin" || ! -x "$sc_bin" ]]; then
  if [[ -x "$root/clients/solana-client/target/release/proof-forge-solana-client" ]]; then
    sc_bin="$root/clients/solana-client/target/release/proof-forge-solana-client"
  elif command -v proof-forge-solana-client >/dev/null 2>&1; then
    sc_bin="$(command -v proof-forge-solana-client)"
  fi
fi
[[ -n "$sc_bin" && -x "$sc_bin" ]] || die "proof-forge-solana-client missing"
export PROOF_FORGE_SOLANA_CLIENT="$sc_bin"

[[ -d "$ui_dir" ]] || die "missing $ui_dir"

started_surfpool=0
cleanup() {
  if [[ "$keep" != "1" && "$started_surfpool" == "1" ]]; then
    bash "$root/scripts/solana_surfpool_down.sh" || true
  fi
}
trap cleanup EXIT

# --- build -------------------------------------------------------------------
info "build $source_rel → $out_dir"
rm -rf "$out_dir"
mkdir -p "$(dirname "$out_dir")"
"$cli" build "$source_rel" --module "$module_name" --target solana -o "$out_dir"

so_path=""
if [[ -f "$out_dir/StateCell.so" ]]; then
  so_path="$out_dir/StateCell.so"
else
  so_path="$(find "$out_dir" -maxdepth 1 -type f -name '*.so' | sort | head -n 1 || true)"
fi
[[ -n "$so_path" && -s "$so_path" ]] || die "no *.so under $out_dir"
program_name="$(basename "$so_path" .so)"
idl_path="$out_dir/${program_name}.idl.json"
[[ -f "$idl_path" ]] || die "missing IDL $idl_path"
elf_size="$(wc -c <"$so_path" | tr -d ' ')"
info "elf=${program_name}.so ${elf_size}B"

# --- offline verify ----------------------------------------------------------
info "offline verify"
if [[ -n "$pf_bin" ]]; then
  "$pf_bin" verify -t solana --artifact "$out_dir" \
    || die "pf verify failed"
else
  "$sc_bin" verify-artifacts --artifact-dir "$out_dir" \
    || die "solana-client verify-artifacts failed"
fi

# --- Surfpool ----------------------------------------------------------------
# Stop stale instance so ports/keys are clean.
bash "$root/scripts/solana_surfpool_down.sh" >/dev/null 2>&1 || true
export SURFPOOL_NETWORK="${SURFPOOL_NETWORK:-offline}"
info "start Surfpool (network=$SURFPOOL_NETWORK)"
bash "$root/scripts/solana_surfpool_up.sh" >/dev/null
started_surfpool=1
rpc_file="$surf_dir/rpc-url.txt"
[[ -f "$rpc_file" ]] || die "missing $rpc_file after surfpool up"
rpc="$(tr -d '[:space:]' <"$rpc_file")"
[[ "$rpc" == http://* || "$rpc" == https://* ]] || die "bad rpc url: $rpc"
payer_kp="$surf_dir/keys/payer.json"
program_kp="$surf_dir/keys/program.json"
[[ -f "$payer_kp" && -f "$program_kp" ]] || die "keypairs missing after up"
program_id="$(solana-keygen pubkey "$program_kp")"
payer_pk="$(solana-keygen pubkey "$payer_kp")"
info "rpc=$rpc program_id=$program_id payer=$payer_pk"

bal="$(solana balance "$payer_pk" --url "$rpc" 2>/dev/null | awk '{print $1}')"
info "payer balance=${bal:-?} SOL"

# --- deploy ------------------------------------------------------------------
tx_dir="$out_dir/tx"
mkdir -p "$tx_dir"
info "deploy $so_path → $program_id"
deploy_log="$(mktemp "${TMPDIR:-/tmp}/pf-sol-demo-deploy.XXXXXX.log")"
deploy_ok=0
if [[ -n "$pf_bin" ]]; then
  set +e
  PF_SOLANA_PAYER_KP="$payer_kp" \
    "$pf_bin" deploy -t solana --artifact "$out_dir" \
      --network local --broadcast --endpoint "$rpc" \
      --private-key-env PF_SOLANA_PAYER_KP \
      --save "$tx_dir" \
      >"$deploy_log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    deploy_ok=1
    # pf may have generated its own program keypair; prefer receipt programId
    if [[ -f "$tx_dir/${program_name}.deployment.receipt.json" ]]; then
      rid="$(/usr/bin/python3 -I -S -c "import json; print(json.load(open('$tx_dir/${program_name}.deployment.receipt.json')).get('programId',''))" 2>/dev/null || true)"
      if [[ -n "${rid:-}" ]]; then
        program_id="$rid"
      fi
    fi
  else
    info "pf deploy broadcast failed; falling back to solana program deploy"
    cat "$deploy_log" >&2 || true
  fi
fi

if [[ "$deploy_ok" != "1" ]]; then
  set +e
  solana program deploy "$so_path" \
    --url "$rpc" \
    --keypair "$payer_kp" \
    --program-id "$program_kp" \
    --max-len "$((elf_size + 65536))" \
    >"$deploy_log" 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || {
    echo "pf-solana-local-demo: deploy failed:" >&2
    cat "$deploy_log" >&2
    rm -f "$deploy_log"
    exit 1
  }
  program_id="$(solana-keygen pubkey "$program_kp")"
fi
sig="$(rg -o 'Signature: *\S+' "$deploy_log" 2>/dev/null | awk '{print $2}' | head -1 || true)"
rm -f "$deploy_log"
info "deploy ok program_id=$program_id sig=${sig:-n/a}"

show_out="$(solana program show "$program_id" --url "$rpc" --keypair "$payer_kp" 2>&1)" \
  || die "program show failed: $show_out"
echo "$show_out" | head -15 >&2

# --- create state account + invoke (solders helper) -------------------------
state_kp="$tx_dir/${program_name}-state-keypair.json"
if [[ ! -f "$state_kp" ]]; then
  solana-keygen new --no-bip39-passphrase --silent -o "$state_kp" >/dev/null \
    || die "generate state keypair"
fi
state_pk="$(solana-keygen pubkey "$state_kp")"
info "state keypair=$state_pk"

info "create state + invoke init/increment"
py_bin="python3"
if [[ -x /tmp/pf-sol-venv/bin/python3 ]]; then
  py_bin=/tmp/pf-sol-venv/bin/python3
elif [[ -n "${VIRTUAL_ENV:-}" && -x "${VIRTUAL_ENV}/bin/python3" ]]; then
  py_bin="${VIRTUAL_ENV}/bin/python3"
fi
set +e
"$py_bin" "$root/scripts/pf_solana_statecell_invoke.py" \
  --rpc "$rpc" \
  --program-id "$program_id" \
  --payer-keypair "$payer_kp" \
  --state-keypair "$state_kp" \
  --idl "$idl_path" \
  --init "$ctor_initial" \
  --delta "$increment_delta" \
  | tee "$tx_dir/invoke.log"
inv_rc=${PIPESTATUS[0]}
set -e
if rg -q '^STATE_PUBKEY=' "$tx_dir/invoke.log" 2>/dev/null; then
  state_pk="$(rg -o 'STATE_PUBKEY=\S+' "$tx_dir/invoke.log" | head -1 | cut -d= -f2)"
fi
if [[ "$inv_rc" -ne 0 ]]; then
  info "WARN: invoke smoke rc=$inv_rc (deploy still ok; need solders in python)"
fi

# --- write UI deployment.json ------------------------------------------------
mkdir -p "$ui_dir/public/artifacts"
cp "$idl_path" "$ui_dir/public/artifacts/${program_name}.idl.json"
# also keep StateCell.idl.json alias for default template load
cp "$idl_path" "$ui_dir/public/artifacts/StateCell.idl.json"

/usr/bin/python3 -I -S - <<PY
import json
from pathlib import Path
idl = json.loads(Path("$idl_path").read_text())
dep = {
  "schema": "proof-forge.pf.solana-local-deployment.v1",
  "program": "$program_name",
  "target": "solana",
  "rpcUrl": "$rpc",
  "programId": "$program_id",
  "stateAccount": "$state_pk",
  "payer": "$payer_pk",
  "idl": idl,
  "ixEncoding": {
    "schema": "proof-forge.solana.ix-data.body-only.v1",
    "profile": "body-only-S1b",
    "layout": "sha256('proof-forge-solana-v1:' + name + '(' + types + ')')[0:8] + params_u64le",
    "note": (
      "StateCell / body-only: first 8 bytes = PF name discriminator (NOT Anchor sighash, "
      "NOT handlerId). init uses disc name 'initialize'. CPI-product programs "
      "(TransferSol) use handlerId u64 LE instead — branch on profile/manifest."
    ),
    "stateLayout": {
      "schema": "proof-forge.solana.state-layout.ordinary.v1",
      "bytes": 16,
      "fields": [
        {"name": "layoutMarker", "offset": 0, "width": 8},
        {"name": "count", "offset": 8, "width": 8},
      ],
    },
  },
  "surfpool": True,
  "notes": [
    "Generated by scripts/pf_solana_local_demo.sh",
    "Local Surfpool only — not public Devnet/Testnet/Mainnet",
    "engineering demo only — not formal/hermetic",
    "init requires state is_signer; use this script (not browser wallet) for init",
  ],
}
Path("$ui_dir/public/deployment.json").write_text(json.dumps(dep, indent=2) + "\\n")
Path("$out_dir/deployment.json").write_text(json.dumps(dep, indent=2) + "\\n")
print("wrote deployment.json")
PY

info "OK"
info "  rpc:        $rpc"
info "  programId:  $program_id"
info "  state:      $state_pk"
info "  artifacts:  $out_dir"
info "  UI config:  $ui_dir/public/deployment.json"
info "  next:       cd templates/solana-dapp-ui && npm install && npm run dev"
if [[ "$keep" == "1" ]]; then
  info "  Surfpool left running (pid $(cat "$surf_dir/pid" 2>/dev/null || echo '?')). Stop: just solana-surfpool-down"
else
  info "  Surfpool will stop on exit (PF_SOLANA_DEMO_KEEP=0)"
fi
info "engineering only — not formal/mainnet"
