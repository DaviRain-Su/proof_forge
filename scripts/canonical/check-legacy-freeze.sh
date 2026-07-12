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
  mkdir -p "$source_repo/ProofForge/IR/Legacy" "$source_repo/ProofForge/Contract" \
    "$source_repo/scripts/canonical"
  printf '%s\n' 'inductive LegacySchema where | original' > "$source_repo/ProofForge/IR/Contract.lean"
  printf '%s\n' 'structure LegacySpec where' '  name : String' > "$source_repo/ProofForge/Contract/Spec.lean"
  printf '%s\n' 'def classification := #["original"]' > "$source_repo/$CLASSIFICATION_FILE"
  : > "$source_repo/scripts/canonical/legacy-production-imports.txt"
  git -C "$source_repo" add .
  git -C "$source_repo" commit -q -m base

  if ! (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null); then
    echo "legacy-freeze self-test: clean snapshot should pass" >&2
    return 1
  fi

  rm "$source_repo/scripts/canonical/legacy-production-imports.txt"
  if (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null 2>&1); then
    echo "legacy-freeze self-test: missing import baseline should fail" >&2
    return 1
  fi
  git -C "$source_repo" restore scripts/canonical/legacy-production-imports.txt

  printf '%s\n' 'import ProofForge.IR.Legacy.Core' > "$source_repo/ProofForge/NewConsumer.lean"
  if (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null 2>&1); then
    echo "legacy-freeze self-test: unreviewed production import should fail" >&2
    return 1
  fi
  rm "$source_repo/ProofForge/NewConsumer.lean"

  printf '%s\n' 'import ProofForge.IR.Legacy.Core' > "$source_repo/ProofForge/NewConsumer.lean"
  printf '%s\n' 'ProofForge/NewConsumer.lean' > \
    "$source_repo/scripts/canonical/legacy-production-imports.txt"
  if ! (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null); then
    echo "legacy-freeze self-test: synchronized import baseline should pass" >&2
    return 1
  fi
  rm "$source_repo/ProofForge/NewConsumer.lean"
  git -C "$source_repo" restore scripts/canonical/legacy-production-imports.txt

  printf '%s\n' 'ProofForge/Nonexistent.lean' > \
    "$source_repo/scripts/canonical/legacy-production-imports.txt"
  if (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null 2>&1); then
    echo "legacy-freeze self-test: baseline-only expansion should fail" >&2
    return 1
  fi
  git -C "$source_repo" restore scripts/canonical/legacy-production-imports.txt

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

  printf '%s\n' '-- committed paired schema edit' >> "$source_repo/ProofForge/IR/Contract.lean"
  printf '%s\n' '-- committed paired classification edit' >> "$source_repo/$CLASSIFICATION_FILE"
  git -C "$source_repo" add ProofForge/IR/Contract.lean "$CLASSIFICATION_FILE"
  git -C "$source_repo" commit -q -m paired
  printf '%s\n' '-- staged schema after paired HEAD' >> "$source_repo/ProofForge/IR/Contract.lean"
  git -C "$source_repo" add ProofForge/IR/Contract.lean
  if (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD^ >/dev/null 2>&1); then
    echo "legacy-freeze self-test: staged schema after paired HEAD should fail" >&2
    return 1
  fi
  git -C "$source_repo" reset -q --hard HEAD

  printf '%s\n' '-- staged paired schema edit' >> "$source_repo/ProofForge/IR/Contract.lean"
  printf '%s\n' '-- staged paired classification edit' >> "$source_repo/$CLASSIFICATION_FILE"
  git -C "$source_repo" add ProofForge/IR/Contract.lean "$CLASSIFICATION_FILE"
  git -C "$source_repo" restore --worktree --source=HEAD ProofForge/IR/Contract.lean
  if (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null 2>&1); then
    echo "legacy-freeze self-test: worktree schema reset shadow should fail" >&2
    return 1
  fi
  git -C "$source_repo" reset -q --hard HEAD

  printf '%s\n' '-- staged paired schema edit, classification later shadowed' >> "$source_repo/ProofForge/IR/Contract.lean"
  printf '%s\n' '-- staged paired classification edit, later shadowed' >> "$source_repo/$CLASSIFICATION_FILE"
  git -C "$source_repo" add ProofForge/IR/Contract.lean "$CLASSIFICATION_FILE"
  git -C "$source_repo" restore --worktree --source=HEAD "$CLASSIFICATION_FILE"
  if (cd "$source_repo" && "$SCRIPT_PATH" --base-ref HEAD >/dev/null 2>&1); then
    echo "legacy-freeze self-test: worktree classification reset shadow should fail" >&2
    return 1
  fi
  git -C "$source_repo" reset -q --hard HEAD

  printf '%s\n' '-- second commit' >> "$source_repo/$CLASSIFICATION_FILE"
  git -C "$source_repo" add "$CLASSIFICATION_FILE"
  git -C "$source_repo" commit -q -m second

  printf '%s\n' '-- schema-only main push' >> "$source_repo/ProofForge/IR/Contract.lean"
  git -C "$source_repo" add ProofForge/IR/Contract.lean
  local before_multi_commit_push
  before_multi_commit_push=$(git -C "$source_repo" rev-parse HEAD)
  git -C "$source_repo" commit -q -m schema-only-main
  git -C "$source_repo" update-ref refs/remotes/origin/main HEAD
  if (cd "$source_repo" && env -u CI_COMMIT_TARGET_BRANCH -u CI_PREV_COMMIT_SHA \
      -u CI_PREV_COMMIT_BRANCH -u CI_COMMIT_BRANCH "$SCRIPT_PATH" >/dev/null 2>&1); then
    echo "legacy-freeze self-test: auto base at origin/main=HEAD should inspect HEAD^" >&2
    return 1
  else
    local auto_main_status=$?
    if [ "$auto_main_status" -ne 1 ]; then
      echo "legacy-freeze self-test: auto main schema failure returned $auto_main_status, expected 1" >&2
      return 1
    fi
  fi

  printf '%s\n' 'unrelated follow-up' > "$source_repo/README.md"
  git -C "$source_repo" add README.md
  git -C "$source_repo" commit -q -m unrelated-follow-up
  git -C "$source_repo" update-ref refs/remotes/origin/main HEAD
  if (cd "$source_repo" && CI_PREV_COMMIT_SHA="$before_multi_commit_push" \
      CI_PREV_COMMIT_BRANCH=main CI_COMMIT_BRANCH=main "$SCRIPT_PATH" >/dev/null 2>&1); then
    echo "legacy-freeze self-test: multi-commit push should use the CI previous SHA" >&2
    return 1
  else
    local multi_commit_status=$?
    if [ "$multi_commit_status" -ne 1 ]; then
      echo "legacy-freeze self-test: multi-commit schema failure returned $multi_commit_status, expected 1" >&2
      return 1
    fi
  fi
  git -C "$source_repo" update-ref -d refs/remotes/origin/main

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

