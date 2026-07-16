#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'v2-isolation: %s\n' "$*" >&2
  exit 1
}

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(CDPATH= cd -- "$script_dir/.." && pwd -P)"
git_root="$(git -C "$source_root" rev-parse --show-toplevel 2>/dev/null)" || \
  fail "source root is not a Git checkout"
[[ "$git_root" == "$source_root" ]] || fail "script must run from the V2 repository root"

dirty="$(
  git -C "$source_root" status --porcelain=v1 --untracked-files=all -- \
    . ':(exclude)active' ':(exclude)active/**'
)"
if [[ -n "$dirty" ]]; then
  printf '%s\n' "$dirty" >&2
  fail "product tree must be committed before archive isolation runs"
fi

candidate_commit="$(git -C "$source_root" rev-parse --verify 'HEAD^{commit}')" || \
  fail "cannot resolve the committed candidate"
temp_root="$(mktemp -d /tmp/proof-forge-v2-isolation.XXXXXX)"
temp_root="$(CDPATH= cd -- "$temp_root" && pwd -P)"
trap 'rm -rf "$temp_root"' EXIT HUP INT TERM
archive="$temp_root/product.tar"
tree_records="$temp_root/tree-records.bin"
product_root="$temp_root/product"
runner_root="$temp_root/runner"
mkdir -p "$product_root" "$runner_root"

product_pathspecs=()
while IFS= read -r -d '' entry; do
  [[ "$entry" == "active" ]] && continue
  [[ "$entry" != *$'\n'* && "$entry" != *$'\r'* && "$entry" != *$'\t'* ]] || \
    fail "control character in a top-level product path"
  product_pathspecs+=(":(literal)$entry")
done < <(git -C "$source_root" ls-tree -z --name-only "$candidate_commit")
(( ${#product_pathspecs[@]} > 0 )) || fail "committed product tree is empty"

git -C "$source_root" ls-tree -r -z "$candidate_commit" -- \
  "${product_pathspecs[@]}" > "$tree_records"
/usr/bin/python3 -I -S -B "$source_root/scripts/v2_isolation.py" \
  --git-tree-records "$tree_records"

git -C "$source_root" archive --format=tar --output="$archive" \
  "$candidate_commit" -- "${product_pathspecs[@]}"
tar -xf "$archive" -C "$product_root"

/usr/bin/python3 -I -S -B "$product_root/scripts/v2_isolation.py" \
  --root "$product_root" \
  --forbidden-checkout "$source_root"

(
  cd "$runner_root"
  unset LEAN_PATH
  lake --dir "$product_root" --no-cache build \
    ProofForgeV2 proof_forge_next proof_forge_next_tests
  lake --dir "$product_root" -q -J query \
    proof_forge_next proof_forge_next_tests > "$temp_root/query.jsonl"
)

{
  IFS= read -r cli_result || fail "Lake query omitted the CLI output"
  IFS= read -r tests_result || fail "Lake query omitted the test output"
  if IFS= read -r extra_result; then
    fail "Lake query returned an unexpected third result: $extra_result"
  fi
} < "$temp_root/query.jsonl"

expected_cli="\"$product_root/.lake/build/bin/proof-forge-next\""
expected_tests="\"$product_root/.lake/build/bin/proof-forge-next-tests\""
[[ "$cli_result" == "$expected_cli" ]] || \
  fail "CLI output is not owned by the extracted workspace: $cli_result"
[[ "$tests_result" == "$expected_tests" ]] || \
  fail "test output is not owned by the extracted workspace: $tests_result"
physical_bin="$(CDPATH= cd -- "$product_root/.lake/build/bin" && pwd -P)"
[[ "$physical_bin" == "$product_root/.lake/build/bin" ]] || \
  fail "Lake executable directory escapes through a symlink: $physical_bin"
if find "$product_root/.lake/build" -type l -print -quit | grep -q .; then
  fail "Lake build output contains a symlink"
fi
[[ -f "$product_root/.lake/build/bin/proof-forge-next" && \
   ! -L "$product_root/.lake/build/bin/proof-forge-next" ]] || \
  fail "CLI query output is not a regular workspace file"
[[ -f "$product_root/.lake/build/bin/proof-forge-next-tests" && \
   ! -L "$product_root/.lake/build/bin/proof-forge-next-tests" ]] || \
  fail "test query output is not a regular workspace file"

(
  cd "$runner_root"
  unset LEAN_PATH
  lake --dir "$product_root" env \
    "$product_root/.lake/build/bin/proof-forge-next-tests"
  lake --dir "$product_root" env \
    "$product_root/.lake/build/bin/proof-forge-next" --help > "$temp_root/help.txt"
  grep -Fq 'Usage:' "$temp_root/help.txt"
)

printf 'v2-isolation: committed archive %s build/test/help ok\n' "$candidate_commit"
