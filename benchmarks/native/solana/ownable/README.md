# Native Solana Ownable

This crate is an independent Pinocchio implementation used only by the CMP-3
native differential suite. It does not import ProofForge compiler or IR code.

Host typecheck:

```bash
cargo check --manifest-path benchmarks/native/solana/ownable/Cargo.toml \
  --features bpf-entrypoint
```

Build the sBPF oracle with the toolchain pinned in the v1 reference manifest:

```bash
cargo-build-sbf \
  --manifest-path benchmarks/native/solana/ownable/Cargo.toml \
  --features bpf-entrypoint
```
