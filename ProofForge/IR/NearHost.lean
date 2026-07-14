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

| Semantic request | Host form | Portable? |
|---|---|---|
| `crosscallContinue` | `promise_then` | no — chain callbacks |
| `hostCall near.promise.results_count` | `promise_results_count` | no — callback entrypoints |
| `hostCall near.promise.result_status` | `promise_result` status | no |
| `hostCall near.promise.result_u64` | Borsh u64 decode | no |
| `crosscallInvokeNamedValue` | low-level `promise_create` | prefer `crosscall.invoke` |

The continuation is a shared semantic request and NEAR-only scalar operations
are target-owned HostOps. Consequently:

* `ProofForge.IR.Portability` marks HostOps target-family-only and continuation family-shared
* Shared examples must not use them (`just portable-default`)
* Product authoring uses `Source.Near` only when Promise chaining is intentional

No NEAR-named constructor remains in the shared `Expr` inductive. This module
is the **vocabulary** for the target facade split.
-/
import ProofForge.IR.Contract
import ProofForge.IR.Portability

namespace ProofForge.IR.NearHost

open ProofForge.IR
open ProofForge.IR.Portability

/-- True when the module body uses NEAR Promise HostOps or async continuation. -/
def usesPromiseExtension (module : Module) : Bool :=
  (classifyModule module).any fun f =>
    f.detail.startsWith "target extension near.promise/" ||
      f.detail.startsWith "crosscall.continue"

/-- True when the module only needs the portable NEAR materialization path
(crosscall.invoke + optional string pool), not Promise chaining. -/
def isPortableNearCrosscall (module : Module) : Bool :=
  !usesPromiseExtension module &&
    ((classifyModule module).any fun f => f.detail.startsWith "crosscall.invoke" ||
      f.path == "module.crosscallStrings")

def productGuidance : String :=
  "Portable: remoteCall/crosscall.invoke + crosscallStrings → promise_create. " ++
  "Host-extension (Source.Near): crosscallContinue / result decode."

end ProofForge.IR.NearHost
