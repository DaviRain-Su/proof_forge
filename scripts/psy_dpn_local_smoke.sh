#!/usr/bin/env bash
# Host-optional: build PF StateCell → DPN, execute via official psy_user_cli simulate.
# Engineering only — not UPS/proof/network/deploy/formal.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

info() { printf 'psy-dpn-local-smoke: %s\n' "$*" >&2; }
die() { info "ERROR: $*"; exit 1; }

if [[ -x "${HOME}/.psy/bin/psy_user_cli" ]]; then
  export PATH="${HOME}/.psy/bin:${PATH}"
fi
if [[ -f "${HOME}/.psy/env" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.psy/env" || true
fi

command -v psy_user_cli >/dev/null 2>&1 \
  || die "psy_user_cli missing — install via psyup (https://github.com/QEDProtocol/psyup)"

pf_bin="${PROOF_FORGE_CLI:-}"
if [[ -z "$pf_bin" && -x "$root/.lake/build/bin/proof-forge-next" ]]; then
  pf_bin="$root/.lake/build/bin/proof-forge-next"
fi
if [[ -z "$pf_bin" ]] && command -v proof-forge-next >/dev/null 2>&1; then
  pf_bin="$(command -v proof-forge-next)"
fi
[[ -n "$pf_bin" && -x "$pf_bin" ]] || die "proof-forge-next not found (set PROOF_FORGE_CLI)"

out="${PF_PSY_OUT:-$root/build/v2/psy-dpn-smoke}"
src="${PF_PSY_SOURCE:-Examples/StateCell.lean}"
mod="${PF_PSY_MODULE:-Examples.StateCell}"
rm -rf "$out"
mkdir -p "$(dirname "$out")"

info "build $src → $out (target=psy)"
"$pf_bin" build "$src" --module "$mod" --target psy -o "$out" >&2

dpn="$(find "$out" -maxdepth 1 -name '*.dpn.json' | head -1)"
[[ -n "$dpn" && -f "$dpn" ]] || die "no *.dpn.json under $out"
info "dpn=$dpn"
info "psy_user_cli=$(command -v psy_user_cli)"

log_dir="$out/simulate-logs"
mkdir -p "$log_dir"

# psy_user_cli prints tracing logs on stdout before JSON — strip to first object.
sim_to() {
  local method="$1" dest="$2"; shift 2
  local raw
  raw="$(mktemp "${TMPDIR:-/tmp}/pf-psy-sim.XXXXXX")"
  # shellcheck disable=SC2068
  psy_user_cli simulate \
    --circuit-defs-path "$dpn" \
    --method "$method" \
    --format json \
    $@ >"$raw" 2>&1 || {
      cat "$raw" >&2
      rm -f "$raw"
      die "simulate $method failed"
    }
  /usr/bin/python3 -I -S -c "
import sys
raw=open(sys.argv[1],encoding='utf-8',errors='replace').read()
i=raw.find('{'); j=raw.rfind('}')
if i<0 or j<=i: raise SystemExit('no json object in simulate output')
open(sys.argv[2],'w',encoding='utf-8').write(raw[i:j+1]+'\n')
" "$raw" "$dest"
  rm -f "$raw"
}

check_json() {
  local path="$1" expect="$2"
  /usr/bin/python3 -I -S -c "
import json,sys
path, expect = sys.argv[1], sys.argv[2]
d=json.load(open(path))
assert d.get('success') is True, d
if expect.startswith('write:'):
    want=int(expect.split(':',1)[1])
    writes=d.get('state_writes') or []
    assert writes, d
    nv=writes[0].get('new_value') or []
    assert nv and int(nv[0])==want, d
    print(f'OK write slot -> {want}')
elif expect.startswith('out:'):
    want=int(expect.split(':',1)[1])
    outs=d.get('outputs') or []
    assert outs and int(outs[0])==want, d
    print(f'OK output -> {want}')
else:
    raise SystemExit(f'bad expect {expect}')
" "$path" "$expect"
}

info "simulate initialize(7)"
sim_to initialize "$log_dir/initialize.json" --inputs 7
check_json "$log_dir/initialize.json" "write:7"

info "simulate increment(5) on fresh state (0+5)"
sim_to increment "$log_dir/increment.json" --inputs 5
check_json "$log_dir/increment.json" "out:5"

info "simulate get() on fresh state"
sim_to get "$log_dir/get.json"
check_json "$log_dir/get.json" "out:0"

info "OK official DPN VM executed PF package"
info "  note: each simulate uses fresh InMemoryStateBackend (no multi-tx session)"
info "  deploy (official, not pf): psy_user_cli deploy-contract --contract-path <dpn>"
info "engineering only — not formal/hermetic/mainnet"
