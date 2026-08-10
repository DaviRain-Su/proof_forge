#!/usr/bin/env bash
# Aleo Wave-C: network transaction materialization for PF-equivalent Instructions.
#
# Default mode (safe): construct deploy (+ optional execute) transactions against a
# live network REST endpoint and **save** them without --broadcast.
#
# Opt-in broadcast (explicit only):
#   PROOF_FORGE_ALEO_BROADCAST=1
#   PROOF_FORGE_ALEO_PRIVATE_KEY=...   # required for broadcast
#   PROOF_FORGE_ALEO_NETWORK=testnet|devnet   # mainnet rejected
#
# Product authority remains PF-emitted Instructions. Because `leo deploy` always
# recompiles package src, this gate:
#   1) builds PF --target aleo (StateCell)
#   2) synthesizes a Leo structural twin known to lower to the **exact same**
#      Instructions bytes (program-id rewritten)
#   3) verifies leo build/main.aleo == rewrite(PF .aleo)
#   4) leo deploy --save (and execute --save) against the endpoint
#
# What this proves (engineering only):
#   - PF StateCell Instructions have a Leo twin with exact bytecode equality
#   - leo can materialize deploy/execute txs bound to live testnet/devnet state
#   - default path never broadcasts
#
# What this does NOT prove:
#   - successful on-chain inclusion (unless broadcast opt-in and credits suffice)
#   - Mainnet (rejected)
#   - product deployable=true / formal / hermetic
#   - MCP default network tools
#
# Exit codes:
#   0  — gate passed, or Leo/endpoint unavailable (skip-clean with message)
#   1  — tools present but gate failed
#   2  — usage / product CLI missing / unsafe config
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

cli="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"
if [[ ! -x "$cli" ]]; then
  echo "aleo-network-tx: FAIL proof-forge-next not built ($cli)" >&2
  exit 2
fi

platform_id() {
  local sys mach
  sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
  mach="$(uname -m | tr '[:upper:]' '[:lower:]')"
  echo "${sys}-${mach}"
}

resolve_leo() {
  if [[ -n "${PROOF_FORGE_ALEO_LEO:-}" && -x "${PROOF_FORGE_ALEO_LEO}" ]]; then
    echo "${PROOF_FORGE_ALEO_LEO}"
    return 0
  fi
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" && -x "${PROOF_FORGE_TOOL_ROOT%/}/leo" ]]; then
    echo "${PROOF_FORGE_TOOL_ROOT%/}/leo"
    return 0
  fi
  local plat cand
  plat="$(platform_id)"
  cand="${HOME}/.cache/proof-forge-v2/tool-root/${plat}/leo"
  if [[ -x "$cand" ]]; then
    echo "$cand"
    return 0
  fi
  if [[ -x "${HOME}/.cargo/bin/leo" ]]; then
    echo "${HOME}/.cargo/bin/leo"
    return 0
  fi
  if command -v leo >/dev/null 2>&1; then
    command -v leo
    return 0
  fi
  return 1
}

if ! leo="$(resolve_leo)"; then
  echo "aleo-network-tx: skipped (leo unavailable)"
  exit 0
fi

leo_ver="$("$leo" --version 2>&1 | head -1 || true)"
echo "aleo-network-tx: using $leo ($leo_ver)"

network="${PROOF_FORGE_ALEO_NETWORK:-testnet}"
case "$network" in
  testnet|devnet) ;;
  mainnet)
    echo "aleo-network-tx: FAIL mainnet is out of product scope (Wave C refuses mainnet)" >&2
    exit 2
    ;;
  *)
    echo "aleo-network-tx: FAIL unknown network '$network' (want testnet|devnet)" >&2
    exit 2
    ;;
esac

if [[ "$network" == "devnet" ]]; then
  endpoint="${PROOF_FORGE_ALEO_ENDPOINT:-http://localhost:3030}"
else
  endpoint="${PROOF_FORGE_ALEO_ENDPOINT:-https://api.explorer.provable.com/v1}"
