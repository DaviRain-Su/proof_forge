# Durable goal: NEAR native-vs-ProofForge compare matrix

Copy this entire document into one long-running `/goal` session (or paste as the
goal objective). Continuous execution charter — not a request for another plan.

Status: **Complete: 28 live dual-deploy** (Wave 13 HeightLockVault HostEnv height gate).
Blocked: full Stdlib.ERC4626 NEAR asset crosscall; UTF-8 string KV.
Optional next: UTF-8 string KV; more product contracts.

Workspace: ProofForge repo root (this tree). Branch may be feature work on
`near-compare` / compare expansion; do not force-push or open PRs unless asked.

Baseline already landed (do not re-build from scratch):

- Dual-deploy harness under `testkit/compare/` (offline size/fuel + NEAR Sandbox)
- Contracts: **Counter**, **ValueVault**
- Gas path: multi-scalar pack (`__pf_s`), event composite putstr, write-only
  `pack_begin_fresh`, zero-arg skip `input`
- Recipes: `just near-compare*`, `just near-compare-value-vault*`,
  `just near-compare-all-live`
- Docs: `testkit/compare/README.md`

---

## Mission

Expand the **NEAR official / near-sdk reference vs ProofForge portable rewrite**
compare matrix until it covers a credible ladder of real NEAR contract shapes:

> For each selected contract: one near-sdk (or near-contract-standards) reference,
> one ProofForge product rewrite, same scenario, offline + Sandbox dual-deploy
> metrics (wasmBytes, deployGasBurnt, callGasBurnt, storageUsageBytes), report
> under `build/testkit/compare/near/<contract>/`, and a row in
> `testkit/compare/README.md`.

Primary product path: `Examples/Product/*` → `--target wasm-near` (EmitWat).
Do **not** invent a parallel NEAR-only authoring stack.

Do not stop after analysis or a checklist. Pick the next eligible task,
implement a reviewable slice, verify, commit, update this ledger, continue.
Stop only when: global completion criteria below are met; global blocked;
human pause; or a destructive/shared action needs explicit approval.

---

## Truth precedence

1. Current code, runnable tests, sandbox reports, tool output.
2. This goal file’s task ledger and acceptance criteria.
3. `AGENTS.md`, root `justfile`, `testkit/compare/README.md`.
4. Product sources under `Examples/Product/` and existing NEAR gates
   (`just product`, `scripts/near/*`, NEP-141 smokes).
5. Older plans / chat summaries as history only.

If code already satisfies a task, re-run acceptance, mark `done` with SHA, do
not rewrite for sport.

---

## Non-negotiable rules

1. **Fair compare.** Same public methods (or documented subset), same scenario
   steps, same event JSON shape when both sides log. Do not “win” gas by
   dropping logs the sdk still emits.
2. **Real dual-deploy for live claims.** Offline size/fuel alone is not enough
   to mark a live task `done`. Sandbox may skip only if the environment cannot
   start sandbox — then leave live as `pending`/`blocked`, not `done`.
3. **One contract slice at a time.** Finish offline + live + README row before
   starting the next contract unless the current one is blocked on tools.
4. **Prefer existing Product sources.** Extend EmitWat/product only when the
   compare scenario requires it; keep changes minimal and covered by smoke.
5. **Evidence before status.** `done` requires fresh commands + commit SHA.
6. **Small coherent commits.** One independently testable slice per commit.
   Example: “add FT near-sdk reference”, “wire offline compare”, “sandbox live”,
   “README matrix” may be separate commits.
7. **Do not weaken gates.** Fix implementation or truly stale goldens; no
   `--no-verify`, no deleting asserts to go green.
8. **Do not push, open a PR, force-push, or rewrite history** unless the human
   explicitly asks.
9. **Stay on NEAR compare scope.** Do not expand EVM/Solana compare matrices
   unless a portable Product fix is required for the NEAR scenario to compile.
10. **Sandbox is expensive.** Prefer offline first; run live once offline is
    green. Reuse built wasm artifacts when safe.

---

## Per-contract recipe (every N*.* task)

For contract `<name>`:

1. Choose / pin reference (near-sdk example or standards crate; note source URL
   or path in `reference-manifest.json`).
2. Define scenario: init → 2–4 mut calls → 1–2 views; document in
   `testkit/compare/near/<name>/` or harness comments.
3. ProofForge: Product lean source → `proof-forge build --target wasm-near`.
4. near-sdk reference crate under `testkit/compare/near/<name>/`.
5. Wire offline driver (`testkit/compare`) + sandbox dual-deploy scenario.
6. `just near-compare-<name>` and `just near-compare-<name>-live`.
7. Hang live into `just near-compare-all-live` when stable.
8. Update `testkit/compare/README.md` matrix with measured numbers.
9. Commit with message describing contract + metrics delta if notable.

