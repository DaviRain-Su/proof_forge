# Multi-chain Vision Gap Audit

Status: **Active remediation source of truth** — Delivery Wave 0 (P0
correctness & claim-honesty gates) is **closed** as of commit `1599f37d`
(2026-07-11); every PF-P0-0N gate named below now runs in `just check`.
The finding bodies are retained verbatim as the traceable remediation record;
their per-task acceptance was re-checked against the gates listed in the
*Wave 0 closure* section.

Date: 2026-07-10 (audit). Wave 0 closure verified 2026-07-11.

This audit compares the product vision -- maintain one body of business logic
and select a target at build time -- with the code and runnable gates on
`main`. It is the current priority source for cross-project remediation. Older
backlogs and phase plans remain useful implementation history, but they do not
override the findings or ordering in this document.

Long-running execution entrypoint:
[`Durable multi-chain remediation agent goal`](agent-goal-prompt.md).

The official general-purpose business-logic surface is `contract_source`,
which elaborates to `ContractSpec` and portable IR. `TokenSpec` remains the
first-class specialized token-intent surface. Compiling arbitrary Lean
functions is not a goal of this audit. The primary product targets are `evm`,
`solana-sbpf-asm`, and `wasm-near`; the other registered targets are audited
for honest behavior and explicit promotion criteria, not equal production
parity.

## Executive verdict

ProofForge has a real multi-chain vertical slice. The same Counter, ValueVault,
and RemoteCall business sources can be lowered through the portable path for
the three primary targets, and the repository contains substantial runtime,
artifact, and formal checks. The project is not merely a collection of source
templates.

The final vision is not yet true for the full target portfolio. The largest
risk is a split contract between five surfaces:

1. what `--list-targets` advertises;
2. what target-first `build` accepts;
3. which input the backend actually lowers;
4. whether the output is an intermediate or a deployable artifact; and
5. what the metadata and documentation claim was validated.

The most serious example is silent input substitution: four target-first
builds accept `Examples/Product/ValueVault.lean`, return success, and emit the
built-in Counter instead. This must be fixed before adding more target breadth.

## Audit evidence

The following commands were run against commit `92e79867` on 2026-07-10:

| Check | Audit-time result | What it establishes |
|---|---|---|
| `just product` | Pass with a coverage gap | `portable-default` counts 20 product sources, but `Tests/Product/Matrix.lean` imports only 18; Counter and RemoteCall build across the primary targets, with Soroban also exercised for RemoteCall |
| `lake env proof-forge --list-targets` | Pass, 10 ids | Registry currently exposes the ten rows in the target matrix below |
| `lake env lean --run Tests/TargetRegistry.lean` | Pass | Registry lookup and declared profiles are internally consistent |
| `scripts/docs/audit-doc-code-sync.sh` | Pass with 7 advisory findings | Current docs still have one P1 and six P2 code-sync findings |
| `scripts/i18n/check-sync.sh` | Fail | `README.md`, `docs/INDEX.md`, `docs/portable-ir.md`, and `docs/targets/wasm-family.md` were stale before this audit-document change |
| `just check` | Stopped at `docs-check` | All steps reached before `scripts/i18n/check-sync.sh` passed; the aggregate exited on the same four stale translations, so later recipes did not run |

Delivery verification was repeated after integrating this audit. The stale
translations were synchronized, and `just check` then exposed a pre-existing
testkit expectation that lagged the actionable Solana empty-peer diagnostic
added in `09e73553`. The scenario was updated to assert a stable diagnostic
prefix. Targeted testkit checks and the final full `just check` both passed.
This baseline repair does not close any architecture task below.

The silent-substitution probe used the same source for five targets:

```sh
lake env proof-forge build --target <target> --root . \
  -o build/audit-input-identity/<target> \
  Examples/Product/ValueVault.lean
```

Observed results:

