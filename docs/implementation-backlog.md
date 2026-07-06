> **Note:** public validation command changes must update
> [validation-gates.md](validation-gates.md) in the same change.

# Implementation Backlog

This backlog turns the multi-chain design into reviewable engineering slices.
It is intentionally scoped to local compiler, artifact, and smoke-test work.
The cloud platform should wait until at least two materially different targets
are working locally.

Related docs:

- [Design decisions](decisions.md)
- [Portable Contract IR](portable-ir.md)
- [Capability registry](capability-registry.md)
- [Shared scenario: Counter](shared-scenario.md)
- [RFC 0002](rfcs/0002-target-implementation-design.md)
- [Target notes](targets/README.md)
- [Validation gates](validation-gates.md)

## Primary-chain completion covenant (D-045)

Before adding implementation scope for more chains, ProofForge must complete
the three priority chains in this order:

1. `solana-sbpf-asm` — Solana direct sBPF assembly backend.
2. `evm` — Ethereum/EVM backend and deployment lane.
3. `wasm-near` — NEAR on the Wasm-family backend.

This is stronger than a research-roadmap preference. It was tracked as Gate P0
in [gate-status.md](gate-status.md), and Gate P0 is now closed. "Complete" means
target-first build/emission, local execution or deployment smoke,
artifact/deploy metadata, capability diagnostics, resource budgets, CI coverage,
and maintained docs for each of the three chains. New-chain implementation work
is no longer blocked by D-045. CLI M3 target-first migration is now landed for
executable callers; Tier-1 M3/M4 advancement still needs explicit scheduling
and should not rely on old research notes as implicit implementation scope.

## Review disposition (2026-07-04)

A July 2026 architecture/product review raised six risks. The current backlog
disposition is:

| Review item | Current disposition | Backlog action |
|---|---|---|
| R1: RFC 0009 and D-039 lagged behind the landed CLI M1 work | Closed on current `main`: RFC 0009 is accepted with M1/M3 landed, and D-039 now ratifies the compatibility-layer implementation instead of claiming a pre-code freeze | Keep RFC 0009 and CLI migration docs synchronized as M4 legacy-alias removal is scheduled |
| R2: too many half-finished workstreams are active | Accepted as a planning risk | Gate P0 is closed and CLI M3 is now guarded by `just cli-target-first`; keep M4 alias removal behind the compatibility window and avoid opening Tier-1 M3/M4 work implicitly |
| R3: no end-to-end proof connects user invariants to generated artifacts | Partially accepted: source-level proofs, FV-2 aggregate/storage/map/control-flow/event-log IR traces, the first FV-8 ValueVault accounting/net-value invariant anchors over IR semantics, NEAR trace obligations plus Counter and ValueVault EmitWat artifact-surface/offline-host execution-surface obligations, the NEAR ValueVault backend-invariant state bridge, NEAR host import-signature, entrypoint input-frame, context-frame, storage-read-key-frame, storage-write-key-value-frame, host-call frame, memory-layout, return-payload-byte, per-step storage-snapshot, storage-byte, and log-payload-byte obligations, and EVM FV-4 executable Yul trace anchors exist, but full IR-to-artifact semantic preservation is not done. The EVM map/storage/aggregate/control-flow/event slices now connect covered FV-2 IR traces to executable Yul obligations. | Extend NEAR FV-4 from the new backend-invariant/import/input-frame/context-frame/storage-read-key-frame/storage-write-key-value-frame/frame/memory-layout/return-payload-byte/storage-byte/log-payload-byte bridge toward a richer Wasm/offline-host semantics boundary, then prove semantic preservation beyond the current state/IO, host-ABI, entrypoint input-frame, context-frame, storage-read-key-frame, storage-write-key-value-frame, host-call-frame, memory-layout, return-payload-byte, storage-snapshot, storage-byte, and log-payload-byte anchors |
| R4: capability granularity is too coarse | Do not churn capability ids in the current phase; storage is already split into scalar/map/array/PDA, and Solana account semantics are modeled separately from storage patterns | Treat cross-target runtime differences as budget/diagnostic obligations: each target must reject unsupported shapes explicitly and pin resource budgets for supported ones |
| R5: docs-first target notes create hidden sunk cost | Closed at the scheduling layer: D-045 and the target roadmap restricted product hardening to `solana-sbpf-asm`, `evm`, and `wasm-near` until Gate P0 closed | Keep research notes as inventory; schedule Tier-1 M3/M4 explicitly rather than letting old research notes create automatic implementation scope |
| R6: Lean/toolchain onboarding friction | Partially closed: `docs/onboarding.md` exists and names the core toolchain and per-target tools, but editor workspace config, templates, and scaffolding remain open DX work | Add VS Code/Cursor workspace recommendations and a minimal project template after the NEAR/Wasm P0-3 closure, unless onboarding friction blocks P0 work earlier |

The immediate engineering order after this review is therefore:

1. ~~Close NEAR/Wasm P0-3 with target-first local execution and deploy metadata
   evidence.~~ ✅ Closed by Gate P0 sign-off.
2. ~~Finish the CLI M3 migration from legacy flags to target-first executable
   invocations.~~ ✅ Landed; `just cli-target-first` scans executable callers
   and runs the target-first mapping regression suite. M4 legacy flag removal
   remains intentionally deferred until the RFC 0009 compatibility window.
3. Continue formal verification work: FV-2 now has aggregate/storage executable
   traces, state-threaded map insert/set lifecycle traces, control-flow traces
   for `ifElse`/`boundedFor`, observable event-log traces, and determinism plus
   bounded-loop measure anchors. The covered EVM
   map/storage/aggregate/control-flow/event obligations compare those IR traces
   against executable emitted Yul. NEAR now has Counter and ValueVault EmitWat
   AST artifact-surface obligations plus offline-host execution-surface
   obligations that pin Borsh input bytes, deterministic host return/log
   observations, storage-key counts, and cumulative log counts. The artifact
   surface now also checks the NEAR host import ABI at the Wasm AST boundary:
   module name plus parameter/result signatures for `input`, `read_register`,
   `storage_read`, `storage_write`, `value_return`, `log_utf8`, and
   `block_index` where used. The NEAR artifact surface also pins host-call
   frames for the `u64` storage read/write helpers, `value_return`, and
   `log_utf8`, including the constants and memory buffers passed to the host.
   The offline-host surface now also records per-step storage snapshots and the
   corresponding little-endian/Borsh storage bytes, so Counter and ValueVault
   must match both semantic storage contents and host storage byte strings
   after each checked entrypoint, not only final storage or key counts. The
   offline-host surface also pins byte-level `value_return` payload hex bytes
   for scalar returns and byte-level `log_utf8` payload hex fragments for
   ValueVault events, separating host payload bytes from human-readable return
   and log line fragments. FV-8 now has a first ValueVault IR invariant anchor for the shared 11-step
   scenario, including return-trace, accounting, final-storage, and net-value
   checks. The latest NEAR FV-4 slices add a decide-checkable
   backend-invariant state/import/input-frame/context-frame/storage-read-key-frame/storage-write-key-value-frame/frame/memory-layout/return-payload-byte/storage-byte/log-payload-byte bridge: the ValueVault
   offline-host input sequence is derived from the FV-8 scenario inputs, return
   fragments are checked against FV-8 expected returns, final offline-host state
   is checked against the FV-8 scenario state and accounting/final-storage
   predicates, scalar `value_return` payload bytes are derived from FV-8
   expected returns, ValueVault event log JSON fragments are derived from the
   invariant final state, each `log_utf8` payload hex fragment is derived from
   the same invariant event stream, each offline-host storage snapshot and
   storage-byte snapshot is pinned, the Wasm memory declaration is pinned, and
   fixed host buffers (`KEY_BUF`, `RET_BUF`, `EVENT_BUF`, `EVT_KEY_PTR`,
   `INPUT_BUF`) are checked to fit within the first page without overlap. Host
   import signatures, entrypoint `input`/`read_register` frames, scalar u64
   parameter loads from `INPUT_BUF`, storage-read key pointer/length frames
   passed into `__pf_read_u64`, storage-write key/value frames passed into
   `__pf_write_u64`, ValueVault `block_index` context reads into `checkpoint`,
   and helper host-call frames are pinned before WAT printing.
   Next extend this bridge from state/IO, host-ABI, host-call-frame,
   entrypoint input-frame, context-frame, storage-read-key-frame,
   storage-write-key-value-frame, memory-layout, return-payload-byte,
   storage-snapshot, storage-byte, and log-payload-byte equality toward a
   richer Wasm memory/host semantics boundary.
4. Address the remaining DX items (`.vscode` recommendations, project template,
   and scaffolding) once they no longer compete with the P0 closure.

## Workstream 1: Target Registry

Goal: make target selection explicit before adding more backends.

Tasks:

- Add target ids: `evm`, `wasm-near`, `wasm-cosmwasm`,
  `solana-sbpf-asm`, `solana-sbpf-linker` (superseded), `solana-zig-fork`,
  `move-sui`, `move-aptos`, `psy-dpn`.
- Define target family, artifact kind, required tools, and capability set
  (see [capability-registry.md](capability-registry.md)).
- Add a target lookup function for CLI and scripts.
- Done: add an EVM-compatible chain profile layer for deployment metadata,
  starting with `robinhood-chain-testnet` under the `evm` compiler target.
- Add diagnostics for unknown targets and unsupported capabilities.

Acceptance criteria:

- `evm` can be represented as a target profile without changing current EVM
  behavior.
- EVM-compatible chain profiles can reuse the `evm` compiler target without
  being returned by target-id lookup.
- A target profile can declare external tool requirements.
- Unsupported capability errors include target id, capability id, and source
  location when available.

## Workstream 1.5: Portable IR and Shared Scenario

Goal: define the contract IR and Counter scenario before non-EVM spikes.

Tasks:

- Implement IR node types per [portable-ir.md](portable-ir.md).
- Express Counter per [shared-scenario.md](shared-scenario.md).
- Lower Counter IR to EVM (directly or via EmitYul adapter).
- Wire capability checker to [capability-registry.md](capability-registry.md).

Acceptance criteria:

- Counter module is representable in IR without EVM opcodes in the IR layer.
- EVM build from IR matches existing Counter behavior.
- At least one unsupported capability is rejected with a clear diagnostic.
- IR version appears in artifact metadata when emitted.

## Workstream 1.6: Quint Model Generation and MBT Replay

Goal: add Quint as an upstream design-validation layer that generates
state-machine models from portable IR, model-checks them, and produces MBT
traces that replay against ProofForge IR semantics.

Tasks:

- Done: add `ProofForge.Backend.Quint` library with AST (`Model.lean`),
  pretty-printer (`Emit.lean`), IR-to-Quint lowering (`Lower.lean`),
  scenario TOML parsing (`Scenario.lean`), invariant derivation
  (`Invariants.lean`), ITF trace parsing (`ITF.lean`), and IR-semantics replay
  (`Replay.lean`).
- Done: wire `proof-forge emit --target quint --fixture counter` into the CLI
  and `Fixture.lean`.
- Done: add end-to-end test `Tests/Quint/CounterReplay.lean` that lowers
  Counter, runs `quint run --mbt --out-itf`, parses the ITF trace, and replays
  every transition through `ProofForge.IR.Semantics`.
- Done: register toolchain capabilities `model.quint`, `verify.model_check`,
  `verify.simulation`, and `test.mbt_trace` in `docs/capability-registry.md`.
- Done: extend `ProofForge.Contract.Spec.Json.render` with a `verification.quint`
  metadata block (model path, invariants, verify command, checker).
- Done: add `scripts/quint/model-check-gate.sh` and
  `scripts/quint/mbt-replay-gate.sh` with graceful skips when `quint` or
  Java 17+ are unavailable; expose them as `just quint-model-gate` and
  `just quint-mbt-gate`.
- Done: add ValueVault fixture and MBT replay gate (`Tests/Quint/ValueVaultReplay.lean`).
- Done: parse scenario TOML `[invariants]` and emit Quint `val` definitions
  (`ProofForge.Backend.Quint.Scenario`, `Invariants.lean`).
- Done: extend supported IR subset with storage arrays, maps (get/has/set),
  struct field flattening, and `storagePath*` fixtures (`array`, `map`, `map-path`,
  `map-nested-path`, `map-path-assign`, `struct`, `array-path`, `struct-path`,
  `struct-dynamic-path`) wired through `just quint-mbt-gate`.
- Done: scalar local assignment (`letMutBind`, `.assign`, `.assignOp` on
  `.local` targets) with `assignment` fixture in `just quint-mbt-gate`.
- Done: scalar `crosscallInvoke` / `crosscallInvokeTyped` (U64 return stub:
  `target + method + sum(args)`) with `crosscall` fixture in `just quint-mbt-gate`.
- Done: crosscall args coverage — `call_with_args` entrypoint sums nondet
  `amount` + `fee` in the `crosscall` fixture Model/Replay gate.
- Done: typed crosscall scalar returns — `crosscallInvokeTyped` Bool/U32/Hash
  stub casts in Lower/Semantics with `call_remote_bool` / `call_remote_u32` /
  `call_remote_hash` in the `crosscall` fixture gate.
- Done: value/static/delegate typed crosscall stubs — `crosscallInvokeValueTyped`
  (+ callValue), `crosscallInvokeStaticTyped` (+1_000_000 tag),
  `crosscallInvokeDelegateTyped` (+2_000_000 tag) in the `crosscall` fixture gate.
- Done: `crosscallCreate` / `crosscallCreate2` stubs — `callValue + 3_000_000` and
  `callValue + salt + 4_000_000` in Lower/Semantics with `deploy_create` /
  `deploy_create2` in the `crosscall` fixture gate.
- Done: aggregate crosscall params/returns — flatten struct and fixed-array
  leaves into deterministic sum slots in Lower/Semantics with
  `call_remote_pair` / `call_remote_pair_arg` / `call_remote_array` /
  `call_remote_array_arg` in the `crosscall` fixture gate.
- Done: `.assert` / `.assertEq` statement guards with `assert` fixture in
  `just quint-mbt-gate`; gate rebuilds `proof-forge` before CLI emit smoke.
- Done: hash-valued map `storagePathAssignOp` replace stub with
  `map-hash-path-assign` fixture in `just quint-mbt-gate`.
- Done: three+ consecutive `mapKey` `storagePath*` paths via generalized
  `mapKeyPath` lowering with `map-triple-path` fixture in `just quint-mbt-gate`.
- Done: literal + dynamic nested `mapKey` `storagePath*` paths via runtime
  braced segment composition with `map-nested-dynamic-path` fixture in
  `just quint-mbt-gate`.
- Done: nested `#[ref]` struct fields via recursive flattening and `storagePath*`
  lowering with `nested-struct-ref` fixture in `just quint-mbt-gate`.
- Done: unbounded integers abstraction — scenario `unbounded_integers` flag,
  two-domain integer bounds documentation, and `unbounded-int` fixture in
  `just quint-mbt-gate`.
- Done: add `quint verify` to the default CI path via `just quint-model-gate`
  with Temurin Java 17 in `.github/workflows/ci.yml`.
- Done: replay sampled Quint MBT traces through the EVM backend (Counter v1)
  via `ProofForge.Backend.Quint.EvmReplay`, `Tests/Quint/CounterEvmReplay.lean`,
  `scripts/quint/evm-backend-replay-gate.sh`, and `just quint-evm-backend-replay-gate`.
- Done: unified `quint-ir-model-gate` (`scripts/quint/ir-model-gate.sh`,
  `Tests/Quint/CounterIrModelGate.lean`, `Tests/Quint/ValueVaultIrModelGate.lean`,
  `just quint-ir-model-gate`) runs emit → verify → MBT → IR replay → Counter EVM
  replay in one gate; wired into `just check` and CI (replacing standalone
  `quint-model-gate` in CI).
- Done: `contract_source` `quint_invariant` annotations on Counter and
  ValueVault (`ProofForge.Contract.Spec.quintInvariants`, CLI emit merge,
  `Tests/Quint/ContractSourceInvariants.lean`); ValueVault scenario TOML
  `[invariants]` moved to contract source.
- Done: `contract_source` `quint_liveness` temporal annotations on Counter
  (`ProofForge.Contract.Spec.quintLiveness`, `ProofForge.Backend.Quint.Liveness`,
  scenario TOML `[liveness]`, `Tests/Quint/ContractSourceLiveness.lean`).
- Done: unified testkit Quint ITF replay bridge (`testkit/harness-quint`,
  `[[quint]]` scenario expectations, `testkit/scenarios/quint-counter.toml` and
  `quint-value-vault.toml`, `just testkit-quint`, wired into `just quint-mbt-gate`).
- Done: auto-generated per-fixture `*.scenario.toml` via
  `proof-forge emit --target quint --format scenario`
  (`ProofForge.Backend.Quint.Scenario.renderToml`, `Tests/Quint/ScenarioEmit.lean`).

Acceptance criteria:

- `lake env proof-forge emit --target quint --fixture counter` writes a valid
  `build/quint/Counter.qnt` model.
- `quint run build/quint/Counter.qnt` finds no invariant violations.
- `just quint-mbt-gate` replays a generated ITF trace through IR semantics and
  passes.
- `quint verify` is exercised by `just quint-model-gate` and skips gracefully
  when Java 17+ is missing.
- `just quint-evm-backend-replay-gate` replays a Counter MBT ITF trace through
  Foundry-etched EVM bytecode and passes.
- `just quint-ir-model-gate` runs the full Counter/ValueVault Quint validation
  pipeline (emit, verify, MBT, IR replay, and Counter EVM replay) in one step.

## Workstream 2: Artifact Metadata

See [validation-gates.md](validation-gates.md) for current and planned validation commands.

Goal: every build should produce a machine-readable result that can later feed
CI and the cloud platform.

Tasks:

- Done for EVM: add a `proof-forge-artifact.json` schema for EVM bytecode
  builds.
- Done for EVM: emit metadata for `--evm-bytecode` and portable IR EVM bytecode
  fixture builds.
- Done for EVM: include source module, target id, artifact paths, SHA-256, byte
  sizes, solc path/version, selector/signature metadata, and validation status.
- Done for EVM: preserve SDK `.evm-methods` Solidity signatures in
  `abi.methods[].signature` for both `proof-forge-artifact.json` and
  `proof-forge-deploy.json`; validators check selector shape, duplicate method
  selectors/functions/signatures, generated Yul function names, and
  signature/arg-count consistency, and SDK example gates require signatures.
- Done for EVM: emit and validate a ProofForge deploy manifest for every EVM
  bytecode build, recording runtime bytecode inputs, ABI selectors, deployable
  initcode, and the current `not-generated` transaction-broadcast status.
- Done for EVM: generate an artifact-linked `.init.bin` creation bytecode file
  for each EVM bytecode build, record it in both `proof-forge-artifact.json`
  and `proof-forge-deploy.json`, and validate that the initcode header copies
  and returns the referenced runtime bytecode.
- Done for EVM: add `--evm-chain-profile <id>` so bytecode builds can record a
  known EVM chain profile such as `robinhood-chain-testnet` or `anvil-local` in
  `proof-forge-deploy.json`; validators check profile id, chain id, RPC URLs,
  explorer, verifier, and deployment-block consistency without broadcasting.
- Done for EVM: add `--evm-constructor-args-hex <hex>` so bytecode builds can
  append explicit ABI-encoded constructor arguments to generated `.init.bin`,
  record normalized hex/byte-size/SHA-256 constructor metadata in
  `proof-forge-deploy.json`, and validate that the initcode tail matches the
  manifest.
- Done for EVM: add `--evm-constructor-param <name:type>` so bytecode builds
  can record static-word constructor ABI schema in artifact metadata and deploy
  manifests, validate supported schema types, and verify that an explicit
  ABI-encoded constructor-argument blob has the expected 32-byte word length.
- Done for EVM: add `--evm-constructor-arg <name=value>` so bytecode builds can
  ABI-encode typed constructor values for `uint256`, `uint64`, `uint32`,
  `bool`, `bytes32`, and `address`, record whether constructor args came from
  typed values or raw hex, reject missing/duplicate/out-of-range values, and
  validate the generated initcode tail against metadata and deploy manifests.
- Done for EVM: record structured portable IR selector-facing entrypoint ABI
  metadata in `abi.entrypoints`, including Solidity-style selector signatures,
  IR type names, ABI parameter/return types, flattened calldata word
  types/counts, and flattened return word types/counts; validators check
  selector/signature consistency with `cast sig` and
  `EvmAbiAggregateProbe` locks aggregate word layouts with
  `--expect-entrypoint-abi`.
- Done for EVM: record portable IR event ABI metadata in `abi.events`, including
  Solidity-style event signatures, `topic0`, indexed/data fields, flattened ABI
  word types, and topic/data encodings; EventProbe validates every emitted event
  with `--expect-event` and `cast keccak`.
- Done for EVM: extend `scripts/evm/diagnostic-smoke.sh` to lock constructor
  CLI diagnostics for unsupported dynamic constructor ABI types, missing or
  duplicate typed values, mixed typed/raw constructor argument sources,
  overflow, and malformed static-word values such as short addresses.
- Done for EVM: add an Anvil deploy smoke that sends generated Counter
  `.init.bin` with `cast send --create`, records constructor ABI schema and
  typed constructor args plus a `proof-forge-deploy-run.json` artifact,
  records the `eth_getTransactionByHash` creation transaction JSON, validates
  the `anvil-local` chain profile, receipt/deployed address/runtime-code match
  and transaction input initcode, and exercises the Counter lifecycle over
  JSON-RPC.
- Keep schema versioned from day one.

Acceptance criteria:

- EVM bytecode build writes runtime bytecode, deployable initcode, metadata,
  and deploy manifest next to each other.
- Metadata and deploy manifests can be parsed independently by CI scripts.
- Portable IR bytecode metadata and deploy manifests can describe ABI-facing
  entrypoints, including selector signatures, flattened calldata word layout,
  and flattened return-data word layout.
- Portable IR bytecode metadata and deploy manifests can describe ABI-facing
  events, including indexed topic encoding and non-indexed data-word encoding.
- Deploy manifests can carry optional EVM chain profile metadata from the
  target registry while keeping transaction broadcast artifacts explicitly
  `not-generated`.
- Local Anvil deployment can consume the generated deploy manifest and initcode,
  produce a validated deploy-run artifact, and prove the deployed runtime code
  matches the generated bytecode even when the initcode includes a typed or raw
  ABI-encoded constructor-argument tail with a recorded static constructor ABI
  schema; the deploy-run artifact also links the observed creation transaction
  JSON and validates that its input equals the generated initcode and that the
  deployment profile chain id matches the actual local chain.
- EVM metadata can represent missing optional version data as `null`, not
  malformed metadata.

## Workstream 3: EVM Baseline Hardening

See [validation-gates.md](validation-gates.md) for current and planned validation commands.

Goal: keep EVM stable while the target model is introduced.

Tasks:

- Keep `proof-forge --evm-bytecode` working.
- EVM semantic plan migration TODO:
  - Done: make `ModulePlan` target-driven so helper planning is derived from
    `Target.resolveModule/resolveSpec Target.evm` before Yul generation.
  - Split `ProofForge.Backend.Evm.IR` into `Validate`, `Lower`, `ToYul`, and
    `Metadata` modules while keeping `IR.lean` as a compatibility facade until
    callers have moved.
  - Done: move scalar and map storage slot Yul construction to
    `StorageSlotPlan -> ToYul`, starting with map value/presence slots used by
    storage paths.
  - Done: extend `StorageSlotPlan -> ToYul` to array slots and struct-array
    field slots. `IR.lean` now routes storage array and struct-array field slot
    lowering through the plan-to-Yul boundary while keeping compatibility
    facade functions for existing callers.
  - Started: `Lower.buildEntrypointPlan` now fills `EntrypointPlan.body` with
    structural `ExprPlan`/`StmtPlan` nodes for the entrypoint IR body, while
    `IR.lean` remains the compatibility Yul assembly facade.
  - Started: selector-dispatch case assembly now consumes an `EntrypointPlan`
    surface helper in `ToYul`, and unit/static ABI-word dispatcher return-data
    encoding plus dynamic `bytes`/`string` dispatcher return-data encoding now
    consume `ReturnPlan` through the same boundary. Dispatch-block setup now
    consumes `DispatchPlan`: entrypoint parameter plans initialize the
    free-memory pointer for dynamic ABI parameters before the selector switch,
    and `DispatchDefaultPlan` lowers ordinary revert vs. UUPS proxy fallback
    cases in `ToYul`. ABI validation/decode statements and dispatcher
    function-call arguments now consume `AbiParamPlan` through `ToYul`, with
    `AbiParamPlan.headWordIndex` carrying calldata head layout. The planned
    dispatcher call expression and internal entrypoint function naming also now
    live in `ToYul`. `AbiParamPlan.localNames` now carries the planned internal
    Yul parameter names, and `ToYul` emits the internal entrypoint `funcDef`
    shell from an `EntrypointPlan`. `ReturnPlan.localNames` now carries planned
    return variable names, and `ToYul.returnTypedNames` emits function return
    typed names from `ReturnPlan`. Body statements still come from the `IR.lean`
    compatibility facade until broader lowering moves behind
    `EntrypointPlan -> Yul`. Complete plans take this path during normal
    lowering; incomplete best-effort diagnostic plans fall back to compatibility
    lowering so user-facing validation errors are not masked by plan-shape
    errors.
  - Started: scalar local binding initialization now consumes the semantic
    plan path for the supported scalar subset:
    `IR Expr -> Lower.buildExprPlan -> ToYul.exprPlanExpr -> Yul.Expr`.
    Counter, expression, and context smokes prove the generated bytecode still
    runs; unsupported aggregate/crosscall plan nodes stay on the compatibility
    facade until their own migration slices add validation coverage.
  - Started: scalar `let` and `let mut` statement assembly now always consumes
    `Lower.buildExprPlan` before `ToYul.scalarBindingStmtPlanStatements`,
    producing the Yul `varDecl` from `StmtPlan.letBind`/`StmtPlan.letMutBind`.
    The now-unused scalar binding `varDecl` compatibility fallback has been
    removed.
  - Started: scalar `assert` and `assertEq` statement assembly now always
    consumes `Lower.buildExprPlan` before
    `ToYul.scalarAssertStmtPlanStatements`. EVM runtime error payload selection
    remains in the `IR.lean` compatibility facade and is passed into `ToYul`
    as a revert-body callback. The now-unused `lowerAssertStmt` compatibility
    helper has been removed.
  - Started: scalar `return` statement assembly now always consumes
    `Lower.buildExprPlan` before `ToYul.scalarReturnExprPlanStatements` for
    single-word `U32`/`U64`/`Bool`/`Hash`/`Address` return values, including
    branch-local `leave` insertion. Local dynamic `bytes`/`string`/array
    returns always use `ToYul.dynamicReturnStmtPlanStatements`, aggregate returns
    keep `lowerReturnAssignments`, and non-local dynamic returns fail explicitly.
    Local, literal, and storage-backed fixed-array/struct aggregate returns now
    use `Lower.returnValueWordPlan? -> ReturnValueWordPlan -> ToYul` for return
    ABI word assignment. Dynamic local `bytes`/`string`/array return
    statements now use `Lower.buildExprPlan -> StmtPlan.return ->
    ToYul.dynamicReturnStmtPlanStatements` for the return data-pointer
    assignment. The old dynamic return word fallback in `lowerReturnWords` has
    been removed; dynamic return success paths must now pass through
    `StmtPlan.return -> ToYul.dynamicReturnStmtPlanStatements`, while non-local
    dynamic return expressions fail with an explicit unsupported-capability
    diagnostic. Broader aggregate/crosscall return paths continue to migrate
    through their own plan-level slices. The old IR-local fixed-array/struct
    return word fallback helpers have been removed; aggregate return success
    paths must now pass through `ReturnValueWordPlan` or aggregate crosscall
    return planning. The remaining scalar return-word fallback in
    `lowerReturnWords` and the last `lowerScalarPlanExprOrFallback` helper have
    been removed; `lowerReturnAssignments` now fails explicitly when neither
    aggregate crosscall return planning nor `ReturnValueWordPlan` applies.
  - Started: direct scalar local assignment and compound-assignment statement
    assembly now always consumes `Lower.buildExprPlan` before
    `ToYul.scalarAssignmentStmtPlanStatements`. Static local fixed-array element
    assignment, static local struct-field assignment, and static local
    struct-array field assignment targets use the same
    `StmtPlan.assign`/`StmtPlan.assignOp -> ToYul` helper through
    `ExprPlan.localArrayGet` and `ExprPlan.structField`, with RHS lowering via
    `lowerAssignmentValueExpr`. The scalar-local `lowerExpr` assignment fallback
    and `exprSupportsPlanScalarYul` gate in
    `lowerStaticAggregateScalarAssignmentPlan?` have been removed.
  - Started: whole local struct assignment now always consumes
    `Lower.structAssignmentSourcePlans -> ToYul.wholeStructAssignStmtFromPlan`.
    The IR-local `lowerStructAssignmentSourceExprs` compatibility helper that
    duplicated planned source expansion with `lowerExpr` fallbacks has been
    removed. Whole-aggregate fixed-array and struct-array assignment already
    used the planned source path only.
  - Started: static local fixed-array element, struct-field, and struct-array field
    assignment targets in `lowerAssignStmt`/`lowerAssignOpStmt` now always consume
    `lowerStaticAggregateScalarAssignmentStmt` (`buildStaticAggregateScalarTargetPlan?
    -> StmtPlan.assign/assignOp -> ToYul`). The `lowerAssignTargetName` +
    `lowerAssignmentValueExpr` fallbacks for static aggregate assignment targets
    have been removed; unsupported targets now fail explicitly.
  - Started: dynamic local fixed-array element and struct-array field assignment
    targets now lower through `lowerAggregateScalarAssignmentStmt` and
    `ToYul.dynamicAggregateScalarAssignmentStmtPlanStatements`
    (`buildStaticAggregateScalarTargetPlan? -> StmtPlan.assign/assignOp -> ToYul`).
    The IR-local dynamic assignment helpers for one-dimensional and nested path
    switch-frame assembly have been removed; `lowerAssignStmt` and
    `lowerAssignOpStmt` now route non-whole-local aggregate targets through the
    unified planned path.
  - Started: scalar `ifElse` compatibility lowering now always routes condition
    expressions through `Lower.buildExprPlan` before
    `ToYul.ifElseStmtPlanStatements`; the old `switchStmt` fallback over
    `lowerScalarPlanExprOrFallback` has been removed. Whole-aggregate
    assignment, dynamic aggregate helper snapshots, and non-scalar storage
    effect writes remain on their existing compatibility paths until their own
    migration slices add coverage.
  - Started: scalar `storageScalarRead`, `storageScalarWrite`, and
    `storageScalarAssignOp` lowering now consumes `ScalarStorageTargetPlan`
    variants from `Lower.buildEffectPlan` for non-struct scalar states. The
    plan carries the storage slot plus packed byte offset/width, and direct
    `EffectPlan -> ToYul` helpers own the final packed read/write/assign-op
    frame. Struct-valued scalar storage reads/writes remain on compatibility
    paths until their field expansion can be represented as planned storage
    targets. The now-unused `lowerScalarStorageWriteStmt` compatibility helper
    has been removed; scalar storage write success paths now pass through the
    target `EffectPlan -> ToYul` helper.
  - Started: direct `storageMapInsert`/`storageMapSet` write assembly now
    consumes `MapWriteTargetPlan` variants from `Lower.buildEffectPlan` for
    supported scalar map key/value expressions. Statement-position writes and
    expression-position return-old-value writes now both route through direct
    `EffectPlan -> ToYul`/`ExprPlan -> ToYul` helpers that own the planned map
    root slot instead of late compatibility-facade lookup. Direct
    `storageMapContains` and `storageMapGet` reads now also consume
    `MapReadTargetPlan` plus `ToYul.mapContainsTargetExpr` /
    `ToYul.mapGetTargetExpr` for final presence/value slot reads. Storage-path
    map reads and writes continue on their dedicated `StorageSlotPlan` /
    `StoragePathWriteTargetPlan` surfaces until typed map path-expression
    planning is widened. The now-unused `lowerMapSetReturnExpr` helper has
    been removed; expression-position map insert/set return effects remain on
    the target effect-plan path.
  - Started: direct `storageArrayRead`/`storageArrayWrite` assembly now
    consumes `ArrayReadTargetPlan`/`ArrayWriteTargetPlan` variants from
    `Lower.buildEffectPlan` for supported scalar index/value expressions. The
    plans carry the array root slot and length, and direct `ExprPlan -> ToYul`
    / `EffectPlan -> ToYul` helpers now own final
    `__proof_forge_array_slot(root, length, index)` assembly instead of late
    compatibility-facade callbacks. Struct-array field reads/writes and
    storage-path array reads/writes remain on their existing helper/target
    surfaces until their metadata is widened into explicit semantic-plan nodes.
  - Started: direct `storageStructFieldWrite` and
    `storageArrayStructFieldWrite` assembly now consume
    `StructFieldWriteTargetPlan`/`StructArrayFieldWriteTargetPlan` variants
    from `Lower.buildEffectPlan` for supported scalar field values and
    struct-array indexes. The plans carry the struct field slot or struct-array
    root slot/length/field metadata, and direct `EffectPlan -> ToYul` helpers
    now own final `sstore(fieldSlot, value)` and
    `__proof_forge_struct_array_slot(root, length, fieldCount, fieldOffset,
    index)` assembly instead of late compatibility-facade callbacks.
    Direct `storageStructFieldRead` now also consumes
    `StructFieldReadTargetPlan` and `ToYul.structFieldReadTargetExpr` for final
    `sload(fieldSlot)` assembly. Direct `storageArrayStructFieldRead` now
    consumes `StructArrayFieldReadTargetPlan` and
    `ToYul.structArrayFieldReadTargetExpr` for final
    `sload(__proof_forge_struct_array_slot(root, length, fieldCount,
    fieldOffset, index))` assembly. Storage-path struct/array field surfaces
    remain on their dedicated storage-path target path until typed path
    expression planning is widened.
  - Advanced: whole-struct `storageScalarWrite` assembly now always starts from
    `Lower.buildEffectPlan` for local struct sources, storage-struct read
    sources, and struct literals. `Lower.storageStructWriteFieldPlans` expands
    the source into `StorageStructWriteFieldPlan` values, and
    `ToYul.storageStructWriteFieldPlanStatements` owns the final snapshot-temp
    declarations and field-slot `sstore` block. Struct-literal field expressions
    that read individual fields from a storage scalar struct now lower through
    planned `storageLoad` slots via `Lower.buildExprPlan`.
    The now-unused `lowerStorageStructWriteSourceExprs`,
    `lowerStorageStructWriteStmt`, and `storageStructWriteSupportsPlan`
    compatibility helpers have been removed.
  - Advanced: statement-position map/array/struct-field/struct-array-field and
    non-struct scalar storage write/assign-op effects now always route through
    `Lower.buildEffectPlan` before final `ToYul` assembly. The now-unused
    `lowerMapWriteStmt`, `lowerArrayWriteStmt`, `lowerStructFieldWriteStmt`,
    `lowerStructArrayFieldWriteStmt`, `lowerMapScalarPlanExprOrFallback`,
    `lowerArraySlotExpr`, and `lowerStructArrayFieldSlotExpr` compatibility
    helpers have been removed; active write success paths must pass through
    target `EffectPlan -> ToYul` helpers.
  - Started: expression-position `storagePathRead` assembly now consumes a
    planned typed `StorageSlotExprPlan` target from `Lower.buildEffectPlan`.
    Direct map, nested map, array, struct-field, and struct-array-field
    storage-path reads route through `ToYul.storagePathReadExprFromExprPlan`
    for the final `sload` slot expression instead of recomputing the slot only
    in the compatibility facade. Active path segment expressions now flow
    through `Lower.buildStoragePathPlan` as `StoragePathPlanSegment` values
    carrying `ExprPlan`s. The compatibility `lowerStoragePathReadExprTarget`
    helper now also builds `Lower.buildStoragePathPlan` and lowers
    `StorageSlotExprPlan -> ToYul`, so raw path segment expressions no longer
    enter the read fallback through `ValuePlan` wrappers. Older `ValuePlan`
    slot helpers remain only for direct `StorageSlotPlan` helper surfaces and
    legacy compatibility tests.
    The now-unused compatibility `lowerStoragePathReadExpr` wrapper has been
    removed; raw planned effects still use `lowerStoragePathReadExprTarget`
    until the remaining diagnostic-only callers no longer need that target
    callback.
    The now-unused legacy `lowerMapPathReadExpr` nested-map read helper has
    been removed.
  - Started: statement-position `storagePathWrite` and `storagePathAssignOp`
    assembly now consume planned `StoragePathWriteExprTargetPlan` variants from
    `Lower.buildEffectPlan`, with direct `EffectPlan -> ToYul` helpers for
    supported scalar write/assign RHS values across direct `mapKey`, `index`,
    `field`, `index`+`field`, and nested consecutive-`mapKey` paths. The
    active statement path now always enters
    `Lower.buildEffectPlan -> StoragePathWriteExprTargetPlan -> ToYul`; raw
    path segment expressions no longer enter write/assign lowering through
    `ValuePlan` wrappers. The compatibility `lowerStoragePathWriteTarget`,
    `lowerStoragePathWriteStmt`, and `lowerStoragePathAssignOpStmt` helpers
    have been removed, along with the raw
    `ToYul.storagePathWriteEffect*` and
    `ToYul.storagePathAssignOpEffect*` callback surfaces. Direct callers and
    diagnostic paths must now use the target-plan or expr-target-plan helpers.
    The now-unused legacy `lowerMapPathWriteStmt` nested-map writeback helper
    has been removed.
    Storage-path assign-op writeback frames now reuse the same expr-target plan
    path, so `IR.lean` no longer chooses fallback storage-path targets or scalar
    value expressions for statement-position write/assign-op lowering.
  - Started: scalar `ifElse` and `boundedFor` control-flow frame assembly now
    consumes narrow `StmtPlan -> ToYul` helpers. If conditions and synthesized
    bounded-loop guards consume `ExprPlan -> ToYul`; supported branch/loop body
    statements now recursively consume planned scalar bindings, scalar/local
    aggregate-scalar assignments, assertions, returns, reverts, scalar storage
    writes, map writes plus map contains/get read expressions, array writes,
    array read expressions, struct-field writes plus struct/struct-array field
    read expressions, and storage-path writes/assign-ops plus read expressions,
    static and dynamic scalar local fixed-array read expressions,
    static/dynamic local struct-array field read expressions, scalar
    non-indexed/indexed event emits, memory-array set effects,
    memory-array length/get expressions (including length over planned
    memory-array allocation), and scalar crosscall/create helper-call
    expressions inside supported body statements.
    Supported branch/loop body
    sequencing now routes through `ToYul.stmtPlanBodyStatements`, which owns
    statement ordering, environment threading, and branch-local
    `leaveAfterReturn` propagation for planned scalar bodies. Planned
    `revert`/`revertWithError` statement frames now route through
    `ToYul.revertStmtPlanStatements`, including empty revert, message revert,
    and callback-provided `ErrorRef` payloads. Unsupported body
    shapes still remain on the `IR.lean` compatibility facade until full
    recursive `StmtPlan -> Yul` lowering is extracted.
  - Started: scalar event data words and indexed scalar event topics now
    consume the same `ExprPlan -> ToYul` expression boundary. Aggregate event
    flattening and indexed aggregate topic hashing remain in the compatibility
    facade until event assembly is extracted behind `EventPlan -> Yul`.
  - Started: final event block assembly now consumes an `EventPlan -> ToYul`
    helper for signature topic setup, indexed-topic statements, non-indexed
    data stores, and final `log1`-`log4` statement selection. `Lower` now owns
    conversion from `AbiValuePlan` sources into per-field `ExprPlan` word
    sequences before ToYul runs, using `EffectPlan.eventEmitWords` /
    `eventEmitIndexedWords` as the active lowering surface. Full semantic-plan
    construction now returns those word-effect variants directly from
    `Lower.buildEffectPlan`; complete module assembly now consumes
    `ModulePlan` entrypoint bodies for the already-supported planned-body subset
    plus aggregate event word effects whose per-word `ExprPlan`s are supported,
    dynamic local returns, and aggregate local/literal return word assignments,
    storage-backed struct scalar return word assignments, and planned aggregate
    crosscall return assignments, plus scalar planned-body returns whose
    crosscall argument words use local/storage source plans, before falling
    back to the portable IR body path for unsupported shapes.
    The IR facade conversion remains only on compatibility event statement
    paths outside that planned-body subset.
    Planned-body event effects now route through
    `ToYul.eventEffectStmtPlanStatements`, so `StmtPlan.effect`
    selects word-effect event block construction behind ToYul,
    and ToYul owns field/value count checks, word-plan-to-Yul expression
    lowering, and indexed-topic/data routing while IR only supplies field word
    plans. Ordinary event statements now use the same `StmtPlan.effect` helper,
    and the IR-local indexed-topic/data-word wrapper helpers have been removed.
    The compatibility `lowerEventEmitCoreStmt` facade now starts from
    `Lower.buildEffectPlan` for portable event effects and only accepts the
    word-planned `eventEmitWords`/`eventEmitIndexedWords` variants before
    delegating to `ToYul.eventEffectStmtPlanStatements`, so event plan and
    field-value source planning no longer happens in `IR.lean`.
    The earlier Yul-expression and field-word provider callback helper shapes
    have also been removed from the active ToYul surface.
  - Advanced: event data-word store assembly and indexed scalar/aggregate topic
    assembly now consume `EventFieldPlan` plus per-field `ExprPlan` word groups
    behind `ToYul.eventEffectStmtPlanStatements`. Field expression evaluation,
    aggregate flattening, and storage-backed aggregate event word expansion happen
    in `Lower.eventEffectWordPlan`; the old ToYul provider-callback event
    flattening helpers have been removed from the semantic-plan surface.
  - Started: helper discovery is now consumed from `ModulePlan` during
    complete plan-driven module lowering. `lowerModuleWithPlan` emits checked
    arithmetic helpers, crosscall helpers (including planned plain native
    transfers), create/create2 helpers, and local-array getter helpers from the
    semantic plan fields. Incomplete best-effort diagnostic plans now use the
    same `Lower`/`Validate` helper-discovery sources rather than IR-local
    rediscovery, so diagnostics are not masked by plan-shape errors while final
    helper ownership stays outside `IR.lean`.
  - Started: crosscall helper naming and body construction now live behind the
    `CrosscallHelperSpec -> ToYul` boundary. `CrosscallHelperSpec.wordTypes`
    carries the planned return ABI word layout, so scalar helpers, aggregate
    return helpers, and plain native transfer helpers can be emitted from the
    semantic plan without rediscovering return layout from the module during
    complete plan-driven lowering. Complete `ModulePlan` construction now
    discovers crosscall helper specs from the already-built
    `EntrypointPlan.body` `StmtPlan`/`ExprPlan` tree, including planned
    argument word arity, planned return word layout, and native-transfer
    detection, in `Lower.buildFullModulePlan`; `IR.buildSemanticPlan` preserves
    those Lower-discovered specs instead of re-scanning the module. The old
    IR-local fallback discovery scanner has been removed; fallback helper
    discovery now calls the raw-IR compatibility scanner
    `Lower.buildCrosscallHelperPlans` only for incomplete/legacy plan surfaces.
  - Started: create/create2 helper naming and body construction now live behind
    the `CreateHelperSpec -> ToYul` boundary. Planned create specs can emit
    deterministic init-code `mstore` frames, `create`/`create2` opcode calls,
    zero-address revert guards, and helper function names without converting
    back to the `IR.lean` compatibility helper spec. Complete `ModulePlan`
    construction now discovers create/create2 helper specs from the already-built
    `EntrypointPlan.body` `StmtPlan`/`ExprPlan` tree in
    `Lower.buildFullModulePlan` and
    `Lower.buildFullModulePlanWithTargetPlan`; `IR.buildSemanticPlan` preserves
    those Lower-discovered specs instead of re-scanning the module. The old
    IR-local discovery scanner and compatibility helper spec facade have been
    removed; fallback helper discovery calls the raw-IR compatibility scanner
    `Lower.buildCreateHelperPlans` only for incomplete/legacy plan surfaces and
    emits through `ToYul.createHelperFunction`.
  - Started: checked-arithmetic and local fixed-array getter helper
    requirements are now discovered from the already-built `EntrypointPlan.body`
    `StmtPlan`/`ExprPlan` tree in `Lower.buildFullModulePlan` and
    `Lower.buildFullModulePlanWithTargetPlan`. Checked-arithmetic discovery
    covers planned `.checkedArith` expressions and planned
    `assignOp`/storage assign-op nodes. Local-array discovery covers planned
    dynamic `ExprPlan.localArrayGet` paths, nested local-array shapes, and
    dynamic array-literal getters; this avoids the legacy raw scanner's
    over-approximation of standalone row helpers when a nested helper covers
    the same access. `IR.buildSemanticPlan` preserves the Lower-owned
    `usesCheckedArithmetic`, `localArrayGetLengths`, and
    `nestedLocalArrayGetShapes` fields instead of re-scanning the module after
    plan construction. Incomplete-plan fallback lowering still calls
    `Validate.moduleUsesCheckedArithmetic`, `Lower.buildLocalArrayGetLengths`,
    and `Lower.buildNestedLocalArrayGetShapes`. Complete `ModulePlan`
    construction now also replaces broad capability-derived memory-array helper
    requirements with helper requirements discovered from planned entrypoint
    bodies; `memoryArrayLength` alone no longer emits allocation/get helpers,
    and `ToYul` can emit memory-array new/get helpers independently. The same
    planned helper scanner now replaces broad capability-derived hash helpers:
    `hash(x)` only emits `hashWord`, `hashTwoToOne(a,b)` only emits `hashPair`,
    and `ToYul` can emit hash word/pair helpers independently. It also replaces
    state-shape-derived storage-array helpers for complete plans, so unused
    fixed-array, dynamic-array, or struct-array state declarations no longer
    emit `arraySlot`, `dynamicArraySlot`, or `structArraySlot` helpers unless
    planned entrypoint bodies actually reference those storage slot plans.
    Complete plans now also replace broad state-shape-derived map helpers with
    helper requirements discovered from planned entrypoint bodies: unused map
    state no longer emits map helpers, contains-only reads emit only
    `mapPresenceSlot`, value reads emit only `mapSlot`, statement writes emit
    `mapWrite` plus its slot/presence dependencies, expression-position
    insert/set emits `mapSetReturn` plus dependencies, and map assign-op
    helpers update `ModulePlan.mapAssignOps` from the final helper set.
  - Started: `ModulePlan.contextOps` is now discovered from the already-built
    `EntrypointPlan.body` `StmtPlan`/`ExprPlan` tree in
    `Lower.buildFullModulePlan` and
    `Lower.buildFullModulePlanWithTargetPlan`. The planned scanner covers
    `ExprPlan.context`, `EffectPlan.contextRead`, nested `blockHash` argument
    expressions, event words, crosscall/create arguments, storage target
    expression slots, and control-flow bodies, then de-duplicates by
    `ContextField.name`. `IR.buildSemanticPlan` preserves these Lower-owned
    context summaries; the raw `Plan.contextOpsFromModule` scanner remains only
    as the base/best-effort compatibility surface.
  - Started: scalar expression-position crosscall helper-call assembly and
    create/create2 helper-call assembly now live behind `ToYul`. `ExprPlan`
    nodes for scalar `call`, value-bearing `call`, native value transfer,
    `staticcall`, `delegatecall`, `create`, and `create2` can lower directly to
    helper calls using the same helper-name selection used for helper body
    emission. `ToYul.crosscallExprPlanExpr` now owns target/method/call-value
    lowering, provider-backed crosscall argument source expansion, helper-call
    name selection, and final argument ordering for scalar crosscall expressions.
    Planned scalar return frames call the same `lowerExprPlanExpr` callback used
    by expression lowering, so local/storage aggregate crosscall argument source
    plans can be provider-expanded before `ToYul` selects the helper-call shape.
    Legacy untyped `.crosscallInvoke` expression lowering now enters the same
    `Lower.buildExpressionExprPlan` -> `ExprPlan.crosscall` ->
    `ToYul.crosscallExprPlanExpr` path instead of assembling its scalar helper
    call directly inside `IR.lowerExpr`. The compatibility `IR.lean` expression
    lowering still supplies local/storage provider callbacks for source plans.
    Legacy `crosscallCreate` and `crosscallCreate2` expression lowering also now
    enters `Lower.buildExpressionExprPlan` -> `ExprPlan.create` ->
    `ToYul.exprPlanExpr`, removing the old IR-local create helper-call branches.
    Hash expression lowering for `hashValue`, `hash`, and `hashTwoToOne` now
    enters `Lower.buildExpressionExprPlan` -> `ExprPlan.hashValue`/`ExprPlan.hash`/
    `ExprPlan.hashTwoToOne` -> `ToYul.exprPlanExpr`, removing the old IR-local
    hash pack/helper-call branches.
    Scalar arithmetic, division/modulo, bitwise, shift, and exponent expression
    lowering now enters `Lower.buildExpressionExprPlan` -> `ExprPlan.checkedArith`
    or `ExprPlan.builtin` -> `ToYul.exprPlanExpr`, so checked helper selection,
    builtin opcode names, and shift argument ordering no longer live in
    `IR.lowerExpr`.
    Comparison, boolean, cast, and native-value expression lowering now also
    enters `Lower.buildExpressionExprPlan` -> `ExprPlan.builtin`/`ExprPlan.cast`/
    `ExprPlan.nativeValue` -> `ToYul.exprPlanExpr`, removing another direct
    scalar expression frame from `IR.lowerExpr`.
    Scalar literal and local expression leaves now also enter
    `Lower.buildExpressionExprPlan` -> `ExprPlan.literalWord`/`ExprPlan.local` ->
    `ToYul.exprPlanExpr`, including `hash4` limb packing through the same
    `Lower.literalPlan` validation path.
    Expression-position storage and context read effects now enter
    `Lower.buildEffectPlan` -> target `EffectPlan`/`EffectPlan.contextRead` ->
    `lowerPlanEffectExpr`/`ToYul` instead of being dispatched directly from
    `IR.lowerEffectExpr`.
    Raw compatibility `EffectPlan.storageMapContains` and
    `EffectPlan.storageMapGet` expression frames now also use
    `ToYul.mapContainsExpr` and `ToYul.mapGetExpr`; `IR.lean` keeps only the
    map state/root-slot lookup for those legacy plan variants.
    Raw compatibility `EffectPlan.storageArrayRead` expression frames now also
    use `ToYul.arrayReadExpr`; `IR.lean` keeps only the array state root-slot
    and length lookup for that legacy plan variant.
    Raw compatibility `EffectPlan.storageStructFieldRead` expression frames now
    also use `ToYul.structFieldReadExpr`; `IR.lean` keeps only the struct
    state/field slot lookup for that legacy plan variant.
    Raw compatibility `EffectPlan.storageArrayStructFieldRead` expression
    frames now also use `ToYul.structArrayFieldReadExpr`; `IR.lean` keeps only
    the struct-array root-slot/length/field metadata lookup for that legacy
    plan variant.
    The now-unused direct read compatibility helpers for map get/contains,
    fixed-array read, dynamic-array read, and struct-array field read have been
    removed from `IR.lean`; direct storage read expressions now enter through
    `lowerEffectExprThroughPlan` and the `lowerPlanEffectExpr -> ToYul`
    boundary.
    The old `lowerMapPathReadExpr` nested-map read helper has been removed
    after storage-path reads switched to the shared `StorageSlotExprPlan ->
    ToYul` frame.
    Expression-position map insert/set return effects now also enter
    `Lower.buildEffectPlan` -> target `EffectPlan.storageMapInsertTarget`/
    `EffectPlan.storageMapSetTarget` -> `lowerPlanEffectExpr`/
    `ToYul.mapSetReturnTargetExpr`.
    The now-unused `lowerMapSetReturnExpr` helper has been removed after this
    expression-position return-old-value path moved behind target effect
    planning.
    Statement-position scalar storage write and assign-op effects now consume
    `Lower.buildEffectPlan` target effects before calling
    `ToYul.scalarStorageTargetEffectStmtPlanStatements`, so scalar slot,
    packing, and fixed-slot target decisions no longer come from IR-local
    target reconstruction.
    The now-unused `lowerScalarStorageWriteStmt` helper has been removed after
    packed scalar write assembly moved behind the target effect helper.
    Statement-position map insert/set write effects now also consume
    `Lower.buildEffectPlan` target effects before calling
    `ToYul.mapWriteTargetEffectStmtPlanStatements`, so map root-slot target
    decisions and key/value expression planning no longer come from IR-local
    target reconstruction.
    Statement-position fixed-array storage write effects now also consume
    `Lower.buildEffectPlan` target effects before calling
    `ToYul.arrayWriteTargetEffectStmtPlanStatements`, so array root-slot,
    length, index, and value planning no longer come from IR-local target
    reconstruction.
    Statement-position storage struct-field write effects now also consume
    `Lower.buildEffectPlan` target effects before calling
    `ToYul.structFieldWriteTargetEffectStmtPlanStatements`, so struct-field slot
    and value planning no longer come from IR-local target reconstruction.
    Statement-position storage struct-array-field write effects now also consume
    `Lower.buildEffectPlan` target effects before calling
    `ToYul.structArrayFieldWriteTargetEffectStmtPlanStatements`, so struct-array
    field root-slot, length, field offset, index, and value planning no longer
    come from IR-local target reconstruction.
    Statement-position storage-path write and assign-op effects now always
    route through `Lower.buildEffectPlan` before final `ToYul` assembly, so
    `IR.lean` no longer chooses fallback storage-path targets or scalar RHS
    expressions for those paths.
    The old `lowerMapPathWriteStmt` nested-map writeback helper has been
    removed after the fallback path switched to the shared `ToYul` frame.
    The old `lowerStoragePathWriteTarget`, `lowerStoragePathWriteStmt`, and
    `lowerStoragePathAssignOpStmt` compatibility helpers plus the raw
    `ToYul.storagePathWriteEffect*` / `ToYul.storagePathAssignOpEffect*`
    callback surfaces have been removed; active storage-path write-like
    lowering must use target-plan or expr-target-plan helpers.
    Statement-position dynamic-array push/pop effects now also consume
    `Lower.buildEffectPlan` target variants carrying a
    `DynamicArrayTargetPlan` before calling
    `ToYul.dynamicArrayPushTargetEffectStmtPlanStatements`/
    `ToYul.dynamicArrayPopTargetEffectStmtPlanStatements`, so push value
    expression planning, pop effect validation, root-slot selection, and final
    dynamic-array slot helper assembly no longer come from IR-local effect
    reconstruction callbacks.
    `Lower.buildEffectPlan` now rejects invalid dynamic-array targets instead
    of returning raw `storageDynamicArrayPush`/`storageDynamicArrayPop`
    fallback plans, and the unused raw dynamic-array ToYul helper/callback
    surface has been removed.
    Entrypoint body-plan completeness is now checked separately from dispatch
    plan completeness, so modules with EVM fallback/receive entrypoints can
    still consume full body plans while dispatch continues to cover only
    selector-addressable functions. Surface plans with empty bodies no longer
    erase fallback/receive lowering.
    The now-unused `lowerDynamicArrayWriteStmt` and
    `lowerDynamicArrayPopStmt` fallback helpers have been removed; dynamic-array
    write-like behavior remains on storage-path write plans, and dynamic-array
    pop success paths must pass through target effect planning.
  - Started: expression-position local fixed-array getter, local struct-field
    getter, and scalar array-literal indexing assembly now live behind
    `ExprPlan -> ToYul` for local scalar leaves. `Lower` records local
    fixed-array path dimensions in `ExprPlan.localArrayGet`, and `ToYul` owns
    the static local-name selection, local struct-field name selection, struct
    literal field selection, array literal element selection, plus
    one-dimensional and nested dynamic helper-call argument frames for scalar
    arrays, scalar array literals, and struct-array fields. Direct
    `IR.lowerExpr` local fixed-array reads now first consume
    `Lower.buildExprPlan` when it produces `.localArrayGet`, and direct local
    struct-field reads first consume `Lower.buildExprPlan` when it produces
    supported `.structField` plans for local struct values, struct literals, or
    local struct-array leaves. Direct scalar array-literal reads also first
    consume `Lower.buildExprPlan` when it produces `.arrayGet (.arrayLit ..)`.
    Storage-backed struct reads, aggregate array values, and unsupported
    aggregate local-array leaves still fall back through the compatibility
    facade.
  - Started: whole local aggregate assignment snapshot blocks now live behind
    `ToYul`. Local fixed-array and flat struct whole-assignment sources now
    enter `Lower.fixedArrayAssignmentSourcePlans` or
    `Lower.structAssignmentSourcePlans` first, so local aggregate sources and
    array/struct literal scalar expressions are represented as `ExprPlan`s
    before `ToYul.*AssignStmtFromPlan` emits the snapshot block.
    Storage-backed scalar struct assignment sources also enter
    `Lower.structAssignmentSourcePlans` and are represented as
    `ExprPlan.storageLoad` word expressions. Nested fixed-array whole-assignment
    sources now enter `Lower.nestedFixedArrayAssignmentSourcePlans` and lower
    through `ToYul.wholeNestedFixedArrayAssignStmtFromPlan`; the IR-local
    `NestedFixedArraySourceExpr` expansion helpers have been removed.
    Struct-array whole-assignment sources now enter
    `Lower.structArrayAssignmentSourcePlans` and lower through
    `ToYul.wholeStructArrayAssignStmtFromPlan`; the IR-local
    `lowerStructArrayAssignmentSourceExprs` helper has been removed.
    Final temp declarations, target local names, and assignment block
    construction are delegated to `ToYul` helpers so the compatibility facade
    no longer owns the final Yul statement frame for supported whole local
    aggregate sources.
  - Started: dynamic local aggregate assignment switch frames now live behind
    `ToYul`. `IR.lean` still resolves dynamic local fixed-array and
    struct-array paths, but dynamic index/value snapshot expressions now enter
    `Lower.buildExprPlan` before `ToYul` emits the shared snapshot locals,
    switch default case, checked-assignment RHS, one-dimensional switch frame,
    and nested path switch frame.
  - Started: aggregate crosscall helper-call assembly and entrypoint multi-word
    return assignment now live behind `ToYul`. Expression-position aggregate
    crosscall return diagnostics now come from `Lower.buildExpressionExprPlan`,
    while aggregate crosscall return assignment decisions now come from
    `Lower.aggregateCrosscallReturnAssignmentPlan?`. That plan records the call
    mode, target/method/call-value expression plans, planned crosscall argument
    words, and `ReturnPlan` local-name/word-layout data; `IR.lean` consumes the
    planned `ExprPlan`s and delegates final helper-call function-name
    selection, argument ordering, and multi-return Yul assignment construction
    to `ToYul`. Aggregate ABI word expansion for entrypoint returns, indexed
    events, and event data now uses `AbiValuePlan` source nodes instead of
    `ExprPlan.localAbiWords`/`ExprPlan.storageAbiWords` expression markers.
    `ReturnValueWordPlan.source`, planned event data fields, and planned event
    indexed fields now carry `AbiValuePlan.expr`, `AbiValuePlan.local`,
    `AbiValuePlan.storage`, `AbiValuePlan.arrayLit`, or
    `AbiValuePlan.structLit`. `Lower.returnValueWordPlans`,
    `Lower.eventFieldDataWordPlans`, and `Lower.eventFieldsDataWordPlans`
    expand those ABI value plans into scalar word `ExprPlan`s. Local aggregates
    lower to explicit `.local` word plans through `Lower.localAbiWordPlans`,
    storage-backed aggregates lower to explicit `ExprPlan.storageLoad` word
    plans through `Lower.storageAbiWordPlans`, and fixed-array/struct literals
    recursively lower to scalar word plans in `Lower.abiValueWordPlans`.
    `IR.lean` now consumes those planned words, lowers each word plan to Yul,
    and delegates only the final return assignment frame to
    `ToYul.returnValueWordAssignments` plus the final event topic/log frames to
    `ToYul.eventIndexedTopicStatements` and `ToYul.eventEmitCoreStatement`.
    Compatibility return and explicit local/storage word helpers still exist for
    direct tests and older callers, but the active IR facade no longer depends
    on provider callbacks or expression-level aggregate source markers for
    return/event aggregate ABI word expansion. Event provider-callback
    `ToYul.*FromPlan` helpers have been removed from the semantic-plan surface.
    Crosscall helper-call assembly now uses
    dedicated `CrosscallArgWordPlan` source nodes rather than expression-level
    crosscall word markers. `ExprPlan.crosscall.args` and
    `CrosscallReturnAssignmentPlan.args` carry planned crosscall argument word
    sources: scalar/literal/storage-load words use `CrosscallArgWordPlan.expr`,
    local aggregate struct/fixed-array sources are now expanded by `Lower` into
    explicit `CrosscallArgWordPlan.expr (.local ...)` word plans, and
    storage-backed aggregate struct/fixed-array sources are now expanded by
    `Lower` into explicit
    `CrosscallArgWordPlan.expr (.storageLoad ...)` word plans instead of
    preserving provider-backed local or storage source markers on the active
    lowering path.
    The obsolete
    `ExprPlan.localAbiWords`, `ExprPlan.storageAbiWords`,
    `ExprPlan.localCrosscallWords`, and `ExprPlan.storageCrosscallWords`
    constructors have been retired from `ExprPlan`.
    `Lower.buildCrosscallArgWordPlansMany`
    now returns those source plans, while active IR lowering consumes them
    through `ToYul.crosscallExpandedArgWordPlanExprs`, which accepts only
    pre-expanded `.expr` word plans. `ToYul.crosscallExpandedExprPlanExpr` wraps
    that traversal with target/method/call-value lowering and scalar helper-call
    selection. Legacy untyped scalar expression crosscall lowering now enters
    `Lower.buildExpressionExprPlan` -> `ExprPlan.crosscall` before that ToYul
    boundary. The old IR-local scalar helper-call branch and
    `lowerCrosscall*ArgWords` expansion tree have been removed.
    Done: retired the provider-backed crosscall ToYul/IR surfaces:
    `ToYul.crosscallArgWordPlanExprs`, `ToYul.crosscallExprPlanExpr`,
    `ToYul.crosscallAggregateReturnAssignmentPlanStatement`,
    `ToYul.localCrosscallWords`, and the IR compatibility helpers
    `lowerLocalCrosscallWords`, `lowerStorageCrosscallWords`,
    `lowerCrosscallArgWordPlanExprs`, and `lowerCrosscallArgWordsMany`.
    Semantic-plan tests now cover only the expanded-word path through
    `Lower.buildCrosscallArgWordPlansMany` / `Lower.localCrosscallWordPlans`
    plus `ToYul.crosscallExpandedArgWordPlanExprs` /
    `ToYul.crosscallExpandedExprPlanExpr`.
    Aggregate crosscall return assignment now also enters
    `ToYul.crosscallAggregateReturnAssignmentExpandedPlanStatement`, so
    target/method/call-value lowering, planned crosscall argument word traversal,
    helper-call name selection, argument ordering, and multi-return assignment
    construction live behind the ToYul plan boundary without provider callbacks.
  - Add `EntrypointPlan` for selector dispatch, calldata guards, ABI word
    flattening, return-data encoding, and metadata selector layout.
  - Add `EventPlan` for event signature topics, indexed-topic hashing,
    non-indexed data flattening, and metadata event layout.
  - Add `CrosscallPlan` for typed `call`, value-bearing `call`, `staticcall`,
    `delegatecall`, `create`, and `create2` helpers.
  - Add `MetadataPlan` and deploy-artifact planning so bytecode metadata,
    initcode, deployment manifests, and chain profile references are produced
    from the same semantic plan.
  - Delete the old custom semantic `IR.lean -> Yul` lowering only after each
    migrated capability is covered by plan-level diagnostics, golden Yul, solc
    bytecode generation, Foundry smokes, artifact metadata validation, and the
    EVM IR coverage manifest.
  - Keep `ProofForge.Compiler.Yul.AST` and
    `ProofForge.Compiler.Yul.Printer`; the migration replaces backend semantic
    lowering, not the target AST/printer boundary.