# Woodpecker exposes the pull-request target branch and the previous successful
# commit. Prefer those event baselines over `origin/main == HEAD`, which can only
# inspect the final commit and would miss an earlier schema-only commit in the
# same push. GitHub supplies `LEGACY_FREEZE_BASE` in its workflow step.
if [ -z "$base_ref" ]; then
  if [ -n "${CI_COMMIT_TARGET_BRANCH:-}" ]; then
    base_ref="origin/${CI_COMMIT_TARGET_BRANCH}"
  elif [ -n "${CI_PREV_COMMIT_SHA:-}" ] &&
      [ "${CI_PREV_COMMIT_BRANCH:-}" = "${CI_COMMIT_BRANCH:-}" ]; then
    base_ref=$CI_PREV_COMMIT_SHA
  fi
fi

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

resolve_parent_or_root() {
  local is_shallow parent_count
  if git rev-parse --verify --quiet HEAD^ >/dev/null; then
    git rev-parse HEAD^
    return
  fi

  is_shallow=$(git rev-parse --is-shallow-repository)
  parent_count=$(git rev-list --parents -n 1 HEAD | awk '{ print NF - 1 }')
  if [ "$is_shallow" = "true" ]; then
    echo "legacy-freeze: cannot resolve a baseline from a shallow repository" >&2
    return 1
  elif [ "$parent_count" -ne 0 ]; then
    echo "legacy-freeze: cannot resolve the parent baseline for HEAD" >&2
    return 1
  fi

  # The empty tree is valid only for a verified, non-shallow root commit.
  printf '%s\n' "$empty_tree"
}

