# D4 Native NFT Target-First Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `proof-forge build --target <primary> --nft <lean-source>` bypass `newCommandArgsToLegacy` and dispatch through a typed native target driver, while keeping all non-NFT paths on the legacy round-trip.

**Architecture:** Add `NativeBuildOp` in a standalone module; add `DispatchKind` / `BuildResult` to `TargetDriver.lean`; update primary triad `resolveBuild` to return `.native` for NFT+Lean inputs; add a `resolveBuildRequest` helper in `TargetFirst.lean`; wire native dispatch in `Cli.lean`; pin behavior in `Tests/CliTargetFirst.lean`.

**Tech Stack:** Lean 4, `lake`, `proof-forge` CLI, existing `ProofForge.Cli.*` modules.

## Global Constraints

- Only NFT `build` on primary targets (`evm`, `solana-sbpf-asm`, `wasm-near`) goes native.
- `emit` and `check` are unchanged; `check` is already native.
- `newCommandArgsToLegacy`, `LegacyArgs`, and `EmitMode` are NOT deleted (M4 scope).
- Native path must not produce user-visible legacy flag strings.
- Native path must preserve artifact output, yul/assembly output, metadata, constructor options, `--root`, `--module`, `--solc`, `--cast`, `--solana-sbpf-arch`, `--peer`, `--peers-demo`, `-o`, `--artifact-output`.
- D4 as a whole stays `replacement_ready`; only the NFT subrow moves to `default_switched`.

---

## File Structure

| File | Responsibility |
|---|---|
| `ProofForge/Cli/NativeBuildOp.lean` | `NativeBuildOp` type (isolated to avoid import cycles). |
| `ProofForge/Cli/TargetDriver.lean` | `BuildResult`, `DispatchKind`, and per-target `resolveBuild` registry. |
| `ProofForge/Cli/TargetFirst.lean` | `NewCommandParseState` parsing and new `resolveBuildRequest` helper. |
| `ProofForge/Cli.lean` | Top-level `build` dispatch: native vs legacy routing. |
| `Tests/CliTargetFirst.lean` | Dispatch-kind assertions for NFT native and non-NFT legacy. |
| `Tests/NftArtifactSchema.lean` | Artifact schema assertions for NFT CLI output. |
| `scripts/portable/nft-multi-target.sh` | Integration smoke for NFT multi-target build. |
| `docs/legacy-replacement-ledger.md` | D4 NFT subrow state update. |
| `docs/implementation-log.md` | D4 completion entry. |
| `AGENTS.md` | Checkpoint update. |
| `docs/superpowers/plans/2026-07-12-incremental-legacy-replacement.md` | D4 checklist completion. |

---

### Task 0: Create `ProofForge/Cli/NativeBuildOp.lean` to break import cycles

**Files:**
- Create: `ProofForge/Cli/NativeBuildOp.lean`

**Interfaces:**
- Produces: `NativeBuildOp` type, available to both `Options.lean` and `TargetDriver.lean` without a cycle.

- [ ] **Step 1: Create the file**

```lean
namespace ProofForge.Cli

inductive NativeBuildOp
  | nftEvmBytecode
  | nftSolanaSbpf
  | nftNearEmitWat
  deriving BEq, Repr

end ProofForge.Cli
```

- [ ] **Step 2: Commit**

```bash
git add ProofForge/Cli/NativeBuildOp.lean
git commit -m "chore(cli): add NativeBuildOp type in isolated module"
```

### Task 1: Add native dispatch result types to `TargetDriver.lean`

**Files:**
- Modify: `ProofForge/Cli/TargetDriver.lean:1-30`
- Test: `Tests/CliTargetFirst.lean`

**Interfaces:**
- Consumes: `NativeBuildOp` from Task 0.
- Produces: `DispatchKind`, `BuildResult`.
- Produces: `TargetCliDriver.resolveBuild : BuildRequest → Except String BuildResult`.

- [ ] **Step 1: Import `NativeBuildOp` and add result types**

Add to imports:

```lean
import ProofForge.Cli.NativeBuildOp
```

Insert after the `EmitRequest` structure definition:

