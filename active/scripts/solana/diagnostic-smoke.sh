#!/usr/bin/env bash
set -euo pipefail

# V-GATE-SOLANA-05 (capability-checker half): the `solana-sbpf-asm` target
# rejects portable IR modules using capabilities it does not support —
# principally the generic `crosscall.invoke` family, since Solana uses
# `crosscall.cpi` (D-027). Each case cites both the target id and the
# capability id in the diagnostic.
#
# Prerequisites: Lean toolchain (lean-toolchain / lake).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT"
lake build proof-forge >/dev/null
lake env lean --run Tests/Backend/Solana/SolanaDiagnostics.lean