# Arbitrum Stylus Hybrid Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a general, capability-gated Arbitrum Stylus backend whose canonical output is direct HostIO Wasm and whose generated Rust SDK crate remains a compatibility and differential-validation renderer.

**Architecture:** Canonical contracts lower exactly once into an immutable `StylusPlan` containing Solidity ABI, EVM-compatible 256-bit storage, HostIO effects, events, calls, resources, and artifacts. A Rust SDK renderer and a direct Wasm renderer consume that same plan; normalized trace equivalence, rather than byte-identical Wasm, controls canonical cutover.

**Tech Stack:** Lean 4/Lake, ProofForge canonical IR, ProofForge Wasm AST/printer, Rust `wasm32-unknown-unknown`, pinned `stylus-sdk` and `cargo-stylus`, Alloy/Solidity ABI, Wasmtime/offline host, Python/shell validation, Just, GitHub Actions.

## Global Constraints

- Planned target id is exactly `wasm-arbitrum-stylus`; family is `wasmHost`.
- Direct Wasm is the final canonical renderer; Rust SDK is bootstrap, compatibility, and differential oracle.
- Both renderers consume only `StylusPlan`; neither re-derives semantics from `ContractSpec`, legacy IR, or source text.
- Stylus storage uses EVM-compatible 256-bit slots and 32-byte words, never NEAR/Soroban string-key storage.
- Solidity ABI selectors, calldata, return data, revert data, and event topics are target contracts, not renderer conventions.
- Unsupported types, effects, host operations, or renderer entries fail before artifact emission with target/function/operation diagnostics.
- The target stays docs-only until Task 7; it is not a primary-triad advertised target.
- Every script that shells out to `proof-forge` first runs `lake build proof-forge`.
- Bootstrap pins are `stylus-sdk = "=0.10.8"`, `cargo-stylus = "=0.10.8"`, Rust `1.91.0`, and target `wasm32-unknown-unknown`; dependency ranges such as `*`, `latest`, or unbounded git branches are forbidden.
- Live RPC/deployment gates remain optional and separate from the static default baseline.
- Existing EVM, Solana, NEAR, Soroban, and CosmWasm output must remain unchanged unless a task names and reviews an intentional golden change.
- Design authority: `docs/superpowers/specs/2026-07-12-arbitrum-stylus-hybrid-backend-design.md`.

---

### Task 1: Docs-Only Stylus Classification and SDK Pin

**Files:**
- Create: `scripts/targets/test-doc-targets.py`
- Create: `docs/targets/arbitrum-stylus.md`
- Create: `docs/zh/targets/arbitrum-stylus.zh.md`
- Modify: `docs/targets/wasm-family.md`
- Modify: `docs/target-roadmap.md`
- Modify: `docs/decisions.md`
- Modify: `scripts/i18n/manifest.json`

**Interfaces:**
- Consumes: official `stylus-sdk-rs`, `cargo-stylus`, and HostIO documentation.
- Produces: exact SDK/toolchain pin, target classification, supported-fragment vocabulary, and promotion gates used by every later task.

- [x] **Step 1: Record the target classification test first**

  Create `scripts/targets/test-doc-targets.py` with these assertions:

  ```python
  from pathlib import Path

  text = Path("docs/targets/arbitrum-stylus.md").read_text()
  assert "`wasm-arbitrum-stylus`" in text
  assert "Direct Wasm" in text
  assert "Rust SDK" in text
  assert "docs-only" in text
  assert '`stylus-sdk = "=0.10.8"`' in text
  assert '`cargo-stylus = "=0.10.8"`' in text
  assert "Rust `1.91.0`" in text
  ```

  Run `python3 scripts/targets/test-doc-targets.py`; expect failure because the target document does not exist.

