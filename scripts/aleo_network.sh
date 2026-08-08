#!/usr/bin/env bash
# Aleo network product path: build → package → deploy [--execute] on a real endpoint.
#
# Authority: docs/targets/09c-aleo-network.md
# Local (no chain): docs/targets/09b-aleo-local-sandbox.md / just aleo-sandbox
#
# N1 requires explicit opt-in network credentials + --broadcast.
# Without them: PF-NETWORK-MISSING (exit 2) — not a product compile failure.
#
# Maturity:
#   * INSTRUCTIONS-PRIMARY product authority
#   * NETWORK-DEPLOY / NETWORK-EXECUTE only when endpoint is reachable
#   * default Finalize remains deployable=false until a product N3 profile
#   * NOT ordinary ci; NOT formal / hermetic
#
# Exit codes:
#   0  network deploy (and optional execute) succeeded
#   1  tool present + network configured but build/pin/deploy/execute failed
#   2  PF-TOOLCHAIN-MISSING / PF-NETWORK-MISSING / unsupported host / usage
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="aleo-network"
PROFILE_LABEL="aleo-network-v1"
GOLDEN_COUNTER="testdata/golden/aleo-instructions-v1/counter.compiled.aleo"

NETWORK="${PROOF_FORGE_ALEO_NETWORK:-}"
ENDPOINT="${PROOF_FORGE_ALEO_ENDPOINT:-}"
PRIVATE_KEY="${PROOF_FORGE_ALEO_PRIVATE_KEY:-}"
BROADCAST=0
DO_EXECUTE=0
CONSENSUS_VERSION=""
SKIP_DEPLOY_CERT=0
KEEP=0
SOURCE="Examples/Counter.lean"
MODULE="Examples.Counter"
PIN_GOLDEN=1
DEVNET=0
# Priority fee in microcredits (leo may under-estimate base fee on some nodes).
PRIORITY_FEES="${PROOF_FORGE_ALEO_PRIORITY_FEES:-}"

usage() {
  cat <<'EOF'
usage: aleo_network.sh --broadcast \
         --network <testnet|mainnet|canary> \
         --endpoint <url> \
         --private-key <key> \
         [options]

  Product Aleo network path (N1 deploy, optional N2 execute).

  Required for N1 (flags or PROOF_FORGE_ALEO_* env):
    --network / PROOF_FORGE_ALEO_NETWORK
    --endpoint / PROOF_FORGE_ALEO_ENDPOINT
    --private-key / PROOF_FORGE_ALEO_PRIVATE_KEY
    --broadcast          (explicit; never implicit)

  Options:
    --execute            after deploy, execute initialize 1u64 + increment 2u64
    --consensus-version N
    --skip-deploy-certificate
    --devnet             pass leo --devnet (local snarkOS-style endpoints)
    --program-source PATH   default Examples/Counter.lean
    --module NAME           default Examples.Counter
    --no-golden-pin         skip golden byte pin (non-Counter sources)
    --keep                  retain workdir
    -h, --help

  Missing network opt-in → exit 2 PF-NETWORK-MISSING
  Missing locked leo     → exit 2 PF-TOOLCHAIN-MISSING

  Local offline run (no chain): just aleo-sandbox
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --network) NETWORK="${2:-}"; shift 2 ;;
    --endpoint) ENDPOINT="${2:-}"; shift 2 ;;
    --private-key) PRIVATE_KEY="${2:-}"; shift 2 ;;
    --broadcast) BROADCAST=1; shift ;;
    --execute) DO_EXECUTE=1; shift ;;
    --consensus-version) CONSENSUS_VERSION="${2:-}"; shift 2 ;;
    --skip-deploy-certificate) SKIP_DEPLOY_CERT=1; shift ;;
    --devnet) DEVNET=1; shift ;;
    --priority-fees) PRIORITY_FEES="${2:-}"; shift 2 ;;
    --program-source) SOURCE="${2:-}"; shift 2 ;;
    --module) MODULE="${2:-}"; shift 2 ;;
    --no-golden-pin) PIN_GOLDEN=0; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "${PREFIX}: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

die() {
  echo "${PREFIX}: $*" >&2
  exit 1
}

missing_tool() {
  echo "${PREFIX}: PF-TOOLCHAIN-MISSING: $*" >&2
  exit 2
}

missing_net() {
  echo "${PREFIX}: PF-NETWORK-MISSING: $*" >&2
  exit 2
}

