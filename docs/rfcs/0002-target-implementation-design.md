# RFC 0002: Target implementation design

Status: Accepted

Date: 2026-06-30

## Summary

RFC 0001 defines the product direction. This RFC defines the first engineering
shape for implementing that direction.

ProofForge should not use one backend strategy for every chain. It should split
targets into implementation families:

- Direct compiler targets: ProofForge owns most lowering logic, as with the
  current EVM/Yul backend.
- Wasm host targets: ProofForge emits a Wasm module plus chain-specific host
  ABI adapters, as with NEAR and CosmWasm.
- Binary toolchain targets: ProofForge emits an intermediate object/bitcode and
  calls a chain-specific packager/linker, as with Solana sBPF.
- Source codegen targets: ProofForge emits target source packages, as with Sui
  Move and Aptos Move.
- ZK circuit sourcegen targets: ProofForge emits target source packages and
  delegates circuit artifact generation to target-native tooling, as with
  Psy/DPN.

This keeps the portable contract model stable while allowing each chain family
to keep its native ABI, storage model, tooling, and tests.

## Design Goals

- Keep Lean as the user-facing language for business logic, types, and proofs.
- Keep target differences explicit through capabilities and target manifests.
- Integrate with mature target-native tools before replacing them.
- Make every build produce machine-readable artifact metadata.
- Make every supported target earn support through at least one local smoke
  test and one capability matrix entry.

Non-goal: arbitrary Lean code should not be expected to compile to every
target. The supported subset will be determined by the portable contract IR and
the selected target's capability profile.

## Proposed Repository Shape

The current repository can evolve toward this layout (paths marked *planned* are
not in the repo yet):

```text
ProofForge/
  Target.lean                    # planned
  Target/
    Capability.lean              # planned
    Artifact.lean                # planned
    Registry.lean                # planned
  IR/
    Contract.lean                # planned — see docs/portable-ir.md
    Type.lean                    # planned
    Effect.lean                  # planned
    Manifest.lean                # planned
  Backend/
    Evm.lean
    Wasm/
      Near.lean                  # planned
      CosmWasm.lean              # planned
    Solana/
      SbfLinker.lean             # planned
      SolanaZig.lean             # planned
    Move/
      Sui.lean                   # planned
      Aptos.lean                 # planned
    Zk/
      PsyDpn.lean                # planned
runtime/
  zig/
    lean_rt/                     # planned
    host/
      near/                      # planned
      cosmwasm/                  # planned
      solana/                    # planned
tools/
  zigc-near                      # planned
  zigc-cosmwasm                  # planned
  zigc-solana-sbpf               # planned
scripts/
  evm/
  near/                          # planned
  cosmwasm/                      # planned
  solana/                        # planned
  move/                          # planned
  psy/                           # planned
Examples/
  Evm/
  Near/                          # planned
  CosmWasm/                      # planned
  Solana/                        # planned
  Move/                          # planned
  Psy/                           # planned
```

This is not a required one-shot refactor. It is a direction for staged work.
The existing EVM implementation can remain where it is until `Target` and `IR`
modules exist.

## Target Profile

Every target should be described by a `TargetProfile`.

Conceptually:

```lean
inductive TargetFamily where
  | evm
  | wasm
  | solana
  | move
  | zkCircuit

inductive ArtifactKind where
  | evmBytecode
  | wasm
  | solanaElf
  | movePackage
  | psyCircuitJson

structure TargetProfile where
  id : String
  family : TargetFamily
  artifactKind : ArtifactKind
  capabilities : CapabilitySet
  buildSteps : Array BuildStep
  smokeTests : Array SmokeTest
```

Initial target ids (historical snapshot — see [Backend Status](../../README.md)
and [doc-code-sync-audit-2026-07.md](../doc-code-sync-audit-2026-07.md) for
current stages):

