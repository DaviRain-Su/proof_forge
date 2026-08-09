#!/usr/bin/env bash
# Focused no-network smoke for host-heavy CLI wrappers and secret redaction.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

cli="$root/.lake/build/bin/proof-forge-next"

echo "local-network-smoke: aleo network wrapper uses fixed bash/python entrypoints"
head -n 1 "$root/scripts/aleo_network.sh" | grep -qx '#!/bin/bash -p'
grep -q 'export PATH=/usr/bin:/bin' "$root/scripts/aleo_network.sh"
grep -q 'exec /usr/bin/python3 -I -S' "$root/scripts/aleo_network.sh"
if grep -Eq 'dirname|`pwd`|\$\(pwd\)' "$root/scripts/aleo_network.sh"; then
  echo "local-network-smoke: aleo_network.sh must not use dirname or pwd command before Python" >&2
  exit 1
fi
bashenv_root="$(mktemp -d /tmp/pf-wrapper-bashenv.XXXXXX)"
printf ': > %q\n' "$bashenv_root/sourced" > "$bashenv_root/bashenv"
set +e
out="$(BASH_ENV="$bashenv_root/bashenv" "$root/scripts/aleo_network.sh" \
  --output-dir nowhere --receipt-dir nowhere-receipt --network mainnet --broadcast 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'mainnet deployment is disabled' <<<"$out"
test ! -e "$bashenv_root/sourced"
rm -rf "$bashenv_root"

if [[ ! -x "$cli" ]]; then
  echo "local-network-smoke: FAIL proof-forge-next not built (lake build proof_forge_next)" >&2
  exit 1
fi

echo "local-network-smoke: local without --target is usage exit 2"
set +e
err="$("$cli" local 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'requires --target' <<<"$err"

echo "local-network-smoke: network without --broadcast is usage exit 2"
set +e
err="$("$cli" network --target aleo 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'requires explicit --broadcast' <<<"$err"

echo "local-network-smoke: design-only local rejected"
set +e
err="$("$cli" local --target soroban 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'design-only' <<<"$err"

echo "local-network-smoke: unsupported network target"
set +e
err="$("$cli" network --target solana --broadcast 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'no package-script path' <<<"$err"

echo "local-network-smoke: aleo local missing tool root → exit 2 + PF-TOOLCHAIN-MISSING"
tmp_root="$(mktemp -d /tmp/pf-local-missing.XXXXXX)"
rm -rf "$tmp_root"
set +e
out="$(PROOF_FORGE_TOOL_ROOT="$tmp_root" "$cli" local --target aleo --mode sandbox --json -- \
  --source Examples/StateCell.lean --module Examples.StateCell --skip-run 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q '"schema":"proof-forge.local.v1"' <<<"$out"
grep -q '"status":"toolchain-missing"' <<<"$out"
grep -q 'PF-TOOLCHAIN-MISSING' <<<"$out"

echo "local-network-smoke: aleo sandbox usage requires --source/--module"
set +e
out="$("$cli" local --target aleo --mode sandbox --json -- --skip-run 2>&1)"
code=$?
set -e
# Wrapper may surface script usage as product-error (exit 1) or toolchain path;
# script itself exits 2 on missing source/module. Accept non-zero + usage text.
[[ "$code" -ne 0 ]]
grep -qE 'usage error|--source and --module|unknown arg' <<<"$out" || \
  grep -q 'aleo-local-sandbox' <<<"$out"

echo "local-network-smoke: missing deploy contract → PF-NETWORK-MISSING"
set +e
out="$("$cli" network --target aleo --broadcast --json 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q '"schema":"proof-forge.network.v1"' <<<"$out"
grep -q '"status":"network-missing"' <<<"$out"
grep -q 'PF-NETWORK-MISSING' <<<"$out"

echo "local-network-smoke: mainnet policy fails closed before tools/network"
set +e
out="$("$cli" network --target aleo --broadcast --json -- \
  --output-dir nowhere --receipt-dir nowhere-receipt \
  --network mainnet --endpoint https://example.com --dev-key 0 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'only permits no-secret DevNet' <<<"$out"
test ! -e nowhere-receipt

echo "local-network-smoke: CLI wrapper rejects signer-bearing secret args before CWD script spawn"
secret="synthetic-private-key-must-not-appear"
set +e
out="$("$cli" network --target aleo --broadcast --json -- \
  --output-dir nowhere --receipt-dir nowhere-receipt \
  --network testnet --endpoint https://api.explorer.provable.com/v2 \
  --private-key "$secret" 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'rejects signer-bearing secret arguments' <<<"$out"