if [ -n "$base_ref" ]; then
  if ! base_commit=$(resolve_merge_base "$base_ref"); then
    exit 2
  fi
elif git rev-parse --verify --quiet origin/main^{commit} >/dev/null; then
  origin_main_commit=$(git rev-parse origin/main^{commit})
  if [ "$origin_main_commit" = "$head_commit" ]; then
    if ! base_commit=$(resolve_parent_or_root); then
      exit 2
    fi
  elif ! base_commit=$(resolve_merge_base origin/main); then
    exit 2
  fi
else
  if ! base_commit=$(resolve_parent_or_root); then
    exit 2
  fi
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
    base) commit_blob "$base_commit" "$file" ;;
    HEAD) commit_blob "$head_commit" "$file" ;;
    index) index_blob "$file" ;;
    worktree) worktree_blob "$file" ;;
    *)
      echo "legacy-freeze: internal unknown snapshot: $snapshot" >&2
      return 2
      ;;
  esac
}

check_transition() {
  local from_snapshot=$1 to_snapshot=$2 file schema_changed=false
  local changed_schema_files=()

  for file in "${SCHEMA_FILES[@]}"; do
    if [ "$(snapshot_blob "$from_snapshot" "$file")" != "$(snapshot_blob "$to_snapshot" "$file")" ]; then
      schema_changed=true
      changed_schema_files+=("$file")
    fi
  done

  if $schema_changed &&
      [ "$(snapshot_blob "$from_snapshot" "$CLASSIFICATION_FILE")" = "$(snapshot_blob "$to_snapshot" "$CLASSIFICATION_FILE")" ]; then
    echo "legacy-freeze: $from_snapshot->$to_snapshot schema changed without a classification update" >&2
    printf '  %s\n' "${changed_schema_files[@]}" >&2
    echo "legacy-freeze: base=$base_commit (override with LEGACY_FREEZE_BASE or --base-ref)" >&2
    return 1
  fi
}

check_transition base HEAD
check_transition HEAD index
check_transition index worktree
# A later layer can change only the classification file and otherwise hide an
# earlier paired edit. Keep the transition checks above for staged/unstaged
# isolation, and also require every final snapshot to remain paired with base.
check_transition base index
check_transition base worktree

# D0: the reviewed production-import baseline is mandatory and exact. A
# migration removes an import and its baseline row in the same change; adding a
# caller or deleting/expanding the baseline alone fails closed.
IMPORTS_BASELINE="scripts/canonical/legacy-production-imports.txt"
if [ ! -f "$IMPORTS_BASELINE" ]; then
  echo "legacy-freeze: missing production import baseline: $IMPORTS_BASELINE" >&2
  exit 1
fi

actual="$(mktemp)"
trap 'rm -f "$actual"' EXIT
rg -l '^import ProofForge\.IR\.Legacy' ProofForge 2>/dev/null | LC_ALL=C sort > "$actual" || true
if ! diff -u "$IMPORTS_BASELINE" "$actual" >/dev/null; then
  echo "legacy-freeze: production legacy imports changed without baseline update" >&2
  diff -u "$IMPORTS_BASELINE" "$actual" >&2 || true
  exit 1
fi

echo "legacy-freeze: ok (base=$base_commit; transitions=base->HEAD->index->worktree; imports=exact)"
