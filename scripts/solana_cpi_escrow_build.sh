#!/usr/bin/env bash
# #124 production-code-generated, test-preactivation composite escrow CPI build.
#
# Loader → product compile → private preflight Plan → Escrow IR → Escrow
# emitter → locked sbpf 0.2.2. Runtime dependencies are committed classic ATA
# and Token ELFs only (byte-verified). Native System is runtime-native (never
# copied). Catalog ATA/Token artifactBinding remains absent / admitted=false.
# Never mints proof-forge.output.v1. Does not activate product sync.
#
# PROOF_FORGE_CPI_ESCROW_MEASURE=1: generate + print measured assembly/ELF/
# calls sizes+SHA without requiring expectedAssembly/Elf/call pin match
# (phase-1 pin discovery only; never invents hashes). MEASURE never deletes,
# replaces, or publishes $PROOF_FORGE_CPI_ESCROW_OUT — only temporary stage
# under build/ is used, then discarded by the EXIT trap.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_path="$root/runtime-tests/solana/fixtures/EscrowCpi.lean"
manifest_path="$root/runtime-tests/solana/escrow/manifest.json"
ata_elf_path="$root/runtime-tests/solana/ata/ata_classic_v1.so"
token_elf_path="$root/runtime-tests/solana/token/token_classic_v1.so"
ata_manifest_path="$root/runtime-tests/solana/ata/manifest.json"
token_manifest_path="$root/runtime-tests/solana/token/manifest.json"
catalog_path="$root/docs/specs/solana-cpi-callee-catalog-v1.json"
rs_path="$root/runtime-tests/solana/tests/cpi_escrow.rs"
exporter_path="$root/Tests/Materialization/SolanaCpiEscrowExportV1.lean"
out_dir="${PROOF_FORGE_CPI_ESCROW_OUT:-$root/build/v2/solana-cpi-escrow}"
stem="escrow_cpi"
measure_mode="${PROOF_FORGE_CPI_ESCROW_MEASURE:-0}"

die() {
  echo "solana-cpi-escrow-build: $*" >&2
  exit 1
}

missing() {
  echo "solana-cpi-escrow-build: $*" >&2
  exit 2
}

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) missing "unsupported host platform: $(uname -s)" ;;
esac

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
sbpf_bin="$PROOF_FORGE_TOOL_ROOT/sbpf"
[[ -x "$sbpf_bin" ]] || missing "sbpf not found at $sbpf_bin"
sbpf_version="$($sbpf_bin --version 2>&1)" || missing "sbpf version probe failed"
[[ "$sbpf_version" == "sbpf 0.2.2" ]] || missing "expected sbpf 0.2.2, got: $sbpf_version"
command -v lake >/dev/null 2>&1 || missing "lake not on PATH"

if [[ -x /usr/bin/python3 ]]; then
  python_bin=/usr/bin/python3
elif command -v python3 >/dev/null 2>&1; then
  python_bin="$(command -v python3)"
else
  missing "python3 not found"
fi

for input in "$source_path" "$manifest_path" "$ata_elf_path" "$token_elf_path" \
  "$ata_manifest_path" "$token_manifest_path" "$catalog_path" "$rs_path"; do
  [[ -f "$input" && ! -L "$input" ]] || die "missing regular non-symlink input $input"
done
for input in "$exporter_path" \
  "$root/ProofForgeV2/Targets/Solana/CpiEscrowIRV1.lean" \
  "$root/ProofForgeV2/Targets/Solana/EmitCpiEscrowSbpfV1.lean"; do
  [[ -f "$input" && ! -L "$input" ]] || missing "missing Escrow authority input $input"
done
grep -q 'resolveSolanaCpiEscrowIRV1' "$root/ProofForgeV2/Targets/Solana/CpiEscrowIRV1.lean" \
  || missing "CpiEscrowIRV1 lacks sole mint"
grep -q 'emitCpiEscrowSbpfV1' "$root/ProofForgeV2/Targets/Solana/EmitCpiEscrowSbpfV1.lean" \
  || missing "EmitCpiEscrowSbpfV1 lacks sole emitter"
grep -q 'sol_invoke_signed_c' "$root/ProofForgeV2/Targets/Solana/EmitCpiEscrowSbpfV1.lean" \
  || missing "Escrow emitter lacks real CPI syscall"

out_dir="$($python_bin -I -S - "$root" "$out_dir" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1]).resolve(strict=True)
build = (root / "build").resolve(strict=False)
candidate = Path(sys.argv[2])
if not candidate.is_absolute():
    candidate = root / candidate
candidate = candidate.resolve(strict=False)
try:
    relative = candidate.relative_to(build)
except ValueError:
    raise SystemExit(f"PROOF_FORGE_CPI_ESCROW_OUT must be under {build}")
if not relative.parts:
    raise SystemExit("refusing to replace build root")
print(candidate)
PY
)" || die "unsafe PROOF_FORGE_CPI_ESCROW_OUT"

stage_parent="$(dirname "$out_dir")"
mkdir -p "$stage_parent"
stage_dir="$(mktemp -d "$stage_parent/solana-cpi-escrow-stage.XXXXXX")" \
  || die "create staging dir"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT
mkdir -p "$stage_dir/src/$stem" "$stage_dir/deploy" "$stage_dir/out"
asm_path="$stage_dir/src/$stem/$stem.s"

echo "solana-cpi-escrow-build: rebuild emitter authority"
(
  cd "$root"
  lake build ProofForgeV2.Targets.Solana.EmitCpiEscrowSbpfV1
  lake env lean --run Tests/Materialization/SolanaCpiEscrowExportV1.lean \
    "runtime-tests/solana/fixtures/EscrowCpi.lean" "$asm_path"
) || die "Lean Escrow CPI export failed"

(
  cd "$stage_dir"
  "$sbpf_bin" build -d "$stage_dir/deploy"
) || die "sbpf build failed"
elf_path="$stage_dir/deploy/$stem.so"
[[ -f "$elf_path" && ! -L "$elf_path" ]] || die "missing generated ELF $elf_path"

disassembly_path="$stage_dir/$stem.disassembly.s"
LC_ALL=C "$sbpf_bin" disassemble "$elf_path" > "$disassembly_path" \
  || die "locked sbpf disassembly failed"
calls_path="$stage_dir/$stem.calls.json"
"$python_bin" -I -S - "$disassembly_path" "$calls_path" <<'PY' \
  || die "final ELF call-surface scan failed"
