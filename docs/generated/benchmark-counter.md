# Benchmark matrix (generated)

Generated: `2026-07-10T11:27:36Z`

Source rows: `build/benchmarks/bm-*_*_{proofforge,native}.json`

Rules:

- No cross-chain score (gas ≠ CU ≠ fuel).
- Behavior parity is gated separately (`just benchmark-behavior-gate`).
- Empty costs mean the runner deferred that dimension (honest `—`).

## `bm-aleo-counter`

| Target | PF ok | Native ok | PF artifact | Native artifact | PF/native size | PF costs | Native costs |
|--------|------:|----------:|------------:|----------------:|---------------:|----------|--------------|
| `aleo-leo` | yes | yes | 519 | 519 | 1.00× | — | — |

<details><summary>Row notes</summary>

- **aleo-leo/proofforge**: PF .leo source + leo toolchain present (leo 4.0.2 (unknown unknown) features=[]); full prove deferred (experimental)
- **aleo-leo/native**: hand-written golden Examples/Backend/Aleo/Counter.golden.leo (source size baseline)

</details>
## `bm-counter`

| Target | PF ok | Native ok | PF artifact | Native artifact | PF/native size | PF costs | Native costs |
|--------|------:|----------:|------------:|----------------:|---------------:|----------|--------------|
| `evm` | yes | yes | 180 | 359 | 0.50× | — | gas[initialize=25626, increment=43581, get=23357] |
| `solana-sbpf-asm` | yes | yes | 1384 | 0 | — | — | — |
| `wasm-near` | yes | yes | 403 | 54785 | 0.01× | fuelΔ[initialize=17, increment=44, get=33] | — |

<details><summary>Row notes</summary>

- **evm/proofforge**: runtime bytecode built; evm_gas requires Foundry/revm (B1.4+)
- **evm/native**: Anvil/cast lifecycle; native Solidity Counter.sol
- **solana-sbpf-asm/proofforge**: ELF built via sbpf; solana_cu requires Mollusk/Surfpool (B1.4+)
- **solana-sbpf-asm/native**: cargo check ok; cargo-build-sbf failed (see build log); CU deferred
- **wasm-near/proofforge**: offline-host; wasmtime fuel delta (not NEAR gas)
- **wasm-near/native**: near-sdk host tests + release wasm; fuel not comparable to PF offline-host ABI

</details>

## `bm-ownable`

| Target | PF ok | Native ok | PF artifact | Native artifact | PF/native size | PF costs | Native costs |
|--------|------:|----------:|------------:|----------------:|---------------:|----------|--------------|
| `evm` | yes | yes | 293 | 520 | 0.56× | — | gas[init=25792, transferOwnership=0, renounceOwnership=26353] |
| `solana-sbpf-asm` | yes | no | 2744 | 0 | — | — | — |
| `wasm-near` | yes | yes | 627 | 160515 | 0.00× | — | — |

<details><summary>Row notes</summary>

- **evm/proofforge**: runtime bytecode; gas via native Anvil runner
- **evm/native**: Anvil/cast Ownable.sol lifecycle
- **solana-sbpf-asm/proofforge**: ELF size only; owner is u64 projection (not AccountId)
- **solana-sbpf-asm/native**: skipped: no Pinocchio Ownable corpus (B1.7 EVM/NEAR focus)
- **wasm-near/proofforge**: wasm size; PF owner is u64 projection vs near-sdk AccountId (parity is structural)
- **wasm-near/native**: near-sdk host tests (testkit/compare/near/ownable)

</details>

## `bm-psy-counter`

| Target | PF ok | Native ok | PF artifact | Native artifact | PF/native size | PF costs | Native costs |
|--------|------:|----------:|------------:|----------------:|---------------:|----------|--------------|
| `psy-dpn` | yes | yes | 1065 | 1065 | 1.00× | — | — |

<details><summary>Row notes</summary>

- **psy-dpn/proofforge**: PF .psy source emit (fixture counter); DPN bytecode metrics require dargo
- **psy-dpn/native**: hand-written golden Examples/Backend/Psy/Counter.golden.psy (source size baseline)

</details>

## `bm-value-vault`

| Target | PF ok | Native ok | PF artifact | Native artifact | PF/native size | PF costs | Native costs |
|--------|------:|----------:|------------:|----------------:|---------------:|----------|--------------|
| `evm` | yes | yes | 1326 | 745 | 1.78× | — | gas[initialize=65847, deposit=32139, get_balance=23425] |
| `solana-sbpf-asm` | yes | no | 5088 | 0 | — | — | — |
| `wasm-near` | yes | yes | 2053 | 156142 | 0.01× | fuelΔ[initialize=1293, get_balance=86, deposit=1589] | — |

<details><summary>Row notes</summary>

- **evm/proofforge**: runtime bytecode; evm_gas deferred (native runner has Anvil gas)
- **evm/native**: Anvil/cast ValueVault.sol lifecycle
- **solana-sbpf-asm/proofforge**: ELF via sbpf; CU deferred
- **solana-sbpf-asm/native**: skipped: no Pinocchio ValueVault corpus yet (Counter-only native Solana in B1.2)
- **wasm-near/proofforge**: offline-host initialize(100)/deposit(50); fuelΔ (not NEAR gas)
- **wasm-near/native**: near-sdk host tests + release wasm; dual-deploy gas via just near-compare-value-vault-live

</details>