| Target | Exit | Output identity |
|---|---:|---|
| `psy-dpn` | 0 | Counter `.psy` |
| `aleo-leo` | 0 | `program counter.aleo` |
| `wasm-cosmwasm` | 0 | static CosmWasm Counter WAT |
| `move-aptos` | 0 | Counter Move package |
| `wasm-cloudflare-workers` | 1 | `unknown target 'wasm-cloudflare-workers'` |

Generated files live under ignored `build/` and are not repository sources.

## Current target matrix

Maturity in this table describes demonstrated behavior, not the label currently
printed in README.

| Target | Accepted product input today | Pipeline and output | Validation evidence | Honest current status | Promotion blocker |
|---|---|---|---|---|---|
| `evm` | `contract_source`; specialized `TokenSpec` | Contract body: `ContractSpec -> IR -> EVM Plan -> Yul AST -> solc -> bytecode`; token intent: `TokenSpec -> evm-erc20-contract` | Foundry, Anvil, metadata and executable Yul traces | Primary Experimental; deployable | Broader product scenarios and proof fragment |
| `solana-sbpf-asm` | `contract_source`; specialized `TokenSpec` | Contract body: `ContractSpec -> IR -> Asm AST -> .s`; token intent: `TokenSpec -> solana-spl-token-plan` or `solana-token-2022-plan`. `SolanaModulePlan` exists but the generic CLI path does not consume the full plan, and source build does not invoke `sbpf build` | assembly, Pinocchio equivalence, optional/live ELF gates, executable sBPF model | Primary Experimental; final artifact path incomplete | Plan-driven production path, generic source-to-ELF and truthful metadata |
| `wasm-near` | `contract_source`; specialized `TokenSpec` | Contract body: `ContractSpec -> IR -> smaller surface plan/lower context -> Wasm AST -> WAT`; token intent: `TokenSpec -> near-nep141-plan`. `NearModulePlan` exists mainly as a side/test path, and Wasm is optional even for a successful build | offline host, WAT/Wasm metadata, formal artifact/trace anchors | Primary Experimental; locally executable when Wasm exists | Full plan-driven production path, strict Wasm build, general async/runtime and sandbox gate |
| `wasm-stellar-soroban` | `contract_source` | shared EmitWat with `HostBridge.soroban` -> WAT/Wasm | product materialization smoke and Counter refinement | Host-adapter Spike | Wrong NEAR capability plan, NEAR wrapper naming, auth/contract-spec/runtime gaps |
| `wasm-cosmwasm` | fixture in reality | Counter-specific WAT adapter; target-first source input is ignored | Counter golden and optional `cosmwasm-check` | Counter Spike | Fail-closed input handling, general plan/AST path, real submessages/runtime |
| `wasm-cloudflare-workers` | fixture emit only | portable IR fixture -> TypeScript Worker | TypeScript type-check and Wrangler dry-run when installed | Off-chain Research Spike | Target-first build lacks an explicit unsupported-command path; profile incorrectly says Wasm |
| `move-aptos` | fixture in reality | Counter -> string-rendered Move package | golden package and optional Aptos CLI smoke | Counter Spike | Fail-closed input handling, general Move plan/AST, runtime scenario |
| `move-sui` | explicit Counter fixture | Counter -> string-rendered Move package | package/layout/client checks; local Sui gate when installed | Counter MVP | General source lowering and typed Move pipeline |
| `psy-dpn` | fixture/sourcegen subset in reality | built-in modules -> Psy Plan/AST -> `.psy`, optionally Dargo circuit JSON | golden, diagnostics, metadata and optional Dargo smokes | Restricted sourcegen lane; not generic `contract_source` | Fail-closed input handling and exact supported-fragment contract |
| `aleo-leo` | fixture/sourcegen subset in reality | built-in modules -> Leo AST/printer -> Leo source | golden/sourcegen smokes; Leo CLI optional | Research Spike | Fail-closed input handling and printer errors for unsupported operators |

