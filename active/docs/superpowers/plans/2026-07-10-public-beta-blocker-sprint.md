# Public Beta Blocker Sprint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the public-beta blockers identified in `docs/review/scorecard.md` so ProofForge is installable, trustworthy, and honest about its supported target surface.

**Architecture:** The work is concentrated in four seams:
1. **CLI entry surface** (`ProofForge/Cli.lean`, `ProofForge/Cli/Usage.lean`, `ProofForge/Cli/TargetFirst.lean`, `ProofForge/Cli/Deploy.lean`) for `--version`, `--help`, and deploy key handling.
2. **Repository trust signals** (`.gitignore`, `.github/workflows/secret-scan.yml`, `CHANGELOG.md`) for secret hygiene and release hygiene.
3. **Release/distribution plumbing** (`.github/workflows/release.yml`, `scripts/ci/install.sh`) for cross-platform binaries and one-line installation.
4. **Documentation/i18n honesty** (`README.md`, `AGENTS.md`, `docs/zh`, `scripts/i18n/check-links.py`) for a corrected onboarding command and an honest target roster.

**Tech Stack:** Lean 4 / Lake, GitHub Actions, bash, Python 3, Foundry/Anvil (for deploy smokes).

## Global Constraints

- Keep `just product` green after every task.
- Preserve existing legacy-flag fixture/CI paths.
- Do not add new external dependencies unless already used in CI.
- All code changes must include tests or CI smoke checks.

---

### Task 1: Add `--version` to `proof-forge`

**Files:**
- Modify: `ProofForge/Cli.lean`
- Test: `lake env proof-forge --version`

**Interfaces:**
- New CLI command: `proof-forge --version`
- Output lines: version string (`0.1.0-beta.1`), Lean toolchain, git short SHA (or `unknown`).

- [ ] **Step 1: Add version helpers in `ProofForge/Cli.lean`.**
  Insert the following definitions inside the `ProofForge.Cli` namespace, after `emitWatFixtureModule?`:

  ```lean
  def cliVersion : String :=
    "0.1.0-beta.1"

  def readFileTrim (path : String) : IO String := do
    let s ← IO.FS.readFile (FilePath.mk path)
    return s.trim

  def gitShortSha? : IO (Option String) := do
    try
      let out ← IO.Process.output { cmd := "git", args := #["rev-parse", "--short", "HEAD"] }
      if out.exitCode == 0 then
        return some out.stdout.trim
      else
        return none
    catch _ =>
      return none

  def printVersion : IO UInt32 := do
    let toolchain ← try readFileTrim "lean-toolchain" catch _ => pure "unknown"
    let sha ← gitShortSha?
    IO.println s!"proof-forge {cliVersion}"
    IO.println s!"Lean toolchain: {toolchain}"
    match sha with
    | some s => IO.println s!"git sha: {s}"
    | none => IO.println "git sha: unknown"
    return 0
  ```

- [ ] **Step 2: Wire `--version` into `main`.**
  In `ProofForge/Cli.lean`, change the top of `unsafe def main` so the new branch appears before the catch-all `_` pattern:

  ```lean
  unsafe def main (args : List String) : IO UInt32 := do
    match args with
    | "init" :: rest =>
      ...
    | "deploy" :: rest =>
      ...
    | "metadata" :: rest =>
      ...
    | ["--version"] | "--version" :: _ =>
      ProofForge.Cli.printVersion
    | _ =>
      ... existing catch-all body unchanged ...
  ```

- [ ] **Step 3: Build and verify.**
  ```bash
  just build
  lake env proof-forge --version
  ```
  Expected output (SHA varies):
  ```text
  proof-forge 0.1.0-beta.1
  Lean toolchain: leanprover/lean4:v4.x.x
  git sha: <short-sha>
  ```

---

### Task 2: Add `--help` handling for target-first verbs `build`/`emit`/`check` and global usage

**Files:**
- Modify: `ProofForge/Cli/Usage.lean`
- Modify: `ProofForge/Cli.lean`
- Test: `lake env proof-forge --help`, `lake env proof-forge build --help`, `lake env proof-forge emit --help`, `lake env proof-forge check --help`

**Interfaces:**
- `proof-forge --help` / `proof-forge -h` prints global usage to stdout and exits `0`.
- `proof-forge build --help` prints `buildUsage`.
- `proof-forge emit --help` prints `emitUsage`.
- `proof-forge check --help` prints `checkUsage`.

- [ ] **Step 1: Append per-command usage strings to `ProofForge/Cli/Usage.lean`.**
  Add the following definitions at the end of the `ProofForge.Cli` namespace, before `end ProofForge.Cli`:

  ```lean
  def buildUsage : String :=
    String.intercalate "\n" [
      "Usage: proof-forge build --target <id> [options] [input.lean]",
      "",
      "Compile a Lean contract source to a target artifact.",
      "",
      "Required:",
      "  --target <id>             target backend (evm | solana-sbpf-asm | wasm-near | …)",
      "",
      "Input / project root:",
      "  input.lean                source file (mutually exclusive with --fixture)",
      "  --root DIR                project root for relative imports/outputs",
      "  --module Mod.Name         module name when input path does not determine it",
      "  --fixture <id>            emit a built-in IR fixture instead of a source file",
      "",
      "Output paths:",
      "  -o, --output PATH         native output path or directory",
      "  --yul-output PATH         EVM Yul intermediate output",
      "  --artifact-output PATH    proof-forge-artifact.json path",
      "",
      "EVM-specific options:",
      "  --evm-chain-profile ID    deployment chain profile metadata",
      "  --evm-constructor-param name:type   constructor ABI schema metadata",
      "  --evm-constructor-arg name=value    ABI-encode one typed constructor value",
      "  --evm-constructor-args-hex HEX      append raw ABI-encoded constructor args",
      "  --solc PATH               solc executable (default: solc)",
      "  --cast PATH               cast executable (default: cast)",
      "",
      "Solana-specific options:",
      "  --solana-sbpf-arch v0|v3  sBPF version (default: v3)",
      "",
      "Other options:",
      "  --peer logical=host       deploy-time peer binding",
      "  --peers-demo              enable demo peer bindings",
      "",
      "Use `proof-forge --help` for the full command list."
    ]

  def emitUsage : String :=
    String.intercalate "\n" [
      "Usage: proof-forge emit --target <id> --fixture <id> [options]",
      "",
      "Emit a built-in IR fixture to a target source or artifact.",
      "",
      "Required:",
      "  --target <id>             target backend",
      "  --fixture <id>            fixture id (see `proof-forge --list-fixtures`)",
      "",
      "Output / format:",
      "  -o, --output PATH         output path or directory",
      "  --format <fmt>            target-specific format (e.g., wat, elf, yul, psy)",
      "  --yul-output PATH         EVM Yul intermediate output",
      "  --artifact-output PATH    proof-forge-artifact.json path",
      "  --scenario PATH           Quint scenario TOML input",
      "",
      "EVM / Solana:",
      "  --evm-chain-profile ID    deployment chain profile metadata",
      "  --solc PATH               solc executable (default: solc)",
      "  --cast PATH               cast executable (default: cast)",
      "  --solana-sbpf-arch v0|v3  sBPF version (default: v3)",
      "",
      "Use `proof-forge --help` for the full command list."
    ]

  def checkUsage : String :=
    String.intercalate "\n" [
      "Usage: proof-forge check --target <id> [options] [input.lean]",
      "",
      "Validate that a source file or fixture is supported by a target.",
      "",
      "Required:",
      "  --target <id>             target backend",
      "",
      "Input:",
      "  input.lean                source file",
      "  --fixture <id>            fixture id",
      "  --format <fmt>            fixture format",
      "  --root DIR                project root",
      "  --module Mod.Name         module name",
      "",
      "Reporting:",
      "  --report-format json|text   output format (default: text)",
      "",
      "Use `proof-forge --help` for the full command list."
    ]
  ```

