#!/usr/bin/env bash
# Portable ValueVault contract_source smoke.
#
# This gate exercises one chain-neutral Lean contract_source file across the
# primary target backends:
#   - EVM: contract_source -> ContractSpec IR -> ABI-selector hydration -> Yul/bytecode, when solc and Foundry cast exist.
#   - Solana: contract_source -> ContractSpec -> target-routed sBPF assembly, manifest, IDL, TS client, metadata.
#   - NEAR: contract_source -> ContractSpec -> target-routed EmitWat, deploy manifest, metadata.
#   - Solana ELF: optional, set PROOF_FORGE_VALUE_VAULT_ELF=1 when sbpf exists.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

export PATH="$HOME/.foundry/bin:$PATH"

OUT_DIR="${PROOF_FORGE_VALUE_VAULT_OUT:-build/portable/value-vault}"
EVM_DIR="$OUT_DIR/evm"
SOLANA_DIR="$OUT_DIR/solana"
NEAR_DIR="$OUT_DIR/near"
SOURCE="${PROOF_FORGE_VALUE_VAULT_SOURCE:-Examples/Product/ValueVault.lean}"

EVM_YUL="$EVM_DIR/ValueVault.yul"
EVM_BIN="$EVM_DIR/ValueVault.bin"
EVM_ARTIFACT="$EVM_DIR/ValueVault.proof-forge-artifact.json"

SOLANA_ASM="$SOLANA_DIR/ValueVault.s"
SOLANA_MANIFEST="$SOLANA_DIR/manifest.toml"
SOLANA_IDL="$SOLANA_DIR/proof-forge-idl.json"
SOLANA_CLIENT="$SOLANA_DIR/proof-forge-client.ts"
SOLANA_ARTIFACT="$SOLANA_DIR/ValueVault.proof-forge-artifact.json"
SOLANA_ELF="$SOLANA_DIR/ValueVault.so"

NEAR_ARTIFACT="$OUT_DIR/ValueVault.near-artifact.json"
NEAR_WAT="$NEAR_DIR/valuevault.wat"

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

rm -rf "$OUT_DIR"
mkdir -p "$EVM_DIR" "$SOLANA_DIR" "$NEAR_DIR"

if command -v solc >/dev/null 2>&1 && command -v cast >/dev/null 2>&1; then
  echo "=== Portable ValueVault step 1: emit EVM bytecode, Yul, and metadata ==="
  lake env proof-forge build --target evm --root . \
    --yul-output "$EVM_YUL" \
    --artifact-output "$EVM_ARTIFACT" \
    -o "$EVM_BIN" \
    "$SOURCE" \
    || fail "proof-forge build --target evm failed"
  require_file "$EVM_YUL"
  require_file "$EVM_BIN"
  require_file "$EVM_ARTIFACT"
  require_contains "$EVM_YUL" 'object "ValueVault"' "EVM Yul object"
  require_contains "$EVM_YUL" "function f_ValueVault_deposit" "EVM Yul deposit function"
  require_contains "$EVM_YUL" "function f_ValueVault_snapshot" "EVM Yul snapshot function"
  require_contains "$EVM_YUL" "log1" "EVM event lowering"
  require_contains "$EVM_YUL" "number()" "EVM checkpoint lowering"

  solc --strict-assembly "$EVM_YUL" --bin >/dev/null \
    || fail "solc --strict-assembly rejected ValueVault Yul"
  python3 "$REPO_ROOT/scripts/evm/validate-artifact-metadata.py" \
    --root "$REPO_ROOT" \
    --expect-fixture ValueVault \
    --expect-source-kind contract-sdk \
    --expect-capability storage.scalar \
    --expect-capability events.emit \
    --expect-capability env.block \
    --expect-entrypoint initialize:fe4b84df \
    --expect-entrypoint deposit:b6b55f25 \
    --expect-entrypoint charge_fee:be168a46 \
    --expect-entrypoint release:37bdc99b \
    --expect-entrypoint snapshot:9711715a \
    --expect-entrypoint get_balance:c1cfb99a \
    --expect-entrypoint get_net_value:d43f79a2 \
    --expect-entrypoint-abi 'initialize:initialize(uint256):1:0' \
    --expect-entrypoint-abi 'deposit:deposit(uint256):1:0' \
    --expect-entrypoint-abi 'charge_fee:charge_fee(uint256,uint256):2:0' \
    --expect-entrypoint-abi 'snapshot:snapshot():0:1' \
    --expect-event 'ValueDeposited:ValueDeposited(uint64,uint64,uint64)' \
    --expect-event 'ValueSnapshot:ValueSnapshot(uint64,uint64,uint64,uint64)' \
    "$EVM_ARTIFACT"
