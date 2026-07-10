# EVM Completeness Gap Analysis & Phased Roadmap

Status: **Draft implementation plan**  
Scope: ProofForge EVM backend (`evm` target) in `/Users/davirian/orca/workspaces/proof_forge/evm-full`.  
Last updated: 2026-07-04.

---

## 1. Current State Summary

### 1.1 Pipeline & architecture

The EVM backend is a portable-IR-to-Yul pipeline:

```text
Lean contract / ProofForge.IR.Module
  -> ProofForge.Backend.Evm.Validate  (pure validation + type inference)
  -> ProofForge.Backend.Evm.Lower     (populate ProofForge.Backend.Evm.Plan.ModulePlan)
  -> ProofForge.Backend.Evm.IR        (Yul AST generation)
  -> ProofForge.Compiler.Yul.Printer  (render Yul text)
  -> solc --strict-assembly           (runtime bytecode)
  -> Foundry / Anvil runtime smokes
```

Key files:

- Portable IR surface: `ProofForge/IR/Contract.lean` (`ValueType`, `ContextField`, `Expr`, `Effect`, `Statement`, `Entrypoint`, `Module`).
- EVM semantic-plan layer (RFC 0004): `ProofForge/Backend/Evm/Plan.lean`, `ProofForge/Backend/Evm/Lower.lean`, `ProofForge/Backend/Evm/Validate.lean`, `ProofForge/Backend/Evm/ToYul.lean`, `ProofForge/Backend/Evm/IR.lean`, `ProofForge/Backend/Evm/Metadata.lean`.
- Yul AST/printer: `ProofForge/Compiler/Yul/AST.lean`, `ProofForge/Compiler/Yul/Printer.lean`.
- Executable refinement model: `ProofForge/Backend/Evm/YulSemantics.lean`, `ProofForge/Backend/Evm/Refinement.lean`.
- Target registry / capabilities: `ProofForge/Target/Registry.lean`, `ProofForge/Target/Capability.lean`, `ProofForge/Target/Adapter.lean`, `docs/capability-registry.md`.

### 1.2 What is already implemented

The portable IR EVM backend (`portable-ir-v0`) supports:

- Scalar types: `Bool`, `U32`, `U64`, `Hash` (one-word `bytes32`).
- Flat structs and fixed arrays of those scalar types, including nesting whose leaves are scalar words or flat structs.
- Scalar storage, `Map<K,V,N>` storage with word key/value types and managed presence slots, fixed-size storage arrays of words and flat structs.
- Entrypoints with static aggregate ABI params/returns (flat structs, fixed arrays, nested fixed arrays), four-byte selectors, and dispatcher range guards for `U32`/`Bool`.
- Events with up to three indexed fields, scalar and aggregate data/indexed topics.
- Synchronous typed `call`/`staticcall`/`delegatecall`, value-bearing calls, fixed-init-code `create`/`create2`.
- Context reads (`caller()`, `address()`, `number()`, `callvalue()`), checked arithmetic (`add`/`sub`/`mul`), all portable `AssignOp` variants, `assert`/`assertEq`, bounded loops, and branch/loop-local early returns.
- Artifact/deploy metadata (`proof-forge-artifact.json`, `proof-forge-deploy.json`), initcode generation, typed/static-hex constructor args, and local Anvil deploy smoke.

### 1.3 CI / gate inventory

Baseline EVM gates (all wired in `just check` / `just ci`):

- Build: `lake build`.
- Plan smoke: `just evm-plan` → `Tests/Backend/Evm/EvmPlan.lean`.
- Semantic plan smoke: `just evm-semantic-plan` → `Tests/Backend/Evm/EvmSemanticPlan.lean`.
- Diagnostic smoke: `scripts/evm/diagnostic-smoke.sh` (58 Lean cases + CLI constructor cases).
- Coverage manifest: `scripts/evm/check-ir-coverage-manifest.py` over `Tests/Backend/Evm/EvmCoverage.tsv`.
- IR smokes: `scripts/evm/*-ir-smoke.sh` (22 fixtures covering scalar ABI, assignment, assign-op, conditionals, loops, context, events, crosscalls, expressions, hash, maps, typed maps, storage arrays, typed storage, storage structs, array values, struct values, struct-array values, ABI aggregates, and the counter smoke).
- SDK examples: `scripts/evm/build-examples.sh` with golden Yul diffs.
- Foundry runtime: `scripts/evm/foundry-smoke.sh`.
- Anvil deploy: `scripts/evm/anvil-deploy-smoke.sh`.
- Full EVM suite: `just evm-all`.

Formal verification anchors:

- `ProofForge/Backend/Evm/Refinement.lean` has decide-checked `*_ir_observable_trace_ok`, `*_evm_yul_surface_trace_entrypoints`, and `*_evm_yul_executable_trace_ok` theorems for Counter, ValueVault, expression, conditional, loop, event, map, typed storage, storage struct, and ABI aggregate probes.
- `ProofForge/Backend/Evm/YulSemantics.lean` is a narrow executable Yul model used by those obligations; it is explicitly *not* a full EVM interpreter.

