#!/usr/bin/env bash
# NEP-297 envelope and NEP-141 fungible-token event conformance.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_DIR="${PROOF_FORGE_NEAR_VM_NEP297_OUT:-build/wasm-near/NearFungibleTokenNep297}"
WASM="$OUT_DIR/nearfungibletoken.wasm"
RUNNER=(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml --)

fail() { echo "vm-nep297: $*" >&2; exit 1; }
for tool in cargo wat2wasm python3 lake; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool '$tool'"
done

lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken >/dev/null
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Backend/WasmNear/FungibleToken.lean >/dev/null
test -s "$WASM"

INPUTS_HEX="$(python3 - <<'PY'
import struct

def slot(name):
    raw = name.encode()
    return struct.pack('<I', len(raw)) + raw + b'\0' * (256 - len(raw))

def u128(value):
    return struct.pack('<QQ', value, 0)

values = [
    b'', slot('alice.testnet') + u128(10),
    b'{"account_id":"bob.testnet"}',
    b'{"receiver_id":"bob.testnet","amount":"3"}', u128(2),
]
print(','.join(value.hex() for value in values))
PY
)"

out="$("${RUNNER[@]}" "$WASM" init ft_mint storage_deposit ft_transfer ft_burn \
  --inputs-hex "$INPUTS_HEX" --predecessor-account-id alice.testnet \
  --attached-deposits-yocto 0,0,3900000000000000000000,1,0)"
echo "$out"

grep -qF 'call ft_mint: log=EVENT_JSON:{"standard":"nep141","version":"1.0.0","event":"ft_mint","data":[{"owner_id":"alice.testnet","amount":"10"}]}' <<<"$out" \
  || fail "ft_mint did not emit the standard NEP-141 event"
grep -qF 'call ft_transfer: log=EVENT_JSON:{"standard":"nep141","version":"1.0.0","event":"ft_transfer","data":[{"old_owner_id":"alice.testnet","new_owner_id":"bob.testnet","amount":"3"}]}' <<<"$out" \
  || fail "ft_transfer did not emit the standard NEP-141 event"
grep -qF 'call ft_burn: log=EVENT_JSON:{"standard":"nep141","version":"1.0.0","event":"ft_burn","data":[{"owner_id":"alice.testnet","amount":"2"}]}' <<<"$out" \
  || fail "ft_burn did not emit the standard NEP-141 event"
grep -qF '[near-vm-runner] 5 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "event sequence did not complete on the real NEAR VM"

echo "vm-nep297: ok"
