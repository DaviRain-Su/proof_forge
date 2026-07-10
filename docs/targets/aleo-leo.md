# Aleo Leo Target

Status: **Registry target (Phase 4 ZK lane, Road 1 sourcegen) — `aleo-leo` is now
in `ProofForge.Target.Registry.all` / `knownIds` and exposed by
`proof-forge --list-targets`**

Candidate target id: **`aleo-leo`** (registered as `ProofForge.Target.aleoLeo`,
family `.zkCircuitSourcegen`, artifact kind `.leoSource`).

This note records the first ProofForge classification for Aleo and the
implemented Road 1 spike. It does not add a Lean target profile yet; the spike
validates the Leo source-generation boundary before any code registry changes.

Primary deliverables:

- `ProofForge.Backend.Aleo.IR` lowers the portable IR to Leo via a generic
  IR→AST→source pipeline (`IR/Common` + `IR/Validate` + `IR`), mirroring
  `ProofForge.Backend.Psy.IR`; it is no longer a Counter-only spike.
- `proof-forge emit --target aleo-leo --fixture counter --format leo` emits
  `Counter.leo`.
- `Examples/Backend/Aleo/Counter.golden.leo` is the tracked golden fixture.
- `scripts/aleo/counter-smoke.sh` generates a Leo package, runs `leo build` and
  `leo test`, writes `proof-forge-artifact.json`, and validates the metadata.
- `ProofForge.Backend.Aleo.IR` additionally supports pure entrypoints with
  parameters/return values and control-flow statements (`assert`, `assertEq`,
  `if/else`, `boundedFor`, `assign`, `assignOp`, `revert`), plus **scalar and
  map storage** (scalar states rewrite to a single-slot Leo `mapping u64 => T`).
- `ProofForge.Backend.Aleo.Metadata` (+ `MetadataJson`) emit plan-free artifact
  metadata (entrypoint ABI, on-chain `mapping` state surface, capabilities) for
  `proof-forge-artifact.json`, matching the Psy/EVM metadata layer.
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

The Road 1 spike is validated end-to-end by:

```bash
./scripts/aleo/counter-smoke.sh
```

Prerequisites:

- Lean toolchain from `lean-toolchain` and a built `proof-forge` binary.
- `python3` for package/manifest helpers.
- `leo` CLI on `PATH` (tested with Leo 4.0.2); if `leo` is missing, the script
  reports the generated `Counter.leo` and exits with code `127`.

What it proves:

- Portable IR `ProofForge.IR.Examples.Counter` lowers to a Leo 4.0 program with
  a public `mapping`, `@noupgrade constructor`, and `fn ... -> Final` entry
  points whose `final` blocks read/write the mapping.
- Generated Leo source matches the tracked golden fixture
  `Examples/Backend/Aleo/Counter.golden.leo`.
- `leo build` produces Aleo Instructions (`build/main.aleo`) and ABI JSON
  (`build/abi.json`).
- `leo test` passes.
- `proof-forge-artifact.json` is produced and schema-validated.

What it does not prove:

- Private records, transitions, or proof generation.
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

## Candidate Target Family

Do not add this to `ProofForge.Target.Registry` until the target model can
express Aleo's proof/finalization split and record/mapping state split.

Candidate family:

