#!/usr/bin/env bash
# Developer-facing Aleo local smoke via `pf` (project flow).
# Complements scripts/aleo_instructions_*_acceptance.sh (compiler-level gates).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/pf_resolve.sh
source "$root/scripts/pf_resolve.sh"
pf_require || exit $?

tmp="$(mktemp -d "${TMPDIR:-/tmp}/aleo-pf-local.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

echo "aleo-pf-local: pf new → build → run"
"$PF" new smoke --target aleo --path "$tmp/smoke" >/dev/null
(
  cd "$tmp/smoke"
  "$PF" build
  if command -v leo >/dev/null 2>&1 || [[ -n "${PROOF_FORGE_ALEO_LEO:-}" ]]; then
    "$PF" run -- initialize 5u64
    "$PF" run -- increment 3u64
  else
    echo "aleo-pf-local: leo missing — skipped run (host-optional)"
  fi
  "$PF" deploy >/dev/null || true  # save-only may need leo; ignore if missing
)
echo "aleo-pf-local: ok"
