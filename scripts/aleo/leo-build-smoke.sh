#!/usr/bin/env bash
# Real Aleo compile gate: render every generated feature shape and `leo build` it.
# Verifies the generated Leo actually COMPILES (the Lean marker-smokes only check
# substrings). Needs `leo` (4.0.2) on PATH; exits 127 if absent (optional gate,
# like the CI aleo-smoke job).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_DIR="${ROOT}/build/aleo/verify"

if ! command -v leo >/dev/null 2>&1; then
  echo "aleo-leo-build-smoke: leo not found (skip; install Leo 4.0.2 to run this gate)" >&2
  exit 127
fi

cd "${ROOT}"
lake build ProofForge.Backend.Aleo.IR >/dev/null
lake env lean --run RenderAleoFixtures.lean >/dev/null

# crosscall imports an external program (credits.aleo) that does not exist
# locally, so it is excluded — its syntax still parses (leo reaches dependency
# resolution), but a full build needs the dependency.
fail=0
for f in "${VERIFY_DIR}"/*.leo; do
  name="$(basename "$f" .leo)"
  [ "$name" = "crosscall" ] && { echo "[leo build] $name: skip (needs external program dep)"; continue; }
  pid="$(grep -oE 'program [a-z0-9_]+\.aleo' "$f" | head -1 | awk '{print $2}')"
  dir="${VERIFY_DIR}/${name}"
  rm -rf "$dir"; mkdir -p "$dir/src"; cp "$f" "$dir/src/main.leo"
  printf '{"program":"%s","version":"0.1.0","description":"","license":"MIT"}\n' "$pid" > "$dir/program.json"
  if (cd "$dir" && leo build) >/dev/null 2>&1; then
    echo "[leo build] $name: OK"
  else
    echo "[leo build] $name: FAILED"; (cd "$dir" && leo build 2>&1 | grep -i error | head -3) >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "aleo-leo-build-smoke: one or more fixtures failed to compile" >&2
  exit 1
fi
echo "aleo-leo-build-smoke: all generated Leo compiles (leo $(leo --version 2>/dev/null | awk '{print $2}'))"
