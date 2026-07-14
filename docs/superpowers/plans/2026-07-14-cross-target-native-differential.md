# Cross-Target Native Differential Validation Plan

Status: **Accepted; CMP-0/CMP-1/CMP-2 done, CMP-3 in progress (2026-07-14)**

Design: [Cross-Target Native Differential Validation](../specs/2026-07-14-cross-target-native-differential-design.md)

## Execution Rule

This is a validation track, not a replacement for the current architecture
queue. A-CUT1e-c2, CMP-0, CMP-1, and A-CUT2/CMP-2 are complete. CMP-3 now
validates the ValueVault cutover as part of A-CUT3 acceptance work. Target-extension tasks
are attached to their target migration instead of opening unrelated backend
work early.

Allowed states are `pending`, `in_progress`, `blocked`, and
`done (verified at <sha>)`. Every completed task records exact gates and updates
the implementation log.

## Current Inventory

| Asset | Current state | Planned disposition |
|---|---|---|
| `testkit/scenarios` | 13 portable v0 scenarios | migrate logical steps during CMP-1/CMP-2 |
| `testkit/compare/near` | 28 Rust v0 references plus offline/Sandbox runners; historical matrix is measurement-only | replace v0 manifests and observations incrementally |
| `references/solana/pinocchio` | 7 Rust v0 references plus 14 static/live scripts | retain as Solana extension catalog and replace v0 manifests in CMP-SOL |
| Stylus differential scripts | 5 focused Rust/direct-Wasm comparisons plus VM/host runners; no v1 native-reference manifest | adapt after the primary-triad schema stabilizes |
| EVM runtime gates | Counter has a pinned Solidity v1 reference and normalized Anvil result; two other handwritten sources remain partial | migrate the remaining references with their A-CUT3 families in CMP-3/CMP-EVM |

## Task Order

### CMP-0 - Freeze inventory and shared contracts

State: `done (verified at 18f15e59)`

- Inventory every native reference, runner, manifest schema, scenario, and CI
  gate; label historical measurement-only reports honestly.
- Define versioned schemas for reference provenance, logical scenarios,
  normalized observations, required coverage, and allowed divergences.
- Add a schema validator that rejects missing provenance, duplicate step IDs,
  unknown observation dimensions, and semantic success with incomplete
  coverage.
- Provide migration adapters for current NEAR v0 and Solana v0 manifests; do
  not bulk rewrite every reference before the validator exists.

Acceptance:

- One generated inventory lists all current NEAR, Solana, Stylus, and EVM
  comparison assets without claiming unobserved equivalence.
- Valid current manifests can migrate explicitly; malformed fixtures fail.
- No compiler or target plan imports the comparison schema.

Focused verification: schema unit tests, manifest fixtures, comparison-matrix
snapshot tests, and `git diff --check`.

Completion evidence:

- `testkit/differential/inventory.v1.json` deterministically lists 85 tracked
  assets across NEAR, Solana, Stylus, EVM, and the portable scenario/CI layer;
  `semanticVerifiedCount` is zero, so existing partial evidence is not promoted.
- Four checked-in v1 JSON schemas and `scripts/differential/contracts.py`
  enforce provenance, unique step IDs, the closed observation-dimension set,
  exact coverage, runner status, and fail-closed semantic promotion.
- Explicit NEAR v0 and Solana v0 migration functions validate all 28 and 7
  current manifests. Missing historical fields are recorded as inference and
  incomplete provenance; migrated observations are skipped and never semantic
  successes. These test-data migrations are deleted as each target moves to v1;
  they are not compiler compatibility routes.
- `just differential-contracts` passes 11 schema/malformed/migration/boundary
  tests, the generated inventory check, and the NEAR matrix snapshot test.

### CMP-1 - Normalized observation runner contract

State: `done (verified at 7fee238c)`

- Add shared runner result types for call status/error, typed return, state,
  events, target-owned external actions, interface assertions, and resources.
- Define actor, account, value, and clock normalization without erasing
  target-native distinctions.
- Require explicit coverage declarations per scenario and per runner.
- Keep target adapters small: they translate native observations but do not
  reinterpret compiler semantics.

Acceptance:

- A synthetic test proves matching results pass, any mismatched dimension
  fails, and missing required observations cannot produce `semanticMatch=true`.
- Resource measurements remain target-local and cannot be aggregated into a
  synthetic cross-chain score.

Completion evidence:

- `proof-forge.differential.runner-result.v1` defines typed logical values,
  accounts, actors, clocks, runner status, declared coverage, and per-step
  observations without entering compiler modules.
- The comparator checks all eight observation dimensions independently,
  requires exact declared/actual coverage, rejects unclassified errors, and
  keeps allowed divergences scoped to an exact dimension and JSON path.
- Cross-target external actions compare their logical payload while retaining
  target-owned native payloads. Resource observations compare only within one
  target family and cannot expose an aggregate cross-chain score.
- `just differential-contracts` passes 11 base-contract tests, 12 runner and
  comparator tests, the 90-asset inventory check, and the NEAR matrix snapshot.

