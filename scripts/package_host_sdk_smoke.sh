#!/usr/bin/env bash
# Host SDK packaging + pip install smoke (engineering-dist).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
PREFIX="package-host-sdk-smoke"
die() { echo "${PREFIX}: $*" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/pf-host-sdk-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

OUT_DIR="$tmp/dist" bash scripts/package_host_sdk.sh
ver="$(tr -d '[:space:]' <VERSION)"
wheel="$(ls -1 "$tmp/dist"/*"${ver}"*.whl | head -1)"
[[ -f "$wheel" ]] || die "missing wheel"

venv="$tmp/venv"
/usr/bin/python3 -m venv "$venv"
# shellcheck disable=SC1091
source "$venv/bin/activate"
pip install -q --upgrade pip
pip install -q "$wheel"
python - <<'PY'
from proof_forge_sdk import ProofForgeClient, self_check
r = self_check()
assert r.get("ok") is True
assert "chain_catalog" in r.get("methods", [])
print("host-sdk-smoke: import+self_check ok")
PY
deactivate
echo "${PREFIX}: HOST-SDK-SMOKE-OK"
exit 0
