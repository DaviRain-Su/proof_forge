#!/usr/bin/env bash
# Harness-only Solana CPI spike build (#115).
# Builds companion.s + caller.s with locked sbpf 0.2.2 (src/<stem>/<stem>.s → deploy).
# Does NOT mint proof-forge.output.v1; binds size + SHA-256 of exact ELF bytes.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
harness_dir="$root/runtime-tests/solana/harness"
out_dir="${PROOF_FORGE_HARNESS_OUT:-$root/build/v2/solana-harness}"

die() {
  echo "solana-harness-build: $*" >&2
  exit 1
}

missing() {
  echo "solana-harness-build: $*" >&2
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

if [[ -x /usr/bin/python3 ]]; then
  python_bin=/usr/bin/python3
elif command -v python3 >/dev/null 2>&1; then
  python_bin="$(command -v python3)"
else
  missing "python3 not found"
fi

for stem in companion caller; do
  src="$harness_dir/src/$stem/$stem.s"
  [[ -f "$src" && ! -L "$src" ]] || die "missing regular harness source $src"
done
manifest_path="$harness_dir/manifest.json"
[[ -f "$manifest_path" && ! -L "$manifest_path" ]] || die "missing regular harness manifest"

# Resolve `..` and existing symlink parents before destructive cleanup, then
# require a strict descendant of this worktree's generated build subtree.
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
    raise SystemExit(f"PROOF_FORGE_HARNESS_OUT must be under {build}")
if not relative.parts:
    raise SystemExit("refusing to replace build root")
print(candidate)
PY
)" || die "unsafe PROOF_FORGE_HARNESS_OUT"
rm -rf "$out_dir"
mkdir -p "$out_dir"

echo "solana-harness-build: sbpf=$sbpf_version"
echo "solana-harness-build: building in $harness_dir → $out_dir"

stage_parent="$(dirname "$out_dir")"
mkdir -p "$stage_parent"
stage_dir="$(mktemp -d "$stage_parent/solana-harness-stage.XXXXXX")" || die "create staging dir"
deploy_tmp="$stage_dir/deploy"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT
mkdir -p "$stage_dir/src/caller" "$stage_dir/src/companion"
cp "$harness_dir/src/caller/caller.s" "$stage_dir/src/caller/caller.s"
cp "$harness_dir/src/companion/companion.s" "$stage_dir/src/companion/companion.s"
(
  cd "$stage_dir"
  "$sbpf_bin" build -d deploy
) || die "sbpf build failed"

"$python_bin" -I -S - "$deploy_tmp" "$out_dir" "$manifest_path" <<'PY' || die "bind/hash step failed"
import hashlib
import json
import os
import sys
from pathlib import Path

deploy = Path(sys.argv[1])
out = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])
stems = ("companion", "caller")


def stable_read_regular(path: Path, label: str) -> bytes:
    st = os.lstat(path)
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"{label} is not a regular non-symlink file: {path}")
    if st.st_nlink != 1:
        raise SystemExit(f"{label} must have one link, nlink={st.st_nlink}: {path}")
    data = path.read_bytes()
    st2 = os.lstat(path)
    if (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns) != (
        st2.st_dev, st2.st_ino, st2.st_size, st2.st_mtime_ns
    ):
        raise SystemExit(f"{label} changed during read: {path}")
    if len(data) != st.st_size:
        raise SystemExit(f"{label} size mismatch for {path}")
    return data


manifest_raw = stable_read_regular(manifest_path, "harness manifest")
try:
    manifest = json.loads(manifest_raw)
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"invalid harness manifest: {error}")
if manifest.get("schema") != "proof-forge.solana.cpi-harness.v1":
    raise SystemExit("wrong harness manifest schema")
if manifest.get("issue") != 115 or manifest.get("sbpf") != "0.2.2":
    raise SystemExit("wrong harness issue or sbpf identity")
expected = manifest.get("expectedElfSha256")
sizes = manifest.get("expectedElfSize")
if not isinstance(expected, dict) or set(expected) != set(stems):
    raise SystemExit("expectedElfSha256 must contain exactly companion and caller")
if not isinstance(sizes, dict) or set(sizes) != set(stems):
    raise SystemExit("expectedElfSize must contain exactly companion and caller")

bound = {}
for stem in stems:
    src = deploy / f"{stem}.so"
    data = stable_read_regular(src, f"{stem} ELF")
    if not data.startswith(b"\x7fELF"):
        raise SystemExit(f"not ELF: {src}")
    digest = hashlib.sha256(data).hexdigest()
    size = len(data)
    want_digest = expected[stem]
    want_size = sizes[stem]
    if not isinstance(want_digest, str) or len(want_digest) != 64:
        raise SystemExit(f"invalid expected digest for {stem}")
    if digest != want_digest:
        raise SystemExit(f"ELF sha256 mismatch for {stem}: got {digest} want {want_digest}")
    if type(want_size) is not int or size != want_size:
        raise SystemExit(f"ELF size mismatch for {stem}: got {size} want {want_size}")
    bound[stem] = (data, digest, size)
    print(f"solana-harness-build: {stem}.so size={size} sha256={digest}")

for stem in stems:
    data, digest, size = bound[stem]
    (out / f"{stem}.so").write_bytes(data)
    (out / f"{stem}.so.sha256").write_text(digest + "\n")
    (out / f"{stem}.so.size").write_text(f"{size}\n")
    print(f"solana-harness-build: verified expected hash for {stem}")
PY

echo "solana-harness-build: ok → $out_dir"
