# RFC 0015: ZK hash + cross-program-call portability across EVM / Psy / Aleo

Status: **Draft**
Scope: portable IR surface
Blocks: `aleo-leo` `crypto.hash` lowering + cross-circuit lowering (both currently
honest rejects); informs `psy-dpn` hash/digest representation.
Related: RFC 0003 (portable IR), RFC 0014 (unified semantic lowering),
`docs/targets/aleo-leo.md`, `docs/targets/psy-dpn.md`.

## Problem

After the `aleo-leo` backend reached feature parity with Psy for everything the
portable IR can express, two capability gaps remain as **honest rejects**, and
both are portable-IR-level — not Aleo-lowering-level — problems:

1. **`crypto.hash`.** The portable `ValueType.hash` is a 32-byte / 4×u64 digest
   (`Literal.hash4 a b c d`, `byteWidth = 32`), and the hash ops
   (`Expr.hashValue a b c d`, `Expr.hash preimage`, `Expr.hashTwoToOne l r`)
   are multi-component. This models **EVM keccak** exactly. Aleo/Leo hash
   intrinsics take a **single** primitive and produce a `field` / `[bool; N]` /
   integer digest — so there is no faithful 4×u64 mapping, and Aleo rejects.
2. **Cross-program call (`crosscallInvoke`).** The portable op is
   runtime-address-based (`crosscallInvoke (targetContractId : Expr) (methodId :
   Expr) (args)`). Leo's `_dynamic_call(prog, net, func, args)` is
   **identifier-based** (compile-time program/network/function names), so the
   mapping is lossy, and Aleo rejects.

Both also affect Psy (the other ZK target) and any future ZK/app-chain target,
so the design belongs at the portable-IR layer.

## Survey (grounded in the in-tree sources + ProvableHQ/leo)

### Hashing

| Target | Algorithm | Digest type | Preimage | Source |
|---|---|---|---|---|
| EVM | keccak256 | `bytes32` ≡ portable `Hash` (4×u64) | packed args (multi) | `Backend/Evm/Lower.lean` (`hashValue a b c d` → keccak) |
| Psy | Psy-native | `Hash` (Psy-defined type) | multi (`hashValue`/`hash`/`hashTwoToOne`) | `Backend/Psy/IR/Common.lean` (`.hash => "Hash"`) |
| Aleo/Leo | Poseidon2/4/8, Pedersen64/128, BHP256/512/768/1024, **Keccak256/384/512**, SHA3 | `field` / `group` / `address` / `u64` / `[bool; 256]` | **single primitive** | `ProvableHQ/leo documentation/language/operators/cryptographic_operators.md` |

Two facts drive the design:

- **Hashing is *capability-portable*, not *value-portable*.** Every target with
  `crypto.hash` can hash, but keccak ≠ Poseidon — the same preimage yields
  different digests on EVM vs Aleo. A portable contract that hashes and compares
  digests across chains is not byte-equivalent. (This is inherent, not a bug.)
- **The digest *type* is already target-resolved.** Psy proves the pattern: Psy
  takes the *same* portable hash ops (`hashValue`/`hash`/`hashTwoToOne`) and the
  *same* portable `Hash` type, but maps both to a **Psy-native** digest — not
  keccak, not 4×u64. EVM resolves `Hash` to `bytes32`. So the portable `Hash` is
  an **opaque digest token** whose concrete representation is each target's
  choice. Aleo is not fundamentally blocked; it is blocked only on **choosing**
  its representation (the convention Psy already adopted for itself).

The genuinely Aleo-specific friction is the **single-input** hash: portable
`hashValue`/`hashTwoToOne` are multi-component, Leo hashes one primitive.

### Cross-program call

| Target | Call shape | Addressing |
|---|---|---|
| EVM | `CALL`/`STATICCALL`/`DELEGATECALL` | runtime 20-byte address + 4-byte selector |
| Solana / NEAR | CPI / promise | runtime pubkey / account id |
| Aleo/Leo | `_dynamic_call(prog, net, func, args)` / static `import` | **identifier** (program/network/function names) |

Account-chains (EVM/Solana/NEAR) address callees by a runtime identifier derived
from a public key / deploy. App-chains (Aleo) address callees by
compile-time program identifiers. The portable `crosscallInvoke(target : Expr,
methodId : Expr)` assumes the account-chain model.

## Design

### Hash: family-resolved digest + native algorithm, with a value-portable opt-in

**Decision 1 — the portable `Hash` is an opaque, target-resolved digest type
(keep the type; standardize the contract).**

- EVM: `bytes32` (4×u64) — status quo.
- Psy: Psy `Hash` — status quo.
- Aleo: **`field`** (a Poseidon digest is a single field element; the natural
  ZK representation). **This single convention unblocks Aleo `crypto.hash`.**

Record this in `docs/capability-registry.md` as the `crypto.hash` "digest
representation per family" so each target's choice is explicit rather than
implicit.

