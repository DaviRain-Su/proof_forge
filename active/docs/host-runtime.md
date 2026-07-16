# Host runtime abstraction (Layer A)

Status: **Active (2026-07-09)**  
Audience: compiler + multi-chain product  
Related: [protocols-layer](protocols-layer.md), [capability-registry](capability-registry.md),
`ProofForge.Target.HostRuntime`, `ProofForge.Target.HostBridge`,
`ProofForge.Backend.Solana.Syscalls`.

## 0. Host-native packing layers (siblings)

| Host | Pack / encode layer | Role |
|------|---------------------|------|
| NEAR / Wasm | `WasmHost.JsonEncode` | promise / event JSON objects |
| EVM | `Evm.AbiEncode` | calldata layouts (Call[], bytes, …) |
| Solana | CPI `dataLayout` (`Extension.Cpi`) | instruction data words |

Authors and Protocols build **schemas**; backends lower once. Do not hand-roll
putc / mstore / ix bytes at call sites.

## 1. Question

> Solana has syscalls, EVM has opcodes/precompiles, NEAR has host imports —
> did we abstract those so the framework can support any chain?

**Short answer:** yes at the **intent / capability** layer; **partially** at the
**native symbol inventory** layer — now formalized as `HostRuntime`.

Authors never write `sol_log_64_` or `SLOAD`. They write portable IR. Targets
materialize. What was missing was one table that says, for each portable
effect, which **native** symbol each chain uses.

## 2. Three sub-layers of “host”

```text
  Author / IR
       │  emit, storage read, remoteCall, caller, …
       ▼
  Capability          (gate: does target claim support?)
       │
       ▼
  HostEffect          (HostRuntime catalog — portable effect id)
       │
       ▼
  NativeBinding       (opcode | syscall | host_import + symbol)
       │
       ▼
  Backend lowerer     (Yul / sBPF / EmitWat actually emits it)
```

| Piece | Role | Location |
|-------|------|----------|
| Portable IR effects | What the contract *means* | `IR`, Surface |
| `Capability` | Support matrix / reject | `Target/Capability.lean` |
| `HostEffect` + `NativeBinding` | **Syscall/opcode inventory** | `Target/HostRuntime.lean` |
| `HostBridge` | Wasm import/export metadata | `Target/HostBridge.lean` |
| Solana `Syscalls` | sBPF symbol constants | `Backend/Solana/Syscalls.lean` |
| Backend lowerers | Real codegen | Evm / Solana / WasmHost |

## 3. Primary triad map (summary)

| HostEffect | EVM | Solana | NEAR |
|------------|-----|--------|------|
| storage read/write | `sload`/`sstore` | account data | `env.storage_*` |
| log | `log0..4` | `sol_log_64_` | `env.log_utf8` |
| caller | `caller` | signer account | `env.signer_account_id` |
| value | `callvalue` | lamports field | `env.attached_deposit` |
| block env | `number`/`timestamp` | `sol_get_clock_sysvar` | `env.block_timestamp` |
| keccak / sha256 | opcode / precompile | `sol_keccak256` / `sol_sha256` | host crypto |
| remote | `call` | `sol_invoke_signed_c` | `env.promise_create` |
| return data | `return` / returndatacopy | `sol_set/get_return_data` | `value_return` / `promise_result` |
| PDA | CREATE2 (weak) | `sol_create_program_address` | n/a |

Full machine-readable table: `ProofForge.Target.HostRuntime.HostEffect.bindings`.

## 4. What “support any chain” means here

1. **Add a target profile** (`Registry`) with capabilities.  
2. **Fill `HostEffect.bindings`** for that `targetId` (or document `n/a`).  
3. **Implement backend lower** for each used effect.  
4. **Optional:** extend `HostBridge` if Wasm-shaped.

New chains do **not** require authors to learn new syscall names. They require
a materializer that honors the same `HostEffect` / Capability surface.

