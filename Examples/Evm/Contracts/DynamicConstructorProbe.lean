/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Dynamic constructor probe: exercises `cstring`, `cbytes`, and `u256array`
constructor params through the EVM target. Validates that the CLI ABI-encodes
dynamic types (head-offset + tail) into the initcode tail and the deploy
manifest records the schema.

Compile:
```
lake env proof-forge build --target evm --root . \
  -o build/evm/DynamicConstructor.bin \
  --evm-constructor-arg "name=hello" \
  --evm-constructor-arg "amounts=1,2,3" \
  Examples/Evm/Contracts/DynamicConstructorProbe.lean
```
-/
import ProofForge.Contract.Source

namespace DynamicConstructorProbe

open ProofForge.Contract.Source

contract_source DynamicConstructorProbe do
  constructor_param name : "cstring";
  constructor_param amounts : "u256array";

  state count : .u64

  entry «initialize» do
    count := u64 0;

  entry increment do
    let n : .u64 := count;
    count := n +! u64 1;

  query get returns(.u64) do
    return count;

end DynamicConstructorProbe