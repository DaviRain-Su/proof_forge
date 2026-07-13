# Arbitrum Stylus General-Contract Completion Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the promised `wasm-arbitrum-stylus` general-contract fragment end to end: canonical Core to one checked `StylusPlan`, maintained Rust oracle and direct Wasm renderers, local VM and Nitro execution, then direct-Wasm artifact cutover.

**Architecture:** Canonical Core owns contract meaning; `StylusPlan` owns all Solidity ABI, storage, HostIO, resource, and cache-transition decisions. Rust SDK and direct Wasm consume the same immutable plan and may not infer layouts independently. Direct Wasm becomes the public artifact only after ValueVault, token, remote-call, aggregate, and evidence gates are green.

**Tech Stack:** Lean 4/Lake, Wasm AST/WAT, wabt `wat2wasm`, Rust 1.91.0, `stylus-sdk = 0.10.8`, `cargo-stylus = 0.10.8`, Wasmtime 45, official Nitro Testnode revision `62f6cae30942f82958695697d3de8b4e1447ea7f`, Foundry `cast`.

**Current checkpoint:** 59/80 acceptance items are complete. Three open queue
packages remain; W5.2 is externally blocked by the unavailable Nitro runtime.
Their dependency order is audited in
`docs/review/stylus-full-integration-gap-2026-07-13.md`.

## Continuous Execution Queue

Agents execute this queue in order without stopping at internal checkpoints.
Each package may contain multiple reviewed commits; only external environment
blockers may defer an item.

- [x] **W3.1 Direct aggregate carriers:** lower multi-child dynamic tuple
  extents and recursively nested dynamic array/tuple tails from plan-owned
  layouts; add malformed-offset and complete-before-copy runtime vectors.
  Multi-child bytes/string tuple extents, `bytes[]` recursive child tails, and
  dynamic tuples containing static-element dynamic arrays are implemented with
  malformed head/offset/length/canonical-element/truncation vectors. Recursive
  preorder policies now cover nested dynamic tuple children and arrays of
  dynamic tuples. The pure decoder, direct-Wasm validator/local VM, and pinned
  Rust renderer agree for `(uint64,(bytes,string))` and
  `(uint64,bytes)[]`, including inside-head, over-limit, and truncated tails.
- [x] **W3.2 Aggregate storage/resources:** implement Solidity-compatible
  dynamic bytes/string/array short-long storage transitions, checked allocation
  exhaustion, maximum-page gates, and Rust/direct differential fixtures.
  Bounded bytes/string now share renderer-neutral short/long transition
  planning and Direct-Wasm load/cache lowering, with Rust `StorageBytes` and
  `StorageString` as the oracle. Dynamic arrays use Solidity packing density
  for the public scalar fragment (bool, uint8..128, address); unsupported
  composite/fixed-bytes/uint256 public carriers fail closed. Maximum-page,
  corrupt-root, exact-maximum, over-limit, stale-word cleanup, Rust `TestVM`,
  and Direct runner vectors pass. The runner's opt-in
  `--shared-storage-batch` preserves committed storage without changing the
  isolated default batch semantics. A validated Canonical Core fixture proves
  that root bytes/string/dynamic-array state reaches these plan operations;
  indexed arrays and composite element storage remain explicit fail-closed
  boundaries.
- [x] **W3.3 Aggregate closure gate:** run the complete aggregate differential,
  diagnostics, resource-adversarial, Rust oracle, and direct-Wasm gates; update
  Task 6 evidence without claiming Nitro execution. `just
  stylus-aggregate-differential`, `just stylus-aggregate-storage`, and `just
  stylus-diagnostics` pass; `just stylus-core-plan` additionally covers the
  checked canonical aggregate route. The storage gate executes one Rust
  `stylus-test` oracle plus Direct-Wasm bytes/string/packed-array lifecycles.
- [x] **W4.1 HostIO/context closure:** audit all remote-call imports against the
  pinned SDK and add static-write rejection plus delegate caller/value/address/
  storage context vectors to the local runner.
