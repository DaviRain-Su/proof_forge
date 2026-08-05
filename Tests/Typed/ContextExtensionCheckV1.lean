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

private def pfAssetsDigest : String :=
  "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

private def extensionSource
    (programName extensionId version digest : String) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  "program " ++ programName ++ " where\n" ++
  "  requires extension " ++ extensionId ++ " version \"" ++ version ++ "\"\n" ++
  "    digest \"" ++ digest ++ "\"\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return 0\n"

private def dualExtensionSource (programName : String) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  "program " ++ programName ++ " where\n" ++
  "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
  "    digest \"" ++ solanaCpiDigest ++ "\"\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  "    digest \"" ++ pfAssetsDigest ++ "\"\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def expectExactExtensionRow
    (label : String) (items : Array RequirementRequestV1)
    (wireId : String)
    (expected : Except String RequirementRequestV1) : IO Unit := do
  let expectedRow ← match expected with
    | .ok row => pure row
    | .error error => throw <| IO.userError s!"{label}: row seed: {error}"
  let rows := items.filter (·.id == wireId)
  expect (rows == #[expectedRow])
    s!"{label}: expected one exact {wireId} row, got count={rows.size}"

private unsafe def expectDeclarationOnlyProvenance
    (label : String) (validated : ValidatedSourceV1)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))
    (carrier : SemanticProgramV1) (data : SemanticProgramDataV1)
    (wireId : String) (itemIndex : Nat) : IO Unit := do
  let path ← match parseProjectRelativePath label with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"{label} path: {error}"
  let (carrierWithProvenance, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"{label} provenance: {repr error}"
  expect (carrierWithProvenance.canonicalBytes == carrier.canonicalBytes)
    s!"{label} provenance: normalization must preserve semantic bytes"

  let mut requirementIndex? : Option Nat := none
  for (row, index) in data.requirements.items.zipIdx do
    if row.id == wireId then
      requirementIndex? := some index
  let some requirementIndex := requirementIndex? |
    throw <| IO.userError s!"{label} provenance: missing requirement index for {wireId}"
  let some binding := provenance.originMap.find? fun candidate =>
      candidate.entity == .requirement (UInt32.ofNat requirementIndex) |
    throw <| IO.userError s!"{label} provenance: missing requirement binding for {wireId}"
  expect (binding.origins.size == 1)
    s!"{label} provenance: declaration-only row must have one origin, got {binding.origins.size}"

  let assignments ← match assignNodeIdsV1
      validated.moduleName validated.programIdentity validated.program with
    | .ok table => pure (nodeAssignmentsPreorderV1 table)
    | .error error => throw <| IO.userError s!"{label} assignments: {error}"
  let extensionPath : NormalizedSyntacticPathV1 := #[{
    parentTag := "Program", fieldTag := "items", index := UInt32.ofNat itemIndex }]
  let some extensionAssignment := assignments.find? fun assignment =>
      assignment.path == extensionPath |
    throw <| IO.userError s!"{label} provenance: missing ExtensionReq assignment at {itemIndex}"
  let some extensionOrigin := binding.origins[0]? |
    throw <| IO.userError s!"{label} provenance: missing declaration origin"
  expect (extensionOrigin.nodeId == extensionAssignment.nodeId)
    s!"{label} provenance: requirement must bind the ExtensionReq declaration node"

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

private unsafe def testExactPfAssetsExtensionOk (session : ParserSession) : IO Unit := do
  let v ← load session
    (extensionSource "ExtPfOk" "pf.assets" "1.1.0" pfAssetsDigest)
    "<ext-pf-ok>" "Tests.ExtPfOk"
  let r := checkContextExtensionResultV1 v
  expect (r.ok && r.analysisComplete && r.diagnostics.isEmpty)
    "exact pf.assets extension triple must pass ContextExtension Check"
  let composed := checkProgramTypedResultV1 v
  expect (composed.ok && composed.analysisComplete)
    "exact pf.assets extension triple must pass CheckV1 composition"
  -- Closed QN table is present and ordered (target-neutral Core authority).
  expect (pfAssetsCatalogQualifiedNamesV1.size == 5)
    "pf.assets catalog must expose five closed QNs"
  expect (pfAssetsCatalogQualifiedNamesV1[0]! == "pf.assets.native.deposit")
    "pf.assets catalog QN0"
  expect (pfAssetsCatalogQualifiedNamesV1[4]! == "pf.assets.token.transferAsync")
    "pf.assets catalog QN4"

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
  expectExactExtensionRow "extension semantic" data.requirements.items
    wireExtensionSolanaCpiAccountsIdV1 solanaCpiAccountsExtensionRequirementV1
  expectDeclarationOnlyProvenance label validated spans carrier data
    wireExtensionSolanaCpiAccountsIdV1 0

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
    "extension absent: normalizer must not invent the solana extension row"
  expect (!(absentData.requirements.items.any fun row =>
      row.id == wireExtensionPfAssetsIdV1))
    "extension absent: normalizer must not invent the pf.assets extension row"

