/-
  Tests.CLI.InlineProofProductV1 — product CLI inline-proof cutover.

  Spawns the real `proof-forge-next` binary for:
    * Counter check: noProof success with proofStatus=not-required, count 0, digest none/null
    * false-theorem program: check fails PF-SRC-INVALID / exit 3
    * false theorem + invalid/unsupported target on build: proof failure wins,
      zero output directory (certifier before TargetRegistry resolve/materialize)
    * false theorem + valid target on build: fails before staging, no output
    * legacy `--proof-bundle*` flags remain unknown options
    * raw same-file simple-closure product-positive (strict red until production
      mints unconditional `generatedSafeV1` + closes encode/decode):
        author inventory theorem is ordinary `SimpleProof.safe`; body exacts
        generated `<Program>.Proof.generatedSafeV1` (never
        redeclared as the inventory theorem)
        (2) CLI check human+JSON → certified, count=1, nonempty digest;
            human digest wire exact-equals JSON digest
        (3) alternate allowlisted body (`apply` vs `exact`): source/semantic digests
            stable; proofCertificationDigest **must** change (raw source bound)
        (4) certified then unknown target → unknown target, zero output
        (5) repeat check → same proofCertificationDigest
        (6) certified + legal target → materializer nonempty-invariant fail closed,
            no destination/staging
      Hard-fails when check is not certified (no soft skip / EXPECTED-RED).
      Product binary is required; absence fails the suite (not skipped).

  No sorry / axiom / native_decide / unsafe proof escape / forged positive.
  Does not import or proxy Tests.Semantic.ProofedClosedCertV1.
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

/-- Literal-true simple-closure: ordinary adjacent author theorem + body that
    exacts planned generated helper (not redeclared under that name). -/
private def simpleClosureSource
    (programName authorTheorem bodyExtra : String) : String :=
  fixtureHeader ++
  "program " ++ programName ++ " where\n" ++
  "  view alive() : Bool do\n" ++
  "    return true\n" ++
  "  invariant safe : true\n" ++
  "  proof safe using " ++ authorTheorem ++ "\n" ++
  bodyExtra

/-- Primary author body (allowlisted `exact`). -/
private def simpleClosureAuthorBodyExact
    (authorTheorem programName : String) : String :=
  "theorem " ++ authorTheorem ++ " : " ++ programName ++
    ".Proof.safe := by\n" ++
  "  exact " ++ programName ++ ".Proof.generatedSafeV1\n"

/-- Alternate allowlisted body with distinct raw source.
    `simpa` / `simp only [lemma]` emit disallowed simpLemma; use `apply`. -/
private def simpleClosureAuthorBodyApply
    (authorTheorem programName : String) : String :=
  "theorem " ++ authorTheorem ++ " : " ++ programName ++
    ".Proof.safe := by\n" ++
  "  apply " ++ programName ++ ".Proof.generatedSafeV1\n"

private def writeFixture (name body : String) : IO FilePath := do
  IO.FS.createDirAll fixtureRoot
  let path := fixtureRoot / FilePath.mk name
  IO.FS.writeFile path body
  pure path

private def relativeFixture (name : String) : String :=
  s!"build/v2/inline-proof-cli-fixtures/{name}"

/-- Extract a human `key=value` field from check stdout (first match). -/
private def humanField? (stdout key : String) : Option String :=
  let needle := key ++ "="
  let rec loop (lines : List String) : Option String :=
    match lines with
    | [] => none
    | line :: rest =>
        if hasSubstr line needle &&
            needle.toList.isPrefixOf line.toList then
          -- Lean 4.31: drop returns String.Slice; rebuild via characters.
          let cs := line.toList.drop needle.length
          some (String.ofList cs)
        else
          loop rest
  loop (stdout.splitOn "\n")

/-- Extract a JSON string field value for `"key":"…"` (first match). -/
private def jsonStringField? (text key : String) : Option String :=
  let needle := s!"\"{key}\":\""
  match text.splitOn needle with
  | _ :: more =>
      match more with
      | rest :: _ =>
          match rest.splitOn "\"" with
          | value :: _ => some value
          | [] => none
      | [] => none
  | _ => none

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

/-- (2)(3)(5) simple-closure check positive + hash independence + digest change.
    (4) unknown target after certified. (6) materializer FC on nonempty invariant.
    Strict: hard-fails unless check exits 0 with proofStatus=certified. -/