- [x] **W4.2 Renderer parity:** support the same bounded static and dynamic
  return envelopes in generated Rust, then compare normalized Rust/direct/
  runner results, failures, calldata, cache transitions, and nested frames.
  Generated Rust now runs four native `stylus-test` cases and writes the same
  versioned seven-step common trace as the direct local runner for results,
  failures, modes, target, calldata, and value. Cache transitions and nested
  frames remain explicitly runner-only because upstream `stylus-test` 0.10.8
  implements cache flush as a no-op and exposes no frame trace.
- [x] **W4.3 Local two-contract evidence:** emit a machine-readable caller/
  callee local evidence manifest and make the remote differential gate verify
  its schema and hashes. An independent verifier reopens the persisted file,
  enforces local/non-Nitro provenance and scenario rollback semantics, and
  recomputes both Wasm hashes. This is local evidence, never Nitro evidence.
- [x] **W5.1 Environment audit:** run the Nitro doctor and persist doctor JSON.
  If Docker/RPC is unavailable, record the external blocker and continue with
  every independent W6/W7 static item rather than stopping the queue.
  Current evidence records cargo-stylus/cast/Rust as available and Docker,
  pinned checkout, and RPC as unavailable (`ready=false`).
- [ ] **W5.2 Live Nitro evidence:** when available, run ValueVault, token,
  remote two-contract, and aggregate check/deploy/E2E scenarios and persist
  addresses, transaction hashes, receipts, results, logs, gas/ink, tool
  versions, and source/artifact hashes.
  All four live recipes and the fail-closed final evidence assembler are now
  implemented and pass syntax/schema self-tests. Every local live recipe now
  requires a fresh successful doctor report before any build or deployment, so
  an arbitrary localhost EVM cannot claim Nitro provenance. RemoteCall and
  Aggregate also pass local product artifact/VM preflight. `final.json` remains
  absent because the current doctor report is `ready=false`; live receipts,
  gas/ink, and deployment evidence cannot be produced without Docker and the
  pinned RPC.
- [x] **W6.1 Renderer contract:** add explicit renderer selection, direct-Wasm
  default, Rust-oracle mode, named unavailable-renderer diagnostics, and strict
  no-fallback tests without promoting Stylus into the primary triad.
- [x] **W6.2 Atomic artifact bundle:** publish WAT/Wasm/ABI/client/plan metadata
  atomically with renderer, plan-schema, ABI, storage, toolchain, and evidence
  hashes; reject skipped or stale required evidence.
  Directory publication and WAT/Wasm/ABI/client/deploy hashes are implemented;
  independent renderer-neutral plan/storage files and hashes are now verified
  equal across direct/Rust. Evidence is now a hashed sidecar: absent live
  evidence is explicit `unavailable`, while supplied final evidence must match
  plan/storage/ABI identities, Task 2-6 Nitro provenance, non-skipped states,
  and a seven-day freshness window before atomic publication.
  W6 re-audit added process-wide temporary-bundle cleanup for every renderer or
  file failure, plus a forced `wat2wasm` failure vector. Cutover validation now
  also requires the pinned Nitro revision/local endpoint, doctor hash, one
  chain id, and per-gate transaction/artifact/summary hashes rather than
  accepting state/provenance labels alone.
- [x] **W6.3 CLI cutover matrix:** build and inspect Counter, ValueVault, Token,
  RemoteCall, and Aggregate bundles through literal CLI commands for both
  supported renderer modes.
  `just stylus-cli-matrix` now builds all five real product sources through
  both renderers, compares renderer-neutral identities and every published
  hash, validates plan-derived aggregate ABI types, rejects an unbound logical
  peer before publication, and executes the bound RemoteCall direct Wasm
  against the full 20-byte address. Aggregate covers its current product API of
  bytes, string, and fixed-array parameters; bounded dynamic-array storage is
  separately pinned through the checked Core/renderer gates and is not hidden
  behind a Rust-specific CLI dispatch.
- [x] **W7.1 Static test integration:** create `stylus-all` with no named skip,
  register every static gate exactly once in four-worker lanes and serial
  coverage, and preserve live Nitro as an explicit separate gate.
