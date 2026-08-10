#!/usr/bin/env bash
# ProofForge external-author installer (engineering-dist bundle).
# Authority: docs/product/14-external-author-mvp.md · ADR-0040
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/DaviRain-Su/proof_forge/main/scripts/install.sh | sh
#   PROOF_FORGE_BUNDLE_URL=... PROOF_FORGE_BUNDLE_SHA256=... sh install.sh
#   sh install.sh --from /path/to/proof-forge-bundle-*.tar.gz
#
# Default prefix: ~/.local/proof-forge/<version>
# Adds bin/ to PATH instructions (does not silently rewrite shell rc unless --yes-path).
set -euo pipefail

PREFIX="proof-forge-install"
REPO_DEFAULT="https://github.com/DaviRain-Su/proof_forge"
CHANNEL="engineering-dist"

die() { echo "${PREFIX}: $*" >&2; exit 1; }
info() { echo "${PREFIX}: $*"; }

FROM_LOCAL=""
YES_PATH=0
PREFIX_DIR="${PROOF_FORGE_PREFIX:-$HOME/.local/proof-forge}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      [[ $# -ge 2 ]] || die "--from needs a path"
      FROM_LOCAL="$2"
      shift 2
      ;;
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix needs a path"
      PREFIX_DIR="$2"
      shift 2
      ;;
    --yes-path) YES_PATH=1; shift ;;
    -h|--help)
      cat <<'EOF'
usage: install.sh [--from TARBALL] [--prefix DIR] [--yes-path]

  Install proof-forge-bundle (pf + proof-forge-next) for external authors.

  Env:
    PROOF_FORGE_BUNDLE_URL      direct tarball URL (required if no --from and no release discovery)
    PROOF_FORGE_BUNDLE_SHA256   expected sha256 of tarball
    PROOF_FORGE_PREFIX          install root (default: ~/.local/proof-forge)
    PROOF_FORGE_VERSION         version pin (optional; used in default URL layout)
EOF
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

platform_id() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo "linux-x86_64" ;;
    Darwin-arm64) echo "darwin-arm64" ;;
    Darwin-x86_64) echo "darwin-x86_64" ;;
    *) return 1 ;;
  esac
}

plat="$(platform_id)" || die "unsupported host $(uname -s)-$(uname -m)"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/pf-install.XXXXXX")"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

archive=""
if [[ -n "$FROM_LOCAL" ]]; then
  [[ -f "$FROM_LOCAL" ]] || die "not a file: $FROM_LOCAL"
  archive="$FROM_LOCAL"
else
  url="${PROOF_FORGE_BUNDLE_URL:-}"
  if [[ -z "$url" ]]; then
    ver="${PROOF_FORGE_VERSION:-}"
    if [[ -z "$ver" ]]; then
      die "set PROOF_FORGE_BUNDLE_URL or PROOF_FORGE_VERSION, or pass --from TARBALL
example:
  PROOF_FORGE_BUNDLE_URL=${REPO_DEFAULT}/releases/download/v0.1.1/proof-forge-bundle-0.1.1-${plat}.tar.gz \\
  PROOF_FORGE_BUNDLE_SHA256=... sh install.sh"
    fi
    url="${REPO_DEFAULT}/releases/download/v${ver}/proof-forge-bundle-${ver}-${plat}.tar.gz"
  fi
  info "downloading $url"
  archive="$tmpdir/bundle.tar.gz"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$archive"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$archive" "$url"
  else
    die "need curl or wget"
  fi
fi

if [[ -n "${PROOF_FORGE_BUNDLE_SHA256:-}" ]]; then
  info "verifying sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "$archive" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    got="$(shasum -a 256 "$archive" | awk '{print $1}')"
  else
    die "need sha256sum or shasum for checksum"
  fi
  [[ "$got" == "$PROOF_FORGE_BUNDLE_SHA256" ]] \
    || die "sha256 mismatch: got $got want $PROOF_FORGE_BUNDLE_SHA256"
else
  info "WARNING: PROOF_FORGE_BUNDLE_SHA256 unset — skipping digest verify (not for production)"
fi

info "extracting"
tar -xzf "$archive" -C "$tmpdir"
stage="$(find "$tmpdir" -maxdepth 1 -type d -name 'proof-forge-bundle-*' | head -1)"
[[ -n "$stage" && -d "$stage" ]] || die "archive missing proof-forge-bundle-* root"
[[ -x "$stage/bin/pf" ]] || die "bundle missing bin/pf"
[[ -x "$stage/bin/proof-forge-next" ]] || die "bundle missing bin/proof-forge-next"
ver="$(tr -d '[:space:]' <"$stage/VERSION" 2>/dev/null || echo unknown)"

dest="${PREFIX_DIR}/${ver}"
info "installing to $dest"
mkdir -p "$PREFIX_DIR"
rm -rf "$dest"
mkdir -p "$dest"
# portable copy
if command -v rsync >/dev/null 2>&1; then
  rsync -a "$stage"/ "$dest"/
else
  tar -C "$stage" -cf - . | tar -C "$dest" -xf -
fi

current="${PREFIX_DIR}/current"
rm -f "$current"
ln -s "$dest" "$current" 2>/dev/null || {
  # Windows-ish / restricted: fall back to a marker file
  echo "$dest" >"${PREFIX_DIR}/current.path"
}

bin_dir="$dest/bin"
info "installed pf + proof-forge-next ${ver} (${plat}, ${CHANNEL})"
cat <<EOF

Next:
  export PATH="${bin_dir}:\$PATH"
  export PROOF_FORGE_CLI="${bin_dir}/proof-forge-next"
  export PROOF_FORGE_ROOT="${dest}"
  # default host mode is dev (no hermetic host pin)
  pf version
  pf -y setup --target evm
  pf new hello --target evm && cd hello && pf build

EOF

if [[ "$YES_PATH" -eq 1 ]]; then
  rc=""
  if [[ -n "${SHELL:-}" && "${SHELL}" == *zsh* ]]; then
    rc="$HOME/.zshrc"
  elif [[ -n "${SHELL:-}" && "${SHELL}" == *bash* ]]; then
    rc="$HOME/.bashrc"
  fi
  if [[ -n "$rc" ]]; then
    marker="# proof-forge-bundle PATH (${ver})"
    if ! grep -qF "$marker" "$rc" 2>/dev/null; then
      {
        echo ""
        echo "$marker"
        echo "export PATH=\"${bin_dir}:\$PATH\""
        echo "export PROOF_FORGE_CLI=\"${bin_dir}/proof-forge-next\""
        echo "export PROOF_FORGE_ROOT=\"${dest}\""
      } >>"$rc"
      info "appended PATH exports to $rc"
    fi
  fi
fi

exit 0
