#!/usr/bin/env bash
# P3: portable AccessControl → solana-sbpf-asm (hash4 limb0 ≥ 2^63 must assemble).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.foundry/bin:${HOME}/.elan/bin:${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH:-}"

OUT="${OUT:-build/solana/access-control-smoke}"
mkdir -p "$OUT"

if [[ -x .lake/build/bin/proof-forge ]]; then
  PF=".lake/build/bin/proof-forge"
else
  lake build proof-forge
  PF=".lake/build/bin/proof-forge"
fi

if ! command -v sbpf >/dev/null 2>&1; then
  echo "access-control-product-smoke: sbpf not on PATH (install blueshift-gg/sbpf)" >&2
  exit 1
fi

echo "access-control-product-smoke: build AccessControl → ${OUT}"
lake env "$PF" build --target solana-sbpf-asm --root . \
  -o "${OUT}/AccessControl" \
  Examples/Product/AccessControl.lean

# Fail if generated assembly still contains unsigned decimals ≥ 2^63 (sbpf rejects).
ASM="$(find "$OUT" -name 'AccessControl.s' | head -1)"
if [[ -z "$ASM" ]]; then
  echo "access-control-product-smoke: AccessControl.s not found under ${OUT}" >&2
  exit 1
fi
if rg -n 'mov64 r[0-9]+, 1[0-9]{18,}' "$ASM" >/dev/null 2>&1; then
  echo "access-control-product-smoke: found decimal imm ≥ 1e18 (likely ≥2^63) in ${ASM}" >&2
  rg -n 'mov64 r[0-9]+, 1[0-9]{18,}' "$ASM" | head -5 >&2
  exit 1
fi
if ! rg -n '0x9e3779|0x9f2df0' "$ASM" >/dev/null 2>&1; then
  echo "access-control-product-smoke: expected hex hash limb imm in ${ASM}" >&2
  exit 1
fi

echo "access-control-product-smoke: ok asm=${ASM}"