- [ ] **W7.2 CI/release evidence:** add GitHub/Woodpecker artifact upload and
  failure doctor data, synchronize registry/README/status/roadmap/i18n claims,
  and generate the final evidence manifest only after live requirements pass.
  GitHub now runs four independent static lanes and uploads artifacts, traces,
  evidence, timings, and failure doctor JSON. Woodpecker packages the same
  evidence in its shared workspace, fails on archive errors, and verifies the
  doctor JSON is present in the archive, but durable upload is externally
  blocked until Codeberg supplies an artifact sink and credentials. Registry and
  bilingual status/gate/roadmap docs are synchronized; `final.json` remains
  correctly absent without Nitro.
- [x] **W7.3 Full regression:** run `just product`, `just stylus-all`, manifest
  and equivalence checks, docs/i18n checks, `JOBS=4 just check-parallel`, and
  `git diff --check`; review the complete range for hidden fallback or
  unsupported claims.
  The final four-worker run passed all lanes in 1020.51 seconds after repairing
  stale NEAR dynamic-ABI expectations, both ValueVault WAT goldens, standalone
  gate rebuild dependencies, exclusive Anvil scheduling, and complete
  Canonical/EVM/Psy/Wasm constructor coverage manifests.
- [ ] **Final integration:** only after the queue is closed or externally
  blocked with exact evidence, review the complete branch, rebase the main
  working branch, resolve conflicts, rerun required gates, and push.

## Global Constraints

- Keep `wasm-arbitrum-stylus` at research maturity until Task 7 cutover evidence passes.
- Never route Stylus through `NearModulePlan`, `EmitWat`, or Soroban host bridges.
- Unsupported types and HostIO fail before artifact publication with target/function/block/operation diagnostics.
- No integer truncation: Core `u128` remains 128 bits and EVM/Stylus values remain 256 bits where the plan says U256.
- Every behavior change follows RED-GREEN-REFACTOR and updates `docs/implementation-log.md` in the same commit.
- Live Nitro gates are required for ValueVault and the final cutover; Sepolia remains explicit-key and optional; mainnet deployment is never automated.
- Preserve unrelated NEAR/WasmHost worktree changes and never stage them into Stylus commits.

---

### Task 1: Close Wide-Value Semantics and Scratch Bounds

**Files:**
- Modify: `ProofForge/Backend/Stylus/DirectWasm/Lower.lean`
- Modify: `ProofForge/Backend/Stylus/DirectWasm/Module.lean`
- Modify: `ProofForge/Backend/Stylus/Validate.lean`
- Extend: `Tests/Stylus/WideArithmetic.lean`
- Extend: `scripts/stylus/wide-arithmetic.sh`

**Interfaces:**
- Consumes: pointer-backed 16-byte `uint128` values and `widePtr` scratch allocation.
- Produces: `uint128` `lt/le/gt/ge`, checked scratch allocation, and named exhaustion diagnostics.

- [x] Add failing vectors for high-word ordering, equal values, low-word ordering, and all four predicates through `user_entrypoint`.
- [x] Add a failing plan whose highest wide SSA id exceeds `maxMemoryPages * 65536`; expect `capability=memory.scratch` before WAT emission.
- [x] Implement bytewise unsigned lexicographic comparison over 16-byte big-endian values without comparing pointers.
- [x] Replace implicit `1024 + id * 32` trust with a checked layout pass consumed by lowering; reject overlap with ABI/context/result scratch regions.
- [x] Run `just stylus-wide-values`, `just stylus-wide-arithmetic`, `just stylus-scalar-params`, `just stylus-counter-differential`, and `git diff --check`.
- [x] Commit as `feat(stylus): close u128 semantics and scratch bounds`.

### Task 2: Complete Canonical ValueVault and Nitro E2E

**Files:**
- Create: `ProofForge/Backend/Stylus/DirectWasm/ValueVault.lean`
- Extend: `Tests/Stylus/ValueVaultDifferential.lean`
- Create: `Tests/Stylus/ValueVaultCanonical.lean`
- Create: `scripts/stylus/value-vault-nitro-e2e.sh`
- Modify: `tools/stylus-vm-runner/src/main.rs`
- Modify: `justfile`

**Interfaces:**
- Consumes: the seven-entrypoint product ValueVault, scalar parameters, checked arithmetic, block context, storage, and events.
- Produces: one canonical ValueVault plan accepted by Rust SDK, direct Wasm, VM runner, and Nitro.

