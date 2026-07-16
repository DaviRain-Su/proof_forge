# Portable error vocabulary (P1.6 / WS33 light)

Status: **Active**
Related: D-041, `just portable-error-catalog`, `just client-schema-parity`,
`ProofForge.Contract.SdkSchema`, EVM custom-error surface (E1.1).

## Goal

One **assertionId** catalogue is shared across product clients. Hosts encode
the same id in native form; clients expose the same lookup helper name.

## Shared catalogue fields

| Field | Type | Meaning |
|-------|------|---------|
| `assertionId` | `u32` / number | Portable stable id (compiler-assigned) |
| `userCode` | optional string/number | Author-facing code when present |
| `message` | string | Human fallback |
| `name` | string | Symbolic name in IR / Solidity custom error |

## Host encoding

| Target | Native form | Client surface |
|--------|-------------|----------------|
| `evm` | Custom-error 4-byte selector (+ static args when present); assert → ProofForge revert payload with id | `ERRORS`, `errorByAssertionId`, `decodeProofForgeRevert` |
| `solana-sbpf-asm` | Custom program error code mapped from assertionId | IDL `errors[]`, `errorByAssertionId`, `errorBySolanaCustomCode` |
| `wasm-near` | Panic / log payload `PF:id:code` style | `ERRORS`, `errorByAssertionId`, `parseProofForgePanic` |

## Lookup contract (required)

All three TypeScript surfaces must export:

```ts
errorByAssertionId(id: number): { assertionId, userCode?, message, name? } | undefined
```

Entrypoint **names** must match across SdkSchema targets (see
[client-schema-parity.md](client-schema-parity.md)).

## Gates

```sh
just portable-error-catalog   # ErrorRefProbe ids locked on triad
just client-schema-parity     # entrypoints + errorByAssertionId on triad
```

## Non-goals (still open)

- Dynamic custom-error ABI args (`string` / `bytes` / arrays) on EVM
- Single cross-host decode function name (host-idiomatic helpers stay)
- Full NEAR structured JSON panic standard beyond PF payload

## Fixture

`ProofForge.IR.Examples.ErrorRefProbe` — assertion ids **1** and **2** are the
locked smoke catalogue.
