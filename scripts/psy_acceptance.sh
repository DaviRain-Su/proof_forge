#!/usr/bin/env bash
# Psy dargo compile-only acceptance helper (engineering only; J3 PsyEmissionFix).
#
# For a Dargo project directory (contains Dargo.toml + src/main.psy):
#   dargo compile --contract-name <Name>
#   dargo generate-abi --contract-name <Name>
#
# Tool resolution order (no psyup authority):
#   1. $PROOF_FORGE_TOOL_ROOT/dargo + lib/psy-std/std.psy
#   2. default cache tool-root/{linux-x86_64,darwin-arm64}
#   3. host ~/.psy/bin/dargo + ~/.psy/toolchains/.../std.psy (compile-only fallback)
#
# When no dargo/std is available the helper skip-cleans (exit 0). When tools are
# present it is fail-closed on non-zero compile/generate-abi.
#
# Exit codes:
#   0  — project accepted, or required tools unavailable (skip with message)
#   1  — tools present but dargo compile/generate-abi failed
#   2  — usage / host error
#
# Not formal Stage-0 / hermetic tool-lock / network UPS / deploy.
# Optional host-heavy local VM execute lives in scripts/psy_runtime_test.sh
# (`just psy-runtime`) and is not ordinary ci.
set -euo pipefail

usage() {
  echo "usage: $0 <dargo-project-dir> [contract-name]" >&2
  echo "  contract-name defaults to scanning src/main.psy for 'pub struct Name'" >&2
  exit 2
}

[[ $# -eq 1 || $# -eq 2 ]] || usage
target="$1"
contract_name="${2:-}"

if [[ ! -d "$target" ]]; then
  echo "psy-acceptance: not a directory: $target" >&2
  exit 2
fi
if [[ ! -f "$target/Dargo.toml" ]]; then
  echo "psy-acceptance: missing Dargo.toml under $target" >&2
  exit 2
fi
if [[ ! -f "$target/src/main.psy" ]]; then
  echo "psy-acceptance: missing src/main.psy under $target" >&2
  exit 2
fi

platform_id() {
  local sys mach
  sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
  mach="$(uname -m | tr '[:upper:]' '[:lower:]')"
  echo "${sys}-${mach}"
}

# Prefer locked / default-cache dargo+std; then host ~/.psy. Never require psyup.
resolve_locked_pair() {
  local root="${1%/}"
  if [[ -x "${root}/dargo" && -f "${root}/lib/psy-std/std.psy" ]]; then
    echo "${root}/dargo"
    echo "${root}/lib/psy-std/std.psy"
    return 0
  fi
  return 1
}

PSY_HOME="${PSY_HOME:-$HOME/.psy}"
plat="$(platform_id)"
dargo=""
std_path=""

if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" ]]; then
  if pair="$(resolve_locked_pair "$PROOF_FORGE_TOOL_ROOT")"; then
    dargo="$(printf '%s\n' "$pair" | sed -n '1p')"
    std_path="$(printf '%s\n' "$pair" | sed -n '2p')"
  fi
fi

if [[ -z "$dargo" ]]; then
  if pair="$(resolve_locked_pair "${HOME}/.cache/proof-forge-v2/tool-root/${plat}")"; then
    dargo="$(printf '%s\n' "$pair" | sed -n '1p')"
    std_path="$(printf '%s\n' "$pair" | sed -n '2p')"
  fi
fi

# Host ~/.psy fallback (compile-only; skip-clean when absent).
if [[ -z "$dargo" ]]; then
  if [[ -x "${PSY_HOME}/bin/dargo" ]]; then
    dargo="${PSY_HOME}/bin/dargo"
  elif [[ -x /opt/homebrew/bin/dargo ]]; then
    dargo=/opt/homebrew/bin/dargo
  elif [[ -x /usr/local/bin/dargo ]]; then
    dargo=/usr/local/bin/dargo
  elif command -v dargo >/dev/null 2>&1; then
    dargo="$(command -v dargo)"
  fi
fi

if [[ -z "${std_path}" ]]; then
  if [[ -n "${DARGO_STD_PATH:-}" && -f "${DARGO_STD_PATH}" ]]; then
    std_path="${DARGO_STD_PATH}"
  elif [[ -f "${PSY_HOME}/toolchains/psy-0.1.0/lib/psy-std/std.psy" ]]; then
    std_path="${PSY_HOME}/toolchains/psy-0.1.0/lib/psy-std/std.psy"
  else
    for cand in "${PSY_HOME}"/toolchains/psy-*/lib/psy-std/std.psy; do
      if [[ -f "$cand" ]]; then
        std_path="$cand"
        break
      fi
    done
  fi
fi

if [[ -z "$dargo" || ! -x "$dargo" ]]; then
  echo "skipped: dargo unavailable"
  exit 0
fi
if [[ -z "${std_path}" || ! -f "${std_path}" ]]; then
  echo "skipped: bundled psy-std (DARGO_STD_PATH) unavailable"
  exit 0
fi

if [[ -z "$contract_name" ]]; then
  # First `pub struct Name` in the entry file (product emitter uses this form).
  contract_name="$(
    sed -n 's/^[[:space:]]*pub struct \([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' \
      "$target/src/main.psy" | head -n 1 || true
  )"
fi
if [[ -z "$contract_name" ]]; then
  echo "psy-acceptance: could not infer contract name from src/main.psy (pass as arg 2)" >&2
  exit 2
fi

# Package stem from Dargo.toml name= (fallback: directory basename).
package_name="$(
  sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$target/Dargo.toml" | head -n 1 || true
)"
if [[ -z "$package_name" ]]; then
  package_name="$(basename "$target")"
fi

export DARGO_STD_PATH="$std_path"

echo "psy-acceptance: dargo=$dargo"
echo "psy-acceptance: DARGO_STD_PATH=$DARGO_STD_PATH"
echo "psy-acceptance: contract=$contract_name package=$package_name"
dargo_version="$("$dargo" --version 2>&1)" || {
  echo "psy-acceptance: dargo --version failed" >&2
  exit 1
}
dargo_first_line="$(printf '%s\n' "$dargo_version" | head -n 1)"
if [[ "$dargo_first_line" != "dargo 0.1.0" ]]; then
  echo "psy-acceptance: expected 'dargo 0.1.0', got '$dargo_first_line'" >&2
  exit 1
fi
echo "$dargo_first_line"

cd "$target"
if ! "$dargo" compile --contract-name "$contract_name"; then
  echo "psy-acceptance: dargo compile FAILED in $target" >&2
  exit 1
fi
if ! "$dargo" generate-abi --contract-name "$contract_name"; then
  echo "psy-acceptance: dargo generate-abi FAILED in $target" >&2
  exit 1
fi

abi_json="target/${contract_name}.abi.json"
pkg_json="target/${package_name}.json"
if [[ ! -s "$abi_json" && ! -s "target/${package_name}.abi.json" ]]; then
  echo "psy-acceptance: missing ABI under target/ (${contract_name}.abi.json)" >&2
  exit 1
fi
if [[ ! -s "$pkg_json" ]]; then
  # Some layouts only emit the contract ABI; accept non-empty ABI as minimum.
  if [[ ! -s "$abi_json" && ! -s "target/${package_name}.abi.json" ]]; then
    echo "psy-acceptance: missing package/ABI json under target/" >&2
    exit 1
  fi
fi

echo "psy-acceptance: ok ($target contract=$contract_name)"
exit 0
