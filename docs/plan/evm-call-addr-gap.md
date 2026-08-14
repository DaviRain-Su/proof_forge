---
id: PLAN-EVM-CALL-ADDR-GAP
title: EVM static-QN hashed address vs deployment-address binding
status: draft
owner: engineering
updated: 2026-08-15
normative: false
---

# EVM-CALL-ADDR-GAP：hashed QN ≠ 部署地址

> Engineering inventory only. Does **not** change the emitter, Plan, IR, or
> resolver. Does **not** close `B-CALL-SEM`, formal TASK/TST, C-3, Anvil
> lossless, accepted-PRD expansion, or CREATE/CREATE2 binding.
> Does **not** invent a new `TASK-*`.

Authority: [`01-evm.md`](../targets/01-evm.md) ·
[`0029-portable-cross-program-interop.md`](../adr/0029-portable-cross-program-interop.md)
§「callee 部署地址绑定」·
[`engineering-backlog.md`](../engineering-backlog.md) `B-CALL-SEM` ·
`ProofForgeV2/Targets/Evm/EmitIRV1.lean` AddressBearing arms.

## 1. What the product actually emits

Generic (non-`pf.assets`, non-`pf.crypto`) `call` / `schedule` stay
**static QualifiedName**. The Yul target is **not** a deployed program's
CREATE/CREATE2 address and **not** a Principal ValueId.

| Step | Code fact |
|---|---|
| Split | `callee[0..n-2]` = target path; last component = method. `n ≥ 2`. |
| Path string | `String.intercalate "."` of the target-path components (UTF-8). `Oracle.feed` → `"Oracle"`. `Ledger.daily` → `"Ledger"`. |
| Address | last 20 bytes of Ethereum Keccak-256 (`Targets.Evm.Keccak`, domain `0x01`, not SHA3-256 `0x06`) of that UTF-8 path |
| Selector | first 4 bytes of Keccak-256 of `method(uintN,…)` (`Keccak.selector`) |
| `CALL` value | always `0` |
| Void `call` | `call(gas(), 0x{addr20}, 0, …)`; `iszero` → `revert(0,0)` |
| Result-bearing `call` | same address; `returndatasize ≥ 32` + unsigned width guard |
| `schedule` | same address/selector; success is `pop`'d (same-tx fire-and-forget) |

`pf.crypto.*` and `pf.assets` do **not** use this hashed AddressBearing path.
Crypto is precompile/`keccak256` opcode. Token transfer is the sole
controlled dynamic callee (`u32le(20)||addr20` mint Principal).

Worked examples (Ethereum Keccak, same pad as `Targets.Evm.Keccak`):

| QN | path UTF-8 | last-20 address |
|---|---|---|
| `Oracle.feed` | `Oracle` | `e8bbb361ae4c140fabb5b8c363bd6282ded34a90` |
| `Ledger.daily` | `Ledger` | `c7ad2f1a51d91ed07c4cc2b5bcea3682b0ac30b2` |

`Tests.Materialization.EvmSmoke.testExternalCallGate` only asserts Yul contains
`call(gas(), 0x` and an `iszero` revert. It does **not** pin the 20-byte
digest. G4 Anvil (`Counter` / `Accumulator` / `ArithOps` / `EventFlow`) does
not deploy code at a hashed QN address.

## 2. Empty-code consequence (why this is PARTIAL)

EVM `CALL` to an account with **no code** returns success and empty
returndata. Therefore a hashed stub with nobody deployed there is:

| Surface | Undeployed hashed address |
|---|---|
| void `call` | succeeds; later state writes still run |
| result-bearing `call` | reverts on `returndatasize < 32` |
| `schedule` | succeeds; result discarded |

A passing void `call Oracle.feed(...)` is **not** evidence that an oracle
contract exists. Reference consumes an environment response; Yul does not.

## 3. What a real binding would have to decide

ADR-0029 already parks this on **NetworkProfile / registry**, not on the
portable call surface. Closing it is a **product decision** (`B-CALL-SEM`),
not a silent emitter tweak. Any later slice must pick, version, and fail
closed:

1. **Who mints the 20 bytes** — compile-time table, NetworkProfile, or
   post-deploy receipt. Hashed stub cannot stay an implicit default once a
   binding exists.
2. **Which EVM address it is** — CREATE, CREATE2 (initcode+salt), or a
   pre-placed Anvil/`cast` address. Those three are not interchangeable.
3. **Identity join** — callee `sourceHash` / `semanticHash` / artifact
   digest must equal the code at that address. A bare hex in Yul is not a
   join.
4. **Product `build` vs test-only** — product materialize must not start
   consuming Anvil placement. Tests may place code at the hashed address
   without claiming binding.
5. **Void success vs empty code** — keep today's empty-account success, or
   fail closed when the target has no code. Changing this is a semantic
   change, not a comment.

Do **not** treat Principal storage, `context.caller` / `context.self`
(`u32le(20)||addr20`), or `pf.assets` mint addresses as this binding.

## 4. Recommended next (serial)

1. **EVM-CALL-ADDR-PIN** (implementable, this wave): pin CallGate /
   ScheduleGate Yul to the exact last-20 hex above. No emitter change.
   Still not a deployment binding.
2. **B-CALL-SEM binding** (decision, skip): versioned address table +
   identity join. Do not start from Goal/drain.
3. Sparse Solana 55-step certificates for initialize / increment / overflow
   stay later and are not this EVM leaf.

## Non-claims

Not `B-CALL-SEM` closed. Not CREATE/CREATE2. Not Anvil callee placement.
Not a second call semantics. Not formal D4 / C-3. Not accepted-PRD
expansion. Not an emitter or capability change.
