#!/usr/bin/env bash
# #118 production-code-generated, test-preactivation Solana preflight build.
#
# The Lean exporter follows the real capability → Semantic-derived Plan →
# resolved preflight IR → emitter chain. The resulting assembly/ELF are bound
# to a committed strict manifest for Mollusk only. This script never mints
# proof-forge.output.v1 and does not activate synchronous-call support.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_path="$root/runtime-tests/solana/fixtures/AccountRoles.lean"
manifest_path="$root/runtime-tests/solana/preflight/manifest.json"
exporter_path="$root/Tests/Materialization/SolanaCpiPreflightExportV1.lean"
out_dir="${PROOF_FORGE_CPI_PREFLIGHT_OUT:-$root/build/v2/solana-cpi-preflight}"
stem="account_roles_preflight"

die() {
  echo "solana-cpi-preflight-build: $*" >&2
  exit 1
}

missing() {
  echo "solana-cpi-preflight-build: $*" >&2
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

for input in "$source_path" "$manifest_path" "$exporter_path"; do
  [[ -f "$input" && ! -L "$input" ]] || die "missing regular non-symlink input $input"
done

# Resolve existing parents and constrain cleanup to this worktree's build tree.
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
    raise SystemExit(f"PROOF_FORGE_CPI_PREFLIGHT_OUT must be under {build}")
if not relative.parts:
    raise SystemExit("refusing to replace build root")
print(candidate)
PY
)" || die "unsafe PROOF_FORGE_CPI_PREFLIGHT_OUT"

stage_parent="$(dirname "$out_dir")"
mkdir -p "$stage_parent"
stage_dir="$(mktemp -d "$stage_parent/solana-cpi-preflight-stage.XXXXXX")" \
  || die "create staging dir"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT
mkdir -p "$stage_dir/src/$stem"
asm_path="$stage_dir/src/$stem/$stem.s"
deploy_dir="$stage_dir/deploy"

echo "solana-cpi-preflight-build: rebuild emitter authority"
(
  cd "$root"
  lake build ProofForgeV2.Targets.Solana.EmitCpiPreflightSbpfV1
  lake env lean --run Tests/Materialization/SolanaCpiPreflightExportV1.lean \
    "runtime-tests/solana/fixtures/AccountRoles.lean" "$asm_path"
) || die "Lean preflight export failed"

echo "solana-cpi-preflight-build: sbpf=$sbpf_version"
(
  cd "$stage_dir"
  "$sbpf_bin" build -d "$deploy_dir"
) || die "sbpf build failed"

elf_path="$deploy_dir/$stem.so"
[[ -f "$elf_path" && ! -L "$elf_path" ]] || die "missing generated ELF $elf_path"

# Prove the final ELF, not only the generated source text, is call-free in
# #118. The locked disassembler decodes linked SBPF instructions; any `call`
# would be a syscall or internal-call surface and is forbidden until #119.
disassembly_path="$stage_dir/$stem.disassembly.s"
LC_ALL=C "$sbpf_bin" disassemble "$elf_path" > "$disassembly_path" \
  || die "locked sbpf disassembly failed"
"$python_bin" -I -S - "$disassembly_path" <<'PY' \
  || die "#118 final ELF call-instruction scan failed"
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    text = path.read_text(encoding="ascii")
except (OSError, UnicodeError) as error:
    raise SystemExit(f"cannot read locked disassembly: {error}")
if not text.strip():
    raise SystemExit("locked disassembly is empty")
for line_number, line in enumerate(text.splitlines(), 1):
    fields = line.lstrip().split(None, 1)
    if fields and fields[0] in {"call", "callx"}:
        raise SystemExit(
            f"forbidden final-ELF call instruction at line {line_number}: {line}"
        )
PY

rm -rf "$out_dir"
mkdir -p "$out_dir"

"$python_bin" -I -S - \
  "$source_path" "$manifest_path" "$asm_path" "$elf_path" "$out_dir" <<'PY' \
  || die "manifest binding failed"
import hashlib
import json
import os
import sys
from pathlib import Path

source_path, manifest_path, asm_path, elf_path, out_dir = map(Path, sys.argv[1:])


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


source = stable_read_regular(source_path, "AccountRoles source")
manifest_raw = stable_read_regular(manifest_path, "preflight manifest")
assembly = stable_read_regular(asm_path, "generated assembly")
elf = stable_read_regular(elf_path, "generated ELF")
try:
    manifest = json.loads(manifest_raw)
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"invalid preflight manifest: {error}")

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
        "handlers",
        "expectedAssembly",
        "expectedElf",
        "reproducibilityNote",
    ),
    "manifest",
)
if manifest["schema"] != "proof-forge.solana.cpi-preflight-runtime.v1":
    raise SystemExit("wrong preflight manifest schema")
if manifest["issue"] != 118 or manifest["sbpf"] != "0.2.2":
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
if fixture["path"] != "runtime-tests/solana/fixtures/AccountRoles.lean":
    raise SystemExit("fixture path mismatch")
if fixture["module"] != "Examples.AccountRoles":
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
if manifest["programIdHex"] != "52" * 32:
    raise SystemExit("test program id mismatch")
handlers = manifest["handlers"]
exact_keys(handlers, ("init", "route", "inspect"), "handlers")
if handlers != {"init": 0, "route": 1, "inspect": 2}:
    raise SystemExit("handler ids mismatch")
if not isinstance(manifest["reproducibilityNote"], str) or not manifest["reproducibilityNote"]:
    raise SystemExit("reproducibilityNote must be nonempty")

asm_digest = bind_bytes(assembly, manifest["expectedAssembly"], "expectedAssembly")
elf_digest = bind_bytes(elf, manifest["expectedElf"], "expectedElf")
if not elf.startswith(b"\x7fELF"):
    raise SystemExit("generated output is not ELF")
for forbidden in (b"sol_invoke", b"invoke_signed", b"ACC0_"):
    if forbidden in assembly:
        raise SystemExit(f"preflight assembly contains forbidden surface {forbidden!r}")
if b"TEST-PREACTIVATION ONLY" not in assembly or b"not a product artifact" not in assembly:
    raise SystemExit("preflight assembly boundary banner missing")

(out_dir / "manifest.json").write_bytes(manifest_raw)
(out_dir / "account_roles_preflight.s").write_bytes(assembly)
(out_dir / "account_roles_preflight.s.sha256").write_text(asm_digest + "\n")
(out_dir / "account_roles_preflight.s.size").write_text(f"{len(assembly)}\n")
(out_dir / "account_roles_preflight.so").write_bytes(elf)
(out_dir / "account_roles_preflight.so.sha256").write_text(elf_digest + "\n")
(out_dir / "account_roles_preflight.so.size").write_text(f"{len(elf)}\n")
print(
    "solana-cpi-preflight-build: "
    f"assembly size={len(assembly)} sha256={asm_digest}"
)
print(
    "solana-cpi-preflight-build: "
    f"ELF size={len(elf)} sha256={elf_digest}"
)
PY

echo "solana-cpi-preflight-build: ok → $out_dir"
