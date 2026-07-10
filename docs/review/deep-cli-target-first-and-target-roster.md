# Deep-dive: CLI target-first surface and honest target roster

**Topic:** `cli-target-first-and-target-roster`
**Project:** ProofForge (`/Users/davirian/orca/projects/proof_forge`)
**Date:** 2026-07-10
**Branch:** `main` (dirty files unrelated to this topic)

---

## 1. How `ProofForge.Cli.TargetFirst` rewrites product commands to legacy flags

The documented product surface is:

```text
proof-forge build|emit|check --target <id> …
```

Today, **`build` and `emit` are implemented but still translate into the legacy `--emit-*` / `--*-bytecode` flag zoo**; **`check` is already native** and does not go through the legacy parser.

### 1.1 Translation layer

`ProofForge/Cli/TargetFirst.lean:167-221` defines `newCommandArgsToLegacy`:

- For `build`, it calls `buildLegacyFlag` (a thin wrapper over the per-target `TargetCliDriver.resolveBuild`) and then appends `-o`, `--root`, `--module`, `--yul-output`, `--artifact-output`, EVM constructor options, `--solc`/`--cast`, `--solana-sbpf-arch`, `--peer`, `--peers-demo`, and the input file.
- For `emit`, it calls `emitLegacyFlag` (driver `resolveEmit`) and appends the same output/control options.
- For `check`, the branch immediately returns `Except.error "proof-forge check is not yet implemented"` (`ProofForge/Cli/TargetFirst.lean:218-219`).

The per-target resolution is in `ProofForge/Cli/TargetDriver.lean`:

- `evmResolveBuild` / `evmResolveEmit` (`ProofForge/Cli/TargetDriver.lean:47-92`) map product requests to flags such as `--evm-bytecode`, `--emit-counter-ir-yul`, `--emit-counter-ir-bytecode`, `--learn-yul`, `--learn-token`, etc.
- `solanaResolveBuild` / `solanaResolveEmit` (`ProofForge/Cli/TargetDriver.lean:94-173`) map to `--contract-source-sbpf`, `--contract-source-solana-elf`, `--emit-counter-ir-sbpf`, `--solana-*-elf`, etc.
- `nearResolveBuild` / `nearResolveEmit` (`ProofForge/Cli/TargetDriver.lean:175-214`) map to `--contract-source-emitwat` and `--emit-*-emitwat` / `--emit-*-ir-wasm-near`.
- Secondary drivers (`sorobanResolveBuild`, `cosmwasmResolveBuild`, `psyResolveBuild`, `aleoResolveBuild`, `aptosResolveBuild`, `suiResolveBuild`, `cloudflareResolveBuild`, `quintResolveEmit`) live at `ProofForge/Cli/TargetDriver.lean:216-370` and are mostly fixture-only or error-closed for source builds.
- All drivers are registered in `cliDrivers` (`ProofForge/Cli/TargetDriver.lean:374-386`).

### 1.2 Main dispatch

`ProofForge/Cli.lean:303-415` is the executable entry point:

- `build` (`ProofForge/Cli.lean:333-346`): `parseNewOptions` → `newCommandArgsToLegacy "build"` → `parseArgs` (the legacy parser in `ProofForge/Cli/LegacyArgs.lean`) → `compileFile`.
- `emit` (`ProofForge/Cli.lean:347-361`): same pattern, ending in `compileFile`.
- `check` (`ProofForge/Cli.lean:362-376`): bypasses `newCommandArgsToLegacy` and constructs a `CliOptions` with `cmd := .check`, then calls `ProofForge.Cli.checkCommand` (`ProofForge/Cli.lean:402-403` / `ProofForge/Cli/Check.lean:457-470`).
- `--list-targets` / `--list-fixtures` are native (`ProofForge/Cli.lean:326-401`).
- `init`, `deploy`, and `metadata` are native subcommands handled before the target-first fallback (`ProofForge/Cli.lean:305-322`).

### 1.3 Native vs stubbed verbs