`quint` is a CLI-only formal-model target. It is intentionally outside
`Target.knownIds` and must not be presented as a deployable compiler target.

## Wave 0 closure (verified 2026-07-11, commit `1599f37d`)

All eight P0 (correctness & claim-honesty) tasks are closed: their acceptance
smokes are wired into `just check` and the related product behavior was
re-verified against the live code. P1 work (one compiler/target contract)
remains the active queue — see `agent-goal-prompt.md`.

| Task | Acceptance gate (now in `just check`) | Status |
|---|---|---|
| PF-P0-01 target-first build silently substitutes Counter | `just source-identity` | Closed |
| PF-P0-02 registry vs executable command support disagree | `just registry-command` | Closed |
| PF-P0-03 Solana generic build claims a final artifact it does not emit | `just solana-source-elf` | Closed |
| PF-P0-04 Soroban build resolves the wrong target profile | `just soroban-profile` | Closed |
| PF-P0-05 documentation and translation gates not truthful | `just doc-sync-audit-strict` (+ `scripts/i18n/check-sync.sh`) | Closed |
| PF-P0-06 `near_gas` mislabeled cumulative Wasmtime fuel | `just near-budget-honesty`; offline-host now emits `wasmtimeFuelCumulative`/`wasmtimeFuelDelta` and rejects `near_gas` as a product name | Closed |
| PF-P0-07 `check` can pass without backend validation | `just check-l2-parity` | Closed |
| PF-P0-08 Wasm build succeeds when no Wasm was produced | `just wat2wasm-fail-closed` | Closed |

The finding paragraphs below are the original 2026-07-10 text and remain the
remediation rationale; they are not re-opened.

## Findings and remediation tasks

### P0: correctness and claim honesty

#### PF-P0-01 - Target-first build silently substitutes Counter

**Evidence:** `ProofForge/Cli/TargetFirst.lean` maps every non-`.learn` build
for CosmWasm, Psy, Aleo, and Aptos to a Counter legacy flag without checking
`isLeanSource`. `ProofForge/Cli/SourcegenCommands.lean` then lowers
`IR.Examples.Counter` directly. The probe above confirms successful wrong
outputs.

**Required change:** reject any source argument for these fixture-only routes.
Keep the explicit `emit --target ... --fixture ...` surface. A target may accept
`contract_source` only after its adapter loads that exact `ContractSpec` and
passes it to the lowerer. Every source-derived artifact must record the input
path hash and `spec.name`.

**Acceptance:** add a source-identity CLI smoke covering every registered
target. `ValueVault.lean` must either produce a `ValueVault` artifact or exit
nonzero with `source input is not supported`; no output may contain Counter.

#### PF-P0-02 - Registry and executable command support disagree

**Evidence:** `Target.knownIds` contains `wasm-cloudflare-workers`, while
`buildLegacyFlag` has no matching build case and returns `unknown target`.
Conversely, target-first behavior is implemented as a separate match table,
so registry membership cannot guarantee command support.

**Required change:** define plain `--list-targets` membership as "a registered
target with at least one supported CLI command", not as source-build support,
and state that meaning in CLI help. Keep Cloudflare listed because its fixture
`emit` is implemented, but decouple target resolution from per-command support:
its source `build`/`check` must resolve the profile and return an explicit
unsupported-command/input diagnostic rather than `unknown target`. PF-P1-02
must advertise it as off-chain Research with `inputModes = fixture`,
`commands = emit`, and a TypeScript-source output stage; its JSON output is the
authoritative capability-discovery surface. A real
`contract_source -> TypeScript Worker` adapter is required for later
promotion, not for honest fixture-only registry visibility. Do not classify
the TypeScript output as Wasm.

**Acceptance:** plain-list help defines the at-least-one-command membership
rule; Cloudflare fixture emit succeeds; its source `build`/`check` return stable
unsupported-command/input diagnostics; no listed id falls through to
`unknown target`. Generated command-matrix parity is accepted under PF-P1-02.