---

## 2. Gap Taxonomy vs. Full Solidity / EVM Semantics

This section catalogs the remaining distance to a production-grade Solidity-equivalent EVM backend. Gaps are grouped by domain.

### 2.1 Type system gaps

| Gap | Current state | Full Solidity/EVM expectation |
|---|---|---|
| Signed integers | Only unsigned `U32`/`U64` and one-word `Hash`. | `int8`..`int256`, signed comparison, signed division/remainder, sign extension. |
| `address` | Not a first-class IR type; addresses are carried as `U64`/`Hash` in some probes but not validated. | Distinct `address` type with 20-byte semantics, checksums, `address(this).balance`, `transfer`, `send`, `call`. |
| `bytes` / `string` | Not supported; `hash`/`Hash` is fixed 32 bytes. | Variable-length `bytes` and UTF-8 `string` values with ABI head-tail encoding and UTF-8 validation. |
| Dynamic arrays | Only `fixedArray` with compile-time length. | `T[]` dynamic arrays in storage, memory, calldata, and ABI. |
| `bytesN` beyond `Hash` | Only `Hash` maps to `bytes32`. | `bytes1`..`bytes32` with precise width semantics and packing. |
| `uint256` / `int256` | `U64` is the widest numeric; `Hash` is opaque bytes32. | Full 256-bit arithmetic with checked/unchecked modes. |
| Enums / user-defined value types | Not in IR. | Solidity enums and UDVTs. |
| `Nat` | Capped at U256 by doc, no bignum path. | Documented known limit; likely stays as explicit diagnostic. |

Files most affected: `ProofForge/IR/Contract.lean`, `ProofForge/Backend/Evm/Validate.lean`, `ProofForge/Backend/Evm/Plan.lean`, `ProofForge/Backend/Evm/IR.lean`.

### 2.2 EVM opcode / context gaps

Current `ContextField` covers `userId` (`caller()`), `contractId` (`address()`), `checkpointId` (`number()`), plus `nativeValue` (`callvalue()`). Missing:

| Opcode / context | Current | Needed |
|---|---|---|
| `timestamp` (`block.timestamp`) | Not exposed. | New `ContextField` or target extension; EVM semantics for seconds since epoch. |
| `chainid` (`block.chainid`) | Stored in deploy metadata but not readable at runtime. | Runtime `chainid()` read; useful for multi-chain logic. |
| `origin` (`tx.origin`) | Not exposed. | `tx.origin` context read. |
| `gasprice` (`tx.gasprice`) | Not exposed. | `gasprice()` read. |
| `blockhash` (`blockhash(n)`) | Not exposed. | `blockhash` read with 256-block history semantics. |
| `gasleft` (`gasleft()`) | Not exposed. | `gasleft()` read for gas-conscious patterns. |
| `extcodesize` / `extcodehash` / `extcodecopy` | Not exposed. | Contract existence/size/hash checks and code copying. |
| `selfdestruct` (`SELFDESTRUCT`) | Not exposed. | Destruct pattern (noting EIP-6780 / Cancun semantics on L2s). |
| `returndatasize` / `returndatacopy` | Typed crosscalls only decode fixed-size return data; short returns revert. | Variable-length return-data handling, including `revert(message)` decoding. |
| `callcode` | Not exposed (only `call`/`staticcall`/`delegatecall`). | `callcode` if legacy support desired; likely low priority. |
| `prevrandao` (`block.prevrandao`) | Not exposed. | Post-Merge `prevrandao()` read; `difficulty` alias. |
| `coinbase` / `basefee` | Not exposed. | `block.coinbase`, `block.basefee` (relevant for L2 gas accounting). |

Files most affected: `ProofForge/IR/Contract.lean` (`ContextField`), `ProofForge/Backend/Evm/Validate.lean`, `ProofForge/Backend/Evm/Plan.lean`, `ProofForge/Backend/Evm/IR.lean`, `ProofForge/Backend/Evm/YulSemantics.lean`.

### 2.3 Contract interaction gaps

| Feature | Current | Needed |
|---|---|---|
| `fallback` / `receive` | Only explicit selector dispatch. | Selector-less fallback and `receive()` entrypoints with Ether acceptance. |
| Custom errors | `assert`/`assertEq` emit bare `revert(0,0)`. | Solidity-style `error CustomError(args)` with ABI-encoded revert reason. |
| Revert messages | Bare reverts only. | String revert reasons (`revert("msg")`). |
| `try/catch` | Not supported. | Try/catch around external calls with error capture. |
| Libraries | Not supported. | Internal library linking or delegate-library patterns. |
| Proxy patterns / EIP-1967 / UUPS | Partial backend UUPS spike: ERC-1967 delegatecall fallback, mandatory atomic implementation/admin constructor binding, no public init selectors, owner-guarded upgrade. Product authority policies fail closed. | Bind product `keyRef`, support atomic initializer calldata and transparent/beacon patterns. |
| Contract metadata / `name`/`version` | Not emitted. | ERC-173/ERC-1967 ownership, upgrade events, implementation slot. |

