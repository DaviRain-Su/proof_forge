#!/usr/bin/env bash
set -euo pipefail

pid="${1:-}"
if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
  echo "stop-background-process: expected a positive PID" >&2
  exit 2
fi
process_running() {
  kill -0 "$pid" >/dev/null 2>&1 || return 1
  local state
  state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')"
  [[ -n "$state" && "$state" != Z* ]]
}

if ! process_running; then
  exit 0
fi

kill "$pid" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  process_running || exit 0
  sleep 0.1
done

kill -KILL "$pid" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  process_running || exit 0
  sleep 0.1
done

echo "stop-background-process: process $pid did not exit" >&2
exit 1