else
  echo "SKIP: solc and cast are required together for EVM bytecode/Yul metadata; EVM branch skipped"
fi

echo "=== Portable ValueVault step 2: emit Solana sBPF assembly ==="
lake env proof-forge build --target solana-sbpf-asm --format s \
  --root . \
  -o "$SOLANA_ASM" \
  --artifact-output "$SOLANA_ARTIFACT" \
  "$SOURCE" \
  || fail "proof-forge build --target solana-sbpf-asm --format s failed"
require_file "$SOLANA_ASM"
require_file "$SOLANA_MANIFEST"
require_file "$SOLANA_IDL"
require_file "$SOLANA_CLIENT"
require_file "$SOLANA_ARTIFACT"
require_contains "$SOLANA_ASM" "solana.event.emit ValueDeposited" "Solana event lowering"
require_contains "$SOLANA_ASM" "solana.event.emit ValueSnapshot" "Solana snapshot event lowering"
require_contains "$SOLANA_ASM" "call sol_log_64_" "Solana event syscall"
require_contains "$SOLANA_ASM" "call sol_get_clock_sysvar" "Solana clock sysvar syscall"
require_contains "$SOLANA_MANIFEST" 'name = "deposit"' "Solana manifest deposit instruction"
require_contains "$SOLANA_MANIFEST" 'name = "charge_fee"' "Solana manifest charge_fee instruction"
require_contains "$SOLANA_MANIFEST" 'name = "snapshot"' "Solana manifest snapshot instruction"

echo "=== Portable ValueVault step 3: validate Solana artifact metadata ==="
python3 - "$REPO_ROOT" "$SOLANA_ARTIFACT" "$SOLANA_ASM" "$SOLANA_MANIFEST" "$SOLANA_IDL" "$SOLANA_CLIENT" "$SOURCE" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
artifact_path = pathlib.Path(sys.argv[2])
asm_path = pathlib.Path(sys.argv[3])
manifest_path = pathlib.Path(sys.argv[4])
idl_path = pathlib.Path(sys.argv[5])
client_path = pathlib.Path(sys.argv[6])
source_path = pathlib.Path(sys.argv[7])
artifact = json.loads(artifact_path.read_text())
idl = json.loads(idl_path.read_text())
client = client_path.read_text()

def fail(message: str) -> None:
    raise SystemExit(message)

def resolve(path_text: str) -> pathlib.Path:
    path = pathlib.Path(path_text)
    return path if path.is_absolute() else root / path

def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)

require(artifact.get("schemaVersion") == 1, "schemaVersion mismatch")
require(artifact.get("target") == "solana-sbpf-asm", "target mismatch")
require(artifact.get("targetFamily") == "solana", "targetFamily mismatch")
# Assembly intermediate (--format s): honest kind is solana-sbpf-asm, not solana-elf (PF-P0-03).
require(artifact.get("artifactKind") == "solana-sbpf-asm", "artifactKind mismatch")
require(artifact.get("fixture") == "ValueVault", "fixture mismatch")
require(artifact.get("sourceKind") == "contract-sdk", "sourceKind mismatch")
require(artifact.get("sourceModule") == "ValueVault", "sourceModule mismatch")
validation = artifact.get("validation") or {}
require(validation.get("sbpfBuild") in ("skipped", "notRun"), "assembly path must not claim sbpfBuild passed")

caps = set(artifact.get("capabilities", []))
for cap in ["storage.scalar", "events.emit", "env.block"]:
    require(cap in caps, f"missing capability {cap}")

plan = artifact.get("capabilityPlan", {})
require(plan.get("targetId") == "solana-sbpf-asm", "capabilityPlan targetId mismatch")
require(set(plan.get("capabilities", [])) >= {"storage.scalar", "events.emit", "env.block"},
        "capabilityPlan capabilities mismatch")

