#!/usr/bin/env bash
# Differential: official psy_user_cli simulate (single-call) vs psy_dpn_session.py
# + multi-step continuity for StateCell / OptionState / Accumulator / WideCounter / MapMini / EmitProbe.
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
assert i>=0 and j>i, sys.argv[1]
json.dump(json.loads(t[i:j+1]), open(sys.argv[2],'w'), indent=2)
" "$1" "$2"
}

# Unique tag for output files (avoids method-name collisions across packages)
run_official() {
  local tag="$1" dpn="$2" method="$3"; shift 3
  local raw="$out/off-${tag}.raw" js="$out/off-${tag}.json"
  set +e
  psy_user_cli simulate --circuit-defs-path "$dpn" --method "$method" --format json "$@" \
    >"$raw" 2>&1
  local rc=$?
  set -e
  [[ $rc -eq 0 ]] || { info "official $tag rc=$rc"; tail -30 "$raw" >&2; return $rc; }
  extract_json "$raw" "$js"
}

run_session_one() {
  local tag="$1" dpn="$2" method="$3"; shift 3
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
  python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" --json --call "$call" \
    >"$out/sess-${tag}.json"
}

compare_outputs() {
  local tag="$1" off="$2" sess="$3"
  python3 -I -S - "$off" "$sess" "$tag" <<'PY'
import json,sys
off=json.load(open(sys.argv[1]))
sess=json.load(open(sys.argv[2]))
tag=sys.argv[3]
s=sess["calls"][0]
assert off.get("success") is True, (tag, off)
assert s.get("success") is True, (tag, s)
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
    raise SystemExit(f"FAIL {tag} outputs off={o_out} sess={s_out}")
print(f"OK diff {tag}: outputs={o_out}")
PY
}

# Compare non-zero leaf writes: map official state_delta / writes → {slot:new}
# vs session physical slots after one call (fresh session).
compare_nonzero_writes() {
  local tag="$1" off="$2" sess="$3"
  python3 -I -S - "$off" "$sess" "$tag" <<'PY'
import json,sys
from collections import defaultdict
off=json.load(open(sys.argv[1]))
sess=json.load(open(sys.argv[2]))
tag=sys.argv[3]
s=sess["calls"][0]
# official: last write wins per slot_index among condition=true writes
off_slots={}
for w in off.get("state_writes") or []:
    if not w.get("condition", True):
        continue
    slot=int(w.get("slot_index",0))
    nv=w.get("new_value") or [0]
    off_slots[slot]=int(nv[0] if isinstance(nv,list) else nv)
# session: physical leaves from writes
sess_slots={}
for w in s.get("state_writes") or []:
    slot=int(w.get("slot_index",0))
    nv=w.get("new_value") or [0]
    sess_slots[slot]=int(nv[0] if isinstance(nv,list) else nv)
# compare only keys where either side nonzero (or both present)
keys=set(off_slots)|set(sess_slots)
mism=[]
for k in sorted(keys):
    o=off_slots.get(k,0); ss=sess_slots.get(k,0)
    if o!=ss:
        mism.append((k,o,ss))
if mism:
    raise SystemExit(f"FAIL {tag} writes mismatch {mism} off={off_slots} sess={sess_slots}")
print(f"OK diff {tag}: nonzero-aligned writes off={ {k:v for k,v in off_slots.items() if v} }")
PY
}

diff_pair() {
  local tag="$1" dpn="$2" method="$3"; shift 3
  info "diff $tag"
  run_official "$tag" "$dpn" "$method" "$@"
  run_session_one "$tag" "$dpn" "$method" "$@"
  compare_outputs "$tag" "$out/off-${tag}.json" "$out/sess-${tag}.json"
}

# --- StateCell ---
dpn=$(build_ex StateCell Examples.StateCell)
python3 -I -S "$root/scripts/psy_dpn_to_abi.py" --dpn "$dpn" -o "$out/StateCell/StateCell.abi.json"

diff_pair sc-init "$dpn" initialize --inputs 7
diff_pair sc-inc "$dpn" increment --inputs 5
diff_pair sc-get "$dpn" get

info "session continuity StateCell 7+5=12"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
  --call initialize:7 --call increment:5 --call get | tee "$out/session-sc.log"
rg -q 'outputs=\[12\]' "$out/session-sc.log"

# --- OptionState ---
dpn_o=$(build_ex OptionState Examples.OptionState)
diff_pair opt-setSome "$dpn_o" setSome --inputs 42
compare_nonzero_writes opt-setSome-writes \
  "$out/off-opt-setSome.json" "$out/sess-opt-setSome.json"

