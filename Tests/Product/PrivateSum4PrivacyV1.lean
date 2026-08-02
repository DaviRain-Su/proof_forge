/-
  Tests.Product.PrivateSum4PrivacyV1 — APP-1 continuous privacy boundary vector.

  Authority: the **shipped** file `Examples/PrivateSum4.lean` (not a parallel
  fixture). Product path must reach disclosure and fail with **PF-VIS-001**
  (private params → public return). PF-SRC-INVALID is a failure of the vector,
  not an acceptable pin.

  Also pins:
    * real `proof-forge-next check` / `build` on that path, exit ≠ 0, PF-VIS-001
    * no `manifest.json` after failed build (no raw-private leak surface)
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

/-- Sole continuous vector path relative to package root. -/
private def shippedSourcePath : FilePath :=
  FilePath.mk "Examples/PrivateSum4.lean"

/-- Read the shipped Examples source; tests must not invent a different body. -/
private def readShippedPrivateSum4 : IO String := do
  unless ← shippedSourcePath.pathExists do
    throw <| IO.userError "Examples/PrivateSum4.lean missing (APP-1 continuous vector)"
  IO.FS.readFile shippedSourcePath

/-- Structural requirements on the shipped vector (so a rewrite cannot drop
    the privacy sink while keeping a green suite). -/
private def assertShippedShape (text : String) : IO Unit := do
  expect (containsSubstr text "program PrivateSum4 where")
    "shipped vector must declare program PrivateSum4"
  expect (containsSubstr text "private a")
    "shipped vector must keep private param a"
  expect (containsSubstr text "private b")
    "shipped vector must keep private param b"
  expect (containsSubstr text "private c")
    "shipped vector must keep private param c"
  expect (containsSubstr text "private d")
    "shipped vector must keep private param d"
  expect (containsSubstr text "return a + b + c + d")
    "shipped vector must return the private sum to a public result"
  -- Doc-comment openers as a line start break product Loader before disclosure.
  let lines := text.splitOn "\n"
  let hasDocOpen := lines.any fun line =>
    let t := String.mk (line.toList.dropWhile fun c => c == ' ' || c == '\t')
    t.startsWith "/--"
  expect (!hasDocOpen)
    "shipped vector must not open module-doc comments (product Loader → PF-SRC-INVALID)"

/-- Product Loader+compile on **shipped** bytes must fail with PF-VIS-001 only. -/
private unsafe def testShippedProductCompilePfVis001 : IO Unit := do
  let text ← readShippedPrivateSum4
  assertShippedShape text
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 text
      "Examples/PrivateSum4.lean" "Examples.PrivateSum4" none with
  | .error e =>
      throw <| IO.userError
        s!"shipped PrivateSum4 must parse/select (got {e.code}: {e.render}); \
PF-SRC-INVALID means the continuous vector is broken before disclosure"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .ok _ =>
          throw <| IO.userError
            "PrivateSum4 must not compile: private→public return is disclosure-illegal"
      | .error e =>
          expect (e.code == "PF-VIS-001")
            s!"expected PF-VIS-001 only, got {e.code}: {e.render}"
          expect (containsSubstr e.render "PF-VIS-001" || containsSubstr e.render "visibility" ||
              containsSubstr e.render "private")
            s!"error must cite visibility/private boundary, got {e.render}"

private def cliBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output {
    cmd := absoluteCli.toString
    args := args
    -- Package root so shipped Examples/PrivateSum4.lean is the product path.
  }
  pure (out.exitCode, out.stdout, out.stderr)

/-- Real product CLI on **shipped** Examples/PrivateSum4.lean → PF-VIS-001. -/
private def testCliCheckShippedPfVis001 : IO Unit := do
  let _ ← readShippedPrivateSum4  -- fail early if file missing
  assertShippedShape (← readShippedPrivateSum4)
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next binary missing (build product CLI)"
  let (code, stdout, stderr) ← runCli
    #["check", "Examples/PrivateSum4.lean",
      "--module", "Examples.PrivateSum4"]
  expect (code != 0) s!"check must fail, exit={code} stdout={stdout} stderr={stderr}"
  let combined := stdout ++ "\n" ++ stderr
  expect (containsSubstr combined "PF-VIS-001")
    s!"check must report PF-VIS-001 (not merely PF-SRC-INVALID), got:\n{combined}"
  expect (!containsSubstr combined "PF-SRC-INVALID")
    s!"shipped vector must not fail at parse; got PF-SRC-INVALID:\n{combined}"
  expect (!containsSubstr combined "private a")
    "diagnostics must not echo raw private param binding text as a leak surface"
  expect (stdout.isEmpty || !containsSubstr stdout "status\":\"ok\"")
    "check must not emit success JSON"

/-- `build --target noir` on shipped vector: fail closed, no manifest. -/
private def testCliBuildShippedNoArtifactLeak : IO Unit := do
  let outDir := FilePath.mk ".lake/build/tmp-app1-privatesum4-out"
  try IO.FS.removeDirAll outDir catch _ => pure ()
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next binary missing (build product CLI)"
  let (code, stdout, stderr) ← runCli
    #["build", "Examples/PrivateSum4.lean",
      "--module", "Examples.PrivateSum4",
      "--target", "noir",
      "-o", outDir.toString]
  expect (code != 0) s!"build must fail, exit={code}"
  let combined := stdout ++ "\n" ++ stderr
  expect (containsSubstr combined "PF-VIS-001")
    s!"build must report PF-VIS-001, got:\n{combined}"
  expect (!containsSubstr combined "PF-SRC-INVALID")
    s!"build must not fail at parse on shipped vector:\n{combined}"
  let manifest := outDir / "manifest.json"
  if ← manifest.pathExists then
    throw <| IO.userError
      "failed PrivateSum4 build must not leave a proof-forge manifest (private leak surface)"
  try IO.FS.removeDirAll outDir catch _ => pure ()

/-- Defensive: if compile ever succeeded, capability mint must still refuse. -/
private unsafe def testTargetsRefuseIfCompileSucceeded : IO Unit := do
  let text ← readShippedPrivateSum4
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 text
      "Examples/PrivateSum4.lean" "Examples.PrivateSum4" none with
  | .error _ =>
      throw <| IO.userError "shipped PrivateSum4 must select for defensive target pin"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error e =>
          expect (e.code == "PF-VIS-001")
            s!"defensive path expects PF-VIS-001, got {e.code}"
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
  testShippedProductCompilePfVis001
  testCliCheckShippedPfVis001
  testCliBuildShippedNoArtifactLeak
  testTargetsRefuseIfCompileSucceeded
  IO.println "Tests.Product.PrivateSum4PrivacyV1: ok"

end Tests.Product.PrivateSum4PrivacyV1
