/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# IR fixture Counter (formal / CLI / golden routes)

**Product author source:** `Examples/Product/Counter.lean` — business logic only.

This module is a **minimal IR fixture** for semantics, CLI `--fixture counter`,
and backend goldens. It intentionally:

* pins optional EVM selector metadata (fixture / materialization, not authoring);
* uses wrapping `.add` so formal total-fuel theorems stay stable.

Shape parity (name, state id, entrypoint names) with Product is checked by
`Tests/Product/Matrix.lean`. Do not treat this file as the authoring surface.
-/
import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.Counter

open ProofForge.IR

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def initializeEntrypoint : Entrypoint := {
  name := "initialize"
  selector? := some "8129fc1c"
  body := #[
    .effect (.storageScalarWrite "count" (.literal (.u64 0)))
  ]
}

def increment : Entrypoint := {
  name := "increment"
  selector? := some "d09de08a"
  body := #[
    .letBind "n" .u64 (.effect (.storageScalarRead "count")),
    .effect (.storageScalarWrite "count" (.add (.local "n") (.literal (.u64 1))))
  ]
}

def get : Entrypoint := {
  name := "get"
  selector? := some "6d4ce63c"
  mutability := .view
  returns := .u64
  body := #[
    .return (.effect (.storageScalarRead "count"))
  ]
}

def module : Module := {
  name := "Counter"
  state := #[stateCount]
  entrypoints := #[initializeEntrypoint, increment, get]
}

end ProofForge.IR.Examples.Counter
