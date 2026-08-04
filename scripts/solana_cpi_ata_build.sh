#!/usr/bin/env bash
# #123 production-code-generated, test-preactivation classic ATA CPI build.
#
# Loader → product compile → private preflight Plan → ATA IR → ATA emitter →
# locked sbpf 0.2.2. The vendored official ATA v8 and classic Token v9 ELF
# bytes are runtime-test dependencies only. Catalog artifact bindings remain
# absent and ordinary product sync remains denied.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_path="$root/runtime-tests/solana/fixtures/AtaCpi.lean"
manifest_path="$root/runtime-tests/solana/ata/manifest.json"
ata_elf_path="$root/runtime-tests/solana/ata/ata_classic_v1.so"
token_elf_path="$root/runtime-tests/solana/token/token_classic_v1.so"
catalog_path="$root/docs/specs/solana-cpi-callee-catalog-v1.json"
exporter_path="$root/Tests/Materialization/SolanaCpiAtaExportV1.lean"
out_dir="${PROOF_FORGE_CPI_ATA_OUT:-$root/build/v2/solana-cpi-ata}"
stem="ata_cpi"
measure_mode="${PROOF_FORGE_CPI_ATA_MEASURE:-0}"

die() {
  echo "solana-cpi-ata-build: $*" >&2
  exit 1
}

missing() {
  echo "solana-cpi-ata-build: $*" >&2
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

for input in "$source_path" "$manifest_path" "$ata_elf_path" "$token_elf_path" "$catalog_path"; do
  [[ -f "$input" && ! -L "$input" ]] || die "missing regular non-symlink input $input"
done
for input in "$exporter_path" \
  "$root/ProofForgeV2/Targets/Solana/CpiAtaIRV1.lean" \
  "$root/ProofForgeV2/Targets/Solana/EmitCpiAtaSbpfV1.lean"; do
  [[ -f "$input" && ! -L "$input" ]] || missing "missing ATA authority input $input"
done
grep -q 'resolveSolanaCpiAtaIRV1' "$root/ProofForgeV2/Targets/Solana/CpiAtaIRV1.lean" \
  || missing "CpiAtaIRV1 lacks sole mint"
grep -q 'emitCpiAtaSbpfV1' "$root/ProofForgeV2/Targets/Solana/EmitCpiAtaSbpfV1.lean" \
  || missing "EmitCpiAtaSbpfV1 lacks sole emitter"
grep -q 'sol_invoke_signed_c' "$root/ProofForgeV2/Targets/Solana/EmitCpiAtaSbpfV1.lean" \
  || missing "ATA emitter lacks real CPI syscall"

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
    raise SystemExit(f"PROOF_FORGE_CPI_ATA_OUT must be under {build}")
if not relative.parts:
    raise SystemExit("refusing to replace build root")
print(candidate)
PY
)" || die "unsafe PROOF_FORGE_CPI_ATA_OUT"

stage_parent="$(dirname "$out_dir")"
mkdir -p "$stage_parent"
stage_dir="$(mktemp -d "$stage_parent/solana-cpi-ata-stage.XXXXXX")" \
  || die "create staging dir"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT
mkdir -p "$stage_dir/src/$stem" "$stage_dir/deploy" "$stage_dir/out"
asm_path="$stage_dir/src/$stem/$stem.s"

echo "solana-cpi-ata-build: rebuild emitter authority"
(
  cd "$root"
  lake build ProofForgeV2.Targets.Solana.EmitCpiAtaSbpfV1
  lake env lean --run Tests/Materialization/SolanaCpiAtaExportV1.lean \
    "runtime-tests/solana/fixtures/AtaCpi.lean" "$asm_path"
) || die "Lean ATA CPI export failed"

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
if observed.count("sol_try_find_program_address") != 2:
    raise SystemExit(f"expected two ATA derivations, got {observed}")
if observed.count("sol_invoke_signed_c") != 2:
    raise SystemExit(f"expected two ATA CPIs, got {observed}")
Path(sys.argv[2]).write_text(json.dumps(observed) + "\n", encoding="ascii")
print(f"solana-cpi-ata-build: final-ELF calls={observed}")
PY

"$python_bin" -I -S - \
  "$source_path" "$manifest_path" "$asm_path" "$elf_path" \
  "$ata_elf_path" "$token_elf_path" "$catalog_path" "$calls_path" \
  "$stage_dir/out" "$measure_mode" <<'PY' || die "manifest binding failed"
