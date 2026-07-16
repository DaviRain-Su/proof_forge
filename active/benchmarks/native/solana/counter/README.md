# Native Solana Counter (Pinocchio-class)

Hand-written reference for `bm-counter` on `solana-sbpf-asm`.

| | |
|--|--|
| Baseline class | Pinocchio `no_allocator` (not Anchor) |
| Mirrors | `Examples/Product/Counter.lean` |
| Tags | `0=initialize`, `1=increment`, `2=get` |
| State | account 0, LE `u64` at offset 0 |

```sh
# Optional host typecheck:
cargo check --manifest-path benchmarks/native/solana/counter/Cargo.toml --features bpf-entrypoint

# Full sBPF (needs platform-tools):
cargo-build-sbf --manifest-path benchmarks/native/solana/counter/Cargo.toml
```