- [ ] **Step 2: Refactor `main` into `dispatch` + pre-checks in `ProofForge/Cli.lean`.**
  This keeps the existing parser/dispatch logic unchanged while letting `--help`, `-h`, and `--version` return before any legacy parsing runs.

  Replace the current `unsafe def main` (lines ~303–415) with the following two definitions:

  ```lean
  def wantsHelp (args : List String) : Bool :=
    args.any (fun a => a == "--help" || a == "-h")

  unsafe def dispatch (args : List String) : IO UInt32 := do
    match args with
    | "init" :: rest =>
        match ProofForge.Cli.Scaffold.parseInitOptions rest with
        | Except.ok opts => ProofForge.Cli.Scaffold.initCommand opts
        | Except.error msg =>
            IO.eprintln msg
            return 1
    | "deploy" :: rest =>
        match ProofForge.Cli.Deploy.parseDeployOptions rest with
        | Except.ok opts => ProofForge.Cli.Deploy.deployCommand opts
        | Except.error msg =>
            IO.eprintln msg
            return 1
    | "metadata" :: rest =>
        match ProofForge.Cli.Metadata.parseMetadataOptions rest with
        | Except.ok opts => ProofForge.Cli.Metadata.metadataCommand opts
        | Except.error msg =>
            IO.eprintln msg
            return 1
    | _ =>
        let parseResult : Except String ProofForge.Cli.CliOptions :=
          match args with
          | "--list-targets" :: rest =>
              let wantsJson := rest.any (fun a => a == "--json")
              Except.ok {
                cmd := ProofForge.Cli.Command.listTargets
                reportFormat? := if wantsJson then some "json" else none }
          | "--list-fixtures" :: _ => Except.ok { cmd := ProofForge.Cli.Command.listFixtures }
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
          | "emit" :: rest =>
              match ProofForge.Cli.parseNewOptions rest {} with
              | Except.ok state =>
                  match ProofForge.Cli.newCommandArgsToLegacy state "emit" with
                  | Except.ok legacyArgs =>
                      match ProofForge.Cli.parseArgs legacyArgs {} with
                      | Except.ok opts => Except.ok { opts with
                          cmd := ProofForge.Cli.Command.emit,
                          fixture? := state.fixture?,
                          format? := state.format?,
                          scenario? := state.scenario?.map FilePath.mk,
                          fromNewSurface := true }
                      | Except.error msg => Except.error msg
                  | Except.error msg => Except.error msg
              | Except.error msg => Except.error msg
          | "check" :: rest =>
              match ProofForge.Cli.parseNewOptions rest {} with
              | Except.ok state =>
                  Except.ok {
                    cmd := ProofForge.Cli.Command.check,
                    targetId? := state.target?,
                    fixture? := state.fixture?,
                    format? := state.format?,
                    reportFormat? := state.reportFormat?,
                    input? := state.input?.map FilePath.mk,
                    root? := state.root?.map FilePath.mk,
                    moduleName? := state.module?.map ProofForge.Cli.parseModuleName,
                    fromNewSurface := true
                    : ProofForge.Cli.CliOptions }
              | Except.error msg => Except.error msg
          | "metadata" :: rest =>
              match ProofForge.Cli.parseNewOptions rest {} with
              | Except.ok state =>
                  Except.ok {
                    cmd := ProofForge.Cli.Command.metadata,
                    fixture? := state.fixture?,
                    output? := state.out?.map FilePath.mk,
                    root? := state.root?.map FilePath.mk,
                    fromNewSurface := true
                    : ProofForge.Cli.CliOptions }
              | Except.error msg => Except.error msg
          | _ => ProofForge.Cli.parseArgs args {}
        match parseResult with
        | Except.ok opts => do
            match opts.cmd with
            | ProofForge.Cli.Command.listTargets =>
                if opts.reportFormat? == some "json" then
                  IO.println ProofForge.Cli.listTargetsJson
                else
                  IO.println (String.intercalate "\n" ProofForge.Target.knownIds.toList)
                return 0
            | ProofForge.Cli.Command.listFixtures =>
                IO.println (String.intercalate "\n" ProofForge.Cli.Fixture.ids.toList)
                return 0
            | ProofForge.Cli.Command.check =>
                ProofForge.Cli.checkCommand opts
            | ProofForge.Cli.Command.metadata =>
                ProofForge.Cli.Metadata.metadataCommandFromCliOptions opts
            | _ =>
                if !opts.fromNewSurface then
                  if let some note := opts.mode.deprecationNote then
                    IO.eprintln note
                if opts.evmChainProfile?.isSome then
                  discard <| ProofForge.Cli.resolveEvmChainProfile? opts.evmChainProfile?
                ProofForge.Cli.compileFile opts
        | Except.error msg =>
            IO.eprintln msg
            return 1

  unsafe def main (args : List String) : IO UInt32 := do
    match args with
    | ["--version"] | "--version" :: _ =>
        ProofForge.Cli.printVersion
    | ["--help"] | "--help" :: _ | ["-h"] | "-h" :: _ =>
        IO.println usage
        return 0
    | [] =>
        IO.println usage
        return 0
    | "build" :: rest =>
        if wantsHelp rest then
          IO.println buildUsage
          return 0
        else
          dispatch args
    | "emit" :: rest =>
        if wantsHelp rest then
          IO.println emitUsage
          return 0
        else
          dispatch args
    | "check" :: rest =>
        if wantsHelp rest then
          IO.println checkUsage
          return 0
        else
          dispatch args
    | _ =>
        dispatch args
  ```

