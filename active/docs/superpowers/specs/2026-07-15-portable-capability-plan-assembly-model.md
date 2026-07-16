# Portable capability, target Plan, and assembly codegen — architecture summary

Status: **Current orientation note (2026-07-15)**  
Branch context: PR #105 Seam A / LR-S* work; decisions **D-057**, **D-058**, **D-050**, **D-054**  
Chinese: [2026-07-15-portable-capability-plan-assembly-model.zh.md](2026-07-15-portable-capability-plan-assembly-model.zh.md)

This document freezes the consensus from architecture discussion on how ProofForge
relates to Solana sBPF assembly, Wasm/NEAR EmitWat, EVM Yul, official SDKs, and
how to improve **expression capability** and **ecosystem completeness** without
mistaking the project for “a full Solana/NEAR SDK in Lean.”

It does **not** reschedule cutover PR #104 or reopen Rust product lower (D-058).

---

## 1. One-line product identity

**ProofForge is an experimental multi-target contract compiler:** authors write
portable (and optional target-extension) logic in Lean; the compiler materializes
**target Plans** and **emits** Yul / sBPF text / WAT for **external** toolchains
and **chain VMs**.

It is **not**:

- a drop-in replacement for the official Solana Rust SDK, Pinocchio, Anchor, or
  NEAR `near-sdk`;
- a product runtime that executes contracts inside Lean;
- a program to re-implement full EVM / Wasm / sBPF virtual machines as the
  deploy path.

---

## 2. What “assembly” means here (codegen, not VM)

```text
Lean authoring (contract_source / extensions)
        │
        ▼
  Canonical Core + CapabilityPlan     ← shared semantic ownership
        │
        ├── EVM:     ModulePlan → Yul text → solc → bytecode → EVM node
        ├── Solana:  SolanaModulePlan → sBPF AST → .s → sbpf → ELF → Solana runtime
        └── NEAR:    NearModulePlan → Wasm AST → .wat → wat2wasm → Wasm → NEAR runtime
```

| Role | Owner |
|---|---|
| Business / portable meaning | Lean frontend + Canonical Core |
| Chain-shaped plan | Target `*ModulePlan` / EVM `ModulePlan` |
| Instruction **text** emission | Lean printers (Yul / sBPF Asm / Wasm Printer) |
| Binary packaging | **External:** `solc`, `sbpf`, `wat2wasm` |
| Production execution | **Chain / ecosystem VMs** (not Lean) |

Optional in-repo **interpreters** (sBPF exec smoke, Wasm exec, Yul semantics) are
**test/formal shadows**, not the product execution path.

**Solana vs Wasm difference:** same *role* (codegen to someone else’s VM),
different *ISA and host model* (register+syscall sBPF vs stack+import Wasm).

---

## 3. Shared capabilities vs chain-unique capabilities

### 3.1 Shared (“portable”) layer

Cross-chain business meaning, e.g.:

- scalar / map / array-shaped state (shape only; binding is target-resolved);
- arithmetic, control flow, assertions;
- event *intent*, crosscall *intent* where portable;
- checked Core validate and capability *requirements*.

This is **not** “Public AI”; call it **portable / shared semantics**.

### 3.2 Chain-unique layer

Examples:

| Family | Unique surface (high level, not opcodes) |
|---|---|
| Solana | Account graphs, PDA, CPI, sysvars, allocator policy, SPL helpers… |
| NEAR | Promise graph, JSON/Borsh host shapes, account-id strings… |
| EVM | Selectors/ABI words, CREATE2, fallback/receive, packing… |

Per **D-027 / D-050 / D-054**: unique APIs live in **target extensions /
Source.\<Chain\> / HostOps**, not as permanent pollution of shared Core.

### 3.3 Same portable intent, different materialization

Even shared ops differ by chain (storage binding, caller identity, logs).
Gaps are therefore:

1. **missing unique capabilities**, and  
2. **incomplete or dishonest materialization of shared ones** (e.g. Solana hash
   limb0-only Phase-1).

---

## 4. High-level abstraction → Plan → assembly

Correct flow for **unique** (and shared) capabilities:

```text
Author surface (high level)
  e.g. PDA seeds, CPI shape, promise.then — NOT mov64 / i64.add
        │
        ▼
Normalized semantic records (extensions, HostOps, materialization metadata)
        │
        ▼
Target Plan (accounts, layout, entrypoints, host calls, …)
        │
        ▼
Assembly / IR print (sBPF AST, Wasm AST, Yul)
        │
        ▼
External packager → deployable artifact
```

**Plan consumes structured meaning; assembly only implements the Plan.**

Do **not** raise expression power by making authors write three full ISAs in
Lean. That trades compiler pain for worse authoring pain and does not unify
multi-chain meaning.

---

## 5. Official SDK parity: what “same level” would require

### 5.1 Not the same product

| | Official Solana Rust / near-sdk | ProofForge today |
|---|---|---|
| Author language | Rust + macros/crates | Lean portable + extensions |
| Expression surface | Near-full chain program surface | **Supported capability slice** |
| Lowering | rustc / official toolchains | Lean Plan → text → solc/sbpf/wat2wasm |
| Execution | Chain VM | Same class of chain VM |
| Gap | — | **expression slice + ecosystem fit**, not “wrong VM” |

### 5.2 Two metrics to raise

| Metric | Meaning | How to raise |
|---|---|---|
| **Expression capability** | What can be written and run with true semantics | Capability table + high-level APIs + Plan + lower + **runtime tests** − silent subsets |
| **Ecosystem completeness** | Tooling/interop/docs/clients | Artifacts, IDL/clients, deploy paths, examples, optional **sourcegen to official crates** |

