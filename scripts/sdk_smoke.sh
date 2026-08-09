#!/usr/bin/env bash
# Focused smoke for SDK-V0: self-check + list-targets + doctor + dry-run install +
# load-manifest. Not host-heavy; not ordinary ci evidence of full toolchain completeness.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

sdk=(/usr/bin/python3 -I "$root/tools/sdk/proof_forge_sdk.py")
cli="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"

echo "sdk-smoke: self-check"
out="$("${sdk[@]}" --self-check)"
echo "$out" | rg -q '"ok": true'
echo "$out" | rg -q 'list_targets'
echo "$out" | rg -q 'load_output_manifest'
echo "$out" | rg -q '"local"'
echo "$out" | rg -q 'chain_catalog'
echo "$out" | rg -q 'proof-forge.sdk.self-check.v1'

echo "sdk-smoke: chain-catalog --target aleo"
cat_out="$("${sdk[@]}" chain-catalog --target aleo)"
echo "$cat_out" | rg -q 'proof-forge.chain-client-catalog.v1'
echo "$cat_out" | rg -q '"id": "aleo"'

if [[ ! -x "$cli" ]]; then
  echo "sdk-smoke: FAIL proof-forge-next missing at $cli (lake build first)" >&2
  exit 1
fi
export PROOF_FORGE_ROOT="$root"
export PROOF_FORGE_CLI="$cli"

echo "sdk-smoke: list-targets via SDK"
lt="$("${sdk[@]}" list-targets)"
echo "$lt" | rg -q '"ok": true'
echo "$lt" | rg -q 'proof-forge.cli.list-targets.v1'
echo "$lt" | rg -q '"id": "evm"'
echo "$lt" | rg -q '"id": "quint"'

echo "sdk-smoke: doctor --target quint (body usable even if tools missing)"
# Doctor may exit non-zero at product layer; SDK CLI exits 0 when parsed body present.
doc="$("${sdk[@]}" doctor --target quint)"
echo "$doc" | rg -q 'proof-forge.doctor.v1'
echo "$doc" | rg -q '"id": "quint"'

echo "sdk-smoke: install dry-run quint into temp tool root"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export PROOF_FORGE_TOOL_ROOT="$tmp/tool-root"
inst="$("${sdk[@]}" install --targets quint --dry-run)"
echo "$inst" | rg -q 'proof-forge.install.v1'
echo "$inst" | rg -q '"dryRun": true'
echo "$inst" | rg -q 'would-install|would-skip|"status"'

echo "sdk-smoke: load-manifest on existing product tree (if present)"
sample=""
for cand in \
  "$root/build/v2/noir-acir-ir6-acir" \
  "$root/build/v2/aleo-compile-compare-acc"
do
  if [[ -f "$cand/manifest.json" ]]; then
    sample="$cand"
    break
  fi
done
if [[ -n "$sample" ]]; then
  man="$("${sdk[@]}" load-manifest "$sample")"
  echo "$man" | rg -q 'proof-forge.output.v1'
  echo "$man" | rg -q '"files"'
  # Python API import path (-I ignores PYTHONPATH; load module by file path)
  PROOF_FORGE_ROOT="$root" PROOF_FORGE_CLI="$cli" \
    /usr/bin/python3 -I -S - "$root/tools/sdk/proof_forge_sdk.py" "$sample" <<'PY'
import importlib.util
import sys
from pathlib import Path

sdk_path = Path(sys.argv[1])
sample = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("proof_forge_sdk", sdk_path)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
sys.modules["proof_forge_sdk"] = mod  # required before exec for dataclasses
spec.loader.exec_module(mod)
c = mod.ProofForgeClient()
m = c.load_output_manifest(sample)
assert m.get("schemaVersion") == mod.SCHEMA_OUTPUT or m.get("schema") == mod.SCHEMA_OUTPUT
# design-only soft gate on build helper
r = c.build(
    "Examples/Counter.lean",
    module="Examples.Counter",
    target="soroban",
    output="/tmp/x",
)
assert r.ok is False and r.error == "usage"
print("sdk-smoke: python API import ok")
PY
else
  echo "sdk-smoke: WARN no sample output tree; skip load-manifest (still pass self-check/list/doctor/install)"
fi

echo "sdk-smoke: PASS"