import copy
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

(source_path, manifest_path, asm_path, elf_path, ata_elf_path,
 token_elf_path, catalog_path, calls_path, out_dir) = map(Path, sys.argv[1:10])
measure = sys.argv[10] == "1"

# Official pins (exact bind; recipeManifestDigest is a frozen digest pin only —
# no independent checked-in recipe is re-hashed here).
ATA_SHA = "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519"
ATA_SIZE = 111136
ATA_PROGRAM_ID_HEX = "8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859"
ATA_REPO = "https://github.com/solana-program/associated-token-account"
ATA_TAG = "program@v8.0.0"
ATA_TAG_OBJECT = "de77f367fdc0341879b1b9f0224c6b86107e1769"
ATA_PEELED_COMMIT = "0b867b5340cd001e5980d8ca7928effc4e10015c"
ATA_RECIPE_DIGEST = "f7ebe5236730d66ad730df6348b74332eb95e2abfda3377f389a13022e4528e2"
TOKEN_SHA = "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9"
TOKEN_SIZE = 94960
TOKEN_PROGRAM_ID_HEX = "06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9"
TOKEN_TAG = "program@v9.0.0"
TOKEN_TAG_OBJECT = "5c37ac99c248567bd7d50b965af8cbd45b6ced96"
TOKEN_PEELED_COMMIT = "dfb260231c761be7d9c8b63728e770a102b86495"
TOKEN_2022_BASE58 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
TOKEN_2022_HEX = "06ddf6e1ee758fde18425dbce46ccddab61afc4d83b90d27febdf928d8a18bfc"
SYSTEM_PROGRAM_ID_HEX = "00" * 32
SYSTEM_AGAVE_COMMIT = "2a165e7a90af75c76426d1e031ed0284211d5d1e"
CATALOG_DIGEST = "41ace268b3bea9837e4a1fc9e456dbfbd36c98a344e51dfd095ab4ffb2086351"
CALLER_ID = "58" * 32
PROFILE_DIGEST = "0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1"
EXTENSION_DIGEST = "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"
GOLDEN_WALLET_HEX = "31" * 32
GOLDEN_MINT_HEX = "41" * 32
GOLDEN_ADDRESS_HEX = "3af639c2730fe3226143abb59a0e253e3a93991c9b44eb86304943ef75e8668d"
GOLDEN_ADDRESS_BASE58 = "4yAQm6WURBF5ipetVEtw8sjHF9yHEKfLPyySQ8cARWPE"
GOLDEN_BUMP = 254

