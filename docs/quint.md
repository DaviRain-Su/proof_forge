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
```

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
`crosscall` (scalar `crosscallInvoke` U64 return stub), and `assert` (`.assert` /
`.assertEq` guards). The generator reads **portable
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
```

MBT tests that exercise `0..N` index parameters (for example
`struct-dynamic-path`) set `indexFromZero := true` in
`ProofForge.Backend.Quint.Scenario.Config` so Quint samples `0.to(MAX_UINT)`
instead of the default `1.to(MAX_UINT)`.

Scenario support is parsed by `ProofForge.Backend.Quint.Scenario` and is
intentionally minimal in v1.

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

## Model-based testing and IR replay

```sh
just quint-mbt-gate
just quint-model-gate
```

This lowers Counter, runs `quint run --mbt --out-itf`, parses the generated ITF
trace, and replays every step against `ProofForge.IR.Semantics` to check that
the abstract model and the executable IR agree on state transitions.

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
  scalar `crosscallInvoke` / `crosscallInvokeTyped` (U64 return stub:
  `target + method + sum(args)`), and `.assert` / `.assertEq` statement guards
- Scenario-driven bounds (`MAX_UINT`, `USERS`), scenario `[invariants]`, and derived `val`s

Still out of scope for the first iteration:
value/static/delegate crosscall variants,
`crosscallCreate`/`crosscallCreate2`, aggregate crosscall returns,
floating-point, and complex bitwise ops. `whileLoop` is lowered by static
unrolling up to `max_loop_unroll` (default 10) in the scenario config; loops that
need more iterations are truncated in the Quint model. Unrolling emits each step
as a `pure def __while_<state>_<n>` helper and assigns the final state from the
last helper, keeping model size linear in the unroll bound.
