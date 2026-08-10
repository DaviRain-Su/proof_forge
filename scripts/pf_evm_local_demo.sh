#!/usr/bin/env bash
# End-to-end local EVM demo for templates/evm-dapp-ui.
#
# 1) pf/proof-forge-next build StateCell → evm
# 2) start Anvil on a free port
# 3) cast deploy constructor(uint64)
# 4) write templates/evm-dapp-ui/public/deployment.json (+ copy abi/bin)
# 5) leave Anvil running in foreground (Ctrl-C stops)
#
# Env:
#   PROOF_FORGE_CLI / PROOF_FORGE_TOOL_ROOT / FOUNDRY_BIN
#   PF_EVM_PORT (default random 18500-18999)
#   PF_EVM_CHAIN_ID (default 31337)
#   PF_EVM_CTOR_INITIAL (default 7)
#   PF_EVM_PRIVATE_KEY (default Anvil #0)
#
# Not formal / not mainnet / not public broadcast.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

ui_dir="$root/templates/evm-dapp-ui"
out_dir="${PF_EVM_DEMO_OUT:-$root/build/v2/evm-dapp-demo}"
source_rel="Examples/StateCell.lean"
module_name="Examples.StateCell"
ctor_initial="${PF_EVM_CTOR_INITIAL:-7}"
chain_id="${PF_EVM_CHAIN_ID:-31337}"
port="${PF_EVM_PORT:-$((18500 + RANDOM % 500))}"
private_key="${PF_EVM_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

die() { echo "pf-evm-local-demo: FAIL: $*" >&2; exit 1; }
info() { echo "pf-evm-local-demo: $*"; }

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) die "unsupported host $(uname -s)" ;;
esac

foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil="$foundry_bin/anvil"
cast="$foundry_bin/cast"
[[ -x "$anvil" && -x "$cast" ]] || die "missing anvil/cast under $foundry_bin (pf setup --target evm / install foundry tools)"

cli="${PROOF_FORGE_CLI:-}"
if [[ -z "$cli" ]]; then
  if [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
    cli="$root/.lake/build/bin/proof-forge-next"
  elif command -v proof-forge-next >/dev/null 2>&1; then
    cli="$(command -v proof-forge-next)"
  elif [[ -x "$root/clients/pf-cli/target/release/pf" ]]; then
    # pf needs PROOF_FORGE_CLI for build; fall through
    true
  fi
fi
if [[ -z "${cli:-}" || ! -x "${cli:-}" ]]; then
  if [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
    cli="$root/.lake/build/bin/proof-forge-next"
  else
    die "proof-forge-next not found (lake build or set PROOF_FORGE_CLI)"
  fi
fi

[[ -d "$ui_dir" ]] || die "missing $ui_dir"

info "build $source_rel → $out_dir"
rm -rf "$out_dir"
mkdir -p "$(dirname "$out_dir")"
"$cli" build "$source_rel" --module "$module_name" --target evm -o "$out_dir"

bin_path=""
if [[ -f "$out_dir/StateCell.bin" ]]; then
  bin_path="$out_dir/StateCell.bin"
else
  bin_path="$(find "$out_dir" -maxdepth 1 -type f -name '*.bin' | sort | head -n 1 || true)"
fi
[[ -n "$bin_path" && -s "$bin_path" ]] || die "no *.bin under $out_dir"
program_name="$(basename "$bin_path" .bin)"
abi_path="$out_dir/${program_name}.abi.json"
[[ -f "$abi_path" ]] || die "missing ABI $abi_path"

rpc="http://127.0.0.1:$port"
log="$(mktemp "${TMPDIR:-/tmp}/pf-evm-demo-anvil.XXXXXX.log")"
anvil_pid=""

cleanup() {
  if [[ -n "${anvil_pid:-}" ]]; then
    kill "$anvil_pid" 2>/dev/null || true
    wait "$anvil_pid" 2>/dev/null || true
  fi
  rm -f "$log"
}
trap cleanup EXIT

info "start anvil port=$port chainId=$chain_id"
"$anvil" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" --silent >"$log" 2>&1 &
anvil_pid=$!

ready=0
for _ in $(seq 1 80); do
  if ! kill -0 "$anvil_pid" 2>/dev/null; then
    die "anvil exited early (log $log)"
  fi
  if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
[[ "$ready" == 1 ]] || die "anvil not ready (log $log)"

bytecode="$(tr -d '\n\r ' < "$bin_path")"
encoded="$("$cast" abi-encode 'constructor(uint64)' "$ctor_initial")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt")"
[[ -n "$addr" && "$addr" != "null" ]] || die "deploy failed: $receipt"

got="$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
info "deployed $program_name @ $addr get()=$got (expect $ctor_initial)"

# Publish artifacts + deployment.json for the UI
mkdir -p "$ui_dir/public/artifacts"
cp -f "$abi_path" "$ui_dir/public/artifacts/${program_name}.abi.json"
cp -f "$abi_path" "$ui_dir/public/artifacts/StateCell.abi.json"
cp -f "$bin_path" "$ui_dir/public/artifacts/${program_name}.bin"
cp -f "$bin_path" "$ui_dir/public/artifacts/StateCell.bin"

/usr/bin/python3 -I -S - "$ui_dir/public/deployment.json" "$rpc" "$chain_id" "$addr" \
  "$program_name" "$ctor_initial" "$abi_path" "$bin_path" <<'PY'
import json, sys
from pathlib import Path
out, rpc, chain_id, addr, program, ctor, abi_path, bin_path = sys.argv[1:9]
abi = json.loads(Path(abi_path).read_text())
bc = Path(bin_path).read_text().strip().replace("\n", "").replace("\r", "").replace(" ", "")
if not bc.startswith("0x"):
    bc = "0x" + bc
doc = {
    "schema": "proof-forge.pf.evm-local-deployment.v1",
    "target": "evm",
    "network": "local",
    "rpcUrl": rpc,
    "chainId": int(chain_id),
    "contractAddress": addr,
    "program": program,
    "constructorInitial": int(ctor),
    "abi": abi,
    "bytecode": bc,
    "notes": [
        "local Anvil only",
        "not mainnet / not public broadcast",
        "not formal",
        "written by scripts/pf_evm_local_demo.sh",
    ],
}
Path(out).write_text(json.dumps(doc, indent=2) + "\n")
print("wrote", out)
PY

info "UI artifacts ready under $ui_dir/public/"
info "Next:"
info "  cd templates/evm-dapp-ui && npm install && npm run dev"
info "  MetaMask → RPC $rpc  chainId $chain_id"
info "  optional Anvil #0 key (LOCAL ONLY): $private_key"
info "Anvil running pid=$anvil_pid — Ctrl-C to stop"

# Keep anvil in foreground
trap - EXIT
wait "$anvil_pid"
