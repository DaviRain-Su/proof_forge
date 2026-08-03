/-
  Tests.CLI.InlineProofProductV1 — product CLI inline-proof cutover.

  Spawns the real `proof-forge-next` binary for:
    * Counter check: noProof success with proofStatus=not-required, count 0, digest none/null
    * false-theorem program: check fails PF-SRC-INVALID / exit 3
    * false theorem + invalid/unsupported target on build: proof failure wins,
      zero output directory (certifier before TargetRegistry resolve/materialize)
    * false theorem + valid target on build: fails before staging, no output
    * legacy `--proof-bundle*` flags remain unknown options

  Positive product invariant certification remains open (bridge authoring gap).
  No sorry / axiom / native_decide / unsafe proof escape / forged positive.
-/
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Core.Common

namespace Tests.CLI.InlineProofProductV1

open System
open ProofForgeV2.CLI
open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def hasSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def stripTrailingNewlines (s : String) : String :=
  let rec loop (cs : List Char) : List Char :=
    match cs with
    | [] => []
    | c :: rest =>
        if c == '\n' || c == '\r' then loop rest else cs
  String.ofList (loop s.toList.reverse).reverse

private def expectCanonicalJson (label text : String) : IO Unit := do
  let body := stripTrailingNewlines text
  match parsePfJcs body with
  | .ok value =>
      match renderPfJcs value with
      | .ok again =>
          expect (again == body)
            s!"{label}: PF-JCS must re-encode identically"
      | .error e => throw <| IO.userError s!"{label}: re-render failed: {e}"
  | .error e => throw <| IO.userError s!"{label}: not PF-JCS: {e}\n{text}"

private def cliBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-next"

private def runCli (args : Array String) : IO (UInt32 × String × String) := do
  unless ← cliBin.pathExists do
    throw <| IO.userError "proof-forge-next missing (build product CLI)"
  let absoluteCli ← IO.FS.realPath cliBin
  let out ← IO.Process.output {
    cmd := absoluteCli.toString
    args := args
  }
  pure (out.exitCode, out.stdout, out.stderr)

private def fixtureRoot : FilePath :=
  FilePath.mk "build/v2/inline-proof-cli-fixtures"

private def fixtureHeader : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n"

/-- Structurally legal inventory + false theorem (`rfl` cannot close
    `InvariantTheoremV1`). Same shape as certifier suite negatives. -/
private def falseTheoremSource : String :=
  fixtureHeader ++
  "program Proofed where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n" ++
  "  invariant safe : true\n" ++
  "  proof safe using ProofedProof.safe\n" ++
  "theorem ProofedProof.safe : Proofed.Proof.safe := by\n" ++
  "  rfl\n"

private def writeFixture (name body : String) : IO FilePath := do
  IO.FS.createDirAll fixtureRoot
  let path := fixtureRoot / FilePath.mk name
  IO.FS.writeFile path body
  pure path

private def relativeFixture (name : String) : String :=
  s!"build/v2/inline-proof-cli-fixtures/{name}"

/-- Counter check: no proof surface → status not-required. -/
private def testCounterCheckNoProof : IO Unit := do
  let (ec, stdout, stderr) ← runCli #[
    "check", "Examples/Counter.lean",
    "--module", "Examples.Counter"
  ]
  expect (ec == 0)
    s!"Counter check must exit 0, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (hasSubstr stdout "ok\n") "Counter check ok line"
  expect (hasSubstr stdout "proofStatus=not-required")
    s!"Counter check must report not-required proof status:\n{stdout}"
  expect (hasSubstr stdout "proofTheoremCount=0")
    s!"Counter check theorem count must be 0:\n{stdout}"
  expect (hasSubstr stdout "proofCertificationDigest=none")
    s!"Counter check digest must be none:\n{stdout}"
  expect (stderr == "")
    s!"Counter check ok must be silent on stderr, got {stderr}"

  let (ecJ, stdoutJ, stderrJ) ← runCli #[
    "check", "Examples/Counter.lean",
    "--module", "Examples.Counter", "--json"
  ]
  expect (ecJ == 0)
    s!"Counter check --json must exit 0, got {ecJ}\n{stderrJ}"
  expectCanonicalJson "counter-check" stdoutJ
  expect (hasSubstr stdoutJ "\"proofStatus\":\"not-required\"")
    s!"json proofStatus: {stdoutJ}"
  expect (hasSubstr stdoutJ "\"proofTheoremCount\":0")
    s!"json theorem count: {stdoutJ}"
  expect (hasSubstr stdoutJ "\"proofCertificationDigest\":null")
    s!"json digest null: {stdoutJ}"
  -- Source/semantic digests remain present and independent of proof status.
  expect (hasSubstr stdoutJ "\"sourceDigest\":\"sha256:")
    s!"source digest preserved: {stdoutJ}"
  expect (hasSubstr stdoutJ "\"semanticDigest\":\"sha256:")
    s!"semantic digest preserved: {stdoutJ}"

