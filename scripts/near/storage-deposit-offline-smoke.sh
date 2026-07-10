#!/usr/bin/env bash
# N1.5: Product StorageDeposit offline lifecycle with withdraw.
#
# init → bounds=1 → bal=0 → deposit(7) → bal=7 → withdraw(3) → bal=4
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_STORAGE_DEPOSIT_OUT:-build/near-storage-deposit-offline}"
WAT="$OUT_DIR/storagedeposit.wat"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

fail() {
  echo "storage-deposit-offline: FAIL: $1" >&2
  exit 1
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null

echo "=== N1.5: build Product StorageDeposit → wasm-near ==="
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Product/StorageDeposit.lean \
  || fail "proof-forge build StorageDeposit failed"
# WAT name is lowercased module name
WAT="$(find "$OUT_DIR" -name '*.wat' | head -n1)"
test -s "$WAT" || fail "missing WAT under $OUT_DIR"

eval "$(python3 - <<'PY'
import hashlib, struct
alice = hashlib.sha256(b"alice.testnet").digest()
bob = hashlib.sha256(b"bob.testnet").digest()
# Call sequence inputs:
# init: empty
# storage_balance_bounds: empty
# storage_balance_of: account
# storage_deposit: account (+ attached_deposit on host)
# storage_balance_of: account
# storage_withdraw: account + amount 3
# storage_balance_of: account
inputs = [
    b"",
    b"",
    alice,
    alice,
    alice,
    alice + struct.pack("<Q", 3),
    alice,
]
print(f'INPUTS_HEX="{",".join(i.hex() for i in inputs)}"')
unauthorized = [b"", bob, bob + struct.pack("<Q", 3), bob]
print(f'UNAUTHORIZED_INPUTS_HEX="{",".join(i.hex() for i in unauthorized)}"')
PY
)"

echo "=== N1.5: offline-host deposit + withdraw lifecycle ==="
out="$("${HOST[@]}" "$WAT" \
  init \
  storage_balance_bounds \
  storage_balance_of \
  storage_deposit \
  storage_balance_of \
  storage_withdraw \
  storage_balance_of \
  --predecessor-account-id alice.testnet \
  --signer-account-id alice.testnet \
  --current-account-id proof-forge.testnet \
  --attached-deposit 7 \
  --inputs-hex "$INPUTS_HEX")"
echo "$out"

grep -Fq "return_u64=1" <<<"$out" || fail "expected bounds=1"
grep -Fq "return_u64=0" <<<"$out" || fail "expected initial balance 0"
grep -Fq "return_u64=7" <<<"$out" || fail "expected balance 7 after deposit"
grep -Fq "return_u64=4" <<<"$out" || fail "expected balance 4 after withdraw 3"
grep -Fq "export \"storage_withdraw\"" "$WAT" || grep -Fq "storage_withdraw" "$WAT" \
  || fail "WAT must export storage_withdraw"

echo "=== N1.5: reject withdrawal from another account ==="
set +e
unauthorized_out="$("${HOST[@]}" "$WAT" \
  init \
  storage_deposit \
  storage_withdraw \
  storage_balance_of \
  --predecessor-account-id alice.testnet \
  --signer-account-id alice.testnet \
  --current-account-id proof-forge.testnet \
  --attached-deposit 7 \
  --inputs-hex "$UNAUTHORIZED_INPUTS_HEX" 2>&1)"
unauthorized_status=$?
set -e
echo "$unauthorized_out"
[[ "$unauthorized_status" -ne 0 ]] || fail "unauthorized withdrawal unexpectedly succeeded"
grep -Fq "call 1:storage_withdraw trapped" <<<"$unauthorized_out" || \
  fail "unauthorized withdrawal did not trap in storage_withdraw"
grep -Fq "unreachable" <<<"$unauthorized_out" || \
  fail "unauthorized withdrawal did not hit the caller guard"

echo "storage-deposit-offline: ok (caller-bound ledger debit 7 → 4; unauthorized debit trapped)"