import json, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="ascii")
if not text.strip():
    raise SystemExit("empty disassembly")
if "0xec01" in text:
    raise SystemExit("final ELF disassembly contains forbidden legacy 0xec01 surface")
observed = []
allowed = {"sol_try_find_program_address", "sol_invoke_signed_c", "sol_set_return_data"}
for line_number, line in enumerate(text.splitlines(), 1):
    fields = line.lstrip().split(None, 1)
    if not fields or fields[0] not in {"call", "callx"}:
        continue
    if fields[0] == "callx":
        raise SystemExit(f"forbidden callx at {line_number}: {line}")
    target = fields[1].strip() if len(fields) > 1 else ""
    if target not in allowed:
        raise SystemExit(f"unexpected call at {line_number}: {line}")
    observed.append(target)
if "sol_invoke_signed_c" not in observed:
    raise SystemExit(f"expected sol_invoke_signed_c in final ELF, got {observed}")
if "sol_try_find_program_address" not in observed:
    raise SystemExit(f"expected sol_try_find_program_address in final ELF, got {observed}")
if "sol_set_return_data" not in observed:
    raise SystemExit(f"expected sol_set_return_data in final ELF, got {observed}")
Path(sys.argv[2]).write_text(json.dumps(observed) + "\n", encoding="ascii")
print(f"solana-cpi-escrow-build: final-ELF calls={observed}")
PY

"$python_bin" -I -S - \
  "$source_path" "$manifest_path" "$asm_path" "$elf_path" \
  "$ata_elf_path" "$token_elf_path" "$ata_manifest_path" "$token_manifest_path" \
  "$catalog_path" "$calls_path" "$rs_path" \
  "$stage_dir/out" "$measure_mode" <<'PY' || die "manifest binding failed"
import copy
import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path

(source_path, manifest_path, asm_path, elf_path, ata_elf_path,
 token_elf_path, ata_manifest_path, token_manifest_path, catalog_path,
 calls_path, rs_path, out_dir) = map(Path, sys.argv[1:13])
measure = sys.argv[13] == "1"

# Official pins (exact bind).
ATA_SHA = "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519"
ATA_SIZE = 111136
ATA_PROGRAM_ID_HEX = "8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859"
ATA_REPO = "https://github.com/solana-program/associated-token-account"
ATA_TAG = "program@v8.0.0"
ATA_TAG_OBJECT = "de77f367fdc0341879b1b9f0224c6b86107e1769"
ATA_PEELED_COMMIT = "0b867b5340cd001e5980d8ca7928effc4e10015c"
ATA_PROGRAM_VERSION = "8.0.0"
ATA_INTERFACE_VERSION = "2.0.0"
ATA_RECIPE_DIGEST = "f7ebe5236730d66ad730df6348b74332eb95e2abfda3377f389a13022e4528e2"
TOKEN_SHA = "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9"
TOKEN_SIZE = 94960
TOKEN_PROGRAM_ID_HEX = "06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9"
TOKEN_REPO = "https://github.com/solana-program/token"
TOKEN_TAG = "program@v9.0.0"
TOKEN_TAG_OBJECT = "5c37ac99c248567bd7d50b965af8cbd45b6ced96"
TOKEN_PEELED_COMMIT = "dfb260231c761be7d9c8b63728e770a102b86495"
TOKEN_PROGRAM_VERSION = "9.0.0"
TOKEN_INTERFACE_VERSION = "2.0.0"
TOKEN_RECIPE_DIGEST = "4af75b0a74ba14daa90a2d3913c71311609b3f3465728e733537dd0e34d8d063"
TOKEN_2022_BASE58 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
TOKEN_2022_HEX = "06ddf6e1ee758fde18425dbce46ccddab61afc4d83b90d27febdf928d8a18bfc"
SYSTEM_PROGRAM_ID_HEX = "00" * 32
SYSTEM_AGAVE_COMMIT = "2a165e7a90af75c76426d1e031ed0284211d5d1e"
CATALOG_RAW_SHA = "513c268853e59e5b274457ef95e7b4007f499897d4db50116d43a6be54da1ead"
CATALOG_DOMAIN_DIGEST = "41ace268b3bea9837e4a1fc9e456dbfbd36c98a344e51dfd095ab4ffb2086351"
CALLER_ID = "59" * 32
PROFILE_DIGEST = "0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1"
EXTENSION_DIGEST = "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"
SOURCE_SHA = "0424045e7cdc7e3c57b79d95c144e6047819db91b46c39607e42bf256b7c33bf"
SOURCE_SIZE = 5378
GOLDEN_WALLET_HEX = "31" * 32
GOLDEN_MINT_HEX = "41" * 32
GOLDEN_ATA_ADDRESS_HEX = "3af639c2730fe3226143abb59a0e253e3a93991c9b44eb86304943ef75e8668d"
GOLDEN_ATA_ADDRESS_BASE58 = "4yAQm6WURBF5ipetVEtw8sjHF9yHEKfLPyySQ8cARWPE"
GOLDEN_ATA_BUMP = 254
PDA_SEED0_UTF8 = "proof-forge:pda:v1"
PDA_SEED0_HEX = "70726f6f662d666f7267653a7064613a7631"
ACCOUNT_ROLE_CAP = 16

EXPECTED_HANDLERS = {
    "init": 0,
    "initializeVault": 1,
    "deposit": 2,
    "release": 3,
    "refund": 4,
    "initializeThenOverflow": 5,
    "depositThenOverflow": 6,
    "releaseThenOverflow": 7,
    "refundThenOverflow": 8,
    "inspect": 9,
}

EXPECTED_NON_CLAIMS = [
    "not OutputFile",
    "not product sync",
    "not multi-top-level transaction atomicity",
    "not formal",
    "not hermetic",
    "not mainnet parity",
    "not cross-host reproducible",
    "not package-owner-published",
    "not Token-2022",
    "not remaining accounts",
    "not dynamic accounts",
    "not multisig",
    "Principal is not a global Solana pubkey",
    "not proof-forge.output.v1",
    "not activated sync",
    "not release",
    "catalog ATA/Token artifactBinding remains absent",
    "catalog ATA/Token admittedForMaterialization=false",
    "harness/test-preactivation dependency only",
]