Files most affected: `ProofForge/Backend/Evm/IR.lean` (dispatcher), `ProofForge/Backend/Evm/Metadata.lean`, CLI deploy manifest logic, new proxy/example modules under `Examples/Backend/Evm/`.

### 2.4 ABI / calldata gaps

| Feature | Current | Needed |
|---|---|---|
| Dynamic-length params/returns | Static aggregate ABI only; zero-length arrays rejected. | Dynamic `T[]`, `bytes`, `string` ABI encoding/decoding with head-tail layout. |
| Dynamic constructor args | Only static-word constructor params (`uint256`, `uint64`, `uint32`, `bool`, `bytes32`, `address`) and raw hex. | Constructor `string`, `bytes`, dynamic arrays, typed value encoding. |
| Tuple ABI | Flat structs encode as tuples; nested tuples / mixed dynamic not supported. | Full tuple ABI, including nested and dynamic tuple members. |
| Function selectors without `.evm-methods` | Portable IR requires explicit `selector?` per entrypoint; SDK path still uses `.evm-methods`. | Automatic selector derivation from entrypoint name + param types in portable IR, or a target manifest replacing `.evm-methods`. |
| ABI JSON output | Metadata has custom `abi.entrypoints` / `abi.events`. | Standard Ethereum ABI JSON (`abi` field) for tooling consumption. |
| `payable` / `nonpayable` / `view` / `pure` | Not tracked in IR metadata. | State mutability annotations in ABI and dispatch guards (e.g. reject value to non-payable). |
| Default arguments / overloads | Not supported. | Solidity-style overload resolution if SDK supports it. |

Files most affected: `ProofForge/Backend/Evm/Plan.lean` (`AbiParamPlan`/`ReturnPlan`), `ProofForge/Backend/Evm/Metadata.lean`, `ProofForge/Backend/Evm/IR.lean` (dispatcher), `ProofForge/Cli.lean`, `scripts/evm/validate-artifact-metadata.py`.

### 2.5 Storage / gas / codegen gaps

| Feature | Current | Needed |
|---|---|---|
| Storage packing | Consecutive small scalar state declarations share slots using Solidity low-order byte offsets; runtime and constructor writes mask field width. Struct fields and array elements still use their existing full-word layouts. | Extend packing beyond top-level consecutive scalar state only when a product case requires it. |
| Slot packing overflow | Checked direct writes and compound assignments reject values wider than a packed field; wrapping writes truncate and preserve neighboring fields. | Keep Foundry neighbor-isolation and rollback regressions in the EVM gate. |
| Yul optimizer | `solc --strict-assembly` is invoked; optimizer settings are script-level (`optimizer = true`, `optimizer_runs = 200`, `via_ir = true`). | First-class optimizer tuning in CLI/metadata; size-vs-runs profiles; contract-size gate. |
| Source maps | Not generated. | Yul→bytecode source maps and metadata hash for explorer verification. |
| Metadata hash (IPFS / swarm / CBOR) | Not appended to bytecode. | `solc` metadata hash injection for verification. |
| Contract-size limit enforcement | No explicit size check. | Warn/fail if runtime bytecode > 24,576 bytes. |
| Storage layout JSON | Not emitted. | Standard `storage-layout` output for upgrade safety tools. |
| Gas estimation / profiling | Not exposed. | Static gas bounds or runtime gas profiling hooks. |
| `memory` / `calldata` data locations | IR has no location concept; locals lower to Yul locals, arrays expand inline. | In-memory dynamic arrays and calldata slices. |

Files most affected: `ProofForge/Backend/Evm/Plan.lean` (`StorageLayout`), `ProofForge/Backend/Evm/IR.lean`, `ProofForge/Backend/Evm/Metadata.lean`, `scripts/evm/build-examples.sh`, `scripts/evm/foundry-smoke.sh`, CLI.

### 2.6 Tooling / deployment gaps

| Feature | Current | Needed |
|---|---|---|
| Transaction signing / broadcast | `deployment.broadcast: not-generated`. | Sign and broadcast deploy transactions; record signed tx / tx hash in deploy manifest. |
| Explorer verification | Chain profile records explorer API; no verification automation. | Submit source/Yul/ABI to Etherscan/Blockscout sourcify-compatible APIs. |
| Gas estimation | Not exposed. | Pre-flight `eth_estimateGas` integration. |
| Library linking | Not supported. | Link libraries at deploy time; record linked addresses in metadata. |
| Multi-network deploy manifests | One manifest per build with optional `chainProfile`. | Multi-network deployment plans and environment-specific overrides. |
| Wallet integration | Uses `cast send` only in Anvil smoke. | Hardware-wallet / keystore / env-key support with safe defaults. |
| Deterministic deploys | `create2` with fixed salt exists; no deterministic factory pattern. | ERC-2470 / create2 factory support. |

