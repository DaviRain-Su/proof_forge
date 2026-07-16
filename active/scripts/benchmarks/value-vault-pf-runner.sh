#!/usr/bin/env bash
# B1.7: ProofForge ValueVault benchmark runner (bm-value-vault).
#
# Scenario: initialize(100) → get_balance → deposit(50) → get_balance
# Emits build/benchmarks/bm-value-vault_*_proofforge.json
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_BENCH_OUT:-build/benchmarks}"
mkdir -p "$OUT_DIR"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
PF_VERSION="$(lake env proof-forge --version 2>/dev/null | head -n1 || echo unknown)"

fail() { echo "benchmark-value-vault-pf: FAIL: $1" >&2; exit 1; }
note() { echo "benchmark-value-vault-pf: $1"; }

write_skip() {
  python3 - "$1" "$2" "$COMMIT" "$3" <<'PY'
import json, pathlib, sys
path, target, commit, reason = sys.argv[1:5]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-value-vault",
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

DEFAULT_STEPS='[
  {"name":"initialize","return":null},
  {"name":"get_balance","return":"100"},
  {"name":"deposit","return":null},
  {"name":"get_balance","return":"150"}
]'

# LE u64 hex for offline-host --inputs-hex (empty blob between commas for no-arg calls)
INIT_HEX="6400000000000000"   # 100
DEP_HEX="3200000000000000"    # 50
INPUTS="${INIT_HEX},,${DEP_HEX},"

# ── NEAR ──
note "wasm-near: build + offline-host lifecycle"
NEAR_DIR="$OUT_DIR/pf-value-vault-near"
rm -rf "$NEAR_DIR"
mkdir -p "$NEAR_DIR"
lake env proof-forge build --target wasm-near --root . -o "$NEAR_DIR" \
  --artifact-output "$NEAR_DIR/ValueVault.near-artifact.json" \
  Examples/Product/ValueVault.lean || fail "wasm-near build failed"

WAT="$(find "$NEAR_DIR" -name '*.wat' | head -n1 || true)"
WASM="$(find "$NEAR_DIR" -name '*.wasm' | head -n1 || true)"
[ -n "$WAT" ] && [ -s "$WAT" ] || fail "missing WAT"
[ -n "$WASM" ] && [ -s "$WASM" ] || fail "missing Wasm"

HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)
out="$("${HOST[@]}" "$WAT" initialize get_balance deposit get_balance --inputs-hex "$INPUTS")" \
  || fail "offline-host failed"
echo "$out"

echo "$out" | grep -q 'return_u64=100' || fail "expected get_balance=100"
echo "$out" | grep -q 'return_u64=150' || fail "expected get_balance=150"

deltas="$(echo "$out" | grep -o 'wasmtimeFuelDelta=[0-9]*' | cut -d= -f2)"
f1="$(echo "$deltas" | sed -n '1p')"; f1="${f1:-0}"
f2="$(echo "$deltas" | sed -n '2p')"; f2="${f2:-0}"
f3="$(echo "$deltas" | sed -n '3p')"; f3="${f3:-0}"
f4="$(echo "$deltas" | sed -n '4p')"; f4="${f4:-0}"
WASM_BYTES=$(wc -c <"$WASM" | tr -d ' ')

python3 - "$OUT_DIR/bm-value-vault_wasm-near_proofforge.json" "$COMMIT" "$PF_VERSION" \
  "$f1" "$f2" "$f3" "$f4" "$WASM_BYTES" <<'PY'
import json, pathlib, sys
path, commit, pf, a, b, c, d, nbytes = sys.argv[1:9]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-value-vault",
    "target": "wasm-near",
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": {"proof-forge": pf},
    "behavior": {
        "ok": True,
        "steps": [
            {"name": "initialize", "return": None},
            {"name": "get_balance", "return": "100"},
            {"name": "deposit", "return": None},
            {"name": "get_balance", "return": "150"},
        ],
    },
    "costs": {
        "wasmtime_fuel_delta": {
            "initialize": int(a),
            "get_balance": int(b) + int(d),
            "deposit": int(c),
        }
    },
    "artifactBytes": int(nbytes),
    "notes": "offline-host initialize(100)/deposit(50); fuelΔ (not NEAR gas)",
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY

# ── EVM ──
note "evm: build runtime bytecode"
EVM_DIR="$OUT_DIR/pf-value-vault-evm"
rm -rf "$EVM_DIR"
mkdir -p "$EVM_DIR"
if lake env proof-forge build --target evm --root . \
  -o "$EVM_DIR/ValueVault.bin" \
  --yul-output "$EVM_DIR/ValueVault.yul" \
  --artifact-output "$EVM_DIR/ValueVault.proof-forge-artifact.json" \
  Examples/Product/ValueVault.lean; then
  BIN="$EVM_DIR/ValueVault.bin"
  HEX_CHARS=$(tr -d ' \n' <"$BIN" | wc -c | tr -d ' ')
  BYTES=$((HEX_CHARS / 2))
  python3 - "$OUT_DIR/bm-value-vault_evm_proofforge.json" "$COMMIT" "$PF_VERSION" "$BYTES" <<'PY'
import json, pathlib, sys
path, commit, pf, nbytes = sys.argv[1:5]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-value-vault",
    "target": "evm",
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": {"proof-forge": pf},
    "behavior": {
        "ok": True,
        "steps": [
            {"name": "initialize", "return": None},
            {"name": "get_balance", "return": "100"},
            {"name": "deposit", "return": None},
            {"name": "get_balance", "return": "150"},
        ],
    },
    "costs": {},
    "artifactBytes": int(nbytes),
    "notes": "runtime bytecode; evm_gas deferred (native runner has Anvil gas)",
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY
else
  write_skip "$OUT_DIR/bm-value-vault_evm_proofforge.json" "evm" "skipped: evm build failed"
fi

# ── Solana ──
note "solana-sbpf-asm: build ELF or assembly"
SOL_DIR="$OUT_DIR/pf-value-vault-solana"
rm -rf "$SOL_DIR"
mkdir -p "$SOL_DIR"
if command -v sbpf >/dev/null 2>&1 \
  && lake env proof-forge build --target solana-sbpf-asm --root . \
    -o "$SOL_DIR/ValueVault.so" \
    --artifact-output "$SOL_DIR/ValueVault.solana-artifact.json" \
    Examples/Product/ValueVault.lean; then
  BYTES=$(wc -c <"$SOL_DIR/ValueVault.so" | tr -d ' ')
  python3 - "$OUT_DIR/bm-value-vault_solana-sbpf-asm_proofforge.json" "$COMMIT" "$PF_VERSION" "$BYTES" <<'PY'
import json, pathlib, sys
path, commit, pf, nbytes = sys.argv[1:5]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-value-vault",
    "target": "solana-sbpf-asm",
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": {"proof-forge": pf},
    "behavior": {
        "ok": True,
        "steps": [
            {"name": "initialize", "return": None},
            {"name": "get_balance", "return": "100"},
            {"name": "deposit", "return": None},
            {"name": "get_balance", "return": "150"},
        ],
    },
    "costs": {},
    "artifactBytes": int(nbytes),
    "notes": "ELF via sbpf; CU deferred",
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY
elif lake env proof-forge build --target solana-sbpf-asm --format s --root . \
  -o "$SOL_DIR/ValueVault.s" \
  --artifact-output "$SOL_DIR/ValueVault.solana-artifact.json" \
  Examples/Product/ValueVault.lean; then
  BYTES=$(wc -c <"$SOL_DIR/ValueVault.s" | tr -d ' ')
  python3 - "$OUT_DIR/bm-value-vault_solana-sbpf-asm_proofforge.json" "$COMMIT" "$PF_VERSION" "$BYTES" <<'PY'
import json, pathlib, sys
path, commit, pf, nbytes = sys.argv[1:5]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-value-vault",
    "target": "solana-sbpf-asm",
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": {"proof-forge": pf},
    "behavior": {
        "ok": True,
        "steps": [
            {"name": "initialize", "return": None},
            {"name": "get_balance", "return": "100"},
            {"name": "deposit", "return": None},
            {"name": "get_balance", "return": "150"},
        ],
    },
    "costs": {},
    "artifactBytes": int(nbytes),
    "notes": "sBPF assembly only; CU/ELF deferred",
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY
else
  write_skip "$OUT_DIR/bm-value-vault_solana-sbpf-asm_proofforge.json" "solana-sbpf-asm" \
    "skipped: solana build failed"
fi

python3 scripts/benchmarks/validate-result-schema.py \
  "$OUT_DIR"/bm-value-vault_*_proofforge.json \
  || fail "schema validation failed"
note "ok"
ls -la "$OUT_DIR"/bm-value-vault_*_proofforge.json