## 5. Honesty

- Inventory ≠ full lowering coverage. Some bindings are notes (“via account
  pointers”) until every path is a single symbol.
- Family-only ops (EVM `CREATE2`, Solana PDA) stay capability-gated.
- **Capability vs n/a gate (shipped):** `requireHostRuntimeHonesty` rejects when a
  plan requests a capability whose linked `HostEffect` has symbol `n/a` on the
  target (e.g. `storage.pda` on `wasm-near`). Wired into
  `requireCapabilityPlan` / `resolveSpec` so diagnostics name `HostRuntime`.
- Layer **B** (Protocols) is *programs/interfaces*, not host syscalls.
- Layer **C** (Stdlib) is *your* contract body.

## 6. Wasm adapters (Soroban · CosmWasm)

Rows live in `HostEffect.adapterBindings` for targets
`wasm-stellar-soroban` and `wasm-cosmwasm`. Real symbols where the host bridge
already lowers them (`env._get`/`_put`, `invoke_contract`, `execute_msg`,
`db_read`/`db_write`); explicit `n/a` elsewhere (PDA, compute, …).

## 7. Lowerer catalog reference

Solana sBPF event lowering emits a comment from `catalogRefComment .logEmit`:

```text
; HostRuntime host.log.emit → syscall:sol_log_64_
```

Smokes assert this string appears in real `SbpfAsm.renderModule` output.

## 8. HostEnv — de-EVM environment vocabulary (gap-analysis step 1)

Authors and IR should not treat `gasprice` / `coinbase` / `prevrandao` as the
portable surface. **`HostEnv`** is the chain-agnostic vocabulary; backends
**materialize or honest-reject** via `materializeEnv targetId env`.

| Bucket | Rule | Terms |
|--------|------|--------|
| **general** | Portable *intent* (not “already lowered everywhere”) | `blockTime`, `blockHeight`, `chainId`, `caller`, `selfAddress`, `attachedValue` |
| **approximate** | Similar meaning, different name/units; notes on materialization | `epoch`, `gasOrComputeBudgetLeft`, `blockHash`, `randomness` (**untrusted**) |
| **chainOnly** | Opt-in / reject off home host | EVM: `gasPrice`, `baseFee`, `txOrigin`, `coinbase`; Solana: `solanaRent`; NEAR: `nearPredecessor` |

**Honesty rule for `materializeEnv`:** return `.ok` only when the target already
has a real lower / host path for that term. Never invent syscalls and never
alias another field (e.g. NEAR `chainId` must **not** map to `block_index`).
General-bucket coverage grows as lowers land; until then, reject.

Triad snapshot (context / `nativeValue` paths):

| HostEnv | EVM | Solana | NEAR |
|---------|-----|--------|------|
| `blockTime` | ok | ok (`Clock.unix_timestamp`) | ok |
| `blockHeight` | ok | ok (`Clock.slot`) | ok |
| `chainId` | ok | reject | reject |
| `caller` / `attachedValue` | ok | ok | ok |
| `selfAddress` | ok | ok (`program_id` sha256 limb0) | ok |
| `epoch` | reject | reject | ok |
| `gasOrComputeBudgetLeft` | ok | ok (`sol_remaining_compute_units`) | reject |
| `blockHash` | ok | reject | reject |
| `randomness` | ok | reject | ok |

### Permanent / deferred HostEnv policy (U1.3–U1.5)

