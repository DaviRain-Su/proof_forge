#!/usr/bin/env bash
# #122 production-code-generated, test-preactivation classic Token CPI build.
#
# Lean exporter: capability → Semantic-derived Plan → Token IR → emitter
# (resolveSolanaCpiTokenIRV1 + emitCpiTokenSbpfV1). Assembly/ELF bind to a
# committed strict manifest for Mollusk only.
#
# Classic Token Program is a vendored source-built loader-v3 ELF at
# runtime-tests/solana/token/token_classic_v1.so built from official
# solana-program/token program@v9.0.0 (annotated tag object 5c37ac99… peeled
# to commit dfb26023…). Catalog token-classic-v1 remains
# artifactBinding.absent / admittedForMaterialization=false — this lane does
# not rewrite the product catalog and does not claim release publication,
# mainnet parity, cross-host, hermetic, formal, or activated sync.
#
# Never mints proof-forge.output.v1. Does not activate synchronous-call support.
# #115–#121 artifacts remain independent.
#
# PROOF_FORGE_CPI_TOKEN_MEASURE=1: generate + print measured assembly/ELF
# digests without requiring expectedAssembly/expectedElf pin match (phase-1
# pin discovery only; never invents hashes).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_path="$root/runtime-tests/solana/fixtures/TokenCpi.lean"
manifest_path="$root/runtime-tests/solana/token/manifest.json"
exporter_path="$root/Tests/Materialization/SolanaCpiTokenExportV1.lean"
token_elf_path="$root/runtime-tests/solana/token/token_classic_v1.so"
out_dir="${PROOF_FORGE_CPI_TOKEN_OUT:-$root/build/v2/solana-cpi-token}"
stem="token_cpi"
measure_mode="${PROOF_FORGE_CPI_TOKEN_MEASURE:-0}"

die() {
  echo "solana-cpi-token-build: $*" >&2
  exit 1
}

missing() {
  echo "solana-cpi-token-build: $*" >&2
  exit 2
}

case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    missing "unsupported host platform: $(uname -s)"
    ;;
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

for input in "$source_path" "$manifest_path" "$token_elf_path"; do
  [[ -f "$input" && ! -L "$input" ]] || die "missing regular non-symlink input $input"
done

if [[ ! -f "$exporter_path" || -L "$exporter_path" ]]; then
  missing "dependency: Lean exporter missing at $exporter_path
  (expected Tests/Materialization/SolanaCpiTokenExportV1.lean using
   resolveSolanaCpiTokenIRV1 + emitCpiTokenSbpfV1)"
fi

ir_path="$root/ProofForgeV2/Targets/Solana/CpiTokenIRV1.lean"
emit_path="$root/ProofForgeV2/Targets/Solana/EmitCpiTokenSbpfV1.lean"
[[ -f "$ir_path" && ! -L "$ir_path" ]] || missing "missing CpiTokenIRV1 at $ir_path"
[[ -f "$emit_path" && ! -L "$emit_path" ]] || missing "missing EmitCpiTokenSbpfV1 at $emit_path"
grep -q 'resolveSolanaCpiTokenIRV1' "$ir_path" \
  || missing "CpiTokenIRV1 lacks resolveSolanaCpiTokenIRV1"
grep -q 'solana.token.transferChecked' "$ir_path" \
  || missing "CpiTokenIRV1 lacks solana.token.transferChecked"
grep -q 'emitCpiTokenSbpfV1' "$emit_path" \
  || missing "EmitCpiTokenSbpfV1 lacks emitCpiTokenSbpfV1"
grep -q 'sol_invoke_signed_c' "$emit_path" \
  || missing "EmitCpiTokenSbpfV1 lacks sol_invoke_signed_c"

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
    raise SystemExit(f"PROOF_FORGE_CPI_TOKEN_OUT must be under {build}")
if not relative.parts:
    raise SystemExit("refusing to replace build root")
print(candidate)
PY
)" || die "unsafe PROOF_FORGE_CPI_TOKEN_OUT"

