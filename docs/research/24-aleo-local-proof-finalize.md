---
id: RPT-024
title: ALEO-R0 Leo 4.0.2 local package/build/execute/proof/finalize empirical freeze
status: draft
owner: engineering
updated: 2026-08-07
normative: false
---

# ALEO-R0: Leo 4.0.2 local toolchain — empirical command/artifact freeze

## Question

What exact Leo 4.0.2 package layout, CLI commands, and on-disk artifacts can
ProofForge freeze **today** for Aleo beyond the existing compile-only acceptance
gate (`leo build --offline`), and which post-compile stages (run / execute /
synthesize / deploy / query / finalize / verify) are offline-reachable with the
**locked** tool only?

## Method

- Host: **darwin-arm64** worktree spike, 2026-08-07 (facts below are
  Darwin-arm64 empirical; not multi-host hermetic claims).
- Tool: locked Leo only —
  `$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64/leo`
  `leo 4.0.2 (13448848d9 HEAD) features=[noconfig]`
  executable SHA-256
  `da83089b4cb43a33a846a3e674c24cf54b66da5d14cd2bcddc2977a3b1856397`
  matches `toolchains.lock.json` tool id `leo`; `requiredByProfiles` now binds
  default source `aleo-leo-4.0.2-u64-v1` plus opt-in compile
  `aleo-leo-4.0.2-u64-compile-v1`.
- **No** PATH fallback for the acceptance path under test; **no** Tool Lock
  install of snarkVM/snarkOS/SDK (none are present in either platform lock or
  the materialize root).
- Isolated temporary `HOME` with empty `.aleo/`; spike also **unsets** ambient
  `PRIVATE_KEY` / `VIEW_KEY` / `NETWORK` / `ENDPOINT` / related selectors so
  the probe does not inherit user wallet or explorer config.
- Packages: (A) `leo new helloworld` template; (B) product-emission-shaped
  Counter state transitions (`fn … -> Final { return final { … }; }` + mappings)
  plus a **spike-only** plain `get` function used to exercise Leo compilation.
  Product bare views are omitted from `.aleo` and exist only in the
  query-contract sidecar, as pinned by `EmitIRV1.lean` / `Aleo.lean`.
- Dual `leo build --offline --disable-update-check` inventories over the
  **exact three content-bearing outputs**
  `build/main.aleo`, `build/abi.json`, `build/program.json`
  (size + SHA-256 + absolute-path string scan; inventory count must be 3;
  empty/partial inventory fail closed). Other optional leaves such as
  `build/imports/*` after `leo test` are **out of** this determinism contract.
- Offline-oriented probes of run / execute / synthesize / deploy / query /
  test / abi / clean / account; dummy endpoint `http://127.0.0.1:9` when a
  network flag is required, **without** broadcast and without intentional
  testnet/mainnet use as product acceptance.
- Repro script: `scripts/aleo_local_toolchain_spike.sh` prints `SPIKE-PASS` on
  success, `SPIKE-BLOCKED` when locked leo is missing (exit 3), and
  `INFO-BLOCKED` for post-compile stage limits (informational only).

This report is **research evidence**, not formal qualification. ALEO-I4 subsequently
productized only the frozen compile stage as the opt-in
`aleo-leo-4.0.2-u64-compile-v1` profile: locked offline build, exactly three
content-bound finalized extras, `deployable=false`. All post-compile blockers and
non-claims below remain unchanged.

## Package layout (Leo 4.0.2)

Minimum legal program package (matches acceptance helper and `leo new`):

```text
<pkg>/
  program.json
  src/main.leo
```

`program.json` fields observed (from `leo new` and acceptance):

```json
{
  "program": "<id>.aleo",
  "version": "0.1.0",
  "description": "",
  "license": "MIT",
  "leo": "4.0.2",
  "dependencies": null,
  "dev_dependencies": null
}
```

