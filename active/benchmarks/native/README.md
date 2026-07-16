# Native Counter corpus (B1.2)

Hand-written baselines for ProofForge vs native comparison.

| Scenario | EVM | Solana | NEAR |
|----------|-----|--------|------|
| `bm-counter` | [`evm/Counter.sol`](evm/Counter.sol) | [`solana/counter/`](solana/counter/) | [`near/counter-rs/`](near/counter-rs/) |
| `bm-value-vault` | [`evm/ValueVault.sol`](evm/ValueVault.sol) | — (skip) | `testkit/compare/near/value-vault` |
| `bm-ownable` | [`evm/Ownable.sol`](evm/Ownable.sol) | — (skip) | `testkit/compare/near/ownable` |

```sh
just benchmark-native-counter   # Counter compile/typecheck
just benchmark-matrix           # full multi-scenario matrix
```
