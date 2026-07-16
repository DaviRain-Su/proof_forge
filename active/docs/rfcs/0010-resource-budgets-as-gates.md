# RFC 0010: Resource Budgets as Gates

Status: **Accepted**
Date: 2026-07-03
Implemented: 2026-07-03

## Problem

The Tier-0 parity gate (D-034) is currently defined as "shared scenario passes
on three targets" — behavior only. A contract could pass Mollusk while
exceeding Solana's default compute budget, or pass revm while consuming far
more EVM gas than a production deployment can afford. Declaring parity without
budgets risks declaring fake parity, and codegen quality regressions have no
tripwire.

The direct-assembly Solana route is already extremely efficient today. Locking
those numbers in now turns an accidental advantage into an intentional,
measured contract:

| Entrypoint | Compute units |
|---|---:|
| `initialize` | 56 |
| `increment` | 63 |
| `get` (writes return data) | 163 |

ELF size: 1336 bytes (Mollusk 0.13.4, loader v3, 2026-07-02).

That is Pinocchio-class efficiency. The first budget gate should preserve it.

## Summary

Extend the testkit scenario schema with optional per-step resource budgets:

```toml
[[step]]
call = "increment"
[step.expect.return]
u64 = 1
[step.expect.budget]
solana_cu = { baseline = 63, tolerance = 0.05 }
evm_gas = { baseline = 25000, tolerance = 0.10 }
near_gas = { baseline = 50000000000000, tolerance = 0.20 }
```

- `baseline` is the measured cost on a reference toolchain version.
- `tolerance` is a relative band (e.g. `0.05` = ±5%).
- Harnesses report the actual budget consumed for each step.
- The runner fails a step when the actual cost exceeds `baseline * (1 + tolerance)`.
- A missing `budget` table means "not asserted yet"; the runner still reports
the measured value so authors can lock baselines.

This applies to the three Tier-0 targets first. Budget assertions become part
of the Gate G0 definition of done.

## Design Goals

- **Codegen quality is a testable gate**, not an afterthought.
- **Baselines are pinned with toolchain versions** so upgrades are explicit.
- **Tolerance bands absorb noise** from host timing, allocator state, and small
  optimizer changes without letting silent regressions through.
- **Budgets are optional per step** so scenarios can be added before baselines
  are measured.

Non-goals:

- This RFC does not define protocol fee modeling or transaction pricing.
- It does not replace the formal verification roadmap (FV-5 checked arithmetic
  is complementary).
- It does not add new fixtures; it adds budget fields to existing scenarios.

## Budget Metrics per Target

| Target | Metric | Source |
|---|---|---|
| `evm` | `gas` | revm `gas_used` after step execution |
| `solana-sbpf-asm` | `cu` | Mollusk `compute_units_consumed` |
| `wasm-near` | `near_gas` | wasmtime instruction / host-call cost model or NEAR host gas counter |

Future targets add their own metrics (e.g. `move_gas`, `wasm_instr`) without
changing the schema shape.

## Schema Extension

The existing `Expectation` struct gains a `budget` field:

```toml
[step.expect.budget]
evm_gas = { baseline = 25000, tolerance = 0.10 }
solana_cu = { baseline = 63, tolerance = 0.05 }
near_gas = { baseline = 50000000000000, tolerance = 0.20 }
```

Compact form for exact tolerance of zero:

```toml
[step.expect.budget]
solana_cu.baseline = 63
```

Shorthand (baseline only, default tolerance 0.0):

```toml
[step.expect.budget]
solana_cu = 63
```

The runner serializes budget assertions into the report so CI diffs show both
behavior and budget results.

## Baseline Locking

Baselines are recorded in the scenario file, not in a separate manifest. Each
baseline implicitly belongs to a reference toolchain recorded in the scenario
metadata:

```toml
[scenario]
name = "counter"
fixture = "counter"
targets = ["evm", "solana-sbpf-asm", "wasm-near"]
reference.toolchain.mollusk = "0.13.4"
reference.toolchain.revm = "<from Cargo.lock>"
reference.toolchain.wasmtime = "<from Cargo.lock>"
```

When a toolchain upgrade changes a baseline, the scenario file is updated in
the same PR that bumps the dependency. This makes baseline changes reviewable
and bisectable.

## Harness Changes

Each `ChainHarness` returns a `CallOutcome` with an optional budget field:

```rust
pub struct CallOutcome {
    pub sequence: u32,
    pub call: String,
    pub return_hex: Option<String>,
    pub return_u64: Option<u64>,
    pub return_u32: Option<u32>,
    pub return_bool: Option<bool>,
    pub allocations: Option<u64>,
    pub reuses: Option<u64>,
    pub deallocations: Option<u64>,
    pub budget: Option<BudgetOutcome>,
    pub raw_line: String,
}

pub struct BudgetOutcome {
    pub evm_gas: Option<u64>,
    pub solana_cu: Option<u64>,
    pub near_gas: Option<u64>,
}
```

- `harness-solana` reads `result.compute_units_consumed` from Mollusk.
- `harness-evm` reads `tx_result.gas_used()` from revm.
- `harness-near` uses a host-side gas counter in `runtime/offline-host`; if
  exact NEAR gas is not available, the harness reports an approximate
  instruction/host-call cost and marks the assertion as `info-only` until the
  model improves.

## Runner Behavior

1. Parse the scenario and expand the target matrix as today.
2. After each step, collect the actual budget from the harness.
3. If the scenario asserts a budget for that step/target, compare actual
   against `baseline * (1 + tolerance)`.
4. If the scenario does not assert a budget, print the measured value as an
   informational line so authors can copy it into the scenario.
5. Cross-target trace equivalence still compares observable outcomes only;
   budgets are per-target, not cross-target.

## Acceptance Criteria

- `testkit/scenarios/counter.toml` includes locked baselines for the three
  Tier-0 targets.
- A deliberate regression in Solana CU or EVM gas fails `just testkit`.
- The runner prints measured budget for every step, even when no baseline is
  asserted.
- Baseline changes are reviewable in the scenario TOML, not hidden in lock
  files.

## Milestones

1. **M1:** Extend scenario schema and `CallOutcome` with budget fields; add
   Solana CU reporting (Mollusk already exposes this).
2. **M2:** Add EVM gas reporting through revm and lock Counter baselines.
3. **M3:** Add NEAR gas reporting via the offline host; lock Counter baselines
   or mark as `info-only` if the model is approximate.
4. **M4:** Update Gate G0 definition (target-roadmap + validation-gates) so
   shared-scenario parity requires budget assertions.

## Pairing with Runtime Error Model

Workstream 33 extends the scenario schema with `expect.error`. The budget and
error schema changes should land together so testkit undergoes only one schema
migration. Coordinate with RFC 0011 (Workstream 33).

## Non-goals

- No protocol-fee or transaction-cost modeling.
- No cross-target budget comparison (EVM gas is not comparable to Solana CU).
- No artifact-size budgets yet; ELF/bytecode size stays in artifact metadata
  and golden files.

## Related

- [RFC 0007](0007-unified-rust-test-framework.md): testkit scenario model.
- [RFC 0009](0009-cli-product-surface.md): CLI surface testkit invokes; budget
  reporting must work through the new surface.
- [Workstream 26](../implementation-backlog.md#workstream-26-unified-rust-test-framework-testkit): testkit M2/M3 schema freeze.
- [Workstream 33](../implementation-backlog.md#workstreams-2933-platform-hardening-planning-first): runtime error model + client generation.
- [target-roadmap.md](../target-roadmap.md): Tier-0 parity gate D-034.
