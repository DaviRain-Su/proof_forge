#!/usr/bin/env bash
# Focused smoke for product local/network (I2): parse wire + missing-tool exit 2.
# Not host-heavy full sandbox/devnet/network success; not ordinary ci evidence.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

cli=""
if [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
  cli="$root/.lake/build/bin/proof-forge-next"
else
  echo "local-network-smoke: FAIL proof-forge-next not built (lake build proof_forge_next)" >&2
  exit 1
fi

echo "local-network-smoke: local without --target is usage exit 2"
set +e
err="$("$cli" local 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
echo "$err" | rg -q 'requires --target'

echo "local-network-smoke: network without --broadcast is usage exit 2"
set +e
err="$("$cli" network --target aleo 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
echo "$err" | rg -q 'requires explicit --broadcast'

echo "local-network-smoke: design-only local rejected"
set +e
err="$("$cli" local --target soroban 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
echo "$err" | rg -q 'design-only'

echo "local-network-smoke: unsupported network target"
set +e
err="$("$cli" network --target solana --broadcast 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
echo "$err" | rg -q 'no package-script path'

echo "local-network-smoke: aleo local missing tool root → exit 2 + PF-TOOLCHAIN-MISSING"
tmp_root="$(mktemp -d /tmp/pf-local-missing.XXXXXX)"
rm -rf "$tmp_root"
set +e
out="$(PROOF_FORGE_TOOL_ROOT="$tmp_root" "$cli" local --target aleo --mode sandbox --json -- --skip-run 2>&1)"
code=$?
set -e
echo "$out" | head -40
[[ "$code" -eq 2 ]]
# PF-JCS has no spaces after ':' — match compact form.
echo "$out" | rg -q '"schema":"proof-forge.local.v1"'
echo "$out" | rg -q '"status":"toolchain-missing"'
echo "$out" | rg -q 'PF-TOOLCHAIN-MISSING'

echo "local-network-smoke: aleo network missing tool + --broadcast → exit 2"
set +e
out="$(PROOF_FORGE_TOOL_ROOT="$tmp_root" "$cli" network --target aleo --broadcast --json 2>&1)"
code=$?
set -e
echo "$out" | head -40
[[ "$code" -eq 2 ]]
echo "$out" | rg -q '"schema":"proof-forge.network.v1"'
echo "$out" | rg -q '"status":"toolchain-missing"'

echo "local-network-smoke: aleo network with tool present but no credentials → PF-NETWORK-MISSING exit 2"
# Prefer real tool root when present so we exercise the broadcast/credentials gate
# after leo is found (not only toolchain-missing).
default_root="${HOME}/.cache/proof-forge-v2/tool-root/linux-x86_64"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) default_root="${HOME}/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
esac
if [[ -x "${PROOF_FORGE_TOOL_ROOT:-$default_root}/leo" ]]; then
  set +e
  out="$(
    env -u PROOF_FORGE_ALEO_NETWORK -u PROOF_FORGE_ALEO_ENDPOINT -u PROOF_FORGE_ALEO_PRIVATE_KEY \
      PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_root}" \
      "$cli" network --target aleo --broadcast --json 2>&1
  )"
  code=$?
  set -e
  echo "$out" | head -40
  [[ "$code" -eq 2 ]]
  echo "$out" | rg -q '"schema":"proof-forge.network.v1"'
  echo "$out" | rg -q 'PF-NETWORK-MISSING'
  echo "$out" | rg -q '"status":"network-missing"'
else
  echo "local-network-smoke: skip network-missing credential gate (leo not present)"
fi

echo "local-network-smoke: ok"
