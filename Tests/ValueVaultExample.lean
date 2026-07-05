import ProofForge.Backend.Solana.Package
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.ValueVaultExample

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def hasCapability (plan : CapabilityPlan) (capability : Capability) : Bool :=
  plan.capabilities.any (fun item => item == capability)

def requireCapability (plan : CapabilityPlan) (capability : Capability) : IO Unit :=
  require (hasCapability plan capability)
    s!"ValueVault plan for `{plan.targetId}` missing capability `{capability.id}`"

def noSolanaMetadata (plan : CapabilityPlan) : Bool :=
  plan.calls.all (fun call =>
    call.metadata.all (fun item => !item.key.startsWith "solana."))

def eventNamesInStatement : ProofForge.IR.Statement → Array String
  | .effect (.eventEmit name _) => #[name]
  | .effect (.eventEmitIndexed name _ _) => #[name]
  | .ifElse _ thenBody elseBody =>
      thenBody.foldl (fun acc stmt => acc ++ eventNamesInStatement stmt) #[] ++
        elseBody.foldl (fun acc stmt => acc ++ eventNamesInStatement stmt) #[]
  | .boundedFor _ _ _ body =>
      body.foldl (fun acc stmt => acc ++ eventNamesInStatement stmt) #[]
  | _ => #[]

def eventNamesInModule (module : ProofForge.IR.Module) : Array String :=
  module.entrypoints.foldl
    (fun acc entrypoint =>
      acc ++ entrypoint.body.foldl (fun names stmt => names ++ eventNamesInStatement stmt) #[])
    #[]

def routableTargets : Array TargetProfile := #[
  evm,
  wasmNear,
  wasmCosmWasm,
  solanaSbpfAsm,
  solanaSbpfLinker,
  solanaZigFork,
  moveAptos,
  psyDpn
]

def requireRoutableTarget (profile : TargetProfile) : IO Unit := do
  let plan ←
    match resolveSpec profile ProofForge.Contract.Examples.ValueVault.spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"ValueVault routing failed for `{profile.id}`: {err.render}"
  require (plan.targetId == profile.id) s!"ValueVault target id mismatch for `{profile.id}`"
  requireCapability plan .storageScalar
  requireCapability plan .eventsEmit
  requireCapability plan .envBlock
  require (noSolanaMetadata plan)
    s!"ValueVault should not carry Solana target-extension metadata for `{profile.id}`"

def requireSuiMvpRejectsValueVault : IO Unit := do
  match resolveSpec moveSui ProofForge.Contract.Examples.ValueVault.spec with
  | .ok _ =>
      throw <| IO.userError "ValueVault should not route through move-sui Counter MVP"
  | .error err =>
      let rendered := err.render
      require (contains rendered "move-sui")
        s!"move-sui ValueVault diagnostic missing target id: {rendered}"
      require (contains rendered "env.block" || contains rendered "events.emit")
        s!"move-sui ValueVault diagnostic missing unsupported capability: {rendered}"

def requireModuleShape : IO Unit := do
  let module := ProofForge.Contract.Examples.ValueVault.module
  require (module.name == "ValueVault") "ValueVault module name mismatch"
  require (module.state.size == 6) "ValueVault should have six scalar state fields"
  let stateIds := module.state.map (fun state => state.id)
  require (stateIds == #[
    "balance",
    "released",
    "fees",
    "last_value",
    "last_checkpoint",
    "operations"
  ]) s!"ValueVault state declaration macro ids mismatch: {stateIds}"
  require (module.entrypoints.size == 7) "ValueVault should have seven entrypoints"
  require (module.entrypoints.all (fun entrypoint => entrypoint.selector?.isNone))
    "ValueVault surface source should defer target selectors to emission"
  let names := module.entrypoints.map (fun entrypoint => entrypoint.name)
  require (names == #[
    "initialize",
    "deposit",
    "charge_fee",
    "release",
    "snapshot",
    "get_balance",
    "get_net_value"
  ]) s!"ValueVault entrypoint order mismatch: {names}"
  let some chargeFee := module.entrypoints.find? (fun entrypoint => entrypoint.name == "charge_fee")
    | throw <| IO.userError "ValueVault missing charge_fee entrypoint"
  let chargeFeeParams := chargeFee.params.map (fun param => param.fst)
  require (chargeFeeParams == #["gross", "fee_bps"])
    s!"ValueVault method declaration macro params mismatch: {chargeFeeParams}"
  let eventNames := eventNamesInModule module
  require (eventNames.contains "ValueDeposited")
    "ValueVault source event should lower ValueDeposited into IR"
  require (eventNames.contains "ValueSnapshot")
    "ValueVault source event should lower ValueSnapshot into IR"

def requireSolanaRender : IO Unit := do
  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "portable-value-vault" ProofForge.Contract.Examples.ValueVault.spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "ValueVault Solana package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "ValueVault Solana package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "name = \"deposit\"")
        "ValueVault Solana manifest missing deposit instruction"
      require (contains manifest "name = \"charge_fee\"")
        "ValueVault Solana manifest missing charge_fee instruction"
      require (contains manifest "name = \"snapshot\"")
        "ValueVault Solana manifest missing snapshot instruction"
      require (contains manifest "{ name = \"amount\", type = \"U64\", offset = 1, byte_size = 8, encoding = \"le-u64\" }")
        "ValueVault Solana manifest missing amount parameter schema"
      require (contains asm "solana.event.emit ValueDeposited: sol_log_64_ scalar fields")
        "ValueVault Solana assembly missing ValueDeposited event"
      require (contains asm "solana.event.emit ValueSnapshot: sol_log_64_ scalar fields")
        "ValueVault Solana assembly missing ValueSnapshot event"
      require (contains asm "solana.sysvar.clock: sol_get_clock_sysvar -> Clock.slot")
        "ValueVault Solana assembly missing checkpoint lowering"
      require (contains asm "call sol_log_64_")
        "ValueVault Solana assembly missing event log syscall"
      require (contains asm "call sol_get_clock_sysvar")
        "ValueVault Solana assembly missing clock sysvar syscall"
  | .error err =>
      throw <| IO.userError s!"ValueVault Solana render failed: {err.render}"

def main : IO UInt32 := do
  requireModuleShape
  for profile in routableTargets do
    requireRoutableTarget profile
  requireSuiMvpRejectsValueVault
  requireSolanaRender
  IO.println "value-vault-example: ok"
  return 0

end ProofForge.Tests.ValueVaultExample

def main : IO UInt32 :=
  ProofForge.Tests.ValueVaultExample.main