```lean
inductive DispatchKind
  | legacy
  | native
  deriving BEq, Repr

structure BuildResult where
  dispatchKind : DispatchKind
  legacyFlag? : Option String := none
  nativeOp? : Option NativeBuildOp := none
  deriving Repr
```

- [ ] **Step 2: Change `TargetCliDriver.resolveBuild` signature**

Change:

```lean
structure TargetCliDriver where
  id : String
  resolveBuild : BuildRequest → Except String String
  resolveEmit : EmitRequest → Except String String
```

to:

```lean
structure TargetCliDriver where
  id : String
  resolveBuild : BuildRequest → Except String BuildResult
  resolveEmit : EmitRequest → Except String String
```

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Cli/TargetDriver.lean
git commit -m "refactor(cli): introduce BuildResult and DispatchKind for native target dispatch"
```

---

### Task 2: Update primary triad `resolveBuild` to return `.native` for NFT

**Files:**
- Modify: `ProofForge/Cli/TargetDriver.lean:48-211`

**Interfaces:**
- Consumes: `BuildResult`, `NativeBuildOp` from Task 1.
- Produces: `.native nftEvmBytecode`, `.native nftSolanaSbpf`, `.native nftNearEmitWat` results.

- [ ] **Step 1: Update `evmResolveBuild`**

Replace the top of `evmResolveBuild` so the NFT branch returns native:

```lean
def evmResolveBuild (req : BuildRequest) : Except String BuildResult :=
  let isLearn := isLearnInput req.input?
  let isLeanSource := isLeanSourceFile req.input?
  if req.nft then
    if isLeanSource then
      Except.ok { dispatchKind := .native, nativeOp? := some .nftEvmBytecode }
    else
      Except.error "proof-forge build --target evm --nft requires a .lean NFTSpec source"
  else if isLearn then
    ...
```

Then update every remaining `Except.ok "..."` in `evmResolveBuild` to wrap in `.legacy`:

```lean
Except.ok { dispatchKind := .legacy, legacyFlag? := some "--evm-bytecode" }
```

- [ ] **Step 2: Update `solanaResolveBuild`**

Similarly:

```lean
def solanaResolveBuild (req : BuildRequest) : Except String BuildResult :=
  let isLearn := isLearnInput req.input?
  let isLeanSource := isLeanSourceFile req.input?
  if req.nft then
    if isLeanSource then
      Except.ok { dispatchKind := .native, nativeOp? := some .nftSolanaSbpf }
    else
      Except.error "proof-forge build --target solana-sbpf-asm --nft requires a .lean NFTSpec source"
  else match isLearn, req.token with
  | true, true => Except.ok { dispatchKind := .legacy, legacyFlag? := some "--learn-token" }
  | true, false => Except.ok { dispatchKind := .legacy, legacyFlag? := some "--learn" }
  ...
```

- [ ] **Step 3: Update `nearResolveBuild`**

```lean
def nearResolveBuild (req : BuildRequest) : Except String BuildResult :=
  let isLearn := isLearnInput req.input?
  let isLeanSource := isLeanSourceFile req.input?
  if req.nft then
    if isLeanSource then
      Except.ok { dispatchKind := .native, nativeOp? := some .nftNearEmitWat }
    else
      Except.error "proof-forge build --target wasm-near --nft requires a .lean NFTSpec source"
  else if isLearn then
    Except.error "proof-forge build --target wasm-near from .learn source is not yet implemented"
  ...
```

- [ ] **Step 4: Build and fix compile errors**

```bash
lake build ProofForge.Cli.TargetDriver
```

Expected: success after updating all `Except.ok` branches.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Cli/TargetDriver.lean
git commit -m "feat(cli): primary triad returns native BuildResult for NFT builds"
```

---

### Task 3: Update secondary drivers and registry helpers

**Files:**
- Modify: `ProofForge/Cli/TargetDriver.lean:226-413`

**Interfaces:**
- Consumes: `BuildResult` from Task 1.
- Produces: `resolveBuildLegacyFlag` returns `Except String String` (kept for callers), `resolveBuild` returns `Except String BuildResult`.

- [ ] **Step 1: Update all secondary `resolveBuild` functions**

