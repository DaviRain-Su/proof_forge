# Portable Contract IR

Status: **Current Legacy compatibility IR reference (2026-07-12).** New
architecture work targets the checked Canonical Core; this file documents the
compatibility input being migrated.

The portable contract IR sits between the chain-neutral Contract Intent API and
target backends. It expresses chain-independent business logic plus the
target-resolved capability effects that the selected target adapter will lower.

Related: [RFC 0001](rfcs/0001-multichain-platform.md),
[RFC 0002](rfcs/0002-target-implementation-design.md),
[RFC 0003](rfcs/0003-portable-ir-and-runtime.md) (detailed draft),
[Capability registry](capability-registry.md),
[Shared scenario](shared-scenario.md).

## Goals

- Preserve the user-facing model where contract source declares portable
  intents and `--target` chooses the concrete chain route at compile time.
- Represent exported entrypoints, state, and transitions without EVM/Solana/Move
  ABI details.
- Record target-resolved capability calls as typed effects so targets can
  reject unsupported operations before lowering.
- Carry enough metadata for artifact emission and cross-target scenario tests.

## Non-goals (v0)

- Full Lean/LCNF preservation — only the contract-relevant subset.
- Automatic account/object inference for Solana or Move.
- Implicitly emulating target-specific semantics when a target cannot route an
  intent safely.
- Runtime proof transport to target chains — proofs are checked in Lean before
  codegen.

## Layering

```text
Lean contract source
  -> Contract Intent API
  -> target intent resolution (`--target`)
  -> CapabilityPlan
  -> Portable Contract IR + target metadata
  -> Target AST / assembler / package printer
```

The default SDK surface is the Contract Intent API. It should not expose EVM
storage slots, Solana account metas, Move resources, or Wasm host ABIs. The
selected target adapter resolves those intents into a `CapabilityPlan` before
lowering. Target Extension SDKs may expose chain-specific operations such as
Solana PDA/CPI or Move resource primitives, but those extensions still lower
through capability ids and target metadata rather than adding chain-only
constructors to the portable IR.

## IR Units (v0 sketch)

### Module

- `name`: package/module identifier
- `entrypoints`: exported handlers
- `state`: declared persistent state slots
- `types`: portable structs/enums used by the module

### Entrypoint

- `name`: logical method name (e.g. `increment`, `get`)
- `tag`: optional dispatch tag for non-EVM targets
- `params`: portable values plus target-resolved account/resource bindings when
  the selected adapter requires explicit metadata
- `effects`: ordered target-resolved capability calls
- `returns`: portable return type or unit

### State

- `id`: stable state variable name
- `kind`: `scalar` | `map` | `array` | `dynamicArray` (shape only)
- `type`: portable type reference

State is **chain-neutral**. Native binding (EVM slots, Solana account bytes,
NEAR host KV, Aptos resources, Sui objects) is **not** part of the IR: the
selected `--target` resolves it via `ProofForge.Target.StorageBinding`
(D-050 / D-028). Authors write `state count: scalar U64` once; each backend
materializes that shape for its chain.

See `ProofForge.IR.Portability` for family-only *constructors* (e.g. CREATE2,
NEAR Promise ops) that must not pretend to be portable core.

### Effect (target-resolved capability call)

- `capability`: id from [capability-registry.md](capability-registry.md)
- `args`: portable operands
- `source`: optional Lean source span for diagnostics

### Expression Surface

The current executable IR in `ProofForge/IR/Contract.lean` includes a compact
expression set for target-source backends:

- literals: `U32`, `U64`/Felt, Bool, and fixed four-limb Hash literals
- local variables, fixed-array literals/indexing, struct literals, and field
  access
- numeric operations: `+`, `-`, `*`, `/`, `%`, `**`
- bitwise operations and shifts: `&`, `|`, `^`, `<<`, `>>`
- casts between supported scalar value types
- comparisons and boolean composition
- dynamic Hash value construction from four Felt limbs
- hash intrinsics: one-to-one and two-to-one hash operations
- effect expressions for storage reads, map reads, array reads, storage-path
  reads, and context reads

The statement set includes immutable and mutable local bindings, plain
assignment, first-class compound assignment (`+=`, `-=`, `*=`, `/=`, `%=`,
`|=`, `&=`, `^=`, `<<=`, `>>=`), statement effects, assertions, `if/else`,
bounded `for`, and explicit `return`. Statement effects include storage writes
and storage-reference compound assignment effects for scalar storage and
generic storage paths.

Each target backend is responsible for either lowering each node it accepts or
rejecting it before source generation with an explicit diagnostic.

## Relationship to LCNF