/-- False theorem: product check fails closed with PF-SRC-INVALID / exit 3. -/
private def testFalseTheoremCheckFails : IO Unit := do
  let _ ← writeFixture "false-theorem.lean" falseTheoremSource
  let rel := relativeFixture "false-theorem.lean"
  let (ec, stdout, stderr) ← runCli #[
    "check", rel, "--module", "Root"
  ]
  expect (ec == 3)
    s!"false theorem check must exit 3, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (hasSubstr stderr "PF-SRC-INVALID")
    s!"false theorem must emit PF-SRC-INVALID:\n{stderr}"
  expect (hasSubstr stderr "inline proof certification failed")
    s!"false theorem must name certifier failure:\n{stderr}"
  expect (!hasSubstr stdout "ok\n")
    "false theorem must not print check success"
  expect (!hasSubstr stdout "proofStatus=certified")
    "false theorem must not claim certified"

/-- Build false theorem before invalid target: proof failure wins, zero output. -/
private def testFalseTheoremBuildBeforeInvalidTarget : IO Unit := do
  let _ ← writeFixture "false-before-target.lean" falseTheoremSource
  let rel := relativeFixture "false-before-target.lean"
  let outDir := FilePath.mk "build/v2/inline-proof-false-before-unknown-target"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (ec, stdout, stderr) ← runCli #[
    "build", rel,
    "--module", "Root",
    "--target", "not-a-real-target",
    "-o", outDir.toString
  ]
  expect (ec == 3)
    s!"proof failure must win over unknown target (exit 3), got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (hasSubstr stderr "PF-SRC-INVALID")
    s!"must be product diagnostic, not usage:\n{stderr}"
  expect (!hasSubstr stderr "unknown target")
    s!"unknown target must not surface when proof fails first:\n{stderr}"
  expect (!(← outDir.pathExists))
    "proof failure must create no output directory"
  expect (!hasSubstr stdout "built target=")
    "proof failure must not print build success"

/-- Build false theorem with valid target still fails before materialize/staging. -/
private def testFalseTheoremBuildBeforeMaterialize : IO Unit := do
  let _ ← writeFixture "false-before-materialize.lean" falseTheoremSource
  let rel := relativeFixture "false-before-materialize.lean"
  let outDir := FilePath.mk "build/v2/inline-proof-false-before-materialize"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let (ec, stdout, stderr) ← runCli #[
    "build", rel,
    "--module", "Root",
    "--target", "solana",
    "-o", outDir.toString
  ]
  expect (ec == 3)
    s!"false theorem build must exit 3, got {ec}\nstderr={stderr}\nstdout={stdout}"
  expect (hasSubstr stderr "PF-SRC-INVALID")
    s!"false theorem build PF-SRC-INVALID:\n{stderr}"
  expect (!(← outDir.pathExists))
    "certifier failure must not publish or stage an output directory"
  -- Sibling staging residue must also be absent.
  let parent := FilePath.mk "build/v2"
  if ← parent.pathExists then
    let entries ← parent.readDir
    let stagingLeft := entries.filter fun e =>
      e.fileName.startsWith ".inline-proof-false-before-materialize.staging-"
    expect stagingLeft.isEmpty
      "certifier failure must not leave staging residue"
  expect (!hasSubstr stdout "built target=")
    "false theorem build must not print success"

