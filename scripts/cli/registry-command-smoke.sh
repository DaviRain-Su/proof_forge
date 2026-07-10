#!/usr/bin/env bash
# PF-P0-02: registry membership means ≥1 CLI command, not source-build support.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${PROOF_FORGE_REGISTRY_COMMAND_OUT:-build/registry-command}"
rm -rf "$OUT"
mkdir -p "$OUT"

lake build proof-forge >/dev/null

fail() {
  echo "registry-command: $*" >&2
  exit 1
}

help_text="$(lake env proof-forge --help 2>&1 || true)"
echo "$help_text" | grep -Fq -- "--list-targets" || fail "help missing --list-targets"
echo "$help_text" | grep -Fq "at least one" || \
  echo "$help_text" | grep -Fq "≥1 CLI command" || \
  fail "help missing list-targets membership rule (at least one / ≥1 CLI command)"
echo "$help_text" | grep -Fq "not a promise" || \
  fail "help missing 'not a promise of Lean contract_source build support'"

# Cloudflare fixture emit is the supported command that justifies list membership.
lake env proof-forge emit --target wasm-cloudflare-workers --fixture counter --format ts \
  -o "$OUT/counter.ts" >/dev/null
[[ -s "$OUT/counter.ts" ]] || fail "cloudflare fixture emit produced empty file"

# Source build/check must fail closed with stable diagnostics (never unknown target).
set +e
build_err="$(lake env proof-forge build --target wasm-cloudflare-workers --root . \
  -o "$OUT/cf-build" Examples/Product/ValueVault.lean 2>&1)"
build_st=$?
check_err="$(lake env proof-forge check --target wasm-cloudflare-workers --root . \
  Examples/Product/ValueVault.lean 2>&1)"
check_st=$?
set -e

[[ "$build_st" -ne 0 ]] || fail "cloudflare source build should fail"
echo "$build_err" | grep -Fq "source input is not supported" || fail "build missing source-input diagnostic: $build_err"
echo "$build_err" | grep -Fq "unknown target" && fail "build returned unknown target: $build_err"

[[ "$check_st" -ne 0 ]] || fail "cloudflare source check should fail"
echo "$check_err" | grep -Fq "source input is not supported" || fail "check missing source-input diagnostic: $check_err"
echo "$check_err" | grep -Fq "unknown target" && fail "check returned unknown target: $check_err"

# Fixture check for Cloudflare should resolve the profile and pass.
lake env proof-forge check --target wasm-cloudflare-workers --fixture counter >/dev/null

# No listed target id falls through to "unknown target '<id>'" on source build.
while IFS= read -r target; do
  [[ -n "$target" ]] || continue
  set +e
  err="$(lake env proof-forge build --target "$target" --root . \
    -o "$OUT/src-$target" Examples/Product/ValueVault.lean 2>&1)"
  st=$?
  set -e
  if echo "$err" | grep -Fq "unknown target '$target'"; then
    fail "listed target $target reported unknown target on build"
  fi
  if echo "$err" | grep -Fq "unknown target \"$target\""; then
    fail "listed target $target reported unknown target on build"
  fi
  # Success or fail-closed is fine; only silent Counter was PF-P0-01.
  if [[ "$st" -eq 0 ]]; then
    echo "registry-command: $target build ok (source)"
  else
    echo "registry-command: $target build fail-closed"
  fi
done < <(lake env proof-forge --list-targets)

echo "registry-command: ok"
