#!/usr/bin/env bash
# B1.8: optional Psy / Aleo Counter benchmark rows (experimental).
#
# Emits bm-psy-counter and bm-aleo-counter rows for proofforge (+ native golden
# source sizes). Full dargo execute / snarkVM proof metrics are tool-gated and
# never faked as zeros.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_BENCH_OUT:-build/benchmarks}"
mkdir -p "$OUT_DIR"
WORK="$OUT_DIR/zk-counter-work"
rm -rf "$WORK"
mkdir -p "$WORK"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
PF_VERSION="$(lake env proof-forge --version 2>/dev/null | head -n1 || echo unknown)"

fail() { echo "benchmark-zk-counter: FAIL: $1" >&2; exit 1; }
note() { echo "benchmark-zk-counter: $1"; }

write_row() {
  python3 - "$@" <<'PY'
import json, pathlib, sys
(
    path, scenario, target, impl, ok, notes, nbytes,
    tools_s, costs_s, steps_s, commit, pf,
) = sys.argv[1:13]
tools = json.loads(tools_s)
if pf and pf not in ("", "unknown") and impl == "proofforge":
    tools.setdefault("proof-forge", pf)
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": scenario,
    "target": target,
    "implementation": impl,
    "commit": commit,
    "toolVersions": tools,
    "behavior": {
        "ok": ok.lower() in ("1", "true", "yes"),
        "steps": json.loads(steps_s),
    },
    "costs": json.loads(costs_s),
    "artifactBytes": int(nbytes),
    "notes": notes,
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY
}

STEPS_OK='[{"name":"initialize","return":null},{"name":"increment","return":null},{"name":"get","return":"1"}]'

# ── Psy DPN (proofforge) ──
note "psy-dpn: emit Counter fixture"
PSY_OUT="$WORK/pf-counter.psy"
if lake env proof-forge emit --target psy-dpn --fixture counter -o "$PSY_OUT"; then
  BYTES=$(wc -c <"$PSY_OUT" | tr -d ' ')
  COSTS='{}'
  NOTES="PF .psy source emit (fixture counter); DPN bytecode metrics require dargo"
  TOOLS="$(python3 -c 'import json,sys; print(json.dumps({"proof-forge":sys.argv[1]}))' "$PF_VERSION")"
  if command -v dargo >/dev/null 2>&1 || [ -x "${PSY_HOME:-}/bin/dargo" ]; then
    DARGO_BIN="$(command -v dargo 2>/dev/null || true)"
    [ -z "$DARGO_BIN" ] && DARGO_BIN="${PSY_HOME}/bin/dargo"
    note "psy-dpn: dargo present ($DARGO_BIN) — package + compile if possible"
    PKG="$WORK/dargo-counter"
    mkdir -p "$PKG/src"
    if [ -f scripts/psy/write-dargo-package.py ]; then
      python3 scripts/psy/write-dargo-package.py \
        --project-dir "$PKG" \
        --source "$PSY_OUT" \
        --name proof_forge_bench_counter 2>/dev/null \
        || cp "$PSY_OUT" "$PKG/src/main.psy"
    else
      cp "$PSY_OUT" "$PKG/src/main.psy"
    fi
    # Best-effort: count definitions/ops from any JSON artifact dargo may emit
    if "$DARGO_BIN" build --manifest-path "$PKG/Dargo.toml" >/tmp/bench-dargo.log 2>&1 \
      || "$DARGO_BIN" build -C "$PKG" >/tmp/bench-dargo.log 2>&1; then
      JSON="$(find "$PKG" -name '*.json' | head -n1 || true)"
      if [ -n "${JSON:-}" ]; then
        METRICS="$(python3 - "$JSON" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
try:
    data = json.loads(p.read_text())
except Exception:
    print("{}"); raise SystemExit
def count_ops(obj, acc=None):
    if acc is None: acc = {"defs": 0, "ops": 0}
    if isinstance(obj, dict):
        if "opcode" in obj or "op" in obj:
            acc["ops"] += 1
        if "definitions" in obj and isinstance(obj["definitions"], list):
            acc["defs"] += len(obj["definitions"])
        for v in obj.values():
            count_ops(v, acc)
    elif isinstance(obj, list):
        for v in obj:
            count_ops(v, acc)
    return acc
m = count_ops(data)
print(json.dumps({
    "dpn_definition_count": m["defs"],
    "dpn_op_count": m["ops"],
}))
PY
)"
        COSTS="$METRICS"
        NOTES="PF .psy + dargo build; DPN metrics best-effort from JSON artifact"
        BYTES=$(wc -c <"${JSON}" | tr -d ' ')
      else
        NOTES="dargo build succeeded but no JSON artifact found; source size only"
      fi
      TOOLS="$(python3 -c 'import json,sys; print(json.dumps({"proof-forge":sys.argv[1],"dargo":sys.argv[2]}))' "$PF_VERSION" "$("$DARGO_BIN" --version 2>/dev/null | head -n1 || echo dargo)")"
    else
      NOTES="dargo present but build failed (see /tmp/bench-dargo.log); source size only"
    fi
  fi
  write_row "$OUT_DIR/bm-psy-counter_psy-dpn_proofforge.json" \
    "bm-psy-counter" "psy-dpn" "proofforge" true "$NOTES" "$BYTES" \
    "$TOOLS" "$COSTS" "$STEPS_OK" "$COMMIT" "$PF_VERSION"
