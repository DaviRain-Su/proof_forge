# Psy DPN ZK Target

Status: **Experimental**

Canonical target id: `psy-dpn`

Reference repository: `https://github.com/PsyProtocol/psy-compiler`

Research snapshot: `mainnet-beta`, commit `24f5ec9`.

Experimental scope: ProofForge can generate reviewable `.psy` source for a
restricted portable IR subset and validate that source with Dargo for Counter,
ExpressionPredicateProbe, GenericEntrypointProbe, ArithmeticProbe,
U32ArithmeticProbe, BitwiseProbe, U32HashPackingProbe,
U32StorageScalarProbe, BoolStorageScalarProbe, BoolStorageArrayProbe,
U32StorageArrayProbe, ConditionalProbe, ContextProbe, HashProbe, MapProbe,
HashStorageProbe, AssertProbe, LoopProbe, ArrayProbe, StructProbe, StructArrayProbe,
AbiAggregateProbe, and NestedAggregateProbe fixtures. It also has an experimental
StorageNestedAggregateProbe fixture for storage-backed nested aggregate updates
across `#[ref]` struct fields and storage arrays. The
target is not production-ready and does not yet cover else-if sugar, upstream
compressed genesis deploy JSON, live Psy node/prover deployment, or broad
Lean-to-IR extraction. It does produce a ProofForge deploy manifest for every
Dargo-backed Psy smoke fixture.

## Summary

Psy is a ZK-oriented contract target, not an EVM/Wasm/Solana/Move variant. The
public compiler repository defines the `.psy` language, parser, semantic
checker, interpreter/lowering flow, ABI generation, Dargo CLI, browser/Node
Wasm bindings, and precompiled contract examples.

The important distinction for ProofForge is that Psy compiles contract methods
to DPN circuit function definitions. The target artifact is closer to a ZK VM
circuit artifact than to EVM bytecode or a Wasm module.

Initial ProofForge integration should therefore treat Psy as a **ZK circuit
source-generation target**:

```text
Lean portable contract
  -> Lean checks and proofs
  -> Psy-compatible portable IR subset
  -> Psy semantic plan (ProofForge.Backend.Psy.Plan)
  -> Psy AST (ProofForge.Compiler.Psy.AST)
  -> generated .psy package (ProofForge.Compiler.Psy.Printer)
  -> dargo compile
  -> DPNFunctionCircuitDefinition JSON + ABI
  -> Psy deploy/test tooling
```

The lowering is now three-stage, mirroring the EVM
(`Lower.lean` → `Plan.lean` → `IR.lean` → `Compiler/Yul/AST.lean` + `Printer.lean`)
and Wasm-family backend pattern:

1. **Plan** (`ProofForge.Backend.Psy.Plan.buildModulePlan`): resolves Psy-specific
   shapes from the portable IR — storage layout (scalar/structRef/map/array +
   feltBackedU32 flags), context fields used, event plans, crosscall targets,
   and the fixture-shape-detected test body. This is the counterpart of EVM
   `Lower.lean` → `Plan.lean`.
2. **AST** (`buildModuleWithPlan`): folds the IR + plan into a target-side
   `Psy.Module` AST. This is the counterpart of EVM `IR.lean lowerModuleWithPlan`.
3. **Printer** (`ProofForge.Compiler.Psy.Printer.module`): renders the AST to
   `.psy` source text. Pure structural, no IR resolution.

The AST is a surface AST that captures exactly the `.psy` forms the printer
emits; it does not model the upstream `psy-ast::Program` interner/arena/checker
layers. The plan decouples shape resolution from source formatting and gives a
stable inspection point for artifact/deploy metadata.

Do not start by directly emitting Psy DPN internals. The public repo does not
expose a stable Yul-like textual intermediate language.

## Why This Is A New Target Family

Existing target families in ProofForge are:

- direct compiler target: EVM through Yul and `solc`
- Wasm host targets: NEAR and CosmWasm
- binary toolchain targets: Solana sBPF
- source codegen targets: Move packages

Psy is different:

- contract execution is circuit/proof oriented
- the compiler output is a set of circuit function definitions
- the deployable object is Psy-specific contract code/deploy JSON
- storage and call semantics are not EVM slot storage
- the usable public integration boundary is `.psy` source plus Dargo tooling

This should become a fifth family:

```text
ZK circuit sourcegen: Portable IR -> target source -> circuit artifact
```

## Toolchain Shape

Observed public tooling:

| Component | Role |
|---|---|
| `.psy` language | Target source language for contracts and tests |
| `dargo compile` | Compiles a Psy package to `Vec<DPNFunctionCircuitDefinition>` JSON |
| `dargo execute` | Runs compiled circuits in a local user/contract execution session |
| `dargo test` | Runs compiler/interpreter tests for Psy source |
| `dargo generate-abi` | Generates ABI JSON from parsed/typechecked contracts |
| `psy-wasm` | Browser/Node wrapper around the compiler and in-memory VM demo |
| `gen_deploy_json` example | Converts compiled function JSON into Psy genesis deploy JSON |

The first ProofForge adapter should shell out to `dargo` rather than embedding
Psy Rust crates. Embedding is possible later, but the compiler workspace depends
on `psy-node` crates through SSH git dependencies, so a CLI boundary is more
practical for early spikes and CI.

## Upstream Syntax And CI Corpus

The best grammar and idiom corpus is the upstream `psy-compiler` repository:

| Source | What to learn |
|---|---|
| `psy-precompiles/*/src/main.psy` | Production-style contract storage, events, fixed arrays, maps, hashing, cross-contract refs, and ABI method sets |
| `psy-precompiles/*/Dargo.toml` | Package layout and local dependency structure |
| `tests/*.psy` | Small syntax and semantic probes for storage refs, context functions, maps, traits, arrays, loops, hashes, and assertions |
| `Makefile` `ci` target | Official local test matrix for `dargo test`, `dargo compile`, and `dargo execute` |
| `Makefile` precompile targets | Method lists for compiling and ABI-generating shipped contracts |

Important Makefile signals:

```make
export DARGO_STD_PATH := $(PWD)/psy-std/std.psy

build:
	@RUSTFLAGS="-A warnings" cargo build --profile ${PROFILE} -p psy-precompiles
	@RUSTFLAGS="-A warnings" cargo build --profile ${PROFILE} --bin dargo --bin psy-lsp-server

DARGO_CLI_COMPILE = RUST_LOG=$(LOG_LEVEL) ./target/${PROFILE}/dargo compile --program-dir tests --debug --entry-path
DARGO_CLI_EXECUTE = RUST_LOG=${LOG_LEVEL} ./target/${PROFILE}/dargo execute --program-dir tests --debug --entry-path
DARGO_CLI_TEST    = RUST_LOG=${LOG_LEVEL} ./target/${PROFILE}/dargo test --file
```

For ProofForge this gives two source-aligned validation styles:

1. Package smoke, matching precompiled contracts:

```sh
cd build/psy/dargo-counter
dargo compile --contract-name Counter --method-names initialize increment get
dargo execute --contract-name Counter --method-names initialize increment increment get
dargo generate-abi --contract-name Counter --output-dir target --pretty
```

2. Syntax corpus smoke, matching upstream `tests`:

```sh
dargo test --file path/to/test.psy
dargo --program-dir tests execute --debug --entry-path ctx_test.psy --parameters 2,3
```

The current ProofForge smoke uses the package style because it mirrors the
eventual generated artifact layout. The temporary Dargo package directories are
now created by `scripts/psy/write-dargo-package.py`, which writes the package
source copy at `src/main.psy` and a stable `Dargo.toml` manifest before the
smoke calls `dargo compile`, `dargo execute`, and `dargo generate-abi`. A future
syntax-regression gate should copy or vendor a curated subset of upstream tests
and run them with the second style against the exact `dargo` version used in CI.

## SDK Surface

The first Lean SDK module is `ProofForge.Psy` with namespace `Lean.Psy`.

It provides:

- primitive aliases for `Felt`, `U32`, and `Hash`
- context helpers such as user id, contract id, checkpoint id, and checkpoint
  roots
- raw state hash accessors
- fixed slot and fixed-capacity map wrappers
- hash intrinsics
- deferred invocation intrinsics

The SDK is intentionally a source-generation boundary. Its `lean_psy_*` externs
do not have a native runtime implementation; the future `psy-dpn` backend should
recognize these names and lower them to `.psy` source constructs or reject them
with capability diagnostics.

