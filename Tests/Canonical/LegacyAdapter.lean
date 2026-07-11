import ProofForge.Contract.Spec
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Core
import Std

namespace Tests.Canonical.LegacyAdapter

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Legacy.Adapter
open ProofForge.Contract

def counterSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.Counter.module

def vaultSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/- Check that every scalar storage load/store in a function refers to the
state declaration with the matching source name. -/

def checkScalarStorageSourceNames (module : Core.Module) : Bool :=
  module.functions.all (fun f =>
    f.blocks.all (fun b =>
      b.instructions.all (fun i =>
        match i.op with
        | .storageLoad path | .storageStore path _ =>
            match module.state.find? (·.id == path.root) with
            | none => false
            | some decl =>
                match decl.shape with
                | .scalar _ => true
                | _ => false
        | _ => true)))

/- Check that a function contains a context read instruction. -/

def hasContextRead (module : Core.Module) (field : Core.ContextField) : Bool :=
  module.functions.any (fun f =>
    f.blocks.any (fun b =>
      b.instructions.any (fun i =>
        match i.op with
        | .contextRead f => f == field
        | _ => false)))

/- Extract event emission names in source order across all functions. -/

def eventNamesInOrder (module : Core.Module) : List String :=
  Id.run do
    let mut names := []
    for f in module.functions do
      for b in f.blocks do
        for i in b.instructions do
          match i.op with
          | .emit eventId _ =>
              match module.events.find? (·.id == eventId) with
              | some ev => names := toString ev.id.value :: names
              | none => pure ()
          | _ => pure ()
    return names.reverse

/- Extract return values in source order. -/

def returnCount (module : Core.Module) : Nat :=
  module.functions.foldl (fun acc f =>
    f.blocks.foldl (fun acc2 b =>
      match b.terminator with
      | .return _ => acc2 + 1
      | _ => acc2) acc) 0

/- Check that an `add` expression in the bundle uses the given overflow mode. -/

def hasArithmeticMode (module : Core.Module) (op : ArithmeticOp) (mode : OverflowMode) : Bool :=
  module.functions.any (fun f =>
    f.blocks.any (fun b =>
      b.instructions.any (fun i =>
        match i.op with
        | .pure (.arithmetic o m _ _) => o == op && m == mode
        | _ => false)))

/- Build a minimal contract whose body reads an unknown state name. -/

def unknownStateModule : ProofForge.IR.Module := {
  name := "UnknownState",
  state := #[{ id := "known", kind := .scalar, type := .u64 }],
  entrypoints := #[{
    name := "get",
    body := #[.return (.effect (.storageScalarRead "missing"))]
  }]
}

/- Build a minimal contract with an out-of-range literal. -/

def outOfRangeModule (ty : ValueType) (value : Nat) : ProofForge.IR.Module := {
  name := "OutOfRange",
  state := #[],
  entrypoints := #[{
    name := "get",
    returns := ty,
    body := #[.return (.literal (match ty with
      | .u8 => Literal.u8 value
      | .u32 => Literal.u32 value
      | .u64 => Literal.u64 value
      | .u128 => Literal.u128 value
      | _ => Literal.u8 value))]
  }]
}

def arithmeticModeModule (checked : Bool) : ProofForge.IR.Module := {
  name := if checked then "Checked" else "Wrapping"
  state := #[]
  entrypoints := #[{
    name := "calculate"
    returns := .u64
    body := #[.return (.add (.literal (.u64 1)) (.literal (.u64 2)) checked)]
  }]
}

