# Formal Verification Roadmap

Status: **Draft (post-consolidation, 2026-07)**

ProofForge is Lean-first, but most of today's assurance comes from tests and
golden files rather than theorems. This page records where formal verification
can be added, what already exists after the 2026-07 branch consolidation, and
which proofs pay for themselves first. Tasks are tracked in
[implementation-backlog.md](implementation-backlog.md) (Workstream 25).

## What already exists

> **Coverage boundary — read before citing the rows below.** The in-Lean
> executable target traces (Solana sBPF and Wasm/NEAR) are `native_decide`
> checks over a **fixed set of fixtures** — Counter, ValueVault, and a few
> storage probes — at **single inputs**, on a scalar plus focused map/array
> subset. They are **pointwise, not universal**: they prove nothing about other
> contracts or other inputs, and they do not cover CPI/PDA/syscalls/Promise/async
> (those stay in external differential gates). A green executable-trace theorem
> means "these fixtures/probes match the IR at these inputs", **not** "the
> target semantics is covered". Universal coverage of a defined *supported fragment* is
> the C-proof track (see the tier table), not these fixtures.

The NEAR work contributed the first three formal anchors, now on `main`:

| Anchor | Module | What it gives us |
|---|---|---|
| Executable IR semantics (scalar + first aggregate/storage/control-flow/event slice) | `ProofForge/IR/Semantics.lean` | A small executable trace interpreter for scalar values plus fixed arrays, structs, storage arrays, storage struct fields, storage paths, aggregate ABI params/returns, `ifElse`, `boundedFor`, and observable event-log items; used by the NEAR trace obligations and the first FV-2 aggregate/storage/control-flow/event checks. **Three-valued `ExecResult` (ok/reverted/error)** now makes contract-level reverts a first-class outcome distinct from interpreter failures, unblocking FV-2/FV-5 revert-aware refinement. **The three backend `Refinement` layers (EVM/Solana/NEAR) are now revert-aware**: a reverting entrypoint produces an `ObservableReturn.reverted` step and does not advance the trace state (chain rollback), so `assert`/`revert`/`revertWithError` are observable, assertable trace outcomes; a `native_decide` rollback invariant (`revert_rollback_ir_trace_ok`) pins this in the Solana layer |
| User contract invariants over IR traces | `ProofForge/Contract/Examples/ValueVaultInvariant.lean`, `Tests/NearWasmFormal.lean` | The first FV-8 worked example: the chain-neutral ValueVault `contract_source` module is executed through the shared 11-step IR scenario, then decide-checked theorems pin the observable returns, the accounting invariant `balance + released + fees = externally supplied value`, final storage fields, and `get_net_value = balance - fees` |
| Ownership rules | `ProofForge/IR/Ownership.lean`, `Tests/IROwnership.lean` | Checker for `release`/owned-local discipline (no use-after-release, branch consistency), currently validated by tests |
| Capability routing soundness (FV-1) | `ProofForge/Target/Formal.lean` (structural, universal), `ProofForge/Target/FormalBoundary.lean`, `Tests/TargetFormal.lean` | `requireCapabilityPlan_sound` (structural, universal in `Formal.lean`) plus full-boundary `resolveSpec_sound_counter_*` / `resolveSpec_sound_value_vault_*` `native_decide` checks across EVM, Solana, and NEAR (in `FormalBoundary.lean`, split out of `Formal.lean` to avoid an import cycle with the example contracts). The platform's "reject rather than silently change semantics" promise is machine-checked at the `resolveSpec` boundary |
| Counter proof-fragment path | `ProofForge/IR/CounterSemantics.lean`, `ProofForge/Backend/Refinement/CounterUniversal.lean`, `ProofForge/Backend/Refinement/Core.lean`, `Tests/IRCounterSemantics.lean`, `Tests/CounterUniversalRefinement.lean`, `Tests/SupportedFragment.lean` | Track 1.1 totalizes the Counter IR fragment with fuel-indexed `def`s and per-entrypoint all-state lemmas. The first Counter C-proof-shaped layer proves per-entrypoint simulation plus an inductive theorem over every Counter call list from related states, and over every init-prefixed call list from arbitrary IR states, against a deliberately tiny `counter-model` target semantics. `traceSimulation_lift` captures the reusable S6/W6 proof pattern: per-call IR/target simulation implies whole-trace observable equality by induction over the call list. `executableStepSimulationOk_sound` and `executableSimulationTraceOk_sound` are the pointwise bridges for real target runners: `native_decide` paired-step checks yield Lean evidence that one entrypoint, or a concrete call list, emitted the same observable(s) and ended in related states. `TargetSemantics.supportedFragment` records the proved fragment boundary and rejects checked/renamed Counter modules outside that boundary |
| Backend trace obligations | `ProofForge/Backend/WasmHost/Refinement.lean`, `ProofForge/Backend/Evm/Refinement.lean`, `ProofForge/Backend/Evm/YulSemantics.lean`, `ProofForge/Backend/Solana/Refinement.lean`, `Tests/NearWasmFormal.lean`, `Tests/Backend/Solana/SolanaRefinement.lean` | `TraceObligation` with `decide`-checked theorems: the Counter, ValueVault, EvmExpressionProbe, EvmMapProbe, EvmTypedStorageProbe, EvmStorageStructProbe, EvmAbiAggregateProbe, ConditionalProbe, EvmLoopProbe, and EventProbe IR traces match expected observable values where IR semantics exists; EmitWat exports cover the NEAR trace entrypoints; the NEAR Counter and ValueVault artifact-surface obligations pin emitted Wasm AST host-boundary calls; the NEAR offline-host execution-surface obligations pin Borsh input bytes plus deterministic host return fragments; the NEAR in-Lean executable trace covers Counter + ValueVault scalar/event plus fixed-array/u64-map storage slices, and the Counter `initialize`/`get`/`increment` step-simulation anchors plus `counter_wasm_trace_simulation_sound_checked` turn the paired-step checks into Lean evidence of matching IR/Wasm entrypoint observations and final storage relation; the EVM Yul surface contains selector-dispatched functions for the same traces and the focused emitted Yul subset executes them to the same observable return/log words; **the Solana sBPF backend now has Counter + ValueVault IR traces, a Counter artifact-surface anchor, executable-trace Counter + ValueVault scalar/event plus fixed-array/u64-map storage slices, Counter `initialize`/`get`/`increment` step-simulation anchors, and `counter_sbpf_trace_simulation_sound_checked` for the Counter paired-step IR/sBPF run** over the lowered structured sBPF AST |
| Solana sBPF ↔ solanalib bridge (Scheme 1 + 2A/B + host) | `ProofForge/Backend/Solana/BpfEncode.lean`, `LabeledSbpf.lean` (default), `SolanaRefinement/*` (opt-in), `docs/solana-sbpf-solanalib-bridge.md`, `docs/portable-ir-semantics-anchor.md` | **Always from Portable IR. Lane complete for Counter+ValueVault pointwise stack:** encode/labeled/lift/verify; core-tail + full hosts; IR paired simulation; core-tail≡abstract composition; ValueVault IR lockstep; `TargetSemantics` id `solana-sbpf-solanalib-host`. Universal all-input host refinement remains research. Gates: `just solana-bpf-encode-smoke`, `just solana-solanalib-adapter` |
| EVM Yul-subset ↔ IR host bridge | `ProofForge/Backend/Evm/YulHostRefinement.lean`, `docs/evm-yul-host-bridge.md` | **Always from Portable IR.** Mathlib-free IR↔`YulSemantics` paired simulation on `ObservableReturn` for Counter (with the canonical slot-0 low-order U64 storage relation) + ValueVault default scenario; soundness wrappers; existing `evmYulTraceOk` re-checked. Powdr bytecode / solc hop stay opt-in. Gate: `just evm-yul-host-refinement-smoke` |

