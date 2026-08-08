#!/usr/bin/env bash
# ALEO-IR-7 / G6 runtime honesty probe (host-heavy; NOT ordinary ci).
#
# Purpose:
#   Probe for a *locked* snarkVM (or honest package-only execute path) that can
#   consume product Aleo Instructions text (`{id}.aleo` from Plan→LowerPlanV1)
#   without inventing a CLI or treating Leo source as the runtime authority.
#
# Honesty baseline (RPT-024 + Tool Lock v4, 2026-08-08):
#   * Tool Lock pins Leo 4.0.2 only (leo build --offline; optional leo run is
#     Leo *source* interpret, not package-only Instructions execute).
#   * No snarkVM / snarkOS asset in either platform lock or materialize root.
#   * leo execute/deploy need REST stateRoot/block even with --offline.
#   * Therefore IR-7 default outcome is **PARTIAL + MISSING**:
#       PF-TOOLCHAIN-MISSING: no locked package-only execute tool
#     until a real pin lands. This script must not invent snarkVM flags.
#
# Locked probe contract (never PATH fallback):
#   $PROOF_FORGE_TOOL_ROOT/snarkvm
#   $PROOF_FORGE_TOOL_ROOT/snarkos
# Platform paths supported only:
#   linux-x86_64 | darwin-arm64
# Engineering runtime label (log only):
#   aleo-instructions-runtime-honesty-v1
#
# Exit codes:
#   0  locked snarkVM present + Counter execute pin passed
#      (not reachable until Tool Lock pin + honest package-only CLI exist)
#   1  locked tool present but execute/version contract failed
#   2  PF-TOOLCHAIN-MISSING / unsupported host / usage (expected default today)
#
# Non-claims:
#   not ordinary ci; not product Finalize; not prove/deploy; not formal;
#   not hermetic Stage-0; deployable=false remains exact.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="aleo-runtime-test"
PROFILE_LABEL="aleo-instructions-runtime-honesty-v1"

die() {
  echo "${PREFIX}: $*" >&2
  exit 1
}

missing() {
  echo "${PREFIX}: PF-TOOLCHAIN-MISSING: $*" >&2
  exit 2
}

usage_err() {
  echo "${PREFIX}: $*" >&2
  exit 2
}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    platform_id="linux-x86_64"
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-x86_64"
    ;;
  Darwin-arm64)
    platform_id="darwin-arm64"
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  *)
    missing "unsupported host platform $(uname -s)-$(uname -m) (only linux-x86_64 and darwin-arm64)"
    ;;
esac

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT%/}"

# Candidate locked paths only — never PATH / cargo / brew / homebrew.
SNARKVM="${TOOL_ROOT}/snarkvm"
SNARKOS="${TOOL_ROOT}/snarkos"
LEO="${TOOL_ROOT}/leo"

echo "${PREFIX}: profile=${PROFILE_LABEL} platform=${platform_id}"
echo "${PREFIX}: tool_root=${TOOL_ROOT}"

# Explicit non-authority: locked Leo (if present) is compile / optional source
# interpret only. IR-7 does **not** promote leo run/execute to package-only
# Instructions runtime maturity.
if [[ -x "$LEO" ]]; then
  echo "${PREFIX}: note: locked leo present at ${LEO}"
  echo "${PREFIX}: note: leo is NOT IR-7 package-only Instructions execute authority"
  echo "${PREFIX}: note: leo run = Leo source interpret only; leo execute needs network state"
else
  echo "${PREFIX}: note: locked leo absent at ${LEO} (compile path independent of IR-7)"
fi

have_snarkvm=0
have_snarkos=0
if [[ -x "$SNARKVM" ]]; then
  have_snarkvm=1
  echo "${PREFIX}: found executable snarkvm at ${SNARKVM}"
fi
if [[ -x "$SNARKOS" ]]; then
  have_snarkos=1
  echo "${PREFIX}: found executable snarkos at ${SNARKOS}"
fi

if [[ "$have_snarkvm" -eq 0 && "$have_snarkos" -eq 0 ]]; then
  cat >&2 <<EOF
${PREFIX}: PF-TOOLCHAIN-MISSING: no locked snarkVM/snarkOS at
  ${SNARKVM}
  ${SNARKOS}
${PREFIX}: PARTIAL honesty (ALEO-IR-7 / G6): package-only execute of product
  Instructions text is MISSING. Tool Lock pins Leo 4.0.2 only; RPT-024 blocked
  offline execute/deploy without snarkOS + CRS. Do not invent snarkVM CLI.
${PREFIX}: product materialize remains Instructions primary + deployable=false;
  ordinary ci does not run this recipe. Next honest step: pin a real package-only
  tool (if upstream provides one) under Tool Lock, then extend this probe.
EOF
  exit 2
fi

# Tool binary present under tool root, but Tool Lock has no snarkVM/snarkOS asset
# and this script must not invent execute flags. Fail closed until a pin lands.
cat >&2 <<EOF
${PREFIX}: locked-path snarkVM/snarkOS binary found under ${TOOL_ROOT}, but
  Tool Lock has no snarkVM/snarkOS asset / digest / version probe contract, and
  no package-only execute recipe is frozen (ALEO-IR-7). Refusing unpinned execute.
${PREFIX}: PF-TOOLCHAIN-MISSING: Tool Lock pin for package-only execute is absent
  (binary presence alone is not a product pin; do not invent CLI).
EOF
exit 2
