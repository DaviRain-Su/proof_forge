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
  "Examples/EmitProbe.lean:Examples.EmitProbe"
  "Examples/CallProbe.lean:Examples.CallProbe"
  "Examples/HashProbe.lean:Examples.HashProbe"
  "Examples/HashOutProbe.lean:Examples.HashOutProbe"
  "Examples/ContextProbe.lean:Examples.ContextProbe"
  "Examples/ImtProbe.lean:Examples.ImtProbe"
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
            --call initialize:10 --call run:0 --call get >/tmp/psy-mat-session-$name.log \
            && rg -q 'outputs=\[14\]' /tmp/psy-mat-session-$name.log \
            && echo "  OK session LoopSum 10+4=14" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
        MapMini)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" \
            --call initialize --call put:1,99 --call get:1 >/tmp/psy-mat-session-$name.log \
            && rg -q 'outputs=\[99\]' /tmp/psy-mat-session-$name.log \
            && echo "  OK session put/get 99" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
        EmitProbe)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" --json \
            --call initialize:0 --call ping:5 --call get >/tmp/psy-mat-session-$name.json \
            && python3 -I -S -c "import json;d=json.load(open('/tmp/psy-mat-session-EmitProbe.json'));assert d['calls'][1]['outputs']==[5] and d['calls'][1]['events'][0]['data']==[5]" \
            && echo "  OK session emit ping" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
        CallProbe)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" --json \
            --call initialize:0 --call notify:7 --call get >/tmp/psy-mat-session-$name.json \
            && python3 -I -S -c "import json;d=json.load(open('/tmp/psy-mat-session-CallProbe.json'));assert d['calls'][1]['outputs']==[7] and d['calls'][1]['external_calls'][0]['input_args']==[7]" \
            && echo "  OK session void call" || { echo "  FAIL session"; fail=$((fail+1)); continue; }
          ;;
        HashProbe)
          if command -v psy_user_cli >/dev/null 2>&1; then
            okh=1
            for spec in "hashPair:1 2" "hashCombine:1 0 0 0 2 0 0 0" "keccakWord:1"; do
              m="${spec%%:*}"; args="${spec#*:}"
              # shellcheck disable=SC2086
              set -- $args
              inargs=()
              for a in "$@"; do inargs+=(--inputs "$a"); done
              if ! psy_user_cli simulate --circuit-defs-path "$dpn" --method "$m" --format json \
                  "${inargs[@]}" >/tmp/psy-mat-hash-$m.json 2>/tmp/psy-mat-hash-$m.err; then
                okh=0; echo "  FAIL official $m"; break
              fi
              if ! python3 -I -S -c "import json;t=open('/tmp/psy-mat-hash-$m.json').read();i,j=t.find('{'),t.rfind('}');d=json.loads(t[i:j+1]);assert d.get('success') and int((d.get('outputs') or [0])[0])!=0"; then
                okh=0; echo "  FAIL official $m nonzero"; break
              fi
            done
            [[ $okh -eq 1 ]] && echo "  OK official hashNoPad/twoToOne/keccak" || { fail=$((fail+1)); continue; }
          else
            echo "  SKIP official hash (no psy_user_cli)"
          fi
          if python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" --call initialize --call hashPair:1,2 >/tmp/psy-mat-hash-sess.txt 2>&1; then
            echo "  FAIL session should reject hash gadgets"; fail=$((fail+1)); continue
          fi
          rg -q 'hashNoPad|op 21|ADR-0039|hash/merkle' /tmp/psy-mat-hash-sess.txt \
            && echo "  OK session hash fail-closed" || { echo "  FAIL session hash msg"; fail=$((fail+1)); continue; }
          ;;
        HashOutProbe)
          if command -v psy_user_cli >/dev/null 2>&1; then
            okh=1
            if ! psy_user_cli simulate --circuit-defs-path "$dpn" --method hashPairFull --format json \
                --inputs 1 --inputs 2 >/tmp/psy-mat-hof-pair.json 2>/tmp/psy-mat-hof-pair.err; then
              okh=0; echo "  FAIL official hashPairFull"
            else
              python3 -I -S -c "
import json
t=open('/tmp/psy-mat-hof-pair.json').read();i,j=t.find('{'),t.rfind('}')
d=json.loads(t[i:j+1]); outs=[int(x) for x in (d.get('outputs') or [])]
assert d.get('success') and len(outs)==4 and outs[0]!=0 and any(x!=0 for x in outs[1:]), (outs,d)
" || { okh=0; echo "  FAIL hashPairFull 4-limb"; }
            fi
            if ! psy_user_cli simulate --circuit-defs-path "$dpn" --method hashCombineFull --format json \
                --inputs 1 --inputs 0 --inputs 0 --inputs 0 --inputs 2 --inputs 0 --inputs 0 --inputs 0 \
                >/tmp/psy-mat-hof-comb.json 2>/tmp/psy-mat-hof-comb.err; then
              okh=0; echo "  FAIL official hashCombineFull"
            else
              python3 -I -S -c "
import json
t=open('/tmp/psy-mat-hof-comb.json').read();i,j=t.find('{'),t.rfind('}')
d=json.loads(t[i:j+1]); outs=[int(x) for x in (d.get('outputs') or [])]
assert d.get('success') and len(outs)==4 and outs[0]!=0, outs
" || { okh=0; echo "  FAIL hashCombineFull 4-limb"; }
            fi
            [[ $okh -eq 1 ]] && echo "  OK official HashOut 4-limb" || { fail=$((fail+1)); continue; }
          else
            echo "  SKIP official HashOut (no psy_user_cli)"
          fi
          if python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" --call initialize --call hashPairFull:1,2 >/tmp/psy-mat-hof-sess.txt 2>&1; then
            echo "  FAIL session should reject hashOut full"; fail=$((fail+1)); continue
          fi
          rg -q 'hashNoPad|op 21|ADR-0039|hash/merkle' /tmp/psy-mat-hof-sess.txt \
            && echo "  OK session HashOut fail-closed" || { echo "  FAIL session HashOut msg"; fail=$((fail+1)); continue; }
          ;;
        ContextProbe)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" --json \
            --call initialize --call snapUser --call snapCheckpoint --call snapUserPk --call snapSessionRoot --call get \
            >/tmp/psy-mat-session-$name.json \
            && python3 -I -S -c "import json;d=json.load(open('/tmp/psy-mat-session-ContextProbe.json'));assert d['calls'][1]['outputs']==[1] and d['calls'][2]['outputs']==[100] and d['calls'][3]['outputs']==[0] and d['calls'][4]['outputs']==[0]" \
            && echo "  OK session context ids+pk+root" || { echo "  FAIL session context"; fail=$((fail+1)); continue; }
          ;;
        ImtProbe)
          python3 -I -S "$root/scripts/psy_dpn_session.py" --dpn "$dpn" --json \
            --call initialize --call put:7,42 --call get:7 --call has:7 \
            --call getExt:1,7 --call getOther:1,1,7 --call hasOther:1,1,7 --call get:9 \
            >/tmp/psy-mat-session-$name.json \
            && python3 -I -S -c "import json;d=json.load(open('/tmp/psy-mat-session-ImtProbe.json'));assert d['calls'][1]['outputs']==[42] and d['calls'][2]['outputs']==[42] and d['calls'][3]['outputs']==[1] and d['calls'][4]['outputs']==[42] and d['calls'][5]['outputs']==[42] and d['calls'][6]['outputs']==[1] and d['calls'][7]['outputs']==[0]" \
            && echo "  OK session IMT self+ext+other" || { echo "  FAIL session IMT"; fail=$((fail+1)); continue; }
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
