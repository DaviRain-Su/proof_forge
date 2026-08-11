#!/usr/bin/env bash
# ProofShip rwa-share-v1 — regenerate dapp artifacts + gate-report.json.
# Runs the real product gates and copies the outputs into dapp/public/.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"
proj="proofship/rwa-share-v1"
dapp="$proj/dapp/public"
cli="$root/.lake/build/bin/proof-forge-next"
[[ -x "$cli" ]] || { echo "build-dapp-artifacts: CLI missing (just build)" >&2; exit 70; }

die() { echo "build-dapp-artifacts: FAIL: $*" >&2; exit 1; }

# 1. golden gate (check + build + inspect) -------------------------------------
"$proj/scripts/gate.sh" RwaShareRegistry.lean RwaShareRegistry >/dev/null
out="$proj/out-evm-rwashareregistry"
[[ -s "$out/RwaShareRegistry.abi.json" && -s "$out/RwaShareRegistry.bin" ]] \
  || die "golden artifacts missing"
cp "$out/RwaShareRegistry.abi.json" "$dapp/artifacts/RwaShareRegistry.abi.json"
cp "$out/RwaShareRegistry.bin" "$dapp/artifacts/RwaShareRegistry.bin"

check_out="$("$cli" check src/RwaShareRegistry.lean --module RwaShareRegistry --root "$proj")"
src_digest="$(echo "$check_out" | grep '^sourceDigest=' | cut -d= -f2)"
sem_digest="$(echo "$check_out" | grep '^semanticDigest=' | cut -d= -f2)"
inspect_out="$("$cli" inspect --output-dir "$out")"
oset_digest="$(echo "$inspect_out" | grep '^outputSetDigest=' | cut -d= -f2)"

# 2. proof positives ------------------------------------------------------------
proofs_json=""
for name in EvenStep ShareConservation; do
  pout="$("$cli" check "proof-twin/$name.lean" --module "$name" --root "$proj")" \
    || die "proof-twin $name failed to certify"
  echo "$pout" | grep -q "proofStatus=certified" || die "$name not certified"
  pd="$(echo "$pout" | grep '^proofCertificationDigest=' | cut -d= -f2)"
  proofs_json+="$(/usr/bin/python3 -I -S -c "
import json
print(json.dumps({
  'file': 'proof-twin/$name.lean',
  'program': '$name',
  'proofStatus': 'certified',
  'proofTheoremCount': 1,
  'proofCertificationDigest': '$pd',
}))"),"
done
proofs_json="${proofs_json%,}"

# 3. negative (fast inventory rejection) -----------------------------------------
set +e
neg_out="$("$cli" check proof-twin/EvenStepBad.lean --module EvenStepBad --root "$proj" 2>&1)"
neg_code=$?
set -e
[[ $neg_code -ne 0 ]] || die "EvenStepBad unexpectedly passed"
neg_diag="$(echo "$neg_out" | head -1)"

# 4. anvil smoke ------------------------------------------------------------------
anvil_result="pass"
"$proj/scripts/anvil-check.sh" >/dev/null 2>&1 || anvil_result="FAIL"
[[ "$anvil_result" == "pass" ]] || die "anvil smoke failed"

# 5. write report ------------------------------------------------------------------
/usr/bin/python3 -I -S - "$dapp/gate-report.json" <<EOF
import json, sys, datetime
report = {
  "schema": "proofship.gate-report.v1",
  "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
  "program": "RwaShareRegistry",
  "sourceDigest": "$src_digest",
  "semanticDigest": "$sem_digest",
  "build": {
    "target": "evm",
    "profile": "evm-yul-solc-0.8.34-v1",
    "deployable": True,
    "outputSetDigest": "$oset_digest",
  },
  "proofs": json.loads('''[$proofs_json]'''),
  "negative": {
    "file": "proof-twin/EvenStepBad.lean",
    "exitCode": $neg_code,
    "diagnostic": '''$neg_diag''',
    "artifacts": "zero artifacts",
  },
  "anvil": {"scenarios": 9, "result": "pass"},
}
with open(sys.argv[1], "w") as fh:
    json.dump(report, fh, indent=2)
    fh.write("\n")
EOF

echo "build-dapp-artifacts: ok → $dapp (abi + bin + gate-report.json)" >&2
