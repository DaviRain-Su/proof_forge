#!/usr/bin/env bash
# Token intent SDK smoke.
#
# This gate exercises both token intent entrypoints across target routing:
#   - Lean TokenSpec -> EVM ERC-20 artifact / Solana SPL Token plan.
#   - Legacy Learn token -> TokenSpec -> the same target-specific outputs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

OUT_DIR="${PROOF_FORGE_TOKEN_INTENT_OUT:-${PROOF_FORGE_LEARN_TOKEN_OUT:-build/portable/token-intent}}"
EVM_DIR="$OUT_DIR/evm"
SOLANA_DIR="$OUT_DIR/solana"

PROOF_TOKEN="Examples/Learn/ProofToken.learn"
FEE_TOKEN="Examples/Learn/FeeToken.learn"
LEAN_TOKEN="Examples/Shared/FungibleToken.lean"
LEAN_FEE_TOKEN="Examples/Shared/FeeToken.lean"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "file not written: $1"
}

require_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  grep -Fq -- "$needle" "$file" || fail "$label missing '$needle' in $file"
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"
command -v cargo >/dev/null 2>&1 || fail "cargo not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$EVM_DIR" "$SOLANA_DIR"

if command -v solc >/dev/null 2>&1; then
  echo "=== Token intent step 1: emit Lean TokenSpec to EVM ERC-20 Yul/bytecode ==="
  LEAN_EVM_YUL="$EVM_DIR/FungibleToken.erc20.yul"
  LEAN_EVM_BIN="$EVM_DIR/FungibleToken.erc20.bin"
  LEAN_EVM_ARTIFACT="$EVM_DIR/FungibleToken.erc20.artifact.json"

  lake env proof-forge build --target evm --token --root . \
    --yul-output "$LEAN_EVM_YUL" \
    --artifact-output "$LEAN_EVM_ARTIFACT" \
    -o "$LEAN_EVM_BIN" \
    "$LEAN_TOKEN" \
    || fail "proof-forge build --target evm --token failed for Lean TokenSpec"

  require_file "$LEAN_EVM_YUL"
  require_file "$LEAN_EVM_BIN"
  require_file "$LEAN_EVM_ARTIFACT"
  require_contains "$LEAN_EVM_YUL" 'object "FungibleToken"' "Lean TokenSpec ERC-20 Yul object"
  require_contains "$LEAN_EVM_YUL" "case 0x70a08231" "Lean TokenSpec ERC-20 balanceOf selector"
  require_contains "$LEAN_EVM_YUL" "case 0xa9059cbb" "Lean TokenSpec ERC-20 transfer selector"

  python3 - "$LEAN_EVM_ARTIFACT" <<'PY'
import json
import sys

artifact = json.load(open(sys.argv[1]))
assert artifact["format"] == "proof-forge-token-artifact-v0"
assert artifact["sourceKind"] == "lean-token-source"
assert artifact["target"] == "evm"
assert artifact["standard"] == "erc20"
assert artifact["artifactKind"] == "evm-erc20-contract"
assert artifact["validation"]["leanTokenLoading"] == "passed"
selectors = {entry["signature"]: entry["selector"] for entry in artifact["abi"]["entrypoints"]}
assert selectors["balanceOf(address)"] == "70a08231"
assert selectors["transfer(address,uint256)"] == "a9059cbb"
print("lean evm token artifact: ok")
PY

  echo "=== Token intent step 2: emit legacy Learn token to EVM ERC-20 Yul/bytecode ==="
  EVM_YUL="$EVM_DIR/ProofToken.erc20.yul"
  EVM_BIN="$EVM_DIR/ProofToken.erc20.bin"
  EVM_ARTIFACT="$EVM_DIR/ProofToken.erc20.artifact.json"

  lake env proof-forge build --target evm --token \
    --yul-output "$EVM_YUL" \
    --artifact-output "$EVM_ARTIFACT" \
    -o "$EVM_BIN" \
    "$PROOF_TOKEN" \
    || fail "proof-forge build --target evm --token failed"

  require_file "$EVM_YUL"
  require_file "$EVM_BIN"
  require_file "$EVM_ARTIFACT"
  require_contains "$EVM_YUL" 'object "ProofToken"' "ERC-20 Yul object"
  require_contains "$EVM_YUL" "case 0x70a08231" "ERC-20 balanceOf selector"
  require_contains "$EVM_YUL" "case 0xa9059cbb" "ERC-20 transfer selector"
  require_contains "$EVM_YUL" "case 0x095ea7b3" "ERC-20 approve selector"
  require_contains "$EVM_YUL" "case 0x23b872dd" "ERC-20 transferFrom selector"
  require_contains "$EVM_YUL" "log3(" "ERC-20 indexed event emission"

  python3 - "$EVM_ARTIFACT" <<'PY'
