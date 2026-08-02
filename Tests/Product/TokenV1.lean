/-
  Tests.Product.TokenV1 — NS-1 fungible Token northstar pin.

  Authority: shipped `Examples/Token.lean`.
    * product `check` succeeds (Normalize Map path: empty + IndexGet/Set)
    * product `build` for evm/solana/near/noir fails closed with Map
      container-state pilot boundary (PF-PLAN-INVARIANT); no output tree
    * not Principal-keyed (still target-gated); not IBC; not four-target deploy

  Opening Map Plan on any target is a separate B/leaf slice — this suite must
  flip only when that happens intentionally.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import Tests.Language.ParserSession

namespace Tests.Product.TokenV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def shippedPath : FilePath := FilePath.mk "Examples/Token.lean"

private def readShipped : IO String := do
  unless ← shippedPath.pathExists do
    throw <| IO.userError "Examples/Token.lean missing (NS-1 continuous vector)"
  IO.FS.readFile shippedPath

private def assertShape (text : String) : IO Unit := do
  expect (containsSubstr text "program Token where") "must declare program Token"
  expect (containsSubstr text "Map UInt64 UInt64") "must use Map balances"
  expect (containsSubstr text "Map.empty()") "must init balances with Map.empty()"
  expect (containsSubstr text "entry mint") "must declare mint"
  expect (containsSubstr text "entry transfer") "must declare transfer"
  expect (containsSubstr text "view balanceOf") "must declare balanceOf"
  expect (containsSubstr text "Option.some")
    "must pattern-match Map IndexGet as Option.some"
  -- Reserved Lean keyword in params breaks product Loader (APP-1 lesson).
  expect (!containsSubstr text "from :")
    "must not use reserved param name `from`"

private def cliBin : FilePath := FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output { cmd := absoluteCli.toString, args }
  pure (out.exitCode, out.stdout, out.stderr)

/-- Product compile of shipped Token must succeed (semantic carrier). -/
private unsafe def testProductCompileOk : IO Unit := do
  let text ← readShipped
  assertShape text
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 text "Examples/Token.lean" "Examples.Token" none with
  | .error e =>
      throw <| IO.userError s!"Token select must succeed: {e.code}: {e.render}"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error e =>
          throw <| IO.userError s!"Token product compile must succeed: {e.render}"
      | .ok _ => pure ()

/-- Real CLI check on shipped Examples/Token.lean. -/
private def testCliCheckOk : IO Unit := do
  assertShape (← readShipped)
  let (code, stdout, stderr) ← runCli
    #["check", "Examples/Token.lean", "--module", "Examples.Token"]
  expect (code == 0)
    s!"Token check must succeed, exit={code} stderr={stderr} stdout={stdout}"
  expect (containsSubstr stdout "program=Token" || containsSubstr stdout "Token")
    s!"check ok must name Token, stdout={stdout}"

private def fourTargets : Array String := #["evm", "solana", "near", "noir"]

/-- Four-target build must fail closed on Map state (no materialize / no manifest). -/
private def testFourTargetsMapFailClosed : IO Unit := do
  assertShape (← readShipped)
  for tid in fourTargets do
    let outDir := FilePath.mk s!".lake/build/tmp-ns1-token-{tid}"
    try IO.FS.removeDirAll outDir catch _ => pure ()
    let (code, stdout, stderr) ← runCli
      #["build", "Examples/Token.lean",
        "--module", "Examples.Token",
        "--target", tid,
        "-o", outDir.toString]
    expect (code != 0)
      s!"Token build --target {tid} must fail closed, exit={code}"
    let combined := stdout ++ "\n" ++ stderr
    expect (
        containsSubstr combined "Map" ||
        containsSubstr combined "container-state" ||
        containsSubstr combined "PF-PLAN-INVARIANT" ||
        containsSubstr combined "PF-REQ")
      s!"{tid}: must cite Map/container/PLAN boundary, got:\n{combined}"
    if ← (outDir / "manifest.json").pathExists then
      throw <| IO.userError
        s!"{tid}: failed Token build must not leave manifest.json"
    try IO.FS.removeDirAll outDir catch _ => pure ()

unsafe def run : IO Unit := do
  testProductCompileOk
  testCliCheckOk
  testFourTargetsMapFailClosed
  IO.println "Tests.Product.TokenV1: ok"

end Tests.Product.TokenV1