| Target id | Family | Artifact | Status (2026-07 on `main`) |
|---|---|---|---|
| `evm` | EVM | Runtime bytecode | Experimental — production-grade gates (Gate P0) |
| `wasm-near` | Wasm host | NEAR-compatible Wasm | Experimental — EmitWat on `main` (Gate P0) |
| `wasm-cosmwasm` | Wasm host | CosmWasm Wasm | Spike — Counter golden WAT + optional CI |
| `solana-sbpf-linker` | Solana | Solana sBPF ELF `.so` | **Deprecated** (D-026; use `solana-sbpf-asm`) |
| `solana-zig-fork` | Solana | Solana sBPF ELF `.so` | **Deprecated** (D-005/D-026) |
| `solana-sbpf-asm` | Solana | sBPF ELF | Experimental — canonical route (Gate P0) |
| `move-sui` | Move | Sui Move package | Counter MVP — local `just sui-*` gates |
| `move-aptos` | Move | Aptos Move package | Spike — Counter golden Move |
| `psy-dpn` | ZK circuit sourcegen | DPN circuit JSON + ABI | Experimental subset |
| `wasm-cloudflare-workers` | Wasm host (off-chain) | TypeScript Worker | Research spike — TS emit |
| `aleo-leo` | ZK / Leo | Leo package | Research spike — CLI-only (D-025) |

Future research (not in registry until scheduled): `wasm-polkadot` (ink!).
See [decisions.md](../decisions.md).

## Capability Matrix

The compiler should use a target capability matrix before lowering. If a
contract uses a capability that the target cannot represent, the build should
fail with a precise diagnostic.

| Capability | EVM | NEAR | CosmWasm | Solana | Sui | Aptos | Psy DPN |
|---|---|---|---|---|---|---|---|
| Persistent scalar state | Slot storage | Host KV | Host KV | Account data | Object fields | Account resources | Psy storage/state |
| Caller/sender | `msg.sender` | predecessor/signer | `MessageInfo.sender` | signer account | `TxContext.sender` | `signer` | Psy user/context |
| Native value received | `msg.value` | attached deposit | funds in message info | lamport accounts | coin objects | coin resources | Psy-specific asset flow |
| Events/logs | EVM logs | logs/events | events/attributes | logs/events | events | events | Research |
| Cross-contract call | call/staticcall | promises | submessages | CPI | module calls/transactions | module calls | `invoke_sync` / `invoke_deferred` |
| State account/object selection | implicit contract | implicit contract | implicit contract | explicit accounts | explicit objects | account resources | Psy contract/user state |
| Dynamic map storage | mapping/keccak slot | KV prefixes | KV prefixes | account-owned data or PDAs | dynamic fields/tables | table resources | fixed-capacity Psy storage |
| Contract deployment package | bytecode | Wasm | Wasm | ELF `.so` | Move package | Move package | DPN circuit JSON + deploy JSON |

Capability ids are canonical in [capability-registry.md](../capability-registry.md).
The semantic matrix below maps portable meaning to target mechanics.

## Artifact Metadata

Every build should emit `proof-forge-artifact.json` next to the target output.

Initial schema:

```json
{
  "schemaVersion": 1,
  "package": "counter",
  "target": "wasm-cosmwasm",
  "source": {
    "entryFile": "Examples/CosmWasm/Counter.lean",
    "module": "Counter"
  },
  "proofs": {
    "checked": true,
    "warnings": []
  },
  "capabilities": [
    "storage.scalar",
    "caller.sender",
    "events.emit"
  ],
  "artifacts": [
    {
      "kind": "wasm",
      "path": "build/cosmwasm/counter.wasm",
      "sha256": "..."
    }
  ],
  "toolchain": {
    "proofForge": "0.1.0",
    "lean": "4.31.0",
    "zig": "0.15.x",
    "external": {
      "cosmwasm-check": "..."
    }
  },
  "targetMetadata": {}
}
```

The cloud platform can later store exactly this metadata, plus deployment
addresses, transaction hashes, and test reports.

## CLI Shape

