# Pinocchio SPL Token Close Account Reference

This fixture checks the ProofForge-generated SPL Token `close_account` CPI
program against a minimal no-allocator Pinocchio reference. It covers the
Lean-authored `SplTokenCloseAccountCpi` SDK fixture, where the generated program
closes a token account and records a marker in program-owned state.

Static equivalence:

```bash
scripts/solana/pinocchio-spl-token-close-account-equivalence.sh
```

Optional Pinocchio typecheck:

```bash
PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1 \
  scripts/solana/pinocchio-spl-token-close-account-equivalence.sh
```

Reference docs:

- Pinocchio Token `CloseAccount` instruction:
  <https://docs.rs/pinocchio-token/latest/pinocchio_token/instructions/struct.CloseAccount.html>
- SPL Token close-account semantics:
  <https://spl.solana.com/token#burning>
