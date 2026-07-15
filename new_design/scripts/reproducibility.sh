#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$root/.lake/build/bin/proof-forge-next"

rm -rf "$root/build/repro"

for run in a b; do
  for target in evm solana near noir; do
    lake env "$compiler" build Examples/Counter.lean --program Examples.Counter \
      --target "$target" -o "build/repro/$run/$target"
  done
done

/usr/bin/python3 -I -S "$root/scripts/check_reproducibility.py" \
  "$root/build/repro/a" "$root/build/repro/b"
