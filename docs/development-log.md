# Development Log

This log records engineering milestones for ProofForge. It is not a replacement
for Git history. Use it to understand what changed, what was validated, and what
the next engineering step is.

## Format

Each entry should include:

- date
- commit or work range
- summary
- validation run
- known limitations
- next step

## 2026-07-04

### FV-8 ValueVault IR Invariant Anchor

Commit: this commit

Summary:

- Added `ProofForge.Contract.Examples.ValueVaultInvariant` as the first
  user-facing contract-invariant proof surface over the executable IR
  semantics.
- The module runs the chain-neutral ValueVault `contract_source` module through
  the shared 11-step scenario and checks the observable return trace.
- Added decide-checkable accounting and net-value invariants over the final IR
  state: `balance + released + fees` equals externally supplied value, final
  storage matches the scenario inputs, and `get_net_value` equals
  `balance - fees`.
- Wired the new FV-8 theorem anchors into `Tests/NearWasmFormal.lean`.

Validation run:

```sh
lake build ProofForge.Contract.Examples.ValueVaultInvariant
lake env lean --run Tests/NearWasmFormal.lean
git diff --check
```

Known limitations:

- This is a concrete executable-trace invariant for the ValueVault worked
  example, not yet a source-level invariant DSL or a universally quantified
  theorem over all valid inputs.
- It proves the invariant against the FV-2 IR semantics. It does not yet
  transport the invariant to emitted EVM, Solana, or NEAR artifacts.

Next step:

- Generalize the FV-8 shape so `contract_source` authors can state reusable
  invariants near the contract and then connect those invariants to the FV-4
  backend obligations.

### FV-4 NEAR Offline-Host Execution Surface Anchor

Commit: this commit

Summary:

- Added a decide-checkable NEAR/Wasm offline-host execution-surface obligation
  for Counter and ValueVault.
- The obligation derives each exported call's Borsh/little-endian input bytes
  and expected `runtime/offline-host` return-line fragment from the same IR
  trace boundary used by the formal anchors.
- Extended `scripts/near/emitwat-ci-smoke.sh` so CI now emits the ValueVault
  WAT fixture and executes the full 11-step ValueVault sequence through
  `runtime/offline-host`, checking typed inputs, return words, event logs, and
  fuel-based `near_gas` observations.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
scripts/near/emitwat-ci-smoke.sh
git diff --check
```

Known limitations:

- This is an execution-surface anchor, not a full Wasm semantics proof and not
  a proof about Wasmtime or the NEAR runtime.
- Aggregate Borsh input values remain outside this small obligation shape.

Next step:

- Deepen the NEAR FV-4 boundary from host-observed IO fragments toward a
  focused Wasm/offline-host semantics model.

### FV-4 NEAR ValueVault Artifact Surface Anchor

Commit: this commit

Summary:

- Extended the NEAR/Wasm artifact-surface obligation from Counter to
  ValueVault.
- The ValueVault obligation inspects the `Compiler.Wasm.AST` emitted by
  `EmitWat.lowerModule` and checks all seven exported entrypoints:
  `initialize`, `deposit`, `charge_fee`, `release`, `snapshot`,
  `get_balance`, and `get_net_value`.
- The check pins the host-boundary shape for storage reads/writes, block
  context reads, value returns, event logging, memory export, storage-key data
  segments, and event-name data segments.
- Wired `value_vault_emitwat_artifact_surface_ok` into
  `Tests/NearWasmFormal.lean`.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
git diff --check
```

Known limitations:

- This is still an AST-level obligation, not a full Wasm evaluator or a proof
  about `wat2wasm`, Wasmtime, or the NEAR runtime.
- It proves the emitted artifact surface for the shared ValueVault scenario;
  the next NEAR FV-4 step is to relate offline-host execution observations to
  the same IR trace boundary.

Next step:

- Add an executable offline-host trace obligation shape for the NEAR Counter
  and ValueVault scenarios, then align it with the existing IR observable
  traces.

### FV-4 NEAR EmitWat Artifact Surface Anchor

Commit: this commit

Summary:

- Added a decide-checkable NEAR/Wasm artifact-surface obligation in
  `ProofForge.Backend.WasmNear.Refinement`.
- The new obligation inspects the `Compiler.Wasm.AST` produced by
  `EmitWat.lowerModule` instead of matching WAT text. It pins the Counter
  artifact's required host imports, exported entrypoint call sequences,
  helper-function calls into NEAR storage/return host functions, memory export,
  and the `count` storage-key data segment.
- Wired `counter_emitwat_artifact_surface_ok` into
  `Tests/NearWasmFormal.lean`, advancing the NEAR FV-4 path beyond export-name
  coverage while keeping the claim below full Wasm semantic preservation.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
git diff --check
```

Known limitations:

- This is an AST-level artifact-surface proof, not a full Wasm evaluator or a
  theorem about `wat2wasm`, Wasmtime, or the NEAR runtime.
- It covers the Counter artifact first. Richer EmitWat fixtures beyond
  ValueVault still need their own NEAR FV-4 obligations.

Next step:

- Connect the offline-host execution trace shape to the same observable IR
  trace boundary.

### FV-2 IR Semantics Metatheory Anchors

Commit: this commit

Summary:

- Added deterministic-result theorems for the executable IR semantics:
  `evalExpr_deterministic`, `execStatements_deterministic`, and
  `runEntrypointWithArgs_deterministic`.
- Added `boundedForRemaining` and `boundedForRemaining_decreases`, a Nat
  measure anchor for `boundedFor` execution. This records the structurally
  decreasing loop argument that the FV-2 roadmap calls out as the bounded-loop
  termination basis.
- Wired the new theorem anchors into `Tests/NearWasmFormal.lean` so the
  existing formal anchor gate checks them alongside the IR trace obligations.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake env lean --run Tests/NearWasmFormal.lean
git diff --check
```

Known limitations:

- These are metatheory anchors over the current executable interpreter, not a
  full progress/preservation proof for every typed IR node.
- `execBoundedFor` remains in the existing partial mutual interpreter; this
  slice proves the decreasing measure used by the bounded loop step.

Next step:

- Continue FV-2 with progress/preservation for the validated typed subset, or
  deepen FV-4 on the NEAR side toward artifact-level execution obligations.

### FV-1 Target Capability Routing Anchors

Commit: this commit

Summary:

- Added theorem-friendly target checker helpers:
  `firstUnsupportedCapability?`, `allCapabilitiesSupported`,
  `firstSolanaMetadataCall?`, and `targetExtensionMetadataAllowed`.
- Routed `defaultResolve` through `requireCapabilityPlan`, so capability
  support and Solana target-extension isolation share one checked boundary.
- Added `ProofForge.Target.Formal` with Lean theorems proving that a
  successfully checked `CapabilityPlan` satisfies the FV-1 `checkedBy`
  predicate.
- Added `Tests/TargetFormal.lean` to exercise representative `resolveSpec`
  boundaries: EVM ValueVault success, Solana rejection of generic
  `crosscall.invoke`, and EVM rejection of Solana extension metadata.

Validation run:

```sh
lake build ProofForge.Target.Formal ProofForge.Target
lake env lean --run Tests/TargetFormal.lean
git diff --check
```

Known limitations:

- This proves the local checked boundary used by `resolveSpec`; it does not
  yet prove a full induction over every future adapter implementation.
- The executable `Tests/TargetFormal.lean` smoke is intentionally not a new
  public `just` gate yet, to avoid changing the validation surface before the
  current documentation sync state is cleaned up.

Next step:

- Extend FV-1 from the default adapter boundary to any non-default target
  adapter once those adapters expose custom resolution logic, then continue the
  formal roadmap toward NEAR artifact-level execution obligations.

### Solana Token-2022 Direct CPI Live Gate

Commit: this commit

Summary:

- Added target-first CLI fixture support for
  `--fixture spl-token-2022-cpi --format s|elf`, backed by the existing
  `ProofForge.Solana.Examples.SplToken2022Cpi` spec.
- Added `Tests/solana/spl_token_2022_cpi_web3_smoke.mjs`, which deploys the
  generated program on Surfpool and exercises Token-2022 transfer-fee direct
  CPI behavior: initialize transfer-fee config, transfer with fee, withdraw
  withheld fees from accounts, harvest withheld fees to mint, withdraw from
  mint, and update transfer-fee parameters.
- Added `scripts/solana/spl-token-2022-cpi-web3-smoke.sh` and the
  `just solana-spl-token-2022-cpi-web3` entrypoint. The shell gate validates
  generated artifact metadata before deploying the ELF.

Validation run:

```sh
lake build ProofForge.Cli ProofForge.Cli.Fixture ProofForge.Solana.Examples.SplToken2022Cpi
lake build proof-forge
lake env proof-forge check --target solana-sbpf-asm --fixture spl-token-2022-cpi --format s
lake env proof-forge check --target solana-sbpf-asm --fixture spl-token-2022-cpi --format elf
lake env lean --run Tests/SolanaCpiPacking.lean
node --check Tests/solana/spl_token_2022_cpi_web3_smoke.mjs
just solana-spl-token-2022-cpi-web3
git diff --check
```

Known limitations:

- This live gate covers the Token-2022 transfer-fee direct-CPI program path.
  The generated `initialize_non_transferable_mint` direct CPI remains covered
  by static packing/artifact checks; its generated-program live behavior should
  be split into a separate mint-initialization smoke.

Next step:

- Continue Solana-first validation expansion with either the non-transferable
  direct-CPI live smoke or the next ecosystem CPI target from the P1 gap list.

### Solana Lean Gate Example Build

Commit: this commit

Summary:

- Made `just solana-lean` explicitly build `ProofForge.Solana.Examples`
  before running tests that import individual Solana example modules.
- This fixes clean CI caches where `lake env lean --run
  Tests/SolanaAccountRealloc.lean` could fail before the imported
  `ProofForge.Solana.Examples.AccountRealloc` `.olean` existed.

Validation run:

```sh
just solana-lean
git diff --check
```

Known limitations:

- This is a CI/build-order fix only; it does not change generated contracts.

Next step:

- Re-run CI, then continue Solana direct Token-2022 live validation.

### Solana Token-2022 Direct CPI Lowering

Commit: this commit

Summary:

- Added direct Solana SDK helpers for Token-2022 transfer-fee and
  non-transferable CPI paths, including typed `Surface` wrappers.
- Lowered Token-2022 instruction data for
  `initialize_transfer_fee_config`, `transfer_checked_with_fee`,
  `withdraw_withheld_tokens_from_mint`,
  `withdraw_withheld_tokens_from_accounts`, `harvest_withheld_tokens_to_mint`,
  `set_transfer_fee`, and `initialize_non_transferable_mint`.
- Added the built-in Token-2022 program id
  `TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb` to direct CPI program-id
  packing, so these calls no longer fall back to placeholder program ids.
- Extended Solana manifest and IDL metadata with fee source, transfer-fee
  authorities, basis points, maximum fee, and withheld-account count fields.
- Added `ProofForge.Solana.Examples.SplToken2022Cpi` and expanded
  `Tests/SolanaCpiPacking.lean` to check Token-2022 tags, data lengths,
  value bindings, program id packing, manifest fields, IDL fields, and
  entrypoint helper calls.

Validation run:

```sh
lake build ProofForge.Solana ProofForge.Solana.Surface ProofForge.Backend.Solana.Extension ProofForge.Backend.Solana.Manifest ProofForge.Backend.Solana.Idl ProofForge.Solana.Examples.SplToken2022Cpi
lake env lean --run Tests/SolanaCpiPacking.lean
scripts/i18n/check-sync.sh
just solana-lean
just solana-light
```

Known limitations:

- This closes the static SDK/backend lowering side of the Token-2022 P0 for
  transfer-fee and non-transferable flows. A live Surfpool/Web3.js gate for
  generated direct-CPI programs, plus a Pinocchio/reference equivalence fixture,
  remains a validation expansion.
- `contract_source` shorthand syntax is still limited to the older SPL Token
  helpers; Token-2022 direct CPI is currently available through the builder API
  and typed `Surface` wrappers.

Next step:

- Continue Solana-first SDK hardening with direct Token-2022 live validation,
  then move to the next primary-chain SDK P0 backlog item.

### Solana Account Realloc API

Commit: this commit

Summary:

- Added Solana account reallocation as a target-specific account action rather
  than a portable IR node.
- Added `ProofForge.Solana.reallocAccount`, typed
  `ProofForge.Solana.Surface.reallocAccount`, and `contract_source`
  `realloc account to N;` syntax for static account-data growth/shrink targets.
- Realloc actions now emit `solana.account_realloc` metadata, automatically
  require a writable program-owned account constraint, and appear in
  `manifest.toml` plus the generated Solana IDL under `accountReallocs`.
- Lowered the action to an sBPF helper that checks
  `current_data_len + MAX_PERMITTED_DATA_INCREASE >= new_size` and writes the
  serialized account `data_len` field, with a dedicated `error_realloc` path.
- Added `ProofForge.Solana.Examples.AccountRealloc` and
  `Tests/SolanaAccountRealloc.lean`, wired into `just solana-lean`.

Validation run:

```sh
lake build ProofForge.Solana ProofForge.Solana.Surface ProofForge.Contract.Source ProofForge.Backend.Solana.Extension ProofForge.Backend.Solana.Manifest ProofForge.Backend.Solana.Idl ProofForge.Solana.Examples.AccountRealloc
lake env lean --run Tests/SolanaAccountRealloc.lean
```

Known limitations:

- This closes the static source/lowering/API side of the realloc P0. Dynamic
  target lengths, zero-initialization semantics, and a dedicated
  Surfpool/Web3.js behavior gate remain follow-up validation expansions.

Next step:

- Continue Solana-first SDK P0 hardening with Token-2022 direct sBPF CPI
  lowering for transfer-fee and non-transferable flows.

### Solana SPL Token Close-Account Lowering

Commit: this commit

Summary:

- Added SPL Token `close_account` CPI helpers to the Solana builder API and
  typed source surface.
- Added `contract_source` and legacy `.learn` syntax for
  `spl_token_close_account(...)` declarations and invocations.
- Lowered `spl-token.close_account` instruction data to the standard one-byte
  SPL Token tag `9` and preserved token-account data-size metadata for the
  closed account.
- Added `ProofForge.Solana.Examples.SplTokenCloseAccountCpi`,
  `Examples/Learn/SplTokenCloseAccountCpi.learn`, and package-rendering checks
  for manifest account schemas, data-layout metadata, data length, instruction
  tag store, and helper calls.
- Added legacy and target-first CLI fixture routes for
  `spl-token-close-account-cpi` in sBPF assembly and ELF formats.

Validation run:

```sh
lake build ProofForge.Solana ProofForge.Solana.Surface ProofForge.Contract.Source ProofForge.Contract.Learn ProofForge.Backend.Solana.SbpfAsm ProofForge.Solana.Examples.SplTokenCloseAccountCpi
lake env lean --run Tests/SolanaCpiPacking.lean
lake env lean --run Tests/LearnSource.lean
lake env proof-forge emit --target solana-sbpf-asm --fixture spl-token-close-account-cpi --format s -o /tmp/proof-forge-spl-token-close-account.s --artifact-output /tmp/proof-forge-spl-token-close-account.json
```

Known limitations:

- This closes the source/lowering side of the close-account P0. A dedicated
  Surfpool/Web3.js behavior gate and Pinocchio reference-equivalence gate for
  close-account are still follow-up validation expansions.

Next step:

- Continue Solana-first SDK P0 hardening with the user-facing realloc API, then
  Token-2022 direct sBPF CPI lowering.

### Solana Owner Constraint Lowering

Commit: this commit

Summary:

- Extended the Solana sBPF account-validation prologue beyond signer/writable
  and current-program owner checks.
- Added executable-account owner validation for `owner = "executable"` using
  the serialized account executable flag.
- Added named owner-account validation: arbitrary owner strings now resolve to
  another declared account in the same Solana account schema and compare the
  target account owner pubkey against that owner account key.
- Added an explicit lowering diagnostic for unknown owner-account references
  instead of silently skipping the check.
- Added `Tests/SolanaAccountConstraints.lean` and wired it into
  `just solana-lean`.

Validation run:

```sh
lake build ProofForge.Backend.Solana.SbpfAsm
lake env lean --run Tests/SolanaAccountConstraints.lean
```

Known limitations:

- This closes the signer/writable/owner account-constraint row. The broader
  Solana SDK P0 still has user-facing realloc API work open.

Next step:

- Continue Solana-first SDK P0 hardening with realloc ergonomics, then
  Token-2022 direct sBPF CPI lowering.

### Solana Compute-Budget Transaction Advice

Commit: this commit

Summary:

- Added a Solana SDK `ComputeBudgetAdvice` path that routes through
  `runtime.compute_units` capability metadata without adding a portable IR
  node or pretending the contract can raise its own transaction budget.
- Extended Solana package metadata so `manifest.toml`, the generated IDL, and
  generated TypeScript clients expose per-entrypoint compute-unit limit and
  priority-fee advice.
- Added generated client helpers that prepend `ComputeBudgetProgram`
  instructions before the ProofForge program instruction for the selected
  entrypoint.
- Added `Tests/SolanaComputeBudgetInstruction.lean` and wired it into
  `just solana-lean`.

Validation run:

```sh
lake build ProofForge.Backend.Solana.Extension ProofForge.Backend.Solana.Manifest ProofForge.Backend.Solana.Idl ProofForge.Backend.Solana.Client ProofForge.Solana
lake env lean --run Tests/SolanaComputeBudgetInstruction.lean
```

Known limitations:

- This closes the transaction-side ComputeBudgetInstruction blocker. The
  existing in-program `runtime.compute_units` syscall coverage remains the
  separate path for reading/logging remaining compute units.
- The generated client emits budget pre-instructions from metadata; live
  Surfpool/Web3 transaction-budget behavior can be added as a follow-up smoke
  once the broader SDK client ergonomics pass starts.

Next step:

- Continue Solana-first SDK P0 hardening with account constraint ergonomics
  (`close`/`realloc`) or Token-2022 direct sBPF CPI lowering.

### FV-4 EVM Event-Log Trace Obligations

Commit: this commit

Summary:

- Extended `ProofForge.IR.Semantics.State` with observable event logs, so
  `eventEmit` and `eventEmitIndexed` now record evaluated indexed/data fields
  instead of acting only as field-evaluation no-ops.
- Extended the focused EVM/Yul executable model so `log0` through `log4`
  record topic and memory data words while preserving the existing selector
  execution API for older obligations.
- Added EVM refinement log comparison for ValueVault business events and
  EventProbe scalar, typed scalar, multi-topic indexed, struct-data, and
  hashed aggregate-indexed event cases, including signature-derived `topic0`
  under the focused interpreter's deterministic pseudo-keccak model.
- Added a CI-visible theorem anchor for the EventProbe IR trace.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Known limitations:

- The focused Yul model compares emitted log topics/data against the IR trace,
  including signature-derived `topic0`, but it still uses the existing
  deterministic pseudo-keccak surrogate rather than claiming cryptographic EVM
  `keccak256` correctness.
- Event declarations remain represented through `eventEmit` effects rather
  than a richer first-class event schema in the portable IR.

Next step:

- Deepen the Wasm/NEAR side from export coverage toward artifact-level
  execution obligations, then move FV-2 from executable traces toward
  determinism/progress statements.

### FV-4 EVM Control-Flow Obligations

Commit: this commit

Summary:

- Extended `ProofForge.IR.Semantics` with executable `ifElse` and
  `boundedFor` semantics, including branch-local early-return propagation and
  loop-index binding.
- Extended the focused EVM/Yul executable model with bounded `for` execution,
  preserving `leave`/`return` control propagation through loop bodies and
  updates.
- Added EVM refinement obligations for `ConditionalProbe` and `EvmLoopProbe`
  so IR traces and emitted-Yul executable traces now agree for if/else storage
  updates, bounded loops, branch-local early returns, and loop-body early
  returns.
- Added CI-visible theorem anchors for the new control-flow obligations and
  updated the formal backlog to leave observable event-log traces as the next
  FV-2/FV-4 slice.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Refinement
```

Known limitations:

- Event effects are still evaluated for field expressions and executable Yul
  `log0`-`log4` calls are still accepted, but event logs are not yet modeled as
  first-class observable trace items.
- The Yul model remains a focused interpreter for generated ProofForge Yul, not
  a general EVM/Yul semantics.

Next step:

- Add observable event-log traces to the IR semantics and EVM/Yul executable
  obligation, then use EventProbe to compare emitted log topics/data against
  the IR trace.

### CLI M3 Target-First Gate Consolidation

Commit: this commit

Summary:

- Moved `Tests/CliTargetFirst.lean` into the `just cli-target-first` gate so
  the CLI M3 check now covers both executable caller scanning and target-first
  compatibility mapping parity.
- Removed the CLI mapping smoke from the Solana-only Lean gate; the same test
  now lives under the CLI product-surface gate where regressions belong.
- Expanded `Tests/CliTargetFirst.lean` across representative EVM, Solana,
  NEAR/Wasm, Psy/DPN, Aleo, Aptos, and Cloudflare target-first mappings.
- Updated RFC 0009, the RFC index, and the implementation backlog to record
  M3 as landed for executable callers while keeping M4 legacy flag removal
  deferred until the compatibility window.

Validation run:

```sh
just cli-target-first
```

Known limitations:

- This does not remove the legacy `EmitMode` parser. RFC 0009 keeps that as
  M4 work after one compatibility window.
- Historical design notes can still mention legacy aliases when they are
  documenting migration history.

Next step:

- Continue FV-2/FV-4 formal work over control-flow and observable event traces,
  or explicitly schedule the RFC 0009 M4 legacy flag removal window.

### FV-4 EVM IR-Backed Aggregate/Storage Obligations

Commit: this commit

Summary:

- Rechecked the architecture review disposition against current `main`. R1 is
  already closed by RFC 0009/D-039, and R5 is already handled by D-045/Gate P0
  plus the target roadmap, so this slice focuses on the still-valid R3 proof
  gap.
- Connected the covered FV-2 IR map/storage/aggregate traces to EVM refinement
  obligations for `EvmMapProbe`, `EvmTypedStorageProbe`,
  `EvmStorageStructProbe`, and `EvmAbiAggregateProbe`.
- Added aggregate observable-return expansion for IR arrays and structs in
  `ProofForge.Backend.Evm.Refinement`, and fixed whole-struct storage writes in
  `ProofForge.IR.Semantics` so direct field keys stay consistent after a full
  struct overwrite.
- Added CI-visible theorem anchors for the new EVM `*_ir_observable_trace_ok`
  checks through `Tests/NearWasmFormal.lean`.
- Synchronized the formal roadmap, backlog, gate notes, and the Chinese
  gate-status page so they no longer describe this EVM wiring as future work.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake build ProofForge.Backend.Evm.Refinement
lake env lean --run Tests/NearWasmFormal.lean
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- This is still an executable trace obligation, not a full proof about `solc`,
  EVM bytecode, or chain runtime execution.
- FV-2 still needs control-flow and observable-event trace semantics, and
  NEAR/Wasm still needs deeper artifact-level execution obligations beyond the
  existing export/trace anchors.

Next step:

- Extend FV-2 over `ifElse`, `boundedFor`, and observable events, then connect
  user-level invariants such as ValueVault solvency to the covered IR semantics.

### FV-2 State-Threaded Map Lifecycle Semantics

Commit: this commit

Summary:

- Refactored `ProofForge.IR.Semantics.evalExpr` so expression evaluation
  returns both the next `State` and the computed `Value`, preserving left-to-right
  effects through arrays, structs, storage path keys, assertions, events,
  `let` bindings, and returns.
- Made `storageMapInsert` and `storageMapSet` in expression position mutate
  storage while returning the previous value, matching the IR fixtures that
  model map upsert/set lifecycles.
- Added decide-checked theorem anchors for `EvmMapProbe.mapLifecycle`,
  `containsLifecycle`, and a parameterized insert/read/set/read sequence.
- Updated the formal roadmap, gate notes, and backlog so FV-2 now records
  state-threaded map lifecycle semantics as landed.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake env lean Tests/NearWasmFormal.lean
lake build ProofForge.Backend.Evm.Refinement
```

Known limitations:

- FV-2 still does not execute `ifElse` or `boundedFor` statements, and events
  are checked for field evaluation only rather than emitted as observable trace
  items.
- The EVM FV-4 aggregate/map obligations still compare Yul execution against
  expected return words; they are not yet wired to compare directly against the
  newly expanded IR traces.

Next step:

- Connect the covered FV-2 map/aggregate/storage traces to the EVM refinement
  obligations, then extend FV-2 statement execution over control flow and
  observable events.

### FV-2 Aggregate/Storage IR Semantics Slice

Commit: this commit

Summary:

- Reviewed the six-item architecture review disposition against current `main`.
  R1 and R5 are already aligned in the accepted RFC 0009 / D-039 docs and the
  primary-chain target scope, so this slice focuses on R3 rather than reopening
  capability ids or target portfolio policy.
- Extended `ProofForge.IR.Semantics` beyond scalar values with executable
  fixed-array, struct, storage-array, storage-struct-field, nested storage-path,
  and aggregate ABI value traces.
- Added decide-checked FV-2 theorem anchors for `ArrayProbe`,
  `EvmMapProbe`, `EvmStorageStructProbe`, and `EvmAbiAggregateProbe`, and wired
  them into `Tests/NearWasmFormal.lean`.
- Updated the formal roadmap/backlog/gate notes to say the first FV-2
  aggregate/storage slice has landed, while full IR-to-artifact semantic
  preservation remains open.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake env lean Tests/NearWasmFormal.lean
lake build ProofForge.Backend.Evm.Refinement
```

Known limitations:

- `storageMapInsert` / `storageMapSet` in expression position still return the
  old value without threading state through nested expression evaluation. Full
  map insert/set lifecycle traces need a state-threaded expression evaluator.
- The new FV-2 traces are not yet connected to the EVM FV-4 Yul obligations;
  they only establish the IR-side executable semantics slice.

Next step:

- Add state-threaded expression evaluation for effectful expressions, then
  wire covered aggregate/storage IR traces into the EVM/NEAR artifact
  obligations.

### Review Disposition Docs Tightening

Commit: this commit

Summary:

- Rechecked the July 2026 review disposition against current `main`: RFC 0009
  and D-039 are already aligned with the landed CLI M1 work, so this slice did
  not reopen that decision.
- Tightened public docs around the Gate P0 boundary: `docs/INDEX.md`, Chinese
  root README, and target-note indexes now agree that the primary-chain
  covenant is closed and the next active lane is CLI M3/M4 target-first
  migration before Tier-1 M3/M4 work.
- Continued the CLI M3 documentation pass by moving public EVM, Solana, NEAR,
  Psy/DPN, Aleo, and Cloudflare examples to
  `proof-forge build|emit --target ...` forms while retaining legacy aliases
  only as compatibility-window notes.

Validation run:

```sh
rg -n -- '--evm-bytecode|--emit-counter-ir|--emit-pure-math-ir|--solana-elf|--emit-counter-emitwat' README.md AGENTS.md Examples docs/INDEX.md docs/zh/INDEX.zh.md docs/targets docs/zh/targets docs/zh/examples-evm-README.zh.md docs/zh/README-root.zh.md
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Historical design/background notes still mention legacy aliases where the
  alias itself is the topic.
- `docs/validation-gates.md` was not rewritten in this slice because the
  current gate table already includes the target-first NEAR lane and the
  Chinese validation-gates translation has unrelated in-progress edits.

Next step:

- Finish executable CLI M3/M4 migration, then schedule FV-2 semantic
  preservation work before opening Tier-1 M3/M4 implementation.

### CLI M3 Target-First Regression Guard

Commit: this commit

Summary:

- Added a `cli-target-first` check that scans executable caller surfaces
  (`justfile`, `scripts/`, `testkit/`, and `Tests/`) and rejects direct
  `proof-forge --legacy-flag` invocations. The check intentionally excludes
  docs and generated build artifacts so it enforces runtime callers without
  blocking historical notes.
- Migrated the TypeScript / Cloudflare Workers Counter smoke from
  `--emit-counter-ir-ts` to
  `emit --target wasm-cloudflare-workers --fixture counter --format ts`.
- Added the target-first Cloudflare Counter mapping to the CLI compatibility
  layer and covered it in `Tests/CliTargetFirst.lean`.

Validation run:

```sh
just cli-target-first
lake build ProofForge.Cli
lake env lean Tests/CliTargetFirst.lean
scripts/ts/counter-ir-smoke.sh
```

Known limitations:

- This guard proves executable caller migration discipline; it does not delete
  the legacy parser or rewrite historical documentation examples.

Next step:

- Continue the M3 pass by migrating remaining examples/docs and only then
  prepare the M4 legacy flag removal plan.

### CLI M3 Target-First Solana Slice

Commit: this commit

Summary:

- Added target-first mapping for the portable ValueVault Solana ELF path:
  `emit --target solana-sbpf-asm --fixture value-vault --format elf` now routes
  to the existing ValueVault ELF builder instead of requiring
  `--value-vault-solana-elf`.
- Migrated the Solana PDA Web3.js smoke to the target-first SDK fixture command:
  `emit --target solana-sbpf-asm --fixture solana-sdk --format s`.
- Migrated the optional Solana ELF branch in the portable ValueVault smoke to
  target-first CLI and extended the CLI mapping smoke so this does not regress.

Validation run:

```sh
lake build ProofForge.Cli
lake env lean Tests/CliTargetFirst.lean
scripts/solana/pda-web3-smoke.sh
PROOF_FORGE_VALUE_VAULT_ELF=1 scripts/portable/value-vault-smoke.sh
```

Known limitations:

- This is an M3 migration slice, not the full M3/M4 cleanup. Two example files
  still show legacy commands, and the legacy parser remains during the
  compatibility window.

Next step:

- Continue migrating remaining examples/docs and then retire legacy flag
  aliases after the compatibility window defined by RFC 0009.

### Primary-Chain Gate P0 Sign-off

Commit: this commit

Summary:

- Closed Gate P0 after the final NEAR/Wasm target-first smoke landed and the
  remote CI run for commit `466b320` completed successfully.
- Recorded P0-3 as met: `wasm-near` now has target-first local execution,
  artifact metadata, deploy metadata, diagnostics, budget baselines, offline
  host execution, and CI coverage.
- Updated the roadmap/backlog boundary so the next active implementation lane
  is CLI M3/M4 migration before scheduling Tier-1 M3/M4 work.

Validation run:

```sh
just check
gh run view 28677055773 --json status,conclusion,headSha,url,jobs
```

Known limitations:

- Gate P0 is a production-hardening sign-off for the three primary local
  backends. It does not mean every target is fully feature-complete, and it
  does not remove the need for CLI M3/M4 cleanup or FV-2 semantic preservation
  work.

Next step:

- Migrate scripts and testkit callers from legacy flags to
  `proof-forge build|emit|check --target ...` before advancing CosmWasm/Aptos
  M3/M4.

### Wasm-NEAR Target-First Metadata Smoke

Commit: this commit

Summary:

- Fixed the target-first Wasm-NEAR `check` path so WAT fixtures are validated by
  the actual EmitWat backend instead of a generic fixture capability table.
- Extended target-first `build --target wasm-near --fixture ... --format wat`
  so it honors the selected fixture for Counter, ErrorRef, Context, Hash, and
  Map probes.
- Added EmitWat artifact and deploy metadata for target-first WAT output,
  including ABI entrypoints, capability ids, WAT/optional Wasm hashes, and the
  local offline-host deployment mode.
- Added `just near-target-first`, which checks Counter and Context target-first
  paths, validates metadata/deploy manifests, and runs the generated Counter WAT
  through `runtime/offline-host`.

Validation run:

```sh
lake build ProofForge.Cli
lake build proof-forge
just near-target-first
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build
```

Known limitations:

- The deploy manifest records a local offline-host execution mode; it does not
  create a live `near-sandbox` account deployment, public NEAR deployment, or
  wallet/key-management flow.
- Gate P0-3 should only be signed off after the GitHub Actions run for this
  commit is observed green.

Next step:

- Observe the remote CI run, then update gate status and the target roadmap to
  close NEAR/Wasm P0-3 if the new mandatory smoke stays green.

### EVM FV-4 Aggregate/Storage Trace Expansion

Commit: `3b2719a`

Summary:

- Extended `ProofForge.Backend.Evm.YulSemantics` with a deterministic
  memory-sensitive `keccak256` surrogate so the focused FV-4 interpreter can
  execute generated map value and presence-slot helpers without collapsing every
  hashed storage slot to `0`.
- Extended `ProofForge.Backend.Evm.Refinement` with decide-checked executable
  EVM/Yul obligations for `EvmMapProbe`, `EvmTypedStorageProbe`,
  `EvmStorageStructProbe`, and `EvmAbiAggregateProbe`.
- Added observable multi-word return support for aggregate ABI returns, covering
  flat struct and fixed-array return data in the executable Yul subset.

Validation run:

```sh
lake build ProofForge.Backend.Evm.YulSemantics
lake build ProofForge.Backend.Evm.Refinement
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build
```

Known limitations:

- These new obligations are EVM/Yul executable checks against expected
  observable return words. They do not yet prove map/array/struct IR semantics,
  because `ProofForge.IR.Semantics` remains scalar-only; that is still FV-2.

Next step:

- Extend FV-2 IR semantics for maps, arrays, structs, and aggregate values so
  the new EVM-only obligations can be connected back to IR traces.

## 2026-07-03

### Solana Pinocchio Live CI Lane

Commit: `a9437c1`..`3b2719a`

Summary:

- Added a mandatory GitHub Actions `solana-pinocchio-live` job for the P0
  Solana hardening lane.
- Added `scripts/solana/install-pinocchio-live-ci-tools.sh` to install/check
  Agave/Solana CLI `v3.1.12`, SBF platform-tools `v1.52`, pinned `sbpf`,
  Surfpool `v0.10.8`, and Node/npm before running the aggregate live suite.
- Hardened the Pinocchio live helper so it can fall back to Agave
  platform-tools rust/cargo with `--no-rustup-override` when rustup
  `+toolchain` dispatch is unavailable.
- Updated Gate P0 evidence so P0-1 now records the new mandatory CI lane,
  while keeping the gate open until a remote run is observed and the broader
  Solana production sign-off is complete.

Validation run:

```sh
bash -n scripts/solana/install-pinocchio-live-ci-tools.sh \
  scripts/solana/pinocchio-live-common.sh \
  scripts/solana/pinocchio-live-equivalence.sh \
  scripts/solana/pinocchio-*-live-equivalence.sh
CARGO_BUILD_SBF_BIN=cargo-build-sbf \
  SOLANA_RUSTUP_TOOLCHAIN=1.89.0-sbpf-solana-v1.52 \
  bash -c '. scripts/solana/pinocchio-live-common.sh; platformToolsRustBin'
```

Known limitations:

- The local installer self-check was interrupted after entering the SBF
  platform-tools install path because the command produced no progress output
  for over 90 seconds on this machine. The CI job covers the fresh-install path
  with a 15-minute timeout around `cargo-build-sbf --install-only`.
- This entry predates the remote sign-off run; P0-1 is closed by the follow-up
  entry below.

Next step:

