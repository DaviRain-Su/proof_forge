#!/usr/bin/env bash
# EVM solc acceptance helper (engineering only).
#
# Compiles every *.yul under a directory (or a single file) with:
#   solc --strict-assembly --optimize --bin <file>
# matching FinalizeV1 product finalization args.
#
# Exit codes:
#   0  — all files accepted, or solc unavailable (skip with message)
#   1  — solc present but at least one file failed
#   2  — usage / host error
#
# Not formal TASK-D4-04 / hermetic tool-lock / Anvil.
set -euo pipefail

usage() {
  echo "usage: $0 <yul-file-or-dir>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
target="$1"

resolve_solc() {
  if [[ -x /opt/homebrew/bin/solc ]]; then
    echo /opt/homebrew/bin/solc
    return 0
  fi
  if [[ -x /usr/local/bin/solc ]]; then
    echo /usr/local/bin/solc
    return 0
  fi
  if command -v solc >/dev/null 2>&1; then
    command -v solc
    return 0
  fi
  return 1
}

if ! solc="$(resolve_solc)"; then
  echo "skipped: solc unavailable"
  exit 0
fi

echo "evm-solc-acceptance: using $solc"
"$solc" --version | head -1

files=()
if [[ -f "$target" ]]; then
  files=("$target")
elif [[ -d "$target" ]]; then
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$target" -type f -name '*.yul' -print0 | sort -z)
else
  echo "evm-solc-acceptance: not a file or directory: $target" >&2
  exit 2
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "evm-solc-acceptance: no .yul files under $target" >&2
  exit 2
fi

failed=0
for f in "${files[@]}"; do
  echo "--- $f"
  dir="$(cd "$(dirname "$f")" && pwd)"
  base="$(basename "$f")"
  if ! out="$("$solc" --strict-assembly --optimize --bin "$base" --base-path "$dir" 2>&1)"; then
    # Retry with cwd-relative path (FinalizeV1 style: cwd = staging dir).
    if ! (cd "$dir" && out="$("$solc" --strict-assembly --optimize --bin "$base" 2>&1)"); then
      echo "FAIL: solc rejected $f" >&2
      echo "$out" >&2
      failed=1
      continue
    fi
  fi
  if ! grep -q 'Binary representation:' <<<"$out"; then
    # Second attempt with cwd
    out="$(cd "$dir" && "$solc" --strict-assembly --optimize --bin "$base" 2>&1)" || {
      echo "FAIL: solc rejected $f" >&2
      echo "$out" >&2
      failed=1
      continue
    }
  fi
  if ! grep -q 'Binary representation:' <<<"$out"; then
    echo "FAIL: missing Binary representation for $f" >&2
    echo "$out" >&2
    failed=1
    continue
  fi
  bin="$(printf '%s\n' "$out" | sed -n '/Binary representation:/,$p' | tail -n +2 | tr -d '[:space:]')"
  if [[ -z "$bin" ]]; then
    echo "FAIL: empty bytecode for $f" >&2
    failed=1
    continue
  fi
  echo "ok: $f → $((${#bin}/2)) bytes"
done

if [[ "$failed" -ne 0 ]]; then
  echo "evm-solc-acceptance: failures detected" >&2
  exit 1
fi
echo "evm-solc-acceptance: ok"
