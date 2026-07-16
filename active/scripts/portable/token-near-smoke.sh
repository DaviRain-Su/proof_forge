#!/usr/bin/env bash
# One Product TokenSpec -> parameterized NEP-141 Wasm, clients, metadata, VM proof.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
export PATH="$HOME/.elan/bin:$HOME/.local/bin:$PATH"

OUT_DIR="${PROOF_FORGE_TOKEN_NEAR_OUT:-build/portable/token-near}"
LEAN_TOKEN="Examples/Product/FungibleToken.lean"
WAT_OUT="$OUT_DIR/prf.wat"
WASM_OUT="$OUT_DIR/prf.wasm"
ARTIFACT_JSON="$OUT_DIR/proof-forge-artifact.json"
CLIENT_TS="$OUT_DIR/proof-forge-near.ts"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "file not written: $1"
}

require_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  grep -Fq -- "$needle" "$file" || fail "$label missing '$needle' in $file"
}

for tool in cargo lake od python3 wat2wasm; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool '$tool'"
done

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null

echo "=== product-token-near: TokenSpec -> parameterized NEP-141 package ==="
lake env lean --run Tests/NearTokenSpecRuntime.lean \
  || fail "TokenSpec runtime structure test failed"
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" "$LEAN_TOKEN" \
  || fail "TokenSpec wasm-near package build failed"

for output in "$WAT_OUT" "$WASM_OUT" "$ARTIFACT_JSON" "$CLIENT_TS"; do
  require_file "$output"
done
require_contains "$WAT_OUT" "Proof Token" "TokenSpec name"
require_contains "$WAT_OUT" "PRF" "TokenSpec symbol"
require_contains "$CLIENT_TS" "ft_metadata" "generated NEAR client"

python3 - "$ARTIFACT_JSON" <<'PY'
import json
import sys

artifact = json.load(open(sys.argv[1]))
assert artifact["target"] == "wasm-near"
assert artifact["artifactKind"] == "wasm"
assert artifact["token"] == {
    "standard": "nep-141",
    "name": "Proof Token",
    "symbol": "PRF",
    "decimals": 9,
    "initialSupply": 1000000,
    "features": ["mintable", "burnable"],
    "authFeatures": [],
}
assert artifact["artifactBundle"]["finalOutput"] == "wasm"
print("parameterized token artifact: ok")
PY

INPUTS_HEX="$(python3 - <<'PY'
values = [b'', b'{}', b'{"account_id":"alice.testnet"}', b'{}']
print(','.join(value.hex() for value in values))
PY
)"
RUNNER=(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml --)
out="$("${RUNNER[@]}" "$WASM_OUT" init ft_total_supply ft_balance_of ft_metadata \
  --inputs-hex "$INPUTS_HEX" --predecessor-account-id alice.testnet)"
echo "$out"
grep -Fq 'call ft_total_supply: return_hex=223130303030303022' <<<"$out" \
  || fail 'TokenSpec initial supply did not execute as JSON "1000000"'
grep -Fq 'call ft_balance_of: return_hex=223130303030303022' <<<"$out" \
  || fail 'TokenSpec deployer balance did not execute as JSON "1000000"'
EXPECTED_METADATA_HEX="$(printf '%s' '{"spec":"ft-1.0.0","name":"Proof Token","symbol":"PRF","icon":"","reference":"","decimals":9}' | od -An -vtx1 | tr -d ' \n')"
grep -Fq "call ft_metadata: return_hex=$EXPECTED_METADATA_HEX" <<<"$out" \
  || fail "TokenSpec metadata did not execute with the authored values"
grep -Fq '4 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "parameterized TokenSpec package did not complete on the real NEAR VM"

echo "product-token-near: ok (one TokenSpec -> Wasm + clients + metadata + real VM)"

set +e
reject_out="$(lake env proof-forge build --target wasm-near --root . \
  -o "$OUT_DIR/rejected" Examples/Product/FeeToken.lean 2>&1)"
reject_status=$?
set -e
[[ $reject_status -ne 0 ]] || fail "unsupported NEAR TokenSpec feature unexpectedly built"
grep -Fq 'does not yet materialize feature(s) `transfer_fee`' <<<"$reject_out" \
  || fail "unsupported NEAR TokenSpec feature did not return the named diagnostic"
echo "product-token-near feature rejection: ok"
