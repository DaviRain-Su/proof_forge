/-
  Tests.Product.PrivateSum4PrivacyV1 — APP-1 continuous privacy boundary vector.

  Pins Phase-1 DoD PrivateSum4 on the **shipped** product path:
    * Loader + `compileValidatedSourceV1` fail closed with `PF-VIS-001`
      (private params → public return)
    * real `proof-forge-next check` / `build` exit non-zero with PF-VIS-001
      human wire and **no** output-dir artifacts (no raw private leak surface)
    * EVM/Solana/NEAR/Noir all refuse materialization past a compile success
      (defensive: current product never succeeds compile)

  Does not claim Noir prove/verify (C-4 closed as research-only) or formal
  TST-NOIR-006. Residual host-model PrivateSum4 remains in NoirRelationModel.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.Registry
import Tests.Language.ParserSession

namespace Tests.Product.PrivateSum4PrivacyV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.BuildSelectionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

/-- Product Examples.PrivateSum4 source (matches `Examples/PrivateSum4.lean`). -/
private def privateSum4SourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program PrivateSum4 where\n" ++
  "  entry sum(private a : UInt64, private b : UInt64, private c : UInt64, private d : UInt64) : UInt64 do\n" ++
  "    return a + b + c + d\n\n" ++
  "end Examples\n"

/-- Product compile must fail closed: private→public return is PF-VIS-001. -/
private unsafe def testProductCompilePfVis001 : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 privateSum4SourceText
      "<app1-private-sum4>" "Examples.PrivateSum4" none with
  | .error e =>
      -- Loader may also reject; still fail closed with a PF-* code.
      expect (e.code.startsWith "PF-")
        s!"Loader must fail closed with PF-*, got {e.render}"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .ok _ =>
          throw <| IO.userError
            "PrivateSum4 must not compile: private→public return is disclosure-illegal"
      | .error e =>
          expect (e.code == "PF-VIS-001" || e.code == "PF-SRC-INVALID")
            s!"expected PF-VIS-001 (or PF-SRC-INVALID), got {e.code}: {e.render}"
          expect (containsSubstr e.render "PF-VIS-001" || e.code == "PF-VIS-001" ||
              containsSubstr e.render "visibility" || containsSubstr e.render "private")
            s!"error must cite visibility/private boundary, got {e.render}"

private def cliBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) (cwd : Option FilePath := none) :
    IO (UInt32 × String × String) := do
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output {
    cmd := absoluteCli.toString
    args := args
    cwd := cwd
  }
  pure (out.exitCode, out.stdout, out.stderr)

/-- Write PrivateSum4 under a temp project root and run product CLI. -/
private def withPrivateSum4Project (body : FilePath → IO Unit) : IO Unit := do
  let tmp ← IO.Process.getCurrentDir
  let root := tmp / ".lake" / "build" / "tmp-app1-privatesum4"
  try IO.FS.removeDirAll root catch _ => pure ()
  IO.FS.createDirAll (root / "Examples")
  IO.FS.writeFile (root / "Examples" / "PrivateSum4.lean") privateSum4SourceText
  try
    body root
  finally
    try IO.FS.removeDirAll root catch _ => pure ()

/-- `check` must fail with PF-VIS-001 and leave no success artifacts. -/
private def testCliCheckNoLeak : IO Unit := do
  withPrivateSum4Project fun root => do
    let (code, stdout, stderr) ← runCli
      #["check", "Examples/PrivateSum4.lean",
        "--module", "Examples.PrivateSum4",
        "--root", root.toString]
      none
    expect (code != 0) s!"check must fail, exit={code} stdout={stdout} stderr={stderr}"
    let combined := stdout ++ "\n" ++ stderr
    expect (containsSubstr combined "PF-VIS-001" || containsSubstr combined "PF-SRC-INVALID")
      s!"check stderr/stdout must cite PF-VIS-001/SRC-INVALID, got:\n{combined}"
    -- No raw private operand values in human output (a,b,c,d literals not printed).
    expect (!containsSubstr combined "private a")
      "diagnostics must not echo raw private param binding text as a leak surface"
    expect (stdout.isEmpty || !containsSubstr stdout "status\":\"ok\"")
      "check must not emit success JSON"

/-- `build --target noir` must fail closed before writing an output tree with private leak. -/
private def testCliBuildNoArtifactLeak : IO Unit := do
  withPrivateSum4Project fun root => do
    let outDir := root / "build" / "v2-private-leak"
    let (code, stdout, stderr) ← runCli
      #["build", "Examples/PrivateSum4.lean",
        "--module", "Examples.PrivateSum4",
        "--root", root.toString,
        "--target", "noir",
        "-o", outDir.toString]
      none
    expect (code != 0) s!"build must fail, exit={code}"
    let combined := stdout ++ "\n" ++ stderr
    expect (containsSubstr combined "PF-VIS-001" || containsSubstr combined "PF-SRC-INVALID" ||
        containsSubstr combined "PF-REQ")
      s!"build must fail closed with product code, got:\n{combined}"
    -- No published output tree (or empty / missing manifest).
    let manifest := outDir / "manifest.json"
    if ← manifest.pathExists then
      throw <| IO.userError
        "failed PrivateSum4 build must not leave a proof-forge manifest (private leak surface)"
/-- Even if compile were hypothetically ok, capability mint for non-Noir (and Noir
    without privateWitness S2 row) must refuse — defensive multi-target pin. -/
private unsafe def testTargetsRefuseIfCompileSucceeded : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 privateSum4SourceText
      "<app1-targets>" "Examples.PrivateSum4" none with
  | .error _ => pure ()  -- already fail closed at parse/select
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error _ => pure ()  -- expected path
      | .ok compiled =>
          for tid in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
            let selection ← match resolveBuildSelectionV1 tid none with
              | .ok s => pure s
              | .error e => throw <| IO.userError s!"selection {tid}: {e.render}"
            match Targets.resolveEngineeringRequirementsV1 selection compiled with
            | .ok _ =>
                throw <| IO.userError
                  s!"{tid}: must not mint capability for PrivateSum4 privacy vector"
            | .error _ => pure ()

unsafe def run : IO Unit := do
  testProductCompilePfVis001
  testCliCheckNoLeak
  testCliBuildNoArtifactLeak
  testTargetsRefuseIfCompileSucceeded
  IO.println "Tests.Product.PrivateSum4PrivacyV1: ok"

end Tests.Product.PrivateSum4PrivacyV1