## Yul-Like IR Assessment

Psy currently has several intermediate layers, but none are equivalent to Yul
for ProofForge's purposes.

| Layer | Public? | Stable integration boundary? | Notes |
|---|---:|---:|---|
| `.psy` source | Yes | Yes | Source text boundary; rendered by `ProofForge.Compiler.Psy.Printer` |
| `psy-ast` / checked AST | Yes | Yes (surface mirror) | ProofForge maintains a target-side surface AST (`ProofForge.Compiler.Psy.AST`) mirroring the `.psy` source forms, **not** the upstream `psy-ast::Program` interner/arena/checker layers |
| `QExecContext` / DPN ops | Partly | No | Symbolic execution/circuit lowering layer; core types come from `psy-node` |
| `DPNFunctionCircuitDefinition` JSON | Yes | Artifact, not IR | Good output artifact, too target-specific and opaque for ProofForge IR |
| ABI / contract code JSON | Yes | Output metadata | Useful for deployment and cloud metadata |

The upstream `psy-ast` crate (`psy-compiler/psy-ast/src`) defines a full
compiler AST with interners, arenas, def-ids, locations, and a checked
`Program<F>` tree. ProofForge does not target that internal representation
directly — it is tied to Psy compiler internals and carries type-checking
state that belongs upstream. Instead, ProofForge defines its own
`ProofForge.Compiler.Psy.AST` module-side AST that captures exactly the
`.psy` surface forms the printer emits (modules, structs, state, methods,
statements, expressions, effects, storage targets, operators, literals, and
context fields). This mirrors the in-repo pattern used by the EVM backend
(`Compiler/Yul/AST.lean` + `Printer.lean`) and the Wasm-family backends
(`Compiler/Wasm/AST.lean` + `Printer.lean`): a small target AST plus a pure
structural printer.

Conclusion: **ProofForge uses its own portable contract IR as the stable
middle layer, resolves Psy-specific shapes into a semantic plan, lowers the
IR + plan to a target-side `Psy.Module` AST, and renders that AST to `.psy`
source**. The three-stage lowering (IR → Plan → AST → source) decouples shape
resolution (plan) from AST construction from source formatting (printer),
mirroring the EVM `Lower → Plan → ToYul → Printer` split, and leaves clear
extension points for future Psy plan-level passes (artifact metadata,
canonicalization) and AST-level passes (formatting control, upstream-AST
emission if the compiler internals stabilize).

## Proposed Target Profile

```text
id: psy-dpn
family: zkCircuitSourcegen
artifactKind: psyCircuitJson
stage: Experimental
primaryInput: ProofForge portable IR subset
primaryOutput: target/contract.json containing DPNFunctionCircuitDefinition[]
sideOutputs:
  - generated .psy source package
  - generated Dargo package source copy
  - generated Dargo.toml package manifest
  - ABI JSON
  - proof-forge-artifact.json
  - ProofForge deploy manifest JSON
  - optional upstream Psy genesis deploy JSON
```

Required external tools:

- Rust toolchain compatible with the Psy compiler workspace
- `dargo`, preferably installed from `psyup`
- optional `wasm-pack` only if using `psy-wasm`
- optional Psy node/prover tooling for deployment-level tests

`cargo install --git https://github.com/PsyProtocol/psy-compiler dargo` is the
upstream Dargo install path, but it may pull `psy-node` and its submodules
during Cargo dependency resolution. On this machine it failed on the
`psy-contracts` submodule URL inside `psy-node`.

`psyup` is the more practical local toolchain path. It installs a released
toolchain tarball, symlinks `dargo`, and writes `DARGO_STD_PATH` to the bundled
`psy-std`.

```sh
curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh | bash
```

Observed release caveat: `psyup` v0.1.1 currently publishes Linux x86_64 only.
For macOS arm64, v0.1.0 includes
`psy-toolchain-v0.1.0-aarch64-apple-darwin.tar.gz` and has been validated with
the Counter smoke:

```sh
psyup install 0.1.0
scripts/psy/counter-smoke.sh
```

## Portable IR Subset

The first `psy-dpn` subset should be stricter than the EVM subset.

Allowed first:

- `Felt`, `Bool`, `U32`
- Felt arithmetic for addition, subtraction, and multiplication
- U32 arithmetic for addition, subtraction, multiplication, division, modulo,
  exponentiation, and casts to/from Bool/Felt
- fixed-size arrays
- concrete structs
- first-order functions
- entrypoint parameters over supported scalar/fixed-size types
- statement-level `if/else` branches with Bool conditions
- static bounded `for` loops that the Psy compiler accepts
- assertions
- hash operations represented through `crypto.hash`
- dynamic `Hash` value construction from four Felt limbs
- context reads such as user id, contract id, and checkpoint id
- persistent scalar state
- fixed-capacity maps where represented in Psy storage
- explicit contract methods

Rejected first:

- arbitrary Lean runtime objects
- closures and higher-order runtime values
- unbounded recursion
- dynamic heap-heavy data structures
- target-native operations not represented as capabilities
- direct emission of DPN internals
- automatic translation of arbitrary EVM storage layouts

The target should fail before source generation when an unsupported IR node or
capability appears.

The current executable rejection gate is:

```sh
scripts/psy/diagnostic-smoke.sh
```

It runs `Tests/PsyDiagnostics.lean` and checks that malformed Psy IR modules
return stable, explicit errors before source generation. Current cases cover
Unit entrypoint parameters, zero-length ABI arrays, unknown ABI structs,
unsupported map key/value shapes, unsupported Unit storage arrays, structs
missing `deriveStorage` for storage,
empty structs, invalid bounded loop ranges,
storage writes used as expressions, storage reads used as statements, invalid
assignment targets, invalid storage paths, unknown locals,
local/array/struct/hash/return type mismatches, immutable assignment, missing
return statements, malformed arithmetic expressions, malformed Hash value
construction, unsupported casts, malformed bitwise/shift expressions, malformed
if conditions, and branch-local escape.

Psy/DPN entrypoints are addressed by contract method name through Dargo and the
generated Psy ABI. The portable IR's optional `selector?` field is target-specific
ABI metadata for EVM-style dispatch; it is not used during Psy source generation
and is not required for this target. A module may still supply a selector (for
example when the same IR module is shared with the EVM backend); the Psy backend
allows it and may record it in artifact metadata for cross-target traceability,
but the generated `.psy` source relies on method names only.

The design philosophy docs reinforce the same boundary: Psy is ZK-native and
uses symbolic execution. Variables become circuit wires, operations become
gates, control flow is flattened, bounded loops are unrolled, and function calls
are inlined by default. The first Psy lowering should therefore prefer static
Felt/Bool/U32 values, fixed-size arrays, bounded loops, explicit storage
effects, and small helper functions over dynamic runtime-like constructs.

## Capability Mapping

Initial mapping:

| Portable capability | Psy direction |
|---|---|
| `storage.scalar` | generated `#[derive(Storage)]` field or explicit state access |
| `storage.map` | fixed-capacity map/storage pattern where supported by Psy |
| `storage.array` | fixed-size Psy storage arrays with indexed read/write access |
| `caller.sender` | Psy user/context functions such as user id |
| `value.native` | rejected by Psy IR v0; Psy 0.1.0 has no `msg.value` equivalent |
| `events.emit` | `__emit([field, ...])` with an event-name comment; EventProbe smoke validates `result_events` |
| `crosscall.invoke` | `__invoke_sync#<Felt>(contract_id, method_id, [args])`; CrosscallProbe smoke validates Dargo compilation; local `dargo execute` panics on unimplemented cross-contract circuit gadget in Psy 0.1.0 |
| `env.block` | checkpoint/block-like context reads where valid |
| `control.conditional` | Psy `if condition { ... } else { ... };` statements |
| `control.bounded_loop` | static Psy `for i in 0u32..Nu32` loops |
| `data.fixed_array` | Psy `[T; N]` value types, literals, and index expressions |
| `data.struct` | Psy `struct` definitions, `new Struct { ... }` literals, and field access |
| `crypto.hash` | Psy hash intrinsics/prelude |
| `assertions.check` | Psy `assert(...)` and `assert_eq(...)` statements in generated methods |
| `zk.circuit` | every contract method lowers to a circuit definition |
| `zk.proof` | proof/deploy/test integration track; not a generic runtime effect |

