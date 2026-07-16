#!/usr/bin/env bash
# NEP-148 fungible-token metadata conformance on the upstream NEAR VM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_DIR="${PROOF_FORGE_NEAR_VM_NEP148_OUT:-build/wasm-near/NearFungibleTokenNep148}"
WASM="$OUT_DIR/nearfungibletoken.wasm"
RUNNER=(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml --)
EXPECTED_HEX="$(printf '%s' '{"spec":"ft-1.0.0","name":"ProofForge Token","symbol":"PFT","icon":"","reference":"","decimals":18}' | od -An -vtx1 | tr -d ' \n')"

fail() { echo "vm-nep148: $*" >&2; exit 1; }
for tool in cargo wat2wasm lake od; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool '$tool'"
done

lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken >/dev/null
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Backend/WasmNear/FungibleToken.lean >/dev/null
test -s "$WASM"

out="$("${RUNNER[@]}" "$WASM" init ft_metadata --inputs-hex ',7b7d')"
echo "$out"
grep -qF "call ft_metadata: return_hex=$EXPECTED_HEX" <<<"$out" \
  || fail "ft_metadata did not return the exact NEP-148 JSON object"
grep -qF '[near-vm-runner] 2 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "metadata module did not complete on the real NEAR VM"

echo "vm-nep148: ok"
