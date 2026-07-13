# NEP-141 / NEP-145 Interop — Unified Execution Plan

Status: active (2026-07-13; Phases 0-3 and Phase 4 Landing 4a complete,
Landing 4b next). Scope: make the ProofForge `wasm-near` NEP-141
FungibleToken and NEP-145 storage management interoperate with real NEAR
contracts, proven by the compare harness at semantic equivalence and by real-VM
conformance.

This plan operationalizes the `pending` Wave-N tasks (`N-01`→`N-04`) from
`docs/superpowers/plans/2026-07-11-primary-triad-multichain-runtime.md`. It is
informed by the 2026-07-13 investigation + three landed increments
(`f53a2610`, `ef217440`, `fc50683b`).

## End state (definition of "done")

1. A ProofForge-compiled NEP-141 FT that speaks the canonical NEAR wire format:
   JSON `AccountId` / `U128`-as-decimal-string for view methods, and JSON (or
   Borsh) for call methods — interoperable with a real `near-sdk-rs` FT.
2. Full NEP-145: `storage_deposit` / `storage_withdraw` / `storage_unregister`
   / `storage_balance_of` / `storage_balance_bounds`, with `StorageBalance`
   JSON objects, predecessor refund, exact one-yocto, byte accounting.
3. NEP-148 metadata object and NEP-297 `EVENT_JSON` envelopes.
4. Evidence: `testkit/compare` flips `fungible-token` and `storage-deposit` to
   `verified: yes` (real cross-side differential), plus `near-vm-runner` gates
   for each new capability.

## Architectural stance (decided)

- u128 two-word encoding, AccountId string keys, and JSON codecs are **NEAR
  backend (EmitWat) materialization details** — inherently target-specific
  (EVM is u256, Solana is u64). They are correctly placed in the backend and
  do **not** require the portable `F-01`/`F-02` foundations as a prerequisite.
- `F-01` (portable `NumericDomain`/`AmountPolicy`, IR-level range validation)
  and `F-02` (opaque `Principal`/`IdentityCodec`, IR-level identity
  abstraction) are a **later refactor** (Phase 9, optional for interop) that
  lifts these patterns onto portable types for cross-target reuse. They are
  deferred to keep the critical path on shipping interop.

## Critical-path insight (from 2026-07-13)

U128 currently has **three inconsistent representations** in EmitWat:
- input params: an i32 **pointer** to a 16-byte buffer (`Params.lean:78-83`);
- literals / arithmetic / scalar storage read-write / return: **two stack
  words** (lo, hi) — standardized by `ef217440` / `fc50683b`;
- `let`-bound locals: a **single i64** (`wasmTypeOf .u128 = i64`,
  `EmitWat.lean:1258`).

Any u128 value that crosses these boundaries (e.g. an `amount` input param
compared to a `balance` read) is incoherent today. **Phase 1 unifies the u128
representation end-to-end** — this is the linchpin that unblocks the FT.

---

## Phase 0 — DONE (landed 2026-07-13)

- `f53a2610` Real-VM FT conformance gate (storage_remove + full promise ABI
  link/execute + `ft_transfer_call`/`ft_resolve_transfer` callback).
- `ef217440` U128 scalar storage round-trip (read/write/return, two-word).
- `fc50683b` U128 scalar `assignOp` (add/sub) + unsigned comparison (lt/le/gt/ge).

---

## Phase 1 — U128 value model completion  (CRITICAL PATH; effort L)

Unify u128 as **two stack words (lo, hi) everywhere**, including locals, maps,
and inputs. (Alternative: pointer-everywhere. Decision deferred to 1.1 design,
but two-words is the established convention.)

- **1.1 Two-word u128 locals** [LINCHPIN]. Local allocation gives a u128 value
  two i64 slots; `localGet`/`localSet` move both; the local-type env records
  `.u128`; `assertEq`/`assert`/comparisons on a let-bound u128 use the u128
  helpers, not single-word `i64.eq`. Touches `EmitWat.lean` (letBind lowering
  ~1161, locals decl ~1258, localGet ~682) and the local-type env.
- **1.2 U128 map values.** Two-word read/write for hash-keyed and u64-indexed
  maps (`__pf_map_read_hash_u128` void → buffer + caller reload; write takes
  lo/hi); special-case the map read/write lowering; exclude u128 from the
  single-word map func emission, emit the u128 variants instead. Survey must
  record u128 map value types.
