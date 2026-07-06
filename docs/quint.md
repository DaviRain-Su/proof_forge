# Quint Model Generation

ProofForge can lift a portable IR contract fixture into an executable Quint
state-machine model. Quint is used as a **design validator** upstream of the
Lean authoring and backend-verification chain, not as a replacement for them.

## Prerequisites

- `quint` CLI (`npm install -g @informalsystems/quint` or equivalent).
- For `quint verify`: Java 17+ (Apalache requirement).

## Emit a model

```sh
lake env proof-forge emit --target quint --fixture counter -o build/quint/Counter.qnt
lake env proof-forge emit --target quint --fixture counter --format scenario -o build/quint/Counter.scenario.toml
lake env proof-forge emit --target quint --fixture conditional -o build/quint/ConditionalProbe.qnt
lake env proof-forge emit --target quint --fixture loop -o build/quint/LoopProbe.qnt
lake env proof-forge emit --target quint --fixture while -o build/quint/WhileProbe.qnt
lake env proof-forge emit --target quint --fixture array -o build/quint/ArrayProbe.qnt
lake env proof-forge emit --target quint --fixture map -o build/quint/MapProbe.qnt
lake env proof-forge emit --target quint --fixture map-path -o build/quint/MapPathProbe.qnt
lake env proof-forge emit --target quint --fixture map-nested-path -o build/quint/MapNestedPathProbe.qnt
lake env proof-forge emit --target quint --fixture map-path-assign -o build/quint/MapPathAssignProbe.qnt
lake env proof-forge emit --target quint --fixture struct -o build/quint/StructProbe.qnt
lake env proof-forge emit --target quint --fixture array-path -o build/quint/ArrayPathProbe.qnt
lake env proof-forge emit --target quint --fixture struct-path -o build/quint/StructPathProbe.qnt
lake env proof-forge emit --target quint --fixture struct-dynamic-path -o build/quint/StructDynamicPathProbe.qnt
lake env proof-forge emit --target quint --fixture nested-struct-ref -o build/quint/NestedStructRefProbe.qnt
lake env proof-forge emit --target quint --fixture assignment -o build/quint/AssignmentProbe.qnt
lake env proof-forge emit --target quint --fixture crosscall -o build/quint/CrosscallProbe.qnt
lake env proof-forge emit --target quint --fixture assert -o build/quint/AssertProbe.qnt
lake env proof-forge emit --target quint --fixture unbounded-int -o build/quint/UnboundedIntProbe.qnt
```

### User invariants in `contract_source`

Declare Quint safety invariants beside contract state:

```lean
contract_source Counter do
  state count : .u64
  quint_invariant countBounded := "count <= MAX_UINT"
  ...
end
```

Expressions use the same small language as scenario TOML `[invariants]`
(`ProofForge.Backend.Quint.InvExpr`). Unsigned scalar state still gets
auto-derived non-negativity `val`s. `proof-forge emit --target quint` merges
`quint_invariant` annotations from the canonical `contract_source` spec.

### Liveness properties in `contract_source`

Declare Quint temporal (liveness) properties beside contract state:

```lean
contract_source Counter do
  state count : .u64
  quint_liveness eventuallyPositive := "eventually(count > 0)"
  ...
end
```

Expressions use the same small language as safety invariants, plus call syntax
for temporal operators (`always(...)`, `eventually(...)`, `next(...)`).
`proof-forge emit --target quint` emits `temporal` definitions alongside `val`
invariants. The default `quint verify` gate still checks safety invariants only;
Apalache does not model-check arbitrary liveness properties in the CI path.

Supported built-in fixtures today: `counter`, `value-vault`, `conditional`, `loop`,
`while`, `array` (fixed-size storage array lifecycle), `map` (hash-keyed storage map
get/has/set with presence guards on get), `map-path` (single-segment `storagePath*` on
maps), `map-nested-path` (two-segment consecutive `mapKey` paths on hash maps),
`map-triple-path` (three-segment consecutive `mapKey` paths on hash maps),
`map-nested-dynamic-path` (literal + dynamic nested `mapKey` paths on hash maps),
`map-path-assign` (single- and nested-mapKey `storagePathAssignOp` on U64 maps),
`map-hash-path-assign` (hash-valued map `storagePathAssignOp` replace stub),
`struct` (flattened struct field storage), `array-path` (index `storagePath*` on
scalar arrays), `struct-path` (literal index+field `storagePath*` on array-of-struct
storage), `struct-dynamic-path` (dynamic index+field `storagePath*` on
array-of-struct storage), `nested-struct-ref` (nested `#[ref]` struct fields via
`storagePath*` on scalar and array-of-struct storage), `assignment` (scalar local `letMutBind`/`.assign`/`.assignOp`),
`crosscall` (scalar `crosscallInvoke` U64 return stub with `target + method +
sum(args)`), `assert` (`.assert` /
`.assertEq` guards), and `unbounded-int` (U128 literals above `MAX_UINT` with
bounded nondet parameters). The generator reads **portable
IR** fixtures, so the same `.qnt` model is target-agnostic: it validates design
intent upstream of EVM, Solana, NEAR, Psy, or any other backend lowering.

