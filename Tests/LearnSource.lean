import ProofForge.Backend.Solana.Package
import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Learn
import ProofForge.Solana.Examples.Clock
import ProofForge.Solana.Examples.Crypto
import ProofForge.Solana.Examples.EpochRewards
import ProofForge.Solana.Examples.EpochSchedule
import ProofForge.Solana.Examples.LastRestartSlot
import ProofForge.Solana.Examples.LogEvent
import ProofForge.Solana.Examples.Memory
import ProofForge.Solana.Examples.Rent
import ProofForge.Solana.Examples.ReturnDataCompute
import ProofForge.Solana.Examples.SplTokenCloseAccountCpi
import ProofForge.Solana.Examples.SplTokenOpsCpi
import ProofForge.Solana.Examples.SystemCpi
import ProofForge.Solana.Examples.SystemCreateAccountCpi
import ProofForge.Solana.Examples.Vault

namespace ProofForge.Tests.LearnSource

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireExcept {α : Type} (label : String) : Except String α → IO α
  | .ok value => pure value
  | .error err => throw <| IO.userError s!"{label}: {err}"

def reprModule (module : ProofForge.IR.Module) : String :=
  toString (repr module)

def parseSpec (path : System.FilePath) : IO ProofForge.Contract.ContractSpec := do
  requireExcept s!"parse/lower {path}" (← ProofForge.Contract.Learn.parseAndLowerFile path)

def requireSameModule (label : String)
    (actual expected : ProofForge.IR.Module) : IO Unit := do
  let actualRepr := reprModule actual
  let expectedRepr := reprModule expected
  require (actualRepr == expectedRepr)
    s!"{label} Learn source did not lower to the expected IR module\nactual:\n{actualRepr}\nexpected:\n{expectedRepr}"

def requireSameText (label actual expected : String) : IO Unit :=
  require (actual == expected)
    s!"{label} mismatch\nactual:\n{actual}\nexpected:\n{expected}"

def packageFile (label path : String)
    (spec : ProofForge.Contract.ContractSpec) : IO String := do
  match ProofForge.Backend.Solana.Package.renderPackageForSpec label spec with
  | .ok pkg =>
      let some file := pkg.files.find? (fun file => file.path == path)
        | throw <| IO.userError s!"{label} package missing {path}"
      pure file.contents
  | .error err =>
      throw <| IO.userError s!"{label} Solana render failed: {err.render}"

def requireValueVaultSolanaRender (spec : ProofForge.Contract.ContractSpec) : IO Unit := do
  let some snapshot := spec.module.entrypoints.find? (fun entrypoint => entrypoint.name == "snapshot")
    | throw <| IO.userError "Learn ValueVault missing snapshot entrypoint"
  require (snapshot.mutability == .call && snapshot.returns == .u64)
    "Learn ValueVault snapshot must remain a mutating U64-returning entrypoint"
  match ProofForge.Backend.Solana.Package.renderPackageForSpec "learn-value-vault" spec with
  | .ok pkg =>
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "Learn ValueVault Solana package missing manifest.toml"
      let manifest := manifestFile.contents
      require (manifest.contains "name = \"deposit\"")
        "Learn ValueVault manifest missing deposit instruction"
      require (manifest.contains "name = \"charge_fee\"")
        "Learn ValueVault manifest missing charge_fee instruction"
      require (manifest.contains "name = \"snapshot\"")
        "Learn ValueVault manifest missing snapshot instruction"
  | .error err =>
      throw <| IO.userError s!"Learn ValueVault Solana render failed: {err.render}"

