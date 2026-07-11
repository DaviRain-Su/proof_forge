#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")

SCHEMA_FILES=(
  "ProofForge/IR/Contract.lean"
  "ProofForge/Contract/Spec.lean"
)
CLASSIFICATION_FILE="ProofForge/IR/Legacy/Classification.lean"

usage() {
  echo "usage: $0 [--base-ref REF] [--self-test]" >&2
}

base_ref=${LEGACY_FREEZE_BASE:-}
self_test=false
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
    --self-test)
      self_test=true
      shift
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

run_self_tests() {
  local temp_root source_repo shallow_repo
  temp_root=$(mktemp -d "${TMPDIR:-/tmp}/legacy-freeze.XXXXXX")
  trap "rm -rf '$temp_root'" EXIT
  source_repo="$temp_root/source"
  shallow_repo="$temp_root/shallow"

  git init -q -b main "$source_repo"
  git -C "$source_repo" config user.name "legacy-freeze-test"
  git -C "$source_repo" config user.email "legacy-freeze-test@example.invalid"
  mkdir -p "$source_repo/ProofForge/IR/Legacy" "$source_repo/ProofForge/Contract"
  printf '%s\n' 'inductive LegacySchema where | original' > "$source_repo/ProofForge/IR/Contract.lean"
  printf '%s\n' 'structure LegacySpec where' '  name : String' > "$source_repo/ProofForge/Contract/Spec.lean"
  printf '%s\n' 'def classification := #["original"]' > "$source_repo/$CLASSIFICATION_FILE"
  git -C "$source_repo" add .
  git -C "$source_repo" commit -q -m base

  if ! (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null); then
    echo "legacy-freeze self-test: clean snapshot should pass" >&2
    return 1
  fi

  printf '%s\n' '-- schema-only worktree edit' >> "$source_repo/ProofForge/IR/Contract.lean"
  if (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null 2>&1); then
    echo "legacy-freeze self-test: schema-only snapshot should fail" >&2
    return 1
  fi
  git -C "$source_repo" restore ProofForge/IR/Contract.lean

  printf '%s\n' '-- paired schema edit' >> "$source_repo/ProofForge/IR/Contract.lean"
  printf '%s\n' '-- paired classification edit' >> "$source_repo/$CLASSIFICATION_FILE"
  if ! (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null); then
    echo "legacy-freeze self-test: paired classification snapshot should pass" >&2
    return 1
  fi
  git -C "$source_repo" restore ProofForge/IR/Contract.lean "$CLASSIFICATION_FILE"

  printf '%s\n' '-- staged schema edit' >> "$source_repo/ProofForge/IR/Contract.lean"
  git -C "$source_repo" add ProofForge/IR/Contract.lean
  printf '%s\n' '-- unstaged classification shadow' >> "$source_repo/$CLASSIFICATION_FILE"
  if (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null 2>&1); then
    echo "legacy-freeze self-test: staged schema shadow should fail" >&2
    return 1
  fi
  git -C "$source_repo" reset -q --hard HEAD

  printf '%s\n' '-- second commit' >> "$source_repo/$CLASSIFICATION_FILE"
  git -C "$source_repo" add "$CLASSIFICATION_FILE"
  git -C "$source_repo" commit -q -m second
  git clone -q --depth 1 --branch main "file://$source_repo" "$shallow_repo"
  git -C "$shallow_repo" remote remove origin
  if (cd "$shallow_repo" && "$SCRIPT_PATH" >/dev/null 2>&1); then
    echo "legacy-freeze self-test: unresolved shallow baseline should fail" >&2
    return 1
  fi

  echo "legacy-freeze self-test: ok"
}

if $self_test; then
  if [ -n "$base_ref" ]; then
    echo "legacy-freeze: --self-test cannot be combined with a base ref" >&2
    exit 2
  fi
  run_self_tests
  exit
fi

if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "legacy-freeze: not inside a Git worktree" >&2
  exit 2
fi
cd "$ROOT"

if ! head_commit=$(git rev-parse --verify HEAD^{commit} 2>/dev/null); then
  echo "legacy-freeze: HEAD does not resolve to a commit" >&2
  exit 2
