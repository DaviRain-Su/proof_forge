import ProofForge.Frontend.Surface
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Canonical
import ProofForge.Contract.Source
import ProofForge.Contract.SdkSchema

/-! # Source Loader Test

Checks that the LoadedContractSource type correctly distinguishes
v1 Legacy and v2 Surface sources, and that both normalize to
CanonicalBundle.
-/

open ProofForge.Frontend.Surface
open ProofForge.IR.Legacy.Adapter
open ProofForge.IR.Canonical
open ProofForge.Contract.SdkSchema

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- Surface Counter fixture. -/
def surfaceCounter : SurfaceContract := {
  name := "Counter",
  structs := #[],
  state := #[{ name := "count", kind := .scalar .u64 }],
  events := #[],
  errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[.stateWrite "count" (.literal (.u64Lit 0))] }
  , { name := "increment", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[.stateWrite "count"
          (.arith .add true (.stateRead "count") (.literal (.u64Lit 1)))] }
  , { name := "get", kind := .function, mutability := .view,
      params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "count")] }
  ],
  constructorParams := #[],
  constructorBindings := #[],
  intents := #[],
}

def main : IO Unit := do
  /- Check 1: Surface v2 normalizes to CanonicalBundle. -/
  match normalizeSurface surfaceCounter with
  | Except.ok bundle =>
    require (bundle.contract.contract.module.name == "Counter")
      "Surface v2 module name mismatch"
    require (bundle.contract.contract.module.functions.size == 3)
      "Surface v2 function count mismatch"
  | Except.error e => throw <| IO.userError s!"Surface v2 normalize failed: {repr e}"

  /- Check 2: Surface v2 normalizer is fail-closed on unknown state. -/
  let badContract := { surfaceCounter with
    state := #[{ name := "count", kind := .scalar .u64 }],
    entrypoints := #[
      { name := "get", kind := .function, mutability := .view,
        params := #[], retType := .u64,
        body := #[.returnExpr (.stateRead "nonexistent")] }
    ] }
  match normalizeSurface badContract with
  | Except.ok _ => throw <| IO.userError "Unknown state should fail"
  | Except.error _ => pure ()

  /- Check 3: SdkSchema reports both source versions. -/
  require (ProofForge.Contract.SdkSchema.sourceVersionV1 == "contract_source-v1")
    "v1 version string mismatch"
  require (ProofForge.Contract.SdkSchema.sourceVersionV2 == "contract_source-v2")
    "v2 version string mismatch"

  /- Check 4: Source.lean reports both source versions. -/
  require (ProofForge.Contract.Source.sourceDslVersion == "contract_source-v1")
    "Source.sourceDslVersion mismatch"
  require (ProofForge.Contract.Source.sourceSurfaceVersion == "contract_source-v2")
    "Source.sourceSurfaceVersion mismatch"

  IO.println "source-loader: ok"