if grep -q "$secret" <<<"$out"; then
  echo "local-network-smoke: raw private key leaked from pre-spawn rejection" >&2
  exit 1
fi

set +e
out="$("$cli" network --target aleo --broadcast --json -- \
  --output-dir nowhere --receipt-dir nowhere-receipt \
  --network testnet --endpoint https://api.explorer.provable.com/v2 \
  --priv-key "$secret" 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'rejects signer-bearing secret arguments' <<<"$out"
if grep -q "$secret" <<<"$out"; then
  echo "local-network-smoke: abbreviated private key leaked from pre-spawn rejection" >&2
  exit 1
fi

fee_record_secret="synthetic-fee-record-must-not-appear"
for fee_arg in "--fee-record $fee_record_secret" "--fee-record=$fee_record_secret"; do
  fake_root="$(mktemp -d /tmp/pf-wrapper-feerecord.XXXXXX)"
  mkdir -p "$fake_root/scripts"
  cat > "$fake_root/scripts/aleo_network.sh" <<'SH'
#!/bin/bash
: > script-was-spawned
exit 2
SH
  set +e
  out="$(cd "$fake_root" && "$cli" network --target aleo --broadcast --json -- --network devnet $fee_arg 2>&1)"
  code=$?
  set -e
  [[ "$code" -eq 2 ]]
  grep -q 'rejects signer-bearing secret arguments' <<<"$out"
  test ! -e "$fake_root/script-was-spawned"
  if grep -q "$fee_record_secret" <<<"$out"; then
    echo "local-network-smoke: fee record leaked from pre-spawn rejection" >&2
    exit 1
  fi
  rm -rf "$fake_root"
done

echo "local-network-smoke: local wrapper rejects signer-bearing args before CWD script spawn"
fake_root="$(mktemp -d /tmp/pf-wrapper-reject.XXXXXX)"
mkdir -p "$fake_root/scripts"
cat > "$fake_root/scripts/aleo_local_sandbox.sh" <<'SH'
#!/bin/bash
: > script-was-spawned
exit 2
SH
set +e
out="$(cd "$fake_root" && "$cli" local --target aleo --json -- --private-key "$secret" 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'local CLI wrapper rejects signer-bearing arguments' <<<"$out"
test ! -e "$fake_root/script-was-spawned"
if grep -q "$secret" <<<"$out"; then
  echo "local-network-smoke: local pre-spawn rejection leaked private key" >&2
  exit 1
fi
rm -rf "$fake_root"

fake_root="$(mktemp -d /tmp/pf-wrapper-local-feerecord.XXXXXX)"
mkdir -p "$fake_root/scripts"
cat > "$fake_root/scripts/aleo_local_sandbox.sh" <<'SH'
#!/bin/bash
: > script-was-spawned
exit 2
SH
set +e
out="$(cd "$fake_root" && "$cli" local --target aleo --json -- --fee-record="$fee_record_secret" 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'local CLI wrapper rejects signer-bearing arguments' <<<"$out"
test ! -e "$fake_root/script-was-spawned"
if grep -q "$fee_record_secret" <<<"$out"; then
  echo "local-network-smoke: local pre-spawn rejection leaked fee record" >&2
  exit 1
fi
rm -rf "$fake_root"

echo "local-network-smoke: CLI wrapper rejects inherited signer environment"
set +e
out="$(PROOF_FORGE_ALEO_PRIVATE_KEY="$secret" \
  "$cli" network --target aleo --broadcast -- \
  --output-dir nowhere --receipt-dir nowhere-receipt \
  --network devnet --endpoint http://127.0.0.1:3030 --dev-key 0 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q "refuses inherited signer environment 'PROOF_FORGE_ALEO_PRIVATE_KEY'" <<<"$out"
if grep -q "$secret" <<<"$out"; then
  echo "local-network-smoke: inherited private key value leaked" >&2
  exit 1
fi

echo "local-network-smoke: interim network wrapper rejects signer-fd capability before CWD script spawn"
fake_root="$(mktemp -d /tmp/pf-wrapper-signerfd.XXXXXX)"
mkdir -p "$fake_root/scripts"
cat > "$fake_root/scripts/aleo_network.sh" <<'SH'
#!/bin/bash
: > script-was-spawned
exit 2
SH
set +e
out="$(cd "$fake_root" && "$cli" network --target aleo --broadcast --json -- --network devnet --signer-fd 7 2>&1)"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q 'rejects --signer-fd capability' <<<"$out"
test ! -e "$fake_root/script-was-spawned"
rm -rf "$fake_root"

echo "local-network-smoke: ok"