### CMP-2 - Counter primary-triad native pilot

State: `done (verified at e2834c59)`

Direct-route prerequisite: `42183403` proves public Source/Loader, EVM,
Solana assembly/ELF, and NEAR/Wasm consume Authored/Core/target plans without a
ContractSpec sidecar or Legacy fallback. `just portable-counter-multi-target`
and each target-specific Counter testkit runner pass; CMP-2 must now attach the
independent native references to the v1 observation/comparator contract.
A-CUT2h commit `b2d673b4` also proves no retired Counter Product alias or
backend ContractSpec wrapper remains; EVM constructor evidence is loaded as a
target-owned attachment after EVM selection.

- Use the unchanged `Examples/Product/Counter.lean` as the only ProofForge
  business source.
- Add or pin independent references: Solidity for EVM, Pinocchio/native Rust for
  Solana, and `near-sdk` Rust for NEAR.
- Execute the same initialize/increment/get scenario with equivalent logical
  actors and inputs in deterministic runners.
- Compare status, returns, state, errors, emitted logs when present, artifact
  metadata, and target-local resources.
- Prove the ProofForge side enters through the direct Authored/Canonical route,
  not `ContractSpec`, `IR.Module`, or a Legacy adapter.

Acceptance:

- All three targets report complete required observation coverage and semantic
  match.
- Each reference manifest pins source provenance, license, and toolchain.
- The focused pilot runs without a full `just check`.

Completion evidence:

- `just differential-counter` builds the unchanged Product Counter through
  direct Authored/checked Core target plans and rejects any ContractSpec
  sidecar. EVM and Solana execute on Anvil and Mollusk; both ProofForge and
  near-sdk Wasm execute on the unmodified upstream NEAR VM.
- Three v1 reference manifests pin SHA-256 source revisions, Apache-2.0, and
  exact compiler/framework toolchains. The Pinocchio reference now returns its
  `get` value through the real Solana return-data syscall.
- EVM, Solana, and NEAR each cover all eight observation dimensions with
  `semanticMatch=true` and zero unallowed mismatches. Target-local gas/CU
  differences are retained under four exact resource paths and are never
  aggregated into a cross-chain score.
- The generated inventory now tracks 96 assets; the three references, v1
  scenario, deterministic runner, and focused gate are the six verified CMP-2
  assets. Comparison code remains outside `ProofForge/`.

### CMP-3 - Stateful portable catalog expansion

State: `in_progress; attached to A-CUT3`

- ValueVault's public source is now direct-only and compiles through checked
  Core on all three primary targets. Add it as the first stateful native
  scenario; no Legacy artifact is eligible for comparison.
- Add the missing independent Solana Rust ValueVault reference; a skip or reuse
  of ProofForge-generated sBPF is not acceptable native evidence.
- Then select one representative each for authorization, map/collection state,
  events/errors, and portable crosscall intent.
- Reuse `Examples/Product`; do not create target-specific Product copies.
- Record unsupported target capabilities as named compile failures, not skips.

Checkpoint (2026-07-14): the 13-step v1 ValueVault scenario now fixes the
stateful lifecycle, all eight observation dimensions, and an arithmetic
underflow rejection. An independent Pinocchio implementation and complete v1
Solana provenance manifest are checked in and host-typechecked. Inventory
records both assets with `semanticEvidence=none`; the next slice must complete
the Solidity/near-sdk references and execute both artifacts on all three VMs
before either asset is promoted.

Reference checkpoint (2026-07-14): the handwritten Solidity and near-sdk
implementations now cover all seven methods, five event families, snapshot,
and checked arithmetic rejection. Their v1 manifests pin `solc` 0.8.30 and
near-sdk 5.28.3/Rust 1.94 respectively; native Solidity compilation, near-sdk
host lifecycle tests, and release Wasm compilation pass. All three references
were held at `semanticEvidence=none` until the shared VM comparison executed.

ValueVault execution checkpoint (2026-07-14): `just
differential-value-vault` now builds the direct Authored Product source through
checked Core and target-owned plans, then executes both implementations on
Anvil, Mollusk, and the upstream NEAR VM. All 13 logical steps, including the
rejected `release(201)`, cover all eight observation dimensions and report
`semanticMatch=true` for EVM, Solana, and NEAR. Native Solidity `uint64` and
ProofForge EVM `uint256` ABIs remain target-local calling details and normalize
to the same portable `u64` interface; no compiler adapter or fallback was
added. The generated inventory has 102 assets and promotes exactly six CMP-3
ValueVault assets, for 12 verified assets total. CMP-3 remains active for the
authorization, map/collection, event/error, and portable-crosscall
representatives.

