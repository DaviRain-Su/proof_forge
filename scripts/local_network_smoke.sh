#!/usr/bin/env bash
# Focused no-network smoke for host-heavy local CLI wrappers.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

cli="$root/.lake/build/bin/proof-forge-next"
if [[ ! -x "$cli" ]]; then
  echo "local-cli-smoke: FAIL proof-forge-next not built (lake build proof_forge_next)" >&2
  exit 1
fi

echo "local-cli-smoke: local without --target is usage exit 2"
set +e
err="$("$cli" local 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'requires --target' <<<"$err"

echo "local-cli-smoke: design-only local rejected"
set +e
err="$("$cli" local --target soroban 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'design-only' <<<"$err"

echo "local-cli-smoke: removed network command is rejected"
set +e
err="$("$cli" network --target aleo --broadcast 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
! grep -q '^  proof-forge-next network' <<<"$err"

echo "local-cli-smoke: removed Aleo and Psy local lanes reject before spawn"
for target in aleo psy; do
  set +e
  err="$("$cli" local --target "$target" 2>&1)"
  code=$?
  set -e
  [[ "$code" -eq 2 ]]
  grep -q "local has no package-script path for target '$target'" <<<"$err"
done

echo "local-cli-smoke: ok"