Files most affected: `ProofForge/Cli.lean`, `ProofForge/Backend/Evm/Metadata.lean`, `scripts/evm/anvil-deploy-smoke.sh`, `scripts/evm/validate-deploy-manifest.py`, `scripts/evm/validate-deploy-run.py`, chain-profile registry (`ProofForge/Target/Registry.lean` or `docs/targets/evm.md`).

### 2.7 Formal verification gaps

| Feature | Current | Needed |
|---|---|---|
| Bytecode equivalence | FV checks emitted Yul against IR traces via a narrow Yul model. | Direct EVM bytecode equivalence or `solc` SMT-backed equivalence claims. |
| EVM opcode semantics model | `YulSemantics.lean` covers a small subset (arithmetic, storage, memory, logs, calldata). | Expand model to cover new opcodes (context, `call` semantics, `returndata`, `create`, `selfdestruct`). |
| SMT integration | None for EVM. | Connect generated Yul/bytecode invariants to SMT or `solc` model-checker outputs. |
| Storage-layout correctness proofs | Slot layout is computed in Plan; no proof of correctness. | Prove storage layout compatible with Solidity for supported shapes. |
| ABI encoding correctness | Validated by Foundry tests; no formal proof. | Machine-checked ABI codec equivalence to Solidity `abi.encode`. |

Files most affected: `ProofForge/Backend/Evm/YulSemantics.lean`, `ProofForge/Backend/Evm/Refinement.lean`, `ProofForge/IR/Semantics.lean`, new theorem modules under `Tests/`.

---

## 3. Implementation Phases

The roadmap is split into **six phases**, each 2–10 engineering days, sequenced from low-risk/high-utility foundations toward higher-risk features. Each phase lists goals, deliverables, success criteria, key files, and risks.

### Phase 0: Foundations — diagnostic, coverage, and plan hardening (5–7 days)

**Goals**

- Make the EVM backend easier to extend by hardening the semantic-plan → Yul boundary and tightening the diagnostic/coverage machinery.
- Ensure every unsupported gap added in later phases fails explicitly and is recorded in `Tests/Backend/Evm/EvmCoverage.tsv`.

**Concrete deliverables**

1. Refactor `ProofForge/Backend/Evm/IR.lean` so that all remaining direct Yul construction routes through `ProofForge.Backend.Evm.Plan` / `ToYul` helpers; delete the legacy inline slot builders that duplicate `StorageSlotPlan` logic.
2. Add an IR-extension checklist and a coverage-manifest helper so new `ValueType`/`ContextField`/`Effect` constructors automatically require a manifest entry.
3. Introduce a typed diagnostic code enum in `ProofForge.Backend.Evm.Validate`/`IR` (e.g. `EvmDiagnosticCode`) so CLI/tests can assert stable error codes, not only strings.
4. Add a `ProofForge.Backend.Evm.Plan.ContextPlan` constructor and extend `ModulePlan` with a `contextOps` field, preparing for Phase 1 context opcodes.
5. Standardize the "golden Yul + solc + Foundry + metadata validator" pattern into a single `scripts/evm/run-ir-smoke.sh` helper used by all `*-ir-smoke.sh` scripts.

**Success criteria / new or modified CI gates**

- `just evm-plan`, `just evm-semantic-plan`, `just evm-diagnostics`, `just evm-coverage`, and `just evm-ir-smokes` remain green.
- Coverage manifest checker reports zero unclassified constructors.
- New helper reduces per-fixture smoke script boilerplate by ≥50%.

**Key files/modules to touch**

- `ProofForge/Backend/Evm/IR.lean` — remove duplicated slot-expression builders.
- `ProofForge/Backend/Evm/Plan.lean` — add `ContextPlan`/`contextOps` scaffolding.
- `ProofForge/Backend/Evm/Validate.lean` — diagnostic code enum.
- `ProofForge/Backend/Evm/ToYul.lean` — route all storage slots through plan.
- `Tests/Backend/Evm/EvmCoverage.tsv` — classification updates.
- `scripts/evm/run-ir-smoke.sh` (new) and existing `*-ir-smoke.sh`.

**Main risks**

- Refactoring `IR.lean` may perturb golden Yul outputs; mitigate by running `scripts/evm/build-examples.sh` and all IR smokes before/after.
- Over-engineering the diagnostic enum; keep it string-compatible.

---

### Phase 1: Context opcode expansion (4–6 days)

**Goals**