The ZK capabilities are target-family capabilities. They should not leak into
portable business logic unless the user explicitly writes a proof-oriented
contract.

## Generated Package Sketch

Current Counter spike output layout:

```text
build/psy/
  Counter.psy
  dargo-counter/
    Dargo.toml
    src/main.psy
    target/proof_forge_counter.json
    target/Counter.json
    target/counter-execute.log
    target/proof-forge-artifact.json
```

Example generated shape:

```text
#[contract]
#[derive(Storage)]
pub struct Counter {
    pub count: Felt,
}

impl CounterRef {
    #[contract_method]
    pub fn initialize() {
        let c = CounterRef::new(ContractMetadata::current());
        c.count = 0;
    }

    #[contract_method]
    pub fn increment() {
        let c = CounterRef::new(ContractMetadata::current());
        let n: Felt = c.count.get();
        c.count = n + 1;
    }

    #[contract_method]
    pub fn get() -> Felt {
        let c = CounterRef::new(ContractMetadata::current());
        return c.count.get();
    }
}
```

This is intentionally source-like and reviewable. The current implementation
lowers the portable IR to a `ProofForge.Compiler.Psy.Module` AST and renders
it through `ProofForge.Compiler.Psy.Printer.module`, exposed through:

```sh
lake env proof-forge emit --target psy-dpn --fixture counter --format psy -o build/psy/Counter.psy
```

The checked-in golden source is `Examples/Psy/Counter.golden.psy`.

Current ContextProbe spike output layout:

```text
build/psy/
  ContextProbe.psy
  dargo-context/
    Dargo.toml
    src/main.psy
    target/proof_forge_context.json
    target/ContextProbe.json
    target/context-execute.log
    target/proof-forge-artifact.json
```

`ContextProbe` is the first non-Counter fixture. It follows upstream
`tests/ctx_test.psy` by lowering entrypoint parameters plus
`get_user_id()`, `get_contract_id()`, and `get_checkpoint_id()` into Psy
source. The contract includes a `_proof_forge_marker` storage field because
Dargo v0.1.0 panics on an empty `#[contract] #[derive(Storage)]` struct.

Current HashProbe output layout:

```text
build/psy/
  HashProbe.psy
  dargo-hash/
    Dargo.toml
    src/main.psy
    target/proof_forge_hash.json
    target/HashProbe.json
    target/hash-execute.log
    target/proof-forge-artifact.json
```

`HashProbe` follows upstream `tests/hash_test.psy` and
`tests/hash_two_to_one_test.psy`. The portable IR now has a `Hash` value type,
four-Felt hash literals, typed `let` bindings, `hash`, and `hash_two_to_one`
expressions. Psy sourcegen lowers those nodes to `Hash`, `[a, b, c, d]`,
`hash(data)`, and `hash_two_to_one(left, right)`.

Current MapProbe output layout:

```text
build/psy/
  MapProbe.psy
  dargo-map/
    Dargo.toml
    src/main.psy
    target/proof_forge_map.json
    target/MapProbe.json
    target/map-execute.log
    target/proof-forge-artifact.json
```

`MapProbe` follows upstream `tests/map_test.psy`,
`tests/map_edge_semantics_test.psy`,
`tests/map_chain_insert_set_get_test.psy`, and
`tests/map_adjacent_fields_preserve_test.psy`. The portable IR now has
fixed-capacity map state and map effects for `contains`, `get`, `insert`, and
`set`, including expression-position `insert`/`set` returns, plus generic
storage paths whose first segment is a map key. Psy sourcegen lowers the
supported storage shape to `Map<Hash, Hash, Nu32>` and emits
`c.map.contains(key)`, `c.map.get(key)`, `c.map.insert(key, value)`,
`c.map.set(key, value)`, and direct map-path `get`/`set` lowering. The current
Psy v0 lowerer deliberately accepts only `Map<Hash, Hash, N>` and rejects other
map key/value shapes or malformed map paths with explicit diagnostics.

Current AssertProbe output layout:

```text
build/psy/
  AssertProbe.psy
  dargo-assert/
    Dargo.toml
    src/main.psy
    target/proof_forge_assert.json
    target/AssertProbe.json
    target/assert-execute.log
    target/proof-forge-artifact.json
```

`AssertProbe` follows upstream precompile and test idioms that use
`assert(condition, "message")` and `assert_eq(left, right, "message")`. The
portable IR now has statement-level assertion nodes, and Psy sourcegen lowers
them into contract method bodies rather than only generated tests.

Current LoopProbe output layout:

```text
build/psy/
  LoopProbe.psy
  dargo-loop/
    Dargo.toml
    src/main.psy
    target/proof_forge_loop.json
    target/LoopProbe.json
    target/loop-execute.log
    target/proof-forge-artifact.json
```

`LoopProbe` follows upstream Psy loop idioms such as
`for _i in 0u32..3u32`. The portable IR now has a static `boundedFor`
statement node, and Psy sourcegen lowers it to a bounded `for` block while EVM
IR v0 rejects it explicitly.

Current ArrayProbe output layout:

```text
build/psy/
  ArrayProbe.psy
  dargo-array/
    Dargo.toml
    src/main.psy
    target/proof_forge_array.json
    target/ArrayProbe.json
    target/array-execute.log
    target/proof-forge-artifact.json
```

`ArrayProbe` follows upstream Psy array idioms from `tests/array_test.psy`,
`tests/parameter_passing_test.psy`, and storage reference tests: fixed array
types such as `[Felt; 3]`, literals such as `[10, 20, 30]`, index reads such
as `xs[0]`, fixed-array `assert_eq`/`==`/`!=` predicates, and fixed storage
arrays such as `pub values: [Felt; 3]`. Storage array reads lower through
`.get()` when used as arithmetic values, while writes use Psy's index
assignment sugar: `c.values[0] = 7`.

Current StructProbe output layout:

```text
build/psy/
  StructProbe.psy
  dargo-struct/
    Dargo.toml
    src/main.psy
    target/proof_forge_struct.json
    target/StructProbe.json
    target/struct-execute.log
    target/proof-forge-artifact.json
```

`StructProbe` follows upstream Psy struct and storage reference idioms from
`tests/struct_field_test.psy`, `tests/ref_struct_eq_assign_test.psy`, and
precompile storage structs. The portable IR now carries struct declarations,
struct value types, `new Struct { ... }` literals, field access expressions,
and scalar storage struct field read/write effects. Storage struct field reads
lower through `.get()` when used as arithmetic values, while writes use Psy's
field assignment sugar: `c.current.y = 19`.

Current StructArrayProbe output layout:

```text
build/psy/
  StructArrayProbe.psy
  dargo-struct-array/
    Dargo.toml
    src/main.psy
    target/proof_forge_struct_array.json
    target/StructArrayProbe.json
    target/struct-array-execute.log
    target/proof-forge-artifact.json
```

`StructArrayProbe` combines the struct and fixed-array slices using upstream
idioms from `tests/array_test.psy`, `tests/array_ref_struct_index_test.psy`,
and `tests/array_ref_struct_bulk_assign_test.psy`. It covers local
`[Person; 2]` struct arrays, field access through `people[0].age`, storage
arrays of structs, whole-element writes such as `c.people[0] = new Person {
... }`, and field writes such as `c.people[1].score = 92`.

Current AbiAggregateProbe output layout:

```text
build/psy/
  AbiAggregateProbe.psy
  dargo-abi-aggregate/
    Dargo.toml
    src/main.psy
    target/proof_forge_abi_aggregate.json
    target/AbiAggregateProbe.json
    target/abi-aggregate-execute.log
    target/proof-forge-artifact.json
```

`AbiAggregateProbe` follows upstream ABI and precompile idioms from
`tests/storage_test.psy` and `psy-precompiles/mining_rewards/src/main.psy`.
It covers contract methods whose public ABI takes a struct parameter, takes a
fixed-array parameter, and returns a struct value. Dargo's execute CLI accepts
these aggregate values as flattened Felt input/output vectors, so the smoke
checks `sum_pair(7,8) -> [15]`, `sum_array(1,2,3) -> [6]`, and
`make_pair(9,4) -> [9,4]`.

Current NestedAggregateProbe output layout:

