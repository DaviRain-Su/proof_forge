#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BUILD_DIR="${1:-build/sui/counter}"
SRC="$BUILD_DIR/sources/counter.move"

if [[ ! -f "$SRC" ]]; then
  rm -rf "$BUILD_DIR"
  lake env proof-forge emit --target move-sui --fixture counter --format sui -o "$BUILD_DIR"
fi

grep -E 'object::new|UID|TxContext' "$SRC" >/dev/null
grep -E 'public fun (create|initialize)\(ctx: &mut TxContext\): Counter' "$SRC" >/dev/null
grep -E 'public fun increment\(counter: &mut Counter\)' "$SRC" >/dev/null
grep -E 'public fun (value|get)\(counter: &Counter\): u64' "$SRC" >/dev/null
grep -E 'object::delete' "$SRC" >/dev/null

! grep -E 'borrow_global|borrow_global_mut|move_to|signer::address_of|aptos_framework|AptosFramework' "$SRC"
! grep -E 'aptos_framework|AptosFramework' "$BUILD_DIR/Move.toml"

echo "sui-object-semantics: ok"
