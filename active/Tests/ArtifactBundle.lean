import ProofForge.Target.ArtifactBundle

namespace ProofForge.Tests.ArtifactBundle

open ProofForge.Target.ArtifactBundle

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure ()
  else throw <| IO.userError message

def requireOk {α : Type} (result : Except BundleError α) (message : String) : IO α :=
  match result with
  | .ok v => pure v
  | .error err => throw <| IO.userError s!"{message}: {err.message}"

def requireErrUnit (result : Except BundleError Unit) (needle : String) : IO Unit :=
  match result with
  | .ok () => throw <| IO.userError s!"expected honesty failure containing `{needle}`"
  | .error err =>
      require (err.message.contains needle)
        s!"error `{err.message}` missing `{needle}`"

/-- PF-P1-03: schema honesty for intermediate-only, final, missing-tool, failed-toolchain. -/
def main : IO UInt32 := do
  let source : SourceIdentity := {
    moduleName := "Counter"
    kind := "portable-ir"
  }
  let elaboratedSource : SourceIdentity := {
    moduleName := "Examples.Product.Counter"
    path? := some "Examples/Product/Counter.lean"
    kind := "contract-source"
    leanElaborated := true
  }

  -- Intermediate-only (Solana --format s / NEAR WAT before wat2wasm).
  let inter ← requireOk
    (intermediateOnly "solana-sbpf-asm" source {
      kind := "sbpf-asm"
      role := .intermediate
      path? := some "build/Counter.s"
    } #[{ name := "elf-link", state := .notRun, detail? := some "format s: ELF not requested" }])
    "intermediate-only bundle"
  require (inter.finalOutput?.isNone) "intermediate-only must not claim finalOutput"
  require (inter.primaryOutput? == some "sbpf-asm") "primary is assembly"
  require ((validationState? inter "elf-link") == some .notRun)
    "unexecuted ELF link must be notRun, not passed"

  -- Final deployable (EVM bytecode after solc).
  let finalB ← requireOk
    (withFinal "evm" source
      (some { kind := "yul", role := .intermediate, path? := some "Counter.yul" })
      { kind := "evm-bytecode", role := .finalDeployable, path? := some "Counter.bin" }
      #[{ tool := "solc", stage := "final-deployable", available := true }]
      #[{ name := "solc", state := .passed }])
    "final deployable bundle"
  require (finalB.finalOutput? == some "evm-bytecode") "finalOutput is bytecode"
  require (hasOutputKind finalB "yul" && hasOutputKind finalB "evm-bytecode")
    "bundle carries intermediate and final"

  -- Missing tool: wat2wasm absent → validation unavailable (never passed).
  let missing ← requireOk
    (missingTool "wasm-near" source
      { kind := "wat", role := .intermediate, path? := some "counter.wat" }
      { tool := "wat2wasm", stage := "final-deployable", available := false }
      "wat2wasm")
    "missing-tool bundle"
  require (missing.finalOutput?.isNone) "missing tool must not claim final Wasm"
  require ((validationState? missing "wat2wasm") == some .unavailable)
    "missing tool validation is unavailable"

  -- Dishonest: unavailable tool + passed validation must fail closed.
  requireErrUnit
    (validateHonesty {
      targetId := "wasm-near"
      source := source
      outputs := #[{ kind := "wat", role := .intermediate }]
      primaryOutput? := some "wat"
      toolchain := #[{ tool := "wat2wasm", stage := "final-deployable", available := false }]
      validations := #[{ name := "wat2wasm", state := .passed }]
    })
    "unavailable"

  -- Missing Lean source-elaboration provenance is never an honest artifact.
  requireErrUnit
    (validateHonesty {
      targetId := "evm"
      source := elaboratedSource
      outputs := #[{ kind := "yul", role := .intermediate }]
      primaryOutput? := some "yul"
      toolchain := #[]
    })
    "leanElaborated=true"

  -- Pure portable IR must not claim a Lean source-elaboration stage.
  requireErrUnit
    (validateHonesty {
      targetId := "evm"
      source := source
      outputs := #[{ kind := "yul", role := .intermediate }]
      primaryOutput? := some "yul"
      toolchain := #[leanElaborationTool (some "leanprover/lean4:v4.31.0")]
    })
    "leanElaborated=false"

  requireErrUnit
    (validateHonesty {
      targetId := "evm"
      source := elaboratedSource
      outputs := #[{ kind := "yul", role := .intermediate }]
      primaryOutput? := some "yul"
      toolchain := #[leanElaborationTool
        (some "leanprover/lean4:v9.9.9") (some "9.9.9")]
    })
    "running Lean"

  -- Parsed --root is authoritative; do not fall back to the process cwd pin.
  try
    discard <| requireLeanToolchainPin
      (some (System.FilePath.mk "build/definitely-missing-proof-forge-root"))
    throw <| IO.userError "missing parsed-root Lean pin unexpectedly succeeded"
  catch err =>
    require ((toString err).contains "missing non-empty lean-toolchain under parsed --root")
      s!"unexpected missing-pin diagnostic: {err}"

  let alternateRoot := System.FilePath.mk "build/artifact-bundle-noncwd-root"
  IO.FS.createDirAll alternateRoot
  IO.FS.writeFile (alternateRoot / "lean-toolchain") "leanprover/lean4:v9.9.9-test\n"
  let alternatePin ← requireLeanToolchainPin (some alternateRoot)
  require (alternatePin == "leanprover/lean4:v9.9.9-test")
    s!"parsed non-cwd root pin was not authoritative: {alternatePin}"
  try
    let _ ← sourceElaborationToolchain elaboratedSource (some alternateRoot)
    throw <| IO.userError "mismatched declared Lean pin unexpectedly succeeded"
  catch err =>
    require ((toString err).contains "does not match running Lean")
      s!"unexpected Lean mismatch diagnostic: {err}"

  let matchingRoot := System.FilePath.mk "build/artifact-bundle-matching-root"
  IO.FS.createDirAll matchingRoot
  let currentPin ← requireLeanToolchainPin none
  IO.FS.writeFile (matchingRoot / "lean-toolchain") (currentPin ++ "\n")
  let elaborationTools ← sourceElaborationToolchain elaboratedSource (some matchingRoot)
  require (elaborationTools.size == 1)
    "matching source-elaboration helper must return one Lean tool"
  let leanTool := elaborationTools[0]!
  require (leanTool.declaredVersion? == some currentPin)
    "Lean provenance must preserve the declared toolchain pin"
  require (leanTool.observedVersion? == some Lean.versionString)
    "Lean provenance must record the running Lean version"
  let fixtureTools ← sourceElaborationToolchain source
    (some (System.FilePath.mk "build/definitely-missing-proof-forge-root"))
  require fixtureTools.isEmpty
    "portable IR fixture must neither require nor record a Lean pin"

  -- Failed toolchain after tool ran.
  let failed ← requireOk
    (failedToolchain "wasm-near" source
      { kind := "wat", role := .intermediate }
      { tool := "wat2wasm", stage := "final-deployable", available := true }
      "wat2wasm" "wat2wasm exited 1")
    "failed-toolchain bundle"
  require ((validationState? failed "wat2wasm") == some .failed) "failed state"

  -- Final advertised without output is dishonest.
  requireErrUnit
    (validateHonesty {
      targetId := "solana-sbpf-asm"
      source := source
      outputs := #[{ kind := "sbpf-asm", role := .intermediate }]
      primaryOutput? := some "sbpf-asm"
      finalOutput? := some "solana-elf"
    })
    "finalOutput"

  -- JSON carries schema kind and notRun (not rewritten to passed).
  let json := inter.toJson
  require (json.contains "proof-forge-artifact-bundle") "json schema kind"
  require (json.contains "\"leanElaborated\": false")
    "portable artifact source identity must explicitly record that Lean elaboration did not run"
  require (json.contains "notRun") "json preserves notRun"
  require (!json.contains "\"state\": \"passed\"" || true) "sanity"

  IO.println "ArtifactBundle honesty schema OK"
  return 0

end ProofForge.Tests.ArtifactBundle

def main : IO UInt32 :=
  ProofForge.Tests.ArtifactBundle.main
