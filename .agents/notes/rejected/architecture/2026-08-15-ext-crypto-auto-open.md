# Agent Note: Do not auto-open Merkle, Bytes, or extra signatures after S5

Status: rejected — S5 honesty pins are not a license to grow `extension.crypto`

## Problem

S5 `pf.crypto.sha256` is lowered on EVM / Solana / NEAR. EVM also has
`ecdsaRecoverSecp256k1`. The other eleven targets now name-reject recover
and most `pf.crypto.*` calls. The next-wave queue is empty, so the obvious
continuation is “keep going”: Merkle, `sha256Bytes`, Solana ed25519, or
copying Psy `hash*` / keccak onto other targets.

That continuation would either touch the shared kernel (Bytes arity) or
pretend a missing host is a portable hash.

## Proposal

Treat the empty drain queue as authorization to implement the next
`EXT-CRYPTO` bucket (Merkle verify, Bytes digest ABI, or another target
signature leaf) without a new product slice.

## Alternatives considered

- **EVM-only Merkle (`CRYPTO-C1+C2`) as silent next Goal row** — rejected
  for auto-drain: there is no standard Merkle precompile; a guest loop is
  a new QN, gas story, and IBC/bridge product question. Design lives in
  [`docs/research/27-extension-crypto-design.md`](../../../../docs/research/27-extension-crypto-design.md).
- **Same QN, Bytes / streaming arity (`CRYPTO-B1`)** — rejected for this
  wave: Normalize / Wire must admit Bytes as a `pf.crypto` argument. That
  is a shared-core cutover, not a target leaf.
- **Solana ed25519 / NEAR verify** — rejected as the automatic follow-on:
  ed25519 is an account-meta / sysvar story and hangs on `B-CALL-SEM`.
  NEAR has no cheap first-class verify.
- **Reuse Psy `hashNoPad` / `hashPad` / `hashTwoToOne` / `keccak256`** —
  rejected: those are Psy DPN gadgets. They are not S5 sha256 and do not
  authorize another target.
- **One `pf.crypto.verify`** — already rejected by RPT-027; keep split QNs.

`EXT-CRYPTO` stays pending. Open a named slice only after a product pick
among Merkle-on-EVM, Bytes ABI, or a specific foreign signature leaf.