#### PF-P0-03 - Solana generic build claims a final artifact it does not emit

**Evidence:** `compileContractSourceSbpf` emits `.s`, manifest, IDL and clients,
but writes `artifactKind = solana-elf` and `sbpfBuild = pending` without an ELF
entry. `compileSolanaSpecElf` already builds a generic `ContractSpec` package
and emits a verified ELF, but is wired only to fixture-oriented commands.

**Required change:** make generic `build --target solana-sbpf-asm` produce ELF
through `compileSolanaSpecElf`. Preserve `--format s` as an explicit
toolchain-free intermediate. If `sbpf` is unavailable, final build fails with
an actionable diagnostic; static product CI requests `--format s` explicitly.
The source route must honor `--format elf`; it currently ignores the format and
always selects assembly.

**Acceptance:** Counter and ValueVault source builds emit ELF with a matching
source module, artifact hash and `sbpfBuild = passed`; `--format s` emits only
assembly and reports an assembly artifact kind.

#### PF-P0-04 - Soroban build resolves the wrong target profile

**Evidence:** `compileContractSourceEmitWat` preserves the requested target id
and selects the Soroban host bridge, but unconditionally calls
`Target.resolveSpec Target.wasmNear`. Sidecars also use the filename
`proof-forge-near.ts` and a NEAR-oriented schema shape.

**Required change:** resolve one `TargetProfile` from the requested target and
use it consistently for capability resolution, preflight, materialization,
bridge selection, metadata and client generation. Add a Soroban-specific
sidecar and keep maturity at Spike until real auth, Stellar contract spec and a
runtime gate exist.

**Acceptance:** a capability present only on NEAR is rejected for Soroban;
Soroban artifacts contain no NEAR target id or NEAR-native wrapper path.

#### PF-P0-05 - Current documentation and translation gates are not truthful

**Evidence:** the mechanical audit reports seven live findings, README omits
Soroban and says Aleo is absent from `--list-targets`, target notes disagree
with registry state, and `docs/target-lowering-interface.md` still says Solana
and NEAR plans do not exist. Four translations were stale at audit start.

**Required change:** close the mechanical findings, correct the target inventory
and pipeline stages, mark old audits as historical snapshots, and keep English
and Chinese indexes synchronized. Add a strict form of the mechanical audit
that exits nonzero when any finding remains. Once PF-P1-02 lands, move target
status tables to generation/checking from that support contract.

**Acceptance:** `just doc-sync-audit-strict` reports zero findings,
`scripts/i18n/check-sync.sh` passes, and all newly added/changed local links
resolve. Generated target-table parity is accepted under PF-P1-02, not this P0
task.

#### PF-P0-06 - `near_gas` is mislabeled cumulative Wasmtime fuel

**Evidence:** `runtime/offline-host/src/main.rs` enables Wasmtime fuel, sets one
initial balance before the full call sequence, and reports
`initial_fuel - remaining_fuel` after every call without resetting it. The
testkit stores that cumulative value under `near_gas`, although it is neither a
per-call delta nor NEAR VM gas.

**Required change:** rename the current observation to
`wasmtimeFuelCumulative`, add a per-call fuel delta if it remains useful, and
remove `near_gas` product claims from offline-host scenarios. A future
`nearGas` budget must come from NEAR VM/sandbox execution and state which costs
are included.

**Acceptance:** Counter budget output distinguishes cumulative and per-call
Wasmtime fuel; no offline-host field is named NEAR gas; a real NEAR gas field is
accepted only from the sandbox/VM harness.

#### PF-P0-07 - `check` can pass without backend validation

**Evidence:** shared preflight implements only L0/L1. `checkContractSource`
performs a real backend check only for NEAR and reports `contractSource =
passed` directly for EVM, Solana and secondary targets. Cloudflare source can
therefore pass check and fail build as unknown; the four substitution targets
also pass without their source identity being validated.