- Keep the mandatory live lane green while the remaining Gate P0 work moves to
  NEAR/Wasm P0-3.

### Solana P0-1 Production Sign-off

Commit: this commit

Summary:

- Marked Solana direct sBPF backend P0-1 as signed off in
  `docs/gate-status.md`.
- Synchronized the target portfolio roadmap and implementation backlog so
  Solana P0-1 and EVM P0-2 are both treated as complete, leaving NEAR/Wasm
  P0-3 as the remaining Gate P0 blocker.

Validation run:

```sh
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
scripts/i18n/check-sync.sh
git diff --check
lake build
gh run view 28675037861 --json status,conclusion,headSha,url,jobs
```

Known limitations:

- Gate P0 is still open until NEAR/Wasm has target-first local execution and
  deploy metadata sign-off.

Next step:

- Start the NEAR/Wasm P0-3 hardening slice.

### Solana Target-First v0 ELF Live Deploy Fix

Commit: feature commit for Solana target-first ELF arch propagation

Summary:

- Fixed the target-first CLI compatibility layer so
  `proof-forge emit --target solana-sbpf-asm --format elf
  --solana-sbpf-arch v0` forwards the requested architecture into the legacy
  Solana ELF builder instead of silently falling back to the default v3 build.
- Confirmed the fixed target-first path now emits the same loader-compatible
  v0 ELF shape as the direct legacy flag: `e_flags = 0`, valid section table,
  and Agave `solana-sbpf 0.13.1` parse/load success.
- Re-ran the full local ProofForge-vs-Pinocchio live dual-deploy suite. All
  five Surfpool scenarios deployed both generated ProofForge and Pinocchio
  reference programs and matched observable state.

Validation run:

```sh
lake build proof-forge
lake env lean Tests/CliTargetFirst.lean
lake env proof-forge emit --target solana-sbpf-asm --fixture system-cpi \
  --format elf --solana-sbpf-arch v0 \
  -o build/solana-compat-check-fixed/new-v0.so \
  --artifact-output build/solana-compat-check-fixed/new-v0.json
cargo run --manifest-path /tmp/proofforge-elf-check-013/Cargo.toml -- \
  build/solana-compat-check-fixed/new-v0.so
just solana-pinocchio-system-transfer-live-equivalence
just solana-pinocchio-live-equivalence
```

Known limitations:

- This resolves the local Agave loader compatibility blocker, but Gate P0 is
  still open. The live Pinocchio suite is not yet mandatory in CI, and broader
  Solana production-grade sign-off remains tracked under Gate P0.

Next step:

- Promote the live Pinocchio suite into a reliable CI lane once Solana
  rustc/platform-tools, Surfpool, Node/npm, and port isolation are stable
  enough for mandatory remote execution.

### Solana Pinocchio Live Deploy Blocker Triage

Commit: documentation commit for Solana live deploy blocker triage

Summary:

- Ran the aggregate Pinocchio live dual-deploy gate locally with Surfpool,
  Agave `solana-cli 3.1.12`, `cargo-build-sbf 3.1.12`, and `sbpf 0.2.2`
  available.
- Confirmed the live suite does not currently fail because of missing tools:
  all five child gates build the ProofForge ELF and Pinocchio reference ELF,
  start Surfpool, then fail at ProofForge `solana program deploy --use-rpc`
  with `Failed to parse ELF file: invalid file header`.
- Triage against Agave's embedded `solana-sbpf 0.13.1` showed the generated
  ProofForge ELF is not Solana CLI loader-compatible: blueshift `sbpf build
  --arch v0` emits a one-segment bare ELF with no section table and
  `e_flags = 3`, which makes Agave use its strict v3 parser. That parser
  requires `EM_SBPF`, four program headers, a valid section-header index, and
  function-start markers. Reflagging the bytecode as v0 is also invalid because
  the v3/static-call bytecode then fails relocation with
  `RelativeJumpOutOfBounds`.
- Recorded the blocker in Gate P0 and Workstream 7 so Solana P0 does not read
  as a generic CI/toolchain-install task.

Validation run:

```sh
just solana-pinocchio-live-equivalence
cargo run --manifest-path /tmp/proofforge-elf-check-013/Cargo.toml -- \
  build/solana-pinocchio-system-transfer-live/proofforge-system-transfer-live-sbpf-project/deploy/proofforge-system-transfer-live.so \
  build/solana-pinocchio-system-transfer-live/pinocchio-system-transfer-reference.so
```

Known limitations:

- This is a blocker triage and documentation pass. It does not yet add the
  Solana loader-compatible ELF packaging path, and the live dual-deploy suite
  remains non-mandatory for CI.

Next step:

- Implement an explicit Solana CLI loader-compatibility path: either emit and
  package through the standard Solana platform-tools format, or extend the
  direct assembler pipeline to produce the strict v3 headers and function-start
  markers accepted by Agave.

### Review Follow-up: RFC, Portfolio, and Gate State Alignment

Commit: feature commit for review follow-up documentation alignment

Summary:

- Reconciled the post-review assessment with the current repository state:
  RFC 0009/D-039 already reflect CLI M1 as landed, and D-045/Gate P0 already
  freeze non-primary target advancement.
- Updated the platform gap analysis so CLI and budget work no longer read as
  unplanned or unimplemented after RFC 0009 M1, D-040, RFC 0010, and Gate G0.
- Updated the implementation backlog so Gate G0 is treated as closed and the
  remaining work is correctly scoped to Gate P0 production hardening and CLI
  M3/M4 migration.

Validation run:

```sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- This is a documentation alignment pass. It does not implement new FV-4
  storage/aggregate trace obligations or change target capability ids.

Next step:

- Continue P0 hardening in priority order, with the next EVM FV-4 slice focused
  on map/fixed-array storage obligations unless Solana live-equivalence work
  takes priority.

### EVM Expression Assertion Executable Yul Trace Obligation

Commit: feature commit for FV-4 EVM expression/assertion executable trace
obligation

Summary:

- Extended `ProofForge.IR.Semantics` with predicate expressions, boolean
  operators, casts, bitwise/shift operators, exponentiation, and assertion /
  assertion-equality statement execution for the focused scalar subset.
- Extended `ProofForge.Backend.Evm.YulSemantics` with `exp`, matching the Yul
  emitted for EVM expression probes.
- Added `expression_evm_yul_executable_trace_ok`, which runs
  `EvmExpressionProbe` through the generated selector-dispatched Yul subset and
  compares observable return words against the IR trace.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake build ProofForge.Backend.Evm.YulSemantics
lake build ProofForge.Backend.Evm.Refinement
lake build ProofForge.Backend.Evm
scripts/i18n/check-sync.sh
git diff --check
just check
```

Known limitations:

- This covers successful assertion/expression paths only. Revert/error traces,
  maps, arrays, structs, aggregate returns, and full EVM word overflow semantics
  are still future FV-4 slices.

Next step:

- Extend executable obligations to map storage and fixed-array storage probes,
  then move into struct and aggregate return/state shapes.

### EVM ValueVault Executable Yul Trace Obligation

Commit: feature commit for FV-4 ValueVault executable Yul trace obligation

Summary:

- Extended `ProofForge.IR.Semantics` with entrypoint argument binding, U32/U64
  `sub`/`mul`/`div`/`mod`, `checkpointId`, and event field evaluation as a
  no-op state effect.
- Extended `ProofForge.Backend.Evm.YulSemantics` with calldata argument words,
  calldata size, `number`, `keccak256`, and `log0` through `log4` execution as
  focused FV-4 primitives.
- Added `value_vault_evm_yul_executable_trace_ok`, which runs the shared
  ValueVault scenario through the generated selector-dispatched Yul subset and
  compares observable return words against the scalar IR trace.

Validation run:

```sh
lake build ProofForge.IR.Semantics
lake build ProofForge.Backend.Evm.YulSemantics
lake env lean ProofForge/Backend/Evm/Refinement.lean
lake build ProofForge.Backend.Evm
scripts/i18n/check-sync.sh
git diff --check
just check
```

Known limitations:

- This is still a focused FV-4 slice, not a full EVM or libyul semantics. Event
  logs are modeled as no-op after field evaluation, block number is fixed at
  zero, `keccak256` returns a deterministic placeholder for the non-observable
  log/topic paths used here, and assertions/maps/arrays/aggregates are not
  covered yet.

Next step:

- Extend executable obligations from scalar storage to assertion, map, array,
  struct, and aggregate probes, then connect ValueVault user invariants to the
  IR semantics.

### EVM Counter Executable Yul Trace Obligation

Commit: feature commit for FV-4 executable Yul trace obligation

Summary:

- Added `ProofForge.Backend.Evm.YulSemantics`, a narrow executable model for
  the Counter-shaped generated Yul subset.
- Covered selector calldata decoding, dispatcher `switch`, internal function
  calls, local variables, `sstore`, `sload`, scalar arithmetic, `mstore`, and
  EVM `return` words.
- Extended `ProofForge.Backend.Evm.Refinement` with
  `counter_evm_yul_executable_trace_ok`, which runs
  `initialize -> get -> increment -> get` through the generated Yul dispatcher
  and compares observable return words against the scalar IR trace.

Validation run:

```sh
lake build ProofForge.Backend.Evm.YulSemantics
lake env lean ProofForge/Backend/Evm/Refinement.lean
lake build ProofForge.Backend.Evm
scripts/i18n/check-sync.sh
git diff --check
just check
```

Known limitations:

- This is still a focused FV-4 slice, not a full EVM or libyul semantics. The
  interpreter fails explicitly for unsupported Yul constructs and currently
  covers the Counter path only.

Next step:

- Extend the Yul-subset interpreter and trace obligations toward ValueVault:
  multi-entry scalar storage behavior first, then assertions, maps, arrays, and
  aggregate return/state shapes.

### EVM Counter Formal Trace Surface Obligation

Commit: feature commit for FV-4 EVM surface obligation

Summary:

- Added `ProofForge.Backend.Evm.Refinement` with a `TraceObligation` for the
  Counter `initialize -> get -> increment -> get` scenario.
- Reused the scalar IR executable semantics to prove the expected observable
  trace (`0` then `1`) with `native_decide`.
- Added an EVM/Yul surface obligation that checks generated Yul has the
  selector-dispatched top-level functions required by the same trace.
- Imported the module from `ProofForge.Backend.Evm`, so the theorem is checked
  by the existing `just build` CI path.

Validation run:

```sh
lake env lean ProofForge/Backend/Evm/Refinement.lean
```

Known limitations:

- This is the first FV-4 EVM anchor, not a full EVM refinement theorem. It does
  not yet interpret Yul storage operations or return words.

Next step:

- Add a tiny Yul-subset interpreter for Counter-shaped Yul (`sstore`, `sload`,
  `add`, selector-dispatched calls, `return`) and compare its observable trace
  against the IR trace.

### Review Alignment: CLI RFC And Primary-Chain Portfolio Freeze

Commit: feature commit for review alignment

Summary:

- Accepted RFC 0009 as the durable target-first CLI surface and recorded that
  M1 has already landed through the compatibility layer; M3/M4 remain open.
- Corrected D-039 so it no longer reads as a pre-code freeze after code already
  exists, and added an explicit superseded-position note for that old wording.
- Tightened the target portfolio wording: current product implementation is
  limited to `solana-sbpf-asm` -> `evm` -> `wasm-near`; `psy-dpn`,
  `aleo-leo`, and `wasm-cloudflare-workers` are maintenance-only inventory
  until Gate P0 closes.

Validation run:

```sh
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- This is a documentation and governance correction. It does not implement the
  missing end-to-end proof link between source-level invariants and generated
  EVM/Wasm artifacts.

Next step:

- Start FV-4 as a separate implementation slice: add an EVM trace obligation
  patterned after the existing NEAR trace obligation, then connect it to a
  concrete generated Yul/bytecode fixture and CI gate.

### Solana Pinocchio Live Equivalence Aggregate Gate

Commit: feature commit for Pinocchio live aggregate gate

Summary:

- Added `scripts/solana/pinocchio-live-equivalence.sh` as one aggregate entrypoint
  for the five ProofForge-vs-Pinocchio live dual-deploy gates.
- Added `just solana-pinocchio-live-equivalence` so local and future profiled CI
  lanes can run the full live suite through one command.
- The aggregate gate runs every child harness, summarizes pass/skip/fail counts,
  fails on any real child failure, and returns skip code `2` when prerequisites
  are missing unless `PROOF_FORGE_PINOCCHIO_LIVE_ALLOW_SKIP=1` is explicitly set
  for a probe lane.

Validation run:

```sh
bash -n scripts/solana/pinocchio-live-equivalence.sh scripts/solana/pinocchio-*-live-equivalence.sh
SURFPOOL=/nonexistent-proof-forge-surfpool scripts/solana/pinocchio-live-equivalence.sh
PROOF_FORGE_PINOCCHIO_LIVE_ALLOW_SKIP=1 SURFPOOL=/nonexistent-proof-forge-surfpool scripts/solana/pinocchio-live-equivalence.sh
```

Known limitations:

- This creates the suite entrypoint and strict skip semantics; it does not yet
  install the Solana SBF toolchain in GitHub Actions or make live dual-deploy
  mandatory in default CI.

Next step:

- Add a profiled CI job that installs/checks Surfpool, Solana CLI,
  `cargo-build-sbf`, `sbpf`, Node, and npm, then runs the aggregate live suite
  without `PROOF_FORGE_PINOCCHIO_LIVE_ALLOW_SKIP`.

### Solana Pinocchio Live Harness Shared Helper

Commit: feature commit for Pinocchio live harness hardening

Summary:

- Added a shared `scripts/solana/pinocchio-live-common.sh` helper for the five
  Pinocchio live dual-deploy harnesses.
- Centralized Solana rustup/toolchain detection, `cargo-build-sbf` invocation,
  SBF repair hints, Pinocchio ELF discovery, skip/fail handling, and Surfpool
  cleanup.
- Kept each harness-specific fixture, port, deployment, Web3.js scenario, and
  result comparison local to the existing live script.

Validation run:

```sh
bash -n scripts/solana/pinocchio-live-common.sh scripts/solana/pinocchio-*-live-equivalence.sh
just solana-pinocchio-reference-equivalence
SURFPOOL=/nonexistent-proof-forge-surfpool scripts/solana/pinocchio-system-transfer-live-equivalence.sh
```

Known limitations:

- This hardens the live harness implementation path but does not make the live
  dual-deploy gates mandatory in CI yet; that still depends on stable Solana
  rustc/platform-tools, Surfpool, Solana CLI, `sbpf`, Node, and npm
  availability in the runner.

Next step:

- Add a CI/profiled live-equivalence lane once the Solana SBF toolchain install
  path is deterministic enough for GitHub Actions, then extend reference
  coverage toward Token-2022.

### Gate G0 Closed

Commit: documentation sign-off commit

Summary:

- Closed Gate G0 in the gate ledger after recording the successful current
  remote CI run for commit `0c52fb8`.
- Clarified that Gate G0 closes only the shared behavior/resource-budget slice;
  Gate P0 remains open for the production-grade Solana, EVM, and NEAR/Wasm
  completion covenant.
- Updated the target roadmap so Tier-1/new-chain advancement stays frozen on
  Gate P0, not the now-closed G0 slice.

Validation run:

```sh
gh run watch 28658576786 --exit-status
```

Known limitations:

- P0 is still open. Solana live dual-deploy equivalence, EVM semantic-plan
  migration, and NEAR/Wasm target-first local execution/deploy metadata
  sign-off remain the next production-hardening tracks.

Next step:

- Continue P0 in implementation order: Solana live Pinocchio dual-deploy
  hardening first, then EVM semantic-plan migration, then NEAR/Wasm
  target-first deploy metadata sign-off.

### Solana Pinocchio Reference Equivalence In CI Light Gate

Commit: feature commit for Solana Pinocchio reference equivalence

Summary:

- Added source-only target-first emission for the Solana ContractSpec CPI
  fixtures (`system-cpi`, `system-create-account-cpi`, SPL Token transfer,
  ops, and authority) so reference-equivalence checks can validate artifact
  ABI/CPI metadata without requiring `sbpf`.
- Added `just solana-pinocchio-reference-equivalence` and included it in
  `just solana-light`, which is the default CI Solana gate.
- Added a CLI mapping regression test for the new target-first `--format s`
  routes and the existing `--format elf` routes.
- Updated Pinocchio reference manifests with source fixture ids while keeping
  ELF fixture ids for live dual-deploy gates.

Validation run:

```sh
lake build proof-forge
lake env lean Tests/CliTargetFirst.lean
just solana-pinocchio-reference-equivalence
```

Known limitations:

- This closes the CI-safe source/reference half of the Pinocchio track only.
  Live dual-deploy equivalence still depends on Surfpool, Solana CLI, `sbpf`,
  and stable `cargo-build-sbf`/Solana rustc platform tools.

Next step:

- Continue Workstream 7 by hardening the live Pinocchio dual-deploy harnesses
  for reproducible local/CI toolchain installation.

### ValueVault Solana Budget Baselines

Commit: feature commit for ValueVault Solana budget baselines

Summary:

- Added `--trace` to the unified testkit runner so budget work can print the
  raw per-call harness lines already stored in `CallOutcome.raw_line`.
- Fixed the EVM ValueVault testkit harness so the `CAST` environment override
  is passed through to `proof-forge emit --cast`, matching the availability
  check that decides whether the EVM branch can run locally.
- Fixed the target-first `proof-forge emit --target evm --fixture ... --format
  bytecode` compatibility mapper so it forwards `--cast` to the legacy EVM
  bytecode flags instead of silently falling back to `cast`.
- Pinned Counter `near_gas` baselines and all ValueVault `solana_cu`,
  `evm_gas`, and `near_gas` baselines in the testkit scenarios.
- Updated the Gate G0 ledger to reflect the repaired remote CI baseline and
  the now-implemented budget acceptance criteria; formal closure still waits
  for the current commit's remote CI/sign-off record.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- --help
.lake/build/bin/proof-forge emit --target evm --fixture value-vault --format bytecode --cast build/tools/cast-shim --yul-output /tmp/pf-vv.yul --artifact-output /tmp/pf-vv.json -o /tmp/pf-vv.bin
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --trace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target solana-sbpf-asm --trace
CAST="$PWD/build/tools/cast-shim" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --trace
```

Known limitations:

- The testkit budget baselines are deterministic harness baselines; live-chain
  budget gates remain a separate Solana/Foundry hardening concern.

Next step:

- Run the current commit through CI, then record Gate G0 sign-off or continue
  the non-blocking Tier-0 hardening items: Solana Pinocchio CI equivalence and
  EVM semantic-plan migration.

### Unified Testkit Deploy Manifest Schema Checks

Commit: feature commit for unified testkit deploy manifest schema checks

Summary:

- Added `exists`, `kind`, and `non_empty` assertions to nested
  `[[artifact.json]]` and `[[artifact.toml]]` checks, so scenario TOML can
  express presence, absence, type, and non-empty schema constraints without
  fixture-specific scripts.
- Updated Counter and ValueVault scenarios to validate EVM deploy manifests as
  first-class artifacts, including init-code mode, absent chain profile,
  not-generated broadcast status, ABI/capability counts, and deploy manifest
  file references back to generated Yul, bytecode, and init-code artifacts.
- Added targeted type/non-empty checks for key EVM and Solana metadata/manifest
  paths that were previously only implicitly checked by equality or script
  validators.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
CAST="$PWD/build/tools/cast-shim" just testkit
```

Known limitations:

- `kind` and `non_empty` validate schema shape only; semantic relations across
  artifacts still use `[[artifact.file]]` and `[[artifact.jsonArtifact]]`.

Next step:

- Continue moving script-only artifact metadata validators into scenario TOML,
  then remove redundant script assertions once the unified testkit owns the same
  artifacts.

### Unified Testkit Structured Length Checks

Commit: feature commit for unified testkit structured length checks

Summary:

- Added `length` assertions to nested `[[artifact.json]]` and
  `[[artifact.toml]]` scenario checks for arrays, objects/tables, and strings.
- Updated Counter and ValueVault scenarios to pin generated ABI entrypoint,
  event, capability, artifact, Solana manifest instruction, Solana metadata
  instruction, and IDL instruction counts declaratively.
- Extended the structured artifact unit test so JSON and TOML length checks are
  covered in `proof-forge-testkit-core`.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
CAST="$PWD/build/tools/cast-shim" just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `length` asserts collection/string shape, not the semantic meaning of each
  item; per-entry checks still need explicit `equals` or `contains` assertions.

Next step:

- Keep migrating old schema validators into scenario TOML, then remove duplicate
  script-only assertions once the testkit owns the same generated artifacts.

### Unified Testkit JSON Artifact Equality Checks

Commit: feature commit for unified testkit JSON artifact equality checks

Summary:

- Added nested `[[artifact.jsonArtifact]]` scenario checks that compare a JSON
  value embedded in one artifact with another harness-produced JSON artifact.
- Updated the Solana ValueVault scenario so metadata must embed the same IDL
  JSON as the generated `idl` artifact.
- Moved ValueVault Solana IDL/client shape checks into scenario TOML through
  structured JSON assertions and text contains checks.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
CAST="$PWD/build/tools/cast-shim" just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- JSON equality checks currently compare JSON values only; non-JSON artifacts
  still use `matches_file`, `contains`, structured TOML checks, or file-reference
  metadata checks.

Next step:

- Continue migrating duplicate per-target schema checks into scenario-declared
  artifact expectations where the harness already exposes the generated files.

### Unified Testkit Artifact File Metadata Checks

Commit: feature commit for unified testkit artifact file metadata checks

Summary:

- Added nested `[[artifact.file]]` scenario checks that validate JSON metadata
  file entries against harness-produced artifacts by path, byte size, and
  SHA-256 hash.
- Extended the EVM testkit harness to expose generated `init-code` and
  `deploy-manifest` artifacts alongside Yul, bytecode, and metadata, so EVM
  metadata references can be asserted declaratively.
- Updated Counter and ValueVault scenarios so EVM and Solana metadata now prove
  their generated artifact references through the shared testkit runner.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
CAST="$PWD/build/tools/cast-shim" just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- `[[artifact.file]]` currently validates JSON metadata entries; TOML file
  reference validation can be added if a target manifest needs the same
  path/bytes/hash relation.

Next step:

- Use the shared metadata file-reference checks to retire more duplicated
  per-target artifact hash validation from fixture-specific scripts where the
  testkit already owns the generated artifacts.

### Unified Testkit EVM ValueVault Golden

Commit: feature commit for unified testkit EVM ValueVault golden

Summary:

- Added `Examples/Evm/ValueVault.golden.yul` as the reviewed Yul source
  snapshot for the portable ValueVault scenario.
- Upgraded the `evm` Yul artifact in `testkit/scenarios/value-vault.toml` to
  check full generated-file equality through `matches_file`, while retaining
  focused substring checks for the contract object, entrypoints, logs, and
  block context access.
- ValueVault now has scenario-declared source equality for `wasm-near` WAT,
  `evm` Yul, and `solana-sbpf-asm` assembly/manifest.

Validation run:

```sh
.lake/build/bin/proof-forge --emit-value-vault-ir-yul --cast build/tools/cast-shim -o build/testkit/evm/value-vault/ValueVault.yul
solc --strict-assembly build/testkit/evm/value-vault/ValueVault.yul --bin
CAST="$PWD/build/tools/cast-shim" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target evm
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Local `just testkit` skips the ValueVault EVM runtime branch unless Foundry
  `cast` or a compatible `CAST` override is available; CI covers that branch
  with Foundry installed.

Next step:

- Move the remaining Workstream 26 M4 declarative coverage toward metadata
  hardening and retiring duplicate per-target script checks.

### Unified Testkit Solana ValueVault Golden

Commit: feature commit for unified testkit Solana ValueVault golden

Summary:

- Added `Examples/Solana/ValueVault.golden.s` and
  `Examples/Solana/ValueVault.manifest.toml` as the reviewed Solana
  source/manifest snapshots for the portable ValueVault scenario.
- Upgraded `testkit/scenarios/value-vault.toml` so the `solana-sbpf-asm`
  assembly and manifest artifacts check full generated-file equality through
  `matches_file`, while retaining focused substring checks for event lowering,
  syscall usage, storage layout, instruction names, and argument encodings.
- ValueVault now has scenario-declared source equality for `wasm-near` WAT and
  `solana-sbpf-asm` assembly/manifest. At this point, EVM Yul remained the
  only ValueVault source artifact still using source-shape checks.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target solana-sbpf-asm
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- At this point, ValueVault EVM Yul still used scenario-declared source-shape
  checks instead of complete golden equality.
- Local `just testkit` skips the ValueVault EVM runtime branch when Foundry
  `cast` is unavailable; CI covers that branch with Foundry installed.

Next step:

- Add a full ValueVault EVM Yul golden once selector hydration is available in
  the validation environment used to refresh the snapshot.

### Unified Testkit Wasm ValueVault Golden

Commit: feature commit for unified testkit Wasm ValueVault golden

Summary:

- Added `Examples/WasmNear/ValueVault.golden.wat` as the portable ValueVault
  WAT golden for the `wasm-near` EmitWat path.
- Upgraded `testkit/scenarios/value-vault.toml` so its `wasm-near` artifact
  checks full generated-source equality through `matches_file`, while keeping
  focused substring checks for important imports, exports, and event logging.
- ValueVault now has scenario-declared Wasm/NEAR WAT source equality in the
  unified testkit; its EVM Yul and Solana sBPF/manifest artifacts still use
  source-shape checks until their full golden snapshots are reviewed.

Validation run:

```sh
lake env lean --run Tests/EmitWatValueVault.lean
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target wasm-near
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- ValueVault EVM Yul and Solana sBPF/manifest comparisons were still
  scenario-declared source-shape checks instead of complete golden equality.
- Local `just testkit` skips the ValueVault EVM runtime branch when Foundry
  `cast` is unavailable; CI covers that branch with Foundry installed.

Next step:

- Add full ValueVault source goldens for EVM Yul and Solana sBPF/manifest once
  their emitted artifacts are stable enough to review as snapshots.

### Unified Testkit Wasm Counter Golden

Commit: feature commit for unified testkit Wasm Counter golden

Summary:

- Added `Examples/WasmNear/Counter.golden.wat` as the portable IR Counter WAT
  golden for the `wasm-near` EmitWat path.
- Moved the `wasm-near` Counter WAT equality check into
  `testkit/scenarios/counter.toml` through a scenario-declared
  `[[artifact]]` `matches_file` expectation.
- Counter now has target-source golden equality in the unified testkit for all
  three priority targets: `wasm-near` WAT, `evm` Yul, and
  `solana-sbpf-asm` assembly plus manifest.

Validation run:

```sh
lake env lean --run Tests/EmitWatSmoke.lean
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --target wasm-near
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- ValueVault still uses scenario-declared WAT/Yul substring checks because it
  does not yet have committed portable-source goldens.

Next step:

- Add source goldens for ValueVault once its cross-target emitted source shape
  is stable enough to review as a snapshot.

### Unified Testkit EVM Counter Golden

Commit: feature commit for unified testkit EVM Counter golden

Summary:

- Added `Examples/Evm/Counter.golden.yul` as the portable IR Counter Yul
  golden, separate from the older Lean SDK contract golden under
  `Examples/Evm/Contracts/`.
- Moved the EVM Counter Yul equality check into
  `testkit/scenarios/counter.toml` through a scenario-declared
  `[[artifact]]` `matches_file` expectation.
- Kept EVM runtime behavior in `testkit/harness-evm`; the harness now only
  publishes the generated `yul` artifact and the common scenario validator owns
  the source snapshot comparison.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --target evm
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- ValueVault still uses scenario-declared Yul substring checks because it does
  not yet have a committed portable-source golden.

Next step:

- Add portable-source goldens for the remaining stable testkit fixtures, then
  decide which old golden-only shell checks can be retired or moved to
  scheduled chain-authentic gates.

### Unified Testkit Unsupported Capability Diagnostics

Commit: feature commit for unified testkit diagnostic scenarios

Summary:

- Added `[[diagnostic]]` scenario expectations so testkit can run
  diagnostic-only scenarios without pretending they have runtime steps.
- Added `testkit/scenarios/unsupported-crosscall.toml`, which asserts that
  `solana-sbpf-asm` rejects the portable `crosscall.invoke` capability with
  the expected target/capability diagnostic.
- Added `Tests/TestkitSolanaCapabilityDiagnostic.lean` as the Lean-side
  diagnostic driver and wired `testkit/harness-solana` to execute it.
- Updated runner target filtering and summary output so diagnostic-only
  scenarios participate in `just testkit` but do not interfere with positive
  target runs.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
lake env lean --run Tests/TestkitSolanaCapabilityDiagnostic.lean
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario unsupported-crosscall
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --target evm
just testkit
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- The diagnostic scenario surface currently has one Solana capability case.
  More target/compiler diagnostics can move in as each harness exposes a
  small target-owned diagnostic driver.

Next step:

- Continue migrating deterministic artifact/source checks into scenario
  declarations, then decide which existing standalone diagnostic smokes should
  become additional `[[diagnostic]]` scenarios.

### Unified Testkit EVM Metadata Expectations

Commit: feature commit for unified testkit EVM metadata expectations

Summary:

- Added scenario-declared EVM metadata checks for Counter and ValueVault,
  covering target identity, artifact kind, fixture/source kind, declared
  capabilities, ABI entrypoint names, and bytecode-generation validation
  status.
- Removed the duplicated EVM harness metadata identity checks for
  `target`/`sourceKind`; `testkit/harness-evm` now reads metadata only for
  runtime selector dispatch.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml --workspace
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter --target evm
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target evm
scripts/i18n/check-sync.sh
git diff --check
```

Known limitations:

- Local ValueVault EVM execution still skips when Foundry `cast` is not on
  `PATH`; CI covers the full path where Foundry is installed.

Next step:

- Continue migrating the remaining shell-only golden/source checks that are
  deterministic into scenario declarations, while keeping live Foundry/Anvil
  deployment gates separate.

### Unified Testkit Scenario Target Validation

Commit: feature commit for unified testkit scenario target validation

Summary:

- Tightened scenario discovery so `testkit/core` rejects empty target ids,
  duplicate target ids, and artifact expectations that reference a target not
  declared in the scenario's `targets` list.
- Added a negative unit test proving stale or mistyped artifact target
  expectations fail during `discover_scenarios`, before any target harness
  runs.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
```

Known limitations:

- This only validates scenario configuration. Harness availability still
  depends on optional target tools such as `cast`, `sbpf`, and
  `solana-keygen`.

Next step:

- Continue moving pure artifact assertions out of target harnesses and into
  scenario declarations until the remaining M4 shell-gate duplication is
  isolated to live/network-authentic smoke tests.

### Unified Testkit Solana Harness Thinning

Commit: feature commit for Solana testkit artifact validation thinning

Summary:

- Removed duplicated Solana harness metadata and manifest semantic validators
  after their checks were moved into scenario-declared
  `[[artifact.json]]`/`[[artifact.toml]]` expectations.
- Kept Solana harness parsing of `manifest.toml` instruction tags because that
  is runtime dispatch data, not a review-only artifact expectation.
- Dropped the direct `serde_json` dependency from `testkit/harness-solana`.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo check --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana
cargo test --manifest-path testkit/Cargo.toml --workspace
scripts/i18n/check-sync.sh
git diff --check
just testkit
lake build
```

Known limitations:

- The scenario still needs optional `sbpf` and `solana-keygen` before Solana
  artifact expectations execute.
- Duplicated shell gates still exist; this only removes duplicated Solana
  harness-internal artifact semantics.

Next step:

- Continue moving pure artifact assertions out of target harnesses and then
  thin duplicated shell-only golden gates once `just testkit` covers them.

### Unified Testkit Structured Artifact Assertions

Commit: feature commit for unified testkit structured artifact assertions

Summary:

- Extended `testkit/core` artifact expectations with nested
  `[[artifact.json]]` and `[[artifact.toml]]` checks.
- Structured checks support dot paths plus array indexes, for example
  `validation.manifestGeneration` and `instruction[1].tag`.
- Added scenario-declared structured checks for Solana Counter and ValueVault
  artifact metadata, manifest target/program fields, instruction names, tags,
  capabilities, and manifest-generation validation status.
- Kept the Solana harness runtime parsing in place for instruction dispatch and
  metadata loading while moving the reviewable expectations into scenario TOML.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo check --manifest-path testkit/Cargo.toml
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
just testkit
```

Known limitations:

- Structured checks currently support equality and containment for JSON/TOML
  values. They do not yet provide unordered array matching or predicate filters
  such as `instruction[name=deposit]`.
- Target harnesses still own runtime-critical parsing and some semantic
  validation until those checks can be represented safely in the scenario
  language.

Next step:

- Migrate the remaining metadata/manifest semantic checks out of target
  harnesses where they are pure artifact expectations, then begin thinning
  duplicated shell-only golden gates.

### Unified Testkit M4 Artifact Expectations

Commit: feature commit for unified testkit artifact expectations

Summary:

- Added top-level `[[artifact]]` scenario expectations to `testkit/core`,
  with `target`, `name`, `matches_file`, and `contains` checks.
- Wired all three harnesses to publish named artifacts back into the common
  validator: `wat` for `wasm-near`, `yul`/`bytecode`/`metadata` for `evm`,
  and `sbpf-asm`/`manifest`/`metadata`/`idl`/`client` for
  `solana-sbpf-asm`.
- Moved the Solana Counter golden assembly and manifest comparisons into
  `testkit/scenarios/counter.toml`.
- Moved ValueVault's WAT/Yul/sBPF/manifest/metadata source-shape checks into
  `testkit/scenarios/value-vault.toml`, reducing hardcoded per-fixture
  behavior in the harnesses.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