stage_parent="$(dirname "$out_dir")"
mkdir -p "$stage_parent"
stage_dir="$(mktemp -d "$stage_parent/solana-cpi-token-stage.XXXXXX")" \
  || die "create staging dir"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT
mkdir -p "$stage_dir/src/$stem"
asm_path="$stage_dir/src/$stem/$stem.s"
deploy_dir="$stage_dir/deploy"

echo "solana-cpi-token-build: rebuild emitter authority"
(
  cd "$root"
  lake build ProofForgeV2.Targets.Solana.EmitCpiTokenSbpfV1
  lake env lean --run Tests/Materialization/SolanaCpiTokenExportV1.lean \
    "runtime-tests/solana/fixtures/TokenCpi.lean" "$asm_path"
) || die "Lean Token CPI export failed"

echo "solana-cpi-token-build: sbpf=$sbpf_version"
(
  cd "$stage_dir"
  "$sbpf_bin" build -d "$deploy_dir"
) || die "sbpf build failed"

elf_path="$deploy_dir/$stem.so"
[[ -f "$elf_path" && ! -L "$elf_path" ]] || die "missing generated ELF $elf_path"

disassembly_path="$stage_dir/$stem.disassembly.s"
LC_ALL=C "$sbpf_bin" disassemble "$elf_path" > "$disassembly_path" \
  || die "locked sbpf disassembly failed"

calls_path="$stage_dir/$stem.calls.json"
"$python_bin" -I -S - "$disassembly_path" "$calls_path" <<'PY' \
  || die "#122 final ELF call-surface scan failed"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
out = Path(sys.argv[2])
try:
    text = path.read_text(encoding="ascii")
except (OSError, UnicodeError) as error:
    raise SystemExit(f"cannot read locked disassembly: {error}")
if not text.strip():
    raise SystemExit("locked disassembly is empty")
if "0xec01" in text:
    raise SystemExit("final ELF disassembly contains forbidden legacy 0xec01 surface")
observed_calls = []
allowed = {
    "sol_try_find_program_address",
    "sol_invoke_signed_c",
    "sol_set_return_data",
}
for line_number, line in enumerate(text.splitlines(), 1):
    fields = line.lstrip().split(None, 1)
    if not fields or fields[0] not in {"call", "callx"}:
        continue
    if fields[0] == "callx":
        raise SystemExit(f"forbidden indirect callx at line {line_number}: {line}")
    target = fields[1].strip() if len(fields) > 1 else ""
    if target not in allowed:
        raise SystemExit(f"unexpected final-ELF call at line {line_number}: {line}")
    observed_calls.append(target)
if "sol_invoke_signed_c" not in observed_calls:
    raise SystemExit("final ELF missing sol_invoke_signed_c")
if "sol_set_return_data" not in observed_calls:
    raise SystemExit("final ELF missing sol_set_return_data")
if "sol_try_find_program_address" not in observed_calls:
    raise SystemExit(
        "final ELF missing sol_try_find_program_address "
        "(transferCheckedPda / PdaThenOverflow require PDA search)"
    )
out.write_text(json.dumps(observed_calls) + "\n", encoding="ascii")
print(f"solana-cpi-token-build: final-ELF calls={observed_calls}")
PY

rm -rf "$out_dir"
mkdir -p "$out_dir"

"$python_bin" -I -S - \
  "$source_path" "$manifest_path" "$asm_path" "$elf_path" "$token_elf_path" \
  "$out_dir" "$calls_path" "$measure_mode" <<'PY' \
  || die "manifest binding failed"
import hashlib
import json
import os
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
asm_path = Path(sys.argv[3])
elf_path = Path(sys.argv[4])
token_elf_path = Path(sys.argv[5])
out_dir = Path(sys.argv[6])
calls_path = Path(sys.argv[7])
measure_mode = sys.argv[8] == "1"

