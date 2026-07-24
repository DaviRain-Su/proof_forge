#!/usr/bin/env bash
set -euo pipefail

root="${ROOT_WORKTREE_PATH:-$PWD}"
toolchain="$(tr -d '[:space:]' < "$root/lean-toolchain")"

if command -v elan >/dev/null 2>&1; then
  elan toolchain install "$toolchain"
fi

if command -v lake >/dev/null 2>&1; then
  lake update
  lake build ProofForgeV2 proof_forge_next
else
  echo "lake not found; install elan/lean toolchain before building this worktree" >&2
  exit 1
fi

echo "ProofForge V2 worktree setup complete."
