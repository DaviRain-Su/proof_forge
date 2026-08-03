/-
  Focused integration tests for product InlineProofCertifierV1.

  Coverage:
    * no-proof programs return explicit `noProof` (never forged success)
    * structurally legal but false theorem → elaboration failure
    * wrong subject bytes (mixed compile carrier) → subject failure
    * forged empty inventory with proof items → obligation failure (not noProof)
    * dual-invariant forged partial/reorder inventories fail closed
    * raw same-file simple-closure positive (planned author theorem name
      `<Program>.Proof.simpleClosure_invariantTheorem`):
        - Loader → compileProgramProductV1 → certifyInlineProofV1
        - expects `.certified`, theoremCount=1, nonempty proofCertificationDigest
        - theorem-body-only rewrite keeps sourceDigest/semanticDigest, may
          change proofCertificationDigest when certification succeeds
      If production B-SC-ENC/DEC/ELAB-THM is still open, the suite records a
      single EXPECTED-RED and continues without forging CertifiedInlineProofV1.
      Never uses Tests.Semantic.ProofedClosedCertV1 or hand-minted carriers.

  Fixture programs:
    * Counter-shaped UInt64 + Bool invariant for certifier negatives
    * Literal-true simple-closure (Bool view + `invariant … : true`) for positive

  No axiom / sorry / native_decide. No CLI. No file re-read by the certifier.
-/
import ProofForgeV2.Compiler.InlineProofCertifierV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Language.TheoremInventoryV1
import Tests.Language.ParserSession

namespace Tests.Compiler.InlineProofCertifierV1

open ProofForgeV2.Compiler
open ProofForgeV2.Compiler.InlineProofCertifierV1
open ProofForgeV2.Compiler.InlineProofProtocolV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Language.Loader
open ProofForgeV2.Language.TheoremInventoryV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectOutcome
    (label : String)
    (outcome : InlineProofCertifierOutcomeV1)
    (pred : InlineProofCertifierOutcomeV1 → Bool) : IO Unit :=
  unless pred outcome do
    throw <| IO.userError s!"{label}: unexpected outcome {repr outcome}"

private def header : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n"

/-- UInt64 Counter surface (proven subject mint) without proofs. -/
private def bareProgram : String :=
  header ++
  "program Bare where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- Counter + invariant + adjacent theorem (allowlisted tactics only). -/
private def proofProgram (programName theoremName theoremBody : String) : String :=
  header ++
  "program " ++ programName ++ " where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n" ++
  "  invariant safe : true\n" ++
  "  proof safe using " ++ theoremName ++ "\n" ++
  theoremBody

/-- Allowlisted `rfl` cannot close `InvariantTheoremV1` — inventory admits
    the syntax; kernel elaboration fails closed. -/
private def falseTheoremBody (theoremName typeName : String) : String :=
  "theorem " ++ theoremName ++ " : " ++ typeName ++ " := by\n" ++
  "  rfl\n"

/-- Literal-true simple-closure family (Normalize/subject match for B-SC).
    Author theorem uses the planned product name
    `<Program>.Proof.simpleClosure_invariantTheorem`. Body applies the
    production encode/decode soundness surface; residual subgoals are the
    open B-SC-ENC/DEC discharge (not a forged success). -/
private def simpleClosureProgram
    (programName : String) (theoremBody : String) : String :=
  header ++
  "program " ++ programName ++ " where\n" ++
  "  view alive() : Bool do\n" ++
  "    return true\n" ++
  "  invariant safe : true\n" ++
  "  proof safe using " ++ programName ++
    ".Proof.simpleClosure_invariantTheorem\n" ++
  theoremBody

/-- Planned author theorem body: production soundness apply, allowlisted
    tactics only. Incomplete residual goals ⇒ elaboration fail closed until
    B-SC-ENC/DEC (or generated theorem mint) closes. -/
private def plannedSimpleClosureTheoremBody (programName : String) : String :=
  "theorem " ++ programName ++
    ".Proof.simpleClosure_invariantTheorem : " ++ programName ++
    ".Proof.safe := by\n" ++
  "  apply ProofForgeV2.Semantic.SimpleClosureDecodeV1." ++
    "invariantTheorem_of_simpleClosure_encode_decode\n" ++
  "  exact " ++ programName ++ ".Proof.simpleClosureParamsV1\n"

/-- Adjacent theorem body rewrite only (same program items / proof binding). -/
private def plannedSimpleClosureTheoremBodyAlt (programName : String) : String :=
  "theorem " ++ programName ++
    ".Proof.simpleClosure_invariantTheorem : " ++ programName ++
    ".Proof.safe := by\n" ++
  "  apply ProofForgeV2.Semantic.SimpleClosureDecodeV1." ++
    "invariantTheorem_of_simpleClosure_encode_decode\n" ++
  "  exact " ++ programName ++ ".Proof.simpleClosureParamsV1\n" ++
  "  -- body-only delta (comment) for raw-source certification digest binding\n"

