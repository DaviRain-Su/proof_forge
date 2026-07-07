#!/usr/bin/env bash
# Deploy and execute the Learn-token ERC-20 artifact in a local revm VM.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

export PATH="$HOME/.foundry/bin:$HOME/.elan/bin:$HOME/.local/bin:$PATH"

OUT_DIR="${PROOF_FORGE_LEARN_TOKEN_EVM_VM_OUT:-build/evm/learn-token-erc20-vm}"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v solc >/dev/null 2>&1 || fail "solc not on PATH"
command -v cast >/dev/null 2>&1 || fail "cast not on PATH"
command -v cargo >/dev/null 2>&1 || fail "cargo not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

EVM_YUL="$OUT_DIR/ProofToken.erc20.yul"
EVM_BIN="$OUT_DIR/ProofToken.erc20.bin"
EVM_ARTIFACT="$OUT_DIR/ProofToken.erc20.artifact.json"

echo "=== Learn token EVM VM step 1: emit ERC-20 artifact ==="
lake env proof-forge build --target evm --token \
  --yul-output "$EVM_YUL" \
  --artifact-output "$EVM_ARTIFACT" \
  -o "$EVM_BIN" \
  Examples/Learn/ProofToken.learn \
  || fail "proof-forge build --target evm --token failed"

test -s "$EVM_BIN" || fail "empty EVM bytecode: $EVM_BIN"
test -s "$EVM_ARTIFACT" || fail "missing EVM artifact: $EVM_ARTIFACT"

echo "=== Learn token EVM VM step 2: deploy and exercise ERC-20 behavior ==="
cargo run --manifest-path testkit/harness-evm/Cargo.toml \
  --bin learn_token_erc20_vm_smoke -- "$EVM_BIN" "$EVM_ARTIFACT" \
  || fail "revm ERC-20 behavior smoke failed"

echo "learn-token-erc20-vm-smoke: PASS"