- `program` must equal the `program <id>.aleo { … }` declaration.
- Program id must **not** contain the substring `aleo` (Leo ENV03711001; also
  enforced in product emitter).
- Optional `tests/*.leo` is created by `leo new` and used by `leo test`.
- Leo 4 keywords observed by parser diagnostics on illegal surface:
  `}`, `@`, `record`, `struct`, `fn`, `final`, `const`, `mapping`, `storage`,
  `script`, `interface`. **`async` is rejected** at program-member level
  (`EPAR0370005`). Product Final surface is `fn name(...) -> Final { return final { ... }; }`,
  not Leo 3-style `async transition` / `async function`.

### Product-shaped Counter (compiled successfully)

Relevant source shape (abbreviated):

```text
program counter.aleo {
    @noupgrade
    constructor() {}
    mapping pf_state_0: u8 => u64;
    mapping initialized: u8 => bool;
    fn initialize(public p0: u64) -> Final {
        return final { ... mapping get_or_use / set / assert ... };
    }
    fn increment(public p0: u64) -> Final { return final { ... }; }
    // Spike-only plain fn; product bare `view get` is sidecar-only and omitted.
    fn get() -> u64 { return 0u64; }
}
```

## CLI surface (exact, from locked `leo --help` / subcommand help)

Top-level commands:

| Command | Role (help text) |
|---|---|
| `account` | Create account; **sign and verify messages** (not proof verify) |
| `new` | Create package directory |
| `run` / `r` | Run program with inputs (local VM interpretation) |
| `test` / `t` | Test Leo program; optional `--prove` |
| `execute` | Execute with inputs; optional `--skip-execute-proof`, `--broadcast`, `--save` |
| `fmt` | Format |
| `deploy` | Deploy program; optional `--skip-deploy-certificate`, `--broadcast`, `--save` |
| `devnet` | Local devnet (**requires external `snarkOS` binary**; optional `--install`) |
| `devnode` | Local devnode start/advance |
| `query` | Query **live** network data |
| `build` / `b` | Compile package to Aleo instructions |
| `abi` | Generate ABI from `.aleo` bytecode |
| `add` / `remove` | Dependency management |
| `clean` | Clean build/outputs |
| `synthesize` | Synthesize individual proving/verifying keys |
| `update` / `upgrade` | CLI update / on-chain upgrade |

**Not present as top-level commands:** `proof`, `verify` (proof), `finalize`.

- **Finalize** is a **language/IR** concept (`return final { … }`, Aleo
  instructions `async …` + `finalize …`), not a Leo subcommand.
- **Verify** under `leo account verify` is **message signature** verify, not
  transaction/proof verification.

Global flags of interest: `--disable-update-check`, `--path`, `--home`,
`-d`/`-q`, `--json-output`.

Build-specific offline flags: `--offline`, `--no-cache`, `--no-local`,
AST snapshot flags, `--build-tests`, optional network/env overrides
(`--network`, `--endpoint`, `--private-key`, …). Even with `--offline`,
build **warns** and defaults:

```text
⚠️ No network specified, defaulting to 'testnet'.
⚠️ No endpoint specified, defaulting to 'https://api.explorer.provable.com/v1'.
```

Those defaults are **advertised** during offline build; offline build itself
did not require a reachable endpoint for the packages tested.

## Empirically reachable stages (locked Leo only)

### 1) `leo build --offline --disable-update-check` — **PASS** (compile-only)

Exact command:

```bash
"$LEO" build --offline --disable-update-check --path "$PKG"
```

Success markers (also used by `scripts/aleo_acceptance.sh` /
`AleoAcceptance.lean`):

- stdout contains `Compiled` and/or `into Aleo instructions`
- exit code `0`

**Content-bearing compile outputs** under package (determinism contract;
helloworld / counter):

