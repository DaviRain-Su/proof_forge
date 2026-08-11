#!/usr/bin/env bash
# ProofShip rwa-share-v1 — one-command X Layer TESTNET deploy (engineering lane).
#
#   1. re-runs the full product gate (check → build → inspect exact closure)
#   2. abi-encodes constructor (supply, perTx, windowCap)
#   3. cast create to X Layer testnet (chainId 1952, OKB gas)
#   4. prints the explorer link
#
# Discipline (mirrors scripts/pf_evm_xlayer_deploy.sh):
#   - opt-in: PF_XLAYER_CONFIRM=yes required
#   - key lives ONLY in an env var you name via PF_XLAYER_PRIVATE_KEY_ENV;
#     never in files, never on this script's argv, never on any MCP surface
#
# Usage:
#   PF_XLAYER_CONFIRM=yes PF_XLAYER_PRIVATE_KEY_ENV=PF_XLAYER_KEY \
#     scripts/deploy-testnet.sh <supply> <perTx> <windowCap> [source.lean ModuleName]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj="$(cd "$here/.." && pwd)"
root="$(cd "$proj/../../.." && pwd)"

die() { echo "deploy-testnet: REFUSED/FAIL: $*" >&2; exit 2; }

[[ "${PF_XLAYER_CONFIRM:-}" == "yes" ]] \
  || die "set PF_XLAYER_CONFIRM=yes (testnet deploy is opt-in)"
KEY_ENV_NAME="${PF_XLAYER_PRIVATE_KEY_ENV:-}"
[[ -n "$KEY_ENV_NAME" ]] || die "set PF_XLAYER_PRIVATE_KEY_ENV to the env var NAME holding the key"
[[ -n "${!KEY_ENV_NAME:-}" ]] || die "env '$KEY_ENV_NAME' is empty"

supply="${1:?usage: deploy-testnet.sh <supply> <perTx> <windowCap> [source Module]}"
per_tx="${2:?missing perTx}"
window_cap="${3:?missing windowCap}"
src_name="${4:-RwaShareRegistry.lean}"
module="${5:-${src_name%.lean}}"

cast_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64}}/cast"
[[ -x "$cast_bin" ]] || cast_bin="$HOME/.foundry/bin/cast"
[[ -x "$cast_bin" ]] || die "cast not found (locked tool root or ~/.foundry/bin)"

CHAIN_ID=1952
RPC="${PF_XLAYER_RPC:-https://testrpc.xlayer.tech/terigon}"

echo "== 1/3 gate (check + build + inspect) ==" >&2
"$here/gate.sh" "$src_name" "$module"
out="$proj/out-evm-$(echo "$module" | tr '[:upper:]' '[:lower:]')"
bin_file="$out/$module.bin"
[[ -s "$bin_file" ]] || die "bin missing under $out"

echo "== 2/3 deploy to X Layer testnet (chainId $CHAIN_ID) ==" >&2
encoded="$("$cast_bin" abi-encode 'constructor(uint64,uint64,uint64)' "$supply" "$per_tx" "$window_cap")"
bytecode="$(tr -d '\n\r ' < "$bin_file")${encoded#0x}"
json="$("$cast_bin" send --json --rpc-url "$RPC" --private-key "${!KEY_ENV_NAME}" \
  --create "0x${bytecode}")"
addr="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin).get("contractAddress",""))' <<<"$json")"
[[ -n "$addr" && "$addr" != "null" ]] || die "deploy returned no contractAddress: $json"

echo "== 3/3 done ==" >&2
echo "contract=$addr"
echo "network=xlayer-testnet chainId=$CHAIN_ID rpc=$RPC"
echo "explorer=https://www.okx.com/web3/explorer/xlayer-test (paste address: $addr)"
echo "ctor=(supply=$supply, perTx=$per_tx, windowCap=$window_cap)"
