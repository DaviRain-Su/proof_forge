# Native EVM Counter

Hand-written Solidity reference for `bm-counter` on `evm`.

| | |
|--|--|
| Source | `Counter.sol` |
| Mirrors | `Examples/Product/Counter.lean` |
| Lifecycle | `initialize()` → `increment()` → `get()` |

```sh
# Compile runtime bytecode (solc on PATH):
solc --bin --optimize --optimize-runs 200 \
  benchmarks/native/evm/Counter.sol \
  -o build/benchmarks/native-evm-counter --overwrite
```