```text
zk-app-sourcegen
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

## Candidate Capabilities

These are research candidates, not canonical capability ids yet.

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

- Do not add `aleo-leo` to the code registry before candidate capabilities are
  reviewed.
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

**Status:** The Road 1 spike satisfies the reproducible local command and
artifact manifest schema criteria. **Phase 4 (2026-07-08) landed the target
profile criterion**: `aleo-leo` is now a registered `TargetProfile`
(`ProofForge.Target.aleoLeo`, family `.zkCircuitSourcegen`, artifact kind
`.leoSource`) and exposed by `proof-forge --list-targets`. The Lean-side
codegen gate `just aleo-leo-codegen-smoke` (in `just check`) witnesses the
Counter→Leo lowering + structure markers without needing the external `leo`
CLI. The remaining criteria (full capability proposal review, private-record
Road 2, devnet validation) stay open.

## Phase 4 Update (2026-07-08): Registry entry landed

`aleo-leo` is now a registered target profile (`ProofForge.Target.aleoLeo`),
exposed by `proof-forge --list-targets`. The profile uses family
`.zkCircuitSourcegen` (same as `psy-dpn`) and artifact kind `.leoSource`. The
canonical capability set for the Road 1 spike is:
`storage.map`, `caller.sender`, `env.block`, `control.conditional`,
`control.bounded_loop`, `data.struct`, `crypto.hash`, `assertions`,
`account.explicit`, `checked.arithmetic`, `zk.circuit`, `zk.proof`.

A Lean-side codegen gate (`just aleo-leo-codegen-smoke`, in `just check`)
verifies the registry entry and that the portable IR `Counter` fixture lowers
to a Leo program with the expected Road 1 structure markers. The external
`leo build` / `leo test` end-to-end gate stays in the GitHub CI `aleo-smoke`
job (`scripts/aleo/counter-smoke.sh` + `pure-math-smoke.sh`).

Road 2 (private records, transitions, proof generation) and Road 3 (direct
Aleo Instructions) remain future work. FV-import for Aleo would require a
Lean 4 semantics of the Aleo VM, which is not yet available; Aleo stays a
codegen target until such a semantics lands.

## Phase 4 Update (2026-07-08)

`aleo-leo` is now a **registry target** (`ProofForge.Target.aleoLeo`):
- `TargetFamily.zkCircuitSourcegen`, `ArtifactKind.leoSource`.
- Capabilities: `storage.map`, `caller.sender`, `env.block`,
  `control.conditional`, `control.bounded_loop`, `data.struct`, `crypto.hash`,
  `assertions`, `account.explicit`, `arith.checked`, `zk.circuit`, `zk.proof`.
- Exposed by `proof-forge --list-targets` / `ProofForge.Target.knownIds`.
- Lean-side codegen gate `just aleo-leo-codegen-smoke` (in `just check`):
  verifies the registry entry, Counter fixture lowering, and Leo structure
  markers without needing the external `leo` CLI.
- The external `leo build` / `leo test` end-to-end gate remains in the GitHub
  CI `aleo-smoke` job (`scripts/aleo/counter-smoke.sh`,
  `scripts/aleo/pure-math-smoke.sh`).

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
  map, `hasEffect` (drives the async/finalize split), Leo identifier
  validation, type-check helpers, scalar→mapping rewrite.
- `Backend/Aleo/IR/Validate.lean` — `validateCapabilities`/`Identifiers`/
  `Structs`/`State`/`Entrypoints`/`EntrypointBodies` with full type inference.
- `Backend/Aleo/IR.lean` — generic `buildExpr`/`buildStmt`/`buildFunction`/
  `buildModule`/`renderModule` (validate→build→print).
- `Backend/Aleo/Metadata.lean` + `MetadataJson.lean` — plan-free artifact
  metadata (entrypoint ABI, on-chain `mapping` state surface, capabilities),
  matching the Psy/EVM metadata layer.

Coverage now lowered: all arithmetic/bitwise/comparison/boolean ops, `cast`,
struct literals/field access, array literals/get, `assert`/`assertEq`/`revert`,
`if/else`, `boundedFor`, `return`, **scalar + map storage**, and **finalize
context reads** (`contextRead .userId/.userIdHash/.origin → self.caller`,
`.checkpointId → block.height`). Entrypoints lower (verified against the
INSTALLED `leo` 4.0.2 — `view fn` and the `..base` struct spread are newer
than 4.0.2, so they are NOT used): **write + pure return value** →
`fn … -> (T, Final)`; **any other storage effect** (write with stateful return,
or read-only) → `fn … -> Final { return final { … }; }` (mapping reads must
run in `final` in 4.0.2); **pure** → `fn … -> T`. Struct-field storage writes
use a 4.0.2-compatible read-modify-write (temp local + full struct rebuild,
NOT `..base`). The profile honestly declares `storage.scalar` (Aleo rewrites
scalars to a single-slot Leo `mapping u64 => T`).
`Tests/AleoLeoMapLoweringSmoke.lean`, `Tests/AleoLeoContextLoweringSmoke.lean`,
and `Tests/AleoLeoMetadataSmoke.lean` extend the `just aleo-leo-codegen-smoke`
gate. PureMath golden is byte-identical; Counter `get` is a `fn … -> Final`
finalize read (4.0.2-correct).

**Real compile gate:** every generated feature shape has been verified against
`leo build` (4.0.2) — see the `aleo-leo-build-smoke` gate (renders all shapes
via `RenderAleoFixtures.lean` and compiles each). Counter/PureMath/records/hash/
map/context/mixed-return/struct all compile; crosscall compiles to Aleo
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
in source order. Functions whose return value reads state keep the plain
`fn -> Final` shape. `Tests/AleoLeoMixedReturnSmoke.lean` covers a
`transfer_public_to_private`-style withdraw.

**Coverage breadth:** `Tests/AleoLeoCoverageSmoke.lean` runs 9 pre-existing IR
probes (arithmetic, bitwise, assertions, conditionals, bounded loops, structs,
U32 arithmetic, U64/U32/Bool scalar storage) through `renderModule`; all lower.

**Struct-field storage writes LANDED:** `storageStructFieldWrite` now lowers via
a read-modify-write using Leo's struct-update form `Name { f: v, ..read }` (new
`Expression.compositeUpdate` + Printer case; `defaultExpr` builds a field-wise
default struct literal so the `get_or_use` read has a fallback). This was the
last gap for the common IR subset (e.g. `StructProbe` now lowers fully).

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

- Target family: `zk-app-sourcegen`.
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
- Spike scope: Road 1 only, public mapping Counter from
  `ProofForge.IR.Examples.Counter`.

The Road 1 spike is implemented; code registry changes
(`ProofForge.Target.Capability` / `ProofForge.Target.Registry`) remain deferred
until the proof/finalization split and private-record roadmap are reviewed.
