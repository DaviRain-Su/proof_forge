#!/usr/bin/env bash
# Aleo local sandbox demo (engineering / hackathon path; NOT ordinary ci).
#
# Authority: docs/targets/09b-aleo-local-sandbox-demo.md
# Parent IR authority: docs/targets/09-aleo-instructions-lowering.md
#
# Pipeline:
#   1) proof-forge-next build Counter --target aleo (+ PROOF_FORGE_ALEO_EMIT_LEO=1)
#   2) pin product counter.aleo ≡ golden Instructions
#   3) stage Leo 4.0.2 package from product counter.leo (debug package path)
#   4) locked leo build --offline; pin build/main.aleo ≡ product Instructions
#   5) locked leo run --offline initialize / increment (local interpret only)
#
# Maturity (must stay honest):
#   * INSTRUCTIONS-PRIMARY: product authority is Plan→Instructions .aleo
#   * LEO-OFFLINE-RUN: local interpret — NOT chain deploy, NOT snarkVM package-only
#   * deployable=false; NOT ordinary ci; NOT formal / hermetic / mainnet
#
# Exit codes:
#   0  locked leo present; product+golden+build pins; offline runs ok
#   1  tool present but build/pin/run failed
#   2  PF-TOOLCHAIN-MISSING / unsupported host / usage
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="aleo-sandbox-demo"
PROFILE_LABEL="aleo-local-sandbox-demo-v1"
GOLDEN="testdata/golden/aleo-instructions-v1/counter.compiled.aleo"
# Official Leo local-dev default; NEVER use in production. Isolated HOME only.
readonly LEO_LOCAL_DEV_PRIVATE_KEY="APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH"

KEEP=0
SKIP_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) KEEP=1; shift ;;
    --skip-run) SKIP_RUN=1; shift ;;
    -h|--help)
      cat <<'EOF'
usage: aleo_local_sandbox_demo.sh [--keep] [--skip-run]

  Local sandbox demo: product Counter → Instructions pin → Leo package →
  offline leo build + leo run (initialize / increment).

  Requires locked Leo 4.0.2 at:
    $PROOF_FORGE_TOOL_ROOT/leo
    or $HOME/.cache/proof-forge-v2/tool-root/<platform>/leo
  Never PATH-fallback.

  Exit 0 on full success; 1 on pin/run failure; 2 if tool missing / bad host.
EOF
      exit 0
      ;;
    *)
      echo "${PREFIX}: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

die() {
  echo "${PREFIX}: $*" >&2
  exit 1
}

missing() {
  echo "${PREFIX}: PF-TOOLCHAIN-MISSING: $*" >&2
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
  missing "unsupported host $(uname -s)-$(uname -m) (only linux-x86_64 and darwin-arm64)"
fi

default_tool_root="${HOME}/.cache/proof-forge-v2/tool-root/${plat}"
export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT%/}"
LEO="${TOOL_ROOT}/leo"

echo "${PREFIX}: profile=${PROFILE_LABEL} platform=${plat}"
echo "${PREFIX}: tool_root=${TOOL_ROOT}"
echo "${PREFIX}: maturity=INSTRUCTIONS-PRIMARY + LEO-DEBUG-PACKAGE + LEO-OFFLINE-RUN"
echo "${PREFIX}: maturity=NOT-PACKAGE-ONLY-SNARKVM deployable=false"

if [[ ! -x "$LEO" ]]; then
  missing "locked leo not found at ${LEO} (materialize Tool Lock leo 4.0.2; no PATH fallback)"
fi

ver_line="$("$LEO" --version 2>&1 | head -1 || true)"
echo "${PREFIX}: leo=${LEO}"
echo "${PREFIX}: leo_version=${ver_line}"
if ! grep -q '4\.0\.2' <<<"$ver_line"; then
  die "expected Leo 4.0.2, got: ${ver_line}"
fi

PF_BIN="${root}/.lake/build/bin/proof-forge-next"
if [[ ! -x "$PF_BIN" ]]; then
  die "missing product CLI ${PF_BIN}; run: lake build proof_forge_next"
