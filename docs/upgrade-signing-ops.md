# Upgrade policy and signing — operational notes (U6.5 / RFC 0013)

Status: **Operational guide** (implements RFC 0013 M4 documentation slice)  
Audience: CI / on-call / agents running live gates  
Related: [RFC 0013](rfcs/0013-deployment-lifecycle-upgrades-and-signing.md), D-043,
`ContractSpec.upgradePolicy?`, deploy manifests.

## Compiler boundary (non-negotiable)

| Responsibility | ProofForge | Outside ProofForge |
|----------------|------------|--------------------|
| Compile + emit artifacts | ✅ | |
| Emit **unsigned** deploy / tx plans | ✅ | |
| Choose `upgradePolicy` honesty (immutable / authority / reject) | ✅ | |
| Hold private keys / mnemonics | ❌ | Wallet, KMS, CI secrets |
| Sign transactions | ❌ | `cast`, Solana CLI, NEAR CLI, hardware wallet |
| Fund live accounts | ❌ | Faucet / treasury (throwaway for gates) |

ProofForge **must never** require a private key as a compiler input. Live smokes
that need keys load them only from environment variables or local secret stores
that are **gitignored**.

## upgradePolicy intent (product)

Authors declare policy on the contract intent; `--target` materializes or
**rejects** before codegen:

| Policy | EVM | Solana | NEAR | Notes |
|--------|-----|--------|------|-------|
| `immutable` | ok (default product) | ok | ok | Prefer for Shared Product |
| `authority(keyRef)` | reject v0; backend UUPS transport does not bind keyRef | upgrade authority | account redeploy keys | keyRef is a **logical** name, not a secret |
| `governance(ref)` | reject v0 | reject v0 | reject v0 | Future |

Diagnostics must name policy + target when rejected (no silent immutable).

## Deploy manifest fields

`proof-forge-deploy.json` (and Solana packages) should record:

```json
{
  "upgradePolicy": { "kind": "immutable" },
  "signing": {
    "generatedBy": "proof-forge",
    "signedBy": null,
    "keyRefs": []
  }
}
```

- `signedBy` stays `null` in compiler output.
- `keyRefs` lists **logical** roles (`deployer`, `upgrade_authority`) resolved
  only by the external signer.

## Live-gate throwaway-key convention

| Gate family | Key source | Rules |
|-------------|------------|--------|
| EVM Anvil / Foundry | Anvil default accounts or `PRIVATE_KEY` in env | Never commit keys; Anvil defaults are **local-only** |
| Solana Surfpool / Pinocchio live | Generated keypair under `build/` or `SOLANA_KEYPAIR` path | Keypair files under `build/` stay gitignored |
| NEAR sandbox / offline host | Offline host needs no funded key; real broadcast uses NEAR credentials **outside** default `just check` | Do not add mainnet keys to CI |

### Forbidden

- Committing `*.json` keypairs, `id.json`, `.env` with secrets, or mnemonic phrases.
- Logging private keys in smoke scripts.
- Baking funded mainnet keys into `justfile` recipes.

### Recommended CI pattern

```bash
# Example only — use your platform secret store
export PRIVATE_KEY="${ANVIL_OR_TESTNET_KEY}"   # injected by CI, not in git
just evm-anvil-deploy   # or chain-specific live recipe
# Prefer ephemeral Anvil; if testnet, rotate keys regularly
```

Optional future CI check (RFC 0013 M4 remainder): scan for PEM / base58 secret
patterns under tracked paths (not implemented in this note).

## Agent / contributor checklist

1. Prefer `upgradePolicy = immutable` for Shared Product demos.
2. If a smoke needs a key, document the **env var name** in the script header.
3. Never paste keys into issues, PRs, or agent transcripts.
4. After live gates: wipe local key material if it was generated for the run.

## Commands

```bash
# Product path does not need keys
just product

# Live EVM (local Anvil — no external secret required)
just evm-anvil-deploy   # if available in justfile

# Versioning / schema (unsigned artifacts)
just versioning-policy
```