Authorization authoring checkpoint (2026-07-14): A-CUT3b1 adds only
target-neutral direct Source operations: portable caller identity, a numeric
zero address, and equality/inequality assertions. The focused `just
authored-authorization` gate proves they normalize to Canonical Core
`contextRead.sender`, `compare`, and `assert` operations and reach EVM,
Solana, and NEAR target plans without `Source.Internal`, Legacy adapters, or a
target-specific frontend branch. A-CUT3b2 then moves Product Ownable itself to
that single route, deletes its ContractSpec/v1 aliases and obsolete EVM wrapper,
and emits EVM, Solana, and final NEAR Wasm artifacts carrying
`contract-source-authored` / `canonical-core-v1`. The focused gate rejects
legacy sidecars and proves NEAR's address carrier is owned by the Wasm-host
plan. Independent native Ownable differential evidence is the next CMP-3
authorization slice.

Acceptance:

- ValueVault passes the primary triad with state snapshots and negative cases.
- Every selected family has a documented observation contract and honest target
  support matrix.
- A-CUT3 cannot mark a product family migrated solely from golden artifacts.

### CMP-SOL - Solana extension conformance

State: `pending with IR-B5`

- Migrate existing Pinocchio references to the shared provenance/observation
  contract.
- Add direct public-authoring scenarios for account declarations, PDA
  derivation, CPI, signer/writable/order constraints, and instruction payloads.
- Compare static plan/manifest facts first, then Mollusk or Surfpool behavior
  when the required toolchain exists.

Acceptance:

- The ProofForge artifact is produced from typed Solana extensions after target
  selection.
- Independent Rust references and ProofForge programs run the same inputs and
  compare account/state/CPI observations.
- No Solana constructor is added to shared IR.

### CMP-NEAR - NEAR native-reference replay

State: `pending with NEAR-R4`

- Reuse the existing `near-sdk` reference catalog and Sandbox harness.
- Complete argument, caller, return, log, storage, promise/action, and negative
  error observations required by each selected scenario.
- Rebuild the ProofForge side through the canonical-only public route before
  accepting historical behavior claims.

Acceptance:

- Counter, ValueVault, and the N-T1 through N-T4 representative contracts pass
  fail-closed semantic comparison from the new route.
- Historical measurement-only reports remain excluded from semantic rankings.
- Receipt scheduling claims use Sandbox/node evidence, not `near-vm-runner`
  conformance alone.

### CMP-EVM - Solidity reference catalog

State: `pending after CMP-2; may proceed with A-CUT3 EVM slices`

- Add minimal independent Solidity references for Counter and ValueVault, then
  representative ABI/event/revert/call/storage cases.
- Pin `solc` and reference origins; run both artifacts on the same `revm` or
  Anvil scenario.
- Retain existing Yul shape and bytecode gates as structural checks, not the
  semantic oracle.

Acceptance:

- Native EVM comparisons use Solidity; any Rust model is labeled secondary.
- Return data, storage, logs, reverts, and gas bands are compared where the
  scenario requires them.

### CMP-STYLUS - Stylus reference normalization

State: `pending after primary-triad CMP-2/CMP-3`

- Adapt existing `stylus-sdk` Rust differential gates to the shared manifest and
  observation contract.
- Preserve the dedicated `StylusPlan`; do not route Stylus through NEAR plans
  merely because both emit Wasm.

Acceptance:

- Direct HostIO Wasm and pinned Rust SDK references execute the same scenarios
  with complete required observations.

### CMP-CI - Tiered execution and promotion policy

State: `pending after CMP-2`

- Add a fast affected-path command for schema/static/VM differentials.
- Keep node/sandbox/live dual-deploy jobs in target-specific lanes with explicit
  tool prerequisites and evidence artifacts.
- Do not add heavyweight live suites to every development slice.
- Require at least one independent native-reference or VM behavior gate before
  a capability is advertised as implemented.

Acceptance:

- Local inner-loop comparison is focused and deterministic.
- CI reports skipped tools separately from passed comparisons.
- IR-B8/A-CUT5 sign-off consumes a generated matrix whose semantic status fails
  closed on missing coverage.

## Integration With The Active Queue

| Order | Work | Comparison requirement |
|---:|---|---|
| 1 | A-CUT1e-c2 | Use existing Solana canonical and Pinocchio evidence; do not wait for CMP framework consolidation |
| 2 | CMP-0 | Freeze schemas and inventory before new references proliferate |
| 3 | A-CUT2 plus CMP-1/CMP-2 | Direct authoring cutover and Counter native pilot land together before A-CUT2 completion |
| 4 | A-CUT3 plus CMP-3/CMP-EVM | Product catalog migration gains stateful native evidence incrementally |
| 5 | IR-B5 plus CMP-SOL | Solana target extensions receive independent Rust conformance |
| 6 | NEAR-R4 plus CMP-NEAR | Canonical-only NEAR artifacts replay the existing native catalog |
| 7 | IR-B8/A-CUT5 plus CMP-CI | Legacy deletion and boundary closure require a fail-closed matrix |
| 8 | CMP-STYLUS and later targets | Adopt the stable contract without disturbing the primary migration order |

## Commit Discipline

Each task is a separate reviewable commit or short series: schema/validator,
one target adapter, one scenario/reference, then CI wiring. Run only focused
affected gates during development. Full `just product` or `just check` remains
an integration checkpoint, not a per-reference requirement.
