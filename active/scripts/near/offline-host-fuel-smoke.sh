#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pf-offline-fuel.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/fuel.wat" <<'WAT'
(module
  (memory (export "memory") 1)
  (func (export "burn")
    (local $i i32)
    i32.const 0
    local.set $i
    block
      loop
        local.get $i
        i32.const 100
        i32.ge_u
        br_if 1
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br 0
      end
    end))
WAT

out="$(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- \
  run "$TMP/fuel.wat" burn burn --fuel 1200)"
echo "$out"

first="$(grep -F 'call 1:burn:' <<<"$out" | sed -n '1p')"
second="$(grep -F 'call 1:burn:' <<<"$out" | sed -n '2p')"
[[ -n "$first" && -n "$second" ]]

field() {
  local line="$1" name="$2"
  sed -E "s/.*${name}=([0-9]+).*/\1/" <<<"$line"
}

delta1="$(field "$first" wasmtimeFuelDelta)"
delta2="$(field "$second" wasmtimeFuelDelta)"
cumulative1="$(field "$first" wasmtimeFuelCumulative)"
cumulative2="$(field "$second" wasmtimeFuelCumulative)"

if (( delta1 <= 0 )); then
  echo "offline-host-fuel-smoke: first receipt consumed no fuel" >&2
  exit 1
fi
if (( delta1 != delta2 )); then
  echo "offline-host-fuel-smoke: identical receipts used different fuel" >&2
  exit 1
fi
if (( cumulative1 != delta1 || cumulative2 != delta1 + delta2 )); then
  echo "offline-host-fuel-smoke: cumulative accounting mismatch" >&2
  exit 1
fi
if (( cumulative2 <= 1200 )); then
  echo "offline-host-fuel-smoke: test does not exceed one receipt budget" >&2
  exit 1
fi

echo "offline-host-fuel-smoke: ok"
