#!/usr/bin/env bash
# B1.2: validate native Counter corpus sources (compile/typecheck when tools present).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT="${PROOF_FORGE_BENCHMARK_NATIVE_OUT:-build/benchmarks/native-counter}"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "benchmark-native-counter: FAIL: $1" >&2; exit 1; }
note() { echo "benchmark-native-counter: $1"; }

require_file() {
  [ -f "$1" ] || fail "missing $1"
}

require_file benchmarks/native/evm/Counter.sol
require_file benchmarks/native/solana/counter/src/lib.rs
require_file benchmarks/native/solana/counter/Cargo.toml
require_file benchmarks/native/near/counter/reference-manifest.json
require_file benchmarks/native/near/counter-rs/src/lib.rs
require_file benchmarks/native/near/counter-rs/Cargo.toml

passed=0
skipped=0

# --- EVM ---
if command -v solc >/dev/null 2>&1; then
  note "evm: compiling Counter.sol with solc"
  mkdir -p "$OUT/evm"
  solc --bin --optimize --optimize-runs 200 \
    benchmarks/native/evm/Counter.sol \
    -o "$OUT/evm" --overwrite \
    || fail "solc compile failed"
  # solc may emit nested paths; find any Counter.bin
  bin_file="$(find "$OUT/evm" -name 'Counter.bin' | head -n1 || true)"
  [ -n "$bin_file" ] && [ -s "$bin_file" ] || fail "solc did not emit Counter.bin"
  note "evm: ok ($(wc -c <"$bin_file") bytes hex-ish artifact at $bin_file)"
  passed=$((passed + 1))
else
  note "evm: SKIP (solc not on PATH)"
  skipped=$((skipped + 1))
fi

# --- Solana (host cargo check; no platform-tools required) ---
if command -v cargo >/dev/null 2>&1; then
  note "solana: cargo check pinocchio counter"
  cargo check --manifest-path benchmarks/native/solana/counter/Cargo.toml \
    --no-default-features --features bpf-entrypoint \
    || fail "solana cargo check failed"
  note "solana: ok (cargo check)"
  passed=$((passed + 1))
else
  note "solana: SKIP (cargo not on PATH)"
  skipped=$((skipped + 1))
fi

# --- NEAR (host unit tests on vendored B1 corpus) ---
if command -v cargo >/dev/null 2>&1; then
  note "near: cargo test host-tests on benchmarks/native/near/counter-rs"
  cargo test --manifest-path benchmarks/native/near/counter-rs/Cargo.toml \
    --features host-tests -- --nocapture \
    || fail "near host tests failed"
  note "near: ok (host tests)"
  passed=$((passed + 1))
else
  note "near: SKIP (cargo not on PATH)"
  skipped=$((skipped + 1))
fi

# Structural JSON pointer for NEAR corpus
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("benchmarks/native/near/counter/reference-manifest.json")
m = json.loads(p.read_text())
assert m["sourcePath"] == "benchmarks/native/near/counter-rs", m
src = pathlib.Path(m["sourcePath"]) / "src" / "lib.rs"
assert src.is_file(), src
print("near: reference-manifest points at counter-rs")
PY

note "summary: ${passed} passed, ${skipped} skipped"
if [ "$passed" -eq 0 ]; then
  fail "no toolchain available to validate native corpus"
fi
echo "=== benchmark-native-counter: PASS ==="