- **1.3 U128 input/param representation aligned.** Today params decode to a
  pointer (`Params.lean:78-83`). Either keep pointer and add explicit
  pointer→(lo,hi) load at use sites, or decode directly to two words. Make the
  param local and the rest of the lowering agree.
- **1.4 U128 in events + casts.** Verify event field encoding for u128 and the
  u128↔u64/u32/bool cast matrix.

**Gate:** extend `just near-vm-u128-scalar` with: a let-bound u128 that is
asserted then returned; a hash-keyed map<u128> write/read round-trip; a u128
input param echoed back — all on the real VM.
**Acceptance:** a u128 value can be let-bound, asserted, stored in a map, read
from a call argument, and returned — coherently — on the unmodified NEAR VM.

## Phase 2 — NearFungibleToken U128 conversion  (DONE 2026-07-13)

**2026-07-13 critical discovery:** `contract_source` (Surface v2 — the FT's
authoring surface) lowers via the **canonical `NearModulePlan` path**, NOT the
legacy `EmitWat`/`renderModule` path. Phase 1's u128 model lives entirely in
the legacy path; the canonical path has **no u128 support** (u128 returns fall
through to `__pf_return_u64`, truncating; no `__pf_read/write_u128`,
`__pf_u128_add`, `__pf_map_read_hash_u128`). The `near-vm-u128-*` gates all use
`renderModule` (legacy), so they verify the legacy path only — they do NOT
cover the FT.

So Phase 2 is **blocked on Phase 1C**: porting the u128 model to the canonical
`NearModulePlan` path. Phase 1 (legacy) is not wasted (legacy is used by
IR-fixture probes and some tests) but the FT specifically needs canonical.

### Phase 1C — u128 in the canonical NearModulePlan path  (effort L; BLOCKER)

Port the two-word u128 model to the canonical lowering (`NearModulePlan/Core.lean`
+ `NearModulePlan.lean`): u128 return (16-byte LE), u128 scalar + map storage
read/write, u128 arithmetic / comparison / locals / decimal formatter. Mirrors
Phase 1.1–1.4 but for the canonical path. **Gate:** a canonical-path u128 probe
on the real VM (e.g. a `proof-forge build`-emitted module asserting u128
returns), or extend `near-vm-u128-*` to exercise the canonical lowering.

DONE 2026-07-13: the FT stdlib is converted to U128 (totalSupply, balances,
allowances, pendingAmounts, all amount params/locals/returns, the refund
helpers via `nearPromiseResultU128`); the canonical `NearModulePlan` lowering
gained the two remaining U128 surfaces (promiseResultU128 op + u128 crosscall
args + u128 event fields + void u128 map write); and the Borsh-input/return
cascade landed in `WasmNearFtTransferCall`, `near-ft-security`, the two offline
smoke scripts, and `near-vm-conformance-ft` (verified on the real NEAR VM).
The `Event.lean` helper set is now self-contained for u128 (`__pf_fmt_u128`/
`__pf_u128_divmod10` emitted with `__pf_evt_putu128`). The compare-harness
reference crate (U64 + sandbox-gated) is deferred to Phase 8.

## Phase 3 — AccountId string keys  (effort M; depends 1)

String-keyed map storage so balances are keyed by `AccountId` string, not
sha256 hash (removes the collision boundary). Add `predecessor_account_id` /
`current_account_id` / `signer_account_id` as full string values (already
imported) and a `callerAccountId` surface construct.
**Gate:** real-VM proof that a string-keyed balance round-trips.
**Acceptance:** FT balances keyed by AccountId string; identity no longer
hash-truncated.

### Landing 1 — string-keyed map mechanism + real-VM gate  (DONE 2026-07-13)

De-risked the riskiest mechanism (variable-length string-keyed storage with a
**runtime** key length `pl + kl`, unlike the fixed-32-byte hash path) before
touching the FT or the cross-backend `ContextField` sweep.

- `Map.lean`: `__pf_map_buildkey_string` / `__pf_map_read_string_<vt>` /
  `__pf_map_write_string_<vt>` / `__pf_map_delete_string_<vt>` /
  `__pf_map_contains_string` helpers (NEAR bridge; scalar + U128 values), with
  inline runtime key length (`mapStringKeyLenInsns`) instead of the
  compile-time `mapStorage*HostInsns`. `.string` dispatch arms in
  `mapReadCall` / `mapWriteCall` / `mapDeleteCall` / `mapContainsCall`.
