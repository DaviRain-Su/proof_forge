# Native Differential Contracts

This directory is test infrastructure. It is not part of the compiler, shared
IR, Canonical Core, or a target plan.

The v1 contracts separate four facts:

- `reference-provenance`: independent source, origin, revision, license, and
  pinned toolchain;
- `logical-scenario`: stable step IDs, required observations, and narrowly
  scoped allowed divergences;
- `normalized-observation`: observed values, coverage, runner status, and the
  fail-closed semantic result;
- `runner-result`: typed logical accounts/actors/clocks, per-step observations,
  and explicit coverage emitted by one target runner;
- `inventory`: every tracked reference, runner, scenario, report catalog, and
  comparison gate with an honest maturity label.

`scripts/differential/runner.py` compares two runner results dimension by
dimension. Logical account and actor identities are compared while native IDs
remain in evidence. Cross-target external actions compare their logical payload
while retaining target-owned native payloads. Resource observations are only
compared within one target family; cross-target results record coverage without
producing a combined gas/CU/fuel score.

Run the focused gate with:

```sh
just differential-contracts
```

`scripts/differential/contracts.py` can read the current NEAR and Solana v0
reference manifests only through explicit migration functions. Migration does
not make those manifests semantically eligible: missing provenance and missing
normalized observations remain explicit, and `semanticMatch` stays false.
Each target follow-up replaces v0 manifests with v1 evidence and then deletes
its migration function. No production compatibility route is introduced.
