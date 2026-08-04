#!/usr/bin/env bash
# Build the tracked TransferSol example through the ordinary Solana CPI product
# profile. This script is offline with respect to Solana RPC; it only invokes
# the local compiler and locked sbpf toolchain.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
label="solana-transfer-sol-build"

fail() {
  echo "${label}: $*" >&2
  exit 1
}

missing() {
  echo "${label}: $*" >&2
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
[[ -x "$PROOF_FORGE_TOOL_ROOT/sbpf" ]] \
  || missing "locked sbpf not found at $PROOF_FORGE_TOOL_ROOT/sbpf"
command -v lake >/dev/null 2>&1 || missing "lake not on PATH"

if [[ -x /usr/bin/python3 ]]; then
  python_bin=/usr/bin/python3
elif command -v python3 >/dev/null 2>&1; then
  python_bin="$(command -v python3)"
else
  missing "python3 not found"
fi

mkdir -p "$root/build"

source_rel="Examples/TransferSol.lean"
module_name="Examples.TransferSol"
program_name="TransferSol"
profile_id="solana-sbpf-cpi-elf-v1"
cli="$root/.lake/build/bin/proof-forge-next"
[[ -f "$root/$source_rel" && ! -L "$root/$source_rel" ]] \
  || fail "tracked source must be a regular non-symlink: $source_rel"

out_raw="${PROOF_FORGE_TRANSFER_SOL_OUT:-$root/build/v2/solana-transfer-sol-product}"
out_dir="$($python_bin -I -S - "$root" "$out_raw" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve(strict=True)
build = (root / "build").resolve(strict=True)
raw = Path(sys.argv[2])
candidate = raw if raw.is_absolute() else root / raw
candidate = Path(os.path.abspath(candidate))
try:
    relative = candidate.relative_to(build)
except ValueError as exc:
    raise SystemExit(f"output must stay under {build}") from exc
if not relative.parts:
    raise SystemExit("refusing to replace the build root")
current = build
for index, part in enumerate(relative.parts):
    current = current / part
    if current.is_symlink():
        raise SystemExit(f"output path contains a symlink: {current}")
    if current.exists() and not current.is_dir():
        raise SystemExit(f"output path component is not a directory: {current}")
print(candidate)
PY
)" || missing "unsafe PROOF_FORGE_TRANSFER_SOL_OUT"

if [[ ! -x "$cli" ]]; then
  echo "${label}: building proof-forge-next"
  lake build proof_forge_next || fail "lake build proof_forge_next failed"
fi
[[ -x "$cli" ]] || fail "compiler executable missing: $cli"

mkdir -p "$(dirname "$out_dir")"
rm -rf "$out_dir"
echo "${label}: build $source_rel -> $out_dir"
lake env "$cli" build "$source_rel" \
  --module "$module_name" \
  --target solana \
  --profile "$profile_id" \
  -o "$out_dir" \
  || fail "ProofForge product build failed"

echo "${label}: inspect exact product closure"
lake env "$cli" inspect --output-dir "$out_dir" --json >/dev/null \
  || fail "ProofForge product inspect failed"

for leaf in \
  "$program_name.cpi-bindings.json" \
  "$program_name.cpi-ir.json" \
  "$program_name.cpi-plan.json" \
  "$program_name.idl.json" \
  "$program_name.s" \
  "$program_name.so" \
  evidence.json \
  manifest.json; do
  [[ -f "$out_dir/$leaf" && ! -L "$out_dir/$leaf" ]] \
    || fail "missing regular product leaf: $leaf"
done

echo "${label}: ok output=$out_dir"