### Acceptance checklist (template)

```sh
# Offline
just near-compare-<name>
# Expect report.json with proofForgeWasmBytes, nearSdkWasmBytes, semantic ok

# Live (when sandbox available)
just near-compare-<name>-live
# Expect sandbox-report.json: semanticMatch true; non-zero gas fields

# Existing matrix must not regress
just near-compare-all-live   # or at least counter + value-vault + new
```

---

## Durable task ledger

Allowed states:

- `pending`
- `in_progress: <slice / next unmet acceptance>`
- `blocked: <external condition + evidence>`
- `done: verified@<sha>; <commands>`

Keep task IDs stable. Prefer wave order; within a wave prefer listed order.
If blocked only by tools (e.g. sandbox), mark blocked and continue another
eligible offline slice.

| Wave | Task | Title | State | Eligibility |
|------|------|-------|-------|-------------|
| 0 | NC-0.1 | Counter dual-deploy compare | done: baseline harness | — |
| 0 | NC-0.2 | ValueVault dual-deploy + gas packing | done: baseline harness | — |
| 0 | NC-0.3 | Harness + README snapshot | done | — |
| 1 | **NC-1.2** | **FungibleToken NEP-141 minimal face** | done: live semanticMatch; wasm ~48× | — |
| 1 | NC-1.3 | Ownable / owner gate | done: live semanticMatch; wasm ~256× | — |
| 1 | NC-1.1 | StatusMessage (string/map guest-book lite) | done: live semanticMatch; U64 codes (not UTF-8); wasm ~126× | honesty: string KV open |
| H | NC-H1 | Scenario registry (less paste in sandbox main) | done: verified@1a9046e1; modular + SideCtx + run_side | — |
| H | NC-H3 | `near-compare-matrix` offline + all-live matrix | done: `just near-compare-all-live` (+ status/guestbook) | — |
| 2 | NC-2.1 | StakingVault (map + nativeValue + pack) | done: live semanticMatch; wasm ~94× | — |
| 2 | NC-2.2 | RoleGatedToken (nested maps / roles) | done: live ~88× wasm | — |
| 2 | NC-2.3 | FeeToken / extended FT | done: live ~93× wasm; body under Backend/WasmNear | — |
| 3 | NC-3.1 | GuestBook / multi-message storage | done: live semanticMatch; U64 codes; wasm ~119× | honesty: string KV open |
| 3 | NC-3.2 | Cross-contract / promise scenario | done: live peer rebuild + dual deploy | — |
| 3 | NC-3.3 | Fuller NEP-141 / storage staking subset | done: live NEP-145-lite StorageDeposit; wasm ~196× | honesty: no full JSON StorageBalance |
| 4 | NC-4.1 | Pausable emergency-stop mixin | done: live semanticMatch; wasm ~131× | — |
| 4 | NC-4.2 | ReentrancyGuard lock-bit | done: live semanticMatch; wasm ~135× | honesty: lock bit only |
| 4 | NC-4.3 | OwnablePausable owner-gated pause | done: live semanticMatch; wasm ~98× | — |
| 5 | NC-5.1 | ArrayExample fixed array locals | done: live semanticMatch; wasm ~131× | view-only |
| 5 | NC-5.2 | OwnableHash 32-byte owner | done: live semanticMatch; wasm ~115× | — |
| 5 | NC-5.3 | HostEnvProbe triad snapshot | done: live semanticMatch; wasm ~84× | honesty: time/height host-defined |
| 6 | NC-6.1 | AuthRemoteCall debit + promise | done: live semanticMatch; wasm ~159× | multi-account + peer rebuild |
| 6 | NC-6.2 | AccessControl role map | done: live semanticMatch; wasm ~177× | .address→U64 on NEAR |
| 7 | NC-7.1 | ExternalTokenTransfer NEP-141 client | done: live ~111× wasm; mock FT peer | Layer B |
| 7 | NC-7.2 | ExternalVault peer client | done: live ~138× wasm; mock vault peer | Layer B |
| 7 | NC-7.3 | Product scan + MATRIX.md comparison | done | Soulbound/ERC4626 blocked |
| 8 | NC-8.1 | ProRataVault (ERC-4626-like NEAR subset) | done: live ~82× wasm | honesty: no IERC20 pulls |
| 8 | NC-8.2 | SoulboundTokenBody mint/burn | done: live ~110× wasm | TokenSpec path separate |
| 9 | NC-9.1 | FtPeerClient protocol NEP-141 client | done: live ~102× wasm | Backend path |
| 9 | NC-9.2 | near-compare-matrix snapshot script | done | scripts/near/compare-matrix-snapshot.py |
| 10 | NC-10.1 | VestingVault HostEnv linear vesting | done: live ~95× wasm | internal claim ledger |
| 11 | NC-11.1 | EscrowVault fund→release|refund | done: live ~95× wasm | two-party state machine |
| 12 | NC-12.1 | TimelockVault binary HostEnv unlock | done: live ~108× wasm | contrast VestingVault linear |
| 13 | NC-13.1 | HeightLockVault binary height gate | done: live ~108× wasm | checkpointId / block_index |

