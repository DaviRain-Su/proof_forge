# Durable multi-chain remediation agent goal

Copy this entire document into one long-running goal or agent session. It is a
continuous execution charter, not a request for another audit or plan.

Status: **Active**

**Complementary post-review execution charter:**
[`superpowers/plans/2026-07-10-post-review-execution.md`](superpowers/plans/2026-07-10-post-review-execution.md)

Queue source of truth:
[`multi-chain-gap-audit-2026-07-10.md`](multi-chain-gap-audit-2026-07-10.md)

Baseline: Waves 0–3 done. Wave 5 PF-P3-01 is complete through the structural
`evm_lowerable_implies_lowering_total` Counter-shape path; PF-P3-03 is complete with
shared frontend refusal, parsed-root Lean provenance, isolated rebuild hashes,
process-tree wall-clock enforcement, and CPU/memory resource gates. Wave 4
PF-P3-02 remains reopened until every advertised secondary-target maturity is
backed by strict tool exits and executable runtime/package validation on one revision.

---

## Mission

Continuously advance ProofForge toward this product contract:

> Authors maintain general contract bodies through `contract_source` and
> specialized token intent through `TokenSpec`. Selecting a target produces an
> honest target artifact without replacing the source, skipping required
> validation, or overstating maturity.

The primary product targets are `evm`, `solana-sbpf-asm`, and `wasm-near`.
Secondary targets remain at their current Spike/MVP/Research scope until they
pass the promotion gates in PF-P3-02.

Do not stop after analysis, a plan, or a checkpoint. Select the next eligible
task, implement a reviewable slice, verify it, commit it, update the ledger,
and continue. Stop only after global completion, the global blocked condition
below, an explicit human pause, or a required destructive action awaiting human
approval.

## Truth precedence

When sources disagree, use this order:

1. Current code, runnable tests, generated artifacts, and tool output.
2. The evidence, required change, and acceptance criteria in the gap audit.
3. `AGENTS.md`, the root `justfile`, and current CI workflows.
4. Current target/architecture documentation.
5. Older plans, backlogs, phase notes, and development logs as history only.

Never implement stale prose blindly. If current code already fixes a queued
problem, reproduce the acceptance criteria, update the ledger and docs, and do
not rewrite the solution.

## Non-negotiable rules

1. **No silent substitution or drop.** The requested source must reach the
   lowerer. Unsupported input, capability, command, format, or final stage must
   fail with a stable diagnostic.
2. **Artifact claims are literal.** Assembly, WAT, sourcegen, bytecode, ELF and
   Wasm are distinct typed outputs. Missing tools or skipped validation never
   become `passed`.
3. **Primary triad first.** Close EVM/Solana/NEAR correctness and product parity
   before broadening secondary targets.
4. **Keep target-specific plans.** Unify driver contracts and artifact schemas,
   not chain semantics. Preserve explicit `IR -> Plan -> typed AST ->
   printer/package -> validation` boundaries.
5. **Evidence before status.** A task becomes `done` only when every acceptance
   item in the audit has fresh evidence tied to a tested commit SHA. Later
   changes do not inherit that evidence automatically.
6. **TDD for behavior changes.** Add the failing regression first, observe the
   intended failure, implement the smallest real fix, then rerun it.
7. **One implementation owner at a time.** Subagents may perform bounded
   research, test inventory, or independent review. Do not let multiple agents
   edit central CLI, registry, artifact schema, or queue files concurrently.
   Recheck worktree ownership before every slice and immediately before staging.
8. **Small coherent commits.** One independently testable slice per commit. A
   large PF task may require several commits and remains `in_progress` until its
   full acceptance criteria pass.
9. **Do not weaken gates.** Fix the implementation or the genuinely stale
   expectation. Do not delete coverage, turn failures into skips, or relax an
   assertion merely to make CI green.
10. **Do not push, open a PR, deploy, force-push, or rewrite history** unless the
    human explicitly asks.