| Verb | Status | Evidence |
|------|--------|----------|
| `build` | **Implemented via target-first parser, but rewritten to legacy flags** | `ProofForge/Cli/TargetFirst.lean:167-199`, `ProofForge/Cli.lean:333-346` |
| `emit` | **Implemented via target-first parser, but rewritten to legacy flags** | `ProofForge/Cli/TargetFirst.lean:200-217`, `ProofForge/Cli.lean:347-361` |
| `check` | **Native** (no legacy rewrite) | `ProofForge/Cli.lean:362-376`, `ProofForge/Cli/Check.lean:457-470` |
| `--list-targets` / `--list-fixtures` | **Native** | `ProofForge/Cli.lean:326-401`, `ProofForge/Cli/TargetJson.lean:345-350` |
| `deploy` / `init` / `metadata` | **Native subcommands**, not target-first | `ProofForge/Cli.lean:305-322` |

So the only remaining legacy-routed product verbs are `build` and `emit`; `check` is already on the native path, despite the misleading stub in `newCommandArgsToLegacy`.

---

## 2. Which registry targets are truly `contract-source` buildable, fixture/emit-only, or research spikes

The registry is authoritative (`ProofForge/Target/Registry.lean:81-483`). The generated matrix is in `docs/generated/backend-status.md`. Reality is stricter than the registry's `inputModes` field suggests, because only the primary triad has real `TargetBackend` `validateModule?` / `ensurePlan?` / `ensurePackage?` hooks (`ProofForge/Target/BackendRegistry.lean:77-96`, `Tests/TargetBackend.lean:24-47`).

### 2.1 Truly `contract-source` buildable for product examples

| Target | Why it counts | Caveats |
|--------|---------------|---------|
| `evm` | `support` = primary triad; real backend hooks; `product` gate builds `Examples/Product/Counter.lean`, `RemoteCall.lean`, etc. | Deepest backend; TokenSpec and full ERC suite supported. |
| `solana-sbpf-asm` | `support` = primary triad; real backend hooks; `product` gate builds Counter and RemoteCall to `.s`/ELF. | CPI/PDA are extensions; TokenSpec only partially wired (`product-token-solana`). |
| `wasm-near` | `support` = primary triad; real backend hooks; `product` gate builds Counter/RemoteCall to WAT/Wasm. | NEAR SDK gaps remain (`keccak256`, `storage_remove`, NEP standards, dynamic Borsh) per `docs/sdk-ecosystem-gaps-2026-07.md`. |

Evidence:
- `ProofForge/Target/Registry.lean:81-148` defines these three with `TargetSupport.primaryTriad`.
- `ProofForge/Target/BackendRegistry.lean:77-96` registers `evmBackend`, `solanaBackend`, `nearBackend` with real hooks.
- `Tests/TargetSupport.lean:23-35` asserts only these three are `isPrimarySource` with `build`/`check`/`package` validation.
- `scripts/portable/counter-multi-target.sh:28-53` and `scripts/portable/remote-call-multi-target.sh:46-67` exercise source builds.

### 2.2 Counter-MVP host adapters (advertise `contract_source`, but limited)

| Target | Registry claim | Honest status |
|--------|----------------|---------------|
| `wasm-cosmwasm` | `inputModes` includes `contractSource`; `build`/`check` advertised (`ProofForge/Target/Registry.lean:150-179`) | Host-bridge adapter via `EmitWat` + `HostBridge.cosmWasm`; `execute_msg` is a stub (`ProofForge/Target/Registry.lean:175-178`); no real backend hooks (`Tests/TargetBackend.lean:54-61`). Only Counter-shaped sources are expected to pass. |
| `wasm-stellar-soroban` | `inputModes` = `contractSource`; `build`/`check` advertised (`ProofForge/Target/Registry.lean:218-251`) | Host-bridge adapter via `EmitWat` + `HostBridge.soroban`; auth is always-auth in Lean (`ProofForge/Backend/WasmHost/SorobanHost.lean:78-90`); Stellar CLI/TTL follow-on; no TokenSpec lane. |

### 2.3 Fixture/emit-only or research-spike targets