| Path | Role | helloworld size / SHA-256 | counter size / SHA-256 |
|---|---|---|---|
| `build/main.aleo` | Aleo instructions | 193 / `413dc59e1531aecd41549dd1ba31c186863c8ef21e6f2bb8ebe0ba387860e911` | 872 / `7f80d8669af2c2d80ad44bcb063a10e13a1b7ab17736a78f24063ba08052cfea` |
| `build/abi.json` | ABI JSON | 873 / `848f1cd7a37b2e83a961f8117910d23405acfef5c4061389ca419722ca4f320f` | 1625 / `04163c5ce358f18227c0498c852fb0b549e6eafcb7cfbd873f47475b7f7c3b09` |
| `build/program.json` | Build-side program metadata | 165 / `2569675a569b56fc02d7c10778ccae70c318c0dc30b231ee822b9b9f52750048` | 162 / `1009ccb4f20775e23109cb51ff48b3da74495e281d9b63538521145a9c3cd92d` |

Also observed after tests (not part of the three-file digests contract):
`build/imports/*.aleo` (+ `.abi.json`) when tests import the main program.

Program checksums printed by compiler (stdout; not separate files):

- helloworld:
  `[96u8, 221u8, 32u8, 227u8, 44u8, 46u8, 93u8, 242u8, 17u8, 214u8, 17u8, 134u8, 170u8, 250u8, 59u8, 72u8, 48u8, 182u8, 210u8, 153u8, 135u8, 38u8, 214u8, 209u8, 12u8, 135u8, 252u8, 74u8, 132u8, 140u8, 123u8, 209u8]`
- counter:
  `[22u8, 157u8, 119u8, 235u8, 132u8, 157u8, 199u8, 189u8, 244u8, 204u8, 14u8, 215u8, 197u8, 163u8, 75u8, 115u8, 53u8, 186u8, 85u8, 143u8, 193u8, 78u8, 69u8, 85u8, 64u8, 90u8, 243u8, 132u8, 219u8, 107u8, 140u8, 227u8]`

#### Determinism (three content-bearing outputs only)

- **Two consecutive builds** on the same package tree: **byte-identical**
  digests for `build/main.aleo`, `build/abi.json`, `build/program.json`
  (helloworld and counter). Inventory exact count **3**; missing any required
  file fails closed (empty/partial inventory must not pass).
- **Two independent package trees** with identical sources: same three files
  byte-identical across trees.
- mtime may advance on rewrite (observed on counter rebuild) while SHA stays
  equal — **content deterministic, timestamps not a product signal**.
- Absolute-path scan (`/Users/`, `/private/var/`, `/var/folders/`) over those
  **three** files only: **no hits** (spike parses canonical inventory lines;
  does not claim a full recursive `build/**` walk).
- Note: failed parses may surface absolute paths in **diagnostics** pointing
  at source files; that is stderr UX, not artifact content.
- Host scope: dual-build digests above are **darwin-arm64** empirical with
  locked leo 4.0.2; not claimed as multi-host hermetic.

#### Compiled IR shape (excerpt)

helloworld `build/main.aleo`:

```text
program helloworld.aleo;
function main:
    input r0 as u32.public;
    input r1 as u32.private;
    add r0 r1 into r2;
    output r2 as u32.private;
constructor:
    assert.eq edition 0u16;
```

counter Final functions lower to `async <fn> …` + `finalize <fn>:` blocks with
`get.or_use` / `set` on public mappings (boolean spelled `boolean` in IR, not
Leo source keyword `bool`).

### 2) `leo run --offline` — **PASS** (local interpret; not proof)

```bash
"$LEO" run --offline --disable-update-check --path "$PKG" main 1u32 2u32
# helloworld → Output • 3u32  (exit 0)
"$LEO" run --offline --disable-update-check --network testnet --path "$CT" initialize 5u64
# counter Final → prints future/payload object; exit 0
```

- Defaults private key to the **public well-known local-dev key** when unset
  (`APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH` — Leo help
  text; never production).
- Loads programs into an embedded VM (“Adding programs to the VM … local”).
- **Not** a proof, not a transaction, not on-chain finalization.

