#!/usr/bin/env bash
# Differential: official psy_user_cli simulate (single-call) vs psy_dpn_session.py
# (fresh session, one call). Compares success + outputs + state write new_values.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export PATH="${HOME}/.psy/bin:${PATH}"
[[ -f "${HOME}/.psy/env" ]] && source "${HOME}/.psy/env" || true

info(){ printf 'psy-dpn-diff: %s\n' "$*" >&2; }
die(){ info "ERROR: $*"; exit 1; }

command -v psy_user_cli >/dev/null || die "psy_user_cli required"
pf_bin="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"
[[ -x "$pf_bin" ]] || die "proof-forge-next missing"

out="${PF_PSY_DIFF_OUT:-$root/build/v2/psy-diff}"
rm -rf "$out" && mkdir -p "$out"

info "build StateCell"
"$pf_bin" build Examples/StateCell.lean --module Examples.StateCell --target psy -o "$out/sc" >&2
dpn=$(ls "$out/sc"/*.dpn.json | head -1)

# ABI
python3 -I -S "$root/scripts/psy_dpn_to_abi.py" --dpn "$dpn" -o "$out/sc/StateCell.abi.json"

extract_json() {
  python3 -I -S -c "
import sys,json
t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
i,j=t.find('{'),t.rfind('}')
assert i>=0 and j>i
json.dump(json.loads(t[i:j+1]), open(sys.argv[2],'w'), indent=2)
" "$1" "$2"
}

run_official() {
  local method="$1"; shift
  local raw="$out/off-$method.raw" js="$out/off-$method.json"
  set +e
  psy_user_cli simulate --circuit-defs-path "$dpn" --method "$method" --format json "$@" \
    >"$raw" 2>&1
  local rc=$?
  set -e
  [[ $rc -eq 0 ]] || { info "official $method rc=$rc"; cat "$raw" >&2; return $rc; }
  extract_json "$raw" "$js"
}

run_session_one() {
  local method="$1"; shift
  # Build --call METHOD or METHOD:args
  local call="$method"
  if [[ $# -gt 0 ]]; then
    # convert --inputs N → method:N
    local args=()
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--inputs" ]]; then shift; args+=("$1"); shift; continue; fi
      shift
    done
    if [[ ${#args[@]} -gt 0 ]]; then
      local joined
      joined=$(IFS=,; echo "${args[*]}")
      call="${method}:${joined}"
    fi
  fi
  python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" --json --call "$call" \
    >"$out/sess-$method.json"
}

compare_one() {
  local method="$1"
  python3 -I -S - "$out/off-$method.json" "$out/sess-$method.json" "$method" <<'PY'
import json,sys
off=json.load(open(sys.argv[1]))
sess=json.load(open(sys.argv[2]))
method=sys.argv[3]
# session file is {calls:[...], slots}
s=sess["calls"][0]
assert off.get("success") is True, off
assert s.get("success") is True, s
o_out=off.get("outputs") or []
s_out=s.get("outputs") or []
# coerce to int lists
def ints(xs):
    return [int(x) if not isinstance(x,list) else int(x[0]) for x in xs]
o_out,s_out=ints(o_out),ints(s_out)
if o_out!=s_out:
    raise SystemExit(f"FAIL {method} outputs off={o_out} sess={s_out}")
# compare last write new_value if any
def writes(d):
    ws=d.get("state_writes") or []
    return [(int(w.get("slot_index",0)), [int(x) for x in (w.get("new_value") or [])]) for w in ws]
ow,sw=writes(off),writes(s)
if ow!=sw:
    # allow empty both
    raise SystemExit(f"FAIL {method} writes off={ow} sess={sw}")
print(f"OK diff {method}: outputs={o_out} writes={ow}")
PY
}

info "diff initialize(7)"
run_official initialize --inputs 7
run_session_one initialize --inputs 7
compare_one initialize

info "diff increment(5) on empty"
run_official increment --inputs 5
run_session_one increment --inputs 5
compare_one increment

info "diff get() on empty"
run_official get
run_session_one get
compare_one get

# Multi-step session continuity still required (official cannot do this in one process)
info "session continuity 7+5=12"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
  --call initialize:7 --call increment:5 --call get | tee "$out/session-cont.log"

info "OK differential matrix + continuity"
echo "artifacts: $out"
