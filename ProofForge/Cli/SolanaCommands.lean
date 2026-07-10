import Lean.Util.Path
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.Solana.Materialize
import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Cli.Artifact
import ProofForge.Cli.ArrayUtil
import ProofForge.Cli.ContractLoader
import ProofForge.Cli.FileUtil
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Options
import ProofForge.Cli.Process
import ProofForge.Cli.SolanaArtifacts
import ProofForge.Cli.TargetJson
import ProofForge.Cli.Usage
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.IR.Examples.Counter
import ProofForge.Solana.Examples.AssociatedTokenCpi
import ProofForge.Solana.Examples.Clock
import ProofForge.Solana.Examples.Crypto
import ProofForge.Solana.Examples.EpochRewards
import ProofForge.Solana.Examples.EpochSchedule
import ProofForge.Solana.Examples.LastRestartSlot
import ProofForge.Solana.Examples.LogEvent
import ProofForge.Solana.Examples.Memory
import ProofForge.Solana.Examples.Rent
import ProofForge.Solana.Examples.ReturnDataCompute
import ProofForge.Solana.Examples.SplToken2022Cpi
import ProofForge.Solana.Examples.SplToken2022PausableCpi
import ProofForge.Solana.Examples.SplToken2022TransferHook
import ProofForge.Solana.Examples.SplTokenAuthorityCpi
import ProofForge.Solana.Examples.SplTokenCloseAccountCpi
import ProofForge.Solana.Examples.SplTokenOpsCpi
import ProofForge.Solana.Examples.SplTokenTransferCheckedCpi
import ProofForge.Solana.Examples.SystemCpi
import ProofForge.Solana.Examples.SystemCreateAccountCpi
import ProofForge.Target
import ProofForge.Target.ArtifactBundle

open System
open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

/-- PF-P1-03: intermediate-only Solana assembly bundle (no ELF). -/
def solanaAsmArtifactBundle
    (sourceModule sourceKind : String) (sourcePath? : Option String)
    (asmPath : FilePath) (asmSha : String) (asmBytes : Nat) :
    ProofForge.Target.ArtifactBundle.ArtifactBundle :=
  open ProofForge.Target.ArtifactBundle in
  {
    targetId := "solana-sbpf-asm"
    source := { moduleName := sourceModule, path? := sourcePath?, kind := sourceKind }
    outputs := #[{
      kind := "sbpf-asm"
      role := .intermediate
      path? := some asmPath.toString
      sha256? := some asmSha
      bytes? := some asmBytes
    }]
    primaryOutput? := some "sbpf-asm"
    finalOutput? := none
    toolchain := #[{ tool := "sbpf", stage := "final-deployable", available := false }]
    validations := #[{
      name := "sbpfBuild"
      state := .notRun
      detail? := some "assembly-only path: ELF link not requested"
    }]
  }

/-- PF-P1-03: final Solana ELF with assembly intermediate. -/
def solanaElfArtifactBundle
    (sourceModule sourceKind : String) (sourcePath? : Option String)
    (asmPath elfPath : FilePath)
    (asmSha elfSha : String) (asmBytes elfBytes : Nat) :
    ProofForge.Target.ArtifactBundle.ArtifactBundle :=
  open ProofForge.Target.ArtifactBundle in
  {
    targetId := "solana-sbpf-asm"
    source := { moduleName := sourceModule, path? := sourcePath?, kind := sourceKind }
    outputs := #[
      {
        kind := "sbpf-asm"
        role := .intermediate
        path? := some asmPath.toString
        sha256? := some asmSha
        bytes? := some asmBytes
      },
      {
        kind := "solana-elf"
        role := .finalDeployable
        path? := some elfPath.toString
        sha256? := some elfSha
        bytes? := some elfBytes
      }
    ]
    primaryOutput? := some "solana-elf"
    finalOutput? := some "solana-elf"
    toolchain := #[{ tool := "sbpf", stage := "final-deployable", available := true }]
    validations := #[{ name := "sbpfBuild", state := .passed }]
  }

def requireHonestBundle (label : String)
    (bundle : ProofForge.Target.ArtifactBundle.ArtifactBundle) : IO Unit := do
  match ProofForge.Target.ArtifactBundle.validateHonesty bundle with
  | .ok () => pure ()
  | .error err => throw <| IO.userError s!"{label} ArtifactBundle honesty: {err.message}"