The current CLI supports EVM bytecode directly:

```sh
lake env proof-forge --evm-bytecode -o build/evm/Counter.bin \
  Examples/Evm/Contracts/Counter.lean
```

The target-oriented CLI should eventually expose:

```sh
proof-forge build --target evm --out build/evm Examples/Evm/Contracts/Counter.lean
proof-forge build --target wasm-near --out build/near Examples/Near/Counter.lean          # planned
proof-forge build --target wasm-cosmwasm --out build/cosmwasm Examples/CosmWasm/Counter.lean  # planned
proof-forge build --target solana-sbpf-asm --out build/solana Examples/Solana/Counter.lean  # planned
proof-forge build --target move-aptos --out build/aptos Examples/Move/Aptos/Counter/       # planned
proof-forge test --target evm
proof-forge test --target solana-sbpf-asm
```

Near-term implementation can keep target scripts under `scripts/<target>/`
while the CLI is being generalized.

## EVM Target

Current pipeline:

```text
Lean contract
  -> Lean frontend / LCNF
  -> EmitYul
  -> Yul
  -> solc --strict-assembly
  -> runtime bytecode
  -> Foundry smoke
```

Implementation notes:

- Keep `ProofForge.Evm` as the first concrete target adapter / extension SDK.
- Keep `.evm-methods` as target metadata until a unified manifest exists.
- Add artifact metadata around the existing bytecode path.
- Add golden Yul snapshots for simple examples before major IR refactors.

## NEAR Target

The Lean fork already demonstrates the desired Wasm-host pattern:

```text
Lean contract
  -> EmitZig
  -> generated Zig contract module
  -> NEAR Zig runtime + host bridge
  -> wasm32-wasi or wasm32-freestanding Wasm
  -> strip/stub incompatible WASI imports if needed
  -> NEAR-compatible Wasm
```

Key pieces observed in the fork:

- `Lean.Near`: Lean SDK with `@[extern "lean_near_*"]` functions.
- `host/near/lean_near.zig`: bridge from Lean objects to NEAR host imports.
- `tools/zigc-near`: wrapper that generates method exports and links runtime.
- `near-strip-wasi-imports.cjs`: removes WASI imports and checks MVP Wasm
  compatibility.

Implementation improvements needed for ProofForge:

- Move `lean_near_*` extern declarations out of core EmitZig runtime externs.
- Make host bridge selection target-driven instead of "all Wasm means NEAR".
- Move method export metadata into a generic target manifest.
- Keep NEAR as the first reference for Wasm-host runtime shape.

## CosmWasm Target

CosmWasm should share the Wasm-host family with NEAR, but it needs a separate
adapter. Wasm is the artifact format; the contract ABI is different.

Expected pipeline:

```text
Lean contract
  -> EmitZig
  -> generated Zig contract module
  -> CosmWasm Zig runtime + host bridge
  -> wasm32-freestanding or wasm32-unknown-style Wasm
  -> cosmwasm-check
  -> cw-multi-test or wasmd smoke
```

Required exports:

- `interface_version_8`
- `allocate`
- `deallocate`
- `instantiate`
- `execute`
- `query`
- optional later: `migrate`, `reply`, `sudo`, `ibc_*`

The entrypoint adapter should use the CosmWasm region-pointer ABI. The first
implementation should keep messages JSON-backed to avoid adding a full schema
compiler before the backend exists.

**Authoritative SDK and spike sketch:** [targets/wasm-family.md](../targets/wasm-family.md)
(Counter spike section). Do not duplicate SDK definitions here.

Zig bridge sketch:

```zig
export fn instantiate(env: u32, info: u32, msg: u32) callconv(.c) u32 {
    return runLeanEntrypoint(.instantiate, env, info, msg);
}

export fn execute(env: u32, info: u32, msg: u32) callconv(.c) u32 {
    return runLeanEntrypoint(.execute, env, info, msg);
}

export fn query(env: u32, msg: u32) callconv(.c) u32 {
    return runLeanQuery(env, msg);
}
```

