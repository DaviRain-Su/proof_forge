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
  lake env "$compiler" build Examples/Accumulator.lean --program Examples.Accumulator \
    --target evm -o "build/repro/$run/evm-accumulator"
  lake env "$compiler" build Examples/Accumulator.lean --program Examples.Accumulator \
    --target solana -o "build/repro/$run/solana-accumulator"
  lake env "$compiler" build Examples/Accumulator.lean --program Examples.Accumulator \
    --target near -o "build/repro/$run/near-accumulator"
  lake env "$compiler" build Examples/Accumulator.lean --program Examples.Accumulator \
    --target noir -o "build/repro/$run/noir-accumulator"
done

/usr/bin/python3 -I -S "$root/scripts/check_reproducibility.py" \
  "$root/build/repro/a" "$root/build/repro/b"