- Extend the portable IR context surface with the most commonly used EVM block/transaction opcodes.

**Concrete deliverables**

1. Add new `ContextField` constructors in `ProofForge/IR/Contract.lean`:
   - `.timestamp` → `block.timestamp`
   - `.chainId` → `chainid()`
   - `.origin` → `tx.origin`
   - `.gasPrice` → `tx.gasprice`
   - `.blockHash (offset : Expr)` → `blockhash(number - offset)` or `blockhash(n)`
   - `.gasLeft` → `gasleft()`
   - `.coinbase`, `.baseFee`, `.prevRandao` (optional stretch)
2. Update `ProofForge.Backend.Evm.Plan` with `ContextOp` plan nodes and `ProofForge.Backend.Evm.YulSemantics.lean` with corresponding executable semantics.
3. Add `ContextExtendedProbe` under `ProofForge/IR/Examples/` and `Examples/Backend/Evm/` with golden Yul + Foundry assertions using `vm.warp`, `vm.fee`, `vm.roll`, `vm.prank`.
4. Update capability registry: new or updated `env.block` semantics; document that `caller.sender` stays separate from `tx.origin`.

**Success criteria / new or modified CI gates**

- `just evm-smoke context-extended` (new) passes golden Yul, solc, Foundry.
- `Tests/Backend/Evm/EvmCoverage.tsv` marks the new `ContextField` constructors as `validated`.
- `Tests/Backend/Evm/EvmDiagnostics.lean` has cases for statement-position misuse and unsupported combinations.
- `ProofForge/Backend/Evm/Refinement.lean` adds a trace obligation for the new probe.

**Key files/modules to touch**

- `ProofForge/IR/Contract.lean`
- `ProofForge/Backend/Evm/Validate.lean`
- `ProofForge/Backend/Evm/Plan.lean`
- `ProofForge/Backend/Evm/IR.lean`
- `ProofForge/Backend/Evm/YulSemantics.lean`
- `ProofForge/Backend/Evm/Refinement.lean`
- `ProofForge/IR/Examples/Backend/EvmContextProbe.lean` (extend) or new probe.
- `docs/capability-registry.md`

**Main risks**

- `blockhash` semantics differ pre/post-merge and on L2s; keep it simple (raw opcode) and document chain-profile caveats.
- `chainid()` is deterministic in `solc --strict-assembly` but may differ at runtime; tests must use `vm.chainId`.

---

### Phase 2: Address, bytes, and string ABI types (6–9 days)

**Goals**

- Introduce `address`, variable-length `bytes`, and `string` as first-class portable IR types with correct ABI encoding.

**Concrete deliverables**

1. Extend `ValueType`:
   - `.address` (20-byte value)
   - `.bytes` (dynamic byte array)
   - `.string` (dynamic UTF-8 string)
2. Add validation rules: addresses reject non-20-byte literals; strings are opaque byte sequences at IR level (UTF-8 validation optional at SDK layer).
3. Implement ABI head-tail encoding in `ProofForge.Backend.Evm.IR`:
   - Static params interleave with dynamic offsets.
   - Dynamic values append `(length, data)` tail with 32-byte word padding.
4. Add dispatcher decoding and return-data encoding for dynamic types.
5. Add `EvmDynamicAbiProbe` with functions like `echo_bytes(bytes)`, `echo_string(string)`, `transfer(address,uint256)`.
6. Update artifact metadata so `abi.entrypoints` records dynamic ABI types and flattened word count becomes "static words + dynamic slots".

**Success criteria / new or modified CI gates**

- `just evm-smoke dynamic-abi` (new) passes golden Yul, solc, Foundry.
- Foundry tests verify `abi.encode`/`abi.decode` round-trips for `bytes`, `string`, and `address`.
- Malformed calldata (short tail, bad offset, invalid address length) reverts.
- Coverage manifest classifies new `ValueType` constructors.

**Key files/modules to touch**

- `ProofForge/IR/Contract.lean`
- `ProofForge/Backend/Evm/Validate.lean`
- `ProofForge/Backend/Evm/Plan.lean` (`AbiParamPlan`/`ReturnPlan`)
- `ProofForge/Backend/Evm/IR.lean` (dispatcher, return encoding)
- `ProofForge/Backend/Evm/Metadata.lean`
- `ProofForge/Backend/Evm/YulSemantics.lean`
- `ProofForge/Backend/Evm/Refinement.lean`
- `scripts/evm/validate-artifact-metadata.py`

**Main risks**

- ABI head-tail encoding is error-prone; use Foundry Solidity reference tests as the oracle.
- Memory management for dynamic values in Yul must avoid clobbering the dispatcher's scratch space; define a stable memory layout contract.

---

### Phase 3: Storage packing, small types, and metadata hash (7–10 days) ✅

**Goals**

- Improve bytecode size and verification compatibility by packing small types and emitting standard metadata.

