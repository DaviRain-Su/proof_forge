#!/usr/bin/env bash
# Aleo leo-build acceptance helper (engineering only; J2 AleoEmissionFix).
#
# Wraps each *.aleo (or a directory of them) into a temporary Leo 4 package
# and runs:
#   leo build --offline --disable-update-check
#
# Exit codes:
#   0  — all files accepted, or leo unavailable (skip with message)
#   1  — leo present but at least one file failed
#   2  — usage / host error
#
# Not formal Stage-0 / hermetic tool-lock / snarkVM prove-deploy.
set -euo pipefail

usage() {
  echo "usage: $0 <aleo-file-or-dir>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
target="$1"

resolve_leo() {
  if [[ -x "${HOME}/.cargo/bin/leo" ]]; then
    echo "${HOME}/.cargo/bin/leo"
    return 0
  fi
  if [[ -x /opt/homebrew/bin/leo ]]; then
    echo /opt/homebrew/bin/leo
    return 0
  fi
  if [[ -x /usr/local/bin/leo ]]; then
    echo /usr/local/bin/leo
    return 0
  fi
  if command -v leo >/dev/null 2>&1; then
    command -v leo
    return 0
  fi
  return 1
}

if ! leo="$(resolve_leo)"; then
  echo "skipped: leo unavailable"
  exit 0
fi

echo "aleo-acceptance: using $leo"
"$leo" --version | head -1

files=()
if [[ -f "$target" ]]; then
  files=("$target")
elif [[ -d "$target" ]]; then
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$target" -type f -name '*.aleo' -print0 | sort -z)
else
  echo "aleo-acceptance: not a file or directory: $target" >&2
  exit 2
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "aleo-acceptance: no .aleo files under $target" >&2
  exit 2
fi

failed=0
workdir="$(mktemp -d "${TMPDIR:-/tmp}/aleo-accept.XXXXXX")"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

for f in "${files[@]}"; do
  echo "--- $f"
  base="$(basename "$f")"
  stem="${base%.aleo}"
  pkg="$workdir/$stem"
  rm -rf "$pkg"
  mkdir -p "$pkg/src"
  cat >"$pkg/program.json" <<EOF
{
  "program": "${stem}.aleo",
  "version": "0.1.0",
  "description": "proof-forge-next aleo acceptance",
  "license": "MIT",
  "leo": "4.0.2",
  "dependencies": null,
  "dev_dependencies": null
}
EOF
  cp "$f" "$pkg/src/main.leo"
  if ! out="$("$leo" build --offline --disable-update-check --path "$pkg" 2>&1)"; then
    echo "FAIL: leo build rejected $f" >&2
    echo "$out" >&2
    failed=1
    continue
  fi
  if ! grep -qE 'Compiled|into Aleo instructions' <<<"$out"; then
    echo "FAIL: missing leo success marker for $f" >&2
    echo "$out" >&2
    failed=1
    continue
  fi
  echo "ok: $f"
done

if [[ "$failed" -ne 0 ]]; then
  echo "aleo-acceptance: failures detected" >&2
  exit 1
fi
echo "aleo-acceptance: ok"
