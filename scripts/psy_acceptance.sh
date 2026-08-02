#!/usr/bin/env bash
# Psy dargo/psyup acceptance helper (engineering only; J3 PsyEmissionFix).
#
# For a Dargo project directory (contains Dargo.toml + src/main.psy):
#   export PATH="$HOME/.psy/bin:$PATH"
#   export DARGO_STD_PATH="$HOME/.psy/toolchains/psy-*/lib/psy-std/std.psy"
#   psyup build
#
# Exit codes:
#   0  — project accepted, or required tools unavailable (skip with message)
#   1  — tools present but psyup build failed
#   2  — usage / host error
#
# Not formal Stage-0 / hermetic tool-lock / Psy VM prove gate.
set -euo pipefail

usage() {
  echo "usage: $0 <dargo-project-dir>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
target="$1"

if [[ ! -d "$target" ]]; then
  echo "psy-acceptance: not a directory: $target" >&2
  exit 2
fi
if [[ ! -f "$target/Dargo.toml" ]]; then
  echo "psy-acceptance: missing Dargo.toml under $target" >&2
  exit 2
fi

PSY_HOME="${PSY_HOME:-$HOME/.psy}"

resolve_tool() {
  local name="$1"
  if [[ -x "$PSY_HOME/bin/$name" ]]; then
    echo "$PSY_HOME/bin/$name"
    return 0
  fi
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

if ! psyup="$(resolve_tool psyup)"; then
  echo "skipped: psyup unavailable"
  exit 0
fi
if ! dargo="$(resolve_tool dargo)"; then
  echo "skipped: dargo unavailable"
  exit 0
fi

# Pin bundled std so dargo does not clone the missing PsyProtocol/psy-v1 git repo.
if [[ -z "${DARGO_STD_PATH:-}" ]]; then
  if [[ -f "$PSY_HOME/toolchains/psy-0.1.0/lib/psy-std/std.psy" ]]; then
    export DARGO_STD_PATH="$PSY_HOME/toolchains/psy-0.1.0/lib/psy-std/std.psy"
  else
    # Fall back to the first psy-* toolchain that carries std.psy.
    for cand in "$PSY_HOME"/toolchains/psy-*/lib/psy-std/std.psy; do
      if [[ -f "$cand" ]]; then
        export DARGO_STD_PATH="$cand"
        break
      fi
    done
  fi
fi

if [[ -z "${DARGO_STD_PATH:-}" || ! -f "${DARGO_STD_PATH}" ]]; then
  echo "skipped: bundled psy-std (DARGO_STD_PATH) unavailable"
  exit 0
fi

export PATH="$(dirname "$psyup"):$(dirname "$dargo"):${PATH}"

echo "psy-acceptance: psyup=$psyup dargo=$dargo"
echo "psy-acceptance: DARGO_STD_PATH=$DARGO_STD_PATH"
"$psyup" version 2>&1 || true

cd "$target"
if ! "$psyup" build; then
  echo "psy-acceptance: psyup build FAILED in $target" >&2
  exit 1
fi

echo "psy-acceptance: ok ($target)"
exit 0