just testkit
```

Known limitations:

- Artifact expectations currently cover whole-file equality and substring
  checks only. Structured JSON/TOML assertions still live in target harnesses
  and external validators.
- The local EVM ValueVault artifact checks run only when Foundry `cast` is
  available; CI covers that path.

Next step:

- Add structured artifact assertions for metadata and manifest fields, then
  migrate more of `scripts/portable/value-vault-smoke.sh` and
  `scripts/solana/counter-smoke.sh` into scenario-declared checks.

### Unified Testkit ValueVault Scenario

Commit: feature commit for unified testkit ValueVault scenario

Summary:

- Added typed scalar scenario args to `testkit/core`, so one TOML scenario can
  describe portable `u64`/`u32`/`bool` call parameters while each target
  harness performs its own ABI encoding.
- Extended `runtime/offline-host` with `--inputs-hex`, allowing the
  deterministic NEAR/Wasm host to run a stateful call sequence whose calls use
  different Borsh input payloads.
- Added `testkit/scenarios/value-vault.toml` covering
  `initialize -> deposit -> charge_fee -> release -> snapshot` plus balance
  and net-value queries.
- Wired ValueVault into `wasm-near` through `Tests/EmitWatValueVault.lean`,
  into `solana-sbpf-asm` through the existing ValueVault sBPF emitter plus
  Mollusk, and into `evm` through the revm harness when Foundry `cast` is
  available for selector hydration.

Validation run:

```sh
lake env lean --run Tests/EmitWatValueVault.lean
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target wasm-near
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target evm
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target solana-sbpf-asm
```

Known limitations:

- ValueVault's EVM branch still depends on `cast` because the current
  Contract SDK EVM path hydrates ABI selectors through Foundry; when `cast` is
  absent, the harness reports a target skip instead of hiding the dependency.
- Testkit validates call order and portable return values. Event payloads,
  account/log traces, gas/compute budgets, and live deployment remain in the
  existing target-specific gates.

Next step:

- Start M4 by migrating more golden-source and artifact checks into scenario
  fixtures while keeping Foundry/Anvil, Surfpool, near-sandbox, dargo, and leo
  as chain-authentic gates.

### Unified Testkit M3 Solana Harness

Commit: feature commit for unified testkit Solana harness

Summary:

- Added `testkit/harness-solana`, backed by `mollusk-svm`, as the third RFC
  0007 target harness for the portable Counter scenario.
- The Solana harness emits Counter sBPF assembly, checks the tracked golden
  assembly, validates `manifest.toml` and `proof-forge-artifact.json`, builds
  a standard `sbpf` ELF project, and executes the stateful
  `initialize -> get -> increment -> get` scenario through Mollusk.
- Extended the testkit runner with explicit harness skip reporting so
  optional chain toolchains such as `sbpf`/`solana-keygen` can be absent
  without masking failures in always-available targets.
- Extended `testkit/scenarios/counter.toml` so Counter now targets
  `wasm-near`, `evm`, and `solana-sbpf-asm`, with normalized trace parity
  across all executed targets.

Validation run:

```sh
scripts/solana/counter-smoke.sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo check --manifest-path testkit/Cargo.toml
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-harness-solana
just testkit
SBPF=/nonexistent-proof-forge-sbpf just testkit
```

Known limitations:

- The Solana testkit harness currently supports the portable IR Counter
  fixture only.
- `solana-sbpf-asm` is skipped with a clear reason when `sbpf` or
  `solana-keygen` is unavailable.
- This is a Mollusk in-process runtime gate, not a Surfpool/Web3 live
  deployment gate.

Next step:

- Add the portable ValueVault scenario to the testkit and run it across the
  targets whose capability plans support the fixture.

### Unified Testkit M2 Trace Parity

Commit: feature commit for unified testkit trace parity

Summary:

- Added a normalized observable trace comparison layer to `testkit/core`.
- The runner now executes every selected target for a scenario, validates each
  target's declared expectations, then asserts cross-target parity for call
  order and portable return values.
- EVM ABI return words and NEAR typed host returns are compared through the
  scenario's expected portable type, so target-specific hex encodings do not
  become false parity failures.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all -- --check
cargo test --manifest-path testkit/Cargo.toml -p proof-forge-testkit-core
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run
```

Known limitations:

- Trace parity currently covers call order and return values only; scenario
  state reads, events, errors, and resource budgets are still follow-up schema
  work before testkit M3/M4.
- `solana-sbpf-asm` is not yet wired into testkit; it remains the M3 harness.

Next step:

- Add `harness-solana` on top of the existing Mollusk templates so the Counter
  scenario runs across `evm`, `wasm-near`, and `solana-sbpf-asm`.

### Unified Testkit M2 EVM Harness

Commit: feature commit for unified testkit EVM harness

Summary:

- Added `testkit/harness-evm`, backed by `revm`, as the second target harness
  for RFC 0007.
- Extended `testkit/scenarios/counter.toml` so the same portable Counter
  scenario runs against both `wasm-near` and `evm`.
- The EVM harness emits portable IR Counter runtime bytecode and artifact
  metadata, loads selectors from metadata, installs the runtime bytecode into
  an in-memory EVM account, and executes each scenario call as a committed EVM
  transaction with sequential nonces.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo check --manifest-path testkit/Cargo.toml
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --target evm
just testkit
```

Known limitations:

- The EVM harness currently covers the portable IR Counter fixture only.
- It validates scenario-level behavior through `revm`; Foundry and Anvil remain
  the mature EVM runtime/deploy gates for broader contracts and live local
  chain behavior.
- Cross-target comparison is still implicit through shared expectations; an
  explicit trace-diff layer should be added next.

Next step:

- Add a target trace comparison report so `wasm-near` and `evm` outcomes are
  compared directly for the shared scenario, then wire the first Solana/Mollusk
  or sBPF runner into the same testkit interface.

### Unified Testkit M1 Skeleton

Commit: feature commit for unified testkit M1 skeleton

Summary:

- Added the RFC 0007 `testkit/` Rust workspace with core scenario parsing,
  NEAR harness wiring, and the `proof-forge-testkit` runner.
- Added `testkit/scenarios/counter.toml` as the first declarative scenario.
- Wired `just testkit`, `just testkit-list`, and the GitHub Actions
  `build-test` job.

Validation run:

```sh
cargo fmt --manifest-path testkit/Cargo.toml --all
cargo check --manifest-path testkit/Cargo.toml
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
just testkit
```

Known limitations:

- This is the M1 `wasm-near` slice only. It wraps the existing deterministic
  `runtime/offline-host`; EVM/revm and Solana/Mollusk are not wired yet.
- Cross-target equivalence assertions start in M2 after the EVM harness lands.

Next step:

- Add `harness-evm` on revm, load emitted runtime bytecode plus
  `.evm-methods`, and compare the Counter observable trace against
  `wasm-near`.

## 2026-07-02

### EVM StorageSlotPlan ToYul Slice

Commit: feature commit for `StorageSlotPlan -> ToYul`

Summary:

- Added `ProofForge.Backend.Evm.ToYul` as the first plan-to-Yul module in the
  EVM semantic-plan migration.
- Moved scalar storage slot expressions and map value/presence slot expressions
  through `StorageSlotPlan -> ToYul` while keeping the existing `IR.lean`
  facade and generated Yul behavior stable.
- Recorded the remaining EVM semantic-plan migration TODO in the implementation
  backlog, including `Validate`, `Lower`, `ToYul`, `Metadata`,
  `EntrypointPlan`, `EventPlan`, `CrosscallPlan`, and `MetadataPlan` stages.

Validation run:

```sh
lake build ProofForge.Backend.Evm.ToYul ProofForge.Backend.Evm.IR
just evm-plan
just evm-smoke map
just evm-smoke typed-map
just evm-smoke typed-storage
just check
just diff-check
```

Known limitations:

- Array slots, struct-array field slots, expression plans, statement plans,
  entrypoint planning, events, crosscalls, and artifact metadata still need to
  move behind semantic plan boundaries.
- `ProofForge.Backend.Evm.IR` remains the public compatibility facade until the
  migrated plan paths have complete validation coverage.

Next step:

- Extend `StorageSlotPlan -> ToYul` to array and struct-array slot plans, then
  begin extracting expression and statement planning out of `IR.lean`.

### Target-Driven EVM Module Plan

Commit: feature commit for EVM capability-aware module planning

Summary:

- Extended `ProofForge.Backend.Evm.Plan` with a target-driven `ModulePlan`
  that preserves the resolved `Target.CapabilityPlan` for the EVM compiler
  target.
- Moved EVM storage/helper planning behind `buildModulePlan`, so the backend
  can consume target-resolved capabilities instead of rediscovering helper
  requirements directly during final Yul lowering.
- Added `lowerModuleWithPlan` in the EVM backend. The public `lowerModule`
  path now builds an EVM module plan first, then renders through the existing
  Yul AST path.
- Extended `Tests/EvmPlan.lean` to verify target id, supported and unsupported
  capabilities, helper requirements, storage layout, map assign-op helper
  requirements, and explicit rejection of a non-EVM target plan.

Validation run:

```sh
lake build ProofForge.Backend.Evm.Plan
lake build ProofForge.Backend.Evm.IR
lake env lean --run Tests/EvmPlan.lean
```

Known limitations:

- ABI dispatch, event plans, crosscall plans, constructor metadata, and artifact
  metadata still need to move behind `ModulePlan`.
- The generated Yul is intentionally unchanged in this slice.

Next step:

- Move storage-path Yul expression construction to consume `StorageSlotPlan`
  directly, then promote ABI/event/crosscall metadata into `ModulePlan`.

### Solana sBPF And SDK PR Merge

Commit: merge commit for PR #2 (`Solana supprot`)

Summary:

- Merged the Solana sBPF assembly backend work into the current EVM-focused
  mainline.
- Added Solana backend modules for sBPF assembly AST/printer, state layout,
  register allocation, syscalls, manifests, packages, and SDK extension
  artifacts.
- Added CLI modes for emitting Solana sBPF assembly, Solana ELF artifacts,
  Solana SDK assembly, and Solana-focused fixture artifacts.
- Added Solana examples, diagnostics, SDK tests, target-routing tests, and
  Solana smoke scripts.
- Resolved RFC numbering against the existing EVM semantic plan RFC: EVM keeps
  RFC 0004, Solana sBPF is RFC 0005, and the multi-chain Token SDK is RFC 0006.

Validation run:

```sh
just solana-light
just docs-check
just check
python3 -m json.tool scripts/i18n/manifest.json >/dev/null
git diff --check
```

Known limitations:

- Solana Mollusk/Surfpool runtime smoke scripts remain gated on local external
  tools such as Mollusk, Surfpool, Node, and npm.
- The merge preserves EVM semantic-plan work; deeper integration between the
  new Solana SDK route and the portable multi-chain planning layer remains
  follow-up work.

Next step:

- Run the available Solana smoke scripts on a machine with the Solana/sBPF
  toolchain installed, then decide which Solana surface should be promoted from
  research to CI-tracked baseline.

### EVM Semantic Plan Storage Slice

Commit: feature commit for the first EVM semantic plan slice

Summary:

- Added `ProofForge.Backend.Evm.Plan` as the first explicit semantic planning
  layer between portable IR and target-specific Yul lowering.
- Modeled storage layout entries, scalar storage slot plans, map value slot
  plans, nested map value slot plans, map presence slot plans, and helper
  requirements without changing generated Yul output.
- Added `Tests/EvmPlan.lean` to lock scalar/map/nested-map slot planning
  against the existing `EvmMapProbe` and `EvmTypedMapProbe` fixtures.
- Added `just evm-plan` and a GitHub Actions step so the plan slice is checked
  independently before broader EVM smokes.

Validation run:

```sh
just evm-plan
```

Known limitations:

- The existing Yul generator still owns actual rendering; this slice creates
  the semantic structures and tests that later lowering can migrate onto.
- The first plan slice covers scalar slots and consecutive `mapKey` paths only.
  Arrays, structs, ABI dispatch, event/crosscall helpers, and artifact metadata
  planning remain follow-up work.

Next step:

- Refactor the current EVM storage path lowering to consume plan nodes while
  preserving golden Yul output, then broaden the plan to arrays and flat
  storage structs.

### EVM Nested Map Storage Paths

Commit: feature commit for EVM nested map storage paths

Summary:

- Extended EVM portable IR storage-path type checking so map-backed state
  accepts one or more consecutive `mapKey` segments when every key expression
  matches the map key type.
- Lowered nested map value slots by folding the existing Solidity-style
  mapping helper, for example `keccak256(inner || keccak256(outer || slot))`.
- Lowered nested map write and compound assignment paths so the final key's
  ProofForge-managed presence slot is marked alongside the value slot.
- Extended `EvmMapProbe` with U64 nested map path lifecycle and dynamic-key
  coverage, and extended `EvmTypedMapProbe` with U32 nested map path coverage
  plus dispatcher range-guard checks.
- Kept mixed map/aggregate storage paths as explicit diagnostics rather than
  silently lowering partial paths.

Validation run:

```sh
lake build proof-forge
just evm-smoke map
just evm-smoke typed-map
just evm-diagnostics
just evm-coverage
just docs-check
just diff-check
```

Known limitations:

- Nested map paths currently model EVM nested mapping slots over a single
  declared `Map<K, V, N>` state by using consecutive keys of the same key type.
- Mixed map/array/struct aggregate paths and non-word or aggregate map
  key/value shapes remain explicit unsupported surfaces.

Next step:

- Continue shrinking the remaining EVM storage surface around aggregate storage
  paths and broader ABI-facing storage-backed values.

### EVM Nested Fixed-Array Event Aggregates

Commit: feature commit for EVM nested fixed-array event aggregates

Summary:

- Extended portable IR EVM event signature generation so nested fixed arrays are
  rendered recursively as Solidity-style event types such as `uint64[2][2]` and
  `(uint64,uint64)[2][2]`.
- Extended event data-word lowering so nested fixed-array event fields flatten
  recursively into ABI-style words when their leaves are scalar words or flat
  structs.
- Added `EventProbe` entrypoints for `MatrixEvent(uint64[2][2])`,
  `PairMatrixEvent((uint64,uint64)[2][2])`,
  `IndexedMatrix(uint64[2][2],uint64)`, and
  `IndexedPairMatrix((uint64,uint64)[2][2],uint64)`.
- Tightened diagnostics so nested fixed arrays whose leaves are unsupported or
  non-flat still fail before Yul generation with explicit errors.

Validation run:

```sh
just evm-smoke event
```

- Generated reproducible EventProbe Yul and runtime bytecode with
  `solc --strict-assembly`.
- Validated new selector/event ABI metadata through
  `scripts/evm/validate-artifact-metadata.py`.
- Foundry ran 24 EventProbe recorded-log tests, including nested scalar and
  nested flat-struct fixed-array data flattening plus indexed aggregate topic
  hashing.

Known limitations:

- Aggregate event fields with unsupported leaves, non-flat struct leaves, or
  richer first-class event declarations remain explicit unsupported surfaces for
  portable IR EVM.

Next step:

- Continue shrinking the EVM aggregate surface around remaining storage and ABI
  edge cases while keeping unsupported shapes diagnostic-first.

### EVM Entrypoint ABI Artifact Metadata

Commit: `feat: record EVM entrypoint ABI metadata`

Summary:

- Portable IR EVM bytecode artifacts and deploy manifests now include
  structured `abi.entrypoints` metadata for selector-facing entrypoints.
- Entrypoint metadata records the Solidity-style selector signature, parameter
  ABI types, flattened calldata word types/counts, return ABI type, flattened
  return word types/counts, and preserves the original IR type names.
- `scripts/evm/validate-artifact-metadata.py` now validates entrypoint
  selectors with `cast sig`, while `scripts/evm/abi-aggregate-ir-smoke.sh`
  locks aggregate calldata/return word layouts through
  `--expect-entrypoint-abi`.

Validation run:

```sh
lake build proof-forge
scripts/evm/abi-aggregate-ir-smoke.sh
```

Known limitations:

- The metadata describes the current static ABI-word surface. Dynamic ABI
  values remain an explicit unsupported surface for portable IR EVM.

Next step:

- Continue tightening metadata validation around deployment-facing manifests
  and expand first-class ABI schema coverage as the portable IR grows.

### EVM Event ABI Artifact Metadata

Commit: `feat: record EVM event ABI metadata`

Summary:

- Portable IR EVM bytecode artifacts and deploy manifests now include
  `abi.events` entries for emitted events.
- Event metadata records the Solidity-style event signature, `topic0`, indexed
  fields, non-indexed data fields, flattened ABI word types, and per-field
  topic/data encoding.
- `scripts/evm/validate-artifact-metadata.py` validates event topics with
  `cast keccak`, and `scripts/evm/event-ir-smoke.sh` now locks all EventProbe
  event signatures through `--expect-event`.

Validation run:

```sh
lake build proof-forge
scripts/evm/event-ir-smoke.sh
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
```

Known limitations:

- Event metadata is emitted for portable IR modules; richer first-class event
  declarations remain an explicit unsupported surface.

Next step:

- Continue promoting ABI-facing metadata from smoke fixtures into a stable
  target manifest schema shared by EVM deployment tooling.

### EVM Anvil Chain Profile Deploy-Run Validation

Commit: `feat: validate Anvil chain profiles`

Summary:

- Added `anvil-local` as a lookup-only EVM chain profile for local Foundry
  Anvil deployments on chain id `31337`.
- `scripts/evm/anvil-deploy-smoke.sh` now regenerates Counter with
  `--evm-chain-profile anvil-local` by default when using the default Anvil
  chain id.
- `proof-forge-deploy-run.json` now links the deploy manifest chain profile,
  and `scripts/evm/validate-deploy-run.py` validates that the profile,
  deployment chain id, actual Anvil chain id, and creation transaction evidence
  agree.

Validation run:

```sh
lake build ProofForge.Target.Registry
lake env lean --run Tests/TargetRegistry.lean
python3 -m py_compile scripts/evm/validate-deploy-run.py
bash -n scripts/evm/anvil-deploy-smoke.sh
scripts/evm/anvil-deploy-smoke.sh
```

Known limitations:

- `anvil-local` is intentionally a local validation profile; it does not imply
  public RPC broadcast support.

Next step:

- Promote profile-aware deploy-run generation into a first-class deploy command
  that can consume any supported EVM chain profile.

### EVM Creation Transaction Deploy-Run Artifact

Commit: `feat: record EVM creation transactions`

Summary:

- Anvil deploy smoke now records the `eth_getTransactionByHash` creation
  transaction JSON alongside the `cast send --create` receipt.
- `proof-forge-deploy-run.json` links that creation transaction artifact with
  path, byte size, and SHA-256 metadata.
- `scripts/evm/validate-deploy-run.py` now validates that the creation
  transaction hash, sender, null `to`, block metadata, and initcode `input`
  match the deploy receipt and generated `.init.bin`.

Validation run:

```sh
python3 -m py_compile scripts/evm/validate-deploy-run.py
bash -n scripts/evm/anvil-deploy-smoke.sh
scripts/evm/anvil-deploy-smoke.sh
just evm-all
```

Known limitations:

- This records a local Anvil creation transaction and receipt, not a signed raw
  transaction artifact or public RPC broadcast workflow.

Next step:

- Promote the deploy-run artifact shape into a first-class deploy/broadcast
  command that consumes `proof-forge-deploy.json`.

### EVM ABI Method Signature Metadata

Commit: `feat: record EVM method signatures`

Summary:

- SDK `.evm-methods` sidecars now preserve the original Solidity method
  signature in `abi.methods[].signature` for EVM artifact metadata and deploy
  manifests.
- Manual `--method selector:fn:argc:view|update` specs remain supported; those
  method entries use `null` signature metadata.
- EVM metadata validators now check selector shape, duplicate method and
  entrypoint selectors, generated Yul function names, signature syntax, and
  signature/arg-count consistency.
- SDK example builds and the Anvil deploy smoke now require method signatures
  in metadata validation.

Validation run:

```sh
lake build proof-forge
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
bash -n scripts/evm/build-examples.sh
bash -n scripts/evm/anvil-deploy-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/anvil-deploy-smoke.sh
```

Known limitations:

- The validators check selector format and method signature metadata, while the
  selector derivation itself still comes from Foundry `cast sig` during
  compilation.

Next step:

- Continue strengthening ABI-facing artifact checks and close remaining
  deploy/broadcast metadata gaps.

### EVM Constructor Diagnostic Coverage

Commit: `test: cover EVM constructor CLI diagnostics`

Summary:

- Extended `scripts/evm/diagnostic-smoke.sh` beyond portable IR diagnostics to
  cover EVM constructor artifact-boundary CLI diagnostics.
- The gate now locks unsupported dynamic constructor ABI types, missing
  constructor values, duplicate typed values, mixed typed/raw constructor
  sources, integer overflow, and malformed address-width inputs.
- This turns the constructor value negative cases from one-off manual checks
  into CI-tracked `just evm-diagnostics` coverage.

Validation run:

```sh
bash -n scripts/evm/diagnostic-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Constructor value encoding is still intentionally limited to static one-word
  ABI types; dynamic constructor ABI values remain unsupported with explicit
  diagnostics.

Next step:

- Continue closing the remaining EVM ABI/backend gaps, especially dynamic ABI
  surfaces and deploy/broadcast artifacts.

### EVM Typed Constructor Value Encoding

Commit: `feat: encode EVM constructor values`

Summary:

- Added `--evm-constructor-arg <name=value>` for EVM bytecode modes.
- Typed constructor args are ABI-encoded from the declared
  `--evm-constructor-param <name:type>` schema and support `uint256`, `uint64`,
  `uint32`, `bool`, `bytes32`, and `address`.
- Constructor arg metadata now records whether the ABI blob came from typed CLI
  args or raw `--evm-constructor-args-hex`.
- Validators accept and can assert constructor arg source, and Anvil deploy
  smoke now defaults to typed `initial=123` input for Counter.
- CLI validation rejects missing typed values, duplicate typed values,
  out-of-range integer values, and mixing typed values with raw constructor hex.

Validation run:

```sh
lake build proof-forge
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py scripts/evm/validate-deploy-run.py
bash -n scripts/evm/anvil-deploy-smoke.sh
lake env proof-forge --evm-bytecode --root . --module contract --evm-constructor-param initial:uint256 --evm-constructor-arg initial=123 ...
python3 scripts/evm/validate-artifact-metadata.py --expect-constructor-args-source=--evm-constructor-arg ...
python3 scripts/evm/validate-deploy-manifest.py --expect-constructor-args-source=--evm-constructor-arg ...
```

Known limitations:

- Constructor value encoding is limited to static one-word ABI types; dynamic
  constructor ABI types are still unsupported.
- This still emits deployable initcode and local Anvil deploy-run artifacts,
  not signed transaction/broadcast artifacts for public RPC networks.

Next step:

- Add first-class EVM deploy/broadcast commands that consume the deploy
  manifest, or continue closing remaining non-dynamic EVM backend gaps.

### EVM Constructor ABI Schema Metadata

Commit: `feat: record EVM constructor ABI schema`

Summary:

- Added `--evm-constructor-param <name:type>` for EVM bytecode modes.
- Constructor params are recorded under `abi.constructor.params` in both
  `proof-forge-artifact.json` and `proof-forge-deploy.json` using static
  32-byte ABI-word metadata.
- Validators now check constructor ABI schema shape, supported static-word
  types, expected parameters, and constructor-argument byte length.
- The Anvil deploy smoke now regenerates Counter with
  `--evm-constructor-param initial:uint256`, records `constructorAbi` in
  `Counter.proof-forge-deploy-run.json`, and validates it against the deploy
  manifest.

Validation run:

```sh
lake build
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py scripts/evm/validate-deploy-run.py
bash -n scripts/evm/anvil-deploy-smoke.sh
lake env proof-forge --evm-bytecode --root . --module contract --evm-constructor-param initial:uint256 --evm-constructor-args-hex 0x000000000000000000000000000000000000000000000000000000000000007b ...
scripts/evm/anvil-deploy-smoke.sh
just check
just evm-all
just psy-golden-sources
git diff --check
```

Known limitations:

- ProofForge records and validates static constructor ABI schema, but does not
  yet parse typed constructor values or ABI-encode them from CLI inputs.
- Dynamic constructor ABI types remain out of scope for the current EVM schema
  slice.

Next step:

- Add typed constructor value parsing/encoding or move to a first-class EVM
  deploy/broadcast command that consumes the deploy manifest.

### Just-Based CI Command Entry

Commit: feature commit for just-based CI command entry

Summary:

- Kept target-specific implementation logic in `scripts/`, but made the root
  `justfile` the shared developer and CI command entrypoint.
- Installed pinned `just` 1.48.0 in GitHub Actions and replaced duplicated CI
  command blocks with existing recipes such as `just build`,
  `just target-registry`, `just docs-check`, `just psy-golden-sources`, and
  `just evm-smoke <fixture>`.
- Preserved separate GitHub Actions steps for EVM/Psy gates so CI failures stay
  easy to locate.
- Updated README, development standards, validation gates, and Chinese mirrors
  to document the split between `just` orchestration and underlying scripts.

Validation run:

```sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); puts "workflow yaml ok"'
just --list
just check
just psy-golden-sources
just --dry-run <each CI-tracked just recipe>
git diff --check
```

Known limitations:

- CI now requires `just` installation before invoking common gate recipes.
- Direct scripts remain supported because they are still the target-specific
  implementation surface.

Next step:

- Consider grouping future target recipes by imported `just` modules if the
  root `justfile` becomes hard to scan.

### EVM Constructor Args Initcode Tail

Commit: feature commit for EVM constructor args initcode tail

Summary:

- Added `--evm-constructor-args-hex <hex>` to EVM bytecode modes.
- The CLI now normalizes ABI-encoded constructor args, appends them to
  generated `.init.bin` creation bytecode, and records the argument blob in
  `proof-forge-deploy.json` with hex, byte size, SHA-256, and source metadata.
- Updated EVM metadata, deploy-manifest, and deploy-run validators so they
  parse the initcode header as `header + runtime + constructorArgs` instead of
  assuming the initcode ends at the runtime bytecode.
- Extended `scripts/evm/anvil-deploy-smoke.sh` so CI deploys Counter initcode
  with a deterministic non-empty constructor-argument tail by default and
  records those args in `Counter.proof-forge-deploy-run.json`.

Validation run:

```sh
lake build
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py scripts/evm/validate-deploy-run.py
scripts/evm/build-examples.sh
scripts/evm/anvil-deploy-smoke.sh
```

Result:

- No-argument SDK example builds still emit valid metadata and deploy
  manifests.
- Counter Anvil deploy smoke regenerated `Counter.init.bin` with a 32-byte
  constructor argument blob (`0x...007b`), deployed it with `cast send
  --create`, and validated that the deployed runtime code still matches
  `Counter.bin`.
- The deploy-run artifact records the constructor args and the Counter
  lifecycle still returned `0`, then `99`, `100`, and `99`.

Known limitations:

- Constructor args are accepted as an explicit ABI-encoded hex blob; ProofForge
  does not yet generate constructor ABI schemas or encode named constructor
  parameters from IR.
- This still validates on local Anvil, not a live public RPC broadcast.

Next step:

- Add a first-class deployment command or broadcast artifact that consumes the
  deploy manifest, selected chain profile, private-key/wallet configuration,
  and constructor args without shell-script-specific glue.

### EVM Anvil Deploy-Run Smoke

Commit: `feat: validate EVM initcode deployment on Anvil`

Summary:

- Added `scripts/evm/anvil-deploy-smoke.sh`, which starts a local Anvil chain
  and deploys generated `Counter.init.bin` with `cast send --create`.
- The smoke records the creation transaction receipt, deployed address, local
  Anvil network id, referenced deploy manifest, initcode, runtime bytecode, and
  Counter lifecycle call results in
  `build/anvil-deploy-smoke/Counter.proof-forge-deploy-run.json`.
- Added `scripts/evm/validate-deploy-run.py` to validate deploy-run artifacts,
  including receipt status, transaction/deployer consistency, deployed runtime
  code hash/size, and `get`/`set`/`increment`/`decrement` JSON-RPC behavior.
- Wired the new smoke into `just evm-anvil-deploy`, `just evm-all`, and CI.

Validation run:

```sh
python3 -m py_compile scripts/evm/validate-deploy-run.py
scripts/evm/anvil-deploy-smoke.sh
```

Result:

- Anvil chain id `31337` started locally.
- `Counter.init.bin` deployed to
  `0x5fbdb2315678afecb367f032d93f642f64180aa3` with a successful creation
  receipt.
- The on-chain deployed code matched `build/evm/Counter.bin`.
- Counter JSON-RPC lifecycle returned `0`, then `99`, `100`, and `99`.

Known limitations:

- This is a local Anvil deploy-run artifact, not a live public RPC broadcast.
- Constructor arguments remain empty.
- Explorer verification and wallet UX are still future work.

Next step:

- Extend deploy-run generation toward chain-profile-aware live RPC deployment
  and constructor argument encoding, while keeping Anvil as the deterministic
  CI smoke.

### EVM Chain Profile Deploy Metadata

Commit: `feat: record EVM chain profile deploy metadata`

Summary:

- Added `--evm-chain-profile <id>` for EVM bytecode modes.
- Resolved EVM chain profiles from the target registry and recorded the selected
  profile in `proof-forge-deploy.json`, including profile id, chain id, RPC
  URLs, native gas symbol, explorer, verifier, and notes.
- Extended the deploy `deployment` block with profile id, chain id, network
  name, RPC URLs, explorer/verifier metadata, and explicit
  `broadcastArtifact: null`.
- Strengthened EVM metadata/deploy validators so selected profiles must match
  deployment fields and unselected profiles remain explicit `null`/empty
  fields.
- Updated `AbiScalarProbe` EVM smoke to validate
  `robinhood-chain-testnet` and chain id `46630`.

Validation run:

```sh
lake build
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture AbiScalarProbe --expect-source-kind portable-ir --expect-chain-profile robinhood-chain-testnet --expect-chain-id 46630 build/ir/AbiScalarProbe.proof-forge-deploy.json
```

Result:

- `AbiScalarProbe.proof-forge-deploy.json` records
  `chainProfile.id: robinhood-chain-testnet`, `deployment.profileId:
  robinhood-chain-testnet`, and `deployment.chainId: 46630`.
- Foundry ABI scalar smoke still ran 2 runtime tests successfully.

Known limitations:

- The manifest is still a deployment plan only.
- Transaction signing, Foundry/Anvil broadcast JSON, deployed address recording,
  and explorer verification remain future work.

Next step:

- Generate a Foundry script or broadcast-oriented artifact from the deploy
  manifest, then validate it against Anvil without relying on live RPC.

### EVM Deploy Initcode Artifacts

Commit: `feat: emit EVM deploy initcode artifacts`

Summary:

- Extended every EVM bytecode build to emit a sibling `.init.bin` deployable
  creation bytecode artifact in addition to the existing runtime `.bin`.
- Updated `proof-forge-artifact.json` and `proof-forge-deploy.json` so EVM
  metadata records the initcode artifact, `creation.mode: init-code`, and
  `validation.initCodeGeneration: passed`.
- Strengthened both EVM metadata validators to parse the initcode
  `PUSH/CODECOPY/RETURN` header and prove it copies and returns the exact
  referenced runtime bytecode artifact.
- Refreshed English/Chinese EVM metadata docs, validation gates, and backlog
  notes to distinguish deployable initcode from future transaction broadcast
  manifests.

Validation run:

```sh
lake build
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/build-examples.sh
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture AbiScalarProbe --expect-source-kind portable-ir build/ir/AbiScalarProbe.proof-forge-deploy.json
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture Counter.lean --expect-source-kind lean-sdk build/evm/Counter.proof-forge-deploy.json
scripts/evm/foundry-smoke.sh
```

Result:

- `AbiScalarProbe` generated `AbiScalarProbe.init.bin` and passed Foundry
  scalar ABI runtime checks.
- SDK examples generated `.init.bin` artifacts for Counter, ArrayExample,
  SimpleToken, ERC20, Ownable, Pausable, and VerifiedVault; the validator
  accepted both small and multi-byte-length runtimes.
- Foundry ran 5 runtime smoke tests, including deploying the generated Counter
  `.init.bin` through EVM `create` and then running the Counter lifecycle.

Known limitations:

- Constructor arguments are still empty.
- Chain profile selection, signed/raw transaction generation, broadcast JSON,
  deployed address recording, and explorer verification remain future work.
- Most Foundry smoke coverage still installs runtime bytecode with `vm.etch`
  for fast runtime checks; Counter now also has a real initcode `create` path.

Next step:

- Continue toward real deployment manifests by adding chain-profile selection
  and a Foundry/Anvil broadcast artifact, or return to the remaining EVM IR
  unsupported surfaces such as dynamic ABI values.

### EVM IR Hash Aggregate ABI Leaves

Commit: `test: cover EVM hash aggregate ABI leaves`

Summary:

- Extended `EvmAbiAggregateProbe` with `HashPair` and `Hash` fixed-array ABI
  entrypoints:
  `echo_hash_pair((bytes32,bytes32))`,
  `make_hash_pair(bytes32,bytes32)`, `pick_hash(bytes32[2])`, and
  `make_hash_array(bytes32,bytes32)`.
- Validated that `Hash` leaves flatten as Solidity `bytes32` words inside flat
  structs and fixed arrays for ABI-facing calldata and return data.
- Refreshed the `EvmAbiAggregateProbe` golden Yul, selector metadata checks,
  Foundry ABI decode checks, coverage table, English/Chinese EVM target docs,
  validation gates, and backlog notes.

Validation run:

```sh
scripts/evm/abi-aggregate-ir-smoke.sh
```

Result:

- `EvmAbiAggregateProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 3 ABI aggregate tests, including `HashPair` calldata/return-data,
  `bytes32[2]` calldata/return-data, and short `bytes32[2]` calldata rejection.

Known limitations:

- Dynamic ABI values remain outside the portable IR EVM v0 surface.
- Rich ABI tuples beyond flat word aggregates remain explicit future work.
- Storage-backed aggregate ABI returns stay covered only by the fixed word-array
  and flat struct-array cases in the dedicated storage probes.

Next step:

- Continue shrinking aggregate ABI/crosscall gaps, or decide whether richer
  dynamic ABI values require a portable IR extension first.

## 2026-07-01

### EVM IR Typed Scalar Event Fields

Commit: feature commit for EVM IR typed scalar event fields

Summary:

- Extended `EventProbe` with typed scalar event entrypoints:
  `emit_typed_scalar_event(bool,uint32,bytes32)` and
  `emit_indexed_typed_scalar_event(bool,uint32,bytes32,uint256)`.
- Validated `Bool`, `U32`, and `Hash` event data fields and indexed topics,
  including `Bool`/`U32` calldata range guards before the event lowering runs.
- Refreshed `EventProbe` golden Yul, metadata selector checks, Foundry
  recorded-log checks, coverage, English/Chinese EVM target docs, validation
  gates, and implementation backlog notes.

Validation run:

```sh
scripts/evm/event-ir-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 20 EventProbe tests, including typed scalar data/topic checks and
  malformed `Bool`/`U32` calldata rejection.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to another unsupported EVM capability surface.

### EVM IR Multi-Topic Indexed Events

Commit: feature commit for EVM IR multi-topic indexed events

Summary:

- Extended `EventProbe` with two scalar indexed-event entrypoints:
  `emit_two_indexed_event(uint256,uint256,uint256)` and
  `emit_three_indexed_event(uint256,uint256,uint256,uint256)`.
- Validated that `eventEmitIndexed` generates `log3` for two indexed fields and
  `log4` for three indexed fields, with ordered scalar topics and one
  non-indexed data word.
- Refreshed `EventProbe` golden Yul, metadata selector checks, Foundry
  recorded-log checks, coverage, English/Chinese EVM target docs, validation
  gates, and implementation backlog notes.

Validation run:

```sh
scripts/evm/event-ir-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 17 EventProbe tests, including `log3` and `log4` scalar indexed
  event coverage.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to another unsupported EVM capability surface.

### EVM IR Storage-Backed Event Fixed Arrays

Commit: feature commit for EVM IR storage-backed event fixed arrays

Summary:

- Extended `EventProbe` with `storedValues` and `storedPairs` fixed storage
  arrays plus four entrypoints:
  `emit_storage_array_event(uint256,uint256)`,
  `emit_storage_pair_array_event(uint256,uint256,uint256,uint256)`,
  `emit_indexed_storage_array_event(uint256,uint256,uint256)`, and
  `emit_indexed_storage_pair_array_event(uint256,uint256,uint256,uint256,uint256)`.
- Validated that storage array reads and storage array struct field reads can
  feed scalar fixed-array and fixed-array-of-flat-struct event aggregates.
- Refreshed `EventProbe` golden Yul, metadata selector checks, Foundry
  recorded-log checks, coverage, English/Chinese EVM target docs, validation
  gates, and implementation backlog notes.

Validation run:

```sh
scripts/evm/event-ir-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 15 EventProbe tests, including storage-backed fixed-array data
  flattening and storage-backed fixed-array indexed topic hashing.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to another unsupported EVM capability surface.