### Task briefs

#### NC-1.2 FungibleToken (NEP-141 minimal) — **start here**

- **PF source:** `Examples/Product/FungibleToken.lean` + existing NEP-141 /
  `wasm-near-ft-*` paths. Use the **minimal comparable surface**: new /
  mint / ft_transfer / ft_balance_of (or documented subset that both sides
  implement). Do not require full NEP-141+NEP-145 on day one.
- **sdk ref:** near-sdk / near-contract-standards FT-shaped crate under
  `testkit/compare/near/fungible-token/`.
- **Scenario (suggested):** initialize supply → mint or seed → transfer →
  balance views on both accounts if needed.
- **Accept:** offline size report + live dual-deploy semantic match + README row.
- **Risks:** TokenSpec vs EmitWat body mismatch; JSON vs Borsh args; map storage
  gas. Prefer fixing product/codegen only as needed for the scenario.

#### NC-1.3 Ownable

- PF: `Examples/Product/Ownable.lean` / stdlib Ownable.
- Scenario: init owner → restricted mut → transfer ownership → reject non-owner.
- Low complexity; good packing/single-field contrast.

#### NC-1.1 StatusMessage — **done (U64 subset)**

- Classic near-examples status message (account → string).
- Landed as **U64 status codes** keyed by caller projection / AccountId map;
  documented in README honesty + product header. Full UTF-8 string KV remains
  open (not required to re-open this task).

#### NC-2.1 StakingVault

- PF: `Examples/Product/StakingVault.lean` already multi-target.
- sdk: hand-written near-sdk mirror (deposit/withdraw/shares map).
- Exercises nativeValue + maps + multi-scalar.

#### NC-H1 / NC-H3

- **NC-H1 (landing):** split `testkit/compare/near/sandbox` into
  `kind` / `report` / `host` (`SideCtx`) / `scenarios/*` with `run_side` registry.
  New contracts add one scenario file + one `ContractKind` arm + `run_side` match arm.
- NC-H3 already done via `just near-compare-all-live`.

---

## Global completion criteria

Mark Status **Complete: verified@\<sha\>** only when all of the following hold:

1. At least **Wave 1**: NC-1.2 done (live), plus either NC-1.3 or NC-1.1 done (live).
2. **Wave 2**: NC-2.1 done (live).
3. `just near-compare-all-live` runs Counter + ValueVault + all new live contracts
   with `semanticMatch: true` (or documented sandbox skip only if environment
   cannot start sandbox — then Complete is not allowed).
4. `testkit/compare/README.md` matrix is up to date for every done contract.
5. No known regression on Counter/ValueVault live ratios worse than noise
   without a documented reason.

Wave 3 is **stretch** — completing Wave 1+2+H is enough for Complete unless
the human extends the goal.

---

## Global blocked protocol

Set Status `Blocked: <date>; <reason>` only if **every** eligible pending task
is blocked on external conditions (missing toolchain, sandbox cannot start and
offline-only is already done, product capability gap with no safe subset).
Record evidence commands. Resume when unblocked; do not invent fake green.

---

## Startup procedure (each session / context recovery)

```sh
pwd
git status --short
git branch --show-current
git log -5 --oneline
# Read ledger in this file; pick first pending eligible task
rg -n "pending|in_progress|blocked" testkit/compare/GOAL.md
cat testkit/compare/README.md | head -80
just --list 2>/dev/null | rg near-compare
# Optional baseline health
just near-compare 2>&1 | tail -20
```

Then: mark chosen task `in_progress`, implement one slice, verify, commit,
update ledger row, continue.

---

## Progress reporting

Use the session goal tool (`update_goal`) when available:

- Short progress messages after each verified slice.
- `completed: true` only when global completion criteria are met.
- `blocked_reason` only under global blocked protocol (failure), never for
  normal “finished a slice”.

---

## Non-goals

- Mainnet / testnet funded deploys.
- Changing event semantics to game call gas.
- Full NEP suite compliance as a gate for first FT compare.
- EVM/Solana dual-deploy matrix (method reuse OK; new harness out of scope).
- Unrelated multi-chain remediation (see `docs/agent-goal-prompt.md`).

---

## One-line `/goal` objective (if the UI wants a short objective)

Expand NEAR compare matrix: add near-sdk vs ProofForge dual-deploy contracts
per `testkit/compare/GOAL.md` (start NC-1.2 FungibleToken, then Ownable /
StakingVault); offline+live metrics; update README; commit each slice; continue
until Wave 1+2 complete.
