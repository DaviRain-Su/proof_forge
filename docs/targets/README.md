# Target Notes

This directory contains target-family notes that sit below the RFCs and above
implementation tasks. They are meant to be edited as research turns into code.

Related: [Documentation index](../INDEX.md),
[RFC 0002](../rfcs/0002-target-implementation-design.md),
[Implementation backlog](../implementation-backlog.md),
[Design decisions](../decisions.md).

## Target Lifecycle

| Stage | Meaning |
|---|---|
| Research | We understand the chain model and toolchain shape, but no local backend exists. |
| Spike | A minimal artifact is being produced, usually for one Counter example. |
| Experimental | A target has SDK, build, and smoke tests, but capability coverage is narrow. |
| Supported | A target has stable CLI, artifact metadata, CI, docs, and shared scenario tests. |

## Stage Exit Criteria

- `Research` exits only when a target profile draft, required-tool list, and
  minimal spike acceptance criteria are documented.
- `Spike` exits only when a reproducible local command or script exists and
  the target note records the result.
- `Experimental` exits only when SDK/build/smoke coverage exists for a narrow
  capability set and docs name artifact metadata, CI or optional CI,
  capability support, and examples.
- `Supported` requires stable CLI, artifact metadata, CI, docs, and at least
  one shared scenario test.

**Experimental** does not mean "broken" — the three Gate P0 chains (`evm`,
`solana-sbpf-asm`, `wasm-near`) have scoped local/CI artifact and execution
gates while capability coverage remains narrower than a full chain SDK.

## Portfolio Scheduling Boundary

The sections below are an inventory of target notes, not a scheduling
authority. The primary-chain completion covenant (D-045) is closed: ProofForge
has signed off the scoped P0 local/CI gates for `solana-sbpf-asm`, `evm`, and
`wasm-near`. All three remain `Experimental`; this sign-off is not a universal
correctness or production-operations claim. The current backlog still puts CLI
M3/M4 target-first migration before Tier-1 M3/M4 advancement.

Use this page to answer "what exists in the repository?" Use
[target-roadmap.md](../target-roadmap.md) and
[gate-status.md](../gate-status.md) to answer "what may receive product
implementation work next?"

## Completed Primary Product Targets (Gate P0)

These three targets completed the D-045 implementation priority.

| Target | Stage | Scheduling status |
|---|---|---|
| [Solana sBPF Asm](solana-sbpf-asm.md) | Experimental | Priority 1 signed off; direct assembly route (`solana-sbpf-asm`), live deploy, and Pinocchio equivalence gates are green. |
| [EVM](evm.md) | Experimental | Priority 2 signed off; Yul/`solc`/Foundry/Anvil gates, EVM-compatible deployment metadata, semantic-plan hardening, and FV-4 anchors are green. |
| [Wasm-NEAR](wasm-near.md) | Experimental | Priority 3 signed off; EmitWat route, diagnostics, IR coverage, formal trace anchors, target-first local execution, artifact/deploy metadata, and offline host smoke are green. |

## Maintenance-Only Landed Inventory

These backends already have useful code or smoke coverage, but they are not
next unless a roadmap gate or explicit backlog slice promotes them. Allowed work
is limited to CI stability, security fixes, and documentation maintenance.

