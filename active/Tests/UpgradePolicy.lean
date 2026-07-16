import ProofForge.Contract.Spec.Json
import ProofForge.IR.Examples.Counter
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.UpgradePolicy

open ProofForge.Contract
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def counterSpecWith (policy : UpgradePolicy) : ContractSpec := {
  ContractSpec.fromIR ProofForge.IR.Examples.Counter.module with
  upgradePolicy? := some policy
}

def metadataValue? (plan : CapabilityPlan) (key : String) : Option String :=
  plan.metadata.find? (fun item => item.key == key) |>.map fun item => item.value

def requireResolves (profile : TargetProfile) (spec : ContractSpec) : IO CapabilityPlan :=
  match resolveSpec profile spec with
  | .ok plan => pure plan
  | .error err => throw <| IO.userError s!"{profile.id} unexpectedly rejected spec: {err.render}"

def requireRejects (profile : TargetProfile) (spec : ContractSpec) (needle : String) : IO Unit :=
  match resolveSpec profile spec with
  | .ok _ => throw <| IO.userError s!"{profile.id} unexpectedly accepted unsupported upgrade policy"
  | .error err =>
      require (err.render.contains needle)
        s!"{profile.id} diagnostic `{err.render}` did not contain `{needle}`"

def testResolverMatrix : IO Unit := do
  let immutable := counterSpecWith .immutable
  let authority := counterSpecWith (.authority "deploy/main")
  let governance := counterSpecWith (.governance "dao/main")

  discard <| requireResolves evm immutable
  requireRejects evm authority "does not materialize `authority`"
  requireRejects evm governance "EVM target does not support `governance`"

  let baseAuthority := counterSpecWith (.authority "admin")
  let uupsAuthority : ContractSpec := {
    baseAuthority with
    proxyPattern? := some .uups
    module := { baseAuthority.module with proxyPattern? := some "uups" }
  }
  requireRejects evm uupsAuthority "does not materialize `authority`"

  let solanaPlan ← requireResolves solanaSbpfAsm authority
  require (metadataValue? solanaPlan "upgrade.policy.kind" == some "authority")
    "Solana authority plan missing upgrade.policy.kind metadata"
  require (metadataValue? solanaPlan "upgrade.policy.key_ref" == some "deploy/main")
    "Solana authority plan missing upgrade.policy.key_ref metadata"
  requireRejects solanaSbpfAsm governance "Solana target does not support `governance`"

  let nearPlan ← requireResolves wasmNear authority
  require (metadataValue? nearPlan "upgrade.policy.kind" == some "authority")
    "NEAR authority plan missing upgrade.policy.kind metadata"
  require (metadataValue? nearPlan "upgrade.policy.key_ref" == some "deploy/main")
    "NEAR authority plan missing upgrade.policy.key_ref metadata"
  requireRejects wasmNear governance "NEAR target does not support `governance`"

  discard <| requireResolves psyDpn immutable
  requireRejects psyDpn authority "Psy DPN target only supports `immutable` upgrade policy"

def testJsonEscaping : IO Unit := do
  let spec := counterSpecWith (.authority "deploy/\"main\\key")
  let json := ProofForge.Contract.Spec.Json.render spec
  require (json.contains "\"upgradePolicy\"")
    "ContractSpec JSON missing upgradePolicy field"
  require (json.contains "\"kind\":\"authority\"")
    "ContractSpec JSON missing authority kind"
  require (json.contains "\"keyRef\":\"deploy/\\\"main\\\\key\"")
    s!"ContractSpec JSON did not escape upgrade policy keyRef correctly: {json}"

def main : IO UInt32 := do
  testResolverMatrix
  testJsonEscaping
  IO.println "upgrade-policy: ok"
  return 0

end ProofForge.Tests.UpgradePolicy

def main : IO UInt32 :=
  ProofForge.Tests.UpgradePolicy.main
