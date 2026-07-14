# OpenVM Research Target Brief

Status: **Research inventory only (2026-07-15)** — no registry id, no backend,
no CLI target, and no product route.

This brief is Task **C3** / Portable Intent **Task 12**. It pins primary-source
facts and records a go/defer decision. It does **not** authorize implementation.

Related:

- [ZK promotion analysis](../superpowers/specs/2026-07-12-psy-integration-analysis.md)
- [Portable Intent plan Task 12](../superpowers/plans/2026-07-12-portable-intent-abstraction.md)
- [Target portfolio](../target-roadmap.md)
- D-056: finish primary-triad authoring cutover before deep secondary-host work

## Decision (reviewed)

| Field | Value |
|---|---|
| Decision | **Defer** OpenVM backend, registry entry, and shared ZK HostOps |
| Revisit after | (1) [PR #104](https://github.com/DaviRain-Su/proof_forge/pull/104) lands; (2) PSy plan-only C1 and Aleo plan-only C2 complete or are explicitly deprioritized with evidence |
| Preferred first spike (if later accepted) | **Rust guest sourcegen** → `cargo openvm build/run/prove` oracle, not hand-written Core→RV32 assembly |
| Forbidden until reopened | `ProofForge.Target` id, `contract_source` for OpenVM, Canonical Core OpenVM constructors, CI prove jobs, maturity upgrades |

Rationale (short):

1. ProofForge's active program is primary-triad direct authoring cutover and
   NEAR/EVM ownership cleanup. OpenVM does not unblock that path.
2. The accepted ZK order is **PSy plan → Aleo plan → OpenVM brief → then
   re-rank**. This brief closes the brief step; it does not jump the queue.
3. OpenVM is a **guest zkVM + STARK/EVM proof** toolchain, not a smart-contract
   chain host like NEAR/Soroban. It needs a new target family plan, not another
   EmitWat host bridge.
4. Upstream already ships a Rust frontend and CLI. Emitting RV32 by hand from
   Canonical Core would duplicate the hard path before any Counter evidence
   exists.
5. Upstream Lean FV is real but **not a drop-in ProofForge library**: different
   Lean version, different proof object (chip vs portable contract), and heavy
   dependency surface.

## Primary sources (pinned 2026-07-15)

| Fact | Source |
|---|---|
| Project home / dual license Apache-2.0 + MIT | [openvm-org/openvm](https://github.com/openvm-org/openvm) |
| Book (intro, install, apps) | [docs.openvm.dev/book](https://docs.openvm.dev/book/getting-started/introduction) |
| Product page / modular extension framing | [axiom.xyz/openvm](https://axiom.xyz/openvm) |
| Whitepaper | [openvm.dev/whitepaper.pdf](https://openvm.dev/whitepaper.pdf) |
| Versioning / vkey compatibility rules | [VERSIONING.md](https://github.com/openvm-org/openvm/blob/main/VERSIONING.md) |
| RV32IM Lean formal verification | [openvm-org/openvm-fv](https://github.com/openvm-org/openvm-fv) |
| Sail-backed RISC-V Lean spec used by FV | [opencompl/sail-riscv-lean](https://github.com/opencompl/sail-riscv-lean) |

## Release and toolchain

| Item | Pinned fact |
|---|---|
| Recommended production release | **v2.0.0** (GitHub release dated 2026-07-10; book status as of July 2026) |
| Install (CPU CLI) | `cargo +1.91 install --locked --git https://github.com/openvm-org/openvm.git --tag v2.0.0 cargo-openvm` |
| Validate install | `cargo openvm --version` |
| Host Rust for install path | toolchain **1.91** in the documented install command |
| Nightly for experimental/tco builds | `nightly-2026-01-18` (+ `rust-src`) |
| Guest path | Rust guest program → RISC-V via OpenVM's Rust frontend / RV32IM extension |
| Config surface | per-project `openvm.toml` selects VM extensions |
| License (framework) | **Apache-2.0 OR MIT** dual license |
| GPU prover license claim | book states GPU prover is open-source under MIT and Apache-2.0 |

Security / audit facts (do not over-claim in ProofForge maturity tables):

- v2.0.0+ recommended for production use; external audit by zkSecurity under
  `audits/v2/`.
- v1.7.0 had Cantina + internal Axiom reviews under `audits/v1/`.
- These are **upstream** assurance claims. ProofForge has zero OpenVM code path,
  so they do not improve any ProofForge target stage.

## Guest ISA and executable format

| Item | Pinned fact |
|---|---|
| Base guest ISA | **RISC-V RV32IM** via an OpenVM extension (not a general multi-chain Wasm host) |
| Architecture style | Modular “no-CPU” framework: chips/extensions compose the machine |
| Documented extensions (non-exhaustive) | Keccak-256, SHA-256, SHA-512; Int256; modular arithmetic; EC ops (incl. secp256k1/secp256r1); pairings BN254 / BLS12-381; aggregation deferral |
| Executable path | Rust guest → build/transpile to OpenVM VM executable (`VmExe` in versioning docs) |
| Commit objects | `app_vm_commit`, `leaf_vm_commit`, `internal_vm_commit` are versioning-stable across patch releases |

## Host/guest I/O ABI

From the writing-apps overview:

| Mechanism | Behavior |
|---|---|
| CLI input | `--input` is a hex string **or** a JSON file with key `input` and an array of hex strings |
| Byte stream prefix | `0x01` + little-endian serialized bytes (structs via `openvm::serde::to_vec`, zero-padded to multiple of 4) |
| Field-element stream | `0x02` + native field elements as little-endian `u32` words (hex length multiple of 8 after prefix) |
| Guest read | `openvm::io::read()` deserializes typed inputs |
| Multi-stream | multiple inputs require the JSON file form |
| Hex length | even length required to avoid nibble ambiguity |

ProofForge implication: any future plan must model **typed guest I/O** and
fail closed on unsupported portable shapes. Do not pretend portable
storage/events/crosscall map 1:1 onto OpenVM guest I/O.

## Execution, prove, and verify commands

Documented CLI flow (CPU path):

```text
cargo openvm build
cargo openvm run [--input ...]
cargo openvm keygen
cargo openvm commit
cargo openvm prove app [--input ...]
cargo openvm verify app
cargo openvm setup [--evm]          # aggregation / EVM verifier artifacts
cargo openvm prove <stark|evm> ...
cargo openvm verify <stark|evm>
```

Proof / verifier artifacts (honest labels only):

| Layer | Meaning for ProofForge |
|---|---|
| Application proof | Program execution proof under the selected OpenVM config |
| STARK aggregation | Aggregated STARK after `setup` |
| EVM proof / verifier | Ethereum-oriented verification path; `setup --evm` is the heavy step |
| Verifier contract | Separate on-chain verification integration — **not** a property of guest lowering alone |

Versioning honesty: OpenVM treats the true API as **proof verification
compatibility** (especially `MultiStarkVerifyingKey`). Patch upgrades keep
vkey/proof format stable; minor bumps may break vkeys. A future ProofForge
artifact schema must pin OpenVM major.minor and treat vkey changes as
breaking.

## Hardware and CI budgets (exact claims from docs)

| Workload | Documented requirement / note |
|---|---|
| CPU install / build / run / app prove | Standard Rust machine; no GPU required |
| `cargo openvm setup --evm` local keygen | **~16 GB** compute/memory class; docs recommend `--download` for pre-built Halo2 keys from S3 when available |
| CUDA `prove app` / `prove stark` | Nvidia GPU + drivers + CUDA toolkit (tested 12.9 / 13.0 / 13.1; CI prefers 12.9) |
| CUDA `prove evm` (`halo2-gpu`) | Peak GPU memory **≥ ~25 GB**; recommend **≥ 32 GB** GPU memory |
| AOT guest→host | x86_64 only; docs mark **unprotected** mode — trusted guests only |

ProofForge CI implication:

- Optional smoke limited to `cargo openvm build` + `run` for a tiny guest may
  fit ordinary runners **if** tools are installed.
- App prove is possible but expensive; do not put full EVM prove or
  `setup --evm` without download on required GitHub/Woodpecker lanes.
- GPU prove stays outside default `just check`, same policy as Solana live /
  heavy external tools.

## Lean semantics dependency and proof boundary

| Item | Fact |
|---|---|
| Upstream FV repo | [openvm-org/openvm-fv](https://github.com/openvm-org/openvm-fv) |
| Lean version (upstream pin) | **Lean v4.26.0** (repo README) |
| ProofForge Lean pin (this repo) | **v4.31.0** (`lean-toolchain`) — **not compatible as a Lake dependency without a dedicated port** |
| Spec baseline | Official Lean RISC-V spec ([sail-riscv-lean](https://github.com/opencompl/sail-riscv-lean)) |
| Proven object | All **45 RV32IM opcodes** (ALU 27, control 10, memory 8) — chip constraints ↔ RISC-V spec |
| Also formalized | BabyBear field helpers, bus interactions, RISC-V→native OpenVM transpiler model |
| Build | `lake update && lake exe cache get! && lake build` |
| License | Apache-2.0 OR MIT |

**Proof boundary for ProofForge (must stay honest):**

```text
What openvm-fv proves:
  OpenVM RV32IM chip constraints  ⇔  Lean RISC-V opcode specs
  (under the assumptions documented in REPORT.pdf)

What ProofForge would still need to prove (none of this exists today):
  portable contract / Canonical Core  ⇒  guest program behavior
  guest program  ⇒  observed OpenVM run / proof public values
  verifier integration  ⇒  on-chain or offline verification of that proof
```

Do **not** market “OpenVM formal verification” as ProofForge contract
correctness. Optional future work is a separate Lake library (same pattern as
`ProofForgeFormalEvm` / `ProofForgeFormalSolana`), never a default compiler
dependency, and only after Lean versions align or a deliberate pin strategy
exists.

## Architecture options (if later accepted)

Accepted potential shape from the ZK analysis, refined by this brief:

```text
CheckedCanonicalContract
  -> OpenVMModulePlan          # target-owned; no Core OpenVM nodes
  -> guest artifact
       preferred: generated Rust crate + openvm.toml
       alternative research: direct RV32 / VmExe emission
  -> cargo openvm build/run    # execution evidence
  -> cargo openvm prove/verify # proof evidence (separate gate)
  -> optional EVM verifier integration (separate artifact lane)
```

### Option A — Rust guest sourcegen (recommended first spike)

Pros:

- Matches upstream developer path and examples.
- Reuses OpenVM extensions via Rust intrinsics instead of inventing chips.
- Fail-closed fragment gates are straightforward (unsupported IR → diagnostic).
- Aligns with ProofForge's historical sourcegen pattern (Psy/Aleo), while
  treating `cargo openvm` as the oracle.

Cons:

- Two compilers in the stack (ProofForge + rustc + OpenVM transpile).
- Guest Rust is not the portable product source; Product remains Lean.

### Option B — Direct Core → RV32 / OpenVM executable

Pros:

- Shorter path if Core already expresses low-level ops cleanly.
- Closer to eventual refinement against RV32 semantics.

Cons:

- Reimplements what the Rust frontend already provides.
- Must own memory layout, syscalls/I/O, and extension encodings.
- Higher risk of silent semantic drift without a large oracle suite.

**Brief recommendation:** if OpenVM is ever scheduled, start with **Option A
Counter-only**, plan-only first (`OpenVMModulePlan` + strict fragment gate),
then optional `build`/`run` smoke. Only consider Option B after Option A has
execution evidence and a measured pain point.

## Comparison to existing ProofForge ZK inventory

| Target | Today | Relation to OpenVM |
|---|---|---|
| `psy-dpn` | Spike sourcegen + Dargo | Different circuit/VM model (DPN); keep first for ZK plan work |
| `aleo-leo` | Research sourcegen | Different Leo/Aleo package model; second plan-only slice |
| OpenVM | **Docs only (this brief)** | Guest zkVM + STARK/EVM proofs; third research candidate |

OpenVM does **not** replace PSy or Aleo. Ranking after C1/C2 should use:

1. tool installability on CI;
2. Counter fragment honesty;
3. proof-gate cost;
4. product demand for “prove portable IR execution” vs chain deploy.

## Explicit non-goals (this brief)

- Adding `openvm` / `zk-openvm` to `ProofForge.Target.knownIds` or
  `--list-targets`.
- Changing Backend Status maturity tables.
- Opening shared `zk.*` HostOps without a concrete target implementation and
  reject tests.
- Importing `openvm-fv` into the default `ProofForge` Lake package.
- Claiming audit or production readiness for any ProofForge OpenVM path.
- Scheduling work that competes with D-056 authoring cutover or NEAR-R* tasks.

## Acceptance for Task C3

This document is complete when:

- [x] Release, ISA, executable path, proof/verifier layers, I/O ABI, license,
  and CLI commands are pinned to primary sources.
- [x] CI/hardware budgets are recorded with upstream numbers, not estimates.
- [x] Lean FV dependency, version skew, and proof boundary are explicit.
- [x] Direct RV32 vs Rust guest approaches are compared.
- [x] A reviewed **defer** decision is recorded (no implementation tasks opened).

## Reopen checklist (future)

Only open an implementation plan when **all** hold:

1. Primary-triad authoring cutover is on `main` (or an explicit exception is
   recorded in `decisions.md`).
2. C1/C2 outcomes are written, or a decision reorders ZK work with evidence.
3. A Counter-only supported fragment is named with fail-closed unsupported
   shapes.
4. CI policy chooses: optional job vs required; CPU-only vs GPU; prove scope
   (`run` only vs `prove app`).
5. Artifact schema pins OpenVM **v2.x** minor for vkey compatibility.
6. No Canonical Core leakage: all OpenVM details stay under a target-owned
   plan/HostOp catalog.
