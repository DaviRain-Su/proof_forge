import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S1 / ADR-0030 E3 Mollusk fixture (product path ELF under
-- solana-sbpf-cpi-elf-v1).
--
-- Solana has no tx.origin / CALLER opcode. Honest binding of
-- `context.caller : Principal` is the 32-byte pubkey of the ABI-specified
-- signer role `pf_caller` (AccountInfo.key + site-time is_signer). Result
-- materializes as Principal canonical wire `u32le(32)||pubkey32` → 9 leaves
-- (len + 8×UInt64 LE body; high 32 body bytes zero). This is identity read
-- only — NOT a transaction fee-payer / origin concept, and does not open
-- arbitrary Principal→Solana address/callee semantics.
--
-- `who` is ordinary T12 Principal ix-data (9×UInt64 LE), not an account role,
-- so pairwise-distinct outer keys stay intact and isMe can return true when
-- who wire equals the pf_caller pubkey. Ordinary Principal ix params are
-- physically validated before business comparison: len ∈ 1..64 and every body
-- byte at index ≥ len must be zero (noncanonical encodings Custom(1)).
--
-- Runtime expectations:
--   * isMe(who) returns 1 (Bool true as UInt64 LE) when who wire == pf_caller
--     pubkey and pf_caller is_signer
--   * isMe(who) returns 0 when who wire differs (pf_caller still signer;
--     different canonical Principal values remain allowed)
--   * pf_caller not signer → fail closed (Custom(1)) + full account snapshot hold
--   * noncanonical who (len=0, len=65, len=32 with nonzero high-tail) →
--     Custom(1) + full snapshot hold
--
-- Admission is caller-only: exact wire-owned `context.caller` requirement on
-- profile solana-sbpf-cpi-elf-v1. No extension.pf-assets / sync-call ticket.
program CallerIsMe where
  view isMe(who : Principal) : Bool do
    return context.caller == who

end Examples
