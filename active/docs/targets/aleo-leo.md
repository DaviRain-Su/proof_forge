# Aleo Leo Target

Status: **Research sourcegen registry target** — `aleo-leo` is in
`ProofForge.Target.Registry.all` / `knownIds` and exposed by
`proof-forge --list-targets`, but it does not claim a final deployable package.

Target id: **`aleo-leo`** (registered as `ProofForge.Target.aleoLeo`,
family `.zkCircuitSourcegen`, artifact kind `.leoSource`).

This note records the ProofForge classification for Aleo and the implemented,
restricted Leo source-generation boundary. Registry membership is not a claim
that every portable contract, or even the full Counter fixture, is lowerable.

Primary deliverables:

- `ProofForge.Backend.Aleo.IR` lowers validated portable IR through a generic
  IR→AST→source pipeline (`IR/Common` + `IR/Validate` + `IR`).
- The full Counter fixture fails closed: Leo 4.0.2 cannot return the value of
  its mapping-backed `get() -> U64` from `final` without changing the ABI.
- `scripts/aleo/counter-smoke.sh` is the stable negative witness for that
  rejection. A write-only Counter fragment remains a compile-tested fixture.
- `ProofForge.Backend.Aleo.IR` additionally supports pure entrypoints with
  parameters/return values and control-flow statements (`assert`, `assertEq`,
  `if/else`, `boundedFor`, `assign`, `assignOp`, `revert`), plus **scalar and
  map storage** (scalar states rewrite to a single-slot Leo `mapping u64 => T`).
- `ProofForge.Backend.Aleo.Metadata` (+ `MetadataJson`) derives ABI and state
  metadata from the same validated `FunctionPlan` used by code generation.
- `Tests/AleoLeoMapLoweringSmoke.lean` and `Tests/AleoLeoMetadataSmoke.lean`
  witness the generic map-storage lowering and the metadata layer in `just check`.
- `proof-forge emit --target aleo-leo --fixture pure-math --format leo` emits
  `PureMath.leo`.
- `Examples/Backend/Aleo/PureMath.golden.leo` is the tracked golden fixture.
- `scripts/aleo/pure-math-smoke.sh` validates the PureMath fixture end-to-end.


Primary sources:

- [Aleo getting started](https://docs.aleo.org/build/getting-started)
- [Leo installation](https://docs.aleo.org/build/leo/documentation/getting_started/installation)
- [Aleo Instructions overview](https://docs.aleo.org/build/aleo-instructions/overview)
- [Public & Private State](https://docs.aleo.org/learn/core-concepts/public-and-private-state)
- [Programs](https://docs.aleo.org/learn/core-concepts/programs)
- [Transactions](https://docs.aleo.org/learn/core-concepts/transactions)
- [Leo finalization model](https://docs.aleo.org/build/leo/documentation/guides/finalization)
- [Leo CLI overview](https://docs.aleo.org/build/leo/documentation/cli/cli_overview)
- [leo build](https://docs.aleo.org/build/leo/documentation/cli/cli_build)
- [leo execute](https://docs.aleo.org/build/leo/documentation/cli/cli_execute)
- [leo test](https://docs.aleo.org/build/leo/documentation/cli/cli_test)

## Local Smoke

The supported and rejected paths are validated by:

```bash
./scripts/aleo/counter-smoke.sh
./scripts/aleo/pure-math-smoke.sh
just aleo-leo-build-smoke
```

Prerequisites:

- Lean toolchain from `lean-toolchain` and a built `proof-forge` binary.
- `python3` for package/manifest helpers.
- `leo` CLI on `PATH` (tested with Leo 4.0.2) for positive build/test gates.

What it proves:

- Full Counter is rejected before source generation rather than exposing an
  ABI-incompatible `get() -> Final`.
- PureMath matches `Examples/Backend/Aleo/PureMath.golden.leo`, and `leo build`
  plus `leo test` succeed.
- The generated-feature build gate compiles write-only Counter, map, context,
  record, hash, mixed-return, and cross-program-call source shapes.

What it does not prove:

- General state-derived return values across Leo `final`.
- Record spend workflows, proof generation, or private-state equivalence.
- Direct Aleo Instructions generation.
- Devnet deployment or execute transactions.
- Cross-target equivalence with EVM/Psy Counter semantics.
- A standalone `.avm` bytecode file; the current `leo build` output embeds VM
  artifacts in the compiled package rather than emitting a separate file.

## Classification

Aleo is a ZK-native smart-contract L1. It is not the same kind of target as
Zcash, Psy/DPN, or Starknet.

The better first classification is:

```text
Aleo ZK application sourcegen target
  with Leo as the first source-generation boundary
  with Aleo Instructions as the lower-level compiler target
  with Aleo VM bytecode, prover/verifier artifacts, ABI, and transaction proofs
```

Aleo is "ZK" because program execution is split between:

- proof context: private, off-chain execution that can consume/create records
  and generate ZK proofs;
- finalization context: public, on-chain execution that reads/writes mappings,
  storage variables, and storage vectors.

That means Aleo is closer to a privacy-aware contract chain than to a plain ZK
circuit output target. ProofForge should model Aleo programs as deployable
program packages, not just as circuits.

## Why This Is Not The Same As Existing ZK Targets

Existing ProofForge ZK-related notes cover different shapes:

- `psy-dpn`: target source compiles to DPN circuit JSON artifacts.
- `zcash-shielded`: ZK proves protocol-defined shielded payment statements.
- `kaspa-toccata`: an L1 covenant may verify a proof inline or settle based-app
  state.
- `starknet-cairo`: Cairo contracts compile through Sierra/CASM; Starknet is
  not modeled as a generic circuit target.

Aleo needs its own family because:

- Leo programs are smart contracts with program ids, imports, entry functions,
  records, mappings, finalization logic, and deploy/execute transactions;
- private state uses records, which are encrypted and UTXO-like;
- public state uses mappings/storage updated by validators in `final` logic;
- execute transactions contain transitions and ZK proofs;
- build outputs include `.aleo` instructions, ABI, prover/verifier files, and
  Aleo VM bytecode;
- local validation can use `leo build`, `leo test`, `leo execute`, and devnet
  deployment flows.

## Target Family Decision

The registered compiler family is:

```text
zk-circuit-sourcegen
```

Candidate backend pattern:

```text
ProofForge portable IR subset
  -> generated Leo package
  -> leo build
  -> Aleo Instructions (.aleo)
  -> Aleo VM bytecode + ABI + prover/verifier artifacts
  -> leo test / leo execute / leo devnet validation metadata
```

Direct Aleo Instructions generation is a later road. It is attractive for a
compiler backend, but Leo is the safer first artifact because it is the
recommended developer language and exposes program structure more clearly.

Candidate artifact shape:

```text
aleo-leo-package
  - generated Leo source
  - program id and imports
  - record / mapping / storage schema
  - proof-context entry functions
  - finalization manifest
  - compiled Aleo Instructions
  - AVM bytecode
  - ABI JSON
  - prover and verifier artifacts
  - execute/deploy transaction metadata
  - test/devnet validation result
```

## Future Aleo-Native Capabilities

These remain research candidates rather than shared capability ids.

| Candidate capability | Meaning |
|---|---|
| `lang.leo` | Target emits Leo source packages. |
| `ir.aleo_instructions` | Build emits or consumes Aleo Instructions. |
| `vm.aleo_avm` | Target runs on the Aleo VM, not Algorand AVM. |
| `artifact.avm` | Build emits Aleo VM bytecode. |
| `artifact.aleo_abi` | Build emits Aleo ABI metadata. |
| `proof.prover_key` | Build or execute flow produces prover artifacts. |
| `proof.verifier_key` | Build or deploy flow records verifier artifacts. |
| `execution.transition` | Entry execution produces a transition and proof. |
| `execution.finalize` | Program has public on-chain finalization logic. |
| `state.record` | Private state is held in encrypted records. |
| `state.mapping` | Public state is held in mappings. |
| `state.storage` | Public state may use storage variables or storage vectors. |
| `input.private` | Function input is private proof-context data. |
| `input.public` | Function input is public data. |
| `output.private` | Function output is private by default. |
| `output.public` | Function output is public. |
| `program.import` | Program imports and calls another Aleo program. |
| `program.upgrade` | Deployment may support explicit program upgrades. |
| `transaction.execute` | Validation can produce an execute transaction. |
| `transaction.deploy` | Validation can produce or inspect a deploy transaction. |
| `fee.credits` | Fees are paid in Aleo Credits, publicly or privately. |
| `test.leo` | Validation uses Leo tests. |
| `test.aleo_devnet` | Validation uses Leo devnet or devnode-backed flows. |

`zk.circuit` alone is not sufficient for Aleo. It may describe the proof aspect,
but Aleo also needs program, state, transaction, and finalization capabilities.

## Implementation Roads

### Road 1: Leo Sourcegen Package

Use this road first.

First spike:

- choose a tiny Counter-like program;
- generate Leo source with one entry `fn` and one `final { }` block;
- use a public `mapping` for the counter;
- run `leo build` and record `.aleo`, ABI, bytecode, and toolchain metadata;
- run `leo test`, with `--prove` as an optional heavier gate.

This validates the compiler boundary without taking responsibility for Aleo VM
internals.

### Road 2: Private Record Flow

Use this road to validate Aleo's ZK-specific value proposition.

First spike:

- define a simple private record type;
- consume one record and create one successor record in a proof-context entry
  function;
- keep record contents private while exposing only required public outputs or
  finalize effects;
- run `leo execute --print` or SDK-backed execution to inspect transaction and
  proof metadata.

This is the path that proves Aleo support is more than an account-chain source
generator.

### Road 3 status (Z2, 2026-07-10)

**Counter public-mapping path is live** as a bootstrap direct emit:

```sh
proof-forge emit --target aleo-leo --fixture counter --format aleo -o Counter.aleo
just aleo-instructions-direct
just aleo-instructions-printer
just aleo-aleo-goldens
```

Golden: `Examples/Backend/Aleo/Counter.golden.aleo` (from `leo build` of
`Counter.golden.leo`). Policy: `docs/superpowers/specs/2026-07-10-z2-fallback-policy.md`.
Leo Road 1 remains the general front-end; private records / proofs are Road 2.

### Road 3: Direct Aleo Instructions

Use this road only after Leo sourcegen proves the semantics.

First spike:

- lower a tiny typed IR fixture directly to `.aleo` instructions;
- preserve public/private input annotations;
- generate or validate prover/verifier artifacts through the official toolchain;
- compare output against Leo-generated Aleo Instructions for the same behavior.

This road is useful for compiler precision, but it has a larger semantic
surface than Leo sourcegen.

## Non-Goals For The First Pass

- Do not widen the registered capability profile without a reviewed semantic
  mapping and a fail-closed gate.
- Do not classify Aleo as only a generic ZK circuit target.
- Do not confuse Aleo VM with Algorand AVM.
- Do not model records as EVM storage or as Zcash shielded notes.
- Do not model `final` blocks as private execution; finalization is public and
  on-chain.
- Do not claim full Aleo support until there is a reproducible local build/test
  command.
- Do not start with direct Aleo Instructions if Leo sourcegen is enough to
  validate the first spike.

## Research Exit Criteria

Aleo can leave Research only when we have:

- a reviewed target profile proposal;
- a committed capability proposal for Leo, Aleo Instructions, Aleo VM bytecode,
  transitions, finalization, records, mappings, proofs, ABI, fees, and devnet
  validation;
- a minimal artifact manifest schema for Leo source, compiled outputs,
  prover/verifier artifacts, ABI, and transaction/deploy metadata;
- a toolchain decision for local validation using Leo CLI, SDK, devnet, or
  devnode;
- one reproducible local command or script that validates a tiny Leo program
  package, even if proving-heavy gates are optional in CI.

**Status:** the profile and reproducible sourcegen gates exist, but devnet,
proof generation, and full portable-state return semantics remain open.

## Registry And Gate Status

`aleo-leo` is a registry target (`ProofForge.Target.aleoLeo`):
- `TargetFamily.zkCircuitSourcegen`, `ArtifactKind.leoSource`.
- Capabilities: `storage.map`, `caller.sender`, `env.block`,
  `control.conditional`, `control.bounded_loop`, `data.struct`,
  `data.linear_record`, `crypto.hash`, `crosscall.named`, `assertions`,
  `account.explicit`, `arith.checked`, `zk.circuit`, `zk.proof`.
- Exposed by `proof-forge --list-targets` / `ProofForge.Target.knownIds`.
- Lean-side codegen gate `just aleo-leo-codegen-smoke` (in `just check`):
  verifies full Counter rejection and supported-fragment lowering.
- `just aleo-leo-build-smoke` uses Leo 4.0.2 to compile every generated
  positive fixture. `scripts/aleo/pure-math-smoke.sh` runs the executable
  golden/package test.

Road 2 (private records, transitions, proof generation) and Road 3 (direct
Aleo Instructions) remain future work. The FV-import lane (Road 2 of the ZK
lane in the roadmap) for Aleo would require an external Lean 4 Aleo VM
semantics, which is not yet available; Cairo (`starkware-libs/formal-proofs`)
and Noir (`reilabs/lampe`) are the ZK targets with ready Lean semantics and
are prioritised for FV-import once the codegen lane lands.

## Phase 4 Update (2026-07-10): generic lowering + metadata

The Road 1 Counter-spike emitter (`ProofForge.Compiler.Leo.Emit`, which
hardcoded `initialize`/`get`/`increment`) is replaced by a **generic IR→Leo
lowering** that mirrors `ProofForge.Backend.Psy.IR`:

- `Backend/Aleo/IR/Common.lean` — LowerError, BuildContext, portable→Leo type
  map, exhaustive expression facts, def-use checked `FunctionPlan`, Leo
  identifier validation, type-check helpers, scalar→mapping rewrite.
- `Backend/Aleo/IR/Validate.lean` — `validateCapabilities`/`Identifiers`/
  `Structs`/`State`/`Entrypoints`/`EntrypointBodies` with full type inference.
- `Backend/Aleo/IR.lean` — generic `buildExpr`/`buildStmt`/`buildFunction`/
  `buildModule`/`renderModule` (validate→build→print).
- `Backend/Aleo/Metadata.lean` + `MetadataJson.lean` — metadata derived from the
  validated function plan (entrypoint ABI, state surface, capabilities).

Coverage now lowered: all arithmetic/bitwise/comparison/boolean ops, `cast`,
struct literals/field access, array literals/get, `assert`/`assertEq`/`revert`,
`if/else`, `boundedFor`, `return`, **scalar + map storage**, and **finalize
context reads** (`contextRead .userId/.userIdHash/.origin → self.caller`,
`.checkpointId → block.height`). Entrypoints lower (verified against Leo 4.0.2):
**write + state-independent return value** → `fn … -> (T, Final)`;
**Unit-returning storage effects** → `fn … -> Final`; **pure** → `fn … -> T`.
State-derived non-Unit returns fail closed because mapping reads only exist in
`final` and cannot produce a caller-visible value in Leo 4.0.2. Struct-field storage writes
use a 4.0.2-compatible read-modify-write (temp local + full struct rebuild,
NOT `..base`). The profile honestly declares `storage.scalar` (Aleo rewrites
scalars to a single-slot Leo `mapping u64 => T`).
For `.add`/`.sub`/`.mul`, the expression node's `overflowChecked` bit selects
checked infix versus Leo `_wrapped` operations; `Module.overflowChecked` only
selects compound `AssignOp`, whose IR node has no per-expression bit.
Mixed `(T, Final)` lowering accepts only the order-preserving canonical form:
an immutable pure prefix, one contiguous storage/final region, and one terminal
state-independent return. Mutable locals, control flow, named crosscalls, or a
pure statement after the final region starts fail closed rather than move across
the boundary. Linear records are detected transitively through structs and
fixed arrays and are forbidden in state keys/values.
`Mapping::get_or_use` defaults are fail-closed for `address`, including an
address nested transitively in an ordinary value struct: Leo 4.0.2 does not
accept `none` as an address and ProofForge will not invent a zero identity.
Write-only address storage remains supported. Ordinary value structs also
cannot declare a field named `owner`; Leo reserves it for records, whose
required `owner: address` field remains supported.
`Tests/AleoLeoMapLoweringSmoke.lean`, `Tests/AleoLeoContextLoweringSmoke.lean`,
`Tests/AleoLeoStorageDefaultSmoke.lean`, and `Tests/AleoLeoMetadataSmoke.lean`
extend the `just aleo-leo-codegen-smoke`
gate. PureMath is the tracked positive golden; full Counter has no Leo golden
because its getter is rejected.

**Real compile gate:** every generated feature shape has been verified against
`leo build` (4.0.2) — see the `aleo-leo-build-smoke` gate (renders all shapes
via `RenderAleoFixtures.lean` and compiles each). Write-only Counter and address
storage, address-free value-struct defaults, PureMath, records, hash, map,
context, and mixed-return shapes compile. Direct and nested address-default
fixtures must be rejected before source emission; crosscall compiles to Aleo
instructions against a local `credits.aleo` stub (leo 4.0.2 has a downstream
bytecode-serialization bug for external calls that fires after instruction
generation — a toolchain defect, not a source defect — so the gate treats
instruction generation as the crosscall success criterion). The Lean marker-smokes
only check substrings, so this `leo build` gate is the real correctness witness.

**`crypto.hash` LANDED (RFC 0015 Decisions 1+2):** Aleo resolves the portable
`Hash` digest to `field` and lowers hash ops to the native ZK hash
`Poseidon2::hash_to_field` (verified against ProvableHQ/leo operators/crypto).
`.hash preimage` → `Poseidon2::hash_to_field(preimage)`; `.hashTwoToOne`/
`.hashValue` fold pairwise (Leo hashes a single primitive). `hash4` literals
are rejected (EVM 4×u64 digest shape). Hashing is capability-portable, NOT
value-portable (keccak ≠ Poseidon) — see RFC 0015.
`Tests/AleoLeoHashLoweringSmoke.lean` covers it.

**Cross-circuit calls LANDED (RFC 0015 Decision 4):** a portable
`crosscallNamed(programId, method, args, returnType)` (new `Expr` constructor +
`crosscall.named` capability, declared on the aleo-leo profile) lowers to a
static qualified call `programId::method(args)` plus an `import programId;`
declaration (verified against `data_types/external_consumer`). Account-chain
targets reject it. `Tests/AleoLeoCrosscallSmoke.lean` covers it.

**Remaining honest reject:** **Events** — Aleo/Leo has no event mechanism
(records + finalize instead); the profile intentionally omits `eventsEmit`.
(RFC 0015 Decision 3 — an opt-in hash-algorithm tag for value-portable keccak —
remains deferred.)

**Mixed `(value, Final)` return LANDED:** a stateful function whose return
value is pure lowers as `fn f(…) -> (T, Final) { …; return (value, final { … }); }`
(verified against `functions/transfer_inline`). Pure (non-storage) statements
+ the pure return run off-chain; storage read/write statements run in `final {}`
in source order. Functions whose caller-visible return depends on state are
rejected. `Tests/AleoLeoMixedReturnSmoke.lean` covers a
`transfer_public_to_private`-style withdraw.

**Coverage breadth:** `Tests/AleoLeoCoverageSmoke.lean` runs 9 pre-existing IR
probes through `renderModule`. Four pure probes lower (arithmetic, bitwise,
assertions, and U32 arithmetic); five stateful probes fail closed because their
caller-visible results depend on Leo mapping state.

**Struct-field storage writes LANDED:** `storageStructFieldWrite` lowers via a
Leo 4.0.2-compatible read-modify-write that rebuilds every field explicitly;
`defaultExpr` provides the `get_or_use` fallback for address-free value structs.
Structs that transitively contain address fail closed because Leo has no honest
address fallback.

Road 2 slice 1 LANDED: record DECLARATION + CREATION. An opt-in
`StructDecl.isRecord` flag (mirroring `deriveStorage`) lowers a struct as a
Leo `record`; a pure `fn … -> Record` that builds a record literal (e.g.
`Token { owner: self.caller, amount }`) lowers directly. `Tests/AleoLeoRecordLoweringSmoke.lean`
witnesses a `mint`-style record creation (verified against `migration/transitions_to_fn`).
Record consume/spend remains future work.

## Research Exit Plan

A detailed design spec covering Research exit + Road 1 spike is in
[docs/superpowers/specs/2026-07-01-aleo-leo-design.md](../../superpowers/specs/2026-07-01-aleo-leo-design.md).

The spec finalizes:

- Original design term: `zk-app-sourcegen`; the registry family id is
  `zk-circuit-sourcegen`.
- Canonical capabilities for the first spike:
  `lang.leo`, `vm.aleo_avm`, `artifact.avm`, `artifact.aleo_abi`,
  `execution.finalize`, `state.mapping`, `input.public`, `output.public`,
  `test.leo`.
- Research-only capabilities for future spikes:
  `ir.aleo_instructions`, `proof.prover_key`, `proof.verifier_key`,
  `execution.transition`, `state.record`, `state.storage`, `input.private`,
  `output.private`, `program.import`, `program.upgrade`, `transaction.execute`,
  `transaction.deploy`, `fee.credits`, `test.aleo_devnet`.
- Artifact manifest schema for `aleo-leo-package`.
- Toolchain decision: `leo build` + `leo test` primary; prove/execute optional.
- Original design scope: public mapping Counter. The implementation now rejects
  its getter and keeps only the write-only slice as positive compile evidence.

The Road 1 profile is implemented. Target-specific proof, transaction, fee,
and devnet capabilities remain deferred until their semantics and validation
surfaces are implemented.