### EVM IR Storage-Backed Event Aggregates

Commit: feature commit for EVM IR storage-backed aggregate events

Summary:

- Extended `EventProbe` with a flat scalar storage struct state and two
  entrypoints:
  `emit_storage_pair_event(uint256,uint256)` and
  `emit_indexed_storage_pair_event(uint256,uint256,uint256)`.
- Validated the existing storage-backed event lowering path where a whole flat
  struct is written with `storageScalarWrite`, read with `storageScalarRead`,
  flattened into non-indexed event data words, or flattened and hashed into an
  indexed aggregate topic.
- Refreshed `EventProbe` golden Yul, metadata selector checks, Foundry
  recorded-log checks, coverage, English target docs, Chinese target docs,
  validation gates, and implementation backlog notes.

Validation run:

```sh
scripts/evm/event-ir-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 11 EventProbe tests, including `StoragePairEvent` data flattening
  from storage reads and `IndexedStoragePair` topic hashing from storage reads.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to another unsupported EVM capability surface.

### EVM IR Indexed Aggregate Event Topics

Commit: feature commit for EVM IR indexed aggregate event topics

Summary:

- Extended `eventEmitIndexed` lowering so supported aggregate indexed fields no
  longer pretend to be scalar topics. Flat structs and fixed arrays whose
  elements are flat structs now flatten to ABI-style 32-byte words and use
  `keccak256` over those words as the indexed topic.
- Preserved direct scalar indexed topics for `U32`, `U64`, `Bool`, and `Hash`.
- Extended `EventProbe` with `emit_indexed_pair_event`,
  `emit_indexed_array_event`, and `emit_indexed_pair_array_event`, covering
  `IndexedPair((uint64,uint64),uint64)` and
  `IndexedArray(uint64[2],uint64)` and
  `IndexedPairArray((uint64,uint64)[2],uint64)`.
- Replaced the old flat-aggregate indexed diagnostic with a nested aggregate
  indexed diagnostic, so unsupported event shapes still fail explicitly instead
  of lowering partially.
- Refreshed golden Yul, artifact metadata selector checks, Foundry recorded-log
  checks, EVM diagnostics, coverage, English target docs, Chinese target docs,
  and implementation backlog notes.

Validation run:

```sh
lake build
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Result:

- `EventProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 9 EventProbe tests, including scalar indexed topics, flat struct
  indexed topic hashes, scalar fixed-array indexed topic hashes,
  fixed-array-of-flat-struct indexed topic hashes,
  aggregate data flattening, selector dispatch, and unknown-selector revert
  behavior.

Known limitations:

- Indexed event fields remain limited to three fields after the signature topic.
- Nested fixed arrays, non-flat structs, and unsupported aggregate leaves remain
  explicit diagnostics for event fields.
- First-class event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking the EVM event gap around richer event declarations, or move
  to the next uncovered EVM capability surface.

### EVM IR Nested Local Struct Arrays

Commit: feature commit for EVM IR nested local struct arrays

Summary:

- Extended portable IR EVM local fixed-array lowering so nested fixed arrays can
  use flat struct leaves, expanding every nested element field into
  deterministic Yul locals such as `grid[1][0].age`.
- Added static and dynamic nested struct field reads through nested local-array
  getter helpers, plus nested mutable field assignment and numeric compound
  assignment through bounds-checked `switch` lowering.
- Added nested whole-local assignment from another local array and from
  self-referential nested array literals, preserving RHS snapshot semantics.
- Extended `EvmStructArrayValueProbe` with `nested_struct_array_sum`,
  `nested_struct_array_dynamic_pick`, `nested_struct_array_update`,
  `nested_struct_array_whole_assign`, and `nested_struct_array_self_assign`.
- Refreshed golden Yul, artifact metadata selector checks, Foundry smoke tests,
  EVM coverage manifest entries, English target docs, Chinese target docs, and
  implementation backlog notes.

Validation run:

```sh
lake build
scripts/evm/struct-array-value-ir-smoke.sh
```

Result:

- `EvmStructArrayValueProbe` generated reproducible Yul and runtime bytecode
  through `solc --strict-assembly`.
- Foundry ran 14 StructArrayValueProbe tests, including nested flat-struct
  field reads, nested field mutation, nested whole assignment, RHS snapshotting,
  dynamic out-of-bounds reverts, and unknown-selector revert behavior.

Known limitations:

- Nested local fixed arrays are still limited to scalar word leaves or flat
  struct leaves. Non-flat struct leaves and other unsupported aggregate leaves
  remain explicit diagnostics.

Next step:

- Continue shrinking the EVM aggregate gap around unsupported nested aggregate
  leaves, richer event schemas, or broader cross-call return data.

### EVM IR Nested Struct Crosscall Fixed Arrays

Commit: feature commit for EVM IR nested struct crosscall arrays

Summary:

- Extended typed crosscall aggregate word-shape validation so nested fixed
  arrays can use flat struct leaves such as `RemotePair[2][2]`, while non-flat
  struct leaves still fail with explicit diagnostics.
- Added `EvmCrosscallProbe` entrypoints for `RemotePair[2][2]` arguments and
  direct entrypoint returns across normal, value-bearing, static, and delegate
  typed calls.
- Refreshed `EvmCrosscallProbe.golden.yul`, metadata selector expectations, and
  the Foundry smoke harness with `Pair[2][2]` callee helpers.
- Updated the EVM coverage manifest and target/validation docs to distinguish
  supported flat struct leaves from unsupported non-flat struct leaves.

Validation run:

```sh
lake build
scripts/i18n/check-sync.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
git diff --check
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 73 CrosscallProbe tests, including nested fixed-array
  flat-struct arguments and returns in normal, value-bearing, static, and
  delegate modes.

Known limitations:

- Dynamic ABI values, nested local fixed-array mutation beyond the current
  local-array surface, nested crosscall fixed arrays with non-flat or
  unsupported leaves, and variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking the EVM aggregate gap around dynamic ABI data, richer
  cross-call return data, or unsupported nested aggregate leaves.

### EVM IR Storage-Backed Aggregate ABI Returns

Commit: feature commit for EVM IR storage-backed aggregate ABI returns

Summary:

- Extended `EvmStorageArrayProbe` with `return_values()`, which writes U64
  storage-array elements, reads them back through `storageArrayRead`, and
  encodes those reads as a fixed-array ABI return.
- Extended `EvmStorageStructProbe` with `return_points()`, which writes fields
  in a fixed storage array of flat structs, reads them back through
  `storageArrayStructFieldRead`, and encodes those reads as a
  fixed-array-of-struct ABI return.
- Refreshed both storage probe golden Yul snapshots and metadata selector
  expectations.
- Added Foundry ABI decoding checks for `uint256[3]` and `Point[2]` returns,
  while still validating the raw storage slots with `vm.load`.

Validation run:

```sh
lake build
scripts/i18n/check-sync.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/storage-struct-ir-smoke.sh
git diff --check
```

Result:

- `EvmStorageArrayProbe` generated reproducible Yul and runtime bytecode, and
  Foundry ran 7 tests including the new storage-backed fixed-array return.
- `EvmStorageStructProbe` generated reproducible Yul and runtime bytecode, and
  Foundry ran 12 tests including the new storage-backed fixed-array-of-struct
  return.

Known limitations:

- This covers fixed-size word arrays and fixed arrays of flat structs assembled
  from storage reads. Dynamic ABI values, richer storage-backed aggregate
  shapes, and variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking the EVM ABI/storage gap around dynamic ABI data, richer
  aggregate storage shapes, or return data that cannot be represented as a
  static word sequence.

### EVM IR Nested Crosscall Fixed Arrays

Commit: `fb0828b` (`feat: support nested EVM crosscall arrays`)

Summary:

- Extended typed crosscall aggregate lowering so nested scalar fixed arrays such
  as `Array<Array<U64,2>,2>` flatten to ABI words for normal, value-bearing,
  static, and delegate typed calls.
- Added `EvmCrosscallProbe` entrypoints for nested scalar fixed-array arguments
  and direct entrypoint returns across all four call modes.
- At this milestone, kept nested fixed arrays with struct or other non-scalar
  leaves as explicit unsupported diagnostics; flat struct leaves were covered by
  a later follow-up.
- Refreshed `EvmCrosscallProbe.golden.yul`, metadata selector expectations, and
  the Foundry smoke harness with `uint64[2][2]` callee helpers.

Validation run:

```sh
lake build
lake env lean --run Tests/TargetRegistry.lean
scripts/i18n/check-sync.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
git diff --check
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 65 CrosscallProbe tests, including nested scalar fixed-array
  arguments and returns in normal, value-bearing, static, and delegate modes.
- GitHub Actions run `28514575022` passed on `main`.

Known limitations:

- Dynamic ABI values, nested local fixed-array mutation beyond the current
  local-array surface, nested crosscall fixed arrays with non-flat or
  unsupported leaves, and variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking the EVM aggregate gap around dynamic ABI data, storage
  backed aggregate ABI surfaces, or richer cross-call return data.

### EVM IR Nested Fixed-Array ABI

Commit: feature commit for EVM IR nested fixed-array ABI

Summary:

- Extended EVM ABI word flattening for entrypoint parameters and returns from
  flat fixed arrays to nested scalar fixed arrays such as
  `Array<Array<U64,2>,2>`.
- Added deterministic flattened Yul local names for nested ABI array words and
  static nested index reads such as `matrix[0][1]`.
- Extended `EvmAbiAggregateProbe` with `sum_matrix`, `make_matrix`, and
  `sum_small_matrix` entrypoints covering nested `U64`/`U32` ABI calldata,
  return-data encoding, and range guards.
- Kept typed crosscall nested aggregate arrays explicitly unsupported with
  crosscall-specific diagnostics instead of silently inheriting ABI entrypoint
  support.

Validation run:

```sh
lake build
scripts/evm/diagnostic-smoke.sh
scripts/evm/abi-aggregate-ir-smoke.sh
```

Result:

- `EvmAbiAggregateProbe` generated reproducible Yul and runtime bytecode
  through `solc --strict-assembly`.
- Foundry validated nested fixed-array parameters, nested fixed-array returns,
  malformed nested calldata length checks, and nested `U32` range guards.
- EVM diagnostics now keep zero-length arrays, non-flat struct fields, nested
  crosscall aggregate arrays, and malformed crosscall surfaces explicit.

Known limitations:

- Nested fixed-array support is currently ABI-entrypoint focused.
- Dynamic ABI values, nested local fixed-array mutation, nested crosscall
  aggregate arrays, and variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking the EVM aggregate gap around nested crosscall aggregates
  or dynamic ABI data.

### EVM IR Contract Creation

Commit: feature commit for EVM IR contract creation

Summary:

- Added portable IR `crosscallCreate` and `crosscallCreate2` expressions for
  EVM contract creation from fixed init-code hex.
- Lowered creation expressions to deterministic Yul helpers that write init
  code into memory, call `create(value, offset, length)` or
  `create2(value, offset, length, salt)`, revert on zero-address failure, and
  return the deployed address word.
- Extended `EvmCrosscallProbe` with `deploy_create` and `deploy_create2`
  entrypoints using tiny init code that deploys a runtime returning U256 `42`.
- Kept non-EVM target behavior explicit by adding Psy unsupported diagnostics
  for both creation expressions.

Validation run:

```sh
lake build ProofForge.IR.Examples.EvmCrosscallProbe
scripts/evm/diagnostic-smoke.sh
scripts/psy/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 57 CrosscallProbe tests, including `create` deployment,
  deterministic `create2` address validation, and calls into the deployed
  runtime.
- EVM diagnostics now cover bad creation value type, malformed init-code hex,
  and bad `create2` salt type; Psy diagnostics cover unsupported creation
  nodes.

Known limitations:

- Creation init code is currently embedded as fixed hex in the IR expression.
- Dynamic constructor arguments, artifact-linked init code, creation manifests,
  live transaction broadcasting, and variable-length cross-call return data
  remain future EVM IR work.

Next step:

- Continue closing EVM call-surface gaps around artifact-linked creation or
  variable-length ABI data.

### EVM IR Struct-Array Crosscall Aggregates

Commit: feature commit for EVM IR struct-array crosscall aggregates

Summary:

- Extended the existing typed crosscall aggregate path to fixed arrays of flat
  structs.
- Added `EvmCrosscallProbe` entrypoints for fixed-array-of-flat-struct typed
  arguments and direct aggregate returns across normal, value-bearing, static,
  and delegate call modes.
- Reused the ABI-static flattening policy: `RemotePair[2]` lowers to four ABI
  words, preserving Bool and U32 return guards for every decoded element field.
- Refreshed golden Yul, artifact metadata entrypoint expectations, Foundry
  callee fixtures, and coverage/target validation docs.

Validation run:

```sh
lake build ProofForge.IR.Examples.EvmCrosscallProbe
scripts/evm/crosscall-ir-smoke.sh
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 55 CrosscallProbe tests, including fixed-array-of-flat-struct
  arguments and returns in normal/value/static/delegate modes.
- Metadata validation now checks all new struct-array crosscall selectors.

Known limitations:

- Aggregate crosscall arguments and returns remain limited to ABI-static flat
  shapes.
- Nested dynamic arrays, variable-length return data, and artifact-linked
  creation remain future EVM IR work.

Next step:

- Continue closing the remaining EVM call-surface gaps around artifact-linked
  creation or variable-length ABI data.

### EVM IR Aggregate Crosscall Arguments

Commit: feature commit for EVM IR aggregate crosscall arguments

Summary:

- Extended typed crosscall argument lowering beyond scalar words for normal,
  value-bearing, static, and delegate typed calls.
- Reused the EVM ABI flattening rules for flat struct and scalar fixed-array
  arguments, so helper arity now reflects the ABI word count rather than the
  surface IR argument count.
- Made crosscall helper discovery type-env aware, allowing let-bound local
  structs and fixed arrays to request the correct generated helper.
- Extended `EvmCrosscallProbe` with normal struct and fixed-array arguments,
  value-bearing struct arguments, static struct arguments, and delegate struct
  arguments.
- Kept nested aggregate crosscall argument shapes as explicit unsupported
  diagnostics.

Validation run:

```sh
lake build
scripts/evm/diagnostic-smoke.sh
scripts/evm/crosscall-ir-smoke.sh
```

Result:

- `EvmCrosscallProbe` generated reproducible Yul and runtime bytecode through
  `solc --strict-assembly`.
- Foundry ran 35 CrosscallProbe tests, including aggregate argument calldata
  packing for normal/value/static/delegate typed calls.
- EVM diagnostics ran 55 cases, including nested aggregate argument rejection.

Known limitations:

- Aggregate crosscall arguments are limited to ABI-static flat structs and
  scalar fixed arrays.
- Value-bearing, static, and delegate typed crosscalls still return scalar
  words only.
- Contract creation and variable-length return data remain future work.

Next step:

- Continue closing EVM call-surface gaps around aggregate returns for
  value/static/delegate calls or contract creation manifests.

### EVM IR Aggregate Crosscall Returns

Commit: feature commit for EVM IR aggregate crosscall returns

Summary:

- Extended normal `crosscallInvokeTyped` returns beyond scalar words when the
  expression is returned directly from an ABI-facing entrypoint.
- Lowered flat struct and scalar fixed-array crosscall return data through
  arity- and ABI-word-shape-specific Yul helpers such as
  `__proof_forge_crosscall_0_abi_bool_u32`, assigning multiple helper results
  directly to the entrypoint's ABI return words.
- Preserved scalar behavior for value-bearing, static, and delegate typed
  crosscalls, and kept unsupported nested aggregate return shapes as explicit
  diagnostics.
- Extended `EvmCrosscallProbe` with `call_remote_pair` and
  `call_remote_array`, refreshed golden Yul, metadata selector checks, Foundry
  aggregate struct/array return tests, malformed Bool/U32 aggregate return
  guard tests, coverage manifests, validation gates, target docs, backlog, and
  Chinese docs.

Validation run:

```sh
lake build
scripts/i18n/check-sync.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/foundry-smoke.sh
```

Known limitations:

- Aggregate crosscall support is limited to normal typed calls returned
  directly from entrypoints.
- Aggregate crosscall arguments, value/static/delegate aggregate returns,
  nested aggregate return data, contract creation, and variable-length return
  data remain future EVM IR work.

Next step:

- Continue shrinking EVM cross-call gaps around aggregate arguments,
  value/static/delegate aggregate returns, or create/create2.

### EVM IR Typed Delegatecalls

Commit: feature commit for EVM IR typed delegatecalls

Summary:

- Added portable IR `crosscallInvokeDelegateTyped` for EVM delegate calls that
  return one scalar word.
- Lowered delegate calls to arity- and return-type-specific Yul helpers using
  `delegatecall(gas(), target, ...)`, sharing selector packing, scalar-word
  argument encoding, short-return checks, and Bool/U32 return guards with the
  other crosscall helper modes.
- Kept delegate semantics explicit across backends: Psy IR v0 rejects delegate
  typed crosscalls with a stable unsupported diagnostic.
- Extended `EvmCrosscallProbe` with U64/Bool/U32/Hash delegate entrypoints,
  refreshed golden Yul, Foundry caller-storage read/write checks, typed-return
  guard checks, metadata selector checks, EVM/Psy diagnostics, coverage
  manifests, target docs, validation gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
scripts/i18n/check-sync.sh
```

Known limitations:

- Delegate crosscalls are currently limited to scalar word arguments and one
  scalar word return (`U32`, `U64`, `Bool`, or `Hash`).
- Contract creation, aggregate crosscall arguments/returns, and
  variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking EVM cross-call gaps around create/create2 or aggregate
  calldata/return-data.

### EVM IR Typed Staticcalls

Commit: feature commit for EVM IR typed staticcalls

Summary:

- Added portable IR `crosscallInvokeStaticTyped` for read-only EVM
  cross-contract calls that return one scalar word.
- Lowered typed static calls to arity- and return-type-specific Yul helpers
  using `staticcall(gas(), target, ...)`, sharing selector packing, scalar-word
  argument encoding, short-return checks, and Bool/U32 return guards with the
  existing call helpers.
- Kept target semantics explicit across backends: Psy IR v0 rejects static
  typed crosscalls with a stable unsupported diagnostic rather than silently
  lowering them to the existing Felt-returning `__invoke_sync` form.
- Extended `EvmCrosscallProbe` with `call_remote_static` plus Bool/U32/Hash
  static typed variants, refreshed golden Yul, Foundry read-only return,
  typed-return guard, and static-context state-write failure checks, metadata
  selector checks, EVM/Psy diagnostics, coverage manifests, target docs,
  validation gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
scripts/i18n/check-sync.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/crosscall-ir-smoke.sh
```

Known limitations:

- Static crosscalls are currently limited to scalar word arguments and one
  scalar word return (`U32`, `U64`, `Bool`, or `Hash`).
- `delegatecall`, contract creation, aggregate crosscall arguments/returns, and
  variable-length return data remain future EVM IR work.

Next step:

- Continue shrinking EVM cross-call gaps around `delegatecall`, create/create2,
  aggregate calldata/return-data, or richer artifact metadata for deployment.

### EVM IR Aggregate Event Data

Commit: feature commit for EVM IR aggregate event data

Summary:

- Extended EVM `eventEmit` / `eventEmitIndexed` lowering so non-indexed event
  data fields can be scalar words, flat structs, scalar fixed arrays, or fixed
  arrays of flat structs.
- Added canonical Solidity-style event signature generation for flat aggregate
  event fields, including `PairEvent((uint64,uint64))`,
  `ArrayEvent(uint64[2])`, and `PairArrayEvent((uint64,uint64)[2])`.
- Flattened aggregate event data into ABI-style 32-byte words before `log1`
  through `log4`, preserving scalar indexed topics for `eventEmitIndexed`.
- At the time of this entry, aggregate indexed fields still failed with a
  diagnostic instead of lowering. That limitation is resolved by the later
  "EVM IR Indexed Aggregate Event Topics" entry for flat supported aggregates.
- Extended `EventProbe` with `emit_pair_event`, `emit_array_event`, and
  `emit_pair_array_event`, refreshed golden Yul, Foundry recorded-log checks,
  metadata selector checks, EVM diagnostics, coverage, target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build proof-forge
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- At the time of this entry, indexed event fields were scalar-only (`U32`,
  `U64`, `Bool`, or `Hash`) and limited to three indexed fields after the
  signature topic. Flat supported aggregate indexed fields are covered by the
  later "EVM IR Indexed Aggregate Event Topics" entry.
- Richer first-class event declarations are still not represented in the
  portable IR.

Next step:

- Continue shrinking EVM gaps around richer cross-call return data,
  `staticcall`/`delegatecall`/creation call kinds, nested aggregate lowering,
  or real creation/broadcast manifests.

### EVM IR Indexed Event Topics

Commit: feature commit for EVM IR indexed events

Summary:

- Added portable IR `eventEmitIndexed` for EVM-style events with scalar indexed
  fields and non-indexed data fields.
- Lowered indexed events to Yul `log2`/`log3`/`log4`: topic0 is the
  Solidity-style event signature hash, indexed fields become topics, and
  non-indexed fields remain ABI-style 32-byte data words.
- Kept indexed events explicit on non-EVM targets: Psy IR v0 rejects the new
  node with a diagnostic instead of silently dropping topic semantics.
- Extended `EventProbe` with `emit_indexed_event`, refreshed golden Yul,
  Foundry recorded-log checks, metadata selector checks, EVM/Psy diagnostics,
  coverage manifests, target docs, validation gates, backlog, capability
  registry entries, and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
scripts/i18n/check-sync.sh
```

Known limitations:

- Indexed event fields are limited to scalar EVM word values (`U32`, `U64`,
  `Bool`, or `Hash`) and at most three indexed fields after the signature
  topic.
- Aggregate event payloads and richer event declarations remain future work.

Next step:

- Continue shrinking EVM gaps around aggregate event payloads, richer
  cross-call return data, contract-creation call kinds, or nested aggregate
  lowering.

### EVM IR Solidity-Style Event Signatures

Commit: feature commit for EVM IR event signature topics

Summary:

- Changed portable IR `eventEmit` topic0 derivation from the raw event-name
  hash to `keccak256(Solidity-style event signature)`.
- Added EVM ABI type names for supported event scalar fields:
  `U32 -> uint32`, `U64 -> uint64`, `Bool -> bool`, and `Hash -> bytes32`.
- Reworked the Yul event topic preimage writer to pack arbitrary-length UTF-8
  signature strings into memory before hashing, removing the old 32-byte event
  name packing limit.
- Updated `EventProbe` golden Yul, Foundry recorded-log assertion, coverage
  manifest, EVM target docs, validation gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/i18n/check-sync.sh
```

Known limitations:

- Portable IR event payload fields remain limited to scalar word values:
  `U32`, `U64`, `Bool`, or `Hash`.
- Richer event declarations are still not represented in the portable IR.

Next step:

- Continue shrinking event gaps around aggregate event payloads or richer event
  declarations, or move to another EVM surface such as richer cross-call return
  data or nested aggregate lowering.

### EVM IR Whole Storage Struct Read/Write

Commit: feature commit for EVM IR whole storage struct read/write

Summary:

- Allowed `storageScalarRead` and `storageScalarWrite` to operate on flat
  scalar storage structs by expanding the struct into declaration-ordered EVM
  field slots.
- Added aggregate-only lowering for struct storage reads: struct local
  bindings, struct field access, whole local struct assignment, and struct
  returns can consume `storageScalarRead` without treating the struct as a
  single EVM word.
- Lowered whole scalar storage struct writes from local structs, struct
  literals, and storage struct reads with RHS field snapshotting before writing
  target slots.
- Extended `EvmStorageStructProbe` with whole write/read-into-local, direct
  ABI struct return from storage, and self-referential storage write snapshot
  coverage.
- Refreshed golden Yul, artifact metadata entrypoint checks, Foundry smoke
  tests, diagnostics, coverage manifest, target docs, validation gates, backlog,
  and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Whole storage struct operations are limited to flat scalar storage structs
  whose fields lower to EVM words (`U32`, `U64`, `Bool`, or `Hash`).
- Nested struct fields, non-flat struct storage, nested arrays, and dynamic or
  nested aggregate ABI values remain explicit diagnostics or documented gaps.

Next step:

- Continue shrinking the EVM aggregate unsupported surface around nested local
  aggregate shapes, broader storage-backed aggregate ABI values, richer
  cross-call return data, or event schema fidelity.

### EVM IR Struct Array Whole Local Assignment

Commit: feature commit for EVM IR struct-array whole local assignment

Summary:

- Allowed `assign (.local name) value` for mutable local fixed arrays whose
  element type is a flat struct.
- Lowered whole local struct-array assignment from another local struct array
  or a struct-array literal by snapshotting every RHS element field into
  temporary Yul locals before writing the expanded target fields.
- Extended `EvmStructArrayValueProbe` with `whole_struct_array_assign()` and
  `self_struct_array_assign()` to validate local-source assignment and
  self-referential literal RHS snapshot semantics.
- Refreshed the golden Yul, artifact metadata entrypoint checks, Foundry smoke
  harness, EVM coverage manifest, target docs, validation gates, backlog, and
  Chinese docs.

Validation run:

```sh
lake build
scripts/evm/struct-array-value-ir-smoke.sh
```

Known limitations:

- Struct-array whole assignment is limited to fixed arrays whose element type is
  a flat struct over EVM word fields (`U32`, `U64`, `Bool`, or `Hash`).
- Nested arrays, nested local structs, whole-struct storage reads/writes, and
  dynamic or nested aggregate ABI values remain explicit diagnostics.

Next step:

- Continue shrinking the remaining EVM aggregate unsupported surface, likely
  around nested aggregate locals, richer cross-call return data, or event schema
  fidelity.

### EVM IR Storage Map Contains

Commit: feature commit for EVM IR storage map contains

Summary:

- Lowered `storage.map.contains` for EVM portable IR through
  ProofForge-managed presence slots instead of treating nonzero map values as
  presence.
- Added `__proof_forge_map_presence_slot(slot, key)`, rooted at
  `keccak256(slot || PROOF_FORGE_MAP_PRESENCE)`, while preserving the existing
  Solidity-style value slot `keccak256(key || slot)`.
- Updated map insert/set, map statement writes, and map storage-path compound
  assignment helpers to mark key presence whenever ProofForge writes a map key.
- Extended `EvmMapProbe` with U64 contains coverage, including a zero-valued
  present key, and extended `EvmTypedMapProbe` with U32/Bool/Hash contains
  entrypoints.
- Updated diagnostics so statement-position `storage.map.contains` fails with
  an expression-only diagnostic instead of an unsupported-capability error.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR proof-forge
scripts/evm/map-ir-smoke.sh
scripts/evm/typed-map-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Presence tracks keys written through ProofForge-generated map helpers; raw
  external storage mutation outside those helpers can still bypass the
  presence mapping.
- Nested map paths and aggregate/non-word map key/value shapes remain explicit
  diagnostics.

Next step:

- Continue shrinking the remaining EVM aggregate unsupported surface, likely
  around nested aggregate locals, richer event schemas, or broader cross-call
  return data.

### EVM IR Whole Local Aggregate Assignment

Commit: feature commit for EVM IR whole local aggregate assignment

Summary:

- Allowed `assign (.local name) value` for mutable local fixed-array and flat
  local struct values.
- Lowered whole local fixed-array assignment from another local fixed-array or a
  fixed-array literal by snapshotting RHS element words into temporary Yul
  locals before assigning expanded target elements.
- Lowered whole local struct assignment from another local struct or a struct
  literal by snapshotting RHS field words into temporary Yul locals before
  assigning expanded target fields.
- Extended `EvmArrayValueProbe` with `whole_array_assign()` and
  `EvmStructValueProbe` with `whole_struct_assign()` to validate local-source
  assignment and self-referential literal RHS snapshot semantics.
- Updated EVM diagnostics, coverage manifests, target docs, validation gates,
  backlog, and Chinese docs to remove the stale whole-local-aggregate
  assignment limitation.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR proof-forge
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Whole local aggregate assignment is limited to flat fixed-array and flat
  struct locals whose elements/fields lower to EVM words.
- Nested arrays, nested local structs, and whole-struct storage reads/writes
  remain explicit diagnostics.
- Dynamic or nested aggregate ABI values remain out of scope for the current
  flat ABI lowering.

Next step:

- Continue shrinking the EVM aggregate unsupported surface around nested
  aggregate locals, richer cross-call return data, or event schema fidelity.

### EVM IR Dynamic Local Fixed-Array Indexes

Commit: feature commit for EVM IR dynamic local fixed-array indexing

Summary:

- Threaded the EVM IR lowering environment through expression, effect,
  aggregate binding, return, and statement lowering so local aggregate shape is
  available during code generation.
- Added dynamic `arrayGet` lowering for local fixed-array values and fixed-array
  literals using length-specific Yul getter helpers with default revert cases.
- Added dynamic mutable local fixed-array element assignment and numeric
  compound assignment lowering with Yul `switch` blocks over expanded local
  elements.
- Extended `EvmArrayValueProbe` with `dynamic_pick(uint256)` and
  `dynamic_update(uint256)`, refreshed golden Yul, metadata entrypoint
  validation, and Foundry assertions for in-bounds values and out-of-bounds
  reverts.
- Updated EVM diagnostics, coverage manifests, target docs, validation gates,
  backlog, and Chinese docs to remove the stale dynamic-local-index limitation.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR proof-forge
scripts/evm/array-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Dynamic fixed-array indexing is limited to local fixed-array values and
  fixed-array literals whose elements lower to EVM words.
- Whole local aggregate assignment is handled by the later
  "EVM IR Whole Local Aggregate Assignment" entry.
- Nested arrays, nested local structs, and whole-struct storage reads/writes
  remain explicit diagnostics.
- Dynamic or nested aggregate ABI values remain out of scope for the current
  flat ABI lowering.

Next step:

- Continue shrinking the EVM aggregate unsupported surface, most likely around
  nested aggregate locals or richer cross-call return data.

### EVM Deploy Manifest Metadata

Commit: feature commit for EVM deploy manifest metadata

Summary:

- Extended EVM bytecode modes to emit a ProofForge EVM deploy manifest next to
  each `proof-forge-artifact.json` metadata file.
- The manifest records source kind/module, portable IR version when present,
  capabilities, ABI entrypoints or SDK methods, Yul/source inputs, runtime
  bytecode hash/size, and `creation.mode: runtime-bytecode`.
- EVM artifact metadata now records the deploy manifest artifact and requires
  `validation.deployManifest: passed`.
- Added a standalone `scripts/evm/validate-deploy-manifest.py` validator and
  extended `scripts/evm/validate-artifact-metadata.py` to validate the
  referenced deploy manifest against metadata.
- Updated EVM target docs, validation gates, backlog, and Chinese docs to
  distinguish ProofForge runtime-bytecode manifests from future broadcast or
  creation-transaction manifests.

Validation run:

```sh
lake build ProofForge.Cli proof-forge
python3 -m py_compile scripts/evm/validate-artifact-metadata.py scripts/evm/validate-deploy-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/build-examples.sh
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture AbiScalarProbe --expect-source-kind portable-ir build/ir/AbiScalarProbe.proof-forge-deploy.json
python3 scripts/evm/validate-deploy-manifest.py --root . --expect-fixture Counter.lean --expect-source-kind lean-sdk build/evm/Counter.proof-forge-deploy.json
```

Known limitations:

- The deploy manifest describes runtime bytecode deployment inputs only.
- It does not yet generate constructor initcode, Foundry broadcast JSON, chain
  id, deployed address, or a signed/raw transaction.
- Foundry smokes still install runtime bytecode with `vm.etch`.

Next step:

- Either extend EVM manifests toward creation/broadcast artifacts, or continue
  shrinking the remaining EVM IR unsupported surface around dynamic aggregates
  and richer cross-call returns.

### EVM IR Mutable Local Aggregates

Commit: feature commit for EVM IR mutable local aggregate lowering

Summary:

- Extended EVM IR lowering for local fixed-array and flat struct values from
  immutable-only bindings to mutable aggregate locals.
- Added static local fixed-array element assignment and numeric compound
  assignment over expanded Yul locals.
- Added static local struct field assignment and numeric compound assignment
  over expanded Yul locals.
- Extended `EvmArrayValueProbe` and `EvmStructValueProbe` with mutable
  `U64`/`U32`/`Bool`/`Hash` write paths, metadata entrypoint validation,
  refreshed golden Yul, and Foundry runtime assertions.
- Updated EVM diagnostics so immutable aggregate element/field assignment still
  fails explicitly while mutable aggregate locals now lower successfully.
- Updated EVM coverage, target docs, validation gates, backlog, and Chinese
  docs to remove stale mutable-local aggregate limitations.

Validation run:

```sh
lake build ProofForge.IR.Examples.EvmArrayValueProbe ProofForge.IR.Examples.EvmStructValueProbe proof-forge
scripts/evm/array-value-ir-smoke.sh
scripts/evm/struct-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- Dynamic local fixed-array indexing is handled by the later
  "EVM IR Dynamic Local Fixed-Array Indexes" entry.
- Whole local aggregate assignment remains an explicit diagnostic; update
  elements or fields directly for now.
- Nested arrays, nested local structs, and whole-struct storage reads/writes
  remain explicit diagnostics.

Next step:

- Continue shrinking the EVM aggregate unsupported surface around nested
  aggregate locals or richer cross-call return data.

### EVM IR Scalar Expression Probe

Commit: feature commit for EVM IR scalar expression validation

Summary:

- Added `ProofForge.IR.Examples.EvmExpressionProbe` to validate scalar
  expression lowering directly, separate from storage or assignment side
  effects.
- Covered `U64` and `U32` arithmetic (`add`, `sub`, `mul`, `div`, `mod`),
  `U64` exponentiation, `U64`/`U32` bitwise operators and shifts, predicates,
  boolean `and`/`or`/`not`, scalar literals, immutable local reads, supported
  `U32`/`U64`/`Bool` casts, one-word scalar returns, and assertion guards.
- Added CLI emission modes, golden Yul, Foundry smoke coverage, artifact
  metadata validation, and CI.
- Updated EVM coverage, target docs, validation gates, backlog, and Chinese
  docs so the scalar expression family now has runtime validation evidence
  instead of only structural lowering notes.

Validation run:

```sh
lake build ProofForge.IR.Examples.EvmExpressionProbe proof-forge
scripts/evm/expression-ir-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Known limitations:

- EVM arithmetic still follows raw EVM word semantics; checked overflow,
  signed arithmetic, and target-specific numeric policies remain future
  design work.
- Aggregate expression behavior remains covered by the array, struct, and ABI
  probes rather than this scalar expression probe.

Next step:

- Continue converting remaining `lowered` coverage rows into validated probes
  or explicit diagnostics, especially around target-specific artifact/deploy
  surfaces and any residual statement/effect validation gaps.

### EVM IR Typed Storage Maps

Commit: feature commit for EVM IR typed storage maps

Summary:

- Generalized portable EVM storage maps from `Map<U64, U64, N>` to word
  key/value maps over `U32`, `U64`, `Bool`, and `Hash`.
- Reused the existing Solidity-style `keccak256(key, slot)` mapping slot helper
  for all supported word map shapes, preserving one declared storage slot per
  map state.
- Added `ProofForge.IR.Examples.EvmTypedMapProbe`, CLI emission modes, golden
  Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Covered ABI dispatcher guards for `U32` and `Bool` map parameters,
  expression-position previous-value returns, statement-position writes,
  `Hash`/`bytes32` map values, raw mapping slots, and single-segment `mapKey`
  storage-path read/write/compound assignment.
- Updated EVM diagnostics, coverage, target docs, validation gates, and Chinese
  docs so unsupported map diagnostics now target non-word map shapes while
  `storage.map.contains` remains explicitly unsupported.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR ProofForge.IR.Examples.EvmTypedMapProbe proof-forge
scripts/evm/typed-map-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Known limitations:

- EVM storage maps still support only single-word key/value shapes. Aggregate,
  nested, dynamic, or non-word map key/value shapes remain explicit diagnostics.
- `storage.map.contains` remains unsupported because EVM mappings do not track
  key presence without an auxiliary bitmap.
- Nested map storage paths remain unsupported; `mapKey` paths are currently
  single-segment only.

Next step:

- Continue reducing the remaining EVM IR unsupported surface, likely around
  richer ABI/cross-call surfaces or target-specific deployment artifacts, with
  the same golden Yul, metadata, Foundry, diagnostics, and CI pattern.

### EVM IR Typed Storage Words

Commit: feature commit for EVM IR typed storage word arrays

Summary:

- Generalized portable EVM storage arrays from `U64`-only arrays to word-scalar
  arrays over `U32`, `U64`, `Bool`, and `Hash`.
- Enabled `Bool` scalar storage in the portable EVM backend; scalar storage
  still rejects unsupported non-word shapes explicitly.
- Reused the existing contiguous `__proof_forge_array_slot(base, length,
  index)` helper for typed word arrays, preserving runtime out-of-bounds
  checks and deterministic slot layout.
- Added `ProofForge.IR.Examples.EvmTypedStorageProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Updated EVM diagnostics, coverage, target docs, validation gates, and Chinese
  docs so `Unit` storage remains the explicit unsupported case while
  `Bool`/`U32`/`Hash` storage arrays are validated behavior.

Validation run:

```sh
lake build ProofForge.Backend.Evm.IR proof-forge
scripts/evm/typed-storage-ir-smoke.sh
```

Known limitations:

- Typed storage arrays are still fixed-size word arrays. Nested arrays, dynamic
  storage arrays, and non-word storage elements remain future work.

Next step:

- Continue reducing the remaining EVM IR unsupported surface, likely either
  richer map shapes or the next ABI/control/cross-call gap, with the same
  golden Yul, metadata, Foundry, diagnostics, and CI pattern.

### EVM IR Flat Storage Structs

Commit: feature commit for EVM IR flat storage struct lowering

Summary:

- Added EVM portable IR lowering for flat scalar storage structs and fixed
  storage arrays of flat structs. Scalar storage structs reserve one slot per
  field; struct arrays reserve `length * field_count` slots.
- Added direct lowering for `storageStructFieldRead`/`Write` and
  `storageArrayStructFieldRead`/`Write`, plus generic storage paths using
  scalar `field` and array `index`+`field` segments.
- Added the `__proof_forge_struct_array_slot` Yul helper with runtime
  out-of-bounds checks and deterministic
  `base + index * field_count + field_offset` slot derivation.
- Added `ProofForge.IR.Examples.EvmStorageStructProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Updated EVM diagnostics and coverage so whole-struct storage reads/writes and
  missing fields fail explicitly before Yul generation.

Validation run:

```sh
lake build proof-forge
scripts/evm/storage-struct-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Known limitations:

- Storage struct support is flat and field-based only. Whole-struct storage
  reads/writes, nested struct fields, map values shaped as structs, and dynamic
  storage arrays remain explicit future work.

Next step:

- Continue EVM portable IR support toward richer storage element types or the
  next unsupported ABI/control surface, keeping the same golden Yul, metadata,
  Foundry, diagnostics, and CI pattern.

### EVM IR Flat Aggregate ABI

Commit: feature commit for EVM IR flat aggregate ABI lowering

Summary:

- Added EVM portable IR ABI flattening for flat static fixed-array and struct
  parameters. Fixed arrays lower to one calldata word per element, and structs
  lower to fields in declaration order.
- Added dispatcher range guards for `U32` and `Bool` words inside aggregate
  ABI parameters.
- Added multi-word return-data lowering for flat fixed-array and struct return
  values, including local fixed-array returns and struct literal returns.
- Added `ProofForge.IR.Examples.EvmAbiAggregateProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Updated EVM diagnostics so Unit ABI values, zero-length ABI arrays, and
  nested aggregate ABI values fail explicitly before Yul generation.

Validation run:

```sh
lake build
scripts/evm/abi-aggregate-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Known limitations:

- Aggregate ABI support is flat/static only. Nested aggregate ABI values,
  dynamic arrays, storage structs, mutable local structs, and struct arrays
  remain future work.

Next step:

- Continue the EVM backend toward storage struct layout or richer ABI/event
  schemas, using the same fixture, golden, metadata, Foundry, and CI pattern.

### CI ContextProbe Target Split

Commit: bugfix commit for CI fixture isolation

Summary:

- Split `ContextProbe` target usage so the shared Psy fixture keeps only
  target-portable context reads.
- Added `ProofForge.IR.Examples.EvmContextProbe` for EVM-only `nativeValue`
  coverage while preserving the existing `ContextProbe` Yul object name,
  selectors, golden Yul, and Foundry smoke behavior.
- Updated EVM context CLI emission to use the EVM-specific fixture, while
  `--emit-context-ir-psy` continues to use the Psy-compatible fixture.
- Fixed the GitHub Actions failure where the Psy golden source step attempted
  to lower `nativeValue`, which Psy IR v0 intentionally rejects.
- Made `scripts/evm/build-examples.sh` explicitly build `ProofForge.Evm` before
  compiling SDK examples so clean CI environments have the SDK `.olean` needed
  by the Lean frontend.

Validation run:

```sh
lake build
# Full Check Psy golden sources block from .github/workflows/ci.yml
scripts/evm/context-ir-smoke.sh
scripts/evm/build-examples.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- Psy still rejects `nativeValue` by design; EVM owns the current
  `callvalue()` lowering and runtime validation.

Next step:

- Re-run GitHub Actions on `main` and continue the EVM aggregate ABI work after
  CI is green.

### EVM IR Local Struct Values

Commit: feature commit for EVM IR local struct values

Summary:

- Added EVM portable IR lowering for flat immutable local struct values by
  expanding each supported field into an internal Yul local.
- Added direct field-access lowering for local struct values and struct
  literals over `U64`, `U32`, `Bool`, and `Hash` fields.
- Registered partial `data.struct` support in the EVM target profile and
  metadata capability flow.
- Added explicit diagnostics for struct storage, mutable local structs, nested
  struct fields, ABI-facing structs, duplicate/empty struct declarations, and
  unsupported field shapes.
- Added `ProofForge.IR.Examples.EvmStructValueProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.

Validation run:

```sh
lake build
scripts/evm/struct-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- This feature supports flat immutable local struct values only. Mutable local
  structs, nested structs, storage structs, struct arrays, ABI structs, and
  struct assignment paths remain future work.

Next step:

- Continue EVM aggregate coverage toward ABI aggregate values or storage
  struct layout once the target-specific EVM ABI/storage policy is specified.

### EVM IR Local Fixed-Array Values

Commit: feature commit for EVM IR local fixed-array values

Summary:

- Added EVM portable IR lowering for immutable local fixed-array values by
  expanding each array element into an internal Yul local.
- Added static `arrayGet` lowering for local fixed-array values and direct
  fixed-array literals over `U64`, `U32`, `Bool`, and `Hash` elements.
- Added explicit diagnostics for mutable fixed-array locals, dynamic local
  fixed-array indexes, and static out-of-bounds indexes.
- Added `ProofForge.IR.Examples.EvmArrayValueProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.

Validation run:

```sh
lake build proof-forge
scripts/evm/array-value-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
```

Known limitations:

- This feature supports immutable local fixed-array values with static indexes.
  Dynamic local indexes, mutable local arrays, nested arrays, aggregate ABI
  arrays, and storage arrays beyond the existing `U64` path remain future work.

Next step:

- Continue EVM aggregate coverage toward structs or ABI aggregate values, using
  the same fixture/golden/smoke/metadata pattern.

### EVM IR Array Index Storage Paths

Commit: feature commit for EVM IR array index storage paths

Summary:

- Added EVM portable IR lowering for single-segment `StoragePathSegment.index`
  paths over `U64` fixed storage arrays.
- Reused `__proof_forge_array_slot(base, length, index)` for generic
  `storagePathRead`, `storagePathWrite`, and `storagePathAssignOp` so direct
  array effects and storage paths share bounds-checking behavior.
- Extended `EvmStorageArrayProbe` with `path_lifecycle()` and
  `path_assign_lifecycle()`.
- Extended `scripts/evm/storage-array-ir-smoke.sh` to validate path read,
  write, compound assignment, metadata selectors, and raw storage slots.
- Kept nested index paths, struct paths, and non-`U64` arrays explicitly
  rejected.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-storage-array-ir-yul -o build/ir/EvmStorageArrayProbe.yul
diff -u Examples/Evm/EvmStorageArrayProbe.golden.yul build/ir/EvmStorageArrayProbe.yul
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- This feature supports exactly one `index` path segment over `U64` storage
  arrays. Nested array paths, struct fields, local fixed-array values, and
  aggregate ABI arrays remain future work.

Next step:

- Move from storage-array paths toward local fixed-array values or flat structs,
  depending on which aggregate surface is needed first.

### EVM IR U64 Storage Arrays

Commit: feature commit for EVM IR U64 storage array lowering

Summary:

- Added EVM target-profile support for `storage.array` and partial
  `data.fixed_array`.
- Added state-slot span accounting so fixed storage arrays reserve one EVM
  storage slot per element and later state starts after the full array span.
- Added portable IR lowering for `storageArrayRead` and `storageArrayWrite`
  over `U64` storage arrays.
- Lowered array access through `__proof_forge_array_slot(base, length, index)`,
  which reverts when the runtime index is out of bounds before `sload` or
  `sstore`.
- Added `ProofForge.IR.Examples.EvmStorageArrayProbe`, CLI emission modes,
  golden Yul, Foundry smoke coverage, artifact metadata validation, and CI.
- Kept local fixed-array values, aggregate ABI arrays, generic index storage
  paths, structs, and non-`U64` storage arrays explicitly rejected.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-storage-array-ir-yul -o build/ir/EvmStorageArrayProbe.yul
diff -u Examples/Evm/EvmStorageArrayProbe.golden.yul build/ir/EvmStorageArrayProbe.yul
scripts/evm/storage-array-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- This feature covers `U64` storage arrays only. `U32`, `Hash`, `Bool`,
  struct arrays, local fixed-array values, ABI arrays, and generic index
  storage paths remain follow-up work.

Next step:

- Extend EVM aggregate support toward local fixed-array values or generic index
  storage paths, then move into structs once the array layout is stable.

### EVM IR Native Value

Commit: feature commit for EVM IR native value lowering

Summary:

- Added EVM portable IR lowering for expression-position `nativeValue` as Yul
  `callvalue()`.
- Extended `ProofForge.IR.Examples.ContextProbe` with `native_value()` and
  selector `0xf0eba40f`.
- Extended `scripts/evm/context-ir-smoke.sh` so Foundry calls
  `native_value()` with attached value and verifies the returned word.
- Updated EVM artifact metadata validation to require `value.native` and the
  `native_value:f0eba40f` entrypoint.
- Moved `Expr.nativeValue` in `Tests/EvmCoverage.tsv` from unsupported to
  validated and removed the old unsupported diagnostic case.

Validation run:

```sh
lake build
lake env proof-forge --emit-context-ir-yul -o build/ir/ContextProbe.yul
diff -u Examples/Evm/ContextProbe.golden.yul build/ir/ContextProbe.yul
scripts/evm/context-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
git diff --check
```

Known limitations:

- `nativeValue` is exposed as the raw EVM call value word. Higher-level native
  asset accounting remains a target/runtime policy layer above this IR node.

Next step:

- Continue expanding EVM portable IR coverage one small capability at a time,
  with fixture, smoke, coverage, docs, commit, and push for each feature.

### EVM IR Map Path Compound Assignment

Commit: feature commit for EVM IR map path compound assignment

Summary:

- Added EVM portable IR lowering for statement-position `storagePathAssignOp`
  on single-segment `mapKey` paths over `Map<U64, U64, N>`.
- Lowered map path compound assignment through generated Yul helpers named
  `__proof_forge_map_assign_<op>`.
- Kept mapping slot calculation inside the helper so the key expression is
  evaluated once and the computed storage slot is reused for `sload` and
  `sstore`.
- Added type validation so storage path compound assignment requires matching
  numeric path/value types.
- Kept nested map paths, array paths, and struct paths explicitly rejected
  until those storage layouts are implemented.
- Extended `ProofForge.IR.Examples.EvmMapProbe` with
  `path_assign_lifecycle()`, updated `Examples/Evm/EvmMapProbe.golden.yul`,
  and extended `scripts/evm/map-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-map-ir-yul -o build/ir/EvmMapProbe.yul
diff -u Examples/Evm/EvmMapProbe.golden.yul build/ir/EvmMapProbe.yul
scripts/evm/map-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmMapProbe Yul includes selector dispatch for
  `path_assign_lifecycle()` and map assign helpers for all `AssignOp`
  variants.
- Foundry verifies `path_assign_lifecycle()` returns `58`, the raw mapping
  slot for key `3003` is `58`, and existing map get/set/path behavior still
  passes.
- EVM artifact metadata records and validates `storage.scalar`, `storage.map`,
  and `assertions.check`.
- Diagnostics reject expression-position `storagePathAssignOp` and nested
  storage-path compound assignment.

Known limitations at the time of this entry:

- EVM IR storage path compound assignment supported only a single `mapKey` over
  `Map<U64, U64, N>`.
- Array index paths, struct field paths, nested paths, and non-`U64` map shapes
  remained explicit diagnostics.

Next step:

- Continue EVM portable IR support toward storage arrays, structs, aggregate
  ABI values, or checked arithmetic semantics.

### EVM IR Compound Assignment

Commit: feature commit for EVM IR compound assignment

Summary:

- Added EVM portable IR lowering for `Statement.assignOp` on mutable local
  `U32`/`U64` bindings.
- Added EVM portable IR lowering for statement-position
  `storageScalarAssignOp` on numeric scalar storage.
- Lowered arithmetic/bitwise compound assignment to Yul
  `add/sub/mul/div/mod/and/or/xor`, and lowered shifts with EVM operand order
  through `shl(shift, value)` and `shr(shift, value)`.
- Added type validation so compound assignment requires matching `U32` or
  `U64` operands, mutable local targets, and scalar numeric storage targets.
- Kept aggregate assignment targets and storage path compound assignment
  outside this local/scalar feature; the following map path entry closes the
  single-segment `mapKey` subset.
- Added `ProofForge.IR.Examples.EvmAssignOpProbe`,
  `--emit-evm-assign-op-ir-yul`, `--emit-evm-assign-op-ir-bytecode`,
  `Examples/Evm/EvmAssignOpProbe.golden.yul`, and
  `scripts/evm/assign-op-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-assign-op-ir-yul -o build/ir/EvmAssignOpProbe.yul
diff -u Examples/Evm/EvmAssignOpProbe.golden.yul build/ir/EvmAssignOpProbe.yul
scripts/evm/assign-op-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmAssignOpProbe Yul includes selector dispatch, local compound
  assignment, scalar storage `sstore(slot, op(sload(slot), value))`, and U32
  ABI range guards.
- Foundry verifies `compound_assignment(uint256)` returns `58`, raw storage
  slot `0` is `58`, `compound_u32(uint32)` returns `11`, and unknown selectors
  revert.
- EVM artifact metadata records and validates `storage.scalar`.
- Diagnostics reject non-local compound assignment targets, non-numeric
  compound operands, and expression-position scalar storage compound
  assignment.

Known limitations:

- EVM IR compound assignment in this entry supports only mutable local scalars
  and scalar storage; aggregate locals remain out of scope.
- Operations use raw EVM word semantics and do not add checked-overflow
  behavior.

Next step:

- Continue EVM portable IR support toward storage arrays, structs, aggregate
  ABI values, or storage-path compound updates.

### EVM IR Bounded Loops

Commit: feature commit for EVM IR bounded loops

Summary:

- Added EVM target support for `control.bounded_loop`.
- Added EVM portable IR lowering for statement-position `boundedFor`.
- Lowered bounded loops to Yul `for` loops with a static `let` index prelude,
  `lt(index, stopExclusive)` condition, and `index := add(index, 1)` post
  block.
- Added type validation for loop bodies with the loop index available as an
  immutable `U32` local.
- Added explicit diagnostics for invalid loop ranges and loop-local returns.
- Added `ProofForge.IR.Examples.EvmLoopProbe`,
  `--emit-evm-loop-ir-yul`, `--emit-evm-loop-ir-bytecode`,
  `Examples/Evm/EvmLoopProbe.golden.yul`, and
  `scripts/evm/loop-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-loop-ir-yul -o build/ir/EvmLoopProbe.yul
diff -u Examples/Evm/EvmLoopProbe.golden.yul build/ir/EvmLoopProbe.yul
scripts/evm/loop-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmLoopProbe Yul includes selector dispatch and a Yul `for` loop
  that increments scalar storage three times.
- Foundry verifies the returned value and raw storage slot are both `3`, plus
  unknown-selector revert behavior.
- EVM artifact metadata records and validates `control.bounded_loop`.
- Diagnostics reject invalid bounded-loop ranges and loop-local returns.

Known limitations:

- EVM IR bounded loops currently require static natural-number bounds from the
  portable IR node.
- Loop-local `return`, `break`, and `continue` are not modeled yet.

Next step:

- Continue expanding EVM portable IR support for aggregate values, storage
  arrays, structs, or compound assignment.

### EVM IR Crosscalls

Commit: feature commit for EVM IR crosscalls

Summary:

- Added EVM portable IR lowering for expression-position `crosscallInvoke`.
- Defined the EVM IR v0 crosscall policy: target is an address word, method is
  a low-32-bit selector, arguments are 32-byte words, the call uses zero ETH
  value, and the result is one 32-byte return word.
- Added arity-specific Yul helpers that pack calldata, call
  `call(gas(), target, 0, ...)`, revert on failed calls or short returns, and
  decode the returned word.
- Added type validation so crosscall target, method, and every argument must be
  `U64`.
- Added `ProofForge.IR.Examples.EvmCrosscallProbe`,
  `--emit-evm-crosscall-ir-yul`, `--emit-evm-crosscall-ir-bytecode`,
  `Examples/Evm/EvmCrosscallProbe.golden.yul`, and
  `scripts/evm/crosscall-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-crosscall-ir-yul -o build/ir/EvmCrosscallProbe.yul
diff -u Examples/Evm/EvmCrosscallProbe.golden.yul build/ir/EvmCrosscallProbe.yul
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmCrosscallProbe Yul includes selector dispatch, calldata size
  guards, zero/one/two-argument crosscall helpers, failed-call reverts,
  short-return reverts, and one-word return decoding.
- Foundry verifies a Solidity callee for zero/one/two argument calls, callee
  reverts, short returns, and unknown-selector reverts.
- EVM artifact metadata records and validates `crosscall.invoke`.
- Diagnostics reject malformed crosscall target, method, and argument types.

Known limitations at this slice:

- This first crosscall slice modeled only synchronous zero-value `call`.
- Later slices below add typed scalar returns and value-bearing typed scalar
  calls; `staticcall`, `delegatecall`, create/create2, aggregate
  arguments/returns, and variable-length return data remain future IR work.

Next step:

- Continue expanding the EVM portable IR surface toward typed scalar returns,
  aggregate ABI values, arrays, structs, or richer call semantics.

### EVM IR Typed Scalar Crosscalls

Commit: feature commit for EVM IR typed scalar crosscalls

Summary:

- Added portable IR `crosscallInvokeTyped` as a typed scalar-word crosscall
  expression while preserving the existing `crosscallInvoke` U64 behavior and
  helper names.
- Extended EVM lowering so typed crosscalls accept `Bool`, `U32`, `U64`, and
  `Hash` word arguments and return `Bool`, `U32`, `U64`, or `Hash`.
- Generated return-type-specific Yul helpers such as
  `__proof_forge_crosscall_1_bool`, `__proof_forge_crosscall_1_u32`, and
  `__proof_forge_crosscall_1_hash`; Bool and U32 helpers reject out-of-range
  return words after `returndatacopy`.
- Extended `EvmCrosscallProbe` with `call_remote_bool`, `call_remote_u32`, and
  `call_remote_hash`, plus Foundry callee methods for valid typed returns and
  malformed Bool/U32 return words.
- Added explicit EVM diagnostics for unsupported typed crosscall aggregate
  arguments/returns and an explicit Psy diagnostic because Psy IR v0 still only
  supports untyped Felt-returning `crosscallInvoke`.
- Updated golden Yul, EVM/Psy coverage manifests, validation gates, EVM target
  docs, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-crosscall-ir-yul -o build/ir/EvmCrosscallProbe.yul
diff -u Examples/Evm/EvmCrosscallProbe.golden.yul build/ir/EvmCrosscallProbe.yul
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/psy/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/check-ir-coverage-manifest.py
```

Result:

- Generated EvmCrosscallProbe Yul includes selector dispatch for the typed
  entrypoints, Bool/U32 calldata guards, typed crosscall helper names, and
  Bool/U32 return-data guards.
- Foundry verifies U64 zero/one/two-argument calls, Bool/U32/Hash typed return
  calls, callee reverts, short returns, invalid Bool/U32 return words, and
  unknown-selector reverts.
- EVM artifact metadata validates all six CrosscallProbe entrypoints and
  records `crosscall.invoke`.
- Diagnostics reject unsupported typed crosscall aggregate arguments/returns,
  while Psy rejects typed crosscalls explicitly instead of silently lowering
  them as Felt calls.

Known limitations:

- Portable IR EVM crosscalls still model only synchronous `call`.
- Aggregate arguments/returns, multi-word return data, `staticcall`,
  `delegatecall`, and create/create2 remain future IR work.

Next step:

- Continue closing EVM backend gaps around richer call semantics, ABI aggregate
  storage-backed surfaces, and unsupported-node diagnostics.

### EVM IR Value-Bearing Typed Crosscalls

Commit: feature commit for EVM IR value-bearing typed crosscalls

Summary:

- Added portable IR `crosscallInvokeValueTyped` for synchronous EVM calls that
  forward an explicit `U64` call-value expression while returning a typed
  scalar word.
- Extended EVM lowering with value-specific Yul helpers named like
  `__proof_forge_crosscall_value_0`; these helpers keep the same selector and
  calldata packing as scalar crosscalls but pass `call_value` into the EVM
  `call(gas(), target, call_value, ...)` value slot.
- Extended `EvmCrosscallProbe` with `call_remote_value`, implemented using
  `.nativeValue` so the entrypoint forwards the ETH received by the probe to a
  payable callee.
- Added Foundry coverage that calls the probe with value, asserts the payable
  callee receives `msg.value`, checks the callee balance, and verifies the probe
  does not retain the forwarded value.
- Added explicit EVM diagnostics for malformed call-value type and unsupported
  aggregate return type, plus an explicit Psy unsupported diagnostic for
  value-bearing typed crosscalls.
- Updated golden Yul, coverage manifests, validation gates, EVM target docs,
  backlog, and Chinese docs.

Validation run:

```sh
lake build
scripts/evm/crosscall-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/psy/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/psy/check-ir-coverage-manifest.py
```

Result:

- `EvmCrosscallProbe` now has seven metadata-validated entrypoints, including
  `call_remote_value:365f4a44`.
- Generated Yul includes `__proof_forge_crosscall_value_0(target, selector,
  call_value)` and passes the helper value parameter to the `call` opcode.
- Foundry verifies 12 crosscall runtime paths, including ETH forwarding through
  `probe.call{value: 1234}` to a payable callee.
- EVM and Psy diagnostics cover the new portable IR node instead of relying on
  missing-pattern or silent lowering behavior.

Known limitations:

- Value-bearing crosscalls are currently limited to synchronous EVM `call` and
  single scalar-word return data.
- `staticcall`, `delegatecall`, create/create2, aggregate arguments/returns,
  and multi-word or variable-length return data remain future IR work.

Next step:

- Continue closing EVM cross-contract gaps around richer call kinds and richer
  return-data encoding.

### EVM IR Events

Commit: feature commit for EVM IR events

Summary:

- Added EVM portable IR lowering for statement-position `eventEmit`.
- Defined the EVM IR v0 event policy:
  `topic0 = keccak256(Solidity-style event signature)` and log data is the
  sequence of 32-byte field words.
- Added event name and field validation: event names must be non-empty; event
  fields must be `U32`, `U64`, `Bool`, or `Hash`; event emission remains
  statement-only.
- Added `--emit-evm-event-ir-yul`, `--emit-evm-event-ir-bytecode`,
  `Examples/Evm/EventProbe.golden.yul`, and
  `scripts/evm/event-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-event-ir-yul -o build/ir/EventProbe.yul
diff -u Examples/Evm/EventProbe.golden.yul build/ir/EventProbe.yul
scripts/evm/event-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EventProbe Yul includes selector dispatch, calldata size guards,
  event signature hashing, field data writes, and `log1(0, 32, topic0)`.
- Foundry verifies recorded logs for emitter address, topic0, decoded data,
  and unknown-selector reverts.
- EVM artifact metadata records and validates `events.emit`.
- Diagnostics reject expression-position events and malformed event names.

Known limitations:

- Event data fields are limited to scalar word values.
- Indexed fields are now covered by `eventEmitIndexed`; aggregate event
  payloads and richer event declarations remain future work.

Next step:

- Extend aggregate event payloads or richer event declarations, or start
  cross-contract call lowering for the EVM portable IR backend.

### EVM IR Hash Words

Commit: feature commit for EVM IR hash words

Summary:

- Added EVM portable IR lowering for `Hash` as a one-word EVM `bytes32`
  representation across locals, ABI parameters, ABI returns, and scalar
  storage.
- Added `hash4` literal packing and dynamic `hashValue` packing from four
  `U64` limbs into one 256-bit word.
- Added Yul helper lowering for `hash` and `hash_two_to_one` using
  `keccak256(0, 32)` and `keccak256(0, 64)`.
- Added lightweight EVM IR type validation for the currently supported scalar
  and Hash subset so Hash/U64 mismatches fail before Yul generation.
- Added `ProofForge.IR.Examples.EvmHashProbe`,
  `--emit-evm-hash-ir-yul`, `--emit-evm-hash-ir-bytecode`,
  `Examples/Evm/EvmHashProbe.golden.yul`, and
  `scripts/evm/hash-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-hash-ir-yul -o build/ir/EvmHashProbe.yul
diff -u Examples/Evm/EvmHashProbe.golden.yul build/ir/EvmHashProbe.yul
scripts/evm/hash-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmHashProbe Yul includes selector dispatch, ABI calldata size
  guards, Hash literal packing, dynamic Hash packing, `keccak256` helpers,
  Hash scalar storage reads/writes, and one-word return encoding.
- Foundry verifies `bytes32` ABI params/returns, single-word and pair hashing,
  dynamic packing, Hash scalar storage, raw slot reads through `vm.load`, and
  unknown-selector reverts.
- EVM artifact metadata records and validates `crypto.hash` and
  `storage.scalar`.
- Diagnostics now treat Hash as supported in the EVM scalar subset and reject
  malformed Hash/U64 usage with explicit type mismatch messages.

Known limitations:

- EVM portable IR Hash currently uses a target-specific one-word `bytes32`
  representation; Psy still uses four Felt limbs.
- Hash map key/value shapes are still unsupported; EVM map support remains
  limited to `Map<U64, U64, N>`.
- Aggregate hashing inputs, arrays, structs, and events remain future work.

Next step:

- Extend EVM maps to additional scalar key/value shapes, or add event emission
  lowering with indexed topic/data metadata.

### EVM IR Storage Maps

Commit: feature commit for EVM IR storage maps

Summary:

- Added EVM portable IR lowering for `Map<U64, U64, N>` storage state.
- Added Solidity-style mapping slot helpers:
  `mstore(0, key)`, `mstore(32, slot)`, `keccak256(0, 64)`.
- Added EVM lowering for `storageMapGet`, `storageMapInsert`, and
  `storageMapSet`; expression-position set/insert return the previous value.
- Added single-segment `storagePathRead`/`storagePathWrite` support for
  `.mapKey` paths over `Map<U64, U64, N>`.
- Kept `storageMapContains` explicitly unsupported because EVM mappings do not
  track key presence without an auxiliary bitmap.
- Added `ProofForge.IR.Examples.EvmMapProbe`, `--emit-evm-map-ir-yul`,
  `--emit-evm-map-ir-bytecode`, `Examples/Evm/EvmMapProbe.golden.yul`, and
  `scripts/evm/map-ir-smoke.sh`.
- Updated EVM diagnostics, coverage manifest, CI, EVM target docs, validation
  gates, backlog, and Chinese docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-evm-map-ir-yul -o build/ir/EvmMapProbe.yul
diff -u Examples/Evm/EvmMapProbe.golden.yul build/ir/EvmMapProbe.yul
scripts/evm/map-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated EvmMapProbe Yul includes selector dispatch, scalar ABI calldata
  guards, map helper functions, map get/set/insert calls, assertion guards, and
  `keccak256(0, 64)` slot hashing.
- Foundry verifies lifecycle behavior, parameterized read/write behavior,
  single-segment `mapKey` storage paths, unknown-selector reverts, and raw
  mapping slots with `vm.load`.
- EVM artifact metadata records and validates `storage.scalar`, `storage.map`,
  and `assertions.check`.
- Diagnostics reject unsupported Hash map shapes, `storage.map.contains`, and
  malformed map storage paths.

Known limitations:

- EVM portable IR map support is currently limited to `Map<U64, U64, N>`.
- `storage.map.contains` remains unsupported until the IR models an EVM
  presence bitmap or a different target-specific presence policy.
- Nested map/struct/array storage paths are still rejected.

Next step:

- Extend maps to more scalar key/value shapes, or add EVM `crypto.hash`
  lowering with a clear Keccak-vs-portable-Hash semantic boundary.

### EVM IR Context Reads

Commit: feature commit for EVM IR context reads

Summary:

- Added EVM portable IR lowering for `contextRead` expressions:
  `userId -> caller()`, `contractId -> address()`, and
  `checkpointId -> number()`.
- Added an EVM selector to `ContextProbe` while preserving the existing Psy
  context fixture.
- Added `--emit-context-ir-yul` and `--emit-context-ir-bytecode` CLI modes.
- Added `Examples/Evm/ContextProbe.golden.yul` plus
  `scripts/evm/context-ir-smoke.sh`.
- Updated EVM capability metadata so `ContextProbe` validates
  `caller.sender`, `account.explicit`, and `env.block`.
- Updated EVM diagnostics, coverage manifest, CI, target docs, validation
  gates, backlog, and capability registry docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-context-ir-yul -o build/ir/ContextProbe.yul
diff -u Examples/Evm/ContextProbe.golden.yul build/ir/ContextProbe.yul
scripts/evm/context-ir-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
```

Result:

- Generated ContextProbe Yul contains selector dispatch for
  `sum_context(uint256,uint256)`, ABI calldata size guarding, and direct EVM
  context opcodes.
- Foundry verifies `caller()` via `vm.prank`, `number()` via `vm.roll`, and
  `address()` via an etched runtime address.
- EVM artifact metadata records and validates the three context capabilities.
- Statement-position context reads remain rejected with an explicit diagnostic.

Known limitations:

- The current portable `ContextField` set covers only user id, contract id, and
  checkpoint id.
- EVM context values are emitted as 256-bit words; address-width and narrower
  integer normalization are still future type-validation work.

Next step:

- Add EVM `crypto.hash` lowering with a clear Keccak-vs-portable-Hash semantic
  boundary, or start EVM storage map slot hashing.

### EVM Artifact Metadata

Commit: feature commit for EVM artifact metadata

Summary:

- Added EVM `proof-forge-artifact.json` emission to `proof-forge`
  bytecode-producing modes, covering both `--evm-bytecode` SDK builds and
  portable IR EVM bytecode fixtures.
- Added `--artifact-output` to override the metadata path; without an override,
  bytecode modes write `proof-forge-artifact.json` next to the bytecode output.
- Added metadata fields for schema version, target id/family, artifact kind,
  source kind/module, portable IR version, capability ids, selector-facing ABI,
  `solc` path/version, Yul/bytecode/source artifact hashes and byte sizes, and
  validation status.
- Added `scripts/evm/validate-artifact-metadata.py` for machine validation of
  EVM metadata files.
- Updated EVM IR smoke scripts and `scripts/evm/build-examples.sh` so generated
  metadata is validated in CI.
- Updated EVM target docs, validation gates, backlog, portable IR docs, and
  Chinese docs.

Validation run:

```sh
lake build
PATH="$HOME/.foundry/bin:$PATH" lake env proof-forge --evm-bytecode --root . --module contract \
  --artifact-output build/evm/Counter.proof-forge-artifact.json \
  -o build/evm/Counter.bin Examples/Evm/Contracts/Counter.lean
python3 scripts/evm/validate-artifact-metadata.py --root . \
  --expect-fixture Counter.lean \
  --expect-source-kind lean-sdk \
  build/evm/Counter.proof-forge-artifact.json
bash -n scripts/evm/*.sh
python3 -m py_compile scripts/evm/validate-artifact-metadata.py
scripts/evm/conditional-ir-smoke.sh
scripts/evm/assignment-ir-smoke.sh
scripts/evm/assert-ir-smoke.sh
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- SDK EVM bytecode builds emit validated metadata with source, Yul, bytecode,
  method selectors, and `solc` validation status.
- Portable IR EVM bytecode builds emit validated metadata with fixture name,
  source module, `irVersion: portable-ir-v0`, capability ids, ABI selectors,
  Yul/bytecode hashes, and validation status.
- Each EVM IR smoke now writes a fixture-specific metadata file to avoid
  parallel-run overwrite races.
- `scripts/evm/build-examples.sh` validates metadata for every SDK example with
  a sibling `.evm-methods` file.

Known limitations:

- EVM metadata is still build metadata, not a full deploy manifest.
- `capabilities` are populated for portable IR fixtures; SDK builds currently
  record method metadata but not inferred SDK capability ids.

Next step:

- Add EVM context or hashing lowering as the next isolated capability slice, or
  turn metadata into a unified target manifest when more targets share the
  schema.

### EVM IR Conditionals

Commit: feature commit for EVM IR conditionals

Summary:

- Added `control.conditional` to the EVM target profile.
- Extended `ProofForge.Backend.Evm.IR` to lower portable IR `if/else` into Yul
  `switch condition case 0 { else } default { then }` blocks.
- Kept branch-local `return` statements explicitly rejected because EVM IR
  `return` currently assigns the generated function result and does not yet
  emit Yul `leave` for early return semantics.
- Added an EVM selector to `ConditionalProbe` while preserving Psy output.
- Added `--emit-conditional-ir-yul` and
  `--emit-conditional-ir-bytecode` CLI modes.
- Added `Examples/Evm/ConditionalProbe.golden.yul` and
  `scripts/evm/conditional-ir-smoke.sh`, then wired the smoke into CI.
- Updated EVM diagnostics, coverage manifest, capability registry, validation
  docs, EVM target docs, and Chinese documentation.

Validation run:

```sh
lake build
lake env proof-forge --emit-conditional-ir-yul -o build/ir/ConditionalProbe.yul
diff -u Examples/Evm/ConditionalProbe.golden.yul build/ir/ConditionalProbe.yul
lake env proof-forge --emit-conditional-ir-psy -o build/psy/ConditionalProbe.psy
diff -u Examples/Psy/ConditionalProbe.golden.psy build/psy/ConditionalProbe.psy
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/conditional-ir-smoke.sh
scripts/evm/assignment-ir-smoke.sh
scripts/evm/assert-ir-smoke.sh
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- Generated ConditionalProbe Yul matches the checked-in golden fixture and
  contains Yul `switch` blocks for both then and else paths.
