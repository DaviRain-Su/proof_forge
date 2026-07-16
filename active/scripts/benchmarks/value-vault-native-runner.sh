#!/usr/bin/env bash
# B1.7: Native ValueVault runner (bm-value-vault).
# EVM: Anvil/cast lifecycle with gas. NEAR: host tests + wasm size.
# Solana: deferred (no Pinocchio ValueVault corpus yet) — honest skip.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_BENCH_OUT:-build/benchmarks}"
mkdir -p "$OUT_DIR"
WORK="$OUT_DIR/native-value-vault-work"
rm -rf "$WORK"
mkdir -p "$WORK"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

fail() { echo "benchmark-value-vault-native: FAIL: $1" >&2; exit 1; }
note() { echo "benchmark-value-vault-native: $1"; }

write_row() {
  python3 - "$@" <<'PY'
import json, pathlib, sys
path, target, ok, notes, nbytes, tools_s, costs_s, steps_s, commit = sys.argv[1:10]
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-value-vault",
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

STEPS='[{"name":"initialize","return":null},{"name":"get_balance","return":"100"},{"name":"deposit","return":null},{"name":"get_balance","return":"150"}]'

# ── EVM ──
note "evm: solc + anvil lifecycle"
EVM_OUT="$OUT_DIR/bm-value-vault_evm_native.json"
if ! command -v solc >/dev/null 2>&1; then
  write_row "$EVM_OUT" "evm" false "skipped: solc not on PATH" 0 '{}' '{}' '[]' "$COMMIT"
elif ! command -v cast >/dev/null 2>&1 || ! command -v anvil >/dev/null 2>&1; then
  EVM_DIR="$WORK/evm"
  mkdir -p "$EVM_DIR"
  solc --bin --optimize --optimize-runs 200 \
    benchmarks/native/evm/ValueVault.sol -o "$EVM_DIR" --overwrite \
    || fail "solc failed"
  BIN="$(find "$EVM_DIR" -name 'ValueVault.bin' | head -n1)"
  HEX="$(tr -d ' \n' <"$BIN")"
  BYTES=$(( ${#HEX} / 2 ))
  SOLC_VER="$(solc --version 2>/dev/null | sed -n 's/.*Version: //p' | head -n1)"
  write_row "$EVM_OUT" "evm" true "solc only; gas needs anvil/cast" "$BYTES" \
    "$(python3 -c 'import json,sys; print(json.dumps({"solc":sys.argv[1]}))' "${SOLC_VER:-solc}")" \
    '{}' "$STEPS" "$COMMIT"
else
  EVM_DIR="$WORK/evm"
  mkdir -p "$EVM_DIR"
  solc --bin --optimize --optimize-runs 200 \
    benchmarks/native/evm/ValueVault.sol -o "$EVM_DIR" --overwrite \
    || fail "solc failed"
  BIN="$(find "$EVM_DIR" -name 'ValueVault.bin' | head -n1)"
  HEX="$(tr -d ' \n' <"$BIN")"
  BYTES=$(( ${#HEX} / 2 ))
  PORT="${PROOF_FORGE_BENCH_ANVIL_PORT:-18546}"
  RPC="http://127.0.0.1:${PORT}"
  PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  anvil --port "$PORT" --quiet >/dev/null 2>&1 &
  ANVIL_PID=$!
  cleanup() { kill "$ANVIL_PID" >/dev/null 2>&1 || true; }
  trap cleanup EXIT
  for _ in $(seq 1 50); do
    cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
    sleep 0.1
  done
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 || fail "anvil failed"

  CREATE_OUT="$(cast send --rpc-url "$RPC" --private-key "$PK" --create "0x${HEX}" --json)"
  ADDR="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$CREATE_OUT")"

  g_init="$(cast estimate --rpc-url "$RPC" "$ADDR" "initialize(uint64)" 100 || echo 0)"
  cast send --rpc-url "$RPC" --private-key "$PK" "$ADDR" "initialize(uint64)" 100 >/dev/null
  bal1="$(cast call --rpc-url "$RPC" "$ADDR" "get_balance()(uint64)" | awk '{print $1}')"
  [ "$bal1" = "100" ] || fail "get_balance after init expected 100 got $bal1"

  g_dep="$(cast estimate --rpc-url "$RPC" "$ADDR" "deposit(uint64)" 50 || echo 0)"
  cast send --rpc-url "$RPC" --private-key "$PK" "$ADDR" "deposit(uint64)" 50 >/dev/null
  bal2="$(cast call --rpc-url "$RPC" "$ADDR" "get_balance()(uint64)" | awk '{print $1}')"
  [ "$bal2" = "150" ] || fail "get_balance after deposit expected 150 got $bal2"

  g_get="$(cast estimate --rpc-url "$RPC" "$ADDR" "get_balance()" || echo 0)"
  cleanup; trap - EXIT

  SOLC_VER="$(solc --version 2>/dev/null | sed -n 's/.*Version: //p' | head -n1)"
  CAST_VER="$(cast --version 2>/dev/null | head -n1 || echo cast)"
  COSTS="$(python3 -c 'import json,sys; print(json.dumps({"evm_gas":{"initialize":int(sys.argv[1]),"deposit":int(sys.argv[2]),"get_balance":int(sys.argv[3])}}))' \
    "$g_init" "$g_dep" "$g_get")"
  TOOLS="$(python3 -c 'import json,sys; print(json.dumps({"solc":sys.argv[1],"cast":sys.argv[2]}))' "${SOLC_VER:-solc}" "$CAST_VER")"
  write_row "$EVM_OUT" "evm" true "Anvil/cast ValueVault.sol lifecycle" "$BYTES" \
    "$TOOLS" "$COSTS" "$STEPS" "$COMMIT"
fi

# ── Solana (no corpus yet) ──
note "solana: honest skip (no native ValueVault Pinocchio corpus in B1.7)"
write_row "$OUT_DIR/bm-value-vault_solana-sbpf-asm_native.json" "solana-sbpf-asm" false \
  "skipped: no Pinocchio ValueVault corpus yet (Counter-only native Solana in B1.2)" \
  0 '{}' '{}' '[]' "$COMMIT"

# ── NEAR ──
note "near: host tests + optional wasm size"
NEAR_OUT="$OUT_DIR/bm-value-vault_wasm-near_native.json"
if ! command -v cargo >/dev/null 2>&1; then
  write_row "$NEAR_OUT" "wasm-near" false "skipped: cargo missing" 0 '{}' '{}' '[]' "$COMMIT"
else
  cargo test --manifest-path testkit/compare/near/value-vault/Cargo.toml \
    --features host-tests -- --nocapture \
    || fail "near value-vault host tests failed"
  WASM_BYTES=0
  NOTES="near-sdk host tests (testkit/compare/near/value-vault)"
  if rustup target list --installed 2>/dev/null | grep -q wasm32-unknown-unknown; then
    if cargo build --manifest-path testkit/compare/near/value-vault/Cargo.toml \
      --target wasm32-unknown-unknown --release >/tmp/bench-vv-near.log 2>&1; then
      WASM="$(find testkit/compare/near/value-vault/target/wasm32-unknown-unknown/release \
        -maxdepth 1 -name '*.wasm' 2>/dev/null | head -n1 || true)"
      if [ -n "${WASM:-}" ] && [ -s "$WASM" ]; then
        WASM_BYTES=$(wc -c <"$WASM" | tr -d ' ')
        NOTES="near-sdk host tests + release wasm; dual-deploy gas via just near-compare-value-vault-live"
      fi
    fi
  fi
  CARGO_VER="$(cargo --version 2>/dev/null || echo cargo)"
  write_row "$NEAR_OUT" "wasm-near" true "$NOTES" "$WASM_BYTES" \
    "$(python3 -c 'import json,sys; print(json.dumps({"cargo":sys.argv[1]}))' "$CARGO_VER")" \
    '{}' "$STEPS" "$COMMIT"
fi

python3 scripts/benchmarks/validate-result-schema.py \
  "$OUT_DIR"/bm-value-vault_*_native.json \
  || fail "schema validation failed"
note "ok"
ls -la "$OUT_DIR"/bm-value-vault_*_native.json
