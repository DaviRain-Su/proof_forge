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
compilers: `evm`, `solana-sbpf-asm`, and `wasm-near`. There is one destination:
direct authoring through checked Canonical Core and target-owned plans. Do not
add compatibility, fallback, or dual-write routes. Existing Legacy callers are
isolated deletion backlog; move their callers under focused gates, then delete
the zero-caller code.

## Current Checkpoint

Keep this section short and update it whenever the active task changes.

| Field | Current value |
|---|---|
| Program | Direct authoring cutover with fail-closed native differential evidence |
| Active task | CMP-1 - implement the normalized runner result and coverage comparator on the v1 contracts from `18f15e59` |
| Next task | CMP-2 plus A-CUT2 - run Counter against independent EVM, Solana, and NEAR references while removing the remaining `ContractSpec`/`IR.Module` authored exchange value |
| Validation track | CMP-0 is done at `18f15e59`; CMP-1 is active and CMP-2 remains an A-CUT2 exit criterion |
| Known blocker | Real receipt scheduling and peer-contract execution require a sandbox/node harness; `near-vm-runner` is VM conformance only |
| Execution queue | [`docs/superpowers/plans/2026-07-14-cross-target-native-differential.md`](docs/superpowers/plans/2026-07-14-cross-target-native-differential.md) |
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

The active NEAR execution order lives in the
[NEP-141 / NEP-145 interop plan](docs/superpowers/plans/2026-07-13-near-nep141-interop-execution.md).
Do not reopen completed U128, AccountId-string, `storage_remove`, gas-context,
or JSON balance/transfer slices from stale gap prose.

The target migration order is fixed. Do not start a later row while an earlier
row still has a production path through `ContractSpec`, `IR.Module`, or a
Legacy adapter.

Module ownership is tracked by the
[2026-07-14 audit](docs/module-ownership-audit-2026-07-14.md). Public Solana
authoring enters through `ProofForge.Contract.Source.Solana`; the old builder is
quarantined under `Source.Solana.Legacy`, Solana fixtures live under
`Examples/Backend/Solana/Contracts`, and Psy externs live under
`ProofForge.Runtime.Psy`. Optional heavyweight proofs live in the separate Lake
libraries `ProofForgeFormalEvm` and `ProofForgeFormalSolana`, with modules under
`ProofForgeFormal/Evm` and `ProofForgeFormal/Solana`; do not import them from the
default `ProofForge` library.

| Order | Target family | State | Exit condition |
|---|---|---|---|
| 1 | EVM | in_progress (public product route canonical; R4a-R4d complete) | Every EVM product route reaches `ModulePlan` without v1 IR and obsolete EVM compatibility code is deleted |
| 2 | NEAR | pending after EVM | Product TokenSpec/Surface v2 reaches `NearModulePlan` without v1 IR and obsolete NEAR compatibility code is deleted |
| 3 | Solana | pending | Product path reaches target-owned plan without v1 IR |
| 4 | Other targets | pending | Each target is migrated or explicitly fixture/research-only |

The immediate architecture prerequisite is the
[IR Target Extension Boundary plan](docs/superpowers/plans/2026-07-14-ir-target-extension-boundary.md).
Complete IR-B0 through IR-B3 before N-T4 resumes. IR-B4 through IR-B8 then
apply the same boundary to EVM, Solana, every other implemented target family,
and shared interface/materialization records.

| ID | State | Task |
|---|---|---|
| IR-B0 | done (verified 2026-07-14) | Audit all shared-layer target leakage and freeze the boundary |
| IR-B1 | done (verified 2026-07-14) | Open extension identities and split target catalogs |
| IR-B2 | done (verified 2026-07-14) | Remove NEAR promise modes and semantics from Canonical Core |
| IR-B3a | done (verified 2026-07-14) | Rename the shared crosscall string pool to target-neutral ownership |
| IR-B3b | done (verified 2026-07-14) | Migrate legacy NEAR scalar operations to generic extension calls |
| IR-B3c | done (verified 2026-07-14) | Migrate continuation calls and delete legacy NEAR constructors |
| IR-B4 | in_progress (B4a-B4b verified) | Move EVM protocol and ABI operations out of shared IR |
| IR-B5 | pending | Audit and migrate Solana PDA/CPI/account behavior |
| IR-B6 | pending | Audit other Wasm-host, Move, Aleo, Psy, and Quint target ownership |
| IR-B7 | in_progress (EVM B7a-B7g verified 2026-07-14) | Move target environment/interface/materialization fields |
| IR-B8 | pending | Empty the compatibility allowlist and enforce the boundary |