- [x] **Step 2: Write the authoritative target document**

  State that Stylus is Wasm-shaped but EVM-semantic; pin `stylus-sdk = "=0.10.8"`, `cargo-stylus = "=0.10.8"`, Rust `1.91.0`, and `wasm32-unknown-unknown`; record 256-bit storage slots, Solidity ABI, `vm_hooks`, cache flush, gas/ink, and the docs-only status. Include direct links to:

  ```text
  https://github.com/OffchainLabs/stylus-sdk-rs
  https://github.com/OffchainLabs/cargo-stylus
  https://raw.githubusercontent.com/OffchainLabs/stylus-sdk-rs/main/stylus-sdk/src/hostio.rs
  ```

- [x] **Step 3: Update Wasm family, roadmap, decision log, and Chinese mirror**

  Add a decision that `wasm-arbitrum-stylus` shares the Wasm family but owns a separate `StylusPlan`; explicitly prohibit routing through `NearModulePlan`. Keep the target out of `Registry.all`.

- [x] **Step 4: Validate and commit**

  Run:

  ```bash
  python3 scripts/targets/test-doc-targets.py
  scripts/i18n/check-sync.sh
  just docs-check
  git diff --check
  ```

  Expect all commands to pass, then commit:

  ```bash
  git add docs scripts/i18n/manifest.json
  git commit -m "docs: classify Arbitrum Stylus backend"
  ```

### Task 2: Stable StylusPlan Data Contract

**Files:**
- Create: `ProofForge/Backend/Stylus/Plan/Types.lean`
- Create: `ProofForge/Backend/Stylus/Plan.lean`
- Create: `Tests/Stylus/PlanContract.lean`
- Modify: `lakefile.lean` only if the repository requires explicit roots
- Modify: `justfile`

**Interfaces:**
- Consumes: `ProofForge.IR.Canonical.CheckedCanonicalContract`, shared canonical ids, and neutral ABI/storage primitives.
- Produces: `StylusPlan`, `StylusAbiPlan`, `StylusStoragePlan`, `StylusFunctionPlan`, `StylusEventPlan`, `StylusCallPlan`, `StylusHostOpPlan`, `StylusResourcePlan`, and `StylusArtifactPlan`.

- [x] **Step 1: Write the failing plan-contract test**

  Create `Tests/Stylus/PlanContract.lean` with compile-time fixtures that construct a plan and assert stable fields:

  ```lean
  import ProofForge.Backend.Stylus.Plan

  open ProofForge.Backend.Stylus

  def emptyPlan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus"
    moduleName := "Empty"
    abi := { methods := #[], errors := #[] }
    storage := { words := #[] }
    functions := #[]
    events := #[]
    calls := #[]
    hostOps := #[]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }

  def main : IO Unit := do
    unless emptyPlan.targetId == "wasm-arbitrum-stylus" do
      throw <| IO.userError "StylusPlan target id drifted"
    IO.println "stylus-plan-contract: ok"
  ```

  Run `lake env lean --run Tests/Stylus/PlanContract.lean`; expect unknown-module failure.

- [x] **Step 2: Implement focused plan types**

  Define exact enums for ABI types, slot expressions, host operations, and call modes. Use stable ids rather than embedded Rust/WAT:

  ```lean
  inductive StylusAbiType where
    | bool | uint (bits : Nat) | address | fixedBytes (bytes : Nat)
    | bytes | string | fixedArray (elem : StylusAbiType) (size : Nat)
    | dynamicArray (elem : StylusAbiType) | tuple (fields : Array StylusAbiType)

  inductive StylusSlotExpr where
    | literal (slot : ByteArray)
    | add (base : StylusSlotExpr) (offset : Nat)
    | mapping (base : StylusSlotExpr) (keyType : StylusAbiType)
    | dynamicBase (base : StylusSlotExpr)

  inductive StylusHostOp where
    | storageLoad | storageCache | storageFlush
    | calldataSize | calldataCopy | writeResult | writeRevert
    | msgSender | msgValue | txOrigin | contractAddress
    | chainId | blockNumber | blockTimestamp | gasLeft | inkLeft
    | keccak256 | emitLog | callContract | staticCallContract
    | delegateCallContract | readReturnData
  ```

  Validate integer widths in `{8,16,32,64,128,160,256}` and fixed bytes in `1..32` through smart constructors, not renderer checks.

