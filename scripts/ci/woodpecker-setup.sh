#!/usr/bin/env bash
# Install the toolchain required by `just check` on Codeberg Woodpecker runners.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.elan/bin:$HOME/.cargo/bin:$HOME/.foundry/bin:$HOME/.local/share/solana/install/active_release/bin:/usr/local/bin:$PATH"

apt-get update
apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  pkg-config \
  libssl-dev \
  python3 \
  wabt

echo "=== install just ==="
curl --proto '=https' --tlsv1.2 -sSfL https://just.systems/install.sh | bash -s -- --to /usr/local/bin --tag 1.48.0

echo "=== install Lean ==="
toolchain="$(cat lean-toolchain)"
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -o /tmp/elan-init.sh
sh /tmp/elan-init.sh -y --default-toolchain "$toolchain"
export PATH="$HOME/.elan/bin:$PATH"
elan toolchain install "$toolchain"

echo "=== install Foundry ==="
curl -L https://foundry.paradigm.xyz | bash
export PATH="$HOME/.foundry/bin:$PATH"
foundryup

echo "=== install solc ==="
curl -L -o /tmp/solc-static-linux https://github.com/ethereum/solidity/releases/download/v0.8.30/solc-static-linux
chmod +x /tmp/solc-static-linux
install -m 0755 /tmp/solc-static-linux /usr/local/bin/solc

echo "=== install Rust ==="
curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.91.0 --profile minimal
export PATH="$HOME/.cargo/bin:$PATH"

echo "=== install Solana testkit tools ==="
scripts/solana/install-testkit-ci-tools.sh

echo "=== tool versions ==="
lean --version
lake --version
forge --version
cast --version
solc --version
rustc --version
cargo --version
just --version
wat2wasm --version