def main : IO UInt32 := do
  let counter ← parseSpec "Examples/Backend/Learn/Counter.learn"
  requireSameModule "Counter" counter.module ProofForge.Contract.Examples.Counter.module
  let valueVault ← parseSpec "Examples/Backend/Learn/ValueVault.learn"
  requireSameModule "ValueVault" valueVault.module ProofForge.Contract.Examples.ValueVault.module
  requireValueVaultSolanaRender valueVault
  let solanaVault ← parseSpec "Examples/Backend/Learn/SolanaVault.learn"
  requireSameModule "SolanaVault" solanaVault.module ProofForge.Solana.Examples.Vault.module
  let learnManifest ← packageFile "learn-solana-vault" "manifest.toml" solanaVault
  let sourceManifest ← packageFile "source-solana-vault" "manifest.toml" ProofForge.Solana.Examples.Vault.spec
  requireSameText "SolanaVault Learn manifest" learnManifest sourceManifest
  let systemCpi ← parseSpec "Examples/Backend/Learn/SystemCpi.learn"
  requireSameModule "SystemCpi" systemCpi.module ProofForge.Solana.Examples.SystemCpi.module
  let learnSystemManifest ← packageFile "learn-system-cpi" "manifest.toml" systemCpi
  let sourceSystemManifest ← packageFile "source-system-cpi" "manifest.toml"
    ProofForge.Solana.Examples.SystemCpi.spec
  requireSameText "SystemCpi Learn manifest" learnSystemManifest sourceSystemManifest
  let systemCreateAccount ← parseSpec "Examples/Backend/Learn/SystemCreateAccountCpi.learn"
  requireSameModule "SystemCreateAccountCpi" systemCreateAccount.module
    ProofForge.Solana.Examples.SystemCreateAccountCpi.module
  let learnCreateAccountManifest ← packageFile "learn-system-create-account-cpi" "manifest.toml"
    systemCreateAccount
  let sourceCreateAccountManifest ← packageFile "source-system-create-account-cpi" "manifest.toml"
    ProofForge.Solana.Examples.SystemCreateAccountCpi.spec
  requireSameText "SystemCreateAccountCpi Learn manifest"
    learnCreateAccountManifest sourceCreateAccountManifest
  let splTokenOps ← parseSpec "Examples/Backend/Learn/SplTokenOpsCpi.learn"
  requireSameModule "SplTokenOpsCpi" splTokenOps.module
    ProofForge.Solana.Examples.SplTokenOpsCpi.module
  let learnTokenOpsManifest ← packageFile "learn-spl-token-ops-cpi" "manifest.toml" splTokenOps
  let sourceTokenOpsManifest ← packageFile "source-spl-token-ops-cpi" "manifest.toml"
    ProofForge.Solana.Examples.SplTokenOpsCpi.spec
  requireSameText "SplTokenOpsCpi Learn manifest" learnTokenOpsManifest sourceTokenOpsManifest
  let splTokenCloseAccount ← parseSpec "Examples/Backend/Learn/SplTokenCloseAccountCpi.learn"
  requireSameModule "SplTokenCloseAccountCpi" splTokenCloseAccount.module
    ProofForge.Solana.Examples.SplTokenCloseAccountCpi.module
  let learnTokenCloseManifest ← packageFile "learn-spl-token-close-account-cpi" "manifest.toml"
    splTokenCloseAccount
  let sourceTokenCloseManifest ← packageFile "source-spl-token-close-account-cpi" "manifest.toml"
    ProofForge.Solana.Examples.SplTokenCloseAccountCpi.spec
  requireSameText "SplTokenCloseAccountCpi Learn manifest"
    learnTokenCloseManifest sourceTokenCloseManifest
  let logEvent ← parseSpec "Examples/Backend/Learn/LogEvent.learn"
  requireSameModule "LogEvent" logEvent.module ProofForge.Solana.Examples.LogEvent.module
  let learnLogEventManifest ← packageFile "learn-log-event" "manifest.toml" logEvent
  let sourceLogEventManifest ← packageFile "source-log-event" "manifest.toml"
    ProofForge.Solana.Examples.LogEvent.spec
  requireSameText "LogEvent Learn manifest" learnLogEventManifest sourceLogEventManifest
  let returnDataCompute ← parseSpec "Examples/Backend/Learn/ReturnDataCompute.learn"
  requireSameModule "ReturnDataCompute" returnDataCompute.module
    ProofForge.Solana.Examples.ReturnDataCompute.module
  let learnReturnDataComputeManifest ← packageFile "learn-return-data-compute" "manifest.toml"
    returnDataCompute
  let sourceReturnDataComputeManifest ← packageFile "source-return-data-compute" "manifest.toml"
    ProofForge.Solana.Examples.ReturnDataCompute.spec
  requireSameText "ReturnDataCompute Learn manifest" learnReturnDataComputeManifest
    sourceReturnDataComputeManifest
  let memory ← parseSpec "Examples/Backend/Learn/Memory.learn"
  requireSameModule "Memory" memory.module ProofForge.Solana.Examples.Memory.module
  let learnMemoryManifest ← packageFile "learn-memory" "manifest.toml" memory
  let sourceMemoryManifest ← packageFile "source-memory" "manifest.toml"
    ProofForge.Solana.Examples.Memory.spec
  requireSameText "Memory Learn manifest" learnMemoryManifest sourceMemoryManifest
  let crypto ← parseSpec "Examples/Backend/Learn/Crypto.learn"
  requireSameModule "Crypto" crypto.module ProofForge.Solana.Examples.Crypto.module
  let learnCryptoManifest ← packageFile "learn-crypto" "manifest.toml" crypto
  let sourceCryptoManifest ← packageFile "source-crypto" "manifest.toml"
    ProofForge.Solana.Examples.Crypto.spec
  requireSameText "Crypto Learn manifest" learnCryptoManifest sourceCryptoManifest
  let clock ← parseSpec "Examples/Backend/Learn/Clock.learn"
  requireSameModule "Clock" clock.module ProofForge.Solana.Examples.Clock.module
  let learnClockManifest ← packageFile "learn-clock" "manifest.toml" clock
  let sourceClockManifest ← packageFile "source-clock" "manifest.toml"
    ProofForge.Solana.Examples.Clock.spec
  requireSameText "Clock Learn manifest" learnClockManifest sourceClockManifest
  let rent ← parseSpec "Examples/Backend/Learn/Rent.learn"
  requireSameModule "Rent" rent.module ProofForge.Solana.Examples.Rent.module
  let learnRentManifest ← packageFile "learn-rent" "manifest.toml" rent
  let sourceRentManifest ← packageFile "source-rent" "manifest.toml"
    ProofForge.Solana.Examples.Rent.spec
  requireSameText "Rent Learn manifest" learnRentManifest sourceRentManifest
  let epochSchedule ← parseSpec "Examples/Backend/Learn/EpochSchedule.learn"
  requireSameModule "EpochSchedule" epochSchedule.module
    ProofForge.Solana.Examples.EpochSchedule.module
  let learnEpochScheduleManifest ← packageFile "learn-epoch-schedule" "manifest.toml"
    epochSchedule
  let sourceEpochScheduleManifest ← packageFile "source-epoch-schedule" "manifest.toml"
    ProofForge.Solana.Examples.EpochSchedule.spec
  requireSameText "EpochSchedule Learn manifest" learnEpochScheduleManifest
    sourceEpochScheduleManifest
  let epochRewards ← parseSpec "Examples/Backend/Learn/EpochRewards.learn"
  requireSameModule "EpochRewards" epochRewards.module
    ProofForge.Solana.Examples.EpochRewards.module
  let learnEpochRewardsManifest ← packageFile "learn-epoch-rewards" "manifest.toml"
    epochRewards
  let sourceEpochRewardsManifest ← packageFile "source-epoch-rewards" "manifest.toml"
    ProofForge.Solana.Examples.EpochRewards.spec
  requireSameText "EpochRewards Learn manifest" learnEpochRewardsManifest
    sourceEpochRewardsManifest
  let lastRestartSlot ← parseSpec "Examples/Backend/Learn/LastRestartSlot.learn"
  requireSameModule "LastRestartSlot" lastRestartSlot.module
    ProofForge.Solana.Examples.LastRestartSlot.module
  let learnLastRestartSlotManifest ← packageFile "learn-last-restart-slot" "manifest.toml"
    lastRestartSlot
  let sourceLastRestartSlotManifest ← packageFile "source-last-restart-slot" "manifest.toml"
    ProofForge.Solana.Examples.LastRestartSlot.spec
  requireSameText "LastRestartSlot Learn manifest" learnLastRestartSlotManifest
    sourceLastRestartSlotManifest
  IO.println "learn-source: ok"
  return 0

end ProofForge.Tests.LearnSource

def main : IO UInt32 :=
  ProofForge.Tests.LearnSource.main
