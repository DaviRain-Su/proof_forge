---
id: PLAN-NEAR-PARITY
title: NEAR parity roadmap (vs EVM / Solana engineering surface)
status: draft
owner: architecture
updated: 2026-08-12
normative: false
---

# NEAR parity roadmap

Goal: close the **engineering / product** gap between NEAR and the stronger
EVM + Solana paths without claiming formal refinement, testnet/mainnet, or
sync-call semantics NEAR cannot honestly provide.

Honesty baseline (do not rewrite):

- NEAR = `wasm-validated-alpha` + locked `near-sandbox` engineering gates.
- Not Reference↔Wasm formal differential.
- Sync `call` / sync native·token transfer remain **permanent fail-closed**
  (Promise is async).
- Proof-bearing invariant-root erasure (ADR-0042) is NEAR-unique engineering;
  it is **not** formal target refinement.

## Phase map (0–4)

| Phase | Name | Intent | Exit criteria | Status (2026-08-11) |
|------:|------|--------|---------------|---------------------|
| **0** | Inventory | Freeze maturity + gaps vs EVM/Solana | This doc + dossier residual list current | **done** |
| **1** | Low-integration demo | One standalone product Example with sandbox | `PoseTransform` builds + sandbox PASS | **done** (sandbox PASS) |
| **2** | Runtime hole-fill | Close known engineering residuals that EVM already gates | `BlockHeightCheck` sandbox PASS; dossier updated | **done** (sandbox PASS) |
| **3** | Product surface | Install / docs / agent path closer to EVM | Cheatsheet + catalog notes | **done** (lite: cheatsheet + catalog) |
| **4** | Remaining engineering slices | constants + unixTime runtime + network catalog; formal deferred | scalar const + unixTime sandbox + near network ids | **partial** (formal still deferred) |

### Phase 0 — Inventory (done as of this doc)

Already strong on NEAR:

- Semantic → NearPlan → WAT → Wasm (locked `wat2wasm`)
- HostModel pins (arith, aggregates, Option, multiword, …)
- ~10 sandbox suites (StateCell, returns, OptionState, VerifiedVaultPF,
  TipJarAsync, TokenJarAsync, EnvReadJar, CallerCheck)
- `pf.assets` async half-binding + caller + blockHeight Plan/IR
- ADR-0042 proof-bearing vault observation

Gaps vs EVM / Solana (engineering, not formal):

| Gap | EVM/Solana today | NEAR |
|-----|------------------|------|
| Low-integration multi-field demo | many Examples | need Pose-class product Example |
| `context.blockHeight` runtime gate | Anvil companion | Plan/IR only → **Phase 2** |
| Product CLI deploy/network/UI | richer | sandbox scripts only → Phase 3 lite |
| Sync assets | native | permanent FC (honest) |
| Formal lighthouse | EVM-first | out of scope here |

### Phase 1 — Low-integration demo (`PoseTransform`)

- Example: translate / rotate90 / scale on a 2D pose (`Int64` x/y).
- No assets, no Promise, no invariants, no cross-contract.
- Wire into `scripts/near_runtime_test.sh` + `runtime-tests/near/run_tests.py`.
- Claim: engineering sandbox observed only.

### Phase 2 — Runtime hole-fill

1. **blockHeight sandbox** — reuse `Examples/BlockHeightCheck.lean`
   (already multi-target Plan-open); assert `height()` / `stamp()` against
   near-sandbox `status.sync_info.latest_block_height`.
2. Dossier residual line for blockHeight runtime → closed (engineering).
3. StateCell `negative_corpus` suite (unknown method / empty·short·long
   increment args + state-hold + recovery) wired into
   `scripts/near_runtime_test.sh`. Optional later: PoseTransform bad-input
   scale overflow (already folded into Pose suite overflow hold).

Not in Phase 2 formal sense: full hermetic GLIBC digests in toolchains lock
(still open). Engineering GLIBC pack path is landed:
`scripts/near_sandbox_glibc_materialize.sh` + `scripts/lib/near_sandbox_launch.sh`
+ `supply-chain/near-sandbox-glibc-linux-x86_64.v1.json` (auto-discover; not
hermetic pin). Also deferred: view-caller and formal identity. Dense Map
return cap-8 (24×u64 LE `value_return`) landed 2026-08-12; only the >8-leaf
encoding story stays deferred (see Phase 4).

### Phase 3 — Product surface (lite)

- `docs/product/near-agent-cheatsheet.md`: install → build -t near →
  near_runtime_test → honesty boundaries (no lake monorepo as default agent path).
- `docs/product/chain-client-catalog.v1.json` near row: note sandbox suites +
  PoseTransform / BlockHeightCheck.
- Align wording in `docs/product/01-toolchain-install-surface.md` if needed
  (`near` + `--with-runtime` → `near-sandbox`).

Out of Phase 3: public testnet broadcast, full `pf deploy -t near`, dApp UI
scaffold parity with EVM.

### Phase 4 — Remaining slices + explicit non-goals

**Done in this wave (engineering):**

- Scalar `const` / `Op.Constant` on NEAR (UInt/Int/Bool) + `ConstAnswer` sandbox
- `UnixTimeCheck` sandbox for `context.unixTimeSeconds`
- Network catalog: `near.local.sandbox` + `near.testnet` (broadcast refused)
- `Bytes N` (1..8) anonymous return + `BytesRet` sandbox (tight u8 pack)
- `pf deploy -t near` save-only package (`--broadcast` refused)

**Still deferred (do not start without a decision):**

- Reference↔Wasm / sandbox **formal** differential
- Sync call or sync transfer wrappers
- Full NEP-141 ledger / mainnet
- view `context.caller` (host-forbidden; keep FC)
- Map return ABI (dense expand >8 leaves — needs a different encoding story)
- Replacing monorepo contributor path (still valid for compiler dev)

## Suggested execution order

```text
Phase 0 (doc) → Phase 1 (PoseTransform + sandbox)
              → Phase 2 (BlockHeightCheck sandbox)
              → Phase 3 (cheatsheet + catalog)
              → stop; Phase 4 stays deferred
```

## Success metric

A new engineer / agent can:

1. Read this roadmap + near dossier in <15 min.
2. Build `PoseTransform` and `BlockHeightCheck` for `--target near`.
3. Run `scripts/near_runtime_test.sh` and see both new suites PASS
   (when tool-root has `near-sandbox` + `wat2wasm`).
4. Never be told to `lake build` the monorepo as the **product** path.