```text
build/psy/
  NestedAggregateProbe.psy
  dargo-nested-aggregate/
    Dargo.toml
    src/main.psy
    target/proof_forge_nested_aggregate.json
    target/NestedAggregateProbe.json
    target/nested-aggregate-execute.log
    target/proof-forge-artifact.json
```

`NestedAggregateProbe` follows upstream mutation idioms from
`tests/array_test.psy` and `tests/struct_test.psy`. It adds mutable local
bindings and assignment statements to the portable IR, then lowers nested
field/index targets such as `families[1].children[0].age = 31`. The fixture
uses an array of `Family` structs, each with a fixed array of `Member` structs,
and verifies the updated nested field through Dargo execution.

Current StorageNestedAggregateProbe output layout:

```text
build/psy/
  StorageNestedAggregateProbe.psy
  dargo-storage-nested-aggregate/
    Dargo.toml
    src/main.psy
    target/proof_forge_storage_nested_aggregate.json
    target/StorageNestedAggregateProbe.json
    target/storage-nested-aggregate-execute.log
    target/proof-forge-artifact.json
```

`StorageNestedAggregateProbe` extends the portable IR with generic storage path
segments. It lowers nested storage references such as `c.person.profile.age`
and `c.people[1].profile.age`, and requires struct-to-struct storage traversal
to use Psy's `#[ref]` field marker. This keeps the IR explicit about the
difference between value fields and nested storage references. It also covers
storage-reference compound assignment effects by lowering scalar storage refs
such as `c.total += 3` and nested storage paths such as
`c.person.profile.age += 2` to native Psy assignment operators. Native U32
fields inside storage structs are also covered: `Profile.rank` lowers to
`pub rank: u32`, path writes lower to `c.person.profile.rank = 9u32`, and path
compound assignment lowers to Psy's native `+=` / `-=` storage-reference idiom.

`ExpressionPredicateProbe` follows upstream predicate idioms from
`tests/opcode_test.psy`, `tests/assert_test.psy`, and the token/deposit-tree
precompiles. It covers `==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `||`, and `!`
inside assertion predicates and boolean local bindings.

`ArithmeticProbe` follows upstream arithmetic idioms from
`tests/u32_test.psy`, `psy-precompiles/deposit_tree/src/main.psy`, and the
token precompiles. It covers portable IR subtraction and multiplication for
Felt-backed `U64` values, and deliberately includes nested arithmetic so the
source generator must preserve Psy precedence with parentheses. Division,
modulo, exponentiation, cast-heavy `u32` arithmetic, and compound assignment
coverage live in `U32ArithmeticProbe`.

`U32ArithmeticProbe` follows the executable shape of upstream
`tests/u32_test.psy`. It adds first-class portable `U32` values, `Nu32`
literals, `u32` ABI parameters, `/`, `%`, `**`, mutable assignment, and casts
such as `z as bool` and `bb as Felt`. It also exercises first-class portable
compound assignment statements for `+=`, `-=`, `*=`, `/=`, and `%=` on mutable
`U32` locals. Dargo execution validates the same `a=2`, `b=3` scenario and
returns `result_vm: [1]`. Richer cast matrices and U32 storage compound
assignment coverage is split across dedicated storage probes:
`U32StorageScalarProbe` covers native scalar `u32` storage and
`U32StorageArrayProbe` covers the current storage-array slice.

`BitwiseProbe` follows upstream bitwise idioms from `tests/opcode_test.psy`,
`tests/storage_u32_assign_ops_test.psy`, and the Merkle path logic in
`psy-precompiles/mining_rewards/src/main.psy`. It adds portable IR nodes for
`&`, `|`, `^`, `<<`, and `>>`, validates same-width numeric operands, and
lowers both Felt-backed `U64` and `U32` operations to native Psy operators.
Dargo execution validates `result_vm: [16]` for the combined Felt/U32 probe.
The same probe now exercises first-class portable compound assignment
statements for `|=`, `&=`, `^=`, `<<=`, and `>>=` on mutable Felt-backed `U64`
and `U32` locals. Storage-reference compound assignment is covered by
`StorageNestedAggregateProbe`.

`U32HashPackingProbe` follows the hash limb representation used by
`psy-precompiles/deposit_tree/src/main.psy` and related Merkle-tree code. It
adds a dynamic portable IR `Hash` constructor for four Felt limbs, then uses it
to pack `[u32; 8]` local arrays and eight U32 ABI parameters into Psy `Hash`
values with the same `lo + hi * 2^32` shape used upstream. Dargo execution
validates deterministic four-Felt outputs for both literal and ABI limb
packing. Current `psyup` 0.1.0 Dargo rejects direct `[u32; N]` contract storage
arrays with an `ArrayRef<u32, N>` type mismatch, so ProofForge lowers portable
U32 storage arrays as `[Felt; N]` storage plus explicit casts at reads and
writes.

`U32StorageScalarProbe` validates native Psy scalar `u32` storage. Portable
`StateDecl.kind = .scalar` with `type = .u32` lowers to `pub value: u32`.
Writes lower as native U32 assignments, reads lower through `.get()` into U32
locals, and scalar storage compound assignment lowers to Psy `+=` for U32
values. Dargo execution validates `result_vm: [12]` for the fixture.

`BoolStorageScalarProbe` validates native Psy scalar `bool` storage. Portable
`StateDecl.kind = .scalar` with `type = .bool` lowers to `pub flag: bool`.
Writes lower as native Bool assignments, reads lower through `.get()` into Bool
locals, and return casts use the same `bool as Felt` idiom already exercised by
the U32 arithmetic cast fixture. Psy std exposes `Storage` for `bool` by
casting the stored Felt back to Bool at reads, and Dargo execution validates
`result_vm: [1]` for the fixture.

`BoolStorageArrayProbe` validates native Psy fixed arrays and storage arrays
whose element type is `bool`. Portable `[Bool; N]` values lower to `[bool; N]`
literal/index expressions, and `StateDecl.kind = .array N` with `type = .bool`
lowers to `pub flags: [bool; N]`. Indexed storage reads/writes lower without
extra casts, generic storage paths use the same indexed syntax, and explicit
`bool as Felt` casts are used when returning summed boolean values. Dargo
execution validates `result_vm: [2]` for both the local fixed-array entrypoint
and the storage lifecycle fixture.

`HashStorageProbe` validates native Psy `Hash` storage. Portable scalar Hash
state lowers to `pub root: Hash`, and portable Hash storage arrays lower to
`pub roots: [Hash; N]`. Scalar storage read/write lowers through `.get()` and
native assignment, while indexed storage-array effects and generic storage-path
read/write lower to the same `c.roots[index]` reference idiom. Dargo execution
validates `result_vm: [5, 6, 7, 8]` for scalar Hash storage and
`result_vm: [55, 66, 77, 88]` for indexed Hash storage arrays.

`U32StorageArrayProbe` validates that Felt-backed storage idiom. Portable
`StateDecl.kind = .array N` with `type = .u32` lowers to `pub limbs: [Felt; N]`.
Writes lower as `u32 as Felt`, reads lower as `.get() as u32`, and generic
storage-path read/write effects use the same representation. Storage-path
compound assignment over those U32 array elements lowers as an explicit
read/update/write sequence: read the Felt slot with `.get() as u32`, apply the
typed U32 operator, then cast the result back to Felt for storage. Native U32
scalar storage and storage struct paths use Psy's native `u32` storage
representation instead; direct `[u32; N]` contract storage arrays remain
avoided until Dargo accepts that shape. Dargo execution validates
`result_vm: [28]` for the fixture.

`ConditionalProbe` follows upstream conditional idioms from
`tests/conditional_assert_test.psy`, `tests/for_if_test.psy`, and
`psy-precompiles/faucet/src/main.psy`. It lowers portable IR
`Statement.ifElse` to Psy `if condition { ... } else { ... };`, validates that
the condition is Bool, keeps branch-local bindings scoped to their branch, and
uses Dargo execution to prove that both then and else paths are represented in
the generated circuit. It does not yet add else-if syntax sugar; nested
conditionals can model that shape when needed.

## Smoke Test Strategy

Experimental smoke does not require a live Psy network.

Preferred first smoke:

1. Generate `.psy` source.
2. Compare it against `Examples/Psy/Counter.golden.psy`.
3. Run `dargo test --file build/psy/Counter.psy`.
4. Generate a temporary Dargo package.
5. Run `dargo compile --contract-name Counter --method-names initialize increment get`.
6. Verify `target/proof_forge_counter.json` is non-empty.
7. Run `dargo execute --contract-name Counter --method-names initialize increment increment get`.
8. Verify the execution log contains `result_vm: [2]`.
9. Run `dargo generate-abi --contract-name Counter --output-dir target --pretty`.
10. Verify `target/Counter.json` is non-empty.
11. Restore the deploy-oriented compile artifact with
    `dargo compile --contract-name Counter --method-names initialize increment get`
    because `dargo execute` writes method-sequence circuits for the local
    execution trace.
12. Emit and validate `target/proof-forge-deploy.json`, a ProofForge deploy
    manifest containing the compiled DPN method ids, ABI summary, deployer,
    state-tree height, source/circuit/ABI hashes, and upstream genesis JSON
    status.
13. Emit `target/proof-forge-artifact.json` with source, circuit JSON, ABI,
    deploy manifest, and execute-log hashes.

This has been run locally with `psyup install 0.1.0` on macOS arm64. The
Counter smoke produced `build/psy/dargo-counter/target/proof_forge_counter.json` and
`build/psy/dargo-counter/target/counter-execute.log`, plus ABI output at
`build/psy/dargo-counter/target/Counter.json`, a ProofForge deploy manifest at
`build/psy/dargo-counter/target/proof-forge-deploy.json`, and metadata at
`build/psy/dargo-counter/target/proof-forge-artifact.json`.

The ProofForge deploy manifest is not Psy's upstream compressed genesis deploy
JSON. The upstream `psy-dargo-cli/examples/gen_deploy_json.rs` sample builds
that form through Rust workspace internals and the current released `dargo`
does not expose it as a CLI subcommand. Until that boundary is stable, the
manifest records reproducible deploy inputs and the upstream conversion gap
explicitly.

Every Dargo-backed Psy smoke script now follows the same deploy-manifest step:
after behavior validation and ABI generation it restores the deploy-oriented
`dargo compile` artifact, emits `target/proof-forge-deploy.json`, validates the
manifest, and records it in `target/proof-forge-artifact.json`. The diagnostic
smoke is intentionally excluded because it validates pre-codegen rejection
paths rather than Dargo artifacts.

The same validation shape is implemented for `ContextProbe`:

```sh
scripts/psy/context-smoke.sh
```

It verifies `result_vm: [15]` for `sum_context(2,3)` under Dargo's local
execution session and emits `build/psy/dargo-context/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `ExpressionPredicateProbe`:

```sh
scripts/psy/expression-predicate-smoke.sh
```

It verifies predicate expression lowering under Dargo local execution:

- `predicate_sum`: `result_vm: [16]`

The script emits and validates
`build/psy/dargo-expression-predicate/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `ArithmeticProbe`:

```sh
scripts/psy/arithmetic-smoke.sh
```

It verifies arithmetic expression lowering under Dargo local execution:

- `arithmetic_mix`: `result_vm: [60]`

The script emits and validates
`build/psy/dargo-arithmetic/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `U32ArithmeticProbe`:

```sh
scripts/psy/u32-arithmetic-smoke.sh
```

It verifies U32 expression lowering under Dargo local execution:

- `u32_arithmetic(2,3)`: `result_vm: [1]`

The script emits and validates
`build/psy/dargo-u32-arithmetic/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `BitwiseProbe`:

```sh
scripts/psy/bitwise-smoke.sh
```

It verifies Felt and U32 bitwise expression lowering under Dargo local
execution:

- `bitwise_mix`: `result_vm: [16]`

The script emits and validates
`build/psy/dargo-bitwise/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `U32HashPackingProbe`:

```sh
scripts/psy/u32-hash-packing-smoke.sh
```

It verifies U32 limb packing and dynamic Hash construction under Dargo local
execution:

- `pack_literal`: `result_vm: [8589934593, 17179869187, 25769803781, 34359738375]`
- `pack_params(9..16)`: `result_vm: [42949672969, 51539607563, 60129542157, 68719476751]`

The script emits and validates
`build/psy/dargo-u32-hash-packing/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `U32StorageScalarProbe`:

```sh
scripts/psy/u32-storage-scalar-smoke.sh
```

It verifies native U32 scalar storage lowering under Dargo local execution:

- `storage_lifecycle`: `result_vm: [12]`

The script emits and validates
`build/psy/dargo-u32-storage-scalar/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `BoolStorageScalarProbe`:

```sh
scripts/psy/bool-storage-scalar-smoke.sh
```

It verifies native Bool scalar storage lowering under Dargo local execution:

- `storage_lifecycle`: `result_vm: [1]`

The script emits and validates
`build/psy/dargo-bool-storage-scalar/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `BoolStorageArrayProbe`:

```sh
scripts/psy/bool-storage-array-smoke.sh
```

It verifies native Bool fixed-array and storage-array lowering under Dargo
local execution:

- `local_flags_sum`: `result_vm: [2]`
- `storage_lifecycle`: `result_vm: [2]`

The script emits and validates
`build/psy/dargo-bool-storage-array/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `U32StorageArrayProbe`:

```sh
scripts/psy/u32-storage-array-smoke.sh
```

It verifies Felt-backed U32 storage-array lowering and path compound assignment
under Dargo local execution:

- `storage_lifecycle`: `result_vm: [28]`

The script emits and validates
`build/psy/dargo-u32-storage-array/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `ConditionalProbe`:

```sh
scripts/psy/conditional-smoke.sh
```

It verifies statement-level conditional lowering under Dargo local execution:

- `conditional_lifecycle`: `result_vm: [10]`

The script emits and validates
`build/psy/dargo-conditional/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `HashProbe`:

```sh
scripts/psy/hash-smoke.sh
```

It verifies both upstream hash idioms under Dargo local execution:

- `poseidon_hash`: `result_vm: [16490263548047147048, 1812405431586978162, 16859324901997577793, 7123796541406703579]`
- `poseidon_pair_hash`: `result_vm: [15064728126975588673, 10314245681893968020, 11300930272442645327, 2830815762300183090]`

The script emits and validates
`build/psy/dargo-hash/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `HashStorageProbe`:

```sh
scripts/psy/hash-storage-smoke.sh
```

It verifies native Hash scalar and storage-array lowering under Dargo local
execution:

- `scalar_lifecycle`: `result_vm: [5, 6, 7, 8]`
- `array_lifecycle`: `result_vm: [55, 66, 77, 88]`

The script emits and validates
`build/psy/dargo-hash-storage/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `MapProbe`:

```sh
scripts/psy/map-smoke.sh
```

It verifies fixed-capacity Psy map storage under Dargo local execution:

- `map_lifecycle`: `result_vm: [55, 66, 77, 88]`
- `path_lifecycle`: `result_vm: [77, 88, 99, 111]`
- `set_return_lifecycle`: `result_vm: [31, 32, 33, 34]`
- `insert_return_lifecycle`: `result_vm: [5, 6, 7, 8]`

The script emits and validates
`build/psy/dargo-map/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `AssertProbe`:

```sh
scripts/psy/assert-smoke.sh
```

It verifies IR-level assertions under Dargo local execution:

- `checked_sum(5,7)`: `result_vm: [12]`

The script emits and validates
`build/psy/dargo-assert/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `LoopProbe`:

```sh
scripts/psy/loop-smoke.sh
```

It verifies static bounded-loop lowering under Dargo local execution:

- `count_to_three`: `result_vm: [3]`

The script emits and validates
`build/psy/dargo-loop/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `ArrayProbe`:

```sh
scripts/psy/array-smoke.sh
```

It verifies fixed-array value, fixed-array equality, and storage lowering under
Dargo local execution:

- `sum_literal`: `result_vm: [60]`
- `storage_lifecycle`: `result_vm: [31]`
- `array_predicates`: `result_vm: [1]`

The script emits and validates
`build/psy/dargo-array/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `StructProbe`:

```sh
scripts/psy/struct-smoke.sh
```

It verifies struct value and scalar storage struct lowering under Dargo local
execution:

- `local_sum`: `result_vm: [30]`
- `storage_lifecycle`: `result_vm: [26]`

