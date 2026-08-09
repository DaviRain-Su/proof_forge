---
id: RPT-015
title: C-2 Aleo/Psy compiler and VM availability research
status: draft
owner: engineering
updated: 2026-08-10
normative: false
---

# C-2: Aleo Leo compiler / Psy VM — promote acceptance gates?

> **2026-08-10 status:** ADR-0035 removed both source-language lanes. Aleo now
> emits only canonical Aleo Instructions; Psy now emits only canonical DPN
> packages. Leo/Dargo compiler, runtime, proof, and network recipes were deleted.
> This report is retained only as a historical 2026-08-02/07 experiment and is
> not a current product or engineering entrypoint.

## Question

Should ProofForge promote **real** compiler/VM acceptance gates for `aleo` and
`psy` (analogous to EvmSolc / Solana Mollusk / NearWasmAcceptance), or keep
**source-only** maturity?

## Method

Code-first audit of in-tree target leaves and product materialize path
(2026-08-02 HEAD), plus dossier claims in `docs/targets/09-aleo.md` /
`10-psy.md` and coverage matrix `12-target-coverage-matrix.md`.  
**No** live network deploys; **no** claim of hermetic tool lock.

## 2026-08-07 follow-up（historical）

Wave 1 / G123 superseded this snapshot's Aleo compile-only deferral by pinning
Leo `4.0.2` in both Tool Lock v4 files and adding locked-only `AleoAcceptance`.
ALEO-I4 now adds an explicit product profile
`aleo-leo-4.0.2-u64-compile-v1`: it shares the source profile's target-owned
Plan/planDigest, runs locked `leo build --offline --disable-update-check` in a
temporary package and isolated HOME, and publishes exactly three content-bound
compiler extras. Missing/mismatched tools and partial outputs fail with zero
published destination; same-host repeat and product `inspect` closure are tested.
Both Aleo profiles remain `deployable=false`.

This is still only engineering compile finalization: no Aleo VM, proof, deploy,
record-custody, network query, or formal/hermetic Stage-0 claim follows. Psy is
unchanged: host-optional source compile only, with no Tool Lock/VM/prover gate.

The Aleo/Psy tables below are retained as the 2026-08-02 audit snapshot; current
feature coverage (including T14, aggregate work, and ALEO-I1–I4) is authoritative
in `12-target-coverage-matrix.md`. For this report's toolchain decision, Aleo's
“no Leo pin / no compile gate” conclusion is superseded, while the no-VM/no-proof
boundary and Psy toolchain conclusion remain current.

## 2026-08-07 follow-up（Psy dargo local VM / base-proof engineering lane）

Official **dargo v0.1.0** is treated as a **proprietary, dev/test-only**
compiler/local VM (no redistribution; no network UPS product path). Engineering
surfaces implemented in-tree:

| Surface | Status |
|---|---|
| Product finalize | Still **zero-tool**, `deployable=false` (`FinalizeV1`); note points at external lane |
| Compile-only acceptance | `PsyAcceptance` + `scripts/psy_acceptance.sh` use **direct** `dargo compile` / `generate-abi` with `--contract-name`; prefer `PROOF_FORGE_TOOL_ROOT` / default cache; host `~/.psy` fallback; **psyup removed as authority**; skip-clean when absent |
| Local VM / base-proof recipe | `scripts/psy_runtime_test.sh` + `just psy-runtime` (NOT ordinary ci): hard-require locked `$ROOT/dargo` + `$ROOT/lib/psy-std/std.psy` on **linux-x86_64** / **darwin-arm64** only; never PATH; missing → `PF-TOOLCHAIN-MISSING` |
| Product runtime flows | 默认 `psy-dargo-u64-v1`：Counter build/inspect → Dargo compile/ABI → happy `initialize(5)/increment(3)/get` (`result_vm` `[]/[8]/[8]`) + `p-1+1` exact overflow。显式 `psy-dargo-0.1.0-vm-v1`：WideCounter 4×UInt32 LE Felt-limb ABI，固定 carry `[4294967295,0,0,0]+1→[0,1,0,0]`、borrow/compare、`[4294967295,0,0,0]^2→[1,4294967294,0,0]` checked mul、mixed multi-limb div/mod、UInt128 add/sub/mul overflow/underflow、div/mod zero-divisor 与 limb range rejection；两路均不 pin 随机 `public_inputs` 值 |
| Profile labels | Registry profiles = explicit `psy-dargo-0.1.0-vm-v1` + historical default `psy-dargo-u64-v1`; engineering runtime log label `psy-dargo-0.1.0-local-proof-v1` |
| UInt128 scope | VM profile only: state/params/literal/constant/entry-view return, checked add/sub/mul/div/mod, six comparisons, atomic four-leaf store; mul=8×UInt16 schoolbook; div/mod=four 32-step restoring loops (1 binding/fn); bit/shift/Switch/pureFn UInt128 return remain fail closed |
| Registry maturity | **Still source-only** |
| Tool Lock / observed run | Official dargo v0.1.0 archives、dargo executable 与 9 个 `psy-std` members 已 pin 到 Darwin arm64 / Linux x86_64 Tool Lock v4；2026-08-07 Linux exact-member root 的 `just psy-runtime` exit 0 for Counter + WideCounter；Darwin runtime 未实跑 |