/-- Legacy structural ambient flags stay unknown options. -/
private def testLegacyProofBundleFlagsUnknown : IO Unit := do
  match parseProductCliCommandV1
      ["check", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--proof-bundle", "/tmp/pb"] with
  | .ok _ => throw <| IO.userError "legacy --proof-bundle must be unknown"
  | .error msg =>
      expect (hasSubstr msg "unknown option")
        s!"legacy --proof-bundle: {msg}"
  match parseProductCliCommandV1
      ["build", "Examples/Counter.lean", "--module", "Examples.Counter",
        "--target", "evm",
        "--proof-bundle-digest",
        "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"] with
  | .ok _ => throw <| IO.userError "legacy --proof-bundle-digest must be unknown"
  | .error msg =>
      expect (hasSubstr msg "unknown option")
        s!"legacy --proof-bundle-digest: {msg}"

/-- Pure renderer pin: notRequired vs certified fields stay schema-compatible. -/
private def testRenderProofStatusFields : IO Unit := do
  let dig : Digest :=
    { algorithm := .sha256
      bytes := ByteArray.mk (Array.replicate 32 0) }
  match renderCheckOkJsonV1 "Counter" dig dig none none #[] .notRequired with
  | .error e => throw <| IO.userError s!"render notRequired: {e.render}"
  | .ok text =>
      expect (hasSubstr text "\"proofStatus\":\"not-required\"") "json not-required"
      expect (hasSubstr text "\"proofTheoremCount\":0") "json count 0"
      expect (hasSubstr text "\"proofCertificationDigest\":null") "json digest null"
  match renderCheckOkHumanV1 "Counter" dig dig none none .notRequired with
  | .error e => throw <| IO.userError s!"human notRequired: {e.render}"
  | .ok text =>
      expect (hasSubstr text "proofStatus=not-required") "human not-required"
      expect (hasSubstr text "proofTheoremCount=0") "human count 0"
      expect (hasSubstr text "proofCertificationDigest=none") "human digest none"
  let certDig : Digest :=
    { algorithm := .sha256
      bytes := ByteArray.mk (Array.replicate 32 1) }
  match renderCheckOkJsonV1 "Proofed" dig dig none none #[]
      (.certified 1 certDig) with
  | .error e => throw <| IO.userError s!"render certified: {e.render}"
  | .ok text =>
      expect (hasSubstr text "\"proofStatus\":\"certified\"") "json certified"
      expect (hasSubstr text "\"proofTheoremCount\":1") "json count 1"
      expect (hasSubstr text "\"proofCertificationDigest\":\"sha256:")
        "json cert digest wire"
      -- Source/semantic digests unchanged by proof observation.
      expect (hasSubstr text "\"sourceDigest\":\"sha256:0000")
        "source digest independent"
  match renderCheckOkHumanV1 "Proofed" dig dig none none
      (.certified 1 certDig) with
  | .error e => throw <| IO.userError s!"human certified: {e.render}"
  | .ok text =>
      expect (hasSubstr text "proofStatus=certified") "human certified"
      expect (hasSubstr text "proofTheoremCount=1") "human count 1"
      expect (hasSubstr text "proofCertificationDigest=sha256:")
        "human cert digest"

def run : IO Unit := do
  testRenderProofStatusFields
  testLegacyProofBundleFlagsUnknown
  if ← cliBin.pathExists then
    testCounterCheckNoProof
    testFalseTheoremCheckFails
    testFalseTheoremBuildBeforeInvalidTarget
    testFalseTheoremBuildBeforeMaterialize
  else
    IO.println "Tests.CLI.InlineProofProductV1: skip product CLI (binary absent)"
  IO.println "Tests.CLI.InlineProofProductV1: ok"

end Tests.CLI.InlineProofProductV1