The default scenario uses small integer bounds (`MAX_UINT = 3`) and a finite
caller set (`USERS = {"alice", "bob", "charlie"}`). You can override them
with a TOML scenario file:

```toml
max_uint = 5
users = ["alice", "bob"]
max_steps = 10
max_loop_unroll = 10
n_traces = 20
unbounded_integers = true
```

Integer abstraction uses two domains:

- **Nondet parameters** sample from `1.to(MAX_UINT)` (or `0.to(MAX_UINT)` when
  `indexFromZero` is set in scenario config). This keeps model checking feasible.
- **Literals and computed state** use Quint unbounded `int` semantics and are not
  clamped to `MAX_UINT`. U128 constants, storage writes, and arithmetic results
  may exceed the scenario bound. ITF replay parses large values via `#bigint`.

Set `unbounded_integers = false` in scenario TOML to document a strict bounded
model; the default is `true`.

MBT tests that exercise `0..N` index parameters (for example
`struct-dynamic-path`) set `indexFromZero := true` in
`ProofForge.Backend.Quint.Scenario.Config` so Quint samples `0.to(MAX_UINT)`
instead of the default `1.to(MAX_UINT)`.

Scenario support is parsed by `ProofForge.Backend.Quint.Scenario` and is
intentionally minimal in v1. Per-fixture defaults ship via
`proof-forge emit --target quint --format scenario`; pass the file back with
`--scenario` when emitting `.qnt` models.

## Simulate

```sh
quint run build/quint/Counter.qnt
```

## Model-check

```sh
quint verify build/quint/Counter.qnt --invariants countNonNegative --max-steps 10
```

`quint verify` requires Java 17+. If your environment only has Java 11, the
`just quint-model-gate` script will skip this step gracefully locally; CI
installs Temurin 17 and runs the gate as a blocking check.

## Unified IR model gate

```sh
just quint-ir-model-gate
```

Runs the full design-spec pipeline for Counter and ValueVault: CLI emit,
`quint verify`, `quint run --mbt`, IR-semantics replay, and (for Counter)
EVM Foundry backend replay.

## Model-based testing and IR replay

```sh
just quint-mbt-gate
just quint-model-gate
just testkit-quint
```

The unified testkit can also drive Quint MBT ITF replay via `[[quint]]`
scenario expectations (`testkit/scenarios/quint-counter.toml`). Each
expectation runs `quint run --mbt`, parses the ITF trace, and replays it
through Lean IR semantics using the mapped `Tests/Quint/*Replay.lean` harness.
Use `cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --target quint`
to run only Quint scenarios.

This lowers Counter, runs `quint run --mbt --out-itf`, parses the generated ITF
trace, and replays every step against `ProofForge.IR.Semantics` to check that
the abstract model and the executable IR agree on state transitions.

## EVM backend MBT replay

```sh
just quint-evm-backend-replay-gate
```

This runs the Counter MBT flow above, emits portable IR bytecode for EVM,
generates a Foundry test from the ITF trace (`ProofForge.Backend.Quint.EvmReplay`),
and replays every `actionTaken` step against the etched runtime bytecode via
`forge test`. The gate skips gracefully when `quint`, `forge`, or `solc` are
missing locally; CI treats it as blocking. The same EVM replay step is also
available standalone via `just quint-evm-backend-replay-gate` and is included
in `just quint-ir-model-gate`.

## Capabilities

The Quint integration contributes these toolchain capabilities (see
[capability-registry.md](capability-registry.md)):

- `model.quint`
- `verify.model_check`
- `verify.simulation`
- `test.mbt_trace`

## Limitations

Phase 3 v1 currently lowers a growing portable IR subset:

- Scalars, `ifElse`, `boundedFor`, `whileLoop` (statically unrolled), and checked arithmetic
- Fixed-size storage arrays (`List[T]` with 0-based Quint list indexing)
- Storage maps (`str -> str` / `str -> int` with `hash:a:b:c:d` or `u64:n` key encoding)
  and struct fields flattened to per-field state variables (`current_x`, `points_0_x`)
- Single- and multi-segment (2+) `mapKey` `storagePath*`, struct/array path shapes,
  dynamic index+field paths on array-of-struct storage, scalar local
  assignment (`letMutBind`, `.assign`, `.assignOp` on `.local` targets), and
  scalar `crosscallInvoke` / `crosscallInvokeTyped` / value/static/delegate
  variants (stub: `target + method + sum(args)` with variant tags and
  Bool/U32/U64/Hash return casts), flat struct and fixed-array aggregate
  crosscall params/returns (stub: flatten leaves into `sum + offset` slots),
  `crosscallCreate` / `crosscallCreate2` (stub: `callValue + tag` and
  `callValue + salt + tag`), and
  `.assert` / `.assertEq` statement guards
- Scenario-driven bounds (`MAX_UINT`, `USERS`), scenario `[invariants]`, and derived `val`s

Still out of scope for the first iteration:
nested aggregate crosscall shapes, floating-point, and complex bitwise ops. `whileLoop` is lowered by static
unrolling up to `max_loop_unroll` (default 10) in the scenario config; loops that
need more iterations are truncated in the Quint model. Unrolling emits each step
as a `pure def __while_<state>_<n>` helper and assigns the final state from the
last helper, keeping model size linear in the unroll bound.
