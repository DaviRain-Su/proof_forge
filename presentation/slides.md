---
theme: default
title: ProofForge V2
info: Hackathon Research Final — 7 min
author: DaviRain / ProofForge
class: text-center
drawings:
  persist: false
fonts:
  sans: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif'
  mono: '"SF Mono", "Fira Code", "JetBrains Mono", "Noto Sans SC", monospace'
---

# ProofForge V2

## One source, multi-chain — no silent drift

**Hackathon Research Final · 7 min**

DaviRain / ProofForge

---
layout: center
---

# Multi-chain today is expensive and risky

<v-clicks>

- One dApp → Solidity, Rust/Solana, Rust/NEAR, Noir, Move…
- Each target re-implements business logic → **semantic drift**
- Re-audit, re-test, re-document for every chain
- Toolchain / version mismatch → "works on my machine"

</v-clicks>

---
layout: center
---

# A growing, real demand

<v-clicks>

- ZK rollups, L2s, appchains, cross-chain apps exploding
- Teams want to deploy on the chain that users prefer
- No widely-adopted "write once, run anywhere" for smart contracts
- Security audit market is large and **per-chain**

</v-clicks>

---
layout: two-cols
---

# Our product: a portable compiler

<v-clicks>

- One `program ... where` source
- `--target evm | solana | near | noir`
- Compiler guarantees semantics **or fails closed**
- No top-level contract / circuit / zkVM label

</v-clicks>

::right::

```lean
program Counter where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count

  view get() : UInt64 do
    return count
```

---
layout: center
---

# User flow: write, check, build, inspect

```bash
proof-forge-next check Counter.lean
proof-forge-next build Counter.lean --target evm
proof-forge-next inspect --target evm
# OutputSet: ABI, bytecode, manifest
```

<v-clicks>

- `check` validates without choosing a target
- `build` emits target artifacts + provenance manifest
- `inspect` lists diagnostics and support decisions
- deploy / prove / verify are **explicit** follow-up commands

</v-clicks>

---
layout: image
image: /images/01-architecture-overview.png
backgroundSize: contain
---

# What makes it technically different?

---
layout: center
---

# Technical differentiation

| What others do | What we do |
| --- | --- |
| Best-effort transpiler | **Exact** requirement → SupportClaim resolver |
| Source coupled to target | Target-neutral `Semantic.Program` |
| Plan as string / JSON | Typed `Plan` + `TargetIR` per target |
| Silent fallback | **Fail-closed** diagnostics |
| Trust environment | Deterministic, reproducible, clean-room build |

---
layout: center
---

# What works now?

| Target | Evidence | Not yet claimed |
| --- | --- | --- |
| EVM | `solc` bytecode + Anvil runtime | Complete EVM backend |
| Solana | typed `.sbpf-plan` + IDL | sBPF object / ELF / runtime |
| NEAR | raw-u64 WAT/Wasm via `wat2wasm` | Sandbox receipt |
| Noir | target-owned Plan + relation IR + `.nr` | ACIR / proof / VK |

<div class="mt-6 text-center text-sm opacity-80">
Honest maturity: all artifacts share one semantic hash.
</div>

---
layout: center
---

# AI & Web3: where we fit

<v-clicks>

- Deeply Web3: smart contracts, ZK circuits, multi-chain accounts
- Not a wrapper: target-owned Plan/IR + exact capability matching
- AI is **not** used in the compiler core today
- Instead, we provide a **deterministic verification layer** — useful whether code is written by humans or AI assistants

</v-clicks>

---
layout: two-cols
---

# Vitalik: the same direction

<v-clicks>

- A high-level language compiled to Lean
- For human-readable definitions & theorems
- Exactly the formal backbone we are building
- AI-generated proofs need a readable, verifiable layer

</v-clicks>

::right::

![Vitalik tweet about Lean](/images/vitalik-lean-tweet.png)

---
layout: center
---

# Business model & ecosystem

<v-clicks>

- **Open-source compiler core** → adoption and community trust
- **Enterprise services**: multi-chain audits, CI gate, SBOM reporting
- **Toolchain integrations**: provers, SDKs, deployment pipelines
- **Ecosystem value**: fewer audits, faster cross-chain launches, lower regression risk

</v-clicks>

---
layout: center
---

# Why us, not a transpiler or bridge?

<v-clicks>

- **Transpilers**: often best-effort, silent semantic drift
- **Bridges**: runtime layer, not source-level semantics
- **ProofForge**: fail-closed, exact-version, reproducible build
- Target picks the form, but **cannot change the meaning**

</v-clicks>

---
layout: image
image: /images/05-target-landscape.png
backgroundSize: contain
---

# Roadmap & target landscape

---
layout: center
---

# Team & next steps

<v-clicks>

- D0 closeout: independent compiler, docs, specs, SBOM
- D1: full parser + type/effect system
- D2: structs, events, fn calls, proof references
- Phase 1: EVM runtime, Solana ELF, NEAR sandbox, Noir proof
- Design-only: CosmWasm, Soroban, ICP, OpenVM, Aleo, Psy

</v-clicks>

---
layout: center
class: text-center
---

# Let's build the common source of truth

## ProofForge V2

- Repo: `github.com/DaviRain-Su/proof_forge`
- Docs: `docs/01-prd.md` · `docs/02-architecture.md`
- Try: `just build && just test`

<div class="mt-8 text-2xl">
  Q & A
</div>