EXPECTED_FORCING_MATRIX = [
    "handler_ids_are_dense_source_order",
    "fixture_source_identity_and_extension_digest",
    "init_and_inspect_ix_layouts",
    "initialize_ix_layout_is_exactly_33_bytes",
    "deposit_ix_layout_is_exactly_17_bytes",
    "release_refund_ix_layout_is_exactly_26_bytes",
    "high_byte_scalar_layout_coverage",
    "case_role_counts_and_flags",
    "independent_authority_pda_oracle_cross_checks_sdk",
    "independent_vault_ata_oracle_cross_checks_sdk",
    "program_id_pin_is_all_0x59",
    "vendored_ata_and_token_elf_pins_are_exact",
    "generated_caller_elf_is_loadable_preactivation",
    "initialize_vault_fresh_success_exact_layout_and_state_order",
    "sequential_deposit_release_refund_amount_conservation",
    "initialize_then_overflow_full_snapshot_rollback_with_inner_logs",
    "deposit_then_overflow_full_snapshot_rollback",
    "release_then_overflow_full_snapshot_rollback",
    "refund_then_overflow_full_snapshot_rollback",
    "underfunded_initialize_inner_failure_full_snapshot",
    "insufficient_deposit_tokens_inner_failure_full_snapshot",
    "insufficient_vault_tokens_on_release_inner_failure_full_snapshot",
    "destination_amount_overflow_on_deposit_inner_failure_full_snapshot",
    "deposit_high_byte_amount_success_exact_delta",
    "inspect_reads_initialized_state",
    "one_mutation_deposit_state_and_privilege_flags",
    "one_mutation_deposit_source_account_shape",
    "one_mutation_deposit_mint_and_vault_account_shape",
    "one_mutation_deposit_token_program_and_aliases",
    "one_mutation_release_privilege_seed_and_program_flags",
    "one_mutation_release_token_account_shapes",
    "one_mutation_release_pda_key_aliases_and_order",
    "one_mutation_refund_destination_and_seed_authority",
    "one_mutation_initialize_privilege_and_program_flags",
    "one_mutation_initialize_keys_prestate_and_identity",
    "wrong_derivation_program_id_with_loaded_alias_program_fails_full_snapshot",
]

FORBIDDEN_SUBSTRINGS = (
    "\"runtimeArtifact\"",
    "\"packageOwnedElf\"",
    "p-token-release",
    "spl_p_token.so",
    "molluskCrateChecksum",
    "molluskRepoCommit",
    "molluskEmbeddedPath",
    "\"admitted\": true",
    "\"admittedForMaterialization\": true",
)


def stable_read(path, label):
    before = os.lstat(path)
    if path.is_symlink() or not stat.S_ISREG(before.st_mode):
        raise SystemExit("%s is not a regular non-symlink file: %s" % (label, path))
    if before.st_nlink != 1:
        raise SystemExit("%s must have one link, got %s: %s" % (label, before.st_nlink, path))
    data = path.read_bytes()
    after = os.lstat(path)
    identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_nlink)
    if identity(before) != identity(after) or len(data) != before.st_size:
        raise SystemExit("%s changed during read: %s" % (label, path))
    return data


def digest(data):
    return hashlib.sha256(data).hexdigest()


def exact_keys(value, expected, label):
    if not isinstance(value, dict) or set(value) != set(expected):
        got = sorted(value) if isinstance(value, dict) else type(value).__name__
        raise SystemExit("%s keys mismatch: got %s, expected %s" % (label, got, sorted(expected)))


def lower_hex(value, label, length):
    if (
        not isinstance(value, str)
        or len(value) != length
        or any(ch not in "0123456789abcdef" for ch in value)
    ):
        raise SystemExit("%s must be %s lowercase hex digits" % (label, length))


def lower_hex64(value, label):
    lower_hex(value, label, 64)


def lower_hex40(value, label):
    lower_hex(value, label, 40)


def bind_bytes(data, expected, label):
    exact_keys(expected, ("sha256", "size"), label)
    lower_hex64(expected["sha256"], "%s.sha256" % label)
    if type(expected["size"]) is not int or expected["size"] <= 0:
        raise SystemExit("%s.size must be a positive integer" % label)
    got = digest(data)
    if got != expected["sha256"]:
        raise SystemExit("%s sha256 mismatch: got %s, want %s" % (label, got, expected["sha256"]))
    if len(data) != expected["size"]:
        raise SystemExit("%s size mismatch: got %s, want %s" % (label, len(data), expected["size"]))
    return got


def exact_str_list(value, expected, label):
    if not isinstance(value, list) or any(not isinstance(x, str) for x in value):
        raise SystemExit("%s must be a list of strings" % label)
    if value != list(expected):
        raise SystemExit("%s exact ordered mismatch: got %s, want %s" % (label, value, list(expected)))


def extract_rs_forcing_matrix(rs_text):
    names = re.findall(r"#\[test\]\s*(?:#\[[^\]]*\]\s*)*fn\s+(\w+)", rs_text)
    if not names:
        raise SystemExit("cpi_escrow.rs has no #[test] functions")
    return names


