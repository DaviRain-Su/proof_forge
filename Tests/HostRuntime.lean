/-
HostRuntime catalog smoke: primary triad bindings + support counts +
capability vs n/a honesty (shipped requireHostRuntimeHonesty / resolveModule).
-/
import ProofForge.Target.HostRuntime
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Contract.Spec
import ProofForge.Contract.Intent
import ProofForge.IR.Contract
import ProofForge.IR.Examples.EventProbe
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.Package

namespace ProofForge.Tests.HostRuntime

open ProofForge.Target
open ProofForge.Target.HostRuntime
open ProofForge.IR
open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

/-- Spec that *requests* `storage.pda` via intent (Solana-shaped HostEffect).
Uses shipped `resolveSpec` / HostRuntime honesty — not a hand-rolled gate. -/
def pdaClaimSpec : ContractSpec := {
  name := "HostRuntimePdaClaim"
  module := {
    name := "HostRuntimePdaClaim"
    state := #[]
    entrypoints := #[{ name := "touch", body := #[] }]
  }
  intents := #[Intent.capability .storagePda "solana.pda.derive"]
}

def main : IO UInt32 := do
  require (catalogId == "host.runtime") "catalog id"
  require (allEffects.size >= 16) "expected full effect catalog"
  require (primaryTargetIds.contains "evm") "primary includes evm"
  require (primaryTargetIds.contains "solana-sbpf-asm") "primary includes solana"
  require (primaryTargetIds.contains "wasm-near") "primary includes near"
  require (adapterTargetIds.contains "wasm-stellar-soroban") "adapter includes soroban"
  require (adapterTargetIds.contains "wasm-cosmwasm") "adapter includes cosmwasm"
  require (catalogTargetIds.size == 5) "catalog has 5 targets"

  -- Every effect has primary triad + adapter rows (even if symbol is n/a).
  for e in allEffects do
    require (e.bindings.size >= 5) s!"{e.id} should list ≥5 host bindings (3+2)"
    for tid in catalogTargetIds do
      require ((bindingsForTarget e tid).size == 1)
        s!"{e.id} should have exactly one binding row for {tid}"

  -- Core portable surface must be supported on all three.
  for e in #[HostEffect.storageRead, .storageWrite, .logEmit, .caller,
      .remoteInvoke, .assertFail, .returnDataSet] do
    require (supports e "evm") s!"evm must support {e.id}"
    require (supports e "solana-sbpf-asm") s!"solana must support {e.id}"
    require (supports e "wasm-near") s!"near must support {e.id}"

  -- PDA is Solana-native; NEAR n/a; EVM pdaFind n/a.
  require (supports .pda "solana-sbpf-asm") "solana PDA"
  require (!supports .pda "wasm-near") "near has no PDA"
  require (!supports .pdaFind "evm") "evm has no pdaFind"
  require (!supports .pdaFind "wasm-near") "near has no pdaFind"
  require (isNaSymbol "n/a") "n/a symbol helper"
  require (!capabilityHostHonest .storagePda "wasm-near")
    "storagePda not host-honest on near"
  require (capabilityHostHonest .storagePda "solana-sbpf-asm")
    "storagePda host-honest on solana"
  require (!capabilityHostHonest .storagePda "evm")
    "storagePda not fully honest on evm (pdaFind n/a)"

  -- Capability linkage for storage / remote.
  require (HostEffect.storageRead.capability? == some .storageScalar)
    "storageRead → storageScalar"
  require (HostEffect.remoteInvoke.capability? == some .crosscallInvoke)
    "remoteInvoke → crosscallInvoke"
  require (HostEffect.remoteInvokeSigned.capability? == some .crosscallCpi)
    "remoteInvokeSigned → crosscallCpi"
  require ((effectsForCapability .storagePda).any (· == .pda))
    "storagePda maps to host.pda effect"

  -- Spot-check native symbols.
  let logEvm := bindingsForTarget .logEmit "evm"
  require (logEvm.any (fun b => b.kind == .opcode && b.symbol.contains "log"))
    "evm log is opcode"
  let logSol := bindingsForTarget .logEmit "solana-sbpf-asm"
  require (logSol.any (fun b => b.kind == .syscall && b.symbol == "sol_log_64_"))
    "solana log is sol_log_64_"
  let logNear := bindingsForTarget .logEmit "wasm-near"
  require (logNear.any (fun b => b.kind == .hostImport && b.symbol == "env.log_utf8"))
    "near log is env.log_utf8"
  let cpi := bindingsForTarget .remoteInvokeSigned "solana-sbpf-asm"
  require (cpi.any (fun b => b.symbol == "sol_invoke_signed_c"))
    "solana signed remote is sol_invoke_signed_c"
  let call := bindingsForTarget .remoteInvoke "evm"
  require (call.any (fun b => b.symbol == "call")) "evm remote is call"
  let prom := bindingsForTarget .remoteInvoke "wasm-near"
  require (prom.any (fun b => b.symbol == "env.promise_create"))
    "near remote is promise_create"
  -- Wasm adapter remote symbols.
  require (supports .remoteInvoke "wasm-stellar-soroban") "soroban remote"
  require (supports .remoteInvoke "wasm-cosmwasm") "cosmwasm remote"
  require (supports .storageRead "wasm-stellar-soroban") "soroban storage read"
  require (supports .storageRead "wasm-cosmwasm") "cosmwasm storage read"
  require (!supports .pda "wasm-stellar-soroban") "soroban no PDA"
  require (!supports .logEmit "wasm-cosmwasm")
    "cosmwasm log is n/a in HostBridge inventory (honest)"
  let ref := catalogRefComment .logEmit "solana-sbpf-asm"
  require (contains ref "HostRuntime") "catalogRefComment names HostRuntime"
  require (contains ref "host.log.emit") "catalogRefComment names effect id"
  require (contains ref "sol_log_64_") "catalogRefComment names sol_log_64_"

  -- Pure honesty helper: NEAR + storage.pda → clear HostRuntime error.
  match requireHostRuntimeHonesty "wasm-near" #[.storagePda] with
  | .ok () => throw (IO.userError "NEAR+storagePda must not pass HostRuntime honesty")
  | .error msg =>
      require (contains msg "HostRuntime") "reject names HostRuntime"
      require (contains msg "wasm-near") "reject names target"
      require (contains msg "storage.pda" || contains msg "host.pda")
        "reject names capability/effect"
      require (contains msg "n/a" || contains msg "no native binding")
        "reject mentions n/a binding"

  -- EVM + storage.pda fails honesty (pdaFind is n/a) even though create2 exists.
  match requireHostRuntimeHonesty "evm" #[.storagePda] with
  | .ok () => throw (IO.userError "EVM+storagePda must fail HostRuntime honesty (pdaFind n/a)")
  | .error msg =>
      require (contains msg "HostRuntime") "evm reject names HostRuntime"
      require (contains msg "host.pda.find" || contains msg "storage.pda")
        "evm reject names pdaFind or storage.pda"

  -- Solana + storage.pda is honest.
  match requireHostRuntimeHonesty "solana-sbpf-asm" #[.storagePda] with
  | .error msg => throw (IO.userError s!"Solana+storagePda should be honest: {msg}")
  | .ok () => pure ()

  -- Shipped resolveSpec path: PDA intent on NEAR fails with HostRuntime text.
  match resolveSpec wasmNear pdaClaimSpec with
  | .ok _ => throw (IO.userError "resolveSpec NEAR+PDA must fail")
  | .error diag =>
      require (contains diag.message "HostRuntime")
        s!"resolveSpec diagnostic must name HostRuntime, got: {diag.message}"
      require (contains diag.message "wasm-near")
        "resolveSpec diagnostic names target"
      require (
          contains diag.message "storage.pda" ||
          contains diag.message "host.pda"
        ) "resolveSpec diagnostic names PDA effect/cap"

  -- Same intent resolves on Solana (profile has storagePda + HostRuntime honest).
  match resolveSpec solanaSbpfAsm pdaClaimSpec with
  | .error diag =>
      throw (IO.userError s!"resolveSpec Solana+PDA should ok: {diag.message}")
  | .ok plan =>
      require (plan.targetId == "solana-sbpf-asm") "plan target solana"
      require (plan.capabilities.any (· == .storagePda)) "plan keeps storagePda"

  let evmN := supportedCount "evm"
  let solN := supportedCount "solana-sbpf-asm"
  let nearN := supportedCount "wasm-near"
  let sorobanN := supportedCount "wasm-stellar-soroban"
  let cosmwasmN := supportedCount "wasm-cosmwasm"
  require (evmN >= 14) s!"evm support count low: {evmN}"
  require (solN >= 16) s!"solana support count low: {solN}"
  require (nearN >= 12) s!"near support count low: {nearN}"
  require (sorobanN >= 4) s!"soroban support count low: {sorobanN}"
  require (cosmwasmN >= 3) s!"cosmwasm support count low: {cosmwasmN}"

  -- Shipped lowerer emits HostRuntime catalog comment on log path.
  match ProofForge.Backend.Solana.SbpfAsm.renderModule
      ProofForge.IR.Examples.EventProbe.module with
  | .error e => throw (IO.userError s!"EventProbe Solana render failed: {e.message}")
  | .ok asm =>
      require (contains asm "HostRuntime host.log.emit")
        "sBPF lowerer must emit HostRuntime catalog ref for logEmit"
      require (contains asm "sol_log_64_")
        "sBPF lowerer must still call sol_log_64_"
      require (contains asm "syscall:sol_log_64_" || contains asm "sol_log_64_")
        "catalog ref or syscall present"

  ---------------------------------------------------------------------------
  -- HostEnv (gap-analysis step 1): buckets + materialize-or-reject triad
  ---------------------------------------------------------------------------
  require (allHostEnvs.size == 19) "HostEnv catalog size"
  require (HostEnv.blockTime.bucket == .general) "blockTime general"
  require (HostEnv.caller.bucket == .general) "caller general"
  require (HostEnv.attachedValue.bucket == .general) "attachedValue general"
  require (HostEnv.epoch.bucket == .approximate) "epoch approximate"
  require (HostEnv.gasOrComputeBudgetLeft.bucket == .approximate)
    "gasOrComputeBudgetLeft approximate"
  require (HostEnv.randomness.bucket == .approximate) "randomness approximate"
  require (HostEnv.blockHash.bucket == .approximate) "blockHash approximate"
  require (HostEnv.gasPrice.bucket == .chainOnly) "gasPrice chainOnly"
  require (HostEnv.baseFee.bucket == .chainOnly) "baseFee chainOnly"
  require (HostEnv.txOrigin.bucket == .chainOnly) "txOrigin chainOnly"
  require (HostEnv.coinbase.bucket == .chainOnly) "coinbase chainOnly"
  require (HostEnv.solanaRent.bucket == .chainOnly) "solanaRent chainOnly"
  require (HostEnv.nearPredecessor.bucket == .chainOnly) "nearPredecessor chainOnly"

  -- General: honest per-target matrix (portable *intent*; only claim lowers that exist).
  -- blockHeight / caller / attachedValue: full triad.
  for env in #[HostEnv.blockHeight, .caller, .attachedValue] do
    for tid in primaryTargetIds do
      match materializeEnv tid env with
      | .error msg =>
          throw (IO.userError s!"general {env.id} must materialize on {tid}: {msg}")
      | .ok m =>
          require (!isNaSymbol m.binding.symbol)
            s!"general {env.id}@{tid} symbol must not be n/a"
          require (m.binding.targetId == tid)
            s!"general {env.id} binding targetId"
  -- blockTime: full triad (Solana Clock.unix_timestamp lower).
  for tid in primaryTargetIds do
    match materializeEnv tid .blockTime with
    | .error msg => throw (IO.userError s!"blockTime must materialize on {tid}: {msg}")
    | .ok m =>
        require (!isNaSymbol m.binding.symbol) s!"blockTime@{tid}"
        require (supportsHostEnv tid .blockTime) s!"supportsHostEnv blockTime@{tid}"
  match materializeEnv "solana-sbpf-asm" .blockTime with
  | .error msg => throw (IO.userError s!"Solana blockTime: {msg}")
  | .ok m =>
      require (contains m.binding.symbol "clock" || contains m.binding.symbol "sol_get_clock")
        "solana blockTime → sol_get_clock_sysvar"
  -- selfAddress: full triad (Solana program_id digest lower).
  for tid in primaryTargetIds do
    match materializeEnv tid .selfAddress with
    | .error msg => throw (IO.userError s!"selfAddress must materialize on {tid}: {msg}")
    | .ok m =>
        require (!isNaSymbol m.binding.symbol) s!"selfAddress@{tid}"
        require (supportsHostEnv tid .selfAddress) s!"supportsHostEnv selfAddress@{tid}"
  match materializeEnv "solana-sbpf-asm" .selfAddress with
  | .error msg => throw (IO.userError s!"Solana selfAddress: {msg}")
  | .ok m =>
      require (contains m.binding.symbol "program")
        "solana selfAddress → program_id"
  -- chainId: EVM only — never alias block_index / invent sol_get_cluster.
  match materializeEnv "evm" .chainId with
  | .ok m => require (m.binding.symbol == "chainid") "evm chainId → chainid"
  | .error msg => throw (IO.userError s!"evm chainId: {msg}")
  for tid in #["solana-sbpf-asm", "wasm-near"] do
    match materializeEnv tid .chainId with
    | .ok m =>
        -- Fail hard if catalog invents a silent wrong binding.
        throw (IO.userError
          s!"chainId must reject on {tid} (got symbol `{m.binding.symbol}`; \
no silent wrong binding — especially not block_index / sol_get_cluster)")
    | .error msg =>
        require (contains msg "HostEnv") s!"chainId@{tid} names HostEnv"
        require (contains msg tid) s!"chainId reject names {tid}"
        require (contains msg "env.chainId") s!"chainId reject names term"
        -- Reject path has no binding; supportsHostEnv must be false.
        require (!supportsHostEnv tid .chainId)
          s!"chainId must not be supportsHostEnv on {tid}"

  -- Approximate: gas/compute — EVM + Solana (U1.4); NEAR permanent reject.
  match materializeEnv "evm" .gasOrComputeBudgetLeft with
  | .ok m => require (m.binding.symbol == "gas") "evm gasOrComputeBudgetLeft → gas"
  | .error msg => throw (IO.userError s!"evm gasOrComputeBudgetLeft: {msg}")
  match materializeEnv "solana-sbpf-asm" .gasOrComputeBudgetLeft with
  | .error msg => throw (IO.userError s!"Solana gasOrComputeBudgetLeft: {msg}")
  | .ok m =>
      require (contains m.binding.symbol "remaining_compute" || contains m.binding.symbol "compute")
        "solana gasOrComputeBudgetLeft → sol_remaining_compute_units"
      require (supportsHostEnv "solana-sbpf-asm" .gasOrComputeBudgetLeft)
        "supportsHostEnv Solana gasOrComputeBudgetLeft"
  match materializeEnv "wasm-near" .gasOrComputeBudgetLeft with
  | .ok m =>
      throw (IO.userError
        s!"gasOrComputeBudgetLeft must permanent-reject on NEAR (got {m.binding.symbol})")
  | .error msg =>
      require (contains msg "HostEnv") "NEAR gas budget names HostEnv"
      require (contains msg "env.gasOrComputeBudgetLeft") "NEAR gas budget names term"
      require (!supportsHostEnv "wasm-near" .gasOrComputeBudgetLeft)
        "NEAR gas must not be supportsHostEnv"
  match materializeEnv "evm" .randomness with
  | .ok m => require (m.binding.symbol == "prevrandao") "evm randomness → prevrandao"
  | .error msg => throw (IO.userError s!"evm randomness: {msg}")
  match materializeEnv "wasm-near" .randomness with
  | .ok m => require (m.binding.symbol == "env.random_seed") "near randomness"
  | .error msg => throw (IO.userError s!"near randomness: {msg}")
  match materializeEnv "solana-sbpf-asm" .randomness with
  | .ok _ => throw (IO.userError "Solana randomness must honest-reject")
  | .error msg => require (contains msg "HostEnv") "Solana randomness HostEnv"
  match materializeEnv "wasm-near" .blockHash with
  | .ok _ => throw (IO.userError "NEAR blockHash must honest-reject")
  | .error msg =>
      require (contains msg "HostEnv") "blockHash reject names HostEnv"
      require (contains msg "wasm-near") "blockHash reject names target"
      require (contains msg "env.blockHash") "blockHash reject names term"
  -- epoch: NEAR only.
  match materializeEnv "wasm-near" .epoch with
  | .ok m => require (m.binding.symbol == "env.epoch_height") "near epoch"
  | .error msg => throw (IO.userError s!"near epoch: {msg}")
  for tid in #["evm", "solana-sbpf-asm"] do
    match materializeEnv tid .epoch with
    | .ok _ => throw (IO.userError s!"epoch must reject on {tid}")
    | .error msg => require (contains msg "HostEnv") s!"epoch@{tid} HostEnv"

  -- Chain-only EVM economics: ok on EVM, reject on Solana/NEAR.
  for env in #[HostEnv.gasPrice, .baseFee, .coinbase] do
    match materializeEnv "evm" env with
    | .error msg => throw (IO.userError s!"EVM must materialize {env.id}: {msg}")
    | .ok m => require (!isNaSymbol m.binding.symbol) s!"evm {env.id}"
    for tid in #["solana-sbpf-asm", "wasm-near"] do
      match materializeEnv tid env with
      | .ok _ => throw (IO.userError s!"{env.id} must reject on {tid}")
      | .error msg =>
          require (contains msg "HostEnv") s!"{env.id}@{tid} names HostEnv"
          require (contains msg tid) s!"{env.id} reject names {tid}"
          require (contains msg env.id) s!"{env.id} reject names term"
  -- txOrigin is exact EVM-only semantics. Portable transaction identity uses signer.
  match materializeEnv "evm" .txOrigin with
  | .error msg => throw (IO.userError s!"EVM txOrigin: {msg}")
  | .ok m => require (m.binding.symbol == "origin") "evm origin symbol"
  match materializeEnv "solana-sbpf-asm" .txOrigin with
  | .ok _ => throw (IO.userError "Solana txOrigin must reject")
  | .error msg => require (contains msg "HostEnv") "solana txOrigin HostEnv"
  match materializeEnv "wasm-near" .txOrigin with
  | .ok _ => throw (IO.userError "NEAR txOrigin must reject")
  | .error msg => require (contains msg "HostEnv") "near txOrigin HostEnv"
  for targetId in #["evm", "solana-sbpf-asm", "wasm-near"] do
    match materializeEnv targetId .signer with
    | .ok _ => pure ()
    | .error msg => throw (IO.userError s!"{targetId} signer must materialize: {msg}")
  match materializeEnv "solana-sbpf-asm" .solanaRent with
  | .ok m => require (contains m.binding.symbol "rent") "solana rent symbol"
  | .error msg => throw (IO.userError s!"solanaRent: {msg}")
  match materializeEnv "evm" .solanaRent with
  | .ok _ => throw (IO.userError "solanaRent must reject on evm")
  | .error msg => require (contains msg "HostEnv") "solanaRent reject HostEnv"
  match materializeEnv "wasm-near" .nearPredecessor with
  | .ok m => require (contains m.binding.symbol "predecessor") "near predecessor"
  | .error msg => throw (IO.userError s!"nearPredecessor: {msg}")
  match materializeEnv "evm" .nearPredecessor with
  | .ok _ => throw (IO.userError "nearPredecessor must reject on evm")
  | .error msg => require (contains msg "HostEnv") "nearPredecessor reject"

  -- ContextField → HostEnv wiring (IR surface stays; vocabulary is HostEnv).
  require (ContextField.timestamp.toHostEnv == .blockTime) "timestamp→blockTime"
  require (ContextField.checkpointId.toHostEnv == .blockHeight) "checkpointId→blockHeight"
  require (ContextField.userId.toHostEnv == .caller) "userId→caller"
  require (ContextField.contractId.toHostEnv == .selfAddress) "contractId→self"
  require (ContextField.gasLeft.toHostEnv == .gasOrComputeBudgetLeft) "gasLeft→budget"
  require (ContextField.signer.toHostEnv == .signer) "signer→signer"
  require (ContextField.randomSeed.toHostEnv == .randomness) "randomSeed→randomness"
  require (!ContextField.gasLeft.isPortableEnv)
    "gasLeft not triad portable-core (NEAR permanent reject; Solana CU is approximate)"
  require ContextField.userId.isPortableEnv "userId portable-core (triad)"
  require ContextField.timestamp.isPortableEnv
    "timestamp portable-core after Solana Clock.unix_timestamp lower (U1.1)"
  require ContextField.contractId.isPortableEnv
    "contractId portable-core after Solana program_id lower (U1.2)"

  -- Solana HostEnv U1.1: contextRead.timestamp lowers Clock.unix_timestamp.
  let tsModule : Module := {
    name := "HostEnvBlockTime"
    state := #[]
    entrypoints := #[{
      name := "now"
      body := #[
        .letBind "t" .u64 (.effect (.contextRead .timestamp))
        , .return (.local "t")
      ]
    }]
  }
  match resolveModule solanaSbpfAsm tsModule with
  | .error err => throw (IO.userError s!"resolve Solana timestamp module: {err.render}")
  | .ok _ => pure ()
  match ProofForge.Backend.Solana.Package.renderPackage "hostenv-blocktime" tsModule with
  | .error err => throw (IO.userError s!"render Solana timestamp: {err.render}")
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw (IO.userError "timestamp package missing asm")
      let asm := asmFile.contents
      require (contains asm "Clock.unix_timestamp")
        "asm must mark Clock.unix_timestamp lower"
      require (contains asm "call sol_get_clock_sysvar")
        "asm must call sol_get_clock_sysvar for timestamp"

  -- Solana HostEnv U1.2: contextRead.contractId lowers program_id digest.
  let selfModule : Module := {
    name := "HostEnvSelfAddress"
    state := #[]
    entrypoints := #[{
      name := "me"
      body := #[
        .letBind "a" .u64 (.effect (.contextRead .contractId))
        , .return (.local "a")
      ]
    }]
  }
  match resolveModule solanaSbpfAsm selfModule with
  | .error err => throw (IO.userError s!"resolve Solana contractId module: {err.render}")
  | .ok _ => pure ()
  match ProofForge.Backend.Solana.Package.renderPackage "hostenv-self" selfModule with
  | .error err => throw (IO.userError s!"render Solana contractId: {err.render}")
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw (IO.userError "self package missing asm")
      let asm := asmFile.contents
      require (contains asm "program_id")
        "asm must mark program_id / contractId lower"
      require (contains asm "call sol_sha256")
        "asm must sha256 program_id for portable self handle"

  -- Solana HostEnv U1.4: contextRead.gasLeft → sol_remaining_compute_units.
  let gasModule : Module := {
    name := "HostEnvGasLeft"
    state := #[]
    entrypoints := #[{
      name := "cu"
      body := #[
        .letBind "g" .u64 (.effect (.contextRead .gasLeft))
        , .return (.local "g")
      ]
    }]
  }
  match resolveModule solanaSbpfAsm gasModule with
  | .error err => throw (IO.userError s!"resolve Solana gasLeft module: {err.render}")
  | .ok _ => pure ()
  match ProofForge.Backend.Solana.Package.renderPackage "hostenv-gas" gasModule with
  | .error err => throw (IO.userError s!"render Solana gasLeft: {err.render}")
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw (IO.userError "gas package missing asm")
      let asm := asmFile.contents
      require (contains asm "sol_remaining_compute_units")
        "asm must call sol_remaining_compute_units for gasLeft"
      require (contains asm "gasLeft" || contains asm "gasOrCompute")
        "asm must mark gasLeft / HostEnv path"

  IO.println s!"host-runtime: ok (effects={allEffects.size} hostEnvs={allHostEnvs.size} evm={evmN} solana={solN} near={nearN} soroban={sorobanN} cosmwasm={cosmwasmN}; adapters+catalog-ref+HostEnv)"
  pure 0

end ProofForge.Tests.HostRuntime

def main : IO UInt32 :=
  ProofForge.Tests.HostRuntime.main
