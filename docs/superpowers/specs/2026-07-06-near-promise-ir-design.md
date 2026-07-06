# NEAR Promise IR (Scheme A)

**Status:** implemented in portable `Expr` + EmitWat lowering (v1: status only)

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
| `return` of promise expr | `promise_return` |

Callback args reuse the crosscall JSON arg builder (`[]` / `[42]`).

## Deferred (v2)

- `nearPromiseResultPayload` / typed Borsh decode of register contents
- `promise_and`, remote-account callbacks, multi-index branching

## Fixture

`ProofForge/IR/Examples/NearCrosscallProbe.lean` — `call_remote_with_callback` +
`handle_remote`.