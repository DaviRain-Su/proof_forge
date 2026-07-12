# Parallel Test Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build conflict-aware local and CI test parallelism with a fast affected-path gate, a four-worker full gate, coverage equivalence, timing evidence, and a retained serial fallback.

**Architecture:** A checked-in JSON manifest owns recipe-to-lane classification and resource policy. A Python coordinator validates the manifest, selects fast or full coverage, schedules isolated lanes with process-group cleanup, and emits JSON timing reports; `just` exposes stable commands while GitHub and Woodpecker invoke the same lanes.

**Tech Stack:** Python 3 standard library, `unittest`, Just 1.48+, GitHub Actions, Woodpecker CI, Lean/Lake, existing shell smoke scripts.

## Global Constraints

- Automatic concurrency is `min(detected CPUs, 4)`.
- `JOBS` may override the default with a positive integer; invalid values fail closed.
- The required product gate remains first and fail-fast.
- Live-network and optional target tools remain outside the default baseline.
- The serial `just check` remains authoritative until coverage equivalence, three stable parallel runs, and performance thresholds pass.
- Full local improvement target is at least 35%; CI critical-path improvement target is at least 30%.

---

### Task 1: Manifest Contract and Validator

**Files:**
- Create: `scripts/test-framework/lanes.json`
- Create: `scripts/test-framework/manifest.py`
- Create: `scripts/test-framework/test_manifest.py`
- Modify: `justfile`

**Interfaces:**
- Produces: `load_manifest(path: Path) -> Manifest`, `validate_manifest(manifest: Manifest, known_recipes: set[str]) -> list[str]`, and `just test-manifest`.
- Consumes: recipe names from `just --summary` and the current serial `check` coverage list.

- [ ] **Step 1: Write failing manifest unit tests**

  Add `unittest` cases for duplicate recipes, unknown execution classes, missing lanes, invalid commands, and one valid minimal manifest. Run `python3 -m unittest scripts/test-framework/test_manifest.py`; expect import failure because `manifest.py` does not exist.

- [ ] **Step 2: Implement typed manifest parsing**

  Define frozen dataclasses `RecipeSpec(name, lane, execution, tags)` and `Manifest(version, recipes)`. Accept only execution values `isolated`, `lane_serial`, and `exclusive`; reject duplicate names and empty lanes with actionable messages.

- [ ] **Step 3: Check in the initial full coverage map**

  Transcribe every dependency of the existing `check` recipe into `lanes.json`. Assign each exactly once to `core-product`, `evm`, `solana`, or `wasm-other-exclusive`; mark `rebuild-hash`, worker-control recipes, shared testkit, and fixed-service recipes exclusive.

- [ ] **Step 4: Add repository validation**

  Compare manifest names with `just --summary` and with a checked-in `serialCoverage` array in the manifest. Fail on missing, duplicate, or nonexistent recipes. Run `python3 -m unittest scripts/test-framework/test_manifest.py` and `python3 scripts/test-framework/manifest.py --check`; expect PASS.