- Done: add EVM IR diagnostic smoke so unsupported portable IR shapes fail
  before Yul generation with stable messages.
- Done: add an EVM IR coverage manifest gate so every portable IR constructor
  must be classified as lowered, validated, unsupported, or structural for the
  EVM backend.
- Done: add `AbiScalarProbe` for portable IR EVM scalar ABI parameter decoding
  over `U64`, `U32`, and `Bool`, with golden Yul, solc bytecode, and Foundry
  malformed-calldata validation.
- Done: add EVM IR `assert` and `assert_eq` lowering as Yul revert guards,
  with `AssertProbe` golden Yul, solc bytecode, and Foundry success/revert
  validation.
- Done: add EVM IR mutable scalar local bindings and local assignment lowering,
  with `AssignmentProbe` golden Yul, solc bytecode, and Foundry success/revert
  validation.
- Done: add EVM IR local and scalar storage compound assignment lowering for
  all portable `AssignOp` variants, with `EvmAssignOpProbe` golden Yul, solc
  bytecode, Foundry runtime/raw-slot validation, metadata capability
  validation, and explicit diagnostics for malformed targets/types.
- Done: add EVM IR statement-level `if/else` lowering as Yul `switch` blocks,
  with `ConditionalProbe` golden Yul, solc bytecode, Foundry runtime
  validation, plus EVM-specific branch-local early-return validation through
  `EvmLoopProbe`.
- Done: add EVM IR `boundedFor` lowering as Yul `for` loops with static
  bounds, with `EvmLoopProbe` golden Yul, solc bytecode, Foundry runtime/raw
  storage validation, metadata capability validation, branch-local and
  loop-local early-return lowering through Yul `leave`, and explicit invalid
  range diagnostics.
- Done: add EVM IR context read lowering for `userId`, `contractId`, and
  `checkpointId` as Yul `caller()`, `address()`, and `number()`, with
  `ContextProbe` golden Yul, solc bytecode, Foundry runtime validation, and
  metadata capability validation.
- Done: add EVM IR `nativeValue` lowering as Yul `callvalue()`, with
  `ContextProbe` golden Yul, solc bytecode, Foundry value-bearing call
  validation, and `value.native` metadata capability validation.
- Done: add EVM IR `eventEmit` lowering to Yul `log1` with
  `keccak256(Solidity-style event signature)` topic0 and 32-byte word data
  fields, with `EventProbe` golden Yul, solc bytecode, Foundry recorded-log
  validation, metadata capability validation, and explicit malformed event
  diagnostics.
- Done: add EVM IR `eventEmitIndexed` lowering to Yul `log2`/`log3`/`log4`
  for up to three scalar indexed fields, with signature topic0, indexed topics,
  non-indexed 32-byte word data, `EventProbe` golden Yul, solc bytecode,
  Foundry recorded-log validation, metadata capability validation, and explicit
  indexed event diagnostics.
- Done: close the EventProbe validation gap for multi-topic scalar indexed
  events. `IndexedTwoValues(uint64,uint64,uint64)` and
  `IndexedThreeValues(uint64,uint64,uint64,uint64)` now prove the generated Yul
  emits `log3` and `log4`, preserves ordered scalar indexed topics, validates
  metadata selectors, compiles with `solc`, and passes Foundry recorded-log
  assertions.
- Done: close the EventProbe validation gap for typed scalar event fields.
  `TypedScalarEvent(bool,uint32,bytes32)` and
  `IndexedTypedScalar(bool,uint32,bytes32,uint64)` now prove Bool, U32, and
  Hash event data words and indexed topics lower correctly, with Bool/U32
  dispatcher guards, golden Yul, metadata selector checks, `solc`, and Foundry
  recorded-log assertions.
- Done: extend EVM IR event data lowering beyond scalar words so non-indexed
  flat struct fields, scalar fixed-array fields, and fixed arrays of flat
  structs emit ABI-style flattened data words, with canonical Solidity-style
  event signatures such as `PairEvent((uint64,uint64))`,
  `ArrayEvent(uint64[2])`, and `PairArrayEvent((uint64,uint64)[2])`,
  `EventProbe`
  golden Yul, solc bytecode, Foundry recorded-log validation, metadata selector
  validation, and explicit diagnostics for unsupported aggregate indexed fields.
- Done: extend EVM IR `eventEmitIndexed` lowering so flat struct indexed fields
  and fixed-array indexed fields whose elements are flat structs hash their
  ABI-style flattened words into indexed topics. `EventProbe` now covers
  `IndexedPair((uint64,uint64),uint64)` and
  `IndexedPairArray((uint64,uint64)[2],uint64)` with golden Yul, solc bytecode,
  metadata selector validation, Foundry recorded-log topic-hash checks, and a
  diagnostic for nested/unsupported aggregate indexed shapes.
- Done: close the EventProbe validation gap for scalar fixed-array indexed
  topics by adding `IndexedArray(uint64[2],uint64)` golden Yul, metadata selector
  validation, solc bytecode generation, and Foundry recorded-log topic-hash
  checks.
- Done: extend EventProbe nested fixed-array event aggregate coverage.
  `MatrixEvent(uint64[2][2])` and
  `PairMatrixEvent((uint64,uint64)[2][2])` prove recursive non-indexed data
  flattening for scalar and flat-struct leaves, while
  `IndexedMatrix(uint64[2][2],uint64)` and
  `IndexedPairMatrix((uint64,uint64)[2][2],uint64)` prove indexed aggregate
  topic hashing over recursively flattened ABI-style words. The smoke now locks
  the new selectors, event ABI metadata, golden Yul, `solc` bytecode, and
  Foundry recorded-log assertions; nested arrays with unsupported or non-flat
  leaves remain explicit diagnostics.
- Done: add EventProbe coverage for storage-backed flat struct event data and
  indexed aggregate topics. `StoragePairEvent((uint64,uint64))` and
  `IndexedStoragePair((uint64,uint64),uint64)` now prove that a whole scalar
  storage struct write can be read back through `storageScalarRead`, flattened
  into event data words, hashed into indexed topics, validated in golden Yul,
  checked in metadata selectors, compiled by `solc`, and decoded by Foundry
  recorded logs.
- Done: add EventProbe coverage for storage-backed fixed-array event aggregates.
  `StorageArrayEvent(uint64[2])`,
  `StoragePairArrayEvent((uint64,uint64)[2])`,
  `IndexedStorageArray(uint64[2],uint64)`, and
  `IndexedStoragePairArray((uint64,uint64)[2],uint64)` now prove that storage
  array reads and storage array struct field reads can feed non-indexed event
  data flattening and indexed aggregate topic hashing, with golden Yul,
  metadata selector checks, `solc`, and Foundry recorded-log validation.
- Done: add EVM IR `crosscallInvoke` lowering to synchronous EVM `call`
  helpers with selector packing, word arguments, one-word returns, failed-call
  and short-return reverts, with `EvmCrosscallProbe` golden Yul, solc bytecode,
  Foundry runtime validation, metadata capability validation, and explicit
  malformed crosscall type diagnostics.
- Done: add EVM IR `crosscallInvokeTyped` lowering for typed scalar-word
  crosscalls over `Bool`, `U32`, `U64`, and `Hash`, with return-type-specific
  Yul helpers, Bool/U32 return-data guards, `EvmCrosscallProbe` golden Yul,
  solc bytecode, Foundry valid/invalid typed-return validation, metadata
  entrypoint validation, diagnostics for aggregate argument/return shapes not
  covered at that stage, and explicit Psy unsupported diagnostics.
- Done: extend EVM IR normal `crosscallInvokeTyped` return lowering beyond
  scalar words for direct entrypoint returns of flat structs and scalar fixed
  arrays, with ABI-word-shape-specific Yul helpers, multi-word return-data
  size checks, Bool/U32 range guards across aggregate return words,
  `EvmCrosscallProbe` golden Yul, solc bytecode, Foundry aggregate
  struct/array return validation, metadata selector validation, and explicit
  diagnostics for aggregate return shapes not covered at that stage.
- Done: extend EVM IR typed crosscall argument lowering beyond scalar words so
  normal, value-bearing, static, and delegate typed calls can flatten flat
  struct and scalar fixed-array arguments into ABI words. `EvmCrosscallProbe`
  now covers normal struct and fixed-array arguments plus value/static/delegate
  struct arguments through golden Yul, solc bytecode, Foundry runtime checks,
  metadata selector validation, and explicit diagnostics for aggregate argument
  shapes not covered at that stage.
- Done: add EVM IR `crosscallInvokeValueTyped` lowering for value-bearing typed
  crosscalls, forwarding an explicit U64 call-value expression through
  value-specific Yul helpers for scalar returns plus flat struct and scalar
  fixed-array entrypoint aggregate returns, with `EvmCrosscallProbe` golden Yul,
  solc bytecode, Foundry `msg.value`/callee-balance validation, aggregate
  Bool/U32 malformed-return guards, metadata entrypoint validation, EVM
  malformed value/return diagnostics, and explicit Psy unsupported diagnostics.
- Done: add EVM IR `crosscallInvokeStaticTyped` lowering for typed staticcalls,
  using value-free Yul `staticcall` helpers with selector/scalar/flat-aggregate
  argument packing, scalar returns, flat struct and scalar fixed-array
  entrypoint aggregate returns, and Bool/U32 return guards, with
  `EvmCrosscallProbe` golden Yul, solc bytecode, Foundry U64 read-only return,
  Bool/U32/Hash static typed return, aggregate return validation, invalid
  typed-return, static-context state-write failure validation, metadata
  entrypoint validation, EVM malformed nested aggregate diagnostics, and
  explicit Psy unsupported diagnostics.
- Done: add EVM IR `crosscallInvokeDelegateTyped` lowering for typed
  delegatecalls, using value-free Yul `delegatecall` helpers with
  selector/scalar/flat-aggregate argument packing, scalar returns, flat struct
  and scalar fixed-array entrypoint aggregate returns, and Bool/U32 return
  guards, with `EvmCrosscallProbe` golden Yul, solc bytecode, Foundry
  caller-storage read/write validation, Bool/U32/Hash delegate typed return
  validation, aggregate return validation, invalid typed-return validation,
  metadata entrypoint validation, EVM malformed nested aggregate diagnostics,
  and explicit Psy unsupported diagnostics.
- Done: extend EVM IR typed crosscall aggregate coverage to fixed arrays of
  flat structs across normal, value-bearing, static, and delegate typed call
  arguments and direct entrypoint returns. `EvmCrosscallProbe` now validates
  `RemotePair[2]` ABI-word flattening, Bool/U32 field return guards, golden
  Yul, solc bytecode, Foundry runtime behavior, and metadata selectors across
  all four call modes.
- Done: extend EVM IR typed crosscall aggregate coverage to nested scalar fixed
  arrays across normal, value-bearing, static, and delegate typed call
  arguments and direct entrypoint returns. `EvmCrosscallProbe` now validates
  `uint64[2][2]` ABI-word flattening, golden Yul, solc bytecode, metadata
  selectors, Foundry runtime behavior, value forwarding, staticcall behavior,
  and delegatecall behavior across all four call modes. At that milestone,
  diagnostics still rejected struct and other non-scalar nested fixed-array
  leaves; flat struct leaves are now covered by the follow-up item below.
- Done: extend EVM IR typed crosscall aggregate coverage to nested fixed arrays
  whose leaves are flat structs. `EvmCrosscallProbe` now validates
  `RemotePair[2][2]` arguments and direct entrypoint returns across normal,
  value-bearing, static, and delegate typed calls, including ABI word
  flattening, Bool/U32 field guards, golden Yul, solc bytecode, metadata
  selectors, Foundry runtime behavior, value forwarding, staticcall behavior,
  and delegatecall behavior. Diagnostics still reject nested fixed-array leaves
  whose structs are non-flat or otherwise unsupported.
- Done: add EVM IR `crosscallCreate` and `crosscallCreate2` lowering for fixed
  init-code hex. Creation helpers write init code to memory, call Yul
  `create`/`create2`, revert on zero-address failure, return the deployed
  address word, and validate golden Yul, solc bytecode, metadata selectors,
  Foundry deployed runtime calls, deterministic CREATE2 address derivation,
  EVM malformed creation diagnostics, and Psy unsupported diagnostics.
- Done: add EVM IR direct scalar expression validation for `U64`/`U32`
  arithmetic, `U64` exponentiation, `U64`/`U32` bitwise operations and shifts,
  predicates, boolean operators, literals, immutable locals, supported casts,
  one-word returns, dispatcher guards, and assertion guards, with
  `EvmExpressionProbe` golden Yul, solc bytecode, Foundry runtime/malformed
  calldata validation, metadata capability validation, and CI coverage.
- Done: add EVM IR `Hash` word lowering, `hash4`/`hashValue` packing, and
  `hash`/`hash_two_to_one` lowering through Yul `keccak256` helpers, with
  `EvmHashProbe` golden Yul, solc bytecode, Foundry ABI/storage validation,
  metadata capability validation, and explicit Hash/U64 mismatch diagnostics.
- Done: add EVM IR `Map<U64, U64, N>` storage lowering through
  Solidity-style `keccak256(key, slot)` mapping slots, with `EvmMapProbe`
  golden Yul, solc bytecode, Foundry runtime/raw-slot validation, metadata
  capability validation, and explicit diagnostics for unsupported map shapes
  and statement-position misuse.
- Done: add EVM IR single-segment `mapKey` storage path compound assignment
  over `Map<U64, U64, N>`, with `EvmMapProbe` golden Yul, solc bytecode,
  Foundry runtime/raw-slot validation, metadata capability validation, and
  explicit diagnostics for expression-position and nested-path misuse.
- Done: generalize EVM IR storage maps to word key/value shapes over `U32`,
  `U64`, `Bool`, and `Hash`, reusing Solidity-style `keccak256(key, slot)`
  mapping slots, with `EvmTypedMapProbe` golden Yul, solc bytecode, Foundry
  runtime/raw-slot validation, `U32`/`Bool` calldata guards, metadata
  capability validation, CI coverage, and explicit diagnostics for non-word map
  shapes.
- Done: add EVM IR `storage.map.contains` lowering through ProofForge-managed
  presence slots rooted at `keccak256(slot || PROOF_FORGE_MAP_PRESENCE)`,
  with `EvmMapProbe` and `EvmTypedMapProbe` golden Yul, solc bytecode, Foundry
  value/presence-slot validation for U64/U32/Bool/Hash maps, zero-valued
  present-key coverage, metadata validation, and explicit diagnostics for
  statement-position misuse.
- Done: add EVM IR nested map storage paths over consecutive `mapKey`
  segments, folding Solidity-style mapping slots for value storage and
  ProofForge-managed presence slots for final keys, with `EvmMapProbe` and
  `EvmTypedMapProbe` golden Yul, solc bytecode, Foundry raw-slot validation,
  U32 dispatcher guard coverage, metadata validation, and explicit diagnostics
  for mixed map/aggregate storage paths.
- Done: add EVM IR `U64` fixed storage array lowering as contiguous storage
  slots with runtime bounds checks, with `EvmStorageArrayProbe` golden Yul,
  solc bytecode, Foundry runtime/raw-slot validation, metadata capability
  validation, and explicit diagnostics for unsupported array element types.
- Done: add EVM IR single-segment `index` storage path read/write/compound
  assignment over `U64` fixed storage arrays, reusing the bounded array slot
  helper and extending `EvmStorageArrayProbe` validation.
- Done: generalize EVM IR word storage to `Bool` scalar storage and
  `U32`/`Bool`/`Hash` fixed storage arrays, reusing the bounded array slot
  helper, with `EvmTypedStorageProbe` golden Yul, solc bytecode, Foundry
  runtime/raw-slot validation, `U32` calldata range guards, metadata capability
  validation, CI coverage, and explicit diagnostics for unsupported non-word
  storage element types.
- Done: add EVM IR immutable local fixed-array value lowering for `U64`,
  `U32`, `Bool`, and `Hash` elements with static literal indexes, direct
  fixed-array literal indexing, `EvmArrayValueProbe` golden Yul, solc
  bytecode, Foundry runtime validation, metadata capability validation, and
  explicit diagnostics for static out-of-bounds indexes.
- Done: extend EVM IR local fixed-array lowering to mutable aggregate locals,
  including static element assignment, numeric element compound assignment, and
  `U32`/`Bool`/`Hash` element writes, with `EvmArrayValueProbe` golden Yul,
  solc bytecode, Foundry runtime validation, metadata entrypoint validation,
  CI coverage, and explicit diagnostics for immutable element assignment.
- Done: extend EVM IR local fixed-array lowering to dynamic local/literal
  indexes by threading a lowering environment through expressions, generating
  length-specific Yul getter helpers for dynamic reads, lowering dynamic local
  element assignment and numeric compound assignment to `switch` blocks, and
  validating dynamic in-bounds/out-of-bounds behavior through
  `EvmArrayValueProbe` golden Yul, metadata entrypoints, solc bytecode, and
  Foundry runtime checks.
