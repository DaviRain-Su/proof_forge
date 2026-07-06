# NEAR Promise IR (Scheme A)

**Status:** implemented in portable `Expr` + EmitWat lowering (v1: status; v2: U64 payload)

## Summary

NEAR async cross-contract execution uses the host Promise API (`promise_create`,
`promise_then`, `promise_results_count`, `promise_result`, `promise_return`).
These forms are **not** extensions of portable `crosscallInvoke`; they are
NEAR-specific `Expr` constructors gated by the `near.promise` capability.

## IR additions

```lean
| nearPromiseThen (parentPromise : Expr) (callbackMethod : Expr) (args : Array Expr) (deposit : Expr)
| nearPromiseResultsCount
| nearPromiseResultStatus (index : Expr)
| nearPromiseResultU64 (index : Expr)
```

### Module metadata

Reuse `module.nearCrosscallStrings` for:

- remote account ids and method names (`crosscallInvoke`)
- **local callback method names** (`nearPromiseThen`)

Indices are referenced with `.literal (.address i)` (same as crosscall targets).

### Types (v1)

| Form | Result |
|------|--------|
| `nearPromiseThen` | `U64` (promise id) |
| `nearPromiseResultsCount` | `U64` |
| `nearPromiseResultStatus` | `U64` (1 success / 2 failed) |
| `nearPromiseResultU64` | `U64` (Borsh payload; 0 on failure) |

### Capability

- `near.promise` — absent from `wasm-near` target profile (routing rejects)
- EmitWat extends its capability set with `near.promise` (mirrors `crosscall.invoke`)

## Lowering (EmitWat)

| IR | Host |
|----|------|
| `crosscallInvoke` | `promise_create` |
| `nearPromiseThen` | `promise_then` + `current_account_id` helper |
| `nearPromiseResultsCount` | `promise_results_count` |
| `nearPromiseResultStatus` | `promise_result` |
| `nearPromiseResultU64` | `promise_result` + `read_register` (Borsh U64) |
| `return` of promise expr | `promise_return` |

Callback args reuse the crosscall JSON arg builder (`[]` / `[42]`).

## Deferred (v3+)

- `nearPromiseResultPayload` for arbitrary Borsh types beyond U64
- `promise_and`, remote-account callbacks, multi-index branching

## Fixture

`ProofForge/IR/Examples/NearCrosscallProbe.lean` — `call_remote_with_callback` +
`handle_remote`.