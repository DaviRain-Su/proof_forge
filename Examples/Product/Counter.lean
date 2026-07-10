/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical portable Counter shared across primary targets.

Compile the same module to EVM, Solana sBPF, and NEAR/Wasm by changing only
`--target`:

  lake env proof-forge build --target evm --root . \
    -o build/portable-counter/Counter.bin \
    --yul-output build/portable-counter/Counter.yul \
    --artifact-output build/portable-counter/Counter.proof-forge-artifact.json \
    Examples/Product/Counter.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/portable-counter/Counter.s \
    --artifact-output build/portable-counter/Counter.solana-artifact.json \
    Examples/Product/Counter.lean

  lake env proof-forge build --target wasm-near --root . \
    -o build/portable-counter/near \
    --artifact-output build/portable-counter/Counter.near-artifact.json \
    Examples/Product/Counter.lean

See `scripts/portable/counter-multi-target.sh` for a checked end-to-end demo.

NEAR native compare (colocated under testkit/compare/near/counter):
  just near-compare
  # optional: PROOF_FORGE_NEAR_SDK_BUILD=1 just near-compare
  # sandbox dual-deploy (real gas): just near-compare-live

Canonical **author** source. `ProofForge.Contract.Examples.Counter` aliases this
module. `ProofForge.IR.Examples.Counter` is a formal/CLI IR fixture with the
same shape (name/state/entrypoints); do not author against the IR path.
-/
import ProofForge.Contract.Source

namespace Examples.Product.Counter

open ProofForge.Contract.Source

contract_source Counter do
  state count : .u64

  quint_invariant countBounded := "count <= MAX_UINT"
  quint_liveness eventuallyPositive := "eventually(count > 0)"
  lean_invariant countBounded := "ProofForge.Contract.Examples.CounterInvariant.countBounded 3"
  lean_invariant countNonNegative := "ProofForge.Contract.Examples.CounterInvariant.countNonNegative"

  entry «initialize» do
    count := u64 0;

  entry increment do
    let n : .u64 := count;
    count := n +! u64 1;

  query get returns(.u64) do
    return count;

end Examples.Product.Counter