These are the right shape: small executable definitions plus decidable
theorems, checked in CI without external tools.

## Verification tiers (read this before claiming "verified")

ProofForge's assurance story has **three distinct tiers**. They are not
interchangeable, and conflating them in external communication (papers,
README, talks) is the main way this project can over-promise. Use this table
to attribute a claim to the correct tier.

| Tier | What it is | What it proves | What it does **not** prove | Where it lives |
|------|-----------|----------------|----------------------------|----------------|
| **A — Design validation** | Quint state-machine model + Apalache model checking + ITF trace replay against `IR.Semantics` | For bounded nondet parameters and a finite caller set, the **contract's stated invariants** hold under the Quint abstraction, and the Quint abstraction agrees with the IR scalar interpreter on the replayed traces | It does **not** prove the Quint lowering equals the IR (the IR→Quint lowering is an unproven abstraction), does not cover the full IR node set (whileLoop is statically unrolled, crosscall is a stub), and has **no relationship to any chain-native artifact** | `ProofForge/Backend/Quint/*`, `Tests/Quint/*`, `just quint-*` |
| **C-diff — Differential testing** | IR reference trace replayed against the EVM Yul-subset interpreter (including mathlib-free IR↔Yul host paired simulation), external `solc --strict-assembly` verification of Counter Yul→bytecode against the powdr witness, the Counter + ValueVault scalar/event slices of the in-Lean Wasm/NEAR and Solana sBPF interpreters, the focused Wasm and Solana fixed-array/u64-map storage slices, the NEAR offline host, and capability routing soundness at the `resolveSpec` boundary | For the **fixed Counter/ValueVault/probe scenarios**, the observable return values and event logs produced by the target artifact match those produced by the IR reference semantics; FV-1 confirms that any spec that resolves to `.ok plan` on a profile yields a plan whose capabilities are all supported | It does **not** prove anything for inputs outside the fixed scenarios (`native_decide` is pointwise, not universal); EVM coverage stops at the Yul subset, while the unproved `solc` hop is only externally checked for Counter; the Wasm and Solana executable traces cover Counter + ValueVault scalar/event plus focused fixed-array/u64-map storage probes, while CPI/PDA, broad host/syscall semantics, hash maps, nested paths, dynamic arrays, and aggregate array elements stay outside these in-Lean target interpreters | `ProofForge/Backend/Evm/Refinement.lean`, `ProofForge/Backend/Evm/YulHostRefinement.lean`, `scripts/evm/yul-compiler-counter-smoke.sh`, `ProofForge/Backend/WasmHost/Refinement.lean`, `ProofForge/Backend/Solana/Refinement.lean`, `ProofForge/Target/Formal.lean` |
| **C-proof — Refinement theorems** | Universally-quantified Lean theorems relating IR semantics to target semantics for all inputs in a declared supported fragment | Today: structural FV-1 routing theorems are universal; `runTraceListGen_sound` is universal over arbitrary machine states and is smoke-instantiated for IR plus the EVM/Yul, Solana sBPF, and Wasm/NEAR target runners; `traceSimulation_lift` is the shared induction lemma that lifts per-entrypoint IR/target simulation into whole-trace observable equality; the Counter proof-fragment path instantiates it against a tiny `counter-model` target semantics, gated by `TargetSemantics.supportedFragment`; the real Solana/Wasm target runners now have Counter entrypoint-level paired-step soundness anchors (`counter_sbpf_*_step_simulation_sound_checked`, `counter_wasm_*_step_simulation_sound_checked`) plus whole fixed-trace soundness theorems for the fixed Counter trace; the EVM bytecode lane has an opt-in powdr-backed target and a canonical low-order Counter fixed-trace witness checked with `native_decide`. Its universal shape, `evmCompiledPowdr_fragment_refines_all`, remains conditional on `CounterCompiledPowdrEntrypointObligations`; those current-runtime obligations are not yet discharged | It does **not** remove powdr `stepF` or Lean's native evaluator from the EVM TCB, and it does not prove ProofForge's Yul→bytecode `solc` hop. The Solana/Wasm paired-step results remain pointwise over documented states/prefixes, not all-input/full-fragment refinement. Deep EVM bytecode reduction is deferred; the former prepared-frame opcode proof is retained only as `LegacyHighPacked` historical evidence | `ProofForge/IR/StepSemantics.lean`, `ProofForge/IR/CounterSemantics.lean`, `ProofForge/Backend/Refinement/Core.lean`, `ProofForge/Backend/Refinement/CounterUniversal.lean`, `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean`, `EvmRefinement/PowdrAdapter.lean`, `EvmRefinement/CounterRefinement.lean`, `ProofForge/Target/Formal.lean` |

