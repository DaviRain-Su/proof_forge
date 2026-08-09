/-
  Package root resolution for CWD-free doctor/install/local/network (REL-CWD-0).

  Authority: docs/product/05-distribution-and-packages.md

  A valid package root contains `scripts/proof_forge_doctor.py` (and peer engines).

  Search order:
  1. `PROOF_FORGE_ROOT` (must be absolute) when it contains the doctor engine
  2. Parent of `IO.appDir` when the CLI is installed as `<root>/bin/proof-forge-next`
  3. Process CWD (monorepo developer workflow)

  Not formal Stage-0. Does not invent tools outside Tool Lock.
-/
namespace ProofForgeV2.CLI.PackageRootV1

open System

/-- Relative path to the doctor engine used as package-root marker. -/
def doctorEngineRelV1 : FilePath :=
  FilePath.mk "scripts" / "proof_forge_doctor.py"

/-- True when `root` looks like a ProofForge package root. -/
def isPackageRootV1 (root : FilePath) : IO Bool := do
  let marker := root / doctorEngineRelV1
  return (← marker.pathExists)

/-- Resolve absolute package root or fail with a stable usage message. -/
def resolvePackageRootV1 : IO (Except String FilePath) := do
  -- 1) Explicit env (absolute only).
  match ← IO.getEnv "PROOF_FORGE_ROOT" with
  | some raw =>
      let trimmed := raw.trimAscii.toString
      if trimmed.isEmpty then
        pure ()
      else
        let p := FilePath.mk trimmed
        unless p.isAbsolute do
          return .error
            "PROOF_FORGE_ROOT must be an absolute path containing scripts/proof_forge_doctor.py"
        if ← isPackageRootV1 p then
          return .ok p
        else
          return .error
            s!"PROOF_FORGE_ROOT={trimmed} is missing scripts/proof_forge_doctor.py"
  | none => pure ()

  -- 2) Install layout: <packageRoot>/bin/proof-forge-next → parent of appDir.
  try
    let appDir ← IO.appDir
    let parent := appDir.parent.getD appDir
    if ← isPackageRootV1 parent then
      return .ok parent
  catch _ =>
    pure ()

  -- 3) Developer CWD (monorepo root).
  let cwd ← IO.currentDir
  if ← isPackageRootV1 cwd then
    return .ok cwd

  return .error
    ("cannot locate package root with scripts/proof_forge_doctor.py; " ++
      "set PROOF_FORGE_ROOT to the install/package directory, " ++
      "install CLI as <root>/bin/proof-forge-next with scripts/ alongside, " ++
      "or run from the monorepo root")

/-- Resolve package root or throw a usage-style string (caller maps to failUsage). -/
def requirePackageRootV1 : IO FilePath := do
  match ← resolvePackageRootV1 with
  | .ok root => pure root
  | .error msg => throw <| IO.userError msg

end ProofForgeV2.CLI.PackageRootV1