platform_id() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo "linux-x86_64" ;;
    Darwin-arm64) echo "darwin-arm64" ;;
    *) return 1 ;;
  esac
}

if ! plat="$(platform_id)"; then
  missing_tool "unsupported host $(uname -s)-$(uname -m) (only linux-x86_64 and darwin-arm64)"
fi

default_tool_root="${HOME}/.cache/proof-forge-v2/tool-root/${plat}"
export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT%/}"
LEO="${TOOL_ROOT}/leo"

echo "${PREFIX}: profile=${PROFILE_LABEL} platform=${plat}"
echo "${PREFIX}: tool_root=${TOOL_ROOT}"
echo "${PREFIX}: maturity=INSTRUCTIONS-PRIMARY + NETWORK path (N1/N2)"
echo "${PREFIX}: maturity=deployable=false until product N3 profile"

if [[ ! -x "$LEO" ]]; then
  missing_tool "locked leo not found at ${LEO} (materialize Tool Lock leo 4.0.2; no PATH fallback)"
fi

ver_line="$("$LEO" --version 2>&1 | head -1 || true)"
echo "${PREFIX}: leo=${LEO}"
echo "${PREFIX}: leo_version=${ver_line}"
if ! grep -q '4\.0\.2' <<<"$ver_line"; then
  die "expected Leo 4.0.2, got: ${ver_line}"
fi

# Network opt-in gate (before any product work that might look like "success").
if [[ "$BROADCAST" -ne 1 ]]; then
  missing_net "refusing network path without explicit --broadcast (local only: just aleo-sandbox)"
fi
if [[ -z "$NETWORK" ]]; then
  missing_net "need --network or PROOF_FORGE_ALEO_NETWORK (testnet|mainnet|canary)"
fi
if [[ -z "$ENDPOINT" ]]; then
  missing_net "need --endpoint or PROOF_FORGE_ALEO_ENDPOINT (leo deploy requires stateRoot; offline save is not enough)"
fi
if [[ -z "$PRIVATE_KEY" ]]; then
  missing_net "need --private-key or PROOF_FORGE_ALEO_PRIVATE_KEY (funded key for deploy fees)"
fi

case "$NETWORK" in
  testnet|mainnet|canary) ;;
  *) die "unsupported --network '${NETWORK}' (expected testnet|mainnet|canary)" ;;
esac

PF_BIN="${root}/.lake/build/bin/proof-forge-next"
if [[ ! -x "$PF_BIN" ]]; then
  die "missing product CLI ${PF_BIN}; run: lake build proof_forge_next"
fi
if [[ ! -f "$SOURCE" ]]; then
  die "missing program source ${SOURCE}"
fi

echo "${PREFIX}: network=${NETWORK}"
echo "${PREFIX}: endpoint=${ENDPOINT}"
echo "${PREFIX}: source=${SOURCE} module=${MODULE}"
echo "${PREFIX}: broadcast=1 execute=${DO_EXECUTE} devnet=${DEVNET}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/aleo-network.XXXXXX")"
cleanup() {
  if [[ "$KEEP" -eq 1 ]]; then
    echo "${PREFIX}: --keep workdir=${WORKDIR}"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

OUT="${WORKDIR}/product-out"
PKG="${WORKDIR}/pkg"
LEO_HOME="${WORKDIR}/leo-home"
TX_DIR="${WORKDIR}/tx"
REAL_HOME="${HOME}"
mkdir -p "$PKG/src" "$LEO_HOME/.aleo" "$TX_DIR"

# Isolate Leo subprocess from ambient wallet/registry without clobbering
# script-local NETWORK/ENDPOINT/PRIVATE_KEY (needed after leo build for deploy).
isolate_leo_env() {
  local net="$NETWORK" ep="$ENDPOINT" pk="$PRIVATE_KEY" dn="$DEVNET" cv="${CONSENSUS_VERSION:-}"
  export HOME="$LEO_HOME"
  # Clear ambient Leo secrets only. Do not leave script vars unbound under `set -u`.
  unset VIEW_KEY ADDRESS \
        CONSENSUS_VERSION_HEIGHTS CONSENSUS_HEIGHTS \
        NETWORK_RETRIES PRIORITY_FEE FEE_RECORD \
        || true
  NETWORK="$net"
  ENDPOINT="$ep"
  PRIVATE_KEY="$pk"
  # Keep DEVNET as 0/1 (not the string "true") so later [[ $DEVNET -eq 1 ]]
  # works under `set -u` (bash arithmetic would treat bare `true` as a name).
  DEVNET="$dn"
  CONSENSUS_VERSION="$cv"
  export NETWORK ENDPOINT PRIVATE_KEY DEVNET
  if [[ -n "$cv" ]]; then
    export CONSENSUS_VERSION
  else
    unset CONSENSUS_VERSION || true
    CONSENSUS_VERSION=""
  fi
}

restore_home() {
  export HOME="$REAL_HOME"
}

echo "${PREFIX}: --- product build (Instructions primary + Leo debug) ---"
set +e
build_out="$(
  restore_home
  PROOF_FORGE_ALEO_EMIT_LEO=1 \
    lake env "$PF_BIN" build "$SOURCE" \
      --module "$MODULE" \
      --target aleo \
      -o "$OUT" 2>&1
)"
build_rc=$?
set -e
if [[ "$build_rc" -ne 0 ]]; then
  echo "$build_out" >&2
  die "product build failed (exit ${build_rc})"