import json
import sys

artifact = json.load(open(sys.argv[1]))
assert artifact["format"] == "proof-forge-token-artifact-v0"
assert artifact["sourceKind"] == "learn-token-source"
assert artifact["target"] == "evm"
assert artifact["standard"] == "erc20"
assert artifact["artifactKind"] == "evm-erc20-contract"
selectors = {entry["signature"]: entry["selector"] for entry in artifact["abi"]["entrypoints"]}
assert selectors["totalSupply()"] == "18160ddd"
assert selectors["balanceOf(address)"] == "70a08231"
assert selectors["transfer(address,uint256)"] == "a9059cbb"
assert selectors["approve(address,uint256)"] == "095ea7b3"
assert selectors["allowance(address,address)"] == "dd62ed3e"
assert selectors["transferFrom(address,address,uint256)"] == "23b872dd"
assert selectors["decimals()"] == "313ce567"
assert selectors["mint(address,uint256)"] == "40c10f19"
assert selectors["burn(uint256)"] == "42966c68"
events = {event["signature"]: event["topic0"] for event in artifact["abi"]["events"]}
assert events["Transfer(address,address,uint256)"] == "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
assert events["Approval(address,address,uint256)"] == "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"
assert artifact["validation"]["solcStrictAssembly"] == "passed"
print("evm token artifact: ok")
PY
else
  echo "SKIP: solc not on PATH; EVM ERC-20 token bytecode check skipped"
fi

echo "=== Token intent step 3: emit Lean TokenSpec to Solana SPL Token plan ==="
LEAN_SOLANA_SPL_PLAN="$SOLANA_DIR/FungibleToken.solana-token-plan.json"
lake env proof-forge build --target solana-sbpf-asm --token --root . \
  -o "$LEAN_SOLANA_SPL_PLAN" \
  "$LEAN_TOKEN" \
  || fail "proof-forge build --target solana-sbpf-asm --token failed for Lean TokenSpec"

require_file "$LEAN_SOLANA_SPL_PLAN"
python3 - "$LEAN_SOLANA_SPL_PLAN" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1]))
assert plan["format"] == "proof-forge-token-plan-v0"
assert plan["sourceKind"] == "lean-token-source"
assert plan["target"] == "solana-sbpf-asm"
assert plan["standard"] == "spl-token"
assert plan["artifactKind"] == "solana-spl-token-plan"
assert plan["validation"]["leanTokenLoading"] == "passed"
assert "spl-token.transfer_checked" in plan["operations"]
print("lean solana spl-token plan: ok")
PY

echo "=== Token intent step 4: emit legacy Learn token to Solana SPL Token plan ==="
SOLANA_SPL_PLAN="$SOLANA_DIR/ProofToken.solana-token-plan.json"
lake env proof-forge build --target solana-sbpf-asm --token \
  -o "$SOLANA_SPL_PLAN" \
  "$PROOF_TOKEN" \
  || fail "proof-forge build --target solana-sbpf-asm --token failed"

require_file "$SOLANA_SPL_PLAN"
python3 - "$SOLANA_SPL_PLAN" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1]))
assert plan["format"] == "proof-forge-token-plan-v0"
assert plan["sourceKind"] == "learn-token-source"
assert plan["target"] == "solana-sbpf-asm"
assert plan["targetFamily"] == "solana"
assert plan["standard"] == "spl-token"
assert plan["artifactKind"] == "solana-spl-token-plan"
assert "spl-token.transfer_checked" in plan["operations"]
assert plan["solana"]["programs"]["token"] == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
names = [instruction["name"] for instruction in plan["solana"]["instructions"]]
for name in [
    "create_mint_account",
    "initialize_mint",
    "create_owner_ata",
    "mint_to_initial_supply",
    "mint_to",
    "transfer_checked",
    "approve_delegate",
    "burn",
    "revoke_delegate",
    "set_mint_authority",
]:
    assert name in names
assert plan["solana"]["extensions"] == []
assert plan["validation"]["planGeneration"] == "passed"
print("learn solana spl-token plan: ok")
PY

