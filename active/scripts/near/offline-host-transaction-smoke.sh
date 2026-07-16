#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pf-offline-transaction.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/transaction.wat" <<'WAT'
(module
  (import "env" "storage_write"
    (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "storage_read"
    (func $storage_read (param i64 i64 i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "panic" (func $panic (param i64 i64)))
  (memory (export "memory") 1)
  (global $counter (mut i64) (i64.const 7))
  (data (i32.const 0) "k")
  (data (i32.const 16) "\07\00\00\00\00\00\00\00")
  (data (i32.const 32) "\09\00\00\00\00\00\00\00")
  (data (i32.const 48) "boom")
  (data (i32.const 80) "\07\00\00\00\00\00\00\00")
  (func (export "seed")
    i64.const 1 i64.const 0
    i64.const 8 i64.const 16 i64.const 0
    call $storage_write drop)
  (func (export "fail")
    i64.const 1 i64.const 0
    i64.const 8 i64.const 32 i64.const 0
    call $storage_write drop
    i64.const 9 global.set $counter
    i32.const 80 i64.const 9 i64.store
    i64.const 4 i64.const 48 call $panic)
  (func (export "read_storage")
    i64.const 1 i64.const 0 i64.const 0 call $storage_read drop
    i64.const 0 i64.const 64 call $read_register
    i64.const 8 i64.const 64 call $value_return)
  (func (export "read_global")
    i32.const 64 global.get $counter i64.store
    i64.const 8 i64.const 64 call $value_return)
  (func (export "read_memory")
    i64.const 8 i64.const 80 call $value_return))
WAT

set +e
out="$(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- \
  run "$TMP/transaction.wat" seed fail read_storage read_global read_memory 2>&1)"
rc=$?
set -e
echo "$out"

if [[ "$rc" -eq 0 ]]; then
  echo "offline-host-transaction-smoke: expected panic sequence to exit non-zero" >&2
  exit 1
fi

grep -Fq "call 1:fail: error=panic=boom" <<<"$out"
grep -Fq "call 1:read_storage: return_hex=0700000000000000 return_u64=7" <<<"$out"
grep -Fq "call 1:read_global: return_hex=0700000000000000 return_u64=7" <<<"$out"
grep -Fq "call 1:read_memory: return_hex=0700000000000000 return_u64=7" <<<"$out"

echo "offline-host-transaction-smoke: ok"
