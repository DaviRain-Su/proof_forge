#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

OUT="${PAUSABLE_TARGET_FIRST_OUT:-build/canonical/pausable-target-first}"
SOURCE=Examples/Product/Pausable.lean

fail() {
  printf 'pausable-target-first: %s\n' "$1" >&2
  exit 1
}

for tool in lake python3 solc cast wat2wasm; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

rm -rf "$OUT"
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

lake build proof-forge Examples.Product.Pausable >/dev/null

lake env proof-forge build --target evm --root . \
  -o "$OUT/evm/Pausable.bin" \
  --yul-output "$OUT/evm/Pausable.yul" \
  --artifact-output "$OUT/evm/Pausable.proof-forge-artifact.json" \
  "$SOURCE"
python3 scripts/evm/validate-artifact-metadata.py \
  --root "$ROOT" \
  --expect-fixture Pausable \
  --expect-source-kind contract-source-authored \
  --expect-entrypoint paused:5c975abb \
  --expect-entrypoint pause:8456cb59 \
  --expect-entrypoint unpause:3f4ba83a \
  "$OUT/evm/Pausable.proof-forge-artifact.json"
cmp Examples/Backend/Evm/Contracts/stdlib/Pausable.golden.yul "$OUT/evm/Pausable.yul" ||
  fail 'direct EVM Yul differs from the reviewed golden'

lake env proof-forge build --target solana-sbpf-asm --format s --root . \
  -o "$OUT/solana/Pausable.s" \
  --artifact-output "$OUT/solana/Pausable.proof-forge-artifact.json" \
  "$SOURCE"
rg -q 'assert_fail' "$OUT/solana/Pausable.s" || fail 'Solana artifact lost pause guards'
rg -q 'stxdw \[r1\+96\]' "$OUT/solana/Pausable.s" ||
  fail 'Solana artifact lost program-state writes'

lake env proof-forge build --target wasm-near --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/near/Pausable.proof-forge-artifact.json" \
  "$SOURCE"
python3 scripts/near/validate-emitwat-metadata.py \
  "$OUT/near/Pausable.proof-forge-artifact.json" \
  --expected-fixture pausable \
  --expected-module Pausable \
  --expected-entrypoints paused,pause,unpause \
  --expected-source-kind contract-source-authored
test -s "$OUT/near/pausable.wasm" || fail 'NEAR final Wasm artifact is missing'

python3 - "$OUT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
artifacts = [
    ("evm", root / "evm/Pausable.proof-forge-artifact.json"),
    ("solana-sbpf-asm", root / "solana/Pausable.proof-forge-artifact.json"),
    ("wasm-near", root / "near/Pausable.proof-forge-artifact.json"),
]
for target, path in artifacts:
    artifact = json.loads(path.read_text())
    assert artifact["target"] == target, (path, artifact.get("target"))
    assert artifact["sourceKind"] == "contract-source-authored", path
    assert artifact["sourceModule"] == "Pausable", path
    assert artifact["irVersion"] == "canonical-core-v1", path

retired = list(root.rglob("*contract-spec*")) + list(root.rglob("*ir-module*"))
assert not retired, f"retired compatibility sidecars emitted: {retired}"
PY

printf 'pausable-target-first: ok\n'