echo "=== Token intent step 5: emit Lean TokenSpec to Solana Token-2022 plan ==="
LEAN_SOLANA_TOKEN_2022_PLAN="$SOLANA_DIR/FeeToken.solana-token-plan.json"
lake env proof-forge build --target solana-sbpf-asm --token --root . \
  -o "$LEAN_SOLANA_TOKEN_2022_PLAN" \
  "$LEAN_FEE_TOKEN" \
  || fail "proof-forge build --target solana-sbpf-asm --token failed for Lean TokenSpec transfer-fee"

require_file "$LEAN_SOLANA_TOKEN_2022_PLAN"
python3 - "$LEAN_SOLANA_TOKEN_2022_PLAN" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1]))
assert plan["format"] == "proof-forge-token-plan-v0"
assert plan["sourceKind"] == "lean-token-source"
assert plan["target"] == "solana-sbpf-asm"
assert plan["targetFamily"] == "solana"
assert plan["standard"] == "spl-token-2022"
assert plan["artifactKind"] == "solana-token-2022-plan"
assert "token-2022.extension.transfer_fee" in plan["operations"]
assert plan["solana"]["programs"]["token"] == "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
extensions = [extension["extension"] for extension in plan["solana"]["extensions"]]
assert "transfer_fee_config" in extensions
names = [instruction["name"] for instruction in plan["solana"]["instructions"]]
assert "initialize_transfer_fee_config" in names
assert names.index("initialize_transfer_fee_config") < names.index("initialize_mint")
for name in [
    "transfer_checked_with_fee",
    "withdraw_withheld_tokens_from_accounts",
    "harvest_withheld_tokens_to_mint",
    "withdraw_withheld_tokens_from_mint",
]:
    assert name in names
assert plan["validation"]["leanTokenLoading"] == "passed"
assert plan["validation"]["planGeneration"] == "passed"
print("lean solana token-2022 plan: ok")
PY

echo "=== Token intent step 6: emit legacy Learn token to Solana Token-2022 plan ==="
SOLANA_TOKEN_2022_PLAN="$SOLANA_DIR/FeeToken.legacy.solana-token-plan.json"
lake env proof-forge build --target solana-sbpf-asm --token \
  -o "$SOLANA_TOKEN_2022_PLAN" \
  "$FEE_TOKEN" \
  || fail "proof-forge build --target solana-sbpf-asm --token failed"

require_file "$SOLANA_TOKEN_2022_PLAN"
python3 - "$SOLANA_TOKEN_2022_PLAN" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1]))
assert plan["format"] == "proof-forge-token-plan-v0"
assert plan["sourceKind"] == "learn-token-source"
assert plan["target"] == "solana-sbpf-asm"
assert plan["targetFamily"] == "solana"
assert plan["standard"] == "spl-token-2022"
assert plan["artifactKind"] == "solana-token-2022-plan"
assert "token-2022.extension.transfer_fee" in plan["operations"]
assert plan["solana"]["programs"]["token"] == "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
extensions = [extension["extension"] for extension in plan["solana"]["extensions"]]
assert "transfer_fee_config" in extensions
names = [instruction["name"] for instruction in plan["solana"]["instructions"]]
assert "initialize_transfer_fee_config" in names
assert names.index("initialize_transfer_fee_config") < names.index("initialize_mint")
for name in [
    "transfer_checked_with_fee",
    "withdraw_withheld_tokens_from_accounts",
    "harvest_withheld_tokens_to_mint",
    "withdraw_withheld_tokens_from_mint",
]:
    assert name in names
assert plan["validation"]["planGeneration"] == "passed"
print("learn solana token-2022 plan: ok")
PY

echo "=== Token intent step 7: validate Solana token plans with Rust harness ==="
cargo run --manifest-path testkit/harness-solana/Cargo.toml \
  --bin token_plan_smoke -- "$LEAN_SOLANA_SPL_PLAN" \
  || fail "Lean Solana SPL Token plan Rust validation failed"
cargo run --manifest-path testkit/harness-solana/Cargo.toml \
  --bin token_plan_smoke -- "$SOLANA_SPL_PLAN" \
  || fail "Solana SPL Token plan Rust validation failed"
cargo run --manifest-path testkit/harness-solana/Cargo.toml \
  --bin token_plan_smoke -- "$LEAN_SOLANA_TOKEN_2022_PLAN" \
  || fail "Lean Solana Token-2022 plan Rust validation failed"
cargo run --manifest-path testkit/harness-solana/Cargo.toml \
  --bin token_plan_smoke -- "$SOLANA_TOKEN_2022_PLAN" \
  || fail "Solana Token-2022 plan Rust validation failed"

echo "token-intent-smoke: PASS"
