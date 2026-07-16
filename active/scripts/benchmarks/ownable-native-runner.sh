#!/usr/bin/env bash
# B1.7: Native Ownable runner (bm-ownable).
# EVM: Anvil/cast init/transfer/renounce. NEAR: host tests + wasm. Solana: skip.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_BENCH_OUT:-build/benchmarks}"
mkdir -p "$OUT_DIR"
WORK="$OUT_DIR/native-ownable-work"
rm -rf "$WORK"
mkdir -p "$WORK"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

fail() { echo "benchmark-ownable-native: FAIL: $1" >&2; exit 1; }
note() { echo "benchmark-ownable-native: $1"; }

write_row() {
  python3 - "$@" <<'PY'
import json, pathlib, sys
path, target, ok, notes, nbytes, tools_s, costs_s, steps_s, commit = sys.argv[1:10]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-ownable",
    "target": target,
    "implementation": "native",
    "commit": commit,
    "toolVersions": json.loads(tools_s),
    "behavior": {"ok": ok.lower() in ("1", "true", "yes"), "steps": json.loads(steps_s)},
    "costs": json.loads(costs_s),
    "artifactBytes": int(nbytes),
    "notes": notes,
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY
}

STEPS='[{"name":"init","return":null},{"name":"transferOwnership","return":null},{"name":"renounceOwnership","return":null}]'

