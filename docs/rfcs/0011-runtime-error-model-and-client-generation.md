# RFC 0011: Portable Runtime Error Model and Unified Client Generation

Status: **Accepted executable architecture (D-041); coverage remains incremental.**
Date: 2026-07-03

## Problem

`assert`/`assertEq` carry optional messages, but each backend already invents
its own failure surface:

- **EVM:** revert with no structured revert-reason encoding today.
- **Solana:** custom program error codes and log lines.
- **NEAR:** panic payload strings.
- **Psy:** circuit assertion index.

The testkit can assert success traces (RFC 0007) but has no vocabulary for
*which* error occurred. Once three more backends harden divergent conventions,
unifying them becomes a breaking change on every target.

At the same time, client generation is already inconsistent. Solana emits an
IDL + TypeScript client (`Backend/Solana/Client.lean`); EVM emits ABI JSON;
NEAR, Psy, and Aleo emit nothing client-facing. The "one contract, many
chains" story is only real if the application developer gets one interface.

## Summary

This RFC has two halves that share one schema layer:

1. **Portable runtime error model.** Add an error id (`assertion_id` +
   optional `user_code`) at the portable IR level. Each target lowers it to a
   native encoding:

   | Target | Encoding |
   |---|---|
   | `evm` | `revert` with a compact ABI encoding of `(assertion_id, user_code?)` |
   | `solana-sbpf-asm` | custom program error code |
   | `wasm-near` | panic payload with a prefixed compact code |
   | `psy-dpn` | assertion index in circuit JSON |

2. **Unified client schema.** Generalize the Solana IDL into a target-neutral
   `ContractSpec` JSON that describes entrypoints, types, accounts, and errors.
   Per-chain TS adapters (EVM ABI wrapper, Solana instruction builder, NEAR
   contract wrapper) are generated from this one schema.

Both halves are planned now and implemented after testkit M3. The error
vocabulary lands together with the budget schema change (RFC 0010) so testkit
undergoes only one schema migration.

## Portable Runtime Error Model

### IR-level representation

Every `assert`/`assertEq` statement carries:

```text
ErrorRef
  assertion_id : u32     -- compiler-assigned, stable within a module
  user_code?   : String  -- optional author-facing code, e.g. "Counter::Overflow"
```

The IR keeps `user_code` as a string so contract authors can write readable
error names without bumping the binary assertion table.

### Per-target encoding table

| Target | Native form | Decoding rule |
|---|---|---|
| `evm` | `revert(abi.encode(uint32 assertion_id, string user_code))` | Testkit parses revert data; user_code is UTF-8 |
| `solana-sbpf-asm` | `solana_program::program_error::ProgramError::Custom(assertion_id)` | Custom error code; user_code emitted in IDL/client schema only |
| `wasm-near` | `panic!("PF:{assertion_id}:{user_code}")` | Prefix `PF:` plus colon-separated fields for deterministic parsing |
| `psy-dpn` | assertion index in `.psy` circuit metadata | Dargo preserves index; user_code in generated circuit docs |

Targets that cannot encode the full pair must at least encode `assertion_id`;
`user_code` then lives only in the client schema and deployment metadata.

### Scenario vocabulary

Testkit `expect` gains an `error` field:

```toml
[[step]]
call = "increment"
[step.expect.error]
assertion_id = 3
user_code = "Counter::Overflow"
```

Compact form when only the id matters:

```toml
[[step]]
call = "increment"
[step.expect.error]
assertion_id = 3
```

If a step declares `expect.error`, the runner asserts the step fails *and*
that the decoded error matches. If the step succeeds, the test fails.

### FV pairing

Error semantics pair with FV-5 checked-arithmetic trap semantics: a checked
arithmetic failure is just another `assertion_id` with a well-known code
(e.g. `0x0001` for overflow). The proof layer can state that no reachable path
raises a given error id.

## Unified Client Schema

### `ContractSpec` JSON

Generalize the Solana IDL into a target-neutral contract description:

```json
{
  "schemaVersion": 1,
  "name": "Counter",
  "entrypoints": [
    {
      "name": "initialize",
      "params": [],
      "returns": { "kind": "unit" },
      "mutates": true
    },
    {
      "name": "increment",
      "params": [],
      "returns": { "kind": "u64" },
      "mutates": true
    },
    {
      "name": "get",
      "params": [],
      "returns": { "kind": "u64" },
      "mutates": false
    }
  ],
  "types": [
    { "name": "u64", "kind": "scalar", "width": 64 }
  ],
  "errors": [
    { "assertion_id": 3, "user_code": "Counter::Overflow" }
  ],
  "accounts": []
}
```

For Solana, `accounts` is populated per instruction. For EVM, the adapter
derives function selectors from entrypoint names and param types. For NEAR,
the adapter generates a wrapper around the exported functions.

### Implementation boundary

The client-schema layer is implemented *after* testkit M3 because the testkit
encoding adapters (selector/instruction/Borsh mapping) are the same logic and
should be written once, then shared with client generation.

```text
ProofForge.IR.Module
  -> ContractSpec JSON (target-neutral)
    -> Solana IDL + TS client
    -> EVM ABI JSON + TS/JS wrapper
    -> NEAR contract TS wrapper
    -> testkit encoding adapters (shared)
```

## Acceptance Criteria

- A `assertEq` failure in Counter produces the same `assertion_id` and
  `user_code` in EVM revert data, Solana custom error, and NEAR panic payload.
- Testkit can assert `expect.error.assertion_id` on all three Tier-0 targets.
- `ContractSpec` JSON is emitted for at least one existing module and used to
  regenerate the existing Solana TS client without behavioral change.
- EVM ABI JSON and NEAR wrapper generation are sketched, even if not yet
  complete.

## Milestones

1. **M1:** Add `ErrorRef` to the portable IR `assert`/`assertEq` constructors
   and assign stable assertion ids during lowering.
2. **M2:** Implement per-target error encodings for EVM, Solana, and NEAR.
3. **M3:** Extend testkit schema and harnesses with `expect.error`; land
   together with RFC 0010's budget schema change.
4. **M4:** Define `ContractSpec` JSON schema and generate Solana IDL/client
   from it; add EVM and NEAR adapter sketches.

## Non-goals

- This RFC does not define a new on-chain protocol or change consensus rules.
- It does not replace chain-native error systems; it wraps them.
- It does not implement the client layer before testkit M3.

## Related

- [RFC 0007](0007-unified-rust-test-framework.md): testkit scenario model.
- [RFC 0010](0010-resource-budgets-as-gates.md): budget schema change that
  should land in the same schema migration.
- [Workstream 26](../implementation-backlog.md#workstream-26-unified-rust-test-framework-testkit): testkit M3.
- [Workstream 33](../implementation-backlog.md#workstreams-2933-platform-hardening-planning-first): runtime error model + client generation.