**How to talk about this externally:** "ProofForge validates contract designs
with Quint (Tier A), gates every backend lowering with differential trace
checks against the IR reference (Tier C-diff), and has started the C-proof
track with a Counter-only supported fragment against a tiny proof target model.
Full chain-native IR↔target refinement remains in progress." Avoid
"ProofForge is formally verified" without naming the tier; today that statement
is only defensible for the specific tier and fragment being cited.

### Crosscall honesty (U2)

IR executable semantics and Quint treat `crosscall.*` as a **deterministic sum
stub** (not a peer VM). That is intentional and documented in
[portable-ir.md](portable-ir.md) § Crosscall semantics honesty.

- **Tier A / IR self-replay** may use the stub for determinism.
- **Product remote correctness** is validated only by **target materialize**
  (CALL / CPI / Promise / …) and multi-target smokes — never by equating IR
  stub returns to chain-native returns.
- **C-proof fragment** must not silently include stub crosscall as “real peer
  semantics” until an oracle path exists (roadmap U2.4 / U5.3).

**F1.4 boundary lock (separate gates — do not merge):**

| Gate | What it proves | What it does **not** prove |
|------|----------------|----------------------------|
| `just ir-crosscall-stub` | IR executable path is a deterministic sum stub | Peer CALL / CPI / Promise semantics |
| `just crosscall-materialize` | Portable `crosscall.invoke` materializes to EVM CALL · Solana CPI · NEAR Promise (plus related portable auth/error/remote smokes) | That the IR stub return equals any chain peer return |

