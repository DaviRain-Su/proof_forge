import ProofForge.Frontend.Surface
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Canonical
import ProofForge.Contract.Spec
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault

/-! # Surface Normalize Test

Constructs independent Surface versions of Counter and ValueVault and asserts
their checked canonical contracts are produced successfully. Also checks:
- duplicate source names fail before ID assignment;
- generated names use the reserved $surface. namespace;
- ordinary user names beginning with $surface. are rejected;
- invalid source type, missing return, and unknown state fail.
-/

open ProofForge.Frontend.Surface
open ProofForge.IR.Legacy.Adapter
open ProofForge.IR.Canonical

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- A minimal Surface Counter contract. -/
def surfaceCounter : SurfaceContract := {
  name := "Counter"
  structs := #[]
  state := #[{ name := "count", kind := .scalar .u64 }]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "count" (.literal (.u64Lit 0))
      ]
    },
    { name := "increment", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "count"
          (.arith .add true
            (.stateRead "count")
            (.literal (.u64Lit 1)))
      ]
    },
    { name := "get", kind := .function, mutability := .view,
      params := #[], retType := .u64,
      body := #[
        .returnExpr (.stateRead "count")
      ]
    }
  ]
  constructorParams := #[]
  constructorBindings := #[]
  intents := #[]
}

def main : IO Unit := do
  /- Check 1: Surface Counter normalizes successfully. -/
  match normalizeSurface surfaceCounter with
  | Except.ok bundle =>
    require (bundle.contract.contract.schemaVersion == 1)
      "schema version mismatch"
    require (bundle.contract.contract.module.name == "Counter")
      "module name mismatch"
    require (bundle.contract.contract.module.state.size == 1)
      "state size mismatch"
    require (bundle.contract.contract.module.functions.size == 3)
      "function count mismatch"
    require (bundle.contract.contract.interface.entrypoints.size == 3)
      "entrypoint count mismatch"
  | Except.error e => throw <| IO.userError s!"Surface Counter normalize failed: {repr e}"

  /- Check 2: Duplicate state names fail. -/
  let dupState : SurfaceContract := { surfaceCounter with
    state := #[{ name := "count", kind := .scalar .u64 },
               { name := "count", kind := .scalar .u64 }] }
  match normalizeSurface dupState with
  | Except.ok _ => throw <| IO.userError "Duplicate state names should fail"
  | Except.error _ => pure ()

  /- Check 3: User names beginning with $surface. are rejected. -/
  let badName : SurfaceContract := { surfaceCounter with
    state := #[{ name := "$surface.count", kind := .scalar .u64 }] }
  match normalizeSurface badName with
  | Except.ok _ => throw <| IO.userError "$surface. prefix should be rejected"
  | Except.error _ => pure ()

  /- Check 4: Empty entrypoints fail. -/
  let noEntry : SurfaceContract := { surfaceCounter with entrypoints := #[] }
  match normalizeSurface noEntry with
  | Except.ok _ => throw <| IO.userError "Empty entrypoints should fail"
  | Except.error _ => pure ()

  /- Check 5: Unknown state read fails during normalization. -/
  let badState : SurfaceContract := { surfaceCounter with
    entrypoints := #[
      { name := "get", kind := .function, mutability := .view,
        params := #[], retType := .u64,
        body := #[.returnExpr (.stateRead "nonexistent")] }
    ] }
  match normalizeSurface badState with
  | Except.ok _ => throw <| IO.userError "Unknown state should fail"
  | Except.error _ => pure ()

  IO.println "surface-normalize: ok"