private def parsePath (s : String) : IO ProjectRelativePath :=
  match parseProjectRelativePath s with
  | .ok p => pure p
  | .error e => throw <| IO.userError s!"path: {e}"

private unsafe def loadProduct
    (session : ParserSession) (src fileName moduleName : String)
    (requested : Option String := none) :
    IO (ValidatedSourceV1 ×
        ProofForgeV2.Source.OriginJoinV1.OriginInventoryV1 ×
        TheoremInventoryV1) := do
  match ← session.selectProgramV1ProductWithTheoremInventory
      src fileName moduleName requested with
  | .ok triple => pure triple
  | .error err =>
      throw <| IO.userError
        s!"load {fileName}: {DiagnosticBundleV1.renderHuman err}"

private unsafe def compileOf
    (source : ValidatedSourceV1)
    (origin : ProofForgeV2.Source.OriginJoinV1.OriginInventoryV1) :
    IO CompiledSemanticV1 :=
  match compileProgramProductV1 source origin with
  | .ok c => pure c
  | .error bundle =>
      throw <| IO.userError
        s!"product compile failed: {DiagnosticBundleV1.renderHuman bundle}"

/-- Product digests are fixed-width SHA-256; "nonempty" means a real 32-byte
    wire value is present (not Option.none / empty). -/
private def digestPresent (d : Digest) : Bool :=
  d.bytes.size == 32

/-- No proof items: certifier must return explicit `noProof`, never success. -/
private unsafe def testNoProofBypass (session : ParserSession) : IO Unit := do
  let path ← parsePath "tests/inline-proof/bare.pf"
  let (source, origin, thmInv) ← loadProduct session bareProgram
      "tests/inline-proof/bare.pf" "Root"
  expect (theoremInventoryBindingsV1 thmInv).isEmpty "bare inventory empty"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 bareProgram source origin thmInv compiled
      path "Root" none
  expectOutcome "noProof" outcome fun
    | .noProof => true
    | _ => false

/-- Structurally legal inventory + false theorem body fails at elaboration. -/
private unsafe def testFalseTheoremElab (session : ParserSession) : IO Unit := do
  let src := proofProgram "Proofed" "ProofedProof.safe"
      (falseTheoremBody "ProofedProof.safe" "Proofed.Proof.safe")
  let path ← parsePath "tests/inline-proof/false.pf"
  let (source, origin, thmInv) ← loadProduct session src
      "tests/inline-proof/false.pf" "Root"
  expect ((theoremInventoryBindingsV1 thmInv).size == 1) "false binding count"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 src source origin thmInv compiled
      path "Root" none
  expectOutcome "false theorem" outcome fun
    | .failed phase detail =>
        phase == .certification && detail == .elaborate
    | _ => false

/-- Mix compiled carrier from another program → subject identity fails closed. -/
private unsafe def testWrongSubjectBytes (session : ParserSession) : IO Unit := do
  let src := proofProgram "Proofed" "ProofedProof.safe"
      (falseTheoremBody "ProofedProof.safe" "Proofed.Proof.safe")
  let other := proofProgram "Other" "OtherProof.safe"
      (falseTheoremBody "OtherProof.safe" "Other.Proof.safe")
  let path ← parsePath "tests/inline-proof/mixed.pf"
  let (source, origin, thmInv) ← loadProduct session src
      "tests/inline-proof/mixed.pf" "Root"
  let (otherSource, otherOrigin, _) ← loadProduct session other
      "tests/inline-proof/other.pf" "Root"
  let otherCompiled ← compileOf otherSource otherOrigin
  let outcome ← certifyInlineProofV1 src source origin thmInv otherCompiled
      path "Root" none
  expectOutcome "wrong subject" outcome fun
    | .failed phase detail =>
        (phase == .subject &&
          (detail == .subjectBuild || detail == .subjectBytes ||
            detail == .missingSubjectDecl)) ||
        (phase == .certification && detail == .elaborate)
    | _ => false

/-- Empty inventory with proof items still present (forged empty inventory)
    must not skip as noProof. -/
private unsafe def testEmptyInventoryWithProofs (session : ParserSession) : IO Unit := do
  let src := proofProgram "Proofed" "ProofedProof.safe"
      (falseTheoremBody "ProofedProof.safe" "Proofed.Proof.safe")
  let path ← parsePath "tests/inline-proof/forged-empty.pf"
  let (source, origin, _) ← loadProduct session src
      "tests/inline-proof/forged-empty.pf" "Root"
  let compiled ← compileOf source origin
  let forgedEmpty := emptyTheoremInventoryV1
  let outcome ← certifyInlineProofV1 src source origin forgedEmpty compiled
      path "Root" none
  expectOutcome "forged empty inventory" outcome fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false

