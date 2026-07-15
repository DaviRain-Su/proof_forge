#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/proof-forge-v2-isolation.XXXXXX")"
cleanup() {
  rm -rf -- "$tmp"
}
trap cleanup EXIT

if find "$root" -type l -not -path "$root/.lake/*" -not -path "$root/build/*" | grep -q .; then
  echo "isolation-check: symlinks are forbidden" >&2
  exit 1
fi

if rg -n '(^|[[:space:]])import[[:space:]]+ProofForge([[:space:].]|$)' \
    "$root/ProofForgeV2" "$root/Tests" "$root/Examples"; then
  echo "isolation-check: parent ProofForge import detected" >&2
  exit 1
fi

tar --exclude='.lake' --exclude='build' --exclude='.proof-forge-next' --exclude='.git' \
  -C "$root" -cf - . | tar -C "$tmp" -xf -

env -u LEAN_PATH -u PROOF_FORGE_V1 -u PROOF_FORGE_BIN \
  lake --dir "$tmp" build ProofForgeV2 proof_forge_next proof_forge_next_tests
env -u LEAN_PATH -u PROOF_FORGE_V1 -u PROOF_FORGE_BIN \
  lake --dir "$tmp" env "$tmp/.lake/build/bin/proof-forge-next-tests"
python3 "$tmp/scripts/docs_check.py"

echo "isolation-check: ok"