| Target | Stage | Scheduling status |
|---|---|---|
| [Psy DPN](psy-dpn.md) | Spike | Generated `.psy`/Dargo path stays maintained; no capability-completion push until a ZK/circuit lane is scheduled. |
| [Aleo Leo](aleo-leo.md) | Research | Counter/PureMath sourcegen and smokes stay maintained; no new ZK-app lane is currently scheduled. |
| [Stellar Soroban](stellar-soroban.md) | Counter MVP | `just soroban-promotion` / `soroban-public-route`; **custom offline bridge only**. Deep HostABI/Env work waits for D-056 (authoring cutover PR #104). Gap list and S0–S5 order live in the target note. |
| CosmWasm | Counter MVP | `just cosmwasm-promotion`; `execute_msg` stub; Gate G1a (M3/M4) not started. Same D-056 sequencing as Soroban for deep work. |

## Research inventory (docs only)

| Target | Stage | Scheduling status |
|---|---|---|
| [OpenVM](openvm-research.md) | Research | Sourced brief closed 2026-07-15 with **defer** on backend/registry; preferred future spike is Rust guest sourcegen if reopened after #104 and PSy/Aleo plan work. No target id. |

**Removed from `main` (2026-07-15, D-055):** `move-aptos`, `move-sui`, and
`wasm-cloudflare-workers` (including `ProofForge/Backend/Move`,
`ProofForge/Compiler/TS`, and related fixtures). Full history is preserved on
branch `archive/move-cloudflare-2026-07-15`.

## Sequencing gate (D-056)

Before opening large secondary-host epics (Soroban Env, CosmWasm M3/M4):

1. Land [PR #104](https://github.com/DaviRain-Su/proof_forge/pull/104) —
   direct authoring cutover + primary-triad native differential — onto current
   `main`.
2. Keep product path on Authored → Canonical Core → target-owned plans.
3. Only then schedule Soroban S0+ or CosmWasm message/reply depth.

## Docs-Only Parked Research

These notes preserve research results, but they are not an active execution
queue. They stay docs-only until their roadmap enabler opens and a specific
spike is scheduled.

| Target | Family | Current boundary |
|---|---|---|
| (historical Move/Aptos/Sui notes) | removed from `main` | See `archive/move-cloudflare-2026-07-15` |
| [Internet Computer](internet-computer.md) | Wasm host | Requires the Wasm-host split plus an async/inter-canister design note. |
| [Algorand AVM](algorand-avm.md) | Source package generation | Parked behind a later sourcegen-lane exit. |
| [Cardano Plutus/Aiken](cardano-plutus-aiken.md) | eUTXO validator sourcegen | Parked behind a later sourcegen-lane exit. |
| [Tezos Michelson/LIGO](tezos-michelson-ligo.md) | Source package generation | Parked behind a later sourcegen-lane exit. |
| [Starknet Cairo](starknet-cairo.md) | Cairo/Sierra/CASM sourcegen **+ FV-import** | First non-Move sourcegen pick after Aptos; **ZK-import group** — has a Lean 4 semantics (`starkware-libs/formal-proofs`) for IR↔Cairo refinement once codegen lands. |
| [Noir (Aztec)](noir-aztec.md) | ZK-circuit sourcegen **+ FV-import** | **ZK-import group** — has a Lean 4 semantics (Reilabs `lampe`); gated on IR→Noir codegen. Not in the repo yet. |
| [TON TVM](ton-tvm.md) | TVM sourcegen | Parked behind a later sourcegen-lane exit. |
| [Bitcoin Script/Miniscript](bitcoin-script-miniscript.md) | Policy family | Opens only when the separate `policy.*` lane is scheduled. |
| [Zcash Shielded](zcash-shielded.md) | Privacy UTXO / ZK payment | Follows a working Bitcoin policy lane. |
| [Bitcoin Cash CashScript](bitcoin-cash-cashscript.md) | UTXO script/covenant sourcegen | Follows the Bitcoin policy lane. |
| [Kaspa Toccata](kaspa-toccata.md) | UTXO covenant / based app | Parked behind the policy/ZK lane decision. |

## Superseded or Reference Routes

| Route | Status | Notes |
|---|---|---|
| Solana sBPF-linker | Superseded | Historical `solana-sbpf-linker` route; replaced by `solana-sbpf-asm` (D-026). |
| Solana Zig fork | Reference only | External reference from `solana-sdk-mono`; not the product path. |

## Documents

- [EVM](evm.md)
- [Wasm family](wasm-family.md)
- [Wasm-NEAR](wasm-near.md)
- [Cloudflare Workers target](cloudflare-workers.md)
- [Stellar Soroban target](stellar-soroban.md)
- [Internet Computer target](internet-computer.md)
- [Algorand AVM target](algorand-avm.md)
- [Solana sBPF Asm](solana-sbpf-asm.md) — canonical direct-assembly route (`solana-sbpf-asm` target id, D-026)
- [Solana sBPF](solana-sbf.md) — superseded Zig/sbpf-linker route (`solana-sbpf-linker` target id)
- [Move family](move-family.md)
- [Cardano Plutus/Aiken target](cardano-plutus-aiken.md)
- [Tezos Michelson/LIGO target](tezos-michelson-ligo.md)
- [Starknet Cairo target](starknet-cairo.md)
- [Noir (Aztec) target](noir-aztec.md)
- [Aleo Leo target](aleo-leo.md)
- [TON TVM target](ton-tvm.md)
- [Bitcoin Script/Miniscript target](bitcoin-script-miniscript.md)
- [Zcash Shielded target](zcash-shielded.md)
- [Bitcoin Cash CashScript target](bitcoin-cash-cashscript.md)
- [Psy DPN ZK target](psy-dpn.md)
- [Kaspa Toccata target](kaspa-toccata.md)