- [x] **Step 3: Add the Just gate and pass it**

  Add:

  ```make
  stylus-plan-contract:
      lake env lean --run Tests/Stylus/PlanContract.lean
  ```

  Run `just stylus-plan-contract`, `lake build ProofForge.Backend.Stylus.Plan`, and `git diff --check`; expect pass.

- [x] **Step 4: Commit**

  ```bash
  git add ProofForge/Backend/Stylus Tests/Stylus justfile lakefile.lean
  git commit -m "feat(stylus): define stable target plan"
  ```

### Task 3: Canonical-to-StylusPlan Builder and Strict Validator

**Files:**
- Create: `ProofForge/Backend/Stylus/Plan/Core.lean`
- Create: `ProofForge/Backend/Stylus/Validate.lean`
- Create: `Tests/Stylus/CorePlan.lean`
- Create: `Tests/Stylus/Diagnostics.lean`
- Modify: `justfile`

**Interfaces:**
- Consumes: `CheckedCanonicalContract` plus `CapabilityPlan` for target `wasm-arbitrum-stylus`.
- Produces: `buildFromCore : CheckedCanonicalContract -> CapabilityPlan -> Except PlanError StylusPlan` and `validatePlan : StylusPlan -> Except PlanError Unit`.

- [x] **Step 1: Pin failing Counter and rejection cases**

  In `CorePlan.lean`, adapt the repository's canonical Counter and require its
  actual `initialize()`, `increment()`, and `get()` selectors, slot zero with
  `uint64` state, storage load/cache/flush HostOps, and
  `requiresStorageFlush = true`. In `Diagnostics.lean`, pin errors for wrong
  target, invalid `uint24`, unsupported target-only operations, missing renderer
  handlers, and invalid packed fields.

  Run both files with `lake env lean --run`; expect missing builder errors.

- [x] **Step 2: Build ABI and storage subplans from canonical facts**

  Implement separate pure functions:

  ```lean
  buildAbiPlan : CheckedCanonicalContract -> Except PlanError StylusAbiPlan
  buildStoragePlan : CheckedCanonicalContract -> Except PlanError StylusStoragePlan
  buildFunctionPlans : CheckedCanonicalContract -> Except PlanError (Array StylusFunctionPlan)
  collectHostOps : CheckedCanonicalContract -> Array StylusHostOpPlan
  ```

  Reuse extracted Solidity signature and slot-layout helpers from EVM only when they do not depend on Yul or bytecode types.

- [x] **Step 3: Enforce renderer completeness in validation**

  `validatePlan` must reject every plan entry without both `rustSdk` and `directWasm` support-state declarations. Before direct implementation, `directWasm` may be `planned`; emission requires `implemented`.

- [x] **Step 4: Verify and commit**

  Add `stylus-core-plan` and `stylus-diagnostics` recipes. Run both, `just canonical-core`, `just evm-plan`, and `git diff --check`, then commit:

  ```bash
  git add ProofForge/Backend/Stylus Tests/Stylus justfile
  git commit -m "feat(stylus): build validated plan from canonical IR"
  ```

### Task 4: Deterministic Rust SDK AST and Renderer

**Files:**
- Create: `ProofForge/Backend/Stylus/RustSdk/AST.lean`
- Create: `ProofForge/Backend/Stylus/RustSdk/Render.lean`
- Create: `Tests/Stylus/RustRender.lean`
- Create: `Tests/fixtures/stylus/counter/src/lib.rs.golden`
- Create: `Tests/fixtures/stylus/counter/Cargo.toml.golden`
- Modify: `justfile`

**Interfaces:**
- Consumes: validated `StylusPlan` only.
- Produces: `renderCrate : StylusPlan -> Except RenderError RustCrate`, where `RustCrate` owns deterministic path/content pairs.

- [x] **Step 1: Write renderer golden tests before implementation**

  Require the Counter output to contain pinned SDK version, `sol_storage!`,
  `#[entrypoint]`, `#[public]`, `uint64 count`, `initialize`, `increment`, `get`,
  checked addition, and no source-contract inspection.

  Run `lake env lean --run Tests/Stylus/RustRender.lean`; expect missing renderer failure.