### 3) `leo test --offline` — **PASS** (default; interpret)

```bash
"$LEO" test --offline --disable-update-check --path "$HW"
# 1 / 1 tests passed (template test_main_fails)
```

`--prove` also returned exit 0 for the template in this spike (still local
ledger load; **not** claimed as product proof maturity).

### 4) `leo abi` — **PASS**

```bash
"$LEO" abi --disable-update-check --path "$HW" "$HW/build/main.aleo"
# JSON ABI to stdout
```

### 5) `leo clean` — **PASS**

Removes package `build/` and `outputs/` directories.

### 6) `leo account new` — **PASS** (local keygen)

Prints Private Key / View Key / Address. Spike used isolated HOME only; **do
not** commit keys. Product scripts must not read secrets/wallets.

### 7) `leo synthesize` — **PARTIAL / offline-unsafe without pre-seeded CRS**

```bash
"$LEO" synthesize --local --offline --disable-update-check \
  --network testnet --endpoint http://127.0.0.1:9 \
  --path "$HW" --save "$OUT" helloworld.aleo
```

Observed:

- Requires explicit `--network` (else `ECLI0377045`).
- With CRS **absent** under `$HOME/.aleo/resources/`, first run **downloaded**
  `https://parameters.provable.com/mainnet/powers-of-beta-16.usrs.84631bc`
  **despite `--offline`**, into
  `$HOME/.aleo/resources/powers-of-beta-16.usrs.84631bc`
  (size `3145736`, SHA-256
  `84631bc11e1a6db99db085a8de586014e7dd10e97b42cbd766c105dea014bbd1`).
  **Therefore `--offline` is not a hermetic network barrier for CRS.**
- Second run with CRS present synthesized without re-download.
- Saved keys (filenames include a numeric suffix; observed as epoch-like):

| Artifact | size | SHA-256 |
|---|---:|---|
| `testnet.helloworld.aleo.main.local.prover.<ts>` | 29434226 | `42406ba09470b680e8dcaa0273b2c0099629345ade5aecb64c7d0dbdbbd69ef4` |
| `testnet.helloworld.aleo.main.local.verifier.<ts>` | 673 | `fa53bc44917db466328b96fafb12bf49ee6e6bc9c99181b899b889b5af53b828` |
| `testnet.helloworld.aleo.main.local.metadata.<ts>` | 233 | `7205547e4ed233ff933b6c764ed699bd5183c212bb689bf94f19f3bf53d3f299` |

Metadata JSON:

```json
{
  "prover_checksum": "42406ba09470b680e8dcaa0273b2c0099629345ade5aecb64c7d0dbdbbd69ef4",
  "prover_size": 29434226,
  "verifier_checksum": "fa53bc44917db466328b96fafb12bf49ee6e6bc9c99181b899b889b5af53b828",
  "verifier_size": 673
}
```

Circuit info (stdout): Public Inputs 16; Variables 12940; Constraints 12927;
Circuit ID `8fbf925ffb3b2e8611ab31eab62753a38206f82fa74762238a18cac2c8e8de2f`.

**Filename non-determinism:** the trailing numeric component changes per
synthesize invocation. Content SHA for prover/verifier was recorded once; dual
synthesize content determinism was **not** frozen in this spike.

### 8) `leo execute` — **BLOCKED offline (needs live stateRoot/block endpoint)**

```bash
# Without --network / --endpoint:
Error [ECLI0377045]: Please provide the `--network` or set the `NETWORK` environment variable.
# With network but no endpoint:
Error [ECLI0377045]: Please provide the `--endpoint` or set the `ENDPOINT` environment variable.
# With --offline --network testnet --endpoint http://127.0.0.1:9
# without --consensus-version: retries endpoint for consensus version, then fails.
# With --consensus-version 8 --skip-execute-proof:
#   progresses through fee summary, then:
Failed to fetch from http://127.0.0.1:9/testnet/stateRoot/latest
# With proof enabled (no --skip-execute-proof):
Failed to fetch from http://127.0.0.1:9/testnet/block/height/latest
```

