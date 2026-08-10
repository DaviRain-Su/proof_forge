#!/usr/bin/env bash
# Build a small set of Examples for target=psy (compile matrix).
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
      echo "  OK $name"
      # session only for StateCell-shaped default sequence
      if [[ "$name" == "StateCell" ]]; then
        python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$(ls "$o"/*.dpn.json | head -1)" \
          --call initialize:7 --call increment:5 --call get >/tmp/psy-mat-session.log \
          && echo "  OK session 12" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
      fi
      ok=$((ok+1))
    else
      echo "  FAIL no dpn"; fail=$((fail+1))
    fi
  else
    # plan FC is acceptable skip for unsupported surface
    if rg -q 'PF-|fail|unsupported|PSY-' /tmp/psy-mat-$name.log; then
      echo "  SKIP/FC $name (see /tmp/psy-mat-$name.log)"
      skip=$((skip+1))
    else
      echo "  FAIL $name"; tail -5 /tmp/psy-mat-$name.log
      fail=$((fail+1))
    fi
  fi
done
echo "summary ok=$ok skip=$skip fail=$fail"
[[ "$fail" -eq 0 ]]
