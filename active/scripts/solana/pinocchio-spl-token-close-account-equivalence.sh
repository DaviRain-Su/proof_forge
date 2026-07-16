#!/usr/bin/env bash
# ProofForge Solana SPL Token close_account Pinocchio reference-equivalence smoke.
#
# Emits the ProofForge SPL Token close_account CPI source fixture and compares
# its artifact ABI/CPI contract against the checked-in Pinocchio reference
# manifest and source constants. Optional Cargo checking is gated by
# PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1 to keep the default gate offline.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_PINOCCHIO_SPL_TOKEN_CLOSE_ACCOUNT_OUT:-build/solana-pinocchio-spl-token-close-account-equivalence}"
REFERENCE_DIR="$REPO_ROOT/references/solana/pinocchio/spl-token-close-account"
REFERENCE_MANIFEST="$REFERENCE_DIR/reference-manifest.json"
REFERENCE_SOURCE="$REFERENCE_DIR/src/lib.rs"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
ASM_OUTPUT="$OUT_DIR/proofforge-spl-token-close-account-reference.s"

fail() { echo "FAIL: $1" >&2; exit 1; }
skip() { echo "SKIP: $1" >&2; exit 2; }

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"
[ -f "$REFERENCE_MANIFEST" ] || fail "reference manifest missing: $REFERENCE_MANIFEST"
[ -f "$REFERENCE_SOURCE" ] || fail "reference source missing: $REFERENCE_SOURCE"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "=== Pinocchio SPL Token close_account equivalence step 1: emit ProofForge source fixture ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture spl-token-close-account-cpi --format s \
  -o "$ASM_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture spl-token-close-account-cpi --format s failed"
[ -f "$ARTIFACT_OUTPUT" ] || fail "artifact not produced: $ARTIFACT_OUTPUT"

echo "=== Pinocchio SPL Token close_account equivalence step 2: compare contracts ==="
python3 - "$ARTIFACT_OUTPUT" "$REFERENCE_MANIFEST" "$REFERENCE_SOURCE" <<'PY'
import json
import pathlib
import re
import sys

artifact_path = pathlib.Path(sys.argv[1])
reference_path = pathlib.Path(sys.argv[2])
source_path = pathlib.Path(sys.argv[3])

artifact = json.loads(artifact_path.read_text())
reference = json.loads(reference_path.read_text())
source = source_path.read_text()
expected_fixture = reference.get("proofForgeSourceFixture", reference["proofForgeFixture"])

def require(condition, message):
    if not condition:
        raise SystemExit(message)

require(artifact.get("fixture") == expected_fixture,
        f"fixture mismatch: {artifact.get('fixture')}")

instructions = artifact.get("solanaInstructions", [])
reference_entrypoints = reference["entrypoints"]
require(len(instructions) == len(reference_entrypoints),
        f"entrypoint count mismatch: {len(instructions)}")
reference_accounts = reference["accounts"]
for instruction, ref_entry in zip(instructions, reference_entrypoints):
    require(instruction.get("name") == ref_entry["name"],
            f"entrypoint name mismatch: {instruction.get('name')}")
    require(instruction.get("tag") == ref_entry["tag"],
            f"entrypoint tag mismatch: {instruction.get('tag')}")
    require(instruction.get("minDataLen") == ref_entry["minDataLen"],
            f"minDataLen mismatch: {instruction.get('minDataLen')}")
    require(instruction.get("params", []) == ref_entry["params"],
            f"params mismatch for {ref_entry['name']}: {instruction.get('params')}")
    artifact_accounts = instruction.get("accounts", [])
    require([a.get("name") for a in artifact_accounts] == [a["name"] for a in reference_accounts],
            f"account order mismatch for {ref_entry['name']}: {artifact_accounts}")
    for got, expected in zip(artifact_accounts, reference_accounts):
        require(got.get("index") == expected["index"],
                f"account {expected['name']} index mismatch: {got}")
        require(got.get("signer") == expected["signer"],
                f"account {expected['name']} signer mismatch: {got}")
        require(got.get("writable") == expected["writable"],
                f"account {expected['name']} writable mismatch: {got}")
        require(got.get("owner") == expected["owner"],
                f"account {expected['name']} owner mismatch: {got}")

