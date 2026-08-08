#!/usr/bin/env bash
# NOIR-IR-7 / G6 prove honesty probe (host-heavy; NOT ordinary ci).
#
# Purpose:
#   Probe for a *locked* Barretenberg / bb prove backend that can consume
#   product ACIR (nargo ProgramArtifact / dual-write extras) without inventing
#   a prove CLI, CRS workflow, or treating nargo compile as prove maturity.
#
# Honesty baseline (Tool Lock v4 + C-4 / C-7, 2026-08-08):
#   * Tool Lock pins nargo 1.0.0-beta.26 compile-only only.
#   * unresolved.barretenberg remains null — not an implementation commitment.
#   * No bb / barretenberg / noir-backend asset in either platform lock or
#     materialize root.
#   * Therefore IR-7 default outcome is **PARTIAL + MISSING**:
#       PF-TOOLCHAIN-MISSING: no locked prove backend
#     until a real pin lands. This script must not invent prove flags or CRS.
#
# Locked probe contract (never PATH fallback):
#   $PROOF_FORGE_TOOL_ROOT/bb
#   $PROOF_FORGE_TOOL_ROOT/barretenberg
#   $PROOF_FORGE_TOOL_ROOT/nargo  (compile-only note only; NOT prove authority)
# Platform paths supported only:
#   linux-x86_64 | darwin-arm64
# Engineering runtime label (log only):
#   noir-acir-prove-honesty-v1
#
# Exit codes:
#   0  locked prove backend present + Counter prove pin passed
#      (not reachable until Tool Lock pin + honest prove recipe exist)
#   1  locked tool present but prove/version contract failed
#   2  PF-TOOLCHAIN-MISSING / unsupported host / usage (expected default today)
#
# Non-claims:
#   not ordinary ci; not product Finalize; not prove product path; not formal;
#   not hermetic Stage-0; deployable=false remains exact.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="noir-runtime-test"
PROFILE_LABEL="noir-acir-prove-honesty-v1"

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

# Candidate locked paths only — never PATH / cargo / brew / homebrew / noirup.
BB="${TOOL_ROOT}/bb"
BARRETENBERG="${TOOL_ROOT}/barretenberg"
NARGO="${TOOL_ROOT}/nargo"

echo "${PREFIX}: profile=${PROFILE_LABEL} platform=${platform_id}"
echo "${PREFIX}: tool_root=${TOOL_ROOT}"

# Explicit non-authority: locked nargo (if present) is compile-only. IR-7 does
# **not** promote `nargo prove` / execute to product prove maturity without a
# Tool Lock Barretenberg/backend pin and frozen recipe.
if [[ -x "$NARGO" ]]; then
  echo "${PREFIX}: note: locked nargo present at ${NARGO}"
  echo "${PREFIX}: note: nargo is compile-only for IR-1..IR-6; NOT IR-7 prove authority"
  echo "${PREFIX}: note: unresolved.barretenberg=null in Tool Lock; no CRS/prove pin"
else
  echo "${PREFIX}: note: locked nargo absent at ${NARGO} (compile path independent of IR-7)"
fi

have_bb=0
have_barretenberg=0
if [[ -x "$BB" ]]; then
  have_bb=1
  echo "${PREFIX}: found executable bb at ${BB}"
fi
if [[ -x "$BARRETENBERG" ]]; then
  have_barretenberg=1
  echo "${PREFIX}: found executable barretenberg at ${BARRETENBERG}"
fi

if [[ "$have_bb" -eq 0 && "$have_barretenberg" -eq 0 ]]; then
  cat >&2 <<EOF
${PREFIX}: PF-TOOLCHAIN-MISSING: no locked Barretenberg/bb prove backend at
  ${BB}
  ${BARRETENBERG}
${PREFIX}: PARTIAL honesty (NOIR-IR-7 / G6): product Counter prove/VK is MISSING.
  Tool Lock pins nargo 1.0.0-beta.26 compile-only; unresolved.barretenberg=null.
  Do not invent bb/prove CLI, CRS, or witness/VK product binding.
${PREFIX}: product materialize remains nargo-assisted ACIR dual-write (opt-in) +
  deployable=false; ordinary ci does not run this recipe. Next honest step: pin a
  real prove backend under Tool Lock (if upstream provides one), then extend this
  probe with a minimal Counter prove pin (still host-heavy; not ordinary ci).
EOF
  exit 2
fi

# Tool binary present under tool root, but Tool Lock has no barretenberg asset
# and this script must not invent prove flags or CRS. Fail closed until a pin lands.
cat >&2 <<EOF
${PREFIX}: locked-path bb/barretenberg binary found under ${TOOL_ROOT}, but
  Tool Lock has no barretenberg asset / digest / version probe contract, and
  no Counter prove recipe is frozen (NOIR-IR-7). Refusing unpinned prove.
${PREFIX}: PF-TOOLCHAIN-MISSING: Tool Lock pin for prove backend is absent
  (binary presence alone is not a product pin; do not invent CLI/CRS).
EOF
exit 2
