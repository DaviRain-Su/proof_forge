# AGENTS.md

This file is the required entry point for agents working in this repository.
It is a control plane, not a replacement for design specifications or task
plans. Start here, follow the linked current documents, and leave the control
plane synchronized when work is complete.

## Project Mission

ProofForge is a Lean 4 compiler/CLI (`proof-forge`) that lowers portable smart
contract sources through checked canonical IR into target plans and artifacts.
The current architecture program, D-052, adds a target-neutral intent and
materializer boundary while preserving the existing primary-triad behavior.

For the public beta, only three targets are advertised as `contract_source`
compilers: `evm`, `solana-sbpf-asm`, and `wasm-near`. Legacy `ContractSpec`
inputs and target adapters are migrated incrementally behind equivalence tests;
do not delete a compatibility path until all callers and fixtures have moved.

## Current Checkpoint

Keep this section short and update it whenever the active task changes.

| Field | Current value |
|---|---|
| Program | Arbitrum Stylus general-contract completion |
| Active task | W7 release integration review |
| Next task | Audit stylus-all membership, four-worker lanes, CI artifact persistence, bilingual status claims, and deferred final regression |
| Known blocker | Nitro needs Docker; Woodpecker durable artifacts need a configured sink/credentials |
| Execution queue | [`docs/superpowers/plans/2026-07-13-arbitrum-stylus-completion.md`](docs/superpowers/plans/2026-07-13-arbitrum-stylus-completion.md) |
| Detailed history | [`docs/implementation-log.md`](docs/implementation-log.md) |

The checkpoint is a navigation aid, not proof that a task is complete. A task
is complete only when its acceptance criteria and reproducible validation are
recorded in the current plan and implementation log.

## Mandatory Reading Order

Before editing code or accepting a task:

1. Read this file completely.
2. Check `git status --short` and recent commits; do not overwrite unrelated
   worktree changes.
3. Read the [documentation lifecycle index](docs/document-status.md).
4. Read the [current architecture design](docs/superpowers/specs/2026-07-12-portable-intent-abstraction-design.md).
5. Read the [current implementation plan](docs/superpowers/plans/2026-07-12-portable-intent-abstraction.md).
6. Read the active task section, its referenced source/tests, and the relevant
   target note or RFC.
7. Check the [backlog](docs/implementation-backlog.md),
   [gate ledger](docs/gate-status.md), and
   [validation catalog](docs/validation-gates.md) before claiming completion.

Do not load the full historical `docs/development-log.md` by default. Search it
only when older implementation evidence is needed.

## Source Of Truth

When sources disagree, use this precedence:

1. Checked-in code, generated artifacts, and reproducible runnable gates.
2. This file's current checkpoint for navigation only.
3. Accepted decisions and current architecture design.
4. The current implementation plan and gate ledger.
5. The current backlog and target roadmap.
6. Historical plans, audits, and development-log entries.

Documentation claims must be verified against code before being repeated.
Historical documents never reopen or reschedule work by themselves.

## Current Program

The authoritative task details and acceptance criteria live in the
[July 12 implementation plan](docs/superpowers/plans/2026-07-12-portable-intent-abstraction.md).
This table is only the agent routing index.

| ID | State | Task | Authoritative task section |
|---|---|---|---|
| A1 | done (verified at 6af4eb72) | Isolate Solana grammar ownership | Plan Task 1 |
| A2 | done (review repaired) | Add the intent materializer contract | Plan Task 2 |
| A3 | done | Define target-neutral NFT intent | Plan Task 3 |
| A4 | done | Audit NFT implementation candidates | Plan Task 4 |
| A5 | done (review repaired) | Add primary-triad NFT materializers | Plan Task 5 |
| A6 | done (verified at 6a6022ea) | Open the NFT CLI and product route | Plan Task 6 |
| D3 | done (verified at 545d7a51) | Make accepted NFT materialization strict | Legacy replacement Task D3 |
| D4 | done (verified at 19c93baf) | Open NFT through native target-first dispatch | Legacy replacement Task D4 |
| B1 | done (verified at c8d2bbb6) | Extract a neutral Wasm-host plan | Plan Task 7 |
| B2 | done (verified at d4df51bc) | Add a strict canonical target gate | Plan Task 8 |
| B3 | done | Promote Soroban Counter (full bridge-aware lowering) | Plan Task 9 |
| C1 | pending after A6 | Add PSy canonical planning | Plan Task 10 |
| C2 | pending after C1 | Add an Aleo semantic plan | Plan Task 11 |
| C3 | pending | Write the sourced OpenVM target brief | Plan Task 12 |