EXPECTED_NON_CLAIMS = [
    "not mainnet parity",
    "not cross-host reproducible",
    "not hermetic",
    "not formal",
    "not release",
    "not proof-forge.output.v1",
    "not activated sync",
    "not package-owner-published",
    "not package-owned locked release asset",
    "not mollusk-embedded ATA program",
]
EXPECTED_FORCING_MATRIX = [
    "generated_assembly_and_elf_are_exact_preactivation",
    "create_idempotent_fresh_success_exact_layout_and_state_order",
    "create_idempotent_replay_is_exactly_idempotent",
    "created_ata_is_usable_by_classic_token_transfer_checked",
    "create_idempotent_then_overflow_full_snapshot_rollback",
    "underfunded_payer_inner_failure_full_snapshot",
    "inspect_reads_initialized_state",
    "one_mutation_ata_key_and_fresh_prestate_negatives",
    "one_mutation_existing_ata_shape_and_join_negatives",
    "one_mutation_mint_account_negatives",
    "one_mutation_payer_and_wallet_negatives",
    "one_mutation_privilege_and_flag_negatives",
    "one_mutation_alias_negatives",
    "one_mutation_role_count_and_order_negatives",
    "ata_program_identity_loader_and_executable_negatives",
    "classic_token_and_token2022_program_negatives",
    "native_system_program_identity_negatives",
    "wrong_wallet_mint_or_token_seed_derivation_fails",
]
EXPECTED_FINAL_ELF_CALLS = [
    "sol_try_find_program_address",
    "sol_invoke_signed_c",
    "sol_set_return_data",
    "sol_set_return_data",
    "sol_try_find_program_address",
    "sol_invoke_signed_c",
    "sol_set_return_data",
    "sol_set_return_data",
    "sol_set_return_data",
]
FORBIDDEN_SUBSTRINGS = (
    "\"runtimeArtifact\"",
    "\"packageOwnedElf\"",
    "p-token-release",
    "spl_p_token.so",
    "molluskCrateChecksum",
    "molluskRepoCommit",
    "molluskEmbeddedPath",
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


def validate_manifest_provenance(manifest, source, ata_bytes, token_bytes, catalog_bytes):
    """Exact structure + value provenance for the committed ATA runtime manifest."""
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
            "programIdHex",
            "catalogDigest",
            "ata",
            "tokenDependency",
            "systemDependency",
            "token2022Negative",
            "handlers",
            "pda",
            "generation",
            "expectedAssembly",
            "expectedElf",
            "expectedFinalElfCalls",
            "forcingMatrix",
            "reproducibilityNote",
        ),
        "manifest",
    )
    if manifest["schema"] != "proof-forge.solana.cpi-ata-runtime.v1":
        raise SystemExit("wrong ATA manifest schema")
    if manifest["issue"] != 123 or manifest["sbpf"] != "0.2.2":
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
    if fixture["path"] != "runtime-tests/solana/fixtures/AtaCpi.lean":
        raise SystemExit("fixture path mismatch")
    if fixture["module"] != "Examples.AtaCpi":
        raise SystemExit("fixture module mismatch")
    lower_hex64(fixture["sourceSha256"], "fixture.sourceSha256")
    if digest(source) != fixture["sourceSha256"]:
        raise SystemExit("fixture sourceSha256 mismatch")
    if type(fixture["sourceSize"]) is not int or len(source) != fixture["sourceSize"]:
        raise SystemExit("fixture sourceSize mismatch")

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

    lower_hex64(manifest["programIdHex"], "programIdHex")
    if manifest["programIdHex"] != CALLER_ID:
        raise SystemExit("test program id must equal the #123 frozen ATA-caller id")
    lower_hex64(manifest["catalogDigest"], "catalogDigest")
    if manifest["catalogDigest"] != CATALOG_DIGEST:
        raise SystemExit("catalogDigest must equal pf.solana.callee-catalog.v1 domain digest")

    ata = manifest["ata"]
    exact_keys(
        ata,
        (
            "package",
            "programIdHex",
            "executionClass",
            "artifactBinding",
            "interface",
            "instructionSurface",
            "vendoredSourceBuiltElf",
        ),
        "ata",
    )
    if ata["package"] != "ata-classic-v1":
        raise SystemExit("ata.package mismatch")
    lower_hex64(ata["programIdHex"], "ata.programIdHex")
    if ata["programIdHex"] != ATA_PROGRAM_ID_HEX:
        raise SystemExit("ata.programIdHex must match frozen classic ATA program id")
    if ata["executionClass"] != "loaderV3Sbpf":
        raise SystemExit("ata.executionClass must be loaderV3Sbpf")
    if ata["artifactBinding"] != "absent":
        raise SystemExit("ata.artifactBinding must remain catalog 'absent'")
    if "runtimeArtifact" in ata or "packageOwnedElf" in ata:
        raise SystemExit("ata must not carry runtimeArtifact/packageOwnedElf")

    iface = ata["interface"]
    exact_keys(
        iface,
        ("repo", "tag", "tagObject", "peeledCommit", "programVersion", "interfaceVersion"),
        "ata.interface",
    )
    lower_hex40(iface["tagObject"], "ata.interface.tagObject")
    lower_hex40(iface["peeledCommit"], "ata.interface.peeledCommit")
    if iface != {
        "repo": ATA_REPO,
        "tag": ATA_TAG,
        "tagObject": ATA_TAG_OBJECT,
        "peeledCommit": ATA_PEELED_COMMIT,
        "programVersion": "8.0.0",
        "interfaceVersion": "2.0.0",
    }:
        raise SystemExit("ata.interface (program@v8.0.0 tagObject/peeled) mismatch")

    surface = ata["instructionSurface"]
    exact_keys(
        surface,
        (
            "createIdempotentTag",
            "createIdempotentDataBytes",
            "cpiMetaCount",
            "outerRoleCount",
            "mintDataBytes",
            "tokenAccountDataBytes",
        ),
        "ata.instructionSurface",
    )
    if surface != {
        "createIdempotentTag": 1,
        "createIdempotentDataBytes": 1,
        "cpiMetaCount": 6,
        "outerRoleCount": 8,
        "mintDataBytes": 82,
        "tokenAccountDataBytes": 165,
    }:
        raise SystemExit("ata instruction surface pin mismatch")

    vendored = ata["vendoredSourceBuiltElf"]
    exact_keys(
        vendored,
        ("status", "path", "sha256", "size", "source", "recipe", "nonClaims", "note"),
        "ata.vendoredSourceBuiltElf",
    )
    if vendored["status"] != "ready":
        raise SystemExit("vendoredSourceBuiltElf.status must be ready")
    if vendored["path"] != "runtime-tests/solana/ata/ata_classic_v1.so":
        raise SystemExit("vendoredSourceBuiltElf.path mismatch")
    lower_hex64(vendored["sha256"], "vendoredSourceBuiltElf.sha256")
    if vendored["sha256"] != ATA_SHA or vendored["size"] != ATA_SIZE:
        raise SystemExit("vendoredSourceBuiltElf sha256/size pin mismatch")
    if type(vendored["size"]) is not int:
        raise SystemExit("vendoredSourceBuiltElf.size must be int")

    vsrc = vendored["source"]
    exact_keys(vsrc, ("repo", "tag", "tagObject", "peeledCommit"), "vendoredSourceBuiltElf.source")
    lower_hex40(vsrc["tagObject"], "vendoredSourceBuiltElf.source.tagObject")
    lower_hex40(vsrc["peeledCommit"], "vendoredSourceBuiltElf.source.peeledCommit")
    if vsrc != {
        "repo": ATA_REPO,
        "tag": ATA_TAG,
        "tagObject": ATA_TAG_OBJECT,
        "peeledCommit": ATA_PEELED_COMMIT,
    }:
        raise SystemExit("vendoredSourceBuiltElf.source mismatch")

    recipe = vendored["recipe"]
    exact_keys(
        recipe,
        (
            "command",
            "solanaCli",
            "cargoBuildSbf",
            "platformTools",
            "sbfRustc",
            "sourceRustToolchain",
            "host",
            "recipeManifestDigest",
            "sameHostRepeat",
        ),
        "vendoredSourceBuiltElf.recipe",
    )
    # Bind every recipe composition field + exact digest pin. No independent
    # recipe file is re-hashed; do not claim recomputation.
    if recipe["command"] != "cargo-build-sbf --manifest-path program/Cargo.toml":
        raise SystemExit("recipe.command mismatch")
    if recipe["solanaCli"] != "3.0.0" or recipe["cargoBuildSbf"] != "3.0.0":
        raise SystemExit("recipe solana/cargo-build-sbf version mismatch")
    if recipe["platformTools"] != "v1.51":
        raise SystemExit("recipe.platformTools mismatch")
    if recipe["sbfRustc"] != "1.84.1-dev":
        raise SystemExit("recipe.sbfRustc mismatch")
    if recipe["sourceRustToolchain"] != "1.86.0":
        raise SystemExit("recipe.sourceRustToolchain mismatch")
    if recipe["host"] != "Darwin arm64":
        raise SystemExit("recipe.host mismatch")
    lower_hex64(recipe["recipeManifestDigest"], "recipe.recipeManifestDigest")
    if recipe["recipeManifestDigest"] != ATA_RECIPE_DIGEST:
        raise SystemExit("recipe.recipeManifestDigest pin mismatch (exact bind only)")
    if recipe["sameHostRepeat"] != 2:
        raise SystemExit("recipe.sameHostRepeat must be 2")

    exact_str_list(vendored["nonClaims"], EXPECTED_NON_CLAIMS, "vendoredSourceBuiltElf.nonClaims")
    note = vendored["note"]
    if not isinstance(note, str) or ATA_TAG not in note:
        raise SystemExit("vendoredSourceBuiltElf.note must identify program@v8.0.0")
    if "p-token@" in note.lower() or "spl_p_token" in note.lower():
        raise SystemExit("vendoredSourceBuiltElf.note must stay classic ATA only")
    if "artifactBinding.absent" not in note:
        raise SystemExit("vendoredSourceBuiltElf.note must deny catalog materialization")
    if "admittedForMaterialization=false" not in note:
        raise SystemExit("vendoredSourceBuiltElf.note must pin admittedForMaterialization=false")

    if len(ata_bytes) != ATA_SIZE or digest(ata_bytes) != ATA_SHA:
        raise SystemExit(
            "vendored ATA ELF mismatch: got size=%s sha=%s" % (len(ata_bytes), digest(ata_bytes))
        )
    if not ata_bytes.startswith(b"\x7fELF"):
        raise SystemExit("vendored ATA is not ELF")

    token_dep = manifest["tokenDependency"]
    exact_keys(
        token_dep,
        (
            "package",
            "programIdHex",
            "path",
            "sha256",
            "size",
            "tag",
            "tagObject",
            "peeledCommit",
            "artifactBinding",
        ),
        "tokenDependency",
    )
    lower_hex64(token_dep["programIdHex"], "tokenDependency.programIdHex")
    lower_hex64(token_dep["sha256"], "tokenDependency.sha256")
    lower_hex40(token_dep["tagObject"], "tokenDependency.tagObject")
    lower_hex40(token_dep["peeledCommit"], "tokenDependency.peeledCommit")
    if token_dep != {
        "package": "token-classic-v1",
        "programIdHex": TOKEN_PROGRAM_ID_HEX,
        "path": "runtime-tests/solana/token/token_classic_v1.so",
        "sha256": TOKEN_SHA,
        "size": TOKEN_SIZE,
        "tag": TOKEN_TAG,
        "tagObject": TOKEN_TAG_OBJECT,
        "peeledCommit": TOKEN_PEELED_COMMIT,
        "artifactBinding": "absent",
    }:
        raise SystemExit("tokenDependency full-field pin mismatch")
    if len(token_bytes) != TOKEN_SIZE or digest(token_bytes) != TOKEN_SHA:
        raise SystemExit(
            "vendored Token ELF mismatch: got size=%s sha=%s"
            % (len(token_bytes), digest(token_bytes))
        )
    if not token_bytes.startswith(b"\x7fELF"):
        raise SystemExit("vendored Token is not ELF")

    system_dep = manifest["systemDependency"]
    exact_keys(
        system_dep,
        ("package", "programIdHex", "executionClass", "agaveCommit", "artifactBinding"),
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
    }:
        raise SystemExit("systemDependency full-field pin mismatch")

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
    exact_keys(
        handlers,
        ("init", "createIdempotent", "createIdempotentThenOverflow", "inspect"),
        "handlers",
    )
    if handlers != {
        "init": 0,
        "createIdempotent": 1,
        "createIdempotentThenOverflow": 2,
        "inspect": 3,
    }:
        raise SystemExit("handler ids mismatch")

    pda = manifest["pda"]
    exact_keys(
        pda,
        (
            "recipe",
            "seeds",
            "derivationProgram",
            "canonicalBumpSearch",
            "bumpInInstructionData",
            "signerEligibleForCaller",
            "golden",
        ),
        "pda",
    )
    if pda["recipe"] != "ata-classic-v1":
        raise SystemExit("pda.recipe mismatch")
    exact_str_list(pda["seeds"], ["wallet", "classicTokenProgramId", "mint"], "pda.seeds")
    if pda["derivationProgram"] != "classicAtaProgramId":
        raise SystemExit("pda.derivationProgram mismatch")
    if pda["canonicalBumpSearch"] != "255..1":
        raise SystemExit("pda.canonicalBumpSearch must be 255..1")
    if pda["bumpInInstructionData"] is not False:
        raise SystemExit("pda.bumpInInstructionData must be false")
    if pda["signerEligibleForCaller"] is not False:
        raise SystemExit("pda.signerEligibleForCaller must be false")
    golden = pda["golden"]
    exact_keys(
        golden,
        ("walletHex", "mintHex", "addressHex", "addressBase58", "bump"),
        "pda.golden",
    )
    lower_hex64(golden["walletHex"], "pda.golden.walletHex")
    lower_hex64(golden["mintHex"], "pda.golden.mintHex")
    lower_hex64(golden["addressHex"], "pda.golden.addressHex")
    if golden != {
        "walletHex": GOLDEN_WALLET_HEX,
        "mintHex": GOLDEN_MINT_HEX,
        "addressHex": GOLDEN_ADDRESS_HEX,
        "addressBase58": GOLDEN_ADDRESS_BASE58,
        "bump": GOLDEN_BUMP,
    }:
        raise SystemExit("pda.golden full-field pin mismatch")

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
        "private ATA IR/emitter",
        "sbpf 0.2.2",
        "absent",
        "ordinary product sync remains denied",
    ):
        if required not in gen_note:
            raise SystemExit("generation.note missing boundary %r" % required)
    if "activated" in gen_note.lower() and "denied" not in gen_note.lower():
        raise SystemExit("generation.note must not claim activated product/sync")

    exact_keys(manifest["expectedAssembly"], ("sha256", "size"), "expectedAssembly")
    lower_hex64(manifest["expectedAssembly"]["sha256"], "expectedAssembly.sha256")
    if type(manifest["expectedAssembly"]["size"]) is not int or manifest["expectedAssembly"]["size"] <= 0:
        raise SystemExit("expectedAssembly.size must be a positive integer")
    exact_keys(manifest["expectedElf"], ("sha256", "size"), "expectedElf")
    lower_hex64(manifest["expectedElf"]["sha256"], "expectedElf.sha256")
    if type(manifest["expectedElf"]["size"]) is not int or manifest["expectedElf"]["size"] <= 0:
        raise SystemExit("expectedElf.size must be a positive integer")

    exact_str_list(
        manifest["expectedFinalElfCalls"], EXPECTED_FINAL_ELF_CALLS, "expectedFinalElfCalls"
    )
    exact_str_list(manifest["forcingMatrix"], EXPECTED_FORCING_MATRIX, "forcingMatrix")

    repro = manifest["reproducibilityNote"]
    if not isinstance(repro, str) or not repro:
        raise SystemExit("reproducibilityNote must be nonempty")
    for required in (
        "not proof-forge.output.v1",
        "not activated sync",
        "not mainnet parity",
        "ATA v8",
        "Token v9",
        "artifactBinding remains absent",
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
    if digest(b"pf.solana.callee-catalog.v1\0" + canonical) != CATALOG_DIGEST:
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
        "interfaceVersion": "2.0.0",
        "programVersion": "8.0.0",
        "repo": ATA_REPO,
        "tag": ATA_TAG,
        "tagObject": ATA_TAG_OBJECT,
    }:
        raise SystemExit("catalog ATA interfaceBinding pin mismatch")