- [x] Pin initialize, charge-fee, release, net-value, block-context, storage, event, and checked-arithmetic vectors.
- [x] Build the plan from `ProofForge.IR.Examples.ValueVault` through canonical Core instead of a hand-authored renderer fixture; retain seven functions and six storage words.
- [x] Execute the product vectors under generated Rust `stylus-test` compilation and direct Wasmtime; compare state/result/status traces.
- [x] Extend the runner with the official `native_keccak256` and `emit_log` hooks; rejected calls discard cache and successful calls commit once.
- [ ] Start the pinned Nitro chain, run `cargo stylus check`, deploy/activate ValueVault, execute the scenario with `cast`, and persist address/tx/result evidence under ignored `build/evidence/stylus/`.
- [ ] Run `just stylus-value-vault-canonical`, `just stylus-vm-runner`, `just stylus-nitro-check`, and `just stylus-value-vault-nitro-e2e`.
- [ ] Mark Task 11 complete and commit as `feat(stylus): complete ValueVault semantics`.

### Task 3: Plan-Owned Mapping Slots and Events

**Files:**
- Create: `ProofForge/Backend/Stylus/StorageLayout.lean`
- Create: `ProofForge/Backend/Stylus/DirectWasm/Keccak.lean`
- Create: `ProofForge/Backend/Stylus/DirectWasm/Event.lean`
- Extend: `ProofForge/Backend/Stylus/Plan/Types.lean`
- Extend: `ProofForge/Backend/Stylus/Plan/Core.lean`
- Extend: `ProofForge/Backend/Stylus/RustSdk/AST.lean`
- Extend: `ProofForge/Backend/Stylus/RustSdk/Render.lean`
- Create: `Tests/Stylus/MappingEventVectors.lean`
- Create: `Tests/fixtures/stylus/token-vectors.json`

**Interfaces:**
- Produces: resolved mapping-key preimages/slots and event topic/data layouts in `StylusPlan`; renderers only execute offsets and buffers.

- [x] Add canonical non-indexed scalar event plans and direct/Rust rendering through official HostIO.
- [x] Pin Foundry vectors for `mapping(uint64 => uint64)`, `mapping(address => uint128)`, and indexed scalar event topic/data layouts.
- [x] Add plan types for single-key resolved storage paths and indexed event emissions, including the maximum-four-topics check.
- [x] Implement `keccak256` HostIO envelopes with exact 32-byte outputs and checked static key types.
- [x] Implement `emit_log` buffers for static indexed/data words; reject more than four topics and dynamic indexed values not pre-hashed by the plan.
- [x] Pin Foundry `cast index` vectors for `mapping(address => uint128)` and nested allowance mappings, plus standard `Transfer` / `Approval` topic/data vectors.
- [x] Render identical Rust/direct layouts and compare single-key/static-event paths to Foundry vectors.
- [x] Run `just stylus-mapping-events`, `just stylus-rust-render`, and `just stylus-diagnostics`.
- [x] Extend canonical Core with ordered composite `StateShape.mapN` keys, logical semantics, shared Stylus planning, nested Rust `StorageMap` rendering, and direct-Wasm VM parity (`just stylus-nested-map`).
- [x] Commit the full nested slice (`09579b6d`, `095ef266`) as canonical nested mapping plus complete mapping/event layouts.

### Task 4: ERC-20 State Machine and EVM Interoperability

**Files:**
- Create: `Tests/Stylus/TokenDifferential.lean`
- Create: `scripts/stylus/token-evm-interop.sh`
- Extend: `runtime/stylus-host/src/lib.rs`
- Modify: `justfile`

**Interfaces:**
- Consumes: mapping/event layouts.
- Produces: Solidity-compatible `balanceOf`, `allowance`, `transfer`, `approve`, and `transferFrom` behavior.

- [x] Pin selector, return, zero-address, insufficient balance/allowance, self-transfer, max allowance, and event vectors (`just stylus-token-differential`).
- [x] Materialize the shared `Examples.Product.FungibleToken.spec` through canonical Core to one Stylus plan; no target-specific frontend fixture.
- [x] Execute normalized abstract/Rust/direct traces for mint/approve/transfer/transferFrom and failure rollback.
- [ ] Deploy direct Wasm to Nitro and call it through standard Solidity ABI with `cast`; compare storage-visible balances and emitted logs.
- [ ] Run `just stylus-token-differential`, `just stylus-token-evm-interop`, and `just stylus-nitro-check`.
- [ ] Mark Task 12 complete and commit as `feat(stylus): complete ERC20 interoperability`.