Allowed task states are `pending`, `in_progress`, `blocked`, and
`done (verified at <sha>)`. Use `blocked` only with a concrete blocker and the
command or dependency needed to clear it. Never use prose such as "mostly
done" as a state.

## Task Execution Protocol

For every implementation or review task:

1. Reconcile this checkpoint and the task plan with the actual branch,
   worktree, code, and tests.
2. Mark exactly one task `in_progress` in this file and the authoritative plan.
3. Write or identify the failing acceptance test before changing behavior.
4. Implement the smallest slice that satisfies the task boundary. Preserve the
   shared architecture; do not bypass it with target-specific frontend routing.
5. During implementation, run only gates directly affected by the current
   change. Reserve `just product`, `just check`, `just stylus-all`, and other
   full aggregates for the final integration checkpoint or an explicit request;
   do not pay their cost after every development slice.
6. Review the diff for unsupported claims, legacy-path regressions, accidental
   generated output, and unrelated edits.
7. Update the task plan, backlog, gate evidence, implementation log, and this
   checkpoint in the same change.
8. Commit or hand off with exact changed files, commands, results, limitations,
   and the next task. A checkpoint without verification is not completion.

If reviewing another agent's result, inspect its commit range and rerun the
acceptance gates. Fix discovered problems before marking the task verified.

## Documentation Update Protocol

Update documentation according to the type of change:

| Change | Required documentation |
|---|---|
| Task starts or ownership changes | Current checkpoint and current plan |
| Task completes | Current plan, backlog, implementation log, current checkpoint |
| Gate criterion changes | `docs/gate-status.md` with reproducible evidence |
| Architecture boundary changes | `docs/decisions.md`, current design, lifecycle index |
| Target support or maturity changes | target note, target roadmap, README status table |
| Public validation command changes | `docs/validation-gates.md` and this file when baseline behavior changes |
| Current document is superseded | `docs/document-status.md`; retain the old path as historical evidence |

Append concise task records to
[`docs/implementation-log.md`](docs/implementation-log.md). The log records
what landed and how it was verified; it does not replace plan checklists or gate
sign-off. `docs/development-log.md` remains the detailed historical stream and
is not the current agent ledger.

When an English document is mapped in `scripts/i18n/manifest.json`, update its
translation in the same change. Run `just docs-check` after documentation
changes and `git diff --check` before handoff.

## Registry vs CLI-only Targets

| Surface | Targets |
|---|---|
| Primary triad `contract_source` compilers (maturity `experimental`) | `evm`, `solana-sbpf-asm`, `wasm-near` |
| `proof-forge --list-targets` / `ProofForge.Target.knownIds` | `evm`, `solana-sbpf-asm`, `wasm-near`, `wasm-cosmwasm`, `wasm-cloudflare-workers`, `wasm-stellar-soroban`, `wasm-arbitrum-stylus`, `move-aptos`, `move-sui`, `psy-dpn`, `aleo-leo` |
| `proof-forge emit --target ...` fixture whitelist | Above plus `quint` (verification; CLI-only). `wasm-stellar-soroban` uses EmitWat plus `HostBridge.soroban`, not a separate codegen core. |

The remaining registry entries are Counter-MVP, fixture, or research spikes.
The formal-verification target `quint` is CLI-only and is not listed by
`--list-targets`. See README "Backend Status" for the full stage table.