def expect_provenance_reject(label, mutate, base_manifest, source, ata_bytes, token_bytes, catalog_bytes):
    mutant = copy.deepcopy(base_manifest)
    mutate(mutant)
    try:
        validate_manifest_provenance(mutant, source, ata_bytes, token_bytes, catalog_bytes)
    except SystemExit as error:
        print("solana-cpi-ata-build: self-test rejected %s (%s)" % (label, error))
        return
    raise SystemExit("self-test failed: mutation %r was accepted" % label)


# --- load committed + generated inputs (stable) ---
source = stable_read(source_path, "AtaCpi source")
manifest_bytes = stable_read(manifest_path, "ata manifest")
assembly = stable_read(asm_path, "generated assembly")
elf = stable_read(elf_path, "generated ELF")
ata_bytes = stable_read(ata_elf_path, "vendored classic ATA ELF")
token_bytes = stable_read(token_elf_path, "vendored classic Token ELF")
catalog_bytes = stable_read(catalog_path, "callee catalog")
calls_bytes = stable_read(calls_path, "call sequence")
try:
    observed_calls = json.loads(calls_bytes.decode("ascii"))
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit("invalid call sequence JSON: %s" % error)
try:
    manifest = json.loads(manifest_bytes)
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit("invalid manifest JSON: %s" % error)

