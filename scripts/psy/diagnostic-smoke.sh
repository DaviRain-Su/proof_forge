#!/usr/bin/env bash
set -euo pipefail

# Validate that unsupported or malformed Psy IR shapes fail before source
# generation with stable, explicit diagnostics.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT"
lake build proof-forge >/dev/null
lake build ProofForge.Backend.Psy.Metadata >/dev/null
lake env lean --run Tests/PsyDiagnostics.lean
