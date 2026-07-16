# RFC 0009: CLI Product Surface

Status: **Accepted — M1/M3 landed, M4 transition open**
Date: 2026-07-03

Implementation status (2026-07-04): RFC 0009 is accepted as the durable CLI
surface. M1 has landed in code: `Command`/`CliOptions` exist, `build`/`emit`
route through the compatibility layer, `check` is a real validation verb,
`--list-targets` and `--list-fixtures` are wired, and legacy emit modes carry
migration/deprecation metadata. M3 has also landed for executable callers:
`just cli-target-first` scans `justfile`, `scripts/`, `testkit/`, and `Tests/`
for direct legacy `proof-forge --flag` invocations and runs
`Tests/CliTargetFirst.lean` to lock representative target-first mappings. The
remaining transition work is M4: remove `EmitMode` and the legacy flag parser
only after the compatibility release window.

## Problem

`ProofForge/Cli.lean` has grown to approximately 136 emit modes and ~130 flag
patterns. Every fixture, target, and artifact kind is exposed as a separate
CLI flag:

- `--evm-bytecode`, `--emit-counter-ir-yul`, `--emit-counter-ir-bytecode`
- `--emit-counter-ir-psy`, `--emit-counter-ir-sbpf`, `--emit-counter-ir-wasm-near`
- `--solana-clock-sysvar-elf`, `--solana-spl-token-transfer-cpi-elf`, ...
- `--learn`, `--learn-yul`, `--learn-bytecode`, `--learn-sbpf`, `--learn-target`, ...

This flag zoo has three concrete costs:

1. **It contradicts the stable interface promised in RFC 0001.** That RFC and
the README describe the CLI as `proof-forge build --target <id>`. Only
`--learn`/`--learn-token` accept `--target` today; the rest require the caller
to know internal `EmitMode` constructor names.
2. **It blocks testkit M4.** Workstream 26 M4 is about to wire scenario
harnesses to these flags. Once the testkit binds to the flag zoo, the flag zoo
becomes API and cannot be changed without breaking the scenario schema.
3. **It multiplies merge conflicts.** The 2026-07 consolidation showed that
nearly every backend addition conflicts in the same CLI file because flags,
`EmitMode`, usage text, and parser branches are all edited by hand.

## Summary

Introduce a small, target-first CLI surface:

```text
proof-forge build --target <id> [--fixture <id>] [--out <dir>] [input]
proof-forge emit  --target <id> --fixture <id> --format <kind> [-o <file>]
proof-forge check --target <id> [input]
```

- `build` compiles a user-supplied Lean contract (or a built-in fixture) to the
  target's primary artifact.
- `emit` renders a built-in IR fixture to an intermediate target representation
  (Yul, WAT, sBPF assembly, Psy, etc.).
- `check` runs static validation: capability checks, toolchain presence, and
  schema validation without producing a full artifact.

Built-in fixtures move from per-flag constructors to a registry keyed by id
(`counter`, `value-vault`, `context`, `hash`, `map`, `assert`, ...). Target id,
fixture id, and artifact format become parameters, not modes.

Legacy flags are kept as thin aliases for one release, emit a deprecation
warning, and are then removed.

## Design Goals

- **Stable, documentable CLI:** A user can discover supported targets with
  `proof-forge --list-targets` and supported fixtures with
  `proof-forge --list-fixtures`.
- **No mode explosion:** Adding a new fixture or target adds one registry entry,
  not two to twenty new flags.
- **Testkit binds to the stable surface:** Scenario harnesses invoke
  `proof-forge build|emit|check`, not `--emit-*-ir-*`.
- **Backward-compatible transition:** Existing CI and smoke scripts keep working
  during the transition; deprecation warnings guide migration.

Non-goals:

- This RFC does not change IR semantics, capability sets, or target bindings.
- It does not add new targets or new fixtures; it only changes how existing
  ones are invoked.
- It does not redesign the artifact/deploy JSON schemas (see Workstream 30).

## Proposed CLI Surface

### Commands

| Command | Purpose | Typical input |
|---|---|---|
| `build` | Full compile: Lean source or fixture → target artifact | `input.lean` or `--fixture <id>` |
| `emit` | Render a built-in fixture to an intermediate representation | `--fixture <id>` |
| `check` | Static validation only (capabilities, tools, schema) | `input.lean` or `--fixture <id>` |

### Common options