**Concrete deliverables**

1. Add packed `ValueType` variants or packing metadata:
   - `uint8`, `uint16`, `uint32`, `uint64`, `uint128`, `bool`, `address` map to packed slots.
   - Storage layout computes byte offsets within a 32-byte slot.
2. Update `StorageLayout` in `ProofForge.Backend.Evm.Plan` to support per-field bit/byte offsets.
3. Lower packed reads/writes to Yul `sload` + bit masking / shifting.
4. Emit `storage-layout` JSON in artifact metadata.
5. Request `solc` metadata hash and append it to deployed bytecode (via `solc --metadata-hash ipfs` or manual CBOR tail).
6. Add a contract-size check in the CLI/metadata validator.

**Success criteria / new or modified CI gates**

- New `EvmPackedStorageProbe` proves that multiple small fields share slots and that reads/writes do not alias.
- `scripts/evm/validate-artifact-metadata.py` checks `storageLayout` and bytecode metadata hash tail.
- Contract-size gate warns when runtime bytecode exceeds 24,576 bytes.
- Golden Yul updates expected; `scripts/evm/build-examples.sh` diffs pass.

**Key files/modules to touch**

- `ProofForge/IR/Contract.lean` (new `ValueType` constructors or width annotations)
- `ProofForge/Backend/Evm/Plan.lean` (`StorageStatePlan` gains offset/width)
- `ProofForge/Backend/Evm/Validate.lean`
- `ProofForge/Backend/Evm/IR.lean`
- `ProofForge/Backend/Evm/Metadata.lean`
- `ProofForge/Cli.lean`
- `scripts/evm/validate-artifact-metadata.py`

**Main risks**

- Packing changes storage layout; upgrades to already-deployed contracts break unless layout is preserved. Mitigate by versioning the layout and documenting that packed layout is opt-in until stable.
- Bit-mask lowering is tedious and bug-prone; lean heavily on Foundry `vm.load` assertions.

---

### Phase 4: Dynamic arrays, memory, and calldata slices (8–10 days) ✅

**Goals**

- Support dynamic arrays in storage, memory, calldata, and ABI; add an in-memory data-location concept.

**Concrete deliverables**

1. Extend `ValueType` with `.array (element : ValueType)` (dynamic).
2. Add `StateKind.dynamicArray (elementType : ValueType)` mapped to Solidity-style length-in-slot-n, keccak256-offset storage layout.
3. Implement memory allocator helpers in Yul for in-memory dynamic arrays and strings.
4. Implement calldata slicing for dynamic calldata arrays.
5. Extend crosscalls to accept/return dynamic arrays and bytes.
6. Add `EvmDynamicArrayProbe` covering storage push/pop, memory arrays, and ABI round-trips.

**Success criteria / new or modified CI gates**

- `just evm-smoke dynamic-array` (new) passes.
- Foundry tests compare against equivalent Solidity functions for `uint256[]`, `bytes`, and `string[]`.
- Coverage manifest classifies dynamic array constructors and effects.

**Key files/modules to touch**

- `ProofForge/IR/Contract.lean`
- `ProofForge/Backend/Evm/Plan.lean`
- `ProofForge/Backend/Evm/Validate.lean`
- `ProofForge/Backend/Evm/IR.lean`
- `ProofForge/Backend/Evm/YulSemantics.lean`
- `ProofForge/Backend/Evm/Refinement.lean`
- `ProofForge/IR/Semantics.lean` (if arrays affect IR semantics values)

**Main risks**

- This is the largest codegen expansion; memory allocator bugs are hard to debug. Mitigate by keeping the allocator simple (bump-only) and validating with Foundry.
- Dynamic storage array layout must match Solidity for upgrade tooling; use `forge inspect` on a reference Solidity contract as an oracle.

---

### Phase 5: Revert reasons, custom errors, fallback, and receive (5–7 days) ✅

**Goals**

- Improve developer experience and Solidity compatibility for error handling and Ether-handling entrypoints.

**Concrete deliverables**

1. Add `Statement.revert (message? : Option String)` and `Statement.revertWithError (errorName : String) (args : Array Expr)` to the IR (or model as effects).
2. Lower revert reasons to ABI-encoded `Error(string)` and custom errors to selector + ABI args.
3. Extend typed crosscalls to decode `returndata` for failure reasons.
4. Add `EntrypointKind.fallback` and `EntrypointKind.receive` to the IR/module plan.
5. Update dispatcher: selector-less fallback runs on non-matching calldata; `receive` runs on empty calldata with value.
6. Add `EvmErrorsProbe` and `EvmFallbackProbe` with golden Yul + Foundry tests.

**Success criteria / new or modified CI gates**

- `just evm-smoke errors` and `just evm-smoke fallback` (new) pass.
- Foundry tests assert custom error selectors and revert messages.
- Sending ETH to a `receive` entrypoint succeeds; sending ETH without `receive`/`fallback payable` reverts.