**Required change:** make `check` invoke the same adapter L2 validation and
input-mode rules as `build`, without emitting artifacts. There must be one
support decision, not separate optimistic check and build tables.

**Acceptance:** every negative source-identity/build case fails `check` with the
same category and target-specific explanation.

#### PF-P0-08 - Wasm build succeeds when no Wasm was produced

**Evidence:** `writeWatPackage` converts `wat2wasm` failure or absence into
`none`; callers still return zero and write `artifactKind = wasm`, with
`wat2wasm = skipped` and no Wasm artifact.

**Required change:** a final Wasm build must fail when `wat2wasm` fails or is
unavailable. Add an explicit `--format wat` intermediate mode that may succeed
with WAT only and reports a WAT artifact kind.

**Acceptance:** a fake failing `wat2wasm` makes the default build nonzero and
writes no success metadata; `--format wat` succeeds with truthful metadata.

### P1: one compiler/target contract

#### PF-P1-01 - Target-first CLI is a legacy-flag translation facade

**Evidence:** `ProofForge/Cli/TargetFirst.lean` contains a large tuple match over
target, input kind, fixture, format and token mode. `ProofForge/Cli.lean` still
dispatches a large `EmitMode` inventory. `TargetAdapter` contains only
`profile` and `resolve`, while `ProofForge/Backend/Lowering.lean` is explicitly a
design-only stage enum.

**Required change:** introduce a registry-backed `TargetBackend` driver. Each
adapter owns validate, plan/lower, emit/build/package and artifact validation
operations while retaining its own target-specific plan type. Migrate EVM,
Solana and NEAR first, then fixture/sourcegen targets. Keep legacy aliases for
one documented compatibility release and delete the match facade afterward.

**Acceptance:** adding a target adapter requires no edit to a central target-id
match; target-first commands call the adapter directly; legacy deletion checks
pass after the compatibility window.

#### PF-P1-02 - TargetProfile cannot express actual support

**Evidence:** `TargetProfile` records family, one artifact kind, broad
capabilities, tools and optional host bridge. It cannot express maturity,
source versus fixture input, command support, output stages, exact lowerable
fragment or required validation. Some profiles therefore advertise far more
than their backend accepts.

**Required change:** retain `requiredTools` and add machine-readable `maturity`,
`inputModes`, `commands`, `outputStages`, `supportedFragment` and
`validationLevel`; associate each existing tool requirement with the stage
that needs it. Expose the same data through `--list-targets --json` and use it
to generate documentation tables and CLI diagnostics. Preserve the documented
plain-list meaning from PF-P0-02; JSON is the authoritative support matrix.

**Acceptance:** the registry can distinguish primary source builds,
fixture-only spikes, off-chain sourcegen and CLI-only verification without
prose exceptions; generated target status tables have zero diff from the
machine-readable contract, and the generated command matrix covers every
advertised command/input/output combination.

#### PF-P1-03 - One ArtifactKind conflates intermediate and final outputs

**Evidence:** the registry says Solana ELF while generic build emits assembly,
Psy circuit JSON while common CLI paths emit `.psy`, and Cloudflare Wasm while
its implemented spike emits TypeScript.

**Required change:** introduce an `ArtifactBundle` with source identity,
multiple typed outputs, `primaryOutput`, optional `finalOutput`, toolchain
provenance and validation states `notRun | passed | failed | unavailable`.
Metadata must never call an unexecuted validation `passed`.

**Acceptance:** schema validation covers intermediate-only, final deployable,
missing-tool and failed-toolchain cases for all target families.

#### PF-P1-04 - Preflight reports ready before backend validation

**Evidence:** `Target.Preflight` sets `readyToMaterialize` from L0 portability
and L1 capability resolution and explicitly leaves L2 protocol validation to
backends. Broad registry capabilities can therefore yield a ready report for a
shape the lowerer later rejects.

