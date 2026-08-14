# Agent Note: Verify with focused `lake env lean`, not shard exes

Status: implemented

## Problem

`proof_forge_next_tests_shard_typed` looks like a cheap typed-suite target.
It is a native exe: Lake compiles the whole `ProofForgeV2` library to C and
runs `clang -O3`. Opening [`Tests.lean`](../../../../Tests.lean) in the
editor starts `lake setup-file` on the full materialization import graph
(Solana CPI, EVM smoke, NEAR, CosmWasm, Psy).

On 2026-08-15 those two overlapped. Load went to ~61 on 12 cores, swap to
~18.7 GiB, and the machine appeared wedged. A two-day orphan
`lean …/CosmWasm/EmitIRV1.lean` was leftover from an earlier unclean
build. The S5 / Sem00x edits themselves were not the cost.

## Decision

Ordinary agent verification is a focused interpreter run of the suite that
owns the change, for example:

```bash
lake env lean Tests/Semantic/Sem002ShapeV1.lean
```

Do **not**:

- `lake build proof_forge_next_tests_shard_*`
- `lake build proof_forge_next_tests` / `proof_forge_next_fast_tests` as a
  habit after a leaf pin
- keep [`Tests.lean`](../../../../Tests.lean) or [`Tests/Fast.lean`](../../../../Tests/Fast.lean)
  open in the Lean server while a Goal is compiling
- `pkill` every `lean` / `lake serve` (those are the editor)

Stop a known `lake build` / compile-only `lean` PID. Leave `lake serve` and
`--worker` alone unless the user asks. Docs-only slices use `just docs-check`.

## Alternatives considered

- **Always build the typed shard because Sem00x is registered there** —
  rejected: registration makes ordinary CI reach the pin; it is not the
  local loop. The exe forces whole-library codegen.
- **Open `Tests.lean` so LSP typechecks the new import** — rejected: that
  file imports the materialization universe. Use the suite file.
- **Record every `lake` invocation as an Agent Note** — rejected: Amp
  threads and `.orca/` already hold run logs. This tree stores the ban,
  not the transcript.

## Consequences

Local Goal / Amp slices stay on one or two Lean processes. CI still builds
shards; that cost belongs on CI machines. Re-opening a full shard build on
the laptop requires an explicit user request.