## Durable task ledger

Allowed states:

- `pending`
- `in_progress: <current slice and next unmet acceptance>`
- `blocked: <external condition and evidence>`
- `done: verified@<tested commit SHA>; <fresh acceptance commands>`

The top-level `Status` near the start of this file is the goal state. Keep it
`Active` while work is eligible, change it to
`Blocked: <date>; <unblock summary>` only under the global blocked protocol,
and change it to `Complete: verified@<final tested code SHA>` only after final
revalidation.

Prefer task-id order inside a wave. A task blocked only by an external tool may
be skipped temporarily so another task in the same wave can proceed, but the
next dependent wave remains closed. Keep task IDs stable and update this table
in the same implementation commit when a task remains `in_progress`. A final
`done` transition requires a small follow-up ledger commit because the tested
implementation SHA is only known after the implementation commit exists.

| Wave | Task | State | Eligibility |
|---|---|---|---|
| 0 | PF-P0-01 | done: verified@0244e8d0; `just cli-target-first`; `just source-identity` | immediately |
| 0 | PF-P0-02 | done: verified@f9590238; `just registry-command`; `just cli-target-first` | immediately; prefer after PF-P0-01 |
| 0 | PF-P0-03 | done: verified@2efe7750; `just solana-source-elf`; `just cli-target-first` | immediately; prefer after PF-P0-02 |
| 0 | PF-P0-04 | done: verified@295132ed; just soroban-profile; just product | immediately; prefer after PF-P0-03 |
| 0 | PF-P0-05 | done: verified@42e025e8; just doc-sync-audit-strict; scripts/i18n/check-sync.sh | immediately; generated support tables remain PF-P1-02 |
| 0 | PF-P0-06 | done: verified@e94bc185; just testkit; offline-host wasmtimeFuel* fields | immediately |
| 0 | PF-P0-07 | done: verified@0334cbaa; just check-l2-parity | immediately |
| 0 | PF-P0-08 | done: verified@0334cbaa; just wat2wasm-fail-closed | immediately |
| 1 | PF-P1-01 | done: verified@885b1ae6; just target-backend; just cli-check; just check-l2-parity; just product; just check | all Wave 0 tasks done |
| 1 | PF-P1-02 | done: verified@3ece05d8; just target-support; just product; just docs-check | all Wave 0 tasks done; coordinate with PF-P1-01 |
| 1 | PF-P1-03 | done: verified@3021cb13; just artifact-bundle; just solana-source-elf; just product; just check | PF-P1-01 and PF-P1-02 done |
| 1 | PF-P1-04 | done: verified@4cae7f88; just preflight-l2; just check-l2-parity; just product; just check | PF-P1-01 through PF-P1-03 done |
| 2 | PF-P1-05 | done: verified@d3d2f3d8; just source-dsl-arity; just portable-default; just product; just check | Wave 1 done |
| 2 | PF-P1-06 | done: verified@1f4c73e7; just leo-printer-fail-closed; just aleo-leo-codegen-smoke; just product; just check | Wave 1 done |
| 3 | PF-P2-01 | done: verified@72c5789e; just product-catalog; just product; just testkit; just testkit-array-example; just testkit-ownable; just testkit-remote-call; just check | Waves 1 and 2 done |
| 3 | PF-P2-02 | done: verified@7c4def9c; Foundry ERC721/1155/custom-error; Solana ELF; `just near-sandbox-peer` (storage_usage + promise peer); `just product`; `just check` | Waves 1 and 2 done; complete one backend slice at a time |
| 3 | PF-P2-03 | done: verified@7c4def9c; `just testkit-remote-call` (evm+solana); Foundry peer; Mollusk CPI; `just near-sandbox-peer` (call_with_args→49); `just product` | Waves 1 and 2 done |
| 5 | PF-P3-01 | done: verified@c576ae4f; `just track14-fragment-theorems-smoke`; `just evm-counter-shape-name-totality`; `just evm-foundry`; `just product` | Wave 3 done; Counter-shape theorem only, not general compiler correctness |
| 5 | PF-P3-03 | done: verified@06bf854a; `just hosted-isolation`; `just rebuild-hash`; `just worker-limits`; `just worker-cgroup`; `just check` | Wave 3 done |
| 4 | PF-P3-02 | in_progress: Cloudflare is honestly retained as off-chain Research sourcegen; Aptos remains Spike/sourcegen while product `contract_source` is unsupported; Aleo remains Research/sourcegen because state-derived getters fail closed; rerun promotion-readiness gates on one revision without overstating maturity | Wave 3 done; promote only one target at a time, and do not block Wave 5 |

