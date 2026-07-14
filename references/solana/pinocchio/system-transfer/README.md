# Pinocchio System Transfer Reference

This fixture is the first Rust/Pinocchio equivalence reference for the
ProofForge Solana SDK beta line. It mirrors
`Examples.Backend.Solana.Contracts.SystemCpi`:

- instruction `transfer`
- tag byte `0`
- instruction data layout: `u8 tag` followed by little-endian `u64 lamports`
- accounts: `last_transfer_lamports`, `payer`, `recipient`, `system_program`
- CPI: System Program `Transfer { from: payer, to: recipient, lamports }`
- observable state write: `last_transfer_lamports = lamports`

The default validation gate compares the checked-in reference manifest and
source constants against the ProofForge-generated artifact. It deliberately
avoids downloading Rust crates by default. To experiment with the native
Pinocchio build path, run:

```sh
PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1 \
  scripts/solana/pinocchio-system-transfer-equivalence.sh
```

The live dual-deploy harness is:

```sh
scripts/solana/pinocchio-system-transfer-live-equivalence.sh
```

It requires `cargo-build-sbf` to find Solana rustc/platform-tools. In
environments where `cargo` is owned by `rustup`, set
`PROOF_FORGE_PINOCCHIO_USE_RUSTUP=1`.
If the Solana rustup toolchain is missing or corrupted, run:

```sh
just solana-pinocchio-install-sbf-tools
```

Primary references:

- Pinocchio entrypoint, `no_allocator!`, and `cpi` feature docs:
  https://docs.rs/pinocchio/latest/pinocchio/
- Pinocchio System `Transfer` instruction docs:
  https://docs.rs/pinocchio-system/latest/pinocchio_system/instructions/struct.Transfer.html
- Solana CPI semantics:
  https://solana.com/docs/core/cpi
