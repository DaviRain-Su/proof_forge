# Z1 fallback policy — Psy DPN direct lower (2026-07-10)

## Decision (Z1.6)

**Go / partial-go for Counter; no-go for general IR→DPN.**

| Path | Status | Role |
|------|--------|------|
| `.psy` sourcegen (`--format psy`) | **Required** general front-end | All fixtures; dargo compile/execute oracle |
| Direct DPN JSON (`--format dpn-json`) | **Bootstrap Counter only** | Measured lower artifact for Z1/B1; matches golden |
| Full opcode selection from arbitrary IR | **Not claimed** | Blocked on method_id tables, state_command encoding, assert packing |

## Why not full direct lower yet

1. **method_id** values are dargo/Psy ABI hashes — PF must either reimplement the
   exact hash or import a table; Counter IDs are pinned from dargo goldens.
2. **State commands** (`GetSelfUserCurrentContractStateSlotSingle`,
   `SetContractStateSlotSingle`, resolution indices) are not a trivial
   projection of portable IR storage ops.
3. **Assertions / events / maps** expand the DAG far beyond Counter’s 9 ops.

## Honesty rules

- Never set `validation.dargoCompile=passed` without running dargo.
- `primaryOutput=dpn-bytecode-json` only when compile passed **or** when emitting
  the direct Counter lower that is explicitly labeled Z1.4 bootstrap.
- Benchmarks measure DPN JSON (size / optional dargo metrics), not a fake
  “bitcode” intermediate.
- Product sources remain fail-closed for `psy-dpn` until a real general lower
  exists (existing product gate).

## Next increments (not Z1.4 scope)

- Derive Counter document from IR ops instead of a hand-encoded golden twin.
- Expand Arithmetic/Assert direct lower using their goldens.
- Optional: shell out to dargo as a backend (not “direct”) for non-Counter.

## Commands

```sh
just psy-dpn-goldens   # Z1.1
just psy-dpn-printer   # Z1.3
just psy-dpn-direct    # Z1.4 Counter emit == golden
```