**Required change:** each adapter exposes its real supported-fragment validator;
`check --target` runs L0, L1 and L2 and reports readiness only after all three.
Backend emit must consume the checked plan rather than repeat a divergent test.

**Acceptance:** representative unsupported shapes fail during `check` with the
same diagnostic category used by `build`, before any artifact is written.

#### PF-P1-05 - The authoring DSL needs a stable diagnostic boundary

**Evidence:** `contract_source` macros directly build `ContractSpec`/IR, support
only zero through four entrypoint parameters, and fall through to macro-level
unsupported-item errors. The base source module also imports Solana Surface
despite documenting chain extensions as opt-in.

**Required change:** keep `contract_source` as the product language, but add
source-location-bearing authoring nodes or builder metadata, generate
variadic-parameter lowering, isolate chain extensions, and version the DSL
surface. Do not create an arbitrary Lean-to-IR compiler.

**Acceptance:** diagnostics identify source item and operation location;
five-plus scalar parameters work where target ABI permits; portable-default
sources do not load chain extension modules.

#### PF-P1-06 - Backend stage discipline and its documentation have diverged

**Evidence:** EVM, Solana, NEAR, Psy, Leo and Worker sourcegen have useful typed
plan/AST boundaries, but the shared lowering contract remains design-only.
CosmWasm is Counter-specific, Move emitters are string renderers, and the Leo
printer prints comments such as `/* nand */` and `/* unsupported unary */`
instead of rejecting unsupported operators. The lowering-interface document
still describes already-landed Solana and NEAR plans as future work.

**Required change:** make `IR -> target Plan -> typed AST -> printer/package`
the promotion contract. Unsupported AST nodes return structured errors. Update
the lowering-interface document to describe current plan modules and remaining
gaps rather than the 2026-07-06 phase-zero snapshot.

**Acceptance:** promotion tests inject one unsupported node per renderer and
assert a nonzero result; plan golden tests and emitted artifacts are derived
from the same plan.

### P2: primary-chain product closure

#### PF-P2-01 - Product build breadth exceeds runtime parity evidence

**Evidence:** `Examples/Product` contains 20 sources, while
`Tests/Product/Matrix.lean` imports 18 and omits `ERC4626Vault` and
`ExternalVault`; their specialized recipes are not part of `just product`.
The testkit contains ten scenario manifests, but only Counter and ValueVault
use product sources across all three primary targets; RoleGatedToken and
StakingVault use product sources on EVM only. The product matrix proves broad
static lowering for the imported set, not equivalent runtime behavior for
every capability family. Counter and ValueVault do have real three-target CI
execution when the required tools are installed. Locally, however, missing
target tools become skips and trace equivalence can still report success with
zero or one executed target.

**Required change:** introduce a checked product catalog declaring every
Product file's authoring kind (`contract_source`, `TokenSpec`, or facade),
claimed targets, expected output stage and required gates; discovery fails for
an uncatalogued file. Replace fixture-name dispatch in the harnesses with
artifact-driven execution, validate scenario capabilities against artifact
metadata, and add per-step caller, native value, context, accounts and peer
inputs. Run CLI source builds for `contract_source`, plan/standard conformance
for `TokenSpec`, and body/runtime tests for facades. Add representative triad
scenarios by capability family: scalar state, auth/policy, map/array,
token/accounting, events/errors and remote calls. Split the gate into a fast
static product catalog and a required runtime subset. Add a strict
`--deny-skip`/required-target policy for CI; adaptive local mode reports
`partial`, never parity success.

**Acceptance:** every capability advertised as portable by the primary triad
has at least one shared semantic scenario, and claimed targets cannot silently
skip it.

#### PF-P2-02 - Primary backends still have ecosystem-specific gaps