- [ ] **Step 5: Add and run the Just gate**

  Add:

  ```make
  test-manifest:
      python3 -m unittest scripts/test-framework/test_manifest.py
      python3 scripts/test-framework/manifest.py --check
  ```

  Run `just test-manifest` and `git diff --check`; expect PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add scripts/test-framework/lanes.json scripts/test-framework/manifest.py scripts/test-framework/test_manifest.py justfile
  git commit -m "test: define parallel lane manifest"
  ```

### Task 2: Process Scheduler and Self-Tests

**Files:**
- Create: `scripts/test-framework/scheduler.py`
- Create: `scripts/test-framework/test_scheduler.py`
- Modify: `justfile`

**Interfaces:**
- Consumes: `Manifest` and selected `RecipeSpec` values from Task 1.
- Produces: `detect_jobs(env: Mapping[str, str], cpu_count: int | None) -> int`, `run_schedule(...) -> RunReport`, CLI modes `--full`, `--lane`, and `--dry-run`.

- [ ] **Step 1: Write failing scheduler tests**

  Cover CPU counts `None`, `1`, `8`; valid `JOBS=2`; invalid `0`, negative, and nonnumeric values; maximum active workers; exclusive ordering; failure cancellation; nonzero propagation; and JSON duration output. Use temporary Python commands rather than project recipes. Expect import failure.

- [ ] **Step 2: Implement concurrency detection**

  Return `min(cpu_count or 1, 4)` when `JOBS` is absent. Parse `JOBS` as a positive integer without applying the automatic cap to an explicit override.

- [ ] **Step 3: Implement process-group scheduling**

  Launch `just <recipe>` with `start_new_session=True`, write combined output to `build/test-lanes/<run-id>/<lane>.log`, and terminate all surviving process groups on failure or interrupt. Never run an exclusive recipe while another child is active.

- [ ] **Step 4: Implement reports and dry-run**

  Emit `timings.json` with commit, CPU count, effective jobs, total seconds, lane seconds, recipe seconds, and status. Print the five slowest recipes plus exact reproduction commands. `--dry-run` prints ordering without spawning `just`.

- [ ] **Step 5: Add scheduler self-test gate**

  Add `test-scheduler` to `justfile`, run `just test-scheduler`, `JOBS=1 python3 scripts/test-framework/scheduler.py --dry-run --full`, and `JOBS=4 ...`; expect deterministic coverage and PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add scripts/test-framework/scheduler.py scripts/test-framework/test_scheduler.py justfile
  git commit -m "test: add conflict-aware test scheduler"
  ```

### Task 3: Fast Affected-Path Selector

**Files:**
- Create: `scripts/test-framework/select.py`
- Create: `scripts/test-framework/test_select.py`
- Modify: `scripts/test-framework/lanes.json`
- Modify: `justfile`

**Interfaces:**
- Consumes: changed paths from `git diff --name-only <base>...HEAD` and manifest tags.
- Produces: `select_tags(paths: Sequence[str]) -> set[str]`, CLI `--fast`, and `just check-fast`.

- [ ] **Step 1: Write table-driven failing tests**

  Pin EVM, Solana, Wasm/NEAR, shared IR/frontend/contract, docs/i18n, scheduler/CI, and unknown-path mappings. Pin the empty-diff fallback to the fixed fast baseline.

- [ ] **Step 2: Implement conservative path selection**

  Use `CHECK_BASE` when set; otherwise use the merge base with the configured upstream, falling back to `HEAD^`. Unknown infrastructure paths select the fixed baseline plus scheduler self-tests.

- [ ] **Step 3: Wire fast execution**

  Add manifest tags and:

  ```make
  check-fast:
      python3 scripts/test-framework/scheduler.py --fast
  ```

  Run selector unit tests and dry runs for synthetic EVM, Solana, Wasm, docs, and shared changes; expect the pinned recipe sets.

- [ ] **Step 4: Run representative fast gates**

  Run `CHECK_BASE=HEAD just check-fast` and one temporary commit-range fixture per backend. Record duration in the implementation log; require correct selection, not yet the final 2-5 minute target.

- [ ] **Step 5: Commit**

  ```bash
  git add scripts/test-framework/select.py scripts/test-framework/test_select.py scripts/test-framework/lanes.json justfile docs/implementation-log.md
  git commit -m "test: add affected-path fast gate"
  ```

### Task 4: Full Local Parallel and Serial Entrypoints

**Files:**
- Modify: `justfile`
- Modify: `scripts/test-framework/lanes.json`
- Create: `scripts/test-framework/check-equivalence.py`
- Create: `scripts/test-framework/test_equivalence.py`

**Interfaces:**
- Produces: `just check-serial`, `just check-parallel`, `just check-lane LANE`, and exact serial/parallel coverage comparison.

- [ ] **Step 1: Preserve the serial reference**

  Rename the current dependency list to `check-serial`. Keep `check` as an alias to `check-serial` during rollout.

- [ ] **Step 2: Add full and per-lane commands**

  Wire `check-parallel` to `scheduler.py --full` and `check-lane lane` to `--lane`. Verify `JOBS=1 just check-parallel --dry-run` contains the same coverage as four jobs.

- [ ] **Step 3: Add equivalence tests**

  Compare the manifest `serialCoverage` set with the `check-serial` dependencies and reject drift. Use `just --dump --dump-format json` when supported; otherwise maintain a machine-readable generated dependency file checked by both recipes, not regex parsing.

