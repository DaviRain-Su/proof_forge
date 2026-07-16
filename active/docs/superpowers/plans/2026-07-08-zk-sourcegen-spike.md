# ZK Sourcegen Spike Plan — Road 1 codegen for the ZK-import lane (Noir first, then Cairo)

> **For agentic workers.** Recommended sub-skill: `superpowers:subagent-driven-development`
> — one subagent per task, review between tasks. Same task format as the FV target-semantics
> plan: **① Read first · ② Context to load · ③ Do · Acceptance · Depends on.**
>
> This is the **Road 1 codegen prerequisite** for the ZK-import lane. Cairo and Noir each have
> a Lean 4 semantics (`starkware-libs/formal-proofs`, `reilabs/lampe`), but you **cannot refine
> the IR against an artifact that does not exist** — codegen must land first. Road 2 (the
> Lampe/formal-proofs FV-import) is scoped in the ZK lane of
> [2026-07-07-fv-target-semantics.md](2026-07-07-fv-target-semantics.md); do NOT start it here.
>
> Target notes: [noir-aztec](../../targets/noir-aztec.md),
> [starknet-cairo](../../targets/starknet-cairo.md).

## Background (read once)

Mirror the proven **Aleo/Psy sourcegen spike** pattern — do NOT invent a new shape:

```text
Compiler/<Lang>/ (AST + Printer)  →  Backend/<Lang>/IR.lean (IR → AST lowering)
  →  Cli/Fixture.lean whitelist + emit route  →  Examples/<Lang>/*.golden.<ext>
  →  scripts/<lang>/*-smoke.sh (native toolchain, skip-if-absent)
```

Reference implementation to copy: `ProofForge/Compiler/Leo/` (AST/Printer/Emit) +
`ProofForge/Backend/Aleo/IR.lean` (IR → Leo) + `Examples/Backend/Aleo/PureMath.golden.leo` +
`scripts/aleo/pure-math-smoke.sh`. `ProofForge/Compiler/Psy/` is a second, more compact ZK
printer example.

**Fixture — start with a PURE FUNCTION, not a stateful contract.** Noir is stateless per
proof. Use `ProofForge/IR/Examples/PureMath.lean` (checked arithmetic + `assert`) — the same
fixture Aleo's `pure-math` spike uses. **No storage, no events, no contract model** in Road 1.

**Non-goals (Road 1):** the proving backend (Barretenberg / `nargo prove` / STARK), Aztec
state (notes/nullifiers), unconstrained/Brillig bodies, and the Lampe FV-import (Road 2).

## Noir Road 1 — tasks NR-1 → NR-4 (do this first — cleanest, pure-function)

### Task NR-1 — Noir AST + printer (`Compiler/Noir/`)