**Key files/modules to touch**

- `ProofForge/IR/Contract.lean` (`Statement`, `Entrypoint`)
- `ProofForge/Backend/Evm/Validate.lean`
- `ProofForge/Backend/Evm/Plan.lean` (`EntrypointPlan`)
- `ProofForge/Backend/Evm/IR.lean` (dispatcher)
- `ProofForge/Backend/Evm/YulSemantics.lean`
- `ProofForge/Backend/Evm/Refinement.lean`
- `docs/capability-registry.md` (error capability)

**Main risks**

- Dispatcher changes affect every EVM contract; run the full `just evm-all` suite.
- `fallback payable` vs `receive` semantics are subtle; document clearly.

---

### Phase 6: Deployment tooling — broadcast, verification, gas estimation (6–9 days)

**Goals**

- Close the transaction-signing/broadcast gap and enable basic explorer verification.

**Concrete deliverables**

1. Add CLI flags for private-key source: `--private-key`, `--keystore`, `--mnemonic`, `--sender` (env-file only, never logged).
2. Implement broadcast flow in `ProofForge.Cli` or a companion script:
   - `eth_estimateGas` → sign → `eth_sendRawTransaction` → poll receipt.
   - Record tx hash, deployed address, gas used, and block in `proof-forge-deploy.json` with `deployment.broadcast: broadcast`.
3. Integrate Blockscout / Etherscan verification API:
   - Submit Yul source + metadata + constructor args.
   - Poll verification status.
4. ✅ Add `--gas-limit`, `--gas-price`, `--max-fee-per-gas`, `--max-priority-fee-per-gas` flags (mapped to `cast send` flags; `--gas-price` and `--max-fee-per-gas` are mutually exclusive).
5. ✅ Add a live `scripts/evm/broadcast-smoke.sh` that deploys Counter to a local Anvil with explicit gas flags and verifies the deploy-run manifest.

**Success criteria / new or modified CI gates**

- `scripts/evm/anvil-deploy-smoke.sh` optionally signs/broadcasts and validates the resulting `proof-forge-deploy-run.json`.
- New `scripts/evm/broadcast-smoke.sh` passes locally (Anvil only; live network gated behind env vars).
- Metadata schema version bumps to `2` if needed.

**Key files/modules to touch**

- `ProofForge/Cli.lean`
- `ProofForge/Backend/Evm/Metadata.lean`
- `scripts/evm/anvil-deploy-smoke.sh`
- `scripts/evm/validate-deploy-run.py`
- `scripts/evm/validate-deploy-manifest.py`
- New `scripts/evm/broadcast-smoke.sh`.

**Main risks**

- Handling real private keys in a CLI is a security hazard; use `cast` for signing or lean on Foundry's secure key management rather than reimplementing crypto.
- Explorer verification APIs are rate-limited and vary; start with Blockscout because the `robinhood-chain-testnet` profile already points to it.

---

## 4. Cross-Cutting Concerns

### 4.1 IR evolution

Every phase that adds `ValueType`, `ContextField`, `Expr`, `Effect`, `Statement`, `Entrypoint`, or `StateKind` constructors must:

1. Update `Tests/Backend/Evm/EvmCoverage.tsv` with `validated`, `lowered`, `unsupported`, or `structural`.
2. Add explicit diagnostics in `ProofForge.Backend.Evm.Validate` for unsupported shapes.
3. Add a Lean test case in `Tests/Backend/Evm/EvmDiagnostics.lean` locking the diagnostic text or code.
4. Extend the semantic model in `ProofForge/IR/Semantics.lean` if the new construct affects observable traces.
5. Extend the executable Yul model in `ProofForge/Backend/Evm/YulSemantics.lean` before claiming refinement obligations.

### 4.2 Capability registry updates

- `env.block` should expand to cover timestamp, chainid, origin, gasprice, blockhash, gasleft, coinbase, basefee, prevrandao.
- Consider new capability ids:
  - `env.transaction` for `tx.origin`, `tx.gasprice`, `msg.value` (some already under `value.native`).
  - `env.extcode` for `extcodesize`/`extcodehash`/`extcodecopy`.
  - `control.revert` for custom errors/revert messages.
  - `crosscall.dynamic_return` for variable-length return data.
  - `data.dynamic_array`, `data.bytes`, `data.string`.
  - `storage.dynamic_array`.
  - `deploy.broadcast`, `deploy.verify`.
- Keep the registry in `docs/capability-registry.md` in sync with `ProofForge/Target/Capability.lean`.

### 4.3 Diagnostic coverage

- Maintain the invariant that **any portable IR shape the EVM backend cannot lower must fail before Yul generation** with a stable message.
- New diagnostics must be added to `Tests/Backend/Evm/EvmDiagnostics.lean` and, where CLI-facing, to `scripts/evm/diagnostic-smoke.sh`.
- Prefer diagnostic codes over prose for programmatic consumers.