fi

empty_tree=$(git hash-object -t tree /dev/null)

resolve_merge_base() {
  local candidate=$1 resolved
  if ! git rev-parse --verify --quiet "${candidate}^{commit}" >/dev/null; then
    echo "legacy-freeze: unknown base ref: $candidate" >&2
    return 1
  fi
  if ! resolved=$(git merge-base "$candidate" "$head_commit"); then
    echo "legacy-freeze: base ref has no merge base with HEAD: $candidate" >&2
    return 1
  fi
  printf '%s\n' "$resolved"
}

if [ -n "$base_ref" ]; then
  if ! base_commit=$(resolve_merge_base "$base_ref"); then
    exit 2
  fi
elif git rev-parse --verify --quiet origin/main^{commit} >/dev/null; then
  if ! base_commit=$(resolve_merge_base origin/main); then
    exit 2
  fi
elif git rev-parse --verify --quiet HEAD^ >/dev/null; then
  base_commit=$(git rev-parse HEAD^)
else
  is_shallow=$(git rev-parse --is-shallow-repository)
  parent_count=$(git rev-list --parents -n 1 HEAD | awk '{ print NF - 1 }')
  if [ "$is_shallow" = "true" ]; then
    echo "legacy-freeze: cannot resolve a baseline from a shallow repository" >&2
    exit 2
  elif [ "$parent_count" -ne 0 ]; then
    echo "legacy-freeze: cannot resolve the parent baseline for HEAD" >&2
    exit 2
  fi
  # The empty tree is valid only for a verified, non-shallow root commit.
  base_commit=$empty_tree
fi

WATCHED_FILES=("${SCHEMA_FILES[@]}" "$CLASSIFICATION_FILE")
if [ -n "$(git ls-files --unmerged -- "${WATCHED_FILES[@]}")" ]; then
  echo "legacy-freeze: watched files contain unresolved index stages" >&2
  exit 2
fi

commit_blob() {
  local commit=$1 file=$2
  if [ "$commit" = "$empty_tree" ]; then
    printf '%s\n' '<missing>'
  elif git cat-file -e "$commit:$file" 2>/dev/null; then
    git rev-parse "$commit:$file"
  else
    printf '%s\n' '<missing>'
  fi
}

index_blob() {
  local file=$1
  if git rev-parse --verify --quiet ":0:$file" >/dev/null; then
    git rev-parse ":0:$file"
  else
    printf '%s\n' '<missing>'
  fi
}

worktree_blob() {
  local file=$1
  if [ -f "$file" ]; then
    git hash-object --path="$file" "$file"
  else
    printf '%s\n' '<missing>'
  fi
}

snapshot_blob() {
  local snapshot=$1 file=$2
  case "$snapshot" in
    HEAD) commit_blob "$head_commit" "$file" ;;
    index) index_blob "$file" ;;
    worktree) worktree_blob "$file" ;;
    *)
      echo "legacy-freeze: internal unknown snapshot: $snapshot" >&2
      return 2
      ;;
  esac
}

check_snapshot() {
  local snapshot=$1 file schema_changed=false
  local changed_schema_files=()

  for file in "${SCHEMA_FILES[@]}"; do
    if [ "$(commit_blob "$base_commit" "$file")" != "$(snapshot_blob "$snapshot" "$file")" ]; then
      schema_changed=true
      changed_schema_files+=("$file")
    fi
  done

  if $schema_changed &&
      [ "$(commit_blob "$base_commit" "$CLASSIFICATION_FILE")" = "$(snapshot_blob "$snapshot" "$CLASSIFICATION_FILE")" ]; then
    echo "legacy-freeze: $snapshot schema changed without a classification update" >&2
    printf '  %s\n' "${changed_schema_files[@]}" >&2
    echo "legacy-freeze: base=$base_commit (override with LEGACY_FREEZE_BASE or --base-ref)" >&2
    return 1
  fi
}

check_snapshot HEAD
check_snapshot index
check_snapshot worktree

echo "legacy-freeze: ok (base=$base_commit; snapshots=HEAD,index,worktree)"
