# Stylus Full Integration Gap Audit - 2026-07-13

## Executive Status

The completion plan currently has 31 of 64 acceptance items checked (48%).
That number understates the foundation already built but accurately shows that
the target is not release-integrated. A useful engineering estimate is:

- compiler/plan/runtime foundation: about 60% complete;
- public default artifact and release integration: about 35-40% complete;
- remaining delivery: seven work packages, four of them large.

`wasm-arbitrum-stylus` must remain research maturity. The CLI still emits the
Rust SDK artifact by default, the registry still describes a Counter-only
fragment, and no current Nitro evidence authorizes a direct-Wasm cutover.

## Verified Baseline

| Surface | Current evidence | Honest status |
|---|---|---|
| Wide scalar semantics | `just stylus-wide-values`, `just stylus-wide-arithmetic` | Complete for the planned u128 slice |
| Canonical ValueVault | `just stylus-value-vault-canonical` | Rust/direct/local runtime green; Nitro evidence missing |
| Mapping/event layouts | `just stylus-mapping-events`, `just stylus-nested-map` | scalar and nested maps, ABI overrides, and standard Transfer/Approval layouts green |
| Canonical nested mapping | `just stylus-nested-map` | address-to-address-to-u128 semantics, plan keys, Rust SDK crate, direct Wasm, and local VM slot parity green |
| Canonical ERC-20 lifecycle | `just stylus-token-differential` | shared TokenSpec, canonical plan, mint/transfer/approve/transferFrom, rollback, edge vectors, and unlimited allowance green locally |
| Dynamic ABI | `just stylus-aggregate-differential` | bounded bytes/string parameter/return slice green after the plan-derived clear-bound fix |
| Remote calls | `just stylus-remote-call-differential` | modes, value, gas, bounded static/dynamic returns, revert, cache policy, nested local frames green |
| Full Lean build/docs | `lake build`, `just docs-check` | green at this checkpoint |

The audit found and repaired a dynamic-return regression: clearing a fixed 4096
bytes before ABI return encoding overwrote dynamic input calldata. The encoder
now obtains the clear bound from the producing function parameter or call
envelope.

## Remaining Work Packages

### W1 - Canonical Nested Storage and Full Event Layouts (complete)

Core now represents composite maps with `StateShape.mapN`, validates every key
in order, and gives logical semantics to the composite key. Both Stylus
renderers consume the same ordered `StylusStorageWordPlan.keyTypes`. The gates
pin nested slots with Foundry `cast index`, execute both direct-Wasm read/write
paths, compile the generated nested Rust SDK crate, and verify standard
`Transfer(address,address,uint256)` / `Approval(address,address,uint256)` logs.

### W2 - Canonical ERC-20 State Machine (large, now unblocked)

The shared TokenSpec now materializes through the existing ERC-20 stdlib into
canonical Core and one Stylus plan. Direct Wasm executes the complete local
lifecycle, edge cases, rollback, standard selectors/events, and unlimited
allowance; the generated Rust SDK crate compiles. Remaining work is normalized
abstract/Rust/direct runtime parity, the public token driver, EVM-client
interop packaging, and Nitro evidence.

### W3 - Aggregate Storage and General ABI Layout (large)

Bytes/string calldata and return carriers exist, but arrays, tuples, nested
tails, dynamic/short-long storage, and allocation/resource exhaustion do not.
Layout arithmetic must move into dedicated checked plan modules before this can
be called a general-contract fragment.

### W4 - Remote-Call Parity Closure (medium)

Direct/local execution is substantial. Remaining evidence is static-write
rejection, delegate caller/value/storage context, Rust call rendering/parity,
and a real two-contract Nitro scenario.

### W5 - Nitro Evidence for ValueVault, Token, Remote, and Aggregates (medium, environment-blocked)

`cargo-stylus` and `wat2wasm` are installed. Docker CLI exists but its daemon is
not running; `cast` is not on the current shell PATH. Live gates must persist
machine-readable address/transaction/result evidence and may not be replaced by
the Wasmtime runner.

### W6 - Direct-Wasm CLI Cutover (large, blocked by W1-W5)

`ProofForge.Cli.StylusArtifacts` still builds the pinned Rust crate and publishes
that Wasm. Required work includes explicit renderer selection, direct default,
plan/ABI/storage hashes, atomic WAT/Wasm/client metadata, evidence freshness,
and strict no-fallback tests.

### W7 - Unified Static CI and Release Evidence (medium, last)

There is no `stylus-all`, the full static suite is not registered in the
four-worker lane manifest, GitHub only runs the generated Rust Counter smoke,
and registry/docs are stale. CI artifacts and final evidence manifests come
after renderer cutover, not before it.

## Critical Path

Execute in this order:

1. W1 nested storage and full event vectors. Complete at `095ef266`.
2. W2 canonical ERC-20. Current next package.
3. W3 remaining aggregate layouts and resource limits.
4. W4 Rust/direct remote parity and context closure.
5. W5 Nitro evidence when the daemon/tool PATH is available.
6. W6 direct-Wasm CLI cutover.
7. W7 static CI, registry/docs, release evidence, and final review.

ValueVault Nitro can run opportunistically during W1-W4, but it must not reorder
the compiler critical path. Task checkboxes should only be closed by their named
runtime or live evidence, not by source inspection.