fi

broadcast="${PROOF_FORGE_ALEO_BROADCAST:-0}"
# Well-known Leo local-dev key — fine for --save dry materialization only.
default_dev_key="APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH"
private_key="${PROOF_FORGE_ALEO_PRIVATE_KEY:-$default_dev_key}"

if [[ "$broadcast" == "1" ]]; then
  if [[ -z "${PROOF_FORGE_ALEO_PRIVATE_KEY:-}" ]]; then
    echo "aleo-network-tx: FAIL broadcast requires PROOF_FORGE_ALEO_PRIVATE_KEY" >&2
    exit 2
  fi
  if [[ "$private_key" == "$default_dev_key" ]]; then
    echo "aleo-network-tx: FAIL refusing broadcast with well-known local-dev key" >&2
    exit 2
  fi
  echo "aleo-network-tx: WARN broadcast enabled for network=$network endpoint=$endpoint" >&2
else
  echo "aleo-network-tx: mode=save-only (no broadcast) network=$network endpoint=$endpoint"
fi

# Endpoint reachability (skip-clean if unreachable — host-optional network).
echo "aleo-network-tx: probe endpoint"
set +e
height="$(curl -sS -m 20 "${endpoint%/}/${network}/block/height/latest" 2>/dev/null || true)"
probe_code=$?
set -e
if [[ "$probe_code" -ne 0 || -z "$height" || "$height" == *"Failed"* || "$height" == *"error"* ]]; then
  echo "aleo-network-tx: skipped (endpoint unreachable: $endpoint network=$network)"
  exit 0
fi
# height should be numeric-ish
if ! grep -Eq '^[0-9]+$' <<<"$height"; then
  echo "aleo-network-tx: skipped (endpoint did not return numeric height: $height)"
  exit 0
fi
echo "aleo-network-tx: endpoint ok height=$height"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/pf-aleo-net.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

export HOME="$tmp/home"
mkdir -p "$HOME/.aleo"
# Do not leak operator secrets into child env except explicit private key flag.
unset VIEW_KEY DEVNET 2>/dev/null || true

# Unique program id: must not contain substring 'aleo'; lowercase alnum.
# statecell may already exist on public testnet — always use a fresh id for tx save.
program_id="pfsc$(date +%s | tail -c 7)"
if grep -qi 'aleo' <<<"$program_id"; then
  echo "aleo-network-tx: FAIL internal program id contains aleo" >&2
  exit 1
fi
echo "aleo-network-tx: program_id=$program_id"

# --- 1) Product PF build (StateCell) ---
pf_out="$tmp/pf-out"
echo "aleo-network-tx: product build Examples/StateCell.lean"
if ! "$cli" build Examples/StateCell.lean --module Examples.StateCell --target aleo \
  -o "$pf_out" >/dev/null; then
  echo "aleo-network-tx: FAIL product build" >&2
  exit 1
fi
pf_aleo="$pf_out/statecell.aleo"
if [[ ! -f "$pf_aleo" ]]; then
  echo "aleo-network-tx: FAIL missing PF statecell.aleo" >&2
  exit 1
fi
if ! grep -q 'not r1 into r2' "$pf_aleo"; then
  echo "aleo-network-tx: FAIL PF emission missing not-guard" >&2
  exit 1
fi
pf_sha="$(shasum -a 256 "$pf_aleo" | awk '{print $1}')"
echo "aleo-network-tx: PF statecell.aleo sha256=$pf_sha"

