#!/usr/bin/env bash
# NEAR Wasm acceptance helper (engineering only; gap C-1).
#
# For each *.wat under a directory (or a single file):
#   wat2wasm <file>.wat -o <file>.wasm
#   wasm-interp --dummy-import-func <file>.wasm   (preferred)
#   — or wasmtime compile / wasmer validate
#
# Exit codes:
#   0  — all files accepted, or required tools unavailable (skip with message)
#   1  — tools present but at least one file failed
#   2  — usage / host error
#
# Not formal Stage-0 / hermetic tool-lock / NEAR sandbox receipt.
set -euo pipefail

usage() {
  echo "usage: $0 <wat-file-or-dir>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
target="$1"

resolve_tool() {
  local name="$1"
  if [[ -x "/opt/homebrew/bin/$name" ]]; then
    echo "/opt/homebrew/bin/$name"
    return 0
  fi
  if [[ -x "/usr/local/bin/$name" ]]; then
    echo "/usr/local/bin/$name"
    return 0
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  return 1
}

if ! wat2wasm="$(resolve_tool wat2wasm)"; then
  echo "skipped: wat2wasm unavailable"
  exit 0
fi

runtime_kind=""
runtime=""
if runtime="$(resolve_tool wasm-interp)"; then
  runtime_kind="wasm-interp"
elif runtime="$(resolve_tool wasmtime)"; then
  runtime_kind="wasmtime"
elif runtime="$(resolve_tool wasmer)"; then
  runtime_kind="wasmer"
else
  echo "skipped: wasm runtime (wasm-interp|wasmtime|wasmer) unavailable"
  exit 0
fi

echo "near-wasm-acceptance: wat2wasm=$wat2wasm runtime=$runtime_kind ($runtime)"
"$wat2wasm" --version 2>&1 | head -1 || true

files=()
if [[ -f "$target" ]]; then
  files=("$target")
elif [[ -d "$target" ]]; then
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$target" -type f -name '*.wat' -print0 | sort -z)
else
  echo "near-wasm-acceptance: not a file or directory: $target" >&2
  exit 2
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "near-wasm-acceptance: no .wat files under $target" >&2
  exit 2
fi

failed=0
for f in "${files[@]}"; do
  echo "--- $f"
  dir="$(cd "$(dirname "$f")" && pwd)"
  base="$(basename "$f")"
  stem="${base%.wat}"
  wasm="$stem.wasm"
  if ! (cd "$dir" && "$wat2wasm" "$base" -o "$wasm" 2>&1); then
    echo "FAIL: wat2wasm rejected $f" >&2
    failed=1
    continue
  fi
  if [[ ! -f "$dir/$wasm" ]]; then
    echo "FAIL: missing $dir/$wasm after wat2wasm" >&2
    failed=1
    continue
  fi
  # Wasm magic \0asm
  magic="$(head -c 4 "$dir/$wasm" | od -An -tx1 | tr -d ' \n')"
  if [[ "$magic" != "0061736d" ]]; then
    echo "FAIL: bad Wasm magic for $f (got $magic)" >&2
    failed=1
    continue
  fi
  case "$runtime_kind" in
    wasm-interp)
      if ! (cd "$dir" && "$runtime" --dummy-import-func "$wasm" 2>&1); then
        echo "FAIL: wasm-interp rejected $f" >&2
        failed=1
        continue
      fi
      ;;
    wasmtime)
      if ! (cd "$dir" && "$runtime" compile "$wasm" 2>&1); then
        echo "FAIL: wasmtime compile rejected $f" >&2
        failed=1
        continue
      fi
      ;;
    wasmer)
      if ! (cd "$dir" && "$runtime" validate "$wasm" 2>&1); then
        echo "FAIL: wasmer validate rejected $f" >&2
        failed=1
        continue
      fi
      ;;
  esac
  size="$(wc -c <"$dir/$wasm" | tr -d ' ')"
  echo "ok: $f → $size bytes ($runtime_kind)"
done

if [[ "$failed" -ne 0 ]]; then
  echo "near-wasm-acceptance: failures detected" >&2
  exit 1
fi
echo "near-wasm-acceptance: ok"