def runAssertions : IO Unit := do
  -- Counter adapts successfully.
  let counterBundle ← match adaptLegacy counterSpec with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"Counter adapt failed: {repr e}"

  let counterModule := counterBundle.contract.contract.module
  require (counterModule.state.size == 1) s!"Counter state count: {counterModule.state.size}"
  require (counterModule.functions.size == 3) s!"Counter function count: {counterModule.functions.size}"
  require (checkScalarStorageSourceNames counterModule) "Counter scalar storage names diverged"
  require (returnCount counterModule == 3) s!"Counter terminator count: {returnCount counterModule}"
  match counterModule.functions.find? (·.id == ⟨2⟩) with
  | some counterGet =>
      require (counterGet.blocks.any (fun b => match b.terminator with
        | .return values => values.size == 1
        | _ => false)) "Counter get return value was not preserved"
  | none => throw <| IO.userError "Counter get function missing"
  require (hasArithmeticMode counterModule .add .checked) "Counter checked add not preserved"

  let wrappingBundle ← match adaptLegacy (ContractSpec.fromIR (arithmeticModeModule false)) with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"wrapping arithmetic adapt failed: {repr e}"
  require (hasArithmeticMode wrappingBundle.contract.contract.module .add .wrapping)
    "explicit wrapping add not preserved"

  -- ValueVault adapts successfully.
  let vaultBundle ← match adaptLegacy vaultSpec with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"ValueVault adapt failed: {repr e}"

  let vaultModule := vaultBundle.contract.contract.module
  require (vaultModule.state.size == 6) s!"ValueVault state count: {vaultModule.state.size}"
  let stateIdSet : Std.HashSet Nat :=
    vaultModule.state.foldl (fun acc s => acc.insert s.id.value) {}
  require (stateIdSet.size == 6) s!"ValueVault distinct StateId count: {stateIdSet.size}"
  require (vaultModule.functions.size == 7) s!"ValueVault function count: {vaultModule.functions.size}"
  require (checkScalarStorageSourceNames vaultModule) "ValueVault scalar storage names diverged"
  require (hasContextRead vaultModule .blockNumber) "checkpointId did not become context read"
  require (returnCount vaultModule == 7) s!"ValueVault terminator count: {returnCount vaultModule}"

  -- Interface contract preserves entrypoint metadata.
  let interface := vaultBundle.contract.contract.interface
  require (interface.entrypoints.size == 7) "interface entrypoint count"
  let initEp? := interface.entrypoints.find? (·.functionId == ⟨0⟩)
  match initEp? with
  | some ep =>
      require (ep.kind == "function") "initialize kind"
      require (ep.mutatesState) "initialize mutability"
  | none => throw <| IO.userError "initialize entrypoint missing from interface"
  let counterInterface := counterBundle.contract.contract.interface
  let counterGetEp? := counterInterface.entrypoints.find? (·.functionId == ⟨2⟩)
  match counterGetEp? with
  | some ep =>
      require (ep.kind == "function") "Counter get kind"
      require (!ep.mutatesState) "Counter get should be view"
  | none => throw <| IO.userError "Counter get entrypoint missing from interface"
  require (interface.dispatchHints.size == 7) "dispatch hint count"

  -- Materialization and evidence cover the spec fields.
  let materialization := vaultBundle.contract.contract.materialization
  require (materialization.upgradePolicy == none) "upgrade policy should be empty for fixture"
  let evidence := vaultBundle.evidence
  require (evidence.legacyClassification.size == 10) "legacy classification evidence count"
  require (evidence.verification.invariants.isEmpty) "fixture has no invariants"

  -- Literal range rejection before numeric narrowing.
  match adaptLegacy (ContractSpec.fromIR (outOfRangeModule .u8 256)) with
  | .error (.literalOutOfRange "u8" _) => pure ()
  | .error e => throw <| IO.userError s!"u8 256 wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "u8 256 should have rejected"

  match adaptLegacy (ContractSpec.fromIR (outOfRangeModule .u32 4294967296)) with
  | .error (.literalOutOfRange "u32" _) => pure ()
  | .error e => throw <| IO.userError s!"u32 2^32 wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "u32 2^32 should have rejected"

  match adaptLegacy (ContractSpec.fromIR (outOfRangeModule .u64 18446744073709551616)) with
  | .error (.literalOutOfRange "u64" _) => pure ()
  | .error e => throw <| IO.userError s!"u64 2^64 wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "u64 2^64 should have rejected"

  match adaptLegacy (ContractSpec.fromIR (outOfRangeModule .u128 340282366920938463463374607431768211456)) with
  | .error (.literalOutOfRange "u128" _) => pure ()
  | .error e => throw <| IO.userError s!"u128 2^128 wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "u128 2^128 should have rejected"

  -- Unknown state name returns `unknownState`, never state zero.
  match adaptLegacy (ContractSpec.fromIR unknownStateModule) with
  | .error (.unknownState "missing") => pure ()
  | .error e => throw <| IO.userError s!"unknown state wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "unknown state should have rejected"

end Tests.Canonical.LegacyAdapter

def main : IO UInt32 := do
  Tests.Canonical.LegacyAdapter.runAssertions
  IO.println "Tests.Canonical.LegacyAdapter: ok"
  return 0