TOKEN_ELF_SHA256 = "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9"
TOKEN_ELF_SIZE = 94960
TOKEN_PROGRAM_ID_HEX = "06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9"
CALLER_PROGRAM_ID_HEX = "57" * 32
PROFILE_DIGEST = "0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1"
EXTENSION_DIGEST = "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"
CATALOG_DIGEST = "0da1837ec10f7acc716c1151bee23a04e019174f99b1fedde635c7d75b4055f5"
TAG_OBJECT = "5c37ac99c248567bd7d50b965af8cbd45b6ced96"
PEELED_COMMIT = "dfb260231c761be7d9c8b63728e770a102b86495"
RECIPE_DIGEST = "4af75b0a74ba14daa90a2d3913c71311609b3f3465728e733537dd0e34d8d063"

# Residual alternate-callee identity keys/values only.
FORBIDDEN_TOKEN_SUBSTRINGS = (
    "\"runtimeArtifact\"",
    "\"packageOwnedElf\"",
    "p-token-release",
    "spl_p_token.so",
    "src/elf/token.so",
    "molluskCrateChecksum",
    "molluskRepoCommit",
    "molluskEmbeddedPath",
)


def stable_read_regular(path: Path, label: str) -> bytes:
    before = os.lstat(path)
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"{label} is not a regular non-symlink file: {path}")
    if before.st_nlink != 1:
        raise SystemExit(f"{label} must have one link, got {before.st_nlink}: {path}")
    data = path.read_bytes()
    after = os.lstat(path)
    observed_before = (
        before.st_dev,
        before.st_ino,
        before.st_size,
        before.st_mtime_ns,
    )
    observed_after = (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
    )
    if observed_before != observed_after or len(data) != before.st_size:
        raise SystemExit(f"{label} changed during read: {path}")
    return data


def exact_keys(value, expected, label):
    if not isinstance(value, dict) or set(value) != set(expected):
        got = sorted(value) if isinstance(value, dict) else type(value).__name__
        raise SystemExit(f"{label} keys mismatch: got {got}, expected {sorted(expected)}")


def lower_hex64(value, label):
    if not isinstance(value, str) or len(value) != 64 or any(
        ch not in "0123456789abcdef" for ch in value
    ):
        raise SystemExit(f"{label} must be 64 lowercase hex digits")


def bind_bytes(data, expected, label):
    exact_keys(expected, ("sha256", "size"), label)
    lower_hex64(expected["sha256"], f"{label}.sha256")
    if type(expected["size"]) is not int or expected["size"] <= 0:
        raise SystemExit(f"{label}.size must be a positive integer")
    digest = hashlib.sha256(data).hexdigest()
    if digest != expected["sha256"]:
        raise SystemExit(
            f"{label} sha256 mismatch: got {digest}, want {expected['sha256']}"
        )
    if len(data) != expected["size"]:
        raise SystemExit(
            f"{label} size mismatch: got {len(data)}, want {expected['size']}"
        )
    return digest


source = stable_read_regular(source_path, "TokenCpi source")
manifest_raw = stable_read_regular(manifest_path, "token manifest")
assembly = stable_read_regular(asm_path, "generated assembly")
elf = stable_read_regular(elf_path, "generated ELF")
token_elf = stable_read_regular(token_elf_path, "vendored classic Token ELF")
observed_calls = json.loads(stable_read_regular(calls_path, "call sequence").decode("ascii"))
try:
    manifest = json.loads(manifest_raw)
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"invalid manifest JSON: {error}")

# Refuse residual alternate-callee identity keys in the committed JSON.
manifest_text = manifest_raw.decode("utf-8")
for forbidden in FORBIDDEN_TOKEN_SUBSTRINGS:
    if forbidden in manifest_text:
        raise SystemExit(
            f"committed token manifest must not contain forbidden identity {forbidden!r}"
        )

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
        "token",
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
if manifest["schema"] != "proof-forge.solana.cpi-token-runtime.v1":
    raise SystemExit("wrong token manifest schema")
if manifest["issue"] != 122 or manifest["sbpf"] != "0.2.2":
    raise SystemExit("wrong issue or sbpf identity")

runtime = manifest["runtimeOracle"]
exact_keys(runtime, ("molluskSvm", "agaveSyscalls", "solanaProgramRuntime"), "runtimeOracle")
if runtime != {
    "molluskSvm": "0.13.4",
    "agaveSyscalls": "4.0.0",
    "solanaProgramRuntime": "4.0.0",
}:
    raise SystemExit("runtime oracle identity mismatch")