### Task 5: Remote Calls, Return Data, and Reentrancy

> Execution dependency: Task 6 aggregate value carriers and calldata layout
> must land first because canonical crosscall methods are strings and arguments
> require ABI encoding. Remote-call lowering must not invent private pointer
> conventions outside `StylusPlan`.

**Files:**
- Create: `ProofForge/Backend/Stylus/DirectWasm/Call.lean`
- Extend: `ProofForge/Backend/Stylus/Plan/Types.lean`
- Extend: `ProofForge/Backend/Stylus/Plan/Core.lean`
- Extend: `ProofForge/Backend/Stylus/Validate.lean`
- Extend: `tools/stylus-vm-runner/src/main.rs`
- Create: `Tests/Stylus/RemoteCallDifferential.lean`
- Create: `scripts/stylus/remote-call-differential.sh`

**Interfaces:**
- Produces: call/static/delegate envelopes, bounded return-data slices, status/revert propagation, and explicit cache transitions.

- [x] Pin success, empty/dynamic result, callee revert, truncation, value call, static write rejection, delegate context, gas bound, and reentrant callback traces.
- [x] Preserve canonical call/static/delegate envelopes in `StylusPlan`, including target, bounded method string, typed arguments, optional value/gas, and return type.
- [x] Lower official call/static/delegate and `read_return_data` signatures for static arguments, u64 and bounded bytes/string results, and call values of uint64/128/256; propagate callee revert bytes.
- [x] Extend the local runner with deterministic mock callees and overlapping return-data reads for all three call modes.
- [x] Audit the direct imports against pinned SDK 0.10.8 `call_contract`, `static_call_contract`, `delegate_call_contract`, `read_return_data`, and `return_data_size`; call length is the official out pointer, not a separate `return_data_len` host function.
- [x] Encode the pinned SDK pre-call cache policy in `StylusPlan`: static calls flush without invalidation; call/delegate clear after persisting dirty values. Renderers may not invent transitions.
- [x] Model nested caller/callee frames and transaction-level commit/revert separately from cache policy; a failed callee frame must not discard caller state unless the caller itself reverts.
- [x] Extend the local runner with deterministic mock callees and nested invocation frames, preserving caller/storage/value identities.
- [x] Execute local Rust/direct/runner behavior parity and persist local caller/callee evidence with explicit non-Nitro provenance.
- [ ] Execute the real two-contract Nitro scenario and persist transaction evidence.
- [ ] Run `just stylus-remote-call-differential` and `just stylus-remote-call-nitro-e2e`.
- [ ] Mark Task 13 complete and commit as `feat(stylus): complete remote call semantics`.

### Task 6: Aggregate ABI, Dynamic Data, and Resource Bounds

**Files:**
- Create: `ProofForge/Backend/Stylus/AbiLayout.lean`
- Create: `ProofForge/Backend/Stylus/StorageLayout/Aggregate.lean`
- Create: `ProofForge/Backend/Stylus/DirectWasm/Aggregate.lean`
- Extend: both renderers and validators
- Create: `Tests/Stylus/AggregateDifferential.lean`
- Create: `Tests/fixtures/stylus/aggregate-vectors.json`
- Create: `scripts/stylus/aggregate-differential.sh`

**Interfaces:**
- Produces: plan-owned static heads, dynamic tails, storage paths, allocation bounds, and maximum memory pages.