The script emits and validates
`build/psy/dargo-struct/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `StructArrayProbe`:

```sh
scripts/psy/struct-array-smoke.sh
```

It verifies struct-array value and storage lowering under Dargo local execution:

- `local_struct_array_sum`: `result_vm: [100]`
- `storage_struct_array_lifecycle`: `result_vm: [102]`

The script emits and validates
`build/psy/dargo-struct-array/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `AbiAggregateProbe`:

```sh
scripts/psy/abi-aggregate-smoke.sh
```

It verifies ABI-facing aggregate parameter and return lowering under Dargo
local execution:

- `sum_pair(7,8)`: `result_vm: [15]`
- `sum_array(1,2,3)`: `result_vm: [6]`
- `make_pair(9,4)`: `result_vm: [9, 4]`

The script emits and validates
`build/psy/dargo-abi-aggregate/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `NestedAggregateProbe`:

```sh
scripts/psy/nested-aggregate-smoke.sh
```

It verifies local nested aggregate mutation under Dargo local execution:

- `nested_update_sum`: `result_vm: [51]`

The script emits and validates
`build/psy/dargo-nested-aggregate/target/proof-forge-artifact.json`.

The same validation shape is also implemented for
`StorageNestedAggregateProbe`:

```sh
scripts/psy/storage-nested-aggregate-smoke.sh
```

It verifies storage-backed nested aggregate updates and storage-reference
compound assignments, including native U32 struct storage paths, under Dargo
local execution:

- `storage_nested_lifecycle`: `result_vm: [252]`

The script emits and validates
`build/psy/dargo-storage-nested-aggregate/target/proof-forge-artifact.json`.

The same validation shape is also implemented for `GenericEntrypointProbe`:

```sh
scripts/psy/generic-entrypoint-smoke.sh
```

This fixture is intentionally not special-cased in `testBody`. It proves that
otherwise valid Psy IR modules receive a generic generated test that instantiates
`<Module>Ref` instead of failing source generation. Dargo local execution
validates:

- `answer`: `result_vm: [42]`

The script emits and validates
`build/psy/dargo-generic-entrypoint/target/proof-forge-artifact.json`.

All Psy smoke scripts run
`scripts/psy/validate-artifact-metadata.py` after metadata generation. The
validator checks schema version, target id, target family, artifact kind,
fixture id, non-empty capabilities, artifact paths, byte sizes, SHA-256 hashes,
validation flags, Dargo package source parity, Dargo package manifest shape,
and expected execution results inside the execute log.

The diagnostic smoke is separate from Dargo smokes because it validates source
generation rejection paths instead of supported Psy programs:

```sh
scripts/psy/diagnostic-smoke.sh
```

It currently asserts forty-eight explicit diagnostics for malformed or
unsupported Psy IR shapes, including invalid Psy identifiers, duplicate
declarations, reserved names, empty contract state rejected before Dargo's
`#[derive(Storage)]` boundary, invalid storage paths, expression/body type
mismatches, malformed equality, malformed comparison, and malformed Hash value
construction, unsupported Unit storage arrays, malformed arithmetic,
unsupported casts, malformed bitwise/shift expressions, malformed boolean
operators, malformed compound assignment statements, malformed storage compound
assignment effects, malformed if conditions, and branch-local escape.

The coverage manifest gate keeps the constructor-level backend contract in
sync with the portable IR:

```sh
scripts/psy/check-ir-coverage-manifest.py
```

It parses `ProofForge/IR/Contract.lean` and requires `Tests/PsyCoverage.tsv` to
contain one status/evidence row for every `ValueType`, `StateKind`, `Literal`,
`ContextField`, `AssignOp`, `Expr`, `Effect`, `StoragePathSegment`, and
`Statement` constructor. This is a structural guard against silent Psy backend
omissions when the portable IR grows; behavior still needs golden and Dargo
coverage in the fixture smokes.

Observed behavior: `dargo execute` compiles the workspace, creates a local
session with a registered user and deployed contract, then executes the method
sequence against the same session. This is not a live network, but it is closer
to an Ethereum-style local execution smoke than a pure compiler check.

Second smoke:

1. Compare high-level Counter behavior with the EVM shared scenario.
2. Extend the Counter deploy manifest into upstream genesis JSON and local
   node/prover deployment once the tooling boundary is stable.

Deployment smoke:

1. Done: emit a ProofForge deploy manifest for every Dargo-backed Psy smoke
   compile output.
2. Convert `DPNFunctionCircuitDefinition[]` to upstream compressed genesis
   deploy JSON with Psy tooling.
3. Run against a local Psy node/prover stack when the toolchain is available.

## Implementation Plan

### Phase A: Documentation and Target Registry

- Add `psy-dpn` to target registry docs.
- Add artifact kind `psyCircuitJson`.
- Add ZK circuit sourcegen target family.
- Record `dargo` as the required external tool.

### Phase B: Source Generator Spike

- Done: generate one Counter `.psy` file from a hand-built portable IR fixture.
- Done: add a golden Psy source fixture.
- Done: add `scripts/psy/counter-smoke.sh` to generate `Dargo.toml`, call
  `dargo test --file`, call `dargo compile`, verify the JSON artifact, call
  `dargo execute`, assert the local execution result, and call
  `dargo generate-abi`.
- Done: add `ExpressionPredicateProbe` with equality, inequality, ordering,
  boolean not/and/or, and assertion predicate lowering aligned with upstream
  Psy operator idioms.
- Done: add `scripts/psy/expression-predicate-smoke.sh` with the same Dargo
  validation shape.
- Done: add `ArithmeticProbe` with subtraction, multiplication, and nested
  arithmetic precedence aligned with upstream arithmetic idioms.
- Done: add `scripts/psy/arithmetic-smoke.sh` with the same Dargo validation
  shape.
- Done: add first-class `U32` values, `Nu32` literals, division, modulo,
  exponentiation, and casts for the upstream `u32_test.psy` arithmetic shape.
- Done: add `U32ArithmeticProbe` and `scripts/psy/u32-arithmetic-smoke.sh` with
  the same Dargo validation shape.
- Done: add portable IR bitwise and shift expressions, `BitwiseProbe`, and
  `scripts/psy/bitwise-smoke.sh` with the same Dargo validation shape.
- Done: add first-class portable compound assignment statements for mutable
  local/aggregate assignment targets, with Psy lowering for `+=`, `-=`, `*=`,
  `/=`, `%=`, `|=`, `&=`, `^=`, `<<=`, and `>>=`.
- Done: add dynamic Hash value construction plus `U32HashPackingProbe` and
  `scripts/psy/u32-hash-packing-smoke.sh` for `[u32; 8]` literal and ABI limb
  packing into Psy `Hash` values.
- Done: add `U32StorageScalarProbe` and
  `scripts/psy/u32-storage-scalar-smoke.sh` for native scalar `u32` storage
  read/write plus scalar storage `+=` validation.
- Done: add `BoolStorageScalarProbe` and
  `scripts/psy/bool-storage-scalar-smoke.sh` for native scalar `bool` storage
  read/write plus `bool as Felt` return-cast validation.
- Done: add `BoolStorageArrayProbe` and
  `scripts/psy/bool-storage-array-smoke.sh` for native `[bool; N]` fixed-array
  literals/indexes, storage-array read/write, storage-path read/write, and
  `bool as Felt` cast validation.
- Done: add `HashStorageProbe` and `scripts/psy/hash-storage-smoke.sh` for
  native scalar `Hash` storage, `[Hash; N]` storage arrays, storage-path
  read/write, and Dargo compile/execute validation.
- Done: add `U32StorageArrayProbe` and
  `scripts/psy/u32-storage-array-smoke.sh` using Felt-backed storage arrays
  plus U32 read/write casts and storage-path compound assignment rewrites after
  Dargo validation showed current `psyup` 0.1.0 rejects direct `[u32; N]`
  contract storage arrays with an `ArrayRef<u32, N>` type mismatch.
- Done: add `ConditionalProbe` with statement-level `if/else` lowering aligned
  with upstream conditional idioms.
- Done: add `scripts/psy/conditional-smoke.sh` with the same Dargo validation
  shape.
- Done: add `ContextProbe` as the first non-Counter Psy fixture with parameter
  lowering and context reads.
- Done: add `scripts/psy/context-smoke.sh` with the same Dargo validation shape.
- Done: add `HashProbe` with `Hash`, typed `let` bindings, `hash`, and
  `hash_two_to_one` lowering aligned with upstream Psy tests.