- Done: add EVM IR whole local fixed-array assignment from local values and
  literals, snapshotting RHS elements into temporary Yul locals before writing
  target elements, and validating local-source and self-referential literal RHS
  behavior through `EvmArrayValueProbe` golden Yul, metadata entrypoints, solc
  bytecode, and Foundry runtime checks.
- Done: extend EVM IR local fixed-array lowering to static nested scalar arrays,
  including immutable reads, mutable leaf assignment, numeric leaf compound
  assignment, nested whole-local assignment, and RHS snapshotting, with
  `EvmArrayValueProbe` golden Yul, metadata entrypoints, solc bytecode, and
  Foundry runtime checks. Flat struct nested leaves are covered by
  `EvmStructArrayValueProbe`; other unsupported aggregate leaves remain
  explicit diagnostics.
- Done: extend EVM IR local fixed-array lowering to dynamic nested scalar array
  indexes, including nested getter helpers for reads, nested `switch` lowering
  for mutable leaf assignment and compound assignment, mixed static/dynamic
  path coverage, runtime out-of-bounds reverts, `EvmArrayValueProbe` golden
  Yul, metadata entrypoints, solc bytecode, and Foundry runtime checks.
- Done: add EVM IR flat immutable local struct value lowering for `U64`,
  `U32`, `Bool`, and `Hash` fields, direct struct literal field access,
  `EvmStructValueProbe` golden Yul, solc bytecode, Foundry runtime validation,
  metadata capability validation, and explicit diagnostics for whole-struct
  storage misuse and nested fields.
- Done: extend EVM IR flat local struct lowering to mutable aggregate locals,
  including static field assignment, numeric field compound assignment, and
  `U32`/`Bool`/`Hash` field writes, with `EvmStructValueProbe` golden Yul,
  solc bytecode, Foundry runtime validation, metadata entrypoint validation,
  CI coverage, and explicit diagnostics for immutable field assignment.
- Done: add EVM IR whole local struct assignment from local values and literals,
  snapshotting RHS fields into temporary Yul locals before writing target
  fields, and validating local-source and self-referential literal RHS behavior
  through `EvmStructValueProbe` golden Yul, metadata entrypoints, solc bytecode,
  and Foundry runtime checks.
- Done: add EVM IR local fixed arrays of flat structs, expanding each element
  field into deterministic Yul locals, supporting static and dynamic
  `field(arrayGet(localArray, index), name)` reads, mutable field assignment,
  numeric field compound assignment, whole local assignment from local arrays
  and self-referential array literals with RHS snapshotting,
  `U64`/`U32`/`Bool`/`Hash` field coverage, dynamic out-of-bounds reverts,
  `EvmStructArrayValueProbe` golden Yul, metadata entrypoint/capability
  validation, solc bytecode generation, Foundry runtime checks, and CI
  coverage.
- Done: extend EVM IR nested local fixed arrays to flat struct leaves, expanding
  each nested element field into deterministic Yul locals, supporting static and
  dynamic nested field reads, nested mutable field assignment, numeric nested
  field compound assignment, whole nested local assignment from local arrays and
  self-referential nested array literals with RHS snapshotting, dynamic
  out-of-bounds reverts, refreshed `EvmStructArrayValueProbe` golden Yul,
  metadata entrypoint validation, solc bytecode generation, Foundry runtime
  checks, and coverage manifest updates.
- Done: add EVM IR flat storage struct lowering for scalar storage structs and
  fixed storage arrays of flat structs, including direct struct field effects,
  scalar `field` storage paths, array `index`+`field` storage paths, numeric
  field compound assignment, whole scalar storage struct read/write with RHS
  snapshotting, storage-backed ABI struct returns, `Bool`/`U32`/`Hash` field
  coverage, `EvmStorageStructProbe` golden Yul, solc bytecode, Foundry
  runtime/raw-slot validation, metadata capability validation, CI coverage, and
  explicit diagnostics for missing fields and non-flat storage structs.
- Done: validate storage-backed aggregate ABI returns for EVM IR by extending
  `EvmStorageArrayProbe` with `return_values()` over storage-array element
  reads and `EvmStorageStructProbe` with `return_points()` over fixed
  storage-array-of-struct field reads, including golden Yul, solc bytecode,
  metadata selector validation, Foundry ABI decoding, and raw-slot checks.
- Done: add EVM IR static aggregate ABI lowering for fixed-array and struct
  parameters/returns, including nested scalar fixed arrays and fixed arrays of
  flat structs, with calldata word flattening, `U32`/`Bool` aggregate word
  guards, multi-word return-data encoding, `EvmAbiAggregateProbe` golden Yul,
  solc bytecode, Foundry runtime/malformed calldata validation, metadata
  capability validation, structured `abi.entrypoints` selector/calldata/return
  word-layout validation, CI coverage, and explicit diagnostics for Unit,
  zero-length arrays, non-flat struct fields, and crosscall-only unsupported
  nested fixed-array leaf shapes.
- Done: close the EVM aggregate ABI validation gap for `Hash` leaves.
  `HashPair(bytes32,bytes32)`, `pick_hash(bytes32[2])`, and
  `make_hash_array(bytes32,bytes32)` now prove `Hash`/`bytes32` fields and
  fixed arrays flatten through calldata and return-data encoding, with golden
  Yul, metadata selector checks, `solc`, Foundry ABI decoding, and short
  `bytes32[2]` calldata rejection.
- Done: add golden Yul outputs for SDK EVM examples (`Counter`,
  `ArrayExample`, `SimpleToken`, `ERC20`, `Ownable`, `Pausable`, and
  `VerifiedVault`) and make `scripts/evm/build-examples.sh` diff generated Yul
  against those fixtures before validating metadata.
- Done: add metadata emission and validation around the current
  `solc --strict-assembly` flow for SDK and portable IR EVM bytecode builds.
- Keep Foundry smoke as the mature EVM smoke test.

Acceptance criteria:

- `lake build` passes.
- `scripts/evm/diagnostic-smoke.sh` passes.
- `scripts/evm/check-ir-coverage-manifest.py` passes.
- `scripts/evm/build-examples.sh` succeeds on a machine with `solc`.
- `scripts/evm/foundry-smoke.sh` succeeds on a machine with Foundry.
- The generated metadata points to the bytecode artifact and records `target:
  evm`.

## Workstream 4: Wasm Host Runtime Split

Goal: make Wasm host adapters target-driven instead of assuming every Wasm
contract is NEAR.

Tasks:

- Move chain extern declarations out of generic EmitZig runtime externs.
- Add a target-selected host bridge list.
- Keep NEAR bridge as the reference implementation.
- Add a CosmWasm bridge skeleton with allocator and region ABI.

Acceptance criteria:

- A Wasm build can select NEAR or CosmWasm bridge explicitly.
- Generic Wasm runtime does not force-link NEAR host functions.
- `wasm-near` and `wasm-cosmwasm` can have different required exports.

## Workstream 5: CosmWasm Spike

Goal: prove that ProofForge can target another Wasm host besides NEAR.

Tasks:

- Add `Lean.CosmWasm` SDK skeleton (see [wasm-family.md](targets/wasm-family.md)).
- Add `zigc-cosmwasm` wrapper.
- Add `cosmwasm_contract_root.zig`.
- Export `interface_version_8`, `allocate`, `deallocate`, `instantiate`,
  `execute`, and `query`.
- Add Counter example using JSON-backed messages.
- Add `cosmwasm-check` smoke.

Acceptance criteria:

- Counter Wasm passes `cosmwasm-check`.
- `instantiate`, `execute`, and `query` are present in exports.
- The smoke test can increment and query counter state.

## Workstream 6: Solana sBPF Assembly Toolchain Integration (Phase 0)

Goal: validate the direct-assembly route end to end — a canned `.s` file
round-trips through the blueshift-gg/sbpf toolchain into a loadable ELF.
Supersedes the old sbpf-linker spike (D-026).

Tasks:

- Install `sbpf` via `cargo install --git https://github.com/blueshift-gg/sbpf.git`.
- Add `--emit-sbpf-asm` CLI mode to `proof-forge` that writes a canned
  `entrypoint.s` (returns success, no account parsing).
- Run `sbpf build` on the canned `.s`; verify a valid eBPF ELF is produced.
- Verify `sbpf disassemble` round-trips the ELF.
- Record toolchain version in artifact metadata.

Acceptance criteria:

- [x] `sbpf build` produces a `.so` recognized as `ELF 64-bit LSB ... eBPF`.
- [x] `sbpf disassemble` produces assembly matching the input.
- [x] `--emit-sbpf-asm` writes valid `.s` without assembly errors.
- [x] `proof-forge-artifact.json` records `target: "solana-sbpf-asm"`.
- [x] `sbpf` installed to PATH via `cargo install`.

Reference: [solana-sbpf-asm design doc](targets/solana-sbpf-asm.md),
[RFC 0005](rfcs/0005-solana-sbpf-assembly-backend.md).

## Workstream 7: Solana sBPF Assembly Counter Codegen (Phase 1)

Goal: lower the portable IR Counter module to sBPF assembly and pass `sbpf test`.
This is the first real codegen backend for the assembly route.

Tasks:

- Implement `ProofForge.Backend.Solana.StateLayout` — compute per-account field
  offsets from the instruction manifest; emit `.equ` constants.
- Implement `ProofForge.Backend.Solana.SbpfAsm` — lower `IR.Module` to `.s`:
  - Entrypoint adapter: parse serialized accounts, dispatch on instruction
    discriminant.
  - Account validation: signer, writable, owner checks per manifest.
  - Expression lowering: literals, locals, add/sub, comparisons, casts.
  - Statement lowering: letBind, assign, assignOp, ifElse, return, assert.
  - Effect lowering: storageScalar read/write at account-data offsets.
- Add `--solana-elf` CLI mode: emit `.s` then invoke `sbpf build`.
- Generate instruction manifest (`manifest.toml`) alongside the `.s`.
- Create `Examples/Solana/Counter.lean` + manifest.
- Run `sbpf test` (Mollusk) and a Surfpool/Web3.js live deployment smoke.

Acceptance criteria:

- Counter scenario (initialize, increment, get) passes `sbpf test`.
- Surfpool/Web3.js live smoke passes (optional, gated on tool availability).
- Capability checker rejects IR modules using unsupported capabilities with a
  clear diagnostic citing target id and capability id.
- Same portable IR Counter module lowers to both EVM and Solana.
- Artifact metadata records `target: "solana-sbpf-asm"`, `irVersion`,
  entrypoints, and capabilities used.

Out of scope (Phase 2+): maps, struct types, events, bounded loops, Borsh
serialization, full SPL Token data layouts, complete live CPI matrix coverage,
and Rust/Pinocchio equivalence. CPI and PDA stay Solana-specific (D-027): the
SDK routes them through target capability calls and sBPF helper actions instead
of adding them to the portable IR.

Reference: [solana-sbpf-asm design doc](targets/solana-sbpf-asm.md) § Phased
Implementation Plan.

### Phase 1 progress (incremental sub-items)

The Workstream 7 Phase 1 backend (`ProofForge.Backend.Solana.SbpfAsm`) lands
incrementally. Each sub-item carries its own runnable validation gate so
partial progress is visible before the full acceptance criteria close:

- [x] IR → sBPF AST → text pipeline; entrypoint adapter dispatches on the
      first instruction-data byte (V-GATE-SOLANA-01/02; Phase 0 baseline).
- [x] Counter codegen (literals, locals, `add`, scalar storage
      read/write/`assignOp`, `letBind`/`letMutBind`, `assign`, `return`);
      Mollusk smoke covers initialize / increment 0→1 / increment 5→6 /
      get→return_data (V-GATE-SOLANA-03).
- [x] Control-flow + assertion coverage: comparison expressions
      (`.eq`/`.ne`/`.lt`/`.le`/`.gt`/`.ge`), boolean expressions
      (`.boolAnd`/`.boolOr`/`.boolNot`), statement-level `.ifElse` then/else
      lowering with fresh named labels, `.assert` and `.assertEq` lowering to
      the shared `assert_fail` (exit 2) / `assert_eq_fail` (exit 3) labels.
      Fixture: `ProofForge.IR.Examples.ControlFlowAssertProbe` (three
      entrypoints: `lifecycle`, `guarded_increment`, `equality_guard`);
      CLI mode `--emit-control-ir-sbpf`; deterministic emission gate
      `scripts/solana/emit-control-smoke.sh` (no `sbpf` required); Mollusk
      runtime gate `scripts/solana/control-smoke.sh` (six checks: lifecycle
      x2, guarded_increment success + assert revert, equality_guard success
      + assertEq revert) (V-GATE-SOLANA-08).
- [x] Instruction manifest (`manifest.toml`) generation alongside the `.s`.
      `ProofForge.Backend.Solana.SbpfAsm.renderManifest` emits a TOML with
      target, program placeholder id, and per-entrypoint instruction tables
      using the Phase 1 default account convention (writable, signer=false,
      owner=program). `--emit-counter-ir-sbpf` and `--emit-control-ir-sbpf`
      write `manifest.toml` next to the `.s` and include it as an artifact.
- [x] `--solana-elf` CLI mode: emits `.s`, writes `manifest.toml`, scaffolds an
      `sbpf` project, invokes `sbpf build`, copies the resulting `.so` to the
      requested output, and records `sbpfBuild: passed` in artifact metadata.
- [x] Account validation: signer / writable / owner checks per manifest. Each
      entrypoint emits a prologue that checks `is_writable` at account-header
      offset 10 and verifies the account owner equals the serialized program
      id. Failure exits are 4 (`error_not_writable`), 5 (`error_signer`), and
      6 (`error_owner`). Phase 1 Mollusk runtime gates disable the
      direct-account-mapping ABI so the legacy embedded account-data layout
      is exercised.
- [x] `Examples/Solana/Counter.lean` + manifest as a self-contained example.
      Includes a tracked `Counter.golden.s` and `Counter.manifest.toml` and a
      CI-runnable `scripts/solana/build-examples.sh` that emits and diffs.
- [x] Capability checker rejects unsupported capability/target combinations
      with a clear diagnostic citing target id and capability id. Basis for
      V-GATE-SOLANA-05; exercised by `Tests/SolanaDiagnostics.lean` and
      `scripts/solana/diagnostic-smoke.sh`.
- [x] Solana SDK target extensions route `ProofForge.Solana` PDA/CPI APIs
      through capability plan metadata, emit `manifest.toml` extension
      definitions plus entrypoint action sections, and inject handler-level
      helper calls (`sol_pda_derive_<name>`, `sol_cpi_<name>`) before the IR
      body while preserving the Solana input pointer in `r1`. Covered by
      `Tests/SolanaSdk.lean`, `Tests/SolanaSdkManifest.lean`, and
      `scripts/solana/sdk-smoke.sh` with `sbpf build` when available.
- [x] Surfpool/Web3.js live deployment smoke (V-GATE-SOLANA-04). The optional
      `scripts/solana/surfpool-web3-smoke.sh` gate builds the Counter ELF,
      starts Surfpool, deploys with the Solana CLI, creates a program-owned
      counter account via `@solana/web3.js`, invokes initialize/increment/get,
      checks account data 0→1→2, and validates `get` return data. The script
      passes `--solana-sbpf-arch v0` to produce a Solana CLI deploy-compatible
      ELF directly and uses `--use-rpc` for Surfpool.
- [x] `--solana-elf` exposes `--solana-sbpf-arch v0|v3` and records the chosen
      architecture in `proof-forge-artifact.json`. Default stays `v3`; Surfpool
      live deployment uses `v0` until the deployed CLI/runtime stack accepts
      the newer sbpf feature set without `--skip-feature-verify`.
- [x] PDA helper runtime packing now emits static ASCII seed byte buffers, Solana
      `Slice { ptr, len }` seed tables, dynamic program-id pointer calculation,
      and a 32-byte PDA result buffer before calling `sol_create_program_address`.
      Covered by `Tests/SolanaSdkManifest.lean` and
      `scripts/solana/sdk-smoke.sh`.
- [x] PDA typed seed lowering now keeps the compatibility `seeds` field while
      adding target-facing typed descriptors for literal/UTF-8 bytes, account
      pubkeys, bump seeds, and scalar instruction-data seeds. The Solana target
      extension consumes those descriptors, appends `bump?` to the effective
      syscall seed list, emits `typed_seeds`/`typedSeeds` in manifest/artifact
      metadata, and validates the derived PDA pubkey against the declared
      account when `account?` is present. Covered by `Tests/SolanaSdk.lean`,
      `Tests/SolanaSdkManifest.lean`, `Tests/SolanaPdaSeeds.lean`,
      `scripts/solana/sdk-smoke.sh`, and
      `scripts/solana/pda-web3-smoke.sh`.
- [x] Standard Solana protocol SDK helpers now cover System Program
      transfer/create-account and SPL Token transfer_checked/mint_to/burn/
      approve/revoke/close_account/set_authority. They route through target capability
      metadata with
      `solana.cpi.protocol`, canonical `data_layout`, account metas, signer
      seeds, and instruction-data source names, and are included in the
      generated manifest plus artifact JSON. Covered by `Tests/SolanaSdk.lean`,
      `Tests/SolanaSdkManifest.lean`, `Tests/SolanaCpiPacking.lean`, and
      `scripts/solana/sdk-smoke.sh`.
- [x] Runtime allocator target extension now models Solana's default
      downward-bump allocator (`heap_start = "0x300000000"`,
      `heap_bytes = 32768`) plus a `noAllocator`/deny-dynamic option aligned
      with Pinocchio-style no-heap entrypoints. The selected allocator routes
      through `runtime.allocator` capability metadata and appears in
      `manifest.toml`, `proof-forge-artifact.json`, and assembly metadata.
      Covered by `Tests/SolanaAllocator.lean`, `Tests/SolanaSdk.lean`,
      `Tests/SolanaSdkManifest.lean`, and `scripts/solana/sdk-smoke.sh`.
- [x] Runtime memory target extension now routes Solana-only SDK actions through
      `runtime.memory` capability metadata and lowers entrypoint actions to
      `sol_memcpy_`, `sol_memcmp_`, and `sol_memset_` helpers over generated
      state-account offsets. The generated manifest and artifact JSON record
      `[[solana.entrypoint_memory]]` / `memoryActions`; Web3.js verifies copied
      bytes, compare result, and fill pattern on a program-owned account.
      Covered by `Tests/SolanaMemory.lean` and
      `scripts/solana/memory-web3-smoke.sh`.
- [x] Return-data and compute-budget target extensions now route Solana-only
      SDK actions through `runtime.return_data` and `runtime.compute_units`
      capability metadata. Return-data actions lower state-backed byte slices
      to `sol_set_return_data` and can read the most recent CPI return-data
      buffer/program id through `sol_get_return_data`; compute-budget actions
      lower the feature-gated `sol_remaining_compute_units` syscall and write
      the observed remaining CU value into state, and profiling actions lower
      `sol_log_compute_units_`. The generated manifest records
      `[[solana.entrypoint_return_data]]` and
      `[[solana.entrypoint_compute_units]]`. Covered by
      `Tests/SolanaReturnDataCompute.lean`.
- [x] Generated Solana SDK instruction schemas now use a module-wide
      multi-account account list instead of the old single-account manifest.
      The schema includes the state account, PDA accounts, CPI accounts, and
      executable CPI program accounts, and the sBPF backend computes
      `INSTRUCTION_DATA` offsets from that same schema. The generated prologue
      validates signer/writable constraints and program-owned accounts from the
      schema. The account list is emitted in both `manifest.toml` and
      `proof-forge-artifact.json`. Covered by `Tests/SolanaSdkManifest.lean`,
      `Tests/SolanaCpiPacking.lean`, and `scripts/solana/sdk-smoke.sh`.
- [x] System Program transfer/create-account and SPL Token CPI instruction-data
      packing emit the standard instruction bytes into the C `SolInstruction`
      payload. System transfer/create-account use bincode-style `u32`
      discriminators plus `u64` lamports/space and owner pubkey fields; SPL
      Token `transfer_checked`, `mint_to`, `burn`, `approve`, and `revoke` use
      the standard token instruction tags and amount/decimals layouts,
      `close_account` packs instruction tag `9`, and `set_authority` packs
      instruction tag `6`, authority type `MintTokens`, and a new-authority
      pubkey sourced from a readonly input account. Value
      sources can bind to generated scalar state offsets, numeric literals, or
      decoded scalar entrypoint parameters. The CPI helper also packs program id
      bytes, C `SolAccountMeta[]`,
      `SolAccountInfo[]` entries bound to the generated multi-account input
      layout, signer seed tables, and syscall register setup. Covered by
      `Tests/SolanaCpiPacking.lean`, `Tests/SolanaSdkManifest.lean`, and
      `scripts/solana/sdk-smoke.sh`.
- [x] System Program transfer CPI now has a live Surfpool/Web3.js behavior
      gate. `ProofForge.Solana.Examples.SystemCpi` builds a generated
      `--solana-system-cpi-elf` fixture whose entrypoint reads a scalar
      `lamports` instruction parameter, performs a System Program transfer CPI,
      and records the transferred amount in a program-owned state account.
      `scripts/solana/system-cpi-web3-smoke.sh` validates the artifact schema,
      deploys the ELF on Surfpool with Solana CLI, invokes it through
      `@solana/web3.js`, and checks both recipient lamport delta and state data.
      The sBPF lowering computes the instruction-data pointer from the
      serialized account layout under direct account mapping and keeps it in
      `r9` so internal helper calls do not lose it across callee stack frames.
      Coverage: `just solana-system-cpi-web3` / V-GATE-SOLANA-10.
- [x] System Program `create_account` CPI now has a live Surfpool/Web3.js
      behavior gate. `ProofForge.Solana.Examples.SystemCreateAccountCpi`
      builds a generated `--solana-system-create-account-cpi-elf` fixture whose
      entrypoint reads scalar `lamports` and `space` instruction parameters,
      performs a System Program `create_account` CPI with payer and new-account
      signers, creates a program-owned account, and records both values in the
      existing program-owned state account. The Web3.js harness checks the new
      account owner, data length, lamports, and recorded state values. Coverage:
      `just solana-system-create-account-cpi-web3` / V-GATE-SOLANA-11.
- [x] SPL Token `transfer_checked` CPI now has a live Surfpool/Web3.js behavior
      gate. `ProofForge.Solana.Examples.SplTokenTransferCheckedCpi` builds a
      generated `--solana-spl-token-transfer-cpi-elf` fixture whose entrypoint
      reads a scalar `amount` instruction parameter, performs an SPL Token
      `transfer_checked` CPI with the source authority signer, and records the
      amount in program-owned state. The Web3.js harness creates a mint plus
      source/destination token accounts through `@solana/spl-token`, checks the
      token balance deltas, and checks the state record. The sBPF lowering now
      builds a runtime account pointer table in each entry/helper stack frame so
      variable-size SPL Token account data does not invalidate account offsets
      across internal helper calls. Coverage:
      `just solana-spl-token-transfer-cpi-web3` / V-GATE-SOLANA-12.
- [x] Entry instruction-data decoding now treats byte 0 as the entrypoint tag
      and decodes packed scalar parameters from `instruction_data+1` into
      stack locals. The initial scalar ABI supports `U64`, `U32`, and `Bool`,
      emits per-entrypoint parameter schemas and minimum instruction-data
      lengths in `manifest.toml`/`proof-forge-artifact.json`, rejects short
      payloads with `error_instruction_data`, and exposes the same fixed input
      offsets to CPI value bindings, so SDK calls such as SPL Token
      `transfer_checked` can source `amount` from a user instruction parameter
      instead of a placeholder. Covered by `Tests/SolanaCpiPacking.lean`,
      `Tests/SolanaSdkManifest.lean`, and `scripts/solana/sdk-smoke.sh`.

### Solana SDK completion roadmap

Reference docs driving this roadmap:

- Solana CPI and PDA docs:
  <https://solana.com/docs/core/cpi> and
  <https://solana.com/docs/core/pda>.
- Anchor CPI/account-constraint docs:
  <https://www.anchor-lang.com/docs/basics/cpi> and
  <https://www.anchor-lang.com/docs/references/account-constraints>.
- Pinocchio no-dependency / no-std program model:
  <https://docs.rs/pinocchio> and
  <https://github.com/anza-xyz/pinocchio>.

Baseline: as of 2026-07-02, the Solana path has direct sBPF assembly emission,
Counter deployment through Surfpool/Web3.js, SDK capability metadata, generated
manifest/artifact output, module-wide multi-account schemas, standard
System/SPL Token CPI data packing, bump-allocator metadata, scalar entrypoint
parameter decoding, typed PDA seed lowering, live System Program transfer plus
create-account CPI validation, live SPL Token `transfer_checked` CPI
validation, live SPL Token `mint_to`/`burn`/`approve`/`revoke` CPI validation,
and live SPL Token `set_authority` CPI validation, plus live scalar
`events.emit` log validation through
`sol_log_64_`, live account-pubkey log validation through `sol_log_pubkey`,
live state-backed data-log validation through `sol_log_data`, and live
`Clock.slot` sysvar validation for `contextRead checkpointId`, plus live
`runtime.memory` validation through `sol_memcpy_`, `sol_memmove_`,
`sol_memcmp_`, and `sol_memset_`, plus live Solana-only `crypto.hash`
validation through `sol_sha256`, `sol_keccak256`, and feature-gated
`sol_blake3`, plus live `Rent.lamports_per_byte_year` sysvar validation
through `sol_get_rent_sysvar`.
It also covers live validation for all current RPC-exposed `EpochSchedule`
fields through `sol_get_epoch_schedule_sysvar`: `slots_per_epoch`,
`leader_schedule_slot_offset`, `warmup`, `first_normal_epoch`, and
`first_normal_slot`, plus live `EpochRewards` validation through
`sol_get_epoch_rewards_sysvar` for
`distribution_starting_block_height`, `num_partitions`,
`parent_blockhash_word0..3`, `total_points_low/high`, `total_rewards`,
`distributed_rewards`, and `active`, plus feature-gated live
`LastRestartSlot.last_restart_slot` validation through `sol_get_sysvar` with
the `SysvarLastRestartS1ot1111111111111111111111` sysvar id. Live SDK
coverage now includes `runtime.return_data` lowering to `sol_set_return_data`
and `sol_get_return_data`, with empty-read, set-return simulation, and
same-instruction set/get roundtrip checks, plus `runtime.compute_units`
lowering to feature-gated `sol_remaining_compute_units` state writes and
profiling logs through `sol_log_compute_units_`.
The estimates below assume one engineer working on this branch,
the current direct-assembly architecture staying stable, and local
`sbpf`/Surfpool/Solana CLI tooling remaining available.