The UInt128 materialization suite also steps the same retained Semantic carrier through the target-neutral Reference machine for carry/borrow/multiply/compare and overflow/underflow rollback. This is a focused engineering differential, not a formal Reference↔Psy refinement proof.

Non-claims: formal Stage-0, hermetic release, network UPS, deploy, redistribution of proprietary bits, product finalize invoking dargo.

The Aleo/Psy tables below retain the 2026-08-02 audit snapshot; current feature
coverage is authoritative in `12-target-coverage-matrix.md`. Aleo's
compile-only gate remains as above; Psy now has an **optional host-heavy**
local-VM recipe without upgrading the registry maturity label.

## Aleo (`TargetId.aleo`)（2026-08-02 历史快照）

### In-tree engineering facts

| Surface | Status |
|---|---|
| Capability Plan / IR / emitter | Present (`Targets/Aleo/*`) |
| Product materialize | Emits Leo-oriented **source package** files |
| Tests | `Tests/Materialization/Aleo.lean` — plan/IR validate + files |
| Coverage | B-1c AleoCoverage: scalar UInt64 envelope LOWERED; Field FAIL-CLOSED (BLS12-377 Fr ≠ catalog bn254); aggregates/ContextRead/emit/call FC |
| Real `leo` compile gate | **Absent** at snapshot — later G123 added locked leo compile-only |

### Compiler/VM availability (research)

- Public Leo 4.x / snarkVM tooling exists upstream, but this repo does **not**
  pin a cargo-git/binary asset for `leo` under Tool Lock v4 product supply
  (snapshot wording; superseded by 2026-08-03 pin).
- Engineering acceptance would require at minimum: pinned Leo patch +
  deterministic `leo build` (or equivalent) on materialize staging, skip-clean
  when absent, fail-closed on non-zero (pattern of EvmSolc / NearWasm).
- Field mismatch (native Aleo field ≠ ProofForge bn254 Fr catalog) remains a
  product semantic lock; a compile gate must not paper over it.

### Recommendation (historical)

**Do not promote** an Aleo compiler acceptance gate in the 2026-08-02 wave.
Later: compile-only gate **was** promoted; VM/prove/deploy still **not**.

## Psy (`TargetId.psy`)

### In-tree engineering facts（updated 2026-08-07）

| Surface | Status |
|---|---|
| Capability Plan / IR / emitter | Present (`Targets/Psy/*`) |
| Product profiles | Historical default `psy-dargo-u64-v1`; explicit VM-observed extension `psy-dargo-0.1.0-vm-v1` |
| Product materialize | Source-oriented packages (`.psy`) |
| UInt128 | VM profile only, 4×UInt32 LE Felt limbs; state/params/literal/constant/entry-view result + checked add/sub/mul/div/mod + six comparisons; mul=8×UInt16 schoolbook; div/mod=restoring; bitwise/shift and UInt256 remain fail closed |
| Field | Psy Felt = Goldilocks (T14 catalog membership) |
| Product finalize | Zero-tool / non-deployable |
| Real dargo compile gate | Optional engineering (`PsyAcceptance`); skip if tools absent |
| Real local VM execute | Optional host-heavy `just psy-runtime` when locked root present; Counter + WideCounter on Linux observed |
| Network UPS / deploy | **Absent** |

### Recommendation（2026-08-07）

- Keep **registry maturity source-only**.
- Keep product finalize free of dargo.
- Treat locked dargo local-VM as a **manual / host-heavy engineering recipe**,
  analogous in discipline to `just solana-runtime` (not ordinary ci).
- Do not advertise formal/hermetic/deploy or proprietary redistribution.

## Decision table（C-2 + later overrides）

| Target | Promote acceptance gate? | Maturity stays |
|---|---|---|
| aleo | **Compile-only yes** (G123); VM/prove **no** | source-only Plan/IR/source package |
| psy | **Compile-only optional**; **local-VM recipe optional host-heavy**; UPS/deploy **no** | source-only / research registry label |

## Explicit non-claims

- Not formal Stage-0 / hermetic evidence.
- Not a claim that Leo/Psy cannot be productized later.
- Not an upgrade of AGENTS registry maturity beyond “source-only” for Psy.
- Not a claim that the Linux Counter-only engineering run establishes Darwin parity,
  Reference differential, network UPS, deployability, hermetic release, or formal proof.

## Follow-on

1. Run the same locked gate on an actual Darwin arm64 host before claiming cross-platform parity.
2. Keep Psy finalize zero-tool; never fold execute into product publish.
3. For every newly opened Psy capability, add target-owned ABI/IR validation,
   locked VM observation, Reference differential, and proof binding where claimed.
