#!/usr/bin/env bash
# Z2.4: validate direct .aleo with leo toolchain when present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${PATH}"
OUT="${PROOF_FORGE_ALEO_VALIDATE_OUT:-build/aleo/z2-validate}"
mkdir -p "$OUT"
note() { echo "aleo-instructions-validate: $1"; }

if ! command -v leo >/dev/null 2>&1; then
  note "SKIP: leo not on PATH"
  echo "=== aleo-instructions-validate: SKIP ==="
  exit 0
fi

# Emit direct instructions
lake env proof-forge emit --target aleo-leo --fixture counter --format aleo \
  -o "$OUT/Counter.aleo"
# Package with Leo source that leo already accepts, and ensure our .aleo matches
# golden (structural validation). Full snarkVM import of hand-written .aleo is
# not required for Z2.4 acceptance when leo is used as the official producer.
diff -u Examples/Backend/Aleo/Counter.golden.aleo "$OUT/Counter.aleo"

PKG="$OUT/pkg"
rm -rf "$PKG"
mkdir -p "$PKG/src"
cp Examples/Backend/Aleo/Counter.golden.leo "$PKG/src/main.leo"
printf '%s\n' '{"program":"counter.aleo","version":"0.1.0","description":"","license":"Apache-2.0"}' > "$PKG/program.json"
(cd "$PKG" && leo build >/dev/null)
diff -u "$OUT/Counter.aleo" "$PKG/build/main.aleo"

note "ok: direct .aleo matches leo-built instructions"
echo "=== aleo-instructions-validate: PASS ==="
