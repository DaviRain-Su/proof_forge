import ProofForge.Frontend.Surface
import ProofForge.Frontend.Authored.Normalize
import ProofForge.IR.Examples.Counter
import ProofForge.Contract.Spec

/-! Task 13 normalization coverage for the independent Surface AST. -/

open ProofForge.Frontend.Surface
open ProofForge.IR.Core
open ProofForge.Frontend.Authored.Normalize

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def expectFailure (label : String) (contract : SurfaceContract) : IO Unit :=
  match normalizeSurface contract with
  | .ok _ => throw <| IO.userError s!"{label}: expected normalization failure"
  | .error _ => pure ()

def surfaceCounter : SurfaceContract := {
  name := "Counter"
  structs := #[]
  state := #[{ name := "count", kind := .scalar .u64 }]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call, selector? := some "8129fc1c",
      params := #[], retType := .unit,
      body := #[.stateWrite "count" (.literal (.u64Lit 0))] },
    { name := "increment", kind := .function, mutability := .call, selector? := some "d09de08a",
      params := #[], retType := .unit,
      body := #[.stateWrite "count" (.arith .add true
        (.stateRead "count") (.literal (.u64Lit 1)))] },
    { name := "get", kind := .function, mutability := .view, selector? := some "6d4ce63c",
      params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "count")] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
  intents := #[
    { kind := .module, operation := .builtin "Counter" },
    { kind := .state, operation := .builtin "count" },
    { kind := .entrypoint, operation := .builtin "initialize" },
    { kind := .entrypoint, operation := .builtin "increment" },
    { kind := .entrypoint, operation := .builtin "get" },
    { kind := .capability, operation := .builtin "storage.scalar", capability? := some .storageScalar },
    { kind := .capability, operation := .builtin "storage.scalar", capability? := some .storageScalar },
    { kind := .capability, operation := .builtin "storage.scalar", capability? := some .storageScalar },
    { kind := .capability, operation := .builtin "storage.scalar", capability? := some .storageScalar }
  ]
}

def surfaceVault : SurfaceContract := {
  name := "ValueVault"
  structs := #[]
  state := #[
    { name := "balance", kind := .scalar .u64 },
    { name := "released", kind := .scalar .u64 }
  ]
  events := #[
    { name := "Deposited", fields := #[{ name := "amount", type := .u64, indexed := false }] },
    { name := "Released", fields := #[{ name := "amount", type := .u64, indexed := false }] }
  ]
  errors := #[]
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      params := #[{ name := "initial", type := .u64 }], retType := .unit,
      body := #[
        .stateWrite "balance" (.local "initial"),
        .stateWrite "released" (.literal (.u64Lit 0))] },
    { name := "deposit", kind := .function, mutability := .call,
      params := #[{ name := "amount", type := .u64 }], retType := .unit,
      body := #[
        .stateWrite "balance" (.arith .add true (.stateRead "balance") (.local "amount")),
        .emit "Deposited" #[.local "amount"]] },
    { name := "release", kind := .function, mutability := .call,
      params := #[{ name := "amount", type := .u64 }], retType := .unit,
      body := #[
        .stateWrite "balance" (.arith .sub true (.stateRead "balance") (.local "amount")),
        .stateWrite "released" (.arith .add true (.stateRead "released") (.local "amount")),
        .emit "Released" #[.local "amount"]] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

def main : IO Unit := do
  let counter ← match normalizeSurface surfaceCounter with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"Counter normalization failed: {repr e}"
  require (counter.contract.contract.module.functions.size == 3) "Counter function count"
  let legacyCounter ← match normalizeContractSpec
      (ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"Legacy Counter adaptation failed: {repr e}"
  let surfaceCanonical := counter.contract.contract
  let legacyCanonical := legacyCounter.contract.contract
  require (surfaceCanonical.module == legacyCanonical.module)
    s!"Surface/Legacy Counter module mismatch:\n{repr surfaceCanonical.module}\n{repr legacyCanonical.module}"
  require (surfaceCanonical.interface == legacyCanonical.interface) "Surface/Legacy Counter interface mismatch"
  require (surfaceCanonical.materialization == legacyCanonical.materialization)
    s!"Surface/Legacy Counter materialization mismatch:\n{repr surfaceCanonical.materialization}\n{repr legacyCanonical.materialization}"
  require (surfaceCanonical.requirements == legacyCanonical.requirements) "Surface/Legacy Counter requirements mismatch"

  let vault ← match normalizeSurface surfaceVault with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"ValueVault normalization failed: {repr e}"
  require (vault.contract.contract.module.state.size == 2) "ValueVault state count"
  require (vault.contract.contract.module.events.size == 2) "ValueVault event count"

  expectFailure "duplicate state" { surfaceCounter with state := surfaceCounter.state ++ surfaceCounter.state }
  expectFailure "reserved namespace" { surfaceCounter with
    state := #[{ name := "$surface.count", kind := .scalar .u64 }] }
  expectFailure "unknown state" { surfaceCounter with entrypoints := #[{
    name := "get", kind := .function, mutability := .view, params := #[], retType := .u64,
    body := #[.returnExpr (.stateRead "missing")] }] }
  expectFailure "missing return" { surfaceCounter with entrypoints := #[{
    name := "get", kind := .function, mutability := .view, params := #[], retType := .u64,
    body := #[] }] }
  expectFailure "out of range literal" { surfaceCounter with entrypoints := #[{
    name := "bad", kind := .function, mutability := .call, params := #[], retType := .unit,
    body := #[.bind "x" .u8 (.literal (.u8Lit 256))] }] }
  expectFailure "store type mismatch" { surfaceCounter with entrypoints := #[{
    name := "bad", kind := .function, mutability := .call, params := #[], retType := .unit,
    body := #[.stateWrite "count" (.literal (.boolLit true))] }] }

  let orderContract : SurfaceContract := { surfaceCounter with entrypoints := #[{
    name := "ordered", kind := .function, mutability := .view, params := #[], retType := .bool,
    body := #[.returnExpr (.compare .lt (.stateRead "count") (.stateRead "count"))] }] }
  let ordered ← match normalizeSurface orderContract with
    | .ok bundle => match bundle.contract.contract.module.functions[0]? with
      | some function => pure function
      | none => throw <| IO.userError "ordered function missing"
    | .error e => throw <| IO.userError s!"ordered normalization failed: {repr e}"
  let instructions ← match ordered.blocks[0]? with
    | some block => pure block.instructions
    | none => throw <| IO.userError "ordered entry block missing"
  require (instructions.size == 3) "effectful comparison must normalize to load, load, compare"
  match instructions[0]!.op, instructions[1]!.op, instructions[2]!.op with
  | .storageLoad _, .storageLoad _, .pure (.compare _ _ _) => pure ()
  | _, _, _ => throw <| IO.userError "effectful expression order changed"

  let loopContract : SurfaceContract := { surfaceCounter with entrypoints := #[{
    name := "loop", kind := .function, mutability := .call, params := #[], retType := .unit,
    body := #[.boundedLoop "i" 2 5 #[.bind "copy" .u64 (.local "i")]] }] }
  let loopBundle ← match normalizeSurface loopContract with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"loop normalization failed: {repr e}"
  let loopFunction ← match loopBundle.contract.contract.module.functions[0]? with
    | some function => pure function
    | none => throw <| IO.userError "loop function missing"
  let hasBound := loopFunction.blocks.any fun block =>
    match block.terminator with
    | .jump _ _ (some (.atMost 3)) => true
    | _ => false
  require hasBound "bounded loop lost LoopBound.atMost"

  IO.println "surface-normalize: ok"