- [x] **Step 2: Implement a structural Rust AST**

  Model crates, uses, attributes, structs, impl blocks, functions, statements, expressions, and types. Do not concatenate whole Rust functions as opaque strings. Permit raw tokens only for pinned macro invocations whose grammar is owned by `stylus-sdk`.

- [x] **Step 3: Render plan-owned storage, ABI, and functions**

  Generate:

  ```rust
  sol_storage! {
      #[entrypoint]
      pub struct Counter {
        uint64 count;
      }
  }

  #[public]
  impl Counter {
      pub fn initialize(&mut self) { self.count.set(0); }
      pub fn get(&self) -> u64 { self.count.get() }
      pub fn increment(&mut self) -> Result<(), Vec<u8>> {
          let next = self.count.get().checked_add(1)
              .ok_or_else(|| b"checked arithmetic overflow".to_vec())?;
          self.count.set(next);
          Ok(())
      }
  }
  ```

  The exact emitted method names and result wrappers come from `StylusAbiPlan`, not this example literal.

- [x] **Step 4: Verify deterministic goldens and commit**

  Run the renderer twice and compare file hashes, then run `just stylus-rust-render` and `git diff --check`. Commit:

  ```bash
  git add ProofForge/Backend/Stylus/RustSdk Tests/Stylus Tests/fixtures/stylus justfile
  git commit -m "feat(stylus): render deterministic Rust SDK crates"
  ```

### Task 5: Rust Crate Packaging and `cargo stylus check`

**Files:**
- Create: `ProofForge/Backend/Stylus/Package.lean`
- Create: `scripts/stylus/rust-counter-smoke.sh`
- Create: `scripts/stylus/check-toolchain.sh`
- Modify: `justfile`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `RustCrate` and Task 1 version pins.
- Produces: generated crate under `build/stylus/rust/<Contract>/`, compiled Wasm, tool report, and static CI evidence.

- [ ] **Step 1: Add a failing packaging smoke**

  The script must remove only its ignored output directory, build `proof-forge`, generate Counter, compare pinned Cargo metadata, run `cargo test`, compile `wasm32-unknown-unknown --release`, and run `cargo stylus check` when installed. Missing `cargo stylus` is a named SKIP locally and a failure in its optional CI job.

- [ ] **Step 2: Implement atomic package writing**

  Write into `build/stylus/.tmp-<pid>` and rename only after every planned file succeeds. Reject `..`, absolute paths, duplicate paths, and output outside the requested root.

- [ ] **Step 3: Add Just and optional CI gates**

  Add `stylus-rust-counter` outside the default `check` until the toolchain is available in hosted CI. Add an optional `stylus-smoke` job that pins Rust, the Wasm target, SDK, and cargo-stylus versions.

- [ ] **Step 4: Verify and commit**

  Run `just stylus-rust-counter`, YAML parse, `just test-equivalence`, and `git diff --check`; commit:

  ```bash
  git add ProofForge/Backend/Stylus/Package.lean scripts/stylus justfile .github/workflows/ci.yml
  git commit -m "test(stylus): validate generated Rust SDK Counter"
  ```

### Task 6: Stylus Abstract Host Semantics and Counter Lifecycle

**Files:**
- Create: `ProofForge/Backend/Stylus/Semantics.lean`
- Create: `ProofForge/Backend/Stylus/CounterRefinement.lean`
- Create: `Tests/Stylus/CounterLifecycle.lean`
- Create: `runtime/stylus-host/` Rust crate
- Modify: `justfile`

**Interfaces:**
- Consumes: validated Counter `StylusPlan`.
- Produces: abstract HostIO state/trace, plan execution, Rust host adapter, and Counter refinement anchors.

- [ ] **Step 1: Pin the observable lifecycle**

  Test `initialize -> increment -> get`, a host-seeded value above `2^32`,
  overflow rejection at `u64::MAX`, unchanged state after rejection, exact ABI
  bytes, slot zero, and one successful cache flush per mutating call.

