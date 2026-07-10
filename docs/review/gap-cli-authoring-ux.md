# Gap Analysis: CLI / Authoring UX

**Dimension:** `cli-authoring-ux`
**Project:** ProofForge (`/Users/davirian/orca/projects/proof_forge`)
**Date:** 2026-07-10

## Executive summary

The CLI is usable for internal/CI workflows, and the target-first surface (`build`/`emit`/`check --target <id>`) is real and gated. However, the user-facing surface is still dominated by a large legacy flag zoo, lacks basic product-grade affordances (`--version`, per-command help, standalone `init`, multi-chain deploy), and uses hand-rolled argument parsing. It is closer to a compiler engineer's toolchain than a polished, production-ready compiler CLI.

**Overall maturity score: 4 / 10**

## What is healthy / complete

| Area | Evidence |
|------|----------|
| Target-first verbs exist and are tested | `ProofForge/Cli.lean:303-415`, `ProofForge/Cli/TargetFirst.lean`, `Tests/CliTargetFirst.lean` |
| `--list-targets` / `--list-targets --json` work and produce a machine-readable support matrix | `ProofForge/Cli.lean:326-397`; live command output verified |
| `check` produces structured JSON/text reports with validation stages and toolchain warnings | `ProofForge/Cli/Check.lean:36-128`; live `proof-forge check --target wasm-near ... --report-format json` verified |
| Legacy-flag migration is enforced in CI/scripts | `scripts/cli/check-target-first-migration.py`, `just cli-target-first` |
| Deprecation metadata is attached to legacy flags | `ProofForge/Cli/EmitMode.lean:362-371` |
| Strong security honesty for hosted/cloud path | `ProofForge/Cli/ContractLoader.lean:18-34` (`PROOF_FORGE_HOSTED_ISOLATION` gate) |
| Dedicated CLI unit tests | `Tests/Cli{Check,Deploy,Init,Metadata,Constructor,TargetFirst}.lean` |
| Product-path docs are clear about the intended authoring model | `docs/product-sdk.md`, `docs/product-authoring-architecture.md` |

## Top 5 product-readiness gaps

### 1. Legacy flag zoo is still the primary CLI surface

- **Severity:** High
- **Evidence:**
  - `ProofForge/Cli/EmitMode.lean` has **157** constructors (`counterIrYul`, `solanaSplToken2022TransferHookElf`, etc.).
  - `ProofForge/Cli/LegacyArgs.lean` contains ~177 distinct `--…` flag parse arms.
  - `ProofForge/Cli/Usage.lean:23` starts the help text with **"Usage (legacy + full surface):"** and lists dozens of `--emit-*` / `--learn-*` / `--solana-*` flags.
  - Running `lake env proof-forge --help` prints the legacy flag catalog before the product path.
  - RFC 0009 M4 (delete legacy surface) is deferred: `docs/cli-m4-deletion-checklist.md`, `docs/cli-m4-legacy-inventory.md`.
  - `ProofForge/Cli/TargetFirst.lean:167-221` does not dispatch natively; it *rewrites* target-first commands into legacy flags.
- **Impact:** New users see a confusing, backend-internal menu. It contradicts the documented product promise that authors only need `build --target <id>`.
- **Remediation direction:** Complete RFC 0009 M4: remove `EmitMode`, delete the legacy parser, implement native registry-based fixture/target dispatch, and make the help text show only `init/build/emit/check --target …`.

### 2. `deploy` is EVM-only and hard-coded to the Counter lifecycle

- **Severity:** High
- **Evidence:**
  - `ProofForge/Cli/Deploy.lean:444` explicitly rejects any target other than `evm`.
  - Lines `394-409` hard-code post-deploy interactions: `get()(uint256)`, `initialize()`, two `increment()` calls, and receipt comparisons.
  - Default Anvil test key/address are baked in (`defaultAnvilPrivateKey`, `defaultAnvilDeployer`, `defaultAnvilChainId` at lines `13-19`).
  - The command is essentially a Counter/Anvil smoke harness, not a generic deployment tool.
- **Impact:** A real multi-chain compiler product needs `proof-forge deploy --target solana-sbpf-asm|wasm-near|…` driven by the generated deploy manifest. Today, deployable artifacts are produced, but only EVM Anvil deployment is automated.
- **Remediation direction:** Generalize `deploy` around the existing `proof-forge-deploy.json` manifest; add target-specific broadcasters (Solana `solana program deploy`, NEAR `near-cli`, etc.); move Counter-specific smoke logic to `scripts/evm/anvil-deploy-smoke.sh`.

### 3. No `--version` and no per-command help

