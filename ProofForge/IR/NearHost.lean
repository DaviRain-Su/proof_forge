/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# NEAR host-extension surface (D-050 Slice 3)

Portable product path for NEAR cross-contract intent:

```
remoteCall / crosscall.invoke  +  module.crosscallStrings
  → EmitWat materializes promise_create
```

**Host-extension only** (opt-in `ProofForge.Contract.Source.Near`, fixtures):

| IR constructor | Host form | Portable? |
|---|---|---|
| `nearPromiseThen` | `promise_then` | no — chain callbacks |
| `nearPromiseResultsCount` | `promise_results_count` | no — callback entrypoints |
| `nearPromiseResultStatus` | `promise_result` status | no |
| `nearPromiseResultU64` | Borsh u64 decode | no |
| `nearCrosscallInvokePool` | low-level `promise_create` | prefer `crosscall.invoke` |

These constructors remain on the portable `Expr` inductive for EmitWat coverage
and ownership/semantics walks, but:

* `ProofForge.IR.Portability` marks them `targetFamilyOnly .wasmHost`
* Shared examples must not use them (`just portable-default`)
* Product authoring uses `Source.Near` only when Promise chaining is intentional

Full removal from the `Expr` inductive is a later mechanical migration (every
Expr match site). This module is the **vocabulary** for that split.
-/
import ProofForge.IR.Contract
import ProofForge.IR.Portability

namespace ProofForge.IR.NearHost

open ProofForge.IR
open ProofForge.IR.Portability

/-- True when the module body uses NEAR Promise host-extension constructors. -/
def usesPromiseExtension (module : Module) : Bool :=
  (classifyModule module).any fun f =>
    match f.class_ with
    | .targetFamilyOnly .wasmHost =>
        f.detail.startsWith "nearPromise" || f.detail.startsWith "nearCrosscallInvokePool"
    | _ => false

/-- True when the module only needs the portable NEAR materialization path
(crosscall.invoke + optional string pool), not Promise chaining. -/
def isPortableNearCrosscall (module : Module) : Bool :=
  !usesPromiseExtension module &&
    ((classifyModule module).any fun f => f.detail.startsWith "crosscall.invoke" ||
      f.path == "module.crosscallStrings")

def productGuidance : String :=
  "Portable: remoteCall/crosscall.invoke + crosscallStrings → promise_create. " ++
  "Host-extension (Source.Near): nearPromiseThen / result decode."

end ProofForge.IR.NearHost