- **① Read first:** `ProofForge/Compiler/Leo/AST.lean` + `Printer.lean` (the mirror);
  [noir-aztec note](../../targets/noir-aztec.md); Noir syntax ([noir-lang.org/docs](https://noir-lang.org/docs)).
- **② Context to load:** `ProofForge/Compiler/Leo/` (AST/Printer/Emit structure);
  `ProofForge/Compiler/Psy/` (compact ZK printer).
- **③ Do:** create `ProofForge/Compiler/Noir/AST.lean` + `Printer.lean` — a typed AST for the
  Noir subset (a `fn` with typed params/return, `let`, arithmetic/comparison expressions,
  `assert`, `Field`/`u64` types) and a printer that renders valid `.nr` source. Register in
  `ProofForge.lean`.
- **Acceptance:** the printer renders a hand-built PureMath-shaped `fn` to `.nr` text; a
  `#check`/golden smoke passes; `lake build` green.
- **Depends on:** none.

### Task NR-2 — IR → Noir lowering (`Backend/Noir/IR.lean`)

- **② Context to load:** `ProofForge/Backend/Aleo/IR.lean` (the mirror — IR → Leo);
  `Compiler/Noir` (NR-1); `ProofForge/IR/Examples/PureMath.lean` (the fixture);
  `ProofForge/IR/Contract.lean` (IR node set).
- **③ Do:** create `ProofForge/Backend/Noir/IR.lean` lowering the PureMath IR fixture to the
  Noir AST — pure entrypoints (params/return), checked arithmetic (`.add`/`.sub`/`.mul` → Noir
  arithmetic with the appropriate range/overflow `assert`s), `assert`. **Reject**
  storage/events/crosscall (Road-1 non-goals) with a clear diagnostic.
- **Acceptance:** `renderModule PureMath.module` produces `.nr` source matching a golden
  fixture; green.
- **Depends on:** NR-1.

### Task NR-3 — CLI emit route + golden fixture

- **② Context to load:** `ProofForge/Cli/Fixture.lean` (the whitelist — mirror the `aleo-leo`
  entries: `.leo` format at :109/:125, target at :143/:158, per-fixture at :210-211);
  `ProofForge/Cli.lean` (emit compile functions); `Examples/Backend/Aleo/PureMath.golden.leo` (mirror).
- **③ Do:** add a `.noir` format + `noir` target id + `("noir", "pure-math", .noir) => true`
  to `Fixture.lean`; add the emit compile function in `Cli.lean`; land
  `Examples/Noir/PureMath.golden.nr`. The command
  `proof-forge emit --target noir --fixture pure-math --format noir -o build/noir/PureMath.nr`
  must produce the golden.
- **Acceptance:** the emit command produces `PureMath.nr` == golden; a `Tests/CliTargetFirst`-
  style regression case passes; green.
- **Depends on:** NR-2.

### Task NR-4 — smoke script (native `nargo`, skip-if-absent)

- **② Context to load:** `scripts/aleo/pure-math-smoke.sh` (the mirror — note its skip-if-`leo`-
  absent exit-127 behavior); `docs/validation-gates.md`.
- **③ Do:** `scripts/noir/pure-math-smoke.sh` — wrap the emitted `.nr` in a `nargo` package, run
  `nargo compile` (ACIR) + `nargo execute` / `nargo test`, write + validate
  `proof-forge-artifact.json` (source, ACIR path, ABI, toolchain versions). **Skip gracefully
  if `nargo` is absent** (report the generated source, exit non-fatally — like the Aleo smoke).
  Record the gate in `docs/validation-gates.md` and add a `just noir-pure-math-smoke` recipe.
- **Acceptance:** `just noir-pure-math-smoke` emits `.nr` + validates metadata; with `nargo`
  present it compiles ACIR + tests; without, it skips gracefully. This closes Noir's Research →
  Spike exit criteria (update the [noir-aztec note](../../targets/noir-aztec.md) Status).
- **Depends on:** NR-3.

## Cairo Road 1 — same shape, subsequent (Scarb/Sierra, CONTRACT fixture)

Cairo mirrors NR-1 → NR-4 but differs: (a) `Compiler/Cairo/` (Cairo AST/printer); (b) Cairo is
a **stateful contract** model (storage), so the first fixture is the **Counter contract**, NOT
a pure function — heavier than Noir; (c) toolchain is `scarb build` → Sierra/CASM (+ Starknet
Foundry `snforge`), not `nargo`; (d) target id `starknet-cairo` (already reserved). **Do Noir
first** (pure-function, simpler); schedule Cairo after Noir NR-4 proves the ZK sourcegen shape.
Tasks CR-1 (Cairo AST/printer) → CR-2 (IR → Cairo, Counter contract) → CR-3 (CLI emit + golden
`Counter.cairo`) → CR-4 (`scarb build`/`snforge` smoke, skip-if-absent).

## Then Road 2 (FV-import) — only after Road 1 produces an artifact

Once `nargo compile` produces ACIR for the Noir fixture (NR-4) — or `scarb build` produces
Sierra for Cairo — the ZK-import refinement (Road 2) copies the EVM E-lane exactly: opt-in lake
dep on `reilabs/lampe` (Noir) / `starkware-libs/formal-proofs` (Cairo) → adapter to its `Step`
→ refine IR ⟷ target for the fixture via the shared `CounterUniversal` induction. The proving
system stays external (non-goal, like `solc`). Scoped in the ZK lane of the FV target-semantics
plan; do not start before Road 1 lands.