| Level | Estimated effort | Done when |
|---|---:|---|
| SDK alpha: usable Solana programs | 3-5 focused engineering days | Simple programs can use state, PDA seeds, scalar instruction parameters, System Program CPI, SPL Token CPI, logs/return data, and Web3.js behavior tests without hand-written assembly patches. |
| SDK beta: reference-comparable Solana backend | 2-3 focused weeks | ProofForge output is compared against Rust/Pinocchio fixtures for the same account schema, covers key syscalls, validates live CPI behavior, and supports per-entrypoint account schemas. |
| Anchor/Pinocchio-class developer surface | 4-6 focused weeks after beta | The SDK offers account constraints, typed account/data helpers, IDL/client generation, richer SPL/Token-2022 coverage, and stable diagnostics comparable to a framework-level workflow. |

Completed alpha slices:

- Instruction ABI hardening: parameter payload length bounds checks,
  per-entrypoint parameter schemas in `manifest.toml` and
  `proof-forge-artifact.json`, and stable scalar parameter metadata are now in
  place.
- PDA typed seed lowering: `literalSeed`/`utf8Seed`, `accountSeed`,
  `bumpSeed`, and `paramSeed` descriptors now lower to Solana seed slices,
  `bump?` participates in the effective seed list, and declared PDA accounts
  can be checked against the derived pubkey.
- PDA/Web3.js derivation fixture: `scripts/solana/pda-web3-smoke.sh` reads the
  generated SDK Vault `typedSeeds` artifact data and verifies literal/account/
  bump descriptor semantics against `PublicKey.findProgramAddressSync` and
  `PublicKey.createProgramAddressSync`; the harness also covers UTF-8 and
  instruction-parameter resolver behavior.
- Live System Program transfer CPI fixture:
  `scripts/solana/system-cpi-web3-smoke.sh` builds and deploys a generated
  transfer CPI program on Surfpool, invokes it through Web3.js, and proves both
  the lamport movement and state write.
- Live System Program create-account CPI fixture:
  `scripts/solana/system-create-account-cpi-web3-smoke.sh` builds and deploys a
  generated create-account CPI program on Surfpool, invokes it through Web3.js,
  and proves the new account owner/space/lamports plus state writes.
- Live SPL Token transfer-checked CPI fixture:
  `scripts/solana/spl-token-transfer-cpi-web3-smoke.sh` builds and deploys a
  generated transfer_checked CPI program on Surfpool, creates SPL Token test
  accounts with `@solana/spl-token`, invokes it through Web3.js, and proves the
  source/destination token balance deltas plus state writes.
- Live SPL Token ops CPI fixture:
  `scripts/solana/spl-token-ops-cpi-web3-smoke.sh` builds and deploys a
  generated `mint_to`/`burn`/`approve`/`revoke` CPI program on Surfpool,
  validates the generated four-entrypoint artifact schema, creates SPL Token
  test accounts with `@solana/spl-token`, invokes all four generated
  entrypoints through Web3.js, and proves supply/balance/delegate changes plus
  state writes.
- Live SPL Token authority CPI fixture:
  `scripts/solana/spl-token-authority-cpi-web3-smoke.sh` builds and deploys a
  generated `set_authority` CPI program on Surfpool, validates the generated
  single-entrypoint artifact schema, creates an SPL Token mint through
  `@solana/spl-token`, invokes the generated entrypoint through Web3.js, and
  proves mint authority moved to the requested new authority plus the marker
  state write.
- Live scalar event, pubkey log, and data log fixture: `scripts/solana/log-event-web3-smoke.sh`
  builds and deploys a generated `events.emit` program on Surfpool, invokes it
  through Web3.js, verifies the generated `sol_log_64_` transaction log
  contains the stable `AmountEvent` tag and scalar `amount` field, and proves
  the program-owned state account recorded the same value. The same fixture now
  validates Solana-only `logAccountPubkey` metadata, invokes the generated
  `log_state_pubkey` entrypoint, and proves `sol_log_pubkey` logs the state
  account's base58 pubkey. It also validates Solana-only `logStateData`
  metadata, invokes `log_state_data`, and proves `sol_log_data` emits a base64
  `Program data:` payload for the state-backed `amount` bytes.
- Live Clock sysvar fixture: `scripts/solana/clock-sysvar-web3-smoke.sh`
  builds and deploys a generated `contextRead checkpointId` program on
  Surfpool, lowers it to `sol_get_clock_sysvar`, invokes it through Web3.js,
  and proves the recorded `Clock.slot` matches the observed transaction slot.
- Live memory syscall fixture: `scripts/solana/memory-web3-smoke.sh` builds and
  deploys a generated `runtime.memory` program on Surfpool, invokes it through
  Web3.js, and proves `sol_memcpy_`, `sol_memmove_`, `sol_memcmp_`, and
  `sol_memset_` effects by reading copied value, moved value, compare result,
  and fill bytes from program-owned state.
- Return-data/compute-units SDK fixture:
  `Tests/SolanaReturnDataCompute.lean` proves `runtime.return_data` and
  `runtime.compute_units` route through Solana-only capability metadata, rejects
  on EVM, and render manifest sections plus sBPF helper calls for
  `sol_set_return_data`, `sol_get_return_data`, feature-gated
  `sol_remaining_compute_units`, and `sol_log_compute_units_`.
  `scripts/solana/return-data-compute-web3-smoke.sh` builds and deploys the
  generated `--solana-return-data-compute-elf` fixture on Surfpool, validates
  artifact action metadata, verifies no-data `sol_get_return_data` reads,
  confirms `sol_set_return_data` through Web3.js simulation returnData, checks a
  same-instruction set/get roundtrip including program id words, records a
  nonzero remaining-compute-units value, and confirms compute-unit logging.
- Live SHA-256/Keccak-256/Blake3 syscall fixture:
  `scripts/solana/crypto-hash-web3-smoke.sh` builds and deploys a generated
  Solana-only `crypto.hash` program on Surfpool, invokes `set_preimage`,
  `hash_preimage`, `keccak_preimage`, and `blake3_preimage` through Web3.js, and
  proves the account-stored 32-byte digests match Node SHA-256 and
  `@noble/hashes` Keccak-256/Blake3 references for the same little-endian
  preimage. The Blake3 action is recorded as feature-gated in manifest and
  artifact metadata.
- Live Rent sysvar fixture: `scripts/solana/rent-sysvar-web3-smoke.sh` builds
  and deploys a generated Solana-only `sysvar` target-extension program on
  Surfpool, invokes `record_rent` through Web3.js, and proves the recorded
  `Rent.lamports_per_byte_year` matches the Rent sysvar account data.
- Live EpochSchedule sysvar fixture:
  `scripts/solana/epoch-schedule-sysvar-web3-smoke.sh` builds and deploys a
  generated Solana-only `sysvar` target-extension program on Surfpool, invokes
  `record_epoch_schedule` through Web3.js, and proves the recorded
  `EpochSchedule.slots_per_epoch`,
  `EpochSchedule.leader_schedule_slot_offset`, `EpochSchedule.warmup`,
  `EpochSchedule.first_normal_epoch`, and `EpochSchedule.first_normal_slot`
  match RPC `getEpochSchedule()` fields.
- Live EpochRewards sysvar fixture:
  `scripts/solana/epoch-rewards-sysvar-web3-smoke.sh` builds and deploys a
  generated Solana-only `sysvar` target-extension program on Surfpool, invokes
  `record_epoch_rewards` through Web3.js, and proves that
  `sol_get_epoch_rewards_sysvar` records `EpochRewards` fields into state.
  `parent_blockhash` is exposed as four little-endian `u64` word views and
  `total_points` is exposed as low/high `u64` word views until the portable
  scalar layer has first-class wide-value output states.
- Live LastRestartSlot sysvar fixture:
  `scripts/solana/last-restart-slot-sysvar-web3-smoke.sh` builds and deploys a
  generated Solana-only `sysvar` target-extension program on Surfpool, invokes
  `record_last_restart_slot` through Web3.js, and proves the feature-gated
  `LastRestartSlot.last_restart_slot` read lowers through `sol_get_sysvar` and
  matches the LastRestartSlot sysvar account data. The action is marked
  `feature_gated` in manifest and artifact metadata.

Completed beta scaffolding slices:

- Pinocchio System transfer reference contract:
  `references/solana/pinocchio/system-transfer` contains a checked-in
  no-allocator Pinocchio reference for the same System transfer account schema
  as `ProofForge.Solana.Examples.SystemCpi`. The gate
  `scripts/solana/pinocchio-system-transfer-equivalence.sh` emits the
  ProofForge System CPI artifact and compares its instruction tag, parameter
  ABI, account order, signer/writable constraints, CPI protocol/data layout,
  and state-write contract against the reference manifest/source.
- Pinocchio System transfer live-equivalence harness:
  `scripts/solana/pinocchio-system-transfer-live-equivalence.sh` is wired to
  build the ProofForge ELF and the checked-in Pinocchio reference ELF, deploy
  both programs to one Surfpool instance, invoke the same Web3.js transfer
  scenario for each, and compare recipient lamport deltas plus state writes.
  The harness currently skips when `cargo-build-sbf` cannot find Solana rustc/
  platform-tools.
- Solana loader-compatible ELF packaging blocker:
  a 2026-07-03 local run of `just solana-pinocchio-live-equivalence` with
  Surfpool, Agave `solana-cli 3.1.12`, `cargo-build-sbf 3.1.12`, and `sbpf
  0.2.2` installed failed all five live dual-deploy children at ProofForge
  program deployment. `solana program deploy --use-rpc` rejects the generated
  ProofForge ELF with `Failed to parse ELF file: invalid file header` before
  the Pinocchio reference deployment or Web3.js behavior checks run. Triage
  showed the current blueshift `sbpf build --arch v0` output is a one-segment
  bare ELF with no section table and `e_flags = 3`; Agave's embedded
  `solana-sbpf 0.13.1` strict loader expects a Solana-compatible v3 layout
  with `EM_SBPF`, four program headers, a valid section-header index, and
  function-start markers. Reflagging the bytes as legacy v0 is not valid
  either, because the bytecode then fails relocation with
  `RelativeJumpOutOfBounds`. The next implementation slice is therefore an
  explicit Solana CLI loader-compatibility path: either emit/package through
  the standard Solana platform-tools format, or extend the direct assembler
  pipeline to produce the strict v3 headers and function markers that Agave
  accepts.
- Pinocchio System create-account reference contract:
  `references/solana/pinocchio/system-create-account` contains a checked-in
  no-allocator Pinocchio reference for the same System Program
  `create_account` account schema as
  `ProofForge.Solana.Examples.SystemCreateAccountCpi`. The gate
  `scripts/solana/pinocchio-system-create-account-equivalence.sh` emits the
  ProofForge create-account CPI artifact and compares its instruction tag,
  two-parameter ABI, account order, signer/writable constraints, CPI
  protocol/data layout, lamports/space/owner contract, and two-field
  state-write contract against the reference manifest/source. With
  `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1`, the same gate typechecks the
  reference against `pinocchio-system`.
- Pinocchio System create-account live-equivalence harness:
  `scripts/solana/pinocchio-system-create-account-live-equivalence.sh` is
  wired to build the ProofForge ELF and the checked-in Pinocchio reference ELF,
  deploy both programs to one Surfpool instance, invoke the same Web3.js
  create-account scenario for each, and compare lamports/space inputs plus
  both state writes. The harness currently skips when `cargo-build-sbf` cannot
  find Solana rustc/platform-tools.
- Pinocchio SPL Token transfer reference contract:
  `references/solana/pinocchio/spl-token-transfer` contains a checked-in
  no-allocator Pinocchio reference for the same SPL Token `transfer_checked`
  account schema as `ProofForge.Solana.Examples.SplTokenTransferCheckedCpi`.
  The gate `scripts/solana/pinocchio-spl-token-transfer-equivalence.sh` emits
  the ProofForge SPL Token CPI artifact and compares its instruction tag,
  parameter ABI, account order, signer/writable constraints, CPI
  protocol/data layout, decimals/amount contract, and state-write contract
  against the reference manifest/source. With
  `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1`, the same gate typechecks the reference
  against `pinocchio-token`.
- Pinocchio SPL Token transfer live-equivalence harness:
  `scripts/solana/pinocchio-spl-token-transfer-live-equivalence.sh` is wired to
  build the ProofForge ELF and the checked-in Pinocchio Token reference ELF,
  deploy both programs to one Surfpool instance, invoke the same Web3.js +
  `@solana/spl-token` transfer_checked scenario for each, and compare
  source/destination token balance deltas plus the amount state write. The
  harness currently skips when `cargo-build-sbf` cannot find Solana rustc/
  platform-tools.
- Pinocchio SPL Token ops reference contract:
  `references/solana/pinocchio/spl-token-ops` contains a checked-in
  no-allocator Pinocchio reference for the same SPL Token
  `mint_to`/`burn`/`approve`/`revoke` account schema as
  `ProofForge.Solana.Examples.SplTokenOpsCpi`. The gate
  `scripts/solana/pinocchio-spl-token-ops-equivalence.sh` emits the ProofForge
  SPL Token ops CPI artifact and compares its four instruction tags, parameter
  ABI, account order, signer/writable constraints, CPI protocol/data layout,
  SPL Token instruction contract, and state-write contract against the
  reference manifest/source. With `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1`, the
  same gate typechecks the reference against `pinocchio-token`.
- Pinocchio SPL Token ops live-equivalence harness:
  `scripts/solana/pinocchio-spl-token-ops-live-equivalence.sh` is wired to
  build the ProofForge ELF and the checked-in Pinocchio Token ops reference
  ELF, deploy both programs to one Surfpool instance, invoke the same Web3.js +
  `@solana/spl-token` mint/burn/approve/revoke scenario for each, and compare
  token effects plus all four amount/marker state writes. The harness currently
  skips when `cargo-build-sbf` cannot find Solana rustc/platform-tools.
- Pinocchio SPL Token authority reference contract:
  `references/solana/pinocchio/spl-token-authority` contains a checked-in
  no-allocator Pinocchio reference for the same SPL Token `set_authority`
  account schema as `ProofForge.Solana.Examples.SplTokenAuthorityCpi`. The
  gate `scripts/solana/pinocchio-spl-token-authority-equivalence.sh` emits the
  ProofForge SPL Token authority CPI artifact and compares its instruction ABI,
  account order, signer/writable constraints, CPI protocol/data layout,
  `SetAuthority` instruction contract, and marker state-write contract against
  the reference manifest/source. With `PROOF_FORGE_PINOCCHIO_CARGO_CHECK=1`,
  the same gate typechecks the reference against `pinocchio-token`.
- Pinocchio SPL Token authority live-equivalence harness:
  `scripts/solana/pinocchio-spl-token-authority-live-equivalence.sh` is wired
  to build the ProofForge ELF and the checked-in Pinocchio Token authority
  reference ELF, deploy both programs to one Surfpool instance, invoke the same
  Web3.js + `@solana/spl-token` mint-authority transfer scenario for each, and
  compare mint authority plus marker state writes. The harness currently skips
  when `cargo-build-sbf` cannot find Solana rustc/platform-tools.

Completed developer-surface slices:

- Portable ValueVault surface source:
  `ProofForge.Contract.Surface` now lets examples declare state slots,
  parameters, methods, and event fields once, then write entrypoint bodies
  through typed refs (`read`, `write`, `bind`, `emit`, `ret`) instead of raw
  `ContractSpec` string plumbing. `ProofForge.Contract.Examples.ValueVault`
  uses this layer and intentionally leaves `selector? = none` in the source.
- Declaration-derived IR names:
  `state_decl`, `binding_decl`, `method_decl`, `method_return_decl`, and
  `event_decl` macros now derive IR names from Lean declarations, so the
  portable Counter and ValueVault sources no longer repeat raw strings for
  state slots, inputs, locals, method names, or event names. Tests assert the
  derived snake-case state/parameter/method names and PascalCase event names
  before routing the same source across EVM and Solana.
- Source-facing declaration facade:
  `contract_decl Name do ...` derives the module name from a Lean identifier
  and keeps `ContractSpec` as the compiler-owned intermediate product rather
  than the user-visible authoring model. `ProofForge.Contract.Examples.Counter`
  and `ProofForge.Contract.Examples.ValueVault` now use this facade; the older
  `*_ref` macros remain as compatibility shims for older downstream source.
- Contract Source Syntax v1:
  `ProofForge.Contract.Source` adds scoped `contract_source` syntax for
  state declarations, events, entrypoints, queries, source-local bindings,
  state assignment, event emission, returns, typed arithmetic operators, and
  Solana extension declarations for allocator, accounts, PDA derivation, and
  SPL Token CPI calls.
  `ProofForge.Contract.Examples.Counter` and
  `ProofForge.Contract.Examples.ValueVault` now author portable logic through
  this source block while the macro emits the same `ContractSpec`/portable IR
  boundary used by routing, EVM selector hydration, Solana instruction tags,
  IDL, and client artifact generation.
- Legacy `.learn` parser/lowering seed:
  `ProofForge.Contract.Learn` now lexes and parses checked-in `.learn` files
  under `Examples/Learn/` into a small source AST for the portable scalar/event
  subset, lowers that AST to `ContractSpec`/portable IR, and serves as a
  compatibility validation entrypoint rather than a new product source
  language. The primary authoring surface remains Lean `.lean` files and Lean
  SDK helpers. It proves that
  `Counter.learn` and `ValueVault.learn` produce the same IR modules as the
  current `contract_source` examples. The CLI still accepts `.learn` files
  through `--learn --target evm` and `--learn --target solana-sbpf-asm`, with
  `--learn-yul`, `--learn-bytecode`, and `--learn-sbpf` retained as lower-level
  compatibility convenience paths.
  `scripts/portable/value-vault-smoke.sh` uses
  `Examples/Learn/ValueVault.learn` as a legacy equivalence fixture and proves
  that compatibility entrypoint can route to EVM Yul/bytecode metadata and
  Solana sBPF assembly/manifest/IDL/client artifacts without hand-authoring
  `ContractSpec`.
- Learn Solana target-extension syntax:
  `ProofForge.Contract.Learn` now parses `SolanaVault.learn` forms for
  `solana allocator`, `solana account`, `solana pda`, `solana cpi
  ... spl_token_transfer_checked(...)`, and entry-level `solana derive` /
  `solana invoke`. The lowering reuses `ProofForge.Solana` builder helpers, so
  account/PDA/CPI metadata still flows through the existing capability plan,
  manifest, IDL, client, and sBPF assembly paths. `Tests/LearnSource.lean`
  checks that Learn-lowered SolanaVault has the same IR module and generated
  manifest as `ProofForge.Solana.Examples.Vault`.
- Learn System Program CPI syntax:
  `SystemCpi.learn` and `SystemCreateAccountCpi.learn` now cover
  `solana cpi ... system_transfer(...)`, `solana cpi ...
  system_create_account(...) owner ...`, and matching entry-level
  `solana invoke` statements. `Tests/LearnSource.lean` proves both Learn files
  lower to the same IR modules and generated manifests as the existing
  `ProofForge.Solana.Examples.SystemCpi` and
  `ProofForge.Solana.Examples.SystemCreateAccountCpi` source examples.
- Learn SPL Token ops syntax:
  `SplTokenOpsCpi.learn` now covers selector-bearing Learn entrypoints plus
  `spl_token_mint_to`, `spl_token_burn`, `spl_token_approve`, and
  `spl_token_revoke` declarations/invocations. `Tests/LearnSource.lean` proves
  the Learn file lowers to the same IR module and generated manifest as
  `ProofForge.Solana.Examples.SplTokenOpsCpi`, keeping the string-heavy Builder
  code as an internal expected fixture rather than the user-facing syntax.
- Learn SPL Token close-account syntax:
  `SplTokenCloseAccountCpi.learn` now covers `spl_token_close_account`
  declarations/invocations and proves the same module/manifest boundary as
  `ProofForge.Solana.Examples.SplTokenCloseAccountCpi` through
  `Tests/LearnSource.lean`.
- Learn log/return-data/compute-unit syntax:
  `LogEvent.learn` and `ReturnDataCompute.learn` now cover Solana pubkey/data
  log helper statements, return-data set/get statements, and remaining
  compute-unit read/log statements. `Tests/LearnSource.lean` proves both Learn
  files lower to the same IR modules and generated manifests as
  `ProofForge.Solana.Examples.LogEvent` and
  `ProofForge.Solana.Examples.ReturnDataCompute`, moving another syscall-facing
  SDK slice from Builder-only fixtures into user-facing Learn source.
- Learn memory/crypto/sysvar syntax:
  `Memory.learn`, `Crypto.learn`, `Rent.learn`, `EpochSchedule.learn`,
  `EpochRewards.learn`, `LastRestartSlot.learn`, and `Clock.learn` now cover
  Solana memory helpers, SHA-256/Keccak-256/BLAKE3 helpers, and
  sysvar/context reads in user-facing Learn source. `Tests/LearnSource.lean`
  proves these Learn files lower to the same IR modules and generated
  manifests as the corresponding `ProofForge.Solana.Examples.*` fixtures.
- Learn reference diagnostics:
  `ProofForge.Contract.Learn` now builds a declaration reference index while
  lowering and rejects unknown or mismatched Solana CPI invocations, unknown
  PDA derivations, invalid signer seeds, CPI declarations that use undeclared
  accounts, CPI account declarations that do not satisfy required writable or
  signer constraints, and helper statements that reference undeclared
  state/account names. `Tests/LearnDiagnostics.lean` pins these messages so
  Learn behaves like a checked language frontend instead of asking users to
  hand-author unchecked `ContractSpec` data.
- Solana typed account surface:
  `ProofForge.Solana.Surface` now adds `account_ref`, `pda_ref`, and `cpi_ref`
  declarations plus typed PDA seed, account constraint, and SPL/System CPI
  helpers. `ProofForge.Solana.Examples.Vault` now uses dedicated
  `contract_source` items such as `allocator bump`, `account ... writable`,
  `pda ... seeds [...]`, `cpi ... spl_token_transfer_checked(...)`, `derive
  pda ...`, `invoke ... spl_token_transfer_checked(...)`, and the same
  first-class source-syntax path now covers `spl_token_close_account(...)` and
  `spl_token_set_authority(...)` instead of raw account/PDA/CPI strings or
  `use`/`do` helper plumbing. The
  target extension
  emits declared account constraints into `manifest.toml`,
  `proof-forge-artifact.json` (`solanaExtensions.accounts`), and the generated
  account-validation schema.
- System create-account source syntax:
  `ProofForge.Contract.Source` now exposes source-level
  `cpi ... system_create_account(...) owner ...` and
  `invoke ... system_create_account(...) owner ...` forms.
  `ProofForge.Solana.Examples.SystemCreateAccountCpi` uses those forms instead
  of the lower-level builder API while preserving the existing generated
  assembly, manifest, artifact, and Surfpool/Web3.js behavior gate.
- SPL Token authority source syntax:
  `ProofForge.Contract.Source` now exposes source-level
  `cpi ... spl_token_set_authority(...) authority_type(...) signer_seeds [...]`
  and `invoke ... spl_token_set_authority(...) authority_type(...) signer_seeds
  [...]` forms. `ProofForge.Solana.Examples.SplTokenAuthorityCpi` uses those
  forms in a Lean `.lean` fixture, and the generated artifact, Surfpool/Web3.js
  behavior gate, and Pinocchio reference gates all validate the same lowering
  boundary.
- SPL Token close-account source syntax:
  `ProofForge.Contract.Source` now exposes source-level
  `cpi ... spl_token_close_account(...) signer_seeds [...]` and
  `invoke ... spl_token_close_account(...) signer_seeds [...]` forms.
  `ProofForge.Solana.Examples.SplTokenCloseAccountCpi` uses those forms in a
  Lean `.lean` fixture; `Tests/SolanaCpiPacking.lean` validates manifest account
  schemas, `spl-token.close_account` metadata, instruction tag `9`, one-byte
  CPI data length, and the generated CPI helper call. The fixture is available
  through target-first CLI as `emit --target solana-sbpf-asm --fixture
  spl-token-close-account-cpi --format s|elf` and through the matching legacy
  compatibility flags. `scripts/solana/spl-token-close-account-cpi-web3-smoke.sh`
  adds the live Surfpool/Web3.js behavior gate: it deploys the generated
  program, creates an empty SPL Token account, invokes the generated
  `close_account` CPI path, proves the token account is removed, verifies the
  rent lamports moved to the destination account, and checks the marker state
  write. Pinocchio equivalence for this specific SPL helper remains a
  reference-breadth follow-up.
- Target-stage ABI selector hydration:
  the Learn/ValueVault CLI emit paths derive EVM selectors from each
  entrypoint's Solidity ABI signature with `cast sig` immediately before EVM
  Yul/bytecode emission, validate any explicit selector against the derived
  value, and keep Solana routing independent by continuing to use target
  instruction tags. `scripts/portable/value-vault-smoke.sh` proves the same
  `.learn` source emits EVM Yul/bytecode metadata plus Solana sBPF
  assembly/manifest/artifact metadata.
- Solana IDL and TypeScript client package output:
  `ProofForge.Backend.Solana.Idl` renders `proof-forge-idl.json` from the same
  instruction/account/PDA/CPI schema used by `manifest.toml` and artifact
  metadata. `ProofForge.Backend.Solana.Client` renders
  `proof-forge-client.ts` with Web3.js `TransactionInstruction` helpers,
  instruction-data encoding, and account-meta construction. Solana package
  printing, `--emit-solana-sdk-sbpf`, `--emit-value-vault-ir-sbpf`, and the
  Solana ELF contract-sdk path now emit and hash both files.

Current boundary:

- `ProofForge.Contract.Learn` is now a legacy `.learn` compatibility
  parser/lowering seed rather than a new product source language. It covers the
  portable Counter/ValueVault subset and the Vault-level
  Solana account/PDA/SPL Token transfer CPI subset, System Program
  transfer/create-account CPI, SPL Token mint/burn/approve/revoke CPI, and
  Solana log/return-data/compute-unit/memory/crypto/sysvar helper statements.
  During lowering, Solana CPI/PDA declarations and entrypoint helper statements
  are cross-checked against declared references. CPI account operands must be
  declared with `solana account ...`; CPI writable/signer requirements are
  checked against those declarations, so the remaining string names are
  compiler-owned identifiers rather than unchecked user-authored specs.
  `ProofForge.Contract.Source` and Lean SDK helpers remain the primary
  authoring frontend; `.learn` files are retained only as legacy compatibility
  and equivalence fixtures that reuse the same lowering boundary by compile-time
  target id. The next authoring gap is to extend the Lean `.lean` surface to
  Token-2022, typed account/data references, and richer Pinocchio-style account
  validation ergonomics; legacy `--learn` package emission is not the direction
  for new syntax work.

Remaining priority slices:

1. Rust/Pinocchio equivalence fixtures (2-4 days): make the Pinocchio live
   equivalence harnesses pass in CI/local environments by installing Solana
   rustc/platform-tools reliably, then extend static and live reference
   coverage to Token-2022 and remaining SPL helper paths beyond the checked
   transfer/mint/burn/approve/revoke/set-authority set. The key comparison
   points are account order, signer/writable checks, CPI instruction data, and
   observable state changes.
