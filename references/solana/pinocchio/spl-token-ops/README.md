# Pinocchio SPL Token Ops Reference

This fixture is a Rust/Pinocchio equivalence reference for the ProofForge
generated SPL Token `mint_to`/`burn`/`approve`/`revoke` CPI program.

It intentionally stays small:

- no allocator through `no_allocator!()`
- entrypoint dispatch tags `0..3` matching the generated ProofForge fixture
- account order matching `Examples.Backend.Solana.Contracts.SplTokenOpsCpi`
- CPI calls through Pinocchio Token `MintTo`, `Burn`, `Approve`, and `Revoke`
- state writes at offsets `0`, `8`, `16`, and `24`

The default equivalence gate is:

```sh
scripts/solana/pinocchio-spl-token-ops-equivalence.sh
```

For an optional typecheck of the Pinocchio build path, run:

```sh
PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1 \
  scripts/solana/pinocchio-spl-token-ops-equivalence.sh
```

The live dual-deploy harness is:

```sh
scripts/solana/pinocchio-spl-token-ops-live-equivalence.sh
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
- Pinocchio Token `MintTo` instruction docs:
  https://docs.rs/pinocchio-token/latest/pinocchio_token/instructions/struct.MintTo.html
- Pinocchio Token `Burn` instruction docs:
  https://docs.rs/pinocchio-token/latest/pinocchio_token/instructions/struct.Burn.html
- Pinocchio Token `Approve` instruction docs:
  https://docs.rs/pinocchio-token/latest/pinocchio_token/instructions/struct.Approve.html
- Pinocchio Token `Revoke` instruction docs:
  https://docs.rs/pinocchio-token/latest/pinocchio_token/instructions/struct.Revoke.html
