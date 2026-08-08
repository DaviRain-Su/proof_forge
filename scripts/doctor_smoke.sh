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

echo "doctor-smoke: I3 aleo snarkos honesty (not Tool Root; test_network probe)"
# snarkos is resolved via PROOF_FORGE_ALEO_SNARKOS / documented cargo-install path,
# never as $TOOL_ROOT/snarkos. Missing path → missing + installCommand.
missing_snarkos="$(mktemp -d /tmp/pf-doctor-snarkos-missing.XXXXXX)"
trap 'rm -rf "$empty" "$missing_snarkos" "$fake_snarkos_dir" 2>/dev/null || true' EXIT
set +e
out="$(
  PROOF_FORGE_TOOL_ROOT="$empty" \
  PROOF_FORGE_ALEO_SNARKOS="$missing_snarkos/snarkos" \
  "${py[@]}" --json --target aleo 2>&1
)"
code=$?
set -e
echo "$out" | head -40
[[ "$code" -eq 3 ]]
echo "$out" | rg -q '"name": "snarkos"'
echo "$out" | rg -q '"status": "missing"'
echo "$out" | rg -q 'features=test_network'
echo "$out" | rg -q 'installCommand'
echo "$out" | rg -q 'PROOF_FORGE_ALEO_SNARKOS|cargo install snarkos'
# Path must not be under tool root.
echo "$out" | rg -q "$missing_snarkos/snarkos"
if echo "$out" | rg -q "\"path\": \"$empty/snarkos\""; then
  echo "doctor-smoke: FAIL snarkos must not resolve under TOOL_ROOT" >&2
  exit 1
fi

echo "doctor-smoke: I3 prebuilt-without-feature is mismatch (never ok)"
fake_snarkos_dir="$(mktemp -d /tmp/pf-doctor-snarkos-fake.XXXXXX)"
fake_bin="$fake_snarkos_dir/snarkos"
cat >"$fake_bin" <<'EOF'
#!/bin/sh
# Pretend prebuilt release: version line without test_network feature.
echo "snarkos 4.9.0 unknown_branch unknown_commit features=[default]"
EOF
chmod +x "$fake_bin"
set +e
out="$(
  PROOF_FORGE_TOOL_ROOT="$empty" \
  PROOF_FORGE_ALEO_SNARKOS="$fake_bin" \
  "${py[@]}" --json --target aleo 2>&1
)"
code=$?
set -e
echo "$out" | head -40
[[ "$code" -eq 3 ]]
printf '%s' "$out" | /usr/bin/python3 -I -S -c '
import json, sys
doc = json.load(sys.stdin)
tools = {t["name"]: t for t in doc["targets"][0]["tools"]}
s = tools["snarkos"]
assert s["status"] == "mismatch", s
assert "test_network" in (s.get("hint") or "") or "test_network" in (s.get("installCommand") or "")
print("doctor-smoke: fake snarkos status=mismatch ok")
'

echo "doctor-smoke: I3 verified test_network binary is ok"
good_bin="$fake_snarkos_dir/snarkos-good"
cat >"$good_bin" <<'EOF'
#!/bin/sh
echo "snarkos 4.9.0 unknown_branch unknown_commit features=[default,snarkos-node-metrics,telemetry,test_network]"
EOF
chmod +x "$good_bin"
set +e
out="$(
  PROOF_FORGE_TOOL_ROOT="$empty" \
  PROOF_FORGE_ALEO_SNARKOS="$good_bin" \
  "${py[@]}" --json --target aleo 2>&1
)"
code=$?
set -e
echo "$out" | head -40
# leo missing under empty root → target still partial; snarkos itself must be ok
printf '%s' "$out" | /usr/bin/python3 -I -S -c '
import json, sys
doc = json.load(sys.stdin)
tools = {t["name"]: t for t in doc["targets"][0]["tools"]}
assert tools["snarkos"]["status"] == "ok", tools["snarkos"]
assert tools["leo"]["status"] == "missing"
assert doc["targets"][0]["status"] == "partial"
print("doctor-smoke: good snarkos status=ok (target partial due to leo)")
'

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
