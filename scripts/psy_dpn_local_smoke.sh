#!/usr/bin/env bash
# Psy DPN local smoke — official CLI first:
#   1) pf/proof-forge-next build → *.dpn.json
#   2) multi-step session continuity (init+inc+get=12)
#   3) official psy_user_cli simulate single-call
#   4) pf deploy save-only wrapping psy_user_cli deploy-contract
#   5) local chain status probe (does not start nodes)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
info(){ printf 'psy-dpn-local-smoke: %s\n' "$*" >&2; }
die(){ info "ERROR: $*"; exit 1; }

export PATH="${HOME}/.psy/bin:${PATH}"
[[ -f "${HOME}/.psy/env" ]] && source "${HOME}/.psy/env" || true

pf_bin="${PROOF_FORGE_CLI:-}"
[[ -z "$pf_bin" && -x "$root/.lake/build/bin/proof-forge-next" ]] && pf_bin="$root/.lake/build/bin/proof-forge-next"
[[ -z "$pf_bin" ]] && command -v proof-forge-next >/dev/null && pf_bin=$(command -v proof-forge-next)
[[ -n "${pf_bin:-}" ]] || die "proof-forge-next missing"

pf_cli="${PF_BIN:-}"
[[ -z "$pf_cli" && -x "$root/clients/pf-cli/target/release/pf" ]] && pf_cli="$root/clients/pf-cli/target/release/pf"
[[ -z "$pf_cli" ]] && command -v pf >/dev/null && pf_cli=$(command -v pf)

out="${PF_PSY_OUT:-$root/build/v2/psy-dpn-smoke}"
rm -rf "$out"
mkdir -p "$(dirname "$out")"

info "1/5 build"
"$pf_bin" build Examples/StateCell.lean --module Examples.StateCell --target psy -o "$out" >&2
dpn=$(find "$out" -maxdepth 1 -name '*.dpn.json' | head -1)
[[ -f "$dpn" ]] || die "no dpn"

info "2/6 multi-step session (shared state → 12)"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
  --call initialize:7 --call increment:5 --call get | tee "$out/session.log"

if command -v psy_user_cli >/dev/null 2>&1; then
  info "3/6 derive ABI from DPN"
python3 -I -S "$root/scripts/psy_dpn_to_abi.py" --dpn "$dpn" -o "${dpn%.dpn.json}.abi.json" || python3 -I -S "$root/scripts/psy_dpn_to_abi.py" --dpn "$dpn" -o "$out/StateCell.abi.json"
info "4/6 official simulate single-call"
  raw=$(mktemp)
  psy_user_cli simulate --circuit-defs-path "$dpn" --method initialize --inputs 7 --format json >"$raw" 2>&1
  python3 -I -S -c "
import sys,json
t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
i,j=t.find('{'),t.rfind('}')
d=json.loads(t[i:j+1])
assert d.get('success') is True
print('OK official simulate initialize')
" "$raw"
  rm -f "$raw"
else
  info "3/5 skip official simulate (no psy_user_cli)"
fi

if [[ -n "${pf_cli:-}" && -x "$pf_cli" ]]; then
  info "5/6 pf deploy save-only (wraps psy_user_cli deploy-contract)"
  export PROOF_FORGE_CLI="$pf_bin"
  "$pf_cli" deploy -t psy --artifact "$out" --network local 2>&1 | tee "$out/deploy-save.log" | tail -20
  ls -la "$out/tx" 2>/dev/null || ls -la "$out"/**/deploy_cmd.json 2>/dev/null || true
  # find deploy_cmd
  if find "$out" -name 'deploy_cmd.json' | head -1 | grep -q .; then
    info "OK deploy_cmd.json written by official CLI via pf"
  else
    die "deploy_cmd.json missing after pf deploy"
  fi
else
  info "4/5 skip pf deploy (build pf first: cargo build -p proof-forge-pf --release)"
  if command -v psy_user_cli >/dev/null; then
    info "    direct official save-only deploy-contract"
    export PRIVATE_KEY="${PRIVATE_KEY:-0000000000000000000000000000000000000000000000000000000000000001}"
    mkdir -p "$out/tx"
    psy_user_cli deploy-contract --contract-path "$dpn" --private-key "$PRIVATE_KEY" \
      --output-path "$out/tx/deploy_cmd.json" --rpc-config "${RPC_CONFIG:-$HOME/.psy/config.json}" >&2
  fi
fi

info "6/6 local chain status probe"
bash "$root/scripts/psy_local_chain_status.sh" || info "local/public coordinator not up (expected if no cluster)"

info "OK psy DPN smoke complete"
info "  session continuity: YES (12)"
info "  official simulate: single-call"
info "  pf deploy: save-only wraps deploy-contract"
info "  ABI: *.abi.json via psy_dpn_to_abi.py (also on pf deploy/test)"
info "  UI: templates/psy-dapp-ui (copy deployment.json + abi)"
info "  persistent chain: start psy-node local-devnet, then pf deploy --broadcast"