- `Plan/Surface.lean` + `Plan.lean`: `IndexedStorageHelperKeyKind.string`,
  `ModuleSurface`/`ModulePlan` string-indexed fields + merge +
  `withStringIndexed*` + `.string` arms in the indexed-storage surface
  summaries; `mapStringHelperFuncsForModulePlan` emitted in
  `ModuleAssembly.helperFuncsForModulePlan`.
- `EmitWat.lean`: `lowerExpr (.local)` for `.string`/`.bytes` emits
  `(localGet name, localGet (name ++ "_len"))` (the param `_len` local exists
  from `Params.loadParams`); `lowerMapKeyFor` dispatches `.string` to a
  `(ptr, len)` key.
- `Capabilities.lean` / `NearAbiPlan.lean` / `Plan/Surface.lean`:
  `emitWatCapabilities` admits `.dataDynamicBytes`; `borshByteWidth` returns
  the flat 260-byte slot for `.string`/`.bytes` (matching `Params.loadParams`);
  `surfaceFromValueType` sets `withArrAlloc` for `.string`/`.bytes` (Borsh
  param decode allocs a payload buffer via `__pf_arr_alloc`).
- The frozen Rust sourcegen keeps its narrower map boundary
  (`Map<U64|Hash, U32|U64|Bool|Hash>`). String-keyed/U128-valued map support is
  owned by canonical EmitWat planning/lowering, not by the sourcegen validator.
- Gate: `just near-vm-string-key-map` — `StringKeyMapProbe`
  (`Map<string, u128>`; `map_roundtrip(key : String) -> U128`: write u128(100)
  at the key, read back) rendered via `EmitWat`, executed on the unmodified
  upstream NEAR VM (`near-vm-runner 0.37` / Wasmtime) with a Borsh string key
  (padded to the 260-byte flat slot). Returns
  `64000000000000000000000000000000` (u128 100).

**Deferred to Landing 2:** `callerAccountId` surface construct + the
`ContextField.accountId` exhaustiveness sweep (`__pf_ctx_account_id` returning
the raw `predecessor_account_id` as a `(ptr, len)` string, no sha256); two-slot
string locals (`let sender : .string := callerAccountId`); string equality;
FT conversion (`balances`/`storageDeposits` → `.string` keys and
`account_id` params → `.string`; `mintAuthority` remains a full SHA-256 hash
because raw string scalar storage is outside this landing); variable-length
string INPUT (the current flat-260 prologue assert is a ProofForge convention;
real variable-length Borsh string input is Phase 4 JSON/Borsh codec).

### Landing 2a — callerAccountId + ContextField.accountId sweep  (DONE 2026-07-13)

Added `ContextField.accountId` to Core `Type.lean` plus the `__pf_ctx_account_id`
VOID host helper (stages the raw `predecessor_account_id` bytes at `ACCT_ID_BUF`
with a 4-byte LE length at `ACCT_ID_LEN`, no sha256) and the `lowerContextExprPlan
.accountId` materializer (`(ptr, len)` of type `.string`). Swept every non-NEAR
backend (EVM ToYul/Effect/Lower/Plan, Legacy classification, IR Semantics +
SemanticsFuel, Solana/Psy/Aleo/Stylus/PortableHonesty/Adapter/Elaborate) to reject
`.accountId` so the triad stays portable.
- Gate: `just near-vm-caller-account-id-map` — `CallerAccountIdMapProbe`
  (`Map<string, u128>` round-trip keyed by `callerAccountId`) returns `u128 100`
  (`64000000000000000000000000000000`) on the upstream NEAR VM. Direct account
  map keys no longer require a hashed identity projection.
- No regressions across the NEAR/EVM/portable gate set; `lake build` (792 jobs).

### Landing 2b — NearFungibleToken AccountId string keys + full transfer_call  (DONE 2026-07-13)

Converted the NEP-141 FT to raw AccountId string keys end-to-end through the
canonical `NearModulePlan` lowering path.
- **FT source:** `balances` / `storageDeposits` → `.string` keys;
  `account_id` / `receiver_id` params → `.string`; `callerHash` →
  `callerAccountId` for balances and transfer ownership; string equality via
  `__pf_str_eq`. **Allowances and `mintAuthority` remain `.hash`**: allowance
  keys are derived composites, while raw string scalar storage is outside this
  landing. The hash is the full 256-bit SHA-256 value, not a truncated limb.
- **Two-slot string locals:** legacy `EmitWat.lean` + `Locals.lean` +
  `Statement.lean` and canonical `NearModulePlan.lean` lower `let sender :
  .string := callerAccountId` to a `(name i32, name_len i32)` local pair.