- **Severity:** Medium-High
- **Evidence:**
  - `lake env proof-forge --version` returns `unknown option: --version` and dumps the global usage.
  - `ProofForge/Cli.lean:303-415` handles `--list-targets` and `--list-fixtures` but has no `--version` branch.
  - `scripts/cli/check-target-first-migration.py:40-44` already allowlists `--version` as a "global meta flag", but it is unimplemented.
  - `lakefile.lean:5` pins version `v!"0.1.0"`, yet the executable never reports it.
  - `proof-forge build --help` also returns `unknown option: --help` and prints the full 187-line global usage (`ProofForge/Cli/Usage.lean`).
- **Impact:** Package managers, CI reproducibility, and user support all require a version flag. Subcommand help is a basic expectation for any CLI product.
- **Remediation direction:** Add a `--version` branch in `ProofForge/Cli.lean` that prints package version, Lean toolchain, and git commit. Implement subcommand-specific usage and honor `--help` inside `build`, `emit`, `check`, `deploy`, `metadata`, and `init`.

### 4. `init` scaffolding only works inside a ProofForge checkout

- **Severity:** Medium
- **Evidence:**
  - `ProofForge/Cli/Scaffold.lean:156-168` searches `LEAN_SRC_PATH` or parent directories for `templates/portable-counter/Counter.lean`.
  - Running `lake env proof-forge init my-counter` from `/tmp` fails with:
    `proof-forge init could not locate templates/portable-counter; run from a ProofForge checkout or set LEAN_SRC_PATH`.
  - Only one template is supported: `defaultTemplateId := "portable-counter"` (`Scaffold.lean:14`).
  - The scaffolded `README.md` references `just build-evm` but the user must manually run `lake update`.
- **Impact:** Users cannot bootstrap a standalone project from a released `proof-forge` binary. The feature is effectively monorepo-only.
- **Remediation direction:** Embed templates in the executable or install them alongside the binary; support `proof-forge init` from any directory; add additional starter templates (Token, Vault); optionally run `lake update` after scaffold.

### 5. Hand-rolled argument parser lacks standard CLI affordances

- **Severity:** Medium
- **Evidence:**
  - `ProofForge/Cli/LegacyArgs.lean`, `ProofForge/Cli/TargetFirst.lean`, and `ProofForge/Cli/Deploy.lean` all implement recursive manual parsers.
  - No support for `--flag=value`, combined short flags, `--` end-of-options, or shell completion.
  - Unknown options produce the full global usage dump (e.g. `proof-forge build --help`).
  - Option groups are duplicated across legacy and target-first parsers, creating ongoing maintenance burden.
- **Impact:** Brittle parsing, poor error UX, and repeated merge conflicts whenever a new option is added.
- **Remediation direction:** Adopt or generate a proper CLI parsing layer (a small Lean combinator library or code-generated parser) that supports POSIX-style flags, subcommands, `--help`, and shell completion.

## Additional important gaps

| # | Gap | Severity | Key evidence |
|---|-----|----------|--------------|
| 6 | `check` diagnostics do not report line/column | Medium | `ProofForge/Cli/Check.lean:68` only heuristically extracts a file string; `line?`/`column?` are always `none` in JSON output. |
| 7 | No project-level config file / multi-target manifest | Medium | Users must pass `--target`, `-o`, `--yul-output`, `--artifact-output` on every invocation; no `proof-forge.toml`-equivalent. |
| 8 | `proof-forge test --target <id>` is not implemented | Medium | Listed as planned in `docs/validation-gates.md:134`; no `Command.test` in `ProofForge/Cli/Options.lean`. |
| 9 | `metadata` command is Psy-only and not integrated | Low-Medium | `ProofForge/Cli/Metadata.lean:105` rejects any target other than `psy-dpn`; fixture list hardcoded. |
| 10 | `build` does not preflight missing tools before invoking them | Low-Medium | `proof-forge check --target evm` warns about missing `foundry`, but `build` fails mid-process with a raw process error (`cast failed with exit code 255: could not execute external process 'cast'`). |
| 11 | `--list-targets` membership is not the same as `contract_source` support | Low (documented) | `ProofForge/Cli/Usage.lean:15-18` admits many registered targets are fixture-only; users may be surprised that `build`/`check` on a `.lean` file errors for e.g. `psy-dpn`. |

## Recommended remediation priority

1. **Short-term (blocks public beta feel):** Add `--version`; implement per-command `--help`; improve the error message for missing external tools in `build`.
2. **Medium-term:** Complete RFC 0009 M4 and remove the legacy flag surface; generalize `deploy` beyond EVM/Anvil; make `init` work from any directory.
3. **Long-term:** Introduce a project config file, add a `test` verb, replace the hand-rolled parser with a generated/standard one, and enrich diagnostics with source positions.