2. Richer structured logs, account data, and typed return helpers (3-5 days):
   extend the current scalar `sol_log_64_`/`sol_log_data` event path to
   string logs, Anchor-style discriminator/Borsh payloads, and indexed event
   forms; add typed return payload helpers beyond `u64`, portable `Expr.hash`
   routing where the hash semantics match the target, and broader account/data
   packing helpers that reuse the new memory/syscall path, with JavaScript
   reference checks.
3. Runtime allocation lowering (1-2 days): route heap-backed SDK structures
   through `runtime.allocator`, emit actual downward bump-pointer allocation
   code when needed, and reject allocation-using structures under
   `noAllocator`.
4. Dynamic per-entrypoint account schemas (3-5 days): replace the current
   module-wide fixed schema with runtime account parsing before dispatch, so
   instruction-data offsets no longer depend on every entrypoint sharing the
   same account list.
5. Token-2022 and richer SPL coverage (3-5 days per iteration): continue
   checked Token-2022 extension routes and remaining SPL variants beyond the
   covered mint-authority `set_authority` path. Associated Token account setup
   now has `create_idempotent` builder/surface/source syntax, sBPF packing,
   target-first fixture routing, and a Surfpool/Web3.js behavior gate, without
   moving those details into portable IR.
6. Developer ergonomics and framework surface (3-5 days per iteration): extend
   the new surface layer toward Lean `.lean`/Lean SDK contract syntax with richer
   typed account/data wrappers, richer generated client APIs, broader
   SPL/Token-2022 helper coverage, and diagnostics that map generated assembly
   failures back to SDK declarations.

The fastest credible route to a more complete SDK is therefore: the alpha
observability baseline is now in place, so next close the richer beta syscall
and return-data slices, then remove remaining architecture shortcuts before adding
Anchor/Pinocchio-class ergonomics.

## Workstream 8: Move Source Generation POC (Aptos first)

Goal: avoid pretending Move is another Lean runtime target.

Tasks:

- Done: define a Move-compatible subset of the portable IR (see [move-family.md](targets/move-family.md)).
- Done: generate one **Aptos** Move counter package via `proof-forge --emit-counter-ir-aptos`.
- Done: generate `Move.toml`, `sources/counter.move`, and `tests/counter_tests.move`.
- Done: add golden fixtures and `scripts/aptos/build-examples.sh` diff gate.
- Done: add `Tests/AptosDiagnostics.lean` so unsupported capabilities fail before codegen.
- In CI: run `aptos move compile/test` (the AptosFramework git dependency fetch is slow and may time out locally; the CI job uses a 10-minute timeout).
- Document verifier restrictions that must feed back into IR design.

Acceptance criteria:

- Generated Aptos Move source shape is locked by golden fixtures and diff gate.
- Generated package has unit tests (`tests/counter_tests.move`).
- Unsupported Lean constructs fail before codegen.
- Follow-up Sui object POC is documented as a separate milestone.

## Workstream 9: CI Expansion

See [validation-gates.md](validation-gates.md) for current and planned validation commands.

Goal: keep CI useful without requiring every external chain tool on day one.

Tasks:

- Keep `lake build` as always-on CI.
- Add EVM smoke only when `solc` and Foundry are available.
- Add optional jobs for CosmWasm, Solana, and Move with clear tool checks.
- Add artifact metadata validation as a tool-independent job.

Acceptance criteria:

- Base CI does not fail because optional chain tools are missing.
- Target-specific CI jobs fail loudly when their toolchain is present but the
  target build fails.
- Metadata schema validation runs without chain tools.

## Workstream 10: Psy DPN ZK Target Spike

Goal: validate a ZK circuit sourcegen target without coupling ProofForge to Psy
compiler internals.

Tasks:

- Done: generate one Counter `.psy` source file from a portable IR fixture.
- Done: add a temporary Dargo package generator in `scripts/psy/counter-smoke.sh`.
- Done: document `dargo test --file` as the first local smoke runner.
- Done: run `dargo compile` with the `psyup` v0.1.0 macOS arm64 toolchain and
  capture DPN circuit JSON.
- Done: run `dargo execute` as a local user/contract session and assert the
  Counter result after two increments.
- Done: call `dargo generate-abi` and capture non-empty ABI JSON.
- Done: emit `proof-forge-artifact.json` with target id `psy-dpn` for Psy smoke
  artifacts.
- Done: add ContextProbe as a non-Counter fixture for parameter lowering and
  context reads.
- Done: add HashProbe for `Hash`, typed hash let-bindings, `hash`, and
  `hash_two_to_one`, aligned with upstream Psy hash tests.
- Done: validate Psy artifact metadata, including hashes, byte sizes,
  capabilities, validation flags, and expected execution results.
- Done: add map/storage-map, assertions, bounded-loop, array, struct,
  aggregate ABI, nested aggregate, storage nested aggregate, U32 arithmetic,
  and bitwise coverage from the upstream `psy-compiler/tests` and
  `psy-precompiles` corpus.
- Done: add U32/Hash limb packing coverage for local arrays and ABI parameters
  from the upstream `psy-precompiles` corpus.
- Done: emit and validate ProofForge deploy manifests for all Dargo-backed Psy
  smoke compile outputs.
- Done: add map storage path coverage for `Map<Hash, Hash, N>` with Dargo
  compile/execute validation.
- Done: add expression-position `storageMapSet` lowering and MapProbe coverage
  for upstream map edge semantics where `set` and repeated `insert` return the
  previous `Hash` value.
- Done: add storage-reference compound assignment coverage for scalar storage
  and generic storage paths with Dargo compile/execute validation.
- Done: add native U32 scalar storage coverage using Psy `pub value: u32`
  storage plus scalar `+=` assignment, with Dargo compile/execute validation.
- Done: add native Bool scalar storage coverage using Psy `pub flag: bool`
  storage plus `bool as Felt` return casts, with Dargo compile/execute
  validation.
- Done: add native Bool fixed-array and storage-array coverage using Psy
  `[bool; N]` literals/indexing plus `pub flags: [bool; N]` storage, with
  Dargo compile/execute validation.
- Done: add native Hash scalar and storage-array coverage using Psy
  `pub root: Hash` and `pub roots: [Hash; N]`, with Dargo compile/execute
  validation.
- Done: add fixed-array equality coverage using Psy `assert_eq`, `==`, and
  `!=` over `[Felt; N]` locals, with Dargo compile/execute validation.
- Done: add U32 storage array coverage using Felt-backed storage plus explicit
  U32 read/write casts, with Dargo compile/execute validation.
- Done: add Felt-backed U32 storage-array path compound assignment lowering as
  explicit read/update/write casts, with Dargo compile/execute validation.
- Done: add native U32 storage struct field path writes, reads, and compound
  assignment coverage, with Dargo compile/execute validation.
- Done: add a Psy IR coverage manifest gate so every portable IR constructor
  must be classified as lowered, validated, unsupported, or structural for the
  Psy backend.
- Done: factor Dargo smoke package generation into a shared writer so every
  Psy smoke creates the same `src/main.psy` and `Dargo.toml` layout before
  metadata validation.
- Done: allow EVM-style entrypoint selectors in the Psy backend as target-specific
  ABI metadata; Psy source generation uses method names only and may record the
  selector in artifact metadata for cross-target traceability.
- Done: validate Psy identifiers and duplicate declarations before source
  generation so invalid names do not fall through to Dargo parser/typechecker
  failures.
- Done: add a generic generated test fallback for valid Psy IR modules that do
  not have fixture-specific assertions, backed by `GenericEntrypointProbe`,
  golden source, Dargo compile/execute validation, ABI generation, deploy
  manifest generation, and artifact metadata validation.
- Convert the deploy manifest path to upstream compressed genesis deploy JSON
  once the Psy tooling exposes a stable boundary, then exercise a local
  node/prover deployment smoke.
- Record Dargo/Psy compiler version or commit once the toolchain exposes a
  stable value.

Acceptance criteria:

- Generated `.psy` source is readable and checked into a golden fixture or
  snapshot.
- `dargo compile` produces a non-empty JSON artifact on a machine with the Psy
  toolchain.
- `dargo execute` returns `result_vm: [2]` for the Counter lifecycle.
- `dargo execute` returns `result_vm: [15]` for ContextProbe's
  `sum_context(2,3)` lifecycle.
- `dargo execute` returns deterministic four-Felt outputs for HashProbe's
  `poseidon_hash` and `poseidon_pair_hash` entrypoints.
- `dargo generate-abi` produces a non-empty ABI JSON artifact.
- `dargo execute` returns `result_vm: [42]` for the generic non-whitelisted
  `GenericEntrypointProbe`.
- Artifact metadata records target id, fixture id, used capabilities, artifact
  paths, hashes, byte sizes, Dargo package source copy, Dargo package manifest,
  and validation status.
- Artifact metadata is machine-validated by the Psy smoke scripts.
- Artifact metadata records Dargo/Psy compiler version or commit once available.
- Unsupported non-circuit-friendly IR nodes fail before source generation.
- CI either pins a known-good `psyup` release or skips this gate clearly when a
  matching toolchain tarball is unavailable.

## Workstream 11: Kaspa Toccata Research Target

Goal: decide whether and how ProofForge should support Kaspa's Toccata
programmability stack without pretending it is an EVM, account-state, or generic
ZK circuit target.

Tasks:

- Done: add a docs-first target note for candidate id `kaspa-toccata`.
- Classify the target as UTXO covenant/based-app research, not
  `zk-circuit-sourcegen`.
- Review candidate capabilities for UTXO state, covenant lineage, transaction
  v1, user lanes, compute budgets, and inline proof verification.
- Decide whether the first spike should generate Silverscript or only produce a
  target manifest around hand-authored covenant source.
- Define a tiny L1 covenant Counter-like scenario with successor-output
  validation.
- Define the minimal artifact metadata shape for covenant source, transaction v1
  manifest, covenant lineage manifest, and optional proof verifier manifest.
- Defer based-app support until the L1 covenant artifact shape is clear.

Acceptance criteria:

- `docs/targets/kaspa-toccata.md` records the target classification and
  non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish inline ZK verification from `psy-dpn`-style circuit
  source generation.

## Workstream 12: Stellar Soroban Research Target

Goal: decide whether and how ProofForge should support Stellar smart contracts
without treating all Wasm contract chains as one target.

Tasks:

- Done: add a docs-first target note for candidate id `wasm-stellar-soroban`.
- Classify Soroban as a Wasm-host candidate, not a generic Wasm artifact target.
- Decide whether the first spike should generate a native Rust/Soroban package
  or wait for a direct Lean-to-Wasm host bridge.
- Review candidate capabilities for address authorization, contract-account
  authorization, storage TTL, contract spec metadata, and Stellar assets.
- Define a tiny Counter-like scenario that exercises storage and event output.
- Define artifact metadata for Wasm, contract spec, deployment manifest,
  toolchain versions, and validation result.
- Identify the local smoke command set: `stellar contract build`, sandbox or
  testnet deploy, and invoke.

Acceptance criteria:

- `docs/targets/stellar-soroban.md` records the target classification and
  non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish Soroban from NEAR and CosmWasm despite all three using
  Wasm artifacts.

## Workstream 13: Internet Computer Research Target

Goal: decide whether and how ProofForge should support Internet Computer
canisters without treating every Wasm artifact as the same contract target.

Tasks:

- Done: add a docs-first target note for candidate id `wasm-icp-canister`.
- Classify ICP canisters as a Wasm-host candidate, not a generic Wasm artifact
  target.
- Decide whether the first spike should generate a native Motoko/Rust CDK
  package or wait for a direct Lean-to-Wasm canister bridge.
- Review candidate capabilities for Candid, update/query method modes, stable
  memory, orthogonal persistence, principals, cycles, async inter-canister
  calls, canister lifecycle, certified data, and management canister APIs.
- Define a tiny Counter-like scenario with one update method and one query
  method.
- Define artifact metadata for Wasm, Candid, canister manifest, stable-state or
  upgrade policy, toolchain versions, and validation result.
- Identify the local smoke command set: local replica, PocketIC, or ICP CLI
  canister install/call flow.

Acceptance criteria:

- `docs/targets/internet-computer.md` records the target classification and
  non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish ICP canisters from NEAR, CosmWasm, and Soroban despite
  all using Wasm artifacts.

## Workstream 14: TON TVM Research Target

Goal: decide whether and how ProofForge should support TON smart contracts
without pretending TVM contracts are EVM, Wasm-host, Move, or ZK targets.

Tasks:

- Done: add a docs-first target note for candidate id `ton-tvm`.
- Classify TON as a TVM/Tolk sourcegen candidate.
- Decide whether the first spike should generate Tolk source/package artifacts
  or wait for a lower-level TVM/cell IR.
- Review candidate capabilities for cells, TL-B metadata, inbound messages,
  outbound messages, get methods, action lists, `StateInit`, account status,
  TVM gas, and jetton/token integration.
- Define a tiny Counter-like scenario with one internal message and one get
  method.
- Define artifact metadata for source, TVM/BOC output, interface metadata,
  initial state, message/action schema, toolchain versions, and validation
  result.
- Identify the local smoke command set: Acton/Tolk compile and local test or
  emulator validation.

Acceptance criteria:

- `docs/targets/ton-tvm.md` records the target classification and non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish TON TVM from Wasm-host, EVM, Move, and ZK targets.

## Workstream 15: Bitcoin Cash CashScript Research Target

Goal: decide whether and how ProofForge should support Bitcoin Cash smart
contracts without pretending UTXO spend paths are stateful contract method calls.

Tasks:

- Done: add a docs-first target note for candidate id `bch-cashscript`.
- Classify BCH/CashScript as a UTXO script/covenant sourcegen candidate.
- Decide whether the first spike should generate CashScript source/package
  artifacts before any lower-level BCH Script path.
- Review candidate capabilities for UTXO state, P2SH scripts, unlockers,
  transaction introspection, covenants, local state, CashTokens, timelocks,
  signature checks, CashScript artifacts, and transaction-builder validation.
- Define a tiny UTXO spend scenario with at least one contract function and a
  transaction-builder smoke.
- Define artifact metadata for `.cash` source, cashc artifact JSON, bytecode,
  constructor/unlocker manifest, transaction scenario, toolchain versions, and
  validation result.
- Identify the local smoke command set: `cashc`, CashScript SDK,
  `MockNetworkProvider`, and optional chipnet/node-backed validation.

Acceptance criteria:

- `docs/targets/bitcoin-cash-cashscript.md` records the target classification
  and non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish BCH/CashScript from EVM, Wasm-host, Move, generic
  Bitcoin, and Kaspa/Toccata targets.

## Workstream 16: Algorand AVM Research Target

Goal: decide whether and how ProofForge should support Algorand smart contracts
without pretending AVM applications are EVM, Wasm-host, Move, Solana, TVM,
UTXO, or ZK circuit targets.

Tasks:

- Done: add a docs-first target note for candidate id `algorand-avm`.
- Classify Algorand as an AVM/TEAL source or package-generation candidate.
- Decide whether the first spike should generate Algorand Python or Algorand
  TypeScript package artifacts before any direct TEAL emitter path.
- Review candidate capabilities for stateful applications, LogicSig programs,
  ARC-4 ABI/app specs, global/local/box storage, transaction groups, resource
  references, inner transactions, Algorand Standard Assets, AVM budget, and
  AlgoKit/Puya artifacts.
- Define a tiny stateful Counter-like application with one update method, one
  read/query path, explicit storage schema, and localnet or simulator-backed
  validation.
- Define artifact metadata for source, approval bytecode, clear-state bytecode,
  optional LogicSig bytecode, ABI/app spec, storage schema, resource references,
  toolchain versions, and validation result.
- Identify the local smoke command set: AlgoKit/Puya compile plus LocalNet or
  simulator-backed create/call/query validation.

Acceptance criteria:

- `docs/targets/algorand-avm.md` records the target classification and
  non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish Algorand AVM from Wasm-host, EVM, Move, Solana, TVM,
  UTXO, and ZK targets.

## Workstream 17: Cardano Plutus/Aiken Research Target

Goal: decide whether and how ProofForge should support Cardano smart contracts
without pretending eUTXO validators are stateful method-call contracts.

Tasks:

- Done: add a docs-first target note for candidate id `cardano-plutus-aiken`.
- Classify Cardano as an eUTXO validator sourcegen candidate.
- Decide whether the first spike should generate Aiken source before any direct
  Plutus/UPLC path.
- Review candidate capabilities for eUTXO state, validator roles, datum,
  redeemer, script context, validity ranges, transaction balancing, native
  tokens, execution units, and Plutus blueprints.
- Define a tiny Counter-like eUTXO state-machine scenario with successor-output
  validation.
- Define artifact metadata for Aiken source, UPLC/Plutus validators, blueprint,
  datum/redeemer schemas, transaction scenario, execution units, toolchain
  versions, and validation result.
- Identify the local smoke command set: Aiken compile/test plus emulator,
  SDK-backed transaction, or cardano-node-backed validation.

Acceptance criteria:

- `docs/targets/cardano-plutus-aiken.md` records the target classification and
  non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish Cardano from EVM, Wasm-host, Move, Solana, TVM, AVM,
  generic Bitcoin, BCH/CashScript, and Kaspa/Toccata targets.

## Workstream 18: Tezos Michelson/LIGO Research Target

Goal: decide whether and how ProofForge should support Tezos smart contracts
without hiding Michelson operation-list semantics behind generic contract calls.

Tasks:

- Done: add a docs-first target note for candidate id `tezos-michelson-ligo`.
- Classify Tezos as a Michelson source/artifact target with LIGO as the first
  sourcegen path.
- Review candidate capabilities for Michelson code, entrypoints, typed
  Micheline storage, `big_map`, operation lists, views, events, tickets,
  Sapling, delegation, gas/storage burn, and LIGO artifacts.
- Define a tiny Counter-like contract with one entrypoint, one view, typed
  storage, and a local test or sandbox validation flow.
- Define artifact metadata for LIGO source, Michelson output, parameter/storage
  schema, operation list, view/event manifest, toolchain versions, and
  validation result.
- Identify the local smoke command set: LIGO compile/test plus Octez sandbox or
  equivalent Tezos local validation.

Acceptance criteria:

- `docs/targets/tezos-michelson-ligo.md` records the target classification and
  non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish Tezos from EVM, Wasm-host, Move, Solana, TVM, AVM, UTXO,
  and ZK targets.

## Workstream 19: Starknet Cairo Research Target

Goal: decide whether and how ProofForge should support Starknet smart contracts
without treating Cairo chain contracts as generic ZK circuits.

Tasks:

- Done: add a docs-first target note for candidate id `starknet-cairo`.
- Classify Starknet as a Cairo/Sierra/CASM sourcegen candidate.
- Review candidate capabilities for Cairo source, Sierra, CASM, class
  declaration, class hash, Starknet ABI, storage, account abstraction, syscalls,
  L1/L2 messaging, Starknet fee/resource constraints, and Starknet Foundry
  validation.
- Define a tiny Counter-like contract with storage, an increment external
  function, a read function, and one event.
- Define artifact metadata for Cairo source, Sierra/CASM artifacts, ABI,
  selector/class-hash metadata, deployment manifest, toolchain versions, and
  validation result.
- Identify the local smoke command set: Scarb build plus `snforge` or
  devnet-backed tests.

Acceptance criteria:

- `docs/targets/starknet-cairo.md` records the target classification and
  non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish Starknet from EVM, Wasm-host, Move, Solana, TVM, AVM,
  UTXO, and `psy-dpn`-style ZK circuit targets.

## Workstream 22: Aleo Leo Research Target

Goal: decide whether and how ProofForge should support Aleo programs without
treating Aleo as only a generic ZK circuit target or confusing Aleo VM with
Algorand AVM.

Tasks:

- Done: add a docs-first target note for candidate id `aleo-leo`.
- Classify Aleo as a ZK application sourcegen candidate with Leo as the first
  source boundary, Aleo Instructions as the lower-level compiler target, and
  Aleo VM bytecode as the deployable execution artifact.
- Review candidate capabilities for Leo source, Aleo Instructions, Aleo VM,
  AVM bytecode, ABI, prover/verifier artifacts, transitions, finalization,
  records, mappings, storage, public/private inputs and outputs, program
  imports/upgrades, execute/deploy transactions, Credits fees, Leo tests, and
  devnet validation.
- Define a tiny Counter-like program with one entry `fn`, one public `mapping`,
  and one `final { }` block.
- Define a second private-record scenario that consumes one encrypted record,
  creates a successor record, and records public/finalization effects only when
  required.
- Define artifact metadata for Leo source, program id/imports, record/mapping
  schemas, finalization manifest, Aleo Instructions, Aleo VM bytecode, ABI,
  prover/verifier artifacts, execute/deploy transaction metadata, toolchain
  versions, and validation result.
- Identify the local smoke command set: `leo build`, `leo test`, optional
  `leo test --prove`, `leo execute --print`, and devnet/devnode-backed deploy
  or execute validation.

Acceptance criteria:

- `docs/targets/aleo-leo.md` records the target classification and non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish Aleo from `psy-dpn`, Zcash Shielded, Kaspa/Toccata
  inline ZK, Starknet Cairo, Algorand AVM, and generic source-generation
  targets.

## Workstream 20: Bitcoin Script/Miniscript Research Target

Goal: decide whether and how ProofForge should support Bitcoin base-layer
spending policies without pretending Bitcoin Script is a general smart-contract
runtime.

Tasks:

- Done: add a docs-first target note for candidate id
  `bitcoin-script-miniscript`.
- Classify Bitcoin as a limited UTXO spending-policy target through Script,
  Miniscript, descriptors, PSBT, and Bitcoin Core validation.
- Review candidate capabilities for Bitcoin Script, Miniscript, descriptors,
  SegWit, Taproot, Tapscript, witness stacks, sighash modes, hash locks,
  threshold multisig, PSBT flows, standardness, weight/fee constraints, and
  Bitcoin Core regtest validation.
- Define a tiny spending-policy scenario such as "A can spend immediately, or B
  can spend after a relative timelock."
- Define artifact metadata for policy, descriptor, output script, witness
  requirements, PSBT/raw transaction scenario, weight/fee, toolchain versions,
  and validation result.
- Identify the local smoke command set: Bitcoin Core regtest, descriptor import
  or address derivation, PSBT signing/finalization, and `testmempoolaccept` or
  equivalent spend validation.

Acceptance criteria:

- `docs/targets/bitcoin-script-miniscript.md` records the target classification
  and non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish Bitcoin Script/Miniscript from EVM, Wasm-host, Move,
  Solana, TVM, AVM, Cardano eUTXO, BCH/CashScript, Kaspa/Toccata, and generic
  smart-contract targets.

## Workstream 21: Zcash Shielded Research Target

Goal: decide whether and how ProofForge should support Zcash shielded payments
without treating Zcash as either plain Bitcoin Script or a generic ZK
smart-contract chain.

Tasks:

- Done: add a docs-first target note for candidate id `zcash-shielded`.
- Classify Zcash as a privacy UTXO/ZK payment candidate with transparent
  Zcash flows plus Sapling/Orchard shielded pools.
- Review candidate capabilities for shielded privacy, transparent pool
  crossings, Sapling, Orchard, shielded notes, note commitments, nullifiers,
  commitment tree anchors, Zcash protocol proofs, private witnesses,
  value-balance constraints, viewing keys, unified addresses, privacy policy,
  and zcashd/library validation.
- Define a tiny shielded payment scenario such as "spend one Orchard note,
  create one Orchard note, reveal one nullifier, preserve value balance, and
  pay a transparent fee."
- Define how a JDL-Z11-like script may express `shield`, `spendNote`,
  `createNote`, `revealNullifier`, `selectAnchor`, and `privacyPolicy` while
  rejecting global mutable shielded storage, method dispatch, and arbitrary
  proof verification.
- Define artifact metadata for transparent inputs/outputs, shielded pool,
  note input/output schema, nullifiers, anchors, value balance, witness/proving
  requirements, viewing-key disclosure, toolchain versions, and validation
  result.
- Identify the local smoke command set: zcashd RPC or a compatible Rust
  wallet/protocol library, with an explicit fallback blocker if local proving is
  too heavy for CI.

Acceptance criteria:

- `docs/targets/zcash-shielded.md` records the target classification and
  non-goals.
- Capability candidates remain documented but are not added to
  `ProofForge.Target.Capability` until reviewed.
- The first spike has a reproducible local validation command or a documented
  external-tool blocker.
- The docs distinguish Zcash from Bitcoin Script/Miniscript, BCH/CashScript,
  Kaspa/Toccata inline ZK, `psy-dpn` circuit sourcegen, and generic smart
  contracts.

## Workstream 23: Multi-Chain Token SDK

Goal: let users describe fungible token intent once, then let `--target`
choose ERC-20 contract generation on EVM or SPL Token / Token-2022 plans on
Solana without exposing chain-specific code at the user-facing SDK layer.

Tasks:

- Done: add RFC 0006, `ProofForge.Contract.Token.TokenSpec`, target token
  plans, and `Tests/TokenSpec.lean`.
- Done: add legacy Learn token intent source syntax,
  `ProofForge.Contract.Token.Learn`,
  `Examples/Learn/ProofToken.learn`, `Examples/Learn/FeeToken.learn`,
  `Tests/TokenLearn.lean`, and `proof-forge --learn-token --target <id>` plan
  emission as a compatibility path into `TokenSpec`.
- Done: add the first EVM ERC-20 artifact emitter for Learn token sources:
  `ProofForge.Contract.Token.Evm`, `Tests/TokenEvm.lean`, standard ERC-20
  selectors/events in metadata, Yul generation, and `solc --strict-assembly`
  bytecode validation through `--learn-token --target evm`.
- Done: add `scripts/portable/learn-token-smoke.sh` / `just
  learn-token-smoke` to validate the EVM ERC-20 token artifact path and the
  Solana Token-2022 plan path from Learn source.
- Done: add `scripts/evm/learn-token-erc20-vm-smoke.sh` / `just
  learn-token-evm-vm` to deploy the generated ERC-20 creation bytecode in an
  EthereumJS VM and validate standard ERC-20 calls, Transfer/Approval topics,
  and insufficient-balance revert behavior.
- Done: implement Solana SPL Token / Token-2022 deployment plan rendering at
  the Lean `TokenSpec` layer. `solanaTokenDeploymentPlan` now records mint
  account creation, associated token accounts, `mint_to`, `transfer_checked`,
  `approve`, `burn`, `revoke`, authority changes, Token-2022 extension
  initialization, Solana program ids, and source documentation references.
- Done: route Token-2022 features such as `transfer_fee`,
  `non_transferable`, `confidential_transfer`, and `transfer_hook` to
  Token-2022 extension metadata rather than custom per-token programs. The
  planner rejects the documented incompatible `transfer_fee` +
  `non_transferable` combination.
- Done: extend `scripts/portable/learn-token-smoke.sh` so the legacy `.learn`
  input path reuses the Lean `TokenSpec` plan, emits both SPL Token and
  Token-2022 structured plan JSON, and validates the plan offline with
  `@solana/spl-token` / `@solana/web3.js` instruction builders.