- Done: add `scripts/psy/hash-smoke.sh` with the same Dargo validation shape.
- Done: emit `proof-forge-artifact.json` metadata from all Psy smoke scripts.
- Done: validate Psy artifact metadata and record used capabilities from the
  smoke scripts.
- Done: add `MapProbe` with fixed-capacity `Map<Hash, Hash, N>` storage and
  `contains`, `get`, `insert`, and `set` lowering aligned with upstream Psy
  map tests, including expression-position `set` return values.
- Done: add `scripts/psy/map-smoke.sh` with the same Dargo validation shape.
- Done: add generic map storage path read/write lowering for
  `Map<Hash, Hash, N>` through first-class `mapKey` path segments.
- Done: add `AssertProbe` with IR-level `assert` and `assert_eq` statements
  aligned with upstream Psy assertion idioms.
- Done: add `scripts/psy/assert-smoke.sh` with the same Dargo validation shape.
- Done: add `LoopProbe` with static `boundedFor` lowering aligned with upstream
  Psy fixed `for` loop idioms.
- Done: add `scripts/psy/loop-smoke.sh` with the same Dargo validation shape.
- Done: add `ArrayProbe` with `[Felt; N]` local array literals, index reads,
  and fixed storage array index read/write lowering aligned with upstream Psy
  array and storage reference idioms.
- Done: extend `ArrayProbe` with fixed-array `assert_eq`, equality, and
  inequality predicates validated through Dargo execution.
- Done: add `scripts/psy/array-smoke.sh` with the same Dargo validation shape.
- Done: add `StructProbe` with struct declarations, struct literals, field
  access, and scalar storage struct field read/write lowering aligned with
  upstream Psy struct and storage reference idioms.
- Done: add `scripts/psy/struct-smoke.sh` with the same Dargo validation shape.
- Done: add `StructArrayProbe` with fixed arrays of struct values and storage
  arrays of structs aligned with upstream Psy array/struct reference idioms.
- Done: add `scripts/psy/struct-array-smoke.sh` with the same Dargo validation
  shape.
- Done: add entrypoint ABI type validation for Unit rejection, declared struct
  lookup, and non-zero fixed-array lengths.
- Done: add `AbiAggregateProbe` with struct parameters, fixed-array parameters,
  and struct return values aligned with upstream Psy ABI/precompile idioms.
- Done: add `scripts/psy/abi-aggregate-smoke.sh` with the same Dargo
  validation shape.
- Done: add `scripts/psy/diagnostic-smoke.sh` and
  `Tests/PsyDiagnostics.lean` to lock down explicit unsupported-shape
  diagnostics before source generation.
- Done: add mutable local bindings and assignment statements to the portable
  IR, with Psy lowering and explicit EVM v0 rejection diagnostics.
- Done: add `NestedAggregateProbe` with nested local struct/fixed-array
  mutation aligned with upstream Psy array/struct mutation idioms.
- Done: add `scripts/psy/nested-aggregate-smoke.sh` with the same Dargo
  validation shape.
- Done: validate the Dargo portion with the `psyup` v0.1.0 macOS arm64
  toolchain.
- Done: add generic storage path read/write effects, storage `#[ref]` field
  metadata, and `StorageNestedAggregateProbe` for scalar struct and storage
  array nested updates.
- Done: add storage-reference compound assignment effects for scalar storage
  and generic storage paths, with Psy lowering to native assignment operators.
- Done: add native U32 storage struct field path writes, reads, and compound
  assignment coverage through `StorageNestedAggregateProbe`.
- Done: add `scripts/psy/storage-nested-aggregate-smoke.sh` with the same
  Dargo validation shape.
- Done: add `proof-forge-deploy.json` generation and validation for every
  Dargo-backed Psy smoke, and record the deploy manifest in
  `proof-forge-artifact.json`.
- Done: add a generic generated test fallback for valid non-whitelisted Psy IR
  modules, plus `GenericEntrypointProbe` and
  `scripts/psy/generic-entrypoint-smoke.sh` to prove the fallback with Dargo.
- Remaining: move to upstream genesis deploy JSON/live node research.

### Phase B2: Two-Stage Lowering via Psy AST

The initial spike lowered portable IR directly to `.psy` source strings inside
`Backend.Psy.IR.renderModule`. This worked but mixed IR validation, shape
resolution, and source formatting in one pass, and left no extension point for
target-side AST-level passes. Phase B2 introduces the two-stage lowering that
the EVM and Wasm-family backends already use.

- Done: add `ProofForge.Compiler.Psy.AST` — a target-side surface AST
  (`Module`, `StructDecl`, `StateDecl`, `Method`, `Stmt`, `Expr`, `Effect`,
  `StorageTarget`, `StoragePathSegment`, `BinaryOp`, `UnaryOp`, `AssignOp`,
  `Literal`, `TypeName`, `ContextField`, `Visibility`) mirroring the `.psy`
  source forms at the granularity the printer needs. It does not model the
  upstream `psy-ast::Program` interner/arena/checker layers.
- Done: add `ProofForge.Compiler.Psy.Printer` — a pure structural renderer
  (`module : Psy.Module → String`) that emits valid `.psy` source text with no
  IR resolution or validation logic.
- Done: refactor `Backend.Psy.IR.renderModule` to lower portable IR →
  `Psy.Module` AST (`buildModule`) and render via `Printer.module`. All
  validation (capabilities, identifiers, structs, entrypoints, state, bodies)
  and shape resolution (storage targets, felt-backed U32 rewrites, map-key
  special cases, path-type-aware casts) stay on the IR-lowering side; the
  printer is self-describing.
- Done: register `ProofForge.Compiler.Psy.AST` and
  `ProofForge.Compiler.Psy.Printer` as `lean_lib` roots in `lakefile.lean`,
  matching the `Compiler.Yul.*` and `Compiler.Wasm.*` registration pattern.
- Done: verify all Psy golden sources are byte-identical after the refactor
  (`just psy-golden-sources`), all 55 diagnostic cases pass
  (`just psy-diagnostics`), and the IR coverage manifest is unchanged
  (`just psy-coverage`).
- Remaining: consider upstream `psy-ast` emission if the compiler internals
  stabilize, and use the AST boundary for formatting control or
  canonicalization passes.

### Phase B3: Semantic Plan Layer

Phase B2 left shape resolution (storage target lookup, felt-backed U32
detection, map-key special cases, test body generation) inline in the AST
builder. Phase B3 extracts that into a semantic plan module, mirroring the
EVM `Lower.lean` → `Plan.lean` split.

- Done: add `ProofForge.Backend.Psy.Plan` — the psy-dpn counterpart of
  `ProofForge.Backend.Evm.Plan`. Captures:
  - `StorageLayout`: per-state resolved shape (scalar/structRef/map/array +
    feltBackedU32 flag).
  - `contextOps : Array ContextOp`: context fields actually used (userId/
    contractId/checkpointId), for artifact metadata.
  - `EventPlan`: event name + ordered data field names.
  - `CrosscallPlan`: crosscall target contract ids.
  - `TestPlan`: fixture-shape-detected test function name + body lines
    (moved from `IR.lean testBody/testFunctionName`).
  - `buildModulePlan`: constructs the full `PsyModulePlan` from a portable
    IR `Module` (mirrors EVM `Lower.buildFullModulePlan`).
- Done: refactor `IR.lean buildModule` into `buildModuleWithPlan(module,
  plan)` + `buildModule(module)` wrapper, and `renderModule` to build the
  plan first then lower IR+plan to the AST. Matches EVM
  `IR.lean lowerModuleWithPlan` pattern.
- Done: add 4 `memoryArray*` diagnostic cases (`memoryArrayNew/Length/Get/Set`)
  to `Tests/PsyDiagnostics.lean` (55 → 59 cases), covering the constructors
  introduced in the main merge.
- Done: verify all Psy golden sources are byte-identical, 59 diagnostic cases
  pass, and the IR coverage manifest is unchanged.
- Done: introduce `BuildContext` (module + `StorageLayout`) and context-based
  lookup helpers (`lookupState?`, `requireScalarStateCtx`, `requireMapStateCtx`,
  `requireArrayStateCtx`, `requireStructScalarStateCtx`, `requireStructArrayStateCtx`,
  `isFeltBackedU32ArrayCtx`, `resolveStoragePathTypeCtx`). All AST builder
  functions now accept `BuildContext` and look up storage shapes from the
  pre-resolved `StorageLayout` rather than re-resolving `findState?` inline.
  Validation functions continue to use the raw `Module` since they run before
  plan construction.