- [ ] **Step 3: Build and verify.**
  ```bash
  just build
  lake env proof-forge --help
  lake env proof-forge -h
  lake env proof-forge build --help
  lake env proof-forge emit --help
  lake env proof-forge check --help
  ```
  Each command must print the corresponding usage text and exit `0`.

---

### Task 3: Remove the stale `proof-forge check is not yet implemented` stub

**Files:**
- Modify: `ProofForge/Cli/TargetFirst.lean`
- Test: `lake env proof-forge check --target wasm-near --fixture counter --format wat`

**Interfaces:**
- `ProofForge.Cli.newCommandArgsToLegacy` no longer returns `proof-forge check is not yet implemented`.
- `check` is already dispatched natively in `ProofForge/Cli.lean`; the stub only existed as an unreachable fallback.

- [ ] **Step 1: Replace the `check` branch in `newCommandArgsToLegacy`.**
  In `ProofForge/Cli/TargetFirst.lean`, change:

  ```lean
  else if cmd == "check" then
    Except.error "proof-forge check is not yet implemented"
  ```

  to:

  ```lean
  else if cmd == "check" then
    Except.error "check is routed natively; newCommandArgsToLegacy should not be called for check"
  ```

- [ ] **Step 2: Build and verify.**
  ```bash
  just build
  lake env proof-forge check --target wasm-near --fixture counter --format wat
  ```
  Expected: command succeeds (prints an `ok` status line) and exits `0`.

---

### Task 4: Harden `deploy` private key handling

**Files:**
- Modify: `ProofForge/Cli/Deploy.lean`
- Modify: `Tests/CliDeploy.lean`
- Modify: `scripts/evm/anvil-deploy-smoke.sh`
- Modify: `scripts/evm/broadcast-smoke.sh`
- Test: `lake env lean --run Tests/CliDeploy.lean`, `just evm-anvil-deploy`, `just evm-broadcast-smoke`

**Interfaces:**
- `ProofForge.Cli.Deploy.resolvePrivateKey : DeployOptions → IO String`
- Resolution order: `--private-key` value, then `PROOF_FORGE_DEPLOY_PRIVATE_KEY` env var, then error.
- No hardcoded Anvil fallback.

- [ ] **Step 1: Remove the hardcoded Anvil key and add explicit resolution in `ProofForge/Cli/Deploy.lean`.**
  - Delete the definition:
    ```lean
    def defaultAnvilPrivateKey : String :=
      "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    ```
  - Update the `--private-key` line in `deployUsage` from:
    ```lean
    "  --private-key KEY       signing key for cast send (default: Anvil test key)",
    ```
    to:
    ```lean
    "  --private-key KEY       signing key for cast send (required unless PROOF_FORGE_DEPLOY_PRIVATE_KEY is set)",
    ```
  - Insert `resolvePrivateKey` after `defaultAnvilChainId`:
    ```lean
    def resolvePrivateKey (opts : DeployOptions) : IO String := do
      if let some key := opts.privateKey? then
        if key.isEmpty then
          throw <| IO.userError "--private-key value is empty"
        return key
      if let some key ← IO.getEnv "PROOF_FORGE_DEPLOY_PRIVATE_KEY" then
        if key.isEmpty then
          throw <| IO.userError "PROOF_FORGE_DEPLOY_PRIVATE_KEY is set but empty"
        return key
      throw <| IO.userError "deploy requires --private-key KEY or the PROOF_FORGE_DEPLOY_PRIVATE_KEY environment variable"
    ```
  - In `broadcastEvmDeploy`, replace:
    ```lean
    let privateKey := opts.privateKey?.getD defaultAnvilPrivateKey
    ```
    with:
    ```lean
    let privateKey ← resolvePrivateKey opts
    ```
    This line is after the `shouldPlanOnly` early-return, so plan-only mode never requires a key.

- [ ] **Step 2: Add private-key tests to `Tests/CliDeploy.lean`.**
  Append the following tests before the final `IO.println "CliDeploy: ok"`:

  ```lean
  match ProofForge.Cli.Deploy.parseDeployOptions [
    "--target", "evm",
    "--deploy-manifest", "build/evm/Counter.proof-forge-deploy.json",
    "--private-key", "0x1234"
  ] with
  | Except.ok opts => do
      let key ← ProofForge.Cli.Deploy.resolvePrivateKey opts
      require (key == "0x1234") "explicit private key resolution"
  | Except.error err => throw <| IO.userError err

  try
    let _ ← ProofForge.Cli.Deploy.resolvePrivateKey {
      targetId := "evm",
      deployManifest := "build/evm/Counter.proof-forge-deploy.json"
    }
    require false "missing private key should error"
  catch _ =>
    pure ()

  match ← IO.getEnv "PROOF_FORGE_DEPLOY_TEST_KEY" with
  | some envKey =>
      match ProofForge.Cli.Deploy.parseDeployOptions [
        "--target", "evm",
        "--deploy-manifest", "build/evm/Counter.proof-forge-deploy.json"
      ] with
      | Except.ok opts => do
          let key ← ProofForge.Cli.Deploy.resolvePrivateKey opts
          require (key == envKey) "env var private key resolution"
      | Except.error err => throw <| IO.userError err
  | none =>
      pure ()
  ```