- Done: add `scripts/solana/token-plan-web3-smoke.sh` / `just
  solana-token-plan-web3` to execute the structured legacy SPL Token plan on
  Surfpool. The live runner creates the mint and associated token accounts,
  mints initial supply, executes the planned `mint_to`, `transfer_checked`,
  `approve`, `burn`, `revoke`, and mint-authority `set_authority` operations,
  and validates balances, supply, delegate state, and authority revocation with
  Web3.js reads.
- Done: add `scripts/solana/token-2022-transfer-fee-web3-smoke.sh` / `just
  solana-token-2022-transfer-fee-web3` to execute the structured Token-2022
  transfer-fee plan on Surfpool. The live runner initializes `TransferFeeConfig`,
  creates Token-2022 associated token accounts, mints initial supply, executes
  `TransferCheckedWithFee`, validates the source balance, recipient net balance,
  and recipient withheld fee, directly withdraws withheld fees from a token
  account, then runs a second transfer, harvests withheld fees to the mint,
  withdraws them from the mint, and validates the fee receiver balance plus
  cleared account/mint withheld amounts with Web3.js reads.
- Done: add `ProofForge.Contract.Token.Examples.SoulboundToken`,
  `Tests/TokenPlanEmit.lean`,
  `scripts/solana/token-2022-non-transferable-web3-smoke.sh`, and `just
  solana-token-2022-non-transferable-web3` to execute a Lean `.lean`
  TokenSpec-backed Token-2022 non-transferable plan on Surfpool. The live
  runner initializes `NonTransferable`, creates Token-2022 associated token
  accounts, mints initial supply, verifies mint/account extensions, proves
  `TransferChecked` is rejected, then burns the token and validates balances
  and supply with Web3.js reads.
- Implement EVM ERC-20 lowering: ABI/selectors, balance/allowance storage,
  total supply, transfer/approve/transferFrom, mint/burn options, events, and
  broader Foundry/Web3 behavior tests.
- Continue Surfpool live validation for Token-2022 extension plans beyond the
  transfer-fee initialization, checked-transfer, direct withdraw, and
  harvest-to-mint withdraw paths plus non-transferable transfer rejection:
  confidential transfer setup and transfer-hook routing.
- Add optional Solana wrapper/authority/transfer-hook program generation for
  custom policies such as capped supply or custom transfer restrictions.
- Extend token-specific artifact metadata with live deployment accounts, tool
  versions, and validation-run results once the Surfpool plan runner lands.

Acceptance criteria:

- A Lean-authored `TokenSpec` has deterministic EVM and Solana token plans; the
  legacy Learn token source lowers to the same `TokenSpec` boundary.
- EVM output emits ERC-20 Yul/bytecode and passes ERC-20 behavior tests using
  standard Web3/Foundry calls.
- Solana output renders structured SPL Token / Token-2022 plans, validates the
  instruction builders offline with `@solana/spl-token`, and now executes the
  legacy SPL Token plan plus the Token-2022 transfer-fee and non-transferable
  plans on Surfpool to create mints and token accounts, mint supply, transfer
  tokens where allowed, validate balances, verify withheld transfer fees,
  collect those fees through both direct account withdraw and harvest-to-mint
  plus mint withdraw, reject non-transferable `TransferChecked`, and burn
  non-transferable supply. Confidential transfer and transfer-hook behavior
  remains follow-up.
- Documentation clearly says Solana does not default to a per-token SPL
  contract; it uses SPL Token / Token-2022 programs by plan and CPI.

## Workstream 24: Architecture Convergence Follow-ups (post-merge)

The 2026-07 branch consolidation merged `solana-supprot`, `lookdown`
(Wasm/NEAR), `aleo-support`, and `cloudflare-support` into the trunk, resolved
the D-025/D-026/D-027 decision-id collisions (NEAR decisions renumbered to
D-029–D-031, Aleo to D-032, Cloudflare to D-033), unified the capability
matrix, and fixed the `IR.Statement.release` semantic conflicts in the EVM
event walker, Leo emitter, and TS emitter. Remaining follow-ups:

Tasks:

- Record the branch policy in `development-standards.md`: chains are
  directories and target ids, not branches; changes to `ProofForge/IR/*`,
  `ProofForge/Target/*`, `ProofForge/Contract/{Spec,Intent,Source}*`,
  `docs/capability-registry.md`, `docs/decisions.md`, and
  `docs/portable-ir.md` land on `main` in standalone PRs.
- Record the i18n rule: feature branches do not touch `docs/zh/*.zh.md` or
  `scripts/i18n/manifest.json`; translation sync runs on `main` only.
- Retire the merged remote branches (`DaviRain-Su/solana-supprot`,
  `DaviRain-Su/lookdown`, `DaviRain-Su/aleo-support`,
  `DaviRain-Su/cloudflare-support`) after the consolidation PR lands.
- Regenerate stale `docs/zh` translations flagged by the post-merge manifest
  (hand-merged decision/capability tables are synced; narrative docs that
  changed under auto-merge should be re-run through `translate-docs.py`).
- Decide whether the Solana bump-allocator selection unifies under the
  merged `TargetProfile.deploymentAllocator?` abstraction or stays
  target-local; record the outcome in `decisions.md`.
- Unify the CI workflow: the merged `.github/workflows/ci.yml` now carries
  EVM, Solana-light, NEAR, and Psy gates; add the Aleo and TS/Cloudflare
  smokes as optional jobs once their toolchains (`leo`, `tsc`/`wrangler`)
  are pinned.
- Naming cleanup: decide the public SDK name, schedule the `Lean.Evm` →
  `ProofForge.*` namespace rename, and enforce the Learn freeze
  ([authoring-model](authoring-model.md)).
- Declare `ContractSpec` → EVM Plan → Yul the EVM product pipeline in
  RFC 0004; label LCNF → `EmitYul` as the Lean-native experimental path.
  ✅ Done (D-046 / CS-6.3): LCNF `EmitYul` removed; RFC 0004 Accepted;
  `contract_source` is the product entry.
- Decide whether `wasm-cloudflare-workers` keeps its registry entry under
  `wasmHost` or moves to a distinct off-chain host family (no consensus, no
  on-chain state) so it does not dilute capability semantics; record in
  `decisions.md` alongside D-033.
- Done: record Gate G0 and the stricter Gate P0 primary-chain completion
  covenant in `decisions.md`, `target-roadmap.md`, and `gate-status.md`. Gate
  G0 closes the shared behavior/budget slice; until Gate P0 closes, new and
  non-primary targets stay docs-only or maintenance-only — no registry,
  capability, testkit, CI, or product-scope advancement.

Acceptance criteria:

- `docs/decisions.md` shows one linear decision log (D-001…D-046, no
  duplicate ids), records the allocator-unification outcome, and aligns
  D-039/RFC 0009 plus D-045/Gate P0 with the codebase's actual state.
- Development standards contain the branch and i18n rules.
- All four merged chain branches are deleted or archived.

## Workstream 25: Formal Verification Roadmap

Goal: convert the platform's core promises into machine-checked theorems,
per [formal-verification.md](formal-verification.md).

Tasks (see the roadmap for full statements):

- FV-1: prove capability routing soundness, rejection completeness, and
  Solana target-extension isolation for `resolveSpec` (D-027/D-028 as
  theorems).
- FV-2: extend `ProofForge/IR/Semantics.lean` beyond the scalar subset.
  Done: executable aggregate/storage slices for fixed arrays, struct values,
  aggregate ABI params/returns, storage arrays, storage struct fields, nested
  storage paths, state-threaded effectful expressions covering map insert/set
  lifecycles, control-flow execution for `ifElse` plus `boundedFor`,
  observable event-log traces, deterministic-result anchors, and a
  bounded-loop decreasing-measure anchor. Remaining: progress/preservation for
  the validated typed subset.
- FV-3: prove the `IR/Ownership.lean` checker sound against release-aware
  semantics (no use-after-release, no double release), justifying the three
  divergent `release` lowerings (EmitWat allocator, EVM/Psy reject, TS
  no-op).
- FV-4: EVM Counter, ValueVault, and EvmExpressionProbe executable trace
  obligations are done in `Backend/Evm/Refinement.lean`, backed by
  `Backend/Evm/YulSemantics.lean`. The obligations mirror
  `Backend/WasmNear/Refinement.lean` for scalar IR traces, check the
  selector-dispatched Yul surface, and execute the focused emitted Yul subset
  (`calldataload`, `calldatasize`, `sstore`, `sload`, scalar arithmetic,
  `exp`, bitwise/shift operators, comparisons, casts, assertions, `number`,
  deterministic memory-sensitive `keccak256` surrogate, `log0`-`log4`,
  `mstore`, `return`, focused `switch`, and bounded `for`) to compare observable EVM return words against the IR
  trace. ValueVault covers calldata arguments, multi-entry scalar storage
  updates, block-number context reads, event field evaluation, and return words;
  EvmExpressionProbe covers assertion success paths, `assertEq`, predicate
  expressions, U32/U64 arithmetic, casts, bitwise operators, and shifts.
  Additional EVM-only executable obligations now cover `EvmMapProbe`
  (map value/presence slots and nested map paths), `EvmTypedStorageProbe`
  (typed storage arrays and hash array reads), `EvmStorageStructProbe`
  (storage structs and arrays of flat structs), `EvmAbiAggregateProbe`
  (aggregate ABI params/returns), `ConditionalProbe` (if/else storage updates),
  and `EvmLoopProbe` (bounded loops plus branch/loop early returns). The covered
  FV-2 IR aggregate/storage/map/control-flow/event traces are now wired into those EVM
  obligations through explicit IR call arguments and `*_ir_observable_trace_ok`
  theorem anchors, so the same observable return words are checked on the IR
  side and the executable emitted-Yul side. NEAR now has Counter and ValueVault
  artifact-surface obligations over the `Compiler.Wasm.AST` produced by
  `EmitWat.lowerModule`, pinning entrypoint/helper host-boundary calls, memory,
  storage-key data, ValueVault event data, and host import module/type
  signatures before WAT printing. The same artifact surface now pins the Wasm
  memory declaration and fixed host buffer layout for the key, return, event,
  event-key, and input buffers, and it pins entrypoint `input`/`read_register`
  prologues, scalar u64 parameter loads from `INPUT_BUF`, storage-read key
  pointer/length frames passed into `__pf_read_u64`, storage-write key/value
  frames passed into `__pf_write_u64`, and ValueVault `block_index` checkpoint
  reads. NEAR also has Counter and ValueVault
  offline-host execution-surface obligations that derive the Borsh/little-endian
  input bytes, expected deterministic host return fragments, storage/log counts,
  final ValueVault state, scalar `value_return` payload bytes, per-step storage
  bytes, event-log fragments, and byte-level `log_utf8` payload hex fragments
  from the same IR trace boundary, while the CI smoke executes the generated WAT through
  `runtime/offline-host` and checks the matching ValueVault returns/events.
  Next: extend NEAR FV-4 from these execution surfaces toward a richer Wasm
  memory and host-call semantics boundary, and keep Psy/Solana on differential
  gates until their interpreters exist.
- FV-5: state checked-arithmetic overflow/division semantics once in the IR
  value domain and add the overflow branch to backend obligations.
- FV-6: prove `.learn`-vs-`contract_source` lowering equivalence for the
  paired fixture subset (decidable `ContractSpec` equality).
- FV-7: prove Token SDK plan invariants (total feature routing, documented
  incompatibility diagnostics, plan well-formedness).
- FV-8: first ValueVault worked-example invariants are now in
  `ProofForge.Contract.Examples.ValueVaultInvariant`. The decide-checkable
  anchors execute the chain-neutral ValueVault `contract_source` module through
  the shared 11-step FV-2 IR scenario, then check the observable return trace,
  `balance + released + fees = externally supplied value`, final storage
  fields, and `get_net_value = balance - fees`. Next: turn this concrete
  module into an author-facing invariant pattern and connect the proved IR
  invariants to FV-4 backend obligations.

Acceptance criteria:

- Each landed FV item is a `decide`-checkable theorem or Lean test wired
  into CI, not an external-tool dependency.
- A backend cannot move from Experimental to Supported without its FV-4
  trace obligation and shared-scenario differential gate.

## Workstream 26: Unified Rust Test Framework (testkit)

Goal: replace per-chain shell/Node harness sprawl with one declarative
scenario format and Rust in-process executors, per
[RFC 0007](rfcs/0007-unified-rust-test-framework.md).

Tasks (one milestone per implementing branch):

- M1: create the `testkit/` Cargo workspace (`core` + scenario TOML model,
  discovery, reporting); port `runtime/offline-host` into `harness-near`
  (wasmtime + NEAR host shim, allocator counters preserved); Counter
  scenario green on `wasm-near`; add `just testkit` and one CI step.
- M2: `harness-evm` on revm — load emitted runtime bytecode, dispatch via
  `.evm-methods` selectors, decode return words; Counter green on `evm`;
  first cross-target equivalence assertion (evm ↔ wasm-near observable
  traces).
- M3: `harness-solana` on mollusk-svm — absorb the
  `Tests/solana/*_mollusk.rs.tpl` logic as library code; Counter green on
  all three targets. Status: Counter is now wired through `mollusk-svm` in
  `testkit/harness-solana`, including golden assembly, manifest, artifact
  metadata, sBPF ELF build, stateful scenario execution, and three-target
  trace parity when `sbpf` and `solana-keygen` are available. ValueVault is
  now covered by `testkit/scenarios/value-vault.toml`, typed scalar scenario
  args, `runtime/offline-host --inputs-hex`, the NEAR/Wasm EmitWat fixture,
  the Solana ValueVault sBPF/Mollusk harness, and the EVM/revm harness when
  Foundry `cast` is available for selector hydration.
- M4: migrate golden-file comparisons and per-fixture behavior scripts into
  scenario steps; retire duplicated shell scripts; collapse the per-fixture
  CI steps into the testkit run. Live/chain-authentic gates (Foundry, Anvil
  deploy, Surfpool, near-sandbox, dargo, leo) remain separate scheduled or
  labeled jobs. Status: the first M4 slice is in place through
  scenario-declared `[[artifact]]` expectations. Counter's Solana golden
  assembly/manifest checks and ValueVault's WAT/Yul/sBPF/manifest/metadata
  source-shape checks now live in scenario TOML instead of hardcoded
  fixture-specific harness branches. The second slice adds nested
  `[[artifact.json]]` and `[[artifact.toml]]` checks so Solana Counter and
  ValueVault metadata/manifest fields, instruction names/tags, capability
  membership, and validation status are asserted declaratively by the scenario
  runner. The follow-up slice removes the duplicated Solana harness-internal
  metadata/manifest semantic validators and leaves only runtime dispatch parsing
  in `testkit/harness-solana`. The next slice tightens scenario discovery so
  empty or duplicate target ids and artifact expectations for undeclared
  targets fail before any harness runs. The current EVM slice moves EVM
  artifact metadata identity, capability, validation, and ABI entrypoint-name
  expectations into scenario-declared `[[artifact.json]]` checks, leaving
  `testkit/harness-evm` responsible only for selector parsing and runtime
  execution. The current diagnostic slice adds scenario-declared
  `[[diagnostic]]` expectations and a diagnostic-only `unsupported-crosscall`
  scenario that proves `solana-sbpf-asm` rejects the portable
  `crosscall.invoke` capability with the expected target/capability message.
  The current EVM golden slice adds `Examples/Evm/Counter.golden.yul` as the
  portable IR Counter Yul golden and makes `testkit/scenarios/counter.toml`
  assert the generated EVM Yul through `matches_file`; the older Lean SDK
  contract golden stays under `Examples/Evm/Contracts/`. The current
  Wasm/NEAR golden slice adds `Examples/WasmNear/Counter.golden.wat` and makes
  the same Counter scenario assert generated EmitWat output through
  `matches_file`, so Counter now has scenario-declared source equality for
  `wasm-near`, `evm`, and `solana-sbpf-asm`. The current ValueVault
  Wasm/NEAR golden slice adds `Examples/WasmNear/ValueVault.golden.wat` and
  makes `testkit/scenarios/value-vault.toml` assert generated EmitWat output
  through `matches_file`. The current ValueVault Solana golden slice adds
  `Examples/Solana/ValueVault.golden.s` and
  `Examples/Solana/ValueVault.manifest.toml`, making the same scenario assert
  generated sBPF assembly and manifest output through `matches_file`. The
  current ValueVault EVM golden slice adds
  `Examples/Evm/ValueVault.golden.yul` and makes the same scenario assert
  generated EVM Yul through `matches_file`, so ValueVault now has
  scenario-declared source equality for `wasm-near`, `solana-sbpf-asm`, and
  `evm`. The current metadata file-reference slice adds nested
  `[[artifact.file]]` checks, makes scenarios assert that JSON metadata file
  entries point at harness-produced artifacts and match path, byte size, and
  SHA-256 hash, and exposes EVM init-code/deploy-manifest outputs as testkit
  artifacts. The current cross-artifact JSON slice adds nested
  `[[artifact.jsonArtifact]]` checks, validates that Solana ValueVault metadata
  embeds the same IDL JSON as the generated IDL artifact, and moves the
  ValueVault IDL/client schema-shape checks into scenario TOML. The current
  structured-length slice adds `length` assertions to nested
  `[[artifact.json]]`/`[[artifact.toml]]` checks and uses them to pin Counter and
  ValueVault ABI entrypoint, event, capability, artifact, manifest instruction,
  Solana instruction, and IDL instruction counts declaratively. The current
  structured-schema slice adds `exists`, `kind`, and `non_empty` checks for
  nested JSON/TOML artifact assertions, then makes Counter and ValueVault
  validate EVM deploy manifests as first-class scenario artifacts, including
  init-code mode, absent chain profile, not-generated broadcast status, ABI and
  capability shape, and file references back to generated Yul, bytecode, and
  init-code artifacts.

Acceptance criteria:

- One scenario file drives all three priority targets when optional Solana
  tooling is available; adding a covered feature requires no new script,
  recipe, or CI step.
- A scenario using an unsupported capability asserts compile-time rejection
  with a diagnostic (never silently skips a target).
- Runner is deterministic and network-free by default; `revm`,
  `mollusk-svm`, and `wasmtime` versions are pinned.
- Lean-side compiler tests (diagnostics, coverage manifests, formal anchors)
  remain in `Tests/*.lean` and are not moved.

## Workstream 27: Allocator Abstraction Unification

Goal: one chain-neutral allocator model bound per target, per
[RFC 0008](rfcs/0008-allocator-abstraction.md); resolves the Workstream 24
allocator-unification decision.

Tasks:

- M1: generalize `ProofForge/IR/Allocator.lean` to the
  strategy/region/release triple (existing constructors map onto it; EmitWat
  behavior unchanged); record the decision in `decisions.md`.
- M2: fold Solana's `RuntimeAllocator` (`Backend/Solana/Extension.lean`)
  into the shared model — `solana.allocator.*` metadata keys stay as the
  Solana configuration syntax but populate the shared type; IDL renders from
  it; `Tests/SolanaAllocator.lean` updated.
- M3: add the explicit EVM binding (bump over call-scratch memory; documents
  what EmitYul/EVM plan already do); define the criteria for moving EVM
  `release` from rejection to checked no-op (blocked on FV-3 ownership
  soundness).
- M4: allocator behavior scenario in testkit (Workstream 26) across the
  three harnesses; NEAR asserts allocator counters, EVM/Solana assert
  observable-trace equality with `release` as no-op.

Acceptance criteria:

- One `AllocatorModel` type is consumed by EmitWat, the Solana backend, and
  the EVM binding; no parallel allocator records remain.
- Persistent-state models (EVM storage, Solana accounts, NEAR storage) are
  explicitly out of scope and unchanged.
- Capability gating via `runtime.allocator` cites `alloc.*` ids in
  diagnostics for unsupported release/strategy demands.

## Workstream 28: Target Portfolio Sequencing

Goal: execute the tiered portfolio in
[target-roadmap.md](target-roadmap.md) (D-034). Gates, not dates; one
milestone per implementing branch.

**Completion-first rule (D-044, 2026-07-03):** finish the three Tier-0 targets
— `solana-sbpf-asm`, `evm`, `wasm-near`, in that implementation priority — to
full DoD (behavior parity *and* resource budgets per D-040) before any new-chain
advancement. Per-criterion status lives in [gate-status.md](gate-status.md).

### Tier-0 completion (current top priority, blocks everything below)

- Done: NEAR budget reporting is wired through the testkit as a wasmtime-fuel
  proxy, with Counter and ValueVault baselines pinned alongside Solana CU and
  EVM gas. A precise NEAR host-gas model remains a P0 hardening refinement, not
  a Gate G0 blocker.
- Done: ValueVault budget baselines are pinned for `solana_cu`, `evm_gas`, and
  `near_gas` across the three primary targets in
  `testkit/scenarios/value-vault.toml`.
- Done: EVM semantic-plan migration (Workstream 3 / P0-2) is signed off.
  ExprPlan, StmtPlan, EntrypointPlan, EventPlan, CrosscallPlan, and
  MetadataPlan now feed the plan-backed EVM lowering and artifact/deploy
  metadata path; `just evm-plan`, `just evm-semantic-plan`, `just evm-all`,
  `just check`, Foundry, Anvil, and the FV-4 executable EVM/Yul trace anchors
  are green. Remaining EVM formal work is FV-2 control-flow/event semantics
  and deeper user-invariant-to-artifact obligations, not a P0-2 blocker.
- Done: Solana Pinocchio CI equivalence (Workstream 7 / P0-1) is signed off.
  The source/reference equivalence suite is included in `just solana-light`,
  and GitHub CI run `28675037861` at commit `3b2719a` completed the mandatory
  `solana-pinocchio-live` job: install Agave/Solana CLI, SBF platform-tools,
  `sbpf`, Surfpool, Node/npm; build ProofForge; run all five live
  dual-deploy scenarios without allow-skip.
- Gate P0 is closed. The landed Aptos/CosmWasm spikes can now be scheduled for
  M3/M4, but scheduling must be explicit; old docs-first research notes do not
  automatically open implementation scope.

Tasks:

- Done: Gate G0 (Tier-0 behavior/budget slice) is closed. Evidence lives in
  [gate-status.md](gate-status.md).
- Done: Gate P0 (primary-chain sign-off) is closed. Gate G0 plus the
  production-grade hardening from D-045 are signed off for Solana P0-1, EVM
  P0-2, and NEAR/Wasm P0-3.
- Tier 1a `wasm-cosmwasm`: M1 CosmWasm host imports + region-allocator ABI
  in EmitWat (the `cosmWasmRegion` binding from RFC 0008); M2 Counter
  artifact passes `cosmwasm-check`; M3 testkit `harness-cosmwasm` scenario
  green with cross-target equivalence vs `wasm-near`; M4 registry stage →
  Experimental.
- Tier 1b `move-aptos` (parallel to 1a): M1 IR → Move module printer for
  the Counter subset; M2 `aptos move test` gate + golden fixture; M3
  testkit CLI-wrapped executor; M4 capability rows validated; `move-sui`
  only after M4.
- Tier 2 (each behind its enabler, see roadmap): `wasm-stellar-soroban`
  after CosmWasm M4; `wasm-icp-canister` additionally requires an
  async/inter-canister design note before any code; `starknet-cairo` is
  the first sourcegen-lane pick after Aptos M4; `ton-tvm`,
  `algorand-avm`, `cardano-plutus-aiken`, `tezos-michelson-ligo` follow
  the one-active-sourcegen-spike rule.
- Tier 3 Bitcoin policy family (opens at Gate G2 = both Tier-1 exits):
  M1 policy IR (predicate tree) + `policy.*` capability ids in the
  registry docs; M2 rust-miniscript/descriptor emission for the 2-of-3 +
  timelock-recovery shared policy scenario; M3 PSBT/regtest testkit gate;
  M4 Lean policy-property checks (path reachability, participant
  non-omission) as decide-checked theorems. `bch-cashscript`,
  `zcash-shielded`, and `kaspa-toccata` stay parked behind M4.

Acceptance criteria:

- **Primary-chain completion covenant (D-045):** ✅ closed. `solana-sbpf-asm`,
  `evm`, and `wasm-near` reached production-grade DoD; Tier-1 advancement is
  now gated by explicit scheduling rather than implicit research-note carryover.
- No Tier-1 code lands before an explicit scheduling decision is reviewed; no
  Tier-2 target starts before its listed enabler; at most one sourcegen spike is
  active at any time.
- Policy-family targets never appear in contract-family capability rows;
  they get a separate `policy.*` section in the capability registry when
  Tier 3 opens.

## Workstreams 29–33: Platform Hardening (planning-first)

These come from the [2026-07 gap analysis](platform-gaps-2026-07.md). Each
starts as an RFC, not code; sequencing hooks are listed in the gap doc.

- **Workstream 29 — CLI product surface.** RFC 0009 is accepted and M1/M3 are
  landed: `proof-forge build|emit|check --target <id> --fixture <id>` exists
  through the compatibility layer, `check` is a real validation verb,
  list commands are wired, legacy flags have alias/deprecation metadata, and
  `just cli-target-first` now enforces that executable callers stay on the
  target-first surface while `Tests/CliTargetFirst.lean` locks representative
  mapping parity. Remaining work is M4: delete the legacy flag zoo only after
  the compatibility window.
- **Workstream 30 — Versioning and compatibility policy.** RFC covering IR
  version rules (tied to the coverage-manifest gate), artifact/deploy
  schema stability, append-only capability ids, and SDK deprecation policy.
- **Workstream 31 — Resource budgets as gates.** ✅ Implemented. The
  testkit scenario schema supports per-step `solana_cu`, `evm_gas`, and
  `near_gas` budgets with baselines and tolerance bands; the runner
  reports measured budgets and fails on regression. Counter baselines
  are locked for Solana CU and EVM gas; NEAR gas is reported as
  wasmtime fuel (info-only proxy) until a precise host-gas model lands.
  Gate G0 in `target-roadmap.md` and `validation-gates.md` now requires
  budget assertions.
- **Workstream 32 — Deployment lifecycle, upgrades, signing.** RFC for an
  upgrade-policy intent (`immutable | authority | governance`) lowered
  honestly per chain (Solana upgrade authority, EVM immutable/proxy, NEAR
  account keys, Aleo `@noupgrade`) or rejected; unsigned-transaction
  signing boundary; live-gate key conventions.
  M1 is implemented: `ContractSpec.upgradePolicy?` is serialized in
  ContractSpec JSON, the target resolver rejects unsupported target/policy
  combinations before code generation, and resolved plans emit
  `upgrade.policy.*` artifact metadata for supported policies.
