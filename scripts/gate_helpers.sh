# Shared deletion-gate helpers for justfile recipes.
# Source from a recipe (cwd = repo root):  source scripts/gate_helpers.sh
# Do not execute this file directly.
#
# Contract (rg exit codes):
#   0 = match found  → fail (forbidden residual still present)
#   1 = no match     → ok for fail_if_match; fail for expect_one_match
#   other            → tool/error failure

# fail_if_match GATE_NAME PAT [PATH...]
# Search PATH... (or cwd default if none) with rg --glob '*.lean'.
# PAT is passed as a single argument to rg (no eval / word-splitting).
fail_if_match() {
  local gate="$1"
  local pat="$2"
  shift 2
  local hits ec
  set +e
  hits="$(rg --glob '*.lean' -n --no-heading "$pat" "$@" 2>&1)"
  ec=$?
  set -e
  if [[ $ec -eq 0 ]]; then
    echo "$gate: forbidden pattern still present: $pat" >&2
    printf '%s\n' "$hits" >&2
    exit 1
  fi
  if [[ $ec -ne 1 ]]; then
    echo "$gate: rg failed for $pat (exit $ec)" >&2
    printf '%s\n' "$hits" >&2
    exit 1
  fi
}

# expect_one_match GATE_NAME PAT FILE LABEL
# Require exactly one match under ProofForgeV2 whose line contains FILE.
expect_one_match() {
  local gate="$1"
  local pat="$2"
  local must_path="$3"
  local label="$4"
  local hits ec count
  set +e
  hits="$(rg --glob '*.lean' -n --no-heading "$pat" ProofForgeV2 2>&1)"
  ec=$?
  set -e
  if [[ $ec -ne 0 ]]; then
    echo "$gate: $label expected one match (rg exit $ec)" >&2
    printf '%s\n' "$hits" >&2
    exit 1
  fi
  # Use absolute sed so interactive shells that alias sed→sd cannot break count.
  count="$(printf '%s\n' "$hits" | /usr/bin/sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" != "1" ]] || ! printf '%s\n' "$hits" | grep -q "$must_path"; then
    echo "$gate: $label expected sole match in $must_path" >&2
    printf '%s\n' "$hits" >&2
    exit 1
  fi
}

# fail_if_file_exists GATE_NAME PATH
fail_if_file_exists() {
  local gate="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    echo "$gate: $path must be deleted" >&2
    exit 1
  fi
}