### 4.4 Golden-Yul / Foundry / Anvil gate patterns

Every new feature must include the canonical gate stack:

1. **Golden Yul** — add/update `.golden.yul` in `Examples/Backend/Evm/`; `scripts/evm/build-examples.sh` diffs.
2. **solc bytecode** — `solc --strict-assembly` must produce runtime bytecode.
3. **Artifact metadata** — `scripts/evm/validate-artifact-metadata.py` checks selectors, capabilities, ABI layouts.
4. **Foundry runtime** — `scripts/evm/foundry-smoke.sh` or a new `scripts/evm/*-ir-smoke.sh` exercises behavior and malformed-calldata reverts.
5. **Anvil deploy** — for features touching deploy/initcode, extend `scripts/evm/anvil-deploy-smoke.sh`.
6. **Refinement** — add a trace obligation in `ProofForge/Backend/Evm/Refinement.lean` if the feature changes observable state/logs/returns.

### 4.5 Security & safety notes

- Private-key handling in Phase 6 must delegate to `cast` or Foundry; never log keys or implement raw secp256k1 signing in Lean for this roadmap.
- `selfdestruct` and `delegatecall` are high-risk opcodes; if exposed, require explicit opt-in capability or target-extension annotations.
- Storage packing changes are layout-breaking; gate them behind an explicit `--evm-storage-layout packed|solidity-compatible` flag until stable.

---

## 5. Recommended Starting Phase and Rationale

**Start with Phase 0** (foundations / diagnostic and plan hardening).

Rationale:

- It is the lowest-risk phase and unblocks all later work.
- It establishes stable diagnostic codes and a coverage-manifest discipline, which prevents "silent unsupported" bugs when `ValueType`/`ContextField` are extended in Phases 1–4.
- Refactoring `IR.lean` to route everything through the semantic plan makes Phases 1 and 2 (context opcodes, dynamic ABI) significantly easier to implement correctly.
- It produces no user-facing semantic changes, so it can be validated entirely within existing CI (`just evm-all`) without new external tooling.
- It aligns with the project's docs-first, gate-first culture: every later phase can then follow the "coverage manifest → diagnostics → golden Yul → Foundry → Anvil" pattern already proven in the existing 22 IR smokes.

After Phase 0, the suggested order is **Phase 1 → Phase 2 → Phase 5 → Phase 3 → Phase 4 → Phase 6**. This prioritizes:

1. Developer-visible features (context reads, address/bytes/string) that unlock real contracts.
2. Error/fallback ergonomics (Phase 5), which are cheap and high-value.
3. Codegen quality (packing/metadata) before the large dynamic-array expansion.
4. Deployment automation (Phase 6) last because it depends on stable metadata and bytecode.

---

## Appendix: Quick reference — files by concern

| Concern | Files |
|---|---|
| Portable IR | `ProofForge/IR/Contract.lean`, `ProofForge/IR/Semantics.lean`, `docs/portable-ir.md` |
| EVM validation / planning | `ProofForge/Backend/Evm/Validate.lean`, `ProofForge/Backend/Evm/Plan.lean`, `ProofForge/Backend/Evm/Lower.lean` |
| Yul generation | `ProofForge/Backend/Evm/IR.lean`, `ProofForge/Backend/Evm/ToYul.lean`, `ProofForge/Compiler/Yul/AST.lean`, `ProofForge/Compiler/Yul/Printer.lean` |
| Metadata / deploy | `ProofForge/Backend/Evm/Metadata.lean`, `ProofForge/Cli.lean`, `scripts/evm/validate-artifact-metadata.py`, `scripts/evm/validate-deploy-manifest.py`, `scripts/evm/validate-deploy-run.py` |
| Formal model / refinement | `ProofForge/Backend/Evm/YulSemantics.lean`, `ProofForge/Backend/Evm/Refinement.lean` |
| Tests & coverage | `Tests/Backend/Evm/EvmDiagnostics.lean`, `Tests/Backend/Evm/EvmPlan.lean`, `Tests/Backend/Evm/EvmSemanticPlan.lean`, `Tests/Backend/Evm/EvmCoverage.tsv` |
| CI / smokes | `justfile`, `scripts/evm/*-ir-smoke.sh`, `scripts/evm/diagnostic-smoke.sh`, `scripts/evm/build-examples.sh`, `scripts/evm/foundry-smoke.sh`, `scripts/evm/anvil-deploy-smoke.sh` |
| Examples / golden fixtures | `Examples/Backend/Evm/*.golden.yul`, `ProofForge/IR/Examples/*.lean` |
| Docs / registry | `docs/targets/evm.md`, `docs/capability-registry.md`, `docs/target-roadmap.md`, `docs/implementation-backlog.md`, `docs/gate-status.md` |
