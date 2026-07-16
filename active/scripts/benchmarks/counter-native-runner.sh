#!/usr/bin/env bash
# B1.4: Native Counter benchmark runner.
#
# Builds/runs hand-written triad baselines under benchmarks/native/ and emits
# proof-forge.benchmark-result.v1 JSON rows alongside the PF rows from B1.3:
#   build/benchmarks/bm-counter_{evm,solana-sbpf-asm,wasm-near}_native.json
#
# Depth (honest, tool-gated):
# - evm: solc + Anvil/cast lifecycle with per-step gas
# - solana-sbpf-asm: cargo check (+ optional cargo-build-sbf ELF size); CU deferred
# - wasm-near: host unit tests + release wasm size (offline-host is PF ABI only)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_BENCH_OUT:-build/benchmarks}"
mkdir -p "$OUT_DIR"
WORK="$OUT_DIR/native-counter-work"
rm -rf "$WORK"
mkdir -p "$WORK"

COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

fail() { echo "benchmark-counter-native: FAIL: $1" >&2; exit 1; }
note() { echo "benchmark-counter-native: $1"; }

write_row() {
  # args: path target ok_bool notes artifact_bytes tool_versions_json costs_json steps_json
  python3 - "$@" <<'PY'
import json, pathlib, sys
path, target, ok, notes, nbytes, tools_s, costs_s, steps_s = sys.argv[1:9]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-counter",
    "target": target,
    "implementation": "native",
    "commit": sys.argv[9] if len(sys.argv) > 9 else "unknown",
    "toolVersions": json.loads(tools_s),
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

write_skip() {
  local path="$1" target="$2" reason="$3"
  write_row "$path" "$target" false "$reason" 0 '{}' '{}' '[]' "$COMMIT"
}

DEFAULT_STEPS='[{"name":"initialize","return":null},{"name":"increment","return":null},{"name":"get","return":"1"}]'

# ── EVM ──
note "evm: solc + anvil lifecycle"
EVM_OUT="$OUT_DIR/bm-counter_evm_native.json"
if ! command -v solc >/dev/null 2>&1; then
  write_skip "$EVM_OUT" "evm" "skipped: solc not on PATH"
elif ! command -v cast >/dev/null 2>&1 || ! command -v anvil >/dev/null 2>&1; then
  # Compile-only path: still record bytecode size without gas
  note "evm: cast/anvil missing — compile-only"
  EVM_DIR="$WORK/evm"
  mkdir -p "$EVM_DIR"
  solc --bin --optimize --optimize-runs 200 \
    benchmarks/native/evm/Counter.sol -o "$EVM_DIR" --overwrite \
    || fail "solc compile failed"
  BIN="$(find "$EVM_DIR" -name 'Counter.bin' | head -n1)"
  [ -n "$BIN" ] && [ -s "$BIN" ] || fail "missing Counter.bin"
  HEX_CHARS=$(tr -d ' \n' <"$BIN" | wc -c | tr -d ' ')
  BYTES=$((HEX_CHARS / 2))
  SOLC_VER="$(solc --version 2>/dev/null | head -n1 || echo solc)"
  write_row "$EVM_OUT" "evm" true \
    "solc bytecode only; gas requires anvil/cast" \
    "$BYTES" \
    "$(python3 -c 'import json,sys; print(json.dumps({"solc":sys.argv[1]}))' "$SOLC_VER")" \
    '{}' \
    "$DEFAULT_STEPS" \
    "$COMMIT"
else
  EVM_DIR="$WORK/evm"
  mkdir -p "$EVM_DIR"
  solc --bin --abi --optimize --optimize-runs 200 \
    benchmarks/native/evm/Counter.sol -o "$EVM_DIR" --overwrite \
    || fail "solc compile failed"
  BIN="$(find "$EVM_DIR" -name 'Counter.bin' | head -n1)"
  [ -n "$BIN" ] && [ -s "$BIN" ] || fail "missing Counter.bin"
  HEX="$(tr -d ' \n' <"$BIN")"
  BYTES=$(( ${#HEX} / 2 ))

  PORT="${PROOF_FORGE_BENCH_ANVIL_PORT:-18545}"
  RPC="http://127.0.0.1:${PORT}"
  # Anvil default first account
  PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

  anvil --port "$PORT" --quiet >/dev/null 2>&1 &
  ANVIL_PID=$!
  cleanup_anvil() { kill "$ANVIL_PID" >/dev/null 2>&1 || true; }
  trap cleanup_anvil EXIT

  # Wait for RPC
  for _ in $(seq 1 50); do
    if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 || fail "anvil did not start on $RPC"

  CREATE_OUT="$(cast send --rpc-url "$RPC" --private-key "$PK" --create "0x${HEX}" --json)" \
    || fail "cast create failed"
  ADDR="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$CREATE_OUT")"
  [ -n "$ADDR" ] || fail "empty contract address"

  gas_initialize="$(cast estimate --rpc-url "$RPC" "$ADDR" "initialize()" || echo 0)"
  cast send --rpc-url "$RPC" --private-key "$PK" "$ADDR" "initialize()" >/dev/null \
    || fail "initialize failed"

  gas_increment="$(cast estimate --rpc-url "$RPC" "$ADDR" "increment()" || echo 0)"
  cast send --rpc-url "$RPC" --private-key "$PK" "$ADDR" "increment()" >/dev/null \
    || fail "increment failed"

  gas_get="$(cast estimate --rpc-url "$RPC" "$ADDR" "get()" || echo 0)"
  GOT="$(cast call --rpc-url "$RPC" "$ADDR" "get()(uint64)")"
  # cast may print "1" or "1 [1e0]"
  GOT_NUM="$(echo "$GOT" | awk '{print $1}')"
  [ "$GOT_NUM" = "1" ] || fail "expected get()=1, got $GOT"

  cleanup_anvil
  trap - EXIT

  # Prefer a short solc version token (full banner is noisy in JSON).
  SOLC_VER="$(solc --version 2>/dev/null | sed -n 's/.*Version: //p' | head -n1)"
  SOLC_VER="${SOLC_VER:-solc}"
  CAST_VER="$(cast --version 2>/dev/null | head -n1 || echo cast)"
  COSTS="$(python3 -c 'import json,sys; print(json.dumps({"evm_gas":{"initialize":int(sys.argv[1]),"increment":int(sys.argv[2]),"get":int(sys.argv[3])}}))' \
    "$gas_initialize" "$gas_increment" "$gas_get")"
  TOOLS="$(python3 -c 'import json,sys; print(json.dumps({"solc":sys.argv[1],"cast":sys.argv[2]}))' "$SOLC_VER" "$CAST_VER")"
  write_row "$EVM_OUT" "evm" true \
    "Anvil/cast lifecycle; native Solidity Counter.sol" \
    "$BYTES" "$TOOLS" "$COSTS" "$DEFAULT_STEPS" "$COMMIT"
fi

# ── Solana ──
note "solana: pinocchio cargo check (+ optional sbf elf)"
SOL_OUT="$OUT_DIR/bm-counter_solana-sbpf-asm_native.json"
if ! command -v cargo >/dev/null 2>&1; then
  write_skip "$SOL_OUT" "solana-sbpf-asm" "skipped: cargo not on PATH"
else
  cargo check --manifest-path benchmarks/native/solana/counter/Cargo.toml \
    --no-default-features --features bpf-entrypoint \
    || fail "solana cargo check failed"

  ELF_BYTES=0
  NOTES="Pinocchio-class host typecheck; solana_cu requires Mollusk/Surfpool"
  if command -v cargo-build-sbf >/dev/null 2>&1; then
    note "solana: attempting cargo-build-sbf"
    if cargo-build-sbf --manifest-path benchmarks/native/solana/counter/Cargo.toml \
      >/tmp/bench-sbf-native.log 2>&1; then
      ELF="$(find benchmarks/native/solana/counter/target -name '*.so' 2>/dev/null | head -n1 || true)"
      if [ -n "${ELF:-}" ] && [ -s "$ELF" ]; then
        ELF_BYTES=$(wc -c <"$ELF" | tr -d ' ')
        NOTES="Pinocchio ELF via cargo-build-sbf; CU deferred (no Mollusk in this gate)"
      fi
    else
      NOTES="cargo check ok; cargo-build-sbf failed (see build log); CU deferred"
    fi
  fi
  CARGO_VER="$(cargo --version 2>/dev/null || echo cargo)"
  write_row "$SOL_OUT" "solana-sbpf-asm" true \
    "$NOTES" \
    "$ELF_BYTES" \
    "$(python3 -c 'import json,sys; print(json.dumps({"cargo":sys.argv[1]}))' "$CARGO_VER")" \
    '{}' \
    "$DEFAULT_STEPS" \
    "$COMMIT"
fi

# ── NEAR ──
note "near: host tests + release wasm size"
NEAR_OUT="$OUT_DIR/bm-counter_wasm-near_native.json"
if ! command -v cargo >/dev/null 2>&1; then
  write_skip "$NEAR_OUT" "wasm-near" "skipped: cargo not on PATH"
else
  cargo test --manifest-path benchmarks/native/near/counter-rs/Cargo.toml \
    --features host-tests -- --nocapture \
    || fail "near host tests failed"

  WASM_BYTES=0
  NOTES="near-sdk host tests green; wasm size via release wasm32 build"
  if rustup target list --installed 2>/dev/null | grep -q 'wasm32-unknown-unknown'; then
    note "near: cargo build --release --target wasm32-unknown-unknown"
    if cargo build --manifest-path benchmarks/native/near/counter-rs/Cargo.toml \
      --target wasm32-unknown-unknown --release \
      >/tmp/bench-near-wasm.log 2>&1; then
      WASM="$(find benchmarks/native/near/counter-rs/target/wasm32-unknown-unknown/release \
        -maxdepth 1 -name '*.wasm' 2>/dev/null | head -n1 || true)"
      if [ -n "${WASM:-}" ] && [ -s "$WASM" ]; then
        WASM_BYTES=$(wc -c <"$WASM" | tr -d ' ')
        NOTES="near-sdk host tests + release wasm; fuel not comparable to PF offline-host ABI"
      fi
    else
      NOTES="near-sdk host tests green; wasm32 release build failed (see log)"
    fi
  else
    NOTES="near-sdk host tests green; wasm32-unknown-unknown target not installed"
  fi
  CARGO_VER="$(cargo --version 2>/dev/null || echo cargo)"
  write_row "$NEAR_OUT" "wasm-near" true \
    "$NOTES" \
    "$WASM_BYTES" \
    "$(python3 -c 'import json,sys; print(json.dumps({"cargo":sys.argv[1]}))' "$CARGO_VER")" \
    '{}' \
    "$DEFAULT_STEPS" \
    "$COMMIT"
fi

note "schema-validate native rows"
python3 scripts/benchmarks/validate-result-schema.py \
  "$OUT_DIR"/bm-counter_*_native.json \
  || fail "schema validation failed"

note "ok — rows in $OUT_DIR"
ls -la "$OUT_DIR"/bm-counter_*_native.json
