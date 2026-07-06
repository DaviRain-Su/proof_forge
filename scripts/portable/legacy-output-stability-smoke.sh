#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LEGACY_DIR="${PROOF_FORGE_LEGACY_COUNTER_OUT:-build/portable-counter}"
BEFORE="build/portable-counter-before.sha256"
AFTER="build/portable-counter-after.sha256"

hash_tree() {
  local dir="$1"
  local manifest="$2"
  python3 - "$dir" "$manifest" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifest = pathlib.Path(sys.argv[2])
lines = []
for path in sorted(p for p in root.rglob("*") if p.is_file()):
    rel = path.relative_to(root).as_posix()
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    lines.append(f"{digest}  {rel}")
manifest.write_text("\n".join(lines) + "\n")
PY
}

rm -rf "$LEGACY_DIR"
scripts/portable/counter-multi-target.sh
hash_tree "$LEGACY_DIR" "$BEFORE"

scripts/portable/counter-four-target-sdk.sh
hash_tree "$LEGACY_DIR" "$AFTER"

diff -u "$BEFORE" "$AFTER"
echo "legacy-output-stability-smoke: ok"