First smoke test:

- Counter contract with `instantiate`, `execute({"increment":{}})`, and
  `query({"get_count":{}})`.
- Build Wasm.
- Run `cosmwasm-check`.
- Run a local Rust or CLI-based smoke that calls instantiate/execute/query.

## Solana Target

Solana should have two implementation profiles.

### Preferred track: `solana-sbpf-linker`

The `zignocchio` project shows a useful no-fork flow:

```text
Zig source
  -> zig build-lib -target bpfel-freestanding -femit-llvm-bc=entrypoint.bc
  -> sbpf-linker --cpu v2 --export entrypoint -o program.so entrypoint.bc
  -> solana-test-validator or Mollusk smoke
```

This matches the "intermediate artifact plus target packager" pattern used by
EVM/Solang-style flows.

ProofForge pipeline:

```text
Lean contract
  -> EmitZig
  -> generated Zig contract module
  -> generated solana_contract_root.zig
  -> zig build-lib -target bpfel-freestanding -femit-llvm-bc
  -> sbpf-linker
  -> Solana ELF `.so`
  -> smoke test
```

Required Solana adapter pieces:

- `Lean.Solana`: account, instruction data, signer, PDA, CPI, log, return data.
- `lean_solana_*` bridge functions in Zig.
- `solana_contract_root.zig`: exports the single `entrypoint(input) -> u64`.
- Instruction dispatch metadata, replacing NEAR-style method exports.
- Explicit account schemas for each entrypoint.

Solana method manifest sketch (format: TOML v0, subject to change — full
example with account `index` fields in
[targets/solana-sbf.md](../targets/solana-sbf.md)):

```toml
[[instruction]]
name = "increment"
tag = 1
handler = "l_Counter_increment"
accounts = [
  { name = "payer", index = 0, signer = true, writable = true },
  { name = "counter", index = 1, signer = false, writable = true, owner = "program" }
]
```

Root adapter sketch:

```zig
export fn entrypoint(input: [*]u8) callconv(.c) u64 {
    var ctx = solana.deserialize(input);
    lean_rt.lean_initialize_runtime_module();
    return dispatchLeanInstruction(&ctx);
}
```

Testing strategy:

- Fast deterministic program tests: Mollusk where possible.
- Deployment-style smoke: `solana-test-validator --bpf-program`.
- First contract: no CPI, one PDA/account state.
- Second contract: CPI to System Program.
- Third contract: SPL Token CPI.

### Fallback/reference track: `solana-zig-fork`

The `solana-sdk-mono` project shows another route:

```text
Zig source
  -> solana-zig target .sbf/.solana
  -> dynamic library `.so`
  -> Mollusk tests
```

This route is useful because the SDK already models accounts, CPI, typed
accounts, events, and program tests in a mature way. It should remain a
reference even if ProofForge chooses `sbpf-linker` first.

## Move Targets

Move targets should not try to compile the full Lean runtime. The first
implementation should generate Move source packages from a restricted portable
IR.

Shared Move restrictions:

- First-order functions only.
- No closures or higher-order runtime values.
- No arbitrary Lean heap objects at runtime.
- Data types must map to Move structs/enums or generated variants.
- Effects must be target capabilities, not arbitrary IO.
- Proofs stay in Lean and are checked before Move code generation.

### Sui

Sui uses an object-centric Move model. Persistent state should map to objects
with `UID`.

Pipeline:

```text
Lean portable contract
  -> Portable IR
  -> Sui Move package
  -> sui move build
  -> sui move test
  -> optional localnet/testnet publish
```

Sui mapping:

| Portable concept | Sui mapping |
|---|---|
| Contract state | Object struct with `id: UID` |
| Caller | `TxContext.sender(ctx)` |
| Entry method | `public entry fun` |
| Native value | `Coin<T>` objects |
| Events | `sui::event::emit` |
| Dynamic map | `table`, dynamic fields, or explicit child objects |

