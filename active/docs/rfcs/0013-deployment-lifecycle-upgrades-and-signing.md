# RFC 0013: Deployment Lifecycle, Upgrades, and Signing

Status: **Accepted (executable slice)**
Date: 2026-07-03
Updated: 2026-07-10 (P1.4)

## Acceptance note (P1.4)

The minimal executable policy is **implemented and gated**:

| Surface | Evidence |
|---------|----------|
| Intent model | `ProofForge.Contract.UpgradePolicy` (`immutable` / `authority` / `governance`) |
| Portable honesty | `ProofForge.Target.PortableHonesty.requireUpgradeHonesty` |
| EVM | `just evm-upgrade-policy-honesty` (UUPS ok; authority without proxy fails closed) |
| Ops | [upgrade-signing-ops.md](../upgrade-signing-ops.md) (unsigned emit; keys outside compiler) |
| Decision | D-043 / E1.4 upgrade-policy honesty |

Governance remains reject-in-v0 on triad. Solana upgrade authority + NEAR redeploy
keys follow the ops table; product examples default to `immutable` or fail closed.

## Problem

Deploy manifests exist today:

- EVM `proof-forge-deploy.json` records chain profiles and constructor args.
- Solana deploy packages include program keypairs and upgrade authority.

But the lifecycle *after* first deployment is unmodeled, and the chains
disagree violently:

- **EVM:** contracts are immutable by default; upgradeability requires a proxy
  pattern that the compiler cannot hide.
- **Solana:** programs have an upgrade authority that can be revoked.
- **NEAR:** code can be redeployed to the same account.
- **Aleo:** programs can declare `@noupgrade`.

The Intent API currently cannot express "this contract is upgradeable by X".
That means every backend picks an implicit, divergent default — exactly the
kind of semantic-silence bug the platform promises to reject.

Key management is also still an open question from RFC 0001 and blocks the
cloud-platform story (D-010). Live gates currently use ad-hoc throwaway keys
per smoke script.

## Summary

Add an `upgradePolicy` intent to the contract model and lower it honestly per
chain:

```text
upgradePolicy :
  | immutable
  | authority(keyRef)      -- single logical authority
  | governance(governanceRef)  -- on-chain governance contract/program
```

Each target either lowers the policy to a native mechanism or rejects it at
compile time with a clear diagnostic:

| Target | `immutable` | `authority(keyRef)` | `governance(ref)` |
|---|---|---|---|
| `evm` | default (no proxy) | rejected unless target explicitly emits a documented proxy pattern | rejected in v0; research proxy governance later |
| `solana-sbpf-asm` | program deploy with authority immediately revoked | program deploy with upgrade authority = keyRef | rejected in v0 |
| `wasm-near` | account key policy fixed at deploy | NEAR account key = keyRef | rejected in v0 |
| `aleo-leo` | `@noupgrade` | rejected | rejected |
| `psy-dpn` | circuit immutable | rejected | rejected |

For signing, ProofForge emits **unsigned transactions and manifests only**.
Key custody stays outside the compiler in wallets, KMS, or CI secrets. Live
gates document their throwaway-key convention.

## Upgrade Policy Intent

The intent lives in the contract/module metadata, not in target-specific
flags. Example:

```toml
[contract]
name = "Counter"
upgrade_policy = { immutable = {} }
```

or

```toml
[contract]
name = "Counter"
upgrade_policy = { authority = { key_ref = "deployer" } }
```

`keyRef` is a logical name resolved by the signer at deployment time, not a
raw private key. This keeps the compiler key-agnostic.

## Lowering Rules

### EVM

- `immutable`: emit bytecode directly; no proxy.
- `authority(keyRef)`: **rejected** in v0. EVM proxy patterns (EIP-1967,
  UUPS, transparent proxy) change the ABI surface, storage layout guarantees,
  and deployment flow. Supporting them requires a separate RFC that specifies
  which proxy pattern, how storage collision is avoided, and how upgrades are
  validated.
- `governance(ref)`: **rejected** in v0.

### Solana

- `immutable`: deploy with the upgrade authority set to a known burn address
  (e.g. `11111111111111111111111111111111`) so the program is effectively
  immutable.
- `authority(keyRef)`: deploy with the upgrade authority set to the public
  key resolved from `keyRef` at signing time.
- `governance(ref)`: **rejected** in v0.

### NEAR

- `immutable`: record in deploy metadata that the account key is the only
  upgrade path; no code changes.
- `authority(keyRef)`: record that the account key identified by `keyRef` is
  the upgrade authority.
- `governance(ref)`: **rejected** in v0.

### Aleo

- `immutable`: emit `@noupgrade` in the Leo source.
- Other policies: **rejected**.

### Psy DPN

- `immutable`: default; circuits are immutable.
- Other policies: **rejected**.

## Signing Boundary

ProofForge never touches private keys. It produces:

- Unsigned transaction payloads (where applicable).
- Deployment manifests with placeholders for signatures and addresses.
- Key-reference metadata (`key_ref`) that a signer resolves.

Signers are outside the compiler:

- Local development: Foundry `cast send`, Solana CLI, `near-cli`, Leo wallet.
- CI: environment-injected secrets used by thin wrapper scripts.
- Cloud platform: KMS-backed signers (future).

Live gates must document:

- Which key references they use.
- That keys are throwaway/testnet-only.
- How to rotate or revoke them.

## Manifest Extension

`proof-forge-deploy.json` gains an `upgradePolicy` field:

```json
{
  "upgradePolicy": {
    "kind": "immutable"
  }
}
```

or

```json
{
  "upgradePolicy": {
    "kind": "authority",
    "keyRef": "deployer"
  }
}
```

The manifest also records the `signingBoundary`:

```json
{
  "signing": {
    "generatedBy": "proof-forge",
    "signedBy": null,
    "keyRefs": ["deployer"]
  }
}
```

## Acceptance Criteria

- `immutable` is supported and documented for all Tier-0 targets.
- `authority(keyRef)` is supported for Solana and NEAR.
- Unsupported policies produce a compile-time diagnostic, not a silent
  divergence.
- Live-gate documentation states the throwaway-key convention.

## Milestones

1. **M1:** Add `upgradePolicy` to the contract intent model and reject
   unsupported combinations.
2. **M2:** Implement lowering for EVM `immutable`, Solana
   `immutable`/`authority`, and NEAR `immutable`/`authority`.
3. **M3:** Update deploy manifests with `upgradePolicy` and `signing` fields.
4. **M4:** Document live-gate key conventions and add a CI check that no
   private key is committed.

## Non-goals

- This RFC does not implement proxy patterns on EVM.
- It does not implement on-chain governance.
- It does not provide a key management service.

## Related

- [RFC 0001](0001-multichain-platform.md): cloud platform and key management
  open question.
- [RFC 0002](0002-target-implementation-design.md): target profiles and
  artifact kinds.
- [RFC 0012](0012-versioning-and-compatibility-policy.md): deploy manifest
  schema versioning.
- [Workstream 32](../implementation-backlog.md#workstreams-2933-platform-hardening-planning-first): deployment lifecycle, upgrades, and signing.