For each secondary driver (`sorobanResolveBuild`, `cosmwasmResolveBuild`, `psyResolveBuild`, `aleoResolveBuild`, `aptosResolveBuild`, `suiResolveBuild`, `cloudflareResolveBuild`, `quintResolveBuild`), wrap every `Except.ok "..."` in:

```lean
Except.ok { dispatchKind := .legacy, legacyFlag? := some "..." }
```

For `quintResolveBuild` errors remain errors.

- [ ] **Step 2: Update `resolveBuildLegacyFlag`**

Change it to use the new driver `resolveBuild` and extract the legacy flag when `.legacy`:

```lean
def resolveBuildLegacyFlag (target : String) (req : BuildRequest) : Except String String :=
  match findCliDriver? target with
  | some driver =>
      match driver.resolveBuild req with
      | .ok { dispatchKind := .legacy, legacyFlag? := some flag, .. } => Except.ok flag
      | .ok { dispatchKind := .native, .. } => Except.error "internal: native build requested via legacy flag helper"
      | .ok _ => Except.error "internal: BuildResult missing legacy flag"
      | .error e => Except.error e
  | none => Except.error s!"unknown target '{target}'"
```

- [ ] **Step 3: Add top-level `resolveBuild`**

Add after `resolveBuildLegacyFlag`:

```lean
def resolveBuild (target : String) (req : BuildRequest) : Except String BuildResult :=
  match findCliDriver? target with
  | some driver => driver.resolveBuild req
  | none => Except.error s!"unknown target '{target}'"
```

- [ ] **Step 4: Build**

```bash
lake build ProofForge.Cli.TargetDriver
```

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Cli/TargetDriver.lean
git commit -m "feat(cli): secondary drivers and registry helpers use BuildResult"
```

---

### Task 4: Add `resolveBuildRequest` helper in `TargetFirst.lean`

**Files:**
- Modify: `ProofForge/Cli/TargetFirst.lean:126-170`

**Interfaces:**
- Produces: `resolveBuildRequest : NewCommandParseState → Except String (String × BuildRequest)`.

- [ ] **Step 1: Add helper after output-path helpers**

```lean
def resolveBuildRequest (state : NewCommandParseState) : Except String (String × BuildRequest) := do
  let target ← match state.target? with
    | some t => Except.ok t
    | none => Except.error "build requires --target <id>"
  let req : BuildRequest := {
    input? := state.input?
    fixture? := state.fixture?
    format? := state.format?
    token := state.token
    nft := state.nft
  }
  Except.ok (target, req)
```

- [ ] **Step 2: Build**

```bash
lake build ProofForge.Cli.TargetFirst
```

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Cli/TargetFirst.lean
git commit -m "feat(cli): add resolveBuildRequest helper for native dispatch"
```

---

### Task 5: Wire native dispatch in `Cli.lean`

**Files:**
- Modify: `ProofForge/Cli.lean:364-377`
- Test: `Tests/CliTargetFirst.lean`

**Interfaces:**
- Consumes: `resolveBuildRequest` from Task 4, `resolveBuild` / `BuildResult` / `NativeBuildOp` from Task 3.
- Produces: Native `build` branch that calls `compileContractSourceEvmBytecode`, `compileContractSourceSbpf`, or `compileContractSourceEmitWat` directly.

- [ ] **Step 1: Add `nativeBuildOp?` to `CliOptions`**

In `ProofForge/Cli/Options.lean`, add `import ProofForge.Cli.NativeBuildOp` to imports and add the field to `CliOptions`:

```lean
nativeBuildOp? : Option NativeBuildOp := none
```

- [ ] **Step 2: Add native `buildOptions` constructor in `Cli.lean`**

Add a helper inside the `ProofForge.Cli` namespace that builds a full `CliOptions` from `NewCommandParseState` for native dispatch:

```lean
def buildNativeOptions (state : ProofForge.Cli.NewCommandParseState) (op : ProofForge.Cli.NativeBuildOp) : Except String CliOptions := do
  let mode ← match op with
    | .nftEvmBytecode => Except.ok .evmBytecode
    | .nftSolanaSbpf => Except.ok .contractSourceSbpf
    | .nftNearEmitWat => Except.ok .contractSourceEmitWat
  let target := state.target?.getD ""
  let flag ← match op with
    | .nftEvmBytecode => Except.ok "--evm-bytecode"
    | .nftSolanaSbpf => Except.ok "--contract-source-sbpf"
    | .nftNearEmitWat => Except.ok "--contract-source-emitwat"
  let output? := state.out?.map (targetFirstNativeOutput target flag ·)
  let yulOutput? :=
    match state.yulOut? with
    | some y => some (FilePath.mk y)
    | none => targetFirstYulOutput? target flag output? none
  Except.ok {
    cmd := .build
    mode := mode
    input? := state.input?.map FilePath.mk
    output? := output?
    root? := state.root?.map FilePath.mk
    moduleName? := state.module?.map parseModuleName
    yulOutput? := yulOutput?
    artifactOutput? := state.artifactOut?.map FilePath.mk
    solc := state.solc
    cast := state.cast
    evmChainProfile? := state.evmChainProfile?
    evmConstructorParams := state.evmConstructorParams
    evmConstructorValues := state.evmConstructorValues
    evmConstructorArgsHex := state.evmConstructorArgsHex
    solanaSbpfArch := state.solanaSbpfArch?.getD "v3"
    targetId? := state.target?
    fixture? := state.fixture?
    format? := state.format?
    nft := true
    peerMap := state.peers.foldl (fun m spec =>
      match ProofForge.Target.PeerMap.parseBinding spec with
      | .ok b => ProofForge.Target.PeerMap.merge m (ProofForge.Target.PeerMap.singleton b)
      | .error _ => m) (if state.peersDemo then ProofForge.Target.PeerMap.nearDemo else ProofForge.Target.PeerMap.identity)
    nativeBuildOp? := some op
    fromNewSurface := true
    : CliOptions
  }
```

This reuses `targetFirstNativeOutput` and `targetFirstYulOutput?` from `ProofForge.Cli.TargetFirst` for output-path parity with the legacy path.

- [ ] **Step 3: Rewrite `build` branch in `dispatch`**

Replace:

```lean
| "build" :: rest =>
    match ProofForge.Cli.parseNewOptions rest {} with
    | Except.ok state =>
        match ProofForge.Cli.newCommandArgsToLegacy state "build" with
        | Except.ok legacyArgs =>
            match ProofForge.Cli.parseArgs legacyArgs {} with
            | Except.ok opts => Except.ok { opts with
                cmd := ProofForge.Cli.Command.build,
                format? := state.format?,
                scenario? := state.scenario?.map FilePath.mk,
                fromNewSurface := true }
            | Except.error msg => Except.error msg
        | Except.error msg => Except.error msg
    | Except.error msg => Except.error msg
```

with:

```lean
| "build" :: rest =>
    match ProofForge.Cli.parseNewOptions rest {} with
    | Except.ok state =>
        match ProofForge.Cli.TargetFirst.resolveBuildRequest state with
        | Except.ok (target, req) =>
            match ProofForge.Cli.TargetDriver.resolveBuild target req with
            | Except.ok { dispatchKind := .native, nativeOp? := some op, .. } =>
                match buildNativeOptions state op with
                | Except.ok opts => Except.ok opts
                | Except.error msg => Except.error msg
            | Except.ok { dispatchKind := .legacy, legacyFlag? := some _, .. } =>
                match ProofForge.Cli.newCommandArgsToLegacy state "build" with
                | Except.ok legacyArgs =>
                    match ProofForge.Cli.parseArgs legacyArgs {} with
                    | Except.ok opts => Except.ok { opts with
                        cmd := ProofForge.Cli.Command.build,
                        format? := state.format?,
                        scenario? := state.scenario?.map FilePath.mk,
                        fromNewSurface := true }
                    | Except.error msg => Except.error msg
                | Except.error msg => Except.error msg
            | Except.ok _ =>
                Except.error "internal: BuildResult missing dispatch data"
            | Except.error msg => Except.error msg
        | Except.error msg => Except.error msg
    | Except.error msg => Except.error msg
```

- [ ] **Step 4: Handle native build in execution phase**

Around `ProofForge/Cli.lean:440` (where `compileFile` is called), change:

```lean
ProofForge.Cli.compileFile opts
```

to:

