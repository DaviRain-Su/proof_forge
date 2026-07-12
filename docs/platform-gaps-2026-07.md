# Platform Gap Analysis (2026-07)

Status: **Historical planning survey (archived 2026-07-12).** Current open
work must be represented in the implementation backlog.

The current planning corpus covers architecture convergence (Workstream 24),
formal verification (25), the unified testkit (26), allocator unification
(27), and the target portfolio (28). This page records the dimensions that
are **not yet planned anywhere** and would become expensive if the queued
work lands first. Each gap states why it must be planned *now*, its current
state in the repo, and the recommended next step. Items graduate into their
own RFC before implementation; backlog tracking is Workstreams 29–33.

Ordered by urgency (how soon queued work bakes in the wrong default).

## Gap 1: CLI product surface (`proof-forge build`) — Workstream 29

**Why now.** `ProofForge/Cli.lean` has grown to ~136 emit modes and ~130
flag patterns; every fixture and target multiplies flags (`--emit-counter-ir-psy`,
`--emit-counter-emitwat`, `--solana-clock-sysvar-elf`, …). Each conflict in
the 2026-07 consolidation was concentrated in this file, and testkit M4
(Workstream 26) is about to wire dozens of these modes into scenario
harnesses. If the testkit binds to the flag zoo, the flag zoo becomes API.

**Current state.** RFC 0009 is accepted and M1 has landed. The CLI now has
`Command`/`CliOptions`, target-first `build`/`emit` routing through the
compatibility layer, a real `check` verb, `--list-targets`,
`--list-fixtures`, and legacy alias/deprecation metadata. D-039 records that
this is a ratification of already-landed M1 code, not a pre-code freeze.

**Recommendation.** Do not reopen the surface. Execute the remaining
transition work: migrate scripts and testkit invocations to
`proof-forge build|emit|check --target <id> --fixture <id>` for M3/M4, keep
legacy flags as thin aliases for the compatibility window, and delete
`EmitMode` only after CI and docs no longer depend on the flag zoo.

## Gap 2: Versioning and compatibility policy — Workstream 30

**Why now.** The IR has 99 constructors and three coverage manifests already
gate its evolution — but only structurally. The strings `portable-ir-v0` and
artifact `format` fields exist with no stated rules: what is a breaking IR
change, what must a bump preserve, which artifact schema fields are stable
for external consumers (explorers, the future cloud platform), and what the
SDK promises contract authors across releases. Workstreams 26–28 all add
external consumers of these formats.

**Current state.** Ad-hoc version strings in `SbpfAsm.lean`/`Idl.lean`/CLI;
no semver policy for the SDK, IR, capability ids, or
`proof-forge-artifact.json` / `proof-forge-deploy.json` schemas.

**Recommendation.** A short RFC defining: (a) IR versioning rules tied to
the coverage-manifest gate (new constructor = minor, changed semantics =
major + migration note); (b) artifact/deploy schema versioning with a
"consumers must tolerate unknown fields" rule; (c) capability-id stability
(ids are append-only; meaning changes require a new id); (d) an SDK
deprecation policy. Cheap to write now, near-impossible to retrofit.

## Gap 3: Resource budgets as first-class gates — Workstream 31

**Why now.** The Tier-0 parity gate (D-034) is defined as "shared scenario
passes on three targets" — behavior only. A hypothetical contract could
pass Mollusk while exceeding Solana's default budget (200k CU/instruction),
and EVM/NEAR gas is currently listed under "not covered" in every
validation gate. Declaring parity without budgets risks declaring fake
parity, and codegen quality regressions have no tripwire.

**Current state (updated 2026-07-03).** D-040 and RFC 0010 made budgets part
of the Tier-0 gate. The testkit scenario schema now supports per-step budget
baselines with tolerance bands, and Gate G0 is closed for Counter and
ValueVault behavior/budget parity across `evm`, `solana-sbpf-asm`, and
`wasm-near`.

The original Solana direct-assembly baseline is still useful context:

| Entrypoint | Compute units |
|---|---:|
| `initialize` | 56 |
| `increment` | 63 |
| `get` (writes return data) | 163 |

That is Pinocchio-class efficiency (hand-optimized native Rust territory;
Anchor equivalents typically cost an order of magnitude more), and it is now
locked by scenario budgets instead of living only in prose. The remaining
work is P0 hardening: keep budget baselines current as maps, aggregates,
CPI-heavy lowering, and NEAR host behavior expand; replace the current
wasmtime-fuel NEAR proxy with a more precise host-gas model when that model
is implemented.