**Status (2026-07):** **EVM slice closed** (PF-P2-02 @7c4def9c / follow-ons).
`docs/sdk-ecosystem-gaps-2026-07.md` marks ERC-721 `onERC721Received`, ERC-1155
receiver + size-2 batch, and custom-error **4-byte selector** surface as
Covered (limited where noted). Remaining open work is P1 depth (arbitrary-length
ERC-1155 batch / `onERC1155BatchReceived`, custom-error *argument* ABI), plus
Solana/NEAR items below — not a reopening of the EVM receiver/selector MVP.

**Historical evidence (pre-close):** gap doc and target notes recorded missing
EVM receiver/batch/error surfaces; PF-P0-03 showed generic Solana source builds
without ELF; NEAR deploy manifest reported local offline-host without sandbox.

**Required change (remaining):** finish documented gaps without treating every
chain-native feature as portable:

- EVM (done for MVP): Solidity-compatible custom-error **selector** surface
  (`errors-ir-smoke` `test_revertCustomError_selector`), ERC721
  `onERC721Received` Foundry accept/reject, ERC1155 `onERC1155Received` +
  size-2 `safeBatchTransferFrom2` Foundry cases. Open: arg ABI + full batch.
- Solana: generic source-to-ELF, deployment-level runtime coverage and remaining
  ABI/length limits (source-ELF path closed separately under PF-P0-03 /
  `just solana-source-elf` where applicable);
- NEAR: generalize async Promise/callback beyond specialized flows, complete
  storage accounting, and keep sandbox peer gates (`just near-sandbox-peer`).

Unsupported chain-native behavior must be an explicit target extension or a
diagnostic, never an invented portable semantic.

**Acceptance:** EVM adds positive and rejection Foundry/Anvil cases for
Solidity-compatible custom-error ABI/client behavior, ERC721 receiver callbacks
and ERC1155 batch/callback behavior — **met** via `just evm-foundry` /
`scripts/evm/foundry-smoke.sh` (`testERC721*`, `testERC1155*`) and
`scripts/evm/errors-ir-smoke.sh` (`test_revertCustomError_selector`); a
source-built Solana ELF runs through the strict testkit gate with boundary ABI
fixtures; and NEAR executes a general caller/callee Promise callback plus
storage-accounting scenario in sandbox. Each capability remains absent from
the portable profile until its corresponding gate passes.

#### PF-P2-03 - Crosscall tests do not prove real peer equivalence

**Evidence:** executable IR and Quint deliberately use a deterministic sum
stub. Materializers emit CALL, CPI, Promise, Soroban invoke or a CosmWasm stub,
but current portable smokes do not establish rich return equivalence against a
real peer contract.

**Required change:** add multi-contract runtime scenarios with a peer oracle and
portable scalar return decoding. Keep aggregate/dynamic returns and CosmWasm
submessages outside the product promise until their cross-host ABI is defined
and tested.

**Acceptance:** each primary target executes the same caller/callee scenario
and matches state, return and failure observations; stub-only tests remain
clearly labeled model tests.

### P3: target promotion, formal scope and platform hardening

#### PF-P3-01 - Formal compiler scope is narrower than codegen scope

**Evidence:** the EVM, Solana and Wasm target-semantics records currently set
both `fragmentAccepts` and `lowerableAccepts` to `isCounterModule`. Additional
ValueVault and storage trace obligations are valuable, but they do not turn the
generic lowering-total theorem into a proof for every supported contract.

The primary target-semantics records also retain the default `irStateRel = True`
and `initialMachineState = none`. The stronger Solana and Wasm Counter theorems
simulate hand-written abstract core steps; they do not yet prove that the
machine produced by `lowerModule m` implements those steps.

**Required change:** define separate real lowerable and proved predicates per
backend. Before merely adding more IR constructors, connect lowered
plan/AST/machine semantics to the existing simulation relations and provide
nontrivial initial states. Then widen the proved fragment in product-driven
slices: scalar/auth, map/array, error/event and remote calls after peer semantics
exist. Replace string-pair `lean_invariant` metadata with typed/elaborated
invariant registration, discover its scenarios in gates automatically, prove
preservation across every supported entrypoint, and only then lift it through
backend refinement. Current invariant evidence remains explicitly
scenario-bound. Keep solc, sbpf, wat2wasm and chain runtimes as explicit
trusted/differential boundaries.

