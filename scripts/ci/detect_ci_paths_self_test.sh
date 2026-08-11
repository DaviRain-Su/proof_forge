#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
fail=0
run() {
  local name="$1" list="$2"; shift 2
  export GITHUB_EVENT_NAME=pull_request GITHUB_REF_NAME=feature/x GITHUB_BASE_REF=main
  export PF_CI_PATH_LIST="$list"
  local out
  out="$(mktemp)"
  export GITHUB_OUTPUT="$out"
  bash scripts/ci/detect_ci_paths.sh >/dev/null
  local got
  got="$(grep -E '^(lean_product|target_smoke|solana_runtime|docs_only)=' "$out" | tr '\n' ' ')"
  rm -f "$out"
  unset PF_CI_PATH_LIST
  for part in "$@"; do
    if ! grep -q "$part" <<<"$got"; then
      echo "FAIL $name: missing $part (got: $got)" >&2
      fail=1
      return
    fi
  done
  echo "ok $name"
}
run docs_only $'docs/targets/01-evm.md\nREADME.md' lean_product=false target_smoke=false solana_runtime=false docs_only=true
run mcp_only $'clients/pf-mcp/src/index.ts' lean_product=false docs_only=true
run lean_core $'ProofForgeV2/Compiler/Pipeline.lean' lean_product=true target_smoke=true
run solana_rt $'runtime-tests/solana/tests/artifacts.rs' solana_runtime=true target_smoke=true lean_product=false
run solana_lean $'ProofForgeV2/Targets/Solana/FinalizeV1.lean' solana_runtime=true lean_product=true
run ci_self $'.github/workflows/ci.yml' lean_product=true target_smoke=true solana_runtime=true
out="$(mktemp)"
export GITHUB_EVENT_NAME=push GITHUB_REF_NAME=main GITHUB_OUTPUT="$out"
unset PF_CI_PATH_LIST || true
bash scripts/ci/detect_ci_paths.sh >/dev/null
got="$(grep -E '^(lean_product|target_smoke|solana_runtime)=' "$out" | tr '\n' ' ')"
rm -f "$out"
for part in lean_product=true target_smoke=true solana_runtime=true; do
  if ! grep -q "$part" <<<"$got"; then
    echo "FAIL force_main: missing $part (got: $got)" >&2
    fail=1
  fi
done
[[ "$fail" -eq 0 ]] && echo "ok force_main"

if [[ "$fail" -ne 0 ]]; then
  echo "detect_ci_paths_self_test: FAILED" >&2
  exit 1
fi
echo "detect_ci_paths_self_test: ok"