- [x] Pin empty/max bytes/string, fixed/dynamic arrays, tuples, nested tails, malformed offsets, UTF-8 byte semantics, short/long storage transition, and allocation exhaustion vectors.
- [x] Add renderer-neutral dynamic ABI head/tail validation for empty/non-aligned payloads, malformed offsets, truncated tails, padding bounds, and maximum length.
- [x] Add plan-owned pointer/length carriers for bounded bytes/string parameters and Solidity-compatible dynamic returns in direct Wasm; compile the same plan as Rust `Vec<u8>`/`String`.
- [x] Lower bounded bytes/string literals into checked scratch carriers for canonical method names and other aggregate consumers.
- [x] Compute ABI and storage layouts in separate Lean modules with checked addition/multiplication and explicit maximum lengths.
- [x] Decode/copy only after complete bounds validation; failure must precede storage cache mutation.
- [ ] Render and execute Rust/direct parity for every fixture and record Wasm bytes/pages plus Nitro ink/gas evidence.
- [ ] Run `just stylus-aggregate-differential`, `just stylus-nitro-check`, and resource-limit adversarial gates.
- [ ] Mark Task 14 complete and commit as `feat(stylus): complete aggregate ABI and storage`.

### Task 7: Direct-Wasm Public Artifact Cutover

**Files:**
- Modify: `ProofForge/Cli/StylusArtifacts.lean`
- Modify: `ProofForge/Cli/Options.lean`
- Modify: `ProofForge/Target/Registry.lean`
- Modify: `ProofForge/Backend/Stylus/Artifact.lean`
- Create: `Tests/Stylus/RendererCutover.lean`
- Create: `scripts/stylus/check-cutover-evidence.py`

**Interfaces:**
- Produces: direct `.wasm` as default final output and explicit `--renderer rust-sdk` oracle/source mode.

- [x] Pin CLI tests for direct default, explicit Rust selection, identical plan/ABI/storage hashes, no fallback, atomic artifacts, and unavailable-renderer diagnostics.
- [x] Add renderer selection to CLI options without adding Stylus to the public-beta primary triad.
- [x] Publish direct Wasm, WAT, ABI, client, plan metadata, renderer id, tool versions, and evidence hash atomically.
- [x] Require a machine-readable evidence manifest whose Task 2-6 gates match the current plan-schema hash and are neither skipped nor stale.
- [x] Run literal CLI builds for Counter, ValueVault, Token, RemoteCall, and Aggregate fixtures and inspect artifact bundles.
- [x] Commit the renderer cutover and renderer-neutral CLI dispatch.

### Task 8: Unified Developer Tooling, CI, and Release Evidence

**Files:**
- Modify: `tools/stylus-vm-runner/`
- Modify: `tools/stylus-nitro/manage.sh`
- Modify: `scripts/test-framework/lanes.json`
- Modify: `justfile`
- Modify: `.github/workflows/ci.yml`
- Modify: `.woodpecker.yml`
- Modify: `AGENTS.md`, `README.md`, target/gate/roadmap docs and Chinese mirrors

**Interfaces:**
- Produces: `just stylus-all`, deterministic local doctor/runner/Nitro workflows, parallel static CI, optional live CI, and final evidence bundle.

- [x] Make `stylus-all` aggregate every static Rust/direct/differential gate with no named SKIP; keep Nitro live jobs separate and explicit.
- [x] Register each recipe exactly once in test lanes and serial coverage; run independent static gates in the default four-worker framework.
- [ ] Add CI artifact upload for WAT/Wasm, Rust crate, normalized traces, Nitro tx/address, timing, and doctor JSON on failure.
- [x] Update registry text and documentation to distinguish implemented fragment, research maturity, direct default, Rust oracle, local VM evidence, and Nitro evidence.
- [ ] Run `just product`, `just stylus-all`, `just test-manifest`, `just test-equivalence`, `just docs-check`, `JOBS=4 just check-parallel`, and `git diff --check`.
- [ ] Run `just stylus-nitro-doctor`, restore/start Nitro if needed, then run all required Nitro E2E gates and write `build/evidence/stylus/final.json`.
- [ ] Review the complete commit range for unsupported claims, primary-triad regressions, generated output, and hidden fallbacks.
- [ ] Mark the plan complete, update `AGENTS.md`, and push the final branch.

## Final Definition of Done

- `wasm-arbitrum-stylus` accepts every canonical contract inside the documented fragment and rejects everything else before partial publication.
- Counter, ValueVault, ERC-20, remote calls, and aggregate fixtures pass abstract, Rust, direct Wasm, and required Nitro evidence gates.
- Direct Wasm is the CLI default; Rust SDK remains an explicit maintained oracle.
- `just stylus-all` contains no skip, `JOBS=4 just check-parallel` passes, translations are synchronized, and the remote branch equals local HEAD.
