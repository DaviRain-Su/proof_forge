#!/usr/bin/env bash
set -euo pipefail

# Validate that unsupported or malformed EVM IR and EVM artifact-boundary
# shapes fail before source generation with stable, explicit diagnostics.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT"
lake build proof-forge Examples.Shared.Counter >/dev/null
lake env lean --run Tests/EvmDiagnostics.lean

run_cli_diagnostic() {
  local name="$1"
  local expected="$2"
  shift 2

  local out_dir="$ROOT/build/evm-diagnostics/$name"
  local stdout_log="$out_dir/stdout.log"
  local stderr_log="$out_dir/stderr.log"
  rm -rf "$out_dir"
  mkdir -p "$out_dir"

  set +e
  lake env proof-forge build --target evm \
    --root . \
    --module Counter \
    --yul-output "$out_dir/Counter.yul" \
    --artifact-output "$out_dir/Counter.proof-forge-artifact.json" \
    -o "$out_dir/Counter.bin" \
    "$@" \
    Examples/Evm/Contracts/Counter.lean \
    >"$stdout_log" 2>"$stderr_log"
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "evm-diagnostics: expected CLI case '$name' to fail" >&2
    echo "stdout:" >&2
    cat "$stdout_log" >&2
    echo "stderr:" >&2
    cat "$stderr_log" >&2
    exit 1
  fi

  if ! grep -Fq -- "$expected" "$stderr_log"; then
    echo "evm-diagnostics: CLI case '$name' did not emit expected diagnostic" >&2
    echo "expected substring: $expected" >&2
    echo "stdout:" >&2
    cat "$stdout_log" >&2
    echo "stderr:" >&2
    cat "$stderr_log" >&2
    exit 1
  fi

  echo "evm-diagnostics: ok: $name"
}

raw_constructor_arg="000000000000000000000000000000000000000000000000000000000000007b"

run_cli_diagnostic \
  "constructor string empty value" \
  "invalid constructor argument spec 'memo=': value is empty" \
  --evm-constructor-param "memo:string" \
  --evm-constructor-arg "memo="

run_cli_diagnostic \
  "constructor schema missing args" \
  "--evm-constructor-arg \`other\` has no matching --evm-constructor-param" \
  --evm-constructor-param "initial:uint256" \
  --evm-constructor-arg "other=1"

run_cli_diagnostic \
  "constructor duplicate typed value" \
  "duplicate --evm-constructor-arg for \`initial\`" \
  --evm-constructor-param "initial:uint256" \
  --evm-constructor-arg "initial=1" \
  --evm-constructor-arg "initial=2"

run_cli_diagnostic \
  "constructor mixed typed and raw args" \
  "--evm-constructor-arg cannot be combined with --evm-constructor-args-hex" \
  --evm-constructor-param "initial:uint256" \
  --evm-constructor-arg "initial=1" \
  --evm-constructor-args-hex "$raw_constructor_arg"

run_cli_diagnostic \
  "constructor uint32 overflow" \
  "constructor argument \`small\` does not fit in uint32" \
  --evm-constructor-param "small:uint32" \
  --evm-constructor-arg "small=4294967296"

run_cli_diagnostic \
  "constructor address length" \
  "constructor argument \`owner\` must be exactly 20 byte(s)" \
  --evm-constructor-param "owner:address" \
  --evm-constructor-arg "owner=0x1234"
