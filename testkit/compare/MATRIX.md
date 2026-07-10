# NEAR compare matrix - observation-aware snapshot

**Historical live dual-deploy reports:** **28**

**Semantically verified reports:** **0**

**Leaderboard eligibility:** exact `proof-forge.testkit.compare.near-sandbox.v1`
schema, `observedSemanticMatch=true`, `semanticMatch=true`, and complete,
internally consistent coverage (`missing=[]`; `covered` contains every required
dimension).

## Verified leaderboard

No archived report from the 2026-07-10 snapshot declares observation coverage.
The recorded size, gas, and storage values remain raw measurements, but none is
eligible for semantic performance ranking. Use
`just near-compare-live-measure <contract>` to refresh an explicitly
measurement-only report; `just near-compare-all-live` remains the fail-closed
semantic gate. Then run `just near-compare-matrix`.

## Observation status

| Contract | observed semantics | coverage | verified | missing |
|----------|--------------------|----------|----------|---------|
| access-control | unknown | missing (legacy schema) | no | observationCoverage |
| array-example | unknown | missing (legacy schema) | no | observationCoverage |
| auth-remote-call | unknown | missing (legacy schema) | no | observationCoverage |
| counter | unknown | missing (legacy schema) | no | observationCoverage |
| escrow-vault | unknown | missing (legacy schema) | no | observationCoverage |
| external-token-transfer | unknown | missing (legacy schema) | no | observationCoverage |
| external-vault | unknown | missing (legacy schema) | no | observationCoverage |
| fee-token | unknown | missing (legacy schema) | no | observationCoverage |
| ft-peer-client | unknown | missing (legacy schema) | no | observationCoverage |
| fungible-token | unknown | missing (legacy schema) | no | observationCoverage |
| guestbook | unknown | missing (legacy schema) | no | observationCoverage |
| height-lock-vault | unknown | missing (legacy schema) | no | observationCoverage |
| host-env-probe | unknown | missing (legacy schema) | no | observationCoverage |
| ownable | unknown | missing (legacy schema) | no | observationCoverage |
| ownable-hash | unknown | missing (legacy schema) | no | observationCoverage |
| ownable-pausable | unknown | missing (legacy schema) | no | observationCoverage |
| pausable | unknown | missing (legacy schema) | no | observationCoverage |
| pro-rata-vault | unknown | missing (legacy schema) | no | observationCoverage |
| reentrancy-guard | unknown | missing (legacy schema) | no | observationCoverage |
| remote-call | unknown | missing (legacy schema) | no | observationCoverage |
| role-gated-token | unknown | missing (legacy schema) | no | observationCoverage |
| soulbound-token | unknown | missing (legacy schema) | no | observationCoverage |
| staking-vault | unknown | missing (legacy schema) | no | observationCoverage |
| status-message | unknown | missing (legacy schema) | no | observationCoverage |
| storage-deposit | unknown | missing (legacy schema) | no | observationCoverage |
| timelock-vault | unknown | missing (legacy schema) | no | observationCoverage |
| value-vault | unknown | missing (legacy schema) | no | observationCoverage |
| vesting-vault | unknown | missing (legacy schema) | no | observationCoverage |

## Interpretation

1. `observedSemanticMatch` compares only evidence recorded by the sandbox harness.
2. Successful deployment and matching partial observations do not establish full semantics.
3. Size, gas, and storage ratios enter the leaderboard only when the exact v1 schema and every semantic and coverage eligibility condition agree.

```sh
just near-compare-matrix
just near-compare-live-measure auth-remote-call
just near-compare-all-live
```
