# Project Completion Roadmap — what's done, what's left, agent handoff (2026-07-08)

> Single hand-off page: the current state of ProofForge's FV + correctness + breadth work,
> in phases an agent can execute IN ORDER. Each item points to its detailed task card.
> Detailed plans: [FV target-semantics](2026-07-07-fv-target-semantics.md),
> [ZK sourcegen](2026-07-08-zk-sourcegen-spike.md),
> [execution-plan §7](../../zh/execution-plan-2026-07.md),
> [platform gaps](../../platform-gaps-2026-07.md).

## ✅ DONE — the big achievement: three-chain universal FV

Machine-checked, universally-quantified (`∀ safe input`) IR↔target refinement, green, no `sorry`:

- **EVM** — against `powdr-labs/evm-semantics` (import; heavy ~13k lines, but strongest trust —
  powdr is conformance-tested vs `ethereum/tests`).
- **Solana** — against a self-built sBPF interpreter (light ~6k lines; Counter universal C-proof +
  ValueVault genericity 283 thms + full-opcode audit; two-hop trust via Mollusk/Surfpool).
- **WASM/NEAR** — Counter universal C-proof CLOSED + green; ValueVault Wasm abstract-core
  trace + canonical anchor landed; CosmWasm host dispatch + chain-axis proof
  (`counterCosmWasm_*_simulates`) landed + smoke gated in `just check`. WASM-5 done.

The self-build path (Solana/WASM) is ~⅓ the size of the import path (EVM) and builds in seconds —
that asymmetry is settled and expected. This is the platform's differentiator, delivered on the 3
primary chains.

## Phase 1 — Finish the FV C-proof lane (DONE — 2026-07-08) — 1 agent

WASM-5 (the double genericity test) is now closed on both axes:

- **ValueVault WASM (contract axis):** `ValueVaultWasmExec.lean` /
  `ValueVaultWasmRefinement.lean` close the abstract-core path — `valueVaultWasm_step_simulates`
  (all 7 entrypoints), `valueVaultWasm_trace_simulates` (arbitrary calls), `after_initialize`,
  and the `initialize 10 → deposit 5 → getNetValue` full-prefix anchor. This is the **abstract-core
  route** (relation-level `canonicalCoreStorage` + one-step simulate + trace lift), intentionally
  lighter than Solana's 283 per-instruction theorems — the asymmetry is by design, not a gap.
- **CosmWasm (chain axis — the killer test):** `CounterCosmWasmRefinement.lean` proves Counter
  reuses the SAME host-agnostic `counterWasmCoreTraceStep` with only the host swapped
  (`counterCosmWasm_*_simulates` + `counterCosmWasm_host_db_write_step_preserves_rel`).
  `WasmInterpreter.runHostCall` dispatches `.cosmWasm` → `runCosmWasmHostCall`
  (`db_read`/`db_write`/`set_return_data`). Smoke gate `just wasm-cosmwasm-refinement-smoke`
  (in `just check`) is green.
- Card: WASM-5 in [FV target-semantics plan](2026-07-07-fv-target-semantics.md).
- **Exit:** all 3 chains have complete universal C-proof + double genericity, green. ✅

## Phase 2 — Close the Track 0 correctness bugs (IMPORTANT — FV did NOT touch these) — 1 agent

The FV proves "IR ⟷ target", but the **IR itself still has the original-review bugs**. Fixing them
is what makes the FV meaningful (you want to prove a *correct* IR, not one with silent
divergences). **All three verified STILL OPEN (2026-07-08):**

- **0.1 overflow, node-level** — DONE (2026-07-08). `IR.Expr.add/.sub/.mul` now carry an
  `overflowChecked : Bool := true` field (default checked, matching Solidity 0.8 / EVM
  semantics). `Builder.add/sub/mul` and `Surface.add/sub/mul` default to `:= true` and
  forward to the constructor; `+!`/`-!`/`*!` use this default. The EVM lowering reads the
  per-node flag (`arithExpr oc op` in `Backend/Evm/ToYul/Helpers.lean`) and emits
  checked-revert (`__pf_checked_*`) when `true`, wrapping Yul builtins when `false`.
  `ExprPlan.checkedArith` carries the flag through to the Yul emit path
  (`Backend/Evm/ToYul/Effect.lean`). Per the cross-target portability decision (wrap on
  non-EVM), `Expr.capabilities` does **not** emit `.checkedArithmetic` from the node flag
  (so a portable contract using `+!` still resolves to all targets and wraps on
  Solana/NEAR, which ignore `oc`). The module-level `Module.overflowChecked` remains the
  capability gate path used by FV-5 (`checkedCounterModule` fixture). All existing gates
  green: `just evm-semantic-plan`, `just fv5-overflow-smoke`, `just value-vault-wasm-refinement-smoke`,
  `just solana-lean`, `just shared-validate-smoke`, `just ir-counter-semantics-smoke`,
  `just counter-universal-refinement-smoke`. (Note: `just docs-check` remains red as a
  pre-existing `docs/targets/README.md` translation-sync staleness, now also flagging
  `docs/capability-registry.md` whose `arith.checked` section was updated to describe the
  new node-level field.)
