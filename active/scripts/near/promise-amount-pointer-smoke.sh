#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pf-promise-amount.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/amount.wat" <<'WAT'
(module
  (import "env" "promise_create"
    (func $promise_create (param i64 i64 i64 i64 i64 i64 i64 i64) (result i64)))
  (import "env" "promise_then"
    (func $promise_then (param i64 i64 i64 i64 i64 i64 i64 i64 i64) (result i64)))
  (memory (export "memory") 1)
  (data (i32.const 0) "peer.test")
  (data (i32.const 16) "receive")
  ;; 2^64 + 42, encoded as a little-endian u128 at offset 64.
  (data (i32.const 64) "\2a\00\00\00\00\00\00\00\01\00\00\00\00\00\00\00")
  ;; 9, encoded as a little-endian u128 at offset 80.
  (data (i32.const 80) "\09\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00")
  (func (export "schedule")
    (local $p i64)
    i64.const 9 i64.const 0
    i64.const 7 i64.const 16
    i64.const 0 i64.const 0
    i64.const 64 i64.const 100
    call $promise_create
    local.set $p
    local.get $p
    i64.const 9 i64.const 0
    i64.const 7 i64.const 16
    i64.const 0 i64.const 0
    i64.const 80 i64.const 200
    call $promise_then
    drop))
WAT

out="$(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- \
  run "$TMP/amount.wat" schedule)"
echo "$out"

grep -Fq "promise_create id=0 account=peer.test method=receive args= deposit=18446744073709551658 gas=100" <<<"$out"
grep -Fq "promise_then id=1 parent=0 account=peer.test method=receive args= deposit=9 gas=200" <<<"$out"

echo "promise-amount-pointer-smoke: ok"
