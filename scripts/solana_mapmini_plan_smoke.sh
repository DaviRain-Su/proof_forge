#!/usr/bin/env bash
# Engineering: MapMini dense Map pilot plan smoke (not Mollusk / not formal).
#
# pure-expr Map lowering exceeds SBPF 4 KiB frame under solana-sbpf-elf-v1, so
# this fixture validates plan+IDL layout only. Mollusk .so differential stays
# deferred until frame-friendly Map IR.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$root/.lake/build/bin/proof-forge-next"
src="$root/runtime-tests/solana/fixtures/MapMini.lean"
out="${PROOF_FORGE_MAPMINI_OUT:-$root/build/v2/mapmini-solana-plan}"

if [[ ! -x "$cli" ]]; then
  echo "solana-mapmini-plan: building proof-forge-next..." >&2
  (cd "$root" && lake build proof_forge_next) || {
    echo "solana-mapmini-plan: skipped: lake build failed" >&2
    exit 0
  }
fi
[[ -f "$src" ]] || { echo "solana-mapmini-plan: missing $src" >&2; exit 2; }

rm -rf "$out"
mkdir -p "$(dirname "$out")"
echo "solana-mapmini-plan: build MapMini --target solana (default plan)" >&2
if ! (cd "$root" && lake env "$cli" build \
  "runtime-tests/solana/fixtures/MapMini.lean" \
  --module MapMini \
  --target solana \
  -o "${out#"$root"/}"); then
  echo "solana-mapmini-plan: FAIL: MapMini plan build" >&2
  exit 1
fi

plan="$out/MapMini.sbpf-plan"
[[ -f "$plan" ]] || { echo "solana-mapmini-plan: FAIL: missing plan" >&2; exit 1; }

# Capacity-8 dense Map → 24 leaf fields m_0..m_23 + 8-byte header → exact-data-len=200.
if ! grep -q 'exact-data-len=200' "$plan"; then
  echo "solana-mapmini-plan: FAIL: expected exact-data-len=200 (8×3×8+8)" >&2
  exit 1
fi
if ! grep -q 'name=m_0 ' "$plan"; then
  echo "solana-mapmini-plan: FAIL: expected map leaf field m_0" >&2
  exit 1
fi
if ! grep -q 'name=m_23 ' "$plan"; then
  echo "solana-mapmini-plan: FAIL: expected map leaf field m_23" >&2
  exit 1
fi
if ! grep -q '\.handler .* put ' "$plan"; then
  echo "solana-mapmini-plan: FAIL: expected put handler" >&2
  exit 1
fi
if ! grep -q '\.handler .* get ' "$plan"; then
  echo "solana-mapmini-plan: FAIL: expected get handler" >&2
  exit 1
fi

echo "solana-mapmini-plan: ok plan layout (cap-8 Map; not Mollusk/ELF)" >&2
echo "solana-mapmini-plan: engineering only; not formal Reference↔Mollusk"
