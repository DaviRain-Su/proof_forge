# Native NEAR Counter

Hand-written near-sdk reference for `bm-counter` on `wasm-near`.

| Path | Role |
|------|------|
| [`../counter-rs/`](../counter-rs/) | **Primary B1 corpus** (vendored near-sdk-rs Counter) |
| `testkit/compare/near/counter` | Live dual-deploy compare driver (`just near-compare`) |

```sh
cargo test --manifest-path benchmarks/native/near/counter-rs/Cargo.toml --features host-tests
# dual-deploy compare (optional):
just near-compare
```
