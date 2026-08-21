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
> `extcodesize` fail closed). The EVM identity follow-on now joins explicit local
> callee outputs and checks runtime `EXTCODEHASH` at each bound call site. It
> still does **not** close `B-CALL-SEM`, formal TASK/TST, C-3, Anvil lossless,
> accepted-PRD expansion, deployment receipt, or CREATE/CREATE2 binding. Does
> **not** invent a new `TASK-*`.

Authority: [`01-evm.md`](../targets/01-evm.md) ·
[`0029-portable-cross-program-interop.md`](../adr/0029-portable-cross-program-interop.md)
§「callee 部署地址绑定」·
[`engineering-backlog.md`](../engineering-backlog.md) `B-CALL-SEM` ·
`ProofForgeV2/Targets/Evm/EmitIRV1.lean` AddressBearing arms.

## 1. What the product actually emits

Generic (non-`pf.assets`, non-`pf.crypto`) `call` / `schedule` stay
**static QualifiedName**. Without `--bindings`, the Yul target remains the
historical hash stub. With an EVM table, the target is its pre-placed 20-byte
address, but that address is still **not** derived from a deployment receipt,
CREATE/CREATE2, or a Principal ValueId.

| Step | Code fact |
|---|---|
| Split | `callee[0..n-2]` = target path; last component = method. `n ≥ 2`. |
| Path string | `String.intercalate "."` of the target-path components (UTF-8). `Oracle.feed` → `"Oracle"`. `Ledger.daily` → `"Ledger"`. |
| Address, no bind | last 20 bytes of Ethereum Keccak-256 (`Targets.Evm.Keccak`, domain `0x01`, not SHA3-256 `0x06`) of that UTF-8 path |
| Address, bind | exact lowercase 20-byte address from the matched `proof-forge.call-bind.v1` row |
| Selector | first 4 bytes of Keccak-256 of `method(uintN,…)` (`Keccak.selector`) |
| `CALL` value | always `0` |
| Bound identity | every row requires complete source/semantic/runtime-artifact SHA-256; one exact explicit local callee output must match program name + digests |
| Bound runtime | finalizer-owned `{program}.runtime.bin` is lowercase hex + LF; artifact SHA-256 hashes those file bytes; `EXTCODEHASH` expected value is Ethereum Keccak-256 of the decoded runtime bytes |
| Void `call` | `extcodesize==0` → `revert(0,0)` (Wave 2a); bound path additionally checks `extcodehash==expected`; then `call(gas(), 0x{addr20}, 0, …)`; `iszero` → `revert(0,0)` |
| Result-bearing `call` | bound path checks `extcodehash==expected`; same address; `returndatasize ≥ 32` + unsigned width guard |
| `schedule` | bound path checks `extcodehash==expected`; same address/selector; success is `pop`'d (same-tx fire-and-forget) |

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

## 2. Local output authority and remaining deployment gap

The product accepts no RPC or ambient registry. The caller must name each
callee output explicitly with repeatable `--callee-output <dir>`. Each directory
must pass the existing full `proof-forge.output.v1` inspector: manifest/evidence,
artifact content, exact disk closure, regular-file/no-symlink/path safety, output
set recomputation, target=`evm`, and deployable=true. Missing, duplicate, unused,
or mismatched authorities fail closed before emit.

EVM `CALL` to an account with **no code** returns success and empty returndata.
Therefore the two product modes are:

| Surface | No bindings | Verified EVM bindings |
|---|---|---|
| void `call` | `extcodesize==0` reverts | `extcodesize` + runtime `extcodehash` exact guard |
| result-bearing `call` | short returndata reverts | runtime `extcodehash` exact guard + returndata checks |
| `schedule` | success is discarded, including empty-code success | runtime `extcodehash` exact guard before CALL |

The bound gate proves only that the code present at call time equals the runtime
artifact whose local output identity was verified. It does not prove who placed
that code, why the table address is correct, or that constructor/deployment state
matches the callee source. Reference still consumes an environment response;
Yul does not.

## 3. What a real binding would have to decide

ADR-0053 chose a compile-time table rather than the older ADR-0029
NetworkProfile direction for this product slice. It still does not move address
or deployment semantics into the portable call surface. Closing the remaining
gap is a **product decision** (`B-CALL-SEM`), not a silent emitter tweak:

1. **Who mints the 20 bytes** — **current answer: explicit compile-time table**.
   A future receipt/registry flow must be separately versioned; hashed stub is
   not an implicit fallback when a binding exists.
2. **Which EVM address it is** — CREATE, CREATE2 (initcode+salt), or a
   pre-placed Anvil/`cast` address. Those three are not interchangeable.
3. **Identity join** — **local artifact/runtime portion done**: callee
   `sourceHash` / `semanticHash` / runtime artifact SHA-256 join the inspected
   output, and CALL-time `EXTCODEHASH` joins the decoded runtime bytes. Receipt,
   constructor state, and address provenance remain open.
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
3. **B-CALL-SEM binding** — **partial**: versioned address table plus explicit
   local output/runtime identity join is implemented. Deployment receipt,
   address provenance, CREATE/CREATE2, constructor state, and other target
   families remain separate decisions.
4. Sparse Solana 55-step certificates for initialize / increment / overflow
   stay later and are not this EVM leaf.

## Non-claims

Not `B-CALL-SEM` closed. Not CREATE/CREATE2. Not deployment receipt or Anvil
callee placement. Not constructor-state identity. Not a second call semantics.
Not formal D4 / C-3. Not accepted-PRD expansion.
