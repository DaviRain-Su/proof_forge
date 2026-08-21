---
id: PLAN-EVM-CALL-ADDR-GAP
title: EVM static-QN hashed address vs deployment-address binding
status: draft
owner: engineering
updated: 2026-08-21
normative: false
---

# EVM-CALL-ADDR-GAP：hashed QN ≠ 部署地址

> Engineering inventory. Wave 2a changed generic void CALL (empty-account
> `extcodesize` fail closed); Wave 4 validates optional identity against a
> static engineering output directory. Still does **not** validate on-chain
> code-at-address or close `B-CALL-SEM`,
> formal TASK/TST, C-3, Anvil lossless, accepted-PRD expansion, or
> CREATE/CREATE2 binding. Does **not** invent a new `TASK-*`.

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
| Void `call` | `extcodesize==0` → `revert(0,0)` (Wave 2a); then `call(gas(), 0x{addr20}, 0, …)`; `iszero` → `revert(0,0)` |
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

`Tests.Materialization.EvmSmoke.testExternalCallGate` now pins Yul
`call(gas(), 0x{last20},` using `Targets.Evm.Keccak` on `"Oracle"` /
`"Ledger"`. That is an emitter-identity pin, **not** a deployment join.
G4 Anvil (`Counter` / `Accumulator` / `ArithOps` / `EventFlow`) does not
deploy code at a hashed QN address.

## 2. Empty-code consequence (why this is PARTIAL)

EVM `CALL` to an account with **no code** returns success and empty
returndata. Therefore a hashed stub with nobody deployed there is:

| Surface | Undeployed hashed address |
|---|---|
| void `call` | **Wave 2a:** reverts on `extcodesize==0` |
| result-bearing `call` | reverts on `returndatasize < 32` |
| `schedule` | succeeds; result discarded |

A passing void `call Oracle.feed(...)` now requires nonempty code at the
target (Wave 2a). That is still **not** a deployment-address join.
Reference consumes an environment response; Yul does not.

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
3. **Identity join** — **static half done (Wave 4):** an independent canonical
   evidence document maps exact callee/address to a fully inspected EVM
   engineering output; optional source/semantic and mandatory raw published
   `.bin` SHA-256 expectations are rechecked, and the expected identity table
   digest enters Plan/build/OutputSet provenance. **Deployment half open:** no
   receipt/RPC/block identity/code-at-address observation proves those `.bin`
   bytes are currently at the endpoint. A bare hex in Yul remains insufficient.
4. **Product `build` vs test-only** — product materialize must not start
   consuming Anvil placement. Tests may place code at the hashed address
   without claiming binding.
5. **Void success vs empty code** — **Wave 2a done:** fail closed when
   the target has no code (`extcodesize`). `schedule` still ignores
   success. Changing this was a semantic change, not a comment.

Do **not** treat Principal storage, `context.caller` / `context.self`
(`u32le(20)||addr20`), or `pf.assets` mint addresses as this binding.

## 4. Recommended next (serial)

1. **EVM-CALL-ADDR-PIN** — **done 2026-08-15**: CallGate / ScheduleGate
   Yul pin the exact last-20 hex via `Targets.Evm.Keccak`. No emitter
   change. Still not a deployment binding.
2. **Inspect residual** — **done 2026-08-19**: product `inspect` /
   `inspect --json` surfaces `callScheduleResidual=hashed-qn-no-deploy-bind`
   (inspect-only; not SupportClaim). Still not a deployment binding.
3. **B-CALL-SEM binding** — endpoint table and static artifact identity are
   done (ADR-0053 Wave 2/4). The remaining deployment-address join must first
   freeze receipt/block/code-at-address evidence; do not infer it from static
   evidence and do not start from Goal/drain.
4. Sparse Solana 55-step certificates for initialize / increment / overflow
   stay later and are not this EVM leaf.

## Non-claims

Not `B-CALL-SEM` closed. Not CREATE/CREATE2. Not Anvil callee placement or
on-chain code-at-address validation. Not a second call semantics. Not formal
D4 / C-3. Not accepted-PRD expansion. Wave 4 changes Plan/provenance and CLI
prepublication validation, not emitted Yul or capability claims.