Any new remote work must keep these two surfaces separate: IR tests stay on the
stub; product remote correctness stays on materialize + multi-target smokes.

## Trusted Computing Base (Track 1.6 audit)

The `native_decide` vs `decide` distinction is the main axis of the Lean FV
TCB. Both discharge a `Bool` proposition, but they trust different evaluators:

| Evaluator | Trust | Where it works | Where it fails |
|-----------|-------|-----------------|----------------|
| `decide` | Lean kernel only (no compiler). The `Decidable` instance must reduce in the kernel. | Small, structurally-recursive `def`s; `DecidableEq` instances on datatypes; theorems whose RHS is a closed kernel-reducible computation. | `partial def`s (not kernel-reducible); fuel-indexed `def`s with a fuel counter large enough to make kernel reduction infeasible (e.g. `Ownership.defaultFuel = 256`); functions that call external/compiled code. |
| `native_decide` | Lean's native (compiled) evaluator. Faster and works on more functions, but trusts the compiler. | All of the above plus `partial def`s (when the compiled code terminates) and deep fuel-indexed computations. | Does not exist when the kernel must check (e.g. inside a proof that cannot rely on compiled evaluation); cannot be used in environments where native evaluation is disabled. |

**Track 1.6 audit conclusion (2026-07-08; F1.5 refresh 2026-07-10):**

