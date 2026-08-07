#!/usr/bin/env bash
# Stop the local Surfpool instance started by solana_surfpool_up.sh.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
surf_dir="$root/runtime-tests/solana/surfpool"
pid_file="$surf_dir/pid"

if [[ ! -f "$pid_file" ]]; then
  echo "solana-surfpool-down: no pid file (already stopped)" >&2
  exit 0
fi

pid="$(cat "$pid_file" 2>/dev/null || true)"
if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null || true
  # Wait for exit (graceful).
  for _ in $(seq 1 40); do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  echo "solana-surfpool-down: stopped pid=$pid" >&2
else
  echo "solana-surfpool-down: stale pid file (process not running)" >&2
fi
rm -f "$pid_file"
# Keep rpc-url.txt for post-mortem; remove so next up is clean.
rm -f "$surf_dir/rpc-url.txt"
