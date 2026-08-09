#!/usr/bin/env bash
# Focused smoke for product doctor (I0): proof-forge.doctor.v1 + CLI wire.
# Not host-heavy; not ordinary ci evidence of tool completeness.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

py=(/usr/bin/python3 -I -S "$root/scripts/proof_forge_doctor.py")

echo "doctor-smoke: direct engine (default tool root or env)"
set +e
out="$("${py[@]}" --json --target noir 2>&1)"
code=$?
set -e
echo "$out" | head -20
echo "doctor-smoke: noir exit=$code (0 ok / 3 missing-partial-mismatch)"
echo "$out" | rg -q '"schema": "proof-forge.doctor.v1"'
echo "$out" | rg -q '"id": "noir"'

echo "doctor-smoke: missing tool root fail closed"
tmp_root="$(mktemp -d /tmp/pf-doctor-missing.XXXXXX)"
rm -rf "$tmp_root"
set +e
err="$(PROOF_FORGE_TOOL_ROOT="$tmp_root" "${py[@]}" --json 2>&1)"
code=$?
set -e
echo "$err"
[[ "$code" -eq 3 ]]
echo "$err" | rg -q 'PF-TOOLCHAIN-MISSING:'

echo "doctor-smoke: design-only unsupported"
out="$("${py[@]}" --json --target soroban)"
echo "$out" | rg -q '"status": "unsupported"'

echo "doctor-smoke: empty root reports missing tools (not crash)"
empty="$(mktemp -d /tmp/pf-doctor-empty.XXXXXX)"
trap 'rm -rf "$empty"' EXIT
set +e
out="$(PROOF_FORGE_TOOL_ROOT="$empty" "${py[@]}" --json --target solana 2>&1)"
code=$?
set -e
echo "$out" | head -30
[[ "$code" -eq 3 ]]
echo "$out" | rg -q '"status": "missing"'
echo "$out" | rg -q '"name": "sbpf"'

echo "doctor-smoke: Aleo and Psy are explicit zero-tool targets"
for target in aleo psy; do
  out="$(PROOF_FORGE_TOOL_ROOT="$empty" "${py[@]}" --json --target "$target")"
  printf '%s' "$out" | /usr/bin/python3 -I -S -c '
import json, sys
doc = json.load(sys.stdin)
target = doc["targets"][0]
assert target["status"] == "ok", target
assert target["tools"] == [], target
'
done

if [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
  cli="$root/.lake/build/bin/proof-forge-next"
  echo "doctor-smoke: CLI doctor --json --target noir"
  set +e
  out="$(PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-}" "$cli" doctor --json --target noir 2>&1)"
  code=$?
  set -e
  echo "$out" | head -20
  echo "doctor-smoke: CLI exit=$code"
  echo "$out" | rg -q '"schema": "proof-forge.doctor.v1"'
else
  echo "doctor-smoke: skip CLI wire (proof-forge-next not built)"
fi

echo "doctor-smoke: ok"
