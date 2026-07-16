# Pinocchio Memo Reference

This fixture checks the ProofForge-generated Memo Program CPI program against a
minimal no-allocator Pinocchio reference. It covers the Lean-authored
`MemoCpi` SDK fixture:

- `log_memo`: classic 8-byte little-endian `u64` memo payload + state write
- `log_memo_bytes`: L1.3 multi-byte `fixedArray .u8 16` raw memo payload

Static equivalence:

```bash
scripts/solana/pinocchio-memo-equivalence.sh
```

Optional Pinocchio typecheck:

```bash
PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1 \
  scripts/solana/pinocchio-memo-equivalence.sh
```

Reference docs:

- Pinocchio Memo instruction:
  <https://docs.rs/pinocchio-memo/latest/pinocchio_memo/instructions/struct.Memo.html>
- SPL Memo program:
  <https://spl.solana.com/memo>
