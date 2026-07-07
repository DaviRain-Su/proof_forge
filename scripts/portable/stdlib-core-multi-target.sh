#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

OUT="${PORTABLE_STDLIB_CORE_OUT:-build/portable-stdlib-core}"
MODULES=(Ownable Pausable ReentrancyGuard)

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "file not written: $1"
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"
command -v solc >/dev/null 2>&1 || fail "solc not on PATH"
command -v cast >/dev/null 2>&1 || fail "cast not on PATH"

rm -rf "$OUT"
mkdir -p "$OUT"

(cd "$ROOT" && lake build proof-forge Examples.Shared.Ownable Examples.Shared.Pausable Examples.Shared.ReentrancyGuard >/dev/null)

expected_entries() {
  case "$1" in
    Ownable) echo "owner,transferOwnership,renounceOwnership,init" ;;
    Pausable) echo "paused,pause,unpause" ;;
    ReentrancyGuard) echo "acquire,release,locked" ;;
    *) fail "unknown stdlib module: $1" ;;
  esac
}

set_evm_metadata_args() {
  case "$1" in
    Ownable)
      metadata_args=( \
        --expect-entrypoint owner:8da5cb5b \
        --expect-entrypoint transferOwnership:d23e8489 \
        --expect-entrypoint renounceOwnership:715018a6 \
        --expect-entrypoint init:e1c7392a \
      )
      ;;
    Pausable)
      metadata_args=( \
        --expect-entrypoint paused:5c975abb \
        --expect-entrypoint pause:8456cb59 \
        --expect-entrypoint unpause:3f4ba83a \
      )
      ;;
    ReentrancyGuard)
      metadata_args=( \
        --expect-entrypoint acquire:a7134f73 \
        --expect-entrypoint release:86d1a69f \
        --expect-entrypoint locked:cf309012 \
      )
      ;;
    *) fail "unknown stdlib module: $1" ;;
  esac
}

for module in "${MODULES[@]}"; do
  source="Examples/Shared/${module}.lean"
  module_out="$OUT/$module"
  mkdir -p "$module_out/evm" "$module_out/solana" "$module_out/near"

  echo "portable-stdlib-core: $module EVM"
  "${proof_forge[@]}" build --target evm --root . \
    -o "$module_out/evm/${module}.bin" \
    --yul-output "$module_out/evm/${module}.yul" \
    --artifact-output "$module_out/evm/${module}.proof-forge-artifact.json" \
    "$source"
  diff -u "Examples/Evm/Contracts/stdlib/${module}.golden.yul" "$module_out/evm/${module}.yul"
  metadata_args=()
  set_evm_metadata_args "$module"
  python3 scripts/evm/validate-artifact-metadata.py \
    --root "$ROOT" \
    --expect-fixture "$module" \
    --expect-source-kind contract-sdk \
    "${metadata_args[@]}" \
    "$module_out/evm/${module}.proof-forge-artifact.json"

  echo "portable-stdlib-core: $module Solana sBPF"
  "${proof_forge[@]}" build --target solana-sbpf-asm --root . \
    -o "$module_out/solana/${module}.s" \
    --artifact-output "$module_out/solana/${module}.solana-artifact.json" \
    "$source"
  require_file "$module_out/solana/${module}.s"
  require_file "$module_out/solana/manifest.toml"
  require_file "$module_out/solana/proof-forge-idl.json"
  require_file "$module_out/solana/proof-forge-client.ts"
  require_file "$module_out/solana/${module}.solana-artifact.json"

  echo "portable-stdlib-core: $module NEAR/Wasm"
  "${proof_forge[@]}" build --target wasm-near --root . \
    -o "$module_out/near" \
    --artifact-output "$module_out/near/${module}.near-artifact.json" \
    "$source"
  lower="$(tr '[:upper:]' '[:lower:]' <<<"$module")"
  require_file "$module_out/near/${lower}.wat"
  require_file "$module_out/near/${lower}.wasm"
  python3 scripts/near/validate-emitwat-metadata.py \
    "$module_out/near/${module}.near-artifact.json" \
    --expected-fixture "$lower" \
    --expected-module "$module" \
    --expected-entrypoints "$(expected_entries "$module")" \
    --expected-source-kind contract-sdk

  python3 - "$module" "$(expected_entries "$module")" \
    "$module_out/solana/${module}.solana-artifact.json" \
    "$module_out/solana/manifest.toml" <<'PY'
import json
import sys

module, entries_csv, artifact_path, manifest_path = sys.argv[1:]
entries = entries_csv.split(",")
artifact = json.load(open(artifact_path))
manifest = open(manifest_path).read()
assert artifact["target"] == "solana-sbpf-asm"
assert artifact["fixture"] == module
assert artifact["sourceKind"] == "contract-sdk"
assert artifact["sourceModule"] == module
for entry in entries:
    assert f'name = "{entry}"' in manifest, f"missing Solana manifest entry {entry}"
print(f"portable-stdlib-core {module} solana artifact: ok")
PY
done

echo "portable-stdlib-core-multi-target: ok"