- [ ] **Step 3: Export the test key in EVM deploy smokes.**
  In `scripts/evm/anvil-deploy-smoke.sh`, add after the existing variable defaults (around line 25):

  ```bash
  export PROOF_FORGE_DEPLOY_PRIVATE_KEY="${PROOF_FORGE_DEPLOY_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
  ```

  In `scripts/evm/broadcast-smoke.sh`, add after the existing `ROOT=...` line (around line 8):

  ```bash
  export PROOF_FORGE_DEPLOY_PRIVATE_KEY="${PROOF_FORGE_DEPLOY_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
  ```

- [ ] **Step 4: Build and verify.**
  ```bash
  just build
  lake env lean --run Tests/CliDeploy.lean
  PROOF_FORGE_DEPLOY_TEST_KEY=0xdeadbeef lake env lean --run Tests/CliDeploy.lean
  just evm-anvil-deploy
  just evm-broadcast-smoke
  ```
  All must pass. The `PROOF_FORGE_DEPLOY_TEST_KEY` run exercises the env-var resolution path.

---

### Task 5: Harden `.gitignore` to ignore key material

**Files:**
- Modify: `.gitignore`
- Test: `git check-ignore -v path/to/test.pem id.json fake.key`

**Interfaces:**
- New `.gitignore` patterns cover `.env`, `*.pem`, `*.key`, keypair files, mnemonics, `id.json`, and `*.p12`.

- [ ] **Step 1: Append key-material patterns to `.gitignore`.**
  Add at the end of `.gitignore`:

  ```gitignore
  # Key material and secrets
  .env
  .env.*
  *.pem
  *.key
  *.p12
  *.pkcs12
  *.keystore
  *.jks
  id.json
  *.mnemonic
  *.seed
  *keypair*
  ```

- [ ] **Step 2: Verify patterns.**
  ```bash
  touch /tmp/test.pem /tmp/id.json /tmp/fake.key
  git check-ignore -v /tmp/test.pem /tmp/id.json /tmp/fake.key
  ```
  Each path must be matched by a `.gitignore` rule.

---

### Task 6: Add a secret-scanning GitHub Actions workflow

**Files:**
- Create: `.github/workflows/secret-scan.yml`
- Test: Validate the YAML syntax (`python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/secret-scan.yml"))'`) and confirm the workflow appears in the GitHub Actions list after merge.

**Interfaces:**
- Runs on every push to `main`, every pull request, and on demand.
- Uses `trufflesecurity/trufflehog@main` with `--only-verified`.
- Fails the job if a verified secret is found.

- [ ] **Step 1: Create `.github/workflows/secret-scan.yml`.**

  ```yaml
  name: Secret Scan

  on:
    push:
      branches: [main]
    pull_request:
    workflow_dispatch:

  jobs:
    trufflehog:
      name: TruffleHog
      runs-on: ubuntu-latest
      steps:
        - name: Checkout
          uses: actions/checkout@v7
          with:
            fetch-depth: 0

        - name: Secret scan
          uses: trufflesecurity/trufflehog@main
          with:
            path: ./
            base: ${{ github.event.repository.default_branch }}
            head: HEAD
            extra_args: --only-verified
  ```

- [ ] **Step 2: Validate YAML and verify the workflow is registered.**
  ```bash
  python3 - <<'PY'
  import yaml
  with open('.github/workflows/secret-scan.yml') as f:
      yaml.safe_load(f)
  print('YAML ok')
  PY
  ```

---

### Task 7: Create `CHANGELOG.md` and bump the package version

**Files:**
- Create: `CHANGELOG.md`
- Modify: `lakefile.lean`
- Test: `grep 'version := v!"0.1.0-beta.1"' lakefile.lean` and `head -n 20 CHANGELOG.md`

**Interfaces:**
- `CHANGELOG.md` at repo root with a `v0.1.0-beta.1` section.
- `lakefile.lean` package version matches `v0.1.0-beta.1`.

- [ ] **Step 1: Update the package version in `lakefile.lean`.**
  Change:
  ```lean
  version := v!"0.1.0"
  ```
  to:
  ```lean
  version := v!"0.1.0-beta.1"
  ```

- [ ] **Step 2: Create `CHANGELOG.md`.**

  ```markdown
  # Changelog

  All notable changes to ProofForge are documented in this file.

  The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
  and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

  ## [0.1.0-beta.1] - 2026-07-10

  ### Breaking / Migration
  - `proof-forge deploy` no longer falls back to the well-known Anvil private key.
    Deployments now require `--private-key KEY` or the `PROOF_FORGE_DEPLOY_PRIVATE_KEY`
    environment variable. Update local Anvil smokes and CI to export the test key.

  ### Added
  - `proof-forge --version` prints the CLI version, Lean toolchain, and git short SHA.
  - Per-command `--help` / `-h` for `build`, `emit`, `check`, and global usage.
  - `.github/workflows/release.yml` builds Linux x86_64, macOS x86_64, and macOS ARM64
    binaries and uploads tarballs + SHA-256 checksums to GitHub Releases.
  - `scripts/ci/install.sh` downloads and installs the matching release tarball.
  - `scripts/i18n/check-links.py` validates internal Markdown links in `docs/zh/`.
  - `.github/workflows/secret-scan.yml` runs TruffleHog with `--only-verified`.
  - `CHANGELOG.md`.

  ### Changed
  - README and AGENTS target roster now advertise only `evm`, `solana-sbpf-asm`, and
    `wasm-near` as beta-ready `contract_source` targets; demoted other targets to
    Counter-MVP / research spikes.
  - Hardened `.gitignore` against key material.

  ### Fixed
  - README "Getting Started" product build command now uses
    `Examples/Product/Counter.lean`.
  - Removed the stale `proof-forge check is not yet implemented` stub in
    `ProofForge/Cli/TargetFirst.lean`.
  ```

- [ ] **Step 3: Verify.**
  ```bash
  grep 'version := v!"0.1.0-beta.1"' lakefile.lean
  head -n 20 CHANGELOG.md
  ```

---

### Task 8: Add a cross-platform release workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Test: Push a tag like `v0.1.0-beta.1-test` and verify the release job produces three tarballs and `checksums.txt`.

