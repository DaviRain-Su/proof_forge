#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

CONTRACT_FILE="ProofForge/IR/Contract.lean"
CLASSIFICATION_FILE="ProofForge/IR/Legacy/Classification.lean"

# Detect added constructor lines (lines beginning with optional whitespace and a
# pipe `|`) in the current working-tree or staged diff for IR.Contract.lean.
new_constructor_lines=$({
  git diff -- "$CONTRACT_FILE" || true
  git diff --cached -- "$CONTRACT_FILE" || true
} | grep -E '^\+[[:space:]]*\|' || true)

if [ -n "$new_constructor_lines" ]; then
  changed_files=$({
    git diff --name-only || true
    git diff --cached --name-only || true
  })
  if ! grep -q "$CLASSIFICATION_FILE" <<< "$changed_files"; then
    echo "legacy-freeze: IR.Contract changed without classification update"
    exit 1
  fi
fi

echo "legacy-freeze: ok"