- [ ] **Step 2: Implement the abstract state**

  Define storage words, cache, calldata, result/revert bytes, logs, calls, context, gas, ink, and normalized trace events. `storageCache` updates cache; `storageFlush` commits cache; revert discards cache.

- [ ] **Step 3: Add Rust host execution**

  The host executes the generated Wasm or SDK test adapter with deterministic context and emits the same normalized JSON trace schema as Lean semantics.

- [ ] **Step 4: Verify and commit**

  Run `just stylus-counter-lifecycle`, Cargo tests, `just counter-universal-refinement-smoke`, and `git diff --check`; commit:

  ```bash
  git add ProofForge/Backend/Stylus Tests/Stylus runtime/stylus-host justfile
  git commit -m "feat(stylus): model HostIO Counter semantics"
  ```

### Task 7: Research Target Registration, Artifact Bundle, and CLI Route

**Files:**
- Modify: `ProofForge/Target/Registry.lean`
- Modify: `ProofForge/Target/BackendRegistry.lean`
- Create: `ProofForge/Backend/Stylus/Artifact.lean`
- Modify: CLI target routing files discovered with `rg 'wasm-stellar-soroban' ProofForge/Cli`
- Create: `Tests/Stylus/PublicRoute.lean`
- Create: `scripts/stylus/public-route-smoke.sh`
- Modify: `README.md`, `AGENTS.md`, generated backend docs, i18n manifest, and `justfile`

**Interfaces:**
- Consumes: strict plan builder, Rust renderer, package writer, and Counter lifecycle evidence.
- Produces: research-stage `contract_source` build/check route, Wasm, Solidity ABI, TypeScript client schema, artifact JSON, and deploy JSON.

- [ ] **Step 1: Write public-route failures first**

  Pin unknown-target behavior before registration, then expected research profile fields, exact renderer metadata, Counter artifact hashes, and named failures for unsupported promise/NEAR operations.

- [ ] **Step 2: Register the target without primary-triad promotion**

  Add `wasm-arbitrum-stylus` as research maturity with Rust SDK output marked bootstrap and direct Wasm marked unavailable. Do not add it to primary strict triad lists.

- [ ] **Step 3: Emit complete artifacts atomically**

  Artifact metadata includes target id, plan schema version, renderer, SDK/tool versions, Wasm hash/size, ABI hash, selector table, storage-layout hash, client hash, and validation evidence.

- [ ] **Step 4: Verify and commit**

  Run public route, target registry, backend status generation, docs/i18n sync, CLI list/build/check, `just product`, and `git diff --check`; commit:

  ```bash
  git add ProofForge Tests scripts README.md AGENTS.md docs justfile
  git commit -m "feat(stylus): add research public target route"
  ```

### Task 8: Direct Wasm HostIO Imports, Memory, and Storage Words

**Files:**
- Create: `ProofForge/Backend/Stylus/DirectWasm/Imports.lean`
- Create: `ProofForge/Backend/Stylus/DirectWasm/Memory.lean`
- Create: `ProofForge/Backend/Stylus/DirectWasm/Storage.lean`
- Create: `Tests/Stylus/DirectStorage.lean`
- Modify: `justfile`

**Interfaces:**
- Consumes: `StylusStoragePlan` and `StylusHostOpPlan`.
- Produces: exact `vm_hooks` imports, bounded scratch memory, 32-byte load/masked-cache/flush helpers, mapping slot Keccak helpers, and valid Wasm AST.

- [ ] **Step 1: Pin import signatures and storage vectors**

  Test `storage_load_bytes32(key_ptr, dest_ptr)`, `storage_cache_bytes32(key_ptr, value_ptr)`, `storage_flush_cache(clear)`, Keccak slot vectors, packed-field preservation, `U256::MAX`, and absence of NEAR/Soroban imports.

- [ ] **Step 2: Implement plan-selected imports only**

  Import module is exactly `vm_hooks`. Reject duplicate imports with inconsistent signatures. Memory helpers use checked `i32` pointer arithmetic and reject scratch regions beyond declared pages.