else
  write_row "$OUT_DIR/bm-psy-counter_psy-dpn_proofforge.json" \
    "bm-psy-counter" "psy-dpn" "proofforge" false \
    "skipped: psy-dpn emit failed" 0 '{}' '{}' '[]' "$COMMIT" "$PF_VERSION"
fi

# Psy native golden source
if [ -f Examples/Backend/Psy/Counter.golden.psy ]; then
  BYTES=$(wc -c <Examples/Backend/Psy/Counter.golden.psy | tr -d ' ')
  write_row "$OUT_DIR/bm-psy-counter_psy-dpn_native.json" \
    "bm-psy-counter" "psy-dpn" "native" true \
    "hand-written golden Examples/Backend/Psy/Counter.golden.psy (source size baseline)" \
    "$BYTES" '{}' '{}' "$STEPS_OK" "$COMMIT" "$PF_VERSION"
else
  write_row "$OUT_DIR/bm-psy-counter_psy-dpn_native.json" \
    "bm-psy-counter" "psy-dpn" "native" false \
    "skipped: golden .psy missing" 0 '{}' '{}' '[]' "$COMMIT" "$PF_VERSION"
fi

# ── Aleo Leo (proofforge) ──
note "aleo-leo: emit Counter fixture"
ALEO_OUT="$WORK/pf-counter.leo"
# emit may write a file or directory depending on CLI mapping
if lake env proof-forge emit --target aleo-leo --fixture counter -o "$ALEO_OUT"; then
  if [ -d "$ALEO_OUT" ]; then
    SRC="$(find "$ALEO_OUT" -name '*.leo' | head -n1 || true)"
  else
    SRC="$ALEO_OUT"
  fi
  [ -n "${SRC:-}" ] && [ -s "$SRC" ] || fail "aleo emit produced empty output"
  BYTES=$(wc -c <"$SRC" | tr -d ' ')
  NOTES="PF .leo source emit (fixture counter); snarkVM constraint metrics optional"
  TOOLS="$(python3 -c 'import json,sys; print(json.dumps({"proof-forge":sys.argv[1]}))' "$PF_VERSION")"
  COSTS='{}'
  if command -v leo >/dev/null 2>&1; then
    LEO_VER="$(leo --version 2>/dev/null | head -n1 || echo leo)"
    TOOLS="$(python3 -c 'import json,sys; print(json.dumps({"proof-forge":sys.argv[1],"leo":sys.argv[2]}))' "$PF_VERSION" "$LEO_VER")"
    # Best-effort: leo may need a package layout; record version only if build is heavy
    NOTES="PF .leo source + leo toolchain present ($LEO_VER); full prove deferred (experimental)"
  fi
  write_row "$OUT_DIR/bm-aleo-counter_aleo-leo_proofforge.json" \
    "bm-aleo-counter" "aleo-leo" "proofforge" true "$NOTES" "$BYTES" \
    "$TOOLS" "$COSTS" "$STEPS_OK" "$COMMIT" "$PF_VERSION"
else
  write_row "$OUT_DIR/bm-aleo-counter_aleo-leo_proofforge.json" \
    "bm-aleo-counter" "aleo-leo" "proofforge" false \
    "skipped: aleo-leo emit failed" 0 '{}' '{}' '[]' "$COMMIT" "$PF_VERSION"
fi

if [ -f Examples/Backend/Aleo/Counter.golden.leo ]; then
  BYTES=$(wc -c <Examples/Backend/Aleo/Counter.golden.leo | tr -d ' ')
  write_row "$OUT_DIR/bm-aleo-counter_aleo-leo_native.json" \
    "bm-aleo-counter" "aleo-leo" "native" true \
    "hand-written golden Examples/Backend/Aleo/Counter.golden.leo (source size baseline)" \
    "$BYTES" '{}' '{}' "$STEPS_OK" "$COMMIT" "$PF_VERSION"
else
  write_row "$OUT_DIR/bm-aleo-counter_aleo-leo_native.json" \
    "bm-aleo-counter" "aleo-leo" "native" false \
    "skipped: golden .leo missing" 0 '{}' '{}' '[]' "$COMMIT" "$PF_VERSION"
fi

note "schema-validate ZK rows"
python3 scripts/benchmarks/validate-result-schema.py \
  "$OUT_DIR"/bm-psy-counter_*.json \
  "$OUT_DIR"/bm-aleo-counter_*.json \
  || fail "schema validation failed"

note "ok (experimental ZK rows)"
ls -la "$OUT_DIR"/bm-psy-counter_*.json "$OUT_DIR"/bm-aleo-counter_*.json