manifest_text = manifest_bytes.decode("utf-8")
for forbidden in FORBIDDEN_SUBSTRINGS:
    if forbidden in manifest_text:
        raise SystemExit(
            "committed ATA manifest must not contain forbidden identity %r" % forbidden
        )

validate_manifest_provenance(manifest, source, ata_bytes, token_bytes, catalog_bytes)

# Embedded mutation self-tests: single-field tampering must reject, and must not
# write staged output (out_dir is empty / not yet written).
expect_provenance_reject(
    "ata.interface.peeledCommit",
    lambda m: m["ata"]["interface"].__setitem__(
        "peeledCommit", "ffffffffffffffffffffffffffffffffffffffff"
    ),
    manifest,
    source,
    ata_bytes,
    token_bytes,
    catalog_bytes,
)
expect_provenance_reject(
    "pda.golden.bump",
    lambda m: m["pda"]["golden"].__setitem__("bump", 255),
    manifest,
    source,
    ata_bytes,
    token_bytes,
    catalog_bytes,
)
expect_provenance_reject(
    "forcingMatrix.order",
    lambda m: m.__setitem__(
        "forcingMatrix",
        list(reversed(list(m["forcingMatrix"]))),
    ),
    manifest,
    source,
    ata_bytes,
    token_bytes,
    catalog_bytes,
)
expect_provenance_reject(
    "vendoredSourceBuiltElf.nonClaims.drop",
    lambda m: m["ata"]["vendoredSourceBuiltElf"].__setitem__(
        "nonClaims",
        list(m["ata"]["vendoredSourceBuiltElf"]["nonClaims"][:-1]),
    ),
    manifest,
    source,
    ata_bytes,
    token_bytes,
    catalog_bytes,
)

