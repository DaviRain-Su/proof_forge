#!/usr/bin/env bash
# Install the pinned Lean toolchain eagerly so later steps never trigger an
# unguarded network download through the elan shim.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
toolchain="$(cat "$ROOT/lean-toolchain")"

curl --retry 5 --retry-all-errors --connect-timeout 20 -sSfL \
  https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
  -o /tmp/proof-forge-elan-init.sh

# elan-init.sh downloads the elan binary with its own unguarded curl; wrap the
# whole invocation so transient CDN 5xx recovers instead of failing the job.
for attempt in 1 2 3; do
  if sh /tmp/proof-forge-elan-init.sh -y --default-toolchain "$toolchain"; then
    break
  fi
  if [ "$attempt" -lt 3 ]; then
    echo "elan-init attempt $attempt failed; retrying..." >&2
    sleep $((attempt * 5))
  else
    echo "elan-init failed after 3 attempts" >&2
    exit 1
  fi
done

export PATH="$HOME/.elan/bin:$PATH"
if elan toolchain list | awk '{print $1}' | grep -Fx "$toolchain" >/dev/null; then
  elan default "$toolchain"
  exit 0
fi

for attempt in 1 2 3; do
  if elan toolchain install "$toolchain"; then
    elan default "$toolchain"
    exit 0
  fi
  if [ "$attempt" -lt 3 ]; then
    echo "Lean toolchain install attempt $attempt failed; retrying..." >&2
    sleep $((attempt * 5))
  fi
done

echo "failed to install Lean toolchain after 3 attempts: $toolchain" >&2
exit 1
