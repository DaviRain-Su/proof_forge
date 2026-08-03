#!/usr/bin/env bash
# #119 production-code-generated, test-preactivation unsigned companion CPI build.
#
# Lean exporter follows capability → Semantic-derived Plan → preflight IR →
# unsigned IR → emitter. Assembly/ELF are bound to a committed strict manifest
# for Mollusk only. Never mints proof-forge.output.v1. Does not activate
# synchronous-call support. #118 preflight artifacts remain independent.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_path="$root/runtime-tests/solana/fixtures/CompanionCpi.lean"
manifest_path="$root/runtime-tests/solana/unsigned/manifest.json"
exporter_path="$root/Tests/Materialization/SolanaCpiUnsignedExportV1.lean"
companion_manifest="$root/runtime-tests/solana/harness/manifest.json"
out_dir="${PROOF_FORGE_CPI_UNSIGNED_OUT:-$root/build/v2/solana-cpi-unsigned}"
stem="companion_cpi_unsigned"

die() {
  echo "solana-cpi-unsigned-build: $*" >&2
  exit 1
}

missing() {
  echo "solana-cpi-unsigned-build: $*" >&2
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

for input in "$source_path" "$manifest_path" "$exporter_path" "$companion_manifest"; do
  [[ -f "$input" && ! -L "$input" ]] || die "missing regular non-symlink input $input"
done

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
    raise SystemExit(f"PROOF_FORGE_CPI_UNSIGNED_OUT must be under {build}")
if not relative.parts:
    raise SystemExit("refusing to replace build root")
print(candidate)
PY
)" || die "unsafe PROOF_FORGE_CPI_UNSIGNED_OUT"

stage_parent="$(dirname "$out_dir")"
mkdir -p "$stage_parent"
stage_dir="$(mktemp -d "$stage_parent/solana-cpi-unsigned-stage.XXXXXX")" \
  || die "create staging dir"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT
mkdir -p "$stage_dir/src/$stem"
asm_path="$stage_dir/src/$stem/$stem.s"
deploy_dir="$stage_dir/deploy"

echo "solana-cpi-unsigned-build: rebuild emitter authority"
(
  cd "$root"
  lake build ProofForgeV2.Targets.Solana.EmitCpiUnsignedSbpfV1
  lake env lean --run Tests/Materialization/SolanaCpiUnsignedExportV1.lean \
    "runtime-tests/solana/fixtures/CompanionCpi.lean" "$asm_path"
) || die "Lean unsigned CPI export failed"

echo "solana-cpi-unsigned-build: sbpf=$sbpf_version"
(
  cd "$stage_dir"
  "$sbpf_bin" build -d "$deploy_dir"
) || die "sbpf build failed"

elf_path="$deploy_dir/$stem.so"
[[ -f "$elf_path" && ! -L "$elf_path" ]] || die "missing generated ELF $elf_path"

# Final ELF must contain sol_invoke_signed_c / sol_set_return_data and must not
# contain legacy 0xec01 call-stub surface. Disassemble with locked sbpf 0.2.2.
disassembly_path="$stage_dir/$stem.disassembly.s"
LC_ALL=C "$sbpf_bin" disassemble "$elf_path" > "$disassembly_path" \
  || die "locked sbpf disassembly failed"
"$python_bin" -I -S - "$disassembly_path" <<'PY' \
  || die "#119 final ELF call-surface scan failed"
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    text = path.read_text(encoding="ascii")
except (OSError, UnicodeError) as error:
    raise SystemExit(f"cannot read locked disassembly: {error}")
if not text.strip():
    raise SystemExit("locked disassembly is empty")
if "0xec01" in text:
    raise SystemExit("final ELF disassembly contains forbidden legacy 0xec01 surface")
observed_calls = []
allowed = {"sol_invoke_signed_c", "sol_set_return_data"}
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
expected_calls = [
    "sol_invoke_signed_c",
    "sol_set_return_data",
    "sol_set_return_data",
    "sol_invoke_signed_c",
    "sol_set_return_data",
    "sol_set_return_data",
    "sol_set_return_data",
]
if observed_calls != expected_calls:
    raise SystemExit(
        f"final ELF call sequence mismatch: got {observed_calls}, want {expected_calls}"
    )
PY

rm -rf "$out_dir"
mkdir -p "$out_dir"

"$python_bin" -I -S - \
  "$source_path" "$manifest_path" "$asm_path" "$elf_path" \
  "$companion_manifest" "$out_dir" <<'PY' \
  || die "manifest binding failed"
import hashlib
import json
import os
import sys
from pathlib import Path

(
    source_path,
    manifest_path,
    asm_path,
    elf_path,
    companion_manifest_path,
    out_dir,
) = map(Path, sys.argv[1:])


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
    if type(expected["size"]) is not int or expected["size"] < 0:
        raise SystemExit(f"{label}.size must be a nonnegative integer")
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


