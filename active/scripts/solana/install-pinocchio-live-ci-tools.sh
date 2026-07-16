#!/usr/bin/env bash
# Install the toolchain required by the Solana Pinocchio live-equivalence CI job.
#
# The live suite needs three layers:
#   - Agave/Solana CLI, including solana-keygen and cargo-build-sbf
#   - Solana SBF rustc/platform-tools for Pinocchio reference builds
#   - Surfpool and blueshift sbpf for local deployment plus generated asm builds
set -euo pipefail

AGAVE_RELEASE="${PROOF_FORGE_AGAVE_RELEASE:-v3.1.12}"
SBF_TOOLS_VERSION="${PROOF_FORGE_SBF_TOOLS_VERSION:-v1.52}"
SBF_RUSTUP_TOOLCHAIN="${PROOF_FORGE_PINOCCHIO_RUSTUP_TOOLCHAIN:-1.89.0-sbpf-solana-v1.52}"
SURFPOOL_REPO="${PROOF_FORGE_SURFPOOL_REPO:-https://github.com/txtx/surfpool.git}"
SURFPOOL_TAG="${PROOF_FORGE_SURFPOOL_TAG:-v0.10.8}"
SBPF_REPO="${PROOF_FORGE_SBPF_REPO:-https://github.com/blueshift-gg/sbpf.git}"
SBPF_REV="${PROOF_FORGE_SBPF_REV:-d835bc6e638e4f55b88f31a31bbc92e3a2e0a5ba}"
SBPF_VERSION="${PROOF_FORGE_SBPF_VERSION:-0.2.2}"

case "${1:-}" in
  "")
    ;;
  -h|--help)
    cat <<EOF
Usage: scripts/solana/install-pinocchio-live-ci-tools.sh

Installs or checks the toolchain required by:
  just solana-pinocchio-live-equivalence

Configuration is read from PROOF_FORGE_* environment variables.
EOF
    exit 0
    ;;
  *)
    echo "unexpected argument: $1" >&2
    exit 2
    ;;
esac

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

tool_version_contains() {
  local tool="$1"
  local expected="$2"
  local version_output
  command -v "$tool" >/dev/null 2>&1 || return 1
  version_output="$("$tool" --version 2>&1 || true)"
  printf '%s\n' "$version_output" | grep -F "$expected" >/dev/null
}

print_tool_version() {
  local tool="$1"
  "$tool" --version 2>&1 || true
}

append_path() {
  local dir="$1"
  export PATH="$dir:$PATH"
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$dir" >> "$GITHUB_PATH"
  fi
}

need_cmd curl
need_cmd cargo
need_cmd rustup

append_path "$HOME/.cargo/bin"

echo "=== install/check Agave ${AGAVE_RELEASE} ==="
if ! tool_version_contains solana "${AGAVE_RELEASE#v}"; then
  curl -sSfL "https://release.anza.xyz/${AGAVE_RELEASE}/install" | sh
fi
AGAVE_BIN="$HOME/.local/share/solana/install/active_release/bin"
append_path "$AGAVE_BIN"
solana --version
solana-keygen --version
cargo-build-sbf --version

echo "=== install/check Solana SBF platform-tools ${SBF_TOOLS_VERSION} ==="
SBF_CACHE_DIR="$HOME/.cache/solana/$SBF_TOOLS_VERSION"
SBF_SDK_DIR="$AGAVE_BIN/platform-tools-sdk/sbf"
SBF_RUST_DIR="$SBF_SDK_DIR/dependencies/platform-tools/rust"
SBF_RUSTUP_LINK="$HOME/.rustup/toolchains/$SBF_RUSTUP_TOOLCHAIN"
if [ -L "$SBF_RUSTUP_LINK" ] && [ ! -e "$SBF_RUSTUP_LINK" ]; then
  echo "Removing broken SBF rustup toolchain link: $SBF_RUSTUP_LINK"
  rm "$SBF_RUSTUP_LINK"
fi
if [ -x "$SBF_RUST_DIR/bin/rustc" ] && [ -d "$SBF_CACHE_DIR/platform-tools" ]; then
  echo "SBF platform-tools already present: $SBF_RUST_DIR, $SBF_CACHE_DIR"
else
  echo "Installing SBF rustup toolchain/cache: $SBF_RUSTUP_TOOLCHAIN, $SBF_CACHE_DIR"
  if command -v timeout >/dev/null 2>&1; then
    timeout 900 cargo-build-sbf --install-only --force-tools-install --tools-version "$SBF_TOOLS_VERSION"
  else
    cargo-build-sbf --install-only --force-tools-install --tools-version "$SBF_TOOLS_VERSION"
  fi
fi
if [ ! -x "$SBF_RUST_DIR/bin/rustc" ]; then
  echo "SBF rustc missing after install: $SBF_RUST_DIR/bin/rustc" >&2
  exit 1
fi
"$SBF_RUST_DIR/bin/rustc" --version
if [ -x "$SBF_RUST_DIR/bin/cargo" ]; then
  "$SBF_RUST_DIR/bin/cargo" --version
fi

echo "=== install/check sbpf ${SBPF_VERSION} ==="
if ! tool_version_contains sbpf "$SBPF_VERSION"; then
  cargo install --git "$SBPF_REPO" --rev "$SBPF_REV" --locked --force sbpf
fi
tool_version_contains sbpf "$SBPF_VERSION" || {
  print_tool_version sbpf
  echo "installed sbpf version does not contain expected version: $SBPF_VERSION" >&2
  exit 1
}
print_tool_version sbpf

echo "=== install/check Surfpool ${SURFPOOL_TAG} ==="
if ! tool_version_contains surfpool "${SURFPOOL_TAG#v}"; then
  cargo install --git "$SURFPOOL_REPO" --tag "$SURFPOOL_TAG" --locked --force surfpool-cli
fi
tool_version_contains surfpool "${SURFPOOL_TAG#v}" || {
  print_tool_version surfpool
  echo "installed Surfpool version does not contain expected version: ${SURFPOOL_TAG#v}" >&2
  exit 1
}
print_tool_version surfpool

echo "=== Node/npm versions ==="
need_cmd node
need_cmd npm
node --version
npm --version

echo "Solana Pinocchio live CI tools: ok"