**Interfaces:**
- Triggered on tag pushes matching `v*`.
- Builds `proof-forge` on `ubuntu-latest`, `macos-13` (x86_64), and `macos-latest` (ARM64).
- Packages a tarball per platform and uploads the tarballs plus a `checksums.txt` to the GitHub Release.

- [ ] **Step 1: Create `.github/workflows/release.yml`.**

  ```yaml
  name: Release

  on:
    push:
      tags:
        - 'v*'

  permissions:
    contents: write

  jobs:
    build:
      name: Build ${{ matrix.name }}
      runs-on: ${{ matrix.os }}
      strategy:
        matrix:
          include:
            - os: ubuntu-latest
              name: linux-x86_64
            - os: macos-13
              name: macos-x86_64
            - os: macos-latest
              name: macos-arm64
      steps:
        - name: Checkout
          uses: actions/checkout@v4

        - name: Install just
          uses: taiki-e/install-action@v2
          with:
            tool: just@1.48.0

        - name: Install Lean
          run: |
            toolchain="$(cat lean-toolchain)"
            curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -o elan-init.sh
            sh elan-init.sh -y --default-toolchain "$toolchain"
            echo "$HOME/.elan/bin" >> "$GITHUB_PATH"

        - name: Build proof-forge
          run: just build

        - name: Package binary
          shell: bash
          run: |
            version="${GITHUB_REF_NAME}"
            name="proof-forge-${version}-${{ matrix.name }}"
            mkdir -p "dist/${name}"
            cp ".lake/build/bin/proof-forge" "dist/${name}/proof-forge"
            chmod +x "dist/${name}/proof-forge"
            tar -czf "dist/${name}.tar.gz" -C "dist/${name}" proof-forge

        - name: Upload artifact
          uses: actions/upload-artifact@v4
          with:
            name: ${{ matrix.name }}
            path: dist/*.tar.gz
            if-no-files-found: error

    release:
      name: Create GitHub Release
      needs: build
      runs-on: ubuntu-latest
      steps:
        - name: Download artifacts
          uses: actions/download-artifact@v4
          with:
            path: dist
            merge-multiple: true

        - name: Generate checksums
          run: |
            cd dist
            sha256sum *.tar.gz > checksums.txt

        - name: Publish release
          uses: softprops/action-gh-release@v2
          with:
            files: dist/*
  ```

- [ ] **Step 2: Validate YAML.**
  ```bash
  python3 - <<'PY'
  import yaml
  with open('.github/workflows/release.yml') as f:
      yaml.safe_load(f)
  print('YAML ok')
  PY
  ```

- [ ] **Step 3: Test end-to-end on a pre-release tag (optional but recommended).**
  ```bash
  git tag v0.1.0-beta.1-test
  git push origin v0.1.0-beta.1-test
  ```
  Wait for the workflow run, then inspect the created release. It must contain three `proof-forge-v0.1.0-beta.1-test-*.tar.gz` files and one `checksums.txt`.

---

### Task 9: Create `scripts/ci/install.sh`

**Files:**
- Create: `scripts/ci/install.sh`
- Test: `chmod +x scripts/ci/install.sh && bash -n scripts/ci/install.sh`

**Interfaces:**
- Detects OS and architecture.
- Downloads the matching release tarball from `https://github.com/davirain/proof_forge/releases`.
- Extracts to `~/.proof-forge/<version>`.
- Symlinks `~/.local/bin/proof-forge` to the extracted binary.
- Optional: verifies `checksums.txt` when published alongside the release.

- [ ] **Step 1: Create `scripts/ci/install.sh`.**

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  # Install proof-forge from a GitHub Release.
  #
  # Usage:
  #   scripts/ci/install.sh [VERSION]
  #
  # Environment:
  #   PROOF_FORGE_VERSION        version to install (default: latest GitHub release)
  #   PROOF_FORGE_REPO           GitHub owner/repo (default: davirain/proof_forge)
  #   PROOF_FORGE_INSTALL_ROOT   parent directory (default: $HOME/.proof-forge)
  #   PROOF_FORGE_BIN_DIR        symlink directory (default: $HOME/.local/bin)

  VERSION="${1:-${PROOF_FORGE_VERSION:-latest}}"
  REPO="${PROOF_FORGE_REPO:-davirain/proof_forge}"
  INSTALL_ROOT="${PROOF_FORGE_INSTALL_ROOT:-$HOME/.proof-forge}"
  BIN_DIR="${PROOF_FORGE_BIN_DIR:-$HOME/.local/bin}"

  OS="$(uname -s)"
  ARCH="$(uname -m)"

  case "$OS" in
    Linux)
      os_tag=linux
      ;;
    Darwin)
      os_tag=macos
      ;;
    *)
      echo "install.sh: unsupported OS: $OS" >&2
      exit 1
      ;;
  esac

  case "$ARCH" in
    x86_64|amd64)
      arch_tag=x86_64
      ;;
    arm64|aarch64)
      arch_tag=arm64
      ;;
    *)
      echo "install.sh: unsupported architecture: $ARCH" >&2
      exit 1
      ;;
  esac

:

  ```bash
  tarball_name="proof-forge-${VERSION}-${os_tag}-${arch_tag}.tar.gz"

  if [ "$VERSION" = "latest" ]; then
    URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
      | grep "browser_download_url" \
      | grep "proof-forge-.*-${os_tag}-${arch_tag}.tar.gz" \
      | head -n1 \
      | cut -d '"' -f4)"
    if [ -z "$URL" ]; then
      echo "install.sh: could not find latest release asset for ${os_tag}-${arch_tag}" >&2
      exit 1
    fi
    # Latest installs cannot be verified against a pinned checksum.
  else
    URL="https://github.com/${REPO}/releases/download/${VERSION}/${tarball_name}"
  fi

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT

  echo "install.sh: downloading proof-forge ${VERSION} for ${os_tag}-${arch_tag}"
  curl -fsSL -o "$TMPDIR/proof-forge.tar.gz" "$URL"

  # Optional checksum verification for pinned-version installs.
  if [ "$VERSION" != "latest" ]; then
    CHECKSUMS_URL="https://github.com/${REPO}/releases/download/${VERSION}/checksums.txt"
    if curl -fsSL -o "$TMPDIR/checksums.txt" "$CHECKSUMS_URL" 2>/dev/null; then
      (cd "$TMPDIR" && grep "^.*  ${tarball_name}$" checksums.txt | sha256sum -c -)
    fi
  fi

  INSTALL_DIR="$INSTALL_ROOT/$VERSION"
  mkdir -p "$INSTALL_DIR"
  tar -xzf "$TMPDIR/proof-forge.tar.gz" -C "$INSTALL_DIR"

  mkdir -p "$BIN_DIR"
  ln -sf "$INSTALL_DIR/proof-forge" "$BIN_DIR/proof-forge"

  echo "install.sh: installed proof-forge ${VERSION} to ${INSTALL_DIR}/proof-forge"
  echo "install.sh: symlinked ${BIN_DIR}/proof-forge"
  ```