# --- 2) Leo package twin that lowers to exact PF bytes (name rewritten) ---
(
  cd "$tmp"
  "$leo" new "$program_id" --disable-update-check >/dev/null
)
pkg="$tmp/$program_id"
cat > "$pkg/src/main.leo" <<EOF
// Structural twin for network packaging only.
// Empirically lowers (Leo 4.0.2) to the same Instructions as PF StateCell
// after rewriting the program id (assert(!seen) → not; dropped re-read kept).
program ${program_id}.aleo {
    @noupgrade
    constructor() {}
    mapping pf_state_0: u8 => u64;
    mapping initialized: u8 => bool;
    fn initialize(public p0: u64) -> Final {
        return final {
            let r1: bool = Mapping::get_or_use(initialized, 0u8, false);
            assert(!r1);
            Mapping::set(pf_state_0, 0u8, p0);
            Mapping::set(initialized, 0u8, true);
        };
    }
    fn increment(public p0: u64) -> Final {
        return final {
            let r1: u64 = Mapping::get_or_use(pf_state_0, 0u8, 0u64);
            let r2: u64 = r1 + p0;
            Mapping::set(pf_state_0, 0u8, r2);
            let r3: u64 = Mapping::get_or_use(pf_state_0, 0u8, 0u64);
        };
    }
}
EOF

echo "aleo-network-tx: leo build twin package"
"$leo" build --offline --disable-update-check --path "$pkg" --network "$network" >/dev/null
twin_aleo="$pkg/build/main.aleo"
if [[ ! -f "$twin_aleo" ]]; then
  echo "aleo-network-tx: FAIL missing twin build/main.aleo" >&2
  exit 1
fi

# Exact equality after rewriting PF program id statecell → $program_id
pf_rewritten="$tmp/pf-rewritten.aleo"
sed "s/statecell\\.aleo/${program_id}.aleo/g" "$pf_aleo" > "$pf_rewritten"
if ! cmp -s "$twin_aleo" "$pf_rewritten"; then
  echo "aleo-network-tx: FAIL twin bytecode != PF emission (program-id rewritten)" >&2
  diff -u "$pf_rewritten" "$twin_aleo" | head -80 >&2 || true
  exit 1
fi
echo "aleo-network-tx: ok twin bytecode exact-match PF (id=$program_id)"

# --- 3) deploy --save (default no broadcast) ---
tx_dir="$tmp/tx"
mkdir -p "$tx_dir"
deploy_args=(
  deploy
  --disable-update-check
  --path "$pkg"
  --network "$network"
  --endpoint "$endpoint"
  --network-retries 2
  --private-key "$private_key"
  --skip-deploy-certificate
  --save "$tx_dir"
  -y
)
if [[ "$broadcast" == "1" ]]; then
  deploy_args+=(--broadcast)
else
  # Explicit non-broadcast materialization
  :
fi

echo "aleo-network-tx: leo deploy --save"
set +e
deploy_out="$("$leo" "${deploy_args[@]}" 2>&1)"
deploy_code=$?
set -e
if [[ "$deploy_code" -ne 0 ]]; then
  echo "aleo-network-tx: FAIL leo deploy (exit $deploy_code)" >&2
  echo "$deploy_out" >&2
  exit 1
fi
if [[ "$broadcast" != "1" ]]; then
  if grep -qiE 'broadcast(ed)? to the network|submitted transaction' <<<"$deploy_out"; then
    # leo prints "will NOT be broadcast" in save-only — ensure we didn't accidentally broadcast
    if ! grep -q 'will NOT be broadcast' <<<"$deploy_out"; then
      echo "aleo-network-tx: FAIL deploy output looks like broadcast without opt-in" >&2
      echo "$deploy_out" >&2
      exit 1
    fi
  fi
  if ! grep -q 'will NOT be broadcast' <<<"$deploy_out"; then
    echo "aleo-network-tx: WARN deploy output missing explicit NOT broadcast marker" >&2
  fi
fi

deploy_json="$(find "$tx_dir" -type f -name '*.deployment.json' | head -1)"
if [[ -z "$deploy_json" || ! -s "$deploy_json" ]]; then
  echo "aleo-network-tx: FAIL missing deployment json under $tx_dir" >&2
  echo "$deploy_out" | tail -40 >&2
  ls -laR "$tx_dir" >&2 || true
  exit 1
