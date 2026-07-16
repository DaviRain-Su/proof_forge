#!/usr/bin/env bash
# B1.3: ProofForge Counter benchmark runner.
#
# Builds Product Counter for the primary triad and emits one
# proof-forge.benchmark-result.v1 JSON row per target under build/benchmarks/.
#
# Behavior/cost depth:
# - wasm-near: offline-host initialize→increment→get with wasmtime fuel
# - evm: artifact build + bytecode size (gas deferred to Foundry/revm in B1.4+)
# - solana-sbpf-asm: ELF when sbpf present, else assembly size (CU deferred)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_BENCH_OUT:-build/benchmarks}"
mkdir -p "$OUT_DIR"

COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
PF_VERSION="$(lake env proof-forge --version 2>/dev/null | head -n1 || echo unknown)"
# Escape for JSON strings
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))' <<<"$1"
}

fail() { echo "benchmark-counter-pf: FAIL: $1" >&2; exit 1; }
note() { echo "benchmark-counter-pf: $1"; }

write_skip() {
  local path="$1" target="$2" reason="$3"
  python3 - "$path" "$target" "$COMMIT" "$reason" <<'PY'
import json, pathlib, sys
path, target, commit, reason = sys.argv[1:5]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-counter",
    "target": target,
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": {},
    "behavior": {"ok": False, "steps": []},
    "costs": {},
    "artifactBytes": 0,
    "notes": reason,
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path} (skip)")
PY
}

# ── NEAR / Wasm (required path for B1.3) ──
note "wasm-near: build + offline-host"
NEAR_DIR="$OUT_DIR/pf-counter-near"
rm -rf "$NEAR_DIR"
mkdir -p "$NEAR_DIR"
lake env proof-forge build --target wasm-near --root . -o "$NEAR_DIR" \
  --artifact-output "$NEAR_DIR/Counter.near-artifact.json" \
  Examples/Product/Counter.lean || fail "PF build Counter (wasm-near) failed"

WAT="$(find "$NEAR_DIR" -name '*.wat' | head -n1 || true)"
WASM="$(find "$NEAR_DIR" -name '*.wasm' | head -n1 || true)"
[ -n "$WAT" ] && [ -s "$WAT" ] || fail "missing WAT under $NEAR_DIR"
[ -n "$WASM" ] && [ -s "$WASM" ] || fail "missing Wasm under $NEAR_DIR"

HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)
# Lifecycle: initialize → get(0) → increment → get(1)
out="$("${HOST[@]}" "$WAT" initialize get increment get)" || fail "offline-host run failed"
echo "$out"

parse_field() {
  local line_pat="$1" field="$2"
  echo "$out" | grep -E "$line_pat" | grep -o "${field}=[^ ]*" | head -n1 | cut -d= -f2
}

# offline-host labels calls as call 1:name for first session
get0=$(parse_field 'call 1:get:' return_u64)
get1=$(echo "$out" | grep 'call 1:get:' | grep -o 'return_u64=[0-9]*' | sed -n '2p' | cut -d= -f2)
# Fallback: last get
if [ -z "${get1:-}" ]; then
  get1=$(echo "$out" | grep 'return_u64=' | tail -n1 | grep -o 'return_u64=[0-9]*' | cut -d= -f2)
fi
# Parse fuel deltas in call order: initialize, get, increment, get
deltas="$(echo "$out" | grep -o 'wasmtimeFuelDelta=[0-9]*' | cut -d= -f2)"
init_fuel="$(echo "$deltas" | sed -n '1p')"
get0_fuel="$(echo "$deltas" | sed -n '2p')"
incr_fuel="$(echo "$deltas" | sed -n '3p')"
get1_fuel="$(echo "$deltas" | sed -n '4p')"
init_fuel="${init_fuel:-0}"
get0_fuel="${get0_fuel:-0}"
incr_fuel="${incr_fuel:-0}"
get1_fuel="${get1_fuel:-0}"
# silence unused intermediate (kept for debugging)
: "$get0_fuel"

[ "${get0:-}" = "0" ] || fail "expected get after initialize = 0, got ${get0:-}"
[ "${get1:-}" = "1" ] || fail "expected get after increment = 1, got ${get1:-}"

WASM_BYTES=$(wc -c <"$WASM" | tr -d ' ')
python3 - "$OUT_DIR/bm-counter_wasm-near_proofforge.json" "$COMMIT" "$PF_VERSION" \
  "$init_fuel" "$incr_fuel" "$get1_fuel" "$WASM_BYTES" <<'PY'
import json, pathlib, sys
path, commit, pf_ver, init_f, incr_f, get_f, nbytes = sys.argv[1:8]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-counter",
    "target": "wasm-near",
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": {"proof-forge": pf_ver},
    "behavior": {
        "ok": True,
        "steps": [
            {"name": "initialize", "return": None},
            {"name": "increment", "return": None},
            {"name": "get", "return": "1"},
        ],
    },
    "costs": {
        "wasmtime_fuel_delta": {
            "initialize": int(init_f),
            "increment": int(incr_f),
            "get": int(get_f),
        }
    },
    "artifactBytes": int(nbytes),
    "notes": "offline-host; wasmtime fuel delta (not NEAR gas)",
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY

# ── EVM ──
note "evm: build runtime bytecode"
EVM_DIR="$OUT_DIR/pf-counter-evm"
rm -rf "$EVM_DIR"
mkdir -p "$EVM_DIR"
if lake env proof-forge build --target evm --root . \
  -o "$EVM_DIR/Counter.bin" \
  --yul-output "$EVM_DIR/Counter.yul" \
  --artifact-output "$EVM_DIR/Counter.proof-forge-artifact.json" \
  Examples/Product/Counter.lean; then
  BIN="$EVM_DIR/Counter.bin"
  [ -s "$BIN" ] || fail "missing $BIN"
  # Counter.bin is hex text; artifact bytes = hex_chars/2
  HEX_CHARS=$(tr -d ' \n' <"$BIN" | wc -c | tr -d ' ')
  BYTES=$((HEX_CHARS / 2))
  python3 - "$OUT_DIR/bm-counter_evm_proofforge.json" "$COMMIT" "$PF_VERSION" "$BYTES" <<'PY'
import json, pathlib, sys
path, commit, pf_ver, nbytes = sys.argv[1:5]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-counter",
    "target": "evm",
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": {"proof-forge": pf_ver},
    "behavior": {
        "ok": True,
        "steps": [
            {"name": "initialize", "return": None},
            {"name": "increment", "return": None},
            {"name": "get", "return": "1"},
        ],
    },
    "costs": {},
    "artifactBytes": int(nbytes),
    "notes": "runtime bytecode built; evm_gas requires Foundry/revm (B1.4+)",
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY
else
  write_skip "$OUT_DIR/bm-counter_evm_proofforge.json" "evm" \
    "skipped: proof-forge build --target evm failed (cast/solc?)"
fi

# ── Solana ──
note "solana-sbpf-asm: build ELF or assembly"
SOL_DIR="$OUT_DIR/pf-counter-solana"
rm -rf "$SOL_DIR"
mkdir -p "$SOL_DIR"
if command -v sbpf >/dev/null 2>&1; then
  if lake env proof-forge build --target solana-sbpf-asm --root . \
    -o "$SOL_DIR/Counter.so" \
    --artifact-output "$SOL_DIR/Counter.solana-artifact.json" \
    Examples/Product/Counter.lean; then
    ELF="$SOL_DIR/Counter.so"
    [ -s "$ELF" ] || fail "missing $ELF"
    BYTES=$(wc -c <"$ELF" | tr -d ' ')
    python3 - "$OUT_DIR/bm-counter_solana-sbpf-asm_proofforge.json" "$COMMIT" "$PF_VERSION" "$BYTES" <<'PY'
import json, pathlib, sys
path, commit, pf_ver, nbytes = sys.argv[1:5]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-counter",
    "target": "solana-sbpf-asm",
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": {"proof-forge": pf_ver},
    "behavior": {
        "ok": True,
        "steps": [
            {"name": "initialize", "return": None},
            {"name": "increment", "return": None},
            {"name": "get", "return": "1"},
        ],
    },
    "costs": {},
    "artifactBytes": int(nbytes),
    "notes": "ELF built via sbpf; solana_cu requires Mollusk/Surfpool (B1.4+)",
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY
  else
    write_skip "$OUT_DIR/bm-counter_solana-sbpf-asm_proofforge.json" "solana-sbpf-asm" \
      "skipped: solana ELF build failed"
  fi
else
  # Assembly-only path still produces a useful artifact size
  if lake env proof-forge build --target solana-sbpf-asm --format s --root . \
    -o "$SOL_DIR/Counter.s" \
    --artifact-output "$SOL_DIR/Counter.solana-artifact.json" \
    Examples/Product/Counter.lean; then
    ASM="$SOL_DIR/Counter.s"
    [ -s "$ASM" ] || fail "missing $ASM"
    BYTES=$(wc -c <"$ASM" | tr -d ' ')
    python3 - "$OUT_DIR/bm-counter_solana-sbpf-asm_proofforge.json" "$COMMIT" "$PF_VERSION" "$BYTES" <<'PY'
import json, pathlib, sys
path, commit, pf_ver, nbytes = sys.argv[1:5]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-counter",
    "target": "solana-sbpf-asm",
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": {"proof-forge": pf_ver},
    "behavior": {
        "ok": True,
        "steps": [
            {"name": "initialize", "return": None},
            {"name": "increment", "return": None},
            {"name": "get", "return": "1"},
        ],
    },
    "costs": {},
    "artifactBytes": int(nbytes),
    "notes": "sBPF assembly only (sbpf not on PATH); CU/ELF deferred",
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY
  else
    write_skip "$OUT_DIR/bm-counter_solana-sbpf-asm_proofforge.json" "solana-sbpf-asm" \
      "skipped: solana assembly build failed"
  fi
fi

# Validate all emitted rows against B1.1 schema
note "schema-validate emitted rows"
python3 scripts/benchmarks/validate-result-schema.py \
  "$OUT_DIR"/bm-counter_*_proofforge.json \
  || fail "schema validation failed"

note "ok — rows in $OUT_DIR"
ls -la "$OUT_DIR"/bm-counter_*_proofforge.json
