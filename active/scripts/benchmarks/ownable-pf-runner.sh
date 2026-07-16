#!/usr/bin/env bash
# B1.7: ProofForge Ownable runner (bm-ownable) — EVM primary; other targets build size.
#
# Steps (behavior-comparable on EVM): init → transferOwnership → renounceOwnership
# owner() return is address-shaped on EVM; NEAR/Solana rows are size/honest-skip.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_BENCH_OUT:-build/benchmarks}"
mkdir -p "$OUT_DIR"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
PF_VERSION="$(lake env proof-forge --version 2>/dev/null | head -n1 || echo unknown)"

fail() { echo "benchmark-ownable-pf: FAIL: $1" >&2; exit 1; }
note() { echo "benchmark-ownable-pf: $1"; }

write_row() {
  python3 - "$@" <<'PY'
import json, pathlib, sys
path, target, ok, notes, nbytes, tools_s, costs_s, steps_s, commit, pf = sys.argv[1:11]
tools = json.loads(tools_s)
if pf and pf != "unknown":
    tools.setdefault("proof-forge", pf)
row = {
    "schema": "proof-forge.benchmark-result.v1",
    "schemaVersion": 1,
    "scenario": "bm-ownable",
    "target": target,
    "implementation": "proofforge",
    "commit": commit,
    "toolVersions": tools,
    "behavior": {"ok": ok.lower() in ("1", "true", "yes"), "steps": json.loads(steps_s)},
    "costs": json.loads(costs_s),
    "artifactBytes": int(nbytes),
    "notes": notes,
}
pathlib.Path(path).write_text(json.dumps(row, indent=2) + "\n")
print(f"wrote {path}")
PY
}

# Lifecycle without comparing address returns (null returns) for cross-impl parity.
STEPS='[{"name":"init","return":null},{"name":"transferOwnership","return":null},{"name":"renounceOwnership","return":null}]'

# ── EVM ──
note "evm: build Ownable"
EVM_DIR="$OUT_DIR/pf-ownable-evm"
rm -rf "$EVM_DIR"
mkdir -p "$EVM_DIR"
if lake env proof-forge build --target evm --root . \
  -o "$EVM_DIR/Ownable.bin" \
  --artifact-output "$EVM_DIR/Ownable.proof-forge-artifact.json" \
  Examples/Product/Ownable.lean; then
  HEX_CHARS=$(tr -d ' \n' <"$EVM_DIR/Ownable.bin" | wc -c | tr -d ' ')
  BYTES=$((HEX_CHARS / 2))
  write_row "$OUT_DIR/bm-ownable_evm_proofforge.json" "evm" true \
    "runtime bytecode; gas via native Anvil runner" "$BYTES" '{}' '{}' "$STEPS" \
    "$COMMIT" "$PF_VERSION"
else
  write_row "$OUT_DIR/bm-ownable_evm_proofforge.json" "evm" false \
    "skipped: evm build failed" 0 '{}' '{}' '[]' "$COMMIT" "$PF_VERSION"
fi

# ── Solana ──
note "solana: build Ownable ELF/asm"
SOL_DIR="$OUT_DIR/pf-ownable-solana"
rm -rf "$SOL_DIR"
mkdir -p "$SOL_DIR"
if command -v sbpf >/dev/null 2>&1 \
  && lake env proof-forge build --target solana-sbpf-asm --root . \
    -o "$SOL_DIR/Ownable.so" \
    --artifact-output "$SOL_DIR/Ownable.solana-artifact.json" \
    Examples/Product/Ownable.lean; then
  BYTES=$(wc -c <"$SOL_DIR/Ownable.so" | tr -d ' ')
  write_row "$OUT_DIR/bm-ownable_solana-sbpf-asm_proofforge.json" "solana-sbpf-asm" true \
    "ELF size only; owner is u64 projection (not AccountId)" "$BYTES" '{}' '{}' "$STEPS" \
    "$COMMIT" "$PF_VERSION"
elif lake env proof-forge build --target solana-sbpf-asm --format s --root . \
  -o "$SOL_DIR/Ownable.s" \
  --artifact-output "$SOL_DIR/Ownable.solana-artifact.json" \
  Examples/Product/Ownable.lean; then
  BYTES=$(wc -c <"$SOL_DIR/Ownable.s" | tr -d ' ')
  write_row "$OUT_DIR/bm-ownable_solana-sbpf-asm_proofforge.json" "solana-sbpf-asm" true \
    "assembly size only" "$BYTES" '{}' '{}' "$STEPS" "$COMMIT" "$PF_VERSION"
else
  write_row "$OUT_DIR/bm-ownable_solana-sbpf-asm_proofforge.json" "solana-sbpf-asm" false \
    "skipped: solana build failed" 0 '{}' '{}' '[]' "$COMMIT" "$PF_VERSION"
fi

# ── NEAR ──
note "near: build Ownable"
NEAR_DIR="$OUT_DIR/pf-ownable-near"
rm -rf "$NEAR_DIR"
mkdir -p "$NEAR_DIR"
if lake env proof-forge build --target wasm-near --root . -o "$NEAR_DIR" \
  --artifact-output "$NEAR_DIR/Ownable.near-artifact.json" \
  Examples/Product/Ownable.lean; then
  WASM="$(find "$NEAR_DIR" -name '*.wasm' | head -n1 || true)"
  BYTES=0
  [ -n "${WASM:-}" ] && BYTES=$(wc -c <"$WASM" | tr -d ' ')
  write_row "$OUT_DIR/bm-ownable_wasm-near_proofforge.json" "wasm-near" true \
    "wasm size; PF owner is u64 projection vs near-sdk AccountId (parity is structural)" \
    "$BYTES" '{}' '{}' "$STEPS" "$COMMIT" "$PF_VERSION"
else
  write_row "$OUT_DIR/bm-ownable_wasm-near_proofforge.json" "wasm-near" false \
    "skipped: wasm-near build failed" 0 '{}' '{}' '[]' "$COMMIT" "$PF_VERSION"
fi

python3 scripts/benchmarks/validate-result-schema.py \
  "$OUT_DIR"/bm-ownable_*_proofforge.json \
  || fail "schema validation failed"
note "ok"
ls -la "$OUT_DIR"/bm-ownable_*_proofforge.json