cpis = artifact.get("solanaExtensions", {}).get("cpis", [])
ref_cpis = reference["cpis"]
require([cpi.get("name") for cpi in cpis] == [cpi["name"] for cpi in ref_cpis],
        f"CPI order mismatch: {cpis}")
for cpi, ref_cpi in zip(cpis, ref_cpis):
    for key in ("name", "program", "protocol", "instruction", "dataLayout", "signed"):
        require(cpi.get(key) == ref_cpi[key], f"CPI {ref_cpi['name']} {key} mismatch: {cpi}")
    require([account.get("name") for account in cpi.get("accounts", [])] == ref_cpi["accounts"],
            f"CPI account order mismatch: {cpi.get('accounts')}")
    require([account.get("access") for account in cpi.get("accounts", [])] == ref_cpi["access"],
            f"CPI access mismatch: {cpi.get('accounts')}")
    require([account.get("signer") for account in cpi.get("accounts", [])] == ref_cpi["signers"],
            f"CPI signer mismatch: {cpi.get('accounts')}")

cpi_actions = artifact.get("solanaExtensions", {}).get("cpiActions", [])
require(cpi_actions == reference["cpiActions"], f"CPI action mismatch: {cpi_actions}")

constants = {}
for match in re.finditer(r"pub const (PF_[A-Z0-9_]+): [^=]+ = ([0-9]+);", source):
    constants[match.group(1)] = int(match.group(2))

instruction_data = reference["instructionData"]
expected_constants = {
    "PF_ENTRYPOINT_TAG": reference_entrypoints[0]["tag"],
    "PF_MIN_INSTRUCTION_DATA_LEN": reference_entrypoints[0]["minDataLen"],
    "PF_ACCOUNT_COUNT": len(reference_accounts),
    "PF_STATE_ACCOUNT_INDEX": 0,
    "PF_TOKEN_ACCOUNT_INDEX": 1,
    "PF_DESTINATION_ACCOUNT_INDEX": 2,
    "PF_AUTHORITY_ACCOUNT_INDEX": 3,
    "PF_SPL_TOKEN_ACCOUNT_INDEX": 4,
    "PF_TOKEN_CLOSE_ACCOUNT_DISCRIMINATOR": instruction_data["discriminator"],
    "PF_TOKEN_CLOSE_ACCOUNT_DATA_LEN": instruction_data["dataLen"],
    "PF_STATE_WRITE_OFFSET": reference["stateWrites"][0]["offset"],
    "PF_STATE_WRITE_SIZE": reference["stateWrites"][0]["byteSize"],
    "PF_STATE_MARKER": reference["stateWrites"][0]["value"],
}
for name, expected in expected_constants.items():
    require(constants.get(name) == expected,
            f"source constant {name} mismatch: got {constants.get(name)} expected {expected}")

source_markers = [
    "pinocchio_token::instructions::CloseAccount",
    "pinocchio_token::check_id",
    "CloseAccount::new(",
    "copy_from_slice(&PF_STATE_MARKER.to_le_bytes())",
]
for marker in source_markers:
    require(marker in source, f"reference source missing marker: {marker}")

print("reference equivalence contract: ok")
PY

if [ "${PROOF_FORGE_PINOCCHIO_CARGO_CHECK:-0}" = "1" ]; then
  command -v cargo >/dev/null 2>&1 || fail "cargo not on PATH"
  echo "=== Pinocchio SPL Token close_account equivalence step 3: optional cargo check ==="
  cargo check --manifest-path "$REFERENCE_DIR/Cargo.toml" --no-default-features --features bpf-entrypoint \
    || fail "Pinocchio reference cargo check failed"
fi

echo "=== Pinocchio SPL Token close_account reference-equivalence smoke: PASS ==="