- [ ] **Step 2: Make executable and validate syntax.**
  ```bash
  chmod +x scripts/ci/install.sh
  bash -n scripts/ci/install.sh
  ```

---

### Task 10: Create `scripts/i18n/check-links.py` and wire it into the docs gate

**Files:**
- Create: `scripts/i18n/check-links.py`
- Create: `scripts/i18n/fix-links.py`
- Modify: `scripts/i18n/check-sync.sh`
- Test: `python3 scripts/i18n/check-links.py` and `just docs-check`

**Interfaces:**
- `check-links.py` scans `docs/zh/**/*.md`, resolves relative Markdown links, accepts sibling `.zh.md` targets or correct English fallbacks, and exits non-zero on broken links.
- `fix-links.py` repairs translated docs by pairing links with their English source and recomputing relative paths; it also applies sibling `.zh.md` / docs-root English fallbacks for native Chinese docs.
- `scripts/i18n/check-sync.sh` now runs both the translation-sync check and the link check.

- [ ] **Step 1: Create `scripts/i18n/check-links.py`.**

  ```python
  #!/usr/bin/env python3
  """Validate internal Markdown links in docs/zh/."""
  import re
  import sys
  from pathlib import Path

  DOCS_ZH = Path('docs/zh')
  LINK_RE = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')


  def is_external(link: str) -> bool:
      return not link or link.startswith(('http://', 'https://', 'mailto:', 'javascript:', '//', '#', '/'))


  def resolve(link: str, src: Path) -> Path | None:
      if '#' in link:
          link = link.split('#', 1)[0]
      if not link or is_external(link):
          return None
      return (src.parent / link).resolve()


  def check_file(src: Path, broken: list[tuple[Path, str, Path]]) -> None:
      for _label, link in LINK_RE.findall(src.read_text(encoding='utf-8')):
          target = resolve(link, src)
          if target is None:
              continue
          if target.exists():
              continue
          if link.endswith('.md') and not link.endswith('.zh.md'):
              zh = target.with_name(target.name[:-3] + '.zh.md')
              if zh.exists():
                  continue
          broken.append((src, link, target))


  def main() -> int:
      if not DOCS_ZH.is_dir():
          print(f'check-links: {DOCS_ZH} not found', file=sys.stderr)
          return 1
      broken: list[tuple[Path, str, Path]] = []
      for src in sorted(DOCS_ZH.rglob('*.md')):
          check_file(src, broken)
      if broken:
          print(f'check-links: {len(broken)} broken link(s):', file=sys.stderr)
          for src, link, target in broken:
              print(f'  {src}: [{link}] -> {target}', file=sys.stderr)
          return 1
      print('check-links: ok')
      return 0


  if __name__ == '__main__':
      sys.exit(main())
  ```

- [ ] **Step 2: Create `scripts/i18n/fix-links.py`.**

  ```python
  #!/usr/bin/env python3
  """Repair internal Markdown links in docs/zh/ translations.

  For translated files, links are paired by occurrence order with the English
  source and recomputed relative to the Chinese file. For native Chinese docs,
  simple sibling .zh.md / docs-root English fallbacks are applied.
  """
  import importlib.util
  import os
  import re
  import sys
  from pathlib import Path

  REPO_ROOT = Path(__file__).resolve().parent.parent.parent
  DOCS_ZH = REPO_ROOT / 'docs/zh'
  LINK_RE = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')

  spec = importlib.util.spec_from_file_location(
      'translate_docs', REPO_ROOT / 'scripts' / 'translate-docs.py'
  )
  translate_docs = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(translate_docs)
  ZH_TO_EN = {zh: en for en, zh in translate_docs.DOC_MAP.items()}
  EN_TO_ZH = {en: zh for en, zh in translate_docs.DOC_MAP.items()}


  def is_external(link: str) -> bool:
      return not link or link.startswith(('http://', 'https://', 'mailto:', 'javascript:', '//', '#', '/'))


  def split_link(link: str) -> tuple[str, str]:
      if '#' in link:
          parts = link.split('#', 1)
          return parts[0], parts[1]
      return link, ''


  def choose_target(en_target: Path) -> Path:
      rel = str(en_target.relative_to(REPO_ROOT))
      if rel in EN_TO_ZH:
          zh = REPO_ROOT / EN_TO_ZH[rel]
          if zh.exists():
              return zh
      if en_target.suffix == '.md':
          zh = en_target.with_name(en_target.name[:-3] + '.zh.md')
          if zh.exists():
              return zh
      return en_target


  def rewrite_translated(zh_path: Path, en_path: Path) -> str | None:
      zh_text = zh_path.read_text(encoding='utf-8')
      en_text = en_path.read_text(encoding='utf-8')
      en_links = list(LINK_RE.finditer(en_text))
      zh_links = list(LINK_RE.finditer(zh_text))
      if len(en_links) != len(zh_links):
          print(
              f'fix-links: link count mismatch in {zh_path}; skipping automatic repair',
              file=sys.stderr,
          )
          return None
      it = iter(en_links)
      changed = False

      def repl(m: re.Match) -> str:
          nonlocal changed
          em = next(it)
          label, link = m.group(1), m.group(2)
          bare, fragment = split_link(link)
          if not bare or is_external(bare):
              return m.group(0)
          en_bare, _ = split_link(em.group(2))
          if not en_bare or is_external(en_bare):
              return m.group(0)
          intended = (en_path.parent / en_bare).resolve()
          if not intended.exists():
              return m.group(0)
          target = choose_target(intended)
          suffix = f'#{fragment}' if fragment else ''
          new_link = os.path.relpath(target, zh_path.parent).replace('\\', '/') + suffix
          if new_link != link:
              changed = True
              return f'[{label}]({new_link})'
          return m.group(0)

      new_text = LINK_RE.sub(repl, zh_text)
      return new_text if changed else None


  def rewrite_native(zh_path: Path) -> str | None:
      zh_text = zh_path.read_text(encoding='utf-8')
      changed = False

      def repl(m: re.Match) -> str:
          nonlocal changed
          label, link = m.group(1), m.group(2)
          bare, fragment = split_link(link)
          if not bare or is_external(bare):
              return m.group(0)
          cur = (zh_path.parent / bare).resolve()
          if cur.exists():
              return m.group(0)
          target = None
          if cur.suffix == '.md':
              zh_sib = cur.with_name(cur.name[:-3] + '.zh.md')
              if zh_sib.exists():
                  target = zh_sib
          if target is None:
              candidates = [REPO_ROOT / 'docs' / bare]
              if bare.endswith('.md'):
                  candidates.append(REPO_ROOT / 'docs' / (bare[:-3] + '.zh.md'))
              for cand in candidates:
                  if cand.exists():
                      target = cand
                      break
          if target is None:
              return m.group(0)
          suffix = f'#{fragment}' if fragment else ''
          new_link = os.path.relpath(target, zh_path.parent).replace('\\', '/') + suffix
          if new_link != link:
              changed = True
              return f'[{label}]({new_link})'
          return m.group(0)

      new_text = LINK_RE.sub(repl, zh_text)
      return new_text if changed else None


  def main() -> int:
      modified = 0
      skipped = 0
      for zh_path in sorted(DOCS_ZH.rglob('*.md')):
          zh_rel = str(zh_path.relative_to(REPO_ROOT))
          en_rel = ZH_TO_EN.get(zh_rel)
          if en_rel:
              en_path = REPO_ROOT / en_rel
              if not en_path.exists():
                  skipped += 1
                  continue
              new_text = rewrite_translated(zh_path, en_path)
          else:
              new_text = rewrite_native(zh_path)
          if new_text is not None:
              zh_path.write_text(new_text, encoding='utf-8')
              print(f'fix-links: {zh_rel}')
              modified += 1
      print(f'fix-links: {modified} file(s) modified, {skipped} skipped')
      return 0


  if __name__ == '__main__':
      sys.exit(main())
  ```

