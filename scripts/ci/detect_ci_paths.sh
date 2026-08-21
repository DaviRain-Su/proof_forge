#!/usr/bin/env bash
# Emit GitHub Actions outputs selecting which heavy CI lanes must run.
#
# Outputs (true/false):
#   lean_product      - ten zero-tool non-target/product shards + product/deletion gates
#   target_smoke      - provisioned target shards + target CLI/source-bound smoke
#   solana_runtime    - Mollusk / solana-runtime-test
#   near_runtime      - near-sandbox / near-runtime-test
#   cosmwasm_runtime  - cosmwasm-vm mock / cosmwasm-runtime-test
#   docs_only         - advisory: only docs/markdown/catalog-ish paths changed
#
# Policy (conservative — prefer running over missing regressions):
#   * workflow_dispatch / schedule → all heavy lanes
#   * push to main/master         → all heavy lanes (protect trunk)
#   * otherwise                   → path filter vs merge-base / before SHA
#
# docs job always runs in ci.yml (not gated here).
set -euo pipefail

out() {
  local key="$1" val="$2"
  echo "${key}=${val}" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "detect_ci_paths: ${key}=${val}" >&2
}

force_all() {
  out lean_product true
  out target_smoke true
  out solana_runtime true
  out near_runtime true
  out cosmwasm_runtime true
  out docs_only false
  exit 0
}

EVENT_NAME="${GITHUB_EVENT_NAME:-}"
REF_NAME="${GITHUB_REF_NAME:-}"
BEFORE_SHA="${GITHUB_EVENT_BEFORE:-}"
BASE_SHA="${GITHUB_BASE_REF:-}"

case "${EVENT_NAME}" in
  workflow_dispatch|schedule)
    echo "detect_ci_paths: force all (${EVENT_NAME})" >&2
    force_all
    ;;
esac

if [[ "${EVENT_NAME}" == "push" && ( "${REF_NAME}" == "main" || "${REF_NAME}" == "master" ) ]]; then
  echo "detect_ci_paths: force all (push to ${REF_NAME})" >&2
  force_all
fi

# Test harness: newline-separated paths in PF_CI_PATH_LIST (skip git).
if [[ -n "${PF_CI_PATH_LIST:-}" ]]; then
  files=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    files+=("${line}")
  done <<< "${PF_CI_PATH_LIST}"
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "detect_ci_paths: empty PF_CI_PATH_LIST; force all" >&2
    force_all
  fi
  echo "detect_ci_paths: harness files=${#files[@]}" >&2
  # Jump past git range collection by reusing the classification loop via a flag.
  PF_CI_PATH_HARNESS=1
else
  PF_CI_PATH_HARNESS=0
fi

if [[ "${PF_CI_PATH_HARNESS}" != "1" ]]; then
# Resolve diff range.
range=""
if [[ "${EVENT_NAME}" == "pull_request" ]]; then
  # actions/checkout with fetch-depth 0; base is origin/<base_ref>
  base_ref="${GITHUB_BASE_REF:-main}"
  if git rev-parse --verify "origin/${base_ref}" >/dev/null 2>&1; then
    range="origin/${base_ref}...HEAD"
  elif git rev-parse --verify "${base_ref}" >/dev/null 2>&1; then
    range="${base_ref}...HEAD"
  fi
elif [[ "${EVENT_NAME}" == "push" ]]; then
  if [[ -n "${BEFORE_SHA}" && "${BEFORE_SHA}" != "0000000000000000000000000000000000000000" ]]; then
    if git cat-file -e "${BEFORE_SHA}^{commit}" 2>/dev/null; then
      range="${BEFORE_SHA}...HEAD"
    fi
  fi
fi

if [[ -z "${range}" ]]; then
  echo "detect_ci_paths: no reliable range; force all" >&2
  force_all
fi

# Portable file list (bash 3.2+ / no mapfile dependency).
files=()
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  files+=("${line}")
done < <(git diff --name-only "${range}" 2>/dev/null || true)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "detect_ci_paths: empty diff; force all (safe)" >&2
  force_all
fi

echo "detect_ci_paths: range=${range} files=${#files[@]}" >&2
fi  # end non-harness git range