- [ ] **Step 3: Implement storage word helpers**

  Load and store 32 bytes in the endian convention pinned by SDK vectors. Masked updates preserve unrelated packed fields. Every successful top-level mutating function schedules one flush; revert schedules none.

- [ ] **Step 4: Compile and commit**

  Render test modules, run `wat2wasm`, execute storage vectors in `runtime/stylus-host`, run `just stylus-direct-storage`, and commit.

### Task 9: Direct Wasm Solidity ABI Dispatcher

**Files:**
- Create: `ProofForge/Backend/Stylus/DirectWasm/Abi.lean`
- Create: `ProofForge/Backend/Stylus/DirectWasm/Dispatch.lean`
- Create: `Tests/Stylus/DirectAbi.lean`
- Create: `Tests/fixtures/stylus/abi-vectors.json`
- Modify: `justfile`

**Interfaces:**
- Consumes: `StylusAbiPlan`.
- Produces: calldata bounds checks, selector dispatch, scalar/static/dynamic decoding, return encoding, and revert encoding as Wasm AST functions.

- [ ] **Step 1: Generate shared ABI vectors from Alloy**

  Include valid and truncated calldata, unknown selector, `uint256`, bool canonicality, address high-bit rejection, fixed bytes, tuple, fixed array, dynamic bytes/string, dynamic array, offset overflow, and overlapping-tail cases.

- [ ] **Step 2: Implement scalar/static dispatcher first**

  Counter methods must match Rust SDK selectors and byte-for-byte outputs. Unknown selector and malformed calldata return deterministic revert bytes rather than trap.

- [ ] **Step 3: Add dynamic codecs behind completeness flags**

  A plan containing a dynamic ABI type is rejected until its decoder and encoder both report `implemented`. Never silently encode an empty result.

- [ ] **Step 4: Verify and commit**

  Run Alloy vector generation, Lean tests, `wat2wasm`, Rust SDK/direct comparison, and `git diff --check`; commit:

  ```bash
  git add ProofForge/Backend/Stylus/DirectWasm Tests/Stylus Tests/fixtures/stylus justfile
  git commit -m "feat(stylus): lower Solidity ABI directly to Wasm"
  ```

### Task 10: Direct Wasm Function Lowering and Counter Differential Gate

**Files:**
- Create: `ProofForge/Backend/Stylus/DirectWasm/Lower.lean`
- Create: `ProofForge/Backend/Stylus/DirectWasm/Module.lean`
- Create: `ProofForge/Backend/Stylus/Differential.lean`
- Create: `Tests/Stylus/CounterDifferential.lean`
- Create: `scripts/stylus/counter-differential.sh`
- Modify: `justfile`

**Interfaces:**
- Consumes: complete validated `StylusPlan`, DirectWasm ABI/storage helpers, and abstract semantics.
- Produces: `lowerFromPlan : StylusPlan -> Except LowerError Wasm.Module` and normalized Rust/direct trace comparison.

- [ ] **Step 1: Pin renderer completeness failure**

  A plan operation without a direct handler must fail with target, function, block, operation id, capability, and renderer. Counter's complete plan must lower.

- [ ] **Step 2: Lower canonical CFG/SSA operations**

  Implement constants, locals, checked add, comparisons, conditional branches, storage load/cache, ABI result/revert, and final flush. Do not lower from legacy `IR.Module`.

- [ ] **Step 3: Run Counter differential scenarios**

  Compare selectors, storage slots, state deltas, returns, reverts, and flush events for initial read, large `u256` set, increment, unknown selector, malformed calldata, and overflow.

- [ ] **Step 4: Verify and commit**

  Run `just stylus-counter-differential` three times, `wat2wasm`, runtime host tests, and `git diff --check`; commit:

  ```bash
  git add ProofForge/Backend/Stylus Tests/Stylus scripts/stylus justfile
  git commit -m "feat(stylus): add direct Wasm Counter renderer"
  ```