- Done: add `ProofForge.Backend.Psy.Metadata` — plan-driven artifact metadata
  (`ArtifactMetadata` with entrypoints, events, context ops, crosscalls,
  capabilities; `buildPlanArtifactMetadata` plan-first construction). Mirrors
  EVM `Metadata.lean`.
- Done: integrate `Metadata.buildPlanArtifactMetadata` into Psy smoke
  scripts so `proof-forge-artifact.json` records the plan-driven metadata.
  `Tests/PsyMetadataExport.lean` renders `ArtifactMetadata` as JSON for each
  fixture; `scripts/psy/write-artifact-metadata.py` accepts `--plan-metadata`
  and merges `moduleName`, `abi.entrypoints`, `events`, `contextOps`,
  `crosscalls`, and `planCapabilities` into the artifact.
- Remaining: consider upstream `psy-ast` emission if the compiler internals stabilize.

### Phase C: Metadata and Scenario Parity

- Done: compare the Psy Counter behavior with the EVM shared Counter scenario.
  The same portable `Counter` IR (`ProofForge.IR.Examples.Counter`) lowers to
  both targets with identical lifecycle semantics:

  | Aspect | EVM (`evm`) | Psy (`psy-dpn`) |
  |---|---|---|
  | State | single storage slot at keccak-derived key | `#[derive(Storage)] pub struct Counter { pub count: Felt }` field |
  | `initialize` | writes `0` to slot | `c.count = 0` |
  | `increment` | reads slot, adds 1, writes back | `let n: Felt = c.count.get(); c.count = n + 1` |
  | `get` | returns slot value | `return c.count.get()` |
  | Smoke result | Foundry `vm.etch` in-memory execution | `dargo execute` in-memory session |
  | Expected final count | `2` (after `initialize`, `increment`, `increment`, `get`) | `result_vm: [2]` (same sequence) |
  | Artifact metadata | `target: evm`, `storage.scalar` capability, 4-byte selectors | `target: psy-dpn`, `planCapabilities` includes `storage.scalar`, entrypoint names (no selectors) |

  The lifecycle is behaviorally equivalent: both targets prove the counter
  reaches `2` after the same method sequence. The only divergence is the
  storage mechanics (EVM 32-byte word vs Psy Felt-backed field) and ABI
  addressing (EVM selectors vs Psy method names).
- Done: decide whether `psy-wasm` adds useful in-memory coverage beyond
  `dargo execute`. Decision: **not for v0**. `dargo execute` already provides
  a complete in-memory execution session with a registered user, deployed
  contract, and method-sequence circuit generation. `psy-wasm` (a browser/Node
  wrapper around the compiler and VM demo) would add browser-based interactive
  testing, but ProofForge's CI gate is headless and artifact-focused; a browser
  wrapper adds no coverage that `dargo execute` + `dargo compile` +
  `dargo generate-abi` do not already provide. Revisit if ProofForge adds a
  browser-facing playground target.
- Done: add a target-specific Counter acceptance note. The Psy Counter
  acceptance is: the portable `Counter` IR lowers to `build/psy/Counter.psy`,
  matches `Examples/Psy/Counter.golden.psy` byte-for-byte, passes
  `dargo test --file`, compiles via `dargo compile` to non-empty DPN circuit
  JSON, executes `initialize → increment → increment → get` via
  `dargo execute` returning `result_vm: [2]`, emits a non-empty ABI via
  `dargo generate-abi`, writes `proof-forge-deploy.json`, and records all
  artifacts in `proof-forge-artifact.json` with plan-driven metadata
  (`moduleName: Counter`, `abi.entrypoints`, `capabilities` including
  `storage.scalar`). `just psy-smoke counter` runs the full gate.

### Phase D: Deployment Research

- Done: produce a ProofForge deploy manifest for every Dargo-backed Psy smoke
  compile output.
- Use Psy's upstream genesis deploy JSON conversion when it is available as a
  stable CLI or vendorable library boundary.
- Document local node/prover setup.
- Decide whether ProofForge should own deployment or only artifact production.

## Open Questions

- Should CI use the `psyup` release tarball, and should we pin v0.1.0 until the
  latest release publishes macOS artifacts?
- Which Psy storage patterns correspond to portable `storage.map` without
  semantic surprises?
- What is the exact artifact schema for contract code, circuit definitions,
  ProofForge deploy manifests, and upstream compressed genesis deploy JSON?
- Should `Felt` become a first-class portable type, or remain target-specific?
- Can ProofForge expose privacy/ZK capabilities without making ordinary
  multi-chain contracts harder to write?
- What is the smallest useful local Psy node/prover deployment smoke beyond
  Dargo's in-memory execution session?

## First Acceptance Criteria

- `psy-dpn` is listed as Experimental in target notes.
- The target profile draft includes artifact kind, required tools, and smoke
  steps.
- Generated Counter, ArithmeticProbe, U32ArithmeticProbe, ContextProbe, and
  HashProbe `.psy` packages compile with `dargo compile` on a machine with the
  Psy toolchain.
- Generated MapProbe `.psy` package compiles with `dargo compile` on a machine
  with the Psy toolchain.
- Generated AssertProbe `.psy` package compiles with `dargo compile` on a
  machine with the Psy toolchain.
- Generated LoopProbe `.psy` package compiles with `dargo compile` on a machine
  with the Psy toolchain.
- Generated ArrayProbe `.psy` package compiles with `dargo compile` on a
  machine with the Psy toolchain.
- Generated StructProbe `.psy` package compiles with `dargo compile` on a
  machine with the Psy toolchain.
- Generated StructArrayProbe `.psy` package compiles with `dargo compile` on a
  machine with the Psy toolchain.
- Generated AbiAggregateProbe `.psy` package compiles with `dargo compile` on
  a machine with the Psy toolchain.
- Generated NestedAggregateProbe `.psy` package compiles with `dargo compile`
  on a machine with the Psy toolchain.
- Generated StorageNestedAggregateProbe `.psy` package compiles with
  `dargo compile` on a machine with the Psy toolchain.
- Generated U32StorageScalarProbe `.psy` package compiles with `dargo compile`
  on a machine with the Psy toolchain.
- Generated BoolStorageScalarProbe `.psy` package compiles with `dargo compile`
  on a machine with the Psy toolchain.
- Generated BoolStorageArrayProbe `.psy` package compiles with `dargo compile`
  on a machine with the Psy toolchain.
- Generated HashStorageProbe `.psy` package compiles with `dargo compile` on a
  machine with the Psy toolchain.
- Generated U32StorageArrayProbe `.psy` package compiles with `dargo compile`
  on a machine with the Psy toolchain.
- Generated ConditionalProbe `.psy` package compiles with `dargo compile` on a
  machine with the Psy toolchain.
- Generated GenericEntrypointProbe `.psy` package compiles with `dargo compile`
  on a machine with the Psy toolchain.
- Dargo execution proves the expected Counter lifecycle, context-read result,
  deterministic hash outputs, map lifecycle output, and assertion-protected
  checked sum output, plus the Felt arithmetic result, U32 arithmetic result,
  bounded loop count result, fixed-array literal/storage results, struct
  literal/storage results, struct-array literal/storage results, ABI aggregate
  parameter/return flattening results, conditional branch result, local nested
  aggregate mutation results, storage-backed nested aggregate path update
  results, native U32 scalar storage result, native Bool scalar storage result,
  native Bool storage-array result, native Hash scalar/storage-array results,
  Felt-backed U32 storage-array/path-assignment result, and
  generic-entrypoint result.
- `scripts/psy/diagnostic-smoke.sh` proves unsupported or malformed Psy IR
  shapes produce explicit diagnostics before source generation.
- Artifact metadata records:
  - target id `psy-dpn`
  - target family and artifact kind
  - generated `.psy` source
  - generated Dargo package source copy
  - generated Dargo package manifest
  - DPN circuit JSON artifact
  - ABI artifact if generated
  - ProofForge deploy manifest if generated
  - Psy compiler/Dargo version or commit
  - used capabilities
- Artifact metadata is machine-validated against the generated artifact files
  and expected Dargo execution result.