1. **EVM bytecode lane** trusts **powdr `stepF`** + `native_decide` (the pinned
   `evm-semantics` tree and Lean's native evaluator are in the EVM TCB). The
   Yul→bytecode `solc` hop is **not** proven, but it is now externally checked
   for Counter: `just evm-yul-compiler-counter-smoke` compiles the emitted Yul
   with `solc --strict-assembly` and verifies the runtime code matches the
   powdr witness embedded in `EvmRefinement`. The Counter IR↔powdr delivery
   boundary is pinned by `counterCompiledPowdr_ir_and_target_trace_match`
   (same `TraceObligation` passes IR reference trace and powdr bytecode trace)
   plus the CLI runtime-bytecode witness check. Gates:
   `just evm-powdr-counter-refinement-smoke`, `just evm-powdr-counter-runtime`,
   `just evm-yul-compiler-counter-smoke`.
2. **EVM Yul-subset host lane (default, mathlib-free)** trusts the in-tree
   `YulSemantics` interpreter + `native_decide` paired-step checks in
   `YulHostRefinement` (Counter storage rel + ValueVault multi-field storage rel
   + return lockstep). This
   is **not** a powdr TCB expansion: it does not import powdr/mathlib and does
   not claim solc or bytecode equivalence. Gate:
   `just evm-yul-host-refinement-smoke`.
3. **Self-built target traces** (Solana sBPF, Wasm/NEAR in-Lean interpreters)
   trust the **in-Lean interpreter** (reviewed, not compiler-trusted for the
   structural lemmas) + the **external differential gate** (Mollusk/Surfpool for
   Solana, NEAR sandbox for Wasm) for CPI/PDA/syscall/Promise coverage that
   stays outside the in-Lean slice.
4. **`decide`-downgradeable candidates (Track 1.6):** theorems whose RHS is a
   closed computation over structurally-recursive, kernel-reducible `def`s.
   The `Ownership` checker was **total-ized in Track 1.5** (fuel-indexed,
   kernel-reducible in principle), but its `defaultFuel = 256` makes kernel
   reduction of `checkEntrypointOk` too deep to discharge via `decide` in
   practice — so the Track 1.5 soundness theorems stay on `native_decide`.
   Lowering `defaultFuel` to a kernel-reducible depth, or restructuring the
   checker to recurse on expression depth rather than a flat fuel counter, is
   future work that would let those theorems move to `decide`.
5. **Structural (universal) theorems** that use `induction`/structural lemmas
   (e.g. `runTraceListGen_sound`, `traceSimulation_lift`,
   `requireCapabilityPlan_sound`, `invariants_hold_after_scenario`,
   `valueVault_step_simulates`) are **kernel-checked** (no `native_decide` on
   the proof itself; any `native_decide` is only on the concrete premise, not
   the bridge). ValueVault **fuel-coverage** witnesses
   (`valueVault_all_entrypoints_in_fuel_coverage`) remain `native_decide`.

The practical TCB statement for external communication:

> "ProofForge's structural refinement theorems are kernel-checked. Pointwise
> trace-matching theorems over fixed fixtures are `native_decide`-checked
> (trusting Lean's native evaluator). EVM bytecode reduction trusts the pinned
> powdr `stepF`. The default EVM Yul host lane trusts in-tree `YulSemantics`
> only (no powdr). Self-built target traces (Solana sBPF, Wasm/NEAR) trust the
> in-Lean interpreter for the covered slice and an external differential gate
> for the rest."

## Verification targets, in priority order

### FV-1: Capability routing soundness (small, high value)

`ProofForge.Target.requireCapabilities` and `resolveSpec` are the platform's
core promise: *a contract that routes to a target only uses capabilities that
target supports*. Today this is a runtime check exercised by tests.

Prove, for the checked boundary:

- **Soundness:** if `resolveSpec profile spec = .ok plan`, then every
  capability in `plan.calls` is in `profile.capabilities`.
- **Completeness of rejection:** if the spec references a capability outside
  the profile, `resolveSpec` returns `.error`.
- **Target-extension isolation:** if any call carries `solana.*` metadata and
  the profile family is not `.solana`, resolution fails (D-027 enforced by
  theorem, not convention).

These are structural inductions over arrays; no semantics needed. They turn
the "reject rather than silently change semantics" principle (RFC 0001) into
a machine-checked invariant.

### FV-2: IR semantics coverage and metatheory

Extend `IR/Semantics.lean` from the scalar subset toward the checked IR
surface. The first aggregate/storage slices are now in place for local fixed
arrays, struct values, aggregate ABI params/returns, storage arrays, storage
struct fields, storage paths (including nested map-key paths), and
state-threaded effectful expressions for storage map insert/set lifecycles,
`ifElse`, `boundedFor`, and observable event-log trace items, through
`decide`-checked traces in `Tests/NearWasmFormal.lean`. The first FV-2
metatheory anchors also state deterministic interpreter results and the
decreasing measure used by `boundedFor`. The next FV-2 work is to state:

- **Progress/preservation for the typed subset:** statements that pass the
  existing shape/type validation do not get stuck and preserve binding types.
- **Bounded termination completion:** the current decreasing-measure anchor
  should grow into a theorem over the release-aware, validated statement
  subset once FV-3 introduces that semantics.

This is the foundation everything else refines against. Keep it executable
(`decide`-friendly) so CI checks stay cheap.

### FV-3: Ownership/release soundness (connect FV-2 to `IR/Ownership.lean`)

The ownership checker currently passes 6 behavioral test cases. Once FV-2
gives release-aware semantics, prove: programs accepted by the ownership
checker never evaluate a released local and never release twice. This is the
formal justification for lowering `release` to allocator frees in EmitWat
while EVM/Psy reject it and TS ignores it — three different lowerings of one
IR construct are only safe if the IR-level discipline is proven.

**Status (2026-07):** the production checker (`IR/Ownership.lean`) is a
`partial def` mutual group (`checkExpr`/`checkEffect`/`checkStatement`/`
checkStatements`) — like every `mutual` block in this codebase. `partial`
forfeits Lean's induction principle, so universally-quantified soundness
requires either (a) re-implementing the checker as well-founded `def`s with
an explicit termination measure, or (b) a parallel specification-predicate
layer (`exprUsesReleased`/`effectUsesReleased`) that terminates on `sizeOf`
and is matched to the production checker pointwise. Option (b) was prototyped;
the load-bearing step is a `mutual` termination proof for the
`Expr ↔ Effect` detector pair, which needs careful `termination_by` handling
and is the next concrete step. The detectors, once total, give an induction
principle any future statement-level checker inherits.

### FV-4: Backend refinement obligations, one scenario at a time

Replicate the `TraceObligation` pattern per backend against the shared
scenario (Counter first, ValueVault second):

| Backend | Obligation shape | Feasibility |
|---|---|---|
| `wasm-near` / EmitWat | Exists (exports + IR trace) and now has Counter + ValueVault artifact-surface obligations over the emitted Wasm AST: required NEAR host imports, entrypoint/helper call sequences, memory export, storage-key data, and ValueVault event data are checked before WAT printing. It also has Counter + ValueVault offline-host execution-surface obligations: the same IR trace boundary derives the Borsh/little-endian input bytes and deterministic host return fragments that `runtime/offline-host` must print when executing the generated WAT. The Counter + ValueVault scalar/event plus focused fixed-array/u64-map storage subset now has an **in-Lean executable Wasm trace** over `EmitWat.lowerModule` output, including helper calls, byte-addressed linear memory, mutable event-buffer globals, NEAR register/storage/value-return/`block_index`/`log_utf8` host functions, storage array helpers, map storage helpers, and a scalar storage relation `R` against `Layout.lean` for the Counter slice. Extend this toward broader maps, arrays, and richer Wasm/offline-host semantics | High for the implemented interpreter slice; offline host already executes the broader artifact deterministically |
| `evm` (IR → Yul plan) | Counter, ValueVault, and EvmExpressionProbe obligations exist for IR trace + selector-dispatched Yul surface + executable Yul-subset trace (`calldataload`, `calldatasize`, `sstore`, `sload`, scalar arithmetic, `exp`, bitwise/shift operators, comparisons, casts, assertions, `number`, deterministic memory-sensitive `keccak256` surrogate, `log0`-`log4`, `mstore`, `return`, focused `switch`, and bounded `for`). The covered FV-2 aggregate/storage, map lifecycle, control-flow, and event-log traces are now wired into the EVM obligations for `EvmMapProbe`, `EvmTypedStorageProbe`, `EvmStorageStructProbe`, `EvmAbiAggregateProbe`, `ConditionalProbe`, `EvmLoopProbe`, and `EventProbe`, so maps, presence slots, typed storage arrays, storage structs, aggregate ABI params/returns, if/else branches, bounded loops, early returns, ValueVault business events, signature-derived `topic0`, scalar indexed events, aggregate event data, and hashed aggregate indexed topics are checked on both the IR trace and executable emitted-Yul sides. | Medium — the focused Yul-subset interpreter is in Lean; expanding coverage keeps `solc` out of the trusted path but not out of the build |
| `psy-dpn` | Compare `dargo execute` result vectors against IR trace outputs (differential gate, not a theorem) | Already close: smoke scripts assert `result_vm` values today |
| `solana-sbpf-asm` | **Executable-trace Counter + ValueVault scalar/event + fixed-array/u64-map storage subset exists**: the Counter, ValueVault, ArrayProbe storage lifecycle, and EvmMapProbe set/read IR observable traces, rendered Counter assembly entrypoint labels, lowered structured `AstNode` interpreter traces, Counter scalar account-data relation `R`, and revert-rollback invariant are all `native_decide`-checked. The in-Lean sBPF interpreter covers dispatch, account-validation path, direct account-data loads/stores, fixed array index scaling/bounds checks, u64 map linear scan/set/read, instruction-data u64 params, ALU/load/store/jump/exit, `sol_set_return_data`, `sol_get_clock_sysvar`, and `sol_log_64_`. **Scheme 1 solanalib bridge (landed skeleton):** mathlib-free `BpfEncode.toBpfBin` + labeled lift + Counter core-tail host bridge under `solanalib.SBPF` (see [solana-sbpf-solanalib-bridge.md](solana-sbpf-solanalib-bridge.md)). Full sBPF semantics (CPI/PDA/broad syscalls/hash maps/nested paths/dynamic arrays/account model) and full IR↔`bpfInterp` simulation stay open; external differential gate remains Mollusk/Surfpool | Medium for the implemented interpreter slice (reuses existing `Asm.lean` structured AST); research track for fuller account/syscall coverage |
| `wasm-cloudflare-workers` | Differential HTTP-level gate only (off-chain host, D-033) | Not a proof target |

Rule of thumb: a backend earns "Experimental → Supported" only with (a) the
scenario differential gate and (b) at least the export/trace obligation
theorem, mirroring what `wasm-near` already has.

### FV-5: Checked arithmetic semantics per target

The SDK's checked operators (`+!`, `-!`, `*!`, `/!`) must mean the same thing
on a 256-bit EVM word, a 64-bit Wasm integer, and a field element in Psy.
State the intended semantics once in FV-2's value domain (trap on overflow /
division-by-zero as trace outcomes), then make each backend's lowering
obligation include the overflow branch. The EVM and Psy diagnostic suites
already test rejection paths; the theorems pin down accepted-path behavior.

### FV-6: Lowering equivalence for the two authoring surfaces

`contract_source` (Lean SDK) and the legacy `.learn` parser both lower to
`ContractSpec`. Today equivalence is enforced by paired fixtures. For the
covered subset, prove that parsing a `.learn` fixture and elaborating the
matching `contract_source` block produce equal `ContractSpec` values
(decidable equality already derives). This keeps the "Learn is frozen
compatibility, not a second language" policy honest, and makes drift a build
failure instead of a review judgment.

### FV-7: Token SDK plan invariants

`TokenSpec.planForTarget` invariants worth stating as theorems:

- Feature routing is total: every accepted feature set yields a plan or a
  planner diagnostic (no silent drops).
- Documented incompatibilities (e.g. `transfer_fee` + `non_transferable`)
  always produce the diagnostic.
- Solana plans reference only program ids and accounts declared in the plan
  itself (well-formedness of the emitted instruction sequence).

### FV-8: User-level contract invariants (product direction)

The long-term differentiator: let contract authors state invariants next to
`contract_source` (e.g. `balance = deposits - releases + fees` for
ValueVault) and prove them against the FV-2 semantics before codegen. This
needs no backend work — it is pure Lean over the IR semantics — and is the
first proof surface users see. The first worked example is now
`ProofForge.Contract.Examples.ValueVaultInvariant`: it executes ValueVault's
shared scenario in the FV-2 interpreter and pins the return trace, final
storage shape, accounting invariant, and net-value invariant.

Next, turn that concrete module into an authoring pattern:

- make invariant declarations live near `contract_source`;
- separate reusable invariant predicates from scenario-specific inputs;
- connect proved IR invariants to FV-4 backend obligations so generated
  artifacts cannot drift from the proved scenario without a theorem/gate
  failure.

## Fragment inventory (F1.1)

This table lists the IR constructs used by each Product matrix source and
whether they are inside the **supported fragment** (C-proof), the **covered
C-diff traces**, or **outside both**. It is the SOT for F1.2 (grow C-diff with
N1/E1) and F1.3 (push simulation lemmas).

| Product source | Key IR constructs | C-proof fragment | C-diff traces | Outside both |
|---|---|---|---|---|
| `Counter` | scalar u64 state, `entry`/`query`, `let`, `+!` | ✅ `.counter` (all inputs, `counter-model`) | ✅ Counter scalar/event (EVM Yul host, Wasm, sBPF) | — |
| `ValueVault` | 6× scalar u64 state, `entry`/`query`, `let`, `+!`/`-!`/`*!`/`/!`, `emit`, `checkpointId` | partial: shallow ∀-call `valueVault_step_simulates` + full entrypoint fuel-coverage (not supportedFragment) | ✅ scalar/event slice + **EVM Yul multi-field storage rel** (Wasm, sBPF) | full IR↔target universal refinement |
| `Ownable` | scalar u64 (owner), `entry`/`query`, caller auth (`signer_account_id`) | ❌ | ❌ | caller-auth host import; ownership transfer |
| `RemoteCall` | scalar u64 state, `entry`, `crosscall.invoke`, `remoteCallRef` | ❌ | ❌ (IR stub, not peer) | crosscall materialize (CALL/CPI/Promise) — F1.4 gates separate |
| `ArrayExample` | `array` state, `query`, `for`, u64 indexing | ❌ | ✅ fixed-array storage probe (Wasm, sBPF) | dynamic array bounds; full `for` loop |
| `StakingVault` | `map` state, scalar state, `entry`/`query`, `emit`, `require`, `let` | ❌ | ❌ | map iteration; `require` assertion lowering |
| `RoleGatedToken` | `map` state, `bool` state, `entry`/`query`, `guard`, `emit`, `require` | ❌ | ✅ u64-map storage probe (Wasm, sBPF) | `guard` DSL lowering; bool state; role map |

**Summary:**

- **C-proof:** only `Counter` in `supportedFragment` (1/7 product sources).
  ValueVault has shallow universal step + fuel-coverage lemmas (F1.3) but is
  **not** yet a supported C-proof fragment.
- **C-diff:** `Counter` + `ValueVault` scalar/event (EVM Yul host + Wasm + sBPF)
  + focused `ArrayExample`/`RoleGatedToken` storage probes (4/7 partially covered).
- **Outside both:** `Ownable` (caller auth), `RemoteCall` (crosscall), and
  richer constructs from `StakingVault`/`RoleGatedToken` (map iteration, `guard`,
  `require` assertion lowering).

**F1.2 landed (2026-07-10)** — host-surface pins for N1/E1-adjacent lower paths:
- EVM: `just evm-yul-host-refinement-smoke` — IR↔Yul Counter + ValueVault
  paired simulation (`YulHostRefinement`; see [evm-yul-host-bridge.md](evm-yul-host-bridge.md));
  ValueVault now also has a slot-packed multi-field storage relation.
- NEAR/Wasm + Solana: existing Counter/ValueVault executable-trace anchors remain
  the triad C-diff pins (`just value-vault-wasm-refinement-smoke`, Solana sBPF
  refinement smokes).
- **Still open (not F1 blockers):** `Ownable` caller-auth trace; `StakingVault`
  map + `require`; `RoleGatedToken` `guard` + bool state.

**F1.3 landed (2026-07-10)** — ValueVault simulation / fuel growth on existing fragment:
- `valueVault_all_entrypoints_in_fuel_coverage` — every product entrypoint body
  is inside the shared fueled interpreter coverage set.
- `valueVault_step_simulates_all_calls` — re-export of the universal shallow
  step existence lemma for all `ValueVaultCall` over related states.
- Gates: `just semantics-fuel-smoke` (pins the new `#check`s).
- Keep crosscall as IR stub in C-proof; do not include materialize paths (F1.4).

## Non-goals

- No proofs about `solc`, `wat2wasm`, `sbpf`, `leo`, or chain runtimes; those
  stay in the differential-testing trust boundary and are recorded per gate
  in [validation-gates.md](validation-gates.md).
- No proof-transport to chains (no on-chain verification of Lean proofs);
  proofs gate codegen, per RFC 0001.
- No attempt to verify the Lean elaborator or Lake; the trusted computing
  base is stated, not eliminated.

## Suggested sequencing

1. FV-1 capability soundness (structural, unblocks nothing, high trust value).
2. FV-2 semantics extension + determinism (foundation).
3. FV-3 ownership soundness (justifies the merged `release` lowerings).
4. FV-4 backend trace obligations: scalar EVM IR traces are done for
   Counter, ValueVault, and EvmExpressionProbe; FV-2 map/aggregate/storage,
   control-flow, and event-log IR traces are now also connected to the EVM map,
   typed-storage, storage-struct, aggregate-ABI, conditional, loop, and event
   obligations. NEAR now has Counter and ValueVault EmitWat artifact-surface
   obligations plus offline-host execution-surface obligations, and the
   Counter + ValueVault scalar/event plus focused fixed-array/u64-map storage
   subset has an in-Lean executable Wasm trace; next, deepen that boundary
   toward broader maps, arrays, and richer Wasm/offline-host semantics. Solana now has the matching Counter +
   ValueVault scalar/event executable trace over lowered sBPF AST, plus focused
   fixed-array/u64-map storage probes and the Counter scalar account-data
   relation `R`; next, deepen that boundary toward broader aggregate storage
   and C-proof-style simulation lemmas.
5. FV-6 authoring-surface equivalence for the fixture subset.
6. FV-5 / FV-7 as the respective surfaces stabilize; continue FV-8 by turning
   the ValueVault invariant anchor into a reusable authoring surface and then
   linking it to backend obligations.