fixture = manifest["fixture"]
exact_keys(fixture, ("path", "module", "sourceSha256", "sourceSize"), "fixture")
if fixture["path"] != "runtime-tests/solana/fixtures/TokenCpi.lean":
    raise SystemExit("fixture path mismatch")
if fixture["module"] != "Examples.TokenCpi":
    raise SystemExit("fixture module mismatch")
lower_hex64(fixture["sourceSha256"], "fixture.sourceSha256")
if hashlib.sha256(source).hexdigest() != fixture["sourceSha256"]:
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
if manifest["programIdHex"] != CALLER_PROGRAM_ID_HEX:
    raise SystemExit("test program id must equal the #122 frozen token-caller id")

lower_hex64(manifest["catalogDigest"], "catalogDigest")
if manifest["catalogDigest"] != CATALOG_DIGEST:
    raise SystemExit("catalogDigest must equal pf.solana.callee-catalog.v1 domain digest")

token = manifest["token"]
exact_keys(
    token,
    (
        "package",
        "programIdHex",
        "executionClass",
        "artifactBinding",
        "interface",
        "instructionSurface",
        "vendoredSourceBuiltElf",
    ),
    "token",
)
if token["package"] != "token-classic-v1":
    raise SystemExit("token package mismatch")
if token["programIdHex"] != TOKEN_PROGRAM_ID_HEX:
    raise SystemExit("token program id must match frozen catalog classic Token id")
if token["executionClass"] != "loaderV3Sbpf":
    raise SystemExit("token executionClass must be loaderV3Sbpf")
if token["artifactBinding"] != "absent":
    raise SystemExit(
        "token.artifactBinding must remain catalog 'absent' "
        "(product materialization still denied)"
    )
if "runtimeArtifact" in token or "packageOwnedElf" in token:
    raise SystemExit(
        "token must not carry runtimeArtifact/packageOwnedElf "
        "(vendoredSourceBuiltElf is the sole classic Token ELF carrier)"
    )

iface = token["interface"]
exact_keys(
    iface,
    ("repo", "tag", "tagObject", "peeledCommit", "programVersion", "interfaceVersion"),
    "token.interface",
)
if iface != {
    "repo": "https://github.com/solana-program/token",
    "tag": "program@v9.0.0",
    "tagObject": TAG_OBJECT,
    "peeledCommit": PEELED_COMMIT,
    "programVersion": "9.0.0",
    "interfaceVersion": "2.0.0",
}:
    raise SystemExit("token.interface (program@v9.0.0 tagObject/peeled) mismatch")

surface = token["instructionSurface"]
exact_keys(
    surface,
    (
        "transferCheckedTag",
        "transferCheckedDataBytes",
        "mintDataBytes",
        "tokenAccountDataBytes",
    ),
    "token.instructionSurface",
)
if surface != {
    "transferCheckedTag": 12,
    "transferCheckedDataBytes": 10,
    "mintDataBytes": 82,
    "tokenAccountDataBytes": 165,
}:
    raise SystemExit("token instruction surface pin mismatch")

vendored = token["vendoredSourceBuiltElf"]
exact_keys(
    vendored,
    (
        "status",
        "path",
        "sha256",
        "size",
        "source",
        "recipe",
        "nonClaims",
        "note",
    ),
    "token.vendoredSourceBuiltElf",
)
if vendored["status"] != "ready":
    raise SystemExit("vendoredSourceBuiltElf.status must be ready")
if vendored["path"] != "runtime-tests/solana/token/token_classic_v1.so":
    raise SystemExit("vendoredSourceBuiltElf.path mismatch")
lower_hex64(vendored["sha256"], "vendoredSourceBuiltElf.sha256")
if vendored["sha256"] != TOKEN_ELF_SHA256:
    raise SystemExit("vendoredSourceBuiltElf.sha256 pin mismatch")
if vendored["size"] != TOKEN_ELF_SIZE:
    raise SystemExit("vendoredSourceBuiltElf.size pin mismatch")

