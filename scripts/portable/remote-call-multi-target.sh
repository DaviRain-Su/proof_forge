#!/usr/bin/env bash
# Portable RemoteCall multi-target smoke.
#
# One Shared source → EVM CALL · Solana CPI · NEAR promise_create · Soroban
# invoke_contract (host bridge; not a --list-targets id yet).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.foundry/bin:$PATH"

SOURCE="${PORTABLE_REMOTE_CALL_SOURCE:-Examples/Product/RemoteCall.lean}"
OUT="${PORTABLE_REMOTE_CALL_OUT:-build/portable-remote-call}"

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi
cast_args=()
if [[ -n "${CAST:-}" ]]; then
  cast_args=(--cast "$CAST")
fi

fail() {
  echo "portable-remote-call: FAIL: $1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_contains() {
  grep -Fq -- "$2" "$1" || fail "$3 missing '$2' in $1"
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

(cd "$ROOT" && lake build proof-forge Examples.Product.RemoteCall >/dev/null)

echo "portable-remote-call: EVM"
if command -v solc >/dev/null 2>&1; then
  "${proof_forge[@]}" build --target evm --root . \
    -o "$OUT/evm/RemoteCall.bin" \
    --yul-output "$OUT/evm/RemoteCall.yul" \
    --artifact-output "$OUT/evm/RemoteCall.proof-forge-artifact.json" \
    "${cast_args[@]+"${cast_args[@]}"}" \
    "$SOURCE"
  require_file "$OUT/evm/RemoteCall.bin"
  require_file "$OUT/evm/RemoteCall.yul"
  require_file "$OUT/evm/RemoteCall.proof-forge-artifact.json"
  # Yul CALL opcode / helper naming varies; accept either form.
  if ! grep -Eqi 'call|staticcall|delegatecall' "$OUT/evm/RemoteCall.yul"; then
    fail "EVM Yul should contain a CALL-family emission"
  fi
else
  echo "portable-remote-call: solc missing; EVM emit skipped (Lean gate still covers plan)"
fi

echo "portable-remote-call: Solana sBPF"
"${proof_forge[@]}" build --target solana-sbpf-asm --format s --root . \
  -o "$OUT/solana/RemoteCall.s" \
  --artifact-output "$OUT/solana/RemoteCall.solana-artifact.json" \
  "$SOURCE"
require_file "$OUT/solana/RemoteCall.s"
require_file "$OUT/solana/manifest.toml"
require_contains "$OUT/solana/RemoteCall.s" "sol_invoke_signed_c" "Solana CPI invoke"
require_contains "$OUT/solana/RemoteCall.s" "sol_get_return_data" "Solana return-data"
# PF-P2-03: portable peer CPI uses empty AccountMeta pack (method+args in ix data);
# peer program_id comes from the peer_program account key. Keep AccountMeta string
# in the comment for smoke grep stability.
require_contains "$OUT/solana/RemoteCall.s" "AccountMeta" "Solana AccountMeta pack comment"
require_contains "$OUT/solana/RemoteCall.s" "peer/callee account index" "Solana peer account index resolve"
require_contains "$OUT/solana/manifest.toml" "callee_program" "manifest callee_program account"
GOLDEN_SOL="$ROOT/Examples/Product/goldens/RemoteCall.solana.s"
if [[ -f "$GOLDEN_SOL" ]]; then
  diff -u "$GOLDEN_SOL" "$OUT/solana/RemoteCall.s" \
    || fail "Solana asm drifted from Examples/Product/goldens/RemoteCall.solana.s"
fi

echo "portable-remote-call: NEAR/Wasm"
# Explicit deploy peer map (no silent default): demo map for golden host ids.
"${proof_forge[@]}" build --target wasm-near --root . \
  --peers-demo \
  -o "$OUT/near" \
  --artifact-output "$OUT/near/RemoteCall.near-artifact.json" \
  "$SOURCE"
# EmitWat names the wat file from module name (lowercased).
WAT=""
if [[ -f "$OUT/near/remotecall.wat" ]]; then
  WAT="$OUT/near/remotecall.wat"
elif [[ -f "$OUT/near/RemoteCall.wat" ]]; then
  WAT="$OUT/near/RemoteCall.wat"
else
  WAT="$(find "$OUT/near" -name '*.wat' | head -n1 || true)"
fi
[[ -n "$WAT" && -f "$WAT" ]] || fail "NEAR WAT not written under $OUT/near"
require_contains "$WAT" "promise_create" "NEAR promise_create materialization"
GOLDEN_NEAR="$ROOT/Examples/Product/goldens/RemoteCall.near.wat"
if [[ -f "$GOLDEN_NEAR" ]]; then
  diff -u "$GOLDEN_NEAR" "$WAT" \
    || fail "NEAR WAT drifted from Examples/Product/goldens/RemoteCall.near.wat"
fi
require_file "$OUT/near/RemoteCall.near-artifact.json"

echo "portable-remote-call: Soroban (wasm-stellar-soroban list-targets)"
mkdir -p "$OUT/soroban"
"${proof_forge[@]}" build --target wasm-stellar-soroban --root . \
  --peers-demo \
  -o "$OUT/soroban" \
  --artifact-output "$OUT/soroban/RemoteCall.soroban-artifact.json" \
  "$SOURCE" \
  || fail "wasm-stellar-soroban build failed"
SOROBAN_WAT=""
if [[ -f "$OUT/soroban/remotecall.wat" ]]; then
  SOROBAN_WAT="$OUT/soroban/remotecall.wat"
elif [[ -f "$OUT/soroban/RemoteCall.wat" ]]; then
  SOROBAN_WAT="$OUT/soroban/RemoteCall.wat"
else
  SOROBAN_WAT="$(find "$OUT/soroban" -name '*.wat' | head -n1 || true)"
fi
[[ -n "$SOROBAN_WAT" && -f "$SOROBAN_WAT" ]] || fail "Soroban WAT not written under $OUT/soroban"
require_contains "$SOROBAN_WAT" "invoke_contract" "Soroban invoke_contract"
require_contains "$SOROBAN_WAT" "callee.example.near" "PeerMap nearDemo on Soroban"
if grep -Fq "promise_create" "$SOROBAN_WAT"; then
  fail "Soroban WAT must not contain promise_create"
fi
require_file "$OUT/soroban/RemoteCall.soroban-artifact.json"
# Binary validity: same EmitWat core as NEAR; wat2wasm proves well-formed wasm.
if command -v wat2wasm >/dev/null 2>&1; then
  SOROBAN_WASM="$OUT/soroban/RemoteCall.wasm"
  wat2wasm "$SOROBAN_WAT" -o "$SOROBAN_WASM" \
    || fail "Soroban wat2wasm failed for $SOROBAN_WAT"
  require_file "$SOROBAN_WASM"
  echo "portable-remote-call: Soroban wat2wasm ok → $SOROBAN_WASM"
else
  echo "portable-remote-call: wat2wasm missing; Soroban binary gate skipped" >&2
fi
echo "portable-remote-call: Soroban ok"

echo "portable-remote-call-multi-target: ok (evm · solana · near · soroban)"