Legacy removal follows the
[incremental replacement plan](docs/superpowers/plans/2026-07-12-incremental-legacy-replacement.md).
The advisory canonical gate is removed (D3); do not reintroduce a path that
turns adaptation, validation, HostOp, capability, or target-plan failure into
success. The Canonical EVM renderer now consumes `ModulePlan` alone. Product
`ContractSpec` removal proceeds through D5-D12; do not reintroduce an
`IR.Module` argument or symbolic storage rediscovery into the strict route.

| ID | State | Task | Authoritative section |
|---|---|---|---|
| N-T0 | done (verified at `337ee823`) | Reconcile stale NEAR task and capability claims | NEAR plan task index |
| N-T1 | pending | Re-land the verified JSON ABI behavior on the canonical-only NEAR route | Phase 4 + NEAR-R4 |
| N-T2 | pending | Re-land the verified NEP-141 behavior on the canonical-only NEAR route | Phase 5 + NEAR-R4 |
| N-T3 | pending | Re-land the verified NEP-145 behavior on the canonical-only NEAR route | Phase 6 + NEAR-R4 |
| N-T4 | pending | Re-land the verified NEP-148/297 behavior on the canonical-only NEAR route | Phase 6 + NEAR-R4 |
| N-T5 | in_progress (N-T5a runtime package verified) | Remove the remaining `NearSpec`/Legacy route from the parameterized TokenSpec NEP-141 artifact | Phase 7 + NEAR-R3/R4 |
| N-T6 | pending after N-T2/N-T3/N-T4 | Refresh sandbox compare and obtain verified evidence | Phase 8 |
| N-T7 | pending after N-T6 | Real receipt/network runner, deploy evidence, and gas bands | Phase 8 extension |
| N-T8 | pending | NEAR ecosystem extensions and formal preservation | Phase 9 extension |

The previous N-T1 through N-T4 commits remain executable behavioral baselines;
they are not accepted as architecture completion because the public FT source
still enters through `NearSpec`/`ContractSpec` compatibility normalization. The NEAR
cutover is split into reviewable removal slices:

| ID | State | Task |
|---|---|---|
| NEAR-R0 | done (verified at `b8acc604`) | Isolate v1 `IR.Module` builders/lowerers behind an explicit Legacy module and enforce import boundaries |
| NEAR-R1 | done (verified 2026-07-14) | Remove v1 `ValueType`, `StructDecl`, and allocator ownership from `NearModulePlan` |
| NEAR-R2 | pending after EVM-R4 (context subtask landed) | Move NEAR-only context, value, receipt, and promise operations into typed Near HostOps |
| NEAR-R3 | pending | Materialize TokenSpec/Surface v2 directly into checked Canonical Core |
| NEAR-R4 | pending | Switch the public CLI route and replay N-T1 through N-T4 gates on the canonical artifact |
| NEAR-R5 | pending | Delete `NearSpec`, the legacy FT product source, adapters, and zero-caller compatibility APIs |

The EVM renderer-only commits are likewise baselines, not completion of the
EVM migration. Finish these rows before resuming NEAR-R2:

| ID | State | Task |
|---|---|---|
| EVM-R0 | done (`c988153b`, `f44be25d`, `4cc2700b`) | Make canonical storage/ABI plans complete enough that the strict renderer consumes `ModulePlan` alone |
| EVM-R1 | done (verified 2026-07-14) | Move EVM-only context, protocol, ABI, call-mode, error, and dispatch semantics into EVM-owned HostOps and plan metadata |
| EVM-R2 | done (28/28 EVM catalog products direct; exact catalog audit and ERC-4626 Anvil smoke verified 2026-07-14) | Materialize Counter, ValueVault, Token, RemoteCall, and remaining EVM product families directly into checked Canonical Core |
| EVM-R3 | done (public Yul, optimized bytecode, check, plan metadata, and 28-product CLI catalog verified 2026-07-14) | Switch EVM build/emit/check and product dispatch to the direct canonical route and replay focused EVM behavior/runtime gates |
| EVM-R4 | done (R4a-R4g verified 2026-07-14) | Delete obsolete EVM legacy lowering/adapters and preserve target-owned logical peer resolution after the direct frontend cutover |

Before NEAR-R2, complete the single-authoring cutover in
[the July 14 authoring plan](docs/superpowers/plans/2026-07-14-authoring-cutover.md).
`Examples/Product` is the only product source; `Frontend.Surface` and Canonical
Core are internal compiler representations.

| ID | State | Task |
|---|---|---|
| A-CUT0 | done (verified 2026-07-14) | Move backend goldens out of Product and delete unused duplicates |
| A-CUT1 | done (verified 2026-07-14) | Enforce the internal Surface boundary and isolate temporary AST fixtures outside Product |
| A-CUT1b | done (verified 2026-07-14) | Audit Legacy callers and move obsolete Core/elaborator/refinement modules out of production |
| A-CUT1c | done (verified at `52742ff5`) | Consolidate the optional EVM and Solana semantic-refinement roots under the independent `ProofForgeFormal` Lake libraries; keep heavyweight proof dependencies out of the default compiler library |
| A-CUT1d | done (verified 2026-07-14) | Optional proof namespaces now use `ProofForgeFormal.Evm.*` / `ProofForgeFormal.Solana.*`; the boundary gate enforces one-way dependency ownership and rejects retired top-level roots |
| A-CUT1e | done (verified 2026-07-14) | Public Solana macros emit only direct Authored contracts; typed target operations survive strict Canonical planning, plan-only package generation, sBPF lowering, and Pinocchio structural comparison without public/internal Legacy imports |
| A-CUT2 | in_progress (through A-CUT2f-c verified) | Direct Authored builder, portable Boolean Core operations, and inferred typed event schemas now cover the Counter/public expression path without `Contract.Builder`; public Source/loader cutover remains pending |
| A-CUT3 | pending | Migrate the full product catalog from the single abstract source |
| A-CUT4 | in_progress (public version split removed) | Delete temporary Surface fixtures; public source identity and loader naming are now unversioned |
| A-CUT5 | pending | Delete all zero-caller Legacy production code and dual-run gates |

Native-reference differential validation follows
[the July 14 comparison plan](docs/superpowers/plans/2026-07-14-cross-target-native-differential.md).
It extends the existing testkit, NEAR Sandbox, Solana Pinocchio, EVM runtime,
and Stylus differential assets; it is not another compiler route. CMP-0 is
done at `18f15e59`; CMP-1 is now the only active comparison slice. CMP-2 is
required for A-CUT2 completion, CMP-SOL attaches to IR-B5, CMP-NEAR
attaches to NEAR-R4, and the final fail-closed matrix attaches to IR-B8/A-CUT5.

The D-052 cross-program routing index remains below for work not superseded by
the active NEAR sequence.

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
| `proof-forge --list-targets` / `ProofForge.Target.knownIds` | `evm`, `solana-sbpf-asm`, `wasm-near`, `wasm-cosmwasm`, `wasm-stellar-soroban`, `wasm-arbitrum-stylus`, `psy-dpn`, `aleo-leo` |
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
| Full parallel baseline | `just check` / `just check-parallel` (143 recipes, default max 4 workers) | GitHub lane matrix; Woodpecker `proof-forge-check`; local pre-push |
| Serial full reference | `just check-serial` | Local race diagnosis and coverage reference |
| Backend-heavy | `build-test` after `product` | GitHub `build-test` (`needs: product`) |

Optional GitHub jobs with `continue-on-error` are `aleo-smoke`,
`cosmwasm-smoke` and `solana-pinocchio-live`.

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
