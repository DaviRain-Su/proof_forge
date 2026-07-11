#!/usr/bin/env bash
# ProofForge Solana SPL Token ops Pinocchio reference-equivalence smoke.
#
# Emits the ProofForge SPL Token mint_to/burn/approve/revoke CPI source fixture
# and compares its artifact ABI/CPI contract against the checked-in Pinocchio
# reference manifest and source constants. Optional Cargo checking is gated by
# PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1 to keep the default gate offline.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${PROOF_FORGE_PINOCCHIO_SPL_TOKEN_OPS_OUT:-build/solana-pinocchio-spl-token-ops-equivalence}"
REFERENCE_DIR="$REPO_ROOT/references/solana/pinocchio/spl-token-ops"
REFERENCE_MANIFEST="$REFERENCE_DIR/reference-manifest.json"
REFERENCE_SOURCE="$REFERENCE_DIR/src/lib.rs"
ARTIFACT_OUTPUT="$OUT_DIR/proof-forge-artifact.json"
ASM_OUTPUT="$OUT_DIR/proofforge-spl-token-ops-reference.s"

fail() { echo "FAIL: $1" >&2; exit 1; }
skip() { echo "SKIP: $1" >&2; exit 2; }

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"
[ -f "$REFERENCE_MANIFEST" ] || fail "reference manifest missing: $REFERENCE_MANIFEST"
[ -f "$REFERENCE_SOURCE" ] || fail "reference source missing: $REFERENCE_SOURCE"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "=== Pinocchio SPL Token ops equivalence step 1: emit ProofForge source fixture ==="
lake env proof-forge emit --target solana-sbpf-asm --fixture spl-token-ops-cpi --format s \
  -o "$ASM_OUTPUT" \
  --artifact-output "$ARTIFACT_OUTPUT" \
  || fail "proof-forge emit --target solana-sbpf-asm --fixture spl-token-ops-cpi --format s failed"
[ -f "$ARTIFACT_OUTPUT" ] || fail "artifact not produced: $ARTIFACT_OUTPUT"

echo "=== Pinocchio SPL Token ops equivalence step 2: compare contracts ==="
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
cpi_by_name = {cpi["name"]: cpi for cpi in reference["cpis"]}
action_by_entrypoint = {
    action["entrypoint"]: action["cpi"] for action in reference["cpiActions"]
}
account_by_name = {account["name"]: account for account in reference_accounts}
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
    cpi = cpi_by_name[action_by_entrypoint[ref_entry["name"]]]
    expected_names = [reference_accounts[0]["name"]]
    expected_names.extend(cpi["accounts"])
    if cpi["program"] not in expected_names:
        expected_names.append(cpi["program"])
    expected_accounts = [account_by_name[name] for name in expected_names]
    require([a.get("name") for a in artifact_accounts] == expected_names,
            f"account order mismatch for {ref_entry['name']}: {artifact_accounts}")
    for index, (got, expected) in enumerate(zip(artifact_accounts, expected_accounts)):
        require(got.get("index") == index,
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
    for key in ("name", "program", "protocol", "instruction", "dataLayout", "amountSource", "signed"):
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

expected_constants = {
    "PF_MINT_ENTRYPOINT_TAG": reference_entrypoints[0]["tag"],
    "PF_BURN_ENTRYPOINT_TAG": reference_entrypoints[1]["tag"],
    "PF_APPROVE_ENTRYPOINT_TAG": reference_entrypoints[2]["tag"],
    "PF_REVOKE_ENTRYPOINT_TAG": reference_entrypoints[3]["tag"],
    "PF_AMOUNT_MIN_INSTRUCTION_DATA_LEN": reference_entrypoints[0]["minDataLen"],
    "PF_REVOKE_MIN_INSTRUCTION_DATA_LEN": reference_entrypoints[3]["minDataLen"],
    "PF_AMOUNT_OFFSET": reference_entrypoints[0]["params"][0]["offset"],
    "PF_AMOUNT_SIZE": reference_entrypoints[0]["params"][0]["byteSize"],
    "PF_ACCOUNT_COUNT": len(reference_accounts),
    "PF_STATE_ACCOUNT_INDEX": 0,
    "PF_MINT_ACCOUNT_INDEX": 1,
    "PF_DESTINATION_ACCOUNT_INDEX": 2,
    "PF_AUTHORITY_ACCOUNT_INDEX": 3,
    "PF_SPL_TOKEN_ACCOUNT_INDEX": 4,
    "PF_SOURCE_ACCOUNT_INDEX": 5,
    "PF_DELEGATE_ACCOUNT_INDEX": 6,
    "PF_TOKEN_MINT_TO_DISCRIMINATOR": 7,
    "PF_TOKEN_BURN_DISCRIMINATOR": 8,
    "PF_TOKEN_APPROVE_DISCRIMINATOR": 4,
    "PF_TOKEN_REVOKE_DISCRIMINATOR": 5,
    "PF_TOKEN_AMOUNT_DATA_LEN": 9,
    "PF_TOKEN_REVOKE_DATA_LEN": 1,
    "PF_STATE_MINT_WRITE_OFFSET": reference["stateWrites"][0]["offset"],
    "PF_STATE_BURN_WRITE_OFFSET": reference["stateWrites"][1]["offset"],
    "PF_STATE_APPROVE_WRITE_OFFSET": reference["stateWrites"][2]["offset"],
    "PF_STATE_REVOKE_WRITE_OFFSET": reference["stateWrites"][3]["offset"],
    "PF_STATE_WRITE_SIZE": reference["stateWrites"][0]["byteSize"],
    "PF_REVOKE_STATE_MARKER": 1,
}
for name, expected in expected_constants.items():
    require(constants.get(name) == expected,
            f"source constant {name} mismatch: got {constants.get(name)} expected {expected}")

source_markers = [
    "pinocchio_token::instructions::{Approve, Burn, MintTo, Revoke}",
    "pinocchio_token::check_id",
    "MintTo::new(mint, destination, authority, amount)",
    "Burn::new(source, mint, authority, amount)",
    "Approve::new(source, delegate, authority, amount)",
    "Revoke::new(source, authority)",
    "write_state_u64(state, PF_STATE_MINT_WRITE_OFFSET, amount)",
    "write_state_u64(state, PF_STATE_BURN_WRITE_OFFSET, amount)",
    "write_state_u64(state, PF_STATE_APPROVE_WRITE_OFFSET, amount)",
    "write_state_u64(state, PF_STATE_REVOKE_WRITE_OFFSET, PF_REVOKE_STATE_MARKER)",
]
for marker in source_markers:
    require(marker in source, f"reference source missing marker: {marker}")

print("reference equivalence contract: ok")
PY

if [ "${PROOF_FORGE_PINOCCHIO_CARGO_CHECK:-0}" = "1" ]; then
  command -v cargo >/dev/null 2>&1 || fail "cargo not on PATH"
  echo "=== Pinocchio SPL Token ops equivalence step 3: optional cargo check ==="
  cargo check --manifest-path "$REFERENCE_DIR/Cargo.toml" --no-default-features --features bpf-entrypoint \
    || fail "Pinocchio reference cargo check failed"
fi

echo "=== Pinocchio SPL Token ops reference-equivalence smoke: PASS ==="
