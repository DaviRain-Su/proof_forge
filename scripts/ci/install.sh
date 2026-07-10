#!/usr/bin/env bash
set -euo pipefail

# Install proof-forge from a GitHub Release.
#
# Usage:
#   scripts/ci/install.sh [VERSION]
#
# Environment:
#   PROOF_FORGE_VERSION        version to install (default: latest GitHub release)
#   PROOF_FORGE_REPO           GitHub owner/repo (default: davirain/proof_forge)
#   PROOF_FORGE_INSTALL_ROOT   parent directory (default: $HOME/.proof-forge)
#   PROOF_FORGE_BIN_DIR        symlink directory (default: $HOME/.local/bin)

VERSION="${1:-${PROOF_FORGE_VERSION:-latest}}"
REPO="${PROOF_FORGE_REPO:-davirain/proof_forge}"
INSTALL_ROOT="${PROOF_FORGE_INSTALL_ROOT:-$HOME/.proof-forge}"
BIN_DIR="${PROOF_FORGE_BIN_DIR:-$HOME/.local/bin}"

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)
    os_tag=linux
    ;;
  Darwin)
    os_tag=macos
    ;;
  *)
    echo "install.sh: unsupported OS: $OS" >&2
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64|amd64)
    arch_tag=x86_64
    ;;
  arm64|aarch64)
    arch_tag=arm64
    ;;
  *)
    echo "install.sh: unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

tarball_name="proof-forge-${VERSION}-${os_tag}-${arch_tag}.tar.gz"

if [ "$VERSION" = "latest" ]; then
  URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep "browser_download_url" \
    | grep "proof-forge-.*-${os_tag}-${arch_tag}.tar.gz" \
    | head -n1 \
    | cut -d '"' -f4)"
  if [ -z "$URL" ]; then
    echo "install.sh: could not find latest release asset for ${os_tag}-${arch_tag}" >&2
    exit 1
  fi
  # Latest installs cannot be verified against a pinned checksum.
else
  URL="https://github.com/${REPO}/releases/download/${VERSION}/${tarball_name}"
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "install.sh: downloading proof-forge ${VERSION} for ${os_tag}-${arch_tag}"
curl -fsSL -o "$TMPDIR/proof-forge.tar.gz" "$URL"

# Optional checksum verification for pinned-version installs.
if [ "$VERSION" != "latest" ]; then
  CHECKSUMS_URL="https://github.com/${REPO}/releases/download/${VERSION}/checksums.txt"
  if curl -fsSL -o "$TMPDIR/checksums.txt" "$CHECKSUMS_URL" 2>/dev/null; then
    (cd "$TMPDIR" && grep "^.*  ${tarball_name}$" checksums.txt | sha256sum -c -)
  fi
fi

INSTALL_DIR="$INSTALL_ROOT/$VERSION"
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMPDIR/proof-forge.tar.gz" -C "$INSTALL_DIR"

mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/proof-forge" "$BIN_DIR/proof-forge"

echo "install.sh: installed proof-forge ${VERSION} to ${INSTALL_DIR}/proof-forge"
echo "install.sh: symlinked ${BIN_DIR}/proof-forge"