private unsafe def testPfAssetsExtensionSemanticAndProvenance
    (session : ParserSession) : IO Unit := do
  let label := "tests/pf-assets-extension-v1.pf"
  let source :=
    extensionSource "ExtPfSemantic" "pf.assets" "1.1.0" pfAssetsDigest
  let (validated, spans) ← loadWithSpans session source label "Tests.ExtPfSemantic"
  let carrier ← expectNormalizeOk "pf-assets semantic" (normalizeProgramV1 validated)
  let data ← match validateSemanticProgramV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"pf-assets semantic: validate failed: {repr error}"
  expectExactExtensionRow "pf-assets semantic" data.requirements.items
    wireExtensionPfAssetsIdV1 pfAssetsExtensionRequirementV1
  -- No solana row invented from pf.assets alone.
  expect (!(data.requirements.items.any fun row =>
      row.id == wireExtensionSolanaCpiAccountsIdV1))
    "pf-assets alone must not mint solana-cpi-accounts"
  expectDeclarationOnlyProvenance label validated spans carrier data
    wireExtensionPfAssetsIdV1 0

private unsafe def testDualExtensionDeclarationOk (session : ParserSession) : IO Unit := do
  let label := "tests/dual-extension-v1.pf"
  let source := dualExtensionSource "ExtDual"
  let v ← load session source ("<" ++ label ++ ">") "Tests.ExtDual"
  let r := checkContextExtensionResultV1 v
  expect (r.ok && r.analysisComplete && r.diagnostics.isEmpty)
    "dual solana+pf.assets declarations must pass ContextExtension"
  let composed := checkProgramTypedResultV1 v
  expect (composed.ok && composed.analysisComplete)
    "dual extension declarations must pass CheckV1 composition"

  let (validated, spans) ← loadWithSpans session source label "Tests.ExtDual"
  let carrier ← expectNormalizeOk "dual extension semantic" (normalizeProgramV1 validated)
  let data ← match validateSemanticProgramV1 carrier with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"dual extension semantic: validate failed: {repr error}"
  expectExactExtensionRow "dual solana" data.requirements.items
    wireExtensionSolanaCpiAccountsIdV1 solanaCpiAccountsExtensionRequirementV1
  expectExactExtensionRow "dual pf-assets" data.requirements.items
    wireExtensionPfAssetsIdV1 pfAssetsExtensionRequirementV1
  -- Sorted order: extension.pf-assets before extension.solana-cpi-accounts
  let mut pfIdx? : Option Nat := none
  let mut solIdx? : Option Nat := none
  for (row, index) in data.requirements.items.zipIdx do
    if row.id == wireExtensionPfAssetsIdV1 then pfIdx? := some index
    if row.id == wireExtensionSolanaCpiAccountsIdV1 then solIdx? := some index
  match (pfIdx?, solIdx?) with
  | (some pfI, some solI) =>
      expect (pfI < solI)
        s!"dual extension sort: pf-assets index {pfI} must precede solana index {solI}"
  | _ => throw <| IO.userError "dual extension sort: missing one of the extension rows"

  -- Provenance: each row binds its own declaration item (0=solana, 1=pf.assets).
  expectDeclarationOnlyProvenance label validated spans carrier data
    wireExtensionSolanaCpiAccountsIdV1 0
  expectDeclarationOnlyProvenance label validated spans carrier data
    wireExtensionPfAssetsIdV1 1

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

private def pfAssetsV1_1_Digest : String :=
  "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

/-- ADR-0030 E2: pf.assets@1.1.0 declaration must pass ContextExtension +
    CheckV1 (additive acceptance). -/
private unsafe def testPfAssetsV1_1ExtensionOk (session : ParserSession) : IO Unit := do
  let v ← load session
    (extensionSource "ExtPf11Ok" "pf.assets" "1.1.0" pfAssetsV1_1_Digest)
    "<pf-assets-1.1-ok>" "Tests.ExtPf11Ok"
  let r := checkContextExtensionResultV1 v
  expect (r.ok && r.diagnostics.isEmpty)
    "exact pf.assets@1.1.0 extension triple must pass ContextExtension Check"
  expect (checkProgramTypedResultV1 v).ok
    "exact pf.assets@1.1.0 extension triple must pass CheckV1 composition"
  -- env-read catalog QNs are two, distinct from the five statement QNs.
  expect (pfAssetsEnvReadQualifiedNamesV1.size == 2)
    "pf.assets env-read catalog must expose two QNs"
  expect (pfAssetsEnvReadQualifiedNamesV1[0]! == "pf.assets.native.balanceOfSelf")
    "pf.assets env-read catalog QN0"
  expect (pfAssetsEnvReadQualifiedNamesV1[1]! == "pf.assets.token.balanceOfSelf")
    "pf.assets env-read catalog QN1"

