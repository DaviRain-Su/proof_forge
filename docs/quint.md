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
```

The default scenario uses small integer bounds (`MAX_UINT = 3`) and a finite
caller set (`USERS = {"alice", "bob", "charlie"}`). You can override them
with a TOML scenario file:

```toml
max_uint = 5
users = ["alice", "bob"]
max_steps = 10
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
`just quint-model-gate` script will skip this step gracefully.

## Model-based testing and IR replay

```sh
just quint-mbt-gate
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

Phase 3 v1 supports only the bounded scalar IR subset: scalars, maps, arrays,
structs, bounded loops, and basic arithmetic. Crosscalls, unbounded loops,
floating-point, and complex bitwise ops are out of scope for the first
iteration.