| Target | Maturity (registry) | Input | Commands | Honest classification |
|--------|---------------------|-------|----------|-----------------------|
| `wasm-cloudflare-workers` | `counter-mvp` | `fixture` only | `emit` only | Research spike: emits TypeScript only, not Wasm (`ProofForge/Target/Registry.lean:181-211`). |
| `move-aptos` | `counter-mvp` | `fixture` only | `build`/`emit`/`check` | Counter-only fixture spike; product source fail-closed (`ProofForge/Target/Registry.lean:330-357`, `scripts/cli/aptos-promotion-smoke.sh:35-43`). |
| `move-sui` | `counter-mvp` | `fixture` only | `build`/`emit`/`check` | Counter-only; only `storageScalar`, `assertions`, `accountExplicit` (`ProofForge/Target/Registry.lean:359-378`, `scripts/cli/sui-promotion-smoke.sh:18-26`). |
| `aleo-leo` | `counter-mvp` | `fixture` only | `emit`/`check` | Road 1 sourcegen spike; private records/proofs are Road 2 (`docs/targets/aleo-leo.md`, `ProofForge/Target/Registry.lean:422-453`). |
| `psy-dpn` | `spike` | `fixture` only | `build`/`emit`/`check` | Research spike; requires `dargo` which is not in the default toolchain (`AGENTS.md:43`). |
| `quint` | CLI-only (not in `knownIds`) | fixtures/scenarios | `emit` only | Formal-verification target, not a deployable backend (`ProofForge/Cli/TargetDriver.lean:348-370`, `ProofForge/Target/Registry.lean:482`). |

Evidence:
- `Tests/TargetSupport.lean:37-46` asserts `move-aptos`, `psy-dpn`, `aleo-leo`, `wasm-cloudflare-workers` must be fixture-only.
- `ProofForge/Cli/Check.lean:208-214` lists fixture-only source targets that fail closed: `wasm-cloudflare-workers`, `psy-dpn`, `aleo-leo`, `move-aptos`, `move-sui`.
- `ProofForge/Cli/TargetDriver.lean:238-242` `fixtureOnlyBuild` rejects source inputs for these targets.

---

## 3. Honest public target support matrix to advertise today

Do **not** market ProofForge as a 10-target compiler. The support surface that is honest for a public beta is:

| Tier | Targets | What users can do |
|------|---------|-------------------|
| **Production compilers** | `evm`, `solana-sbpf-asm`, `wasm-near` | Build real `Examples/Product/*.lean` contracts to deployable artifacts (bytecode/ELF/Wasm). `check` runs full package validation. |
| **Counter-MVP host adapters** | `wasm-cosmwasm`, `wasm-stellar-soroban` | `build --target … Examples/Product/Counter.lean` may produce a WAT/Wasm artifact, but the surface is intentionally narrow and several host features are stubs. |
| **Fixture/research spikes** | `wasm-cloudflare-workers`, `move-aptos`, `move-sui`, `aleo-leo`, `psy-dpn` | `emit --fixture counter` and `check --fixture counter` only. Product `.lean` sources are rejected. |
| **Verification target** | `quint` | `emit --target quint --fixture …` for model-checking only; not in `--list-targets`. |

The machine-readable registry already encodes this in `ProofForge/Target/Support.lean` (`experimental`, `counter-mvp`, `spike`, `research`) and is rendered in `docs/generated/backend-status.md`. The gap between registry claims and real backend depth is the main credibility risk; the registry should be the source of truth for marketing copy.

---

## 4. What would need to change to finish RFC 0009 M4 (remove the legacy surface)

RFC 0009 M4 aims to delete the legacy flag zoo so the only supported surface is `build|emit|check --target <id>`. Current inventory: `ProofForge/Cli/EmitMode.lean` has **158 constructors** and `ProofForge/Cli/LegacyArgs.lean` has **~183 legacy flag parse arms** (`docs/cli-m4-legacy-inventory.md:25-26`).

### 4.1 Files and functions to change

1. **Delete `ProofForge/Cli/EmitMode.lean` or shrink it to zero.**
   - Remove all 158 constructors (e.g. `counterIrYul`, `solanaSplToken2022TransferHookElf`, etc.) and the `CliOptions.mode` field.

2. **Delete `ProofForge/Cli/LegacyArgs.lean`.**
   - Remove the ~183 `--emit-*`, `--learn-*`, `--solana-*`, etc. parse arms.
   - Migrate any still-needed global options (`-o`, `--root`, `--module`, EVM constructor flags, `--solana-sbpf-arch`) into the target-first parser in `ProofForge/Cli/TargetFirst.lean`.