def validate_committed_dependency_manifest(dep_manifest, kind, elf_bytes):
    """Cross-check committed ATA/Token runtime manifests for official provenance."""
    if kind == "ata":
        exact_keys(
            dep_manifest,
            (
                "schema", "issue", "sbpf", "runtimeOracle", "fixture", "profile",
                "extension", "boundary", "programIdHex", "catalogDigest", "ata",
                "tokenDependency", "systemDependency", "token2022Negative",
                "handlers", "pda", "generation", "expectedAssembly", "expectedElf",
                "expectedFinalElfCalls", "forcingMatrix", "reproducibilityNote",
            ),
            "ata.manifest",
        )
        if dep_manifest["schema"] != "proof-forge.solana.cpi-ata-runtime.v1":
            raise SystemExit("ata dependency manifest schema mismatch")
        ata = dep_manifest["ata"]
        iface = ata["interface"]
        vendored = ata["vendoredSourceBuiltElf"]
        recipe = vendored["recipe"]
        source = vendored["source"]
        if iface["tagObject"] != ATA_TAG_OBJECT or iface["peeledCommit"] != ATA_PEELED_COMMIT:
            raise SystemExit("ata dependency interface tagObject/peeledCommit mismatch")
        if iface["tag"] != ATA_TAG or iface["programVersion"] != ATA_PROGRAM_VERSION:
            raise SystemExit("ata dependency interface version/tag mismatch")
        if source["tagObject"] != ATA_TAG_OBJECT or source["peeledCommit"] != ATA_PEELED_COMMIT:
            raise SystemExit("ata dependency vendored source pin mismatch")
        if vendored["sha256"] != ATA_SHA or vendored["size"] != ATA_SIZE:
            raise SystemExit("ata dependency vendored sha/size pin mismatch")
        if recipe["recipeManifestDigest"] != ATA_RECIPE_DIGEST:
            raise SystemExit("ata dependency recipe digest mismatch")
        if recipe["sameHostRepeat"] != 2:
            raise SystemExit("ata dependency recipe.sameHostRepeat must be 2")
        if ata["artifactBinding"] != "absent":
            raise SystemExit("ata dependency artifactBinding must remain absent")
        if len(elf_bytes) != ATA_SIZE or digest(elf_bytes) != ATA_SHA:
            raise SystemExit("ata dependency ELF bytes disagree with committed pin")
    elif kind == "token":
        exact_keys(
            dep_manifest,
            (
                "schema", "issue", "sbpf", "runtimeOracle", "fixture", "profile",
                "extension", "boundary", "programIdHex", "catalogDigest", "token",
                "token2022Negative", "handlers", "pda", "generation",
                "expectedAssembly", "expectedElf", "expectedFinalElfCalls",
                "forcingMatrix", "reproducibilityNote",
            ),
            "token.manifest",
        )
        if dep_manifest["schema"] != "proof-forge.solana.cpi-token-runtime.v1":
            raise SystemExit("token dependency manifest schema mismatch")
        token = dep_manifest["token"]
        iface = token["interface"]
        vendored = token["vendoredSourceBuiltElf"]
        recipe = vendored["recipe"]
        source = vendored["source"]
        if iface["tagObject"] != TOKEN_TAG_OBJECT or iface["peeledCommit"] != TOKEN_PEELED_COMMIT:
            raise SystemExit("token dependency interface tagObject/peeledCommit mismatch")
        if iface["tag"] != TOKEN_TAG or iface["programVersion"] != TOKEN_PROGRAM_VERSION:
            raise SystemExit("token dependency interface version/tag mismatch")
        if source["tagObject"] != TOKEN_TAG_OBJECT or source["peeledCommit"] != TOKEN_PEELED_COMMIT:
            raise SystemExit("token dependency vendored source pin mismatch")
        if vendored["sha256"] != TOKEN_SHA or vendored["size"] != TOKEN_SIZE:
            raise SystemExit("token dependency vendored sha/size pin mismatch")
        if recipe["recipeManifestDigest"] != TOKEN_RECIPE_DIGEST:
            raise SystemExit("token dependency recipe digest mismatch")
        if recipe["sameHostRepeat"] != 2:
            raise SystemExit("token dependency recipe.sameHostRepeat must be 2")
        if token["artifactBinding"] != "absent":
            raise SystemExit("token dependency artifactBinding must remain absent")
        if len(elf_bytes) != TOKEN_SIZE or digest(elf_bytes) != TOKEN_SHA:
            raise SystemExit("token dependency ELF bytes disagree with committed pin")
    else:
        raise SystemExit("unknown dependency kind %r" % kind)


