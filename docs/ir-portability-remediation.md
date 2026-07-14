# IR Portability Remediation

Status: **In progress (D-050 corrected 2026-07-09 — target-resolved binding)**

Addresses the review finding that the portable IR evolved under EVM pressure.
The authoring surface and IR stay **chain-neutral**; chain-native materialization
is chosen only by `--target`.

Related: [portable-ir.md](portable-ir.md), [D-027](decisions.md),
[D-028](decisions.md), [D-050](decisions.md),
`ProofForge/IR/Portability.lean`, `ProofForge/Target/StorageBinding.lean`.

## Principle (non-negotiable)

```text
Author / portable IR          Target adapter (--target)
─────────────────────         ─────────────────────────
state count: scalar U64  →    evm        → contract storage slot
                         →    solana     → account data field
                         →    wasm-near  → host KV key
                         →    move-aptos → has-key resource
                         →    move-sui   → object with UID
```

Authors **never** write `objectState` / `resourceState` / EVM slot annotations
in the portable path. Those are lowering *outputs*, not IR *inputs*.

## Wrong direction (reverted)

An early D-050 draft put `StorageOwner.resource` / `.object` on `StateDecl`
and exposed `objectState` / `resourceState` builders. That forced authors to
pick a chain at write time and violated D-028. **Removed.**

## Correct layering

| Layer | Owns | Does not own |
|---|---|---|
| Contract Intent / `contract_source` | Portable state, entrypoints, arithmetic, events | Object vs resource vs slot |
| Portable IR (`StateDecl`) | Shape: `scalar` / `map` / `array` + `ValueType` | Chain binding model |
| Capability plan | `storage.scalar`, … | How a chain stores it |
| `Target.StorageBinding` | Profile → native binding enum | Author annotations |
| Backend plan / emit | Materialize binding (Yul `sstore`, Move `has key`, …) | Portable business logic |

## Slice 1 (landed, corrected)

- [x] Portable `StateDecl` is shape-only (no owner field)
- [x] `Target.StorageBinding` resolves binding from target id/family
- [x] EVM/Solana/NEAR/Aptos/Sui adapters map the **same** Counter IR
- [x] Neutral renames: `paramAbiWords`, `proxyPattern?` (metadata, not author intent)
- [x] `ProofForge.IR.Portability` flags true family-only *constructors*
      (create2, NEAR Promise ops, fallback/receive) — not storage binding
- [x] `just ir-portability-smoke`

## Slice 2 (mostly landed)

- [x] NEAR Promise product split (D-050 Slice 3 partial): portable path is
      `crosscall.invoke` + `crosscallStrings` → `promise_create`
      (`Backend.WasmHost.PortableCrosscall`, `NearCrosscallProbe.portableModule`,
      `Shared.RemoteCall`, `just portable-remote-call-multi-target`).
      Host-extension vocabulary: `ProofForge.IR.NearHost` + `Source.Near`.
      `crosscallContinue` / result constructors remain on `Expr` for EmitWat
      coverage but are non-portable-core (`targetFamilyOnly .wasmHost`);
      full inductive removal is deferred (every Expr match site).
- [x] Generalize Move entrypoint lowering beyond hardcoded Counter entrypoint
      names — Aptos `renderEntrypoint` now classifies entrypoints by IR body
      shape (`matchInitShape` / `matchIncrementShape` / `matchGetShape`) against
      the scalar state id, so renamed entrypoints (`init`/`bump`/`read`) lower
      correctly and keep their IR names; unsupported body shapes are rejected.
      Witnessed in `Tests/IRPortability.lean` (renamed-entrypoint lowering +
      unsupported-shape rejection).
- [x] Context field split: portable env vs EVM-only (`baseFee`, `prevRandao`, …)
      — `ContextField.isPortableEnv` is the single source of truth for which
      context fields (`timestamp`/`chainId`/`epochHeight`/`checkpointId`/
      `userId`/`userIdHash`/`contractId`) have a native analogue on every
      primary target vs which are EVM-specific
      (`gasPrice`/`gasLeft`/`baseFee`/`prevRandao`/`randomSeed`/`origin`/
      `coinbase`/`blockHash`). The `Portability` classifier consumes it, so
      the split is machine-checked and witnessed in `Tests/IRPortability.lean`
      (portable-env read stays portable-core; EVM-only read violates non-EVM
      families).
- [x] Portable identity type vocabulary — `ValueType.isPortableIdentity`
      documents `.address` as the chain-neutral account/identity handle;
      target adapters rename it to native form (EVM `address`, Solana
      `Pubkey`, NEAR `AccountId`, Move `signer`/`address`) via `paramAbiWords`
      metadata, not in `ValueType` itself. Witnessed in `Tests/IRPortability.lean`.
- [x] Surface `storageBinding` in artifact/deploy JSON for debugging — the
      EVM, Solana, and Wasm-NEAR artifact/deploy manifests and metadata now
      carry a `storageBinding` field (`contract-global` / `account-data` /
      `host-key-value` / `move-resource` / `move-object`) resolved from the
      selected target via `TargetProfile.storageBinding`, so operators can see
      how the portable state was materialized without re-deriving it.

## Author guidance

```lean
-- One source for every target:
scalarState "count" .u64

-- Build:
--   proof-forge build --target evm ...
--   proof-forge build --target move-sui ...
--   proof-forge build --target move-aptos ...
```

Target Extension SDKs (Solana PDA/CPI, …) remain the only place for
*explicit* chain-native authoring — and they still lower through capabilities
and metadata, not portable IR constructors (D-027).

**Product architecture (broader than IR hygiene):** authors write business
logic only; Token features, storage binding, accounts/PDA/CPI, and host
models are all target-materialized. See
[product-authoring-architecture.md](product-authoring-architecture.md).