The generic Track 1.4 theorem schemas currently accept the desired lowering or
subset fact as an argument, and backend instances discharge only canonical
Counter. Treat them as scaffolding/Counter witnesses, not general compiler
correctness, until the structural bridge above is complete.

**Acceptance:** prove `forall m, proved m -> lowerable m` and
`forall m, lowerable m -> lowering m succeeds` over structural predicates, and
provide at least one checked witness satisfying `lowerable m && !proved m`.
The result must not be limited to the canonical Counter constant.

#### PF-P3-02 - Secondary targets lack one promotion definition

Promote one target at a time in this order: Soroban, CosmWasm, Aptos, Sui,
Cloudflare Workers, Psy, Aleo. A promotion requires all of:

1. the declared input is actually loaded;
2. an exact supported-fragment validator exists;
3. lowering follows Plan -> typed AST -> printer/package;
4. final output is checked by the target toolchain;
5. at least one runtime semantic scenario passes; and
6. registry, CLI, README, target note and Chinese docs agree.

Until all six pass, the target remains at its current Spike/MVP/Research scope
and must reject every input or output stage it does not actually implement.
An existing source path, such as Soroban's host-adapter path, is not by itself a
promotion.

#### PF-P3-03 - Hosted compilation and artifact reproducibility are not ready

**Evidence:** `ContractLoader` elaborates and evaluates a local Lean constant
with initializers enabled. This is appropriate for trusted local source, but it
is not an isolation boundary for a future cloud compiler. Some external
toolchain versions and dependency revisions are also not pinned in artifacts.

**Required change:** before hosted compilation, execute source loading in an
isolated worker with CPU/memory/time limits. Pin target toolchains, record
versions and hashes, add deterministic rebuild checks and retain an auditable
artifact provenance chain.

**Acceptance:** hostile-source tests cannot escape the worker limits, and a
clean rebuild either reproduces artifact hashes or explains every declared
nondeterministic input.

## Delivery waves and dependencies

| Wave | Tasks | Exit condition |
|---|---|---|
| 0 - Stop false success | PF-P0-01 through PF-P0-08 | no wrong-input/check/build success; registry/CLI/artifact/docs/budget labels agree |
| 1 - One target driver | PF-P1-01 through PF-P1-04 | registry-backed command matrix and truthful artifact bundle drive the primary triad |
| 2 - Author and backend boundary | PF-P1-05, PF-P1-06 | stable DSL diagnostics and plan/AST promotion contract |
| 3 - Deployable triad | PF-P2-01 through PF-P2-03 | shared runtime scenarios and final artifacts for EVM, Solana and NEAR |
| 4 - Promote deliberately | PF-P3-02 | secondary targets advance one at a time through the six promotion gates |
| 5 - Proof and platform | PF-P3-01, PF-P3-03 | structural proof fragments, reproducible artifacts and hosted isolation |

Wave 1 depends on Wave 0 because a generic driver must not preserve silent
substitution. Wave 3 depends on the artifact/support contracts from Wave 1.
Secondary target promotion does not block primary product closure.

## Global definition of done

Every remediation PR runs the narrow tests for its boundary plus:

```sh
just product
just check
just doc-sync-audit-strict  # available after PF-P0-05 lands
scripts/i18n/check-sync.sh
git diff --check
```

Live gates requiring Surfpool, Sui, Leo, Dargo, Wrangler or chain CLIs remain
conditional until those tools are installed, but a target cannot be promoted
past the maturity level whose required gate was skipped.

No target maturity label may be raised until its source identity, final
artifact, runtime scenario, failure diagnostics and documentation all pass in
the same revision.