def validate_manifest_provenance(
    manifest, source, ata_bytes, token_bytes, catalog_bytes, rs_text,
    ata_manifest, token_manifest,
):
    """Exact structure + value provenance for the committed escrow runtime manifest."""
    exact_keys(
        manifest,
        (
            "schema",
            "issue",
            "sbpf",
            "runtimeOracle",
            "fixture",
            "profile",
            "extension",
            "boundary",
            "productionCodeGenerated",
            "programIdHex",
            "catalogRawSha256",
            "catalogDigest",
            "accountRoleCap",
            "ataDependency",
            "tokenDependency",
            "systemDependency",
            "token2022Negative",
            "handlers",
            "pda",
            "ataPda",
            "generation",
            "expectedAssembly",
            "expectedElf",
            "expectedFinalElfCalls",
            "forcingMatrix",
            "nonClaims",
            "reproducibilityNote",
        ),
        "manifest",
    )
    if manifest["schema"] != "proof-forge.solana.cpi-escrow-runtime.v1":
        raise SystemExit("wrong Escrow manifest schema")
    if manifest["issue"] != 124 or manifest["sbpf"] != "0.2.2":
        raise SystemExit("wrong issue or sbpf identity")

    runtime = manifest["runtimeOracle"]
    exact_keys(runtime, ("molluskSvm", "agaveSyscalls", "solanaProgramRuntime"), "runtimeOracle")
    if runtime != {
        "molluskSvm": "0.13.4",
        "agaveSyscalls": "4.0.0",
        "solanaProgramRuntime": "4.0.0",
    }:
        raise SystemExit("runtimeOracle identity mismatch")

    fixture = manifest["fixture"]
    exact_keys(fixture, ("path", "module", "sourceSha256", "sourceSize"), "fixture")
    if fixture["path"] != "runtime-tests/solana/fixtures/EscrowCpi.lean":
        raise SystemExit("fixture path mismatch")
    if fixture["module"] != "Examples.EscrowCpi":
        raise SystemExit("fixture module mismatch")
    lower_hex64(fixture["sourceSha256"], "fixture.sourceSha256")
    if digest(source) != fixture["sourceSha256"]:
        raise SystemExit("fixture sourceSha256 mismatch")
    if type(fixture["sourceSize"]) is not int or len(source) != fixture["sourceSize"]:
        raise SystemExit("fixture sourceSize mismatch")
    if fixture["sourceSha256"] != SOURCE_SHA or fixture["sourceSize"] != SOURCE_SIZE:
        raise SystemExit("fixture source pin disagrees with frozen #124 source identity")

    profile = manifest["profile"]
    exact_keys(profile, ("id", "digest"), "profile")
    if profile["id"] != "solana-sbpf-cpi-elf-v1":
        raise SystemExit("profile id mismatch")
    lower_hex64(profile["digest"], "profile.digest")
    if profile["digest"] != PROFILE_DIGEST:
        raise SystemExit("profile digest mismatch")

    extension = manifest["extension"]
    exact_keys(extension, ("id", "version", "digest"), "extension")
    if extension != {
        "id": "solana.cpi.accounts",
        "version": "1.0.0",
        "digest": EXTENSION_DIGEST,
    }:
        raise SystemExit("extension identity mismatch")

    boundary = manifest["boundary"]
    exact_keys(boundary, ("productArtifact", "testPreactivation", "activationDenied"), "boundary")
    if boundary != {
        "productArtifact": False,
        "testPreactivation": True,
        "activationDenied": True,
    }:
        raise SystemExit("preactivation boundary mismatch")
    if manifest["productionCodeGenerated"] is not True:
        raise SystemExit("productionCodeGenerated must be true")

    lower_hex64(manifest["programIdHex"], "programIdHex")
    if manifest["programIdHex"] != CALLER_ID:
        raise SystemExit("test program id must equal the #124 frozen escrow-caller id (all-0x59)")
    lower_hex64(manifest["catalogRawSha256"], "catalogRawSha256")
    if manifest["catalogRawSha256"] != CATALOG_RAW_SHA:
        raise SystemExit("catalogRawSha256 mismatch")
    lower_hex64(manifest["catalogDigest"], "catalogDigest")
    if manifest["catalogDigest"] != CATALOG_DOMAIN_DIGEST:
        raise SystemExit("catalogDigest must equal pf.solana.callee-catalog.v1 domain digest")
    if type(manifest["accountRoleCap"]) is not int or manifest["accountRoleCap"] != ACCOUNT_ROLE_CAP:
        raise SystemExit("accountRoleCap must be 16")

    # --- ATA dependency (committed ELF + committed ATA manifest cross-check) ---
    ata_dep = manifest["ataDependency"]
    exact_keys(
        ata_dep,
        (
            "package",
            "programIdHex",
            "executionClass",
            "artifactBinding",
            "path",
            "sha256",
            "size",
            "tag",
            "tagObject",
            "peeledCommit",
            "programVersion",
            "interfaceVersion",
            "recipeManifestDigest",
            "sameHostRepeat",
            "note",
        ),
        "ataDependency",
    )
    lower_hex64(ata_dep["programIdHex"], "ataDependency.programIdHex")
    lower_hex64(ata_dep["sha256"], "ataDependency.sha256")
    lower_hex40(ata_dep["tagObject"], "ataDependency.tagObject")
    lower_hex40(ata_dep["peeledCommit"], "ataDependency.peeledCommit")
    lower_hex64(ata_dep["recipeManifestDigest"], "ataDependency.recipeManifestDigest")
    if ata_dep != {
        "package": "ata-classic-v1",
        "programIdHex": ATA_PROGRAM_ID_HEX,
        "executionClass": "loaderV3Sbpf",
        "artifactBinding": "absent",
        "path": "runtime-tests/solana/ata/ata_classic_v1.so",
        "sha256": ATA_SHA,
        "size": ATA_SIZE,
        "tag": ATA_TAG,
        "tagObject": ATA_TAG_OBJECT,
        "peeledCommit": ATA_PEELED_COMMIT,
        "programVersion": ATA_PROGRAM_VERSION,
        "interfaceVersion": ATA_INTERFACE_VERSION,
        "recipeManifestDigest": ATA_RECIPE_DIGEST,
        "sameHostRepeat": 2,
        "note": ata_dep["note"],
    }:
        raise SystemExit("ataDependency full-field pin mismatch")
    note = ata_dep["note"]
    if not isinstance(note, str) or "harness" not in note.lower():
        raise SystemExit("ataDependency.note must identify harness/test-preactivation dependency")
    if "absent" not in note or "admitted" not in note.lower():
        raise SystemExit("ataDependency.note must deny catalog materialization admission")
    if len(ata_bytes) != ATA_SIZE or digest(ata_bytes) != ATA_SHA:
        raise SystemExit(
            "vendored ATA ELF mismatch: got size=%s sha=%s" % (len(ata_bytes), digest(ata_bytes))
        )
    if not ata_bytes.startswith(b"\x7fELF"):
        raise SystemExit("vendored ATA is not ELF")
    validate_committed_dependency_manifest(ata_manifest, "ata", ata_bytes)

    # --- Token dependency ---
    token_dep = manifest["tokenDependency"]
    exact_keys(
        token_dep,
        (
            "package",
            "programIdHex",
            "executionClass",
            "artifactBinding",
            "path",
            "sha256",
            "size",
            "tag",
            "tagObject",
            "peeledCommit",
            "programVersion",
            "interfaceVersion",
            "recipeManifestDigest",
            "sameHostRepeat",
            "note",
        ),
        "tokenDependency",
    )
    lower_hex64(token_dep["programIdHex"], "tokenDependency.programIdHex")
    lower_hex64(token_dep["sha256"], "tokenDependency.sha256")
    lower_hex40(token_dep["tagObject"], "tokenDependency.tagObject")
    lower_hex40(token_dep["peeledCommit"], "tokenDependency.peeledCommit")
    lower_hex64(token_dep["recipeManifestDigest"], "tokenDependency.recipeManifestDigest")
    if token_dep != {
        "package": "token-classic-v1",
        "programIdHex": TOKEN_PROGRAM_ID_HEX,
        "executionClass": "loaderV3Sbpf",
        "artifactBinding": "absent",
        "path": "runtime-tests/solana/token/token_classic_v1.so",
        "sha256": TOKEN_SHA,
        "size": TOKEN_SIZE,
        "tag": TOKEN_TAG,
        "tagObject": TOKEN_TAG_OBJECT,
        "peeledCommit": TOKEN_PEELED_COMMIT,
        "programVersion": TOKEN_PROGRAM_VERSION,
        "interfaceVersion": TOKEN_INTERFACE_VERSION,
        "recipeManifestDigest": TOKEN_RECIPE_DIGEST,
        "sameHostRepeat": 2,
        "note": token_dep["note"],
    }:
        raise SystemExit("tokenDependency full-field pin mismatch")
    tnote = token_dep["note"]
    if not isinstance(tnote, str) or "harness" not in tnote.lower():
        raise SystemExit("tokenDependency.note must identify harness/test-preactivation dependency")
    if "absent" not in tnote or "admitted" not in tnote.lower():
        raise SystemExit("tokenDependency.note must deny catalog materialization admission")
    if len(token_bytes) != TOKEN_SIZE or digest(token_bytes) != TOKEN_SHA:
        raise SystemExit(
            "vendored Token ELF mismatch: got size=%s sha=%s"
            % (len(token_bytes), digest(token_bytes))
        )
    if not token_bytes.startswith(b"\x7fELF"):
        raise SystemExit("vendored Token is not ELF")
    validate_committed_dependency_manifest(token_manifest, "token", token_bytes)

    # --- System: native only, never copy fake ELF ---
    system_dep = manifest["systemDependency"]
    exact_keys(
        system_dep,
        (
            "package",
            "programIdHex",
            "executionClass",
            "agaveCommit",
            "artifactBinding",
            "copiedElf",
            "note",
        ),
        "systemDependency",
    )
    lower_hex64(system_dep["programIdHex"], "systemDependency.programIdHex")
    lower_hex40(system_dep["agaveCommit"], "systemDependency.agaveCommit")
    if system_dep != {
        "package": "system-v1",
        "programIdHex": SYSTEM_PROGRAM_ID_HEX,
        "executionClass": "nativeSystem",
        "agaveCommit": SYSTEM_AGAVE_COMMIT,
        "artifactBinding": "runtimeNative",
        "copiedElf": False,
        "note": system_dep["note"],
    }:
        raise SystemExit("systemDependency full-field pin mismatch")
    if not isinstance(system_dep["note"], str) or "native" not in system_dep["note"].lower():
        raise SystemExit("systemDependency.note must identify native System (no fake ELF)")
    if system_dep["copiedElf"] is not False:
        raise SystemExit("systemDependency.copiedElf must be false")

    t22 = manifest["token2022Negative"]
    exact_keys(t22, ("programIdBase58", "programIdHex", "note"), "token2022Negative")
    lower_hex64(t22["programIdHex"], "token2022Negative.programIdHex")
    if t22["programIdBase58"] != TOKEN_2022_BASE58:
        raise SystemExit("token2022Negative.programIdBase58 mismatch")
    if t22["programIdHex"] != TOKEN_2022_HEX:
        raise SystemExit("token2022Negative.programIdHex mismatch")
    if not isinstance(t22["note"], str) or "fail-closed" not in t22["note"]:
        raise SystemExit("token2022Negative.note must state fail-closed")

    handlers = manifest["handlers"]
    exact_keys(handlers, tuple(EXPECTED_HANDLERS.keys()), "handlers")
    if handlers != EXPECTED_HANDLERS:
        raise SystemExit("handler ids / source-order mismatch: got %s" % handlers)

    pda = manifest["pda"]
    exact_keys(
        pda,
        (
            "recipe",
            "seed0Utf8",
            "seed0Hex",
            "canonicalBumpSearch",
            "bump0Rejected",
            "usedBy",
        ),
        "pda",
    )
    if pda["recipe"] != "current-program-tagged-v1":
        raise SystemExit("pda.recipe mismatch")
    if pda["seed0Utf8"] != PDA_SEED0_UTF8:
        raise SystemExit("pda.seed0Utf8 mismatch")
    if pda["seed0Hex"] != PDA_SEED0_HEX:
        raise SystemExit("pda.seed0Hex mismatch")
    if pda["canonicalBumpSearch"] != "255..1":
        raise SystemExit("pda.canonicalBumpSearch must be 255..1")
    if pda["bump0Rejected"] is not True:
        raise SystemExit("pda.bump0Rejected must be true")
    exact_str_list(
        pda["usedBy"],
        ["createPdaAccount", "transferCheckedPda"],
        "pda.usedBy",
    )

    ata_pda = manifest["ataPda"]
    exact_keys(
        ata_pda,
        (
            "recipe",
            "seeds",
            "derivationProgram",
            "canonicalBumpSearch",
            "bumpInInstructionData",
            "signerEligibleForCaller",
            "golden",
            "usedBy",
        ),
        "ataPda",
    )
    if ata_pda["recipe"] != "ata-classic-v1":
        raise SystemExit("ataPda.recipe mismatch")
    exact_str_list(
        ata_pda["seeds"],
        ["wallet", "classicTokenProgramId", "mint"],
        "ataPda.seeds",
    )
    if ata_pda["derivationProgram"] != "classicAtaProgramId":
        raise SystemExit("ataPda.derivationProgram mismatch")
    if ata_pda["canonicalBumpSearch"] != "255..1":
        raise SystemExit("ataPda.canonicalBumpSearch must be 255..1")
    if ata_pda["bumpInInstructionData"] is not False:
        raise SystemExit("ataPda.bumpInInstructionData must be false")
    if ata_pda["signerEligibleForCaller"] is not False:
        raise SystemExit("ataPda.signerEligibleForCaller must be false")
    golden = ata_pda["golden"]
    exact_keys(
        golden,
        ("walletHex", "mintHex", "addressHex", "addressBase58", "bump"),
        "ataPda.golden",
    )
    lower_hex64(golden["walletHex"], "ataPda.golden.walletHex")
    lower_hex64(golden["mintHex"], "ataPda.golden.mintHex")
    lower_hex64(golden["addressHex"], "ataPda.golden.addressHex")
    if golden != {
        "walletHex": GOLDEN_WALLET_HEX,
        "mintHex": GOLDEN_MINT_HEX,
        "addressHex": GOLDEN_ATA_ADDRESS_HEX,
        "addressBase58": GOLDEN_ATA_ADDRESS_BASE58,
        "bump": GOLDEN_ATA_BUMP,
    }:
        raise SystemExit("ataPda.golden full-field pin mismatch")
    exact_str_list(ata_pda["usedBy"], ["createIdempotent"], "ataPda.usedBy")

    generation = manifest["generation"]
    exact_keys(generation, ("status", "blockers", "note"), "generation")
    if generation["status"] != "ready":
        raise SystemExit("generation.status must be ready for this build path")
    if generation["blockers"] != []:
        raise SystemExit("generation.blockers must be empty when ready")
    gen_note = generation["note"]
    if not isinstance(gen_note, str) or not gen_note:
        raise SystemExit("generation.note must be nonempty")
    for required in (
        "private Escrow IR/emitter",
        "sbpf 0.2.2",
        "absent",
        "ordinary product sync remains denied",
        "harness",
    ):
        if required not in gen_note:
            raise SystemExit("generation.note missing boundary %r" % required)

    exact_keys(manifest["expectedAssembly"], ("sha256", "size"), "expectedAssembly")
    lower_hex64(manifest["expectedAssembly"]["sha256"], "expectedAssembly.sha256")
    if type(manifest["expectedAssembly"]["size"]) is not int or manifest["expectedAssembly"]["size"] <= 0:
        raise SystemExit("expectedAssembly.size must be a positive integer")
    exact_keys(manifest["expectedElf"], ("sha256", "size"), "expectedElf")
    lower_hex64(manifest["expectedElf"]["sha256"], "expectedElf.sha256")
    if type(manifest["expectedElf"]["size"]) is not int or manifest["expectedElf"]["size"] <= 0:
        raise SystemExit("expectedElf.size must be a positive integer")

    if not isinstance(manifest["expectedFinalElfCalls"], list) or not manifest["expectedFinalElfCalls"]:
        raise SystemExit("expectedFinalElfCalls must be a nonempty list")
    if any(not isinstance(x, str) for x in manifest["expectedFinalElfCalls"]):
        raise SystemExit("expectedFinalElfCalls must be strings")
    allowed_calls = {
        "sol_try_find_program_address",
        "sol_invoke_signed_c",
        "sol_set_return_data",
    }
    if any(x not in allowed_calls for x in manifest["expectedFinalElfCalls"]):
        raise SystemExit("expectedFinalElfCalls contains non-allowlisted syscall")

    exact_str_list(manifest["forcingMatrix"], EXPECTED_FORCING_MATRIX, "forcingMatrix")
    rs_matrix = extract_rs_forcing_matrix(rs_text)
    if rs_matrix != EXPECTED_FORCING_MATRIX:
        raise SystemExit(
            "cpi_escrow.rs active tests disagree with frozen forcingMatrix: got %s"
            % rs_matrix
        )
    if rs_matrix != manifest["forcingMatrix"]:
        raise SystemExit("manifest.forcingMatrix disagrees with cpi_escrow.rs #[test] order")

    exact_str_list(manifest["nonClaims"], EXPECTED_NON_CLAIMS, "nonClaims")

    repro = manifest["reproducibilityNote"]
    if not isinstance(repro, str) or not repro:
        raise SystemExit("reproducibilityNote must be nonempty")
    for required in (
        "not proof-forge.output.v1",
        "not activated sync",
        "not mainnet parity",
        "not multi-top-level transaction atomicity",
        "ATA v8",
        "Token v9",
        "artifactBinding remains absent",
        "harness/test-preactivation",
        "Principal is not a global Solana pubkey",
    ):
        if required not in repro:
            raise SystemExit("reproducibilityNote missing boundary %r" % required)
    if "p-token@" in repro.lower() or "spl_p_token" in repro.lower():
        raise SystemExit("reproducibilityNote must stay classic ATA/Token only")

    # Catalog domain digest + package deny (same authority as committed digest pin).
    try:
        catalog = json.loads(catalog_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit("invalid callee catalog JSON: %s" % error)
    canonical = json.dumps(catalog, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    if canonical != catalog_bytes:
        raise SystemExit("callee catalog not canonical JCS")
    if digest(catalog_bytes) != CATALOG_RAW_SHA:
        raise SystemExit("catalog raw sha256 mismatch")
    if digest(b"pf.solana.callee-catalog.v1\0" + canonical) != CATALOG_DOMAIN_DIGEST:
        raise SystemExit("catalog domain digest mismatch")
    packages = {p["packageId"]: p for p in catalog["packages"]}
    for package in ("ata-classic-v1", "token-classic-v1"):
        if package not in packages:
            raise SystemExit("catalog missing package %s" % package)
        if packages[package]["artifactBinding"] != {"kind": "absent"}:
            raise SystemExit("catalog unexpectedly binds %s" % package)
        if packages[package]["admittedForMaterialization"] is not False:
            raise SystemExit("catalog unexpectedly admits %s" % package)
    if packages["ata-classic-v1"]["interfaceBinding"] != {
        "commit": ATA_PEELED_COMMIT,
        "interfaceVersion": ATA_INTERFACE_VERSION,
        "programVersion": ATA_PROGRAM_VERSION,
        "repo": ATA_REPO,
        "tag": ATA_TAG,
        "tagObject": ATA_TAG_OBJECT,
    }:
        raise SystemExit("catalog ATA interfaceBinding pin mismatch")
    if packages["token-classic-v1"]["interfaceBinding"] != {
        "commit": TOKEN_PEELED_COMMIT,
        "interfaceVersion": TOKEN_INTERFACE_VERSION,
        "programVersion": TOKEN_PROGRAM_VERSION,
        "repo": TOKEN_REPO,
        "tag": TOKEN_TAG,
        "tagObject": TOKEN_TAG_OBJECT,
    }:
        raise SystemExit("catalog Token interfaceBinding pin mismatch")


def expect_provenance_reject(
    label, mutate, base_manifest, source, ata_bytes, token_bytes, catalog_bytes,
    rs_text, ata_manifest, token_manifest,
):
    mutant = copy.deepcopy(base_manifest)
    mutate(mutant)
    try:
        validate_manifest_provenance(
            mutant, source, ata_bytes, token_bytes, catalog_bytes, rs_text,
            ata_manifest, token_manifest,
        )
    except SystemExit as error:
        print("solana-cpi-escrow-build: self-test rejected %s (%s)" % (label, error))
        return
    raise SystemExit("self-test failed: mutation %r was accepted" % label)


# --- load committed + generated inputs (stable) ---
source = stable_read(source_path, "EscrowCpi source")
manifest_bytes = stable_read(manifest_path, "escrow manifest")
assembly = stable_read(asm_path, "generated assembly")
elf = stable_read(elf_path, "generated ELF")
ata_bytes = stable_read(ata_elf_path, "vendored classic ATA ELF")
token_bytes = stable_read(token_elf_path, "vendored classic Token ELF")
ata_manifest_bytes = stable_read(ata_manifest_path, "ata dependency manifest")
token_manifest_bytes = stable_read(token_manifest_path, "token dependency manifest")
catalog_bytes = stable_read(catalog_path, "callee catalog")
calls_bytes = stable_read(calls_path, "call sequence")
rs_text = stable_read(rs_path, "cpi_escrow.rs").decode("utf-8")
try:
    observed_calls = json.loads(calls_bytes.decode("ascii"))
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit("invalid call sequence JSON: %s" % error)
try:
    manifest = json.loads(manifest_bytes)
    ata_manifest = json.loads(ata_manifest_bytes)
    token_manifest = json.loads(token_manifest_bytes)
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit("invalid manifest JSON: %s" % error)

manifest_text = manifest_bytes.decode("utf-8")
for forbidden in FORBIDDEN_SUBSTRINGS:
    if forbidden in manifest_text:
        raise SystemExit(
            "committed Escrow manifest must not contain forbidden identity %r" % forbidden
        )

validate_manifest_provenance(
    manifest, source, ata_bytes, token_bytes, catalog_bytes, rs_text,
    ata_manifest, token_manifest,
)

# Embedded mutation self-tests: single-field tampering must reject.
expect_provenance_reject(
    "tokenDependency.peeledCommit",
    lambda m: m["tokenDependency"].__setitem__(
        "peeledCommit", "ffffffffffffffffffffffffffffffffffffffff"
    ),
    manifest, source, ata_bytes, token_bytes, catalog_bytes, rs_text,
    ata_manifest, token_manifest,
)
expect_provenance_reject(
    "handlers.order",
    lambda m: m["handlers"].__setitem__("inspect", 1),
    manifest, source, ata_bytes, token_bytes, catalog_bytes, rs_text,
    ata_manifest, token_manifest,
)
expect_provenance_reject(
    "ataPda.golden.bump",
    lambda m: m["ataPda"]["golden"].__setitem__("bump", 255),
    manifest, source, ata_bytes, token_bytes, catalog_bytes, rs_text,
    ata_manifest, token_manifest,
)
expect_provenance_reject(
    "forcingMatrix.order",
    lambda m: m.__setitem__(
        "forcingMatrix",
        list(reversed(list(m["forcingMatrix"]))),
    ),
    manifest, source, ata_bytes, token_bytes, catalog_bytes, rs_text,
    ata_manifest, token_manifest,
)
expect_provenance_reject(
    "nonClaims.drop",
    lambda m: m.__setitem__("nonClaims", list(m["nonClaims"][:-1])),
    manifest, source, ata_bytes, token_bytes, catalog_bytes, rs_text,
    ata_manifest, token_manifest,
)

asm_digest = digest(assembly)
elf_digest = digest(elf)
print(
    "solana-cpi-escrow-build: measured source size=%s sha256=%s"
    % (len(source), digest(source))
)
print(
    "solana-cpi-escrow-build: measured assembly size=%s sha256=%s"
    % (len(assembly), asm_digest)
)
print(
    "solana-cpi-escrow-build: measured caller ELF size=%s sha256=%s" % (len(elf), elf_digest)
)
print(
    "solana-cpi-escrow-build: measured classic ATA ELF size=%s sha256=%s"
    % (len(ata_bytes), digest(ata_bytes))
)
print(
    "solana-cpi-escrow-build: measured classic Token ELF size=%s sha256=%s"
    % (len(token_bytes), digest(token_bytes))
)
print("solana-cpi-escrow-build: measured final-ELF calls=%s" % (observed_calls,))
print(
    "solana-cpi-escrow-build: measured ataPda.golden bump=%s addressHex=%s"
    % (GOLDEN_ATA_BUMP, GOLDEN_ATA_ADDRESS_HEX)
)

if measure:
    print(
        "solana-cpi-escrow-build: MEASURE mode — skipping expectedAssembly/Elf/call pin match"
    )
    print(
        "solana-cpi-escrow-build: MEASURE pin hint expectedAssembly="
        + json.dumps({"sha256": asm_digest, "size": len(assembly)})
    )
    print(
        "solana-cpi-escrow-build: MEASURE pin hint expectedElf="
        + json.dumps({"sha256": elf_digest, "size": len(elf)})
    )
    print(
        "solana-cpi-escrow-build: MEASURE pin hint expectedFinalElfCalls="
        + json.dumps(observed_calls)
    )
    # MEASURE must not write leaves or publish PROOF_FORGE_CPI_ESCROW_OUT.
    # Shell exits before any rm/mv of the final out_dir; stage is discarded by trap.
    print("solana-cpi-escrow-build: MEASURE nonpublish — stage leaves not written")
    raise SystemExit(0)

if observed_calls != list(manifest["expectedFinalElfCalls"]):
    raise SystemExit(
        "final ELF call sequence mismatch: got %s, want %s"
        % (observed_calls, list(manifest["expectedFinalElfCalls"]))
    )
asm_digest = bind_bytes(assembly, manifest["expectedAssembly"], "expectedAssembly")
elf_digest = bind_bytes(elf, manifest["expectedElf"], "expectedElf")

if not elf.startswith(b"\x7fELF"):
    raise SystemExit("generated output is not ELF")
for forbidden in (b"0xec01", b"ACC0_"):
    if forbidden in assembly:
        raise SystemExit("Escrow assembly contains forbidden surface %r" % forbidden)
for required in (
    b"sol_invoke_signed_c",
    b"sol_set_return_data",
    b"sol_try_find_program_address",
):
    if required not in assembly:
        raise SystemExit("Escrow assembly missing %s" % required.decode())
if b"TEST-PREACTIVATION ONLY" not in assembly or b"not a product artifact" not in assembly:
    raise SystemExit("Escrow assembly boundary banner missing")

# Staged output: copy only already-validated input/generated bytes (no re-encode).
# System is native — never stage a fake System ELF. Normal mode only.
out_dir.mkdir(parents=True, exist_ok=True)
leaves = {
    "escrow_cpi.s": assembly,
    "escrow_cpi.so": elf,
    "ata_classic_v1.so": ata_bytes,
    "token_classic_v1.so": token_bytes,
    "escrow_cpi.calls.json": calls_bytes,
    "manifest.json": manifest_bytes,
}
for name, data in leaves.items():
    (out_dir / name).write_bytes(data)
    if name != "manifest.json":
        (out_dir / ("%s.sha256" % name)).write_text(digest(data) + "\n", encoding="ascii")
        (out_dir / ("%s.size" % name)).write_text("%s\n" % len(data), encoding="ascii")
print(
    "solana-cpi-escrow-build: assembly size=%s sha256=%s" % (len(assembly), asm_digest)
)
print("solana-cpi-escrow-build: caller ELF size=%s sha256=%s" % (len(elf), elf_digest))
print(
    "solana-cpi-escrow-build: classic ATA ELF size=%s sha256=%s"
    % (len(ata_bytes), digest(ata_bytes))
)
print(
    "solana-cpi-escrow-build: classic Token ELF size=%s sha256=%s"
    % (len(token_bytes), digest(token_bytes))
)
# Signal normal mode to shell: stage/out is ready for publish.
Path(out_dir / ".escrow-publish-ready").write_text("1\n", encoding="ascii")
PY

if [[ "$measure_mode" == "1" ]]; then
  echo "solana-cpi-escrow-build: MEASURE complete — no publish (out_dir untouched)"
  exit 0
fi

[[ -f "$stage_dir/out/.escrow-publish-ready" ]] \
  || die "normal mode missing publish-ready marker (refusing to publish)"
rm -f "$stage_dir/out/.escrow-publish-ready"
rm -rf "$out_dir"
mv "$stage_dir/out" "$out_dir"
echo "solana-cpi-escrow-build: output=$out_dir"