is_docs_path() {
  local f="$1"
  case "${f}" in
    docs/*|presentation/*|licenses/*|Examples/*.md)
      return 0 ;;
    *.md|*.mdx|LICENSE|SECURITY.md|RECOVERY.md|MIGRATION_MATRIX.md|QUALIFICATION_INVENTORY.md)
      return 0 ;;
    docs/product/*|docs/demos/*|docs/adr/*|docs/targets/*|docs/plan/*|docs/research/*)
      return 0 ;;
    clients/pf-mcp/content/*|clients/pf-mcp/README.md|clients/pf-mcp/src/bundled.ts)
      # bundled.ts is generated from docs; treat with mcp path class below
      return 1 ;;
  esac
  return 1
}

is_mcp_or_template() {
  local f="$1"
  case "${f}" in
    clients/pf-mcp/*|templates/*|clients/solana-dapp-ui/*|clients/pf-cli/README.md)
      return 0 ;;
  esac
  return 1
}

# Pure Solana Mollusk / CPI runtime surface (does not by itself force lean-product).
is_solana_runtime_core() {
  local f="$1"
  case "${f}" in
    ProofForgeV2/Targets/Solana/*|runtime-tests/solana/*)
      return 0 ;;
    scripts/solana_*|scripts/*solana*|scripts/pf_solana_*)
      return 0 ;;
    supply-chain/solana*|supply-chain/solana-cpi-assets/*)
      return 0 ;;
  esac
  return 1
}

is_near_runtime_core() {
  local f="$1"
  case "${f}" in
    ProofForgeV2/Targets/Near/*|runtime-tests/near/*)
      return 0 ;;
    scripts/near_*|scripts/*near*|scripts/pf_near_*)
      return 0 ;;
    Examples/ConstAnswer.lean|Examples/UnixTimeCheck.lean|Examples/PoseTransform.lean|Examples/BlockHeightCheck.lean)
      return 0 ;;
  esac
  return 1
}

is_cosmwasm_runtime_core() {
  local f="$1"
  case "${f}" in
    ProofForgeV2/Targets/CosmWasm/*|runtime-tests/cosmwasm/*)
      return 0 ;;
    scripts/cosmwasm_*|scripts/*cosmwasm*|scripts/pf_cosmwasm_*)
      return 0 ;;
    Examples/ConstAnswer.lean|Examples/UnixTimeCheck.lean|Examples/PoseTransform.lean|Examples/BlockHeightCheck.lean|Examples/TipJar.lean|Examples/TokenJar.lean)
      return 0 ;;
  esac
  return 1
}

# Paths that change the product CLI binary used by host runtime tests.
is_runtime_cli_dep() {
  local f="$1"
  case "${f}" in
    justfile|lakefile.lean|lean-toolchain|lake-manifest.json|ProofForgeV2.lean)
      return 0 ;;
    ProofForgeV2/CLI/*|ProofForgeV2/Materialization/*|ProofForgeV2/Compiler/*)
      return 0 ;;
    ProofForgeV2/Targets/EngineeringBuildV1.lean|ProofForgeV2/Targets/EnvelopeV1.lean|ProofForgeV2/Targets/DescriptorDataV1.lean)
      return 0 ;;
    .github/workflows/ci.yml|.github/workflows/ci-nightly.yml|scripts/ci/*)
      return 0 ;;
  esac
  return 1
}

# Back-compat alias used by Solana classification.
is_solana_cli_dep() {
  is_runtime_cli_dep "$1"
}

is_solana_runtime() {
  local f="$1"
  if is_solana_runtime_core "${f}" || is_runtime_cli_dep "${f}"; then
    return 0
  fi
  return 1
}

is_near_runtime() {
  local f="$1"
  if is_near_runtime_core "${f}" || is_runtime_cli_dep "${f}"; then
    return 0
  fi
  return 1
}

is_cosmwasm_runtime() {
  local f="$1"
  if is_cosmwasm_runtime_core "${f}" || is_runtime_cli_dep "${f}"; then
    return 0
  fi
  return 1
}

is_target_smoke() {
  local f="$1"
  case "${f}" in
    Tests/Materialization/*|Tests/Targets/*|Tests/CLI/*|Tests/Product/*|Tests/Shards/Targets*)
      return 0 ;;
    Tests/Language/ProgramV1Bounds.lean|scripts/program_v1_source_bounds)
      return 0 ;;
    ProofForgeV2/Targets/*|Examples/*)
      return 0 ;;
    scripts/evm_*|scripts/near_*|scripts/psy_*|scripts/noir_*|scripts/cosmwasm_*|scripts/ton_*|scripts/quint_*)
      return 0 ;;
    scripts/pf_evm_*|scripts/smoke_evm*|scripts/mcp_*|scripts/local_*)
      return 0 ;;
    testdata/evm-corpus/*)
      return 0 ;;
    # Non-Solana runtime-tests still force target-smoke (NEAR sandbox fixtures, etc.)
    runtime-tests/near/*|runtime-tests/evm/*|runtime-tests/cosmwasm/*|runtime-tests/noir/*)
      return 0 ;;
    justfile|lakefile.lean|lean-toolchain|lake-manifest.json|Tests.lean|Examples.lean)
      return 0 ;;
    ProofForgeV2/*)
      return 0 ;;
    supply-chain/*)
      return 0 ;;
    .github/workflows/ci.yml|.github/workflows/ci-nightly.yml|scripts/ci/*|scripts/docs_check.py|scripts/sbom_*|scripts/gate_*)
      return 0 ;;
  esac
  return 1
}

is_lean_product() {
  local f="$1"
  if is_docs_path "${f}"; then
    return 1
  fi
  if is_mcp_or_template "${f}"; then
    case "${f}" in
      .github/*|justfile|scripts/ci/*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  # Pure host-runtime fixture/script edits: covered by *-runtime jobs +
  # target-smoke when lowering Lean changes; skip lean-product for runtime-tests only.
  if is_solana_runtime_core "${f}"; then
    case "${f}" in
      ProofForgeV2/Targets/Solana/*)
        return 0 ;;  # Solana lowering still needs product Lean shards when shared
      runtime-tests/solana/*)
        return 1 ;;
      scripts/solana_*|scripts/*solana*|scripts/pf_solana_*)
        return 1 ;;
      supply-chain/solana*|supply-chain/solana-cpi-assets/*)
        return 1 ;;
    esac
  fi
  if is_near_runtime_core "${f}"; then
    case "${f}" in
      ProofForgeV2/Targets/Near/*|Examples/*)
        return 0 ;;
      runtime-tests/near/*|scripts/near_*|scripts/*near*|scripts/pf_near_*)
        return 1 ;;
    esac
  fi
  if is_cosmwasm_runtime_core "${f}"; then
    case "${f}" in
      ProofForgeV2/Targets/CosmWasm/*|Examples/*)
        return 0 ;;
      runtime-tests/cosmwasm/*|scripts/cosmwasm_*|scripts/*cosmwasm*|scripts/pf_cosmwasm_*)
        return 1 ;;
    esac
  fi
  case "${f}" in
    ProofForgeV2/*|Tests/*|Examples/*|scripts/*|supply-chain/*|testdata/*|runtime-tests/*)
      return 0 ;;
    justfile|lakefile.lean|lean-toolchain|lake-manifest.json|*.lean|host-*.lock*|toolchains*.lock.json|unicode.lock.json)
      return 0 ;;
    .github/workflows/ci.yml|.github/workflows/ci-nightly.yml|scripts/ci/*)
      return 0 ;;
    clients/pf-cli/*)
      return 0 ;;
  esac
  # Unknown path → run lean-product (fail closed on filter gaps)
  return 0
}

lean_product=false
target_smoke=false
solana_runtime=false
near_runtime=false
cosmwasm_runtime=false
all_docs_or_mcp=true

for f in "${files[@]}"; do
  if ! is_docs_path "${f}" && ! is_mcp_or_template "${f}"; then
    all_docs_or_mcp=false
  fi
  if is_lean_product "${f}"; then
    lean_product=true
  fi
  if is_target_smoke "${f}"; then
    target_smoke=true
  fi
  if is_solana_runtime "${f}"; then
    solana_runtime=true
  fi
  if is_near_runtime "${f}"; then
    near_runtime=true
  fi
  if is_cosmwasm_runtime "${f}"; then
    cosmwasm_runtime=true
  fi
done

# Target smoke implies we already pay for a lake build; keep lean gates when
# product Lean changed. docs/mcp-only → no heavy lanes.
if [[ "${all_docs_or_mcp}" == "true" ]]; then
  lean_product=false
  target_smoke=false
  solana_runtime=false
  near_runtime=false
  cosmwasm_runtime=false
fi

# Changing CI path logic itself must exercise all lanes once.
for f in "${files[@]}"; do
  case "${f}" in
    .github/workflows/ci.yml|.github/workflows/ci-nightly.yml|scripts/ci/detect_ci_paths.sh|.github/actions/*)
      lean_product=true
      target_smoke=true
      solana_runtime=true
      near_runtime=true
      cosmwasm_runtime=true
      all_docs_or_mcp=false
      ;;
  esac
done

# If only host runtime-tests/scripts changed (no Lean product), still run
# target-smoke + the matching *-runtime job, but lean-product may stay off.
if [[ "${solana_runtime}" == "true" && "${lean_product}" == "false" ]]; then
  target_smoke=true
fi
if [[ "${near_runtime}" == "true" && "${lean_product}" == "false" ]]; then
  target_smoke=true
fi
if [[ "${cosmwasm_runtime}" == "true" && "${lean_product}" == "false" ]]; then
  target_smoke=true
fi
docs_only=false
if [[ "${all_docs_or_mcp}" == "true" ]]; then
  docs_only=true
fi

out lean_product "${lean_product}"
out target_smoke "${target_smoke}"
out solana_runtime "${solana_runtime}"
out near_runtime "${near_runtime}"
out cosmwasm_runtime "${cosmwasm_runtime}"
out docs_only "${docs_only}"