```text
Lean contract source
  -> Lean frontend / LCNF (today)
  -> Portable Contract IR (Phase 1)
  -> Target lowering
```

**Phase 1 transition:** EVM may temporarily lower from LCNF while the IR extractor
is built, but the Counter shared scenario must compile through IR before Phase 2
spikes are considered complete.

## Target IR Subsets

Each target accepts a subset of IR. Unsupported constructs fail at capability
check time with target id and capability id.

| Restriction | Solana | Move (Aptos/Sui) | Psy DPN |
|---|---|---|---|
| Implicit contract storage | Rejected — use explicit accounts | Rejected — use resources/objects | Allowed only through explicit Psy storage/sourcegen mapping |
| Higher-order functions | Restricted runtime subset TBD | Rejected in v0 | Rejected in v0 |
| Arbitrary heap objects | Runtime size TBD | Rejected | Rejected |
| Closures | TBD with sBPF spike | Rejected | Rejected |
| Unbounded loops | TBD with sBPF spike | Rejected in v0 | Rejected; require circuit-friendly bounded shape |

See [targets/solana-sbf.md](targets/solana-sbf.md),
[targets/move-family.md](targets/move-family.md), and
[targets/psy-dpn.md](targets/psy-dpn.md) for family-specific limits.

## Counter IR Example (v0)

Logical module for the [shared scenario](shared-scenario.md):

```text
module Counter {
  state count: scalar U64

  entrypoint initialize() {
    effect storage.scalar.write("count", 0)
  }

  entrypoint increment() {
    let n = effect storage.scalar.read("count")
    effect storage.scalar.write("count", n + 1)
  }

  entrypoint get() -> U64 {
    return effect storage.scalar.read("count")
  }
}
```

EVM lowering maps `storage.scalar` to slot storage; Solana maps to account data;
CosmWasm maps to string-keyed KV; Aptos maps to an account resource field.

## Phase 1 Acceptance Criteria

- [ ] IR node types documented in Lean (`ProofForge/IR/` or equivalent).
- [ ] Counter module expressible in IR without EVM-specific opcodes.
- [ ] EVM backend can lower Counter IR to Yul (directly or via existing EmitYul
      path with a thin adapter).
- [ ] Capability checker rejects at least one unsupported capability per
      non-EVM target with a clear diagnostic.
- [x] EVM portable IR bytecode metadata records `irVersion:
      portable-ir-v0` in `proof-forge-artifact.json`.


## Crosscall semantics honesty (U2)

Portable IR can *represent* remote calls (`crosscall.invoke` / typed variants /
CREATE*). **Executable IR semantics does not simulate a real peer.**

| Layer | What happens on `crosscall.*` | Trust / use |
|-------|-------------------------------|-------------|
| **IR `Semantics`** | **Deterministic stub**: sum target + method + scalar args (and optional tags for static/delegate/create); typed returns are cast from that sum (`crosscallHashStubValue` for hashes). | Quint MBT / IR self-replay / fixture determinism only |
| **Quint lowering** | Same sum stub (`lowerCrosscallInvokeSumExpr`) aligned with IR | Tier A design validation |
| **Target materialize** | Real host form: EVM CALL · Solana CPI · NEAR `promise_create` · Soroban `invoke_contract` · CosmWasm `execute_msg` | Product / gates: `just crosscall-materialize`, `just portable-remote-call-multi-target` |

**Do not claim** that IR `runEntrypoint` return values equal EVM CALL / CPI /
Promise results. Product remote correctness is proven by **target emit + host
smokes**, not by IR↔chain return equality on crosscall.

Optional future (U2.4): an IR peer-oracle registry for FV could replace the sum
stub for selected modules; until then, stub crosscall stays **outside** the
universal C-proof fragment (see FV-9 / U5.3).

### Portable return decode (U2.5)

Product portable remotes materialize **scalar returns** (primarily `u64` /
bool-as-word). Solana portable CPI decodes return data as a **single u64**
(`decodeReturnDataU64`). Richer aggregate / dynamic returns are **not** a
portable product promise today: use target extensions or honest-reject at
materialize/plan rather than inventing a cross-host ABI. IR stub typed
returns remain cast-from-sum (not peer ABI).

Related: `ProofForge/IR/Semantics.lean` (`evalCrosscallInvokeSum`),
`ProofForge/Backend/Quint/Lower.lean`, `ProofForge/Target/CrosscallMaterialize.lean`,
`Tests/IRCrosscallStub.lean`, `Tests/CrosscallMaterialize.lean`.

## Open Questions

- How much of LCNF to reuse vs. a fresh contract IR AST?
- Should account schemas live in IR or in target sidecar manifests?
- IR versioning strategy when capabilities expand.