info "session continuity OptionState setSome/peek/clear"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn_o" \
  --call initialize --call setSome:42 --call peek --call clear --call peek \
  | tee "$out/session-opt.log"
rg -q 'outputs=\[42\]' "$out/session-opt.log"

# --- Accumulator ---
dpn_a=$(build_ex Accumulator Examples.Accumulator)
diff_pair acc-add "$dpn_a" add --inputs 5

info "session continuity Accumulator 10+5=15"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn_a" \
  --call initialize:10 --call add:5 --call current | tee "$out/session-acc.log"
rg -q 'outputs=\[15\]' "$out/session-acc.log"

# --- WideCounter ---
dpn_w=$(build_ex WideCounter Examples.WideCounter)
diff_pair wc-get "$dpn_w" get
diff_pair wc-init "$dpn_w" initialize --inputs 1 --inputs 0 --inputs 0 --inputs 0
compare_nonzero_writes wc-init-writes \
  "$out/off-wc-init.json" "$out/sess-wc-init.json"

info "session continuity WideCounter init+add+get"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn_w" \
  --call initialize:1,0,0,0 --call add:2,0,0,0 --call get | tee "$out/session-wc.log"
rg -q 'outputs=\[3, 0, 0, 0\]' "$out/session-wc.log"

# --- MapMini (P1) ---
dpn_m=$(build_ex MapMini Examples.MapMini)
python3 -I -S "$root/scripts/psy_dpn_to_abi.py" --dpn "$dpn_m" -o "$out/MapMini/MapMini.abi.json"

diff_pair map-put "$dpn_m" put --inputs 1 --inputs 99
compare_nonzero_writes map-put-writes \
  "$out/off-map-put.json" "$out/sess-map-put.json"

diff_pair map-get-empty "$dpn_m" get --inputs 1

info "session continuity MapMini multi-key"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn_m" \
  --call initialize \
  --call put:1,99 --call put:2,77 --call put:1,55 \
  --call get:1 --call get:2 --call get:3 \
  | tee "$out/session-map.log"
# get:1 after overwrite → 55; get:2 → 77; get:3 → 0
python3 -I -S - "$out/session-map.log" <<'PY'
import sys,re
t=open(sys.argv[1]).read()
# lines like OK get([1]) outputs=[55]
gets=re.findall(r"OK get\(\[(\d+)\]\) outputs=\[(\d+)\]", t)
m={int(k):int(v) for k,v in gets}
assert m.get(1)==55, m
assert m.get(2)==77, m
assert m.get(3)==0, m
print("OK map multi-key continuity", m)
PY

# Official single-call put after fresh process cannot see prior puts; still
# verify a second key put alone writes occ/key/val for first empty slot.
diff_pair map-put2 "$dpn_m" put --inputs 2 --inputs 77
compare_nonzero_writes map-put2-writes \
  "$out/off-map-put2.json" "$out/sess-map-put2.json"

# --- EmitProbe (event PARTIAL surface) ---
dpn_e=$(build_ex EmitProbe Examples.EmitProbe)
diff_pair emit-ping "$dpn_e" ping --inputs 5
python3 -I -S - "$out/off-emit-ping.json" "$out/sess-emit-ping.json" <<'PYE'
import json,sys
off=json.load(open(sys.argv[1]))
sess=json.load(open(sys.argv[2]))
s=sess["calls"][0]
assert off.get("success") and s.get("success")
o_ev=off.get("events") or []
s_ev=s.get("events") or []
assert len(o_ev)>=1 and len(s_ev)>=1, (o_ev,s_ev)
assert [int(x) for x in o_ev[0].get("data") or []] == [int(x) for x in s_ev[0].get("data") or []]
assert int(o_ev[0].get("user_id",0))==int(s_ev[0].get("user_id",0))
assert int(o_ev[0].get("contract_id",0))==int(s_ev[0].get("contract_id",0))
print(f"OK diff emit-ping events data={o_ev[0].get('data')} user={o_ev[0].get('user_id')}")
PYE

info "session continuity EmitProbe init+ping+get"
python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn_e" \
  --call initialize:0 --call ping:5 --call get | tee "$out/session-emit.log"
rg -q 'outputs=\[5\]' "$out/session-emit.log"

# coverage report from built artifacts
python3 -I -S "$root/scripts/psy_dpn_op_coverage.py" \
  --artifact-root "$out" -o "$out/psy-op-coverage.v1.json"
# also refresh docs copy when matrix succeeds
python3 -I -S "$root/scripts/psy_dpn_op_coverage.py" \
  --artifact-root "$out" -o "$root/docs/targets/psy-op-coverage.v1.json"

info "OK differential matrix + MapMini multi-key + EmitProbe events + coverage"
echo "artifacts: $out"
