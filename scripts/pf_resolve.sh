#!/usr/bin/env bash
# Resolve developer CLI `pf` + compiler for monorepo scripts/just recipes.
# shellcheck shell=bash
# Usage: source scripts/pf_resolve.sh
# Exports: PF, PROOF_FORGE_CLI, PROOF_FORGE_ROOT (if unset)

_pf_resolve_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$_pf_resolve_root}"

if [[ -z "${PROOF_FORGE_CLI:-}" ]]; then
  if [[ -x "$PROOF_FORGE_ROOT/.lake/build/bin/proof-forge-next" ]]; then
    export PROOF_FORGE_CLI="$PROOF_FORGE_ROOT/.lake/build/bin/proof-forge-next"
  elif command -v proof-forge-next >/dev/null 2>&1; then
    export PROOF_FORGE_CLI="$(command -v proof-forge-next)"
  fi
fi

if [[ -z "${PF:-}" ]]; then
  if [[ -x "$PROOF_FORGE_ROOT/clients/pf-cli/target/release/pf" ]]; then
    PF="$PROOF_FORGE_ROOT/clients/pf-cli/target/release/pf"
  elif [[ -x "$PROOF_FORGE_ROOT/clients/pf-cli/target/debug/pf" ]]; then
    PF="$PROOF_FORGE_ROOT/clients/pf-cli/target/debug/pf"
  elif command -v pf >/dev/null 2>&1; then
    # Prefer monorepo binary over unrelated PATH `pf` if both exist.
    PF="$(command -v pf)"
  else
    PF=""
  fi
fi
export PF

pf_require() {
  if [[ -z "${PF:-}" || ! -x "$PF" ]]; then
    echo "pf_resolve: missing pf binary (build: just pf-cli-build)" >&2
    return 2
  fi
  if [[ -z "${PROOF_FORGE_CLI:-}" || ! -x "$PROOF_FORGE_CLI" ]]; then
    echo "pf_resolve: missing proof-forge-next (build: lake build proof_forge_next)" >&2
    return 2
  fi
  return 0
}
