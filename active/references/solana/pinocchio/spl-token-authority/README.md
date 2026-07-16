# Pinocchio SPL Token Authority Reference

This fixture checks the ProofForge-generated SPL Token `set_authority` CPI
program against a minimal no-allocator Pinocchio reference. It covers the
Lean-authored `SplTokenAuthorityCpi` SDK fixture, where the generated program
sets mint authority to a new authority pubkey read from an input account.

Static equivalence:

```bash
scripts/solana/pinocchio-spl-token-authority-equivalence.sh
```

Optional Pinocchio typecheck:

```bash
PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1 \
  scripts/solana/pinocchio-spl-token-authority-equivalence.sh
```

Dual-deploy live equivalence:

```bash
scripts/solana/pinocchio-spl-token-authority-live-equivalence.sh
```

Reference docs:

- Pinocchio Token `SetAuthority` instruction:
  <https://docs.rs/pinocchio-token/latest/pinocchio_token/instructions/struct.SetAuthority.html>
- Pinocchio Token `AuthorityType` values:
  <https://docs.rs/pinocchio-token/latest/pinocchio_token/instructions/enum.AuthorityType.html>
- SPL Token `AuthorityType` values:
  <https://docs.rs/spl-token/latest/spl_token/instruction/enum.AuthorityType.html>
