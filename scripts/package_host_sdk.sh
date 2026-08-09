#!/usr/bin/env bash
# Package Host SDK (Python) as wheel + sdist (REL-HOST-0).
# Authority: docs/product/05-distribution-and-packages.md
# Channel: engineering-dist only. Not formal Stage-0. Not a second compiler.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="package-host-sdk"
OUT_DIR="${OUT_DIR:-$root/dist}"
SDK_DIR="$root/tools/sdk"

die() { echo "${PREFIX}: $*" >&2; exit 1; }
bad() { echo "${PREFIX}: $*" >&2; exit 2; }

[[ -f "$root/VERSION" ]] || bad "missing VERSION"
VERSION="$(tr -d '[:space:]' <"$root/VERSION")"
[[ -n "$VERSION" ]] || bad "empty VERSION"
[[ -f "$SDK_DIR/proof_forge_sdk.py" ]] || bad "missing tools/sdk/proof_forge_sdk.py"
[[ -f "$SDK_DIR/pyproject.toml" ]] || bad "missing tools/sdk/pyproject.toml"

mkdir -p "$OUT_DIR"
work="$(mktemp -d "${TMPDIR:-/tmp}/pf-host-sdk.XXXXXX")"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

# Isolated build tree so we can rewrite version without dirtying the monorepo.
cp -a "$SDK_DIR/proof_forge_sdk.py" "$work/"
cp -a "$SDK_DIR/README.md" "$work/"
# Rewrite version field in pyproject to match VERSION.
python3 - <<PY
from pathlib import Path
import re
src = Path("$SDK_DIR/pyproject.toml").read_text(encoding="utf-8")
ver = "${VERSION}"
out = re.sub(r'(?m)^version\s*=\s*"[^"]*"\s*$', f'version = "{ver}"', src, count=1)
Path("$work/pyproject.toml").write_text(out, encoding="utf-8")
if f'version = "{ver}"' not in out:
    raise SystemExit("failed to pin version in pyproject.toml")
PY

echo "${PREFIX}: building wheel+sdist version=${VERSION}"
# Note: monorepo has a top-level `build/` directory that can shadow PyPI's
# `build` package on sys.path — always install pypa build into a temp venv.
venv="$work/.venv"
/usr/bin/python3 -m venv "$venv"
# shellcheck disable=SC1091
source "$venv/bin/activate"
python -m pip install -q --upgrade pip
python -m pip install -q build wheel
(
  cd "$work"
  python -m build --outdir "$OUT_DIR" .
)
deactivate

wheel="$(ls -1 "$OUT_DIR"/proof_forge_sdk-"${VERSION}"-*.whl 2>/dev/null | head -1 || true)"
# setuptools normalizes name with underscores in wheel filename for proof-forge-sdk
if [[ -z "$wheel" ]]; then
  wheel="$(ls -1 "$OUT_DIR"/proof_forge_sdk-"${VERSION}"*.whl 2>/dev/null | head -1 || true)"
fi
if [[ -z "$wheel" ]]; then
  wheel="$(ls -1 "$OUT_DIR"/*"${VERSION}"*.whl 2>/dev/null | head -1 || true)"
fi
[[ -n "$wheel" && -f "$wheel" ]] || die "wheel not produced under $OUT_DIR"
sdist="$(ls -1 "$OUT_DIR"/proof_forge_sdk-"${VERSION}".tar.gz 2>/dev/null | head -1 || true)"
if [[ -z "$sdist" ]]; then
  sdist="$(ls -1 "$OUT_DIR"/proof-forge-sdk-"${VERSION}".tar.gz 2>/dev/null | head -1 || true)"
fi

# Checksums
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$OUT_DIR" && sha256sum "$(basename "$wheel")" >"$(basename "$wheel").sha256")
  [[ -n "$sdist" && -f "$sdist" ]] && \
    (cd "$OUT_DIR" && sha256sum "$(basename "$sdist")" >"$(basename "$sdist").sha256")
elif command -v shasum >/dev/null 2>&1; then
  (cd "$OUT_DIR" && shasum -a 256 "$(basename "$wheel")" >"$(basename "$wheel").sha256")
  [[ -n "$sdist" && -f "$sdist" ]] && \
    (cd "$OUT_DIR" && shasum -a 256 "$(basename "$sdist")" >"$(basename "$sdist").sha256")
fi

# Import smoke from wheel contents via unzip module path (no install required).
echo "${PREFIX}: import smoke"
/usr/bin/python3 - <<PY
import importlib.util
import sys
from pathlib import Path
# Ensure module file is importable from work copy
spec = importlib.util.spec_from_file_location(
    "proof_forge_sdk", Path("$work/proof_forge_sdk.py")
)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules["proof_forge_sdk"] = mod
spec.loader.exec_module(mod)
assert hasattr(mod, "ProofForgeClient")
print("ok: ProofForgeClient present")
PY

echo "${PREFIX}: wheel=$wheel"
[[ -n "$sdist" ]] && echo "${PREFIX}: sdist=$sdist"
echo "${PREFIX}: PACKAGED-OK version=${VERSION} channel=engineering-dist"
echo "${PREFIX}: NOT formal Stage-0 / hermetic / mainnet"
exit 0