PF-P3-02 promotion order is fixed unless the human changes it: Soroban,
CosmWasm, Aptos, Sui, Cloudflare Workers, Psy, Aleo. Completing one target is a
valid slice, but PF-P3-02 remains `in_progress` until all explicitly scheduled
promotion work is complete or the audit narrows its scope. This ordered list is
not a mandate to promote all seven targets: PF-P3-02 may finish with targets
honestly retained at Spike/MVP/Research when the six-gate policy is enforced
and unsupported inputs and stages fail closed.

## Startup procedure

Run this at the beginning of a new session or after context recovery:

```sh
pwd
git status --short
git branch --show-current
git log -5 --oneline
```

Then:

1. Read `AGENTS.md`.
2. Read this file and the complete section for the selected task in
   `docs/multi-chain-gap-audit-2026-07-10.md`.
3. Inspect the exact code and tests cited by that task.
4. Check for user or agent changes made since the ledger was last updated.
5. Reproduce the reported behavior before editing. Treat a non-reproducible or
   already-fixed finding as a verification task, not permission to invent work.
6. Select the lowest-priority-number eligible `in_progress` task, otherwise the
   lowest eligible `pending` task.

Do not reset, clean, checkout, or overwrite unrelated dirty changes. Work with
them if they affect the task; otherwise leave them untouched.

## Execution loop

Repeat this loop until the global completion condition is met:

1. **Restate the contract.** Write down the selected PF task, its exact current
   failure, required behavior, files likely involved, and acceptance commands.
2. **Claim the slice paths.** Run `git status --short` and
   `git diff --name-only`; list the exact files this slice owns. Recheck after
   every subagent returns. Do not absorb new user/agent changes into the slice.
3. **Map the boundary.** Trace input identity through load, resolve, lower,
   emit/package, validation, metadata and CLI exit status. For proof work, trace
   the actual lowerer output into the machine semantics and relation.
4. **Choose one vertical slice.** It must remove one real failure and be small
   enough for an independent reviewer to accept or reject on its own.
5. **Write the regression first.** Prefer the nearest existing Lean test, shell
   smoke, testkit scenario, schema check or golden test. Include negative cases
   for fail-closed behavior.
6. **Observe the expected failure.** Record the command and failure reason.
7. **Implement the smallest complete fix.** Reuse repository abstractions. Do
   not add a parallel registry, plan, AST, schema or driver unless the selected
   task explicitly requires the migration boundary.
8. **Run narrow verification.** Use the task's acceptance criteria and the gate
   matrix below. Rebuild `proof-forge` before scripts that invoke the binary.
9. **Inspect generated artifacts.** Check source identity, artifact kind,
   declared validation state, hashes and target-specific names, not only exit 0.
10. **Request independent review.** Use a fresh reviewer/subagent when the
    environment supports it; otherwise perform and record a separate review
    pass. Check correctness, regressions, false capability claims and missing
    negative tests. Resolve all Critical/Important findings before proceeding.
11. **Run completion gates.** Run the global gates required for the affected
    surface. A task cannot become `done` while a required gate is failing.
