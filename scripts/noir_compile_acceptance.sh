#!/usr/bin/env bash
# Noir nargo compile-only acceptance helper (engineering only; G123 / RPT-017 min path).
#
# For each Nargo package directory (contains Nargo.toml + src/main.nr), or a
# product relations tree, runs:
#   nargo compile
#
# Exit codes:
#   0  — all packages compiled, or nargo unavailable (skip with message)
#   1  — nargo present but at least one package failed
#   2  — usage / host error
#
# Compile-only: never prove/verify; does not emit/ship .acir/.proof/.vk/.witness
# as product leaves (scripts/validate_artifacts.py continues to reject those).
# Not formal Stage-0 / hermetic Tool Lock verify / Noir prove path.
set -euo pipefail

usage() {
  echo "usage: $0 <nargo-package-or-relations-dir>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
target="$1"

platform_id() {
  local sys mach
  sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
  mach="$(uname -m | tr '[:upper:]' '[:lower:]')"
  echo "${sys}-${mach}"
}

resolve_nargo() {
  local plat cand
  plat="$(platform_id)"
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" && -x "${PROOF_FORGE_TOOL_ROOT%/}/nargo" ]]; then
    echo "${PROOF_FORGE_TOOL_ROOT%/}/nargo"
    return 0
  fi
  cand="${HOME}/.cache/proof-forge-v2/tool-root/${plat}/nargo"
  if [[ -x "$cand" ]]; then
    echo "$cand"
    return 0
  fi
  if [[ -x "${HOME}/.nargo/bin/nargo" ]]; then
    echo "${HOME}/.nargo/bin/nargo"
    return 0
  fi
  if [[ -x /opt/homebrew/bin/nargo ]]; then
    echo /opt/homebrew/bin/nargo
    return 0
  fi
  if [[ -x /usr/local/bin/nargo ]]; then
    echo /usr/local/bin/nargo
    return 0
  fi
  if command -v nargo >/dev/null 2>&1; then
    command -v nargo
    return 0
  fi
  return 1
}

if ! nargo="$(resolve_nargo)"; then
  echo "skipped: nargo unavailable"
  exit 0
fi

echo "noir-compile-acceptance: using $nargo"
"$nargo" --version 2>&1 | head -3 || true

# Collect package roots: either the path itself has Nargo.toml, or children under
# relations/* / * that contain Nargo.toml.
packages=()
if [[ -f "$target/Nargo.toml" ]]; then
  packages+=("$target")
elif [[ -d "$target" ]]; then
  while IFS= read -r -d '' f; do
    packages+=("$(dirname "$f")")
  done < <(find "$target" -type f -name 'Nargo.toml' -print0 | sort -z)
else
  echo "noir-compile-acceptance: not a directory: $target" >&2
  exit 2
fi

if [[ ${#packages[@]} -eq 0 ]]; then
  echo "noir-compile-acceptance: no Nargo.toml under $target" >&2
  exit 2
fi

failed=0
for pkg in "${packages[@]}"; do
  echo "--- $pkg"
  # nargo discovers Nargo.toml by walking ancestors of cwd.
  if ! out="$(cd "$pkg" && "$nargo" compile --silence-warnings 2>&1)"; then
    echo "FAIL: nargo compile rejected $pkg" >&2
    echo "$out" >&2
    failed=1
    continue
  fi
  echo "ok: $pkg"
done

if [[ "$failed" -ne 0 ]]; then
  echo "noir-compile-acceptance: failures detected" >&2
  exit 1
fi
echo "noir-compile-acceptance: ok"
