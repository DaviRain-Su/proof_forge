import ProofForge.IR.Semantics
import ProofForge.IR.Core.Semantics
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Legacy.Refinement
import ProofForge.Contract.Spec
import Std

namespace Tests.Canonical.LegacyParity

open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics
open ProofForge.IR.Legacy.Adapter
open ProofForge.IR.Legacy.Refinement
open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def expectBundle (spec : ContractSpec) : IO ProofForge.IR.Canonical.CanonicalBundle :=
  match adaptLegacy spec with
  | .ok b => pure b
  | .error e => throw <| IO.userError s!"adapt failed: {repr e}"

/-- Host semantics that stubs the context fields used by the fixtures.
Crosscalls and hashes remain unsupported, matching the scalar fragment. -/
def testHostSemantics : HostSemantics where
  handle _ _ _ := .error (.unknownHostOp { namespace_ := "test", name := "unknown", version := { major := 1, minor := 0, patch := 0 } })
  handleContext field :=
    match field with
    | .sender | .signer | .contractAddress => .ok (.address "")
    | .blockNumber | .blockTimestamp | .gas => .ok (.u64 0)
    | .value => .ok (.u128 0)
  handleHash _ := .error .unsupportedHash
  handleCrosscall request _ := .error (.unsupportedCrosscall request.mode)

def runStep (spec : ContractSpec) (entrypointName : String)
    (args : Array ProofForge.IR.Semantics.Value)
    (legacyState : ProofForge.IR.Semantics.State) (coreState : LogicalState)
    (expectedReturn? : Option CoreValue) :
    IO (ProofForge.IR.Semantics.State × LogicalState) := do
  let legacyState := { legacyState with logs := #[] }
  let legacyRes := executeLegacyEntrypoint spec entrypointName args legacyState
  let bundle ← expectBundle spec
  let coreArgs := args.map (fun v => (legacyToCoreValue v).getD .unit)
  let idx := spec.module.entrypoints.findIdx? (·.name == entrypointName) |>.getD 0
  let coreRes := execute testHostSemantics 100 bundle.contract ⟨idx⟩ coreArgs coreState
  unless observableMatch spec legacyRes coreRes do
    throw <| IO.userError s!"observable mismatch at `{entrypointName}`:\n  legacy={repr legacyRes}\n  core={repr coreRes}"
  match legacyRes, coreRes with
  | .ok (ls, _), .ok cr =>
      match expectedReturn? with
      | none => pure ()
      | some expected =>
          unless cr.returnValue == expected do
            throw <| IO.userError s!"unexpected return value at `{entrypointName}`: {repr cr.returnValue} ≠ {repr expected}"
      return (ls, cr.finalState)
  | _, _ =>
      throw <| IO.userError s!"expected ok at `{entrypointName}`"

def expectErrorStep (spec : ContractSpec) (entrypointName : String)
    (args : Array ProofForge.IR.Semantics.Value)
    (legacyState : ProofForge.IR.Semantics.State) (coreState : LogicalState) :
    IO Unit := do
  let legacyState := { legacyState with logs := #[] }
  let legacyRes := executeLegacyEntrypoint spec entrypointName args legacyState
  let bundle ← expectBundle spec
  let coreArgs := args.map (fun v => (legacyToCoreValue v).getD .unit)
  let idx := spec.module.entrypoints.findIdx? (·.name == entrypointName) |>.getD 0
  let coreRes := execute testHostSemantics 100 bundle.contract ⟨idx⟩ coreArgs coreState
  unless observableMatch spec legacyRes coreRes do
    throw <| IO.userError s!"observable mismatch at error `{entrypointName}`:\n  legacy={repr legacyRes}\n  core={repr coreRes}"
  match legacyRes, coreRes with
  | .ok _, .ok _ => throw <| IO.userError s!"expected error at `{entrypointName}`"
  | _, _ => pure ()

def counterSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.Counter.module

def vaultSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module

def runCounterScenario : IO Unit := do
  let (s1, c1) ← runStep counterSpec "initialize" #[]
    ProofForge.IR.Semantics.State.empty { storage := fun _ => none } none
  let (s2, c2) ← runStep counterSpec "increment" #[] s1 c1 none
  let (s3, c3) ← runStep counterSpec "increment" #[] s2 c2 none
  let _ ← runStep counterSpec "get" #[] s3 c3 (some (.u64 2))
  pure ()

def runValueVaultScenario : IO Unit := do
  let (s1, c1) ← runStep vaultSpec "initialize" #[.u64 100]
    ProofForge.IR.Semantics.State.empty { storage := fun _ => none } none
  let (s2, c2) ← runStep vaultSpec "deposit" #[.u64 25] s1 c1 none
  let (s3, c3) ← runStep vaultSpec "charge_fee" #[.u64 10, .u64 500] s2 c2 none
  let (s4, c4) ← runStep vaultSpec "release" #[.u64 5] s3 c3 none
  let (s5, c5) ← runStep vaultSpec "snapshot" #[] s4 c4 (some (.u64 130))
  let (s6, c6) ← runStep vaultSpec "get_balance" #[] s5 c5 (some (.u64 130))
  let _ ← runStep vaultSpec "get_net_value" #[] s6 c6 (some (.u64 130))
  pure ()

/- Counter checked-overflow fixture: incrementing u64::max produces an
out-of-range legacy value, which the runner reclassifies as an arithmetic
overflow revert. Core rejects the same operation with `arithmeticOverflow`. -/

def counterOverflowModule : ProofForge.IR.Module := {
  name := "CounterOverflow",
  state := #[{ id := "count", kind := .scalar, type := .u64 }],
  entrypoints := #[{
    name := "overflow",
    body := #[
      .effect (.storageScalarWrite "count" (.literal (.u64 u64Max))),
      .effect (.storageScalarWrite "count" (.add (.effect (.storageScalarRead "count")) (.literal (.u64 1))))
    ]
  }]
}