- [ ] **Step 3: Wire the link check into `scripts/i18n/check-sync.sh`.**
  Change the script to:

  ```sh
  #!/bin/sh
  set -e

  REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

  python3 "$REPO_ROOT/scripts/translate-docs.py" --check
  python3 "$REPO_ROOT/scripts/i18n/check-links.py"
  ```

- [ ] **Step 4: Repair links and verify the gate.**
  ```bash
  chmod +x scripts/i18n/check-links.py scripts/i18n/fix-links.py
  python3 scripts/i18n/fix-links.py
  python3 scripts/i18n/check-links.py
  just docs-check
  ```
  If `check-links.py` still reports broken links after `fix-links.py`, manually repair the remaining entries (they are typically native Chinese docs or links to files outside `docs/`) and rerun until the gate passes.

---

### Task 11: Add first-run CI smokes to `.github/workflows/ci.yml`

**Files:**
- Modify: `.github/workflows/ci.yml`
- Test: The `product` job in CI must pass with the new steps.

**Interfaces:**
- New CI steps run `just portable-init-smoke`, `just portable-check-smoke`, `just portable-evm-client`, and the corrected literal README product build command.

- [ ] **Step 1: Insert first-run smoke steps into the `product` job.**
  In `.github/workflows/ci.yml`, after the existing `Product multi-target gate` step in the `product` job, add:

  ```yaml
      - name: First-run portable init smoke
        run: just portable-init-smoke

      - name: First-run portable check smoke
        run: just portable-check-smoke

      - name: First-run portable EVM client smoke
        run: just portable-evm-client

      - name: Literal README product build command
        run: |
          lake env proof-forge build --target evm --root . \
            -o build/evm/Counter.bin Examples/Product/Counter.lean
  ```

- [ ] **Step 2: Validate CI YAML and run the new steps locally.**
  ```bash
  python3 - <<'PY'
  import yaml
  with open('.github/workflows/ci.yml') as f:
      yaml.safe_load(f)
  print('YAML ok')
  PY
  just portable-init-smoke
  just portable-check-smoke
  just portable-evm-client
  lake env proof-forge build --target evm --root . \
    -o build/evm/Counter.bin Examples/Product/Counter.lean
  ```

---

### Task 12: Update `README.md` and `AGENTS.md` with an honest target support matrix

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Test: `just docs-check` and visual inspection of the rendered tables.

**Interfaces:**
- Public docs now advertise only `evm`, `solana-sbpf-asm`, and `wasm-near` as beta-ready `contract_source` targets.
- Other targets are listed in a separate "Counter-MVP / research spikes" table.
- The README onboarding command uses `Examples/Product/Counter.lean` (module auto-resolved).

- [ ] **Step 1: Fix the README onboarding command.**
  In `README.md`, replace:

  ```markdown
  lake env proof-forge build --target evm --root . --module Counter \
    -o build/evm/Counter.bin Examples/Backend/Evm/Contracts/Counter.lean
  ```

  with:

  ```markdown
  lake env proof-forge build --target evm --root . \
    -o build/evm/Counter.bin Examples/Product/Counter.lean
  ```