| Option | Applies to | Meaning |
|---|---|---|
| `--target <id>` | all | Target profile id (`evm`, `solana-sbpf-asm`, `wasm-near`, ...) |
| `--fixture <id>` | build, emit, check | Built-in fixture id instead of user source |
| `--out <path>` | build, emit | Output file or directory |
| `--root <dir>` | build, check | Lean package root (default `.`) |
| `--module <Name>` | build, check | Lean module name inside the package |
| `--artifact-output <file>` | build | Emit `proof-forge-artifact.json` |
| `--format <kind>` | emit | Intermediate format (`yul`, `bytecode`, `wat`, `s`, `psy`, ...) |

### `build` examples

```sh
# Compile a Lean contract to EVM bytecode.
proof-forge build --target evm -o build/evm/Counter.bin Examples/Backend/Evm/Contracts/Counter.lean

# Build the built-in Counter fixture for NEAR.
proof-forge build --target wasm-near --fixture counter -o build/near

# Build the built-in Counter fixture for Solana direct-assembly.
proof-forge build --target solana-sbpf-asm --fixture counter -o build/solana
```

### `emit` examples

```sh
# Render the Counter IR fixture to Yul (equivalent to old --emit-counter-ir-yul).
proof-forge emit --target evm --fixture counter --format yul -o build/counter.yul

# Render the Counter IR fixture to WAT for CosmWasm/NEAR host ABI.
proof-forge emit --target wasm-near --fixture counter --format wat -o build/counter.wat

# Render the Counter IR fixture to sBPF assembly.
proof-forge emit --target solana-sbpf-asm --fixture counter --format s -o build/counter.s

# Render the Counter IR fixture to Psy.
proof-forge emit --target psy-dpn --fixture counter --format psy -o build/counter.psy
```

### `check` examples

```sh
# Validate that a Lean contract can be lowered to the target.
proof-forge check --target wasm-near Examples/Near/Counter.lean

# Validate a built-in fixture against a target capability set.
proof-forge check --target solana-sbpf-asm --fixture value-vault
```

## Fixture Registry

Built-in fixtures are currently encoded as `EmitMode` constructors. They become
a registry in `ProofForge.Cli.Fixture` (or `ProofForge.Target.Fixture`):

```text
FixtureId  | Sources / Capabilities                    | Default formats by target
counter    | IR.Examples.Counter                       | yul, bytecode, wat, s, psy
value-vault| Contract.Examples.ValueVault              | yul, bytecode, s
context    | IR.Examples.ContextProbe                  | yul, bytecode, wat, psy
hash       | IR.Examples.HashProbe                     | yul, bytecode, wat, psy
map        | IR.Examples.MapProbe                      | yul, bytecode, wat
assert     | IR.Examples.AssertProbe                   | yul, bytecode, psy
...        | ...                                       | ...
```

Each fixture entry carries:

- `id : String`
- `module : Name` — the Lean module that produces the IR
- `capabilities : Array CapabilityId` — for capability gating in `check`/`build`
- `defaultFormats : Array String` — formats the fixture supports
- `targetOverrides : TargetId → FormatOptions` — per-target tweaks (e.g. EVM
  constructor args, Solana account schemas)

The CLI enumerates the registry for `--list-fixtures` and rejects unknown
fixture ids with a diagnostic that lists valid ids.

## Target Binding

The target profile (`ProofForge.Target.Registry`) already carries `id`,
`family`, `artifactKind`, and `capabilities`. The CLI uses this registry to:

1. Resolve `--target` to a `TargetProfile`.
2. Choose the default artifact kind for `build`.
3. Validate that the requested `--format` is in the target family's supported
   set.
4. Run capability checks before lowering.

Target-specific options (e.g. `--solana-sbpf-arch`, `--evm-chain-profile`,
`--evm-constructor-param`) remain as typed options scoped to the relevant
target family. They are accepted only when `--target` resolves to a profile
that declares the matching capability or required tool.

## Legacy Flag Aliases

For one release, the existing flag set is interpreted as an alias layer that
rewrites to the new command surface. Examples:

| Legacy flag | New equivalent |
|---|---|
| `--evm-bytecode` | `build --target evm` |
| `--emit-counter-ir-yul` | `emit --target evm --fixture counter --format yul` |
| `--emit-counter-ir-bytecode` | `emit --target evm --fixture counter --format bytecode` |
| `--emit-counter-ir-psy` | `emit --target psy-dpn --fixture counter --format psy` |
| `--emit-counter-ir-sbpf` | `emit --target solana-sbpf-asm --fixture counter --format s` |
| `--emit-counter-ir-wasm-near` | `emit --target wasm-near --fixture counter --format wat` |
| `--emit-solana-system-cpi-sbpf` | `emit --target solana-sbpf-asm --fixture system-cpi --format s` |
| `--emit-solana-system-create-account-cpi-sbpf` | `emit --target solana-sbpf-asm --fixture system-create-account-cpi --format s` |
| `--emit-solana-spl-token-transfer-cpi-sbpf` | `emit --target solana-sbpf-asm --fixture spl-token-transfer-cpi --format s` |
| `--emit-solana-spl-token-ops-cpi-sbpf` | `emit --target solana-sbpf-asm --fixture spl-token-ops-cpi --format s` |
| `--emit-solana-spl-token-close-account-cpi-sbpf` | `emit --target solana-sbpf-asm --fixture spl-token-close-account-cpi --format s` |
| `--emit-solana-spl-token-authority-cpi-sbpf` | `emit --target solana-sbpf-asm --fixture spl-token-authority-cpi --format s` |
| `--learn --target evm` | `build --target evm` on a `.learn` input |
| `--learn-yul` | `build --target evm --format yul` on a `.learn` input |
| `--learn-sbpf` | `build --target solana-sbpf-asm` on a `.learn` input |
| `--solana-elf` | `build --target solana-sbpf-asm` |
| `--solana-clock-sysvar-elf` | `emit --target solana-sbpf-asm --fixture clock-sysvar` |

Aliases emit a deprecation warning to stderr and a migration note. The warning
includes the exact new command so users and scripts can update mechanically.

## Internal Refactoring

The CLI internal state changes from a single `EmitMode` enum to a command +
target + fixture + format model:

```lean
inductive Command where
  | build
  | emit
  | check
  | listTargets
  | listFixtures

structure CliOptions where
  cmd : Command
  targetId : String
  fixture? : Option String := none
  format? : Option String := none
  input? : Option FilePath := none
  output? : Option FilePath := none
  root? : Option FilePath := none
  moduleName? : Option Name := none
  -- target-family scoped options remain:
  evmChainProfile? : Option String := none
  evmConstructorParams : Array ConstructorParamSpec := #[]
  evmConstructorValues : Array ConstructorValueSpec := #[]
  evmConstructorArgsHex : String := ""
  solanaSbpfArch : String := "v3"
  -- ...
```

`EmitMode` is retained only as the alias-layer decode target; new code does not
add constructors to it. Once aliases are removed, `EmitMode` is deleted.

## Acceptance Criteria

- `proof-forge build --target evm Examples/Backend/Evm/Contracts/Counter.lean` produces
  the same bytecode as the old `--evm-bytecode` path.
- `proof-forge emit --target evm --fixture counter --format yul` produces the
  same Yul as the old `--emit-counter-ir-yul` path.
- `proof-forge check --target wasm-near --fixture map` fails with a clear
  capability diagnostic if the fixture uses an unsupported capability.
- `--list-targets` and `--list-fixtures` print machine-readable ids.
- Every legacy flag used in `just check` / `just evm-all` / `just solana-light`
  has a deprecation warning and a documented new equivalent.

## Milestones

1. **M1 — landed:** Define fixture registry, add `Command`/`CliOptions`
   refactor, and implement `build`/`emit`/`check` for the three primary targets
   (`evm`, `solana-sbpf-asm`, `wasm-near`). Keep legacy flags working as
   aliases.
2. **M2 — mostly landed:** Implement `--list-targets`, `--list-fixtures`, and
   deprecation warnings for legacy flags used in CI. Remaining M2 work is only
   parity cleanup where a legacy path lacks a stable target-first equivalent.
3. **M3 — landed:** `scripts/`, `testkit/`, and executable `Tests/`
   invocations use the new surface; `just cli-target-first` enforces that
   runtime callers stay on `build`/`emit`/`check` and that representative
   target-first mappings keep their legacy-equivalent behavior.
4. **M4 — open:** Remove the `EmitMode` enum and legacy flag parser after one
   release of deprecation warnings.

## Non-goals

- No new contract examples or new IR constructors.
- No change to artifact/deploy JSON schema versioning (Workstream 30).
- No removal of target-family-specific options; they become scoped instead of
  global.

## Related

- [RFC 0001](0001-multichain-platform.md): promised `build --target <id>` surface.
- [RFC 0002](0002-target-implementation-design.md): target profiles and artifact kinds.
- [RFC 0007](0007-unified-rust-test-framework.md): testkit scenarios that must bind to the stable CLI.
- [Workstream 26](../implementation-backlog.md#workstream-26-unified-rust-test-framework-testkit): testkit M4.
- [Workstream 30](../implementation-backlog.md#workstreams-2933-platform-hardening-planning-first): versioning and compatibility policy.