- **0.2 capability derivation** — `capabilityCallsForSpec` is intent-OR-module (`if calls.size == 0`);
  module capabilities silently drop when intents exist, so `resolveSpec` can return `.ok` for a
  module using an unsupported capability. Fix: `intent ∪ module` (dedup). File: `Target/Adapter.lean`.
- **0.3 `nearCrosscallInvokePool`** — maps to generic `.crosscallInvoke`; the capability layer
  can't reject it on EVM/Solana (only a hardcoded Validate arm does). Fix: give it a unique
  `.nearPromise` capability (or move it to an extension node per D-027). File: `IR/Contract.lean`.
- Card: Track 0 in [execution-plan §1](../../zh/execution-plan-2026-07.md).

## Phase 3 — Complete the FV foundation (Track 1 remainder) — 1 agent

- **1.4 supported-fragment predicate**, generalized beyond Counter, + the two theorems
  (`capabilityAccept ⟹ fragment`, `fragment ⟹ lowering-total`) — replaces the Python coverage
  manifest scripts with proofs.
- **1.5 ownership soundness (FV-3)** — total-ize `IR/Ownership.lean`; prove no-use-after-release,
  no double-release (justifies the divergent `release` lowerings).
- **1.6 native_decide→decide audit** — downgrade what can be kernel-checked; add a TCB doc entry
  ("EVM trusts powdr + `native_decide`; self-built targets trust the interpreter + the external
  differential gate").
- **1.7 FV-8 user invariants (product differentiator)** — authors state invariants next to
  `contract_source`, proven pre-codegen against the IR semantics; turn `ValueVaultInvariant` from a
  worked example into a reusable authoring surface. **Highest product value in this phase.**

## Phase 4 — Breadth (after the primaries are solid) — parallelizable

- **WASM host families** — add Soroban / MultiversX / Casper / … hosts, each a thin `*Host.lean`
  reusing the SAME `WasmExec` (one CosmWasm host already serves the whole Cosmos ecosystem). Order
  + fit: the WASM host-family map in [FV target-semantics plan](2026-07-07-fv-target-semantics.md).
- **ZK lane** — Road 1 codegen (Noir `NR-1..4` first — pure-function, cleanest — then Cairo
  `CR-1..4`), then Road 2 FV-import (Cairo→`starkware-libs/formal-proofs`, Noir→`reilabs/lampe`,
  copying the EVM E-lane; each ZK target has a ready Lean 4 semantics). Card:
  [ZK sourcegen spike](2026-07-08-zk-sourcegen-spike.md); target notes:
  [noir-aztec](../../targets/noir-aztec.md), [starknet-cairo](../../targets/starknet-cairo.md).

## Phase 5 — Platform gaps + structural debt (docs-first, parallelizable)

- **WS30** versioning/compat policy · **WS32** deploy lifecycle / upgrade-policy intent / signing ·
  **WS33a** portable runtime error model · **WS33b** unified client generation (the "调用文档"
  layer). Scoped in [platform-gaps-2026-07](../../platform-gaps-2026-07.md) +
  [execution-plan §3/§4](../../zh/execution-plan-2026-07.md).
- **Structural debt:** finish RFC 0014 `LoweringError` instance migration · rename `Lean.Evm` →
  `ProofForge.*` · CLI flag-zoo → target-first M3/M4.

## Recommended order for agents (hand each agent ONE phase, or one task within it)

1. **Phase 1 (WASM-5)** — ✅ CLOSED 2026-07-08: both axes landed + gated.
2. **Phase 2 (Track 0 bugs)** — real shipping bugs, small + high value; makes the FV meaningful.
3. **Phase 3 (FV foundation)** — `1.7` FV-8 is the product differentiator; `1.4/1.5/1.6` harden the TCB.
4. **Phase 4 / 5** — parallelizable once 1–3 land; ZK + client + platform gaps are docs-first, low risk.

Discipline that held for EVM/Solana/WASM and must continue: generic exec layers carry **0 contract
names**; every universal theorem is **closed** (obligations constructed, not hypothesized) and
**green**; **no `sorry`**; self-built targets **keep the external differential gate** (Mollusk /
Surfpool / wasmtime) for the "interpreter ≈ real VM" hop.