12. **Update truth sources.** Update English documentation first, the Chinese
    mirror, i18n manifest and mechanical audit expectations. Set the ledger to
    `in_progress` in this commit if any acceptance item remains.
13. **Stage owned paths only.** Re-run `git status --short` and
    `git diff --name-only`, then stage each owned path explicitly. Never use
    `git add -A`, `git add .`, a directory-wide wildcard, or a mixed-ownership
    file whose changes cannot be separated safely. Run:

    ```sh
    git diff --cached --check
    git diff --cached --stat
    git diff --cached
    ```

    Commit only after the cached diff contains exactly this slice. Verify the
    result with `git show --stat --oneline HEAD`.
14. **Record durable evidence.** With no uncommitted agent-owned changes, capture
    the implementation SHA and rerun the task's acceptance commands. If the
    full PF task is complete, change its ledger row to
    `done: verified@<implementation SHA>; <commands>` and commit that one-file
    ledger update separately. If acceptance fails, keep it `in_progress` and fix
    the implementation rather than recording stale evidence.
15. **Continue immediately.** Re-read the ledger and begin the next eligible
    slice. A progress summary is not a stopping condition.

## Gate matrix

Always start with the narrowest relevant gates. Use `lake env` for Lean and CLI
commands.

| Boundary | Minimum narrow evidence |
|---|---|
| Registry / command support | `just target-registry`, `just cli-target-first`, `just cli-check`, relevant source-identity CLI smoke |
| Authoring / portable IR | `just product`, `just contract-source-diagnostics`, affected `portable-*-multi-target` recipe |
| EVM output/runtime | affected Lean/golden test, then `just evm-all` when runtime or final artifacts change |
| Solana output/runtime | affected Lean/golden test, `just solana-light`; live Surfpool only when required and installed |
| NEAR/Wasm output/runtime | `just near-plan-smoke`, `just near-target-first`, affected offline-host or EmitWat smoke |
| Cross-target runtime parity | `just testkit` plus the affected source-backed scenario; inspect per-target traces |
| Formal semantics | affected `lake env lean --run Tests/...` theorem smoke and `just check`; preserve external differential gates |
| Documentation / schemas | `just docs-check`, `just doc-sync-audit`, `scripts/i18n/check-sync.sh` |

Before marking any PF task done, run:

```sh
just product
just check
scripts/i18n/check-sync.sh
git diff --check
```

After PF-P0-05 introduces the strict recipe, also require:

```sh
just doc-sync-audit-strict
```

Until then, run `just doc-sync-audit`, record its finding count, and do not claim
that advisory exit 0 means zero drift.

Live gates requiring Surfpool, Sui, Leo, Dargo, Wrangler, chain CLIs or funded
accounts are conditional on installed tools. Missing tools may justify a
recorded external blocker, but never a maturity promotion or fabricated pass.

## Task-specific safety constraints

- For PF-P0-01, test every registered target with a non-Counter source. Success
  must preserve source identity; unsupported routes must fail without artifacts.
- For PF-P0-02, keep target registration distinct from per-command support.
  Plain list membership means at least one real command; JSON support data is
  authoritative once PF-P1-02 lands.
- For PF-P0-03 and PF-P0-08, distinguish intermediate output from final build.
  Tool absence and conversion failure must propagate to exit status and metadata.
- For PF-P0-04, carry the requested target profile through capability resolve,
  host bridge, metadata and client generation. Do not alias Soroban to NEAR.
- For PF-P0-06, do not translate Wasmtime fuel into chain gas without a validated
  schedule. Rename first; model later.
- For PF-P0-07 and PF-P1-04, `ready` requires backend validation of the exact
  supported fragment, not only broad capability resolution.
- For PF-P1-01 through PF-P1-04, migrate the primary triad before fixture and
  sourcegen targets. Keep compatibility aliases only for the documented window.