- **String event field values:** `__pf_evt_putstr_value` emits dynamic `(ptr, len)`
  strings as JSON-quoted UTF-8 (FTransfer now logs `"from":"alice.testnet"`).
- **Params payload copy fix:** `Params.loadParams` for `.string` now
  copies the full `len + 4` bytes (length prefix + payload) from `INPUT_BUF`, not
  just the 4-byte length prefix — the param string pointer previously pointed at
  uninitialized memory, so param-keyed writes and `callerAccountId`-keyed reads
  mismatched and `ft_transfer` trapped on `requireGe`. Dynamic `.bytes` ABI
  parameters remain explicitly unsupported in canonical EmitWat (the frozen
  Rust sourcegen has its own `Vec<u8>` ABI surface).
- **u128 helper dedup:** `__pf_u128_divmod10` / `__pf_fmt_u128` are event-format
  helpers, not u128 arithmetic; removed from `u128ArithFuncs` (kept in the event
  helper set) and added name-based dedup to the legacy `helperFuncsForModulePlan`
  (the canonical path already deduped via `foldl`). Fixes a redefinition that
  broke `near-u128-fmt-smoke` and would have broken any legacy render with both
  crosscall and event u128.
- **Canonical context path:** `Core.ContextField.accountId` + adapter +
  `NearModulePlan` lowering + Core surface + `LegacyParity.lean` handleContext.
- **Local real-VM contexts:** `near-vm-runner` accepts per-call predecessor and
  attached-deposit sequences. The FT gate proves deposit `7`, authorized
  withdrawal `3` (balance `4`), and an attacker predecessor abort on the
  unmodified upstream VM, covering both outcomes of string equality.
- **Backend-boundary repair:** the frozen Rust sourcegen now rejects
  String-keyed/U128-valued maps during validation with a canonical-EmitWat
  routing diagnostic, instead of accepting shapes for which it has no map
  helpers. Its existing U128/String/Bytes parameter and return surface remains
  covered by positive sourcegen diagnostics.
- Gates (all on the unmodified upstream NEAR VM / offline host):
  `just near-vm-conformance-ft` — full NEP-141 `ft_transfer_call` +
  `ft_resolve_transfer` callback (sender 100→30→55, receiver 0→70→45, refund 45);
  `just wasm-near-ft-transfer-call`, `just wasm-near-ft-transfer-call-e2e`
  (happy path, repeat-init, private callback, bounded refund, concurrent
  contexts), `just near-ft-security`, `just product-token-near`,
  `just near-vm-caller-account-id-map`, `just near-vm-string-key-map`,
  `just near-u128-fmt-smoke`, `just portable-nft-multi-target`, `just nft-intent`,
  `just evm-plan`, `just evm-abi-schema`, `just strict-intent-materialization`.
  `lake build` (794 jobs). Both Wasm coverage manifests contain all 149 IR
  constructors; Rust sourcegen diagnostics pass 51 cases.
- **Known unrelated baseline drift:** `portable-value-vault` / `solana-light`
  still reference a stale `ValueVault.canonical.golden.wat` predating the Phase
  2 u128 event helpers. The missing canonical refinement constructors were
  repaired here and `just canonical-core` now passes.

## Phase 4 — JSON codecs (N-01)  (effort XL; biggest risk; depends 2,3)

Wallet-facing interop. JSON decode of entrypoint args (`ft_transfer
{receiver_id, amount}`); JSON encode of returns (U128 decimal string,
`StorageBalance`/metadata objects). Per-entrypoint codec plan shared by
contract and the generated client. JSON parsing/serializing in a hand-rolled
Wasm backend is the dominant risk — evaluate host-assisted decode vs in-Wasm
parser early in the phase.
**Gate:** a real JSON `ft_balance_of` call returns a decimal-string U128 on the
real VM (or compare harness).
**Acceptance:** wallet-compatible JSON views.

### Landing 4a — canonical `ft_balance_of` JSON boundary (DONE 2026-07-13)

- `NearAbiPlan.buildSignaturePlan` is the single per-entrypoint codec decision
  consumed by both legacy and canonical Core builders. The standard signature
  `ft_balance_of(account_id : String) -> U128` selects JSON input/output;
  existing non-standard entrypoints remain Borsh.
- The Wasm decoder accepts the canonical one-field object
  `{"account_id":"<AccountId>"}`, validates its exact frame and the NEAR
  AccountId 2-64-byte bound, and binds a zero-copy `(ptr,len)` string view.
  The return helper emits the NEAR JSON U128 decimal-string form (`"100"`).