- [ ] **Step 2: Replace the README `Backend Status` narrative table with an honest roster.**
  Replace the paragraph beginning with "The machine-readable support matrix..." and the large table that follows it with the following content (keep the generated-backend-status note):

  ```markdown
  The machine-readable support matrix (maturity, input modes, commands, output
  stages, validation level) is generated from `proof-forge --list-targets --json`
  into [`docs/generated/backend-status.md`](docs/generated/backend-status.md)
  (`just target-support` / `just backend-status-gen`). The narrative table below
  is the human overview; the generated table remains the PF-P1-02 contract.

  ### Beta-ready `contract_source` targets

  These three targets compile real `ProofForge.Contract.Source` contracts,
  produce a canonical SDK layout, and are required to pass `just product`:

  | Target id | Pipeline | Stage | Local validation |
  |---|---|---|---|
  | `evm` | Lean / portable IR → Yul → `solc` → bytecode | Beta-ready | golden Yul, diagnostics, Foundry runtime smoke, Anvil deploy, dynamic constructor Anvil, constructor body, deploy gas-limit/price/priority flags, stdlib coverage |
  | `solana-sbpf-asm` | portable IR → sBPF assembly → `sbpf` → ELF | Beta-ready | Mollusk tests, Surfpool/Rust live smokes, Pinocchio equivalence gates, indexed events, CPI gates, Token-2022 extensions, map storage |
  | `wasm-near` | portable IR → `EmitWat` (Wasm AST → WAT) → `wat2wasm` | Beta-ready | diagnostics, IR coverage manifests, formal trace obligations, target-first smoke, offline host smoke, NEP-141 FT stdlib, aggregate ABI params |

  ### Counter-MVP / research spikes (not beta-ready)

  The following targets are implemented on `main` but are intentionally limited
  to Counter fixtures, host-adapter spikes, or research prototypes. They are **not**
  advertised as public-beta `contract_source` compilers:

  | Target id | Status | Why it is demoted |
  |---|---|---|
  | `wasm-stellar-soroban` | Counter MVP (PF-P3-02) | Auth still spike-always; Stellar CLI/TTL remain follow-on. |
  | `wasm-cosmwasm` | Counter MVP (PF-P3-02) | `execute_msg` is a WasmMsg-shaped stub; full crosscall not wired. |
  | `move-aptos` | Counter spike (PF-P3-02) | Product source fail-closed; needs `aptos` CLI for validation. |
  | `move-sui` | Counter MVP | Counter package layout only; beyond-Counter planning is ongoing. |
  | `psy-dpn` | Research spike (restricted subset) | Dargo-backed execution only; not a general compiler. |
  | `aleo-leo` | Counter MVP / research (Road 1+) | Generic Leo sourcegen + ALU ops; broader shape coverage in progress. |
  | `wasm-cloudflare-workers` | Counter TS spike (PF-P3-02) | TypeScript Worker output; not a Wasm binary target. |

  **CLI-only verification target:** `quint` is accepted by `proof-forge emit --target quint`
  for formal/model-checking fixtures but is **not** in `Target.knownIds` /
  `--list-targets` (verification lane, not a product host).
  ```

- [ ] **Step 3: Update `AGENTS.md` to match the honest roster.**
  - Replace the opening paragraph that lists all ten targets with:

    ```markdown
    ProofForge is a Lean 4 compiler/CLI (`proof-forge`) that lowers Lean smart-contract
    sources to portable IR and target artifacts. For the public beta, only three targets
    are advertised as `contract_source` compilers: `evm`, `solana-sbpf-asm`, and
    `wasm-near`. The remaining registry entries (`wasm-cosmwasm`, `wasm-stellar-soroban`,
    `move-aptos`, `move-sui`, `psy-dpn`, `aleo-leo`, `wasm-cloudflare-workers`) are
    Counter-MVP/fixture/research spikes on `main`; the formal-verification target `quint`
    is CLI-only and not in `--list-targets`. See README "Backend Status" for the full
    stage table.
    ```

  - Replace the "Registry vs CLI-only targets" table with:

    ```markdown
    ### Registry vs CLI-only targets

    | Surface | Targets |
    |---------|---------|
    | Beta-ready `contract_source` compilers | `evm`, `solana-sbpf-asm`, `wasm-near` |
    | `proof-forge --list-targets` / `ProofForge.Target.knownIds` | `evm`, `solana-sbpf-asm`, `wasm-near`, `wasm-cosmwasm`, `wasm-cloudflare-workers`, `wasm-stellar-soroban`, `move-aptos`, `move-sui`, `psy-dpn`, `aleo-leo` |
    | `proof-forge emit --target …` (fixture whitelist) | above plus `quint` (verification; CLI-only). `wasm-stellar-soroban` uses EmitWat + `HostBridge.soroban` (not a separate codegen core). |
    ```

- [ ] **Step 4: Verify docs.**
  ```bash
  just docs-check
  ```

---

## Self-Review

### Spec coverage
- **Task 1** covers `--version` output (version, Lean toolchain, git SHA).
- **Task 2** covers `--help` for global, `build`, `emit`, and `check`.
- **Task 3** removes the stale `check` stub.
- **Task 4** removes the hardcoded Anvil key, adds env-var fallback, and updates deploy smokes.
- **Task 5** adds `.gitignore` patterns for key material.
- **Task 6** adds TruffleHog secret scanning.
- **Task 7** adds `CHANGELOG.md` and aligns `lakefile.lean` version.
- **Task 8** adds a cross-platform release workflow.
- **Task 9** adds an OS/arch-aware install script.
- **Task 10** adds the Chinese link checker, a repair script, and wires it into `docs-check`.
- **Task 11** adds first-run CI smokes and the corrected README build command.
- **Task 12** updates `README.md` and `AGENTS.md` with the honest beta-ready target matrix.

### Placeholder scan
- No `TODO`, `FIXME`, or hand-wavy placeholders remain in the planned code.
- The only non-mechanical step is the tail end of Task 10: if `fix-links.py` leaves any broken links, the implementer must manually repair them before the gate passes. The acceptance criterion is explicit: `python3 scripts/i18n/check-links.py` exits `0`.

### Type consistency
- Lean code uses `IO UInt32` for CLI entry points, `IO String` for key resolution, and `Except String` for pure parsers.
- Bash scripts use `set -euo pipefail` and explicit variable defaults.
- Python scripts use type hints compatible with Python 3.10+ and return explicit exit codes.

---

## Execution Handoff

**Option A — Subagent-Driven Development:**
Hand off this plan to a coding subagent using `superpowers:subagent-driven-development`. Instruct the subagent to implement the tasks in order, checking `just product` after every task, and to stop for human review if any task fails its verification commands.

**Option B — Inline Execution:**
If executing inline, work task-by-task in the order listed. After each task run the verification commands given in that task, and run `just product` before moving on. Treat Task 10 as two phases: run `fix-links.py`, then triage any remaining broken links reported by `check-links.py` before enabling the gate.
