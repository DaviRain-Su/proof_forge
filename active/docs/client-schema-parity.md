# Client schema parity (U6.4)

Status: **Enforced** via `just client-schema-parity` / `Tests/ClientSchemaParity.lean`  
Related: `just portable-error-catalog`, `ProofForge.Contract.SdkSchema`,
`ProofForge.Contract.Client`, Solana IDL/client.

## Shared product contract

| Concern | Unified across triad? | Surface |
|---------|----------------------|---------|
| Entrypoint **names** | **Yes** | SdkSchema `entrypoints[].name`; EVM/NEAR `export async function <name>`; Solana IDL `instructions[].name` |
| Error **assertionId** + **userCode** | **Yes** | SdkSchema `errors[]`; TS `ERRORS` / `errorByAssertionId` |
| Host decode helper **name** | **No** (idiomatic) | EVM `decodeProofForgeRevert`; NEAR `parseProofForgePanic`; Solana `errorBySolanaCustomCode` |
| Param TS types | Best-effort | `Client.typeToTs` (u64→bigint, …) |

## Commands

```bash
just client-schema-parity
just portable-error-catalog
just contract-client
just sdk-schema
```

## Non-goals

- One universal TS package for all chains (host SDKs differ).
- Renaming Solana instructions away from IR entrypoint names.
- Forcing a single revert decoder name on every host.