### Task 11: ValueVault Context, Payable, and Authorization Slice

**Files:**
- Extend: `ProofForge/Backend/Stylus/Plan/Core.lean`
- Create: `ProofForge/Backend/Stylus/DirectWasm/Context.lean`
- Extend: Rust and direct renderers
- Create: `Tests/Stylus/ValueVaultDifferential.lean`
- Create: `scripts/stylus/value-vault-differential.sh`
- Modify: `justfile`

**Interfaces:**
- Adds: address, sender, value, contract address, block number/timestamp, payable policy, authorization assertion, and revert rollback.

- [ ] **Step 1: Pin ValueVault plan and traces**

  Cover authorized deposit/withdraw, unauthorized rejection, zero/excess value policy, block context, state rollback, and exact ABI/revert bytes.

- [ ] **Step 2: Implement context HostIO and payable prologue**

  Use official pointer widths for address/U256 outputs. Reject context fields without official HostIO rather than borrowing NEAR names.

- [ ] **Step 3: Prove cache/reentrancy behavior**

  Rejected authorization and reverted calls discard pending cache. Successful external-call boundaries flush or clear according to the pinned policy.

- [ ] **Step 4: Verify and commit**

  Run Rust/direct/abstract differential gates, ABI client calls, `cargo stylus check`, and commit with message `feat(stylus): support ValueVault context semantics`.

### Task 12: Token Mapping, Events, and EVM Interoperability Slice

**Files:**
- Create: `ProofForge/Backend/Stylus/DirectWasm/Event.lean`
- Extend: storage mapping and both renderers
- Create: `Tests/Stylus/TokenDifferential.lean`
- Create: `scripts/stylus/token-evm-interop.sh`
- Modify: `justfile`

**Interfaces:**
- Adds: address-keyed and nested mappings, indexed events, ERC-20 selector/topic compatibility, allowance and transfer state transitions.

- [ ] **Step 1: Pin Solidity-compatible vectors**

  Use Alloy/Foundry to pin mapping slots, `Transfer`/`Approval` topics, calldata, return data, insufficient balance/allowance reverts, and zero-address policy.

- [ ] **Step 2: Implement mapping and event plans/renderers**

  Mapping keys are ABI-padded before Keccak with base slot. Event buffer is topics followed by data; reject more than four topics before emission.

- [ ] **Step 3: Run cross-language interoperability**

  Call generated Rust and direct artifacts through the same EVM ABI client and compare normalized traces plus Solidity-visible results.

- [ ] **Step 4: Verify and commit**

  Run Token differential, Foundry/Alloy vectors, host tests, `cargo stylus check`, and commit `feat(stylus): support mappings and EVM events`.

### Task 13: Remote Calls, Return Data, and Reentrancy Slice

**Files:**
- Create: `ProofForge/Backend/Stylus/DirectWasm/Call.lean`
- Extend: plan builder, validators, semantics, and both renderers
- Create: `Tests/Stylus/RemoteCallDifferential.lean`
- Create: `scripts/stylus/remote-call-differential.sh`
- Modify: `justfile`

**Interfaces:**
- Adds: call/static-call/delegate-call modes, value/gas, status, bounded return-data copy, revert propagation, and cache policy.

- [ ] **Step 1: Pin success/failure/reentrancy traces**

  Cover empty and dynamic results, callee revert, truncated result copy, value call, static write rejection, delegate storage context, gas limit, and reentrant callback.

- [ ] **Step 2: Implement official HostIO call envelopes**

  Use `call_contract`, delegate/static equivalents present in the pinned HostIO, `return_data_len`, and `read_return_data`. Missing official operation fails plan validation.

- [ ] **Step 3: Enforce cache transitions**

  Flush before an external call when visibility is required, clear on reentrant boundaries, restore/discard on failure, and record each transition in normalized traces.

- [ ] **Step 4: Verify and commit**

  Run differential scenarios, resource bounds, Rust/direct artifacts, and commit `feat(stylus): support EVM-compatible remote calls`.

### Task 14: Aggregate and Dynamic Data Slice

