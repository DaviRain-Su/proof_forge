#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

SCHEMA_FILES=(
  "ProofForge/IR/Contract.lean"
  "ProofForge/Contract/Spec.lean"
)
CLASSIFICATION_FILE="ProofForge/IR/Legacy/Classification.lean"

usage() {
  echo "usage: $0 [--base-ref REF]" >&2
}

base_ref=${LEGACY_FREEZE_BASE:-}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-ref)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      base_ref=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [ -z "$base_ref" ]; then
  if git rev-parse --verify --quiet origin/main^{commit} >/dev/null; then
    base_ref=origin/main
  elif git rev-parse --verify --quiet HEAD^ >/dev/null; then
    base_ref=HEAD^
  else
    base_ref=$(git hash-object -t tree /dev/null)
  fi
fi

empty_tree=$(git hash-object -t tree /dev/null)
if [ "$base_ref" = "$empty_tree" ]; then
  base_commit=$empty_tree
elif ! git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null; then
  echo "legacy-freeze: unknown base ref: $base_ref" >&2
  exit 2
else
  base_commit=$(git merge-base "$base_ref" HEAD || git rev-parse "${base_ref}^{commit}")
fi

# Hash source after removing whitespace. This intentionally treats formatting
# changes as no change, so whitespace-only edits cannot satisfy the requirement
# for a substantive classification update.
normalized_base_hash() {
  local file=$1
  if git cat-file -e "$base_commit:$file" 2>/dev/null; then
    git show "$base_commit:$file" | LC_ALL=C tr -d '[:space:]' | git hash-object --stdin
  else
    echo "<missing>"
  fi
}

normalized_worktree_hash() {
  local file=$1
  if [ -f "$file" ]; then
    LC_ALL=C tr -d '[:space:]' < "$file" | git hash-object --stdin
  else
    echo "<missing>"
  fi
}

changed_schema_files=()
for file in "${SCHEMA_FILES[@]}"; do
  if [ "$(normalized_base_hash "$file")" != "$(normalized_worktree_hash "$file")" ]; then
    changed_schema_files+=("$file")
  fi
done

if [ "${#changed_schema_files[@]}" -gt 0 ] &&
    [ "$(normalized_base_hash "$CLASSIFICATION_FILE")" = "$(normalized_worktree_hash "$CLASSIFICATION_FILE")" ]; then
  echo "legacy-freeze: legacy schema changed without a substantive classification update" >&2
  printf '  %s\n' "${changed_schema_files[@]}" >&2
  echo "legacy-freeze: base=$base_commit (override with LEGACY_FREEZE_BASE or --base-ref)" >&2
  exit 1
fi

echo "legacy-freeze: ok (base=$base_commit)"
