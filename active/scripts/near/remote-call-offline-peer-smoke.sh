#!/usr/bin/env bash
# N1.4: Product RemoteCall offline peer stub — call_with_args → 49 (42+7).
#
# Real sandbox peer remains `just near-sandbox-peer`. This smoke proves the
# offline-host promise_return path materializes a Borsh U64 peer result so
# CI without near-sandbox can still gate peer-shaped returns.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_REMOTE_CALL_OFFLINE_OUT:-build/near-remote-call-offline}"
WAT="$OUT_DIR/remotecall.wat"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

fail() {
  echo "remote-call-offline-peer: FAIL: $1" >&2
  exit 1
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null

echo "=== N1.4: build Product RemoteCall → wasm-near ==="
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Product/RemoteCall.lean \
  || fail "proof-forge build RemoteCall failed"
test -s "$WAT" || fail "missing $WAT"

echo "=== N1.4: offline-host initialize + call_with_args ==="
out="$("${HOST[@]}" "$WAT" \
  initialize \
  call_with_args \
  --predecessor-account-id alice.testnet \
  --signer-account-id alice.testnet \
  --current-account-id proof-forge.testnet)"
echo "$out"

grep -Fq "promise_create" <<<"$out" || fail "expected promise_create"
grep -Fq "promise_return id=" <<<"$out" || fail "expected promise_return"
grep -Fq "return_u64=49" <<<"$out" || fail "expected call_with_args → 49 (42+7 offline peer stub)"
grep -Fq "args=[42,7]" <<<"$out" || fail "expected args=[42,7] in promise_create"

echo "remote-call-offline-peer: ok (call_with_args → 49)"
