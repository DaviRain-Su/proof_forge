/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable ArrayExample shared across primary targets.

Demonstrates local fixed-array literals, element access, and reductions in
`contract_source` syntax. Compile the same module to EVM, Solana sBPF, and
NEAR/Wasm by changing only `--target`.

See `scripts/portable/array-example-multi-target.sh` for a checked end-to-end
demo.
-/
import ProofForge.Contract.Source

namespace Examples.Product.ArrayExample

open ProofForge.Contract.Source

contract_source ArrayExample do
  query sizeOf3 returns(.u64) do
    return u64 3;

  query getElem returns(.u64) do
    let xs : .memoryRef .u64 := arrayLiteral .u64 #[u64 10, u64 20, u64 30];
    return arrayGet xs (u64 1);

  query sumOf3 returns(.u64) do
    let xs : .memoryRef .u64 := arrayLiteral .u64 #[u64 10, u64 20, u64 30];
    return (arrayGet xs (u64 0)) +! (arrayGet xs (u64 1)) +! (arrayGet xs (u64 2));

  query outOfBounds returns(.u64) do
    let xs : .memoryRef .u64 := arrayLiteral .u64 #[u64 10, u64 20, u64 30];
    return arrayGet xs (u64 3);

end Examples.Product.ArrayExample