## Product And Backend CI

CI is product-first: required `just product` runs before backend-heavy suites.

| Gate | Command | CI |
|---|---|---|
| Product (required, fail-fast) | `just product` | GitHub `product`; Woodpecker `proof-forge-product` |
| Fast affected-path baseline | `just check-fast` (fixed core/product + focused changed targets) | Local inner loop |
| Full parallel baseline | `just check` / `just check-parallel` (108 recipes, default max 4 workers) | GitHub lane matrix; Woodpecker `proof-forge-check`; local pre-push |
| Serial full reference | `just check-serial` | Local race diagnosis and coverage reference |
| Backend-heavy | `build-test` after `product` | GitHub `build-test` (`needs: product`) |

Optional GitHub jobs with `continue-on-error` are `aleo-smoke`,
`cloudflare-smoke`, `cosmwasm-smoke`, `aptos-smoke`, and
`solana-pinocchio-live`. Sui gates (`just sui-*`) are local-only and require the
`sui` CLI.

`just ci` is a local CI-flavored aggregate, not a strict subset of GitHub's
`build-test`. To reproduce `build-test`, run its steps from
`.github/workflows/ci.yml`. `sdk-schema`, `cli-deploy`, and `cli-check` are in
`just check` but not in that GitHub job.

## Build, Test, And Run

The root `justfile` is the canonical command catalog (`just --list`). Key gates:

- Build: `just build` (`lake build`).
- Product gate: `just product`. Run this first for authoring or portable-path
  changes.
- Fast inner loop: `just check-fast`. Set `CHECK_BASE=<rev>` to override the
  upstream merge-base selection.
- Full static baseline: `just check` (alias of `just check-parallel`). Automatic
  concurrency is capped at four; set `JOBS=<positive integer>` to override.
- Serial diagnostic fallback: `just check-serial`. Parallel logs and timings are
  written under `build/test-lanes/<run-id>/`.
- Full EVM gates: `just evm-all`.
- Lean commands must run through `lake env ...`.

Example target-first compile:

```bash
lake env proof-forge build --target evm --root . \
  -o build/evm/Counter.bin Examples/Product/Counter.lean
```

Product sources contain business logic plus `--target`; chain fixtures belong
under `Examples/Backend/`.

## Toolchain And Environment

- `lean` and `lake` come from `elan`; the version is pinned by
  `lean-toolchain`. If missing, run
  `elan toolchain install "$(cat lean-toolchain)"`.
- `just`, `solc` 0.8.30, Foundry (`forge`, `cast`, `anvil`), `wat2wasm`, and
  Rust/Cargo are expected on `PATH`. For non-interactive shells add
  `$HOME/.elan/bin`, `$HOME/.local/bin`, and `$HOME/.foundry/bin`.
- `sui`, `leo`, `wrangler`, Surfpool, Dargo, and Solana SBF platform tools are
  not installed in the baseline VM. Do not claim live-gate verification when
  those tools are absent.
- `just evm-all` and `just evm-anvil-deploy` start their own Anvil instance.
- Solana `*-web3` compatibility recipes are wrappers checked by
  `just solana-light`; they must only forward to Rust/live gates.
- Solana live Pinocchio and `just psy-all` are outside `just check`. Run them
  only when their external tools are available or the task explicitly requires
  them.
- Build output lives in ignored `build/` and `.lake/` directories.

## Remotes And Hosted CI

- Codeberg remote: `git@codeberg.org:davirain/proof_forge.git` (`codeberg`).
- Woodpecker configuration: `.woodpecker.yml`; it runs `just product` and then
  `just check` after `scripts/ci/woodpecker-setup.sh`.
- GitHub configuration: `.github/workflows/ci.yml`.

## Historical Documentation

The [documentation status index](docs/document-status.md) is authoritative for
current versus historical classification. Do not treat a dated plan, audit, or
completed agent ledger as a current queue merely because it remains in the
repository. Preserve historical paths for traceability and update their status
banner when they are superseded.