private def testSimpleClosureProductPositiveCli : IO Unit := do
  let programName := "Simple"
  let authorTheorem := "SimpleProof.safe"
  let srcA := simpleClosureSource programName authorTheorem
    (simpleClosureAuthorBodyExact authorTheorem programName)
  let srcB := simpleClosureSource programName authorTheorem
    (simpleClosureAuthorBodyApply authorTheorem programName)
  expect (srcA != srcB) "CLI fixtures must differ only in theorem body"
  let _ ← writeFixture "simple-closure-a.lean" srcA
  let _ ← writeFixture "simple-closure-b.lean" srcB
  let relA := relativeFixture "simple-closure-a.lean"
  let relB := relativeFixture "simple-closure-b.lean"

  let (ecA, stdoutA, stderrA) ← runCli #["check", relA, "--module", "Root"]
  -- Strict product-positive: no soft-green / skip on failure.
  expect (ecA == 0)
    s!"simple-closure check must exit 0 certified, got {ecA}\nstderr={stderrA}\nstdout={stdoutA}"

  -- (2) human certified
  expect (hasSubstr stdoutA "ok\n") s!"check ok:\n{stdoutA}"
  expect (hasSubstr stdoutA "proofStatus=certified")
    s!"human certified:\n{stdoutA}"
  expect (hasSubstr stdoutA "proofTheoremCount=1")
    s!"human count=1:\n{stdoutA}"
  let digA ← match humanField? stdoutA "proofCertificationDigest" with
    | some d => pure d
    | none => throw <| IO.userError s!"missing human cert digest:\n{stdoutA}"
  expect (hasSubstr digA "sha256:")
    s!"human cert digest wire:\n{digA}"
  expect (digA != "none")
    "certified digest must not be none"
  expect (stderrA == "")
    s!"certified check must be silent on stderr: {stderrA}"

  let (ecJ, stdoutJ, stderrJ) ← runCli #[
    "check", relA, "--module", "Root", "--json"
  ]
  expect (ecJ == 0) s!"json check exit 0, got {ecJ}\n{stderrJ}"
  expectCanonicalJson "simple-closure-check" stdoutJ
  expect (hasSubstr stdoutJ "\"proofStatus\":\"certified\"")
    s!"json certified: {stdoutJ}"
  expect (hasSubstr stdoutJ "\"proofTheoremCount\":1")
    s!"json count 1: {stdoutJ}"
  expect (hasSubstr stdoutJ "\"proofCertificationDigest\":\"sha256:")
    s!"json cert digest: {stdoutJ}"
  let srcDigA ← match jsonStringField? stdoutJ "sourceDigest" with
    | some d => pure d
    | none => throw <| IO.userError s!"json sourceDigest: {stdoutJ}"
  let semDigA ← match jsonStringField? stdoutJ "semanticDigest" with
    | some d => pure d
    | none => throw <| IO.userError s!"json semanticDigest: {stdoutJ}"
  let certDigJ ← match jsonStringField? stdoutJ "proofCertificationDigest" with
    | some d => pure d
    | none => throw <| IO.userError s!"json cert digest missing: {stdoutJ}"
  -- human and JSON must observe the same certification digest wire.
  expect (digA == certDigJ)
    s!"human/JSON proofCertificationDigest must match:\nhuman={digA}\njson={certDigJ}"

  -- (3) theorem-body rewrite: source/semantic stable; cert digest **must** change
  let (ecB, stdoutB, stderrB) ← runCli #[
    "check", relB, "--module", "Root", "--json"
  ]
  expect (ecB == 0)
    s!"alt body must also certify, got {ecB}\n{stderrB}\n{stdoutB}"
  expectCanonicalJson "simple-closure-check-b" stdoutB
  expect (hasSubstr stdoutB "\"proofStatus\":\"certified\"")
    s!"alt certified: {stdoutB}"
  let srcDigB ← match jsonStringField? stdoutB "sourceDigest" with
    | some d => pure d
    | none => throw <| IO.userError s!"alt sourceDigest: {stdoutB}"
  let semDigB ← match jsonStringField? stdoutB "semanticDigest" with
    | some d => pure d
    | none => throw <| IO.userError s!"alt semanticDigest: {stdoutB}"
  expect (srcDigA == srcDigB)
    s!"sourceDigest independent of theorem body:\nA={srcDigA}\nB={srcDigB}"
  expect (semDigA == semDigB)
    s!"semanticDigest independent of theorem body:\nA={semDigA}\nB={semDigB}"
  let certDigB ← match jsonStringField? stdoutB "proofCertificationDigest" with
    | some d => pure d
    | none => throw <| IO.userError s!"alt cert digest: {stdoutB}"
  expect (hasSubstr certDigJ "sha256:" && hasSubstr certDigB "sha256:")
    "cert digests must be sha256 wires"
  expect (certDigJ != certDigB)
    s!"proofCertificationDigest must change with theorem body:\nA={certDigJ}\nB={certDigB}"

  -- (5) repeat check digest stable
  let (ecR, stdoutR, stderrR) ← runCli #[
    "check", relA, "--module", "Root", "--json"
  ]
  expect (ecR == 0) s!"repeat check exit 0: {ecR}\n{stderrR}"
  let certDigR ← match jsonStringField? stdoutR "proofCertificationDigest" with
    | some d => pure d
    | none => throw <| IO.userError s!"repeat cert digest: {stdoutR}"
  expect (certDigR == certDigJ)
    s!"repeat check digest must be stable:\n1={certDigJ}\n2={certDigR}"

  -- (4) certified then unknown target → usage unknown target, zero output
  let outUnknown := FilePath.mk "build/v2/inline-proof-simple-unknown-target"
  if ← outUnknown.pathExists then IO.FS.removeDirAll outUnknown
  let (ecU, stdoutU, stderrU) ← runCli #[
    "build", relA,
    "--module", "Root",
    "--target", "not-a-real-target",
    "-o", outUnknown.toString
  ]
  -- Usage exit for unknown target (not PF-SRC-INVALID — proof already certified).
  expect (ecU != 0)
    s!"unknown target must fail, got {ecU}\n{stderrU}\n{stdoutU}"
  expect (hasSubstr stderrU "unknown target")
    s!"must report unknown target after certified:\n{stderrU}"
  expect (!hasSubstr stderrU "PF-SRC-INVALID")
    s!"certified path must not re-fail as PF-SRC-INVALID:\n{stderrU}"
  expect (!(← outUnknown.pathExists))
    "unknown target must create no destination"
  expect (!hasSubstr stdoutU "built target=")
    "unknown target must not print build success"

  -- (6) legal target + nonempty invariant → materializer fail closed, no staging
  let outSol := FilePath.mk "build/v2/inline-proof-simple-solana-fc"
  if ← outSol.pathExists then IO.FS.removeDirAll outSol
  let (ecS, stdoutS, stderrS) ← runCli #[
    "build", relA,
    "--module", "Root",
    "--target", "solana",
    "-o", outSol.toString
  ]
  expect (ecS != 0)
    s!"nonempty invariant materializer must fail closed, got {ecS}\n{stderrS}\n{stdoutS}"
  expect (
      hasSubstr stderrS "invariant" ||
      hasSubstr stderrS "invariants" ||
      hasSubstr stderrS "unsupported")
    s!"must name invariant/unsupported materializer FC:\n{stderrS}"
  expect (!(← outSol.pathExists))
    "materializer FC must not publish destination"
  let parent := FilePath.mk "build/v2"
  if ← parent.pathExists then
    let entries ← parent.readDir
    let stagingLeft := entries.filter fun e =>
      e.fileName.startsWith ".inline-proof-simple-solana-fc.staging-"
    expect stagingLeft.isEmpty
      "materializer FC must not leave staging residue"
  expect (!hasSubstr stdoutS "built target=")
    "materializer FC must not print build success"

  IO.println
    "Tests.CLI.InlineProofProductV1: simple-closure product-positive CERTIFIED (2–6)"

def run : IO Unit := do
  testRenderProofStatusFields
  testLegacyProofBundleFlagsUnknown
  -- Product-positive CLI path hard-requires the built binary (no soft skip).
  unless ← cliBin.pathExists do
    throw <| IO.userError
      "proof-forge-next missing: product-positive CLI suite requires built binary"
  testCounterCheckNoProof
  testFalseTheoremCheckFails
  testFalseTheoremBuildBeforeInvalidTarget
  testFalseTheoremBuildBeforeMaterialize
  testSimpleClosureProductPositiveCli
  IO.println "Tests.CLI.InlineProofProductV1: ok"

end Tests.CLI.InlineProofProductV1
