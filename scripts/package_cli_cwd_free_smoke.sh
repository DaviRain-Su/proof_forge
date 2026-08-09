#!/usr/bin/env bash
# Smoke: package CLI dist, run doctor from a foreign CWD (no monorepo).
# Engineering-dist only. Not formal Stage-0.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="package-cli-cwd-free-smoke"
PF="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"
die() { echo "${PREFIX}: $*" >&2; exit 1; }

[[ -x "$PF" ]] || die "missing CLI $PF; lake build proof_forge_next first"

# Require version command (REL-CLI-0).
"$PF" version --json | grep -q engineering-dist || die "version identity missing"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/pf-cwd-free.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

echo "${PREFIX}: package dist → $tmp/dist"
bash "$root/scripts/package_cli_dist.sh" --out "$tmp/dist"

archive="$(ls "$tmp/dist"/proof-forge-next-*-*.tar.gz | head -1)"
[[ -f "$archive" ]] || die "missing archive"
mkdir -p "$tmp/extract"
tar -xzf "$archive" -C "$tmp/extract"
stage="$(find "$tmp/extract" -maxdepth 1 -type d -name 'proof-forge-next-*' | head -1)"
[[ -d "$stage" ]] || die "missing stage"
[[ -f "$stage/scripts/proof_forge_doctor.py" ]] || die "dist missing doctor engine"
[[ -x "$stage/bin/proof-forge-next" ]] || die "dist missing binary"

foreign="$tmp/foreign-cwd"
mkdir -p "$foreign"
cd "$foreign"

echo "${PREFIX}: doctor from foreign CWD via bin layout (no PROOF_FORGE_ROOT)"
# Unset root so install layout (parent of bin/) is used.
unset PROOF_FORGE_ROOT || true
out="$("$stage/bin/proof-forge-next" doctor --target quint --json 2>&1)" || code=$?
code="${code:-0}"
# doctor may exit 3 when tools missing — still success for CWD-free discovery
if [[ "$code" -ne 0 && "$code" -ne 3 ]]; then
  echo "$out" >&2
  die "doctor failed with exit $code (expected 0 or 3)"
fi
echo "$out" | grep -q 'proof-forge.doctor.v1' || die "missing doctor schema in: $out"
echo "${PREFIX}: doctor ok (exit=$code) from $foreign"

echo "${PREFIX}: doctor via PROOF_FORGE_ROOT + PROOF_FORGE_CLI from foreign CWD"
export PROOF_FORGE_ROOT="$stage"
export PROOF_FORGE_CLI="$stage/bin/proof-forge-next"
out2="$("$PROOF_FORGE_CLI" doctor --target quint --json 2>&1)" || code2=$?
code2="${code2:-0}"
if [[ "$code2" -ne 0 && "$code2" -ne 3 ]]; then
  echo "$out2" >&2
  die "doctor via env failed exit $code2"
fi
echo "$out2" | grep -q 'proof-forge.doctor.v1' || die "missing schema via env"

echo "${PREFIX}: CWD-FREE-SMOKE-OK"
exit 0
