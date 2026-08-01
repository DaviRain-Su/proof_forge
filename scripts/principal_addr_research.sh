#!/usr/bin/env bash
# PrincipalAddr (B-3) research pin — documentation helper (engineering only).
#
# Prints the exact Principal wire vs target address layout table that justifies
# keeping all Phase-1 targets on pilotPrincipalPolicyNone (fail-closed).
# No build, no network, no codegen. Exit 0 always.
#
# Companion: docs/research/12-target-coverage-matrix.md §B-3;
#            ProofForgeV2/Targets/EnvelopeV1.lean PilotPrincipalPolicy.
set -euo pipefail

cat <<'EOF'
PrincipalAddr (B-3) research pin — fail-closed (2026-08-02)

Wire Principal valueBytes (SPEC-SEM-WIRE-001 §5 / ValueBytesV1):
  layout  : u32 LE length || opaque body
  length  : 1 <= len <= maxTypeLengthV1 (4096)
  default : encodeU32le(1) || 0x00   (5 bytes total)
  ops     : identity-only eq/ne at Normalize; no arith/order/bitwise/unary

Target native identities (Phase-1):
  EVM address          : fixed 20 raw bytes (no length prefix; ABI word = 32B right-aligned)
  Solana pubkey/prog id: fixed 32 raw bytes (ed25519)
  NEAR account id      : UTF-8 string (not binary identity payload)
  Noir Field / Psy Felt: field elements (not opaque identity bytes)

Mismatch (no lossless exact canonical-bytes match):
  * Strip u32 prefix + pad/truncate to 20/32 invents a second identity spelling.
  * "Require body length == 20/32" still drops the wire length header and
    rejects legal Principal values of other lengths (1..19/21..4096 etc.).
  * Product call/schedule callees are static QualifiedName on Op.ExternalCall
    / Op.Schedule — not Principal ValueIds. Principal storage alone cannot
    unlock CALL/CPI without a new address-bearing expression surface.

Decision (PsyFelt-style honesty pin):
  * All Phase-1 targets: pilotPrincipalPolicyNone (admitPrincipal = false).
  * Do NOT open approximate Principal→address mapping on EVM/Solana.
  * EVM/Solana type-closure wording pins 20-byte / 32-byte mismatch.
  * Resolver still declines effect.synchronous-call / asynchronous-workflow
    on EVM/Solana (no address-bearing type).

Code anchors:
  ProofForgeV2/Semantic/Wire/ValueBytesV1.lean   (.principal decode)
  ProofForgeV2/Targets/EnvelopeV1.lean           (PilotPrincipalPolicy)
  ProofForgeV2/Targets/Evm/LowerSemanticV1.lean  (principalPolicy := none)
  ProofForgeV2/Targets/Solana/LowerSemanticV1.lean
  Tests/Materialization/Targets.lean             (N2c + B-3 wording pins)
  docs/research/12-target-coverage-matrix.md     §B-3

EOF