/-- Dual-invariant program with two proofs; forged partial inventory (one of two
    bindings) must fail closed at obligation bijection — not noProof/certified. -/
private unsafe def testForgedPartialDualInvariant (session : ParserSession) : IO Unit := do
  let src :=
    header ++
    "program Dual where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n" ++
    "  invariant first : true\n" ++
    "  invariant second : true\n" ++
    "  proof first using DualProof.first\n" ++
    "  proof second using DualProof.second\n" ++
    falseTheoremBody "DualProof.first" "Dual.Proof.first" ++
    falseTheoremBody "DualProof.second" "Dual.Proof.second"
  let path ← parsePath "tests/inline-proof/dual-partial.pf"
  let (source, origin, fullInv) ← loadProduct session src
      "tests/inline-proof/dual-partial.pf" "Root"
  let fullBindings := theoremInventoryBindingsV1 fullInv
  expect (fullBindings.size == 2) "dual full binding count"
  let compiled ← compileOf source origin
  -- Forged partial: keep only the first binding.
  let partialInv := mintTheoremInventoryV1 #[fullBindings[0]!]
  let outcomePartial ← certifyInlineProofV1 src source origin partialInv compiled
      path "Root" none
  expectOutcome "forged partial dual" outcomePartial fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false
  -- Forged reordered: swap the two bindings.
  let reorderedInv :=
    mintTheoremInventoryV1 #[fullBindings[1]!, fullBindings[0]!]
  let outcomeReorder ← certifyInlineProofV1 src source origin reorderedInv compiled
      path "Root" none
  expectOutcome "forged reorder dual" outcomeReorder fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false
  -- Forged extra on bare program (no proofs expected).
  let extraOnBare := mintTheoremInventoryV1 #[fullBindings[0]!]
  let pathBare ← parsePath "tests/inline-proof/bare-extra.pf"
  let (bareSrc, bareOrigin, _) ← loadProduct session bareProgram
      "tests/inline-proof/bare-extra.pf" "Root"
  let bareCompiled ← compileOf bareSrc bareOrigin
  let outcomeExtra ← certifyInlineProofV1 bareProgram bareSrc bareOrigin extraOnBare
      bareCompiled pathBare "Root" none
  expectOutcome "forged extra on bare" outcomeExtra fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false

/-- Protocol success mint is not a product capability: only the private carrier
    from `certifyInlineProofV1` is accepted. Runtime checks that noProof/fail
    paths never yield certified. -/
private unsafe def testNoForgedSuccess (session : ParserSession) : IO Unit := do
  let path ← parsePath "tests/inline-proof/no-forge.pf"
  let (source, origin, thmInv) ← loadProduct session bareProgram
      "tests/inline-proof/no-forge.pf" "Root"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 bareProgram source origin thmInv compiled
      path "Root" none
  match outcome with
  | .certified _ =>
      throw <| IO.userError "noProof path must not mint CertifiedInlineProofV1"
  | .noProof => pure ()
  | .failed _ _ =>
      throw <| IO.userError "bare program must be noProof, not failure"

/-- Assert full certified observation on a private certifier carrier. -/
private def expectCertifiedCarrier
    (label : String) (c : CertifiedInlineProofV1) : IO Unit := do
  expect (CertifiedInlineProofV1.theoremCount c == 1)
    s!"{label}: theoremCount must be 1, got {CertifiedInlineProofV1.theoremCount c}"
  expect (digestPresent (CertifiedInlineProofV1.proofCertificationDigest c))
    s!"{label}: proofCertificationDigest must be present (32-byte)"
  expect (digestPresent (CertifiedInlineProofV1.requestDigest c))
    s!"{label}: requestDigest must be present (32-byte)"
  expect ((CertifiedInlineProofV1.audited c).size == 1)
    s!"{label}: audited theorem set size must be 1"

/-- (1) Loader → compile → certify simple-closure with planned theorem name.
    (3) Adjacent theorem body rewrite keeps source/semantic digests.
    Never hand-mints CertifiedInlineProofV1 / ProductProofStatusV1. -/