- [ ] **Step 4: Verify exclusive resource classification**

  Run scheduler fixtures that model shared output roots, fixed ports, and destructive rebuild directories. Keep `rebuild-hash`, `worker-limits`, `worker-cgroup`, and `testkit` exclusive in the initial release, with manifest reasons naming the protected resource.

- [ ] **Step 5: Verify local framework**

  Run `just test-manifest`, `just test-scheduler`, `python3 -m unittest scripts/test-framework/test_equivalence.py`, `JOBS=1 just check-parallel`, and `git diff --check`; expect PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add justfile scripts/test-framework docs/implementation-log.md
  git commit -m "test: expose serial and parallel full gates"
  ```

### Task 5: Stability and Performance Qualification

**Files:**
- Create: `scripts/test-framework/benchmark.py`
- Create: `docs/generated/test-timing-baseline.md`
- Modify: `docs/validation-gates.md`
- Modify: `docs/implementation-log.md`

**Interfaces:**
- Consumes: scheduler timing JSON and serial wall time.
- Produces: committed comparison report and cutover decision.

- [ ] **Step 1: Implement benchmark aggregation**

  Read timing reports and render machine, commit, job count, serial wall time, parallel wall time, improvement percentage, lane balance, and slowest recipes.

- [ ] **Step 2: Run the required qualification matrix**

  Run one `JOBS=1 just check-parallel`, three consecutive default-job `just check-parallel` runs, and one `just check-serial` on the same clean commit and warm cache.

- [ ] **Step 3: Evaluate acceptance**

  Require three green parallel runs, exact coverage equivalence, at least 35% local improvement, and no unexplained lane above 1.5 times median duration. Keep `check` serial if any condition fails and record the blocker.

- [ ] **Step 4: Document gates and commit**

  Run `just docs-check` and `git diff --check`, then commit timing report, validation catalog, and implementation log.

### Task 6: GitHub Actions Parallel Matrix

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/test-framework/lanes.json`
- Modify: `docs/implementation-log.md`

**Interfaces:**
- Produces: required jobs `product`, `check-lane` matrix, and `check-summary`.

- [ ] **Step 1: Add a four-lane matrix after product**

  Configure matrix values from the four manifest lane names. Each job installs the existing required tools, restores toolchain-keyed caches, and runs `just check-lane ${{ matrix.lane }}`.

- [ ] **Step 2: Add summary and artifact upload**

  Require all matrix cells. Upload `build/test-lanes/**/timings.json` always and lane logs on failure. Keep optional live jobs unchanged.

- [ ] **Step 3: Remove duplicate backend execution only after comparison**

  Compare old `build-test` steps against manifest coverage. Delete a step only when the validator proves its recipe exists in a required lane.

- [ ] **Step 4: Validate and commit**

  Run `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml")'`, scheduler dry-run for every lane, `just test-manifest`, and `git diff --check`; commit the workflow change.

### Task 7: Woodpecker Integration and Default Cutover

**Files:**
- Modify: `.woodpecker.yml`
- Modify: `justfile`
- Modify: `AGENTS.md`
- Modify: `docs/validation-gates.md`
- Modify: `docs/implementation-log.md`

**Interfaces:**
- Produces: Woodpecker parallel coordinator use and, only when qualified, `check -> check-parallel` with `check-serial` fallback.

- [ ] **Step 1: Wire Woodpecker to the shared coordinator**

  Preserve product-first ordering, then run `just check-parallel` with the default four-job cap. Do not duplicate canonical/product commands already proven by required steps unless the coverage policy intentionally requires them.

- [ ] **Step 2: Decide default cutover from Task 5 evidence**

  If all thresholds pass, make `check: check-parallel`; otherwise leave `check: check-serial` and record measured blockers. Never claim the cutover without the timing report.

- [ ] **Step 3: Update agent and validation documentation**

  Document `check-fast` for inner-loop work, `check-parallel` for pre-push, `check-serial` for race diagnosis, `JOBS`, `CHECK_BASE`, log locations, and optional-tool exclusions. Sync translations and manifest hashes.

- [ ] **Step 4: Final verification and commit**

  Run `ruby -e 'require "yaml"; YAML.load_file(".woodpecker.yml")'`, scheduler unit tests, manifest/equivalence validation, `just docs-check`, the selected default full gate, and `git diff --check`. Commit and push the completed framework.