```lean
match opts.nativeBuildOp? with
| some op =>
    match op with
    | .nftEvmBytecode => compileContractSourceEvmBytecode opts
    | .nftSolanaSbpf => compileContractSourceSbpf opts
    | .nftNearEmitWat => compileContractSourceEmitWat opts
| none => ProofForge.Cli.compileFile opts
```

- [ ] **Step 5: Build**

```bash
lake build ProofForge.Cli
```

- [ ] **Step 6: Commit**

```bash
git add ProofForge/Cli.lean ProofForge/Cli/Options.lean ProofForge/Cli/TargetFirst.lean ProofForge/Cli/TargetDriver.lean ProofForge/Cli/NativeBuildOp.lean
git commit -m "feat(cli): native NFT build dispatch bypasses legacy argument rewrite"
```

---

### Task 6: Update `Tests/CliTargetFirst.lean`

**Files:**
- Modify: `Tests/CliTargetFirst.lean`

**Interfaces:**
- Consumes: `NativeBuildOp` from Task 0; `BuildResult`, `DispatchKind` from Task 1.

- [ ] **Step 1: Read current test structure**

```bash
lake env lean --run Tests/CliTargetFirst.lean
```

Current expected output: existing tests pass.

- [ ] **Step 2: Add native dispatch assertions**

After existing tests, add:

```lean
def requireNftNative (target : String) (input : String) : IO Unit := do
  let state ← match ProofForge.Cli.parseNewOptions ["--target", target, "--nft", input] {} with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"parse failed: {e}"
  let (gotTarget, req) ← match ProofForge.Cli.TargetFirst.resolveBuildRequest state with
    | .ok r => pure r
    | .error e => throw <| IO.userError e
  unless gotTarget == target do
    throw <| IO.userError s!"target mismatch: {gotTarget} != {target}"
  match ProofForge.Cli.TargetDriver.resolveBuild gotTarget req with
  | .ok { dispatchKind := .native, nativeOp? := some op, .. } =>
      let expectedOp ← match target with
        | "evm" => pure ProofForge.Cli.NativeBuildOp.nftEvmBytecode
        | "solana-sbpf-asm" => pure ProofForge.Cli.NativeBuildOp.nftSolanaSbpf
        | "wasm-near" => pure ProofForge.Cli.NativeBuildOp.nftNearEmitWat
        | _ => throw <| IO.userError s!"unexpected native target {target}"
      unless op == expectedOp do
        throw <| IO.userError s!"native op mismatch for {target}: {repr op}"
  | .ok other =>
      throw <| IO.userError s!"expected native dispatch for {target}, got {repr other}"
  | .error e =>
      throw <| IO.userError s!"resolve failed for {target}: {e}"

def requireLegacy (target : String) (fixture? : Option String := none) : IO Unit := do
  let args := ["--target", target] ++ fixture?.toList.flatMap (fun f => ["--fixture", f])
  let state ← match ProofForge.Cli.parseNewOptions args {} with
    | .ok s => pure s
    | .error e => throw <| IO.userError e
  let (gotTarget, req) ← match ProofForge.Cli.TargetFirst.resolveBuildRequest state with
    | .ok r => pure r
    | .error e => throw <| IO.userError e
  match ProofForge.Cli.TargetDriver.resolveBuild gotTarget req with
  | .ok { dispatchKind := .legacy, legacyFlag? := some _, .. } => pure ()
  | .ok other => throw <| IO.userError s!"expected legacy dispatch for {target}, got {repr other}"
  | .error e => throw <| IO.userError e
```

Then in the main test runner, add:

```lean
requireNftNative "evm" "Examples/Product/Nft.lean"
requireNftNative "solana-sbpf-asm" "Examples/Product/Nft.lean"
requireNftNative "wasm-near" "Examples/Product/Nft.lean"
requireLegacy "evm" (some "counter")
requireLegacy "solana-sbpf-asm" (some "counter")
requireLegacy "wasm-near" (some "counter")
```

- [ ] **Step 3: Run tests**

```bash
lake env lean --run Tests/CliTargetFirst.lean
```

Expected: `cli-target-first: ok`

- [ ] **Step 4: Commit**

```bash
git add Tests/CliTargetFirst.lean
git commit -m "test(cli): pin NFT native dispatch and non-NFT legacy dispatch"
```

---

### Task 7: Verify integration gates

