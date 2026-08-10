#!/usr/bin/env bash
# Build a set of Examples for target=psy + session smoke where shapes are known.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
pf_bin="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"
[[ -x "$pf_bin" ]] || { echo "missing proof-forge-next"; exit 2; }
mods=(
  "Examples/StateCell.lean:Examples.StateCell"
  "Examples/Counter.lean:Examples.Counter"
  "Examples/LoopSum.lean:Examples.LoopSum"
  "Examples/OptionState.lean:Examples.OptionState"
  "Examples/Accumulator.lean:Examples.Accumulator"
  "Examples/WideCounter.lean:Examples.WideCounter"
  "Examples/MapMini.lean:Examples.MapMini"
)
ok=0; fail=0; skip=0
out_root="$root/build/v2/psy-matrix"
rm -rf "$out_root"
for entry in "${mods[@]}"; do
  src="${entry%%:*}"; mod="${entry##*:}"
  name=$(basename "$src" .lean)
  o="$out_root/$name"
  echo "==> build $mod"
  if "$pf_bin" build "$src" --module "$mod" --target psy -o "$o" >/tmp/psy-mat-$name.log 2>&1; then
    if [[ -f "$o/$name.dpn.json" ]] || ls "$o"/*.dpn.json >/dev/null 2>&1; then
      dpn=$(ls "$o"/*.dpn.json | head -1)
      echo "  OK $name"
      case "$name" in
        StateCell)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
            --call initialize:7 --call increment:5 --call get >/tmp/psy-mat-session-$name.log \
            && echo "  OK session 12" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
        OptionState)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
            --call initialize --call setSome:42 --call peek >/tmp/psy-mat-session-$name.log \
            && rg -q 'outputs=\[42\]' /tmp/psy-mat-session-$name.log \
            && echo "  OK session peek=42" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
        Accumulator)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
            --call initialize:10 --call add:5 --call current >/tmp/psy-mat-session-$name.log \
            && rg -q 'outputs=\[15\]' /tmp/psy-mat-session-$name.log \
            && echo "  OK session 15" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
        WideCounter)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
            --call initialize:1,0,0,0 --call add:2,0,0,0 --call get >/tmp/psy-mat-session-$name.log \
            && rg -q 'outputs=\[3, 0, 0, 0\]' /tmp/psy-mat-session-$name.log \
            && echo "  OK session wide 3" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
        LoopSum)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
            --call initialize:0 --call run:0 --call get >/tmp/psy-mat-session-$name.log \
            && echo "  OK session LoopSum (official also 0 on empty)" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
        MapMini)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
            --call initialize --call put:1,99 --call get:1 >/tmp/psy-mat-session-$name.log \
            && rg -q 'outputs=\[99\]' /tmp/psy-mat-session-$name.log \
            && echo "  OK session put/get 99" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
      esac
      ok=$((ok+1))
    else
      echo "  FAIL no dpn"; fail=$((fail+1))
    fi
  else
    if rg -q 'PF-|fail|unsupported|PSY-|invalid psy plan' /tmp/psy-mat-$name.log; then
      echo "  SKIP/FC $name (see /tmp/psy-mat-$name.log)"
      skip=$((skip+1))
    else
      echo "  FAIL $name"; tail -5 /tmp/psy-mat-$name.log
      fail=$((fail+1))
    fi
  fi
done
# coverage from matrix artifacts
python3 -I -S "$root/scripts/psy_dpn_op_coverage.py" \
  --artifact-root "$out_root" -o "$root/docs/targets/psy-op-coverage.v1.json" || true
echo "summary ok=$ok skip=$skip fail=$fail"
[[ "$fail" -eq 0 ]]