- Both legacy EmitWat and canonical `NearModulePlan` route through the same
  codec plan and emit helpers on demand. The generated TypeScript client sends
  UTF-8 JSON through raw RPC and converts the returned decimal string to
  `bigint`.
- `just near-vm-json-balance` compiles the public FT source and proves
  `init -> ft_mint(100) -> ft_balance_of(JSON) == "100"` on the unmodified
  upstream NEAR VM; malformed JSON aborts. Existing transfer/callback and
  product-token gates now query balances through JSON and continue to pass.

Landing 4a meets the first view-method gate, not the whole phase. Landing 4b
adds reusable multi-field JSON decoding and JSON call transport for
`ft_transfer`; later slices add optional/memo/msg fields and structured
NEP-145/148 return objects. Borsh mutation entrypoints remain intentional
compatibility behavior until their individual JSON decoders and real-VM gates
land.

## Phase 5 — NEP-141 core interop (N-03)  (effort L; depends 4)

`memo`/`msg` params; local `ft_on_transfer` receiver hook; full
`ft_transfer_call(receiver_id, amount, memo, msg)`; registration
(storage_deposit before transfer); exact one-yocto guard.
**Gate:** compare harness differential on transfer / transfer_call.

## Phase 6 — NEP-145 / 148 / 297 closure (N-04)  (effort L; depends 3,4)

`storage_unregister` (force one-yocto); predecessor refund via
`promise_transfer`; `StorageBalance` / `StorageBalanceBounds` JSON; storage
byte accounting / cost (`storage_usage` host APIs); attack tests. NEP-148
metadata object `{spec, name, symbol, decimals, …}`. NEP-297 `EVENT_JSON`
envelopes. Lift the route-test ban on advertising `storage_unregister`.
**Gate:** compare harness `storage-deposit` → `verified: yes`.

## Phase 7 — TokenSpec parameterized runtime (N-02)  (effort M; depends 2)

`name`/`symbol`/`decimals`/`initialSupply`/`features` affect the emitted Wasm
(not just the plan JSON); unsupported features reject.

## Phase 8 — Compare harness → semantic equivalence  (effort M; depends 5,6)

Upgrade the reference `testkit/compare/near/fungible-token` crate to a real
NEP-141 (JSON/U128/AccountId); make the harness run a real cross-ABI
differential (PF answers standard calls); flip `MATRIX.md` `verified: yes`.

## Phase 9 — (optional, later) Portable abstraction (F-01/F-02)

Lift the u128 amount and AccountId patterns onto portable `NumericDomain` /
`AmountPolicy` and `Principal` / `IdentityCodec` for cross-target reuse. Not
required for NEP-141/145 interop; defers cleanly.

---

## Dependency graph

```
Phase 1 (u128 value model) ──┬─► Phase 2 (FT u128) ──┬─► Phase 4 (JSON) ──► Phase 5 (NEP-141 core) ──┐
                             │                        │                                       ├─► Phase 8 (compare verified)
                             └─► Phase 3 (AccountId) ─┴─► Phase 4 ──► Phase 6 (NEP-145/148/297) ─────┘
                                      Phase 7 (TokenSpec runtime) ◄── Phase 2
                                      Phase 9 (portable F-01/F-02) — independent, later
```

Phase 1 is the single critical-path prerequisite for everything u128. Phase 4
(JSON) is the long pole and highest risk.

## Per-phase deliverable shape (uniform)

Each phase lands: (a) the EmitWat/stdlib change, (b) an `U128…`/focused IR
probe where useful, (c) a `near-vm-*` real-VM gate or compare-harness update,
(d) `docs/validation-gates.md` (en+zh) row + `implementation-log.md` entry +
i18n manifest sha, (e) regression run (`wasm-near-scalar-safety`,
`wasm-near-plan`, `near-vm-conformance`, `near-vm-conformance-ft`,
`manifest`/`equivalence`, `docs-check`, `git diff --check`).

## Honest notes

- `just product` has a pre-existing failure (`OwnableHash Soroban ... _get
  ABI`, unrelated, recorded 2026-07-12); it is not a gate for this work.
- u128 `mul` helper is simplified (lo×lo only, `Scalar.lean`); adequate for
  transfer/approve arithmetic, not for interest-bearing math.
- This is orthogonal to the active D-052 program (next task C1). It advances
  the separate Wave-N track.