source = stable_read_regular(source_path, "CompanionCpi source")
manifest_raw = stable_read_regular(manifest_path, "unsigned manifest")
assembly = stable_read_regular(asm_path, "generated assembly")
elf = stable_read_regular(elf_path, "generated ELF")
companion_manifest_raw = stable_read_regular(
    companion_manifest_path, "harness companion manifest"
)
try:
    manifest = json.loads(manifest_raw)
    companion_manifest = json.loads(companion_manifest_raw)
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"invalid manifest JSON: {error}")

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
        "companionProgramIdHex",
        "companion",
        "handlers",
        "expectedAssembly",
        "expectedElf",
        "reproducibilityNote",
    ),
    "manifest",
)
if manifest["schema"] != "proof-forge.solana.cpi-unsigned-runtime.v1":
    raise SystemExit("wrong unsigned manifest schema")
if manifest["issue"] != 119 or manifest["sbpf"] != "0.2.2":
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
if fixture["path"] != "runtime-tests/solana/fixtures/CompanionCpi.lean":
    raise SystemExit("fixture path mismatch")
if fixture["module"] != "Examples.CompanionCpi":
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
if profile["digest"] != "0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1":
    raise SystemExit("profile digest mismatch")

extension = manifest["extension"]
exact_keys(extension, ("id", "version", "digest"), "extension")
if extension != {
    "id": "solana.cpi.accounts",
    "version": "1.0.0",
    "digest": "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020",
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
if manifest["programIdHex"] != "55" * 32:
    raise SystemExit("test program id mismatch")
lower_hex64(manifest["companionProgramIdHex"], "companionProgramIdHex")
if manifest["companionProgramIdHex"] != "43" * 32:
    raise SystemExit("companion program id mismatch")

companion = manifest["companion"]
exact_keys(companion, ("package", "programIdHex", "elfSha256", "elfSize"), "companion")
if companion["package"] != "companion-v1":
    raise SystemExit("companion package mismatch")
if companion["programIdHex"] != "43" * 32:
    raise SystemExit("companion programIdHex mismatch")
# Bind to #115 harness companion identity from committed harness manifest.
if companion_manifest.get("programIds", {}).get("companionHex") != "43" * 32:
    raise SystemExit("harness companion id diverged")
expected_companion_sha = companion_manifest["expectedElfSha256"]["companion"]
expected_companion_size = companion_manifest["expectedElfSize"]["companion"]
if expected_companion_sha != "c8738f1220c49c309ffe820ca397ae25540d6be29c6153934abd8548fa08c4b9":
    raise SystemExit("#115 harness companion sha256 pin diverged")
if expected_companion_size != 1776:
    raise SystemExit("#115 harness companion size pin diverged")
if companion["elfSha256"] != expected_companion_sha:
    raise SystemExit("companion elfSha256 must match #115 harness pin")
if companion["elfSize"] != expected_companion_size:
    raise SystemExit("companion elfSize must match #115 harness pin")

handlers = manifest["handlers"]
exact_keys(handlers, ("init", "invokeOnce", "failOnce", "inspect"), "handlers")
if handlers != {"init": 0, "invokeOnce": 1, "failOnce": 2, "inspect": 3}:
    raise SystemExit("handler ids mismatch")
if not isinstance(manifest["reproducibilityNote"], str) or not manifest["reproducibilityNote"]:
    raise SystemExit("reproducibilityNote must be nonempty")
if "not proof-forge.output.v1" not in manifest["reproducibilityNote"]:
    raise SystemExit("reproducibilityNote must deny product OutputSet")
if "not an activated CPI artifact" not in manifest["reproducibilityNote"]:
    raise SystemExit("reproducibilityNote must deny activation")

asm_digest = bind_bytes(assembly, manifest["expectedAssembly"], "expectedAssembly")
elf_digest = bind_bytes(elf, manifest["expectedElf"], "expectedElf")
if not elf.startswith(b"\x7fELF"):
    raise SystemExit("generated output is not ELF")
for forbidden in (b"0xec01", b"ACC0_"):
    if forbidden in assembly:
        raise SystemExit(f"unsigned assembly contains forbidden surface {forbidden!r}")
if b"sol_invoke_signed_c" not in assembly:
    raise SystemExit("unsigned assembly missing sol_invoke_signed_c")
if b"sol_set_return_data" not in assembly:
    raise SystemExit("unsigned assembly missing sol_set_return_data")
if b"TEST-PREACTIVATION ONLY" not in assembly or b"not a product artifact" not in assembly:
    raise SystemExit("unsigned assembly boundary banner missing")

stem = "companion_cpi_unsigned"
(out_dir / "manifest.json").write_bytes(manifest_raw)
(out_dir / f"{stem}.s").write_bytes(assembly)
(out_dir / f"{stem}.s.sha256").write_text(asm_digest + "\n")
(out_dir / f"{stem}.s.size").write_text(f"{len(assembly)}\n")
(out_dir / f"{stem}.so").write_bytes(elf)
(out_dir / f"{stem}.so.sha256").write_text(elf_digest + "\n")
(out_dir / f"{stem}.so.size").write_text(f"{len(elf)}\n")
print(
    "solana-cpi-unsigned-build: "
    f"assembly size={len(assembly)} sha256={asm_digest}"
)
print(
    "solana-cpi-unsigned-build: "
    f"ELF size={len(elf)} sha256={elf_digest}"
)
PY

echo "solana-cpi-unsigned-build: ok → $out_dir"
