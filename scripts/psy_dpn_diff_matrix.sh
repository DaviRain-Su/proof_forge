#!/usr/bin/env bash
# Differential: official psy_user_cli simulate (single-call) vs psy_dpn_session.py
# + multi-step continuity for StateCell / OptionState / Accumulator / WideCounter.
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

build_ex() {
  local name="$1" mod="$2"
  info "build $name"
  "$pf_bin" build "Examples/${name}.lean" --module "$mod" --target psy -o "$out/$name" >&2
  ls "$out/$name"/*.dpn.json | head -1
}

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
  local dpn="$1" method="$2"; shift 2
  local raw="$out/off-${method//[:\/]/_}.raw" js="$out/off-${method//[:\/]/_}.json"
  set +e
  psy_user_cli simulate --circuit-defs-path "$dpn" --method "$method" --format json "$@" \
    >"$raw" 2>&1
  local rc=$?
  set -e
  [[ $rc -eq 0 ]] || { info "official $method rc=$rc"; tail -20 "$raw" >&2; return $rc; }
  extract_json "$raw" "$js"
}

run_session_one() {
  local dpn="$1" method="$2"; shift 2
  local call="$method"
  if [[ $# -gt 0 ]]; then
    local args=()
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--inputs" ]]; then shift; args+=("$1"); shift; continue; fi
      shift
    done
    if [[ ${#args[@]} -gt 0 ]]; then
      local joined; joined=$(IFS=,; echo "${args[*]}")
      call="${method}:${joined}"
    fi
  fi
  local tag="${method//[:\/]/_}"
  python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" --json --call "$call" \
    >"$out/sess-$tag.json"
}

compare_one() {
  local method="$1" off="$2" sess="$3"
  python3 -I -S - "$off" "$sess" "$method" <<'PY'
import json,sys
off=json.load(open(sys.argv[1]))
sess=json.load(open(sys.argv[2]))
method=sys.argv[3]
s=sess["calls"][0]
assert off.get("success") is True, off
assert s.get("success") is True, s
def ints(xs):
    out=[]
    for x in xs or []:
        if isinstance(x,list):
            out.append(int(x[0]) if x else 0)
        else:
            out.append(int(x))
    return out
o_out,s_out=ints(off.get("outputs")),ints(s.get("outputs"))
if o_out!=s_out:
    raise SystemExit(f"FAIL {method} outputs off={o_out} sess={s_out}")
print(f"OK diff {method}: outputs={o_out}")
PY
}

# --- StateCell ---
dpn=$(build_ex StateCell Examples.StateCell)
python3 -I -S "$root/scripts/psy_dpn_to_abi.py" --dpn "$dpn" -o "$out/StateCell/StateCell.abi.json"

info "diff StateCell initialize(7)"
run_official "$dpn" initialize --inputs 7
run_session_one "$dpn" initialize --inputs 7
compare_one initialize "$out/off-initialize.json" "$out/sess-initialize.json"

info "diff StateCell increment(5) empty"
run_official "$dpn" increment --inputs 5
run_session_one "$dpn" increment --inputs 5
compare_one increment "$out/off-increment.json" "$out/sess-increment.json"

info "diff StateCell get empty"
run_official "$dpn" get
run_session_one "$dpn" get
compare_one get "$out/off-get.json" "$out/sess-get.json"

info "session continuity StateCell 7+5=12"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
  --call initialize:7 --call increment:5 --call get | tee "$out/session-sc.log"

# --- OptionState ---
dpn_o=$(build_ex OptionState Examples.OptionState)
info "diff OptionState setSome(42) empty"
run_official "$dpn_o" setSome --inputs 42
run_session_one "$dpn_o" setSome --inputs 42
compare_one setSome "$out/off-setSome.json" "$out/sess-setSome.json"

info "session continuity OptionState setSome/peek/clear"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn_o" \
  --call initialize --call setSome:42 --call peek --call clear --call peek \
  | tee "$out/session-opt.log"
rg -q 'outputs=\[42\]' "$out/session-opt.log"
rg -q 'FINAL slots' "$out/session-opt.log"

# --- Accumulator ---
dpn_a=$(build_ex Accumulator Examples.Accumulator)
info "diff Accumulator add(5) empty"
run_official "$dpn_a" add --inputs 5
run_session_one "$dpn_a" add --inputs 5
compare_one add "$out/off-add.json" "$out/sess-add.json"

info "session continuity Accumulator 10+5=15"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn_a" \
  --call initialize:10 --call add:5 --call current | tee "$out/session-acc.log"
rg -q 'outputs=\[15\]' "$out/session-acc.log"

# --- WideCounter ---
dpn_w=$(build_ex WideCounter Examples.WideCounter)
info "diff WideCounter get empty"
run_official "$dpn_w" get
run_session_one "$dpn_w" get
compare_one getw "$out/off-get.json" "$out/sess-get.json" || true
# re-run with unique names
run_official "$dpn_w" get
extract_json "$out/off-get.raw" "$out/off-wc-get.json" 2>/dev/null || \
  python3 -I -S -c "import json;t=open('$out/off-get.raw',errors='replace').read();i,j=t.find('{'),t.rfind('}');json.dump(json.loads(t[i:j+1]),open('$out/off-wc-get.json','w'),indent=2)"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn_w" --json --call get >"$out/sess-wc-get.json"
compare_one WideCounter.get "$out/off-wc-get.json" "$out/sess-wc-get.json"

info "session continuity WideCounter init+add+get"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn_w" \
  --call initialize:1,0,0,0 --call add:2,0,0,0 --call get | tee "$out/session-wc.log"
rg -q 'outputs=\[3, 0, 0, 0\]' "$out/session-wc.log"

# coverage report from built artifacts
python3 -I -S "$root/scripts/psy_dpn_op_coverage.py" \
  --artifact-root "$out" -o "$out/psy-op-coverage.v1.json"

info "OK differential matrix + multi-example continuity + coverage"
echo "artifacts: $out"