Exit codes observed: `213` (CLI config/consensus), `248` (network fetch fail
after partial plan). No transaction file written under `--save` on failure.

**Conclusion:** transaction materialization (even without broadcast and even
with `--skip-execute-proof`) still queries a REST endpoint for chain state.
There is **no** pure offline execute path with locked Leo alone.

### 9) `leo deploy` — **BLOCKED offline (same consensus/endpoint dependency)**

Same pattern as execute: requires `--network` + `--endpoint` (or env), then
fails consensus-version discovery against a dead endpoint, or would need a live
node. `--skip-deploy-certificate` does not remove the network dependency.
`--print` / `--save` without `--broadcast` still did not complete offline.

### 10) `leo query` — **BLOCKED without network**

```bash
"$LEO" query --endpoint http://127.0.0.1:1 --network testnet --network-retries 0 block 0
# Error [EUTL03710016]: Failed to retrieve ... Connection refused
```

Subcommands: `block`, `transaction`, `program`, `stateroot`, `committee`,
`mempool`, `peers`. All are live-network queries.

### 11) `leo devnet` / `devnode` — **BLOCKED (snarkOS not pinned)**

`leo devnet --help` documents:

- `--snarkos <PATH>` — path to snarkOS binary
- `--install` — build/install snarkOS (network/crates.io)
- `--snarkos-version` defaults to **latest** on crates.io if unset

Materialize root and both Tool Lock files contain **leo only** for Aleo — **no**
`snarkos`, **no** `snarkvm` asset. Host `which snarkvm snarkos` empty. Spike
**did not** download or install snarkOS.

Leo binary strings show it is **built against snarkVM crates 4.6.1**
(embedded libraries), but that is **not** a standalone snarkVM/snarkOS CLI pin.

### 12) Proof verify / public finalize — **NOT REACHABLE offline**

- No Leo subcommand that verifies a Varuna/execution proof artifact.
- On-chain finalize is implied by deploy/execute + network consensus; not a
  local `leo finalize` step.
- `leo account verify` is message signatures only.

## Maturity ceiling (honest)

| Layer | Status after this spike |
|---|---|
| Product Plan/IR/Leo source emit | Present; default source profile remains zero-tool |
| Locked Leo 4.0.2 compile-only | **Productized opt-in** by ALEO-I4; dual-build byte-stable three content-bearing outputs (`main.aleo` / `abi.json` / `program.json`) on darwin-arm64, published under stable finalized-extra names |
| Local interpret (`run` / default `test`) | **Works offline** with locked Leo |
| Key synthesis | **Works when CRS present**; CRS **auto-download is network** even with `--offline` |
| Offline transaction prove/execute/deploy | **Blocked** — needs REST stateRoot/block (or snarkOS node) |
| Query / broadcast / testnet/mainnet | Out of scope / blocked offline |
| snarkOS local ledger + finalize | **Blocked** — tool not pinned |
| Product maturity label | **Source emission + engineering locked compile finalization**; still non-deployable |
| Formal / hermetic Stage-0 | **Not** claimed |

Do **not** promote Aleo to proof/runtime maturity on this evidence alone.

## Blockers (freeze list)

1. **No pinned snarkOS** (and no snarkVM standalone CLI) in Tool Lock / materialize
   root → no local ledger, no honest local deploy/execute finalization loop.
2. **`leo execute` / `leo deploy` require endpoint state** (`stateRoot/latest` or
   `block/height/latest`) even with `--offline` and without `--broadcast`.
3. **`--offline` does not prevent CRS parameter download** on `leo synthesize`
   when `$HOME/.aleo/resources/powers-of-beta-16.usrs.*` is missing.
4. **CRS / proving params not in Tool Lock** — size ~3 MiB CRS + ~29 MiB prover
   key for trivial helloworld; product gate would need exact digests + offline
   seed policy.
