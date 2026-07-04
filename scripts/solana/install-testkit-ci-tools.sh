#!/usr/bin/env bash
# Install the minimal Solana toolchain required by `just testkit`.
#
# The unified testkit Solana harness needs:
#   - solana-keygen (from Agave CLI) to scaffold sbpf projects
#   - blueshift sbpf to assemble emitted assembly into ELF artifacts
set -euo pipefail

AGAVE_RELEASE="${PROOF_FORGE_AGAVE_RELEASE:-v3.1.12}"
SBPF_REPO="${PROOF_FORGE_SBPF_REPO:-https://github.com/blueshift-gg/sbpf.git}"
SBPF_REV="${PROOF_FORGE_SBPF_REV:-d835bc6e638e4f55b88f31a31bbc92e3a2e0a5ba}"
SBPF_VERSION="${PROOF_FORGE_SBPF_VERSION:-0.2.2}"

case "${1:-}" in
  "")
    ;;
  -h|--help)
    cat <<EOF
Usage: scripts/solana/install-testkit-ci-tools.sh

Installs or checks the toolchain required by:
  just testkit

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

append_path "$HOME/.cargo/bin"

echo "=== install/check Agave ${AGAVE_RELEASE} (solana-keygen) ==="
if ! tool_version_contains solana-keygen "${AGAVE_RELEASE#v}"; then
  curl -sSfL "https://release.anza.xyz/${AGAVE_RELEASE}/install" | sh
fi
AGAVE_BIN="$HOME/.local/share/solana/install/active_release/bin"
append_path "$AGAVE_BIN"
solana-keygen --version

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

echo "testkit-solana-tools: ok"
