import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Collections.Set

/-! # Set Normalize Test

Checks that Surface Set declarations expand to Core state declarations
with the correct generated names and shapes.
-/

open ProofForge.Frontend.Surface

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- A Set with element type u64 and capacity 100. -/
def testSet : SurfaceSetDecl := { id := 0, elementType := .u64, capacity := 100 }

/-- A Surface contract with a Set embedded as expanded state. -/
def setContract : SurfaceContract := {
  name := "SetRegistry",
  structs := #[],
  state := testSet.expand.toList.toArray,
  events := #[],
  errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[], retType := .unit,
      body := #[
        .stateWrite "$surface.set.0.cardinality" (.literal (.u64Lit 0))
      ]
    },
    { name := "getCardinality", kind := .function, mutability := .view,
      params := #[], retType := .u64,
      body := #[
        .returnExpr (.stateRead "$surface.set.0.cardinality")
      ]
    }
  ],
  constructorParams := #[],
  constructorBindings := #[],
  intents := #[]
}

def main : IO Unit := do
  /- Check 1: Set expands to two state declarations. -/
  let expanded := testSet.expand
  require (expanded.size == 2) "Set should expand to 2 state declarations"
  require (expanded[0]!.name == "$surface.set.0.members")
    "members name mismatch"
  require (expanded[1]!.name == "$surface.set.0.cardinality")
    "cardinality name mismatch"

  /- Check 2: Capacity zero rejects. -/
  match SurfaceSetDecl.validate { id := 1, elementType := .u64, capacity := 0 } with
  | Except.error _ => pure ()
  | Except.ok _ => throw <| IO.userError "Capacity zero should reject"

  /- Check 3: Valid capacity accepts. -/
  match SurfaceSetDecl.validate testSet with
  | Except.ok _ => pure ()
  | Except.error e => throw <| IO.userError s!"Valid set should accept: {e}"

  /- Check 4: Contract with expanded set state normalizes. -/
  match normalizeSurface setContract with
  | Except.ok bundle =>
    require (bundle.contract.contract.module.state.size == 2)
      "Module should have 2 state declarations"
    require (bundle.contract.contract.module.functions.size == 2)
      "Module should have 2 functions"
  | Except.error e => throw <| IO.userError s!"Set contract normalize failed: {repr e}"

  /- Check 5: Generated names use $surface.set. prefix. -/
  let membersName := testSet.membersName
  let cardName := testSet.cardinalityName
  require (membersName.startsWith "$surface.set.") "members name should use $surface.set. prefix"
  require (cardName.startsWith "$surface.set.") "cardinality name should use $surface.set. prefix"

  IO.println "set-normalize: ok"