- **Workstream 33 — Runtime error model + client generation.** Portable
  error codes with per-target encodings and `expect.error` scenario
  vocabulary (plan with Workstream 31's schema change); then a
  client-schema layer generalizing the Solana IDL/TS client generation to
  all targets (implementation waits for testkit M3).

  Milestones:

  - M1: Add `ErrorRef` (`assertion_id` + optional `user_code`) to the
    portable IR `assert`/`assertEq` constructors and update every backend
    pattern match to compile with the new shape. `message` remains the
    fallback text. ✅ Implemented.
  - M2: Implement per-target error encodings for EVM, Solana, and NEAR:
    EVM reverts with `abi.encode(uint32 assertion_id, string user_code)`;
    Solana returns `ProgramError::Custom(assertion_id)`; NEAR panics with
    a `PF:{id}:{code}` prefix. ✅ Implemented.
  - M3: Extend testkit schema and harnesses with `expect.error` so a
    scenario step can assert the exact `assertion_id`/`user_code` on
    failure. ✅ Implemented: `testkit/scenarios/error-ref.toml` verifies
    assertion ids across `wasm-near`, `evm`, and `solana-sbpf-asm`; the
    `error-ref-user-code` scenario additionally asserts exact EVM/NEAR
    `user_code` values. Solana intentionally remains assertion-id only because
    its runtime encoding is `ProgramError::Custom(assertion_id)`.
  - M4: Define target-neutral `ContractSpec` JSON schema and generate
    Solana IDL/client, EVM ABI wrapper, and NEAR wrapper sketches from it.
    ✅ Implemented at the client-schema/sketch boundary: `ContractSpec` JSON now
    emits a target-neutral `errors` catalogue derived from portable `ErrorRef`
    assertions, including `assertionId`, optional `userCode`, fallback
    `message`, and owning `entrypoints`; generated EVM and NEAR wrapper
    sketches embed the same `ERRORS` catalogue and expose assertion-id lookup
    plus native error parsing helpers (`decodeProofForgeRevert`,
    `parseProofForgePanic`); Solana IDL/client output embeds the same error
    catalogue and exposes assertion-id/custom-error lookup helpers. Guards:
    `Tests/ContractSpecJson.lean`, `Tests/ContractClient.lean`, and
    `Tests/SolanaSdkManifest.lean`. Deeper production client ergonomics moves
    to the SDK ecosystem completeness backlog.

## Workstream 34: Contract Source Productization (unified authoring layer)

Goal: make `contract_source` the **only product authoring surface** for
portable smart contracts. Application authors write business logic once in
Lean SDK syntax; **`proof-forge build --target <id>`** selects the chain and
the compiler routes capabilities, extensions, ABI/layout, and artifact emission.
Authors should not hand-write `ContractSpec`, `.evm-methods`, or target-specific
deployment plumbing in application modules.

Related:

- [Authoring model](authoring-model.md)
- [SDK ecosystem gaps (2026-07)](sdk-ecosystem-gaps-2026-07.md)
- [Shared scenario](shared-scenario.md)
- PR #11 unified EVM entry (legacy `Lean.Evm` / LCNF removed)

### Design contract

```text
contract_source / Token SDK  (portable business logic + typed capability intents)
  -> source AST
  -> ContractSpec / TokenSpec / portable IR
  -> target resolver + capability routing   <-- chosen by --target
  -> target semantic plan
  -> printer / assembler / package emitter
  -> artifacts (Yul/bytecode, sBPF, WAT, …) + manifests + clients
```

Rules for new work in this workstream:

1. **Portable first:** state, entrypoints, events, arithmetic, and control flow
   stay target-neutral in source unless a capability truly has no shared shape.
2. **Target at build time:** chain choice is CLI/config (`--target evm`,
   `--target solana-sbpf-asm`, …), not `#ifdef`-style duplication in contract
   modules.
3. **Extensions lower honestly:** Solana account/PDA/CPI, EVM payable/receive,
   NEAR promises, etc. attach through typed SDK forms and capability routing;
   unsupported combinations fail with explicit diagnostics.
4. **No second product language:** Builder string fixtures and `.learn` remain
   compiler/test inputs; new SDK features land in `ProofForge.Contract.Source`
   (or `Token`) first.

### Phase CS-0 — Unified compiler entry ✅ (landed PR #11)

| ID | Task | Status |
|---|---|---|
| CS-0.1 | Route all EVM example builds through `ContractLoader` + portable IR | ✅ |
| CS-0.2 | Remove legacy `ProofForge.Evm`, LCNF `EmitYul`, `.evm-methods` | ✅ |
| CS-0.3 | Migrate `Examples/Evm/Contracts/*` to `contract_source` / `ContractSpec` | ✅ |
| CS-0.4 | Refresh CI gates (build-examples, Foundry, Anvil, docs-check) | ✅ |

### Phase CS-1 — Portable authoring core

Focus: one syntax for cross-target business logic; tighten the portable vs
target-extension boundary in `contract_source`.

| ID | Task | Acceptance |
|---|---|---|
| CS-1.1 | Document portable subset vs target-extension forms in `authoring-model.md` with examples for EVM/Solana/NEAR | Authors can tell which statements compile on all primary targets vs one target |
| CS-1.2 | Add compiler diagnostics when portable syntax uses a capability absent from the selected `--target` | Error names target id, capability id, and source location |
| CS-1.3 | Add `contract_source` modules for shared scenarios (`Counter`, `ValueVault`) as canonical references; demote Builder-only examples to `Tests/` or `ProofForge/Contract/Examples/` | `Examples/` tree shows only `contract_source` product style |
| CS-1.4 | Extend Learn → `contract_source` equivalence tests (FV-6) for portable entrypoints/state/events | Paired `.learn` and `contract_source` fixtures produce equivalent `ContractSpec` |
| CS-1.5 | Target-first project layout convention: one `*.lean` contract module + `proof-forge build --target <id>` per artifact; no per-chain source forks | Documented in onboarding + one multi-target example compiling Counter to EVM + Solana + NEAR from the same file |

Current CS-1.2 slice: `wasm-near` contract_source builds now resolve the
loaded `ContractSpec` through `Target.resolveSpec` before EmitWat lowering. The
plan-backed EmitWat path rejects unsupported capabilities with the selected
target id, capability id, operation name, and source marker; `just
contract-source-diagnostics` locks the CLI behavior with a negative
`contract_source` fixture.

Current CS-1.3/CS-5.1 slice: ValueVault now has an application-facing shared
`contract_source` module at `Examples/Shared/ValueVault.lean`. `just
portable-value-vault` builds that same `.lean` file for the three primary
targets: EVM bytecode/Yul/metadata, Solana sBPF assembly plus manifest/IDL/TS
client metadata, and NEAR/Wasm WAT plus deploy metadata. The legacy
`Examples/Learn/ValueVault.learn` file remains an equivalence fixture, not the
recommended product authoring path.

Current CS-1.4 slice: `Tests/SharedContractSource.lean` now loads
`Examples/Shared/Counter.lean` and `Examples/Shared/ValueVault.lean` through
the product `contract_source` loader, compares their lowered IR modules against
the canonical `ProofForge.Contract.Examples.*` specs, and compares the paired
legacy `.learn` fixtures against those same shared modules. ValueVault also
compares the Solana package manifest rendered from the shared `.lean` source
against the manifest rendered from the legacy `.learn` fixture, so the
equivalence gate covers portable state, entrypoints, events, and package-facing
metadata for the current shared scenario.

Current CS-1.5/CS-4.1 starter-template slice: `templates/portable-counter`
is now a direct target-first `contract_source` starter. Its namespace matches
the file basename so `ContractLoader` can resolve the generated `Counter.spec`
without extra CLI flags, and its README uses `proof-forge build --target ...`
against the template source for EVM, Solana sBPF assembly, and NEAR/Wasm. The
existing `portable-counter-multi-target` smoke can validate the template by
setting `PORTABLE_COUNTER_SOURCE=templates/portable-counter/Counter.lean`.

### Phase CS-2 — EVM stdlib in `contract_source`

Focus: replace Builder-string stdlib with importable `contract_source` modules.
Maps to SDK ecosystem P0/P1 "access patterns" and partial token work.

| ID | Task | Acceptance |
|---|---|---|
| CS-2.1 | Rewrite `Examples/Evm/Contracts/stdlib/Ownable.lean` as `contract_source` module with `onlyOwner`-style entry guards | Builds on `--target evm`; Foundry smoke covers owner transfer/renounce |
| CS-2.2 | Rewrite `Pausable.lean` as `contract_source` with pause/unpause + `whenNotPaused` guard | Foundry smoke for paused/unpaused paths |
| CS-2.3 | Rewrite `ERC20.lean` as `contract_source` stdlib (not Builder map boilerplate) | Matches canonical ERC-20 selectors/events; Foundry lifecycle smoke |
| CS-2.4 | Add reusable `ReentrancyGuard` module (`contract_source`) | `VerifiedVault` uses stdlib guard instead of hand-rolled lock state |
| CS-2.5 | Add `import`/`open` story for stdlib modules in `contract_source` | Two example contracts compose Ownable + ERC20 without copy-paste |
| CS-2.6 | Unify `TokenSpec` ERC-20 emission with `contract_source` token modules (single planning boundary) | Same token semantics whether authored as Token SDK or contract module |

### Phase CS-3 — EVM capability surface in SDK syntax

Focus: expose already-lowered IR features through typed `contract_source` forms
so authors never drop to Builder for common EVM patterns. Cross-ref
[sdk-ecosystem-gaps-2026-07.md](sdk-ecosystem-gaps-2026-07.md) EVM P0/P1.

| ID | Task | Priority | Acceptance |
|---|---|---|---|
| CS-3.1 | `payable` entry / `msg.value` syntax (`nativeValue` routing) | P0 | Authoring syntax for value-bearing entries; Foundry value tests |
| CS-3.2 | Native ETH transfer helper (plain transfer to EOA/contract) | P0 | No manual `crosscallInvokeValueTyped(u64 0)` in examples |
| CS-3.3 | Entry modifiers / guards (`onlyOwner`, `whenNotPaused`, role guards) | P0 | Desugar to portable IR checks; diagnostics on misuse |
| CS-3.4 | Constructor dynamic ABI (string, bytes, dynamic arrays) | P0 | CLI + artifact metadata; deploy-object init reads initcode tail into storage; Foundry + Anvil smokes with `DynamicConstructorProbe` |
| CS-3.5 | Custom errors (Solidity-style selectors) | P1 | Structured revert surface + client decode helpers |
| CS-3.6 | ERC-165 `supportsInterface` module | P0 | Foundry interface probe tests |
| CS-3.7 | AccessControl roles (grant/revoke/hasRole) | P0 | Role-guarded entries in `contract_source` |
| CS-3.8 | ERC-721 core (ownerOf, transfer, safeTransferFrom, mint, burn) | P0 | Foundry NFT lifecycle smoke |
| CS-3.9 | CREATE2 factory template module | P1 | Deterministic deploy example + metadata |
| CS-3.10 | Proxy/upgrade patterns (UUPS or transparent) aligned with Workstream 32 `upgradePolicy` | P1 | Honest lowering or explicit reject per policy |
| CS-3.11 | ERC-1155 single-transfer core | P1 | ✅ `Stdlib/ERC1155.lean` covers balances, operator approvals, mint, burn, and single `safeTransferFrom`; Foundry smoke covers lifecycle. Batch transfer and receiver callbacks remain open |

### Phase CS-4 — Project development experience

Focus: a developer can open a repo, write `contract_source`, and run
build/test/deploy without touching compiler internals.

| ID | Task | Acceptance |
|---|---|---|
| CS-4.1 | `proof-forge init` (or documented template repo) with `contract_source` stub + multi-target `justfile` | New project builds Counter on `evm` and at least one other primary target |
| CS-4.2 | Foundry workspace integration: generated artifacts feed `forge test` / `forge script` with stable paths | Documented workflow; CI recipe |
| CS-4.3 | Productize `ContractClient` for EVM (ABI wrapper + deploy helpers) from `ContractSpec` JSON | TypeScript or Rust client generated beside artifact |
| CS-4.4 | Deploy commands beyond metadata: RPC broadcast + tx/receipt artifacts using chain profiles | Anvil-local + one documented testnet profile |
| CS-4.5 | VS Code/Cursor workspace recommendations + diagnostic surfacing from `proof-forge check --target <id>` | Onboarding friction item R6 partial closure |

### Phase CS-5 — Cross-target parity and testkit

Focus: prove the unified authoring story on all three primary chains.

| ID | Task | Acceptance |
|---|---|---|
| CS-5.1 | Expand testkit scenarios for `contract_source`-authored Counter/ValueVault on `evm`, `solana-sbpf-asm`, `wasm-near` | ✅ `just testkit` covers same scenario file, different `--target` artifacts |
| CS-5.2 | Resource budget baselines for new stdlib contracts (EVM gas, Solana CU) | ✅ Workstream 31 budgets extended; regressions fail CI |
| CS-5.3 | Authoring-model worked example: one business module, three targets, zero source forks | ✅ Tutorial in docs (EN + zh sync via translate pipeline) |

Current CS-5.1 testkit slice: `testkit/scenarios/counter.toml` and
`testkit/scenarios/value-vault.toml` now declare `source =
"Examples/Shared/*.lean"`. The EVM, Solana, and NEAR harnesses consume that
field and run target-first `proof-forge build --target ... --root . <source>`
instead of fixture-only emission for Counter/ValueVault. Scenario assertions now
pin `contract-sdk` metadata, NEAR artifact/deploy-manifest metadata parity,
Solana source/IDL/client artifacts, metadata file references, and the existing
behavior/budget traces. CI installs Rust 1.88 and the minimal Solana testkit
toolchain (`solana-keygen` + `sbpf`) before `just testkit` so all three primary
targets execute instead of skipping Solana. Rust 1.91+ is required for the
pinned testkit dependencies (`revm` and `sbpf`). The fixture-only paths remain for
specialized compiler/runtime scenarios such as `error-ref` and allocator probes.

Current CS-5.2 budget slice: `testkit/scenarios/counter.toml` and
`testkit/scenarios/value-vault.toml` pin per-step `evm_gas`, `solana_cu`, and
`near_gas` baselines for the shared `contract_source` modules. Each scenario
records reference harness toolchains under `[scenario.reference.toolchain]`.
`just testkit-budget-gate` runs Counter and ValueVault through the unified
testkit; CI still executes the full `just testkit` suite, so budget regressions
fail the default pipeline.

Current CS-5.3 tutorial slice: [tutorials/portable-contract-three-targets.md](tutorials/portable-contract-three-targets.md)
walks through `Examples/Shared/Counter.lean` and ValueVault with build commands,
`just portable-counter-multi-target`, testkit parity, and budget gates. The zh
mirror lives at [docs/zh/tutorials/portable-contract-three-targets.zh.md](zh/tutorials/portable-contract-three-targets.zh.md)
and is tracked in the translate manifest.

### Phase CS-6 — Documentation and legacy cleanup

| ID | Task | Acceptance |
|---|---|---|
| CS-6.1 | Rewrite `docs/targets/evm.md` pipeline section for unified entry (remove EmitYul/Lean.Evm) | ✅ Current EVM target note describes `contract_source` / `ContractSpec` → portable IR → EVM semantic plan → Yul AST/printer → solc, and labels the old EVM/LCNF route legacy/research |
| CS-6.2 | Update `development-standards.md` library roots (drop `ProofForge.Evm`, `EmitYul`) | ✅ Current roots match `lakefile.lean`; authoring guidance names `contract_source` and labels the old EVM/LCNF route legacy/research |
| CS-6.3 | Close Workstream 24 items: declare LCNF→EmitYul removed; record `contract_source` as EVM product pipeline | ✅ Decision log + RFC 0004 alignment (D-046) |
| CS-6.4 | Keep `docs/zh/examples-evm-README.zh.md` synced when `Examples/Evm/README.md` changes | ✅ `just docs-check` green; translate manifest tracks `Examples/Evm/README.md` |

Current CS-6.2 slice: `docs/development-standards.md` and its zh mirror now
list the current Lake roots from `lakefile.lean`, remove `ProofForge.Evm` and
`ProofForge.Compiler.LCNF.EmitYul` from current package guidance, and state that
`ProofForge.Backend.Evm` is compiler implementation code rather than a product
authoring SDK. New `Examples/` guidance is `contract_source` first; backend-only
probes belong under `Tests/` or `ProofForge/IR/Examples/`.

Current CS-6.1 slice: `docs/targets/evm.md` and its zh mirror now describe the
current unified EVM product pipeline, selector/ABI derivation from
`ContractSpec`, target-first example workflow, current backend module layout,
metadata source kind `contract-sdk`, and EVM gates. The old `.evm-methods` and
`ProofForge.Evm` / `Lean.Evm` / LCNF `EmitYul` route remains documented only as
legacy compatibility or historical research context.

Current CS-6.3 slice: [decisions.md](decisions.md) D-046 records removal of
`ProofForge.Evm`, LCNF `EmitYul`, and `.evm-methods`; [RFC 0004](rfcs/0004-evm-semantic-plan.md)
is **Accepted** and names `contract_source` → portable IR → EVM semantic plan →
Yul → solc as the sole EVM product pipeline. [INDEX.md](INDEX.md),
[validation-gates.md](validation-gates.md), and [targets/evm.md](targets/evm.md)
no longer describe LCNF as a live compiler route.

Current CS-6.4 slice: `Examples/Evm/README.md` and
`docs/zh/examples-evm-README.zh.md` are aligned on the unified `contract_source`
entry; the translate manifest entry keeps `just docs-check` green when the
English README changes.

### Suggested sequencing (Workstream 34)

1. **CS-1** portable boundary + diagnostics (unblocks honest multi-target authoring).
2. **CS-2** EVM stdlib in `contract_source` (immediate developer-visible win).
3. **CS-3** EVM P0 SDK blockers (parallelize CS-3.1–3.4 with CS-2).
4. **CS-4** project DX once stdlib + payable/constructor land.
5. **CS-5** testkit parity evidence across three primary targets.
6. **CS-6** docs/decisions cleanup continuously, not only at the end.

### Acceptance criteria (workstream complete)

- Every file under `Examples/Evm/Contracts/` is authored with `contract_source`
  or composes stdlib `contract_source` modules; Builder-only EVM examples live
  only under compiler test/fixture paths.
- A new developer can write a portable contract module and run
  `proof-forge build --target evm|solana-sbpf-asm|wasm-near` without editing
  chain-specific source.
- EVM P0 SDK blockers in [sdk-ecosystem-gaps-2026-07.md](sdk-ecosystem-gaps-2026-07.md)
  are either implemented through `contract_source` or explicitly rejected with
  diagnostics.
- CI covers stdlib + at least one multi-target shared-scenario build.

## Suggested Order

Workstreams 1, 1.5, 2–3, 6–7 (registry, portable IR, EVM metadata, Solana
asm) are substantially complete; remaining per-target detail lives in each
workstream. The forward order follows the tier gates of
[target-roadmap.md](target-roadmap.md) (D-034):

0. Architecture convergence follow-ups (Workstream 24) and FV-1/FV-2 from
   the formal verification roadmap (Workstream 25). In parallel, finish the
   platform-hardening follow-through from the gap analysis: CLI M4 legacy-alias
   removal after the RFC 0009 compatibility window, runtime error vocabulary
   for testkit, and the versioning / deployment lifecycle policies (30/32,
   docs-agent parallel track).
0b. **Contract Source productization (Workstream 34):** after unified EVM entry
   (CS-0 ✅), land portable authoring boundary (CS-1), EVM stdlib in
   `contract_source` (CS-2), then EVM SDK P0 surface (CS-3) before broad
   project DX (CS-4). This is the primary post-PR-#11 product track and
   subsumes the EVM rows in SDK Ecosystem Completeness below.
1. **Parallel:** unified testkit (Workstream 26) and allocator unification
   (Workstream 27) — testkit M1/M2 has no dependency on allocator M1/M2;
   allocator M4 lands after testkit M3.
2. **CLI target-first transition:** M3 caller migration is landed and guarded;
   M4 removes legacy flags only after the compatibility window.
3. **Parallel Tier 1 (after explicit scheduling):** `wasm-cosmwasm`
   (Workstreams 5/28) and `move-aptos` (Workstreams 8/28).
4. Tier 2 per enabler: Soroban after CosmWasm; Sui and the sourcegen lane
   (Starknet first pick) after Aptos; ICP additionally behind an async
   design note; one sourcegen spike at a time (Workstreams 12–19/22, 28).
5. Bitcoin policy family at Gate G2 (Workstreams 11/15/20/21, 28) —
   miniscript first, then CashScript/Zcash/Kaspa behind it.
6. Multi-chain Token SDK follow-ups (Workstream 23) continue alongside, and
   the remaining live-gate CI matrix (Workstream 9) grows with each target.
7. Cloud platform design refresh (prerequisite: two+ targets at Experimental
   with shared-scenario parity; D-010).

## SDK Ecosystem Completeness (post-P0 hardening)

Gate P0 closure proved production-grade compiler correctness for the three
primary chains. The next hardening phase is **SDK ecosystem completeness**:
ensure a developer can write and deploy **any** contract on each chain, not
just Counter and ValueVault. The full gap analysis lives in
[sdk-ecosystem-gaps-2026-07.md](sdk-ecosystem-gaps-2026-07.md).

**Principle:** Tier-1 targets (CosmWasm, Aptos) stay frozen until each primary
chain's P0 SDK blockers are closed. "P0 SDK blocker" = a feature whose absence
means a real developer cannot write a common contract pattern.

### EVM SDK blockers (5 P0, 10 P1)

Tracked in detail as **Workstream 34 Phase CS-2/CS-3**; implementation must
land in `contract_source` / Token SDK syntax, not Builder fixtures.

- ✅ P0: ERC-20 (stdlib mixin + compose + Foundry + VM smoke)
- ✅ P0: ERC-721 NFT (stdlib mixin; safeTransferFrom lacks onERC721Received → P1)
- ✅ P0: ERC-165 supportsInterface (stdlib mixin)
- ✅ P0: AccessControl roles (stdlib mixin + guard_role)
- ✅ P0: Constructor dynamic-type args (CLI ABI encoding + constructor_body + Anvil verified)
- P1: ERC-1155 batch transfer/receiver callbacks, ERC-4626 vault, ERC-2612 permit, custom errors,
  storage packing, batch operations, factory deployment template, AMM,
  Pausable auth, ERC-721 onERC721Received, dynamic constructor args runtime

### Solana SDK blockers (5 tracked P0, 4 closed, 7 P1)

- ✅ P0: Account constraint enforcement. Owner validation now lowers
  `owner=program`, `owner=executable`, and named owner-account references into
  the sBPF prologue with explicit diagnostics for unknown owner references, and
  `reallocAccount` plus `contract_source` `realloc account to N;` statements
  now emit static account-data reallocation metadata, manifest/IDL action
  records, and sBPF data-length stores guarded by
  `MAX_PERMITTED_DATA_INCREASE`. Surfpool behavior remains a validation
  expansion.
- ✅ P0: SPL Token close-account CPI now has builder helpers, typed
  `contract_source` syntax, legacy Learn syntax, manifest/artifact metadata,
  and sBPF instruction-data packing for tag `9`, covered by
  `Tests/SolanaCpiPacking.lean`, `Tests/LearnSource.lean`, and
  `Tests/CliTargetFirst.lean`. `just solana-spl-token-close-account-cpi-web3`
  now covers the live Surfpool/Web3.js validation path for closing an empty SPL
  Token account through CPI, destination rent lamport recovery, and marker
  state recording. Pinocchio equivalence for close-account remains a
  reference-breadth follow-up.
- ✅ P0: ComputeBudgetInstruction (set compute unit limit, priority fees)
  landed as transaction-side compute-budget advice in Solana manifests, IDL,
  generated TypeScript clients, and package metadata. The helper emits
  `ComputeBudgetProgram` pre-instructions from the selected entrypoint; it is
  intentionally not lowered as an in-program syscall.
- ✅ P0: Token-2022 direct sBPF CPI lowering now covers transfer-fee,
  non-transferable, metadata-pointer, default-account-state, immutable-owner,
  permanent-delegate, interest-bearing, memo-transfer, transfer-hook
  initialization, and pausable instruction layouts
  in the Solana builder API, typed `Surface` wrappers, manifest/IDL metadata,
  and sBPF instruction-data packing. Covered layouts include
  `initialize_transfer_fee_config`, `transfer_checked_with_fee`,
  withdraw/harvest fee collection, `set_transfer_fee`,
  `initialize_non_transferable_mint`, `initialize_metadata_pointer`,
  `initialize_default_account_state`, `initialize_immutable_owner`,
  `initialize_permanent_delegate`, `initialize_interest_bearing_mint`, and
  `enable_required_memo_transfers`, `initialize_transfer_hook`,
  `initialize_pausable_config`, `pause`, and `resume`; generated-program
  Token-2022 direct-CPI Surfpool/Web3.js gates verify the initialized extension
  state and Pausable pause/resume transitions.
- ✅ P1: Token-2022 transfer-hook execute/extra-account-meta routing now has a
  generated hook-program fixture with external `Execute` discriminator
  dispatch, per-entrypoint account constraints, PDA signer seeds for the
  validation account, static extra-account-meta TLV serialization, manifest/IDL
  metadata, target-first fixture routing, and
  `just solana-spl-token-2022-transfer-hook-web3` Surfpool/Web3.js validation
  for initializing the validation PDA, routing two static extra accounts through
  Web3.js, accepting an allowed transfer, and rejecting an over-limit transfer.
- ✅ P1: Associated Token `create_idempotent` CPI now has builder helpers,
  typed `Surface` wrappers, `contract_source` syntax, target-first fixture
  routing, manifest/IDL/artifact metadata including the selected token program,
  sBPF data packing for `associated-token.create_idempotent`, a separated
  6-account CPI account-meta frame, and `just solana-associated-token-cpi-web3`
  Surfpool/Web3.js validation that creates the canonical ATA and re-invokes the
  idempotent path.
- P1: Memo/Stake/Vote CPI, confidential_transfer,
  Pinocchio reference ≥10, Metaplex NFT, Anchor-style derive macro,
  address lookup tables

### NEAR SDK blockers (0 open P0, 6 closed, 9 P1)

- ✅ P0: Promise API (host imports in HostBridge + EmitWat crosscall stub; full async is P1)
- ✅ P0: NEP-141 fungible token (NearFungibleToken.lean stdlib mixin)
- ✅ P0: signer_account_id (host import + ctxSignerFunc + Surface.signer)
- ✅ P0: attached_deposit (host import + .nativeValue lowering)
- ✅ P0: Aggregate ABI (loadParams Borsh struct/array decode)
- ✅ P0: Callback handling (promise_result host import + offline stub)
- ✅ P1: block_timestamp (`block_timestamp` host import + `.contextRead .timestamp` lowering + Surface/Source helpers)
- ✅ P1: epoch_height (`epoch_height` host import + `.contextRead .epochHeight` lowering + Surface/Source helpers)
- ✅ P1: random_seed (`random_seed(register_id)` host import + `.contextRead .randomSeed` lowering + Surface/Source helpers returning `Hash`)
- ✅ P1: near-api-js client options (`NearViewOptions` for views, gas/attached-deposit `NearCallOptions` for function calls)
- ✅ P1: NEP-145 storage-management starter (`storage_deposit`/`storage_balance_*` U64 projection + Hash map target-first/offline-host smoke)
- P1: Full Promise async execution, full NEP-145 JSON balance objects/withdraw/refund/storage byte accounting,
  NEP-148 metadata, NEP-171 NFT, keccak256/crypto, storage_remove,
  gas accounting, real NEAR broadcast smoke
