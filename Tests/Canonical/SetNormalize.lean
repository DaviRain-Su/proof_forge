import ProofForge.Frontend.Surface
import Examples.Product.Canonical.SetRegistry

/-! Task 15 structural normalization tests for bounded Surface sets. -/

open ProofForge.Frontend.Surface
open ProofForge.IR.Core

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def testSet := Examples.Product.Canonical.SetRegistry.registry
def setContract := Examples.Product.Canonical.SetRegistry.contract

def main : IO Unit := do
  let expanded := testSet.expand
  require (expanded.size == 2) "Set expansion size"
  require (expanded[0]!.name == testSet.membersName && expanded[0]!.generated) "members name/provenance"
  require (expanded[1]!.name == testSet.cardinalityName && expanded[1]!.generated) "cardinality name/provenance"
  match expanded[0]!.kind with
  | .map .u64 .bool (some 100) => pure ()
  | shape => throw <| IO.userError s!"wrong members shape: {repr shape}"
  match SurfaceSetDecl.validate { id := 1, elementType := .u64, capacity := 0 } with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "zero-capacity Set accepted"

  let bundle ← match normalizeSurface setContract with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"Set normalization failed: {repr e}"
  require (bundle.contract.contract.module.state.size == 2) "Core Set state count"
  let insert ← match bundle.contract.contract.module.functions[1]? with
    | some function => pure function
    | none => throw <| IO.userError "Set insert function missing"
  let hasMapRead := insert.blocks.any fun block => block.instructions.any fun instruction =>
    match instruction.op with
    | .storageLoad { path := #[.mapKey _], .. } => true
    | _ => false
  let hasMapWrite := insert.blocks.any fun block => block.instructions.any fun instruction =>
    match instruction.op with
    | .storageStore { path := #[.mapKey _], .. } _ => true
    | _ => false
  require hasMapRead "Set insert emitted no Core map read"
  require hasMapWrite "Set insert emitted no Core map write"
  require (insert.blocks.any fun block => match block.terminator with | .branch _ _ _ => true | _ => false)
    "Set insert emitted no idempotency branch"

  let spoofed : SurfaceContract := { setContract with
    state := #[{ name := "$surface.set.7.members", kind := .map .u64 .bool (some 1) }] }
  match normalizeSurface spoofed with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "user-authored reserved Set state accepted"
  let collision : SurfaceContract := { setContract with state := testSet.expand ++ testSet.expand }
  match normalizeSurface collision with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "generated Set name collision accepted"

  IO.println "set-normalize: ok"
