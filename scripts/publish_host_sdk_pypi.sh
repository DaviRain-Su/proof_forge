#!/usr/bin/env bash
# Publish Host SDK wheel/sdist to PyPI or TestPyPI (REL-HOST-1).
# Authority: docs/product/05-distribution-and-packages.md
#
# Engineering-dist only. Not formal Stage-0.
#
# Usage:
#   just package-host-sdk
#   just publish-host-sdk-pypi                 # real PyPI (needs trusted publisher or token)
#   just publish-host-sdk-pypi --repository testpypi
#   just publish-host-sdk-pypi --dry-run       # twine check only
#
# Auth (pick one):
#   - CI: OIDC Trusted Publishing (preferred; no long-lived token)
#   - Local: TWINE_USERNAME=__token__ TWINE_PASSWORD=pypi-...
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="publish-host-sdk-pypi"
OUT_DIR="${OUT_DIR:-$root/dist}"
REPOSITORY="pypi"
DRY_RUN=0

usage() {
  cat <<'EOF'
usage: publish_host_sdk_pypi.sh [--repository pypi|testpypi] [--dry-run] [--out DIR]

  Publish already-built Host SDK artifacts from dist/ to PyPI.

  Requires wheel (+ preferably sdist) matching VERSION.
  --dry-run   only run twine check (no upload)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --repository needs value" >&2; exit 2; }
      REPOSITORY="$2"
      shift 2
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    --out)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --out needs value" >&2; exit 2; }
      OUT_DIR="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "${PREFIX}: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

die() { echo "${PREFIX}: $*" >&2; exit 1; }
bad() { echo "${PREFIX}: $*" >&2; exit 2; }

[[ -f "$root/VERSION" ]] || bad "missing VERSION"
VERSION="$(tr -d '[:space:]' <"$root/VERSION")"
[[ -n "$VERSION" ]] || bad "empty VERSION"

case "$REPOSITORY" in
  pypi|testpypi) ;;
  *) bad "repository must be pypi or testpypi" ;;
esac

mkdir -p "$OUT_DIR"
# Prefer existing artifacts; otherwise package first.
wheel="$(ls -1 "$OUT_DIR"/proof_forge_sdk-"${VERSION}"-*.whl 2>/dev/null | head -1 || true)"
if [[ -z "$wheel" ]]; then
  echo "${PREFIX}: no wheel for ${VERSION}; running package-host-sdk"
  OUT_DIR="$OUT_DIR" bash "$root/scripts/package_host_sdk.sh"
  wheel="$(ls -1 "$OUT_DIR"/proof_forge_sdk-"${VERSION}"-*.whl 2>/dev/null | head -1 || true)"
fi
[[ -n "$wheel" && -f "$wheel" ]] || die "missing wheel for version ${VERSION}"

sdist="$(ls -1 "$OUT_DIR"/proof_forge_sdk-"${VERSION}".tar.gz 2>/dev/null | head -1 || true)"
files=("$wheel")
if [[ -n "$sdist" && -f "$sdist" ]]; then
  files+=("$sdist")
fi

echo "${PREFIX}: artifacts:"
for f in "${files[@]}"; do
  echo "  - $f"
done

venv="$(mktemp -d "${TMPDIR:-/tmp}/pf-twine.XXXXXX")"
cleanup() { rm -rf "$venv"; }
trap cleanup EXIT
/usr/bin/python3 -m venv "$venv"
# shellcheck disable=SC1091
source "$venv/bin/activate"
python -m pip install -q --upgrade pip
python -m pip install -q twine

echo "${PREFIX}: twine check"
twine check "${files[@]}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "${PREFIX}: DRY-RUN-OK (twine check only; not uploaded)"
  deactivate
  exit 0
fi

echo "${PREFIX}: uploading to ${REPOSITORY}"
# Trusted Publishing in CI sets OIDC; twine/pypi-publish uses that.
# Local: require token env.
if [[ -z "${TWINE_USERNAME:-}" && -z "${TWINE_PASSWORD:-}" && -z "${PYPI_API_TOKEN:-}" && -z "${TESTPYPI_API_TOKEN:-}" ]]; then
  if [[ -z "${CI:-}" ]]; then
    die "set TWINE_USERNAME=__token__ and TWINE_PASSWORD=pypi-... (or PYPI_API_TOKEN / TESTPYPI_API_TOKEN)"
  fi
fi

if [[ -n "${PYPI_API_TOKEN:-}" && "$REPOSITORY" == "pypi" && -z "${TWINE_PASSWORD:-}" ]]; then
  export TWINE_USERNAME="__token__"
  export TWINE_PASSWORD="$PYPI_API_TOKEN"
fi
if [[ -n "${TESTPYPI_API_TOKEN:-}" && "$REPOSITORY" == "testpypi" && -z "${TWINE_PASSWORD:-}" ]]; then
  export TWINE_USERNAME="__token__"
  export TWINE_PASSWORD="$TESTPYPI_API_TOKEN"
fi

if [[ "$REPOSITORY" == "testpypi" ]]; then
  twine upload --repository testpypi --non-interactive "${files[@]}"
else
  twine upload --repository pypi --non-interactive "${files[@]}"
fi

echo "${PREFIX}: PUBLISHED-OK repository=${REPOSITORY} version=${VERSION}"
echo "${PREFIX}: channel=engineering-dist (not formal Stage-0)"
deactivate
exit 0