artifacts = artifact.get("artifacts", {})
for name, expected_path in [
    ("source", source_path),
    ("sbpfAsm", asm_path),
    ("manifestToml", manifest_path),
    ("solanaIdl", idl_path),
    ("solanaClientTs", client_path),
]:
    entry = artifacts.get(name)
    require(isinstance(entry, dict), f"missing artifact entry {name}")
    actual_path = resolve(entry.get("path", ""))
    require(actual_path.resolve() == expected_path.resolve(), f"{name} path mismatch")
    data = actual_path.read_bytes()
    require(entry.get("bytes") == len(data), f"{name} bytes mismatch")
    require(entry.get("sha256") == hashlib.sha256(data).hexdigest(), f"{name} sha256 mismatch")

instructions = artifact.get("solanaInstructions", [])
require(artifact.get("solanaIdl") == idl, "artifact solanaIdl does not match IDL file")
require(idl.get("schema") == "proof-forge.solana.idl.v0", "IDL schema mismatch")
require(idl.get("name") == "ValueVault", "IDL program name mismatch")
require(idl.get("target") == "solana-sbpf-asm", "IDL target mismatch")
for needle in ["export const IDL = ", "encodeInstructionData", "accountMetas", "createInstruction"]:
    require(needle in client, f"client missing {needle}")
idl_instructions = idl.get("instructions", [])
require([instruction.get("name") for instruction in idl_instructions] == [
    "initialize",
    "deposit",
    "charge_fee",
    "release",
    "snapshot",
    "get_balance",
    "get_net_value",
], "IDL instruction order mismatch")
names = [instruction.get("name") for instruction in instructions]
expected_names = [
    "initialize",
    "deposit",
    "charge_fee",
    "release",
    "snapshot",
    "get_balance",
    "get_net_value",
]
require(names == expected_names, f"instruction order mismatch: {names}")
by_name = {instruction["name"]: instruction for instruction in instructions}

def param_shape(instruction: str):
    return [
        (param.get("name"), param.get("type"), param.get("offset"),
         param.get("byteSize"), param.get("encoding"))
        for param in by_name[instruction].get("params", [])
    ]

require(param_shape("deposit") == [("amount", "U64", 1, 8, "le-u64")],
        "deposit params mismatch")
require(param_shape("charge_fee") == [
    ("gross", "U64", 1, 8, "le-u64"),
    ("fee_bps", "U64", 9, 8, "le-u64"),
], "charge_fee params mismatch")
require(by_name["snapshot"].get("params") == [], "snapshot should have no params")
require(by_name["charge_fee"].get("minDataLen") == 17, "charge_fee minDataLen mismatch")
require(artifact.get("solanaExtensions", {}).get("allocators") == [],
        "portable ValueVault should not require Solana-only allocators")
PY

echo "=== Portable ValueVault step 4: emit NEAR/Wasm WAT ==="
lake env proof-forge build --target wasm-near \
  --root . \
  -o "$NEAR_DIR" \
  --artifact-output "$NEAR_ARTIFACT" \
  "$SOURCE" \
  || fail "proof-forge build --target wasm-near failed"
require_file "$NEAR_WAT"
require_file "$NEAR_ARTIFACT"
diff -u Examples/Backend/WasmNear/ValueVault.golden.wat "$NEAR_WAT" \
  || fail "NEAR ValueVault WAT golden mismatch"
python3 scripts/near/validate-emitwat-metadata.py \
  "$NEAR_ARTIFACT" \
  --expected-fixture valuevault \
  --expected-module ValueVault \
  --expected-entrypoints initialize,deposit,charge_fee,release,snapshot,get_balance,get_net_value \
  --expected-source-kind contract-sdk

if [ "${PROOF_FORGE_VALUE_VAULT_ELF:-0}" = "1" ]; then
  command -v sbpf >/dev/null 2>&1 || fail "PROOF_FORGE_VALUE_VAULT_ELF=1 requires sbpf on PATH"
  echo "=== Portable ValueVault step 5: build Solana ELF ==="
  lake env proof-forge emit --target solana-sbpf-asm --fixture value-vault --format elf \
    -o "$SOLANA_ELF" \
    --artifact-output "$SOLANA_DIR/ValueVault.elf.proof-forge-artifact.json" \
    || fail "proof-forge emit --target solana-sbpf-asm --fixture value-vault --format elf failed"
  require_file "$SOLANA_ELF"
else
  echo "SKIP: set PROOF_FORGE_VALUE_VAULT_ELF=1 to build the optional Solana ELF"
fi

echo ""
echo "portable-value-vault-smoke: PASS"