**Files:**
- Read-only: `Tests/NftArtifactSchema.lean`, `scripts/portable/nft-multi-target.sh`

- [ ] **Step 1: Run NFT artifact schema test**

```bash
lake env lean --run Tests/NftArtifactSchema.lean
```

Expected: passes (may need updates if native path changes observable fields).

- [ ] **Step 2: Run NFT multi-target script**

```bash
scripts/portable/nft-multi-target.sh
```

Expected: all three primary targets produce artifacts.

- [ ] **Step 3: Run product gate**

```bash
just product
```

Expected: passes.

- [ ] **Step 4: Run full static baseline**

```bash
just check
```

Expected: passes (quint verify may be skipped if Java 17+ is missing).

- [ ] **Step 5: Commit fixes if any**

```bash
git diff --check
```

---

### Task 8: Update documentation and ledger

**Files:**
- Modify: `docs/legacy-replacement-ledger.md`
- Modify: `docs/implementation-log.md`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/plans/2026-07-12-incremental-legacy-replacement.md`

- [ ] **Step 1: Update D4 ledger section**

In `docs/legacy-replacement-ledger.md` D4 section, change state from `inventoried` to note NFT subrow `default_switched` and D4 overall `replacement_ready`. Add evidence:

```markdown
- **State:** `replacement_ready` overall; NFT `build` subrow is `default_switched`.
- **Evidence:**
  - `Tests/CliTargetFirst.lean` asserts NFT primary-triad dispatch kind is `.native`.
  - Non-NFT Counter/Token/fixture paths still return `.legacy`.
  - `scripts/portable/nft-multi-target.sh` and `just product` exercise the native path.
```

- [ ] **Step 2: Add implementation log entry**

Append to `docs/implementation-log.md`:

```markdown
## 2026-07-12 - D4: Native NFT target-first dispatch

- Status: `done (verified at <sha>)`
- Result: switched NFT `build` on the primary triad to a typed native target driver.
  `TargetDriver.resolveBuild` returns `BuildResult` with `.native`/`DispatchKind`;
  `Cli.lean` bypasses `newCommandArgsToLegacy` for NFT and calls
  `compileContractSourceEvmBytecode` / `compileContractSourceSbpf` /
  `compileContractSourceEmitWat` directly.
- Interfaces: `ProofForge.Cli.TargetDriver.BuildResult`,
  `ProofForge.Cli.TargetFirst.resolveBuildRequest`,
  `ProofForge.Cli.CliOptions.nativeBuildOp?`.
- Verification:
  - `lake env lean --run Tests/CliTargetFirst.lean` passed
  - `lake env lean --run Tests/NftArtifactSchema.lean` passed
  - `scripts/portable/nft-multi-target.sh` passed
  - `just product` passed
  - `just check` passed
  - `git diff --check` passed
- Remaining: migrate Counter, ValueVault, Token, RemoteCall, and secondary targets
  to native dispatch before D4 reaches `default_switched`.
- Documentation: `docs/legacy-replacement-ledger.md`, `AGENTS.md`, current plan,
  `docs/implementation-log.md`.
```

- [ ] **Step 3: Update AGENTS.md checkpoint**

Set active task to D4 and state to `in_progress` during work, then `done (verified at <sha>)` when complete. Update next task to D5.

- [ ] **Step 4: Update authoritative plan D4 checklist**

In `docs/superpowers/plans/2026-07-12-incremental-legacy-replacement.md`, mark D4 steps complete and note NFT-only scope.

- [ ] **Step 5: Commit**

```bash
git add docs/legacy-replacement-ledger.md docs/implementation-log.md AGENTS.md docs/superpowers/plans/2026-07-12-incremental-legacy-replacement.md
git commit -m "docs: record D4 NFT native dispatch completion"
```

---

## Self-Review Checklist

- [ ] Spec coverage: every section of `2026-07-12-d4-native-nft-dispatch-design.md` maps to a task.
- [ ] No placeholders: every step has exact file paths, code, and commands.
- [ ] Type consistency: `BuildResult`, `DispatchKind`, `NativeBuildOp` used consistently across tasks.
- [ ] Scope control: only NFT build on primary targets is native; emit/check and non-NFT stay legacy.