First Sui POC:

- Counter object with `init`, `increment`, `get`.
- Generate `Move.toml` and `sources/counter.move`.
- Add Move unit tests.

### Aptos

Aptos uses a module/resource model closer to account-scoped storage.

Pipeline:

```text
Lean portable contract
  -> Portable IR
  -> Aptos Move package
  -> aptos move compile
  -> aptos move test
  -> optional localnet/testnet publish
```

Aptos mapping:

| Portable concept | Aptos mapping |
|---|---|
| Contract state | `struct State has key` under an account |
| Caller | `&signer` |
| Entry method | `public entry fun` |
| Native value | `aptos_coin` / fungible asset APIs |
| Events | event module APIs |
| Dynamic map | table resources |

First Aptos POC:

- Account-owned counter resource.
- `initialize(account: &signer)`
- `increment(account: &signer)`
- `get(addr: address): u64`

Sui object POC follows in a separate slice after Aptos (see
[decisions.md](../decisions.md)).

## Implementation Phases

Aligned with [RFC 0001](0001-multichain-platform.md) and
[decisions.md](../decisions.md):

### Phase 1: Target registry, portable IR, metadata

- Add target ids and capability sets ([capability-registry.md](../capability-registry.md)).
- Implement portable IR per [portable-ir.md](../portable-ir.md).
- Define Counter [shared scenario](../shared-scenario.md).
- Add artifact metadata schema.
- Keep current EVM command working.

### Phase 2: Parallel spikes (CosmWasm + Solana)

- Wasm-host extraction and `wasm-cosmwasm` Counter spike.
- `solana-sbpf-linker` Counter spike with instruction manifest.
- Both depend on Phase 1 completion; may run in parallel.

### Phase 3: EVM hardening (ongoing)

- Emit `proof-forge-artifact.json` for EVM builds.
- Golden output tests for core EVM examples.

### Phase 4: Move sourcegen (Aptos first)

- Restricted Move-compatible IR subset.
- Aptos counter package; Sui object POC as follow-up.

### Phase 5: Cross-target scenario hardening and cloud prep

- Shared scenario tests across multiple targets.
- Cloud platform design after two+ Experimental targets.

## Open Engineering Risks

- Lean runtime on sBPF may be too large or use unsupported sections.
- Full Lean heap/object model may be too expensive for Solana compute budgets.
- CosmWasm may require a tighter no-WASI runtime than NEAR's first path.
- Move codegen requires a real ownership/resource model, not string templates.
- A portable IR that is too close to EVM will fail on Solana and Move.
- A portable IR that is too generic will become unusable for real contracts.

## Settled Decisions

See [decisions.md](../decisions.md) for the decision log. Key items:

- Phase 1 before non-EVM spikes.
- CosmWasm and Solana spikes in parallel after Phase 1.
- `solana-sbpf-linker` as primary Solana path; `solana-zig-fork` as fallback.
- Aptos-first Move POC; Sui follows.

## Research References

- EVM baseline in this repository: `ProofForge.Compiler.LCNF.EmitYul`,
  `ProofForge.Evm`, `scripts/evm/foundry-smoke.sh`.
- NEAR reference in local Lean fork (lean4-zig-compiler): `Lean.Near.lean`,
  `tools/zigc-near`, `src/runtime/zig/host/near`.
- Solana fork-target reference:
  `https://github.com/DaviRain-Su/solana-sdk-mono.git`.
- Solana stock-Zig reference:
  `https://github.com/vitorpy/zignocchio`.
- sbpf-linker:
  `https://github.com/blueshift-gg/sbpf-linker`.
- CosmWasm docs:
  `https://cosmwasm.cosmos.network/`.
- Sui Move docs:
  `https://docs.sui.io/concepts/sui-move-concepts`.
- Aptos Move docs:
  `https://aptos.dev/network/blockchain/move`.
