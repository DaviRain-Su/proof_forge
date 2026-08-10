# Publishing `proof-forge-solana-client`

Offline Solana OutputSet verifier binary. **No network / deploy / wallet.**

Used by:

```bash
pf verify -t solana --artifact build/solana
# spawns: proof-forge-solana-client verify-artifacts --artifact-dir …
```

## Install (users)

```bash
cargo install proof-forge-solana-client --locked
# ensure it is on PATH, or:
export PROOF_FORGE_SOLANA_CLIENT="$(which proof-forge-solana-client)"
# or place next to `pf` in a Release bundle
```

## Publish (maintainers)

```bash
cargo test --manifest-path clients/solana-client/Cargo.toml --locked
cargo publish --manifest-path clients/solana-client/Cargo.toml --locked --dry-run
# real upload:
SC_PUBLISH=1 just solana-client-publish
```

Requires `cargo login` with crates.io token. Never commit tokens.
