#!/usr/bin/env bash
# Focused smoke for product install (I1): proof-forge.install.v1 + dry-run / idempotent.
# Not host-heavy full --all-core; not ordinary ci evidence of tool completeness.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

py=(/usr/bin/python3 -I -S "$root/scripts/proof_forge_install.py")

echo "install-smoke: usage without --yes fails closed"
set +e
err="$("${py[@]}" --targets quint 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
echo "$err" | rg -q 'requires --yes'

echo "install-smoke: dry-run does not require --yes"
out="$("${py[@]}" --targets quint --dry-run --json)"
echo "$out" | head -30
echo "$out" | rg -q '"schema": "proof-forge.install.v1"'
echo "$out" | rg -q '"dryRun": true'
echo "$out" | rg -q '"name": "jv"'

echo "install-smoke: design-only rejected"
set +e
err="$("${py[@]}" --targets soroban --yes 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
echo "$err" | rg -q 'design-only'

echo "install-smoke: materialize quint (jv) into temp tool root (cached asset preferred)"
tmp_root="$(mktemp -d /tmp/pf-install-smoke.XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT
set +e
out="$(PROOF_FORGE_TOOL_ROOT="$tmp_root" "${py[@]}" --targets quint --yes --json 2>&1)"
code=$?
set -e
echo "$out" | head -40
[[ "$code" -eq 0 ]]
echo "$out" | rg -q '"schema": "proof-forge.install.v1"'
echo "$out" | rg -q '"name": "jv"'
# installed or skipped (if somehow pre-seeded)
echo "$out" | rg -q '"status": "(installed|skipped)"'
[[ -x "$tmp_root/jv" ]]

echo "install-smoke: second run is idempotent skip"
out="$(PROOF_FORGE_TOOL_ROOT="$tmp_root" "${py[@]}" --targets quint --yes --json)"
echo "$out" | rg -q '"status": "skipped"'
[[ "$code" -eq 0 ]]

echo "install-smoke: dry-run against present root reports would-skip"
out="$(PROOF_FORGE_TOOL_ROOT="$tmp_root" "${py[@]}" --targets quint --dry-run --json)"
echo "$out" | rg -q '"status": "would-skip"'

echo "install-smoke: dry-run reports but retains retired tool-root node"
printf 'retired\n' > "$tmp_root/leo"
out="$(PROOF_FORGE_TOOL_ROOT="$tmp_root" "${py[@]}" --targets aleo --dry-run --json)"
echo "$out" | rg -q 'would remove retired tool-root node: leo'
[[ -f "$tmp_root/leo" ]]

echo "install-smoke: install prunes retired tool-root node without network"
out="$(PROOF_FORGE_TOOL_ROOT="$tmp_root" "${py[@]}" --targets aleo --yes --json)"
echo "$out" | rg -q 'removed retired tool-root node: leo'
[[ ! -e "$tmp_root/leo" ]]

echo "install-smoke: Aleo and Psy remain zero-tool with --with-runtime"
for target in aleo psy; do
  out="$(
    PROOF_FORGE_TOOL_ROOT="$tmp_root" \
    "${py[@]}" --targets "$target" --with-runtime --dry-run --json 2>&1
  )"
  printf '%s' "$out" | /usr/bin/python3 -I -S -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["tools"] == [], doc
assert doc["notes"] == [], doc
'
done

if [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
  cli="$root/.lake/build/bin/proof-forge-next"
  echo "install-smoke: CLI install --dry-run --json --targets quint"
  set +e
  out="$("$cli" install --targets quint --dry-run --json 2>&1)"
  code=$?
  set -e
  echo "$out" | head -20
  echo "install-smoke: CLI exit=$code"
  echo "$out" | rg -q '"schema": "proof-forge.install.v1"'
else
  echo "install-smoke: skip CLI wire (proof-forge-next not built)"
fi

echo "install-smoke: ok"