/-- ADR-0030 E2: env-read `native.balanceOfSelf()` in a view passes CheckV1
    with the 1.1.0 declaration; the legacy v1.0.0 triple fails closed
    (extensionVersion) at declaration acceptance after the E2 cutover. -/
private def envReadViewSource
    (programName version digest : String) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  "program " ++ programName ++ " where\n" ++
  "  requires extension pf.assets version \"" ++ version ++ "\"\n" ++
  "    digest \"" ++ digest ++ "\"\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  view nativeBalance() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n"

private unsafe def testEnvReadViewOkWithV1_1 (session : ParserSession) : IO Unit := do
  let src := envReadViewSource "EnvReadOk" "1.1.0" pfAssetsV1_1_Digest
  let v ← load session src "<env-read-ok>" "Tests.EnvReadOk"
  let composed := checkProgramTypedResultV1 v
  expect composed.ok
    s!"env-read view with 1.1.0 must pass CheckV1; got: {composed.diagnostics.map (·.message)|>.toList}"

private unsafe def testEnvReadViewFailsWithV1_0 (session : ParserSession) : IO Unit := do
  let src := envReadViewSource "EnvReadV10" "1.0.0" pfAssetsDigest
  let v ← load session src "<env-read-v10>" "Tests.EnvReadV10"
  let composed := checkProgramTypedResultV1 v
  expect (!composed.ok)
    "env-read view with v1.0.0 must fail CheckV1"
  expect (composed.diagnostics.any (·.code == .extensionVersion))
    "env-read view with v1.0.0 must fail with extensionVersion"

/-- ADR-0030 E2: statement-position `call pf.assets.native.balanceOfSelf()`
    fails closed (env-read is expression-position only). -/
private unsafe def testEnvReadStatementPositionFails (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program EnvReadStmt where\n" ++
    "  requires extension pf.assets version \"1.1.0\"\n" ++
    "    digest \"" ++ pfAssetsV1_1_Digest ++ "\"\n" ++
    "  entry run() : UInt64 do\n" ++
    "    call pf.assets.native.balanceOfSelf()\n" ++
    "    return 0\n"
  let v ← load session src "<env-read-stmt>" "Tests.EnvReadStmt"
  let composed := checkProgramTypedResultV1 v
  expect (!composed.ok)
    "statement-position env-read call must fail CheckV1"
  expect (composed.diagnostics.any (·.code == .sourceInvalid))
    "statement-position env-read call must fail with sourceInvalid"

/-- ADR-0030 E2: wrong arity `pf.assets.native.balanceOfSelf(42)` fails. -/
private unsafe def testEnvReadWrongArityFails (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program EnvReadArity where\n" ++
    "  requires extension pf.assets version \"1.1.0\"\n" ++
    "    digest \"" ++ pfAssetsV1_1_Digest ++ "\"\n" ++
    "  view bad() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf(42)\n"
  let v ← load session src "<env-read-arity>" "Tests.EnvReadArity"
  let composed := checkProgramTypedResultV1 v
  expect (!composed.ok)
    "wrong-arity env-read must fail CheckV1"

private unsafe def testExtensionNegativeMatrix (session : ParserSession) : IO Unit := do
  let zeroDigest :=
    "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  expectExtensionFailure session "ext-unknown" "ExtUnknown"
    "proof.forge.feature" "1.0.0" zeroDigest .ext001
  expectExtensionFailure session "ext-version" "ExtVersion"
    "solana.cpi.accounts" "1.0.1" solanaCpiDigest .extensionVersion
  expectExtensionFailure session "ext-digest" "ExtDigest"
    "solana.cpi.accounts" "1.0.0" zeroDigest .extensionVersion
  -- pf.assets negatives: known id, wrong version/digest still extensionVersion
  expectExtensionFailure session "ext-pf-version" "ExtPfVersion"
    "pf.assets" "1.0.1" pfAssetsDigest .extensionVersion
  expectExtensionFailure session "ext-pf-digest" "ExtPfDigest"
    "pf.assets" "1.0.0" zeroDigest .extensionVersion

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testAdmittedCallerOk session
  testBadContextSurface session
  testExactSolanaCpiExtensionOk session
  testExactPfAssetsExtensionOk session
  testPfAssetsV1_1ExtensionOk session
  testSolanaCpiExtensionSemanticAndProvenance session
  testPfAssetsExtensionSemanticAndProvenance session
  testDualExtensionDeclarationOk session
  testExtensionNegativeMatrix session
  testEnvReadViewOkWithV1_1 session
  testEnvReadViewFailsWithV1_0 session
  testEnvReadStatementPositionFails session
  testEnvReadWrongArityFails session
  IO.println "Tests.Typed.ContextExtensionCheckV1: ok"

end Tests.Typed.ContextExtensionCheckV1