- For PF-P2-01 through PF-P2-03, a build smoke is not runtime parity. Exercise
  caller, value, failure, event, storage and peer behavior where applicable.
- For PF-P3-01, never state general compiler correctness from Counter witnesses.
  Separate `proved` and `lowerable`, connect proofs to actual lowerer output, and
  keep toolchains/runtime conformance in the trusted or differential boundary.
- For PF-P3-02, source acceptance alone is not promotion. All six gates in the
  audit must pass for the promoted target on one revision.
- For PF-P3-03, do not expose trusted local elaboration as a hosted isolation
  boundary. Isolation, limits, provenance and reproducibility must be explicit.

## Blocked and recovery protocol

Do not mark a task blocked because it is large, unfamiliar, slow, or would
benefit from clarification. Investigate and continue with the smallest useful
slice.

A real blocker is an external condition such as a required unavailable
toolchain, credential, network service, incompatible upstream dependency, or a
conflicting user change that makes safe progress impossible. Before recording
`blocked`:

1. reproduce the same blocker three times or through three concrete resolution
   attempts;
2. capture the exact command and error;
3. finish all independent static/test/doc work for the task;
4. record the unblock condition in the ledger; and
5. continue another eligible task if wave dependencies allow it.

If every open task in the current wave is validly `blocked` and all remaining
tasks are dependency-closed, enter the **global blocked** state instead of
retrying forever. Before stopping:

1. re-run `git status --short` and leave no uncommitted agent-owned change;
2. ensure every blocked row contains the exact command/error, last attempted
   revision and concrete unblock condition;
3. change the top-level goal `Status` to `Blocked`, then commit the prompt update
   using explicit path staging;
4. report the complete blocker set and the first task to resume; and
5. stop without marking the long-running goal complete.

On resume, recheck every unblock condition and return to the startup procedure.
If any task is now eligible, clear the global blocked state and continue.

If a session must end because of context limits, leave the repository
recoverable: tests for the last completed slice green, changes committed, the
ledger accurate, and the next unmet acceptance written in the `in_progress`
state. On restart, follow the startup procedure instead of restarting the
project analysis.

## Global completion condition

The long-running goal is complete only when:

1. all ledger rows are `done` with tested SHAs and task-specific commands;
2. no target silently substitutes input or reports a final artifact it did not
   produce;
3. primary EVM/Solana/NEAR source-backed runtime scenarios pass;
4. secondary target maturity matches the six-gate promotion policy;
5. formal claims name their exact structural fragment and trusted boundaries;
6. `just doc-sync-audit-strict` reports zero findings;
7. `just product`, `just check`, i18n sync and diff checks pass together; and
8. README, target registry, CLI help, target notes and Chinese mirrors agree.

Before declaring completion, verify every recorded implementation SHA is an
ancestor of the final branch and rerun each task-specific acceptance command at
the final code HEAD, or an aggregate regression gate that explicitly subsumes
it. Then rerun all global gates above. Record the tested final code SHA in a
final evidence-only ledger commit; after that commit, rerun `just docs-check`,
`scripts/i18n/check-sync.sh`, and `git diff --check`. No code or schema change is
allowed after final code revalidation without repeating it.

Do not mark the goal complete because the token/time budget is low. Persist
state and continue in the next long-running turn.

## Out of scope unless explicitly scheduled

- Adding a new chain target.
- Promoting a secondary target around missing runtime/toolchain evidence.
- Replacing all backend plans with one chain-neutral plan.
- Treating arbitrary Lean functions as the supported authoring surface.
- Public deployment, funded transactions, key handling or production rollout.
- Force-push, history rewrite, broad rename or unrelated repository cleanup.

## One-line restart

> Continue the ProofForge multi-chain remediation loop from
> `docs/agent-goal-prompt.md`: read the audit, select the highest-priority
> eligible PF task, implement one TDD slice, run narrow and global gates, update
> the ledger, commit, and continue until the global completion condition holds.