src = vendored["source"]
exact_keys(
    src,
    ("repo", "tag", "tagObject", "peeledCommit"),
    "vendoredSourceBuiltElf.source",
)
if src != {
    "repo": "https://github.com/solana-program/token",
    "tag": "program@v9.0.0",
    "tagObject": TAG_OBJECT,
    "peeledCommit": PEELED_COMMIT,
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
if recipe["recipeManifestDigest"] != RECIPE_DIGEST:
    raise SystemExit("recipe.recipeManifestDigest mismatch")
if recipe["sameHostRepeat"] != 2:
    raise SystemExit("recipe.sameHostRepeat must be 2")

non_claims = vendored["nonClaims"]
if not isinstance(non_claims, list) or not non_claims:
    raise SystemExit("vendoredSourceBuiltElf.nonClaims must be nonempty list")
required_non_claims = {
    "not mainnet parity",
    "not cross-host reproducible",
    "not hermetic",
    "not formal",
    "not release",
    "not proof-forge.output.v1",
    "not activated sync",
    "not package-owner-published",
    "not package-owned locked release asset",
    "not p-token",
    "not mollusk-embedded token.so",
}
if not required_non_claims.issubset(set(non_claims)):
    raise SystemExit(f"vendoredSourceBuiltElf.nonClaims missing required entries")

if not isinstance(vendored["note"], str) or "program@v9.0.0" not in vendored["note"]:
    raise SystemExit("vendoredSourceBuiltElf.note must identify program@v9.0.0")
if "p-token@" in vendored["note"].lower() or "spl_p_token" in vendored["note"].lower():
    raise SystemExit("vendoredSourceBuiltElf.note must stay program@v9.0.0 source-built only")

token_digest = hashlib.sha256(token_elf).hexdigest()
if token_digest != TOKEN_ELF_SHA256 or len(token_elf) != TOKEN_ELF_SIZE:
    raise SystemExit(
        f"vendored Token ELF mismatch: got size={len(token_elf)} sha={token_digest}"
    )
if not token_elf.startswith(b"\x7fELF"):
    raise SystemExit("vendored Token is not ELF")

t22 = manifest["token2022Negative"]
exact_keys(t22, ("programIdBase58", "programIdHex", "note"), "token2022Negative")
if t22["programIdBase58"] != "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb":
    raise SystemExit("token2022Negative.programIdBase58 mismatch")
if t22["programIdHex"] != "06ddf6e1ee758fde18425dbce46ccddab61afc4d83b90d27febdf928d8a18bfc":
    raise SystemExit("token2022Negative.programIdHex mismatch")

handlers = manifest["handlers"]
exact_keys(
    handlers,
    (
        "init",
        "transferChecked",
        "transferCheckedPda",
        "transferCheckedThenOverflow",
        "transferCheckedPdaThenOverflow",
        "inspect",
    ),
    "handlers",
)
if handlers != {
    "init": 0,
    "transferChecked": 1,
    "transferCheckedPda": 2,
    "transferCheckedThenOverflow": 3,
    "transferCheckedPdaThenOverflow": 4,
    "inspect": 5,
}:
    raise SystemExit("handler ids mismatch")

pda = manifest["pda"]
exact_keys(
    pda,
    ("recipe", "seed0Utf8", "seed0Hex", "canonicalBumpSearch", "bump0Rejected"),
    "pda",
)
if pda != {
    "recipe": "current-program-tagged-v1",
    "seed0Utf8": "proof-forge:pda:v1",
    "seed0Hex": "70726f6f662d666f7267653a7064613a7631",
    "canonicalBumpSearch": "255..1",
    "bump0Rejected": True,
}:
    raise SystemExit("PDA recipe identity mismatch")

generation = manifest["generation"]
exact_keys(generation, ("status", "blockers", "note"), "generation")
if generation["status"] != "ready":
    raise SystemExit("generation.status must be ready for this build path")
if generation["blockers"] != []:
    raise SystemExit("generation.blockers must be empty when ready")
if not isinstance(generation["note"], str) or "program@v9.0.0" not in generation["note"]:
    raise SystemExit("generation.note must mention program@v9.0.0")
if "p-token@" in generation["note"].lower() or "spl_p_token" in generation["note"].lower():
    raise SystemExit("generation.note must stay program@v9.0.0 source-built only")

if not isinstance(manifest["reproducibilityNote"], str) or not manifest["reproducibilityNote"]:
    raise SystemExit("reproducibilityNote must be nonempty")
for required in (
    "not proof-forge.output.v1",
    "not an activated CPI artifact",
    "not mainnet parity",
    "program@v9.0.0",
):
    if required not in manifest["reproducibilityNote"]:
        raise SystemExit(f"reproducibilityNote missing {required!r}")
if "p-token@" in manifest["reproducibilityNote"].lower() or "spl_p_token" in manifest[
    "reproducibilityNote"
].lower():
    raise SystemExit("reproducibilityNote must stay program@v9.0.0 source-built only")

asm_digest = hashlib.sha256(assembly).hexdigest()
elf_digest = hashlib.sha256(elf).hexdigest()
print(
    "solana-cpi-token-build: measured "
    f"assembly size={len(assembly)} sha256={asm_digest}"
)
print(
    "solana-cpi-token-build: measured "
    f"caller ELF size={len(elf)} sha256={elf_digest}"
)
print(
    "solana-cpi-token-build: measured "
    f"classic Token ELF size={len(token_elf)} sha256={token_digest}"
)
print(f"solana-cpi-token-build: measured final-ELF calls={observed_calls}")

if measure_mode:
    print("solana-cpi-token-build: MEASURE mode — skipping expectedAssembly/Elf pin match")
else:
    expected_calls = manifest["expectedFinalElfCalls"]
    if not isinstance(expected_calls, list) or not expected_calls:
        raise SystemExit("expectedFinalElfCalls must be a nonempty list")
    if observed_calls != expected_calls:
        raise SystemExit(
            f"final ELF call sequence mismatch: got {observed_calls}, want {expected_calls}"
        )
    asm_digest = bind_bytes(assembly, manifest["expectedAssembly"], "expectedAssembly")
    elf_digest = bind_bytes(elf, manifest["expectedElf"], "expectedElf")

if not elf.startswith(b"\x7fELF"):
    raise SystemExit("generated output is not ELF")
for forbidden in (b"0xec01", b"ACC0_"):
    if forbidden in assembly:
        raise SystemExit(f"token assembly contains forbidden surface {forbidden!r}")
for required in (
    b"sol_invoke_signed_c",
    b"sol_set_return_data",
    b"sol_try_find_program_address",
):
    if required not in assembly:
        raise SystemExit(f"token assembly missing {required.decode()}")
if b"TEST-PREACTIVATION ONLY" not in assembly or b"not a product artifact" not in assembly:
    raise SystemExit("token assembly boundary banner missing")

stem = "token_cpi"
(out_dir / "manifest.json").write_bytes(manifest_raw)
(out_dir / f"{stem}.s").write_bytes(assembly)
(out_dir / f"{stem}.s.sha256").write_text(asm_digest + "\n")
(out_dir / f"{stem}.s.size").write_text(f"{len(assembly)}\n")
(out_dir / f"{stem}.so").write_bytes(elf)
(out_dir / f"{stem}.so.sha256").write_text(elf_digest + "\n")
(out_dir / f"{stem}.so.size").write_text(f"{len(elf)}\n")
(out_dir / "token_classic_v1.so").write_bytes(token_elf)
(out_dir / "token_classic_v1.so.sha256").write_text(token_digest + "\n")
(out_dir / "token_classic_v1.so.size").write_text(f"{len(token_elf)}\n")
(out_dir / f"{stem}.calls.json").write_text(
    json.dumps(observed_calls) + "\n", encoding="ascii"
)
print(
    "solana-cpi-token-build: "
    f"assembly size={len(assembly)} sha256={asm_digest}"
)
print(
    "solana-cpi-token-build: "
    f"caller ELF size={len(elf)} sha256={elf_digest}"
)
print(
    "solana-cpi-token-build: "
    f"classic Token ELF size={len(token_elf)} sha256={token_digest}"
)
PY

echo "solana-cpi-token-build: ok → $out_dir"
