#!/usr/bin/env bash
set -euo pipefail

# Check that stable build/evm artifact paths exist for a Foundry workspace.
#
# Usage:
#   scripts/evm/prepare-foundry-workspace.sh [PROJECT_ROOT]
#
# Defaults PROJECT_ROOT to the repository root. When invoked from an init
# project, pass the project directory that contains build/evm and foundry/.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="${1:-$ROOT}"

ARTIFACT_DIR="$PROJECT/build/evm"
FORGE_DIR="$PROJECT/foundry"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "prepare-foundry-workspace: missing required artifact: $path" >&2
    exit 1
  fi
}

if [[ ! -d "$FORGE_DIR" ]]; then
  echo "prepare-foundry-workspace: missing Foundry workspace at $FORGE_DIR" >&2
  exit 1
fi

require_file "$ARTIFACT_DIR/Counter.bin"
require_file "$ARTIFACT_DIR/Counter.init.bin"
require_file "$FORGE_DIR/foundry.toml"
require_file "$FORGE_DIR/test/Counter.t.sol"
require_file "$FORGE_DIR/script/DeployCounter.s.sol"

echo "prepare-foundry-workspace: ok ($ARTIFACT_DIR -> $FORGE_DIR)"