**Files:**
- Create: `ProofForge/Backend/Stylus/DirectWasm/Aggregate.lean`
- Extend: ABI, storage, semantics, and both renderers
- Create: `Tests/Stylus/AggregateDifferential.lean`
- Create: `Tests/fixtures/stylus/aggregate-vectors.json`
- Modify: `justfile`

**Interfaces:**
- Adds: structs/tuples, fixed arrays, dynamic arrays, bytes, string, nested ABI layouts, and corresponding Solidity storage layouts.

- [ ] **Step 1: Pin layout and adversarial vectors**

  Include empty/max-bound values, nested dynamic tails, short/long bytes transition, UTF-8 byte semantics, packed structs, array slot overflow, malformed offsets, and allocation exhaustion.

- [ ] **Step 2: Implement plan-owned layout algorithms**

  ABI and storage layout are separate functions with explicit size/bounds results. Renderers consume offsets; they do not recompute layouts.

- [ ] **Step 3: Add bounded memory and resource evidence**

  Reject unbounded input-derived allocations, record maximum pages, Wasm size, ink, and gas evidence, and prove failure leaves persistent state unchanged.

- [ ] **Step 4: Verify and commit**

  Run all vectors through abstract/Rust/direct paths and commit `feat(stylus): support aggregate ABI and storage`.

### Task 15: Canonical Direct-Wasm Cutover and Maintained Rust Oracle

**Files:**
- Modify: `ProofForge/Target/BackendRegistry.lean`
- Modify: `ProofForge/Target/Registry.lean`
- Modify: CLI renderer selection and artifact metadata
- Modify: `AGENTS.md`, `README.md`, target docs, roadmap, gate status, implementation log, validation gates, i18n files
- Modify: `.github/workflows/ci.yml`, `.woodpecker.yml`, `scripts/test-framework/lanes.json`, and `justfile`
- Create: `Tests/Stylus/RendererCutover.lean`

**Interfaces:**
- Consumes: green Counter, ValueVault, Token, RemoteCall, and aggregate differential gates.
- Produces: direct Wasm as default renderer; explicit `--renderer rust-sdk` compatibility/oracle mode; required static and optional live CI evidence.

- [ ] **Step 1: Write cutover invariants**

  Pin direct default, explicit Rust selection, identical plan hash/ABI/storage metadata, no silent fallback, unavailable renderer diagnostic, and unchanged primary-triad target lists.

- [ ] **Step 2: Switch default only after evidence aggregation passes**

  Add a machine-readable evidence file listing every required gate and commit. The cutover command fails if any entry is missing, skipped, stale, or from a different plan schema hash.

- [ ] **Step 3: Integrate conflict-aware CI lanes**

  Add Stylus static recipes exactly once to the manifest and serial coverage. Keep live RPC/deploy optional. Upload Rust/direct traces, Wasm, ABI, storage layout, and timing reports on failure.

- [ ] **Step 4: Run final verification**

  Run:

  ```bash
  just product
  just stylus-all
  just test-manifest
  just test-equivalence
  just docs-check
  JOBS=4 just check-parallel
  git diff --check
  ```

  Expect every required gate to pass with no Stylus SKIP in `stylus-all`.

- [ ] **Step 5: Commit and publish**

  ```bash
  git add ProofForge Tests scripts runtime AGENTS.md README.md docs justfile .github .woodpecker.yml
  git commit -m "feat(stylus): make direct Wasm the canonical renderer"
  git push origin HEAD:DaviRain-Su/new-design
  ```

## Review Checkpoints

Review after every task. Do not batch approvals across these boundaries:

- Tasks 1-3: target classification and immutable plan contract.
- Tasks 4-7: Rust bootstrap route and real artifact evidence.
- Tasks 8-10: direct Wasm Counter and first differential closure.
- Tasks 11-14: general-contract capability expansion.
- Task 15: canonical renderer cutover.

At each checkpoint, compare documentation claims with code, plan completeness,
runtime evidence, and current CI rather than accepting a passing unit test alone.