| Term | Policy | Rationale |
|------|--------|-----------|
| Solana `randomness` | **Permanent reject** (until SlotHashes HostEnv lower) | No portable VRF; SlotHashes not wired as context path |
| Solana `epoch` | **Permanent reject** (until Clock.epoch context lower) | Clock has epoch field; not product-blocking; keep honest reject |
| EVM `epoch` | Permanent reject | No EVM epoch-height opcode |
| NEAR / Solana `chainId` | Permanent reject | No EIP-155 chain id; must not alias block height |
| NEAR `gasOrComputeBudgetLeft` | **Permanent reject** as HostEnv | `prepaid_gas` not a portable context lower |
| Solana `gasOrComputeBudgetLeft` | **Wired** (U1.4) | `contextRead.gasLeft` → `sol_remaining_compute_units` (CU, not EVM gas) |
| NEAR `blockHash` | Permanent reject | Use `randomness` / `random_seed` when needed |
| Solana `blockTime` / `selfAddress` | **Wired** (U1.1–U1.2) | Clock.unix_timestamp; program_id sha256 limb0 |

Product Shared path (`Examples/Product`) should only use triad-safe env
(`caller`, `timestamp`, `checkpointId`, `contractId`, `nativeValue` / attached
value). See `Examples/Product/HostEnvProbe.lean` (U1.6).

API (in `ProofForge.Target.HostRuntime`):

- `HostEnv` / `HostEnvBucket` / `allHostEnvs`
- `HostEnv.bucket`
- `materializeEnv` / `requireHostEnv` / `supportsHostEnv` → `Except String HostEnvMaterialization`
- Reject strings always name `HostEnv`, the target id, and `env.*` term id

IR bridge: `ContextField.toHostEnv` maps legacy IR field names onto HostEnv
(`timestamp` → `blockTime`, `userId` → `caller`, `gasLeft` → `gasOrComputeBudgetLeft`,
`origin` → `txOrigin`, `prevRandao`/`randomSeed` → `randomness`, …).
`ContextField.isPortableEnv` remains the **coarse** family-shared gate used by
portability checks; fine-grained honesty is `materializeEnv`.

Cross-ref: [chain-agnostic gap analysis (zh)](zh/chain-agnostic-gap-analysis.md) §(B)
and suggested route step 1 (HostEnv before Address / sync-crosscall / Token).

## 9. Route steps 2–7 (chain-agnostic epics)

| Step | Module | Honesty surface |
|------|--------|-----------------|
| 2 Identity | `Target/Identity.lean` | `materializeIdentity` (EVM-20 / Sol-32 / NEAR-name) |
| 3 Sync crosscall | `CrosscallMaterialize` sync-subset | `requireSyncSubset` + `inferSolanaAccounts` + `materializeSyncRemote` |
| 4 Token auth + FP | `Contract/TokenAuth.lean`, `FixedPoint.lean` | `materializeAuth` / `validateDecimals` |
| 5 Upgrade | `UpgradePolicy/Lower.materializeUpgrade` | proxy / upgrade-authority / redeploy+migrate |
| 6–7 Mechanics | `Target/PortableMechanics.lean` | crypto / error / serde materialize-or-reject |

**Pipeline (not catalog-only):** `Target/PortableHonesty.lean` is invoked from
`Adapter.defaultResolve` / `resolveSpec` on the primary triad so HostEnv,
Identity, sync-crosscall, **PortableMechanics**, and upgrade materialize fail
closed before codegen. Solana portable remotes: empty peer rejects;
`inferSolanaAccounts` merges into `Manifest.ensurePortableCrosscallAccounts`
(AccountEntry schema used by CPI packing), not note-only.

Smoke: `Tests/ChainAgnosticRoute.lean` (resolveSpec / planForTarget /
ensurePortableCrosscallAccounts) + `Tests/HostRuntime.lean`.

## 10. Tests

`Tests/HostRuntime.lean` — catalog shape, primary + adapter targets, support counts,
`requireHostRuntimeHonesty` + `resolveSpec` PDA-on-NEAR reject, catalog-ref on
EventProbe, **HostEnv bucket + materialize-or-reject triad** (general / approximate
/ chainOnly) + `ContextField.toHostEnv` wiring.

`Tests/ChainAgnosticRoute.lean` — Identity, sync-subset crosscall, TokenAuth +
FixedPoint, upgrade lifecycle, PortableMechanics.
-/