fi
# Deployment must embed our twin/PF program text
if ! grep -q "program ${program_id}.aleo" "$deploy_json"; then
  echo "aleo-network-tx: FAIL deployment json missing program ${program_id}.aleo" >&2
  exit 1
fi
if ! grep -q 'not r1 into r2' "$deploy_json"; then
  echo "aleo-network-tx: FAIL deployment json missing PF not-guard in program body" >&2
  exit 1
fi
echo "aleo-network-tx: ok deploy tx saved $(basename "$deploy_json") ($(wc -c <"$deploy_json") bytes)"

# After deploy, leo rebuilds — re-assert twin still matches if rebuilt
if [[ -f "$twin_aleo" ]]; then
  if ! cmp -s "$twin_aleo" "$pf_rewritten"; then
    # rebuild may have run; re-check from current main.aleo
    if ! cmp -s "$pkg/build/main.aleo" "$pf_rewritten"; then
      echo "aleo-network-tx: FAIL post-deploy package bytecode diverged from PF" >&2
      exit 1
    fi
  fi
fi

# --- 4) execute --save initialize (no broadcast by default) ---
ex_dir="$tmp/ex"
mkdir -p "$ex_dir"
exec_args=(
  execute
  --disable-update-check
  --path "$pkg"
  --network "$network"
  --endpoint "$endpoint"
  --network-retries 2
  --private-key "$private_key"
  --skip-execute-proof
  --save "$ex_dir"
  -y
  initialize
  5u64
)
if [[ "$broadcast" == "1" ]]; then
  exec_args+=(--broadcast)
fi

echo "aleo-network-tx: leo execute --save initialize 5u64"
set +e
exec_out="$("$leo" "${exec_args[@]}" 2>&1)"
exec_code=$?
set -e
if [[ "$exec_code" -ne 0 ]]; then
  echo "aleo-network-tx: FAIL leo execute (exit $exec_code)" >&2
  echo "$exec_out" >&2
  exit 1
fi
ex_json="$(find "$ex_dir" -type f -name '*.json' | head -1)"
if [[ -z "$ex_json" || ! -s "$ex_json" ]]; then
  echo "aleo-network-tx: FAIL missing execution json" >&2
  echo "$exec_out" | tail -40 >&2
  exit 1
fi
if ! grep -q 'initialize' <<<"$exec_out"; then
  echo "aleo-network-tx: FAIL execute output missing initialize" >&2
  echo "$exec_out" | tail -40 >&2
  exit 1
fi
echo "aleo-network-tx: ok execute tx saved $(basename "$ex_json") ($(wc -c <"$ex_json") bytes)"

# Copy artifacts to build/ for operator inspection (gitignored build/)
out_keep="$root/build/v2/aleo-network-tx-${network}-${program_id}"
rm -rf "$out_keep"
mkdir -p "$out_keep"
cp "$pf_aleo" "$out_keep/statecell.pf.aleo"
cp "$pf_rewritten" "$out_keep/${program_id}.pf-rewritten.aleo"
cp "$pkg/build/main.aleo" "$out_keep/${program_id}.twin.aleo"
cp "$deploy_json" "$out_keep/"
cp "$ex_json" "$out_keep/"
cat > "$out_keep/README.txt" <<EOF
Aleo Wave-C network tx materialization (engineering)
network=$network
endpoint=$endpoint
program_id=$program_id
broadcast=$broadcast
block_height_at_probe=$height
pf_statecell_sha256=$pf_sha
twin_exact_match_pf_rewritten=true
deployable_product=false
notes=save-only unless PROOF_FORGE_ALEO_BROADCAST=1; mainnet rejected; not formal/hermetic
EOF
echo "aleo-network-tx: artifacts → $out_keep"

echo "aleo-network-tx: ok (exact twin + deploy/execute tx save; broadcast=$broadcast)"
echo "aleo-network-tx: non-claims = no mainnet product path; deployable=false; not formal"