def runCounterOverflowScenario : IO Unit := do
  let spec := ContractSpec.fromIR counterOverflowModule
  expectErrorStep spec "overflow" #[]
    ProofForge.IR.Semantics.State.empty { storage := fun _ => none }

/- ValueVault release-beyond-balance fixture: an explicit assertion keeps the
legacy and Core error paths aligned (assertion failure / assertionFailure). -/

def releaseAssertModule : ProofForge.IR.Module := {
  name := "ValueVaultReleaseAssert",
  state := #[
    { id := "balance", kind := .scalar, type := .u64 },
    { id := "released", kind := .scalar, type := .u64 }
  ],
  entrypoints := #[
    {
      name := "initialize",
      body := #[
        .effect (.storageScalarWrite "balance" (.literal (.u64 100))),
        .effect (.storageScalarWrite "released" (.literal (.u64 0)))
      ]
    },
    {
      name := "release",
      params := #[("amount", .u64)],
      body := #[
        .assert (.le (.local "amount") (.effect (.storageScalarRead "balance")))
          "release exceeds balance" none,
        .letBind "current" .u64 (.effect (.storageScalarRead "balance")),
        .letBind "next" .u64 (.sub (.local "current") (.local "amount")),
        .effect (.storageScalarWrite "balance" (.local "next")),
        .letBind "released_before" .u64 (.effect (.storageScalarRead "released")),
        .letBind "released_next" .u64 (.add (.local "released_before") (.local "amount")),
        .effect (.storageScalarWrite "released" (.local "released_next"))
      ]
    }
  ]
}

def runVaultReleaseErrorScenario : IO Unit := do
  let spec := ContractSpec.fromIR releaseAssertModule
  let (s1, c1) ← runStep spec "initialize" #[]
    ProofForge.IR.Semantics.State.empty { storage := fun _ => none } none
  expectErrorStep spec "release" #[.u64 200] s1 c1

end Tests.Canonical.LegacyParity

def main : IO UInt32 := do
  Tests.Canonical.LegacyParity.runCounterScenario
  Tests.Canonical.LegacyParity.runValueVaultScenario
  Tests.Canonical.LegacyParity.runCounterOverflowScenario
  Tests.Canonical.LegacyParity.runVaultReleaseErrorScenario
  IO.println "Tests.Canonical.LegacyParity: ok"
  return 0