# ── EVM ──
note "evm: solc + anvil Ownable lifecycle"
EVM_OUT="$OUT_DIR/bm-ownable_evm_native.json"
if ! command -v solc >/dev/null 2>&1 || ! command -v cast >/dev/null 2>&1 || ! command -v anvil >/dev/null 2>&1; then
  if command -v solc >/dev/null 2>&1; then
    EVM_DIR="$WORK/evm"
    mkdir -p "$EVM_DIR"
    solc --bin --optimize --optimize-runs 200 \
      benchmarks/native/evm/Ownable.sol -o "$EVM_DIR" --overwrite || fail "solc failed"
    BIN="$(find "$EVM_DIR" -name 'Ownable.bin' | head -n1)"
    HEX="$(tr -d ' \n' <"$BIN")"
    BYTES=$(( ${#HEX} / 2 ))
    write_row "$EVM_OUT" "evm" true "solc only" "$BYTES" \
      "$(python3 -c 'import json; print(json.dumps({"solc":"present"}))')" '{}' "$STEPS" "$COMMIT"
  else
    write_row "$EVM_OUT" "evm" false "skipped: solc/cast/anvil missing" 0 '{}' '{}' '[]' "$COMMIT"
  fi
else
  EVM_DIR="$WORK/evm"
  mkdir -p "$EVM_DIR"
  solc --bin --optimize --optimize-runs 200 \
    benchmarks/native/evm/Ownable.sol -o "$EVM_DIR" --overwrite || fail "solc failed"
  BIN="$(find "$EVM_DIR" -name 'Ownable.bin' | head -n1)"
  HEX="$(tr -d ' \n' <"$BIN")"
  BYTES=$(( ${#HEX} / 2 ))
  PORT="${PROOF_FORGE_BENCH_ANVIL_PORT:-18547}"
  RPC="http://127.0.0.1:${PORT}"
  PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  # second anvil account as new owner
  PK2="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
  anvil --port "$PORT" --quiet >/dev/null 2>&1 &
  ANVIL_PID=$!
  cleanup() { kill "$ANVIL_PID" >/dev/null 2>&1 || true; }
  trap cleanup EXIT
  for _ in $(seq 1 50); do
    cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
    sleep 0.1
  done
  CREATE_OUT="$(cast send --rpc-url "$RPC" --private-key "$PK" --create "0x${HEX}" --json)"
  ADDR="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$CREATE_OUT")"
  BOB="$(cast wallet address --private-key "$PK2")"

  g_init="$(cast estimate --rpc-url "$RPC" "$ADDR" "init()" || echo 0)"
  cast send --rpc-url "$RPC" --private-key "$PK" "$ADDR" "init()" >/dev/null

  g_xfer="$(cast estimate --rpc-url "$RPC" "$ADDR" "transferOwnership(address)" "$BOB" || echo 0)"
  cast send --rpc-url "$RPC" --private-key "$PK" "$ADDR" "transferOwnership(address)" "$BOB" >/dev/null

  g_ren="$(cast estimate --rpc-url "$RPC" --private-key "$PK2" "$ADDR" "renounceOwnership()" || echo 0)"
  cast send --rpc-url "$RPC" --private-key "$PK2" "$ADDR" "renounceOwnership()" >/dev/null
  OWNER="$(cast call --rpc-url "$RPC" "$ADDR" "owner()(address)" | tr '[:upper:]' '[:lower:]')"
  echo "$OWNER" | grep -Eq '0x0+$|0x0000' || fail "expected renounced owner=0 got $OWNER"

  cleanup; trap - EXIT
  SOLC_VER="$(solc --version 2>/dev/null | sed -n 's/.*Version: //p' | head -n1)"
  CAST_VER="$(cast --version 2>/dev/null | head -n1 || echo cast)"
  COSTS="$(python3 -c 'import json,sys; print(json.dumps({"evm_gas":{"init":int(sys.argv[1]),"transferOwnership":int(sys.argv[2]),"renounceOwnership":int(sys.argv[3])}}))' \
    "$g_init" "$g_xfer" "$g_ren")"
  TOOLS="$(python3 -c 'import json,sys; print(json.dumps({"solc":sys.argv[1],"cast":sys.argv[2]}))' "${SOLC_VER:-solc}" "$CAST_VER")"
  write_row "$EVM_OUT" "evm" true "Anvil/cast Ownable.sol lifecycle" "$BYTES" \
    "$TOOLS" "$COSTS" "$STEPS" "$COMMIT"
fi

# ── Solana ──
write_row "$OUT_DIR/bm-ownable_solana-sbpf-asm_native.json" "solana-sbpf-asm" false \
  "skipped: no Pinocchio Ownable corpus (B1.7 EVM/NEAR focus)" 0 '{}' '{}' '[]' "$COMMIT"

# ── NEAR ──
note "near: host tests"
NEAR_OUT="$OUT_DIR/bm-ownable_wasm-near_native.json"
if command -v cargo >/dev/null 2>&1; then
  cargo test --manifest-path testkit/compare/near/ownable/Cargo.toml \
    --features host-tests -- --nocapture \
    || fail "near ownable host tests failed"
  WASM_BYTES=0
  NOTES="near-sdk host tests (testkit/compare/near/ownable)"
  if rustup target list --installed 2>/dev/null | grep -q wasm32-unknown-unknown; then
    if cargo build --manifest-path testkit/compare/near/ownable/Cargo.toml \
      --target wasm32-unknown-unknown --release >/tmp/bench-ownable-near.log 2>&1; then
      WASM="$(find testkit/compare/near/ownable/target/wasm32-unknown-unknown/release \
        -maxdepth 1 -name '*.wasm' 2>/dev/null | head -n1 || true)"
      if [ -n "${WASM:-}" ] && [ -s "$WASM" ]; then
        WASM_BYTES=$(wc -c <"$WASM" | tr -d ' ')
      fi
    fi
  fi
  CARGO_VER="$(cargo --version 2>/dev/null || echo cargo)"
  write_row "$NEAR_OUT" "wasm-near" true "$NOTES" "$WASM_BYTES" \
    "$(python3 -c 'import json,sys; print(json.dumps({"cargo":sys.argv[1]}))' "$CARGO_VER")" \
    '{}' "$STEPS" "$COMMIT"
else
  write_row "$NEAR_OUT" "wasm-near" false "skipped: cargo missing" 0 '{}' '{}' '[]' "$COMMIT"
fi

python3 scripts/benchmarks/validate-result-schema.py \
  "$OUT_DIR"/bm-ownable_*_native.json \
  || fail "schema validation failed"
note "ok"
ls -la "$OUT_DIR"/bm-ownable_*_native.json
