/-
  Tests.Typed.ContextExtensionCheckV1 — T-2 context/extension CheckV1 gate.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.ProvenanceV1
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Typed.CheckV1
import ProofForgeV2.Typed.ContextExtensionCheckV1
import Tests.Language.ParserSession

namespace Tests.Typed.ContextExtensionCheckV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Language.Loader
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ProvenanceV1
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.CheckV1
open ProofForgeV2.Typed.ContextExtensionCheckV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def hasSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private unsafe def load (session : ParserSession) (src label mod_ : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 src label mod_ none with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: {e.render}"

private unsafe def loadWithSpans (session : ParserSession) (src label mod_ : String) :
    IO (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  match ← session.selectProgramV1WithSpans src label mod_ none with
  | .ok pair => pure pair
  | .error e => throw <| IO.userError s!"{label}: {e.render}"

private def expectNormalizeOk
    (label : String) (result : Except NormalizeErrorV1 α) : IO α := do
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: normalize failed: {repr error}"

private unsafe def testAdmittedCallerOk (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program CtxOk where\n" ++
    "  entry run() : Principal do\n" ++
    "    return context.caller\n"
  let v ← load session src "<ctx-ok>" "Tests.CtxOk"
  let r := checkContextExtensionResultV1 v
  expect (r.ok && r.diagnostics.isEmpty) "admitted context.caller ok"
  expect (checkProgramTypedResultV1 v).ok "CheckV1 ok with caller"

/-- Non-admitted `context.*` place that still name-resolves: state named
    `context` with field `foo` is not ContextRead (only caller/unixTimeSeconds
    are admitted). NameResolution/TypeCheck succeed; ContextExtensionCheck
    must emit the exact reqPrecondition gate. -/
private unsafe def testBadContextSurface (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program CtxBad where\n" ++
    "  struct Bag where\n" ++
    "    foo : UInt64\n" ++
    "  state context : Bag\n" ++
    "  init() do\n" ++
    "    context := Bag.new(0)\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return context.foo\n"
  let v ← load session src "<ctx-bad>" "Tests.CtxBad"
  let r := checkContextExtensionResultV1 v
  expect r.analysisComplete
    "ctx-bad: ContextExtension analysis must complete (resolution ok)"
  expect (!r.ok) "ctx-bad: ContextExtension must fail closed"
  expect (r.diagnostics.size ≥ 1) "ctx-bad: must emit diagnostics"
  let d := r.diagnostics[0]!
  expect (d.code == .reqPrecondition)
    s!"ctx-bad: code must be reqPrecondition, got {d.code.wire}"
  expect (d.message ==
      "unsupported context surface (only context.caller and context.unixTimeSeconds are admitted)")
    s!"ctx-bad: exact message, got {d.message}"
  let composed := checkProgramTypedResultV1 v
  expect (!composed.ok) "ctx-bad: CheckV1 composition must fail"
  expect (composed.diagnostics.any fun x =>
      x.code == .reqPrecondition &&
        x.message ==
          "unsupported context surface (only context.caller and context.unixTimeSeconds are admitted)")
    "ctx-bad: CheckV1 must surface the same ContextExtension gate"

private def solanaCpiDigest : String :=
  "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

private def extensionSource
    (programName extensionId version digest : String) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  "program " ++ programName ++ " where\n" ++
  "  requires extension " ++ extensionId ++ " version \"" ++ version ++ "\"\n" ++
  "    digest \"" ++ digest ++ "\"\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def testExactSolanaCpiExtensionOk (session : ParserSession) : IO Unit := do
  let v ← load session
    (extensionSource "ExtOk" "solana.cpi.accounts" "1.0.0" solanaCpiDigest)
    "<ext-ok>" "Tests.ExtOk"
  let r := checkContextExtensionResultV1 v
  expect (r.ok && r.analysisComplete && r.diagnostics.isEmpty)
    "exact Solana CPI extension triple must pass ContextExtension Check"
  let composed := checkProgramTypedResultV1 v
  expect (composed.ok && composed.analysisComplete)
    "exact Solana CPI extension triple must pass CheckV1 composition"

private unsafe def testSolanaCpiExtensionSemanticAndProvenance
    (session : ParserSession) : IO Unit := do
  let label := "tests/solana-cpi-extension-v1.pf"
  let source :=
    extensionSource "ExtSemantic" "solana.cpi.accounts" "1.0.0" solanaCpiDigest
  let (validated, spans) ← loadWithSpans session source label "Tests.ExtSemantic"
  let carrier ← expectNormalizeOk "extension semantic" (normalizeProgramV1 validated)
  let data ← match validateSemanticProgramV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"extension semantic: validate failed: {repr error}"
  let expectedRow ← match solanaCpiAccountsExtensionRequirementV1 with
    | .ok row => pure row
    | .error error => throw <| IO.userError s!"extension row: {error}"
  let extensionRows := data.requirements.items.filter fun row =>
    row.id == wireExtensionSolanaCpiAccountsIdV1
  expect (extensionRows == #[expectedRow])
    s!"extension semantic: expected one exact row, got count={extensionRows.size}"

  let path ← match parseProjectRelativePath label with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"extension path: {error}"
  let (carrierWithProvenance, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"extension provenance: {repr error}"
  expect (carrierWithProvenance.canonicalBytes == carrier.canonicalBytes)
    "extension provenance: normalization must preserve semantic bytes"

  let mut requirementIndex? : Option Nat := none
  for (row, index) in data.requirements.items.zipIdx do
    if row.id == wireExtensionSolanaCpiAccountsIdV1 then
      requirementIndex? := some index
  let some requirementIndex := requirementIndex? |
    throw <| IO.userError "extension provenance: missing requirement index"
  let some binding := provenance.originMap.find? fun candidate =>
      candidate.entity == .requirement (UInt32.ofNat requirementIndex) |
    throw <| IO.userError "extension provenance: missing requirement binding"
  expect (binding.origins.size == 1)
    s!"extension provenance: declaration-only row must have one origin, got {binding.origins.size}"

  let assignments ← match assignNodeIdsV1
      validated.moduleName validated.programIdentity validated.program with
    | .ok table => pure (nodeAssignmentsPreorderV1 table)
    | .error error => throw <| IO.userError s!"extension assignments: {error}"
  let extensionPath : NormalizedSyntacticPathV1 := #[{
    parentTag := "Program", fieldTag := "items", index := 0 }]
  let some extensionAssignment := assignments.find? fun assignment =>
      assignment.path == extensionPath |
    throw <| IO.userError "extension provenance: missing ExtensionReq assignment"
  let some extensionOrigin := binding.origins[0]? |
    throw <| IO.userError "extension provenance: missing declaration origin"
  expect (extensionOrigin.nodeId == extensionAssignment.nodeId)
    "extension provenance: requirement must bind the ExtensionReq declaration node"

  let noExtension ← load session
    ("import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
      "program ExtAbsent where\n" ++
      "  entry run() : UInt64 do\n" ++
      "    return 0\n")
    "<ext-absent>" "Tests.ExtAbsent"
  let absentCarrier ← expectNormalizeOk "extension absent" (normalizeProgramV1 noExtension)
  let absentData ← match validateSemanticProgramV1 absentCarrier with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"extension absent: {repr error}"
  expect (!(absentData.requirements.items.any fun row =>
      row.id == wireExtensionSolanaCpiAccountsIdV1))
    "extension absent: normalizer must not invent the extension row"

private unsafe def expectExtensionFailure
    (session : ParserSession) (label programName extensionId version digest : String)
    (code : DiagnosticCodeV1) : IO Unit := do
  let v ← load session (extensionSource programName extensionId version digest)
    ("<" ++ label ++ ">") ("Tests." ++ programName)
  let r := checkContextExtensionResultV1 v
  expect (r.analysisComplete && !r.ok)
    s!"{label}: ContextExtension must fail after complete analysis"
  expect (r.diagnostics.size == 1)
    s!"{label}: expected one diagnostic, got {r.diagnostics.size}"
  expect (r.diagnostics[0]!.code == code)
    s!"{label}: expected {code.wire}, got {r.diagnostics[0]!.code.wire}"
  let composed := checkProgramTypedResultV1 v
  expect (!composed.ok && composed.diagnostics.any (·.code == code))
    s!"{label}: CheckV1 composition must preserve {code.wire}"
  expect (match normalizeProgramV1 v with
    | .error (.typedNotOk diagnostics) => diagnostics.any (·.code == code)
    | _ => false)
    s!"{label}: Normalize must stop at typedNotOk with {code.wire}"

private unsafe def testExtensionNegativeMatrix (session : ParserSession) : IO Unit := do
  let zeroDigest :=
    "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  expectExtensionFailure session "ext-unknown" "ExtUnknown"
    "proof.forge.feature" "1.0.0" zeroDigest .ext001
  expectExtensionFailure session "ext-version" "ExtVersion"
    "solana.cpi.accounts" "1.0.1" solanaCpiDigest .extensionVersion
  expectExtensionFailure session "ext-digest" "ExtDigest"
    "solana.cpi.accounts" "1.0.0" zeroDigest .extensionVersion

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testAdmittedCallerOk session
  testBadContextSurface session
  testExactSolanaCpiExtensionOk session
  testSolanaCpiExtensionSemanticAndProvenance session
  testExtensionNegativeMatrix session
  IO.println "Tests.Typed.ContextExtensionCheckV1: ok"

end Tests.Typed.ContextExtensionCheckV1