fi
if [[ ! -f "$GOLDEN" ]]; then
  die "missing golden ${GOLDEN}"
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/aleo-sandbox-demo.XXXXXX")"
cleanup() {
  if [[ "$KEEP" -eq 1 ]]; then
    echo "${PREFIX}: --keep workdir=${WORKDIR}"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

# Product CLI uses real HOME (elan/lake). Leo steps use isolated HOME only.
OUT="${WORKDIR}/product-out"
PKG="${WORKDIR}/counter"
DEMO_HOME="${WORKDIR}/leo-home"
REAL_HOME="${HOME}"
mkdir -p "$PKG/src" "$DEMO_HOME/.aleo"

isolate_leo_env() {
  export HOME="$DEMO_HOME"
  unset PRIVATE_KEY VIEW_KEY ADDRESS NETWORK ENDPOINT DEVNET \
        CONSENSUS_VERSION CONSENSUS_VERSION_HEIGHTS CONSENSUS_HEIGHTS \
        NETWORK_RETRIES PRIORITY_FEE FEE_RECORD \
        || true
}

restore_home() {
  export HOME="$REAL_HOME"
}

echo "${PREFIX}: --- product build (Instructions primary + Leo debug) ---"
# Do not pre-create -o dir: product publisher fails closed on existing path.
set +e
build_out="$(
  restore_home
  PROOF_FORGE_ALEO_EMIT_LEO=1 \
    lake env "$PF_BIN" build Examples/Counter.lean \
      --module Examples.Counter \
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

for f in counter.aleo counter.leo counter.aleo-query-contract.json manifest.json; do
  [[ -f "${OUT}/${f}" ]] || die "missing product artifact ${f}"
done
echo "${PREFIX}: product artifacts ok under ${OUT}"

if ! cmp -s "${OUT}/counter.aleo" "$GOLDEN"; then
  die "product counter.aleo !== golden ${GOLDEN}"
fi
echo "${PREFIX}: pin ok: product counter.aleo ≡ golden Instructions"

cat >"$PKG/program.json" <<'EOF'
{
  "program": "counter.aleo",
  "version": "0.1.0",
  "description": "proof-forge-next aleo local sandbox demo",
  "license": "MIT",
  "leo": "4.0.2",
  "dependencies": null,
  "dev_dependencies": null
}
EOF
cp "${OUT}/counter.leo" "$PKG/src/main.leo"
echo "${PREFIX}: staged Leo package from product counter.leo (LEO-DEBUG-PACKAGE)"

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
if ! cmp -s "${OUT}/counter.aleo" "$PKG/build/main.aleo"; then
  die "leo build/main.aleo !== product counter.aleo (Instructions pin broken)"
fi
echo "${PREFIX}: pin ok: leo build/main.aleo ≡ product Instructions"

if [[ "$SKIP_RUN" -eq 1 ]]; then
  echo "${PREFIX}: --skip-run: skipping leo run"
  echo "${PREFIX}: SANDBOX-DEMO-PASS (build pins only)"
  exit 0
fi

run_fn() {
  local name="$1"
  shift
  echo "${PREFIX}: --- leo run --offline ${name} $* ---"
  isolate_leo_env
  set +e
  # Explicit local-dev key so the script does not depend on ambient wallets.
  rout="$("$LEO" run --offline --disable-update-check \
    --private-key "$LEO_LOCAL_DEV_PRIVATE_KEY" \
    --path "$PKG" "$name" "$@" 2>&1)"
  rrc=$?
  set -e
  restore_home
  if [[ "$rrc" -ne 0 ]]; then
    echo "$rout" >&2
    die "leo run ${name} failed (exit ${rrc})"
  fi
  # Show the structured Output block when present; else a short tail.
  if grep -q '➡️  Output' <<<"$rout"; then
    echo "$rout" | sed -n '/➡️  Output/,$p' | head -20
  else
    echo "$rout" | tail -15
  fi
  echo "${PREFIX}: ok: leo run ${name} (LEO-OFFLINE-RUN local interpret)"
}

run_fn initialize 1u64
run_fn increment 2u64

echo "${PREFIX}: --- query-contract (network-state descriptor; not live query) ---"
if command -v python3 >/dev/null 2>&1; then
  python3 - <<PY
import json
p = "${OUT}/counter.aleo-query-contract.json"
with open(p) as f:
    d = json.load(f)
print("${PREFIX}: schema=", d.get("schema"))
print("${PREFIX}: program=", d.get("program"))
print("${PREFIX}: executionModel=", d.get("executionModel"))
for m in d.get("mappings") or []:
    print("${PREFIX}: mapping", m.get("name"), "dsl=", m.get("dslName"), "type=", m.get("type"))
for v in d.get("views") or []:
    print("${PREFIX}: view", v.get("name"), "→", v.get("mapping"), "[", v.get("key"), "]")
PY
else
  head -c 400 "${OUT}/counter.aleo-query-contract.json"
  echo
fi

cat <<EOF
${PREFIX}: --- maturity restate ---
${PREFIX}: profile=${PROFILE_LABEL}
${PREFIX}: INSTRUCTIONS-PRIMARY: product counter.aleo ≡ golden ≡ leo build/main.aleo
${PREFIX}: LEO-OFFLINE-RUN: initialize(1u64) + increment(2u64) local interpret only
${PREFIX}: NOT chain deploy / NOT leo execute broadcast / NOT snarkVM package-only
${PREFIX}: deployable=false; for package-only probe use: just aleo-runtime
${PREFIX}: SANDBOX-DEMO-PASS
EOF
exit 0