**Decision 2 — hash ops lower to the target's native algorithm
(capability-portable by default).**

- `.hash preimage` → EVM `keccak(preimage)` / Psy-hash / Aleo
  `Poseidon2::hash_to_field(preimage)` (preimage coerced to `field`/`u64`).
- `.hashTwoToOne l r` → each target's pairwise idiom; Aleo folds
  `Poseidon2::hash_to_field(l) ⊕ hash_to_field(r)` or hashes a packed pair.
- `.hashValue a b c d` → EVM packs 4×u64 + keccak; Aleo folds pairwise (the
  4×u64 packing does not fit one ~252-bit field, so fold: combine four into two
  then one).

Default semantics: **the digest is not guaranteed equal across families.** State
this explicitly in the portable IR doc and in `validateModule` diagnostics when a
module both hashes and compares digests (a cross-family portability warning, not
an error).

**Decision 3 (opt-in, future) — value-portable hashing via a fixed algorithm.**

Leo *has* `Keccak256::hash_to_bits` / `hash_to_address`. Introduce an optional
algorithm tag on the hash op (e.g. `Expr.hash preimage (.keccak)` /
`(.poseidon)` / `(.native)`) so authors who need **cross-chain identical
digests** (e.g. EVM↔Aleo light-client verification) can force keccak. `native`
(default) preserves today's per-family behavior. This is additive and can land
later; Decisions 1+2 are the unblock.

### Cross-program call: an identifier-based surface alongside the runtime-address one

**Decision 4 — add a portable *named-callee* call op for app-chains, keep
`crosscallInvoke` for account-chains.**

- Keep `crosscallInvoke(target : Expr, methodId : Expr, args)` for account-chain
  targets (EVM/Solana/NEAR) — status quo.
- Add `crosscallNamed(programId : String, method : String, args)` (or a
  `TargetFamily.zkCircuitSourcegen`-resolved variant) for app-chain targets:
  Aleo lowers it to `_dynamic_call(programId, 'aleo', method, args)` or a static
  `import` + qualified call.
- Each op carries a distinct capability so `validateCapabilities` routes
  correctly: account chains reject `crosscallNamed`, app chains reject
  `crosscallInvoke`.

This keeps the account-chain model untouched and gives ZK/app targets an honest,
non-lossy path.

## Consequences

- **Aleo `crypto.hash` becomes implementable** (Decision 1: `Hash ≡ field`).
  Follow-up commit: `valueType .hash => .field`, `leoLiteral hash4 → field
  fold`, `buildExpr .hash/.hashValue/.hashTwoToOne → Poseidon2` with pairwise
  folding; `validateValueType`/`inferExprType` treat `Hash` as `field` in the
  Aleo target. A `HashProbe`-style fixture becomes the regression.
- **Psy is unaffected** (it already does target-resolved hashing); the RFC only
  names the contract Psy already implements.
- **EVM is unaffected** (`Hash ≡ bytes32`, keccak — status quo).
- **Cross-circuit** on Aleo becomes implementable after Decision 4 (separate,
  smaller change).
- **No portable-IR breaking change** for Decisions 1/2 (representation choices +
  target-native lowering, as Psy already does). Decision 3 (algorithm tag) and
  Decision 4 (named-callee op) are additive.

## Alternatives considered

- **Status quo (Aleo rejects hash forever).** Rejected — hashing is central to
  ZK (commitments, Merkle roots); an Aleo backend that cannot hash is not a
  credible ZK target.
- **Force keccak everywhere (value-portable).** Rejected — keccak is not
  ZK-friendly (expensive in-circuit); ZK targets should default to Poseidon.
  Offered only as the opt-in (Decision 3).
- **Replace portable `Hash` (4×u64) with a single `field` globally.** Rejected —
  breaks EVM's bytes32 storage layout and existing keccak semantics. Keep
  `Hash` opaque; resolve per family (Psy's approach).

## Open decisions (need sign-off)

1. Confirm **Aleo `Hash ≡ field`** (Decision 1) vs `[u64; 4]` struct (more
   faithful to the 4×u64 shape, but heavier and un-ZK-idiomatic). Recommendation:
   `field`.
2. Confirm **default algorithm per family** (EVM keccak / ZK Poseidon) vs a
   single global default. Recommendation: per-family. **(Resolved 2026-07-10:
   per-family landed — Aleo Poseidon via D1+2.)**
3. **Decision 3 (algorithm tag): DEFERRED.** Landing it would require either
   modifying `Expr.hash`'s arity (breaks 61 `.hash` match sites across all
   backends) or adding a new `Expr.hashWith` constructor (a ~30-file cascade
   like `crosscallNamed`). For an *opt-in* value-portable feature that most
   contracts do not need, that cost is not justified now; revisit if a real
   cross-chain Merkle/bridge use case demands forced-keccak digests.
4. **Cross-circuit (Decision 4): LANDED 2026-07-10** (`crosscallNamed` → static
   qualified call + import).
