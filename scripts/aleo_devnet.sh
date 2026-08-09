#!/usr/bin/env bash
# Ownership-safe Aleo local DevNet lifecycle wrapper (host-heavy; not ordinary CI).
#
# Each start uses a fresh ledger, loopback-only REST listeners, and an exact PID
# inventory. Stop never performs global process-name discovery.
#
# Authority: docs/targets/09c-aleo-network.md
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec /usr/bin/python3 -I -S "$root/scripts/aleo_devnet.py" "$@"