- Psy ConditionalProbe output remains unchanged after adding target-specific
  selector metadata.
- `scripts/evm/conditional-ir-smoke.sh` compiles ConditionalProbe to bytecode
  and passes Foundry tests for the expected conditional lifecycle result and
  unknown-selector revert behavior.
- EVM diagnostics now cover the remaining conditional boundary: branch-local
  return statements.

Known limitations:

- Conditional branch early returns are not supported until EVM IR return
  lowering grows Yul `leave`.
- The EVM IR backend still has minimal expression type validation.

Next step:

- Add EVM artifact metadata or scalar context/hash lowering as the next isolated
  feature slice.

### EVM IR Local Assignment

Commit: feature commit for EVM IR local assignment

Summary:

- Treated the capability-complete EVM backend prompt as an incremental
  validation contract: every portable IR node must either gain a positive EVM
  fixture or retain a documented diagnostic.
- Extended `ProofForge.Backend.Evm.IR` so mutable scalar local bindings lower
  to Yul `let` declarations.
- Extended EVM IR assignment lowering for local targets as Yul `:=`
  assignments, while keeping non-local assignment targets and compound
  assignment statements explicitly rejected.
- Added `ProofForge.IR.Examples.AssignmentProbe` with
  `reassignment(uint256)`, covering mutable `U64` and `Bool` locals plus a
  bool guard that depends on assignment.
- Added `--emit-assignment-ir-yul` and
  `--emit-assignment-ir-bytecode` CLI modes.
- Added `Examples/Evm/AssignmentProbe.golden.yul` and
  `scripts/evm/assignment-ir-smoke.sh`, then wired the smoke into CI.
- Updated EVM diagnostics, coverage manifest, validation docs, and the EVM
  target docs.

Validation run:

```sh
lake build
lake env proof-forge --emit-assignment-ir-yul -o build/ir/AssignmentProbe.yul
diff -u Examples/Evm/AssignmentProbe.golden.yul build/ir/AssignmentProbe.yul
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/assignment-ir-smoke.sh
scripts/evm/assert-ir-smoke.sh
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- Generated AssignmentProbe Yul matches the checked-in golden fixture and
  contains `let total := seed`, `total := add(total, 7)`, and
  `matched := eq(total, 12)`.
- `scripts/evm/assignment-ir-smoke.sh` compiles AssignmentProbe to bytecode and
  passes Foundry tests for the successful assignment path and the bool-guard
  revert path.
- EVM diagnostics now cover the remaining assignment boundaries: non-local
  assignment targets and compound assignment statements.

Known limitations:

- Local assignment support is scalar-only (`U32`, `U64`, `Bool`).
- Compound assignment, aggregate assignment paths, storage assignment paths,
  and artifact metadata remain separate EVM work items.

Next step:

- Add EVM IR statement-level conditional lowering or EVM artifact metadata as
  the next isolated feature slice.

### EVM IR Assertions

Commit: feature commit for EVM IR assertions

Summary:

- Added `assertions.check` to the EVM target profile and capability registry.
- Extended `ProofForge.Backend.Evm.IR` to lower portable IR `assert` into
  `if iszero(condition) { revert(0, 0) }`.
- Extended EVM IR `assertEq` lowering into
  `if iszero(eq(lhs, rhs)) { revert(0, 0) }`.
- Added an EVM selector to `AssertProbe` while preserving Psy's selector-ignore
  behavior.
- Added `--emit-assert-ir-yul` and `--emit-assert-ir-bytecode` CLI modes.
- Added `Examples/Evm/AssertProbe.golden.yul` and
  `scripts/evm/assert-ir-smoke.sh`, then wired the smoke into CI.
- Updated EVM diagnostics and coverage manifest to treat assertions as lowered
  instead of unsupported.

Validation run:

```sh
lake build
lake env proof-forge --emit-assert-ir-yul -o build/ir/AssertProbe.yul
diff -u Examples/Evm/AssertProbe.golden.yul build/ir/AssertProbe.yul
lake env proof-forge --emit-assert-ir-psy -o build/psy/AssertProbe.psy
diff -u Examples/Psy/AssertProbe.golden.psy build/psy/AssertProbe.psy
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/assert-ir-smoke.sh
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- Generated EVM AssertProbe Yul matches the checked-in golden fixture.
- Psy AssertProbe output remains unchanged after adding target-specific selector
  metadata.
- `scripts/evm/assert-ir-smoke.sh` compiles AssertProbe to bytecode and passes
  Foundry tests for both successful assertion execution and assertion-failure
  revert behavior.
- Existing EVM ABI scalar, IR Counter, SDK example build, and Foundry smoke
  gates still pass.

Known limitations:

- EVM assertions currently revert with empty revert data.
- Expression type validation is still minimal in the EVM IR backend.

Next step:

- Add EVM IR statement-level assignment or conditional lowering so larger
  portable IR fixtures can move from unsupported diagnostics to Foundry-backed
  positive coverage.

### EVM IR Scalar ABI Parameters

Commit: feature commit for EVM IR scalar ABI parameters

Summary:

- Added `ProofForge.IR.Examples.AbiScalarProbe` with `mix(uint256,uint32,bool)`
  and `same(uint256,uint256)` portable IR entrypoints.
- Extended `ProofForge.Backend.Evm.IR` so `U64`, `U32`, and `Bool` entrypoint
  parameters lower to Yul function parameters and dispatcher `calldataload`
  arguments.
- Added dispatcher ABI guards for short calldata, out-of-range `uint32`
  values, and invalid `bool` encodings.
- Added CLI modes:
  `--emit-abi-scalar-ir-yul` and `--emit-abi-scalar-ir-bytecode`.
- Added `Examples/Evm/AbiScalarProbe.golden.yul` and
  `scripts/evm/abi-scalar-ir-smoke.sh`, then wired the smoke into CI.
- Updated EVM diagnostics to reject only non-scalar ABI parameter types instead
  of rejecting every parameterized entrypoint.

Validation run:

```sh
lake build
lake env proof-forge --emit-abi-scalar-ir-yul -o build/ir/AbiScalarProbe.yul
diff -u Examples/Evm/AbiScalarProbe.golden.yul build/ir/AbiScalarProbe.yul
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/abi-scalar-ir-smoke.sh
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- Generated Yul includes selector dispatch for `mix` and `same`, calldata size
  guards, `uint32` range validation, and `bool` encoding validation.
- `scripts/evm/abi-scalar-ir-smoke.sh` compiles the fixture to bytecode,
  verifies the golden Yul snapshot, and passes Foundry tests for valid calls
  and malformed calldata reverts.
- EVM diagnostic smoke passes after replacing the obsolete all-parameter
  rejection with Unit/Hash ABI parameter diagnostics.
- Existing EVM SDK examples still build and the Foundry smoke suite passes all
  four tests.

Known limitations:

- This only covers scalar word ABI parameters and one-word returns.
- Aggregate ABI values, dynamic data, events, and artifact metadata remain
  pending.

Next step:

- Add the next EVM IR positive fixture for either assertions/reverts or
  statement-level assignment before expanding storage layout.

### EVM IR Coverage And Diagnostics Baseline

Commit: feature commit for EVM IR coverage and diagnostics

Summary:

- Added `Tests/EvmCoverage.tsv`, tracking every portable IR constructor as
  `lowered`, `validated`, `unsupported`, or `structural` for the current EVM
  IR backend.
- Added `scripts/evm/check-ir-coverage-manifest.py` so new portable IR nodes
  must be classified for EVM before CI passes.
- Added `Tests/EvmDiagnostics.lean` and `scripts/evm/diagnostic-smoke.sh`,
  covering explicit diagnostics for missing selectors, unsupported ABI
  parameters, missing returns, unsupported aggregate/control/storage/context
  surfaces, events, crosscalls, native value, and Hash expressions.
- Fixed the EVM IR backend to reject non-Unit entrypoints that do not end with
  a return statement instead of emitting an unassigned `result`.
- Wired the new EVM diagnostic and coverage gates into CI.

Validation run:

```sh
lake build
bash -n scripts/evm/*.sh
scripts/evm/diagnostic-smoke.sh
scripts/evm/check-ir-coverage-manifest.py
scripts/evm/ir-counter-smoke.sh
scripts/evm/build-examples.sh
scripts/evm/foundry-smoke.sh
git diff --check
```

Result:

- `scripts/evm/diagnostic-smoke.sh` passes 25 diagnostic cases.
- `scripts/evm/check-ir-coverage-manifest.py` confirms 91 portable IR
  constructor entries match `ProofForge/IR/Contract.lean`.
- The EVM IR Counter smoke still compiles to bytecode and passes Foundry.
- The existing EVM SDK examples still build and the Foundry smoke suite passes
  all four tests.

Known limitations:

- This feature does not expand EVM lowering support; unsupported surfaces remain
  explicit until implemented with Yul golden, solc, and Foundry coverage.
- EVM artifact metadata is still pending.

Next step:

- Start replacing selected `unsupported` EVM coverage rows with Dapp-style
  Yul/Foundry-backed positive fixtures, one feature at a time.

### Psy Fixed Array Equality

Commit: feature commit for Psy fixed-array equality

Summary:

- Allowed Psy IR equality validation for fixed-array value types after a Dargo
  probe confirmed Psy supports `assert_eq(xs, ys)`, `xs == ys`, and `xs != zs`
  for fixed arrays.
- Extended `ArrayProbe` with `array_predicates`, covering fixed-array
  `assert_eq`, equality, and inequality over `[Felt; 3]` locals.
- Updated `scripts/psy/array-smoke.sh` to compile and execute
  `array_predicates`, record `result_vm: [1]`, and include it in artifact
  metadata validation.

Validation run:

```sh
lake build
lake env proof-forge --emit-array-ir-psy -o build/psy/ArrayProbe.psy
diff -u Examples/Psy/ArrayProbe.golden.psy build/psy/ArrayProbe.psy
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/array-smoke.sh
git diff --check
```

Result:

- Generated ArrayProbe source includes `array_predicates`, using
  `assert_eq(xs, ys, ...)`, `xs == ys`, and `xs != zs`.
- `scripts/psy/array-smoke.sh` validates `sum_literal`,
  `storage_lifecycle`, and `array_predicates` through Dargo test, compile,
  execute, ABI generation, deploy manifest, and artifact metadata checks.
- Dargo execution returns `result_vm: [1]` for `array_predicates`.

Known limitations:

- This feature covers same-typed fixed-array equality only; mismatched element
  types and lengths still fail through the existing type checker.

Next step:

- Commit and push this single feature before starting the next Psy surface area.

### Psy Native U32 Storage Struct Paths

Commit: feature commit for Psy native U32 storage struct paths

Summary:

- Fixed Psy `storagePathWrite` so U32 paths only cast to Felt for the validated
  Felt-backed U32 storage-array representation.
- Allowed native U32 storage struct field paths to use Psy's own `u32` storage
  reference idiom for path writes, reads, and compound assignment.
- Extended `StorageNestedAggregateProbe` with a native `Profile.rank: u32`
  storage field across scalar struct and storage-array paths.
- Removed the obsolete diagnostic that rejected non-array U32 storage-path
  compound assignment.

Validation run:

```sh
lake build
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
diff -u Examples/Psy/StorageNestedAggregateProbe.golden.psy build/psy/StorageNestedAggregateProbe.psy
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/storage-nested-aggregate-smoke.sh
```

Result:

- Generated StorageNestedAggregateProbe source emits native `pub rank: u32`,
  native U32 path writes such as `c.person.profile.rank = 9u32`, and native
  U32 path compound assignment such as `c.person.profile.rank += 4u32`.
- `scripts/psy/diagnostic-smoke.sh` passes all 48 diagnostic cases after
  removing the obsolete unsupported U32 path case.
- `scripts/psy/storage-nested-aggregate-smoke.sh` passes `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  validation, and artifact metadata validation.
- Dargo execution returns `result_vm: [252]` for `storage_nested_lifecycle`.

Known limitations:

- Direct Psy `[u32; N]` contract storage arrays remain avoided because current
  `psyup` 0.1.0 rejects them with an `ArrayRef<u32, N>` mismatch.
- Map value compound assignment remains outside the supported storage-path
  surface.

Next step:

- Continue shrinking storage and ABI edge cases into Dargo-backed fixtures, one
  committed feature at a time.

### Psy U32 Storage Path Assignment

Commit: feature commit for Psy U32 storage path assignment

Summary:

- Extended Psy lowering for Felt-backed U32 storage arrays so
  `storagePathAssignOp` emits typed read/update/write code instead of raw Felt
  compound assignment.
- Covered all `AssignOp` variants in `U32StorageArrayProbe`: arithmetic,
  modulo, bitwise, and shifts.
- Kept non-array U32 storage-path compound assignment rejected with an explicit
  ProofForge diagnostic until that storage representation is validated.
- Updated the golden Psy source, Dargo smoke expected result, coverage matrix,
  and validation docs.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-array-smoke.sh
```

Result:

- Generated U32StorageArrayProbe source rewrites U32 storage-path compound
  assignment as `.get() as u32`, typed operation, then `as Felt` writeback.
- `scripts/psy/diagnostic-smoke.sh` passes all 49 diagnostic cases, including
  the remaining unsupported non-array U32 storage-path assignment boundary.
- `scripts/psy/u32-storage-array-smoke.sh` passes `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  validation, and artifact metadata validation.
- Dargo execution returns `result_vm: [28]` for `storage_lifecycle`.

Known limitations:

- Direct Psy `[u32; N]` contract storage arrays remain avoided because current
  `psyup` 0.1.0 rejects them with an `ArrayRef<u32, N>` mismatch.
- U32 storage-path compound assignment is supported only for the validated
  Felt-backed storage-array representation, not arbitrary U32 struct paths.
  This struct-path limitation is superseded by the native U32 storage struct
  path entry above.

Next step:

- Continue closing one Psy storage or expression gap per feature branch, with
  Dargo-backed smoke coverage before each commit.

### Psy Hash Storage Coverage

Commit: feature commit for Psy Hash storage coverage

Summary:

- Added `HashStorageProbe` as a portable IR fixture for native Psy scalar
  `Hash` storage and `[Hash; N]` storage arrays.
- Extended Psy state validation so `StateDecl.kind = .scalar` with
  `type = .hash` lowers to `pub root: Hash`.
- Added CLI emission through `--emit-hash-storage-ir-psy` plus a checked
  golden source fixture.
- Added `scripts/psy/hash-storage-smoke.sh` to validate `dargo test`,
  `dargo compile`, two `dargo execute` entrypoints, `dargo generate-abi`,
  deploy manifest generation, and artifact metadata validation.

Validation run:

```sh
lake build
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake env proof-forge --emit-hash-storage-ir-psy -o build/psy/HashStorageProbe.psy
diff -u Examples/Psy/HashStorageProbe.golden.psy build/psy/HashStorageProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/hash-storage-smoke.sh
git diff --check
```

Result:

- Generated HashStorageProbe source lowers `pub root: Hash`,
  `pub roots: [Hash; 2]`, scalar Hash read/write, indexed Hash array read/write,
  and generic storage-path read/write.
- Dargo execution validates `result_vm: [5, 6, 7, 8]` for scalar storage and
  `result_vm: [55, 66, 77, 88]` for storage-array access.

Known limitations:

- This does not change U32 storage arrays, which remain Felt-backed because
  Dargo v0.1.0 rejects direct `[u32; N]` contract storage arrays.

Next step:

- Continue replacing explicit unsupported storage diagnostics with
  Dargo-validated Psy storage idioms where the upstream toolchain accepts the
  shape.

### Psy Bool Storage Array Coverage

Commit: feature commit for Psy Bool storage array coverage

Summary:

- Added `BoolStorageArrayProbe` as a portable IR fixture for native Psy
  `[bool; N]` fixed arrays and `bool` storage arrays.
- Extended Psy state validation so `StateDecl.kind = .array N` with
  `type = .bool` lowers to `pub flags: [bool; N]`.
- Added CLI emission through `--emit-bool-storage-array-ir-psy` plus a checked
  golden source fixture.
- Replaced the previous unsupported bool storage-array diagnostic with an
  unsupported Unit storage-array diagnostic.
- Added `scripts/psy/bool-storage-array-smoke.sh` to validate `dargo test`,
  `dargo compile`, two `dargo execute` entrypoints, `dargo generate-abi`,
  deploy manifest generation, and artifact metadata validation.

Validation run:

```sh
lake build
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake env proof-forge --emit-bool-storage-array-ir-psy -o build/psy/BoolStorageArrayProbe.psy
diff -u Examples/Psy/BoolStorageArrayProbe.golden.psy build/psy/BoolStorageArrayProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/bool-storage-array-smoke.sh
git diff --check
```

Result:

- Generated BoolStorageArrayProbe source lowers local `[bool; 3]` arrays,
  `pub flags: [bool; 3]` storage arrays, indexed storage read/write, generic
  storage-path read/write, and `bool as Felt` return casts.
- Dargo execution validates `result_vm: [2]` for both `local_flags_sum` and
  `storage_lifecycle`.

Known limitations:

- This does not change the existing U32 storage-array representation; U32
  arrays remain Felt-backed because Dargo v0.1.0 rejects direct `[u32; N]`
  contract storage arrays.

Next step:

- Continue shrinking explicit unsupported diagnostics into Dargo-validated Psy
  support where the upstream toolchain accepts the target shape.

### Psy Bool Scalar Storage Coverage

Commit: feature commit for Psy Bool scalar storage coverage

Summary:

- Added `BoolStorageScalarProbe` as a portable IR fixture for native Psy
  `bool` scalar storage.
- Added CLI emission through `--emit-bool-storage-scalar-ir-psy` plus a
  checked golden source fixture.
- Added `scripts/psy/bool-storage-scalar-smoke.sh` to validate `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  generation, and artifact metadata validation.
- Extended Psy coverage evidence, validation docs, and CI golden checks.

Validation run:

```sh
lake build
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake env proof-forge --emit-bool-storage-scalar-ir-psy -o build/psy/BoolStorageScalarProbe.psy
diff -u Examples/Psy/BoolStorageScalarProbe.golden.psy build/psy/BoolStorageScalarProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/bool-storage-scalar-smoke.sh
git diff --check
```

Result:

- Generated BoolStorageScalarProbe source lowers scalar storage to
  `pub flag: bool`, native Bool reads/writes, and `bool as Felt` return casts.
- Dargo execution validates `result_vm: [1]`.

Known limitations:

- This entry covered native scalar `bool` storage only. The later
  BoolStorageArrayProbe entry supersedes the previous bool storage-array
  limitation.

Next step:

- Continue filling the Psy scalar/aggregate storage matrix one feature at a
  time, with Dargo execution backing each newly enabled shape.

### Psy Map Set Expression Return Coverage

Commit: feature commit for Psy map set expression returns

Summary:

- Added Psy lowering and type validation for `storageMapSet` when used as an
  expression, matching upstream `MapRef::set` returning the previous `Hash`.
- Extended `MapProbe` with `set_return_lifecycle` and
  `insert_return_lifecycle` to cover absent-key zero returns, previous-value
  returns, and latest-value reads.
- Updated the MapProbe generated test to bind side-effectful method results
  before assertion, avoiding Dargo repeated-evaluation behavior for direct
  calls inside `assert_eq`.
- Extended the MapProbe smoke to execute the new methods and validate artifact
  metadata against all returned results.

Validation run:

```sh
lake build
lake env proof-forge --emit-map-ir-psy -o build/psy/MapProbe.psy
diff -u Examples/Psy/MapProbe.golden.psy build/psy/MapProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/map-smoke.sh
```

Result:

- `set_return_lifecycle` returns `result_vm: [31, 32, 33, 34]`.
- `insert_return_lifecycle` returns `result_vm: [5, 6, 7, 8]`.

Known limitations:

- Psy map support remains deliberately limited to `Map<Hash, Hash, N>` until
  non-Hash map value semantics are modeled explicitly in the portable IR.

Next step:

- Continue converting upstream Psy map/storage semantics into fixture-backed
  ProofForge IR coverage.

### Psy Generic Test Fallback

Commit: feature commit for generic Psy fallback tests

Summary:

- Replaced the Psy backend's fixture-only test generation failure with a
  generic fallback test that instantiates `<Module>Ref`.
- Added `GenericEntrypointProbe` as a valid non-whitelisted portable IR fixture
  to prove that arbitrary supported modules can render `.psy` source.
- Added a Dargo-backed smoke script, golden source, CI golden check, deploy
  manifest generation, and artifact metadata validation for the new fixture.
- Added an explicit empty-state diagnostic because Dargo v0.1.0 rejects empty
  `#[derive(Storage)]` contracts.

Validation run:

```sh
lake build
bash -n scripts/psy/*.sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake env proof-forge --emit-generic-entrypoint-ir-psy -o build/psy/GenericEntrypointProbe.psy
diff -u Examples/Psy/GenericEntrypointProbe.golden.psy build/psy/GenericEntrypointProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/generic-entrypoint-smoke.sh
git diff --check
```

Result:

- Dargo accepts the generic generated test and executes
  `GenericEntrypointProbe.answer` with `result_vm: [42]`.
- Psy diagnostic smoke now covers 49 malformed or unsupported IR cases.

Known limitations:

- The generic fallback only proves source/package validity and ref
  instantiation. Fixture-specific behavior still needs dedicated assertions
  and smoke scripts when a feature has semantic expectations.

Next step:

- Continue closing expression and storage coverage gaps with one fixture-backed
  feature at a time.

### Psy Identifier Diagnostics

Commit: feature commit for Psy identifier validation

Summary:

- Added Psy backend validation for module, struct, field, state, entrypoint,
  parameter, local, and loop-index identifiers before source generation.
- Added duplicate declaration checks for struct names, state ids, entrypoint
  names, struct field ids, and entrypoint parameter names.
- Added diagnostic fixtures for invalid module identifiers, duplicate state
  ids, duplicate entrypoint names, and reserved local names.

Validation run:

```sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake build
git diff --check
```

Result:

- Psy diagnostic smoke now covers 48 malformed or unsupported IR cases.
- Invalid or ambiguous names fail in ProofForge before Dargo parsing or
  typechecking.

Known limitations:

- The reserved-word list covers Psy keywords and builtin names used by current
  generated source. If Psy adds new reserved identifiers upstream, this list
  should be updated with the toolchain bump.

Next step:

- Continue reducing Dargo-discovered failures into ProofForge diagnostics.

### Psy U32 Scalar Storage Coverage

Commit: feature commit for Psy U32 scalar storage coverage

Summary:

- Added `U32StorageScalarProbe` as a portable IR fixture for native Psy
  `u32` scalar storage.
- Added CLI emission through `--emit-u32-storage-scalar-ir-psy` plus a checked
  golden source fixture.
- Added `scripts/psy/u32-storage-scalar-smoke.sh` to validate `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  generation, and artifact metadata validation.
- Extended Psy coverage evidence, validation docs, and CI golden checks.

Validation run:

```sh
DARGO_STD_PATH=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/lib/psy-std/std.psy \
  /tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  test --file /tmp/proof_forge_probe/u32_scalar_storage.psy
lake build
bash -n scripts/psy/*.sh
lake env proof-forge --emit-u32-storage-scalar-ir-psy -o build/psy/U32StorageScalarProbe.psy
diff -u Examples/Psy/U32StorageScalarProbe.golden.psy build/psy/U32StorageScalarProbe.psy
scripts/psy/check-ir-coverage-manifest.py
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-scalar-smoke.sh
git diff --check
```

Result:

- Generated U32StorageScalarProbe source lowers scalar storage to
  `pub value: u32`, native U32 reads/writes, and scalar `+=`.
- Dargo execution validates `result_vm: [12]`.

Known limitations:

- This covers native scalar `u32` storage only. U32 storage arrays still use the
  existing Felt-backed representation because current `psyup` 0.1.0 rejects
  direct `[u32; N]` contract storage arrays.

Next step:

- Continue broadening Psy storage and ABI validation while keeping unsupported
  storage forms explicit.

### Psy Entrypoint Selector Diagnostic

Commit: feature commit for Psy selector rejection

Summary:

- Added a Psy backend validation rule that rejects `Entrypoint.selector?`
  before source generation.
- Documented that Psy/DPN entrypoints are addressed by contract method name via
  Dargo and the generated Psy ABI, so EVM-style selectors are target-invalid
  rather than ignored.
- Added a `Tests/PsyDiagnostics.lean` case to lock the diagnostic text.

Validation run:

```sh
scripts/psy/diagnostic-smoke.sh
scripts/psy/check-ir-coverage-manifest.py
lake build
git diff --check
```

Result:

- Malformed Psy IR modules with entrypoint selectors now fail with an explicit
  diagnostic instead of silently dropping selector metadata.

Known limitations:

- This does not add a Psy-native selector concept. If Psy later exposes stable
  selector metadata, the backend should model it separately from EVM selectors.

Next step:

- Continue expanding non-fixture-specific Psy package generation and deployment
  validation.

### Psy Shared Dargo Package Writer

Commit: feature commit for shared Psy Dargo package generation

Summary:

- Added `scripts/psy/write-dargo-package.py` as the shared package writer for
  Dargo-backed Psy smoke fixtures.
- Replaced repeated shell `rm`/`mkdir`/`cp`/`Dargo.toml` heredocs across all
  Dargo-backed smoke scripts with a single writer invocation.
- Kept a smoke-directory guard in the writer so it only rewrites `dargo-*`
  package directories.

Validation run:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  scripts/psy/write-dargo-package.py \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py \
  scripts/psy/check-ir-coverage-manifest.py
bash -n scripts/psy/*.sh
scripts/psy/check-ir-coverage-manifest.py
lake build
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-array-smoke.sh
```

Result:

- Both representative Dargo smokes generate packages through the shared writer,
  then pass `dargo test`, `dargo compile`, `dargo execute`, `dargo generate-abi`,
  deploy-manifest validation, and artifact metadata validation.
- Existing metadata source/package-source parity and `Dargo.toml` manifest
  validation continue to pass.

Known limitations:

- This factors local Dargo package creation only; upstream compressed genesis
  deploy JSON and live node/prover smoke remain separate deployment work.

Next step:

- Continue toward upstream genesis deploy JSON/local node research.

### Psy Dargo Package Source Metadata

Commit: feature commit for Psy Dargo package source metadata

Summary:

- Extended Psy artifact metadata to record the Dargo package source copy
  (`src/main.psy`) used by every Dargo-backed smoke fixture.
- Updated metadata validation to check the package source path, byte size,
  SHA-256 hash, and hash parity with the generated `.psy` source.
- Updated all Dargo-backed Psy smoke scripts to pass
  `"$PROJECT_DIR/src/main.psy"` into `write-artifact-metadata.py`.

Validation run:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py \
  scripts/psy/check-ir-coverage-manifest.py
bash -n scripts/psy/*.sh
lake build
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-array-smoke.sh
```

Result:

- Counter and U32StorageArrayProbe smoke metadata now include
  `artifacts.packageSource`.
- The metadata validator accepts the updated schema and proves the package
  source copy has the same SHA-256 hash as the generated source file.

Known limitations:

- This validates the generated Dargo package source copy, not upstream
  compressed genesis deploy JSON or live node/prover state.

Next step:

- Continue toward upstream genesis deploy JSON/local node research, or factor
  the repeated Dargo package generation into a reusable package writer.

### Psy Dargo Package Manifest Metadata

Commit: feature commit for Psy Dargo package manifest metadata

Summary:

- Extended Psy artifact metadata to record the generated Dargo package manifest
  (`Dargo.toml`) for every Dargo-backed smoke fixture.
- Updated metadata validation to check the manifest path, byte size, SHA-256
  hash, `[package]` section, `type = "bin"`, and `[dependencies]` section.
- Updated all Dargo-backed Psy smoke scripts to pass the generated
  `"$PROJECT_DIR/Dargo.toml"` into `write-artifact-metadata.py`.

Validation run:

```sh
python3 -m py_compile \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py
bash -n scripts/psy/*.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
```

Result:

- Counter smoke metadata now includes `artifacts.dargoManifest` with a checked
  hash and package manifest shape.
- The metadata validator accepts the updated schema after Dargo `test`,
  `compile`, `execute`, `generate-abi`, deploy manifest validation, and package
  manifest validation.

Known limitations:

- This records the generated Dargo package manifest, not Psy upstream compressed
  genesis deploy JSON or live node/prover state.

Next step:

- Continue toward upstream genesis deploy JSON/local node research, or factor
  the repeated Dargo package generation into a reusable package writer.

### Psy IR Coverage Manifest Gate

Commit: feature commit for Psy IR coverage manifest validation

Summary:

- Added `Tests/PsyCoverage.tsv` as a constructor-level coverage manifest for
  the portable IR surface used by the Psy backend.
- Added `scripts/psy/check-ir-coverage-manifest.py`, which parses
  `ProofForge/IR/Contract.lean` and fails if any tracked constructor is missing
  from the manifest or if the manifest contains stale/duplicate entries.
- Added CI and validation docs for the new gate so future IR expansion must
  classify each constructor as lowered, validated, unsupported, or structural.

Validation run:

```sh
python3 -m py_compile scripts/psy/check-ir-coverage-manifest.py
scripts/psy/check-ir-coverage-manifest.py
```

Result:

- The checker reports 88 constructor entries matching
  `ProofForge/IR/Contract.lean`.

Known limitations:

- The manifest is a structural guard, not behavioral proof. Supported rows still
  require fixture, golden, Dargo, and metadata validation when they describe
  runtime behavior.

Next step:

- Continue closing behavioral Psy gaps and use the manifest as a tripwire when
  extending the portable IR.

### Psy U32 Storage Array Lowering

Commit: feature commit for Psy U32 storage array coverage

Summary:

- Added `U32StorageArrayProbe` as a dedicated portable IR fixture for U32
  storage-array reads and writes.
- Extended Psy sourcegen so portable U32 storage arrays lower to Felt-backed
  Psy storage arrays. Writes use `u32 as Felt`; reads use `.get() as u32`.
- Reused the same representation for generic storage-path read/write effects
  over U32 array elements.
- Kept U32 storage-path compound assignment explicitly rejected, because direct
  Felt storage `+=` would not preserve a clear U32 storage arithmetic boundary.
- Added CLI, golden source, CI golden coverage, diagnostic coverage, Dargo
  smoke coverage, and validation docs for the new fixture.

Validation run:

```sh
lake build
lake env proof-forge --emit-u32-storage-array-ir-psy -o build/psy/U32StorageArrayProbe.psy
diff -u Examples/Psy/U32StorageArrayProbe.golden.psy build/psy/U32StorageArrayProbe.psy
scripts/psy/diagnostic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-storage-array-smoke.sh
```

Result:

- Generated U32StorageArrayProbe source matches the checked-in golden fixture.
- `scripts/psy/diagnostic-smoke.sh` passes all 43 diagnostic cases.
- `scripts/psy/u32-storage-array-smoke.sh` passes `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  validation, and artifact metadata validation.
- Dargo execution returns `result_vm: [48]` for `storage_lifecycle`.

Known limitations:

- Direct Psy `[u32; N]` contract storage arrays remain avoided because current
  `psyup` 0.1.0 rejects them with an `ArrayRef<u32, N>` mismatch.
- U32 storage-path compound assignment is still unsupported; use explicit
  read/update/write.

Next step:

- Move the Psy deployment track toward upstream compressed genesis deploy JSON
  and local node/prover smoke work, or continue broadening Lean-to-IR extraction
  into the now-supported Psy surface.

### Psy Storage Compound Assignment Effects

Commit: feature commit for Psy storage-reference compound assignment effects

Summary:

- Added portable IR storage effects for scalar storage compound assignment and
  generic storage-path compound assignment.
- Extended Psy sourcegen to lower storage refs such as `c.total += 3`,
  `c.person.profile.age += 2`, and `c.people[1].score -= 9` to native Psy
  assignment operators.
- Kept EVM IR v0 behavior explicit by rejecting the new storage compound
  effects with target-specific diagnostics.
- Extended `StorageNestedAggregateProbe` to validate scalar storage compound
  assignment, nested scalar storage paths, and storage-array scalar paths under
  Dargo execution.
- Added Psy diagnostics for storage compound effects used as expressions and
  malformed storage compound assignment value types.

Validation run:

```sh
lake build
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
diff -u Examples/Psy/StorageNestedAggregateProbe.golden.psy build/psy/StorageNestedAggregateProbe.psy
scripts/psy/diagnostic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/storage-nested-aggregate-smoke.sh
```

Result:

- Generated StorageNestedAggregateProbe source matches the checked-in golden
  fixture.
- `scripts/psy/diagnostic-smoke.sh` passes all 42 diagnostic cases.
- `scripts/psy/storage-nested-aggregate-smoke.sh` passes `dargo test`,
  `dargo compile`, `dargo execute`, `dargo generate-abi`, deploy manifest
  validation, and artifact metadata validation.
- Dargo execution returns `result_vm: [229]` for `storage_nested_lifecycle`.

Known limitations:

- Map storage values remain excluded from compound assignment because the
  current supported map shape uses `get`/`set` over `Map<Hash, Hash, N>`.
- U32 storage arrays remain explicitly rejected until a stable Dargo-compatible
  storage idiom is identified.

Next step:

- Continue with U32 storage-array research or move toward upstream genesis
  deploy JSON/local node smoke work.

### Psy Compound Assignment Lowering

Commit: feature commit for Psy compound assignment lowering

Summary:

- Added first-class `AssignOp` and `Statement.assignOp` nodes to the portable
  IR for `+=`, `-=`, `*=`, `/=`, `%=`, `|=`, `&=`, `^=`, `<<=`, and `>>=`.
- Lowered compound assignments to native Psy assignment operators for mutable
  local, array-index, and field-path assignment targets.
- Kept EVM IR v0 explicit by rejecting compound assignment statements with a
  dedicated diagnostic.
- Extended `U32ArithmeticProbe` with arithmetic compound assignment coverage
  and `BitwiseProbe` with Felt/U32 bitwise and shift compound assignment
  coverage.
- Added Psy diagnostics for malformed compound assignment value types and
  immutable compound assignment targets.

Validation run:

```sh
lake build
lake env proof-forge --emit-u32-arithmetic-ir-psy -o build/psy/U32ArithmeticProbe.psy
diff -u Examples/Psy/U32ArithmeticProbe.golden.psy build/psy/U32ArithmeticProbe.psy
lake env proof-forge --emit-bitwise-ir-psy -o build/psy/BitwiseProbe.psy
diff -u Examples/Psy/BitwiseProbe.golden.psy build/psy/BitwiseProbe.psy
scripts/psy/diagnostic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-arithmetic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/bitwise-smoke.sh
```

Result:

- Generated U32ArithmeticProbe and BitwiseProbe sources match the checked-in
  golden fixtures.
- `scripts/psy/diagnostic-smoke.sh` passes all 39 diagnostic cases.
- Dargo validates the updated U32ArithmeticProbe and BitwiseProbe sources with
  `test`, `compile`, `execute`, `generate-abi`, deploy manifest validation, and
  artifact metadata validation.

Known limitations:

- Compound assignment currently targets mutable local/aggregate assignment
  paths. Storage-reference compound assignment remains a separate design item
  because portable storage writes are modeled as effects.
- U32 storage arrays remain explicitly rejected until a stable Dargo-compatible
  storage idiom is identified.

Next step:

- Continue with U32 storage-array research or add storage-reference compound
  assignment effects if that becomes the next Psy surface to close.

### Psy Map Storage Path Lowering

Commit: feature commit for Psy map storage path coverage

Summary:

- Added `StoragePathSegment.mapKey` to the portable IR so generic storage path
  effects can target supported `Map<Hash, Hash, N>` state.
- Extended Psy storage path type resolution, validation, and source lowering so
  `storagePathRead "balances" #[.mapKey key]` lowers to `c.balances.get(key)`
  and `storagePathWrite "balances" #[.mapKey key] value` lowers to
  `c.balances.set(key, value)`.
- Added map path key validation and explicit diagnostics for malformed map
  paths or wrong key types.
- Extended `MapProbe` with `path_lifecycle`, updated its golden `.psy`, and
  updated `scripts/psy/map-smoke.sh` to execute both direct map effects and the
  generic map storage path entrypoint.

Validation run:

```sh
lake build
lake env proof-forge --emit-map-ir-psy -o build/psy/MapProbe.psy
diff -u Examples/Psy/MapProbe.golden.psy build/psy/MapProbe.psy
scripts/psy/diagnostic-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/map-smoke.sh
```

Result:

- Generated MapProbe source matches the checked-in golden fixture.
- `scripts/psy/diagnostic-smoke.sh` passes all 37 diagnostic cases.
- `scripts/psy/map-smoke.sh` passes `dargo test`, `dargo compile`,
  `dargo execute`, `dargo generate-abi`, deploy manifest validation, and
  artifact metadata validation.
- Dargo execution returns `result_vm: [55, 66, 77, 88]` for `map_lifecycle`
  and `result_vm: [77, 88, 99, 111]` for `path_lifecycle`.

Known limitations:

- Map storage paths currently support direct `Map<Hash, Hash, N>` key access.
  Nested map value traversal remains unsupported because Psy IR v0 only accepts
  Hash map values.
- U32 storage arrays remain explicitly rejected until a stable Dargo-compatible
  storage idiom is identified.

Next step:

- Continue with U32 storage-array research or decide whether compound
  assignment should become IR sugar.

### Psy Deploy Manifests For All Dargo Smokes

Commit: feature commit for broad Psy deploy manifest coverage

Summary:

- Added `scripts/psy/write-smoke-deploy-manifest.sh` as the shared smoke helper
  for deploy manifest generation and validation.
- Updated every Dargo-backed Psy smoke script to write
  `target/proof-forge-deploy.json`, validate it, and record it as `deployJson`
  inside `target/proof-forge-artifact.json`.
- Restored each smoke's deploy-oriented `dargo compile` artifact after
  `dargo execute` and `dargo generate-abi`, so deploy manifests describe the
  compile method set rather than an execution trace.
- Kept `scripts/psy/diagnostic-smoke.sh` separate because it validates
  pre-codegen diagnostics and does not produce Dargo artifacts.
- Updated validation docs, target notes, and backlog so the remaining deployment
  gap is specifically upstream compressed genesis deploy JSON plus local
  node/prover execution.

Validation run:

```sh
python3 -m py_compile \
  scripts/psy/write-deploy-manifest.py \
  scripts/psy/validate-deploy-manifest.py \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py
git diff --check
lake build
export PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy
export DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo
for script in scripts/psy/*-smoke.sh; do
  case "$script" in
    scripts/psy/diagnostic-smoke.sh) ;;
    *) "$script" ;;
  esac
done
scripts/psy/diagnostic-smoke.sh
```

Result:

- All Dargo-backed Psy smokes generated DPN circuit JSON, ABI JSON, execute
  logs, `proof-forge-deploy.json`, and `proof-forge-artifact.json`.
- Artifact metadata validation now checks deploy-manifest file hashes whenever
  `deployJson` is present.
- Deploy manifests record the restored compile method set for each fixture.
- `scripts/psy/diagnostic-smoke.sh` still passes all 35 diagnostic cases.

Known limitations:

- `proof-forge-deploy.json` remains ProofForge-owned metadata, not the upstream
  compressed genesis deploy JSON consumed by Psy node setup.
- The local node/prover deployment smoke is still not implemented.

Next step:

- Research whether to vendor or wrap Psy's `gen_deploy_json` path, then add the
  smallest local node/prover smoke that consumes the resulting deployment
  package.

### Psy Counter Deploy Manifest Metadata

Commit: feature commit for Psy Counter deploy manifest coverage

Summary:

- Added `scripts/psy/write-deploy-manifest.py` to produce
  `proof-forge-deploy.json` from the Counter `.psy` source, Dargo circuit JSON,
  and Dargo ABI JSON.
- Added `scripts/psy/validate-deploy-manifest.py` to verify manifest schema,
  deployer format, state-tree height, source/circuit/ABI hashes, function
  whitelist ordering, and upstream genesis JSON status.
- Updated `scripts/psy/counter-smoke.sh` so the Counter Dargo smoke now writes
  and validates `target/proof-forge-deploy.json`.
- Re-runs `dargo compile` after `dargo execute` so deploy metadata points at
  the deploy-oriented compile artifact rather than the method-sequence
  execution trace.
- Extended Psy artifact metadata to optionally record `deployJson` and require
  `validation.deployManifest = "passed"` whenever that artifact is present.
- Documented that this is a ProofForge deploy manifest, not Psy's upstream
  compressed genesis deploy JSON from `gen_deploy_json`.

Validation run:

```sh
python3 -m py_compile \
  scripts/psy/write-deploy-manifest.py \
  scripts/psy/validate-deploy-manifest.py \
  scripts/psy/write-artifact-metadata.py \
  scripts/psy/validate-artifact-metadata.py
git diff --check
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
```

Result:

- Counter generated source still matches `Examples/Psy/Counter.golden.psy`.
- Dargo `test`, `compile`, `execute`, and `generate-abi` passed.
- `dargo execute` returned `result_vm: [2]` after initialize plus two
  increments.
- `proof-forge-deploy.json` and `proof-forge-artifact.json` were generated and
  validated.

Known limitations:

- The manifest is ProofForge-owned metadata, not the upstream compressed
  genesis deploy JSON consumed by Psy node setup.
- The upstream `psy-dargo-cli/examples/gen_deploy_json.rs` path still requires
  Rust workspace internals; current released `dargo` does not expose it as a
  subcommand.
- Only the Counter smoke emits deploy manifest metadata so far.

Next step:

- Either extend deploy manifest generation to the broader Psy fixture set, or
  research the smallest stable upstream boundary for genesis deploy JSON plus a
  local Psy node/prover smoke.

### Psy U32HashPackingProbe Dynamic Hash Construction

Commit: feature commit for Psy U32 hash packing coverage

Summary:

- Added portable IR `Expr.hashValue` for dynamic `Hash` construction from four
  Felt-backed limbs.
- Extended Psy type validation so each dynamic Hash part must be `U64`/Felt and
  malformed Hash construction fails before `.psy` generation.
- Kept EVM IR v0 explicit by rejecting dynamic Hash value construction with a
  clear diagnostic.
- Added `ProofForge.IR.Examples.U32HashPackingProbe`, aligned with the
  `[u32; 8]` limb packing idioms in the deposit-tree and mining-rewards
  precompiles.
- Covered both local `[u32; 8]` literals and U32 ABI parameters packed into Psy
  `Hash` values through `lo + hi * 2^32`.
- Added an explicit rejection diagnostic for U32 storage arrays after Dargo
  validation showed current `psyup` 0.1.0 rejects direct `[u32; N]` contract
  storage arrays with an `ArrayRef<u32, N>` type mismatch.
- Added CLI support:

```sh
lake env proof-forge --emit-u32-hash-packing-ir-psy -o build/psy/U32HashPackingProbe.psy
```

- Added `Examples/Psy/U32HashPackingProbe.golden.psy`.
- Added `scripts/psy/u32-hash-packing-smoke.sh`, which generates a temporary
  Dargo package, runs `dargo test --file`, `dargo compile`, two
  `dargo execute` checks, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Added CI coverage for the U32HashPackingProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-u32-hash-packing-ir-psy -o build/psy/U32HashPackingProbe.psy
diff -u Examples/Psy/U32HashPackingProbe.golden.psy build/psy/U32HashPackingProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-hash-packing-smoke.sh
```

Result:

- Generated U32HashPackingProbe source matches the checked-in golden fixture.
- `scripts/psy/u32-hash-packing-smoke.sh` generated DPN JSON, ABI JSON,
  execute log, and `proof-forge-artifact.json`.
- `dargo execute` returned the expected four-Felt Hash values for both
  `pack_literal` and `pack_params`.
- `scripts/psy/diagnostic-smoke.sh` passed all 35 diagnostic cases.

Known limitations:

- This adds Hash value construction and U32 limb packing, not Psy deploy JSON
  or live node/prover execution.
- U32 storage arrays are explicitly rejected until a stable Psy storage idiom is
  validated against Dargo.
- Compound assignment operators remain represented as explicit assignment plus
  expression nodes.
- Map storage paths remain rejected until a stable Psy idiom is identified.

Next step:

- Decide whether to add compound assignment as IR sugar or leave it to a future
  source normalizer, then continue with map storage paths or deploy JSON.

### Psy BitwiseProbe Native Bitwise Expressions

Commit: feature commit for Psy bitwise expression coverage

Summary:

- Added portable IR expression nodes for `&`, `|`, `^`, `<<`, and `>>`.
- Extended Psy source generation for Felt-backed `U64` and `U32` bitwise
  expressions, with same-width numeric validation before `.psy` generation.
- Added EVM IR lowering for the same pure bitwise/shift nodes through Yul
  `and`, `or`, `xor`, `shl`, and `shr` builtins.
- Added explicit diagnostics for malformed bitwise and shift operands.
- Added `ProofForge.IR.Examples.BitwiseProbe`, aligned with upstream
  `psy-compiler/tests/opcode_test.psy`,
  `tests/storage_u32_assign_ops_test.psy`, and precompile Merkle path idioms.
- Added CLI support:

```sh
lake env proof-forge --emit-bitwise-ir-psy -o build/psy/BitwiseProbe.psy
```

- Added `Examples/Psy/BitwiseProbe.golden.psy`.
- Added `scripts/psy/bitwise-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the BitwiseProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-bitwise-ir-psy -o build/psy/BitwiseProbe.psy
diff -u Examples/Psy/BitwiseProbe.golden.psy build/psy/BitwiseProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/bitwise-smoke.sh
```

Result:

- Generated BitwiseProbe source matches the checked-in golden fixture.
- `scripts/psy/bitwise-smoke.sh` generated DPN JSON, ABI JSON, execute log,
  and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [16]` for `bitwise_mix`.
- `scripts/psy/diagnostic-smoke.sh` passed all 33 diagnostic cases.

Known limitations:

- Compound assignment operators such as `|=`, `&=`, `^=`, `<<=`, and `>>=`
  are still represented as explicit assignment plus expression nodes.
- This does not yet add u32 storage arithmetic probes or map storage paths.

Next step:

- Add storage-heavy U32/Hash limb packing probes from the deposit-tree and
  mining-rewards precompiles, then decide whether compound assignment sugar
  belongs in the portable IR or only in sourcegen normalization.

### Psy U32ArithmeticProbe Native U32 Arithmetic

Commit: feature commit for Psy U32 arithmetic coverage

Summary:

- Added portable IR `ValueType.u32` and `Literal.u32`.
- Added portable IR expression nodes for division, modulo, exponentiation, and
  explicit casts.
- Extended Psy source generation for `u32`, `Nu32` literals, `/`, `%`, `**`,
  and casts such as `z as bool` and `bb as Felt`.
- Updated bounded-loop typing so generated `for i in 0u32..Nu32` loop indices
  are tracked as `U32`.
- Extended numeric type validation so `U32` arithmetic remains type-consistent
  and malformed mixed-width arithmetic fails before source generation.
- Added EVM IR lowering for the new pure arithmetic/cast nodes through Yul
  builtins or no-op casts.
- Added `ProofForge.IR.Examples.U32ArithmeticProbe`, mirroring the core
  executable shape of upstream `psy-compiler/tests/u32_test.psy`.
- Added CLI support:

```sh
lake env proof-forge --emit-u32-arithmetic-ir-psy -o build/psy/U32ArithmeticProbe.psy
```

- Added `Examples/Psy/U32ArithmeticProbe.golden.psy`.
- Added `scripts/psy/u32-arithmetic-smoke.sh`, which generates a temporary
  Dargo package, runs `dargo test --file`, `dargo compile`, `dargo execute
  --parameters 2,3`, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Added CI coverage for the U32ArithmeticProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-u32-arithmetic-ir-psy -o build/psy/U32ArithmeticProbe.psy
diff -u Examples/Psy/U32ArithmeticProbe.golden.psy build/psy/U32ArithmeticProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/u32-arithmetic-smoke.sh
```

Result:

- Generated U32ArithmeticProbe source matches the checked-in golden fixture.
- `scripts/psy/u32-arithmetic-smoke.sh` generated DPN JSON, ABI JSON, execute
  log, and `proof-forge-artifact.json`.
- `dargo execute --parameters 2,3` returned `result_vm: [1]` for
  `u32_arithmetic`.
- `scripts/psy/diagnostic-smoke.sh` passed all 31 diagnostic cases.

Known limitations:

- This does not yet add bitwise shifts, bitwise and/or, u32 storage probes, or
  the full cast matrix used by the token/deposit-tree precompiles.
- Cast lowering is intentionally explicit and rejects unsupported source/target
  pairs before `.psy` source generation.

Next step:

- Add bitwise operations and u32 array/hash-packing probes, since the Psy
  precompiles use `u32` limbs heavily for token addresses and tree roots.

### Psy ArithmeticProbe Sub/Mul Expressions

Commit: feature commit for Psy arithmetic expression coverage

Summary:

- Added portable IR expression nodes for subtraction and multiplication.
- Added Psy source generation for `-` and `*`, including parentheses around
  nested arithmetic operands where precedence would otherwise change meaning.
- Added sourcegen diagnostics for malformed subtraction and multiplication
  operand types.
- Added EVM IR lowering for the same pure arithmetic nodes through Yul builtins.
- Added `ProofForge.IR.Examples.ArithmeticProbe`, covering subtraction,
  multiplication, and nested arithmetic precedence.
- Added CLI support:

```sh
lake env proof-forge --emit-arithmetic-ir-psy -o build/psy/ArithmeticProbe.psy
```

- Added `Examples/Psy/ArithmeticProbe.golden.psy`.
- Added `scripts/psy/arithmetic-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the ArithmeticProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-arithmetic-ir-psy -o build/psy/ArithmeticProbe.psy
diff -u Examples/Psy/ArithmeticProbe.golden.psy build/psy/ArithmeticProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/arithmetic-smoke.sh
```

Result:

- Generated ArithmeticProbe source matches the checked-in golden fixture.
- `scripts/psy/arithmetic-smoke.sh` generated DPN JSON, ABI JSON, execute log,
  and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [60]` for `arithmetic_mix`.
- `scripts/psy/diagnostic-smoke.sh` passed all 29 diagnostic cases.

Known limitations:

- This adds subtraction and multiplication, not division, modulo,
  exponentiation, cast-heavy `u32` arithmetic, or compound assignment operators.
- The IR still represents these values as `U64` mapped to Psy `Felt`; a
  dedicated `U32` surface should be added before copying upstream `u32_test`
  semantics directly.

Next step:

- Add division/modulo only after deciding whether they belong to Felt-backed
  `U64`, a new `U32` value type, or target-specific checked arithmetic helpers.

### Psy ConditionalProbe Statement If/Else

Commit: feature commit for Psy conditional statement coverage

Summary:

- Added portable IR `Statement.ifElse` with a new `control.conditional`
  capability.
- Added Psy source generation for `if condition { ... } else { ... };`, aligned
  with upstream `.psy` conditional syntax.
- Added sourcegen diagnostics for non-Bool if conditions and branch-local
  bindings escaping their branch.
- Kept EVM IR v0 explicit by rejecting statement-level if/else.
- Added `ProofForge.IR.Examples.ConditionalProbe`, covering then and else branch
  execution over scalar storage.
- Added CLI support:

```sh
lake env proof-forge --emit-conditional-ir-psy -o build/psy/ConditionalProbe.psy
```

- Added `Examples/Psy/ConditionalProbe.golden.psy`.
- Added `scripts/psy/conditional-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the ConditionalProbe Psy golden source snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-conditional-ir-psy -o build/psy/ConditionalProbe.psy
diff -u Examples/Psy/ConditionalProbe.golden.psy build/psy/ConditionalProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/conditional-smoke.sh
```

Result:

- Generated ConditionalProbe source matches the checked-in golden fixture.
- `scripts/psy/conditional-smoke.sh` generated DPN JSON, ABI JSON, execute log,
  and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [10]` for `conditional_lifecycle`.
- `scripts/psy/diagnostic-smoke.sh` passed all 27 diagnostic cases.

Known limitations:

- This adds statement-level if/else, not else-if syntax sugar.
- Non-unit entrypoints still need an explicit final top-level return statement;
  return coverage through both conditional branches is not analyzed yet.

Next step:

- Continue broadening Psy expression/arithmetic coverage or add map storage path
  support once a stable upstream Psy idiom is identified.

### Psy ExpressionPredicateProbe Boolean Predicates

Commit: feature commit for Psy predicate expression coverage

Summary:

- Added portable IR expression nodes for equality, inequality, ordering
  comparisons, boolean conjunction, boolean disjunction, and boolean negation.
- Added Psy lowering using upstream `.psy` idioms: `==`, `!=`, `<`, `<=`, `>`,
  `>=`, `&&`, `||`, and `!`.
- Added sourcegen type diagnostics for malformed equality, comparison, and
  boolean operator operands.
- Added EVM IR lowering for the same pure predicate nodes through Yul builtins.
- Added `ProofForge.IR.Examples.ExpressionPredicateProbe`, covering predicate
  locals and assertion predicates.
- Added CLI support:

```sh
lake env proof-forge --emit-expression-predicate-ir-psy -o build/psy/ExpressionPredicateProbe.psy
```

- Added `Examples/Psy/ExpressionPredicateProbe.golden.psy`.
- Added `scripts/psy/expression-predicate-smoke.sh`, which generates a
  temporary Dargo package, runs `dargo test --file`, `dargo compile`,
  `dargo execute`, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Added CI coverage for the ExpressionPredicateProbe Psy golden source
  snapshot.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-expression-predicate-ir-psy -o build/psy/ExpressionPredicateProbe.psy
diff -u Examples/Psy/ExpressionPredicateProbe.golden.psy build/psy/ExpressionPredicateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/expression-predicate-smoke.sh
```

Result:

- Generated ExpressionPredicateProbe source matches the checked-in golden
  fixture.
- `scripts/psy/expression-predicate-smoke.sh` generated DPN JSON, ABI JSON,
  execute log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [16]` for `predicate_sum`.
- `scripts/psy/diagnostic-smoke.sh` passed all 25 diagnostic cases.

Known limitations:

- This adds expression predicates, not statement-level `if/else` lowering.
- Fixed-array equality was outside this original expression fixture; it is now
  covered separately by the Dargo-backed `ArrayProbe`.

Next step:

- Add statement-level conditional lowering or broaden arithmetic expression
  coverage with upstream/Dargo fixtures.

### Psy Sourcegen Type Diagnostics

Commit: feature commit for Psy expression and statement type diagnostics

Summary:

- Added a lightweight Psy backend type environment for entrypoint parameters,
  local bindings, mutable locals, and bounded-loop indices.
- Added sourcegen-time type inference and validation for literals, locals,
  fixed arrays, struct literals, field access, addition, hash operations,
  storage effects, context reads, assignment targets, assertions, and returns.
- Added diagnostics for unknown locals, local/array/struct/hash type
  mismatches, immutable assignment, missing non-unit returns, and storage write
  type mismatches.
- Kept existing lowering behavior unchanged for valid fixtures; this feature
  blocks malformed IR before `.psy` source is emitted.
- Extended `Tests/PsyDiagnostics.lean` from 12 to 22 explicit rejection cases.

Validation run:

```sh
lake build
scripts/psy/diagnostic-smoke.sh
lake env proof-forge --emit-counter-ir-psy -o build/psy/Counter.psy
diff -u Examples/Psy/Counter.golden.psy build/psy/Counter.psy
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
diff -u Examples/Psy/StorageNestedAggregateProbe.golden.psy build/psy/StorageNestedAggregateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/{counter,context,hash,map,assert,loop,array,struct,struct-array,abi-aggregate,nested-aggregate,storage-nested-aggregate}-smoke.sh
```

Result:

- `scripts/psy/diagnostic-smoke.sh` passed all 22 diagnostic cases.
- All checked Psy golden source snapshots remain unchanged.
- All Psy Dargo smokes passed and revalidated source snapshots, DPN JSON, ABI
  JSON, execute logs, and `proof-forge-artifact.json`.

Known limitations:

- This is a sourcegen validation layer, not a formal type system for every
  future portable IR extension.
- Assignment mutability is enforced for local/index/field paths rooted in local
  bindings; storage mutation continues to use explicit storage effects.

Next step:

- Continue closing Psy valid-surface gaps with either Dargo-backed fixtures or
  explicit diagnostics before adding new IR nodes.

### Psy StorageNestedAggregateProbe Storage Paths

Commit: feature commit for storage nested aggregate Psy IR coverage

Summary:

- Added generic storage path read/write effects to the portable IR.
- Added `StructField.isRef` so the IR can explicitly model Psy `#[ref]`
  fields for nested storage references.
- Added Psy lowering for storage paths such as `c.person.profile.age` and
  `c.people[1].profile.age`, plus validation for empty paths and missing
  nested `#[ref]` markers.
- Kept EVM IR v0 behavior explicit by rejecting storage path effects.
- Added `ProofForge.IR.Examples.StorageNestedAggregateProbe`, covering scalar
  struct storage and fixed storage arrays of structs.
- Added CLI support:

```sh
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
```

- Added `Examples/Psy/StorageNestedAggregateProbe.golden.psy`.
- Added `scripts/psy/storage-nested-aggregate-smoke.sh`, which generates a
  temporary Dargo package, runs `dargo test --file`, `dargo compile`,
  `dargo execute`, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Extended `Tests/PsyDiagnostics.lean` with invalid storage path cases.
- Added CI coverage for the StorageNestedAggregateProbe Psy golden source
  snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-storage-nested-aggregate-ir-psy -o build/psy/StorageNestedAggregateProbe.psy
diff -u Examples/Psy/StorageNestedAggregateProbe.golden.psy build/psy/StorageNestedAggregateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/storage-nested-aggregate-smoke.sh
scripts/psy/diagnostic-smoke.sh
```

Result:

- Generated StorageNestedAggregateProbe source matches the checked-in golden
  fixture.
- `scripts/psy/storage-nested-aggregate-smoke.sh` generated DPN JSON, ABI JSON,
  execute log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [220]` for
  `storage_nested_lifecycle`.
- `scripts/psy/diagnostic-smoke.sh` passed all 12 diagnostic cases.

Known limitations:

- Storage path lowering intentionally rejects map storage paths until a stable
  Psy idiom is identified and covered by an upstream-style fixture.
- This does not yet produce deploy JSON or exercise a live Psy node/prover.

Next step:

- Research deploy JSON/live node execution for Psy artifacts, or continue
  expanding expression/path coverage behind diagnostic gates.

### Psy NestedAggregateProbe Mixed Aggregate Updates

Commit: feature commit for nested aggregate Psy IR coverage

Summary:

- Added portable IR statements for mutable local bindings and assignment.
- Added Psy lowering for `let mut` and nested assignment targets made from
  local names, array indexes, and field paths.
- Kept EVM IR v0 behavior explicit by rejecting mutable local bindings and
  assignment statements.
- Added `ProofForge.IR.Examples.NestedAggregateProbe`, covering a mutable
  `[Family; 2]` value whose `Family.children` field is `[Member; 2]`.
- Added CLI support:

```sh
lake env proof-forge --emit-nested-aggregate-ir-psy -o build/psy/NestedAggregateProbe.psy
```

- Added `Examples/Psy/NestedAggregateProbe.golden.psy`.
- Added `scripts/psy/nested-aggregate-smoke.sh`, which generates a temporary
  Dargo package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Extended `Tests/PsyDiagnostics.lean` with an invalid assignment target case.
- Added CI coverage for the NestedAggregateProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-nested-aggregate-ir-psy -o build/psy/NestedAggregateProbe.psy
diff -u Examples/Psy/NestedAggregateProbe.golden.psy build/psy/NestedAggregateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/nested-aggregate-smoke.sh
scripts/psy/diagnostic-smoke.sh
```

Result:

- `lake build` passed.
- Generated NestedAggregateProbe source matches the checked-in golden fixture.
- `scripts/psy/nested-aggregate-smoke.sh` generated DPN JSON, ABI JSON,
  execute log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [51]` for `nested_update_sum`.
- `scripts/psy/diagnostic-smoke.sh` passed all 10 diagnostic cases.

Known limitations:

- This feature covers local nested aggregate mutation, not storage-backed
  nested aggregate mutation.
- Assignment targets are intentionally limited to local/index/field paths.

Next step:

- Add storage-backed nested aggregate updates or deploy JSON metadata.

### Psy Unsupported Diagnostic Gate

Commit: feature commit for Psy diagnostic regression coverage

Summary:

- Added `Tests/PsyDiagnostics.lean`, a runnable Lean diagnostic regression
  suite for Psy IR rejection paths.
- Added `scripts/psy/diagnostic-smoke.sh`.
- Covered explicit diagnostics for:
  - Unit entrypoint parameters
  - zero-length ABI fixed arrays
  - unknown ABI struct types
  - unsupported map key/value shapes
  - structs used in storage without `deriveStorage`
  - empty struct declarations
  - invalid bounded loop ranges
  - storage writes used as expressions
  - storage reads used as statements
  - invalid assignment targets
- Added the diagnostic smoke to CI.
- Documented the gate in README, validation gates, and `psy-dpn` target notes.

Validation run:

```sh
scripts/psy/diagnostic-smoke.sh
lake build
```

Result:

- `scripts/psy/diagnostic-smoke.sh` passed all 10 diagnostic cases.
- `lake build` passed.

Known limitations:

- This is a regression gate for representative unsupported shapes, not an
  exhaustive formal proof over every impossible IR construction.
- Cross-target capability rejection matrices still need broader coverage.

Next step:

- Expand diagnostics as new Psy IR nodes are added, then continue with deeper
  mixed aggregate update coverage or deploy JSON metadata.

### Psy AbiAggregateProbe ABI Aggregates

Commit: feature commit for ABI aggregate Psy IR coverage

Summary:

- Added entrypoint ABI type validation for Psy IR parameters and returns.
- Rejected Unit parameters before source generation, while keeping Unit returns
  valid for void methods.
- Validated entrypoint fixed-array ABI types as non-empty and struct ABI types
  as declared.
- Added `ProofForge.IR.Examples.AbiAggregateProbe`, covering a struct
  parameter, fixed-array parameter, and struct return value.
- Added CLI support:

```sh
lake env proof-forge --emit-abi-aggregate-ir-psy -o build/psy/AbiAggregateProbe.psy
```

- Added `Examples/Psy/AbiAggregateProbe.golden.psy`.
- Added `scripts/psy/abi-aggregate-smoke.sh`, which generates a temporary
  Dargo package, runs `dargo test --file`, `dargo compile`, three
  `dargo execute` calls, `dargo generate-abi`, and validates
  `proof-forge-artifact.json`.
- Added CI coverage for the AbiAggregateProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-abi-aggregate-ir-psy -o build/psy/AbiAggregateProbe.psy
diff -u Examples/Psy/AbiAggregateProbe.golden.psy build/psy/AbiAggregateProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/abi-aggregate-smoke.sh
```

Result:

- `lake build` passed.
- Generated AbiAggregateProbe source matches the checked-in golden fixture.
- `scripts/psy/abi-aggregate-smoke.sh` generated DPN JSON, ABI JSON, execute
  log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [15]` for `sum_pair`.
- `dargo execute` returned `result_vm: [6]` for `sum_array`.
- `dargo execute` returned `result_vm: [9, 4]` for `make_pair`.

Known limitations:

- Dargo CLI aggregate execution is flattened to Felt vectors.
- This feature validates flat struct and one-dimensional fixed-array ABI
  shapes, not deeply nested mixed aggregate ABI shapes.

Next step:

- Add deeper nested mixed aggregate update and ABI coverage from the upstream
  Psy syntax corpus, then continue toward deploy JSON metadata.

### Psy StructArrayProbe Struct Arrays

Commit: feature commit for struct-array Psy IR coverage

Summary:

- Extended portable IR storage effects with indexed storage array struct field
  read/write nodes.
- Extended Psy sourcegen to lower storage arrays of structs, whole struct array
  element writes, and indexed struct field reads through `.get()`.
- Extended Psy state validation so fixed storage arrays can use `deriveStorage`
  struct element types.
- Kept EVM IR v0 behavior explicit by rejecting storage array struct field
  effects.
- Added `ProofForge.IR.Examples.StructArrayProbe`, covering local `[Person; 2]`
  struct arrays plus fixed storage arrays of structs.
- Added CLI support:

```sh
lake env proof-forge --emit-struct-array-ir-psy -o build/psy/StructArrayProbe.psy
```

- Added `Examples/Psy/StructArrayProbe.golden.psy`.
- Added `scripts/psy/struct-array-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, two `dargo execute`
  calls, `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the StructArrayProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-struct-array-ir-psy -o build/psy/StructArrayProbe.psy
diff -u Examples/Psy/StructArrayProbe.golden.psy build/psy/StructArrayProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/struct-array-smoke.sh
```

Result:

- `lake build` passed.
- Generated StructArrayProbe source matches the checked-in golden fixture.
- `scripts/psy/struct-array-smoke.sh` generated DPN JSON, ABI JSON, execute
  log, and `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [100]` for
  `local_struct_array_sum`.
- `dargo execute` returned `result_vm: [102]` for
  `storage_struct_array_lifecycle`.

Known limitations:

- This feature covers one-dimensional arrays of flat structs.
- Deeply nested mixed aggregate updates still need dedicated coverage.
- EVM IR v0 explicitly rejects struct-array storage field effects.

Next step:

- Add ABI-facing entrypoint aggregate parameters or return-shape validation,
  then continue toward deployment/deploy JSON metadata.

### Psy StructProbe Struct Values And Storage

Commit: feature commit for struct Psy IR coverage

Summary:

- Extended portable IR with struct declarations, struct value types, struct
  literals, and field access expressions.
- Registered `data.struct` as a target capability for struct values and field
  access.
- Extended portable IR storage effects with scalar storage struct field
  read/write nodes.
- Extended Psy sourcegen to emit `#[derive(Storage)]` struct declarations,
  `new Struct { ... }` literals, local field access, scalar storage struct
  assignment, and storage struct field reads through `.get()`.
- Kept EVM IR v0 behavior explicit by rejecting struct literals, field access,
  struct typed let bindings, struct returns, and storage struct field effects.
- Added `ProofForge.IR.Examples.StructProbe`, covering local struct literals
  plus scalar storage struct read/write behavior.
- Added CLI support:

```sh
lake env proof-forge --emit-struct-ir-psy -o build/psy/StructProbe.psy
```

- Added `Examples/Psy/StructProbe.golden.psy`.
- Added `scripts/psy/struct-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, two `dargo execute`
  calls, `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the StructProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-struct-ir-psy -o build/psy/StructProbe.psy
diff -u Examples/Psy/StructProbe.golden.psy build/psy/StructProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/struct-smoke.sh
```

Result:

- `lake build` passed.
- Generated StructProbe source matches the checked-in golden fixture.
- `scripts/psy/struct-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [30]` for `local_sum`.
- `dargo execute` returned `result_vm: [26]` for `storage_lifecycle`.

Known limitations:

- This feature covers flat struct values and scalar storage structs.
- Struct arrays, nested structs, and methods on structs still need dedicated
  coverage.
- EVM IR v0 explicitly rejects struct IR nodes.

Next step:

- Combine structs with fixed arrays in a follow-up fixture aligned with
  upstream `array_test.psy` and `array_ref_struct_index_test.psy`.

### Psy ArrayProbe Fixed Arrays

Commit: feature commit for fixed-array Psy IR coverage

Summary:

- Extended portable IR types with fixed arrays, represented as `[T; N]` in Psy.
- Added `data.fixed_array` for fixed-size array values and `storage.array` for
  fixed array storage fields.
- Extended portable IR expressions with fixed array literals and index reads.
- Extended portable IR storage effects with fixed array index read/write nodes.
- Extended Psy sourcegen to lower local array literals, index reads, storage
  array writes, and storage array reads through `.get()` when used as values.
- Kept EVM IR v0 behavior explicit by rejecting fixed-array literals, index
  access, storage array effects, and fixed-array returns.
- Added `ProofForge.IR.Examples.ArrayProbe`, covering local `[Felt; 3]`
  literals plus fixed storage array read/write behavior.
- Added CLI support:

```sh
lake env proof-forge --emit-array-ir-psy -o build/psy/ArrayProbe.psy
```

- Added `Examples/Psy/ArrayProbe.golden.psy`.
- Added `scripts/psy/array-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, three `dargo execute`
  calls, `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the ArrayProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-array-ir-psy -o build/psy/ArrayProbe.psy
diff -u Examples/Psy/ArrayProbe.golden.psy build/psy/ArrayProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/array-smoke.sh
```

Result:

- `lake build` passed.
- Generated ArrayProbe source matches the checked-in golden fixture.
- `scripts/psy/array-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [60]` for `sum_literal`.
- `dargo execute` returned `result_vm: [31]` for `storage_lifecycle`.
- `dargo execute` returned `result_vm: [1]` for `array_predicates`.

Known limitations:

- This feature covers one-dimensional fixed arrays over `Felt` and `Hash`
  storage elements. Struct arrays and nested arrays still need dedicated
  coverage.
- Dynamic arrays and unbounded indexing are still unsupported.
- EVM IR v0 explicitly rejects fixed-array IR nodes.

Next step:

- Add struct coverage next, then combine structs with arrays in a follow-up
  fixture aligned with upstream `array_test.psy`.

### Psy LoopProbe Bounded Loops

Commit: feature commit for bounded-loop Psy IR coverage

Summary:

- Extended portable IR statements with a static `boundedFor` node.
- Registered `control.bounded_loop` as a target capability and enabled it for
  `psy-dpn`.
- Extended Psy sourcegen to lower `boundedFor` to Psy fixed-range `for` loops
  such as `for _i in 0u32..3u32`.
- Kept EVM IR v0 behavior explicit by rejecting bounded loops with a diagnostic.
- Added `ProofForge.IR.Examples.LoopProbe`, which resets scalar storage, runs a
  three-iteration loop, and returns the final count.
- Added CLI support:

```sh
lake env proof-forge --emit-loop-ir-psy -o build/psy/LoopProbe.psy
```

- Added `Examples/Psy/LoopProbe.golden.psy`.
- Added `scripts/psy/loop-smoke.sh`, which generates a temporary Dargo package,
  runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the LoopProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-loop-ir-psy -o build/psy/LoopProbe.psy
diff -u Examples/Psy/LoopProbe.golden.psy build/psy/LoopProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/loop-smoke.sh
```

Result:

- `lake build` passed.
- Generated LoopProbe source matches the checked-in golden fixture.
- `scripts/psy/loop-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [3]` for `count_to_three`.

Known limitations:

- Loop lowering is deliberately static and bounded; dynamic or unbounded loops
  are still unsupported.
- The portable IR still lacks array and struct coverage.
- EVM IR v0 explicitly rejects bounded loops.

Next step:

- Add array coverage next, because upstream Psy tests and precompiles use
  fixed arrays heavily alongside bounded loops.

### Psy AssertProbe IR Assertions

Commit: feature commit for dynamic nested EVM local arrays

Summary:

- Extended portable IR with statement-level `assert` and `assertEq` nodes.
- Registered the `assertions` capability for target profiles and artifact
  metadata.
- Extended Psy sourcegen to lower assertion statements into method bodies as
  `assert(condition, "message")` and `assert_eq(lhs, rhs, "message")`.
- Added basic string escaping for generated Psy assertion messages.
- Added `ProofForge.IR.Examples.AssertProbe`, which validates assertions inside
  a contract method body.
- Added CLI support:

```sh
lake env proof-forge --emit-assert-ir-psy -o build/psy/AssertProbe.psy
```

- Added `Examples/Psy/AssertProbe.golden.psy`.
- Added `scripts/psy/assert-smoke.sh`, which generates a temporary Dargo
  package, runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the AssertProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-assert-ir-psy -o build/psy/AssertProbe.psy
diff -u Examples/Psy/AssertProbe.golden.psy build/psy/AssertProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/assert-smoke.sh
```

Result:

- `lake build` passed.
- Generated AssertProbe source matches the checked-in golden fixture.
- `scripts/psy/assert-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [12]` for `checked_sum(5,7)`.

Known limitations:

- Assertion conditions still depend on the currently narrow expression subset.
- EVM IR v0 rejects assertion statements through capability diagnostics.

Next step:

- Add bounded-loop coverage next, because loops are heavily used by Psy
  precompiles and are required for array/tree-style contracts.

### Psy MapProbe Storage Map Coverage

Commit: `427a0ec feat: support dynamic nested EVM local arrays`

Summary:

- Extended portable IR with fixed-capacity map state and `storage.map` effects:
  `contains`, `get`, `insert`, and `set`.
- Extended Psy sourcegen to lower the supported map shape to
  `Map<Hash, Hash, Nu32>` and to reject unsupported map key/value types with an
  explicit diagnostic.
- Added `ProofForge.IR.Examples.MapProbe` with scalar fields adjacent to the
  map to mirror upstream Psy storage-layout regression tests.
- Added CLI support:

```sh
lake env proof-forge --emit-map-ir-psy -o build/psy/MapProbe.psy
```

- Added `Examples/Psy/MapProbe.golden.psy`.
- Added `scripts/psy/map-smoke.sh`, which generates a temporary Dargo package,
  runs `dargo test --file`, `dargo compile`, `dargo execute`,
  `dargo generate-abi`, and validates `proof-forge-artifact.json`.
- Added CI coverage for the MapProbe Psy golden source snapshot.

Validation run:

```sh
lake build
lake env proof-forge --emit-map-ir-psy -o build/psy/MapProbe.psy
diff -u Examples/Psy/MapProbe.golden.psy build/psy/MapProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/map-smoke.sh
```

Result:

- `lake build` passed.
- Generated MapProbe source matches the checked-in golden fixture.
- `scripts/psy/map-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [55, 66, 77, 88]` for
  `map_lifecycle`.

Known limitations:

- Psy map lowering currently supports only `Map<Hash, Hash, N>`.
- The portable IR still lacks first-class assertions, bounded loops, arrays,
  and structs.
- EVM IR v0 explicitly rejects portable map storage.

Next step:

- Add IR-level assertions or bounded-loop coverage next, then validate the new
  node through Psy golden output and Dargo smoke.

### Psy HashProbe And Experimental Target Slice

Commit: test commit for EVM SDK example golden Yul fixtures

Summary:

- Extended portable IR with `Hash`, four-Felt hash literals, typed `let`
  bindings, `hash`, and `hash_two_to_one` expressions.
- Extended Psy sourcegen to lower hash values through upstream Psy idioms:
  `Hash`, `[a, b, c, d]`, `hash(data)`, and `hash_two_to_one(left, right)`.
- Added `ProofForge.IR.Examples.HashProbe` with two contract methods:
  `poseidon_hash` and `poseidon_pair_hash`.
- Added CLI support:

```sh
lake env proof-forge --emit-hash-ir-psy -o build/psy/HashProbe.psy
```

- Added `Examples/Psy/HashProbe.golden.psy`.
- Added `scripts/psy/hash-smoke.sh`, which generates a temporary Dargo package,
  runs `dargo test --file`, `dargo compile`, two `dargo execute` calls,
  `dargo generate-abi`, and writes `proof-forge-artifact.json`.
- Added `scripts/psy/validate-artifact-metadata.py`; the Counter, ContextProbe,
  and HashProbe smokes now validate artifact hashes, byte sizes, capability
  records, validation flags, and expected execution results.
- Added CI coverage for Psy golden source generation without requiring Dargo on
  GitHub Actions.

Validation run:

```sh
lake build
lake env proof-forge --emit-hash-ir-psy -o build/psy/HashProbe.psy
diff -u Examples/Psy/HashProbe.golden.psy build/psy/HashProbe.psy
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/counter-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/context-smoke.sh
PSY_HOME=/tmp/proof_forge_refs/psyup-home-test/.psy \
  DARGO=/tmp/proof_forge_refs/psyup-home-test/.psy/toolchains/psy-0.1.0/bin/dargo \
  scripts/psy/hash-smoke.sh
```

Result:

- `lake build` passed.
- Generated HashProbe source matches the checked-in golden fixture.
- `scripts/psy/hash-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- All three Psy smoke scripts validated `proof-forge-artifact.json` against the
  generated files and expected execution output.
- `dargo execute` returned the expected four-Felt output for `poseidon_hash`.
- `dargo execute` returned the expected four-Felt output for
  `poseidon_pair_hash`.

Known limitations:

- Hash support is deliberately narrow: fixed four-Felt `Hash` values only.
- Psy storage maps, bounded loops, and deploy JSON are still not implemented.
- EVM IR v0 explicitly rejects Hash values and hash expressions.

Next step:

- Add map/storage-map coverage from upstream `psy-compiler/tests` and
  `psy-precompiles`, then factor the repeated Dargo package generation logic.

### Psy ContextProbe Fixture And Artifact Metadata

Commit: pending

Summary:

- Extended portable IR with `context.read` effects for `userId`, `contractId`,
  and `checkpointId`.
- Extended Psy sourcegen to lower entrypoint parameters and context reads.
- Added `ProofForge.IR.Examples.ContextProbe`, the first non-Counter Psy IR
  fixture.
- Added CLI support:

```sh
lake env proof-forge --emit-context-ir-psy -o build/psy/ContextProbe.psy
```

- Added `Examples/Psy/ContextProbe.golden.psy`.
- Added `scripts/psy/context-smoke.sh`, which mirrors the Counter Dargo smoke:
  `dargo test --file`, `dargo compile`, `dargo execute`, and
  `dargo generate-abi`.
- Added `scripts/psy/write-artifact-metadata.py` and wired both Psy smoke
  scripts to emit `proof-forge-artifact.json` with hashes for source, circuit
  JSON, ABI JSON, and execute logs.

Validation run:

```sh
lake build
lake env proof-forge --emit-context-ir-psy -o build/psy/ContextProbe.psy
diff -u Examples/Psy/ContextProbe.golden.psy build/psy/ContextProbe.psy
scripts/psy/context-smoke.sh
scripts/psy/counter-smoke.sh
git diff --check
```

Result:

- `lake build` passed.
- ContextProbe emits reviewable Psy source with parameters and context reads.
- Generated ContextProbe source matches the checked-in golden fixture.
- `scripts/psy/context-smoke.sh` generated DPN JSON, ABI JSON, execute log, and
  `proof-forge-artifact.json`.
- `dargo execute` returned `result_vm: [15]` for `sum_context(2,3)`.
- `scripts/psy/counter-smoke.sh` now also emits `proof-forge-artifact.json`.

Known limitations:

- ContextProbe uses `_proof_forge_marker` storage because Dargo v0.1.0 panics on
  an empty `#[contract] #[derive(Storage)]` struct.
- The IR still lacks maps, fixed arrays, assertions, hashes, bounded loops, and
  reusable package generation.
- Dargo does not expose a `--version` flag, so metadata records the Dargo path
  and leaves the version null for now.

Next step:

- Add a curated upstream syntax regression subset from `psy-compiler/tests`,
  then expand the IR/sourcegen surface toward maps, arrays, assertions, and
  hashes.

## 2026-06-30

### Psy Counter IR Sourcegen And Smoke

Commit: pending

Summary:

- Added `ProofForge.Backend.Psy.IR`, a strict v0 source generator for the
  hand-written portable Counter IR fixture.
- Added CLI support:

```sh
lake env proof-forge --emit-counter-ir-psy -o build/psy/Counter.psy
```

- Added `Examples/Psy/Counter.golden.psy` as the reviewed source snapshot.
- Added `scripts/psy/counter-smoke.sh`, which:
  - regenerates Counter Psy source
  - compares it against the golden fixture
  - runs `dargo test --file`
  - creates a temporary Dargo package
  - runs `dargo compile --contract-name Counter --method-names initialize increment get`
  - checks the Dargo JSON artifact is non-empty
  - runs `dargo execute --contract-name Counter --method-names initialize increment increment get`
  - checks the local execution log contains `result_vm: [2]`
  - runs `dargo generate-abi --contract-name Counter --output-dir target --pretty`
  - checks the ABI JSON artifact is non-empty
- Verified `psyup install 0.1.0` as a working macOS arm64 toolchain path for
  this smoke.
- Recorded the upstream syntax/CI corpus: `psy-precompiles`, `tests`, and
  `psy-compiler`'s Makefile `build`/`ci` targets.

Validation run:

```sh
lake build
lake env proof-forge --emit-counter-ir-psy -o build/psy/Counter.psy
diff -u Examples/Psy/Counter.golden.psy build/psy/Counter.psy
psyup install 0.1.0
scripts/psy/counter-smoke.sh
```

Result:

- `lake build` passed.
- Counter IR emits reviewable Psy source.
- Generated Psy source matches the checked-in golden fixture.
- `scripts/psy/counter-smoke.sh` generated `build/psy/Counter.psy`, ran
  `dargo test --file`, ran `dargo compile`, produced
  `build/psy/dargo-counter/target/proof_forge_counter.json`, ran
  `dargo execute`, and verified `get` returned `result_vm: [2]` after two
  increments in the same local execution session.
- The same smoke generated non-empty ABI output at
  `build/psy/dargo-counter/target/Counter.json`.
- Direct `cargo install --git https://github.com/PsyProtocol/psy-compiler dargo`
  fetched `psy-compiler` but failed while Cargo updated the `psy-node`
  `psy-contracts` submodule URL.
- `psyup` v0.1.1 currently has only a Linux x86_64 release asset; macOS arm64
  was validated by pinning `psyup install 0.1.0`.

Known limitations:

- The generator supports only the current no-argument Counter IR subset:
  `u64` scalar state, scalar read/write, `add`, let-bind, and return.
- No deploy JSON, artifact metadata, or live Psy node smoke exists yet.
  `dargo execute` covers local user/contract execution, not network deployment.

Next step:

- Add `proof-forge-artifact.json` metadata to the Psy smoke, then decide
  whether CI should pin `psyup` v0.1.0 or wait for a newer macOS release asset.

### Psy/DPN SDK Skeleton

Commit: `feat: add Psy DPN SDK skeleton`

Summary:

- Added `ProofForge.Psy` as the first Lean SDK surface for the `psy-dpn` ZK
  target.
- Added primitive types and helpers:
  - `Felt`
  - `U32`
  - `Hash`
  - `ContractMetadata`
- Added context, storage, IMT map, hash, and deferred invocation externs under
  the `lean_psy_*` naming convention.
- Added a small `Examples/Psy/Counter.lean` SDK example.

Validation run:

```sh
lake build
lake env lean Examples/Psy/Counter.lean
```

Result:

- Passed.

Notes:

- The example uses `initCounter` instead of `initialize` because `initialize`
  is a Lean command keyword.

Known limitations:

- The SDK is a source-generation boundary only; no Psy backend lowers these
  externs yet.
- There is no Dargo package generation or `.psy` output yet.

Next step:

- Add a `psy-dpn` source generator for the hand-written Counter IR fixture.

### Portable IR Counter Runtime Dispatch

Commit: `824f5f8 feat: add IR counter EVM runtime smoke`

Summary:

- Added EVM selector metadata to the hand-written Counter IR fixture.
- Extended IR-to-Yul lowering to emit runtime selector dispatch for:
  - `initialize()`
  - `increment()`
  - `get()`
- Added `proof-forge --emit-counter-ir-bytecode`, which compiles Counter IR
  through runtime Yul and `solc --strict-assembly`.
- Added a dedicated Foundry smoke script for the IR Counter path:

```sh
scripts/evm/ir-counter-smoke.sh
```

Validation run:

```sh
lake build
lake env proof-forge --emit-counter-ir-yul -o build/ir/Counter.yul
lake env proof-forge --emit-counter-ir-bytecode -o build/ir/Counter.bin --yul-output build/ir/Counter.bytecode.yul
solc --strict-assembly build/ir/Counter.yul --bin
scripts/evm/ir-counter-smoke.sh
```

Result:

- `lake build` passed.
- Counter IR emits selector-dispatch Yul.
- Counter IR emits non-empty EVM bytecode.
- `solc --strict-assembly` accepts the generated runtime Yul.
- Foundry smoke passes for `initialize`/`increment`/`get` and unknown-selector
  revert behavior.

Known limitations:

- The IR fixture is still hand-written; there is no Lean-source-to-IR extractor.
- Only no-argument entrypoints are supported in the IR EVM dispatcher.

Next step:

- Promote the IR Counter path into CI once external tool gating is in place, and
  generalize the dispatcher beyond no-argument entrypoints.

### Portable IR Counter Lowering

Commit: `787d437 feat: add portable IR counter lowering`

Summary:

- Added the first target registry modules:
  - `ProofForge.Target.Capability`
  - `ProofForge.Target.Registry`
  - `ProofForge.Target.Check`
- Added the first portable contract IR:
  - `ValueType`
  - `StateDecl`
  - `Expr`
  - `Effect`
  - `Statement`
  - `Entrypoint`
  - `Module`
- Added a hand-written Counter IR fixture in `ProofForge.IR.Examples.Counter`.
- Added an EVM/Yul lowering path for the Counter-shaped IR subset.
- Added CLI smoke command:

```sh
lake env proof-forge --emit-counter-ir-yul -o build/ir/Counter.yul
```

Validation run:

```sh
lake build
lake env proof-forge --emit-counter-ir-yul -o build/ir/Counter.yul
solc --strict-assembly build/ir/Counter.yul --bin
```

Result:

- `lake build` passed.
- Counter IR lowers to Yul.
- `solc --strict-assembly` accepts the generated Yul.

Known limitations:

- The IR-generated Yul currently contains function definitions only.
- It does not yet generate EVM calldata selector dispatch.
- `solc` emits `00` for this debug object because no runtime dispatcher calls
  the generated functions yet.
- Existing `--evm-bytecode` smoke still requires Foundry `cast`; it was not
  revalidated locally because `cast` was not on `PATH`.

Next step:

- Generate an EVM dispatcher/runtime wrapper from IR entrypoints so the IR path
  can produce callable bytecode and run through Foundry smoke.

### Psy DPN Target Research

Commit: `ce5ab3e docs: add Psy DPN target research`

Summary:

- Added `psy-dpn` as a Research-stage target.
- Classified Psy as a ZK circuit source-generation target.
- Documented why the first integration path should generate `.psy` source and
  call Dargo instead of directly emitting DPN internals.
- Added `zk.circuit` and `zk.proof` capability ids.
- Added Chinese analysis for the Psy/DPN target.

Validation run:

```sh
git diff --check
```

Result:

- Documentation whitespace check passed before commit.

Known limitations:

- No Psy source generator exists yet.
- No Dargo smoke exists in this repository.

Next step:

- Reuse the portable Counter IR fixture once the IR-to-sourcegen path exists.

### Portable IR And Target Planning Docs

Commit: `9b7fce3 docs: add portable IR, capability registry, validation gates, and dev standards`

Summary:

- Added the first portable IR spec.
- Added canonical capability ids.
- Added shared Counter scenario.
- Added validation gates and development standards.
- Added implementation backlog slices for target registry, IR, metadata, EVM
  hardening, Wasm, Solana, Move, CI, and Psy.

Validation run:

```sh
git diff --check
```

Result:

- Documentation whitespace check passed before commit.

Known limitations:

- These were planning docs only; no IR code existed yet.

Next step:

- Implement the Target registry and Counter-shaped IR v0 in Lean.

### Multi-Chain Target Design

Commit: `a5555e5 docs: add multichain target design`

Summary:

- Added the first multi-chain platform RFCs and Chinese feasibility/technical
  analysis.
- Established the direction: Lean business logic plus target-specific adapters.
- Documented EVM, Solana, Wasm-family, Move-family, and cloud platform tracks.

Validation run:

```sh
git diff --check
```

Result:

- Documentation whitespace check passed before commit.

Known limitations:

- Design-only milestone.

Next step:

- Split the design into concrete target registry, IR, and validation tasks.

### EVM Baseline

Commits:

- `34b1708 Initial ProofForge EVM backend`
- `b7a5343 Add EVM examples and Foundry smoke tests`
- `a97dd21 Add CI and integrate EVM bytecode CLI`

Summary:

- Added the initial EVM SDK and Yul backend.
- Added EVM examples and Foundry smoke tests.
- Added bytecode compilation through `solc --strict-assembly`.
- Added CI around the baseline build and EVM smoke path.

Current role:

- EVM remains the first working target.
- New IR work should use EVM as the first executable backend to validate
  semantics before adding more chains.

### EVM Nested Local Fixed Arrays

Commit: pending

Summary:

- Extended portable IR EVM local fixed-array lowering to static nested scalar
  arrays.
- Added deterministic Yul locals for nested leaves such as `matrix[1][0]`.
- Covered static nested reads, mutable leaf assignment, numeric leaf compound
  assignment, nested whole-local assignment, and RHS snapshotting.
- Extended nested local scalar fixed arrays to dynamic index paths, including
  nested getter helpers for reads and nested `switch` blocks for mutable leaf
  assignment and compound assignment.
- Added `nested_dynamic_pick`, `nested_dynamic_row_pick`,
  `nested_dynamic_update`, and `nested_dynamic_row_update` coverage to
  `EvmArrayValueProbe`.

Validation run:

```sh
lake build
scripts/evm/array-value-ir-smoke.sh
```

Result:

- Lean build passed.
- Array value smoke produced reproducible golden Yul, compiled bytecode with
  `solc --strict-assembly`, validated metadata, and passed 17 Foundry tests.

Known limitations:

- Nested local arrays with unsupported aggregate or non-flat leaves remain
  explicit unsupported surfaces; flat struct leaves are covered by
  `EvmStructArrayValueProbe`.

### EVM SDK Example Golden Yul

Commit: pending

Summary:

- Added tracked golden Yul fixtures for SDK EVM examples:
  `ArrayExample`, `Counter`, `SimpleToken`, `ERC20`, `Ownable`, `Pausable`,
  and `VerifiedVault`.
- Updated `scripts/evm/build-examples.sh` to emit generated SDK Yul into
  `build/evm`, diff it against each sibling `.golden.yul`, compile bytecode,
  and validate ProofForge artifact metadata.
- Updated EVM validation docs and example README files so changing an SDK
  example now includes updating its golden Yul fixture.

Validation run:

```sh
scripts/evm/build-examples.sh
```

Result:

- All seven SDK examples produced reproducible Yul matching the new golden
  fixtures.
- All seven SDK examples compiled with `solc --strict-assembly` and validated
  EVM artifact/deploy metadata.

Known limitations:

- Runtime behavior remains covered by `scripts/evm/foundry-smoke.sh`.

### CI Baseline Repair + Upgrade Policy Resolver

Commit: pending

Summary:

- Fixed the root `target/` ignore rule so `ProofForge/Target/HostBridge.lean`
  is no longer silently ignored on case-insensitive filesystems, while keeping
  Rust build output ignored in known target directories.
- Replaced the missing GitHub Actions Rust setup action with
  `dtolnay/rust-toolchain@stable`, then pinned the CosmWasm smoke job to
  Rust `1.88.0` and `cosmwasm-check 2.2.9 --locked` after latest
  `cosmwasm-check` failed to link against newer Rust/Wasmer probestack symbols.
- Wired `ContractSpec.upgradePolicy?` into target resolution so unsupported
  target/policy combinations fail before code generation, and supported
  policies emit `upgrade.policy.*` metadata.
- Added a focused upgrade-policy smoke covering EVM, Solana, NEAR, Psy, JSON
  serialization, and escaping.
- Corrected the Gate G0 ledger so it no longer claims `just check` is green
  before CI and docs sync evidence are actually green.

Validation run:

```sh
lake build ProofForge.Target.Adapter
lake env lean --run Tests/UpgradePolicy.lean
lake build ProofForge.Target
```

Result:

- Target adapter build, upgrade-policy smoke, and target library build passed
  locally before the full repo validation pass.

### Testkit Runtime Error Expectations

Commit: pending

Summary:

- Added `testkit/scenarios/error-ref-user-code.toml`, a focused EVM +
  Wasm-NEAR scenario that reuses the portable `error-ref` fixture and asserts
  exact `assertion_id` plus `user_code` values for both failing entrypoints.
- Kept Solana in the existing three-target `error-ref` scenario as
  assertion-id-only, matching its runtime encoding as
  `ProgramError::Custom(assertion_id)`.
- Updated the Workstream 33 backlog status so M3 is recorded as implemented
  with testkit evidence.

Validation run:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario error-ref-user-code --trace
```

Result:

- EVM and Wasm-NEAR both reported and matched `Counter::Overflow` and
  `Counter::ExactMatch` user codes.
- The two-target normalized trace parity check passed.

### Portable Starter Authoring Boundary

Commit: pending

Summary:

- Clarified that new starter contracts should import
  `ProofForge.Contract.Source` and stay chain-neutral.
- Moved `ProofForge.Evm` / `Lean.Evm` wording to the EVM-native legacy/example
  path instead of presenting it as the default contract authoring surface.
- Updated the Chinese README and development-standards translations plus the
  i18n manifest hashes.

Validation run:

```sh
lake env lean templates/portable-counter/Counter.lean
scripts/i18n/check-sync.sh
git diff --check
```

Result:

- The portable starter template loaded successfully.
- Translation sync and whitespace checks passed.

### ContractSpec Error Catalogue

Commit: pending

Summary:

- Added a target-neutral `errors` catalogue to `ContractSpec` JSON output.
  Entries are derived from portable IR `assert` / `assertEq` `ErrorRef`
  metadata and include `assertionId`, optional `userCode`, fallback `message`,
  and owning `entrypoints`.
- Added `Tests/ContractSpecJson.lean` for Counter's empty error catalogue,
  ErrorRefProbe's two user-code entries, and nested control-flow assertions.
- Added `just contract-spec-json` and wired it into CI before backend-specific
  semantic-plan checks.
- Marked Workstream 33 M4 as partially implemented while keeping client
  wrapper consumption open.

Validation run:

```sh
lake build ProofForge.Contract.Spec.Json
lake env lean --run Tests/ContractSpecJson.lean
just contract-spec-json
```

Result:

- ContractSpec JSON schema tests passed locally.

### Contract Client Error Catalogue Helpers

Commit: pending

Summary:

- Embedded the target-neutral ContractSpec `ERRORS` catalogue into generated
  EVM and NEAR TypeScript wrapper sketches.
- Added `errorByAssertionId` to both wrappers, `decodeProofForgeRevert` for
  the EVM ABI-encoded `(uint32,string)` revert payload, and
  `parseProofForgePanic` for NEAR's `PF:{id}:{code}` panic prefix.
- Added `Tests/ContractClient.lean`, `just contract-client`, and a CI step for
  generated wrapper checks.
- Updated Workstream 33 M4 status to show EVM/NEAR wrapper consumption as
  implemented while keeping Solana IDL/client consumption open.

Validation run:

```sh
lake build ProofForge.Contract.Client
lake env lean --run Tests/ContractClient.lean
just contract-client
```

Result:

- Generated client wrapper checks passed locally.

### Solana Client Error Catalogue

Commit: pending

Summary:

- Added the portable `errors` catalogue to Solana IDL output, reusing the
  target-neutral ContractSpec error schema.
- Exported `ERRORS`, `errorByAssertionId`, and `errorBySolanaCustomCode` from
  the generated Solana TypeScript client.
- Extended `Tests/SolanaSdkManifest.lean` so package IDL/client output exposes
  empty error catalogues for contracts without `ErrorRef`, and ErrorRefProbe
  exposes the two portable assertion errors.
- Marked Workstream 33 M4 implemented at the client-schema/sketch boundary.

Validation run:

```sh
lake build ProofForge.Backend.Solana.Idl ProofForge.Backend.Solana.Client
lake env lean --run Tests/SolanaSdkManifest.lean
```

Result:

- Solana IDL/client error catalogue checks passed locally.

### NEAR ValueVault Backend-Invariant State Bridge

Commit: pending

Summary:

- Extended the decide-checkable NEAR FV-4 bridge from the ValueVault FV-8
  invariant scenario to the EmitWat/offline-host execution surface.
- Derived the ValueVault offline-host input sequence from
  `ValueVaultInvariant.defaultInputs` and checked return fragments against
  `ValueVaultInvariant.expectedReturns`.
- Added storage-key counts and cumulative log counts to each offline-host IO
  expectation.
- Checked the final offline-host state against the FV-8 scenario state plus
  the ValueVault accounting and final-storage predicates.
- Derived the ValueVault event log JSON fragments from the invariant final
  state, covering `VaultInitialized`, `ValueDeposited`, `ValueCharged`,
  `ValueReleased`, and `ValueSnapshot`.
- Wired the new `value_vault_emitwat_backend_invariant_bridge_ok` theorem into
  the formal smoke entrypoint.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR ValueVault backend-invariant state bridge checks passed locally.

### NEAR EmitWat Host Import Signatures

Commit: pending

Summary:

- Added `WasmImportExpectation` to the NEAR refinement artifact surface so
  obligations can check host import module names plus Wasm parameter/result
  signatures, not only imported function names.
- Pinned the Counter and ValueVault NEAR host-call ABI for `input`,
  `read_register`, `storage_read`, `storage_write`, `value_return`,
  `log_utf8`, and `block_index` where those imports are part of the checked
  surface.
- Added decide-checkable `counter_emitwat_host_import_signatures_ok` and
  `value_vault_emitwat_host_import_signatures_ok` anchors and wired both into
  the formal smoke entrypoint.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat host import signature checks passed locally.

### NEAR EmitWat Host Call Frames

Commit: pending

Summary:

- Added `WasmTraceOp` and `WasmHostFrameExpectation` to the NEAR refinement
  artifact surface so obligations can check contiguous Wasm AST instruction
  frames around host calls, not only call names.
- Pinned the `u64` storage read/write helper frames for `storage_read`,
  `read_register`, and `storage_write`, including the key/value buffer
  constants passed to the NEAR host ABI.
- Pinned the `u64` return helper frame for `value_return` and the ValueVault
  event-log frame for `log_utf8`.
- Added decide-checkable `counter_emitwat_host_frames_ok` and
  `value_vault_emitwat_host_frames_ok` anchors and wired both into the formal
  smoke entrypoint.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat host call-frame checks passed locally.

### NEAR Offline-Host Storage Snapshots

Commit: pending

Summary:

- Added per-step `storageSnapshot` data to NEAR offline-host IO expectations.
- Extended the offline-host trace runner so each checked Counter and ValueVault
  entrypoint records the full IR storage contents after execution, not only the
  number of storage keys.
- Added `OfflineHostExecutionObligation.storageSnapshotsOk` plus
  decide-checkable Counter and ValueVault storage-snapshot anchors.
- Folded the ValueVault storage-snapshot check into the existing
  backend-invariant bridge so the FV-8 scenario now constrains every checked
  intermediate storage state as well as final storage.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR offline-host storage snapshot checks passed locally.

### NEAR Offline-Host Storage Bytes

Commit: pending

Summary:

- Added byte-level `storageHexSnapshot` data to NEAR offline-host IO
  expectations.
- Derived storage bytes from the same Borsh/little-endian scalar encoder used
  for offline-host inputs and return observations.
- Pinned Counter and ValueVault storage byte strings after every checked
  entrypoint, connecting the semantic storage snapshots to the byte strings
  that the NEAR host storage boundary would persist.
- Added decide-checkable Counter and ValueVault storage-byte anchors and folded
  the ValueVault storage-byte check into the backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR offline-host storage byte checks passed locally.

### NEAR Offline-Host Log Payload Bytes

Commit: pending

Summary:

- Added byte-level `logPayloadHexFragments` data to NEAR offline-host IO
  expectations for ValueVault event logs.
- Split ValueVault event formatting into the host `log_utf8` payload and the
  human-readable offline-host log-line fragment, so obligations can check the
  actual UTF-8 payload bytes separately from console text.
- Derived expected `log_utf8` payload hex fragments from the same FV-8
  ValueVault invariant event stream that produces the semantic event logs.
- Added decide-checkable ValueVault log-payload-byte anchors and folded the
  log payload hex check into the backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR offline-host log payload byte checks passed locally.

### NEAR Offline-Host Return Payload Bytes

Commit: pending

Summary:

- Added byte-level `returnPayloadHex` data to NEAR offline-host IO
  expectations.
- Derived `returnPayloadHex` from the same scalar Borsh/little-endian encoder
  used by `value_return` observations, rather than relying only on the
  human-readable `returnLineFragment`.
- Added decide-checkable Counter and ValueVault return-payload-byte anchors.
- Folded the ValueVault return payload hex check into the backend-invariant
  bridge so FV-8 expected returns now constrain both semantic return values and
  the host `value_return` payload bytes.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR offline-host return payload byte checks passed locally.

### NEAR EmitWat Memory Layout Surface

Commit: pending

Summary:

- Added a memory-surface check to NEAR artifact obligations so Counter and
  ValueVault pin the emitted Wasm memory declaration, not only the memory export
  name.
- Added fixed host-buffer memory region expectations for `KEY_BUF`, `RET_BUF`,
  `EVENT_BUF`, `EVT_KEY_PTR`, and `INPUT_BUF`.
- Checked that those host buffers have nonzero size, fit in the first Wasm
  memory page, and do not overlap.
- Wired the new memory-surface anchors into the formal smoke entrypoint and the
  ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat memory layout surface checks passed locally.

### NEAR EmitWat Entrypoint Input Frames

Commit: pending

Summary:

- Added artifact-surface host-frame expectations for entrypoint input
  prologues.
- Pinned the `input(0)` plus `read_register(0, INPUT_BUF)` sequence used by
  Counter and ValueVault exported entrypoints before parameter decoding.
- Pinned scalar u64 parameter loads from `INPUT_BUF` for ValueVault's
  `initialize`, `deposit`, `charge_fee`, and `release` entrypoints, including
  the second `charge_fee` parameter at offset 8.
- Wired the new Counter and ValueVault input-frame anchors into the formal
  smoke entrypoint and the ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat entrypoint input-frame checks passed locally.

### NEAR EmitWat Context Host Frames

Commit: pending

Summary:

- Added ValueVault context host-frame expectations for `checkpointId`
  lowering.
- Pinned the `block_index` host call followed by `local.set checkpoint` in both
  `initialize` and `snapshot`.
- Wired the new context-frame anchor into the formal smoke entrypoint and the
  ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat context host-frame checks passed locally.

### NEAR EmitWat Storage Read Key Frames

Commit: pending

Summary:

- Added artifact-surface host-frame expectations for scalar storage reads.
- Pinned the Counter `count` key pointer/length passed into `__pf_read_u64`
  for `increment` and `get`.
- Pinned the ValueVault `balance`, `released`, `fees`, and `operations` key
  pointer/length pairs passed into `__pf_read_u64` for `deposit`,
  `charge_fee`, `release`, `snapshot`, `get_balance`, and `get_net_value`.
- Wired the new storage-read-key-frame anchors into the formal smoke entrypoint
  and the ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat storage read key-frame checks passed locally.

### NEAR EmitWat Storage Write Key/Value Frames

Commit: pending

Summary:

- Added artifact-surface host-frame expectations for scalar storage writes.
- Pinned Counter `count` writes passed into `__pf_write_u64` for `initialize`
  and `increment`, including the `n + 1` value expression.
- Pinned ValueVault `balance`, `released`, `fees`, `last_value`,
  `last_checkpoint`, and `operations` write key/value frames for `initialize`,
  `deposit`, `charge_fee`, `release`, and `snapshot`.
- Wired the new storage-write-key-value-frame anchors into the formal smoke
  entrypoint and the ValueVault backend-invariant bridge.

Validation run:

```sh
lake build ProofForge.Backend.WasmNear.Refinement
lake env lean --run Tests/NearWasmFormal.lean
```

Result:

- NEAR EmitWat storage write key/value-frame checks passed locally.
