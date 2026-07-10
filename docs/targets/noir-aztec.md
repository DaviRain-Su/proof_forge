# Noir (Aztec) Target

Status: **Research (docs-first candidate)**

Candidate target id: **`noir`** (Aztec is the primary deployment chain; Noir is also a
standalone ZK-circuit language)

This note records the first ProofForge classification for Noir — the Rust-like
zero-knowledge circuit language from the Aztec ecosystem. It does not add a Lean target
profile yet. Noir is called out separately from `psy-dpn` and `aleo-leo` because it has an
**existing Lean 4 formal semantics** (`reilabs/lampe`), which makes it an **FV-import
target** (like the EVM lane's `powdr-labs/evm-semantics`), not merely a ZK sourcegen target.

Primary sources:

- [Noir documentation](https://noir-lang.org/docs)
- [Noir GitHub](https://github.com/noir-lang/noir) (`nargo` compiler)
- [awesome-noir](https://github.com/noir-lang/awesome-noir)
- [Aztec docs](https://docs.aztec.network/)
- [Reilabs `lampe` — Noir → Lean 4](https://github.com/reilabs/lampe)
- [NAVe: Formally Verifying Noir ZK Programs (arXiv:2601.09372)](https://arxiv.org/abs/2601.09372)

## Classification

Noir is a **ZK-circuit source-generation target with an FV-import path**. It is not EVM,
Wasm-host, Move, Solana sBPF, TVM, AVM, or UTXO script.

```text
Noir target
  -> generated Noir package (constrained + optional unconstrained fns)
  -> nargo compile
  -> ACIR (constraint IR) + Brillig (unconstrained bytecode)
  -> proving backend (Barretenberg / others) -> proof + verifier
  -> Aztec deploy, OR standalone proof generation/verification
```

Noir compiles to **ACIR** (Abstract Circuit Intermediate Representation — the constraint
system) plus **Brillig** (bytecode for unconstrained/`unsafe` functions). ACIR is
backend-agnostic; the default proving backend is Aztec's **Barretenberg**, but Noir is not
tied to one proof system.

## Lean 4 semantics availability — why Noir is an FV-import target

- **[`reilabs/lampe`](https://github.com/reilabs/lampe)** — "extracting the semantics of
  Noir to Lean for formal verification." It models **Noir's execution semantics in Lean 4**
  and lets a user interactively prove program properties (presented at NoirCon 2, "Shedding
  Light on Noir with Lampe").
- **NAVe** (arXiv:2601.09372) — an *automated* (SMT-based) verifier that formalizes **ACIR**
  rather than Noir (ACIR is more stable and shared by other languages targeting it).
  Complementary to Lampe (interactive, Lean 4).

Because Lampe is a Lean 4 execution semantics of Noir, ProofForge can treat Noir like the
EVM lane treats `powdr-labs/evm-semantics`: **refine the portable IR against Noir's Lean
`Step`/semantics via the shared `CounterUniversal` induction.** See the **ZK-import group**
in [the FV target-semantics plan](../superpowers/plans/2026-07-07-fv-target-semantics.md).

**Boundary (non-goal, like `solc`):** the proving system (Barretenberg / Honk / Groth16)
stays external. We prove IR ⟷ the Noir program's computed function; "the circuit is sound /
the proof verifies" is the ZK toolchain's job, not ProofForge's.

## Why This Matters For ProofForge

Noir gives ProofForge a **ZK application surface with a ready Lean semantics** — the only ZK
target besides Cairo where FV can be *imported* rather than self-built (Aleo/Psy have no
Lean semantics). Its ACIR IR also fits the "restricted portable-IR subset" sourcegen pattern
(like `psy-dpn`), so the codegen is tractable.

Target-specific concerns:

- Noir functions split into **constrained** (circuit) and **unconstrained** (`unsafe`,
  Brillig) bodies — the portable-IR subset must map to constrained functions first.
- ACIR has **high-level memory ops, range checks, and bit-level operators** — richer than a
  plain field-arithmetic circuit; start the IR subset at scalar/field + assertions.
- Noir is **stateless per proof** (no persistent chain storage in the circuit itself); Aztec
  state (notes/nullifiers) is a separate later concern — the first spike is a pure-function
  circuit, not a stateful contract.
- Aztec deployment (contract functions, private/public execution) is a **later road**; the
  first artifact is a standalone Noir package + `nargo` compile + optional proof.

## Candidate Target Family

```text
zk-circuit-sourcegen   (shared with psy-dpn; Noir adds the Lean-semantics FV-import path)
```

Candidate artifact shape:

```text
noir-package
  - generated Noir source (constrained functions, asserts)
  - nargo.toml + package layout
  - compiled ACIR (+ Brillig for any unconstrained helpers)
  - ABI (input/return witness map)
  - optional proof + verifier (Barretenberg), behind an opt-in gate
  - nargo test / execute validation report
```

## Candidate Capabilities

Research candidates, not canonical ids yet:

| Candidate capability | Meaning |
|---|---|
| `lang.noir` | Target emits Noir source packages. |
| `ir.acir` | Build emits/consumes ACIR constraint IR. |
| `ir.brillig` | Unconstrained (Brillig) bodies are used. |
| `zk.circuit` | Entrypoints compile to a circuit (shared with `psy-dpn`). |
| `zk.proof` | Proof generation/verification flow (external backend). |
| `assertions.check` | Noir `assert` / constraint. |
| `crypto.hash` | Pedersen/Poseidon/Keccak circuit gadgets. |
| `input.private` / `input.public` | Private-by-default witness inputs; declared public inputs. |
| `test.nargo` | Validation uses `nargo test` / `nargo execute`. |
| `fv.lampe` | Program has a Lampe/Lean 4 semantics available for refinement. |

Do not add these to `ProofForge.Target.Capability` until a target profile and lowering rules
are reviewed.

## Lowering sketch (portable IR → Noir) — Road 1 implementation map

Grounded in `noir-lang/noir` (`test_programs`, `noir_stdlib/src/hash/poseidon2.nr`).
Noir-core maps closely to `psy-dpn` (both ZK-circuit sourcegen); the first spike is a
pure-function circuit (no Aztec state).

| Portable IR | Noir | Notes |
|---|---|---|
| `u8/u16/u32/u64/u128` | `u8/u16/u32/u64/u128` | Noir has the full integer widths — closer to the portable IR than Leo. |
| `bool` | `bool` | direct |
| `field` / `hash` | `Field` | a Noir `Field` is the native circuit element; a Poseidon digest is a `Field` (RFC 0015 `Hash ≡ field` applies). |
| `address` | `Field` | Aztec addresses are `Field`; first spike treats address as `Field`. |
| `fixedArray T N` | `[T; N]` | direct |
| `structType` | `struct` | direct |
| `Expr.add/sub/mul/…` (wrapping) | `+ - * …` | Noir integer arithmetic wraps by default (matches portable wrapping default). |
| `Expr.assert` / `assertEq` | `assert(cond)` / `assert(lhs == rhs)` | Noir `assert` is the circuit constraint. |
| `Expr.hash preimage` | `std::hash::Poseidon2Hasher` (or `std::hash<…>`) | Noir stdlib ships Poseidon2 — same algorithm family as Aleo/Psy (capability-portable, not value-portable, per RFC 0015). |
| `if/else`, `boundedFor` | `if` / `for i in 0..n` | Noir supports both (bounded `for` unrolls into constraints). |
| `letBind/assign/return` | `let` (immutable) / `let mut` / trailing expr | Noir returns the trailing expression. |
| entrypoint | `fn main(..)` constrained | one constrained `fn` per proof; `pub` marks public inputs. |

**First-spike fixture:** `PureMath` (pure arithmetic, no state) → a Noir `fn main(a: u64, b: u64) -> u64 { a + b }` package + `nargo compile`/`nargo test`. This is the Road 1 exit and the prerequisite for the Lampe FV-import (Road 2).

## Implementation Roads

### Road 1: Noir package sourcegen (the codegen prerequisite)

The conservative first spike, and the **prerequisite for any FV-import work**.

- choose a tiny pure-function fixture (checked-arithmetic PureMath, or a hash-preimage
  check) from the portable IR;
- generate a Noir package (one constrained `fn`, `assert`s);
- run `nargo compile` (ACIR) and `nargo execute` / `nargo test`;
- record source, ACIR, ABI, toolchain versions, and validation in artifact metadata.

### Road 2: FV-import refinement (ZK-import lane, gated on Road 1)

Once IR → Noir codegen exists, copy the EVM E-lane:

- add `reilabs/lampe` as an **opt-in lake dependency** (isolated target, like the EVM
  `EvmRefinement` target — keep the default build lampe/mathlib-free);
- write an adapter to Lampe's Noir `Step`/semantics;
- refine the portable IR against it for the fixture via the shared `CounterUniversal`
  induction (IR ⟷ Noir computed function; proving stays external).

## Non-Goals For The First Pass

- Do not add `noir` to the code registry before Road 1 codegen + capabilities are reviewed.
- Do not model the proving system (Barretenberg/Honk) — external, like `solc`.
- Do not start with Aztec's stateful contract model (notes/nullifiers) — pure-function
  circuit first.
- Do not start with unconstrained/Brillig bodies — constrained functions first.
- Do not begin the Lampe FV-import (Road 2) before Road 1 codegen produces a Noir artifact.

## Research Exit Criteria

Noir can leave Research only when we have:

- a reviewed target profile proposal and capability set;
- a decided first spike (Road 1 Noir package sourcegen) with a PureMath/Counter-like fixture;
- an artifact manifest schema (source, ACIR, ABI, toolchain, validation);
- a `nargo` toolchain requirement recorded in `docs/validation-gates.md`;
- at least one reproducible local command (`nargo compile` / `nargo test`);
- a recorded decision on when the Lampe FV-import (Road 2) is scheduled.