3. **Rewrite `ProofForge/Cli.lean` dispatch.**
   - Remove the `compileFile` giant `match opts.mode with` (`ProofForge/Cli.lean:141-300`) that calls one function per `EmitMode`.
   - Replace it with a registry-driven dispatcher: given `targetId`, `fixture?`, `format?`, `input?`, look up the `TargetBackend` and/or a fixture-to-compiler map and invoke the correct compiler function directly.
   - Update `main` so `build`/`emit` no longer call `parseArgs` (`ProofForge/Cli.lean:338-344`, `351-359`); they should call the new dispatcher.
   - Keep `check` as-is (it is already native).

4. **Change `ProofForge/Cli/TargetFirst.lean`.**
   - `newCommandArgsToLegacy` should be replaced by a function that returns a structured build/emit request (target + fixture + format + input + options) instead of a list of legacy flags.
   - The output-path helpers (`targetFirstNativeOutput`, `targetFirstYulOutput?`, `ProofForge/Cli/TargetFirst.lean:130-148`) can remain, but should be called by the dispatcher, not by a legacy rewrite.

5. **Change `ProofForge/Cli/TargetDriver.lean`.**
   - `resolveBuild` and `resolveEmit` currently return `Except String String` (a legacy flag). They should return either a compile action/closure or a small AST describing what to compile.
   - `cliDrivers` (`ProofForge/Cli/TargetDriver.lean:374-386`) should map target ids to compiler functions, not to flag strings.

6. **Update `ProofForge/Cli/Usage.lean`.**
   - Remove the "Usage (legacy + full surface):" catalog (`ProofForge/Cli/Usage.lean:23+`) and keep only the product-path examples.

7. **Update tests.**
   - `Tests/CliTargetFirst.lean` currently asserts legacy flag equivalences. It should assert direct output-path or compiler-call equivalences.
   - `Tests/TargetBackend.lean` already asserts the right backend hooks and can remain with minor import cleanup.

8. **Update docs and migration gate.**
   - `docs/cli-m4-legacy-inventory.md` and `docs/cli-m4-deletion-checklist.md` should be closed out.
   - `scripts/cli/check-target-first-migration.py` can be retired (or turned into a docs-only legacy-flag detector).

### 4.2 Rough scope

| Area | Approx. change |
|------|----------------|
| Delete `EmitMode` constructors | 158 constructors (~200 lines) |
| Delete `LegacyArgs` legacy arms | ~183 arms (~250 lines) |
| Rewrite `compileFile` / main dispatch | ~150-250 lines new, ~150 lines removed |
| Convert `TargetDriver` to action registry | ~100-150 lines |
| Update `Usage.lean` | ~160 lines removed |
| Update `Tests/CliTargetFirst.lean` | ~100 lines |
| Docs / inventory retirement | ~50 lines |
| **Total** | **~1.0-1.5 kloc churn, mostly deletion** |

The actual semantic work is smaller than the line count: the compiler functions already exist; M4 is primarily about routing them through the registry instead of through a 158-constructor enum.

---

## Top 3 findings

1. **`build`/`emit` are still legacy translations; `check` is already native.** The target-first surface is usable, but `ProofForge.Cli.TargetFirst.newCommandArgsToLegacy` converts every `build`/`emit` call into an old `--emit-*` or `--*-bytecode` flag, then re-parses it with `LegacyArgs`. `check` bypasses this entirely.

2. **Only three targets are real product compilers.** `evm`, `solana-sbpf-asm`, and `wasm-near` have actual `TargetBackend` validate/plan/package hooks and are exercised by `just product` on real `Examples/Product/*.lean` sources. The other seven registry entries are Counter-MVP adapters, fixture-only spikes, or research targets.

3. **M4 is a large but mechanical cleanup.** Finishing RFC 0009 M4 means deleting the 158-constructor `EmitMode` enum, the ~183-arm `LegacyArgs` parser, and the giant `compileFile` mode match, then wiring `TargetDriver` to call compiler functions directly. Most compiler logic can be reused; the bulk of the work is deletion and dispatcher wiring.