asm_digest = digest(assembly)
elf_digest = digest(elf)
print(
    "solana-cpi-ata-build: measured assembly size=%s sha256=%s"
    % (len(assembly), asm_digest)
)
print(
    "solana-cpi-ata-build: measured caller ELF size=%s sha256=%s" % (len(elf), elf_digest)
)
print(
    "solana-cpi-ata-build: measured classic ATA ELF size=%s sha256=%s"
    % (len(ata_bytes), digest(ata_bytes))
)
print(
    "solana-cpi-ata-build: measured classic Token ELF size=%s sha256=%s"
    % (len(token_bytes), digest(token_bytes))
)
print("solana-cpi-ata-build: measured final-ELF calls=%s" % (observed_calls,))

if measure:
    print(
        "solana-cpi-ata-build: MEASURE mode — skipping expectedAssembly/Elf/call pin match"
    )
else:
    if observed_calls != list(EXPECTED_FINAL_ELF_CALLS):
        raise SystemExit(
            "final ELF call sequence mismatch: got %s, want %s"
            % (observed_calls, list(EXPECTED_FINAL_ELF_CALLS))
        )
    if observed_calls != manifest["expectedFinalElfCalls"]:
        raise SystemExit("observed calls disagree with committed expectedFinalElfCalls")
    asm_digest = bind_bytes(assembly, manifest["expectedAssembly"], "expectedAssembly")
    elf_digest = bind_bytes(elf, manifest["expectedElf"], "expectedElf")

