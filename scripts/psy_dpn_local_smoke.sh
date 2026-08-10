#!/usr/bin/env bash
# Host-optional Psy DPN local smoke:
#   1) pf build → *.dpn.json
#   2) multi-step session: initialize(7)→increment(5)→get  expect 12
#   3) optional single-call official psy_user_cli simulate (process-isolated)
#
# IMPORTANT: official `psy_user_cli simulate` is ONE method per process with a
# fresh InMemoryStateBackend. Three separate simulates cannot show 7+5=12.
# Continuity is scripts/psy_dpn_session.py (IDE/WASM-style commit loop).
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

info "multi-step session (shared state): init(7)+inc(5)+get → 12"
/usr/bin/python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
  --call initialize:7 --call increment:5 --call get \
  | tee "$out/session.log"

# Optional: prove official CLI still accepts the package (single-call only)
if command -v psy_user_cli >/dev/null 2>&1; then
  info "official simulate single-call sanity (fresh state each time — NOT a sequence)"
  raw="$(mktemp)"
  psy_user_cli simulate --circuit-defs-path "$dpn" --method initialize --inputs 7 --format json \
    >"$raw" 2>&1 || { cat "$raw" >&2; die "official simulate failed"; }
  /usr/bin/python3 -I -S -c "
import sys
raw=open(sys.argv[1],encoding='utf-8',errors='replace').read()
i,j=raw.find('{'),raw.rfind('}')
import json
d=json.loads(raw[i:j+1])
assert d.get('success') is True, d
w=d.get('state_writes') or []
assert w and int(w[0]['new_value'][0])==7, d
print('OK official simulate initialize(7) alone')
" "$raw"
  rm -f "$raw"
else
  info "skip official simulate (psy_user_cli not on PATH)"
fi

info "OK"
info "  continuity: scripts/psy_dpn_session.py (expect 12)"
info "  official single-call: psy_user_cli simulate (expect fresh state)"
info "  deploy: psy_user_cli deploy-contract --contract-path <dpn> (not pf)"
info "engineering only — not formal/hermetic/mainnet"
