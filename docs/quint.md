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
```

Supported built-in fixtures today: `counter`, `value-vault`, `conditional`, `loop`,
`while`, and `array` (fixed-size storage array lifecycle). The generator reads **portable
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
- Fixed-size storage arrays (`List[T]` with 1-based Quint indexing)
- Scenario-driven bounds (`MAX_UINT`, `USERS`) and manual invariants

Still out of scope for the first iteration: map/struct storage, crosscalls,
floating-point, and complex bitwise ops. `whileLoop` is lowered by static
unrolling up to `max_loop_unroll` (default 10) in the scenario config; loops that
need more iterations are truncated in the Quint model. Unrolling emits each step
as a `pure def __while_<state>_<n>` helper and assigns the final state from the
last helper, keeping model size linear in the unroll bound.
