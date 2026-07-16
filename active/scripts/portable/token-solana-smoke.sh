#!/usr/bin/env bash
# Wave β deepen: Product TokenSpec → Solana SPL token **plan** one-command path.
#
# "Done" for product teaching: plan JSON with transfer_checked / mint_to ops.
# Live Surfpool execution remains `just solana-token-plan-live` (extra tools).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
export PATH="$HOME/.elan/bin:$HOME/.local/bin:$PATH"

OUT_DIR="${PROOF_FORGE_TOKEN_SOLANA_OUT:-build/portable/token-solana}"
LEAN_TOKEN="Examples/Product/FungibleToken.lean"
PLAN_JSON="$OUT_DIR/FungibleToken.solana-spl-token-plan.json"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "file not written: $1"
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "=== product-token-solana: TokenSpec → solana-sbpf-asm SPL plan ==="
lake env proof-forge build --target solana-sbpf-asm --token --root . \
  -o "$PLAN_JSON" \
  "$LEAN_TOKEN" \
  || fail "proof-forge build --target solana-sbpf-asm --token failed for Product FungibleToken"

require_file "$PLAN_JSON"
python3 - "$PLAN_JSON" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1]))
assert plan["format"] == "proof-forge-token-plan-v0"
assert plan["sourceKind"] == "lean-token-source"
assert plan["target"] == "solana-sbpf-asm"
assert plan["standard"] == "spl-token"
assert plan["artifactKind"] == "solana-spl-token-plan"
ops = plan.get("operations") or []
assert "spl-token.transfer_checked" in ops, f"missing transfer_checked in {ops}"
assert "spl-token.mint_to" in ops or any("mint" in o for o in ops), f"missing mint op in {ops}"
sol = plan.get("solana") or {}
progs = sol.get("programs") or {}
assert progs.get("token") == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
names = [ix["name"] for ix in sol.get("instructions") or []]
for name in ["transfer_checked", "mint_to", "initialize_mint"]:
    assert name in names, f"missing instruction {name} in {names}"
print("solana spl-token plan: ok")
PY

echo "product-token-solana: ok (SPL plan · transfer_checked · mint_to)"
