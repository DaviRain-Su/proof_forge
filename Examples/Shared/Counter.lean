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
    Examples/Shared/Counter.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/portable-counter/Counter.s \
    --artifact-output build/portable-counter/Counter.solana-artifact.json \
    Examples/Shared/Counter.lean

  lake env proof-forge build --target wasm-near --root . \
    -o build/portable-counter/near \
    --artifact-output build/portable-counter/Counter.near-artifact.json \
    Examples/Shared/Counter.lean

See `scripts/portable/counter-multi-target.sh` for a checked end-to-end demo.

`ProofForge/Contract/Examples/Counter.lean` is a compatibility alias for this
source so tests and formal gates keep one canonical authoring surface.
-/
import ProofForge.Contract.Source

namespace Examples.Shared.Counter

open ProofForge.Contract.Source

contract_source Counter do
  state count : .u64

  quint_invariant countBounded := "count <= MAX_UINT"
  quint_liveness eventuallyPositive := "eventually(count > 0)"

  entry «initialize» do
    count := u64 0;

  entry increment do
    let n : .u64 := count;
    count := n +! u64 1;

  query get returns(.u64) do
    return count;

end Examples.Shared.Counter