5. **Synthesize key filenames carry a changing numeric suffix** — path identity
   is not stable across runs without renaming policy.
6. **No proof-verify CLI** in Leo 4.0.2 top-level surface.
7. **Default network/endpoint warnings** even in offline build — any future
   gate must pin `NETWORK`/`ENDPOINT`/`--consensus-version` explicitly and fail
   closed if network is touched (product policy TBD).

## Recommended product posture (research only)

| Gate | Recommend |
|---|---|
| Keep `AleoAcceptance` / `leo build --offline` | **Yes** — only frozen offline product-grade stage |
| Dual-build content hash pin (optional hardening) | Feasible: pin the three content-bearing outputs (`main.aleo` / `abi.json` / `program.json`) for fixtures |
| Local `leo run` smoke | Optional engineering extra; not proof maturity |
| Promote prove/verify/deploy maturity | **No** until snarkOS (or equivalent) is Tool-Locked, CRS seeded offline, execute/deploy complete without live explorer, and proof verify contract exists |
| Download snarkOS/SDK in CI | **Out of scope** for this wave; record as blocker only |

## Exact command cheat-sheet (observed)

```bash
LEO="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64/leo"  # or $PROOF_FORGE_TOOL_ROOT/leo

"$LEO" --version
"$LEO" --help
"$LEO" build --help
"$LEO" new helloworld --disable-update-check
"$LEO" build --offline --disable-update-check --path "$PKG"
"$LEO" run --offline --disable-update-check --path "$PKG" main 1u32 2u32
"$LEO" test --offline --disable-update-check --path "$PKG"
"$LEO" abi --disable-update-check --path "$PKG" "$PKG/build/main.aleo"
"$LEO" clean --disable-update-check --path "$PKG"

# Partial / blocked offline without extra pins:
"$LEO" synthesize --local --offline --disable-update-check \
  --network testnet --endpoint http://127.0.0.1:9 \
  --path "$PKG" --save "$OUT" helloworld.aleo
# ↑ may download CRS despite --offline if resources missing

"$LEO" execute --offline --disable-update-check \
  --network testnet --endpoint http://127.0.0.1:9 \
  --consensus-version 8 --network-retries 0 \
  --skip-execute-proof --path "$PKG" --private-key "$KEY" --print --yes main …
# ↑ fails: Failed to fetch …/stateRoot/latest

"$LEO" query --endpoint http://127.0.0.1:1 --network testnet --network-retries 0 block 0
# ↑ connection refused
```

## Explicit non-claims

- Not formal D2/D3/D4/D5 or TST-ALEO-*.
- Not hermetic Stage-0 or release qualification.
- Not mainnet/testnet deployment evidence.
- Not a claim that `leo run` or `leo synthesize` equals product proof maturity.
- Does not expand accepted PRD Phase-1 target scope.
- Does not authorize network installs of snarkOS/snarkVM/SDK.

## Related in-tree surfaces

- Dossier: [`docs/targets/09-aleo.md`](../targets/09-aleo.md)
- Prior research: [`15-aleo-psy-compiler-vm.md`](15-aleo-psy-compiler-vm.md) (compile-only gate already landed; this report freezes post-compile offline reality)
- Acceptance/finalization: `scripts/aleo_acceptance.sh`, `Tests/Materialization/AleoAcceptance.lean`, `ProofForgeV2/Targets/Aleo/FinalizeV1.lean`, `Tests/Materialization/AleoCompiledFinalizationV1.lean`
- Optional spike script: `scripts/aleo_local_toolchain_spike.sh` (engineering
  probe only; not CI; `SPIKE-PASS` / `SPIKE-BLOCKED` / `INFO-BLOCKED` markers;
  exact-3 inventory fail closed; clears ambient Aleo env)
- Tool Lock: `toolchains.lock.json` / `toolchains-linux-x86_64.lock.json` tool `leo` 4.0.2