if not elf.startswith(b"\x7fELF"):
    raise SystemExit("generated output is not ELF")
for forbidden in (b"0xec01", b"ACC0_"):
    if forbidden in assembly:
        raise SystemExit("ATA assembly contains forbidden surface %r" % forbidden)
for required in (
    b"sol_invoke_signed_c",
    b"sol_set_return_data",
    b"sol_try_find_program_address",
):
    if required not in assembly:
        raise SystemExit("ATA assembly missing %s" % required.decode())
if b"TEST-PREACTIVATION ONLY" not in assembly or b"not a product artifact" not in assembly:
    raise SystemExit("ATA assembly boundary banner missing")

# Staged output: copy only already-validated input/generated bytes (no re-encode).
out_dir.mkdir(parents=True, exist_ok=True)
leaves = {
    "ata_cpi.s": assembly,
    "ata_cpi.so": elf,
    "ata_classic_v1.so": ata_bytes,
    "token_classic_v1.so": token_bytes,
    "ata_cpi.calls.json": calls_bytes,
    "manifest.json": manifest_bytes,
}
for name, data in leaves.items():
    (out_dir / name).write_bytes(data)
    if name != "manifest.json":
        (out_dir / ("%s.sha256" % name)).write_text(digest(data) + "\n", encoding="ascii")
        (out_dir / ("%s.size" % name)).write_text("%s\n" % len(data), encoding="ascii")
print(
    "solana-cpi-ata-build: assembly size=%s sha256=%s" % (len(assembly), asm_digest)
)
print("solana-cpi-ata-build: caller ELF size=%s sha256=%s" % (len(elf), elf_digest))
print(
    "solana-cpi-ata-build: classic ATA ELF size=%s sha256=%s"
    % (len(ata_bytes), digest(ata_bytes))
)
print(
    "solana-cpi-ata-build: classic Token ELF size=%s sha256=%s"
    % (len(token_bytes), digest(token_bytes))
)
PY

rm -rf "$out_dir"
mv "$stage_dir/out" "$out_dir"
echo "solana-cpi-ata-build: output=$out_dir"
