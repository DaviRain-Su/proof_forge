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

CURL_USER_AGENT="User-Agent: proof-forge-installer"

if [ "$VERSION" = "latest" ]; then
  # The pipeline may exit non-zero when no matching asset is found; capture the
  # result so the diagnostic below is reachable under set -e.
  URL="$(curl -fsSL -H "$CURL_USER_AGENT" "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
    | grep "browser_download_url" \
    | grep "proof-forge-.*-${os_tag}-${arch_tag}.tar.gz" \
    | head -n1 \
    | cut -d '"' -f4)" || URL=""
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
curl -fsSL -H "$CURL_USER_AGENT" -o "$TMPDIR/${tarball_name}" "$URL"

# Optional checksum verification for pinned-version installs.
if [ "$VERSION" != "latest" ]; then
  CHECKSUMS_URL="https://github.com/${REPO}/releases/download/${VERSION}/checksums.txt"
  if curl -fsSL -H "$CURL_USER_AGENT" -o "$TMPDIR/checksums.txt" "$CHECKSUMS_URL" 2>/dev/null; then
    # Prefer GNU sha256sum; fall back to macOS shasum.
    if command -v sha256sum >/dev/null 2>&1; then
      sha_cmd=(sha256sum -c -)
    elif command -v shasum >/dev/null 2>&1; then
      sha_cmd=(shasum -a 256 -c -)
    else
      echo "install.sh: no sha256 checksum utility found (sha256sum or shasum)" >&2
      exit 1
    fi
    checksum_line="$(cd "$TMPDIR" && grep -E "^[a-f0-9]+  ${tarball_name}$" checksums.txt || true)"
    if [ -z "$checksum_line" ]; then
      echo "install.sh: no checksum found for ${tarball_name}" >&2
      exit 1
    fi
    if ! (cd "$TMPDIR" && printf '%s\n' "$checksum_line" | "${sha_cmd[@]}"); then
      echo "install.sh: checksum verification failed for ${tarball_name}" >&2
      exit 1
    fi
  fi
fi

INSTALL_DIR="$INSTALL_ROOT/$VERSION"
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMPDIR/${tarball_name}" -C "$INSTALL_DIR"

mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/proof-forge" "$BIN_DIR/proof-forge"

echo "install.sh: installed proof-forge ${VERSION} to ${INSTALL_DIR}/proof-forge"
echo "install.sh: symlinked ${BIN_DIR}/proof-forge"
