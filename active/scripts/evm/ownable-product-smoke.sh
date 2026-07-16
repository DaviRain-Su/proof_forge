#!/usr/bin/env bash
# LR-S5 / M1: portable Ownable product → EVM Yul → solc bytecode.
# No Rust product lower (D-058). Requires solc on PATH; cast optional (Lean keccak fallback).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.foundry/bin:${HOME}/.elan/bin:${HOME}/.local/bin:${PATH:-}"

OUT_DIR="${OUT_DIR:-build/evm/ownable-smoke}"
BIN_OUT="${OUT_DIR}/Ownable.bin"
YUL_OUT="${OUT_DIR}/Ownable.yul"
mkdir -p "$OUT_DIR"

if [[ -x .lake/build/bin/proof-forge ]]; then
  PF=".lake/build/bin/proof-forge"
else
  lake build proof-forge
  PF=".lake/build/bin/proof-forge"
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "ownable-product-smoke: solc not on PATH" >&2
  exit 1
fi

echo "ownable-product-smoke: build product Ownable → ${BIN_OUT}"
lake env "$PF" build --target evm --root . \
  -o "$BIN_OUT" \
  --yul-output "$YUL_OUT" \
  Examples/Product/Ownable.lean

if [[ ! -s "$BIN_OUT" ]]; then
  echo "ownable-product-smoke: missing or empty bytecode ${BIN_OUT}" >&2
  exit 1
fi

# Hex bytecode line (non-empty, mostly hex)
HEX_CHARS="$(tr -d '[:space:]' < "$BIN_OUT" | tr -d '\n')"
if [[ ${#HEX_CHARS} -lt 40 ]]; then
  echo "ownable-product-smoke: bytecode too short (${#HEX_CHARS} chars)" >&2
  exit 1
fi
if ! [[ "$HEX_CHARS" =~ ^[0-9a-fA-F]+$ ]]; then
  echo "ownable-product-smoke: bytecode is not pure hex" >&2
  exit 1
fi

if [[ -f "$YUL_OUT" ]]; then
  if ! grep -q "object" "$YUL_OUT"; then
    echo "ownable-product-smoke: yul missing object header" >&2
    exit 1
  fi
  echo "ownable-product-smoke: yul ok ${YUL_OUT}"
fi

echo "ownable-product-smoke: ok bytes=${#HEX_CHARS} bin=${BIN_OUT}"
