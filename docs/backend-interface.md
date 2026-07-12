# Canonical Backend Interface

A backend starts at a checked canonical contract plus its resolved
`CapabilityPlan`. Its target semantic plan is the only layer allowed to choose
physical storage, ABI layout, host imports/syscalls, and target helper
requirements. The renderer receives that plan and emits the existing target
artifact format.

Target plan modules must not import `Frontend.Surface`, and canonical builders
must not import `IR.Contract`. Target plan type declarations must not embed raw
Yul, sBPF, or Wasm AST nodes. These dependencies are checked by
`just canonical-boundary`.

## Host operations

Every `HostOp` is identified by an exact id and version and has an exact
signature: argument types, result type, and effect class. Resolution is
fail-closed. Compilation fails before rendering when any of these conditions
holds:

- the id or exact version is unknown;
- argument arity or any argument type differs;
- the declared result type differs;
- the operation is used in the wrong effect position; or
- the selected target has no handler for the exact operation.

There is no version-range matching, implicit coercion, nearest-version lookup,
or generic fallback handler. A target extension becomes usable only after its
capability and exact handler are both registered and tested.

## Queue and Set expansion

Surface v2 `Queue` and `Set` are bounded authoring structures. Normalization
requires an explicit capacity and expands their operations into existing
canonical state and control primitives. Backends do not gain Queue/Set syntax
and renderers do not implement collection algorithms. Invalid capacities,
overflow, underflow, or a target that cannot materialize the expanded
primitives fail before artifact emission.

## Target acceptance

The primary public routes remain `evm`, `solana-sbpf-asm`, and `wasm-near`.
Their canonical builders must prove plan and artifact parity against the frozen
shared Legacy fragment, then pass product scenarios and the architecture
boundary gate. Parallel `*-core` ids and skeleton-only outputs are forbidden.

External syntax and runtime tools remain evidence gates, not compiler semantic
fallbacks: EVM uses `solc`, Foundry, and Anvil; Solana uses the sBPF
assembler/verifier and optional Mollusk/Surfpool/Pinocchio suites; NEAR uses
`wat2wasm` and the offline host. Live-network suites that require unavailable
tooling remain optional and are not part of default required CI.

See [Canonical compiler architecture](architecture.md) and
[Validation gates](validation-gates.md).