Assembly codegen drives expression; ecosystem needs **connectors** (IDL, scripts,
interop with hand-written Pinocchio/near-sdk programs).

### 5.3 “Just provide roughly the same capabilities?”

**As a slogan: yes.**  
As engineering: capabilities must be **(1) listed, (2) semantically true, (3)
authorable**. A name on a table without full-width hash (or with sole-parameter
string limits) is not parity.

**Honest today:** experimental multi-chain **slice**, not SDK parity.

---

## 6. Coverage honesty (Solana / Wasm)

Detail: [solana-wasm-coverage-scan-2026-07-15.md](../../targets/solana-wasm-coverage-scan-2026-07-15.md).

| | Solana sBPF path | Wasm-NEAR EmitWat |
|---|---|---|
| Simple portable products compile | Often yes | Often yes |
| Full official SDK surface | **No** | **No** |
| Largest semantic risks | Hash **limb0** Phase-1; events/CPI depth | Multi-arg dynamic string/bytes; U128/bytes/memory-array gaps |
| Failure style | Mix of fail-closed + **silent subset** | Mostly fail-closed |
| Fixture `emit` matrix | Incomplete mapping | Incomplete mapping (product may still build) |

**Build green ≠ production-complete semantics.**

Related fix on this branch: `Asm.numStr` emits `0x…` for immediates `≥ 2^63`
so sbpf accepts AccessControl-style hash limbs (`just access-control-solana-smoke`).

---

## 7. How to complete the model (operating system)

### 7.1 Supported Surface table (scope)

Freeze what is promised (v0, v1, …). Outside the table: **compile fail**, not
half semantics.

### 7.2 Capability packages (expression)

Grow by package: state, control, full-width hash/identity, account/CPI/PDA
matrix rows, event shapes, FT/NFT fixed shapes, etc.

Each package graduation:

```text
author API → Plan fields → assembly lower → runtime assertion → table “verified”
```

### 7.3 Differential testing (primary acceptance)

For each package:

1. Fixed scenario script.  
2. ProofForge artifact.  
3. Minimal **official-style** reference (Pinocchio / near-sdk / Solidity).  
4. **Declared observe dimensions** (state, success/fail, returns, normalized
   logs; not raw binary equality).  
5. CI / `just` gate.

Differential **accepts** the pipeline; it does **not** replace high-level
authoring. Existing seeds: Pinocchio references, testkit multi-target, Stylus
rust-sdk oracle, Seam A observe dual-run (narrow dimensions).

### 7.4 Fail-closed + kill silent subsets

Prefer refuse over limb0-as-full-hash. Either finish full-width hash or rename
APIs and document the subset.

### 7.5 Ecosystem levers

Stable artifacts, clients, one-path deploy docs, interop examples (ProofForge
core + official edge), optional **sourcegen** to Pinocchio/near-sdk when
self-hosted lower cost exceeds benefit (D-058: do not re-print sBPF/WAT in Rust
without ready libs or explicit sourcegen strategy).

### 7.6 What not to do

- Default author path = three full ISAs in Lean.  
- Product Lean VMs instead of chain execution.  
- Rust re-implementation of machine-IR printers “because strings are hard”
  (**D-058**).  
- Claim SDK parity from product compile smoke alone.

---

## 8. Seam A (Lean/Rust) in one paragraph

**D-057 / D-058 / PR #105:** experimental **Core export** + read-only Rust
inspect / surface sketch / observe dual-run (entrypoints + slots). Product
lower stays Lean. No multi-chain SDK mega-binary, no object-pointer FFI as the
semantic seam. Export packages are a **stable contract**, optionally orchestrated
(`just export-inspect`, `just dual-run-observe-seam-a`), not a second compiler.

---

## 9. Related documents

| Topic | Doc |
|---|---|
| Decisions D-050/D-054/D-057/D-058 | [decisions.md](../../decisions.md) |
| Lean/Rust boundary | [lean-rust-boundary design](2026-07-15-lean-rust-boundary-design.md) |
| Core export / Seam A | [core-export-v0 draft](2026-07-15-core-export-v0-draft.md), [agent-goal-prompt-lean-rust-seam-a.md](../../agent-goal-prompt-lean-rust-seam-a.md) |
| EVM selectors | [evm-selectors.md](../../targets/evm-selectors.md) |
| Solana/Wasm scan evidence | [solana-wasm-coverage-scan-2026-07-15.md](../../targets/solana-wasm-coverage-scan-2026-07-15.md) |
| Solana target note | [solana-sbpf-asm.md](../../targets/solana-sbpf-asm.md) |
| NEAR / Wasm family | [wasm-near.md](../../targets/wasm-near.md), [wasm-family.md](../../targets/wasm-family.md) |

---

## 10. Bottom line

1. **Shared portable capabilities + chain-unique high-level capabilities** →
   **target Plan materialization** → **assembly emission** → external tools →
   chain VMs.  
2. Unique features must stay **high-level until Plan**, then lower—do not dump
   ISAs into shared Core.  
3. Raising “SDK level” means a **capability table with true semantics and
   differential graduation**, plus ecosystem connectors—not implementing three
   full VMs in Lean and not pretending assembly printers equal official SDKs.  
4. **Differential vs official minimal references** is the main *acceptance*
   engine; **Supported Surface + fail-closed** is the main *scope* engine.