**Recommendation.** Treat budget regressions as product regressions for the
three primary chains. New target work remains frozen by D-045 until Gate P0
closes; after that, every target entering a shared scenario must add its
native budget dimension before it can claim parity.

## Gap 4: Deployment lifecycle, upgrades, and signing — Workstream 32

**Why now.** Deploy manifests exist (EVM `proof-forge-deploy.json` with
chain profiles and constructor args; Solana deploy packages with program
keypairs), but the lifecycle *after* first deployment is unmodeled, and the
chains disagree violently: EVM immutability vs proxy patterns, Solana
program upgrade authority (and its revocation), NEAR code redeployment on
the same account, Aleo `@noupgrade`. The Intent API currently cannot express
"this contract is upgradeable by X" — meaning every backend picks an
implicit, divergent default. That is a semantic-silence bug of exactly the
kind the platform promises to reject. Key management is still an open
question from RFC 0001 and blocks the cloud-platform story (D-010).

**Current state.** First-deploy manifests only; no upgradeability intent; no
signing boundary (who holds deploy/upgrade keys, how CI/live gates get
funded keys — currently ad-hoc per smoke script).

**Recommendation.** An RFC defining an upgrade-policy intent
(`immutable | authority(key) | governance(ref)`) that each target either
lowers honestly (Solana upgrade authority, EVM immutable-or-documented-proxy,
NEAR account-key policy, Aleo `@noupgrade`) or rejects at compile time; plus
a signing boundary: ProofForge emits unsigned transactions/manifests, key
custody stays outside (wallet/KMS), live gates document their throwaway-key
convention.

## Gap 5: Portable runtime error model — Workstream 33

**Why now.** `assert`/`assertEq` carry optional messages, and each backend
already invents its own failure surface: EVM reverts (no revert-reason
encoding today), Solana custom program errors / log lines, NEAR panics, Psy
circuit assertion failures. Clients and the testkit need to assert *which*
error occurred; once three more backends harden divergent conventions,
unifying costs a breaking change on every one.

**Current state.** Diagnostics at compile time are excellent; runtime errors
are stringly and per-chain. Testkit RFC asserts success traces but has no
error-expectation vocabulary yet.

**Recommendation.** Small RFC: portable error codes at the IR level
(assertion id + optional user code), per-target encoding table (EVM
`revert` with a compact ABI encoding, Solana custom error codes, NEAR panic
payload, Psy assertion index), and `expect.error = <code>` in testkit
scenarios. Pairs naturally with FV-5 (checked-arithmetic trap semantics).

## Gap 6: Unified client generation (DX) — Workstream 33 (second half)

**Why now.** Solana already generates IDL + TypeScript clients
(`Backend/Solana/Client.lean`); EVM emits ABI JSON; NEAR/Psy/Aleo emit
nothing client-facing. The "one contract, many chains" story is only real if
the *application developer* gets one client interface. Waiting lets each
backend grow a different client idiom, repeating the allocator/testkit
divergence pattern at the DX layer.

**Current state.** Per-chain artifacts with no shared client schema; web3
smokes hand-write per-chain call code.

**Recommendation.** Plan (not build yet) a client-schema layer: one
JSON description of entrypoints/types/errors derived from `ContractSpec`
(the IDL generalized beyond Solana), from which per-chain TS adapters are
generated. Defer implementation until after testkit M3 — the testkit
encoding adapters (selector/instruction/Borsh mapping) are the same logic
and should be written once, then shared with client generation.

## Explicit non-goals to record (so they stop being implicit)

- **Cross-chain interop/bridging** (same contract instances talking across
  chains): out of scope for the platform's current phase; deploying to many
  chains ≠ connecting them. Should be stated in RFC 0001's non-goals when
  next amended.
- **Fuzzing/property-based testing:** a future testkit extension (the
  scenario model must not preclude generated step sequences), not a current
  workstream.
- **Compiler performance:** no planning needed until build times hurt;
  revisit when the fixture registry (Gap 1) lands and `lake build` cost is
  measurable per backend.
- **i18n automation:** translation currently requires manual sync when
  `OLLAMA_API_KEY` is absent; acceptable, tracked inside Workstream 24.

## Sequencing hooks

- Gap 1 (CLI) M1 is done; M3/M4 must migrate testkit and scripts before the
  compatibility aliases are removed.
- Gap 3 (budgets) is implemented for Gate G0; keep it active as a P0
  regression gate and refine NEAR gas from fuel proxy to native model when
  available.
- Gap 5 (errors) should still land its scenario vocabulary before the
  next broad testkit schema freeze.
- Gaps 2 and 4 are independent of the testkit and can be planned in
  parallel by a docs-focused agent.
- Gap 6 waits for testkit M3 by design.
