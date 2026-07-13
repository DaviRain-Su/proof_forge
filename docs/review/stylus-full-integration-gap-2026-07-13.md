# Stylus Full Integration Gap Audit - 2026-07-13

## Executive Status

`wasm-arbitrum-stylus` has a locally executable general-contract research
backend. Canonical Core produces one checked `StylusPlan`; direct HostIO Wasm
is the CLI default, and pinned `stylus-sdk = 0.10.8` remains the explicit Rust
oracle. Recursive aggregate storage/resource work is closed locally, but the
target must remain at Research maturity because real Nitro evidence is still
open.

The active completion plan records 59 of 80 acceptance items complete. Three
queue packages remain: environment-blocked W5.2, externally limited W7.2, and
final integration. This audit is a gap ledger, not completion proof; the plan
and reproducible gates remain authoritative.

## Verified Baseline

| Surface | Evidence | Current status |
|---|---|---|
| Wide scalar semantics | `just stylus-wide-values`, `just stylus-wide-arithmetic` | planned u128 slice complete locally |
| ValueVault | `just stylus-value-vault-canonical` | Rust/direct/local runtime green; Nitro pending |
| Mapping/events and ERC-20 | `just stylus-nested-map`, `just stylus-token-differential`, `just stylus-token-evm-interop` | nested slots, standard events/selectors, lifecycle and rollback green locally |
| Aggregate ABI/storage | `just stylus-aggregate-differential`, `just stylus-aggregate-storage`, `just stylus-core-plan` | recursive calldata carriers plus bounded bytes/string/packed scalar-array storage green locally; indexed/composite array storage remains fail-closed |
| Remote calls | `just stylus-remote-call-differential` | Rust/direct normalized parity plus runner-only cache/frame/context vectors and local two-contract evidence green |
| Public artifact route | `just stylus-public-route`, `just stylus-cli-matrix` | direct default, explicit Rust oracle, no fallback, atomic bundles, exact ABI selectors, and evidence hashes green |
| Static integration | `just stylus-all`, `just test-manifest`, `just test-equivalence` | 26 Stylus gates registered once across four lanes; live Nitro remains separate; final post-rebase full rerun is deferred |

## Closed Packages

### W1 - Nested Storage and Event Layouts

Canonical composite maps retain ordered key types through Core and
`StylusPlan`. Rust and direct Wasm consume the same slot/event layouts, with
Foundry-derived nested-map and Transfer/Approval vectors.

### W2 - Canonical ERC-20 State Machine

The shared TokenSpec materializes through canonical Core into one Stylus plan.
Local direct/Rust evidence covers mint, transfer, approve, transferFrom,
unlimited allowance, rollback, standard client calldata, mappings, and logs.
Only the live Nitro portion remains under W5.

### W3 - Aggregate ABI, Storage, and Resources

Recursive dynamic calldata bounds, bytes/string short-long storage, bounded
packed scalar arrays, stale-word cleanup, corrupt-root/over-limit rejection,
maximum-page guards, Rust `stylus-test`, Direct-Wasm runner vectors, and a
Checked Canonical Core root-storage fixture are green. Indexed arrays,
fixed-bytes/uint256 public array carriers, and composite array storage remain
explicitly outside the accepted fragment rather than incomplete advertised
features.

### W4 - Remote-Call Parity

Generated Rust and direct Wasm emit the same normalized seven-step common
trace for call/static/delegate modes, success/revert, calldata/value, and
bounded results. Static-write rejection, delegate context, reentrancy, cache
transitions, and nested frames are explicitly runner-only where upstream
`stylus-test` exposes no equivalent observability. The live two-contract run
remains under W5.

### W6 - Direct-Wasm CLI Cutover

Direct Wasm is the default renderer and `--renderer rust-sdk` is explicit.
Bundles are atomically published and globally cleaned on failure. Cutover
evidence is fresh and identity-bound, and must include the pinned local Nitro
revision, doctor hash, one chain id, and per-gate transaction/artifact/summary
hashes. Missing evidence stays `unavailable` and cannot promote maturity.

## Open Packages

### W5.2 - Live Nitro Evidence (environment-blocked)

ValueVault, Token/mapping-events, RemoteCall two-contract, and Aggregate live
recipes plus a fail-closed final assembler are implemented and pass local
syntax/schema/product preflight. All live entrypoints now require a fresh ready
doctor before build/deploy. The current doctor is `ready=false`: Docker, the
pinned checkout, and local RPC are unavailable. Therefore no address, receipt,
gas/ink, or `final.json` evidence is claimed.

### W7.2 - CI and Release Evidence (partially external)

GitHub runs four independent optional Stylus static lanes and always uploads
artifacts, traces, evidence, and timings; failures also run the Nitro doctor.
Woodpecker packages and verifies the same workspace evidence, including doctor
JSON. Durable Codeberg publication still requires an externally configured
artifact sink and credentials. Real `final.json` generation remains gated by
W5.2.

### Final Integration

After external blockers are either cleared or recorded with exact evidence,
review the complete branch, rebase the main work branch, resolve conflicts, and
run the final full regression once. Feature iteration continues to use only
change-related gates.

## Critical Path

1. Run W5.2 when the pinned Nitro environment is available.
2. Configure the Woodpecker durable artifact sink for W7.2.
3. Perform final review, rebase, conflict resolution, and one full regression.