def compileSolanaElf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/Counter.so")
  let projectName := match output.fileName with
    | some n => (n.splitOn ".").headD "counter"
    | none => "counter"
  let projectDir := match output.parent with
    | some parent => parent / s!"{projectName}-sbpf-project"
    | none => FilePath.mk s!"{projectName}-sbpf-project"

  match ProofForge.Backend.Solana.Package.renderPackage projectName ProofForge.IR.Examples.Counter.module with
  | .ok pkg =>
      for file in pkg.files do
        let path := packagePath projectDir file.path
        writeTextFile path file.contents
        IO.println s!"wrote {path}"

      let asmSrc := packagePath projectDir pkg.asmPath
      let manifestOutput := packagePath projectDir pkg.manifestPath

      -- Invoke the sbpf toolchain to assemble and link the ELF.
      let _ ← runProcess "sbpf" #["build", "--arch", opts.solanaSbpfArch] (cwd? := some projectDir)

      let builtElf := projectDir / "deploy" / s!"{projectName}.so"
      if ! (← builtElf.pathExists) then
        throw <| IO.userError s!"sbpf build did not produce {builtElf}"

      let elfBytes ← IO.FS.readBinFile builtElf
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      IO.FS.writeBinFile output elfBytes
      IO.println s!"wrote {output}"

      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson asmSrc
      let manifestArtifact ← artifactEntryJson manifestOutput
      let elfArtifact ← artifactEntryJson output
      let asmDigest ← fileDigestAndBytes asmSrc
      let elfDigest ← fileDigestAndBytes output
      let bundle := solanaElfArtifactBundle "Counter" "portable-ir" none asmSrc output
        asmDigest.fst elfDigest.fst asmDigest.snd elfDigest.snd
      requireHonestBundle "Solana ELF Counter" bundle
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "counter-elf"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString "Counter"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "control.conditional"]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null"),
            ("arch", jsonString opts.solanaSbpfArch)
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaElf", elfArtifact)
        ]),
        ("artifactBundle", ProofForge.Target.ArtifactBundle.ArtifactBundle.toJson bundle),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "passed"),
          ("sbpfDisassembleRoundtrip", jsonString "pending"),
          ("manifestGeneration", jsonString "passed")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSpecElf (opts : CliOptions) (defaultOutput : FilePath)
    (fallbackProjectName fixture : String) (spec : ProofForge.Contract.ContractSpec) :
    IO UInt32 := do
  let output := opts.output?.getD defaultOutput
  let projectName := match output.fileName with
    | some n => (n.splitOn ".").headD fallbackProjectName
    | none => fallbackProjectName
  let projectDir := match output.parent with
    | some parent => parent / s!"{projectName}-sbpf-project"
    | none => FilePath.mk s!"{projectName}-sbpf-project"
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render

  match ProofForge.Backend.Solana.Package.renderPackageForSpec projectName spec with
  | .ok pkg =>
      for file in pkg.files do
        let path := packagePath projectDir file.path
        writeTextFile path file.contents
        IO.println s!"wrote {path}"

      let asmSrc := packagePath projectDir pkg.asmPath
      let manifestOutput := packagePath projectDir pkg.manifestPath
      let idlOutput := packagePath projectDir pkg.idlPath
      let clientOutput := packagePath projectDir pkg.clientPath
      let _ ← runProcess "sbpf" #["build", "--arch", opts.solanaSbpfArch] (cwd? := some projectDir)

      let builtElf := projectDir / "deploy" / s!"{projectName}.so"
      if ! (← builtElf.pathExists) then
        throw <| IO.userError s!"sbpf build did not produce {builtElf}"

      let elfBytes ← IO.FS.readBinFile builtElf
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      IO.FS.writeBinFile output elfBytes
      IO.println s!"wrote {output}"

      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson asmSrc
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let elfArtifact ← artifactEntryJson output
      let asmDigest ← fileDigestAndBytes asmSrc
      let elfDigest ← fileDigestAndBytes output
      let bundle := solanaElfArtifactBundle spec.name "contract-sdk" none asmSrc output
        asmDigest.fst elfDigest.fst asmDigest.snd elfDigest.snd
      requireHonestBundle "Solana ELF" bundle
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString fixture),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("materialization",
          ProofForge.Target.Materialize.Report.json
            (ProofForge.Target.Materialize.forSolana spec.module
              (ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlan plan))),
        ("solanaMaterialization",
          ProofForge.Backend.Solana.Materialize.reportJson
            (ProofForge.Backend.Solana.Materialize.report spec.module
              (ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlan plan))),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null"),
            ("arch", jsonString opts.solanaSbpfArch)
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact),
          ("solanaElf", elfArtifact)
        ]),
        ("artifactBundle", ProofForge.Target.ArtifactBundle.ArtifactBundle.toJson bundle),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "passed"),
          ("liveCpi", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

/-- Source-backed Solana ELF build (PF-P0-03). Loads `contract_source` and runs
the same package/ELF path as fixture ELF emits. Fails if `sbpf` is unavailable. -/
unsafe def compileContractSourceSolanaElf (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let base := leanBaseName input
  let defaultOut := siblingPath input s!"{base}.so"
  compileSolanaSpecElf opts defaultOut base base spec

def compileSolanaSpecSbpf (opts : CliOptions) (defaultOutput : FilePath)
    (fixture : String) (spec : ProofForge.Contract.ContractSpec) : IO UInt32 := do
  let output := opts.output?.getD defaultOutput
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let asmDigest ← fileDigestAndBytes output
      let bundle := solanaAsmArtifactBundle spec.name "contract-sdk" none output
        asmDigest.fst asmDigest.snd
      requireHonestBundle "Solana asm fixture" bundle
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString "solana-sbpf-asm"),
        ("fixture", jsonString fixture),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("materialization",
          ProofForge.Target.Materialize.Report.json
            (ProofForge.Target.Materialize.forSolana spec.module
              (ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlan plan))),
        ("solanaMaterialization",
          ProofForge.Backend.Solana.Materialize.reportJson
            (ProofForge.Backend.Solana.Materialize.report spec.module
              (ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlan plan))),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("artifactBundle", ProofForge.Target.ArtifactBundle.ArtifactBundle.toJson bundle),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "notRun"),
          ("liveCpi", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSystemCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SystemCpi.s")
    "solana-system-cpi-sbpf"
    ProofForge.Solana.Examples.SystemCpi.spec

def compileSolanaSystemCreateAccountCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SystemCreateAccountCpi.s")
    "solana-system-create-account-cpi-sbpf"
    ProofForge.Solana.Examples.SystemCreateAccountCpi.spec

def compileSolanaSplTokenTransferCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenTransferCheckedCpi.s")
    "solana-spl-token-transfer-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenTransferCheckedCpi.spec

def compileSolanaSplTokenOpsCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenOpsCpi.s")
    "solana-spl-token-ops-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenOpsCpi.spec

def compileSolanaSplTokenCloseAccountCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenCloseAccountCpi.s")
    "solana-spl-token-close-account-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenCloseAccountCpi.spec

def compileSolanaSplTokenAuthorityCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenAuthorityCpi.s")
    "solana-spl-token-authority-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenAuthorityCpi.spec

def compileSolanaAssociatedTokenCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/AssociatedTokenCpi.s")
    "solana-associated-token-cpi-sbpf"
    ProofForge.Solana.Examples.AssociatedTokenCpi.spec

def compileSolanaSplToken2022CpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplToken2022Cpi.s")
    "solana-spl-token-2022-cpi-sbpf"
    ProofForge.Solana.Examples.SplToken2022Cpi.spec

def compileSolanaSplToken2022PausableCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplToken2022PausableCpi.s")
    "solana-spl-token-2022-pausable-cpi-sbpf"
    ProofForge.Solana.Examples.SplToken2022PausableCpi.spec

def compileSolanaSplToken2022TransferHookSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplToken2022TransferHook.s")
    "solana-spl-token-2022-transfer-hook-sbpf"
    ProofForge.Solana.Examples.SplToken2022TransferHook.spec

def compileValueVaultSolanaElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/ValueVault.so")
    "value-vault"
    "value-vault-solana-elf"
    ProofForge.Contract.Examples.ValueVault.spec

def compileSolanaSystemCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SystemCpi.so")
    "system-cpi"
    "solana-system-cpi-elf"
    ProofForge.Solana.Examples.SystemCpi.spec

def compileSolanaSystemCreateAccountCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SystemCreateAccountCpi.so")
    "system-create-account-cpi"
    "solana-system-create-account-cpi-elf"
    ProofForge.Solana.Examples.SystemCreateAccountCpi.spec

def compileSolanaSplTokenTransferCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenTransferCheckedCpi.so")
    "spl-token-transfer-cpi"
    "solana-spl-token-transfer-cpi-elf"
    ProofForge.Solana.Examples.SplTokenTransferCheckedCpi.spec

def compileSolanaSplTokenOpsCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenOpsCpi.so")
    "spl-token-ops-cpi"
    "solana-spl-token-ops-cpi-elf"
    ProofForge.Solana.Examples.SplTokenOpsCpi.spec

def compileSolanaSplTokenCloseAccountCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenCloseAccountCpi.so")
    "spl-token-close-account-cpi"
    "solana-spl-token-close-account-cpi-elf"
    ProofForge.Solana.Examples.SplTokenCloseAccountCpi.spec

def compileSolanaSplTokenAuthorityCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenAuthorityCpi.so")
    "spl-token-authority-cpi"
    "solana-spl-token-authority-cpi-elf"
    ProofForge.Solana.Examples.SplTokenAuthorityCpi.spec

def compileSolanaAssociatedTokenCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/AssociatedTokenCpi.so")
    "associated-token-cpi"
    "solana-associated-token-cpi-elf"
    ProofForge.Solana.Examples.AssociatedTokenCpi.spec

def compileSolanaSplToken2022CpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplToken2022Cpi.so")
    "spl-token-2022-cpi"
    "solana-spl-token-2022-cpi-elf"
    ProofForge.Solana.Examples.SplToken2022Cpi.spec

def compileSolanaSplToken2022PausableCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplToken2022PausableCpi.so")
    "spl-token-2022-pausable-cpi"
    "solana-spl-token-2022-pausable-cpi-elf"
    ProofForge.Solana.Examples.SplToken2022PausableCpi.spec

def compileSolanaSplToken2022TransferHookElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplToken2022TransferHook.so")
    "spl-token-2022-transfer-hook"
    "solana-spl-token-2022-transfer-hook-elf"
    ProofForge.Solana.Examples.SplToken2022TransferHook.spec

def compileSolanaLogEventElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/LogEvent.so")
    "log-event"
    "solana-log-event-elf"
    ProofForge.Solana.Examples.LogEvent.spec

def compileSolanaClockSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/Clock.so")
    "clock-sysvar"
    "solana-clock-sysvar-elf"
    ProofForge.Solana.Examples.Clock.spec

def compileSolanaRentSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/Rent.so")
    "rent-sysvar"
    "solana-rent-sysvar-elf"
    ProofForge.Solana.Examples.Rent.spec

def compileSolanaEpochScheduleSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/EpochSchedule.so")
    "epoch-schedule-sysvar"
    "solana-epoch-schedule-sysvar-elf"
    ProofForge.Solana.Examples.EpochSchedule.spec

def compileSolanaEpochRewardsSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/EpochRewards.so")
    "epoch-rewards-sysvar"
    "solana-epoch-rewards-sysvar-elf"
    ProofForge.Solana.Examples.EpochRewards.spec

def compileSolanaLastRestartSlotSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/LastRestartSlot.so")
    "last-restart-slot-sysvar"
    "solana-last-restart-slot-sysvar-elf"
    ProofForge.Solana.Examples.LastRestartSlot.spec

def compileSolanaMemoryElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/Memory.so")
    "memory"
    "solana-memory-elf"
    ProofForge.Solana.Examples.Memory.spec

def compileSolanaCryptoHashElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/CryptoHash.so")
    "crypto-hash"
    "solana-crypto-hash-elf"
    ProofForge.Solana.Examples.Crypto.spec

def compileSolanaReturnDataComputeElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/ReturnDataCompute.so")
    "return-data-compute"
    "solana-return-data-compute-elf"
    ProofForge.Solana.Examples.ReturnDataCompute.spec

def compileSbpfAsm (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/entrypoint.s")
  match ProofForge.Backend.Solana.SbpfAsm.renderCannedEntrypoint with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "sbpf-asm-phase0-canned-entrypoint"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("capabilities", jsonStringArray #[]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "pending"),
          ("sbpfDisassembleRoundtrip", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

end ProofForge.Cli