fi
echo "$build_out" | tail -5

# Discover primary .aleo / .leo (Counter → counter.*; other programs vary).
mapfile -t ALEO_FILES < <(find "$OUT" -maxdepth 1 -type f -name '*.aleo' ! -name '*.aleo-query-contract.json' | LC_ALL=C sort)
mapfile -t LEO_FILES < <(find "$OUT" -maxdepth 1 -type f -name '*.leo' | LC_ALL=C sort)
if [[ ${#ALEO_FILES[@]} -ne 1 ]]; then
  die "expected exactly one primary .aleo under ${OUT}, found ${#ALEO_FILES[@]}"
fi
if [[ ${#LEO_FILES[@]} -ne 1 ]]; then
  die "expected exactly one debug .leo under ${OUT} (PROOF_FORGE_ALEO_EMIT_LEO=1), found ${#LEO_FILES[@]}"
fi
PRIMARY_ALEO="${ALEO_FILES[0]}"
PRIMARY_LEO="${LEO_FILES[0]}"
STEM="$(basename "$PRIMARY_ALEO" .aleo)"
echo "${PREFIX}: primary_aleo=${PRIMARY_ALEO}"
echo "${PREFIX}: primary_leo=${PRIMARY_LEO}"

if [[ "$PIN_GOLDEN" -eq 1 ]]; then
  if [[ "$STEM" != "counter" ]]; then
    die "golden pin only defined for counter; pass --no-golden-pin for other sources"
  fi
  if [[ ! -f "$GOLDEN_COUNTER" ]]; then
    die "missing golden ${GOLDEN_COUNTER}"
  fi
  if ! cmp -s "$PRIMARY_ALEO" "$GOLDEN_COUNTER"; then
    die "product ${STEM}.aleo !== golden ${GOLDEN_COUNTER}"
  fi
  echo "${PREFIX}: pin ok: product ${STEM}.aleo ≡ golden Instructions"
else
  echo "${PREFIX}: golden pin skipped (--no-golden-pin)"
fi

cat >"$PKG/program.json" <<EOF
{
  "program": "${STEM}.aleo",
  "version": "0.1.0",
  "description": "proof-forge-next aleo network package",
  "license": "MIT",
  "leo": "4.0.2",
  "dependencies": null,
  "dev_dependencies": null
}
EOF
cp "$PRIMARY_LEO" "$PKG/src/main.leo"
echo "${PREFIX}: staged Leo package from product ${STEM}.leo"

echo "${PREFIX}: --- leo build --offline ---"
isolate_leo_env
set +e
bout="$("$LEO" build --offline --disable-update-check --path "$PKG" 2>&1)"
brc=$?
set -e
restore_home
if [[ "$brc" -ne 0 ]]; then
  echo "$bout" >&2
  die "leo build failed (exit ${brc})"
fi
if ! grep -qE 'Compiled|into Aleo instructions' <<<"$bout"; then
  echo "$bout" >&2
  die "leo build missing success marker"
fi
[[ -f "$PKG/build/main.aleo" ]] || die "leo build missing build/main.aleo"
if ! cmp -s "$PRIMARY_ALEO" "$PKG/build/main.aleo"; then
  die "leo build/main.aleo !== product ${STEM}.aleo (Instructions pin broken)"
fi
echo "${PREFIX}: pin ok: leo build/main.aleo ≡ product Instructions"

# Resolve snarkOS for N1/N2. Leo 4.0.2 deploy can under-estimate base fee vs
# snarkOS 4.9.x nodes; product path prefers snarkos developer when present.
resolve_snarkos() {
  local cand
  if [[ -n "${PROOF_FORGE_ALEO_SNARKOS:-}" && -x "${PROOF_FORGE_ALEO_SNARKOS}" ]]; then
    echo "${PROOF_FORGE_ALEO_SNARKOS}"
    return 0
  fi
  for cand in \
    "${TOOL_ROOT}/snarkos" \
    "${HOME}/.cache/proof-forge-v2/aleo-devnet/cargo-install/bin/snarkos" \
    "${REAL_HOME}/.cache/proof-forge-v2/aleo-devnet/cargo-install/bin/snarkos"; do
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

network_id() {
  case "$NETWORK" in
    mainnet) echo 0 ;;
    testnet) echo 1 ;;
    canary) echo 2 ;;
    *) die "internal: bad network for snarkos id: ${NETWORK}" ;;
  esac
}

SNARKOS=""
if SNARKOS="$(resolve_snarkos)"; then
  echo "${PREFIX}: snarkos=${SNARKOS} (N1/N2 authority)"
else
  echo "${PREFIX}: snarkos absent — falling back to leo deploy/execute (may fail fee-match on newer nodes)"
fi

PRIORITY_FEE_U="${PRIORITY_FEES:-1000000}"

if [[ -n "$SNARKOS" ]]; then
  # snarkos developer expects main.aleo at package root (not build/).
  SNARK_PKG="${WORKDIR}/snarkos-pkg"
  mkdir -p "$SNARK_PKG"
  cp "$PRIMARY_ALEO" "$SNARK_PKG/main.aleo"
  NET_ID="$(network_id)"

  echo "${PREFIX}: --- snarkos developer deploy --broadcast (NETWORK-DEPLOY) ---"
  isolate_leo_env
  set +e
  dout="$("$SNARKOS" developer deploy "${STEM}.aleo" \
    --path "$SNARK_PKG" \
    --private-key "$PRIVATE_KEY" \
    --endpoint "$ENDPOINT" \
    --network "$NET_ID" \
    --broadcast \
    --priority-fee "$PRIORITY_FEE_U" \
    --verbosity 1 2>&1)"
  drc=$?
  set -e
  restore_home
  echo "$dout" | tail -50
  printf '%s\n' "$dout" >"${TX_DIR}/deploy.log"
  if [[ "$drc" -ne 0 ]]; then
    die "snarkos deploy failed (exit ${drc}); check endpoint, credits, program name collision"
  fi
  if ! grep -qE 'has been broadcast|Created deployment' <<<"$dout"; then
    die "snarkos deploy missing broadcast success marker"
  fi
  echo "${PREFIX}: ok: NETWORK-DEPLOY via snarkos network=${NETWORK} program=${STEM}.aleo"

  if [[ "$DO_EXECUTE" -eq 1 ]]; then
    run_execute_snarkos() {
      local name="$1"
      shift
      echo "${PREFIX}: --- snarkos developer execute --broadcast ${name} $* (NETWORK-EXECUTE) ---"
      isolate_leo_env
      set +e
      eout="$("$SNARKOS" developer execute "${STEM}.aleo" "$name" "$@" \
        --private-key "$PRIVATE_KEY" \
        --endpoint "$ENDPOINT" \
        --network "$NET_ID" \
        --broadcast \
        --priority-fee "$PRIORITY_FEE_U" \
        --verbosity 1 2>&1)"
      erc=$?
      set -e
      restore_home
      echo "$eout" | tail -30
      printf '%s\n' "$eout" >"${TX_DIR}/execute-${name}.log"
      if [[ "$erc" -ne 0 ]]; then
        die "snarkos execute ${name} failed (exit ${erc})"
      fi
      if ! grep -qE 'has been broadcast|Created execution' <<<"$eout"; then
        die "snarkos execute ${name} missing broadcast success marker"
      fi
      echo "${PREFIX}: ok: NETWORK-EXECUTE ${name}"
    }
    run_execute_snarkos initialize 1u64
    # wait briefly for finalize before increment (mapping state)
    sleep 2
    run_execute_snarkos increment 2u64
  fi
else
  deploy_args=(
    deploy
    --network "$NETWORK"
    --endpoint "$ENDPOINT"
    --private-key "$PRIVATE_KEY"
    --broadcast
    --yes
    --disable-update-check
    --path "$PKG"
    --save "$TX_DIR"
    --json-output="${TX_DIR}/deploy.json"
  )
  if [[ "$DEVNET" -eq 1 ]]; then
    deploy_args+=(--devnet)
  fi
  if [[ -n "$CONSENSUS_VERSION" ]]; then
    deploy_args+=(--consensus-version "$CONSENSUS_VERSION")
  fi
  if [[ "$SKIP_DEPLOY_CERT" -eq 1 ]]; then
    deploy_args+=(--skip-deploy-certificate)
  fi
  if [[ -n "${PRIORITY_FEES}" ]]; then
    deploy_args+=(--priority-fees "$PRIORITY_FEES")
  fi

  echo "${PREFIX}: --- leo deploy --broadcast (NETWORK-DEPLOY fallback) ---"
  isolate_leo_env
  set +e
  dout="$("$LEO" "${deploy_args[@]}" 2>&1)"
  drc=$?
  set -e
  restore_home
  echo "$dout" | tail -40
  if [[ "$drc" -ne 0 ]]; then
    die "leo deploy failed (exit ${drc}); install snarkos with test_network or check fees/endpoint"
  fi
  if grep -qiE 'Error \[ECLI|Failed to fetch|Failed to get consensus|insufficient base fee' <<<"$dout"; then
    die "leo deploy reported error in output"
  fi
  echo "${PREFIX}: ok: NETWORK-DEPLOY network=${NETWORK} program=${STEM}.aleo"

  if [[ "$DO_EXECUTE" -eq 1 ]]; then
    run_execute() {
      local name="$1"
      shift
      local ex_args=(
        execute
        --network "$NETWORK"
        --endpoint "$ENDPOINT"
        --private-key "$PRIVATE_KEY"
        --broadcast
        --yes
        --disable-update-check
        --path "$PKG"
        --json-output="${TX_DIR}/execute-${name}.json"
        "$name"
      )
      if [[ "$DEVNET" -eq 1 ]]; then
        ex_args+=(--devnet)
      fi
      if [[ -n "$CONSENSUS_VERSION" ]]; then
        ex_args+=(--consensus-version "$CONSENSUS_VERSION")
      fi
      ex_args+=("$@")
      echo "${PREFIX}: --- leo execute --broadcast ${name} $* (NETWORK-EXECUTE) ---"
      isolate_leo_env
      set +e
      eout="$("$LEO" "${ex_args[@]}" 2>&1)"
      erc=$?
      set -e
      restore_home
      echo "$eout" | tail -30
      if [[ "$erc" -ne 0 ]]; then
        die "leo execute ${name} failed (exit ${erc})"
      fi
      if grep -qiE 'Error \[ECLI|Failed to fetch' <<<"$eout"; then
        die "leo execute ${name} reported error in output"
      fi
      echo "${PREFIX}: ok: NETWORK-EXECUTE ${name}"
    }
    run_execute initialize 1u64
    run_execute increment 2u64
  fi
fi

echo "${PREFIX}: --- query-contract sidecar (descriptor; live query is separate) ---"
QC="$(find "$OUT" -maxdepth 1 -type f -name '*-query-contract.json' | head -1 || true)"
if [[ -n "$QC" && -f "$QC" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<PY
import json
with open("${QC}") as f:
    d = json.load(f)
print("${PREFIX}: schema=", d.get("schema"))
print("${PREFIX}: program=", d.get("program"))
print("${PREFIX}: executionModel=", d.get("executionModel"))
PY
  else
    head -c 300 "$QC"; echo
  fi
fi

cat <<EOF
${PREFIX}: --- maturity restate ---
${PREFIX}: profile=${PROFILE_LABEL}
${PREFIX}: NETWORK-DEPLOY completed for ${STEM}.aleo on ${NETWORK}
${PREFIX}: endpoint=${ENDPOINT}
${PREFIX}: tx_dir=${TX_DIR} (if leo wrote artifacts)
${PREFIX}: default product Finalize remains deployable=false (N3 not landed)
${PREFIX}: admit-surface programs only; unsupported ProgramV1 shapes fail closed at compile
${PREFIX}: NETWORK-OK
EOF
exit 0
