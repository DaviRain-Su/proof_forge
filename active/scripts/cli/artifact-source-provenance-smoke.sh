#!/usr/bin/env bash
# SourceIdentity and Lean tool provenance must describe the invocation that
# produced the artifact, not how the CLI binary itself was compiled.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.foundry/bin:${HOME}/.local/bin:${PATH}"

OUT="${PROOF_FORGE_ARTIFACT_SOURCE_PROVENANCE_OUT:-build/artifact-source-provenance}"
SOURCE="Examples/Product/Counter.lean"
rm -rf "$OUT"
mkdir -p "$OUT/evm" "$OUT/near" "$OUT/fixture"

lake build proof-forge >/dev/null

lake env proof-forge build --target evm --root . \
  --yul-output "$OUT/evm/Counter.yul" \
  --artifact-output "$OUT/evm/artifact.json" \
  -o "$OUT/evm/Counter.bin" "$SOURCE" >/dev/null

lake env proof-forge build --target wasm-near --root . \
  --artifact-output "$OUT/near/artifact.json" \
  -o "$OUT/near" "$SOURCE" >/dev/null

lake env proof-forge emit --target evm --fixture value-vault --format bytecode \
  --yul-output "$OUT/fixture/ValueVault.yul" \
  --artifact-output "$OUT/fixture/artifact.json" \
  -o "$OUT/fixture/ValueVault.bin" >/dev/null

python3 - "$SOURCE" "$OUT/evm/artifact.json" "$OUT/near/artifact.json" \
  "$OUT/fixture/artifact.json" <<'PY'
import json
import sys

source_path, evm_path, near_path, fixture_path = sys.argv[1:]
pin = open("lean-toolchain", encoding="utf-8").read().strip()
expected_observed = pin.rsplit(":", 1)[-1]
if expected_observed.startswith("v"):
    expected_observed = expected_observed[1:]

for target, path in (("evm", evm_path), ("wasm-near", near_path)):
    bundle = json.load(open(path, encoding="utf-8"))["artifactBundle"]
    source = bundle["source"]
    assert source["kind"] == "contract-sdk", (target, source)
    assert source["path"] == source_path, (target, source)
    assert source["leanElaborated"] is True, (target, source)
    lean = next(t for t in bundle["toolchain"] if t.get("stage") == "source-elaboration")
    assert lean["tool"] == "lean" and lean["available"] is True, lean
    assert lean["declaredVersion"] == pin, lean
    assert lean["observedVersion"] == expected_observed, lean
    assert lean["version"] == lean["observedVersion"], lean

fixture = json.load(open(fixture_path, encoding="utf-8"))["artifactBundle"]
source = fixture["source"]
assert source["kind"] == "portable-ir", source
assert source["path"] is None, source
assert source["leanElaborated"] is False, source
assert not any(t.get("stage") == "source-elaboration" for t in fixture["toolchain"]), fixture["toolchain"]

print("artifact-source-provenance: ok (EVM/NEAR source path + embedded fixture + declared/observed Lean)")
PY
