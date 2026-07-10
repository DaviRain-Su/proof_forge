#!/usr/bin/env bash
# N1.7: NEAR deploy metadata honesty.
#
# Build-time proof-forge-deploy.json must label offline-only execution and must
# never claim network broadcast / account deployment without a broadcast tool.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_DEPLOY_HONESTY_OUT:-build/near-deploy-honesty}"

fail() {
  echo "deploy-honesty: FAIL: $1" >&2
  exit 1
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null

echo "=== N1.7: build Counter wasm-near (deploy metadata) ==="
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Product/Counter.lean \
  || fail "Counter build failed"

ARTIFACT="$(find "$OUT_DIR" -name 'proof-forge-artifact.json' | head -n1)"
DEPLOY="$(find "$OUT_DIR" -name 'proof-forge-deploy.json' | head -n1)"
test -s "$ARTIFACT" || fail "missing proof-forge-artifact.json"
test -s "$DEPLOY" || fail "missing proof-forge-deploy.json"

echo "artifact: $ARTIFACT"
echo "deploy:   $DEPLOY"

python3 scripts/near/validate-emitwat-metadata.py \
  "$ARTIFACT" \
  --expected-fixture counter \
  --expected-module Counter \
  --expected-entrypoints initialize,increment,get \
  --expected-source-kind contract-sdk \
  || fail "validate-emitwat-metadata failed"

python3 - "$DEPLOY" "$ARTIFACT" <<'PY' || fail "deploy honesty field checks failed"
import json
import sys
from pathlib import Path

deploy_path = Path(sys.argv[1])
artifact_path = Path(sys.argv[2])
deploy = json.loads(deploy_path.read_text())
artifact = json.loads(artifact_path.read_text())

dep = deploy.get("deployment") or {}
required = {
    "mode": "local-offline-host",
    "status": "not-broadcast",
    "broadcast": "not-generated",
    "networkDeploy": "not-generated",
    "localExecutor": "runtime/offline-host",
    "nearSandbox": "not-generated",
}
for key, expected in required.items():
    actual = dep.get(key)
    if actual != expected:
        raise SystemExit(f"deployment.{key}: expected {expected!r}, got {actual!r}")

if dep.get("broadcastArtifact") is not None:
    raise SystemExit(f"deployment.broadcastArtifact must be null, got {dep.get('broadcastArtifact')!r}")
if dep.get("nearAccountId") is not None:
    raise SystemExit(f"deployment.nearAccountId must be null, got {dep.get('nearAccountId')!r}")

note = dep.get("note") or ""
if "offline-host" not in note:
    raise SystemExit("deployment.note must mention offline-host")
if "not generated" not in note.lower() and "not-generated" not in note.lower():
    # note uses prose "are not generated"
    if "not generated" not in note and "is not generated" not in note and "are not generated" not in note:
        raise SystemExit("deployment.note must state network deploy is not generated")

# Forbid overclaim strings anywhere in the deploy JSON text.
text = deploy_path.read_text().lower()
for forbidden in (
    '"broadcast": "passed"',
    '"broadcast":"passed"',
    '"status": "broadcasted"',
    '"status": "deployed"',
    '"networkdeploy": "passed"',
    '"networkdeploy":"passed"',
):
    if forbidden.replace(" ", "") in text.replace(" ", ""):
        raise SystemExit(f"deploy manifest overclaims live deploy: found {forbidden}")

validation = artifact.get("validation") or {}
if validation.get("deployManifest") != "passed":
    raise SystemExit(
        "validation.deployManifest must be passed (manifest written), "
        f"got {validation.get('deployManifest')!r}"
    )
# offlineHost may stay pending until a host smoke; must never be a broadcast claim.
if validation.get("offlineHost") not in (None, "pending", "passed", "skipped", "unavailable"):
    raise SystemExit(f"unexpected validation.offlineHost={validation.get('offlineHost')!r}")
for key, value in validation.items():
    if "broadcast" in key.lower() and value == "passed":
        raise SystemExit(f"validation.{key}=passed is forbidden without a broadcast tool")

print("deploy-honesty fields: ok")
PY

echo "deploy-honesty: ok (mode=local-offline-host, broadcast=not-generated, status=not-broadcast)"