private unsafe def testSimpleClosureProductPositive
    (session : ParserSession) : IO Unit := do
  let programName := "Simple"
  let bodyA := plannedSimpleClosureTheoremBody programName
  let bodyB := plannedSimpleClosureTheoremBodyAlt programName
  let srcA := simpleClosureProgram programName bodyA
  let srcB := simpleClosureProgram programName bodyB
  expect (srcA != srcB) "theorem-body rewrite must change raw source"
  let pathA ← parsePath "tests/inline-proof/simple-closure-a.pf"
  let pathB ← parsePath "tests/inline-proof/simple-closure-b.pf"
  let (sourceA, originA, thmInvA) ← loadProduct session srcA
      "tests/inline-proof/simple-closure-a.pf" "Root"
  let (sourceB, originB, thmInvB) ← loadProduct session srcB
      "tests/inline-proof/simple-closure-b.pf" "Root"
  -- Inventory: planned author theorem FQN + Prop alias type components.
  let bindingsA := theoremInventoryBindingsV1 thmInvA
  expect (bindingsA.size == 1) "simple-closure inventory size"
  let b0 := bindingsA[0]!
  expect (b0.invariantName == "safe") "simple-closure invariant name"
  expect (b0.theoremComponents ==
      #[programName, "Proof", "simpleClosure_invariantTheorem"])
    s!"planned theorem components: {b0.theoremComponents}"
  expect (b0.typeComponents == #[programName, "Proof", "safe"])
    s!"planned type components: {b0.typeComponents}"
  expect ((theoremInventoryBindingsV1 thmInvB).size == 1)
    "alt body inventory size"
  -- Product compile (structure-gated Normalize) for both sources.
  let compiledA ← compileOf sourceA originA
  let compiledB ← compileOf sourceB originB
  let srcDigA := CompiledSemanticV1.sourceDigestOf compiledA
  let srcDigB := CompiledSemanticV1.sourceDigestOf compiledB
  let semDigA := CompiledSemanticV1.semanticDigestOf compiledA
  let semDigB := CompiledSemanticV1.semanticDigestOf compiledB
  -- (3) ProgramV1 / semantic identity ignore adjacent theorem body.
  expect (srcDigA == srcDigB)
    "sourceDigest must be independent of adjacent theorem body"
  expect (semDigA == semDigB)
    "semanticDigest must be independent of adjacent theorem body"
  expect ((CompiledSemanticV1.semanticV1Of compiledA).canonicalBytes ==
      (CompiledSemanticV1.semanticV1Of compiledB).canonicalBytes)
    "semantic bytes must match across theorem-body rewrite"
  -- Sole product certifier on held raw source (no re-read, no forge).
  let outcomeA ← certifyInlineProofV1 srcA sourceA originA thmInvA compiledA
      pathA "Root" none
  let outcomeB ← certifyInlineProofV1 srcB sourceB originB thmInvB compiledB
      pathB "Root" none
  -- Never accept noProof for a nonempty proof surface.
  match outcomeA with
  | .noProof =>
      throw <| IO.userError
        "simple-closure with proof items must not return noProof"
  | .certified cA =>
      expectCertifiedCarrier "simple-closure-A" cA
      match outcomeB with
      | .certified cB =>
          expectCertifiedCarrier "simple-closure-B" cB
          -- proofCertificationDigest binds raw source; body rewrite may change it.
          let digA := CertifiedInlineProofV1.proofCertificationDigest cA
          let digB := CertifiedInlineProofV1.proofCertificationDigest cB
          expect (digestPresent digA && digestPresent digB)
            "both certification digests present"
          -- Digests may be equal only if protocol ignores body; either is honest
          -- as long as source/semantic stayed equal (asserted above).
          pure ()
      | .noProof =>
          throw <| IO.userError "alt body must not return noProof"
      | .failed phase detail =>
          throw <| IO.userError
            s!"simple-closure-A certified but B failed: {repr phase}/{repr detail}"
      IO.println
        "Tests.Compiler.InlineProofCertifierV1: simple-closure product-positive CERTIFIED"
  | .failed phase detail =>
      -- Unique expected-red until B-SC-ENC/DEC + author/elab theorem closes.
      -- Do not forge CertifiedInlineProofV1. Structural preconditions above
      -- already passed (load/compile/inventory/hash independence).
      expect (phase == .certification || phase == .subject)
        s!"unexpected failure phase for simple-closure: {repr phase}/{repr detail}"
      IO.println
        ("EXPECTED-RED B-SC-PRODUCT: certifyInlineProofV1 failed " ++
          s!"phase={repr phase} detail={repr detail}; " ++
          "planned theorem Simple.Proof.simpleClosure_invariantTheorem; " ++
          "requires unconditional encode/decode (or generated theorem mint) " ++
          "to close InvariantTheoremV1 on raw same-file simple-closure. " ++
          "Never forged certified. sourceDigest/semanticDigest hash independence OK.")

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testNoProofBypass session
  testFalseTheoremElab session
  testWrongSubjectBytes session
  testEmptyInventoryWithProofs session
  testForgedPartialDualInvariant session
  testNoForgedSuccess session
  testSimpleClosureProductPositive session
  IO.println "Tests.Compiler.InlineProofCertifierV1: ok"

end Tests.Compiler.InlineProofCertifierV1
