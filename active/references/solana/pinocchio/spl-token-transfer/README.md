# Pinocchio SPL Token Transfer Reference

This fixture is the second Rust/Pinocchio equivalence reference for the
ProofForge Solana SDK beta line. It mirrors
`Examples.Backend.Solana.Contracts.SplTokenTransferCheckedCpi`:

- instruction `transfer`
- tag byte `0`
- instruction data layout: `u8 tag` followed by little-endian `u64 amount`
- accounts: `last_transfer_amount`, `source`, `mint`, `destination`,
  `authority`, `spl_token`
- CPI: SPL Token `TransferChecked::new(source, mint, destination, authority,
  amount, 9).invoke()`
- observable state write: `last_transfer_amount = amount`

The default validation gate compares the checked-in reference manifest and
source constants against the ProofForge-generated artifact. It deliberately
avoids downloading Rust crates by default. To experiment with the native
Pinocchio build path, run:

```sh
PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1 \
  scripts/solana/pinocchio-spl-token-transfer-equivalence.sh
```

The live dual-deploy harness is:

```sh
scripts/solana/pinocchio-spl-token-transfer-live-equivalence.sh
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
- Pinocchio Token `TransferChecked` instruction docs:
  https://docs.rs/pinocchio-token/latest/pinocchio_token/instructions/struct.TransferChecked.html
- Solana token transfer semantics:
  https://solana.com/docs/tokens/basics/transfer-tokens
- Anchor Token CPI shape:
  https://www.anchor-lang.com/docs/tokens/basics/transfer-tokens
